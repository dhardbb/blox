--!strict
-- Pure UI helpers: colors, the node-map layout, the plan draft preview, fixtures.

local Test = require("@testlib/Test")
local Colors = require("@ui/Colors")
local Config = require("@sim/Config")
local Fixtures = require("@ui/Fixtures")
local MapLayout = require("@ui/MapLayout")
local Match = require("@sim/Match")
local Plan = require("@sim/Plan")
local PlanDraft = require("@ui/PlanDraft")
local StateData = require("@sim/StateData")

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
		while match.phase ~= "Plan" do
			match = Match.advance(C, match, {})
		end
		local View = require("@sim/View")
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
			elseif moment == "Plan" or moment == "DebatePrep" then
				expect(payload.stage):toBe("Input")
				expect(payload.view.phase):toBe("Plan")
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
