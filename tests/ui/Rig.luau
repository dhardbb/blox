--!strict
-- Shared helpers for the fake-engine UI specs (tests/ui/*.spec.luau): worlds
-- with an offline fixture screen or a live practice match, finding and tapping
-- elements by Name inside a mounted screen, spying on Net, and driving a
-- practice match to the first Draft or Plan step. Not a spec itself.

local process = require("@lune/process")

local FakeRoblox = require("@testlib/FakeRoblox")

local PHONE = { x = 390, y = 844 }
local MATCH_LIMIT = 900 -- simulated seconds

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function noErrors(world: FakeRoblox.World)
	check(#world.errors == 0, "script errors: " .. table.concat(world.errors, " | "))
	check(#world.wireWarnings == 0, "wire warnings: " .. table.concat(world.wireWarnings, " | "))
end

local function contains(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

local function count(peer: FakeRoblox.Peer, text: string): number
	local n = 0
	for _, line in peer.log do
		if string.find(line, text, 1, true) then
			n += 1
		end
	end
	return n
end

local function newWorld(seed: number, screen: { x: number, y: number }?): FakeRoblox.World
	return FakeRoblox.world({ root = process.cwd, seed = seed, screen = screen })
end

-- A client showing fixture `moment` offline (DEBUG_UI mode).
local function fixture(moment: string, screen: { x: number, y: number }?): (FakeRoblox.World, FakeRoblox.Peer)
	local world = newWorld(3, screen)
	local peer = FakeRoblox.join(world, "P", { DebugScreen = moment })
	FakeRoblox.run(world, 1.5)
	return world, peer
end

-- A real server with one human, who has pressed Practice.
local function practice(seed: number): (FakeRoblox.World, FakeRoblox.Peer)
	local world = newWorld(seed)
	local peer = FakeRoblox.join(world, "A")
	FakeRoblox.run(world, 1)
	return world, peer
end

local function findIn(peer: FakeRoblox.Peer, screen: string, name: string): any
	local root = FakeRoblox.find(peer, screen)
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

local function need(peer: FakeRoblox.Peer, screen: string, name: string): any
	local inst = findIn(peer, screen, name)
	check(inst ~= nil, `{screen} has no element {name}`)
	return inst
end

local function textOf(peer: FakeRoblox.Peer, screen: string, name: string): string
	return tostring(need(peer, screen, name).Text)
end

local function tap(
	world: FakeRoblox.World,
	peer: FakeRoblox.Peer,
	screen: string,
	name: string,
	wait: number?
)
	local inst = need(peer, screen, name)
	world.current = peer
	inst.Activated.fire()
	world.current = nil
	FakeRoblox.run(world, wait or 0.3)
end

-- Shown: this element and every ancestor up to the screen holder are Visible.
local function shown(inst: any, screen: string): boolean
	local node = inst
	while node ~= nil and node.Name ~= screen do
		if node.Visible == false then
			return false
		end
		node = node.Parent
	end
	return node ~= nil
end

local function enabled(peer: FakeRoblox.Peer, screen: string, name: string): boolean
	return need(peer, screen, name).Active ~= false
end

local function storeOf(world: FakeRoblox.World, peer: FakeRoblox.Peer): any
	local store = peer.modules[`{world.root}/src/client/Store.luau`]
	check(store ~= nil, "the Store module is not loaded")
	return store
end

local function netOf(world: FakeRoblox.World, peer: FakeRoblox.Peer): any
	local net = peer.modules[`{world.root}/src/client/Net.luau`]
	check(net ~= nil, "the Net module is not loaded")
	return net
end

local function payloadOf(world: FakeRoblox.World, peer: FakeRoblox.Peer): any
	return storeOf(world, peer).get().payload
end

-- Records every Net.submit the client makes (the real one still runs).
local function spySubmits(world: FakeRoblox.World, peer: FakeRoblox.Peer): { any }
	local net = netOf(world, peer)
	local calls: { any } = {}
	local real = net.submit
	net.submit = function(input: any)
		table.insert(calls, input)
		real(input)
	end
	return calls
end

-- Makes every Net.submit send `bad` instead, so the server rejects the lock-in.
local function sabotageSubmits(world: FakeRoblox.World, peer: FakeRoblox.Peer, bad: any)
	local net = netOf(world, peer)
	local real = net.submit
	net.submit = function(_input: any)
		real(bad)
	end
end

local function push(world: FakeRoblox.World, peer: FakeRoblox.Peer, payload: any)
	world.current = peer
	storeOf(world, peer).setPayload(payload)
	world.current = nil
	FakeRoblox.run(world, 0.3)
end

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

local function waitFor(world: FakeRoblox.World, predicate: () -> boolean, limit: number, what: string)
	check(FakeRoblox.runUntil(world, predicate, limit), `never reached: {what}`)
end

-- Select through the real screen, up to (not including) Lock In.
-- A candidate nobody has claimed yet, preferring `want` (default Hale).
local function freeCandidate(world: FakeRoblox.World, peer: FakeRoblox.Peer, want: string?): string
	local p = payloadOf(world, peer)
	local claims = if p then p.view.claims else {}
	local order = { want or "hale", "okafor", "venkat", "reyes", "begay", "strand" }
	for _, id in order do
		if claims[id] == nil or claims[id] == p.you then
			return id
		end
	end
	return "calloway"
end

-- Step 1 of Select (D-045): tap a free candidate and claim it with "Next".
local function claim(world: FakeRoblox.World, peer: FakeRoblox.Peer, want: string?): string
	local id = freeCandidate(world, peer, want)
	tap(world, peer, "Select", `Candidate_{id}`)
	tap(world, peer, "Select", "LockIn")
	waitFor(world, function()
		local p = payloadOf(world, peer)
		return p ~= nil and p.view.claims[id] == p.you
	end, 5, "the claim")
	FakeRoblox.run(world, 0.3)
	return id
end

-- Both steps of Select, up to (not including) Lock in. Returns the candidate.
local function pickAll(world: FakeRoblox.World, peer: FakeRoblox.Peer): string
	local id = claim(world, peer)
	for _, issue in { "Jobs", "Health", "Farms" } do
		tap(world, peer, "Select", `Issue_{issue}`)
	end
	return id
end

-- A practice match, picked and locked, run to the first draft round.
local function toDraftInput(world: FakeRoblox.World, peer: FakeRoblox.Peer)
	tap(world, peer, "Lobby", "Practice", 1)
	pickAll(world, peer)
	tap(world, peer, "Select", "LockIn")
	waitFor(world, function()
		local p = payloadOf(world, peer)
		return p ~= nil and p.stage == "Input" and p.view.phase == "Draft"
	end, 60, "the first draft round")
end

-- A practice match run to the first week's plan.
local function toPlanInput(world: FakeRoblox.World, peer: FakeRoblox.Peer)
	tap(world, peer, "Lobby", "Practice", 1)
	pickAll(world, peer)
	tap(world, peer, "Select", "LockIn")
	local driven: { [number]: boolean } = {}
	waitFor(world, function()
		local p = payloadOf(world, peer)
		if p ~= nil and p.stage == "Input" and p.view.phase == "Draft" and not driven[p.step] then
			driven[p.step] = true
			local picks = 0
			for _, sv in p.view.states do
				local legal = if p.view.draftKind == "Nominate"
					then not sv.isHome and not sv.battleground
					else sv.owner == nil and not sv.battleground
				if legal and picks < 1 then
					tap(world, peer, "Draft", `Row_{sv.id}`, 0.05)
					picks += 1
				end
			end
			tap(world, peer, "Draft", "LockIn", 0.1)
		end
		return p ~= nil and p.stage == "Input" and p.view.phase == "Plan"
	end, MATCH_LIMIT, "the first plan")
end

-- A state the Draft screen allows in any round.
local function safeState(view: any): string
	local last: string? = nil
	for _, sv in view.states do
		if sv.owner == nil and not sv.battleground and not sv.isHome then
			last = sv.id
		end
	end
	return last :: string
end

-- Every shown button outside the map is 44 px tall, every shown text fits.
local function audit(peer: FakeRoblox.Peer, screen: string): { string }
	local problems = {}
	local holder = FakeRoblox.find(peer, screen)
	check(holder ~= nil, `{screen} is not mounted`)
	for _, inst in holder:GetDescendants() do
		local inMap = false
		local node = inst
		while node ~= nil and node ~= holder do
			if node.Name == "NodeMap" then
				inMap = true
			end
			node = node.Parent
		end
		if not inMap and shown(inst, screen) then
			if inst:IsA("GuiButton") and inst.AbsoluteSize.Y < 44 - 0.5 then
				table.insert(problems, `button {inst.Name} is {inst.AbsoluteSize.Y}px`)
			end
			if inst.ClassName == "TextLabel" or inst.ClassName == "TextButton" then
				if inst.Text ~= "" and not inst.TextWrapped and not inst.TextScaled and not inst.TextFits then
					table.insert(problems, `text in {inst.Name} is truncated`)
				end
			end
		end
	end
	return problems
end

return {
	check = check,
	noErrors = noErrors,
	contains = contains,
	count = count,
	newWorld = newWorld,
	fixture = fixture,
	practice = practice,
	findIn = findIn,
	need = need,
	textOf = textOf,
	tap = tap,
	shown = shown,
	enabled = enabled,
	storeOf = storeOf,
	netOf = netOf,
	payloadOf = payloadOf,
	spySubmits = spySubmits,
	sabotageSubmits = sabotageSubmits,
	push = push,
	deepCopy = deepCopy,
	waitFor = waitFor,
	pickAll = pickAll,
	claim = claim,
	freeCandidate = freeCandidate,
	toDraftInput = toDraftInput,
	toPlanInput = toPlanInput,
	safeState = safeState,
	audit = audit,
	PHONE = PHONE,
	MATCH_LIMIT = MATCH_LIMIT,
}
