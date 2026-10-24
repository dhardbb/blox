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
-- unpublished place and transient failures: world.data; GetOrderedDataStore
-- too, whose integer values live in world.data.ordered and whose GetSortedAsync
-- returns one DataStorePages-like page set), Players:GetNameFromUserIdAsync
-- (world.userNames, else a joined player's name; fails while
-- world.nameFailures > 0, or for an unknown id), game.JobId,
-- game:BindToClose (FakeRoblox.shutdown runs the handlers), and os.time on the
-- simulated clock.
--
-- MarketplaceService (the Color Pass, docs/DESIGN.md D-055): UserOwnsGamePassAsync
-- answers from world.market.owned after the DataStore latency, or fails while
-- world.market.failures > 0; PromptGamePassPurchase only logs the prompt in
-- world.market.prompts; FakeRoblox.finishPassPurchase plays the player's answer
-- (marks the pass owned when bought and fires the server's
-- PromptGamePassPurchaseFinished). FakeRoblox.setModuleField changes a constant
-- in a shared module on every peer (FakeRoblox.setColorPass: Net/Products).
--
-- Presentation stubs (client polish, docs/DESIGN.md D-053): TweenService
-- (Create returns a tween whose Play applies the goals at once and fires
-- Completed on the next step; Cancel fires it as Cancelled), TweenInfo,
-- ColorSequence and NumberSequence values, GuiService (ReducedMotionEnabled reads
-- world.reducedMotion, PreferredTransparency 1; FakeRoblox.setReducedMotion fires
-- its property signal), SoundService (an ordinary instance; a Sound starts
-- IsLoaded = true and every Sound:Play() is logged in world.sounds) and
-- ContentProvider (PreloadAsync reports each asset Success, or Failure when its
-- id is in world.brokenAssets). Specs assert end states, never timings.
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
	-- Ordered data stores (the leaderboard) keep their own counters and failure
	-- switch, so they never use up the failures a PlayerData spec sets up.
	ordered: { [string]: { [string]: number } }, -- ordered store name -> key -> integer value
	orderedFailures: number, -- the next N ordered-store requests fail with a transient error
	orderedRequests: number, -- ordered-store requests so far
	orderedWrites: number, -- successful ordered-store writes so far
	sortedReads: number, -- GetSortedAsync calls so far
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
	reducedMotion: boolean, -- what GuiService.ReducedMotionEnabled answers (default false)
	sounds: { SoundPlay }, -- every Sound:Play() on any client, in order
	brokenAssets: { [string]: boolean }, -- content ids PreloadAsync reports as Failure
	market: MarketState,
	overrides: { [string]: { [string]: any } }, -- module path (from the root) -> fields set after it loads
	userNames: { [number]: string }, -- usernames GetNameFromUserIdAsync knows besides joined players
	nameFailures: number, -- the next N GetNameFromUserIdAsync calls fail
	nameLookups: number, -- GetNameFromUserIdAsync calls so far
}

-- The fake MarketplaceService's world-level state. Tests flip the switches.
export type MarketState = {
	owned: { [number]: { [number]: boolean } }, -- user id -> pass id -> owned
	failures: number, -- the next N UserOwnsGamePassAsync calls fail
	checks: number, -- UserOwnsGamePassAsync calls so far
	prompts: { { userId: number, passId: number } }, -- PromptGamePassPurchase calls, in order
}

-- One Sound:Play() in the fake engine (world.sounds).
export type SoundPlay = {
	peer: string, -- the client's name
	name: string, -- the Sound's Name (UI/Audio names each Sound after its cue)
	id: string, -- its SoundId
	speed: number, -- PlaybackSpeed
	volume: number, -- Volume
	at: number, -- world.clock
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

local function vector2(x: number?, y: number?): any
	-- Vector2.new() is (0, 0), as in Roblox.
	return readonly("Vector2", { X = x or 0, Y = y or 0 }, `{x or 0}, {y or 0}`)
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

local function tweenInfo(
	time: number?,
	style: any?,
	direction: any?,
	repeatCount: number?,
	reverses: boolean?,
	delayTime: number?
): any
	return readonly("TweenInfo", {
		Time = time or 1,
		EasingStyle = style,
		EasingDirection = direction,
		RepeatCount = repeatCount or 0,
		Reverses = reverses or false,
		DelayTime = delayTime or 0,
	}, "TweenInfo")
end

-- ColorSequence.new(c) / (c0, c1) / ({ keypoints }) and NumberSequence.new(n) /
-- (n0, n1) / ({ keypoints }), with ColorSequenceKeypoint and NumberSequenceKeypoint.
local function keypoint(kind: string, time: number, value: any): any
	return readonly(kind, { Time = time, Value = value }, kind)
end
local ColorSequence = {
	new = function(a: any, b: any?): any
		local points = if type(a) == "table"
				and a.Time == nil
				and a.R == nil
			then a
			else { { Time = 0, Value = a }, { Time = 1, Value = b or a } }
		return readonly("ColorSequence", { Keypoints = points }, "ColorSequence")
	end,
}
local ColorSequenceKeypoint = {
	new = function(time: number, color: any): any
		return keypoint("ColorSequenceKeypoint", time, color)
	end,
}
local NumberSequence = {
	new = function(a: any, b: number?): any
		local points = if type(a) == "table"
			then a
			else { { Time = 0, Value = a }, { Time = 1, Value = b or a } }
		return readonly("NumberSequence", { Keypoints = points }, "NumberSequence")
	end,
}
local NumberSequenceKeypoint = {
	new = function(time: number, value: number): any
		return keypoint("NumberSequenceKeypoint", time, value)
	end,
}
local Rect = {
	new = function(x0: number?, y0: number?, x1: number?, y1: number?): any
		local a, b, c, d = x0 or 0, y0 or 0, x1 or 0, y1 or 0
		return readonly(
			"Rect",
			{ Min = vector2(a, b), Max = vector2(c, d), Width = c - a, Height = d - b },
			`{a}, {b}, {c}, {d}`
		)
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

-- MarketplaceService for one peer: game passes only.
local function newMarketplaceService(world: World): any
	return {
		UserOwnsGamePassAsync = function(_self: any, userId: number, passId: number): boolean
			local market = world.market
			market.checks += 1
			requestDelay(world)
			if market.failures > 0 then
				market.failures -= 1
				error("HTTP 500 (simulated MarketplaceService failure)", 0)
			end
			local passes = market.owned[userId]
			return passes ~= nil and passes[passId] == true
		end,
		PromptGamePassPurchase = function(_self: any, player: any, passId: number)
			table.insert(world.market.prompts, { userId = player.UserId, passId = passId })
		end,
		PromptGamePassPurchaseFinished = newSignal(world),
	}
end

-- An OrderedDataStore: integer values only; GetSortedAsync returns a pages
-- object with GetCurrentPage ({ key, value } rows), IsFinished and
-- AdvanceToNextPageAsync, as DataStorePages does.
-- Counts an ordered-store request, waits, and raises the configured failure.
local function beginOrderedRequest(world: World)
	local data = world.data
	data.orderedRequests += 1
	requestDelay(world)
	if data.unpublished then
		error(data.unpublishedMessage, 0)
	end
	if data.orderedFailures > 0 then
		data.orderedFailures -= 1
		error("503: DataStore request failed (simulated transient error)", 0)
	end
end

local function newOrderedDataStore(world: World, name: string): any
	local keys = world.data.ordered[name]
	if keys == nil then
		keys = {}
		world.data.ordered[name] = keys
	end
	local store = {}
	function store.GetAsync(_self: any, key: string): any
		beginOrderedRequest(world)
		return keys[key]
	end
	function store.SetAsync(_self: any, key: string, value: any): ()
		if type(value) ~= "number" or value ~= math.floor(value) or value ~= value then
			error("OrderedDataStore: value must be an integer", 0)
		end
		beginOrderedRequest(world)
		keys[key] = value
		world.data.orderedWrites += 1
	end
	function store.GetSortedAsync(_self: any, ascending: boolean, pageSize: number): any
		assert(type(pageSize) == "number" and pageSize >= 1 and pageSize <= 100, "pagesize must be 1 to 100")
		world.data.sortedReads += 1
		beginOrderedRequest(world)
		local rows = {}
		for key, value in keys do
			table.insert(rows, { key = key, value = value })
		end
		table.sort(rows, function(a, b)
			if a.value ~= b.value then
				return if ascending then a.value < b.value else a.value > b.value
			end
			return a.key < b.key
		end)
		local page = 1
		local pages = {}
		local function slice(): { any }
			local out = {}
			for k = (page - 1) * pageSize + 1, math.min(#rows, page * pageSize) do
				table.insert(out, table.clone(rows[k]))
			end
			return out
		end
		pages.IsFinished = #rows <= pageSize
		function pages.GetCurrentPage(_pages: any): { any }
			return slice()
		end
		function pages.AdvanceToNextPageAsync(_pages: any)
			beginOrderedRequest(world)
			page += 1
			pages.IsFinished = #rows <= page * pageSize
		end
		return pages
	end
	return store
end

local function newDataStoreService(world: World): any
	return {
		GetDataStore = function(_self: any, name: string, _scope: string?): any
			return newDataStore(world, name)
		end,
		GetOrderedDataStore = function(_self: any, name: string, _scope: string?): any
			return newOrderedDataStore(world, name)
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
	MouseLeave = true,
	Ended = true,
}

local TEXT_CLASSES = { TextLabel = true, TextButton = true, TextBox = true }

local newInstance: (world: World, className: string, name: string?) -> any
local addPresentationServices: (world: World, peer: Peer) -> ()

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
		-- A text that grows sideways is as wide as its text (textFits's estimate).
		local name = raw.AutomaticSize.Name
		if (name == "X" or name == "XY") and raw.Text ~= nil and not raw.TextWrapped then
			x = math.max(x, #tostring(raw.Text) * (raw.TextSize or 14) * 0.55)
		end
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

function methods.FindFirstAncestorWhichIsA(self: any, className: string): any
	local node = rawget(self, "_parent")
	while node do
		if node:IsA(className) then
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

-- Like Roblox: fires after the property is set to a new value (Parent included).
function methods.GetPropertyChangedSignal(self: any, name: string): any
	local signals = rawget(self, "_propSignals")
	if signals == nil then
		signals = {}
		rawset(self, "_propSignals", signals)
	end
	if signals[name] == nil then
		signals[name] = newSignal(rawget(self, "_world"))
	end
	return signals[name]
end

-- Value equality for the fake data types (UDim2, Color3, Vector2, ...): field by field.
local function sameValue(a: any, b: any): boolean
	if rawequal(a, b) then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for _, field in { "X", "Y", "Scale", "Offset", "R", "G", "B", "Name", "Min", "Max" } do
		local x, y = rawget(a, field), rawget(b, field)
		if (x ~= nil or y ~= nil) and not sameValue(x, y) then
			return false
		end
	end
	return getmetatable(a) ~= nil and getmetatable(b) ~= nil and rawget(a, "Keypoints") == nil
end

local function propertyChanged(inst: any, name: string)
	local signals = rawget(inst, "_propSignals")
	local signal = if signals then signals[name] else nil
	if signal then
		signal.fire()
	end
end

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

-- Players:GetNameFromUserIdAsync: world.userNames, else a joined player's name,
-- after the DataStore latency; fails while world.nameFailures > 0 or for an
-- id nobody has.
function methods.GetNameFromUserIdAsync(self: any, userId: number): string
	local world: World = rawget(self, "_world")
	world.nameLookups += 1
	requestDelay(world)
	if world.nameFailures > 0 then
		world.nameFailures -= 1
		error("HTTP 500 (simulated GetNameFromUserIdAsync failure)", 0)
	end
	local known = world.userNames[userId]
	if known then
		return known
	end
	for _, player in methods.GetPlayers(self) do
		if player.UserId == userId then
			return player.Name
		end
	end
	error("HTTP 400 (Unknown user)", 0)
end

function methods.GetPlayerByUserId(self: any, userId: number): any
	for _, player in methods.GetPlayers(self) do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

-- Sound: Play logs to world.sounds and sets Playing; Stop clears it.
function methods.Play(self: any)
	local world: World = rawget(self, "_world")
	local props = rawget(self, "_props")
	props.Playing = true
	props.IsPlaying = true
	local peer = world.current
	table.insert(world.sounds, {
		peer = if peer then peer.name else "?",
		name = tostring(props.Name),
		id = tostring(props.SoundId or ""),
		speed = props.PlaybackSpeed or 1,
		volume = props.Volume or 0.5,
		at = world.clock,
	})
end

function methods.Stop(self: any)
	local props = rawget(self, "_props")
	props.Playing = false
	props.IsPlaying = false
	props.TimePosition = 0
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
		if old == value then
			return
		end
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
		propertyChanged(self, "Parent")
		return
	end
	local props = rawget(self, "_props")
	local old = props[key]
	props[key] = value
	if not sameValue(old, value) then
		propertyChanged(self, key)
	end
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
	if className == "Sound" then
		local props = rawget(inst, "_props")
		props.IsLoaded = true
		props.Playing = false
		props.Volume = 0.5
		props.PlaybackSpeed = 1
		props.TimeLength = 0.5
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
		TweenInfo = { new = tweenInfo },
		ColorSequence = ColorSequence,
		ColorSequenceKeypoint = ColorSequenceKeypoint,
		NumberSequence = NumberSequence,
		NumberSequenceKeypoint = NumberSequenceKeypoint,
		Rect = Rect,
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
	local fields = world.overrides[string.sub(path, #world.root + 2)]
	if fields and type(result) == "table" then
		for key, value in fields do
			result[key] = value
		end
	end
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
	services.MarketplaceService = newMarketplaceService(world)
	rawget(game, "_props").JobId = if isServer then world.jobId else ""
	if isServer then
		local spsParent = newInstance(world, "StarterPlayerScripts", "StarterPlayerScripts")
		spsParent.Parent = services.StarterPlayer
	end
	return game
end

-- A stub Tween: Play applies the goals at once and fires Completed (Completed)
-- on the next step; Cancel before that fires it as Cancelled instead.
local function newTween(world: World, peer: Peer, inst: any, info: any, goals: { [string]: any }): any
	local completed = newSignal(world)
	local tween = {
		Instance = inst,
		TweenInfo = info,
		PlaybackState = Enum.PlaybackState.Begin,
		Completed = completed,
	}
	local token = 0
	local function finish(state: string)
		token += 1
		local mine = token
		tween.PlaybackState = (Enum.PlaybackState :: any)[state]
		local co = coroutine.create(function()
			if mine == token then
				completed.fire((Enum.PlaybackState :: any)[state])
			end
		end)
		schedule(world, world.clock, co, peer, {})
	end
	function tween.Play(_self: any)
		for key, value in goals do
			inst[key] = value
		end
		finish("Completed")
	end
	function tween.Cancel(_self: any)
		finish("Cancelled")
	end
	function tween.Pause(_self: any)
		token += 1
		tween.PlaybackState = Enum.PlaybackState.Paused
	end
	return tween
end

-- TweenService, GuiService, SoundService and ContentProvider for one peer.
addPresentationServices = function(world: World, peer: Peer)
	local game = peer.game
	local services = rawget(game, "_services")
	services.TweenService = {
		Create = function(_self: any, inst: any, info: any, goals: { [string]: any }): any
			return newTween(world, peer, inst, info, goals)
		end,
	}
	local reducedSignal = newSignal(world)
	rawset(peer :: any, "_reducedSignal", reducedSignal)
	services.GuiService = setmetatable({
		GetPropertyChangedSignal = function(_self: any, name: string): any
			return if name == "ReducedMotionEnabled" then reducedSignal else newSignal(world)
		end,
		-- The top bar's inset (Snapshot draws the same 58 px strip).
		GetGuiInset = function(_self: any): (any, any)
			return vector2(0, 58), vector2(0, 0)
		end,
	}, {
		__index = function(_, key: string): any
			if key == "ReducedMotionEnabled" then
				return world.reducedMotion
			elseif key == "PreferredTransparency" then
				return 1
			end
			return nil
		end,
	})
	local soundService = newInstance(world, "SoundService", "SoundService")
	soundService.Parent = game
	services.SoundService = soundService
	services.ContentProvider = {
		PreloadAsync = function(_self: any, list: { any }, callback: ((string, any) -> ())?)
			for _, inst in list do
				local ids = {}
				for _, node in { inst, table.unpack(inst:GetDescendants()) } do
					local id = rawget(node, "_props").SoundId
					if type(id) == "string" and id ~= "" then
						table.insert(ids, id)
					end
				end
				for _, id in ids do
					if callback then
						local status = if world.brokenAssets[id]
							then Enum.AssetFetchStatus.Failure
							else Enum.AssetFetchStatus.Success
						callback(id, status)
					end
				end
			end
		end,
	}
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
	addPresentationServices(world, peer)
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
			ordered = {},
			orderedFailures = 0,
			orderedRequests = 0,
			orderedWrites = 0,
			sortedReads = 0,
		},
		jobId = "job-1",
		closeHandlers = {},
		studio = true,
		clientFolder = nil,
		reducedMotion = false,
		sounds = {},
		brokenAssets = {},
		market = { owned = {}, failures = 0, checks = 0, prompts = {} },
		overrides = {},
		userNames = {},
		nameFailures = 0,
		nameLookups = 0,
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

-- Turns the player's Reduce Motion setting on or off for every client, firing
-- GuiService's ReducedMotionEnabled property signal as Roblox does.
function FakeRoblox.setReducedMotion(world: World, on: boolean)
	world.reducedMotion = on
	for _, client in world.clients do
		local signal = rawget(client :: any, "_reducedSignal")
		if signal then
			world.current = client
			signal.fire()
			world.current = nil
		end
	end
end

-- Sets `key` to `value` in the module at `path` (from the repository root, e.g.
-- "src/shared/Net/Products.luau") on every peer: copies already loaded now,
-- later loads (a client that joins afterwards) as they load. The module must
-- return an unfrozen table.
function FakeRoblox.setModuleField(world: World, path: string, key: string, value: any)
	local fields = world.overrides[path] or {}
	fields[key] = value
	world.overrides[path] = fields
	local full = `{world.root}/{path}`
	for _, peer in { world.server, table.unpack(world.clients) } do
		local loaded = peer.modules[full]
		if type(loaded) == "table" then
			loaded[key] = value
		end
	end
end

-- Sets up the Color Pass (Net/Products.COLOR_PASS_ID) for this world; 0 turns it off.
function FakeRoblox.setColorPass(world: World, passId: number)
	FakeRoblox.setModuleField(world, "src/shared/Net/Products.luau", "COLOR_PASS_ID", passId)
end

-- Gives (or takes back) a pass outside the game, as a purchase on the website would.
function FakeRoblox.setOwnsPass(world: World, userId: number, passId: number, owned: boolean)
	local passes = world.market.owned[userId] or {}
	passes[passId] = if owned then true else nil
	world.market.owned[userId] = passes
end

-- The player closes a pass purchase prompt: `purchased` true pays (the pass is
-- theirs) and false cancels. Fires PromptGamePassPurchaseFinished on the server.
function FakeRoblox.finishPassPurchase(world: World, peer: Peer, passId: number, purchased: boolean)
	local player = peer.player
	if purchased then
		FakeRoblox.setOwnsPass(world, player.UserId, passId, true)
	end
	local market = world.server.game:GetService("MarketplaceService")
	world.current = world.server
	market.PromptGamePassPurchaseFinished.fire(player, passId, purchased)
	world.current = nil
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
