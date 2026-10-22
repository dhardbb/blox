--!strict
-- Config and Candidates sanity: internal consistency, time budget, roster rules.

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local Candidates = require("@sim/Candidates")
local StateData = require("@sim/StateData")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

describe("Config", function()
	it("starting support and undecided sum to 100", function()
		expect(C.BASE_SUPPORT * 2 + C.BASE_UNDECIDED):toBe(100)
	end)

	it("draft priority covers every round and is balanced", function()
		expect(#C.DRAFT_PRIORITY):toBe(1 + C.STRONGHOLD_ROUNDS + C.NOMINATION_ROUNDS)
		local count = { 0, 0 }
		for _, slot in C.DRAFT_PRIORITY do
			count[slot] += 1
		end
		expect(count[1]):toBe(count[2])
	end)

	it("debates fall inside the campaign", function()
		for _, week in C.DEBATE_WEEKS do
			expect(week >= 2 and week <= C.WEEKS):toBe(true)
		end
	end)

	it("a debate sweep is meaningful, never decisive (D-019)", function()
		-- A 3-0 sweep moves the population-weighted average by under one point, so it
		-- cannot by itself outrun election-day noise in a tied state.
		local sweep = C.DEBATE_TOPICS * C.DEBATE_TOPIC_WIN + C.DEBATE_SWEEP
		expect(sweep < 1):toBe(true)
		expect(sweep >= 0.5):toBe(true)
		expect(C.DEBATE_GAFFE <= C.DEBATE_TOPIC_WIN):toBe(true)
		-- The roll dilutes a one-point edge: with a 0..6 roll, +1 wins 57% and loses 31%.
		expect(C.DEBATE_ROLL_MAX >= 2 * C.DEBATE_PLATFORM_BONUS):toBe(true)
	end)

	it("events stay small and off the first and last weeks (D-027)", function()
		expect(C.EVENT_FIRST_WEEK >= 2 and C.EVENT_LAST_WEEK <= C.WEEKS - 1):toBe(true)
		expect(C.EVENT_FIRST_WEEK <= C.EVENT_LAST_WEEK):toBe(true)
		for _, mult in { C.EVENT_SPOTLIGHT_MULT, C.EVENT_REGIONAL_MULT, C.EVENT_WINDFALL_MULT } do
			expect(mult > 1 and mult <= 1.5):toBe(true)
		end
		-- Every Choice payoff is inside the cap and smaller than a 3-0 debate sweep.
		local sweep = C.DEBATE_TOPICS * C.DEBATE_TOPIC_WIN + C.DEBATE_SWEEP
		local payoffs = {
			C.CHOICE_ATTACK_ATTACK,
			C.CHOICE_ATTACK_DEFEND,
			C.CHOICE_ATTACK_IGNORE,
			C.CHOICE_DEFEND_ATTACK,
			C.CHOICE_DEFEND_DEFEND,
			C.CHOICE_DEFEND_IGNORE,
			C.CHOICE_IGNORE_ATTACK,
			C.CHOICE_IGNORE_DEFEND,
			C.CHOICE_IGNORE_IGNORE,
		}
		for _, v in payoffs do
			expect(math.abs(v) <= C.EVENT_CAP and math.abs(v) < sweep):toBe(true)
		end
		expect(C.CHOICE_IGNORE_IGNORE):toBe(0)
	end)

	it("ground game beats a poorly matched media buy per dollar (D-021)", function()
		-- Hidden, unsaturating and placed late, GOTV must be the better use of a dollar
		-- somewhere, or nobody buys it. Compare with a media buy on a mismatched issue.
		local gotvPerDollar = C.GOTV_PER_UNIT / C.GOTV_COST
		local mediaMargin = C.MEDIA_SUPPORT * C.ISSUE_MULT_NEITHER * (2 - C.GAIN_FROM_UNDECIDED)
		expect(gotvPerDollar > mediaMargin / C.MEDIA_COST):toBe(true)
		-- ... but not a well matched one, so it stays a late-game sink, not the default.
		local bestMedia = C.MEDIA_SUPPORT * C.ISSUE_MULT_BOTH * (2 - C.GAIN_FROM_UNDECIDED)
		expect(gotvPerDollar < bestMedia / C.MEDIA_COST):toBe(true)
	end)

	it("worst-case match fits the 17.5-minute budget (D-005)", function()
		local worst = C.TIMER_SELECT
			+ C.TIMER_MAP_REVEAL
			+ #C.DRAFT_PRIORITY * (C.TIMER_DRAFT_ROUND + C.DRAFT_REVEAL)
			+ C.WEEKS * (C.TIMER_PLAN + C.TIMER_RESOLVE)
			+ C.TIME_BANK * 2
			+ #C.DEBATE_WEEKS * C.TIMER_DEBATE
			+ C.TIMER_ELECTION
			+ C.TRANSITION_ALLOWANCE
		expect(worst):toBe(1042)
		expect(worst):toBeLessThan(17.5 * 60 + 1)
	end)

	it("is frozen, nested tables included", function()
		expect(function()
			(C :: any).WEEKS = 1
		end):toThrow()
		expect(function()
			(C.DRAFT_PRIORITY :: any)[1] = 2
		end):toThrow()
	end)

	it("no state's pool funds three fundraisers at starting support (D-012)", function()
		local smallestYield = C.FUNDRAISER_BASE + C.FUNDRAISER_PER_SHARE * C.BASE_SUPPORT / 100
		for _, s in StateData.list do
			local capacity = Config.poolCapacity(C, s.pop)
			if capacity >= 3 * smallestYield then
				error(`{s.id} pool {capacity} funds three fundraisers`)
			end
		end
	end)

	it("with() overrides known keys and rejects typos", function()
		local variant = Config.with(C, { POLL_SIGMA = 5 })
		expect(variant.POLL_SIGMA):toBe(5)
		expect(C.POLL_SIGMA):toBe(3)
		expect(function()
			Config.with(C, { POLL_SIGAM = 5 })
		end):toThrow("unknown Config key")
	end)
end)

describe("Candidates", function()
	it("has eight unique candidates with full profiles", function()
		expect(#Candidates.ids):toBe(8)
		local seen = {}
		for _, id in Candidates.ids do
			expect(seen[id]):toBe(nil)
			seen[id] = true
			local p = Candidates.profile(C, id)
			expect(p.id):toBe(id)
			expect(p.apPerWeek >= 1 and p.debatePrep >= 1 and p.mediaCost >= 1):toBe(true)
		end
	end)

	it("no debate stat exceeds another by more than the allowed gap", function()
		local lo, hi = math.huge, -math.huge
		for _, id in Candidates.ids do
			local stat = Candidates.profile(C, id).debateStat
			lo, hi = math.min(lo, stat), math.max(hi, stat)
		end
		expect(hi - lo <= C.DEBATE_MAX_STAT_GAP):toBe(true)
	end)

	it("applies the roster overrides (revision 2 as retuned in D-022, D-023, D-037)", function()
		expect(Candidates.profile(C, "calloway").apPerWeek):toBe(4)
		expect(Candidates.profile(C, "calloway").rallySupport):toBe(2.3)
		expect(Candidates.profile(C, "hale").debateStat):toBe(C.DEBATE_STAT) -- D-023: prep, not stat
		expect(Candidates.profile(C, "hale").debatePrep):toBe(7) -- 8 -> 7 in D-037: debates matter now
		expect(Candidates.profile(C, "hale").startCash):toBe(0)
		expect(Candidates.profile(C, "venkat").debateStat):toBe(C.DEBATE_STAT) -- D-023: income, not stat
		expect(Candidates.profile(C, "venkat").passiveIncome):toBe(2) -- 3 -> 2 in D-037
		expect(Candidates.profile(C, "venkat").mediaSaturation):toBe(0.65)
		expect(Candidates.profile(C, "okafor").rallyMult):toBe(1)
		expect(Candidates.profile(C, "okafor").fundraiseMult):toBe(1.25) -- 1.5 -> 1.25 in D-037: money counts now
		expect(Candidates.profile(C, "alvarado").startCash):toBe(20)
		expect(Candidates.profile(C, "alvarado").passiveIncome):toBe(3.75)
		expect(Candidates.profile(C, "reyes").momentumGainMult):toBe(1.65)
		expect(Candidates.profile(C, "strand").mediaMult):toBe(0.9) -- 0.85 -> 0.9 in D-037
		expect(Candidates.profile(C, "strand").freePolls):toBe(2)
		expect(Candidates.profile(C, "strand").eventPreview):toBe(1) -- D-035: sees next week's event
		expect(Candidates.profile(C, "okafor").eventPreview):toBe(0)
		expect(Candidates.profile(C, "begay").rallySupport):toBe(2.9)
		expect(Candidates.profile(C, "begay").gotvCost):toBe(1)
		expect(Candidates.profile(C, "reyes").momentumDecay):toBe(0.25)
		expect(Candidates.profile(C, "reyes").frontrunnerEV):toBe(40)
		expect(Candidates.profile(C, "okafor").frontrunnerEV):toBe(nil)
	end)

	it("profiles follow config variants", function()
		local variant = Config.with(C, { AP_PER_WEEK = 2 })
		expect(Candidates.profile(variant, "okafor").apPerWeek):toBe(2)
	end)
end)
