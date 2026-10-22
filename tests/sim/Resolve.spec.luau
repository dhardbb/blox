--!strict
-- Weekly resolution: snapshot symmetry, action values, momentum and drift,
-- fundraising pools, media saturation, attacks and backlash, pivots, upkeep.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Match = require("@sim/Match")
local State = require("@sim/State")
local StateData = require("@sim/StateData")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local SAME = { { "Jobs", "Health", "Schools" }, { "Jobs", "Health", "Schools" } }

-- Week 1 with both players identical, in Ohio, every state reset to 35/35/30 with
-- no lean, momentum, ownership or rubber band. Marcus Hale is the default because
-- his perk touches nothing resolved here.
local function clean(candidates: { string }?): State.MatchState
	local match =
		Fixtures.campaign({ seed = 21, candidates = candidates or { "hale", "hale" }, platforms = SAME })
	for _, s in match.states do
		s.support = { 35, 35 }
		s.undecided = 30
		s.lean, s.leanTo = 0, nil
		s.battleground, s.owner, s.isHome = false, nil, false
		s.momentum = { 0, 0 }
		s.pool = s.capacity
	end
	for _, player in match.players do
		player.location = "OH"
		player.cash = 50
		player.underdogTier = 0
		player.frontrunner = false
	end
	return match
end

local function run(match: State.MatchState, a: { any }, b: { any }): State.MatchState
	for p, actions in { a, b } do
		local ok, reason = Match.validate(C, match, p, { actions = actions })
		assert(ok, `plan {p} rejected: {reason}`)
	end
	local nextMatch = Match.advance(C, match, { { actions = a }, { actions = b } })
	Fixtures.checkSupport(nextMatch)
	return nextMatch
end

local function at(match: State.MatchState, id: string): State.StateSim
	return State.get(match, id)
end

describe("Resolve: snapshot rule (D-001)", function()
	it("identical plans give identical results for both players", function()
		local plan = {
			{ kind = "Rally", state = "OH", issue = "Jobs" },
			{ kind = "Fundraise", state = "OH" },
			{ kind = "Rally", state = "PA", issue = "Health" },
			{ kind = "Media", state = "PA", issue = "Jobs" },
			{ kind = "Attack", state = "MI", issue = "Farms" },
		}
		local match = run(clean(), plan, plan)
		for _, s in match.states do
			expect(s.support[1]):toBeCloseTo(s.support[2], 1e-9)
			expect(s.momentum[1]):toBeCloseTo(s.momentum[2], 1e-9)
		end
		expect(match.players[1].cash):toBeCloseTo(match.players[2].cash, 1e-9)
		expect(match.players[1].location):toBe(match.players[2].location)
	end)

	it("swapping which player submits which plan mirrors the outcome", function()
		local a = {
			{ kind = "Rally", state = "OH", issue = "Jobs" },
			{ kind = "Media", state = "IN", issue = "Health" },
		}
		local b = {
			{ kind = "Rally", state = "OH", issue = "Health" },
			{ kind = "Attack", state = "IN", issue = "Farms" },
		}
		local one = run(clean(), a, b)
		local two = run(clean(), b, a)
		for i, s in one.states do
			local t = two.states[i]
			expect(s.support[1]):toBeCloseTo(t.support[2], 1e-9)
			expect(s.support[2]):toBeCloseTo(t.support[1], 1e-9)
			expect(s.undecided):toBeCloseTo(t.undecided, 1e-9)
		end
	end)
end)

describe("Resolve: rallies, momentum and drift", function()
	it("a matched rally is worth 4.5, then drifts on 2 momentum", function()
		local match = run(clean(), { { kind = "Rally", state = "OH", issue = "Jobs" } }, {})
		local s = at(match, "OH") -- OH top issues include Jobs; Jobs is in the platform
		expect(table.find(StateData.byId.OH.issues, "Jobs") ~= nil):toBe(true)
		expect(s.momentum[1]):toBe(C.RALLY_MOMENTUM)
		-- Rally +4.5: 39.5 / 33.65 / 26.85. Drift 0.6 x 2 = 1.2: 40.7 / 33.29 / 26.01.
		expect(s.support[1]):toBeCloseTo(40.7)
		expect(s.support[2]):toBeCloseTo(33.29)
		expect(s.undecided):toBeCloseTo(26.01)
	end)

	it("battlegrounds multiply rally support by 1.5", function()
		local match = clean()
		at(match, "OH").battleground = true
		match = run(match, { { kind = "Rally", state = "OH", issue = "Jobs" } }, {})
		-- Rally +6.75: 41.75 / 32.975 / 25.275, then drift 1.2.
		expect(at(match, "OH").support[1]):toBeCloseTo(41.75 + 1.2)
	end)

	it("momentum halves each week and caps at 6", function()
		local match = clean({ "calloway", "hale" })
		local four = {}
		for k = 1, 4 do
			four[k] = { kind = "Rally", state = "OH", issue = "Jobs" }
		end
		match = run(match, four, {})
		expect(at(match, "OH").momentum[1]):toBe(C.MOMENTUM_CAP)
		match = run(match, {}, {})
		expect(at(match, "OH").momentum[1]):toBe(C.MOMENTUM_CAP * C.MOMENTUM_DECAY)
	end)

	it("Tomas gains 65% more momentum and keeps only 25%", function()
		local match = run(
			clean({ "reyes", "hale" }),
			{ { kind = "Rally", state = "OH", issue = "Jobs" } },
			{}
		)
		expect(at(match, "OH").momentum[1]):toBe(3.3)
		match = run(match, {}, {})
		expect(at(match, "OH").momentum[1]):toBe(0.825)
	end)

	it("only the momentum leader drifts, by the gap, capped at 3", function()
		local match = clean()
		at(match, "OH").momentum = { 12, 2 } -- decays to 6 and 1 with no actions
		match = run(match, {}, {})
		local s = at(match, "OH")
		expect(s.momentum[1]):toBe(6)
		expect(s.momentum[2]):toBe(1)
		-- Drift min(0.6 x 5, 3) = 3 to player 1: 38 / 34.1 / 27.9.
		expect(s.support[1]):toBeCloseTo(38)
		expect(s.support[2]):toBeCloseTo(34.1)
	end)
end)

describe("Resolve: fundraisers", function()
	it("yield 2 + 6 x share, capped by the pool, which refills 25% a week", function()
		local match = clean()
		local pool = at(match, "OH").capacity
		match = run(match, { { kind = "Fundraise", state = "OH" } }, {})
		local raised = 2 + 6 * 0.35
		expect(match.players[1].raised):toBeCloseTo(raised)
		expect(match.players[1].cash):toBeCloseTo(50 + raised + C.PASSIVE_INCOME)
		expect(at(match, "OH").pool):toBeCloseTo(math.min(pool, pool - raised + pool * C.POOL_REFILL))
	end)

	it("two fundraisers in one pool split it in proportion to their yields", function()
		local match = clean()
		local wy = at(match, "WY")
		wy.support = { 45, 25 }
		local cap = wy.capacity
		for _, player in match.players do
			player.location = "WY"
		end
		match = run(match, { { kind = "Fundraise", state = "WY" } }, { { kind = "Fundraise", state = "WY" } })
		local rawA, rawB = 2 + 6 * 0.45, 2 + 6 * 0.25
		expect(rawA + rawB > cap):toBe(true)
		expect(match.players[1].raised):toBeCloseTo(cap * rawA / (rawA + rawB))
		expect(match.players[2].raised):toBeCloseTo(cap * rawB / (rawA + rawB))
		expect(at(match, "WY").pool):toBeCloseTo(cap * C.POOL_REFILL)
	end)

	it("perk and home multipliers apply after the cap and do not drain the pool", function()
		local match = clean({ "okafor", "hale" })
		local oh = at(match, "OH")
		oh.isHome, oh.owner = true, 1
		match = run(match, { { kind = "Fundraise", state = "OH" } }, {})
		local raw = 2 + 6 * 0.35
		expect(match.players[1].raised):toBeCloseTo(raw * 1.3 * C.HOME_FUNDRAISE_MULT)
		expect(at(match, "OH").capacity - at(match, "OH").pool):toBeCloseTo(
			raw - at(match, "OH").capacity * C.POOL_REFILL
		)
	end)

	it("an empty pool raises nothing", function()
		local match = clean()
		at(match, "OH").pool = 0
		match = run(match, { { kind = "Fundraise", state = "OH" } }, {})
		expect(match.players[1].raised):toBe(0)
	end)
end)

describe("Resolve: media and attacks", function()
	it("repeat buys in one state are worth 60%, then 36%", function()
		local one = run(clean(), { { kind = "Media", state = "OH", issue = "Jobs" } }, {})
		local three = run(clean(), {
			{ kind = "Media", state = "OH", issue = "Jobs" },
			{ kind = "Media", state = "OH", issue = "Jobs" },
			{ kind = "Media", state = "OH", issue = "Jobs" },
		}, {})
		expect(at(one, "OH").momentum[1]):toBeCloseTo(1)
		expect(at(three, "OH").momentum[1]):toBeCloseTo(1 + 0.6 + 0.36)
		expect(at(three, "OH").support[1] > at(one, "OH").support[1]):toBe(true)
	end)

	it("an attack on a top issue the target lacks costs 2.4 and earns no momentum", function()
		local match = clean()
		local issue = "Farms"
		expect(table.find(StateData.byId.IA.issues, issue) ~= nil):toBe(true)
		match = run(match, { { kind = "Attack", state = "IA", issue = issue } }, {})
		local s = at(match, "IA")
		-- Loss 1.6 x 1.5 = 2.4: target 32.6, attacker +0.96, undecided +1.44.
		expect(s.support[2]):toBeCloseTo(32.6)
		expect(s.support[1]):toBeCloseTo(35.96)
		expect(s.undecided):toBeCloseTo(31.44)
		expect(s.momentum[1]):toBe(0)
	end)

	it("backlash: the fourth attack in a state costs the attacker and resets the meter", function()
		local attacks = {}
		for k = 1, 3 do
			attacks[k] = { kind = "Attack", state = "IA", issue = "Farms" }
		end
		local match = run(clean(), attacks, {})
		expect(at(match, "IA").backlash[1]):toBe(3 - C.BACKLASH_DECAY)
		match = clean()
		at(match, "IA").backlash[1] = 3
		local before = at(match, "IA").support[1]
		match = run(match, { attacks[1] }, {})
		expect(at(match, "IA").backlash[1]):toBe(0)
		-- +0.96 from the attack, -0.8 backlash.
		expect(at(match, "IA").support[1]):toBeCloseTo(before + 0.96 - C.BACKLASH_PENALTY)
	end)

	it("Helen's media is 10% weaker; Priya's repeat buys keep 70%", function()
		local two = {
			{ kind = "Media", state = "OH", issue = "Jobs" },
			{ kind = "Media", state = "OH", issue = "Jobs" },
		}
		local priya = run(clean({ "venkat", "hale" }), two, {})
		expect(at(priya, "OH").momentum[1]):toBeCloseTo(1.7)
		local helen = run(clean({ "strand", "hale" }), { two[1] }, {})
		local base = run(clean(), { two[1] }, {})
		expect(at(helen, "OH").support[1] < at(base, "OH").support[1]):toBe(true)
	end)
end)

describe("Resolve: pivots and upkeep", function()
	it("a pivot swaps the issue and costs 1 point of national support", function()
		local match = clean()
		local weights, before = 0, 0
		for i, s in match.states do
			weights += StateData.list[i].pop
			before += StateData.list[i].pop * s.support[1]
		end
		match = run(match, { { kind = "Pivot", drop = "Schools", add = "Farms" } }, {})
		expect(match.players[1].platform):toEqual({ "Jobs", "Health", "Farms" })
		expect(match.players[1].pivotUsed):toBe(true)
		expect(match.players[1].card and match.players[1].card.pivot):toEqual({
			drop = "Schools",
			add = "Farms",
		})
		local after = 0
		for i, s in match.states do
			after += StateData.list[i].pop * s.support[1]
		end
		expect((after - before) / weights):toBeCloseTo(-C.PIVOT_PENALTY, 1e-6)
	end)

	it("pays income, charges costs and flights, and moves the candidate", function()
		local match = clean()
		match = run(match, {
			{ kind = "Rally", state = "CA", issue = "Jobs" },
			{ kind = "Media", state = "TX", issue = "Jobs" },
			{ kind = "Poll", state = "FL" },
		}, {})
		expect(match.players[1].cash):toBeCloseTo(
			50 - C.FLIGHT_COST - C.MEDIA_COST - C.INTERNAL_POLL_COST + C.PASSIVE_INCOME
		)
		expect(match.players[1].location):toBe("CA")
		expect(match.players[1].card and match.players[1].card.flights):toBe(1)
		expect(match.players[2].cash):toBe(50 + C.PASSIVE_INCOME)
	end)

	it("internal polls report support within the error, exact undecided and momentum", function()
		local match = run(
			clean(),
			{ { kind = "Poll", state = "OH" }, { kind = "RegionPoll", region = "Pacific" } },
			{}
		)
		local polls = match.players[1].internalPolls
		local pacific = 0
		for _, record in StateData.list do
			if record.region == "Pacific" then
				pacific += 1
			end
		end
		expect(#polls):toBe(1 + pacific)
		for _, poll in polls do
			local s = at(match, poll.state)
			for p = 1, 2 do
				expect(math.abs(poll.support[p] - s.support[p]) <= C.INTERNAL_POLL_ERROR + 0.05):toBe(true)
			end
			expect(poll.undecided):toBeCloseTo(s.undecided, 0.05)
			expect(poll.momentum):toEqual(s.momentum)
		end
		expect(#match.players[2].internalPolls):toBe(0)
	end)

	it("places ground game units", function()
		local match = run(clean(), { { kind = "Gotv", state = "OH", units = 3 } }, {})
		expect(at(match, "OH").gotv):toEqual({ 3, 0 })
	end)

	it("every candidate survives a full week of every action", function()
		for _, id in Candidates.ids do
			local match = clean({ id, id })
			local plan = {
				{ kind = "Rally", state = "OH", issue = "Jobs" },
				{ kind = "Fundraise", state = "OH" },
				{ kind = "Media", state = "PA", issue = "Health" },
				{ kind = "Attack", state = "PA", issue = "Farms" },
				{ kind = "Poll", state = "MI" },
				{ kind = "Gotv", state = "OH", units = 1 },
				{ kind = "Pivot", drop = "Schools", add = "Farms" },
			}
			run(match, plan, plan)
		end
	end)
end)
