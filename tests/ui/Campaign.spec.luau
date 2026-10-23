--!strict
-- The campaign screen (src/client/Screens/Campaign.luau) on the fake engine:
-- every campaign fixture mounts cleanly in 16:9 and phone portrait, the plan can
-- be built and locked in by pressing buttons, the reveals play, and a whole
-- autoplayed practice match runs through the screen. The Decision screen (debate
-- focus and stances, D-044) has its own checks here and in tests/ui/Decision.spec.
-- Also the v0.3.1 bug-hunt cases for this screen: the state list and its
-- ordering, auto-submit, retries after a rejection, the forfeit countdown, and
-- readable rejection codes (Net).

local process = require("@lune/process")

local Config = require("@sim/Config")
local Events = require("@sim/Events")
local Explain = require("@ui/Explain")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Plan = require("@sim/Plan")
local PlanDraft = require("@ui/PlanDraft")
local Rig = require("./Rig")
local Session = require("@net/Session")
local StateData = require("@sim/StateData")
local StateOrder = require("@ui/StateOrder")
local Support = require("../e2e/Support")
local Swing = require("@ui/Swing")
local Test = require("@testlib/Test")
local Words = require("@ui/Words/Campaign")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local PHONE = { x = 390, y = 844 }
local MOMENTS = { "Plan", "ChoiceWeek", "Resolve", "Debate" }

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
	while node ~= nil and node.Name ~= "Campaign" and node.Name ~= "Decision" do
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
local function audit(peer: FakeRoblox.Peer, screen: string?): { string }
	local problems = {}
	local holder = find(peer, screen or "Campaign")
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
	screen: { x: number, y: number }?,
	name: string?
): (FakeRoblox.World, FakeRoblox.Peer)
	local world, peer = fixture(moment, screen)
	FakeRoblox.run(world, 1)
	noErrors(world)
	local holder = name or "Campaign"
	check(said(peer, `screen {holder}`), `fixture {moment} did not route to {holder}`)
	check(said(peer, `UI audit {holder}: 0 problem(s)`), `no clean UI audit for {moment}`)
	local problems = audit(peer, holder)
	check(#problems == 0, `{moment}: ` .. table.concat(problems, "; "))
	return world, peer
end

describe("Campaign screen", function()
	for _, moment in MOMENTS do
		it(`mounts the {moment} fixture with no errors or audit problems`, function()
			local _, peer = mountsCleanly(moment)
			check(shown(find(peer, "TopBar")), "no top bar")
			check(string.find(text(peer, "WeekLabel"), "of 12", 1, true) ~= nil, "no week label")
			if moment == "Plan" or moment == "ChoiceWeek" then
				check(shown(find(peer, "LockIn")), "Lock in is hidden while planning")
				-- The week starts on the map: no card until a state is tapped (UI-STYLE §4.5).
				check(not shown(find(peer, "StateCard")), "the state card shows before a state is tapped")
				expect(text(peer, "NowText")):toBe("Tap a state on the map")
				check(
					text(peer, "StageLabel") == "Plan your week",
					"stage label: " .. text(peer, "StageLabel")
				)
			else
				check(shown(find(peer, "RevealPanel")), "the reveal panel is hidden")
				check(FakeRoblox.find(peer, "LockIn") == nil, "Lock in shows during a reveal")
			end
			-- The debate focus and the stance have their own screen (D-044): never here.
			check(FakeRoblox.find(peer, "FocusPanel") == nil, "a focus panel on the plan screen")
			local chip = FakeRoblox.find(peer, "ChoiceA")
			check(chip == nil or not shown(chip), "stance chips on the plan screen")
		end)
	end

	it("mounts in phone portrait with the map on top", function()
		for _, moment in MOMENTS do
			local _, peer = mountsCleanly(moment, PHONE)
			local area = find(peer, "MapArea")
			check(area.Size.X.Scale == 1, `{moment}: the map is not full width on a phone`)
			check(shown(find(peer, "Score")), `{moment}: the phone header has no score row`)
		end
	end)

	it("builds a plan from map taps and card buttons, then locks it in", function()
		local world, peer = fixture("Plan")
		local view = Fixtures.payload(C, "Plan").view
		local home = view.players[view.you].location :: string

		press(world, peer, home)
		check(shown(find(peer, "StateCard")), "the state card did not open")
		check(string.find(text(peer, "CardTitle"), "votes", 1, true) ~= nil, "the state card shows no state")
		local before = text(peer, "BarStatus")
		expect(before):toBe("Nothing planned yet")
		-- An empty plan still locks in with one tap: the button says it skips the week.
		expect(text(peer, "LockIn")):toBe("Skip this week")

		-- Change the rally message (one tap, opening "More" if Health is not a
		-- chip here), then rally, fundraise and run an ad.
		if not shown(find(peer, "IssueHealth")) then
			press(world, peer, "MessageMore")
		end
		press(world, peer, "IssueHealth")
		check(
			find(peer, "IssueHealth"):GetAttribute("Selected") == true,
			"the picked message is not selected"
		)
		press(world, peer, "Rally")
		press(world, peer, "Fundraise")
		press(world, peer, "Ad")
		check(
			string.find(text(peer, "PlanItem1"), "Rally", 1, true) ~= nil,
			"item 1: " .. text(peer, "PlanItem1")
		)
		check(string.find(text(peer, "PlanItem1"), "Health", 1, true) ~= nil, "the picked issue was not used")
		check(
			string.find(text(peer, "PlanItem2"), "Fundraise", 1, true) ~= nil,
			"item 2: " .. text(peer, "PlanItem2")
		)
		check(
			string.find(text(peer, "PlanItem3"), "Ad", 1, true) ~= nil,
			"item 3: " .. text(peer, "PlanItem3")
		)
		local after = text(peer, "BarStatus")
		check(after ~= before, "the plan status did not change")
		check(string.find(after, "Plan: Rally", 1, true) ~= nil, "plan status: " .. after)
		expect(text(peer, "LockIn")):toBe("Lock in")
		check(text(peer, "APLabel") == "1 action left", "header actions: " .. text(peer, "APLabel"))
		check(string.find(text(peer, "PlanTitle"), "2 of 3 actions", 1, true) ~= nil, text(peer, "PlanTitle"))

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
		expect(text(peer, "BarStatus")):toBe("Locked in · waiting for opponent")
		expect(text(peer, "LockIn")):toBe("Locked in")
		check(find(peer, "LockIn").Active == false, "Lock in is still enabled after locking")
		check(find(peer, "Fundraise").Active == false, "the card is still editable after locking")
		check(find(peer, "RemoveItem1").Active == false, "the tray is still editable after locking")
		noErrors(world)
	end)

	it("adds GOTV units to one tray line and clears the plan", function()
		local world, peer = fixture("Plan")
		-- Two units cost $5 at GOTV_COST 2.5 (D-049): more than the week-3 fixture holds.
		local payload = Rig.deepCopy(Fixtures.payload(C, "Plan"))
		payload.view.players[payload.view.you].cash = 10
		Rig.push(world, peer, payload)
		press(world, peer, "OH")
		press(world, peer, "Gotv")
		press(world, peer, "Gotv")
		check(
			string.find(text(peer, "PlanItem1"), "+2", 1, true) ~= nil,
			"gotv line: " .. text(peer, "PlanItem1")
		)
		check(FakeRoblox.find(peer, "PlanItem2") == nil, "GOTV took two tray lines")
		press(world, peer, "ClearButton")
		press(world, peer, "ClearButton")
		check(FakeRoblox.find(peer, "PlanItem1") == nil, "Clear left items behind")
		press(world, peer, "BankButton")
		check(said(peer, "[270] DEBUG_UI bank"), "Bank sent nothing")
		noErrors(world)
	end)

	it("says on the state card what a poll shows of their ground game (D-049)", function()
		local world, peer = fixture("Plan")
		press(world, peer, "OH")
		check(
			string.find(text(peer, "CardScout"), "hidden. A poll shows it", 1, true) ~= nil,
			"scout hint: " .. text(peer, "CardScout")
		)
		noErrors(world)
		-- After a poll of OH that saw three of their units, the card says so.
		local payload = Rig.deepCopy(Fixtures.payload(C, "Plan"))
		local view = payload.view
		local seen = table.create(#view.players, 0)
		seen[if view.you == 1 then 2 else 1] = 3
		view.scouted = { { state = "OH", week = view.week - 1, gotv = seen } }
		local world2, peer2 = fixture("Plan")
		Rig.push(world2, peer2, payload)
		press(world2, peer2, "OH")
		expect(text(peer2, "CardScout")):toBe(Explain.scoutNote(Config.defaults, view, "OH"))
		check(string.find(text(peer2, "CardScout"), "3 units", 1, true) ~= nil, text(peer2, "CardScout"))
		noErrors(world2)
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
		press(world, peer, view.players[view.you].location :: string)
		press(world, peer, "MoreActions")
		check(shown(find(peer, "PivotButton")), "More actions does not show Pivot")
		press(world, peer, "PivotButton")
		press(world, peer, `PivotDrop{platform[1]}`)
		press(world, peer, `PivotAdd{other}`)
		check(string.find(text(peer, "PlanItem1"), "Pivot", 1, true) ~= nil, "no pivot in the tray")
		check(find(peer, "PivotButton").Active == false, "Pivot is still offered with a pivot planned")
		check(shown(find(peer, "ActionGrid")), "the action grid did not come back after the pivot")
		noErrors(world)
	end)

	it("says the stance you took in one line in a Choice week's plan (D-044)", function()
		local world, peer = mountsCleanly("ChoiceWeek")
		local view = Fixtures.payload(C, "ChoiceWeek").view
		check(view.stance ~= nil, "the fixture took no stance")
		check(shown(find(peer, "ChoiceTaken")), "no stance line on the plan screen")
		check(
			string.find(text(peer, "ChoiceTaken"), `Your stance: {view.stance}`, 1, true) ~= nil,
			"stance line: " .. text(peer, "ChoiceTaken")
		)
		check(not shown(find(peer, "ChoicePayHead")), "the per-state stance lists crowd the plan screen")
		noErrors(world)
	end)

	it("plays the resolve reveal and can be skipped from the action bar", function()
		local world, peer = fixture("Resolve")
		check(text(peer, "StageLabel") == "Results", "stage label: " .. text(peer, "StageLabel"))
		check(text(peer, "RevealLine1") ~= "", "no event lines")
		-- The reveal's latest line is the header's now line.
		local first = text(peer, "NowText")
		FakeRoblox.run(world, 7)
		check(text(peer, "NowText") ~= "" and text(peer, "RevealSummary") ~= "", "the reveal never finished")
		check(first ~= "", "no now line during the reveal")
		press(world, peer, "SkipButton")
		check(said(peer, "[270] DEBUG_UI skip"), "Skip sent nothing")
		check(
			string.find(text(peer, "SkipButton"), "Waiting", 1, true) ~= nil,
			"skip button: " .. text(peer, "SkipButton")
		)
		check(find(peer, "SkipButton").Active == false, "Skip is still enabled after the tap")
		check(find(peer, "SkipButton"):GetAttribute("PrimaryAction") == true, "Skip is not the bar's primary")
		noErrors(world)
	end)

	it("shows the debate result topic by topic", function()
		local world, peer = fixture("Debate")
		local payload = Fixtures.payload(C, "Debate")
		local result = payload.view.debates[#payload.view.debates]
		FakeRoblox.run(world, 8)
		for t = 1, #result.topics do
			-- The scoreboard row: the topic, "you – them", a verdict (WP-C, UI-STYLE §4.7).
			check(text(peer, `DebateTopic{t}`) ~= "", `topic {t} not shown`)
			check(
				string.find(text(peer, `DebateScore{t}`), " – ", 1, true) ~= nil,
				`topic {t} has no score`
			)
			check(text(peer, `DebateVerdict{t}`) ~= "", `topic {t} has no verdict`)
		end
		check(
			string.find(text(peer, "RevealSummary"), "Every state also got", 1, true) ~= nil,
			"no summary of the points every state got"
		)
		check(not shown(find(peer, "SkipButton")), "debates cannot be skipped")
		noErrors(world)
	end)

	it("shows the week's event under the plan, with its effect in plain words", function()
		-- The Plan fixture is a Windfall week.
		local _, peer = mountsCleanly("Plan")
		local event = Fixtures.payload(C, "Plan").view.event
		check(event ~= nil and event.kind == "Windfall", "the Plan fixture is no longer a Windfall week")
		local banner = find(peer, "EventCard")
		check(shown(banner), "no event card")
		expect(banner:GetAttribute("EventName")):toBe((event :: any).name)
		check(
			string.find(text(peer, "EventToggle"), (event :: any).name, 1, true) ~= nil,
			"title: " .. text(peer, "EventToggle")
		)
		expect(text(peer, "EventText")):toBe((event :: any).text)
		-- Collapsed in a Windfall week, but the effect line still shows (two lines).
		check(not shown(find(peer, "EventText")), "the Windfall card is not collapsed")
		check(shown(find(peer, "EventEffect")), "the effect line is hidden on the collapsed card")
		expect(text(peer, "EventEffect")):toBe(
			"Fundraisers in states where you trail in the public poll raise ×1.2 this week"
		)
		check(not shown(find(peer, "ChoiceRow")), "answer buttons show in a Windfall week")
		check(not shown(find(peer, "ChoiceNote")), "the Choice note shows in a Windfall week")
		check(not shown(find(peer, "EventMapNote")), "a Windfall marks no states")
		local card, plan = find(peer, "StateCard"), find(peer, "PlanList")
		check(card.LayoutOrder < plan.LayoutOrder, "the state card is not above the plan")
		check(plan.LayoutOrder < banner.LayoutOrder, "the plan is not above the event card")
	end)

	it("hides the banner during the resolve reveal, which carries next week's view", function()
		local _, peer = mountsCleanly("Resolve")
		local view = Fixtures.payload(C, "Resolve").view
		check(view.event ~= nil, "the Resolve fixture has no next-week event to hide")
		check(not shown(find(peer, "EventCard")), "the event card shows next week's event early")
	end)

	-- Strand's perk (D-035): View.nextEvent is next week's event, for that player only.
	it("shows next week's event to a candidate who previews it", function()
		local world, peer = mountsCleanly("Plan")
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		local upcoming = Rig.deepCopy(payload.view.event or Fixtures.payload(C, "ChoiceWeek").view.event)
		upcoming.week = payload.view.week + 1
		payload.view.nextEvent = upcoming
		Rig.push(world, peer, payload)
		check(shown(find(peer, "NextEvent")), "no next-week line for a previewing candidate")
		check(
			string.find(text(peer, "NextEvent"), upcoming.name, 1, true) ~= nil,
			"next-week line: " .. text(peer, "NextEvent")
		)
		-- Also when there is no event this week (week 1 sees week 2's).
		payload.view.event = nil
		Rig.push(world, peer, payload)
		check(shown(find(peer, "EventCard")), "the card hides when only next week's event is known")
		check(shown(find(peer, "NextEvent")), "no next-week line without an event this week")
		payload.view.nextEvent = nil
		Rig.push(world, peer, payload)
		check(not shown(find(peer, "EventCard")), "an empty event card shows")
		Rig.noErrors(world)
	end)

	for _, size in { { name = "16:9", screen = nil }, { name = "phone", screen = PHONE } } do
		it(`offers stances A, B and C on the Decision screen in a Choice week ({size.name})`, function()
			local world, peer = mountsCleanly("Stance", size.screen, "Decision")
			local event = Fixtures.payload(C, "Stance").view.event :: any
			check(event.kind == "Choice", "not a Choice week")
			expect(find(peer, "EventCard"):GetAttribute("EventName")):toBe(event.name)
			check(find(peer, "EventToggle"):GetAttribute("Expanded") == true, "the Choice card is collapsed")
			expect(text(peer, "EventEffect")):toBe(PlanDraft.eventEffect(C, event))
			-- The header names the event; the card has no title row of its own.
			check(string.find(text(peer, "WeekLabel"), event.name, 1, true) ~= nil, text(peer, "WeekLabel"))
			check(not shown(find(peer, "EventToggle")), "the stance card still has a title row")
			check(not shown(find(peer, "ChoiceNote")), "the tradeoff note is not behind Why?")
			press(world, peer, "WhyToggle")
			check(shown(find(peer, "ChoiceNote")), "no tradeoff note")
			check(
				string.find(text(peer, "ChoiceNote"), "top issue", 1, true) ~= nil,
				"note: " .. text(peer, "ChoiceNote")
			)
			local attack, defend, ignore = find(peer, "ChoiceA"), find(peer, "ChoiceB"), find(peer, "ChoiceC")
			for _, button in { attack, defend, ignore } do
				check(shown(button), `{button.Name} is hidden`)
				check(button.AbsoluteSize.Y >= 44 - 0.5, `{button.Name} is {button.AbsoluteSize.Y}px tall`)
				check(button.Active ~= false, `{button.Name} is disabled`)
			end
			local stanceA = event.stances[1]
			expect(text(peer, "ChoiceA")):toBe(`A · {stanceA.name}`)
			local view = Fixtures.payload(C, "Stance").view
			expect(text(peer, "ChoiceAEffect")):toBe(Words.stanceEffect(Swing.stance(C, view, "A")))
			-- The hedge (C) starts selected: it alone looks different.
			check(attack.BackgroundColor3 == defend.BackgroundColor3, "attack and defend differ")
			check(ignore.BackgroundColor3 ~= defend.BackgroundColor3, "Ignore is not selected by default")
			check(ignore:GetAttribute("Selected") == true, "Ignore is not selected")
			check(ignore.VariantStroke.Enabled == true, "Ignore has no selection outline")

			press(world, peer, "ChoiceA")
			check(attack.BackgroundColor3 ~= defend.BackgroundColor3, "A did not become selected")
			check(ignore.BackgroundColor3 == defend.BackgroundColor3, "C stayed selected")
			press(world, peer, "ChoiceB")
			check(defend.BackgroundColor3 ~= attack.BackgroundColor3, "B did not become selected")
			press(world, peer, "ChoiceA")

			press(world, peer, "LockIn")
			check(said(peer, "[270] DEBUG_UI submit"), "Lock in sent nothing")
			for _, button in { attack, defend, ignore } do
				check(button.Active == false, `{button.Name} is still enabled after locking`)
			end
			check(
				attack.BackgroundColor3 ~= defend.BackgroundColor3,
				"the locked answer is no longer shown selected"
			)
			check(
				#audit(peer, "Decision") == 0,
				"audit after locking: " .. table.concat(audit(peer, "Decision"), "; ")
			)
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

	it("sends the Choice stance with Lock in and shows it in the reveal and the week card", function()
		local rig, peer = startPractice(5)
		local choosing = function()
			local button = FakeRoblox.find(peer, "ChoiceA")
			return button ~= nil and shown(button) and button.Active ~= false
		end
		check(walk(rig, peer, choosing, 900), "no Choice week came up in a whole match")
		local event = definition(tostring(find(peer, "EventCard"):GetAttribute("EventName")))
		check(event.kind == "Choice", `{event.name} is not a Choice event`)
		Support.press(rig, peer, "ChoiceA")
		Support.press(rig, peer, "LockIn")
		local chip = FakeRoblox.find(peer, "ChoiceA")
		check(
			chip == nil or not shown(chip) or chip.Active == false,
			"the stances are still open after Lock in"
		)
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
		-- "Your week" lists the stance as "{event}: stance A · …" (WP-C, UI-STYLE §4.7).
		local lines = {}
		for k = 1, 6 do
			table.insert(lines, text(peer, `RevealLine{k}`))
		end
		local revealed = false
		for _, line in lines do
			if string.find(line, event.name .. ": stance A · ", 1, true) then
				revealed = true
			end
		end
		check(revealed, "the reveal never captioned your answer: " .. table.concat(lines, " | "))
		local feedLine = text(peer, "FeedEvent")
		check(not shown(find(peer, "FeedEvent")), "the News card is not collapsed by default")
		Support.press(rig, peer, "WeekToggle")
		check(shown(find(peer, "FeedEvent")), "the week card shows no event")
		check(
			string.find(feedLine, `Last week's event: {event.name}.\nYou took A · `, 1, true) ~= nil,
			"week card: " .. feedLine
		)
		check(string.find(feedLine, "They took ", 1, true) ~= nil, "week card: " .. feedLine)
		check(string.find(feedLine, "On the polls you both saw", 1, true) ~= nil, "week card: " .. feedLine)
		noErrors(rig.world)
	end)

	it("stars the states a Spotlight or Regional event singles out on the map", function()
		local rig, peer = startPractice(5)
		local singled = function()
			local card = FakeRoblox.find(peer, "EventCard")
			local planning = FakeRoblox.find(peer, "LockIn")
			local kind = if card then card:GetAttribute("EventKind") else nil
			return card ~= nil
				and shown(card)
				and planning ~= nil
				and shown(planning)
				and (kind == "Spotlight" or kind == "Regional")
		end
		check(walk(rig, peer, singled, 900), "no Spotlight or Regional week came up")
		local event = definition(tostring(find(peer, "EventCard"):GetAttribute("EventName")))
		check(shown(find(peer, "EventText")), "the Spotlight/Regional card is not expanded")
		local view: any = { week = 0, id = event.id, kind = event.kind, name = event.name, text = event.text }
		view.issue, view.region = event.issue, event.region
		local expected = PlanDraft.eventStates(view, Rig.payloadOf(rig.world, peer).view.issueMap)
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
		for _, tag in find(peer, "NodeMap"):FindFirstChild("Tags"):GetChildren() do
			if tag.Visible ~= false and string.find(tag.Text, "*", 1, true) then
				starred[tag.Name] = true
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

-- ------------------------------------------------------------------ v0.3.1 bug hunt
-- (moved here from ClientFixes.spec when it was split per screen)

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
		local sv = Rig.deepCopy(view.states[1])
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
		local sv = Rig.deepCopy(view.states[1])
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
		local world, peer = Rig.fixture("Plan", Rig.PHONE)
		local toggle = Rig.need(peer, "Campaign", "StatesToggle")
		check(Rig.shown(toggle, "Campaign"), "no states button on the campaign screen")
		check(not Rig.shown(Rig.need(peer, "Campaign", "StatePicker"), "Campaign"), "the list starts open")
		Rig.tap(world, peer, "Campaign", "StatesToggle")
		check(Rig.shown(Rig.need(peer, "Campaign", "StatePicker"), "Campaign"), "the list did not open")
		for _, record in StateData.list do
			Rig.need(peer, "Campaign", `Row_{record.id}`)
		end
		local problems = Rig.audit(peer, "Campaign")
		check(#problems == 0, "open list: " .. table.concat(problems, "; "))
		Rig.noErrors(world)
	end)

	it("selects the states the phone map hides, in two taps", function()
		local world, peer = Rig.fixture("Plan", Rig.PHONE)
		for _, id in { "MA", "DE", "DC", "CT", "WV" } do
			Rig.tap(world, peer, "Campaign", "StatesToggle")
			Rig.tap(world, peer, "Campaign", `Row_{id}`)
			local title = Rig.textOf(peer, "Campaign", "CardTitle")
			check(Rig.contains(title, StateData.byId[id].name), `{id}: the card shows "{title}"`)
			check(not Rig.shown(Rig.need(peer, "Campaign", "StatePicker"), "Campaign"), "the list stays open")
		end
		Rig.noErrors(world)
	end)

	it("works on a wide screen and the state's actions follow the pick", function()
		local world, peer = Rig.fixture("Plan", nil)
		Rig.tap(world, peer, "Campaign", "StatesToggle")
		Rig.tap(world, peer, "Campaign", "Row_WY")
		check(Rig.contains(Rig.textOf(peer, "Campaign", "CardTitle"), "Wyoming"), "Wyoming was not selected")
		check(Rig.contains(Rig.textOf(peer, "Campaign", "FundraiseLabel"), "Fundraise"), "no action buttons")
		Rig.tap(world, peer, "Campaign", "Fundraise")
		check(
			Rig.contains(Rig.textOf(peer, "Campaign", "PlanItem1"), "Wyoming"),
			Rig.textOf(peer, "Campaign", "PlanItem1")
		)
		Rig.noErrors(world)
	end)

	it("shows each row's poll and your momentum, and re-sorts", function()
		local world, peer = Rig.fixture("Plan", nil)
		Rig.tap(world, peer, "Campaign", "StatesToggle")
		local row = Rig.need(peer, "Campaign", "Row_OH")
		local texts = {}
		for _, inst in row:GetDescendants() do
			if inst.ClassName == "TextLabel" then
				table.insert(texts, tostring(inst.Text))
			end
		end
		local all = table.concat(texts, " | ")
		check(Rig.contains(all, "OH") and Rig.contains(all, "votes"), `row text: {all}`)
		check(Rig.contains(all, "Mom"), `no momentum in the row: {all}`)
		check(
			Rig.need(peer, "Campaign", "Sort_Closest"):GetAttribute("Selected") == true,
			"not sorted closest"
		)
		Rig.tap(world, peer, "Campaign", "Sort_Biggest")
		check(
			Rig.need(peer, "Campaign", "Sort_Biggest"):GetAttribute("Selected") == true,
			"the sort chip did not change"
		)
		local biggest = StateData.list[1]
		for _, record in StateData.list do
			if record.ev > biggest.ev or (record.ev == biggest.ev and record.id < biggest.id) then
				biggest = record
			end
		end
		check(
			Rig.need(peer, "Campaign", `Row_{biggest.id}`).LayoutOrder == 1,
			`{biggest.id} is not first when sorted by size`
		)
		Rig.tap(world, peer, "Campaign", "Sort_Name")
		check(Rig.need(peer, "Campaign", "Row_AL").LayoutOrder == 1, "Alabama is not first by name")
		Rig.noErrors(world)
	end)
end)

describe("Campaign auto-submit before the timer ends", function()
	it("Campaign locks the plan that was built", function()
		local world, peer = Rig.practice(3)
		Rig.toPlanInput(world, peer)
		local view = Rig.payloadOf(world, peer).view
		local calls = Rig.spySubmits(world, peer)
		Rig.tap(world, peer, "Campaign", view.players[1].location, 0.05)
		Rig.tap(world, peer, "Campaign", "Rally", 0.05)
		Rig.tap(world, peer, "Campaign", "Ad", 0.05)
		Rig.waitFor(world, function()
			return Rig.payloadOf(world, peer).reveal == "Resolve"
		end, 200, "the resolve reveal")
		FakeRoblox.run(world, 1)
		expect(#calls):toBe(1)
		-- "Your week" merges repeats into one line ("Rally in Ohio ×2 · …").
		local mentions = 0
		for k = 1, 6 do
			local line = Rig.findIn(peer, "Campaign", `RevealLine{k}`)
			if line and Rig.contains(tostring(line.Text), "Rally in ") then
				mentions += 1
			end
		end
		check(mentions == 1, `the reveal shows {mentions} lines about your rally`)
		Rig.noErrors(world)
	end)

	it("Campaign never double-submits after a manual lock", function()
		local world, peer = Rig.practice(3)
		Rig.toPlanInput(world, peer)
		local calls = Rig.spySubmits(world, peer)
		Rig.tap(world, peer, "Campaign", "LockIn")
		Rig.waitFor(world, function()
			return Rig.payloadOf(world, peer).reveal == "Resolve"
		end, 200, "the resolve reveal")
		expect(#calls):toBe(1)
		Rig.noErrors(world)
	end)

	it("an offline Campaign fixture submits once, half a second early", function()
		local world, peer = Rig.fixture("Plan", nil)
		local left = Rig.payloadOf(world, peer).deadline - world.clock
		FakeRoblox.run(world, left - 2)
		expect(Rig.count(peer, "DEBUG_UI submit")):toBe(0)
		FakeRoblox.run(world, 1.9)
		expect(Rig.count(peer, "DEBUG_UI submit")):toBe(1)
		FakeRoblox.run(world, 10)
		expect(Rig.count(peer, "DEBUG_UI submit")):toBe(1)
		Rig.noErrors(world)
	end)

	it("Campaign submits nothing when the draft has a problem", function()
		local world, peer = Rig.fixture("Plan", nil)
		local view = Rig.payloadOf(world, peer).view
		Rig.tap(world, peer, "Campaign", view.players[view.you].location, 0.05)
		Rig.tap(world, peer, "Campaign", "Ad", 0.05)
		-- The money is gone by the time the timer ends: the plan no longer fits.
		local broke = Rig.deepCopy(Rig.payloadOf(world, peer))
		broke.view.players[broke.view.you].cash = 0
		Rig.push(world, peer, broke)
		FakeRoblox.run(world, broke.deadline - world.clock + 5)
		expect(Rig.count(peer, "DEBUG_UI submit")):toBe(0)
		Rig.noErrors(world)
	end)
end)

describe("Campaign rejections with a full message log", function()
	it("lets Campaign retry a rejected plan even with a full log", function()
		local world, peer = Rig.practice(3)
		local store = Rig.storeOf(world, peer)
		Rig.toPlanInput(world, peer)
		for k = 1, 25 do
			store.say(`filler {k}`)
		end
		Rig.sabotageSubmits(world, peer, { actions = { { kind = "Zzz" } } })
		Rig.tap(world, peer, "Campaign", "LockIn", 1)
		check(Rig.enabled(peer, "Campaign", "LockIn"), "Lock in stays disabled after a rejection")
		check(
			not Rig.contains(Rig.textOf(peer, "Campaign", "StageLabel"), "Locked"),
			"the stage still says Locked in"
		)
		Rig.noErrors(world)
	end)

	it("explains a NotEnoughMoney rejection with cost and cash (playtest 1, bug 2)", function()
		local world, peer = Rig.practice(3)
		Rig.toPlanInput(world, peer)
		local broke = {}
		for _ = 1, 12 do
			table.insert(broke, { kind = "RegionPoll", region = "Pacific" })
		end
		Rig.sabotageSubmits(world, peer, { actions = broke })
		Rig.tap(world, peer, "Campaign", "LockIn", 1)
		check(Rig.enabled(peer, "Campaign", "LockIn"), "Lock in stays disabled after a rejection")
		local status = Rig.textOf(peer, "Campaign", "BarStatus")
		check(Rig.contains(status, "Plan costs $"), status)
		check(Rig.contains(status, ", you have $"), status)
		Rig.noErrors(world)
	end)
end)

describe("Campaign with a disconnected opponent", function()
	it("drops the auto-submit countdown once the grace period is over", function()
		local world, peer = Rig.fixture("Plan", nil)
		local base = Rig.payloadOf(world, peer)
		local them = 3 - base.you
		local away = Rig.deepCopy(base)
		away.seats[them].connected = false
		away.seats[them].graceUntil = world.clock + 5
		Rig.push(world, peer, away)
		local notice = Rig.need(peer, "Campaign", "OpponentNotice")
		check(notice.Visible ~= false, "no disconnected notice")
		check(Rig.contains(tostring(notice.Text), "auto-submit in"), tostring(notice.Text))
		FakeRoblox.run(world, 6)
		expect(tostring(notice.Text)):toBe("Opponent disconnected")
		Rig.noErrors(world)
	end)
end)

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
		"CandidateTaken",
		"AlreadyClaimed",
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
		local world, peer = Rig.practice(3)
		local net = Rig.netOf(world, peer)
		local missing = {}
		for _, code in CODES do
			local reason = net.reasonText(code)
			if string.sub(reason, 1, 9) == "Rejected:" then
				table.insert(missing, code)
			end
		end
		check(#missing == 0, "no text for: " .. table.concat(missing, ", "))
	end)

	it("falls back to the code itself for one it does not know", function()
		local world, peer = Rig.practice(3)
		expect(Rig.netOf(world, peer).reasonText("Brand New")):toBe("Rejected: Brand New")
		expect(Rig.netOf(world, peer).reasonText(nil)):toBe("Rejected: unknown")
	end)

	it("labels the fundraising pool as its size", function()
		local world, peer = Rig.fixture("Plan", nil)
		local view = Rig.payloadOf(world, peer).view
		Rig.tap(world, peer, "Campaign", view.players[view.you].location)
		local ground = Rig.textOf(peer, "Campaign", "CardGround")
		check(Rig.contains(ground, "pool size $"), ground)
		check(not Rig.contains(ground, "fundraising pool"), ground)
	end)
end)
