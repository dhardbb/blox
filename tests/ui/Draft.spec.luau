--!strict
-- The Draft screen (map reveal + 3 blind rounds) on the fake Roblox engine:
-- fixtures render offline with a clean UI audit in 16:9 and phone portrait, the
-- list and map pickers fill the ranked top 2, illegal states are refused, Lock In
-- submits, reveals show both picks, and a live practice match drafts through the
-- screen and on to week 1. Also the v0.3.1 bug-hunt cases: auto-submit, a
-- retry after a rejection, and the disconnected opponent. The UI overhaul
-- (WP4) cases measure the explicitly positioned boxes: the portrait split, the
-- list ahead of the board, the pinned action bar, and a strict audit.

local process = require("@lune/process")

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Rig = require("./Rig")
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

-- The header's title line.
local function titleOf(peer: FakeRoblox.Peer): string
	local header = need(peer, "Header")
	for _, inst in header:GetDescendants() do
		if inst.Name == "Title" then
			return tostring(inst.Text)
		end
	end
	error("the Draft header has no title", 0)
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

-- Two states the fixture's nomination round allows, and one it does not (a home).
local function sampleStates(payload: Session.StatePayload): (string, string, string)
	local legal: { string } = {}
	local taken: string? = nil
	for _, sv in payload.view.states do
		if not sv.isHome and not sv.battleground then
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
		{ kind = "Pick", player = payload.you, state = mine, issue = "Nominate" },
		{ kind = "Pick", player = 3 - payload.you, state = theirs, issue = "Nominate" },
	}
	for _, pick in payload.events do
		table.insert(
			payload.view.draftLog,
			{ round = round, player = pick.player, state = pick.state, kind = "Nominate" }
		)
		table.insert(payload.view.players[pick.player].nominations, pick.state)
		for _, sv in payload.view.states do
			if sv.id == pick.state then
				sv.battleground = true
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
		expect(titleOf(peer)):toBe("The map for this match")
		expect(need(peer, "Slots").Visible):toBe(false)
		expect(need(peer, "ActionBar").Visible):toBe(false)
		check(contains(textOf(peer, "Priority"), "priority"), textOf(peer, "Priority"))
		-- Strongholds are assigned before the draft and shown for both players (D-045).
		local line = need(peer, "Strongholds")
		expect(line.Visible):toBe(true)
		check(contains(tostring(line.Text), "Your strongholds: "), tostring(line.Text))
		check(contains(tostring(line.Text), "theirs: "), tostring(line.Text))
		check(contains(textOf(peer, "HowItWorks"), "strongest-leaning"), textOf(peer, "HowItWorks"))
		check(contains(textOf(peer, "HowItWorks"), "3 blind rounds"), textOf(peer, "HowItWorks"))
	end)

	it("describes the round and who has priority", function()
		local _world, peer = mount("Draft")
		local header = titleOf(peer)
		check(contains(header, "Round 2 of 3"), header)
		check(contains(header, "Nominate"), header)
		check(contains(textOf(peer, "Explain"), "×1.5"), textOf(peer, "Explain"))
		expect(need(peer, "Strongholds").Visible):toBe(true)
		local priority = textOf(peer, "Priority")
		check(contains(priority, "have priority"), priority)
		expect(need(peer, "ActionBar").Visible):toBe(true)
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
		expect(need(wide, "Legend").Parent.Name):toBe("Below")
		local _w2, phone = mount("Draft", PHONE)
		expect(need(phone, "Board"):FindFirstAncestor("BoardCard") ~= nil):toBe(true)
		expect(need(phone, "Legend"):FindFirstAncestor("BoardCard") ~= nil):toBe(true)
		expect(need(phone, "BoardCard").Parent.Name):toBe("PanelScroll")
	end)
end)

describe("Draft screen: picking", function()
	it("fills the ranked top 2 from the list, and un-picks on a second tap", function()
		local world, peer = mount("Draft")
		local a, b = sampleStates(draftPayload())
		tap(world, peer, `Row_{a}`)
		expect(textOf(peer, "Choice1")):toBe(`1st: {a}`)
		expect(textOf(peer, "Choice2")):toBe("2nd: —")
		tap(world, peer, `Row_{b}`)
		expect(textOf(peer, "Choice2")):toBe(`2nd: {b}`)
		-- A third state replaces the backup, not the first choice.
		local c = select(3, sampleStates(draftPayload()))
		expect(c ~= a):toBe(true)
		tap(world, peer, `Row_{a}`)
		expect(textOf(peer, "Choice1")):toBe(`1st: {b}`)
		expect(textOf(peer, "Choice2")):toBe("2nd: —")
		noErrors(world)
	end)

	it("takes a tap on a map node too, and clears with the × buttons", function()
		local world, peer = mount("Draft")
		local a, b = sampleStates(draftPayload())
		tap(world, peer, a)
		expect(textOf(peer, "Choice1")):toBe(`1st: {a}`)
		tap(world, peer, `Row_{b}`)
		tap(world, peer, "Clear1")
		expect(textOf(peer, "Choice1")):toBe(`1st: {b}`)
		tap(world, peer, `Row_{a}`)
		tap(world, peer, "Clear2")
		expect(textOf(peer, "Choice2")):toBe("2nd: —")
		tap(world, peer, "Clear1")
		expect(textOf(peer, "Choice1")):toBe("1st: —")
		noErrors(world)
	end)

	it("aims at a slot when you tap Choice2 first", function()
		local world, peer = mount("Draft")
		local a, b = sampleStates(draftPayload())
		tap(world, peer, `Row_{a}`)
		tap(world, peer, "Choice1")
		tap(world, peer, `Row_{b}`)
		expect(textOf(peer, "Choice1")):toBe(`1st: {b}`)
		noErrors(world)
	end)

	it("refuses a state that is already drafted", function()
		local world, peer = mount("Draft")
		local _a, _b, taken = sampleStates(draftPayload())
		tap(world, peer, `Row_{taken}`)
		expect(textOf(peer, "Choice1")):toBe("1st: —")
		tap(world, peer, taken)
		expect(textOf(peer, "Choice1")):toBe("1st: —")
		check(contains(textOf(peer, "BarStatus"), "can't nominate"), textOf(peer, "BarStatus"))
		noErrors(world)
	end)

	it("refuses a stronghold in the home round (D-045)", function()
		local world, peer = mount("Draft")
		-- The fixture's round turned back into the home round: no homes yet.
		local home = deepCopy(draftPayload())
		home.step += 1
		home.view.draftRound = 0
		home.view.draftKind = "Home"
		home.view.draftPriority = home.view.priorityA
		for _, sv in home.view.states do
			if sv.isHome then
				sv.isHome = false
				sv.owner = nil
			end
			sv.battleground = false
		end
		for _, player in home.view.players do
			player.home = nil
			player.nominations = {}
		end
		push(world, peer, home)
		check(contains(titleOf(peer), "Round 1 of 3"), titleOf(peer))
		for _, p in { home.you, 3 - home.you } do
			local stronghold = home.view.players[p].strongholds[1]
			tap(world, peer, `Row_{stronghold}`)
			expect(textOf(peer, "Choice1")):toBe("1st: —")
			expect(textOf(peer, "BarStatus")):toBe(`{stronghold}: a stronghold, can't be a home`)
		end
		noErrors(world)
	end)

	it("only enables Lock In once there is a first choice", function()
		local world, peer = mount("Draft")
		local a = sampleStates(draftPayload())
		tap(world, peer, "LockIn")
		check(not logged(peer, "DEBUG_UI submit"), "locked in with nothing chosen")
		expect(textOf(peer, "LockIn")):toBe("Pick a state")
		tap(world, peer, `Row_{a}`)
		expect(textOf(peer, "LockIn")):toBe("Lock in")
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
		expect(textOf(peer, "LockIn")):toBe("Locked in")
		expect(textOf(peer, "BarStatus")):toBe("Locked in · waiting for opponent")
		check(contains(textOf(peer, "BarOpponent"), "Opponent"), textOf(peer, "BarOpponent"))
		-- Locked means locked: more taps change nothing and nothing is sent twice.
		local sent = 0
		for _, line in peer.log do
			if contains(line, "DEBUG_UI submit") then
				sent += 1
			end
		end
		tap(world, peer, "Clear1")
		tap(world, peer, "LockIn")
		expect(textOf(peer, "Choice1")):toBe(`1st: {a}`)
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
		check(contains(textOf(peer, "BarStatus"), "backup"), textOf(peer, "BarStatus"))
		tap(world, peer, "LockIn")
		check(logged(peer, "[270] DEBUG_UI submit"), "no submit line")
		expect(textOf(peer, "LockIn")):toBe("Locked in")
	end)
end)

describe("Draft screen: reveal and rounds", function()
	it("shows both picks after a round and highlights them", function()
		local world, peer = mount("Draft")
		local base = draftPayload()
		local a, b = sampleStates(base)
		push(world, peer, revealOf(base, a, b))
		noErrors(world)
		expect(titleOf(peer)):toBe("Round 2 of 3 · picks revealed")
		expect(need(peer, "RevealBox").Visible):toBe(true)
		expect(need(peer, "ActionBar").Visible):toBe(false)
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
		nextRound.view.draftKind = "Nominate"
		for _, sv in nextRound.view.states do
			if sv.id == a or sv.id == b then
				sv.battleground = true
			end
		end
		push(world, peer, nextRound)
		check(contains(titleOf(peer), "Round 3 of 3"), titleOf(peer))
		expect(textOf(peer, "Choice1")):toBe("1st: —")
		expect(textOf(peer, "LockIn") ~= "Locked in"):toBe(true)
		-- The two states just nominated are no longer pickable.
		tap(world, peer, `Row_{a}`)
		expect(textOf(peer, "Choice1")):toBe("1st: —")
		noErrors(world)
	end)

	it("shows the final reveal after round 3, when the match is already in week 1", function()
		local world, peer = mount("Draft")
		local base = draftPayload()
		local a, b = sampleStates(base)
		local last = revealOf(base, a, b)
		last.view.phase = "Plan"
		last.view.week = 1
		last.view.draftKind = nil
		last.view.draftPriority = nil
		last.view.draftRound = 2
		for _, pick in last.view.draftLog do
			if pick.round == 1 then
				pick.round = 2
			end
		end
		push(world, peer, last)
		noErrors(world)
		expect(titleOf(peer)):toBe("Round 3 of 3 · picks revealed")
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

-- ------------------------------------------------------------------ v0.3.1 bug hunt
-- (moved here from ClientFixes.spec when it was split per screen)

describe("Draft auto-submit before the timer ends", function()
	it("Draft locks the current choices", function()
		local world, peer = Rig.practice(3)
		Rig.toDraftInput(world, peer)
		local view = Rig.payloadOf(world, peer).view
		local mine = Rig.safeState(view)
		local calls = Rig.spySubmits(world, peer)
		Rig.tap(world, peer, "Draft", `Row_{mine}`)
		Rig.waitFor(world, function()
			return Rig.payloadOf(world, peer).reveal == "Draft"
		end, 60, "the draft reveal")
		expect(#calls):toBe(1)
		local got = false
		for _, pick in Rig.payloadOf(world, peer).view.draftLog do
			if pick.player == 1 and pick.state == mine then
				got = true
			end
		end
		check(got, `the pick {mine} was thrown away at the deadline`)
		Rig.noErrors(world)
	end)

	it("Draft submits nothing when no state is picked", function()
		local world, peer = Rig.practice(3)
		Rig.toDraftInput(world, peer)
		local calls = Rig.spySubmits(world, peer)
		Rig.waitFor(world, function()
			return Rig.payloadOf(world, peer).reveal == "Draft"
		end, 60, "the draft reveal")
		expect(#calls):toBe(0)
		Rig.noErrors(world)
	end)

	it("Draft never double-submits after a manual lock", function()
		local world, peer = Rig.practice(3)
		Rig.toDraftInput(world, peer)
		local mine = Rig.safeState(Rig.payloadOf(world, peer).view)
		local calls = Rig.spySubmits(world, peer)
		Rig.tap(world, peer, "Draft", `Row_{mine}`)
		Rig.tap(world, peer, "Draft", "LockIn")
		Rig.waitFor(world, function()
			return Rig.payloadOf(world, peer).reveal == "Draft"
		end, 60, "the draft reveal")
		expect(#calls):toBe(1)
		Rig.noErrors(world)
	end)
end)

describe("Draft rejections with a full message log", function()
	it("lets Draft retry a rejected lock-in even with a full log", function()
		local world, peer = Rig.practice(3)
		local store = Rig.storeOf(world, peer)
		for k = 1, 25 do
			store.say(`filler {k}`)
		end
		Rig.toDraftInput(world, peer)
		Rig.sabotageSubmits(world, peer, { choices = { "ZZ" } })
		Rig.tap(world, peer, "Draft", `Row_{Rig.safeState(Rig.payloadOf(world, peer).view)}`)
		Rig.tap(world, peer, "Draft", "LockIn", 1)
		expect(Rig.textOf(peer, "Draft", "LockIn")):toBe("Lock in")
		check(Rig.enabled(peer, "Draft", "LockIn"), "Lock In stays disabled after a rejection")
		Rig.noErrors(world)
	end)
end)

describe("Draft with a disconnected opponent", function()
	it("shows on the Draft screen", function()
		local world, peer = Rig.fixture("Draft", nil)
		local base = Rig.payloadOf(world, peer)
		local them = 3 - base.you
		local before = Rig.textOf(peer, "Draft", "BarOpponent")
		local away = Rig.deepCopy(base)
		away.seats[them].connected = false
		away.seats[them].graceUntil = world.clock + 20
		Rig.push(world, peer, away)
		check(
			Rig.contains(Rig.textOf(peer, "Draft", "BarOpponent"), "disconnected"),
			Rig.textOf(peer, "Draft", "BarOpponent")
		)
		Rig.push(world, peer, Rig.deepCopy(base))
		expect(Rig.textOf(peer, "Draft", "BarOpponent")):toBe(before)
		Rig.noErrors(world)
	end)
end)

-- ------------------------------------------------------------------ UI overhaul (WP4)

-- Every audit finding off the map (the map is WP1's), with the PENDING list ignored.
local function strictFindings(world: FakeRoblox.World, peer: FakeRoblox.Peer): { string }
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	local out = {}
	for _, finding in Audit.check(FakeRoblox.find(peer, "Draft")) do
		if not finding.onMap then
			table.insert(out, `{finding.rule}: {finding.message}`)
		end
	end
	return out
end

local function bottom(inst: any): number
	return inst.AbsolutePosition.Y + inst.AbsoluteSize.Y
end

-- The child of PanelScroll that holds `inst`.
local function panelChild(inst: any): any
	local node = inst
	while node ~= nil and node.Parent ~= nil and node.Parent.Name ~= "PanelScroll" do
		node = node.Parent
	end
	check(node ~= nil and node.Parent ~= nil, `{inst.Name} is not in the panel`)
	return node
end

describe("Draft screen: UI overhaul (WP4)", function()
	for _, phone in { false, true } do
		local label = if phone then "on a phone" else "at 16:9"
		it(`passes the strict audit {label} in every mode`, function()
			for _, moment in { "MapReveal", "Draft" } do
				local world, peer = mount(moment, if phone then PHONE else nil)
				local problems = strictFindings(world, peer)
				check(#problems == 0, `{moment}: ` .. table.concat(problems, " | "))
				if moment == "Draft" then
					local a, b = sampleStates(draftPayload())
					tap(world, peer, `Row_{a}`)
					tap(world, peer, `Row_{b}`)
					local picked = strictFindings(world, peer)
					check(#picked == 0, "with two picks: " .. table.concat(picked, " | "))
					push(world, peer, revealOf(draftPayload(), a, b))
					local revealed = strictFindings(world, peer)
					check(#revealed == 0, "reveal: " .. table.concat(revealed, " | "))
				end
				noErrors(world)
			end
		end)

		it(`pins Lock in on screen and out of the scroll {label}`, function()
			local _world, peer = mount("Draft", if phone then PHONE else nil)
			local lock = need(peer, "LockIn")
			expect(lock:GetAttribute("PrimaryAction")):toBe(true)
			local node = lock.Parent
			while node ~= nil do
				check(node.ClassName ~= "ScrollingFrame", `Lock in scrolls inside {node.Name}`)
				node = node.Parent
			end
			local screen = FakeRoblox.find(peer, "Draft")
			check(bottom(lock) <= bottom(screen), "Lock in is below the screen")
			check(lock.AbsolutePosition.Y >= bottom(need(peer, "PanelScroll")), "Lock in overlaps the panel")
		end)
	end

	it(
		"puts the state list right after the slots in portrait, the board collapsed at the end (B10)",
		function()
			local _world, peer = mount("Draft", PHONE)
			local list = need(peer, "StateList")
			expect(list.Parent.Name):toBe("PanelScroll")
			local slots = need(peer, "Slots")
			check(slots.LayoutOrder < list.LayoutOrder, "the slots are not above the list")
			local card = panelChild(need(peer, "Board"))
			expect(card.Name):toBe("BoardCard")
			check(list.LayoutOrder < card.LayoutOrder, "the board comes before the state list")
			for _, child in need(peer, "PanelScroll"):GetChildren() do
				if child:IsA("GuiObject") and child ~= card then
					check(child.LayoutOrder < card.LayoutOrder, `{child.Name} is after the board`)
				end
			end
			local toggle = card:FindFirstChild("Toggle")
			expect(toggle:GetAttribute("Expanded")):toBe(false)
		end
	)

	it("splits a phone screen with pixel math, no dead band (B11)", function()
		local _world, peer = mount("Draft", PHONE)
		local screen = FakeRoblox.find(peer, "Draft")
		local width, height = screen.AbsoluteSize.X, screen.AbsoluteSize.Y
		local mapArea, panel = need(peer, "MapArea"), need(peer, "Panel")
		-- The lens row (44 px chips + 4 px) sits over the map, inside the same 0.34 share (D-046).
		local lensRow = 44 + 4
		local want = lensRow + math.floor(math.min(width / 1.6, 0.34 * height - lensRow))
		expect(mapArea.AbsoluteSize.Y):toBe(want)
		expect(panel.AbsolutePosition.Y):toBe(bottom(mapArea) + 8)
		expect(bottom(panel)):toBe(bottom(screen))
		expect(mapArea.AbsolutePosition.Y):toBe(bottom(need(peer, "Header")) + 8)
	end)

	it("keeps the 16:9 map at 0.66 of its column with the legend and board under it", function()
		local _world, peer = mount("Draft")
		local mapArea, holder = need(peer, "MapArea"), need(peer, "MapHolder")
		expect(math.abs(holder.AbsoluteSize.Y - 0.66 * mapArea.AbsoluteSize.Y) < 1):toBe(true)
		expect(need(peer, "Legend").Parent.Name):toBe("Below")
		expect(need(peer, "Board").Parent.Name):toBe("Below")
	end)

	it("keeps an illegal-tap reason in the bar until the next tap", function()
		local world, peer = mount("Draft")
		local a, _b, taken = sampleStates(draftPayload())
		tap(world, peer, `Row_{taken}`)
		local reason = textOf(peer, "BarStatus")
		check(contains(reason, taken) and contains(reason, "can't nominate"), reason)
		FakeRoblox.run(world, 6)
		expect(textOf(peer, "BarStatus")):toBe(reason)
		tap(world, peer, `Row_{a}`)
		check(not contains(textOf(peer, "BarStatus"), "can't"), textOf(peer, "BarStatus"))
	end)

	it("has 44x44 × buttons and no Clear both", function()
		local world, peer = mount("Draft", PHONE)
		expect(findIn(peer, "ClearChoices")):toBe(nil)
		local a, b = sampleStates(draftPayload())
		tap(world, peer, `Row_{a}`)
		tap(world, peer, `Row_{b}`)
		for _, name in { "Clear1", "Clear2" } do
			local button = need(peer, name)
			expect(button.AbsoluteSize.X):toBe(44)
			expect(button.AbsoluteSize.Y):toBe(44)
			expect(button.Visible):toBe(true)
		end
		tap(world, peer, "Clear2")
		expect(need(peer, "Clear2").Visible):toBe(false)
	end)

	for _, phone in { false, true } do
		it(
			`fills the map reveal panel with the legend and how the draft works ({if phone
				then "phone"
				else "16:9"})`,
			function()
				local world, peer = mount("MapReveal", if phone then PHONE else nil)
				local screen = FakeRoblox.find(peer, "Draft")
				expect(screen:GetAttribute("PrimaryOptional")):toBe(true)
				expect(need(peer, "ActionBar").Visible):toBe(false)
				expect(panelChild(need(peer, "Legend")).Name):toBe("Legend")
				check(need(peer, "Legend").Visible ~= false, "the legend is hidden")
				check(contains(textOf(peer, "Priority"), "priority in round 1"), textOf(peer, "Priority"))
				local how = need(peer, "HowItWorks")
				check(how.Visible ~= false and contains(tostring(how.Text), "priority"), tostring(how.Text))
				noErrors(world)
			end
		)
	end
end)

describe("drawn colors (D-047, replaces the playtest-1 color clash)", function()
	it("gives the two players different colors and never toasts about them", function()
		local world, peer = Rig.fixture("Draft", nil)
		local view = Rig.payloadOf(world, peer).view
		check(view.players[1].color ~= view.players[2].color, "two players share a color")
		for _, message in Rig.storeOf(world, peer).get().messages do
			check(string.find(message.text, "coin flip", 1, true) == nil, message.text)
		end
		Rig.noErrors(world)
	end)
end)
