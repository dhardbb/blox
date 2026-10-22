--!strict
-- Pure UI helpers: colors, the node-map layout, the plan draft preview, fixtures.

local Test = require("@testlib/Test")
local Colors = require("@ui/Colors")
local Config = require("@sim/Config")
local Events = require("@sim/Events")
local Fixtures = require("@ui/Fixtures")
local MapLayout = require("@ui/MapLayout")
local Match = require("@sim/Match")
local Numbers = require("@ui/Numbers")
local Plan = require("@sim/Plan")
local PlanDraft = require("@ui/PlanDraft")
local State = require("@sim/State")
local StateData = require("@sim/StateData")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

describe("Colors", function()
	it("has a color for every pickable player color", function()
		local Candidates = require("@sim/Candidates")
		for _, name in Candidates.colors do
			expect(Colors.player[name] ~= nil):toBe(true)
		end
	end)

	it("fills ties neutral and blends toward the leader", function()
		local colors = { Colors.player.Crimson, Colors.player.Cobalt }
		expect(Colors.stateFill({ 40, 40 }, colors)):toEqual(Colors.neutral)
		expect(Colors.stateFill(nil, colors)):toEqual(Colors.neutral)
		local full = Colors.stateFill({ 55, 40 }, colors)
		expect(full):toEqual(Colors.mix(Colors.neutral, Colors.player.Crimson, 1))
		local half = Colors.stateFill({ 40, 46 }, colors)
		expect(half):toEqual(Colors.mix(Colors.neutral, Colors.player.Cobalt, 0.5))
	end)

	it("has the design-system tokens (D-030)", function()
		expect(Colors.onAccent):toEqual(Colors.background)
		expect(Colors.warn):toEqual(Colors.accent)
		expect(Colors.disabledText):toEqual(Colors.muted)
		local field = Colors.field
		-- The field well sits between the background and a panel.
		expect(field.r > Colors.background.r and field.r < Colors.surface.r):toBe(true)
	end)

	it("tints toward a color, clamped, and keeps mix as the same function", function()
		expect(Colors.mix):toBe(Colors.tint)
		local base, color = Colors.raised, Colors.player.Crimson
		expect(Colors.tint(base, color, 0)):toEqual({ r = base.r, g = base.g, b = base.b })
		expect(Colors.tint(base, color, 1)):toEqual({ r = color.r, g = color.g, b = color.b })
		expect(Colors.tint(base, color, 2)):toEqual(Colors.tint(base, color, 1))
		expect(Colors.tint({ r = 0, g = 0, b = 0 }, { r = 100, g = 200, b = 50 }, 0.35)):toEqual({
			r = 35,
			g = 70,
			b = 18,
		})
	end)

	it("picks dark text on light swatches and light text on dark ones", function()
		for _, name in { "Amber", "Teal", "Emerald" } do
			expect(Colors.onColor(Colors.player[name])):toEqual(Colors.background)
		end
		for _, name in { "Crimson", "Cobalt", "Violet" } do
			expect(Colors.onColor(Colors.player[name])):toEqual(Colors.text)
		end
		expect(Colors.onColor({ r = 255, g = 255, b = 255 })):toEqual(Colors.background)
		expect(Colors.onColor({ r = 0, g = 0, b = 0 })):toEqual(Colors.text)
		expect(Colors.onColor(Colors.accent)):toEqual(Colors.onAccent)
	end)
end)

describe("MapLayout", function()
	it("places every state inside the box", function()
		local nodes = MapLayout.nodes()
		expect(#nodes):toBe(#StateData.list)
		for _, n in nodes do
			expect(n.x - n.r >= 0 and n.x + n.r <= 1):toBe(true)
			local ry = n.r * MapLayout.ASPECT
			expect(n.y - ry >= -1e-9 and n.y + ry <= 1 + 1e-9):toBe(true)
		end
	end)

	it("keeps circles from overlapping", function()
		local nodes = MapLayout.nodes()
		local worst = 0
		for i = 1, #nodes do
			for j = i + 1, #nodes do
				local a, b = nodes[i], nodes[j]
				local dx, dy = a.x - b.x, (a.y - b.y) / MapLayout.ASPECT
				local overlap = a.r + b.r - math.sqrt(dx * dx + dy * dy)
				worst = math.max(worst, overlap / math.min(a.r, b.r))
			end
		end
		expect(worst < 0.1):toBe(true)
	end)

	it("keeps the map recognisable: west is left, north is up", function()
		local at = {}
		for _, n in MapLayout.nodes() do
			at[n.id] = n
		end
		expect(at.CA.x < at.TX.x and at.TX.x < at.FL.x and at.FL.x < at.ME.x + 0.1):toBe(true)
		expect(at.WA.y < at.CA.y and at.ND.y < at.TX.y and at.MI.y < at.FL.y):toBe(true)
		expect(at.CA.r > at.WY.r):toBe(true)
	end)

	it("lists each land border once", function()
		local count = 0
		for _, record in StateData.list do
			count += #record.adjacent
		end
		expect(#MapLayout.edges()):toBe(count / 2)
	end)
end)

describe("PlanDraft", function()
	local function planView()
		return Fixtures.payload(C, "Plan").view
	end

	it("previews the same cost the server charges", function()
		local view = planView()
		local draft = PlanDraft.new()
		local home = view.players[view.you].location :: string
		PlanDraft.add(draft, { kind = "Rally", state = home, issue = "Jobs" })
		PlanDraft.add(draft, { kind = "Rally", state = "HI", issue = "Jobs" })
		PlanDraft.add(draft, { kind = "Media", state = "OH", issue = "Jobs" })
		local cost = PlanDraft.cost(C, view, draft)
		expect(cost.ap):toBe(2)
		expect(cost.flights):toBe(1)
		expect(cost.cash):toBe(C.FLIGHT_COST + C.MEDIA_COST)
		local route = PlanDraft.route(view, draft)
		expect(#route):toBe(2)
		expect(route[2].flight):toBe(true)
		expect(PlanDraft.location(view, draft)):toBe("HI")
	end)

	it("flags what the server would reject", function()
		local view = planView()
		local draft = PlanDraft.new()
		expect(PlanDraft.problem(C, view, draft)):toBe(nil)
		for _ = 1, 4 do
			PlanDraft.add(draft, { kind = "Rally", state = view.players[view.you].location, issue = "Jobs" })
		end
		expect(PlanDraft.problem(C, view, draft)):toBe(Plan.Reason.NotEnoughAP)
		draft = PlanDraft.new()
		PlanDraft.add(draft, { kind = "Gotv", state = "OH", units = 5 })
		expect(PlanDraft.problem(C, view, draft)):toBe(Plan.Reason.GotvCap)
		draft = PlanDraft.new()
		PlanDraft.add(draft, { kind = "Poll", state = "OH" })
		PlanDraft.add(draft, { kind = "Poll", state = "OH" })
		expect(PlanDraft.problem(C, view, draft)):toBe(Plan.Reason.DuplicatePoll)
	end)

	it("suggests the best issue for a rally and an attack", function()
		local view = planView()
		local platform = view.players[view.you].platform :: { string }
		for _, record in StateData.list do
			local issue, mult = PlanDraft.bestIssue(C, view, record.id)
			expect(mult >= C.ISSUE_MULT_STATE):toBe(true)
			expect(table.find(record.issues, issue) ~= nil):toBe(true)
			local inBoth = false
			for _, i in record.issues do
				if table.find(platform, i) then
					inBoth = true
				end
			end
			expect(mult):toBe(if inBoth then C.ISSUE_MULT_BOTH else C.ISSUE_MULT_STATE)
			local attackIssue = PlanDraft.bestAttackIssue(C, view, record.id)
			expect(table.find(record.issues, attackIssue) ~= nil):toBe(true)
		end
	end)

	it("a previewed plan with no problem passes the real validator", function()
		local match = Match.new(C, 5, { "a", "b" })
		local pick = { candidate = "okafor", color = "Teal", platform = { "Jobs", "Health", "Schools" } }
		match = Match.advance(C, match, { pick, pick })
		while match.phase ~= "Plan" do
			match = Match.advance(C, match, {})
		end
		local view = View.build(C, match, 1)
		local draft = PlanDraft.new()
		local home = view.players[1].location :: string
		PlanDraft.add(draft, { kind = "Rally", state = home, issue = PlanDraft.bestIssue(C, view, home) })
		PlanDraft.add(draft, { kind = "Fundraise", state = home })
		PlanDraft.add(draft, { kind = "Poll", state = "PA" })
		expect(PlanDraft.problem(C, view, draft)):toBe(nil)
		local ok, reason = Match.validate(C, match, 1, PlanDraft.payload(draft))
		expect(reason):toBe(nil)
		expect(ok):toBe(true)
	end)
end)

-- A fresh two-player match advanced (with empty plans) to the Plan phase of the
-- first week at or after `week` whose event is a Choice (`choice` true) or isn't.
local function planWeek(seed: number, choice: boolean): Match.MatchState
	local match = Match.new(C, seed, { "a", "b" })
	local pick = { candidate = "okafor", color = "Teal", platform = { "Jobs", "Health", "Schools" } }
	match = Match.advance(C, match, { pick, pick })
	for _ = 1, 200 do
		if match.phase == "Plan" and Events.isChoiceWeek(match) == choice and Events.at(match) ~= nil then
			return match
		end
		match = Match.advance(C, match, {})
	end
	error("no such plan week")
end

describe("PlanDraft weekly events", function()
	it("sends a Choice stance only when one is set, and the server accepts it", function()
		local match = planWeek(1, true)
		local view = View.build(C, match, 1)
		local draft = PlanDraft.new()
		expect(PlanDraft.isChoiceWeek(view)):toBe(true)
		expect(PlanDraft.payload(draft).choice):toBe(nil)
		draft.choice = "A"
		expect(PlanDraft.payload(draft).choice):toBe("A")
		expect(PlanDraft.problem(C, view, draft)):toBe(nil)
		for _, answer in Events.CHOICES do
			draft.choice = answer
			local ok, reason = Match.validate(C, match, 1, PlanDraft.payload(draft))
			expect(reason):toBe(nil)
			expect(ok):toBe(true)
		end
	end)

	it("rejects a Choice stance in any other week, like the server", function()
		local match = planWeek(1, false)
		local view = View.build(C, match, 1)
		expect(PlanDraft.isChoiceWeek(view)):toBe(false)
		local draft = PlanDraft.new()
		expect(PlanDraft.problem(C, view, draft)):toBe(nil)
		draft.choice = "B"
		expect(PlanDraft.problem(C, view, draft)):toBe(Plan.Reason.UnexpectedChoice)
		local ok, reason = Match.validate(C, match, 1, PlanDraft.payload(draft))
		expect(ok):toBe(false)
		expect(reason):toBe(Plan.Reason.UnexpectedChoice)
		-- No event at all (week 1) is also not a Choice week.
		local early = Match.new(C, 1, { "a", "b" })
		early = Match.advance(C, early, {
			{ candidate = "okafor", color = "Teal", platform = { "Jobs", "Health", "Schools" } },
			{ candidate = "okafor", color = "Teal", platform = { "Jobs", "Health", "Schools" } },
		})
		while early.phase ~= "Plan" do
			early = Match.advance(C, early, {})
		end
		local earlyView = View.build(C, early, 1)
		expect(earlyView.event):toBe(nil)
		expect(PlanDraft.problem(C, earlyView, draft)):toBe(Plan.Reason.UnexpectedChoice)
	end)

	it("describes each kind of event in plain words with the Config numbers", function()
		local function event(kind: any, issue: any, region: any): View.EventView
			return { week = 3, id = "x", kind = kind, name = "N", text = "T", issue = issue, region = region }
		end
		local spot = PlanDraft.eventEffect(C, event("Spotlight", "Transit", nil))
		expect(spot):toBe("Rallies and ads about Roads & Transit are worth ×1.3 this week")
		local region = PlanDraft.eventEffect(C, event("Regional", nil, "GreatLakes"))
		expect(region):toBe("Rallies in the Great Lakes states are worth ×1.5 this week")
		local windfall = PlanDraft.eventEffect(C, event("Windfall", nil, nil))
		expect(windfall):toBe(
			"Fundraisers in states where you trail in the public poll raise ×1.2 this week"
		)
		expect(PlanDraft.eventEffect(C, event("Choice", nil, nil))):toBe("Take a stance: A / B / C")
		local more = Config.with(C, { EVENT_SPOTLIGHT_MULT = 2 })
		expect(PlanDraft.eventEffect(more, event("Spotlight", "Jobs", nil))):toBe(
			"Rallies and ads about Jobs are worth ×2 this week"
		)
		expect(PlanDraft.choiceNote(C)):toBe(
			-- Numbers follow D-039 (stances).
			`Only states with this issue as a top issue react, by their other top issue: +{C.STANCE_POINTS} where a stance is liked, -{C.STANCE_POINTS} where it is not, +{C.STANCE_HEDGE} otherwise. C is the hedge: +{C.STANCE_HEDGE} in every such state. A candidate who runs on the issue is heard ×{C.STANCE_PLATFORM_MULT}. Stances stay secret until the week resolves.`
		)
	end)

	it("marks the states a Spotlight or Regional event singles out", function()
		local function event(kind: any, issue: any, region: any): View.EventView
			return { week = 3, id = "x", kind = kind, name = "N", text = "T", issue = issue, region = region }
		end
		local pacific = PlanDraft.eventStates(event("Regional", nil, "Pacific"))
		local health = PlanDraft.eventStates(event("Spotlight", "Health", nil))
		local pacificCount, healthCount = 0, 0
		for _, record in StateData.list do
			expect(pacific[record.id] == true):toBe(record.region == "Pacific")
			expect(health[record.id] == true):toBe(table.find(record.issues, "Health") ~= nil)
			pacificCount += if pacific[record.id] then 1 else 0
			healthCount += if health[record.id] then 1 else 0
		end
		expect(pacificCount > 0 and pacificCount < #StateData.list):toBe(true)
		expect(healthCount > 0 and healthCount < #StateData.list):toBe(true)
		expect(next(PlanDraft.eventStates(event("Windfall", nil, nil)))):toBe(nil)
		expect(next(PlanDraft.eventStates(event("Choice", nil, nil)))):toBe(nil)
		expect(PlanDraft.eventMapNote(event("Windfall", nil, nil))):toBe(nil)
	end)

	it("reports last week's event with both stances and the points each asked for", function()
		local match = planWeek(1, true)
		local week = match.week
		local after = Match.advance(C, match, {
			{ actions = {}, choice = "B" },
			{ actions = {}, choice = "A" },
		})
		while after.phase ~= "Plan" and after.week == week do
			after = Match.advance(C, after, {})
		end
		local event = Events.at(match) :: Events.Definition
		local logged = after.eventLog[#after.eventLog]
		local moves = logged.moves :: { State.StateMove }
		local net = { 0, 0 }
		for _, move in moves do
			net[1] += move.points[1]
			net[2] += move.points[2]
		end
		local mine = View.build(C, after, 1)
		expect(mine.week):toBe(week + 1)
		expect(PlanDraft.lastEventLine(mine)):toBe(
			`Last week's event: {event.name}. You took stance B, they took stance A: {#moves} states moved, {Numbers.signed(
				net[1]
			)} / {Numbers.signed(net[2])} points in all.`
		)
		local theirs = View.build(C, after, 2)
		expect(PlanDraft.lastEventLine(theirs)):toBe(
			`Last week's event: {event.name}. You took stance A, they took stance B: {#moves} states moved, {Numbers.signed(
				net[2]
			)} / {Numbers.signed(net[1])} points in all.`
		)
	end)

	it("names a resolved event that has no Choice", function()
		local match = planWeek(1, false)
		local week = match.week
		local name = (Events.at(match) :: Events.Definition).name
		local after = Match.advance(C, match, {})
		while after.phase ~= "Plan" and after.week == week do
			after = Match.advance(C, after, {})
		end
		expect(PlanDraft.lastEventLine(View.build(C, after, 1))):toBe(`Last week's event: {name}.`)
	end)
end)

describe("Fixtures", function()
	it("reaches every moment with a payload for that screen", function()
		for _, moment in Fixtures.MOMENTS do
			local payload = Fixtures.payload(C, moment)
			expect(payload.you):toBe(1)
			if moment == "Select" then
				expect(payload.view.phase):toBe("Select")
			elseif moment == "Draft" then
				expect(payload.view.phase):toBe("Draft")
				expect(#payload.view.draftLog > 0):toBe(true)
			elseif moment == "Plan" or moment == "DebatePrep" or moment == "ChoiceWeek" then
				expect(payload.stage):toBe("Input")
				expect(payload.view.phase):toBe("Plan")
				if moment == "ChoiceWeek" then
					local event = payload.view.event
					expect(event ~= nil and event.kind == "Choice"):toBe(true)
					expect(payload.view.week >= 2 and payload.view.week <= 11):toBe(true)
				end
			elseif moment == "Resolve" then
				expect(payload.reveal):toBe("Resolve")
				expect(#payload.events > 0):toBe(true)
			elseif moment == "Debate" then
				expect(payload.reveal):toBe("Debate")
				expect(#payload.view.debates > 0):toBe(true)
			elseif moment == "Election" then
				expect(payload.view.election ~= nil):toBe(true)
			elseif moment == "Over" then
				expect(payload.result ~= nil):toBe(true)
			end
		end
	end)
end)
