--!strict
-- Plan validation: costs, route flights, caps, reason codes, and fuzzed payloads.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Config = require("@sim/Config")
local Match = require("@sim/Match")
local Plan = require("@sim/Plan")
local Rng = require("@sim/Rng")
local State = require("@sim/State")
local StateData = require("@sim/StateData")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

-- Week 1 with player 1 at home in Ohio and a known amount of cash.
local function week1(candidate: string?): State.MatchState
	local match = Fixtures.campaign({ seed = 9, candidates = { candidate or "okafor", "okafor" } })
	match.players[1].location = "OH"
	match.players[1].cash = 10
	return match
end

local function check(match: State.MatchState, actions: { any }, prep: any?): (boolean, string?)
	local ok, reason = Plan.validate(C, match, 1, { actions = actions, prep = prep })
	return ok, reason
end

describe("Plan.validate", function()
	it("accepts a route through adjacent states without flights", function()
		local match = week1()
		local plan = {
			{ kind = "Rally", state = "OH", issue = "Jobs" },
			{ kind = "Fundraise", state = "PA" },
			{ kind = "Rally", state = "NY", issue = "Health" },
		}
		local ok, reason = check(match, plan)
		expect(reason):toBe(nil)
		expect(ok):toBe(true)
		local _, _, normalized = Plan.validate(C, match, 1, { actions = plan })
		local cost = Plan.cost(C, match, 1, normalized :: Plan.Plan)
		expect(cost):toEqual({ ap = 3, cash = 0, flights = 0 })
	end)

	it("charges a flight for a non-adjacent stop", function()
		local match = week1()
		local _, _, normalized = Plan.validate(C, match, 1, {
			actions = {
				{ kind = "Rally", state = "CA", issue = "Jobs" }, -- flight
				{ kind = "Rally", state = "NV", issue = "Jobs" }, -- adjacent to CA
				{ kind = "Rally", state = "HI", issue = "Jobs" }, -- flight
			},
		})
		local cost = Plan.cost(C, match, 1, normalized :: Plan.Plan)
		expect(cost.flights):toBe(2)
		expect(cost.cash):toBe(2 * C.FLIGHT_COST)
	end)

	it("rejects plans over the AP budget, but Rex gets 4", function()
		local rallies = {}
		for k = 1, 4 do
			rallies[k] = { kind = "Rally", state = "OH", issue = "Jobs" }
		end
		expect(select(2, check(week1(), rallies))):toBe(Plan.Reason.NotEnoughAP)
		expect((check(week1("calloway"), rallies))):toBe(true)
	end)

	it("rejects plans the player cannot afford", function()
		local match = week1()
		local plan = {}
		for k = 1, 4 do
			plan[k] = { kind = "Media", state = "OH", issue = "Jobs" }
		end
		expect(select(2, check(match, plan))):toBe(Plan.Reason.NotEnoughMoney) -- $12 > $10
		table.remove(plan)
		expect((check(match, plan))):toBe(true) -- $9
	end)

	it("prices media by candidate", function()
		local match = week1("venkat")
		local _, _, normalized =
			Plan.validate(C, match, 1, { actions = { { kind = "Media", state = "OH", issue = "Jobs" } } })
		expect(Plan.cost(C, match, 1, normalized :: Plan.Plan).cash):toBe(2)
	end)

	it("gives Helen two free single-state polls a week", function()
		local match = week1("strand")
		local _, _, normalized = Plan.validate(C, match, 1, {
			actions = {
				{ kind = "Poll", state = "OH" },
				{ kind = "Poll", state = "PA" },
				{ kind = "Poll", state = "MI" },
				{ kind = "RegionPoll", region = "Pacific" },
			},
		})
		expect(Plan.cost(C, match, 1, normalized :: Plan.Plan).cash):toBe(
			C.INTERNAL_POLL_COST + C.REGION_POLL_COST
		)
	end)

	it("rejects polling one state twice", function()
		local match = week1()
		local plan = { { kind = "Poll", state = "OH" }, { kind = "Poll", state = "OH" } }
		expect(select(2, check(match, plan))):toBe(Plan.Reason.DuplicatePoll)
	end)

	it("caps ground game per state, counting units already placed", function()
		local match = week1()
		match.players[1].cash = 100
		expect((check(match, { { kind = "Gotv", state = "OH", units = 4 } }))):toBe(true)
		expect(select(2, check(match, { { kind = "Gotv", state = "OH", units = 5 } }))):toBe(
			Plan.Reason.GotvCap
		)
		State.get(match, "OH").gotv[1] = 3
		local split =
			{ { kind = "Gotv", state = "OH", units = 1 }, { kind = "Gotv", state = "OH", units = 1 } }
		expect(select(2, check(match, split))):toBe(Plan.Reason.GotvCap)
		local walt = week1("begay")
		walt.players[1].cash = 100
		expect((check(walt, { { kind = "Gotv", state = "OH", units = 6 } }))):toBe(true)
	end)

	it("allows one pivot per match, from a platform issue to a new one", function()
		local match = week1()
		local platform = match.players[1].platform
		local outside = "Farms"
		expect(table.find(platform, outside)):toBe(nil)
		local pivot = { kind = "Pivot", drop = platform[1], add = outside }
		expect((check(match, { pivot }))):toBe(true)
		expect(select(2, check(match, { pivot, pivot }))):toBe(Plan.Reason.PivotUsed)
		expect(select(2, check(match, { { kind = "Pivot", drop = outside, add = platform[1] } }))):toBe(
			Plan.Reason.BadPivot
		)
		match.players[1].pivotUsed = true
		expect(select(2, check(match, { pivot }))):toBe(Plan.Reason.PivotUsed)
	end)

	it("attacks default to the only opponent and cannot target yourself", function()
		local match = week1()
		local _, _, normalized =
			Plan.validate(C, match, 1, { actions = { { kind = "Attack", state = "OH", issue = "Jobs" } } })
		expect((normalized :: Plan.Plan).actions[1].target):toBe(2)
		local self = { { kind = "Attack", state = "OH", issue = "Jobs", target = 1 } }
		expect(select(2, check(match, self))):toBe(Plan.Reason.BadTarget)
	end)

	it("never carries debate prep or a stance: those have their own Decision phase (D-044)", function()
		local match = week1()
		expect(select(2, check(match, {}, { 2, 2, 2 }))):toBe(Plan.Reason.UnexpectedPrep)
		match = Fixtures.advanceTo(match, "Plan", 3)
		expect(select(2, check(match, {}, { 2, 2, 2 }))):toBe(Plan.Reason.UnexpectedPrep)
		local ok, reason = Plan.validate(C, match, 1, { actions = {}, choice = "C" })
		expect(ok):toBe(false)
		expect(reason):toBe(Plan.Reason.UnexpectedChoice)
		expect(Plan.empty()):toEqual({ actions = {} })
	end)

	it("drops unknown fields when normalizing", function()
		local match = week1()
		local _, _, normalized = Plan.validate(C, match, 1, {
			cheat = true,
			actions = { { kind = "Rally", state = "OH", issue = "Jobs", support = 99 } },
		})
		expect((normalized :: any).cheat):toBe(nil)
		expect(((normalized :: any).actions[1]).support):toBe(nil)
	end)

	it("returns reason codes for malformed payloads", function()
		local match = week1()
		local cases: { { any } } = {
			{ nil, Plan.Reason.BadShape },
			{ "plan", Plan.Reason.BadShape },
			{ { actions = "x" }, Plan.Reason.BadShape },
			{ { actions = { foo = 1 } }, Plan.Reason.BadShape },
			{ { actions = { 5 } }, Plan.Reason.BadShape },
			{ { actions = { { kind = "Bribe" } } }, Plan.Reason.UnknownKind },
			{ { actions = { { kind = "Rally", state = "XX", issue = "Jobs" } } }, Plan.Reason.UnknownState },
			{ { actions = { { kind = "Rally", state = "OH", issue = "Taxes" } } }, Plan.Reason.UnknownIssue },
			{ { actions = { { kind = "RegionPoll", region = "Moon" } } }, Plan.Reason.UnknownRegion },
			{ { actions = { { kind = "Gotv", state = "OH", units = 0 } } }, Plan.Reason.BadUnits },
			{ { actions = { { kind = "Gotv", state = "OH", units = 1.5 } } }, Plan.Reason.BadUnits },
			{ { actions = { { kind = "Gotv", state = "OH", units = 0 / 0 } } }, Plan.Reason.BadUnits },
		}
		for _, case in cases do
			local ok, reason = Plan.validate(C, match, 1, case[1])
			expect(ok):toBe(false)
			expect(reason):toBe(case[2])
		end
		local tooMany = {}
		for k = 1, C.PLAN_MAX_ACTIONS + 1 do
			tooMany[k] = { kind = "Poll", state = StateData.list[k % 51 + 1].id }
		end
		expect(select(2, check(match, tooMany))):toBe(Plan.Reason.TooManyActions)
	end)

	it("never throws on random garbage", function()
		local match = week1()
		local rng = Rng.new(123)
		local atoms: { any } = { 0, -1, 1.5, "OH", "Jobs", "Rally", true, false, {}, 1e309, -0 }
		local kinds = { "Rally", "Fundraise", "Media", "Attack", "Poll", "RegionPoll", "Gotv", "Pivot", "X" }
		local keys = { "kind", "state", "issue", "target", "region", "units", "drop", "add" }
		for _ = 1, 500 do
			local actions = {}
			for k = 1, Rng.nextInt(rng, 0, 6) do
				local action: { [string]: any } = { kind = kinds[Rng.nextInt(rng, 1, #kinds)] }
				for _, key in keys do
					if Rng.nextFloat(rng) < 0.6 then
						action[key] = atoms[Rng.nextInt(rng, 1, #atoms)]
					end
				end
				action.kind = action.kind or "Rally"
				actions[k] = action
			end
			local ok, reason = Match.validate(C, match, 1, { actions = actions })
			expect(type(ok)):toBe("boolean")
			if not ok then
				expect(type(reason)):toBe("string")
				expect(reason ~= "Internal"):toBe(true)
			end
		end
	end)

	it("rejects plans outside the Plan phase", function()
		local match = Fixtures.selected()
		expect(select(2, Plan.validate(C, match, 1, { actions = {} }))):toBe(Plan.Reason.WrongPhase)
	end)
end)
