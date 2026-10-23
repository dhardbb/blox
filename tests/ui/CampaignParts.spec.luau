--!strict
-- The redesigned campaign screen (UI overhaul WP3, src/client/Screens/
-- CampaignParts) on the fake engine: Lock in pinned in the action bar on both
-- screen sizes, no event card during the debate (B1), the Region poll button (B3), one-tap message chips, two-tap
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
local MOMENTS = { "Plan", "ChoiceWeek", "Resolve", "Debate" }

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
		check(Rig.contains(textOf(peer, "AdEffect"), "Not enough money"), textOf(peer, "AdEffect"))
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

describe("Campaign parts: the action grid", function()
	it("adds a Region poll for the selected state's region (B3)", function()
		local world, peer = Rig.fixture("Plan", nil)
		tap(world, peer, "OH")
		local region = PlanDraft.regionOf("OH") :: string
		local cost = string.format("$%.1f", C.REGION_POLL_COST)
		-- Region poll is one of the extra actions, behind "More actions".
		check(not shown(need(peer, "RegionPoll")), "Region poll shows before More actions")
		tap(world, peer, "MoreActions")
		check(shown(need(peer, "RegionPoll")), "More actions did not show Region poll")
		check(
			Rig.contains(textOf(peer, "RegionPollEffect"), cost),
			"label: " .. textOf(peer, "RegionPollEffect")
		)
		tap(world, peer, "RegionPoll")
		expect(textOf(peer, "PlanItem1")):toBe(`1. Region poll · {Issues.regionName[region]}`)
		check(need(peer, "RegionPoll").Active == false, "the same region can be polled twice")
		check(
			Rig.contains(textOf(peer, "RegionPollEffect"), "Already polled"),
			textOf(peer, "RegionPollEffect")
		)
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
		tap(world, peer, "OH")
		tap(world, peer, "MoreActions")
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
		tap(world, peer, "TX")
		check(shown(need(peer, "StateCard")), "the state card is hidden during the reveal")
		check(not shown(need(peer, "Actions")), "action buttons show during the reveal")
		check(Rig.contains(textOf(peer, "CardTitle"), "Texas"), textOf(peer, "CardTitle"))
		tap(world, peer, "DetailsToggle")
		check(shown(need(peer, "CardPoll")), "Details do not open during the reveal")
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
	it("is one 44 px row and the now line, on 16:9 and on a phone", function()
		for _, size in SIZES do
			local _, peer = Rig.fixture("Plan", size.screen)
			local top = need(peer, "TopBar")
			expect(top.AbsoluteSize.Y):toBe(44 + 32)
			local score = need(peer, "Score")
			check(shown(score), `{size.name}: no score`)
			check(
				score.AbsolutePosition.Y + score.AbsoluteSize.Y <= top.AbsolutePosition.Y + 44,
				`{size.name}: the score strip is not in the header row`
			)
			check(Rig.contains(textOf(peer, "YouLabel"), " "), textOf(peer, "YouLabel"))
			expect(textOf(peer, "NowText")):toBe("Tap a state on the map")
			expect(textOf(peer, "APLabel")):toBe("3 actions left")
			check(Rig.contains(textOf(peer, "MoneyLabel"), "$"), textOf(peer, "MoneyLabel"))
		end
	end)

	it("says what to do now as the plan grows", function()
		local world, peer = Rig.fixture("Plan", WIDE)
		tap(world, peer, "OH")
		expect(textOf(peer, "NowText")):toBe("Pick an action in Ohio")
		for _ = 1, 3 do
			tap(world, peer, "Rally")
		end
		expect(textOf(peer, "NowText")):toBe("All set? Press Lock in")
		expect(textOf(peer, "APLabel")):toBe("0 actions left")
		-- Tapping the selected state again closes its card.
		tap(world, peer, "OH")
		check(not shown(need(peer, "StateCard")), "the card stays open on a second tap")
		tap(world, peer, "LockIn")
		check(Rig.contains(textOf(peer, "NowText"), "Waiting for"), textOf(peer, "NowText"))
		Rig.noErrors(world)
	end)

	it("turns the timer warn under ten seconds and danger under five", function()
		local world, peer = Rig.fixture("Plan", nil)
		local Kit = kitOf(world, peer)
		local timer = need(peer, "Countdown")
		check(same(timer.TextColor3, Kit.colors.accent), "the timer does not start accent")
		local left = Rig.payloadOf(world, peer).deadline - world.clock
		FakeRoblox.run(world, left - 10.5)
		check(same(timer.TextColor3, Kit.colors.accent), `the timer is already urgent at {timer.Text}`)
		FakeRoblox.run(world, 2)
		check(same(timer.TextColor3, Kit.colors.warn), `the timer is not warn at {timer.Text}`)
		FakeRoblox.run(world, 5)
		check(same(timer.TextColor3, Kit.colors.danger), `the timer is not danger at {timer.Text}`)
		Rig.noErrors(world)
	end)

	it("shows the opponent's status in the action bar, by their first name", function()
		local world, peer = Rig.fixture("Plan", nil)
		local base = Rig.payloadOf(world, peer)
		local them = 3 - base.you
		local Model = FakeRoblox.require(world, peer, "src/client/Screens/CampaignParts/Model.luau")
		local name = Model.firstName(C, base.view, them)
		-- Thinking: the dots step along at a fixed width.
		local thinking = Rig.deepCopy(base)
		thinking.seats[them].locked = false
		Rig.push(world, peer, thinking)
		local seen = {}
		for _ = 1, 4 do
			local text = textOf(peer, "BarOpponent")
			check(string.sub(text, 1, #name + 10) == `{name}: thinking`, text)
			expect(#text):toBe(#name + 13)
			seen[text] = true
			FakeRoblox.run(world, 0.5)
		end
		check(next(seen, next(seen)) ~= nil, "the thinking dots never move")
		local locked = Rig.deepCopy(base)
		locked.seats[them].locked = true
		Rig.push(world, peer, locked)
		expect(textOf(peer, "BarOpponent")):toBe(`{name}: locked in ✓`)
		local away = Rig.deepCopy(locked)
		away.seats[them].connected = false
		Rig.push(world, peer, away)
		expect(textOf(peer, "BarOpponent")):toBe(`{name}: disconnected`)
		Rig.push(world, peer, locked)
		expect(textOf(peer, "BarOpponent")):toBe(`{name}: back`)
		FakeRoblox.run(world, 5)
		expect(textOf(peer, "BarOpponent")):toBe(`{name}: locked in ✓`)
		Rig.noErrors(world)
	end)

	it("keeps the thinking dots still under reduced motion", function()
		local world, peer = Rig.fixture("Plan", nil, { reducedMotion = true })
		local base = Rig.payloadOf(world, peer)
		local Model = FakeRoblox.require(world, peer, "src/client/Screens/CampaignParts/Model.luau")
		local name = Model.firstName(C, base.view, 3 - base.you)
		local thinking = Rig.deepCopy(base)
		thinking.seats[3 - base.you].locked = false
		Rig.push(world, peer, thinking)
		for _ = 1, 3 do
			expect(textOf(peer, "BarOpponent")):toBe(`{name}: thinking...`)
			FakeRoblox.run(world, 0.5)
		end
		Rig.noErrors(world)
	end)
end)

-- The board's motion and sound (polish WP-1, docs/DESIGN.md D-053): planned
-- badges on the map, one cue per plan change, the refusal shake, the ghost tag
-- while an action is held, the score counting, the map key's color steps, and
-- the same end state with Reduce Motion on.
describe("Campaign board motion and sound", function()
	local Words = require("@ui/Words/Campaign")

	local function node(peer: FakeRoblox.Peer, id: string): any
		local map = need(peer, "NodeMap")
		return map.Nodes:FindFirstChild(id)
	end

	local function count(list: { string }, name: string): number
		local n = 0
		for _, entry in list do
			if entry == name then
				n += 1
			end
		end
		return n
	end

	local function badgeIcon(peer: FakeRoblox.Peer, id: string): string?
		local badge = node(peer, id):FindFirstChild("PlanBadge")
		if badge == nil then
			return nil
		end
		return badge.Icon:GetAttribute("Icon")
	end

	-- A tap and the cues it plays, then a pause: UI/Audio sounds at most four
	-- cues at once (each counts for 0.5 s here, where sounds have no length).
	local function slowTap(world: FakeRoblox.World, peer: FakeRoblox.Peer, name: string)
		tap(world, peer, name, 0.6)
	end

	-- Plans an ad in OH and a fundraiser in PA, then removes the ad.
	local function planTwo(world: FakeRoblox.World, peer: FakeRoblox.Peer): { [string]: any }
		local seen = {}
		slowTap(world, peer, "OH")
		slowTap(world, peer, "Ad")
		seen.afterOne = count(Rig.sounds(peer), "planAdd")
		seen.ohBadge = badgeIcon(peer, "OH")
		slowTap(world, peer, "PA")
		slowTap(world, peer, "Fundraise")
		seen.afterTwo = count(Rig.sounds(peer), "planAdd")
		seen.paBadge = badgeIcon(peer, "PA")
		seen.money = textOf(peer, "MoneyLabel")
		slowTap(world, peer, "RemoveItem1")
		seen.removes = count(Rig.sounds(peer), "planRemove")
		seen.ohAfter = badgeIcon(peer, "OH")
		seen.paAfter = badgeIcon(peer, "PA")
		seen.item = textOf(peer, "PlanItem1")
		seen.leaving = Rig.findIn(peer, "Campaign", "PlanItemLeaving")
		return seen
	end

	it("badges each planned state and plays one cue per change", function()
		local world, peer = Rig.fixture("Plan", nil)
		local seen = planTwo(world, peer)
		expect(seen.afterOne):toBe(1)
		expect(seen.afterTwo):toBe(2)
		expect(seen.ohBadge):toBe("tv")
		expect(seen.paBadge):toBe("coins")
		expect(seen.removes):toBe(1)
		expect(seen.ohAfter):toBe(nil)
		expect(seen.paAfter):toBe("coins")
		check(Rig.contains(seen.item, "Fundraise"), seen.item)
		check(seen.leaving == nil, "the removed row never left")
		-- Tapping a state is a "select".
		check(count(Rig.sounds(peer), "select") >= 2, "no select cue on a state tap")
		Rig.noErrors(world)
	end)

	it("lands on the same end state with Reduce Motion on", function()
		local fullWorld, fullPeer = Rig.fixture("Plan", nil)
		local full = planTwo(fullWorld, fullPeer)
		local world, peer = Rig.fixture("Plan", nil, { reducedMotion = true })
		local reduced = planTwo(world, peer)
		expect(reduced):toEqual(full)
		check(node(peer, "PA").PlanBadge:FindFirstChild("MotionScale") == nil, "the badge popped")
		check(need(peer, "StateCard"):FindFirstChild("MotionScale", true) == nil, "the card's buttons popped")
		check(Rig.findIn(peer, "Campaign", "Delta") == nil, "a delta chip under reduced motion")
		Rig.noErrors(world)
		Rig.noErrors(fullWorld)
	end)

	it("shakes the bar with one error for a greyed-out Lock in", function()
		local world, peer = Rig.fixture("Plan", nil)
		slowTap(world, peer, "OH")
		slowTap(world, peer, "Ad")
		local broke = Rig.deepCopy(Rig.payloadOf(world, peer))
		broke.view.players[broke.view.you].cash = 0
		Rig.push(world, peer, broke)
		check(need(peer, "LockIn").Active == false, "Lock in is enabled on a broke plan")
		slowTap(world, peer, "LockIn")
		expect(count(Rig.sounds(peer), "error")):toBe(1)
		slowTap(world, peer, "LockIn")
		expect(count(Rig.sounds(peer), "error")):toBe(2)
		Rig.noErrors(world)
	end)

	it("plays one error when the server turns the plan down", function()
		local world, peer = Rig.practice(3)
		Rig.toPlanInput(world, peer)
		Rig.sabotageSubmits(world, peer, { actions = { { kind = "Zzz" } } })
		Rig.tap(world, peer, "Campaign", "LockIn", 1)
		expect(count(Rig.sounds(peer), "error")):toBe(1)
		Rig.noErrors(world)
	end)

	it("shows a held action's effect on the map as a ghost tag", function()
		local world, peer = Rig.fixture("Plan", nil)
		tap(world, peer, "OH")
		local rally = need(peer, "Rally")
		world.current = peer
		rally.InputBegan.fire({ UserInputType = { Name = "Touch" } })
		world.current = nil
		local ghost = Rig.need(peer, "Campaign", "GhostTag")
		check(ghost.Visible ~= false, "no ghost tag while Rally is held")
		local effect = textOf(peer, "RallyEffect")
		expect(ghost.Text):toBe(Words.gain(effect))
		world.current = peer
		rally.InputEnded.fire({ UserInputType = { Name = "Touch" } })
		world.current = nil
		check(ghost.Visible == false, "the ghost tag stays after release")
		Rig.noErrors(world)
	end)

	it("counts the score to its new value with a delta chip", function()
		local world, peer = Rig.fixture("Plan", nil)
		local base = Rig.payloadOf(world, peer)
		local me = base.view.you
		local before = base.view.projectedEV[me]
		local moved = Rig.deepCopy(base)
		moved.view.projectedEV[me] = before + 12
		Rig.push(world, peer, moved)
		local chip = Rig.findIn(peer, "Campaign", "Delta")
		check(chip ~= nil, "no delta chip")
		expect(chip.Text):toBe("+12")
		check(chip:GetAttribute("Decor") == true, "the delta chip is not decorative")
		FakeRoblox.run(world, 1)
		local you = textOf(peer, "YouLabel")
		check(string.sub(you, -#tostring(before + 12)) == tostring(before + 12), you)
		check(Rig.findIn(peer, "Campaign", "Delta") == nil, "the delta chip stays")
		Rig.noErrors(world)
	end)

	it("shows the four color steps in the map key", function()
		local world, peer = Rig.fixture("Plan", nil)
		tap(world, peer, "MapKey")
		local bands = Words.bands()
		expect(#bands):toBe(4)
		for k, band in bands do
			local row = need(peer, `KeyBand{k}`)
			expect(row.BandText.Text):toBe(band.text)
			expect(row.Theirs.Visible):toBe(k > 1)
		end
		Rig.noErrors(world)
	end)
end)
