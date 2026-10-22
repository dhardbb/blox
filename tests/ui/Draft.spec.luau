--!strict
-- The Draft screen (map reveal + 8 blind rounds) on the fake Roblox engine:
-- fixtures render offline with a clean UI audit in 16:9 and phone portrait, the
-- list and map pickers fill the ranked top 2, illegal states are refused, Lock In
-- submits, reveals show both picks, and a live practice match drafts through the
-- screen and on to week 1.

local process = require("@lune/process")

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Session = require("@net/Session")
local Support = require("../e2e/Support")

local describe, it, expect = Test.describe, Test.it, Test.expect

local PHONE = { x = 390, y = 844 }
local DRAFT_LIMIT = 120 -- simulated seconds to reach week 1 from a fresh practice match

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function logged(peer: FakeRoblox.Peer, text: string): boolean
	for _, line in peer.log do
		if string.find(line, text, 1, true) then
			return true
		end
	end
	return false
end

local function contains(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

-- A world with one player looking at a fixture screen.
local function mount(moment: string, screen: { x: number, y: number }?): (FakeRoblox.World, FakeRoblox.Peer)
	local world = FakeRoblox.world({ root = process.cwd, seed = 3, screen = screen })
	local peer = FakeRoblox.join(world, "P", { DebugScreen = moment })
	FakeRoblox.run(world, 1.5)
	return world, peer
end

local function noErrors(world: FakeRoblox.World)
	check(#world.errors == 0, "script errors: " .. table.concat(world.errors, " | "))
	check(#world.wireWarnings == 0, "wire warnings: " .. table.concat(world.wireWarnings, " | "))
end

-- Finds `name` inside the Draft screen's frame.
local function findIn(peer: FakeRoblox.Peer, name: string): any
	local root = FakeRoblox.find(peer, "Draft")
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

local function need(peer: FakeRoblox.Peer, name: string): any
	local inst = findIn(peer, name)
	check(inst ~= nil, `the Draft screen has no element {name}`)
	return inst
end

local function textOf(peer: FakeRoblox.Peer, name: string): string
	return tostring(need(peer, name).Text)
end

local function tap(world: FakeRoblox.World, peer: FakeRoblox.Peer, name: string)
	local inst = need(peer, name)
	world.current = peer
	inst.Activated.fire()
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

-- The payload the "Draft" fixture shows (the client builds it with the same call).
local function draftPayload(): Session.StatePayload
	return Fixtures.payload(Config.defaults, "Draft")
end

-- Two states a stronghold round allows, and one it does not.
local function sampleStates(payload: Session.StatePayload): (string, string, string)
	local legal: { string } = {}
	local taken: string? = nil
	for _, sv in payload.view.states do
		if sv.owner == nil and not sv.battleground then
			table.insert(legal, sv.id)
		elseif taken == nil then
			taken = sv.id
		end
	end
	check(#legal >= 3 and taken ~= nil, "the fixture has no taken state")
	return legal[1], legal[2], taken :: string
end

-- Pushes a payload into the client's Store, as the server would.
local function push(world: FakeRoblox.World, peer: FakeRoblox.Peer, payload: any)
	local store = peer.modules[`{world.root}/src/client/Store.luau`]
	check(store ~= nil, "the Store module is not loaded")
	store.setPayload(payload)
	FakeRoblox.run(world, 0.3)
end

-- The fixture payload turned into the reveal of its round: `mine` and `theirs` picked.
local function revealOf(base: Session.StatePayload, mine: string, theirs: string): any
	local payload = deepCopy(base)
	payload.step += 1
	payload.stage = "Reveal"
	payload.reveal = "Draft"
	local round = payload.view.draftRound
	payload.events = {
		{ kind = "Pick", player = payload.you, state = mine, issue = "Stronghold" },
		{ kind = "Pick", player = 3 - payload.you, state = theirs, issue = "Stronghold" },
	}
	for _, pick in payload.events do
		table.insert(
			payload.view.draftLog,
			{ round = round, player = pick.player, state = pick.state, kind = "Stronghold" }
		)
		table.insert(payload.view.players[pick.player].strongholds, pick.state)
		for _, sv in payload.view.states do
			if sv.id == pick.state then
				sv.owner = pick.player
			end
		end
	end
	return payload
end

describe("Draft screen: fixtures", function()
	for _, moment in { "MapReveal", "Draft" } do
		for _, phone in { false, true } do
			local label = `{moment} {if phone then "on a phone" else "at 16:9"}`
			it(`mounts {label} with a clean audit`, function()
				local world, peer = mount(moment, if phone then PHONE else nil)
				noErrors(world)
				check(
					logged(peer, "UI audit Draft: 0 problem(s)"),
					"no clean audit line: " .. table.concat(peer.log, " | ")
				)
				check(
					not logged(peer, "WARN [270] UI audit"),
					"audit warnings: " .. table.concat(peer.log, " | ")
				)
				for _, name in { "NodeMap", "Header", "Timer", "StateList", "Board", "Legend" } do
					need(peer, name)
				end
			end)
		end
	end

	it("shows the map heading and no pickers during the map reveal", function()
		local _world, peer = mount("MapReveal")
		expect(textOf(peer, "Header")):toBe("The map for this match")
		expect(need(peer, "Slots").Visible):toBe(false)
		expect(need(peer, "LockBar").Visible):toBe(false)
		check(contains(textOf(peer, "Priority"), "priority"), textOf(peer, "Priority"))
	end)

	it("describes the round and who has priority", function()
		local _world, peer = mount("Draft")
		local header = textOf(peer, "Header")
		check(contains(header, "Round 4 of 8"), header)
		check(contains(header, "STRONGHOLD"), header)
		check(contains(textOf(peer, "Explain"), "+8"), textOf(peer, "Explain"))
		local priority = textOf(peer, "Priority")
		check(contains(priority, "have priority"), priority)
		expect(need(peer, "LockBar").Visible):toBe(true)
	end)

	it("has a tappable row for every state, biggest first, and a map node", function()
		local _world, peer = mount("Draft")
		local StateData = require("@sim/StateData")
		for _, record in StateData.list do
			need(peer, `Row_{record.id}`)
			need(peer, record.id)
		end
		-- California (54 EV) leads the list.
		local list = need(peer, "StateList")
		local first: any = nil
		for _, child in list:GetChildren() do
			if
				child.ClassName == "TextButton" and (first == nil or child.LayoutOrder < first.LayoutOrder)
			then
				first = child
			end
		end
		expect(first.Name):toBe("Row_CA")
	end)

	it("puts the legend and board under the map on wide screens and in the panel on phones", function()
		local _w1, wide = mount("Draft")
		expect(need(wide, "Board").Parent.Name):toBe("Below")
		local _w2, phone = mount("Draft", PHONE)
		expect(need(phone, "Board").Parent.Name):toBe("PanelScroll")
		expect(need(phone, "Legend").Parent.Name):toBe("PanelScroll")
	end)
end)

describe("Draft screen: picking", function()
	it("fills the ranked top 2 from the list, and un-picks on a second tap", function()
		local world, peer = mount("Draft")
		local a, b = sampleStates(draftPayload())
		tap(world, peer, `Row_{a}`)
		check(contains(textOf(peer, "Choice1"), `({a})`), textOf(peer, "Choice1"))
		check(contains(textOf(peer, "Choice2"), "tap a state"), textOf(peer, "Choice2"))
		tap(world, peer, `Row_{b}`)
		check(contains(textOf(peer, "Choice2"), `({b})`), textOf(peer, "Choice2"))
		-- A third state replaces the backup, not the first choice.
		local c = select(3, sampleStates(draftPayload()))
		expect(c ~= a):toBe(true)
		tap(world, peer, `Row_{a}`)
		check(
			contains(textOf(peer, "Choice1"), `({b})`),
			"the backup should move up: " .. textOf(peer, "Choice1")
		)
		check(contains(textOf(peer, "Choice2"), "tap a state"), textOf(peer, "Choice2"))
		noErrors(world)
	end)

	it("takes a tap on a map node too, and clears with the clear buttons", function()
		local world, peer = mount("Draft")
		local a, b = sampleStates(draftPayload())
		tap(world, peer, a)
		check(contains(textOf(peer, "Choice1"), `({a})`), textOf(peer, "Choice1"))
		tap(world, peer, `Row_{b}`)
		tap(world, peer, "Clear1")
		check(contains(textOf(peer, "Choice1"), `({b})`), "clearing the 1st choice promotes the backup")
		tap(world, peer, `Row_{a}`)
		tap(world, peer, "ClearChoices")
		check(contains(textOf(peer, "Choice1"), "tap a state"), textOf(peer, "Choice1"))
		check(contains(textOf(peer, "Choice2"), "tap a state"), textOf(peer, "Choice2"))
		noErrors(world)
	end)

	it("aims at a slot when you tap Choice2 first", function()
		local world, peer = mount("Draft")
		local a, b = sampleStates(draftPayload())
		tap(world, peer, `Row_{a}`)
		tap(world, peer, "Choice1")
		tap(world, peer, `Row_{b}`)
		check(
			contains(textOf(peer, "Choice1"), `({b})`),
			"the aimed slot takes the pick: " .. textOf(peer, "Choice1")
		)
		noErrors(world)
	end)

	it("refuses a state that is already drafted", function()
		local world, peer = mount("Draft")
		local _a, _b, taken = sampleStates(draftPayload())
		tap(world, peer, `Row_{taken}`)
		check(
			contains(textOf(peer, "Choice1"), "tap a state"),
			"an illegal state was picked: " .. textOf(peer, "Choice1")
		)
		tap(world, peer, taken)
		check(contains(textOf(peer, "Choice1"), "tap a state"), "an illegal map tap was picked")
		check(contains(textOf(peer, "Hint"), "already"), textOf(peer, "Hint"))
		noErrors(world)
	end)

	it("only enables Lock In once there is a first choice", function()
		local world, peer = mount("Draft")
		local a = sampleStates(draftPayload())
		tap(world, peer, "LockIn")
		check(not logged(peer, "DEBUG_UI submit"), "locked in with nothing chosen")
		tap(world, peer, `Row_{a}`)
		expect(textOf(peer, "LockIn")):toBe("Lock In")
	end)
end)

describe("Draft screen: locking in", function()
	it("submits the choices and shows the locked state", function()
		local world, peer = mount("Draft")
		local a, b = sampleStates(draftPayload())
		tap(world, peer, `Row_{a}`)
		tap(world, peer, `Row_{b}`)
		tap(world, peer, "LockIn")
		check(logged(peer, "[270] DEBUG_UI submit"), "no submit line: " .. table.concat(peer.log, " | "))
		expect(textOf(peer, "LockIn")):toBe("Locked")
		check(contains(textOf(peer, "LockStatus"), "Locked"), textOf(peer, "LockStatus"))
		check(contains(textOf(peer, "LockStatus"), "waiting for opponent"), textOf(peer, "LockStatus"))
		check(contains(textOf(peer, "OpponentStatus"), "Opponent"), textOf(peer, "OpponentStatus"))
		-- Locked means locked: more taps change nothing and nothing is sent twice.
		local sent = 0
		for _, line in peer.log do
			if contains(line, "DEBUG_UI submit") then
				sent += 1
			end
		end
		tap(world, peer, "Clear1")
		tap(world, peer, "LockIn")
		check(contains(textOf(peer, "Choice1"), `({a})`), "a locked choice changed")
		local after = 0
		for _, line in peer.log do
			if contains(line, "DEBUG_UI submit") then
				after += 1
			end
		end
		expect(after):toBe(sent)
		noErrors(world)
	end)

	it("allows locking in with a single choice", function()
		local world, peer = mount("Draft")
		local a = sampleStates(draftPayload())
		tap(world, peer, `Row_{a}`)
		check(contains(textOf(peer, "Hint"), "No backup"), textOf(peer, "Hint"))
		tap(world, peer, "LockIn")
		check(logged(peer, "[270] DEBUG_UI submit"), "no submit line")
		expect(textOf(peer, "LockIn")):toBe("Locked")
	end)
end)

describe("Draft screen: reveal and rounds", function()
	it("shows both picks after a round and highlights them", function()
		local world, peer = mount("Draft")
		local base = draftPayload()
		local a, b = sampleStates(base)
		push(world, peer, revealOf(base, a, b))
		noErrors(world)
		expect(textOf(peer, "Header")):toBe("Round 4 of 8 — picks revealed")
		expect(need(peer, "RevealBox").Visible):toBe(true)
		expect(need(peer, "LockBar").Visible):toBe(false)
		expect(need(peer, "Slots").Visible):toBe(false)
		expect(tostring(need(peer, "YouPick"):FindFirstChild("Title").Text)):toBe(`You got {a}`)
		expect(tostring(need(peer, "ThemPick"):FindFirstChild("Title").Text)):toBe(`They got {b}`)
		-- The new owners show in the draft board.
		check(contains(textOf(peer, "Detail"), a) or contains(textOf(peer, "Detail"), b), "board not updated")
	end)

	it("says who won a clash when your first choice went to the other player", function()
		local world, peer = mount("Draft")
		local base = draftPayload()
		local a, b = sampleStates(base)
		tap(world, peer, `Row_{a}`)
		tap(world, peer, `Row_{b}`)
		tap(world, peer, "LockIn")
		-- They took your first choice; you fell back to your second.
		push(world, peer, revealOf(base, b, a))
		local note = tostring(need(peer, "ClashNote").Text)
		check(contains(note, a) and contains(note, "instead"), "clash note: " .. note)
		expect(need(peer, "ClashNote").Visible):toBe(true)
		-- Getting what you asked for needs no note.
		push(world, peer, revealOf(base, a, b))
		expect(need(peer, "ClashNote").Visible):toBe(false)
		noErrors(world)
	end)

	it("starts the next round with clean slots", function()
		local world, peer = mount("Draft")
		local base = draftPayload()
		local a, b = sampleStates(base)
		tap(world, peer, `Row_{a}`)
		tap(world, peer, "LockIn")
		push(world, peer, revealOf(base, a, b))
		local nextRound = deepCopy(base)
		nextRound.step += 2
		nextRound.view.draftRound += 1
		nextRound.view.draftKind = "Stronghold"
		for _, sv in nextRound.view.states do
			if sv.id == a then
				sv.owner = nextRound.you
			elseif sv.id == b then
				sv.owner = 3 - nextRound.you
			end
		end
		push(world, peer, nextRound)
		check(contains(textOf(peer, "Header"), "Round 5 of 8"), textOf(peer, "Header"))
		check(contains(textOf(peer, "Choice1"), "tap a state"), textOf(peer, "Choice1"))
		expect(textOf(peer, "LockIn") ~= "Locked"):toBe(true)
		-- The two states just drafted are no longer pickable.
		tap(world, peer, `Row_{a}`)
		check(contains(textOf(peer, "Choice1"), "tap a state"), "a drafted state was picked")
		noErrors(world)
	end)

	it("shows the final reveal after round 8, when the match is already in week 1", function()
		local world, peer = mount("Draft")
		local base = draftPayload()
		local a, b = sampleStates(base)
		local last = revealOf(base, a, b)
		last.view.phase = "Plan"
		last.view.week = 1
		last.view.draftKind = nil
		last.view.draftPriority = nil
		last.view.draftRound = 7
		for _, pick in last.view.draftLog do
			if pick.round == 3 then
				pick.round = 7
			end
		end
		push(world, peer, last)
		noErrors(world)
		expect(textOf(peer, "Header")):toBe("Round 8 of 8 — picks revealed")
		check(contains(textOf(peer, "Explain"), "campaign"), textOf(peer, "Explain"))
	end)
end)

describe("Draft screen: a live match", function()
	for _, phone in { false, true } do
		it(`drafts through the screen and reaches week 1 ({if phone then "phone" else "16:9"})`, function()
			local rig = Support.new(process.cwd, 9, if phone then PHONE else nil)
			local p1 = Support.join(rig, "Player1")
			Support.press(rig, p1, "Practice")
			-- Play Select with the debug panel's Auto button, then wait for round 1.
			check(Support.autoUntil(rig, { p1 }, "Draft round 1", 60), "never reached the draft")
			check(findIn(p1, "LockIn") ~= nil, "the Draft screen is not showing")
			local world = rig.world
			-- Round 1 through the screen: two homes from the list, then Lock In.
			tap(world, p1, "Row_CA")
			tap(world, p1, "Row_TX")
			tap(world, p1, "LockIn")
			Support.run(rig, 3)
			check(logged(p1, "UI audit Draft: 0 problem(s)"), "the Draft screen was never audited")
			local title = tostring(need(p1, "YouPick"):FindFirstChild("Title").Text)
			check(contains(title, "You got"), "no reveal after round 1: " .. title)
			-- Then let Autoplay finish the draft.
			Support.press(rig, p1, "Autoplay")
			check(Support.untilStatus(rig, p1, "Week 1", DRAFT_LIMIT), "never reached week 1")
			local problems: { string } = {}
			for _, message in world.errors do
				table.insert(problems, message)
			end
			check(#problems == 0, "script errors: " .. table.concat(problems, " | "))
			for _, line in p1.log do
				check(not contains(line, "UI audit Draft: ") or contains(line, ": 0 problem(s)"), line)
			end
		end)
	end
end)
