--!strict
-- A small fake Roblox engine for Lune: just enough of the API to run the game's
-- real server and client scripts (src/server, src/client) headlessly, with any
-- number of simulated players, on a simulated clock.
--
-- What it fakes: game/GetService, Instances (with Parent/children, child access
-- by name, WaitForChild), signals, RemoteEvents with per-player delivery and
-- Roblox-style argument copying, Players (PlayerAdded/Removing, LocalPlayer,
-- PlayerGui), RunService.Heartbeat/RenderStepped, workspace:GetServerTimeNow,
-- the task library, Random, Enum, Color3/UDim/UDim2/Vector2, and a rough
-- AbsoluteSize/AbsolutePosition/TextFits layout so the UI audit's checks run
-- (Size, Position, AnchorPoint and UISizeConstraint; list, grid and padding
-- layouts are not run, so a child of a list sits at its parent's corner). Also
-- DataStoreService (a world-level key/value table with switches for an
-- unpublished place and transient failures: world.data), game.JobId,
-- game:BindToClose (FakeRoblox.shutdown runs the handlers), and os.time on the
-- simulated clock.
--
-- What it does not fake: rendering, physics, real replication of anything but
-- remotes, or Studio. Real-engine checks still need Studio
-- (docs/TESTING.md). Used by tests/e2e and tests/play.luau.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Rng = require("@sim/Rng")

local FakeRoblox = {}

-- ---------------------------------------------------------------- types

export type Peer = {
	name: string, -- "server" or the player's name
	isServer: boolean,
	player: any?, -- client peers: their Player instance
	game: any,
	modules: { [string]: any }, -- module cache by file path
	log: { string }, -- Output window
	runStepped: any, -- RunService.RenderStepped (client) signal
	heartbeat: any, -- RunService.Heartbeat signal
	inbox: { { any } }, -- queued remote messages to deliver
}

-- The fake DataStoreService's world-level state. Tests flip the switches.
export type DataState = {
	stores: { [string]: { [string]: any } }, -- store name -> key -> value (deep copies)
	unpublished: boolean, -- every request fails as in an unpublished Studio place
	unpublishedMessage: string, -- the error text for that
	failures: number, -- the next N requests fail with a transient error
	reruns: number, -- the next N UpdateAsync calls run their callback twice (a write conflict)
	latency: number, -- simulated seconds each request takes
	requests: number, -- requests made so far
	writes: number, -- successful writes so far
}

export type World = {
	clock: number,
	seed: number,
	root: string, -- repository root
	screen: { x: number, y: number },
	tasks: { { at: number, seq: number, co: thread, peer: Peer, args: { any } } },
	seq: number,
	current: Peer?,
	server: Peer,
	clients: { Peer },
	shared: any, -- ReplicatedStorage, one tree seen by every peer
	errors: { string },
	wireWarnings: { string },
	nextUserId: number,
	data: DataState,
	jobId: string, -- the server's game.JobId
	closeHandlers: { () -> () }, -- game:BindToClose callbacks
	studio: boolean, -- what RunService:IsStudio() answers (default true)
	clientFolder: any, -- this world's StarterPlayerScripts tree (src/client)
}

-- ---------------------------------------------------------------- data types

local function readonly(kind: string, fields: { [string]: any }, text: string): any
	return setmetatable(fields, {
		__tostring = function()
			return text
		end,
		__type = kind,
	})
end

local function vector2(x: number, y: number): any
	return readonly("Vector2", { X = x, Y = y }, `{x}, {y}`)
end

local function udim(scale: number?, offset: number?): any
	local s, o = scale or 0, offset or 0
	return readonly("UDim", { Scale = s, Offset = o }, `{s}, {o}`)
end

local UDim2 = {}
function UDim2.new(a: any, b: any, c: any, d: any): any
	local x, y
	if type(a) == "table" then
		x, y = a, b
	else
		x, y = udim(a, b), udim(c, d)
	end
	return readonly("UDim2", { X = x, Y = y }, `{x}, {y}`)
end
function UDim2.fromScale(x: number, y: number): any
	return UDim2.new(x, 0, y, 0)
end
function UDim2.fromOffset(x: number, y: number): any
	return UDim2.new(0, x, 0, y)
end

local Color3 = {
	fromRGB = function(r: number, g: number, b: number): any
		return readonly("Color3", { R = r / 255, G = g / 255, B = b / 255 }, `{r}, {g}, {b}`)
	end,
	new = function(r: number?, g: number?, b: number?): any
		return readonly("Color3", { R = r or 0, G = g or 0, B = b or 0 }, "color")
	end,
}

local Enum = setmetatable({}, {
	__index = function(_, enumType: string)
		return setmetatable({}, {
			__index = function(_, item: string)
				return readonly("EnumItem", { EnumType = enumType, Name = item }, `Enum.{enumType}.{item}`)
			end,
		})
	end,
})

-- ---------------------------------------------------------------- scheduler

local function schedule(world: World, at: number, co: thread, peer: Peer, args: { any })
	world.seq += 1
	table.insert(world.tasks, { at = at, seq = world.seq, co = co, peer = peer, args = args })
end

local function resume(world: World, peer: Peer, co: thread, ...: any)
	local previous = world.current
	world.current = peer
	local ok, err = coroutine.resume(co, ...)
	world.current = previous
	if not ok then
		local message = `[{peer.name}] ERROR: {err}`
		table.insert(world.errors, message)
		table.insert(peer.log, message)
	end
end

local function spawnOn(world: World, peer: Peer, fn: (...any) -> ...any, ...: any): thread
	local co = coroutine.create(fn)
	resume(world, peer, co, ...)
	return co
end

local function taskLibrary(world: World, peer: Peer): any
	local task = {}
	function task.spawn(fn: any, ...: any): thread
		if type(fn) == "thread" then
			resume(world, peer, fn, ...)
			return fn
		end
		return spawnOn(world, peer, fn, ...)
	end
	function task.defer(fn: any, ...: any): thread
		local co = if type(fn) == "thread" then fn else coroutine.create(fn)
		schedule(world, world.clock, co, peer, { ... })
		return co
	end
	function task.delay(seconds: number?, fn: any, ...: any): thread
		local co = if type(fn) == "thread" then fn else coroutine.create(fn)
		schedule(world, world.clock + (seconds or 0), co, peer, { ... })
		return co
	end
	function task.wait(seconds: number?): number
		local start = world.clock
		schedule(world, world.clock + math.max(seconds or 0, 1 / 60), coroutine.running(), peer, {})
		coroutine.yield()
		return world.clock - start
	end
	function task.cancel(co: thread)
		for k = #world.tasks, 1, -1 do
			if world.tasks[k].co == co then
				table.remove(world.tasks, k)
			end
		end
	end
	return table.freeze(task)
end

-- ---------------------------------------------------------------- signals

local function newSignal(world: World): any
	local signal = { connections = {} }
	function signal.Connect(_self: any, fn: (...any) -> ())
		local connection = { fn = fn, peer = world.current, connected = true }
		table.insert(signal.connections, connection)
		return {
			Disconnect = function()
				connection.connected = false
			end,
		}
	end
	-- Internal: call every handler (each in its own thread, like Roblox).
	function signal.fire(...: any)
		for _, connection in table.clone(signal.connections) do
			if connection.connected then
				spawnOn(world, connection.peer or world.server, connection.fn, ...)
			end
		end
	end
	return signal
end

-- ---------------------------------------------------------------- remote argument copying

-- Copies an argument the way a RemoteEvent would, recording anything Roblox
-- would mangle (functions, mixed tables, sparse arrays, odd keys).
local function wireCopy(world: World, value: any, path: string): any
	local kind = type(value)
	if kind == "function" or kind == "thread" then
		table.insert(world.wireWarnings, `{path}: a {kind} does not cross a remote`)
		return nil
	elseif kind ~= "table" then
		return value
	end
	local numeric, text = 0, 0
	for key in value do
		if type(key) == "number" then
			numeric += 1
		elseif type(key) == "string" then
			text += 1
		else
			table.insert(world.wireWarnings, `{path}: a {type(key)} key becomes a string`)
		end
	end
	if numeric > 0 and text > 0 then
		table.insert(world.wireWarnings, `{path}: mixed numeric and string keys`)
	end
	if numeric > 0 and #value ~= numeric then
		table.insert(world.wireWarnings, `{path}: sparse array`)
	end
	local copy = {}
	for key, child in value do
		copy[key] = wireCopy(world, child, `{path}.{tostring(key)}`)
	end
	return copy
end

local function copyArgs(world: World, args: { any }): { any }
	local out = {}
	for k = 1, select("#", table.unpack(args)) do
		out[k] = wireCopy(world, args[k], `arg{k}`)
	end
	return out
end

-- ---------------------------------------------------------------- data stores

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in value do
		out[key] = deepCopy(child)
	end
	return out
end

-- Errors the way a DataStore refuses values it can't serialize.
local function checkStorable(value: any, path: string)
	local kind = type(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error(`DataStore: cannot store a non-finite number at {path}`, 0)
		end
	elseif kind == "table" then
		if getmetatable(value) ~= nil then
			error(`DataStore: cannot store an Instance or object at {path}`, 0)
		end
		local numeric, text = 0, 0
		for key, child in value do
			if type(key) == "number" then
				numeric += 1
			elseif type(key) == "string" then
				text += 1
			else
				error(`DataStore: cannot store a {type(key)} key at {path}`, 0)
			end
			checkStorable(child, `{path}.{tostring(key)}`)
		end
		if numeric > 0 and (text > 0 or #value ~= numeric) then
			error(`DataStore: cannot store a mixed or sparse table at {path}`, 0)
		end
	elseif kind ~= "string" and kind ~= "boolean" then
		error(`DataStore: cannot store a {kind} at {path}`, 0)
	end
end

-- Yields the calling script for the simulated request time.
local function requestDelay(world: World)
	local peer = world.current
	assert(peer, "a DataStore request must come from a script")
	schedule(world, world.clock + world.data.latency, coroutine.running(), peer, {})
	coroutine.yield()
end

-- Counts the request, waits, and raises the configured failure, if any.
local function beginRequest(world: World)
	local data = world.data
	data.requests += 1
	requestDelay(world)
	if data.unpublished then
		error(data.unpublishedMessage, 0)
	end
	if data.failures > 0 then
		data.failures -= 1
		error("503: DataStore request failed (simulated transient error)", 0)
	end
end

local function newDataStore(world: World, name: string): any
	local keys = world.data.stores[name]
	if keys == nil then
		keys = {}
		world.data.stores[name] = keys
	end
	local store = {}
	function store.GetAsync(_self: any, key: string): (any, any)
		beginRequest(world)
		return deepCopy(keys[key]), if keys[key] ~= nil then {} else nil
	end
	function store.SetAsync(_self: any, key: string, value: any): ()
		checkStorable(value, "value")
		beginRequest(world)
		keys[key] = deepCopy(value)
		world.data.writes += 1
	end
	function store.UpdateAsync(_self: any, key: string, transform: (any, any) -> any): (any, any)
		beginRequest(world)
		if world.data.reruns > 0 then
			-- Another server wrote in between: Roblox discards this result and calls again.
			world.data.reruns -= 1
			transform(deepCopy(keys[key]), {})
		end
		local old = deepCopy(keys[key])
		local new = transform(old, {})
		if new == nil then
			return old, nil
		end
		checkStorable(new, "value")
		keys[key] = deepCopy(new)
		world.data.writes += 1
		return deepCopy(new), {}
	end
	return store
end

local function newDataStoreService(world: World): any
	return {
		GetDataStore = function(_self: any, name: string, _scope: string?): any
			return newDataStore(world, name)
		end,
	}
end

-- ---------------------------------------------------------------- instances

local EVENTS = {
	Activated = true,
	FocusLost = true,
	MouseButton1Click = true,
	Changed = true,
	ChildAdded = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	InputBegan = true,
	InputEnded = true,
}

local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

local newInstance: (world: World, className: string, name: string?) -> any

-- Rough layout: size from UDim2 against the parent's size, clamped by a child
-- UISizeConstraint (padding and list layouts ignored), enough for the UI audit's
-- 44 px, truncation and on-screen checks.
local function absoluteSize(world: World, inst: any): (number, number)
	local raw = rawget(inst, "_props")
	local parent = rawget(inst, "_parent")
	if inst.ClassName == "ScreenGui" or parent == nil then
		return world.screen.x, world.screen.y
	end
	local px, py = absoluteSize(world, parent)
	local size = raw.Size
	if size == nil then
		return px, py
	end
	local x = px * size.X.Scale + size.X.Offset
	local y = py * size.Y.Scale + size.Y.Offset
	if raw.AutomaticSize ~= nil and raw.AutomaticSize.Name ~= "None" then
		y = math.max(y, 20)
	end
	for _, child in rawget(inst, "_children") do
		if child.ClassName == "UISizeConstraint" then
			local props = rawget(child, "_props")
			local min, max = props.MinSize, props.MaxSize
			if max then
				x, y = math.min(x, max.X), math.min(y, max.Y)
			end
			if min then
				x, y = math.max(x, min.X), math.max(y, min.Y)
			end
		end
	end
	return x, y
end

-- Top-left corner from the parent's corner, Position and AnchorPoint. Objects
-- without a Size (folders, unsized frames) sit at their parent's corner; a
-- ScreenGui at the origin.
local function absolutePosition(world: World, inst: any): (number, number)
	local raw = rawget(inst, "_props")
	local parent = rawget(inst, "_parent")
	if inst.ClassName == "ScreenGui" or parent == nil then
		return 0, 0
	end
	local ox, oy = absolutePosition(world, parent)
	if raw.Size == nil then
		return ox, oy
	end
	local pw, ph = absoluteSize(world, parent)
	local w, h = absoluteSize(world, inst)
	local position, anchor = raw.Position, raw.AnchorPoint
	local x, y = ox, oy
	if position then
		x += pw * position.X.Scale + position.X.Offset
		y += ph * position.Y.Scale + position.Y.Offset
	end
	if anchor then
		x -= w * anchor.X
		y -= h * anchor.Y
	end
	return x, y
end

local function textFits(world: World, inst: any): boolean
	local raw = rawget(inst, "_props")
	local x, y = absoluteSize(world, inst)
	local text = tostring(raw.Text or "")
	local size = raw.TextSize or 14
	if raw.TextWrapped then
		return true
	end
	return #text * size * 0.55 <= x and size <= y
end

local methods = {}

function methods.GetService(self: any, name: string): any
	local service = rawget(self, "_services")[name]
	assert(service, `fake engine has no service {name}`)
	return service
end

-- FindFirstChild(name, recursive): with `recursive` true it searches every
-- descendant (children first, then theirs, as Roblox does), not only the children.
function methods.FindFirstChild(self: any, name: string, recursive: boolean?): any
	local children = rawget(self, "_children")
	for _, child in children do
		if rawget(child, "_props").Name == name then
			return child
		end
	end
	if recursive then
		for _, child in children do
			local found = methods.FindFirstChild(child, name, true)
			if found ~= nil then
				return found
			end
		end
	end
	return nil
end

function methods.FindFirstAncestor(self: any, name: string): any
	local node = rawget(self, "_parent")
	while node do
		if rawget(node, "_props").Name == name then
			return node
		end
		node = rawget(node, "_parent")
	end
	return nil
end

function methods.FindFirstChildOfClass(self: any, className: string): any
	for _, child in rawget(self, "_children") do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

function methods.WaitForChild(self: any, name: string, timeout: number?): any
	local world: World = rawget(self, "_world")
	local start = world.clock
	while true do
		local child = methods.FindFirstChild(self, name)
		if child then
			return child
		end
		if timeout and world.clock - start >= timeout then
			return nil
		end
		if coroutine.isyieldable() then
			schedule(world, world.clock + 0.05, coroutine.running(), world.current :: Peer, {})
			coroutine.yield()
		else
			error(`WaitForChild({name}) would yield forever outside a thread`)
		end
	end
end

function methods.GetChildren(self: any): { any }
	return table.clone(rawget(self, "_children"))
end

function methods.GetDescendants(self: any): { any }
	local out = {}
	local function walk(node: any)
		for _, child in rawget(node, "_children") do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

local GUI_OBJECTS = {
	Frame = true,
	ScrollingFrame = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
	ImageButton = true,
	CanvasGroup = true,
}
local GUI_BUTTONS = { TextButton = true, ImageButton = true }

function methods.IsA(self: any, className: string): boolean
	return self.ClassName == className
		or (className == "GuiObject" and GUI_OBJECTS[self.ClassName] ~= nil)
		or (className == "GuiButton" and GUI_BUTTONS[self.ClassName] ~= nil)
		or (className == "Instance")
end

function methods.GetAttribute(self: any, name: string): any
	local attributes = rawget(self, "_attributes")
	return if attributes then attributes[name] else nil
end

function methods.SetAttribute(self: any, name: string, value: any)
	local attributes = rawget(self, "_attributes")
	if attributes == nil then
		attributes = {}
		rawset(self, "_attributes", attributes)
	end
	attributes[name] = value
end

function methods.SetCoreGuiEnabled(_self: any, _kind: any, _enabled: boolean) end

function methods.Destroy(self: any)
	self.Parent = nil
end

function methods.GetPlayers(self: any): { any }
	local list = {}
	for _, child in rawget(self, "_children") do
		if child.ClassName == "Player" then
			table.insert(list, child)
		end
	end
	return list
end

function methods.GetPlayerByUserId(self: any, userId: number): any
	for _, player in methods.GetPlayers(self) do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

function methods.GetServerTimeNow(self: any): number
	return (rawget(self, "_world") :: World).clock
end

-- DataModel
function methods.BindToClose(self: any, callback: () -> ())
	table.insert((rawget(self, "_world") :: World).closeHandlers, callback)
end

-- RunService: the fake runs "in Studio" unless a test sets world.studio = false.
function methods.IsStudio(self: any): boolean
	return (rawget(self, "_world") :: World).studio
end

function methods.IsServer(self: any): boolean
	local world: World = rawget(self, "_world")
	return world.current == nil or (world.current :: Peer).isServer
end

function methods.IsClient(self: any): boolean
	return not methods.IsServer(self)
end

-- RemoteEvent
function methods.FireServer(self: any, ...: any)
	local world: World = rawget(self, "_world")
	local peer = world.current
	assert(peer and not peer.isServer, "FireServer can only be called from a client")
	table.insert(world.server.inbox, { self, peer.player, copyArgs(world, { ... }) })
end

function methods.FireClient(self: any, player: any, ...: any)
	local world: World = rawget(self, "_world")
	assert(
		world.current == nil or (world.current :: Peer).isServer,
		"FireClient can only be called from the server"
	)
	for _, client in world.clients do
		if client.player == player then
			table.insert(client.inbox, { self, nil, copyArgs(world, { ... }) })
		end
	end
end

function methods.FireAllClients(self: any, ...: any)
	for _, client in (rawget(self, "_world") :: World).clients do
		methods.FireClient(self, client.player, ...)
	end
end

local instanceMeta = {}

function instanceMeta.__index(self: any, key: string): any
	if key == "ClassName" then
		return rawget(self, "_class")
	elseif key == "Parent" then
		return rawget(self, "_parent")
	elseif key == "AbsoluteSize" then
		local x, y = absoluteSize(rawget(self, "_world"), self)
		return vector2(x, y)
	elseif key == "AbsolutePosition" then
		local x, y = absolutePosition(rawget(self, "_world"), self)
		return vector2(x, y)
	elseif key == "TextFits" then
		return textFits(rawget(self, "_world"), self)
	end
	local props = rawget(self, "_props")
	local value = props[key]
	if value ~= nil then
		return value
	end
	if methods[key] then
		return methods[key]
	end
	local child = methods.FindFirstChild(self, key)
	if child then
		return child
	end
	local signals = rawget(self, "_signals")
	if signals[key] then
		return signals[key]
	end
	if EVENTS[key] then
		signals[key] = newSignal(rawget(self, "_world"))
		return signals[key]
	end
	return nil
end

function instanceMeta.__newindex(self: any, key: string, value: any)
	if key == "Parent" then
		local old = rawget(self, "_parent")
		if old then
			local siblings = rawget(old, "_children")
			local at = table.find(siblings, self)
			if at then
				table.remove(siblings, at)
			end
		end
		rawset(self, "_parent", value)
		if value then
			table.insert(rawget(value, "_children"), self)
		end
		return
	end
	rawget(self, "_props")[key] = value
end

function instanceMeta.__tostring(self: any): string
	return rawget(self, "_props").Name
end

newInstance = function(world: World, className: string, name: string?): any
	local inst = setmetatable({
		_world = world,
		_class = className,
		_parent = nil,
		_children = {},
		_props = { Name = name or className },
		_signals = {},
		_services = {},
	}, instanceMeta)
	if TEXT_CLASSES[className] then
		rawget(inst, "_props").Text = if className == "TextBox" then "" else "Label"
		rawget(inst, "_props").TextSize = 14 -- Roblox's default
	end
	if GUI_OBJECTS[className] or className == "ScreenGui" then
		-- Like Roblox: GUI objects are visible and enabled unless told otherwise.
		rawget(inst, "_props").Visible = true
		rawget(inst, "_props").Enabled = true
	end
	if GUI_OBJECTS[className] then
		rawget(inst, "_props").BackgroundTransparency = 0
	end
	if className == "UITextSizeConstraint" then
		rawget(inst, "_props").MinTextSize = 1
		rawget(inst, "_props").MaxTextSize = 100
	end
	if className == "RemoteEvent" then
		-- One signal for the server, one per client peer.
		local signals = rawget(inst, "_signals")
		signals.OnServerEvent = newSignal(world)
		signals.OnClientEvent = newSignal(world)
	end
	return inst
end

-- ---------------------------------------------------------------- module loading

-- Sources are read up front (Lune's file reads yield, which would suspend the
-- script threads), keyed by absolute path.
local sources: { [string]: string } = {}

local function readSource(path: string): string
	local source = sources[path]
	assert(source, `no source loaded for {path}`)
	return source
end

local loadScript: (world: World, peer: Peer, path: string, inst: any) -> ...any

local function stdEnv(world: World, peer: Peer, path: string, inst: any): { [string]: any }
	local game = peer.game
	local env: { [string]: any } = {
		game = game,
		workspace = game:GetService("Workspace"),
		script = inst,
		task = taskLibrary(world, peer),
		Enum = Enum,
		Color3 = Color3,
		UDim = { new = udim },
		UDim2 = UDim2,
		Vector2 = { new = vector2 },
		Instance = {
			new = function(className: string, parent: any?)
				local created = newInstance(world, className)
				if parent then
					created.Parent = parent
				end
				return created
			end,
		},
		Random = {
			new = function(seed: number?)
				local rng = Rng.new(seed or (world.seed + #peer.log * 7919 + 1))
				return {
					NextInteger = function(_self: any, lo: number, hi: number): number
						return Rng.nextInt(rng, lo, hi)
					end,
					NextNumber = function(_self: any, lo: number?, hi: number?): number
						local a, b = lo or 0, hi or 1
						return a + (b - a) * Rng.nextFloat(rng)
					end,
				}
			end,
		},
		-- The server rate-limits with os.clock; on the simulated clock a whole match
		-- takes milliseconds of real time, so real time would trip the limit.
		os = (function()
			local fake = table.clone(os)
			fake.clock = function(): number
				return world.clock
			end
			-- Unix time on the simulated clock, so lock ages and `at` stamps follow sim time.
			fake.time = function(): number
				return math.floor(world.clock)
			end
			return fake
		end)(),
		print = function(...: any)
			local parts = {}
			for k = 1, select("#", ...) do
				parts[k] = tostring((select(k, ...)))
			end
			table.insert(peer.log, table.concat(parts, " "))
		end,
		warn = function(...: any)
			local parts = {}
			for k = 1, select("#", ...) do
				parts[k] = tostring((select(k, ...)))
			end
			table.insert(peer.log, "WARN " .. table.concat(parts, " "))
		end,
	}
	env.require = function(target: any): any
		if type(target) == "string" then
			local dir = string.match(path, "^(.*)/[^/]+$") :: string
			if string.match(path, "/init%.luau$") then
				dir = string.match(dir, "^(.*)/[^/]+$") :: string
			end
			local resolved = dir .. "/" .. target
			-- Collapse "./" and "../" segments.
			local parts = {}
			for segment in string.gmatch(resolved, "[^/]+") do
				if segment == ".." then
					table.remove(parts)
				elseif segment ~= "." then
					table.insert(parts, segment)
				end
			end
			local file = (if string.sub(resolved, 1, 1) == "/" then "/" else "") .. table.concat(parts, "/")
			if sources[file .. ".luau"] then
				file ..= ".luau"
			else
				file ..= "/init.luau"
			end
			return loadScript(world, peer, file, nil)
		end
		local file = rawget(target, "_path")
		assert(file, `require of a non-module {tostring(target)}`)
		return loadScript(world, peer, file, target)
	end
	return env
end

loadScript = function(world: World, peer: Peer, path: string, inst: any): ...any
	local cached = peer.modules[path]
	if cached ~= nil then
		return cached
	end
	local chunk = luau.load(readSource(path), {
		debugName = string.sub(path, #world.root + 2),
		environment = stdEnv(world, peer, path, inst),
	})
	local result = chunk()
	peer.modules[path] = result
	return result
end

-- Builds the instance tree for one Rojo path: folders, ModuleScripts, Scripts.
local function mount(world: World, dir: string, parent: any)
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			local folder = newInstance(world, "Folder", entry)
			folder.Parent = parent
			mount(world, path, folder)
		else
			local base, kind = string.match(entry, "^(.-)%.(%a+)%.luau$")
			local className = "ModuleScript"
			if kind == "server" then
				className = "Script"
			elseif kind == "client" then
				className = "LocalScript"
			else
				base = string.match(entry, "^(.-)%.luau$")
			end
			if base then
				sources[path] = fs.readFile(path)
				local script = newInstance(world, className, base)
				rawset(script, "_path", path)
				script.Parent = parent
			end
		end
	end
end

-- ---------------------------------------------------------------- peers and world

local clientFolder: any = nil -- StarterPlayerScripts contents, mounted once per world

local function newGame(world: World, isServer: boolean): any
	local game = newInstance(world, "DataModel", "Game")
	local services = rawget(game, "_services")
	for _, name in
		{
			"Players",
			"Workspace",
			"RunService",
			"ServerScriptService",
			"StarterPlayer",
			"StarterGui",
			"UserInputService",
		}
	do
		local service = newInstance(world, name, name)
		service.Parent = game
		services[name] = service
	end
	services.ReplicatedStorage = world.shared
	services.DataStoreService = newDataStoreService(world)
	rawget(game, "_props").JobId = if isServer then world.jobId else ""
	if isServer then
		local spsParent = newInstance(world, "StarterPlayerScripts", "StarterPlayerScripts")
		spsParent.Parent = services.StarterPlayer
	end
	return game
end

local function newPeer(world: World, name: string, isServer: boolean): Peer
	local game = newGame(world, isServer)
	local runService = game:GetService("RunService")
	local peer: Peer = {
		name = name,
		isServer = isServer,
		player = nil,
		game = game,
		modules = {},
		log = {},
		runStepped = nil,
		heartbeat = nil,
		inbox = {},
	}
	local signals = rawget(runService, "_signals")
	signals.Heartbeat = newSignal(world)
	signals.RenderStepped = newSignal(world)
	peer.heartbeat = signals.Heartbeat
	peer.runStepped = signals.RenderStepped
	return peer
end

-- A new world with the server running. `root` is the repository root.
function FakeRoblox.world(options: { root: string, seed: number?, screen: { x: number, y: number }? }): World
	local world = {
		clock = 1000,
		seed = options.seed or 1,
		root = (string.gsub(options.root, "/+$", "")),
		screen = options.screen or { x = 1280, y = 720 },
		tasks = {},
		seq = 0,
		current = nil,
		server = nil :: any,
		clients = {},
		shared = nil :: any,
		errors = {},
		wireWarnings = {},
		nextUserId = 1,
		data = {
			stores = {},
			unpublished = false,
			unpublishedMessage = "You must publish this place to the web to access DataStore.",
			failures = 0,
			reruns = 0,
			latency = 0.2,
			requests = 0,
			writes = 0,
		},
		jobId = "job-1",
		closeHandlers = {},
		studio = true,
		clientFolder = nil,
	} :: World
	world.shared = newInstance(world, "ReplicatedStorage", "ReplicatedStorage")
	local sharedFolder = newInstance(world, "Folder", "Shared")
	sharedFolder.Parent = world.shared
	mount(world, `{world.root}/src/shared`, sharedFolder)

	world.server = newPeer(world, "server", true)
	local sss = world.server.game:GetService("ServerScriptService")
	local serverFolder = newInstance(world, "Folder", "Server")
	serverFolder.Parent = sss
	mount(world, `{world.root}/src/server`, serverFolder)
	clientFolder = newInstance(world, "Folder", "Client")
	mount(world, `{world.root}/src/client`, clientFolder)
	world.clientFolder = clientFolder
	for _, inst in serverFolder:GetDescendants() do
		if inst.ClassName == "Script" then
			spawnOn(world, world.server, function()
				loadScript(world, world.server, rawget(inst, "_path"), inst)
			end)
		end
	end
	return world
end

-- A player joins: the server sees PlayerAdded, and the client scripts start.
-- `extra` is either a user id (a number: brings back a returning player; default a
-- new one) or a table of attributes set on that client's workspace first (e.g.
-- DebugScreen = "Plan" renders a fixture screen offline; see src/client/App.client.luau).
function FakeRoblox.join(world: World, name: string, extra: any?): Peer
	local userId: number? = if type(extra) == "number" then extra else nil
	local attributes: { [string]: any }? = if type(extra) == "table" then extra else nil
	local id = userId or world.nextUserId
	if id >= world.nextUserId then
		world.nextUserId = id + 1
	end
	local peer = newPeer(world, name, false)
	if attributes then
		local clientWorkspace = peer.game:GetService("Workspace")
		for key, value in attributes do
			clientWorkspace:SetAttribute(key, value)
		end
	end

	local function makePlayer(game: any): any
		local player = newInstance(world, "Player", name)
		player.UserId = id
		player.DisplayName = name
		local gui = newInstance(world, "PlayerGui", "PlayerGui")
		gui.Parent = player
		player.Parent = game:GetService("Players")
		return player
	end

	local serverPlayer = makePlayer(world.server.game)
	peer.player = serverPlayer
	-- The client's own Players service holds the same Player as LocalPlayer.
	local clientPlayers = peer.game:GetService("Players")
	clientPlayers.LocalPlayer = serverPlayer
	table.insert(world.clients, peer)

	local serverPlayers = world.server.game:GetService("Players")
	world.current = world.server
	serverPlayers.PlayerAdded.fire(serverPlayer)
	world.current = nil

	for _, inst in world.clientFolder:GetDescendants() do
		if inst.ClassName == "LocalScript" then
			spawnOn(world, peer, function()
				loadScript(world, peer, rawget(inst, "_path"), inst)
			end)
		end
	end
	return peer
end

-- A player leaves: PlayerRemoving fires and their client stops receiving.
function FakeRoblox.leave(world: World, peer: Peer)
	local players = world.server.game:GetService("Players")
	world.current = world.server
	players.PlayerRemoving.fire(peer.player)
	world.current = nil
	local at = table.find(world.clients, peer)
	if at then
		table.remove(world.clients, at)
	end
	peer.player.Parent = nil
	for k = #world.tasks, 1, -1 do
		if world.tasks[k].peer == peer then
			table.remove(world.tasks, k)
		end
	end
end

-- Delivers queued remote messages: client requests to the server, then server
-- messages to each client.
local function deliver(world: World)
	local inbox = world.server.inbox
	world.server.inbox = {}
	for _, item in inbox do
		local remote, player, args = item[1], item[2], item[3]
		if player.Parent ~= nil then
			world.current = world.server
			rawget(remote, "_signals").OnServerEvent.fire(player, table.unpack(args))
			world.current = nil
		end
	end
	for _, client in world.clients do
		local queued = client.inbox
		client.inbox = {}
		for _, item in queued do
			local remote, args = item[1], item[3]
			for _, connection in rawget(remote, "_signals").OnClientEvent.connections do
				if connection.connected and connection.peer == client then
					spawnOn(world, client, connection.fn, table.unpack(args))
				end
			end
		end
	end
end

-- Advances the clock by `dt`: messages, then due tasks, then frame signals.
function FakeRoblox.step(world: World, dt: number)
	world.clock += dt
	deliver(world)
	local due = {}
	local rest = {}
	for _, item in world.tasks do
		if item.at <= world.clock then
			table.insert(due, item)
		else
			table.insert(rest, item)
		end
	end
	world.tasks = rest
	table.sort(due, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.seq < b.seq
	end)
	for _, item in due do
		if coroutine.status(item.co) == "suspended" then
			resume(world, item.peer, item.co, table.unpack(item.args))
		end
	end
	world.current = world.server
	world.server.heartbeat.fire(dt)
	for _, client in world.clients do
		world.current = client
		client.heartbeat.fire(dt)
		client.runStepped.fire(dt)
	end
	world.current = nil
	deliver(world)
end

-- Runs the world for `seconds` of simulated time.
function FakeRoblox.run(world: World, seconds: number, dt: number?)
	local stepSize = dt or 0.1
	local steps = math.ceil(seconds / stepSize)
	for _ = 1, steps do
		FakeRoblox.step(world, stepSize)
	end
end

-- Runs until `predicate()` is true or `limit` seconds pass. Returns whether it held.
function FakeRoblox.runUntil(world: World, predicate: () -> boolean, limit: number, dt: number?): boolean
	local stepSize = dt or 0.1
	local waited = 0
	while waited < limit do
		if predicate() then
			return true
		end
		FakeRoblox.step(world, stepSize)
		waited += stepSize
	end
	return predicate()
end

-- The server is closing: runs every game:BindToClose callback in parallel, then
-- up to Roblox's 30 simulated seconds for them to finish. Returns true if they all did.
function FakeRoblox.shutdown(world: World): boolean
	local finished = 0
	local handlers = table.clone(world.closeHandlers)
	for _, handler in handlers do
		spawnOn(world, world.server, function()
			handler()
			finished += 1
		end)
	end
	FakeRoblox.runUntil(world, function()
		return finished == #handlers
	end, 30)
	return finished == #handlers
end

-- ---------------------------------------------------------------- client UI helpers

-- Requires a client module as `peer` would (its own copy, sharing that peer's
-- cache): `path` is relative to the repository root, e.g. "src/client/UI/Kit.luau".
function FakeRoblox.require(world: World, peer: Peer, path: string): any
	local full = `{world.root}/{path}`
	for _, inst in world.clientFolder:GetDescendants() do
		if rawget(inst, "_path") == full then
			local previous = world.current
			world.current = peer
			local result = loadScript(world, peer, full, inst)
			world.current = previous
			return result
		end
	end
	error(`no client module at {path}`)
end

-- The fake engine's value types, for tests that build GUI trees themselves.
FakeRoblox.types = {
	UDim = { new = udim },
	UDim2 = UDim2,
	Vector2 = { new = vector2 },
	Color3 = Color3,
	Enum = Enum,
}

local function gui(peer: Peer): any
	return peer.player:FindFirstChild("PlayerGui")
end

-- Finds a UI element in a client's PlayerGui by Name.
function FakeRoblox.find(peer: Peer, name: string): any
	local root = gui(peer)
	if root == nil then
		return nil
	end
	for _, inst in root:GetDescendants() do
		if inst.Name == name then
			return inst
		end
	end
	return nil
end

-- What the player's debug UI shows right now.
function FakeRoblox.screen(peer: Peer): { status: string, board: string, log: string }
	local function text(name: string): string
		local inst = FakeRoblox.find(peer, name)
		return if inst then tostring(inst.Text) else ""
	end
	return { status = text("Status"), board = text("Board"), log = text("Log") }
end

-- Types a command into the debug UI's command box and presses Enter.
function FakeRoblox.type(world: World, peer: Peer, command: string)
	local box = FakeRoblox.find(peer, "CommandBox")
	assert(box, `{peer.name} has no command box`)
	box.Text = command
	world.current = peer
	box.FocusLost.fire(true)
	world.current = nil
end

-- Presses a debug UI button by its label.
function FakeRoblox.press(world: World, peer: Peer, label: string)
	local button = FakeRoblox.find(peer, label)
	assert(button, `{peer.name} has no button {label}`)
	world.current = peer
	button.Activated.fire()
	world.current = nil
end

-- Sends a raw request as this client, bypassing the UI (for cheating tests).
function FakeRoblox.fire(world: World, peer: Peer, payload: any)
	local remotes = world.shared:FindFirstChild("Remotes")
	assert(remotes, "remotes are not set up")
	world.current = peer
	remotes.ToServer:FireServer(payload)
	world.current = nil
end

return FakeRoblox
