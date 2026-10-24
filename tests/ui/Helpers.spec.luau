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
local IssueMap = require("@sim/IssueMap")
local StateData = require("@sim/StateData")
local Swing = require("@ui/Swing")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

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
		-- Half the full margin is past half the color (FILL_CURVE, D-064).
		local half = Colors.stateFill({ 40, 46 }, colors)
		expect(half):toEqual(Colors.mix(Colors.neutral, Colors.player.Cobalt, 0.5 ^ Colors.FILL_CURVE))
	end)

	it("keeps player text readable and as saturated as it can (D-064)", function()
		for name, c in Colors.player do
			local t = Colors.textOn(c)
			local ratio = Colors.contrast(t, Colors.surfaceTop)
			check(ratio >= Colors.TEXT_CONTRAST, `{name} text is only {ratio}:1 on a card`)
			-- A color that already reads is left alone; a dark one is lifted, never darkened.
			if Colors.contrast(c, Colors.surfaceTop) >= Colors.TEXT_CONTRAST then
				expect(t):toEqual({ r = c.r, g = c.g, b = c.b })
			else
				check(Colors.luma(t) > Colors.luma(c), `{name} text is not lighter than the fill`)
			end
		end
		-- Crimson keeps its hue: brightened, red stays the biggest channel by far.
		local red = Colors.textOn(Colors.player.Crimson)
		check(red.r == 252 and red.g < 100, `Crimson text is {red.r}, {red.g}, {red.b}`)
		-- A slate stays a slate: brightened with its channels in the same order.
		local grey = Colors.textOn(Colors.neutral)
		check(grey.b > grey.g and grey.g > grey.r, `neutral text is {grey.r}, {grey.g}, {grey.b}`)
		expect(Colors.contrast(Colors.text, Colors.text)):toBe(1)
	end)

	it("keeps the player colors apart from each other and from the loss orange (D-056, D-064)", function()
		-- CIE76 distance in L*a*b* (D65); D-056's "about 30" floor.
		local function lab(c: Colors.RGB): (number, number, number)
			local function lin(v: number): number
				local s = v / 255
				return if s <= 0.04045 then s / 12.92 else ((s + 0.055) / 1.055) ^ 2.4
			end
			local r, g, b = lin(c.r), lin(c.g), lin(c.b)
			local x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
			local y = 0.2126 * r + 0.7152 * g + 0.0722 * b
			local z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
			local function f(t: number): number
				return if t > 0.008856 then t ^ (1 / 3) else 7.787 * t + 16 / 116
			end
			return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))
		end
		local function dist(a: Colors.RGB, b: Colors.RGB): number
			local l1, a1, b1 = lab(a)
			local l2, a2, b2 = lab(b)
			return math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
		end
		local names = {}
		for name in Colors.player do
			table.insert(names, name)
		end
		table.sort(names)
		for i, a in names do
			local d = dist(Colors.player[a], Colors.loss)
			check(d >= 40, `{a} is only {d} from the loss orange`)
			for j = i + 1, #names do
				local b = names[j]
				local e = dist(Colors.player[a], Colors.player[b])
				check(e >= 35, `{a} and {b} are only {e} apart`)
			end
		end
	end)

	it("has the design-system tokens (D-030)", function()
		expect(Colors.onAccent):toEqual(Colors.background)
		-- Warning text is its own color, so "careful" never reads as "press here".
		expect(Colors.warn == Colors.accent):toBe(false)
		expect(Colors.disabledText):toEqual(Colors.muted)
		local field = Colors.field
		-- The field well sits between the background and a panel.
		expect(field.r > Colors.background.r and field.r < Colors.surface.r):toBe(true)
	end)

	it("keeps the white accent apart from every player color and status color (D-058)", function()
		-- D-051 checked a hue gap for the pink accent. White has no hue to speak
		-- of, so the check is now: the accent is a neutral (no color of its own,
		-- color is kept for meaning), clearly lighter than every player and status
		-- color, its label reads at 7:1 and its slate lip shows on the stage.
		local function lum(c: Colors.RGB): number
			local function lin(v: number): number
				local s = v / 255
				return if s <= 0.04045 then s / 12.92 else ((s + 0.055) / 1.055) ^ 2.4
			end
			return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
		end
		local function contrast(a: Colors.RGB, b: Colors.RGB): number
			local x, y = lum(a), lum(b)
			return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
		end
		local a = Colors.accent
		local spread = math.max(a.r, a.g, a.b) - math.min(a.r, a.g, a.b)
		check(spread <= 12, `the accent is tinted ({spread} between its channels)`)
		local others: { [string]: Colors.RGB } =
			{ good = Colors.good, bad = Colors.danger, warn = Colors.warn }
		for name, c in Colors.player do
			others[name] = c
		end
		for name, c in others do
			check(lum(a) > lum(c), `the accent is not lighter than {name}`)
			local ratio = contrast(a, c)
			check(ratio >= 1.5, `the accent is only {ratio}:1 from {name}`)
		end
		-- WCAG contrast of the primary's label (onAccent) on the accent fill.
		local label = contrast(a, Colors.onAccent)
		check(label >= 7, `primary label contrast is {label}:1`)
		-- The lip under the white face shows on the stage and on a card.
		for _, ground in { Colors.background, Colors.surface } do
			local lip = contrast(Colors.accentLip, ground)
			check(lip >= 3, `the primary's lip is only {lip}:1 on the stage`)
		end
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
		for i, record in StateData.list do
			local issues = view.issueMap[i]
			local issue, mult = PlanDraft.bestIssue(C, view, record.id)
			expect(mult >= C.ISSUE_MULT_STATE):toBe(true)
			expect(table.find(issues, issue) ~= nil):toBe(true)
			-- The best platform issue here, at this match's multiplier (D-047).
			local best = C.ISSUE_MULT_STATE
			for _, top in issues do
				if table.find(platform, top) then
					best = math.max(best, view.platformMults[top])
				end
			end
			expect(mult):toBe(best)
			local attackIssue = PlanDraft.bestAttackIssue(C, view, record.id)
			expect(table.find(issues, attackIssue) ~= nil):toBe(true)
		end
	end)

	it("a previewed plan with no problem passes the real validator", function()
		local match = Match.new(C, 5, { "a", "b" })
		local pick = { candidate = "okafor", platform = { "Jobs", "Health", "Schools" } }
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
	local pick = { candidate = "okafor", platform = { "Jobs", "Health", "Schools" } }
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
	it("a plan never carries a stance: it is decided on its own screen first (D-044)", function()
		local match = planWeek(1, true)
		local view = View.build(C, match, 1)
		local draft = PlanDraft.new()
		expect(PlanDraft.isChoiceWeek(view)):toBe(true)
		expect(PlanDraft.payload(draft)):toEqual({ actions = {} })
		expect(PlanDraft.problem(C, view, draft)):toBe(nil)
		local ok, reason = Match.validate(C, match, 1, PlanDraft.payload(draft))
		expect(reason):toBe(nil)
		expect(ok):toBe(true)
		-- The stance was taken in the Decision step before this plan: the view says which.
		expect(view.stance):toBe("C")
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
		expect(PlanDraft.eventEffect(C, event("Choice", "Jobs", nil))):toBe(
			"Take a stance on Jobs: each state reacts by its own top issues"
		)
		local more = Config.with(C, { EVENT_SPOTLIGHT_MULT = 2 })
		expect(PlanDraft.eventEffect(more, event("Spotlight", "Jobs", nil))):toBe(
			"Rallies and ads about Jobs are worth ×2 this week"
		)
		expect(PlanDraft.choiceNote(C)):toBe(
			-- Numbers follow D-039 and D-043 (stances).
			`States with the issue react by their other top issue (+{C.STANCE_POINTS} or -{C.STANCE_POINTS}); every other state moves {PlanDraft.points(
				C.STANCE_SPILL
			)} per top issue a side likes, {PlanDraft.points(-C.STANCE_SPILL)} per one it dislikes. Your home and strongholds count ×{C.STANCE_BASE_MULT}. The hedge (C) moves nothing, but costs {PlanDraft.points(
				-C.STANCE_HEDGE_COST
			)} in your home and strongholds with the issue. Running on the issue: ×{C.STANCE_PLATFORM_MULT} in its states. Stances stay secret until the week resolves; no stance in time is C.`
		)
	end)

	it("marks the states a Spotlight or Regional event singles out", function()
		local function event(kind: any, issue: any, region: any): View.EventView
			return { week = 3, id = "x", kind = kind, name = "N", text = "T", issue = issue, region = region }
		end
		local pacific = PlanDraft.eventStates(event("Regional", nil, "Pacific"), IssueMap.flavor)
		local health = PlanDraft.eventStates(event("Spotlight", "Health", nil), IssueMap.flavor)
		local pacificCount, healthCount = 0, 0
		for _, record in StateData.list do
			expect(pacific[record.id] == true):toBe(record.region == "Pacific")
			expect(health[record.id] == true):toBe(table.find(record.flavor, "Health") ~= nil)
			pacificCount += if pacific[record.id] then 1 else 0
			healthCount += if health[record.id] then 1 else 0
		end
		expect(pacificCount > 0 and pacificCount < #StateData.list):toBe(true)
		expect(healthCount > 0 and healthCount < #StateData.list):toBe(true)
		expect(next(PlanDraft.eventStates(event("Windfall", nil, nil), IssueMap.flavor))):toBe(nil)
		expect(next(PlanDraft.eventStates(event("Choice", nil, nil), IssueMap.flavor))):toBe(nil)
		expect(PlanDraft.eventMapNote(event("Windfall", nil, nil))):toBe(nil)
	end)

	it("reports last week's event with both stances and the points each asked for", function()
		local match = planWeek(1, true)
		local week = match.week
		match.players[1].stance, match.players[2].stance = "B", "A" -- as their Decision step set them
		local after = Match.advance(C, match, {})
		while after.phase ~= "Plan" and after.week == week do
			after = Match.advance(C, after, {})
		end
		local event = Events.at(match) :: Events.Definition
		local logged = after.eventLog[#after.eventLog]
		local moves = logged.moves :: { State.StateMove }
		local mine = View.build(C, after, 1)
		expect(mine.week):toBe(week + 1)
		expect(PlanDraft.lastEventLine(mine)):toBe(`Last week's event: {event.name}.`)
		-- The stances and their points are Swing's lines (D-042), from each side.
		local stanceB = (Events.stance(event, "B") :: Events.Stance).name
		local stanceA = (Events.stance(event, "A") :: Events.Stance).name
		local mineLines = Swing.choiceLines(C, mine, Swing.lastChoice(mine) :: any)
		check(string.find(mineLines[1], `You took B · {stanceB}`, 1, true) ~= nil, mineLines[1])
		check(string.find(mineLines[2], `They took A · {stanceA}`, 1, true) ~= nil, mineLines[2])
		local gain = 0
		for _, move in moves do
			gain += math.max(0, move.points[1])
		end
		check(string.find(mineLines[1], `: {Numbers.signed(gain)} total over `, 1, true) ~= nil, mineLines[1])
		local theirs = View.build(C, after, 2)
		local theirLines = Swing.choiceLines(C, theirs, Swing.lastChoice(theirs) :: any)
		check(string.find(theirLines[1], `You took A · {stanceA}`, 1, true) ~= nil, theirLines[1])
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
			elseif moment == "Stance" then
				expect(payload.stage):toBe("Input")
				expect(payload.view.phase):toBe("Decision")
				expect(payload.view.decision):toBe(moment)
			elseif moment == "DebateIntro" then
				expect(payload.reveal):toBe("DebateIntro")
				expect(payload.view.debate ~= nil):toBe(true)
			elseif moment == "DebateRound" then
				expect(payload.stage):toBe("Input")
				expect(payload.view.phase):toBe("Debate")
				expect(payload.view.debate.round):toBe(2)
			elseif moment == "Clash" then
				expect(payload.reveal):toBe("Clash")
			elseif moment == "Plan" or moment == "ChoiceWeek" then
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
				expect(payload.reveal):toBe("Verdict")
				expect(#payload.view.debates > 0):toBe(true)
			elseif moment == "Election" then
				expect(payload.view.election ~= nil):toBe(true)
			elseif moment == "Over" then
				expect(payload.result ~= nil):toBe(true)
			end
		end
	end)
end)
