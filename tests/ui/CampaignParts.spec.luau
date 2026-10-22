--!strict
-- The redesigned campaign screen (UI overhaul WP3, src/client/Screens/
-- CampaignParts) on the fake engine: Lock in pinned in the action bar on both
-- screen sizes, debate prep above the plan (B2), no event card during the
-- debate (B1), the Region poll button (B3), one-tap message chips, two-tap
-- Clear, the read-only state card during the resolve reveal, the header, and
-- the strict UI audit on every campaign moment.

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Issues = require("@sim/Issues")
local PlanDraft = require("@ui/PlanDraft")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local WIDE = { x = 1280, y = 720 }
local SIZES = { { name = "16:9", screen = WIDE }, { name = "phone", screen = Rig.PHONE } }
local MOMENTS = { "Plan", "ChoiceWeek", "Resolve", "DebatePrep", "Debate" }

local check = Rig.check
local need = function(peer: FakeRoblox.Peer, name: string): any
	return Rig.need(peer, "Campaign", name)
end
local shown = function(inst: any): boolean
	return Rig.shown(inst, "Campaign")
end
local tap = function(world: FakeRoblox.World, peer: FakeRoblox.Peer, name: string, wait: number?)
	Rig.tap(world, peer, "Campaign", name, wait or 0.1)
end
local textOf = function(peer: FakeRoblox.Peer, name: string): string
	return Rig.textOf(peer, "Campaign", name)
end

local function same(a: any, b: any): boolean
	return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
end

local function kitOf(world: FakeRoblox.World, peer: FakeRoblox.Peer): any
	return FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
end

-- Audit findings on the campaign screen outside the node map (the map is WP1's).
local function strictFindings(world: FakeRoblox.World, peer: FakeRoblox.Peer): { string }
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	local findings = Audit.check(FakeRoblox.find(peer, "Campaign"))
	local out = {}
	for _, finding in findings do
		if not finding.onMap then
			table.insert(out, `{finding.rule}: {finding.message}`)
		end
	end
	return out
end

local function hasScroller(inst: any): boolean
	local node = inst.Parent
	while node ~= nil do
		if node.ClassName == "ScrollingFrame" then
			return true
		end
		node = node.Parent
	end
	return false
end

local function accentButtons(world: FakeRoblox.World, peer: FakeRoblox.Peer): { string }
	local Kit = kitOf(world, peer)
	local out = {}
	for _, inst in FakeRoblox.find(peer, "Campaign"):GetDescendants() do
		if
			inst:IsA("GuiButton")
			and shown(inst)
			and inst.BackgroundTransparency < 1
			and same(inst.BackgroundColor3, Kit.colors.accent)
		then
			table.insert(out, inst.Name)
		end
	end
	return out
end

describe("Campaign parts: the pinned action bar", function()
	for _, size in SIZES do
		it(`keeps Lock in pinned and on screen ({size.name})`, function()
			local world, peer = Rig.fixture("Plan", size.screen)
			local lock = need(peer, "LockIn")
			check(lock:GetAttribute("PrimaryAction") == true, "Lock in is not the primary action")
			check(not hasScroller(lock), "Lock in scrolls")
			check(shown(lock), "Lock in is hidden")
			check(
				lock.AbsolutePosition.Y + 56 <= size.screen.y + 0.5,
				`Lock in ends at {lock.AbsolutePosition.Y + 56} on a {size.screen.y} px screen`
			)
			local accents = accentButtons(world, peer)
			check(#accents == 1 and accents[1] == "LockIn", "accent buttons: " .. table.concat(accents, ", "))
			Rig.noErrors(world)
		end)
	end

	for _, size in SIZES do
		it(`passes the strict UI audit on every moment ({size.name})`, function()
			for _, moment in MOMENTS do
				local world, peer = Rig.fixture(moment, size.screen)
				local problems = strictFindings(world, peer)
				check(#problems == 0, `{moment}: ` .. table.concat(problems, "; "))
				Rig.noErrors(world)
			end
		end)
	end

	it("names what is wrong on a disabled Lock in", function()
		local world, peer = Rig.fixture("Plan", nil)
		tap(world, peer, "OH")
		tap(world, peer, "Ad")
		-- The money is gone: the plan no longer fits.
		local broke = Rig.deepCopy(Rig.payloadOf(world, peer))
		broke.view.players[broke.view.you].cash = 0
		Rig.push(world, peer, broke)
		expect(textOf(peer, "LockIn")):toBe("Not enough money")
		check(need(peer, "LockIn").Active == false, "Lock in is enabled on a plan with a problem")
		-- Playtest 1, bug 2: the money problem says what the plan costs and what you have.
		local status = textOf(peer, "BarStatus")
		check(Rig.contains(status, "Plan costs $"), status)
		check(Rig.contains(status, "you have $0.0 (1 ad $"), status)
		local Kit = kitOf(world, peer)
		check(same(need(peer, "BarStatus").TextColor3, Kit.colors.danger), "the problem is not in danger")
		check(Rig.contains(textOf(peer, "Ad"), "no $"), textOf(peer, "Ad"))
		Rig.noErrors(world)
	end)

	it("hides Bank when the time bank is empty", function()
		local world, peer = Rig.fixture("Plan", nil)
		check(shown(need(peer, "BankButton")), "no Bank button with time in the bank")
		local empty = Rig.deepCopy(Rig.payloadOf(world, peer))
		empty.seats[empty.you].bank = 0
		Rig.push(world, peer, empty)
		check(not shown(need(peer, "BankButton")), "Bank shows with an empty bank")
		Rig.noErrors(world)
	end)
end)

describe("Campaign parts: debate prep (B2)", function()
	for _, size in SIZES do
		it(`sits above the plan and above Lock in ({size.name})`, function()
			local world, peer = Rig.fixture("DebatePrep", size.screen)
			local prep, plan, lock = need(peer, "PrepPanel"), need(peer, "PlanList"), need(peer, "LockIn")
			check(shown(prep), "no debate prep in the week before a debate")
			check(prep.LayoutOrder < plan.LayoutOrder, "prep is listed after the plan")
			-- The state card is tall; below it, prep would be scrolled out of sight (Studio, v0.4.0).
			check(
				prep.LayoutOrder < need(peer, "StateCard").LayoutOrder,
				"prep is listed after the state card"
			)
			check(prep.AbsolutePosition.Y < lock.AbsolutePosition.Y, "prep is below Lock in")
			check(
				prep.AbsolutePosition.Y >= 0 and prep.AbsolutePosition.Y < size.screen.y,
				"prep is off screen"
			)
			for _, name in { "PrepPlus1", "PrepMinus1" } do
				local button = need(peer, name)
				expect(button.AbsoluteSize.X):toBe(44)
				expect(button.AbsoluteSize.Y):toBe(44)
			end
			Rig.noErrors(world)
		end)
	end

	it("says why a stepper is greyed out and shows the split on the bar", function()
		local world, peer = Rig.fixture("DebatePrep", nil)
		check(Rig.contains(textOf(peer, "BarStatus"), "prep 2/2/2"), textOf(peer, "BarStatus"))
		tap(world, peer, "PrepPlus1")
		tap(world, peer, "PrepPlus1")
		expect(textOf(peer, "PrepValue1")):toBe(tostring(C.DEBATE_MAX_PER_TOPIC))
		check(need(peer, "PrepPlus1").Active == false, "+ is enabled at the maximum")
		check(shown(need(peer, "PrepNote1")), "no reason under a greyed +")
		check(
			Rig.contains(textOf(peer, "PrepNote1"), `max {C.DEBATE_MAX_PER_TOPIC}`),
			textOf(peer, "PrepNote1")
		)
		check(Rig.contains(textOf(peer, "BarStatus"), "prep 4/1/1"), textOf(peer, "BarStatus"))
		Rig.noErrors(world)
	end)
end)

describe("Campaign parts: the debate reveal (B1)", function()
	it("hides the event card and has nothing to press", function()
		local world, peer = Rig.fixture("Debate", nil)
		local view = Fixtures.payload(C, "Debate").view
		check(view.event ~= nil, "the Debate fixture carries no event, so B1 is not exercised")
		check(not shown(need(peer, "EventCard")), "the event card shows during the debate")
		for t = 1, C.DEBATE_TOPICS do
			need(peer, `DebateTopic{t}`)
		end
		check(FakeRoblox.find(peer, "LockIn") == nil, "Lock in exists during the debate")
		check(not shown(need(peer, "SkipButton")), "a primary button shows during the debate")
		check(FakeRoblox.find(peer, "Campaign"):GetAttribute("PrimaryOptional") == true, "no PrimaryOptional")
		check(Rig.contains(textOf(peer, "BarStatus"), "Debate · topic"), textOf(peer, "BarStatus"))
		Rig.noErrors(world)
	end)
end)

describe("Campaign parts: Choice weeks", function()
	it("puts the expanded event card first, with Ignore outlined", function()
		local world, peer = Rig.fixture("ChoiceWeek", nil)
		local event = need(peer, "EventCard")
		local first: any = nil
		for _, child in need(peer, "Side"):GetChildren() do
			if child:IsA("GuiObject") and child.Visible ~= false then
				if first == nil or child.LayoutOrder < first.LayoutOrder then
					first = child
				end
			end
		end
		check(first == event, `the first side panel is {if first then first.Name else "nothing"}`)
		check(shown(need(peer, "ChoiceRow")), "the answers are hidden")
		local Kit = kitOf(world, peer)
		local ignore = need(peer, "ChoiceIgnore")
		check(ignore:GetAttribute("Selected") == true, "Ignore is not preselected")
		check(not same(ignore.BackgroundColor3, Kit.colors.accent), "Ignore is accent-filled")
		check(same(ignore.VariantStroke.Color, Kit.colors.accent), "Ignore's outline is not accent")
		Rig.noErrors(world)
	end)
end)

describe("Campaign parts: the action grid", function()
	it("adds a Region poll for the selected state's region (B3)", function()
		local world, peer = Rig.fixture("Plan", nil)
		tap(world, peer, "OH")
		local region = PlanDraft.regionOf("OH") :: string
		local cost = string.format("$%.1f", C.REGION_POLL_COST)
		check(Rig.contains(textOf(peer, "RegionPoll"), cost), "label: " .. textOf(peer, "RegionPoll"))
		tap(world, peer, "RegionPoll")
		expect(textOf(peer, "PlanItem1")):toBe(`1. Region poll · {Issues.regionName[region]}`)
		check(need(peer, "RegionPoll").Active == false, "the same region can be polled twice")
		check(Rig.contains(textOf(peer, "RegionPoll"), "polled"), textOf(peer, "RegionPoll"))
		Rig.noErrors(world)
	end)

	it("sends the Region poll and the server takes it", function()
		local world, peer = Rig.practice(3)
		Rig.toPlanInput(world, peer)
		-- Week 1 starts with no money: fundraise first, then poll in a later week.
		local first = Rig.payloadOf(world, peer)
		tap(world, peer, first.view.players[first.view.you].location, 0.05)
		tap(world, peer, "Fundraise", 0.05)
		tap(world, peer, "LockIn", 0.1)
		Rig.waitFor(world, function()
			local p = Rig.payloadOf(world, peer)
			return p.stage == "Input"
				and p.view.phase == "Plan"
				and p.step ~= first.step
				and (p.view.players[p.view.you].cash or 0) >= C.REGION_POLL_COST
		end, Rig.MATCH_LIMIT, "a plan with money for a region poll")
		local calls = Rig.spySubmits(world, peer)
		local view = Rig.payloadOf(world, peer).view
		local home = view.players[view.you].location :: string
		tap(world, peer, home, 0.05)
		tap(world, peer, "RegionPoll", 0.05)
		local store = Rig.storeOf(world, peer)
		local before = #store.get().messages
		tap(world, peer, "LockIn", 1)
		expect(#calls):toBe(1)
		expect(calls[1].actions[1]):toEqual({ kind = "RegionPoll", region = PlanDraft.regionOf(home) })
		local messages = store.get().messages
		for k = before + 1, #messages do
			check(not messages[k].rejected, "the server rejected the plan: " .. messages[k].text)
		end
		Rig.noErrors(world)
	end)

	it("changes the next rally's message in one tap", function()
		local world, peer = Rig.fixture("Plan", nil)
		tap(world, peer, "OH")
		local view = Rig.payloadOf(world, peer).view
		local choices = PlanDraft.messageChoices(C, view, "OH")
		check(#choices >= 2, "Ohio offers fewer than two messages")
		check(
			need(peer, `Issue{choices[1].issue}`):GetAttribute("Selected") == true,
			"the best is not preselected"
		)
		local pick = choices[2].issue
		check(shown(need(peer, `Issue{pick}`)), "the second choice is not on the chip row")
		tap(world, peer, `Issue{pick}`)
		tap(world, peer, "Rally")
		check(Rig.contains(textOf(peer, "PlanItem1"), Issues.displayName[pick]), textOf(peer, "PlanItem1"))
		Rig.noErrors(world)
	end)

	it("opens the pivot chooser in place of the grid and cancels it", function()
		local world, peer = Rig.fixture("Plan", nil)
		tap(world, peer, "PivotButton")
		check(not shown(need(peer, "ActionGrid")), "the grid stays up under the pivot chooser")
		check(shown(need(peer, "PivotChooser")), "no pivot chooser")
		tap(world, peer, "PivotCancel")
		check(shown(need(peer, "ActionGrid")), "Cancel did not bring the grid back")
		Rig.noErrors(world)
	end)
end)

describe("Campaign parts: the plan list", function()
	it("clears only on a second tap within three seconds", function()
		local world, peer = Rig.fixture("Plan", nil)
		tap(world, peer, "OH")
		tap(world, peer, "Fundraise")
		tap(world, peer, "ClearButton")
		expect(textOf(peer, "ClearButton")):toBe("Clear? tap again")
		need(peer, "PlanItem1")
		FakeRoblox.run(world, 3.5)
		expect(textOf(peer, "ClearButton")):toBe("Clear")
		tap(world, peer, "ClearButton")
		need(peer, "PlanItem1")
		tap(world, peer, "ClearButton")
		check(FakeRoblox.find(peer, "PlanItem1") == nil, "two taps did not clear the plan")
		Rig.noErrors(world)
	end)
end)

describe("Campaign parts: the resolve reveal", function()
	it("keeps the state card up, read-only, and lets the player inspect states", function()
		local world, peer = Rig.fixture("Resolve", nil)
		expect(textOf(peer, "SkipButton")):toBe("Skip")
		check(shown(need(peer, "StateCard")), "the state card is hidden during the reveal")
		check(not shown(need(peer, "Actions")), "action buttons show during the reveal")
		tap(world, peer, "TX")
		check(Rig.contains(textOf(peer, "CardTitle"), "Texas"), textOf(peer, "CardTitle"))
		check(
			need(peer, "RevealPanel").LayoutOrder < need(peer, "StateCard").LayoutOrder,
			"reveal is not first"
		)
		tap(world, peer, "SkipButton")
		expect(textOf(peer, "SkipButton")):toBe("Waiting for opponent…")
		Rig.noErrors(world)
	end)
end)

describe("Campaign parts: the header", function()
	it("is one 44 px row on 16:9 and two rows on a phone", function()
		local _, wide = Rig.fixture("Plan", WIDE)
		expect(need(wide, "TopBar").AbsoluteSize.Y):toBe(44)
		local score = need(wide, "Score")
		check(
			score.AbsolutePosition.Y + score.AbsoluteSize.Y <= 44,
			"the 16:9 score strip is not in the header row"
		)
		local _, phone = Rig.fixture("Plan", Rig.PHONE)
		expect(need(phone, "TopBar").AbsoluteSize.Y):toBe(72)
		expect(need(phone, "Score").AbsolutePosition.Y):toBe(44)
		check(Rig.contains(textOf(phone, "YouLabel"), " "), textOf(phone, "YouLabel"))
	end)

	it("turns the timer danger-colored under ten seconds", function()
		local world, peer = Rig.fixture("Plan", nil)
		local Kit = kitOf(world, peer)
		local timer = need(peer, "Countdown")
		check(same(timer.TextColor3, Kit.colors.accent), "the timer does not start accent")
		local left = Rig.payloadOf(world, peer).deadline - world.clock
		FakeRoblox.run(world, left - 10.5)
		check(same(timer.TextColor3, Kit.colors.accent), `the timer is already danger at {timer.Text}`)
		FakeRoblox.run(world, 2)
		check(same(timer.TextColor3, Kit.colors.danger), `the timer is not danger at {timer.Text}`)
		Rig.noErrors(world)
	end)

	it("shows the opponent's status in the action bar", function()
		local world, peer = Rig.fixture("Plan", nil)
		local base = Rig.payloadOf(world, peer)
		local them = 3 - base.you
		local locked = Rig.deepCopy(base)
		locked.seats[them].locked = true
		Rig.push(world, peer, locked)
		expect(textOf(peer, "BarOpponent")):toBe("Opponent: locked in")
		local away = Rig.deepCopy(locked)
		away.seats[them].connected = false
		Rig.push(world, peer, away)
		expect(textOf(peer, "BarOpponent")):toBe("Opponent: disconnected")
		Rig.push(world, peer, locked)
		expect(textOf(peer, "BarOpponent")):toBe("Opponent: back")
		FakeRoblox.run(world, 5)
		expect(textOf(peer, "BarOpponent")):toBe("Opponent: locked in")
		Rig.noErrors(world)
	end)
end)
