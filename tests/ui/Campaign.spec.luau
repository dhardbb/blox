--!strict
-- The campaign screen (src/client/Screens/Campaign.luau) on the fake engine:
-- every campaign fixture mounts cleanly in 16:9 and phone portrait, the plan can
-- be built and locked in by pressing buttons, debate prep keeps its total, the
-- reveals play, and a whole autoplayed practice match runs through the screen.

local process = require("@lune/process")

local Config = require("@sim/Config")
local Events = require("@sim/Events")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local PlanDraft = require("@ui/PlanDraft")
local Support = require("../e2e/Support")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local PHONE = { x = 390, y = 844 }
local MOMENTS = { "Plan", "ChoiceWeek", "Resolve", "DebatePrep", "Debate" }

-- Fails the spec with a readable message.
local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function said(peer: FakeRoblox.Peer, text: string): boolean
	for _, line in peer.log do
		if string.find(line, text, 1, true) then
			return true
		end
	end
	return false
end

local function noErrors(world: FakeRoblox.World)
	check(#world.errors == 0, "script errors: " .. table.concat(world.errors, " | "))
end

-- A client showing fixture `moment` offline (DEBUG_UI mode).
local function fixture(moment: string, screen: { x: number, y: number }?): (FakeRoblox.World, FakeRoblox.Peer)
	local world = FakeRoblox.world({ root = process.cwd, screen = screen })
	local peer = FakeRoblox.join(world, "P", { DebugScreen = moment })
	FakeRoblox.run(world, 1)
	return world, peer
end

local function find(peer: FakeRoblox.Peer, name: string): any
	local inst = FakeRoblox.find(peer, name)
	check(inst ~= nil, `no element named {name}`)
	return inst
end

local function text(peer: FakeRoblox.Peer, name: string): string
	return tostring(find(peer, name).Text)
end

local function press(world: FakeRoblox.World, peer: FakeRoblox.Peer, name: string)
	FakeRoblox.press(world, peer, name)
	FakeRoblox.run(world, 0.1)
end

-- Shown: this element and every ancestor up to the screen holder are Visible.
local function shown(inst: any): boolean
	local node = inst
	while node ~= nil and node.Name ~= "Campaign" do
		if node.Visible == false then
			return false
		end
		node = node.Parent
	end
	return node ~= nil
end

-- A stricter audit than the router's (which the fake engine lets skip anything
-- without an explicit Visible): every shown button outside the map is at least
-- 44 px tall, and every shown text either wraps, scales, or fits.
local function audit(peer: FakeRoblox.Peer): { string }
	local problems = {}
	local holder = find(peer, "Campaign")
	for _, inst in holder:GetDescendants() do
		local inMap = false
		local node = inst
		while node ~= nil and node ~= holder do
			if node.Name == "NodeMap" then
				inMap = true
			end
			node = node.Parent
		end
		if not inMap and shown(inst) then
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

local function mountsCleanly(
	moment: string,
	screen: { x: number, y: number }?
): (FakeRoblox.World, FakeRoblox.Peer)
	local world, peer = fixture(moment, screen)
	FakeRoblox.run(world, 1)
	noErrors(world)
	check(said(peer, `screen Campaign`), `fixture {moment} did not route to Campaign`)
	check(said(peer, "UI audit Campaign: 0 problem(s)"), `no clean UI audit for {moment}`)
	local problems = audit(peer)
	check(#problems == 0, `{moment}: ` .. table.concat(problems, "; "))
	return world, peer
end

-- Values of the three prep steppers.
local function prepValues(peer: FakeRoblox.Peer): { number }
	local values = {}
	for t = 1, C.DEBATE_TOPICS do
		values[t] = tonumber(text(peer, `PrepValue{t}`)) :: number
	end
	return values
end

local function sum(list: { number }): number
	local total = 0
	for _, v in list do
		total += v
	end
	return total
end

describe("Campaign screen", function()
	for _, moment in MOMENTS do
		it(`mounts the {moment} fixture with no errors or audit problems`, function()
			local _, peer = mountsCleanly(moment)
			check(shown(find(peer, "TopBar")), "no top bar")
			check(string.find(text(peer, "WeekLabel"), "of 12", 1, true) ~= nil, "no week label")
			if moment == "Plan" or moment == "DebatePrep" or moment == "ChoiceWeek" then
				check(shown(find(peer, "LockIn")), "Lock in is hidden while planning")
				check(shown(find(peer, "StateCard")), "the state card is hidden while planning")
				check(
					text(peer, "StageLabel") == "Plan your week",
					"stage label: " .. text(peer, "StageLabel")
				)
			else
				check(shown(find(peer, "RevealPanel")), "the reveal panel is hidden")
				check(not shown(find(peer, "LockIn")), "Lock in shows during a reveal")
			end
			-- Both plan fixtures (weeks 3 and 8) are the week before a debate.
			if moment == "Plan" or moment == "DebatePrep" then
				check(shown(find(peer, "PrepPanel")), "debate prep is hidden the week before a debate")
			end
		end)
	end

	it("mounts in phone portrait with the map on top", function()
		for _, moment in MOMENTS do
			local _, peer = mountsCleanly(moment, PHONE)
			local area = find(peer, "MapArea")
			check(area.Size.X.Scale == 1, `{moment}: the map is not full width on a phone`)
			check(find(peer, "TopRow3").Visible ~= false, `{moment}: the phone top bar has no third row`)
		end
	end)

	it("builds a plan from map taps and card buttons, then locks it in", function()
		local world, peer = fixture("Plan")
		local view = Fixtures.payload(C, "Plan").view
		local home = view.players[view.you].location :: string

		press(world, peer, home)
		check(string.find(text(peer, "CardTitle"), "EV", 1, true) ~= nil, "the state card shows no state")
		local before = text(peer, "TrayCost")
		check(string.find(before, "AP used 0/3", 1, true) ~= nil, "empty tray cost: " .. before)

		-- Change the rally message in two taps, then rally, fundraise and run an ad.
		press(world, peer, "IssueButton")
		check(shown(find(peer, "IssuePicker")), "the issue picker did not open")
		press(world, peer, "IssueHealth")
		check(not shown(find(peer, "IssuePicker")), "the issue picker did not close")
		press(world, peer, "Rally")
		press(world, peer, "Fundraise")
		press(world, peer, "Ad")
		check(
			string.find(text(peer, "PlanItem1"), "Rally", 1, true) ~= nil,
			"item 1: " .. text(peer, "PlanItem1")
		)
		check(string.find(text(peer, "PlanItem1"), "Health", 1, true) ~= nil, "the picked issue was not used")
		check(
			string.find(text(peer, "PlanItem2"), "Fundraiser", 1, true) ~= nil,
			"item 2: " .. text(peer, "PlanItem2")
		)
		check(
			string.find(text(peer, "PlanItem3"), "Ad", 1, true) ~= nil,
			"item 3: " .. text(peer, "PlanItem3")
		)
		local after = text(peer, "TrayCost")
		check(after ~= before, "the tray cost did not change")
		check(string.find(after, "AP used 2/3", 1, true) ~= nil, "tray cost: " .. after)
		check(
			string.find(text(peer, "APLabel"), "AP 1 of 3", 1, true) ~= nil,
			"top bar AP: " .. text(peer, "APLabel")
		)

		-- Removing an item renumbers the tray.
		press(world, peer, "RemoveItem2")
		check(FakeRoblox.find(peer, "PlanItem3") == nil, "the removed item is still listed")
		check(string.find(text(peer, "PlanItem2"), "Ad", 1, true) ~= nil, "items were not renumbered")

		-- Out of AP: rally buttons grey out and say why.
		press(world, peer, "Rally")
		press(world, peer, "Rally")
		check(find(peer, "Rally").Active == false, "Rally is still enabled with no AP left")
		check(
			string.find(text(peer, "ActionHint"), "action points", 1, true) ~= nil,
			"hint: " .. text(peer, "ActionHint")
		)
		press(world, peer, "Rally")
		check(FakeRoblox.find(peer, "PlanItem5") == nil, "a disabled button still added an action")

		press(world, peer, "LockIn")
		check(said(peer, "[270] DEBUG_UI submit"), "Lock in sent nothing")
		check(shown(find(peer, "LockedNote")), "no locked note")
		check(
			string.find(text(peer, "LockedNote"), "waiting for opponent", 1, true) ~= nil,
			"locked note text"
		)
		check(find(peer, "Fundraise").Active == false, "the card is still editable after locking")
		check(find(peer, "RemoveItem1").Active == false, "the tray is still editable after locking")
		noErrors(world)
	end)

	it("adds GOTV units to one tray line and clears the plan", function()
		local world, peer = fixture("Plan")
		press(world, peer, "OH")
		press(world, peer, "Gotv")
		press(world, peer, "Gotv")
		check(
			string.find(text(peer, "PlanItem1"), "+2", 1, true) ~= nil,
			"gotv line: " .. text(peer, "PlanItem1")
		)
		check(FakeRoblox.find(peer, "PlanItem2") == nil, "GOTV took two tray lines")
		press(world, peer, "ClearButton")
		check(FakeRoblox.find(peer, "PlanItem1") == nil, "Clear left items behind")
		press(world, peer, "BankButton")
		check(said(peer, "[270] DEBUG_UI bank"), "Bank sent nothing")
		noErrors(world)
	end)

	it("pivots in two choices behind the Pivot button", function()
		local world, peer = fixture("Plan")
		local view = Fixtures.payload(C, "Plan").view
		local platform = view.players[view.you].platform :: { string }
		local other = nil
		for _, issue in
			{ "Jobs", "Health", "Schools", "Environment", "Safety", "Transit", "Technology", "Farms" }
		do
			if not table.find(platform, issue) and other == nil then
				other = issue
			end
		end
		press(world, peer, "PivotButton")
		press(world, peer, `PivotDrop{platform[1]}`)
		press(world, peer, `PivotAdd{other}`)
		check(string.find(text(peer, "PlanItem1"), "Pivot", 1, true) ~= nil, "no pivot in the tray")
		check(not shown(find(peer, "PivotButton")), "Pivot is still offered with a pivot planned")
		noErrors(world)
	end)

	it("debate prep steppers keep the total", function()
		local world, peer = fixture("DebatePrep")
		local points = sum(prepValues(peer))
		check(points == C.DEBATE_PREP, `default prep totals {points}`)
		expect(prepValues(peer)):toEqual({ 2, 2, 2 })
		for _ = 1, 4 do
			press(world, peer, "PrepPlus1")
			check(sum(prepValues(peer)) == points, "plus changed the total")
		end
		expect(prepValues(peer)[1]):toBe(C.DEBATE_MAX_PER_TOPIC)
		for _ = 1, 6 do
			press(world, peer, "PrepMinus1")
			check(sum(prepValues(peer)) == points, "minus changed the total")
		end
		expect(prepValues(peer)[1]):toBe(0)
		press(world, peer, "PrepPlus3")
		check(sum(prepValues(peer)) == points, "plus on topic 3 changed the total")
		press(world, peer, "LockIn")
		check(said(peer, "[270] DEBUG_UI submit"), "Lock in sent nothing")
		noErrors(world)
	end)

	it("plays the resolve reveal and can be skipped", function()
		local world, peer = fixture("Resolve")
		check(text(peer, "StageLabel") == "Results", "stage label: " .. text(peer, "StageLabel"))
		check(text(peer, "RevealLine1") ~= "", "no event lines")
		local first = text(peer, "Caption")
		FakeRoblox.run(world, 7)
		check(text(peer, "Caption") ~= "" and text(peer, "RevealSummary") ~= "", "the reveal never finished")
		check(first ~= "", "no caption over the map")
		press(world, peer, "SkipButton")
		check(said(peer, "[270] DEBUG_UI skip"), "Skip sent nothing")
		check(
			string.find(text(peer, "SkipButton"), "Waiting", 1, true) ~= nil,
			"skip button: " .. text(peer, "SkipButton")
		)
		noErrors(world)
	end)

	it("shows the debate result topic by topic", function()
		local world, peer = fixture("Debate")
		local payload = Fixtures.payload(C, "Debate")
		local result = payload.view.debates[#payload.view.debates]
		FakeRoblox.run(world, 8)
		for t = 1, #result.topics do
			check(string.find(text(peer, `DebateTopic{t}`), "you", 1, true) ~= nil, `topic {t} not shown`)
		end
		check(
			string.find(text(peer, "RevealSummary"), "National support", 1, true) ~= nil,
			"no national summary"
		)
		check(not shown(find(peer, "SkipButton")), "debates cannot be skipped")
		noErrors(world)
	end)

	it("shows the week's event above everything else, with its effect in plain words", function()
		-- The Plan fixture is a Windfall week.
		local _, peer = mountsCleanly("Plan")
		local event = Fixtures.payload(C, "Plan").view.event
		check(event ~= nil and event.kind == "Windfall", "the Plan fixture is no longer a Windfall week")
		check(shown(find(peer, "EventBanner")), "no event banner")
		check(text(peer, "EventTitle") == (event :: any).name, "title: " .. text(peer, "EventTitle"))
		check(text(peer, "EventText") == (event :: any).text, "flavor: " .. text(peer, "EventText"))
		expect(text(peer, "EventEffect")):toBe(
			"Fundraisers in states where you trail in the public poll raise ×1.2 this week"
		)
		check(not shown(find(peer, "ChoiceRow")), "answer buttons show in a Windfall week")
		check(not shown(find(peer, "ChoiceNote")), "the Choice note shows in a Windfall week")
		check(not shown(find(peer, "EventMapNote")), "a Windfall marks no states")
		local banner, card = find(peer, "EventBanner"), find(peer, "StateCard")
		check(banner.LayoutOrder < card.LayoutOrder, "the banner is not first in the side panel")
	end)

	it("hides the banner during the resolve reveal, which carries next week's view", function()
		local _, peer = mountsCleanly("Resolve")
		local view = Fixtures.payload(C, "Resolve").view
		check(view.event ~= nil, "the Resolve fixture has no next-week event to hide")
		check(not shown(find(peer, "EventBanner")), "the banner shows next week's event early")
	end)

	for _, size in { { name = "16:9", screen = nil }, { name = "phone", screen = PHONE } } do
		it(`offers Attack, Defend and Ignore in a Choice week ({size.name})`, function()
			local world, peer = mountsCleanly("ChoiceWeek", size.screen)
			local event = Fixtures.payload(C, "ChoiceWeek").view.event :: any
			check(event.kind == "Choice", "not a Choice week")
			check(text(peer, "EventTitle") == event.name, "title: " .. text(peer, "EventTitle"))
			expect(text(peer, "EventEffect")):toBe("Choose how to respond: Attack / Defend / Ignore")
			check(shown(find(peer, "ChoiceNote")), "no tradeoff note")
			check(
				string.find(text(peer, "ChoiceNote"), "Attack beats Ignore", 1, true) ~= nil,
				"note: " .. text(peer, "ChoiceNote")
			)
			local attack, defend, ignore =
				find(peer, "ChoiceAttack"), find(peer, "ChoiceDefend"), find(peer, "ChoiceIgnore")
			for _, button in { attack, defend, ignore } do
				check(shown(button), `{button.Name} is hidden`)
				check(button.AbsoluteSize.Y >= 44 - 0.5, `{button.Name} is {button.AbsoluteSize.Y}px tall`)
				check(button.Active ~= false, `{button.Name} is disabled`)
			end
			check(text(peer, "ChoiceAttack") == "Attack", "attack label")
			-- Ignore starts selected: it alone looks different.
			check(attack.BackgroundColor3 == defend.BackgroundColor3, "attack and defend differ")
			check(ignore.BackgroundColor3 ~= defend.BackgroundColor3, "Ignore is not selected by default")

			press(world, peer, "ChoiceAttack")
			check(attack.BackgroundColor3 ~= defend.BackgroundColor3, "Attack did not become selected")
			check(ignore.BackgroundColor3 == defend.BackgroundColor3, "Ignore stayed selected")
			press(world, peer, "ChoiceDefend")
			check(defend.BackgroundColor3 ~= attack.BackgroundColor3, "Defend did not become selected")
			press(world, peer, "ChoiceAttack")

			press(world, peer, "LockIn")
			check(said(peer, "[270] DEBUG_UI submit"), "Lock in sent nothing")
			for _, button in { attack, defend, ignore } do
				check(button.Active == false, `{button.Name} is still enabled after locking`)
			end
			check(
				attack.BackgroundColor3 ~= defend.BackgroundColor3,
				"the locked answer is no longer shown selected"
			)
			check(#audit(peer) == 0, "audit after locking: " .. table.concat(audit(peer), "; "))
			noErrors(world)
		end)
	end

	-- Plays a practice match with the debug UI's Auto button until `done()` holds,
	-- checking it before each automatic move so the stage asked for is still open.
	local function walk(rig: Support.Rig, peer: FakeRoblox.Peer, done: () -> boolean, limit: number): boolean
		local waited = 0
		while waited < limit do
			Support.run(rig, 0.5)
			waited += 0.5
			if done() then
				return true
			end
			if string.find(Support.screen(peer).status, "your move", 1, true) then
				Support.press(rig, peer, "Auto")
				waited += 0.2
			end
		end
		return false
	end

	local function startPractice(seed: number): (Support.Rig, FakeRoblox.Peer)
		local rig = Support.new(process.cwd, seed)
		local peer = Support.join(rig, "Player1")
		Support.press(rig, peer, "Practice")
		Support.run(rig, 1)
		return rig, peer
	end

	local function definition(name: string): Events.Definition
		for _, event in Events.deck do
			if event.name == name then
				return event
			end
		end
		error(`no event named {name}`)
	end

	it("sends the Choice answer with Lock in and shows it in the reveal and the week card", function()
		local rig, peer = startPractice(5)
		local choosing = function()
			local button = FakeRoblox.find(peer, "ChoiceAttack")
			return button ~= nil and shown(button) and button.Active ~= false
		end
		check(walk(rig, peer, choosing, 900), "no Choice week came up in a whole match")
		local event = definition(text(peer, "EventTitle"))
		check(event.kind == "Choice", `{event.name} is not a Choice event`)
		Support.press(rig, peer, "ChoiceAttack")
		Support.press(rig, peer, "LockIn")
		check(find(peer, "ChoiceAttack").Active == false, "the answers are still open after Lock in")
		check(
			Support.runUntil(rig, function()
				return shown(find(peer, "RevealPanel"))
			end, 120),
			"the resolve reveal never started"
		)
		check(
			Support.runUntil(rig, function()
				return text(peer, "RevealSummary") ~= ""
			end, 120),
			"the resolve reveal never finished"
		)
		local lines = {}
		for k = 1, 8 do
			table.insert(lines, text(peer, `RevealLine{k}`))
		end
		local revealed = false
		for _, line in lines do
			if string.find(line, event.name .. ": You attacked (", 1, true) then
				revealed = true
			end
		end
		check(revealed, "the reveal never captioned your answer: " .. table.concat(lines, " | "))
		local feedLine = text(peer, "FeedEvent")
		check(shown(find(peer, "FeedEvent")), "the week card shows no event")
		check(
			string.find(feedLine, `Last week's event: {event.name}. You attacked, they `, 1, true) ~= nil,
			"week card: " .. feedLine
		)
		check(string.find(feedLine, "national points", 1, true) ~= nil, "week card: " .. feedLine)
		noErrors(rig.world)
	end)

	it("stars the states a Spotlight or Regional event singles out on the map", function()
		local rig, peer = startPractice(5)
		local singled = function()
			local kind = FakeRoblox.find(peer, "EventKind")
			local planning = FakeRoblox.find(peer, "LockIn")
			return kind ~= nil
				and shown(kind)
				and planning ~= nil
				and shown(planning)
				and (
					string.find(text(peer, "EventKind"), "Spotlight", 1, true) ~= nil
					or string.find(text(peer, "EventKind"), "Regional", 1, true) ~= nil
				)
		end
		check(walk(rig, peer, singled, 900), "no Spotlight or Regional week came up")
		local event = definition(text(peer, "EventTitle"))
		local view: any = { week = 0, id = event.id, kind = event.kind, name = event.name, text = event.text }
		view.issue, view.region = event.issue, event.region
		local expected = PlanDraft.eventStates(view)
		expect(text(peer, "EventEffect")):toBe(PlanDraft.eventEffect(C, view))
		check(
			string.find(text(peer, "EventEffect"), "×1.", 1, true) ~= nil,
			"no multiplier in the effect line"
		)
		check(shown(find(peer, "EventMapNote")), "no note on what the * means")
		check(
			text(peer, "EventMapNote") == PlanDraft.eventMapNote(view),
			"map note: " .. text(peer, "EventMapNote")
		)
		local starred: { [string]: boolean } = {}
		for _, inst in find(peer, "NodeMap"):GetDescendants() do
			if inst.Name == "Badge" and inst.Visible ~= false and string.find(inst.Text, "*", 1, true) then
				local label = inst.Parent:FindFirstChild("Label")
				starred[tostring(label.Text)] = true
			end
		end
		for id in expected do
			check(starred[id] == true, `{id} should be starred under {event.name}`)
		end
		for id in starred do
			check(expected[id] == true, `{id} is starred but {event.name} does not single it out`)
		end
		noErrors(rig.world)
	end)

	it("follows a whole autoplayed practice match", function()
		local rig = Support.new(process.cwd, 5)
		local peer = Support.join(rig, "Player1")
		Support.press(rig, peer, "Practice")
		Support.run(rig, 1)
		Support.press(rig, peer, "Autoplay")
		local stages: { [string]: boolean } = {}
		local countdowns: { [string]: boolean } = {}
		local done = Support.runUntil(rig, function()
			local stage = FakeRoblox.find(peer, "StageLabel")
			if stage then
				stages[tostring(stage.Text)] = true
				countdowns[tostring(FakeRoblox.find(peer, "Countdown").Text)] = true
			end
			return Support.said(rig, peer, "match over")
		end, 600)
		check(done, "the match never finished")
		check(Support.said(rig, peer, "match over: Election"), "the match did not end with an election")
		noErrors(rig.world)
		check(said(peer, "UI audit Campaign: 0 problem(s)"), "the campaign screen was never audited clean")
		check(stages["Results"] == true, "never showed a resolve reveal")
		check(stages["Debate"] == true, "never showed a debate")
		check(stages["Locked in"] == true or stages["Plan your week"] == true, "never showed a plan stage")
		local distinct = 0
		for _ in countdowns do
			distinct += 1
		end
		check(distinct > 10, "the countdown never ticked")
	end)
end)
