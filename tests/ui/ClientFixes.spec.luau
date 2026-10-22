--!strict
-- Client bugs found by the bug hunt, each with the spec that failed first:
-- the Campaign state list, auto-submit before a timer ends, message ids instead
-- of counts, the Draft's disconnected opponent, the forfeit countdown, the
-- spare Debug-button space, the Results rating line, readable rejection codes
-- and a Lobby that never locks a player out.

local process = require("@lune/process")

local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Plan = require("@sim/Plan")
local Config = require("@sim/Config")
local Session = require("@net/Session")
local StateOrder = require("@ui/StateOrder")
local StateData = require("@sim/StateData")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

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
local function pickAll(world: FakeRoblox.World, peer: FakeRoblox.Peer)
	tap(world, peer, "Select", "Candidate_hale")
	tap(world, peer, "Select", "Color_Teal")
	for _, issue in { "Jobs", "Health", "Farms" } do
		tap(world, peer, "Select", `Issue_{issue}`)
	end
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

-- ------------------------------------------------------------------ bug 1

describe("StateOrder", function()
	local view = Fixtures.payload(Config.defaults, "Plan").view

	it("sorts by closeness, then size, then code", function()
		local ids = StateOrder.sort(view, "Closest")
		expect(#ids):toBe(#StateData.list)
		local index: { [string]: number } = {}
		for i, record in StateData.list do
			index[record.id] = i
		end
		for k = 2, #ids do
			local a, b = view.states[index[ids[k - 1]]], view.states[index[ids[k]]]
			local gapA, gapB = math.abs(StateOrder.margin(view, a)), math.abs(StateOrder.margin(view, b))
			check(gapA <= gapB, `{ids[k - 1]} ({gapA}) is listed before {ids[k]} ({gapB})`)
			if gapA == gapB then
				local evA, evB = StateData.byId[ids[k - 1]].ev, StateData.byId[ids[k]].ev
				check(evA >= evB, "equally close states are not biggest first")
			end
		end
	end)

	it("sorts by size and by name", function()
		local big = StateOrder.sort(view, "Biggest")
		for k = 2, #big do
			check(StateData.byId[big[k - 1]].ev >= StateData.byId[big[k]].ev, "not biggest first")
		end
		local names = StateOrder.sort(view, "Name")
		expect(StateData.byId[names[1]].name):toBe("Alabama")
		for k = 2, #names do
			check(StateData.byId[names[k - 1]].name < StateData.byId[names[k]].name, "not A to Z")
		end
	end)

	it("cycles through every mode and back", function()
		local mode = StateOrder.MODES[1]
		local seen = {}
		for _ = 1, #StateOrder.MODES do
			seen[mode] = true
			mode = StateOrder.nextMode(mode)
		end
		expect(mode):toBe(StateOrder.MODES[1])
		for _, each in StateOrder.MODES do
			check(seen[each] == true and #StateOrder.label(each) > 0, `mode {each} was skipped`)
		end
	end)

	it("reads the margin from the poll, or from the lean before one", function()
		local sv = deepCopy(view.states[1])
		sv.poll = { support = { [view.you] = 44, [3 - view.you] = 41 }, undecided = 15 }
		expect(StateOrder.margin(view, sv)):toBe(3)
		expect(StateOrder.marginText(view, sv)):toBe("You +3")
		sv.poll = { support = { [view.you] = 40, [3 - view.you] = 45 }, undecided = 15 }
		expect(StateOrder.marginText(view, sv)):toBe("Them +5")
		sv.poll = { support = { [view.you] = 40, [3 - view.you] = 40 }, undecided = 20 }
		expect(StateOrder.marginText(view, sv)):toBe("Tied")
		sv.poll = nil
		sv.leanTo = 3 - view.you
		sv.lean = 4
		expect(StateOrder.margin(view, sv)):toBe(-4)
		expect(StateOrder.marginText(view, sv)):toBe("Lean: Them +4")
		sv.leanTo = nil
		expect(StateOrder.marginText(view, sv)):toBe("No poll")
	end)

	it("writes your momentum with a sign", function()
		local sv = deepCopy(view.states[1])
		sv.momentum = { [view.you] = 1.26 }
		expect(StateOrder.momentumText(view, sv)):toBe("Mom +1.3")
		sv.momentum = { [view.you] = -0.5 }
		expect(StateOrder.momentumText(view, sv)):toBe("Mom -0.5")
		sv.momentum = { [view.you] = 0.01 }
		expect(StateOrder.momentumText(view, sv)):toBe("Mom 0")
	end)
end)

describe("Campaign state list", function()
	it("is collapsed until asked for, then lists every state", function()
		local world, peer = fixture("Plan", PHONE)
		local toggle = need(peer, "Campaign", "StatesToggle")
		check(shown(toggle, "Campaign"), "no states button on the campaign screen")
		check(not shown(need(peer, "Campaign", "StatePicker"), "Campaign"), "the list starts open")
		tap(world, peer, "Campaign", "StatesToggle")
		check(shown(need(peer, "Campaign", "StatePicker"), "Campaign"), "the list did not open")
		for _, record in StateData.list do
			need(peer, "Campaign", `Row_{record.id}`)
		end
		local problems = audit(peer, "Campaign")
		check(#problems == 0, "open list: " .. table.concat(problems, "; "))
		noErrors(world)
	end)

	it("selects the states the phone map hides, in two taps", function()
		local world, peer = fixture("Plan", PHONE)
		for _, id in { "MA", "DE", "DC", "CT", "WV" } do
			tap(world, peer, "Campaign", "StatesToggle")
			tap(world, peer, "Campaign", `Row_{id}`)
			local title = textOf(peer, "Campaign", "CardTitle")
			check(contains(title, StateData.byId[id].name), `{id}: the card shows "{title}"`)
			check(not shown(need(peer, "Campaign", "StatePicker"), "Campaign"), "the list stays open")
		end
		noErrors(world)
	end)

	it("works on a wide screen and the state's actions follow the pick", function()
		local world, peer = fixture("Plan", nil)
		tap(world, peer, "Campaign", "StatesToggle")
		tap(world, peer, "Campaign", "Row_WY")
		check(contains(textOf(peer, "Campaign", "CardTitle"), "Wyoming"), "Wyoming was not selected")
		check(contains(textOf(peer, "Campaign", "Fundraise"), "Fundraise"), "no action buttons")
		tap(world, peer, "Campaign", "Fundraise")
		check(
			contains(textOf(peer, "Campaign", "PlanItem1"), "Wyoming"),
			textOf(peer, "Campaign", "PlanItem1")
		)
		noErrors(world)
	end)

	it("shows each row's poll and your momentum, and re-sorts", function()
		local world, peer = fixture("Plan", nil)
		tap(world, peer, "Campaign", "StatesToggle")
		local row = need(peer, "Campaign", "Row_OH")
		local texts = {}
		for _, inst in row:GetDescendants() do
			if inst.ClassName == "TextLabel" then
				table.insert(texts, tostring(inst.Text))
			end
		end
		local all = table.concat(texts, " | ")
		check(contains(all, "OH") and contains(all, "EV"), `row text: {all}`)
		check(contains(all, "Mom"), `no momentum in the row: {all}`)
		local first = textOf(peer, "Campaign", "StatesSort")
		tap(world, peer, "Campaign", "StatesSort")
		check(textOf(peer, "Campaign", "StatesSort") ~= first, "the sort button did not change")
		local biggest = StateData.list[1]
		for _, record in StateData.list do
			if record.ev > biggest.ev or (record.ev == biggest.ev and record.id < biggest.id) then
				biggest = record
			end
		end
		check(
			need(peer, "Campaign", `Row_{biggest.id}`).LayoutOrder == 1,
			`{biggest.id} is not first when sorted by size`
		)
		tap(world, peer, "Campaign", "StatesSort")
		check(need(peer, "Campaign", "Row_AL").LayoutOrder == 1, "Alabama is not first by name")
		noErrors(world)
	end)
end)

-- ------------------------------------------------------------------ bug 2

describe("Auto-submit before the timer ends", function()
	it("Select locks a complete, unlocked pick", function()
		local world, peer = practice(3)
		tap(world, peer, "Lobby", "Practice", 1)
		pickAll(world, peer)
		local calls = spySubmits(world, peer)
		waitFor(world, function()
			return payloadOf(world, peer).view.phase ~= "Select"
		end, 60, "the end of Select")
		local me = payloadOf(world, peer).view.players[1]
		expect(me.candidate):toBe("hale")
		expect(me.color):toBe("Teal")
		expect(#calls):toBe(1)
		noErrors(world)
	end)

	it("Select leaves an incomplete pick to the server", function()
		local world, peer = practice(3)
		tap(world, peer, "Lobby", "Practice", 1)
		tap(world, peer, "Select", "Candidate_hale")
		local calls = spySubmits(world, peer)
		waitFor(world, function()
			return payloadOf(world, peer).view.phase ~= "Select"
		end, 60, "the end of Select")
		expect(#calls):toBe(0)
		noErrors(world)
	end)

	it("Select sends the pre-pick as soon as the pick is complete", function()
		local world, peer = fixture("Select", nil)
		tap(world, peer, "Select", "Candidate_hale")
		tap(world, peer, "Select", "Color_Teal")
		tap(world, peer, "Select", "Issue_Jobs")
		tap(world, peer, "Select", "Issue_Health")
		expect(count(peer, "DEBUG_UI send PrePick")):toBe(0)
		tap(world, peer, "Select", "Issue_Schools")
		expect(count(peer, "DEBUG_UI send PrePick")):toBe(1)
		-- Locking the same pick does not send it again.
		tap(world, peer, "Select", "LockIn")
		expect(count(peer, "DEBUG_UI send PrePick")):toBe(1)
		expect(count(peer, "DEBUG_UI submit")):toBe(1)
		noErrors(world)
	end)

	it("Draft locks the current choices", function()
		local world, peer = practice(3)
		toDraftInput(world, peer)
		local view = payloadOf(world, peer).view
		local mine = safeState(view)
		local calls = spySubmits(world, peer)
		tap(world, peer, "Draft", `Row_{mine}`)
		waitFor(world, function()
			return payloadOf(world, peer).reveal == "Draft"
		end, 60, "the draft reveal")
		expect(#calls):toBe(1)
		local got = false
		for _, pick in payloadOf(world, peer).view.draftLog do
			if pick.player == 1 and pick.state == mine then
				got = true
			end
		end
		check(got, `the pick {mine} was thrown away at the deadline`)
		noErrors(world)
	end)

	it("Draft submits nothing when no state is picked", function()
		local world, peer = practice(3)
		toDraftInput(world, peer)
		local calls = spySubmits(world, peer)
		waitFor(world, function()
			return payloadOf(world, peer).reveal == "Draft"
		end, 60, "the draft reveal")
		expect(#calls):toBe(0)
		noErrors(world)
	end)

	it("Draft never double-submits after a manual lock", function()
		local world, peer = practice(3)
		toDraftInput(world, peer)
		local mine = safeState(payloadOf(world, peer).view)
		local calls = spySubmits(world, peer)
		tap(world, peer, "Draft", `Row_{mine}`)
		tap(world, peer, "Draft", "LockIn")
		waitFor(world, function()
			return payloadOf(world, peer).reveal == "Draft"
		end, 60, "the draft reveal")
		expect(#calls):toBe(1)
		noErrors(world)
	end)

	it("Campaign locks the plan that was built", function()
		local world, peer = practice(3)
		toPlanInput(world, peer)
		local view = payloadOf(world, peer).view
		local calls = spySubmits(world, peer)
		tap(world, peer, "Campaign", view.players[1].location, 0.05)
		tap(world, peer, "Campaign", "Rally", 0.05)
		tap(world, peer, "Campaign", "Ad", 0.05)
		waitFor(world, function()
			return payloadOf(world, peer).reveal == "Resolve"
		end, 200, "the resolve reveal")
		FakeRoblox.run(world, 1)
		expect(#calls):toBe(1)
		local mentions = 0
		for k = 1, 8 do
			local line = findIn(peer, "Campaign", `RevealLine{k}`)
			if line and contains(tostring(line.Text), "You rallied") then
				mentions += 1
			end
		end
		check(mentions == 1, `the reveal shows {mentions} lines about your rally`)
		noErrors(world)
	end)

	it("Campaign never double-submits after a manual lock", function()
		local world, peer = practice(3)
		toPlanInput(world, peer)
		local calls = spySubmits(world, peer)
		tap(world, peer, "Campaign", "LockIn")
		waitFor(world, function()
			return payloadOf(world, peer).reveal == "Resolve"
		end, 200, "the resolve reveal")
		expect(#calls):toBe(1)
		noErrors(world)
	end)

	it("an offline Campaign fixture submits once, half a second early", function()
		local world, peer = fixture("Plan", nil)
		local left = payloadOf(world, peer).deadline - world.clock
		FakeRoblox.run(world, left - 2)
		expect(count(peer, "DEBUG_UI submit")):toBe(0)
		FakeRoblox.run(world, 1.9)
		expect(count(peer, "DEBUG_UI submit")):toBe(1)
		FakeRoblox.run(world, 10)
		expect(count(peer, "DEBUG_UI submit")):toBe(1)
		noErrors(world)
	end)

	it("Campaign submits nothing when the draft has a problem", function()
		local world, peer = fixture("Plan", nil)
		local view = payloadOf(world, peer).view
		tap(world, peer, "Campaign", view.players[view.you].location, 0.05)
		tap(world, peer, "Campaign", "Ad", 0.05)
		-- The money is gone by the time the timer ends: the plan no longer fits.
		local broke = deepCopy(payloadOf(world, peer))
		broke.view.players[broke.view.you].cash = 0
		push(world, peer, broke)
		FakeRoblox.run(world, broke.deadline - world.clock + 5)
		expect(count(peer, "DEBUG_UI submit")):toBe(0)
		noErrors(world)
	end)
end)

-- ------------------------------------------------------------------ bug 3

describe("Messages are told apart by id", function()
	it("keeps counting past the size of the log", function()
		local world, peer = practice(3)
		local store = storeOf(world, peer)
		local last = 0
		for k = 1, 30 do
			store.say(`message {k}`)
			local messages = store.get().messages
			local newest = messages[#messages]
			check(type(newest) == "table" and newest.text == `message {k}`, "newest message is wrong")
			check(newest.id > last, "ids do not grow")
			last = newest.id
		end
		noErrors(world)
	end)

	it("shows the Lobby toast for every rejection, not only the first 20", function()
		local world, peer = practice(3)
		local box = need(peer, "Lobby", "CodeBox")
		for k = 1, 24 do
			box.Text = "ZZZZ9"
			tap(world, peer, "Lobby", "Join", 0.3)
			check(shown(need(peer, "Lobby", "Toast"), "Lobby"), `no toast for attempt {k}`)
			FakeRoblox.run(world, 5)
			check(not shown(need(peer, "Lobby", "Toast"), "Lobby"), "the toast never went away")
		end
		noErrors(world)
	end)

	it("lets Draft retry a rejected lock-in even with a full log", function()
		local world, peer = practice(3)
		local store = storeOf(world, peer)
		for k = 1, 25 do
			store.say(`filler {k}`)
		end
		toDraftInput(world, peer)
		sabotageSubmits(world, peer, { choices = { "ZZ" } })
		tap(world, peer, "Draft", `Row_{safeState(payloadOf(world, peer).view)}`)
		tap(world, peer, "Draft", "LockIn", 1)
		expect(textOf(peer, "Draft", "LockIn")):toBe("Lock In")
		check(enabled(peer, "Draft", "LockIn"), "Lock In stays disabled after a rejection")
		noErrors(world)
	end)

	it("lets Campaign retry a rejected plan even with a full log", function()
		local world, peer = practice(3)
		local store = storeOf(world, peer)
		toPlanInput(world, peer)
		for k = 1, 25 do
			store.say(`filler {k}`)
		end
		sabotageSubmits(world, peer, { actions = { { kind = "Zzz" } } })
		tap(world, peer, "Campaign", "LockIn", 1)
		check(enabled(peer, "Campaign", "LockIn"), "Lock in stays disabled after a rejection")
		check(
			not contains(textOf(peer, "Campaign", "StageLabel"), "Locked"),
			"the stage still says Locked in"
		)
		noErrors(world)
	end)

	it("lets Select retry a rejected lock-in", function()
		local world, peer = practice(3)
		tap(world, peer, "Lobby", "Practice", 1)
		pickAll(world, peer)
		sabotageSubmits(world, peer, { candidate = "hale", color = "Teal", platform = { "Jobs" } })
		tap(world, peer, "Select", "LockIn", 1)
		expect(textOf(peer, "Select", "LockIn")):toBe("Lock In")
		check(enabled(peer, "Select", "LockIn"), "Lock In stays disabled after a rejection")
		noErrors(world)
	end)

	it("Select keeps a lock-in the server accepted", function()
		local world, peer = practice(3)
		tap(world, peer, "Lobby", "Practice", 1)
		pickAll(world, peer)
		local store = storeOf(world, peer)
		tap(world, peer, "Select", "LockIn", 0.01)
		-- An unrelated message arriving must not reopen a locked pick.
		store.say("Your opponent is back.")
		FakeRoblox.run(world, 0.05)
		if findIn(peer, "Select", "LockIn") then
			expect(textOf(peer, "Select", "LockIn")):toBe("Locked")
		end
		noErrors(world)
	end)
end)

-- ------------------------------------------------------------------ bugs 4 and 5

describe("A disconnected opponent", function()
	it("shows on the Draft screen", function()
		local world, peer = fixture("Draft", nil)
		local base = payloadOf(world, peer)
		local them = 3 - base.you
		local before = textOf(peer, "Draft", "OpponentStatus")
		local away = deepCopy(base)
		away.seats[them].connected = false
		away.seats[them].graceUntil = world.clock + 20
		push(world, peer, away)
		check(
			contains(textOf(peer, "Draft", "OpponentStatus"), "disconnected"),
			textOf(peer, "Draft", "OpponentStatus")
		)
		push(world, peer, deepCopy(base))
		expect(textOf(peer, "Draft", "OpponentStatus")):toBe(before)
		noErrors(world)
	end)

	it("drops the auto-submit countdown once the grace period is over", function()
		local world, peer = fixture("Plan", nil)
		local base = payloadOf(world, peer)
		local them = 3 - base.you
		local away = deepCopy(base)
		away.seats[them].connected = false
		away.seats[them].graceUntil = world.clock + 5
		push(world, peer, away)
		local notice = need(peer, "Campaign", "OpponentNotice")
		check(notice.Visible ~= false, "no disconnected notice")
		check(contains(tostring(notice.Text), "auto-submit in"), tostring(notice.Text))
		FakeRoblox.run(world, 6)
		expect(tostring(notice.Text)):toBe("Opponent disconnected")
		noErrors(world)
	end)
end)

-- ------------------------------------------------------------------ bug 6

describe("No space is kept for a Debug button", function()
	it("pins the Select footer to the bottom edge on a phone", function()
		local _, peer = fixture("Select", PHONE)
		local bar = need(peer, "Select", "FooterBar")
		expect(bar.Position.Y.Offset):toBe(0)
	end)

	it("leaves the footer full width on a wide screen", function()
		local _, peer = fixture("Select", nil)
		local bar = need(peer, "Select", "FooterBar")
		local pad = bar:FindFirstChildOfClass("UIPadding")
		check(pad == nil or pad.PaddingRight.Offset == 0, "the footer is padded away from the right edge")
	end)

	it("does not pad the bottom of the Lobby page", function()
		local _, peer = fixture("Lobby", PHONE)
		local content = need(peer, "Lobby", "Content")
		expect(content:FindFirstChildOfClass("UIPadding").PaddingBottom.Offset <= 16):toBe(true)
	end)
end)

-- ------------------------------------------------------------------ bug 7

describe("Results rating line", function()
	it("FakeRoblox finds descendants with FindFirstChild(name, true)", function()
		local _, peer = fixture("Over", nil)
		local screens = FakeRoblox.find(peer, "Screens")
		check(screens:FindFirstChild("RatingChange") == nil, "RatingChange is not a direct child")
		check(screens:FindFirstChild("RatingChange", true) ~= nil, "the recursive search found nothing")
		check(screens:FindFirstChild("NoSuchThing", true) == nil, "found a thing that does not exist")
	end)

	it("shows the rating change of this match", function()
		local world, peer = fixture("Over", nil)
		local store = storeOf(world, peer)
		local matchId = payloadOf(world, peer).matchId
		check(not shown(need(peer, "Results", "RatingChange"), "Results"), "the rating line shows early")
		world.current = peer
		store.setRating({ matchId = matchId, before = 1000, after = 1016 })
		world.current = nil
		FakeRoblox.run(world, 0.3)
		expect(textOf(peer, "Results", "RatingChange")):toBe("Rating 1000 → 1016 (+16)")
		check(shown(need(peer, "Results", "RatingChange"), "Results"), "the rating line is hidden")
		noErrors(world)
	end)

	it("writes a loss with a minus sign", function()
		local world, peer = fixture("Over", nil)
		local matchId = payloadOf(world, peer).matchId
		world.current = peer
		storeOf(world, peer).setRating({ matchId = matchId, before = 1016, after = 1004 })
		world.current = nil
		FakeRoblox.run(world, 0.3)
		expect(textOf(peer, "Results", "RatingChange")):toBe("Rating 1016 → 1004 (-12)")
	end)

	it("ignores a change that belongs to an earlier match", function()
		local world, peer = fixture("Over", nil)
		world.current = peer
		storeOf(world, peer).setRating({ matchId = "an-earlier-match", before = 900, after = 920 })
		world.current = nil
		FakeRoblox.run(world, 0.3)
		check(not shown(need(peer, "Results", "RatingChange"), "Results"), "a stale rating change is shown")
		expect(textOf(peer, "Results", "RatingChange")):toBe("")
		noErrors(world)
	end)
end)

-- ------------------------------------------------------------------ bug 8

describe("Rejection codes", function()
	local CODES: { string } = {
		-- Server and request checks
		"NotInMatch",
		"Internal",
		"RateLimited",
		"BadShape",
		"UnknownOp",
		"BadCode",
		"Rejected",
		-- Lobby
		"InMatch",
		"ServerFull",
		"CodeTaken",
		"NoSuchCode",
		"OwnCode",
		-- Match and Draft
		"WrongPhase",
		"UnknownCandidate",
		"UnknownColor",
		"BadPlatform",
		"UnknownPlayer",
		"UnknownState",
		"BadChoiceCount",
		"DuplicateChoice",
		"IllegalChoice",
	}
	for _, code in Plan.Reason do
		table.insert(CODES, code)
	end
	for _, code in Session.Reason do
		table.insert(CODES, code)
	end

	it("has readable text for every code the client can receive", function()
		local world, peer = practice(3)
		local net = netOf(world, peer)
		local missing = {}
		for _, code in CODES do
			local text = net.reasonText(code)
			if string.sub(text, 1, 9) == "Rejected:" then
				table.insert(missing, code)
			end
		end
		check(#missing == 0, "no text for: " .. table.concat(missing, ", "))
	end)

	it("falls back to the code itself for one it does not know", function()
		local world, peer = practice(3)
		expect(netOf(world, peer).reasonText("Brand New")):toBe("Rejected: Brand New")
		expect(netOf(world, peer).reasonText(nil)):toBe("Rejected: unknown")
	end)

	it("labels the fundraising pool as its size", function()
		local world, peer = fixture("Plan", nil)
		local view = payloadOf(world, peer).view
		tap(world, peer, "Campaign", view.players[view.you].location)
		local ground = textOf(peer, "Campaign", "CardGround")
		check(contains(ground, "pool size $"), ground)
		check(not contains(ground, "fundraising pool"), ground)
	end)
end)

-- ------------------------------------------------------------------ bug 9

describe("A full server never locks the Lobby", function()
	it("keeps the banner as information and the buttons working", function()
		local world, peer = fixture("Lobby", nil)
		local full = Fixtures.lobby("Idle")
		full.full = true
		world.current = peer
		storeOf(world, peer).setLobby(full)
		world.current = nil
		FakeRoblox.run(world, 0.3)
		check(shown(need(peer, "Lobby", "ServerFull"), "Lobby"), "no server full banner")
		for _, name in { "Practice", "FindMatch", "Host", "Join" } do
			check(enabled(peer, "Lobby", name), `{name} is disabled while the status says full`)
		end
		tap(world, peer, "Lobby", "Practice")
		expect(count(peer, "DEBUG_UI send Practice")):toBe(1)
		tap(world, peer, "Lobby", "FindMatch")
		expect(count(peer, "DEBUG_UI send Queue")):toBe(1)
		tap(world, peer, "Lobby", "Host")
		expect(count(peer, "DEBUG_UI send Host")):toBe(1)
		need(peer, "Lobby", "CodeBox").Text = "AB3CD"
		tap(world, peer, "Lobby", "Join")
		expect(count(peer, "DEBUG_UI send Join")):toBe(1)
		noErrors(world)
	end)

	it("hides the banner again when the status says there is room", function()
		local world, peer = fixture("Lobby", nil)
		local full = Fixtures.lobby("Idle")
		full.full = true
		world.current = peer
		storeOf(world, peer).setLobby(full)
		storeOf(world, peer).setLobby(Fixtures.lobby("Idle"))
		world.current = nil
		FakeRoblox.run(world, 0.3)
		check(not shown(need(peer, "Lobby", "ServerFull"), "Lobby"), "the banner stays")
	end)
end)
