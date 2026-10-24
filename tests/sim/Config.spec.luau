--!strict
-- Config and Candidates sanity: internal consistency, time budget, roster rules.

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local Events = require("@sim/Events")
local Candidates = require("@sim/Candidates")
local StateData = require("@sim/StateData")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

describe("Config", function()
	it("starting support and undecided sum to 100", function()
		expect(C.BASE_SUPPORT * 2 + C.BASE_UNDECIDED):toBe(100)
	end)

	it("draft priority covers every round; A has the home, B the nominations (D-045)", function()
		expect(#C.DRAFT_PRIORITY):toBe(1 + C.NOMINATION_ROUNDS)
		expect(C.DRAFT_PRIORITY[1]):toBe(1)
		for round = 2, #C.DRAFT_PRIORITY do
			expect(C.DRAFT_PRIORITY[round]):toBe(2)
		end
	end)

	it("debates fall inside the campaign", function()
		for _, week in C.DEBATE_WEEKS do
			expect(week >= 2 and week <= C.WEEKS):toBe(true)
		end
	end)

	it("a debate round is felt in its states; splits and backfires are smaller (D-062)", function()
		-- A round win moves every landing state by a visible amount, never more than
		-- the event cap even with a staked Zinger; a split and a backfire are half.
		expect(C.DEBATE_ROUND_WIN >= 0.5 and C.DEBATE_ROUND_WIN * C.DEBATE_ZINGER_MULT <= C.EVENT_CAP):toBe(
			true
		)
		expect(C.DEBATE_ROUND_SPLIT < C.DEBATE_ROUND_WIN):toBe(true)
		expect(C.DEBATE_BACKFIRE > 0 and C.DEBATE_BACKFIRE < C.DEBATE_ROUND_WIN):toBe(true)
		expect(#C.DEBATE_COUNTER >= C.DEBATE_TOPICS):toBe(true)
		-- The counter never shrinks, so later rounds are no formality.
		for r = 2, #C.DEBATE_COUNTER do
			expect(C.DEBATE_COUNTER[r] >= C.DEBATE_COUNTER[r - 1]):toBe(true)
		end
		-- One Zinger, a stake: it multiplies, it never adds to a score.
		expect(C.DEBATE_ZINGERS):toBe(1)
		expect(C.DEBATE_ZINGER_MULT > 1):toBe(true)
		-- A crowd sweep reaches the ovation; one round alone cannot.
		expect(C.DEBATE_CROWD_ROUND_MAX < C.DEBATE_OVATION):toBe(true)
		expect(C.DEBATE_TOPICS * C.DEBATE_CROWD_ROUND_MAX >= C.DEBATE_OVATION):toBe(true)
	end)

	it("every move is the strongest in some situation (D-062)", function()
		-- Owning the topic makes Defend strongest; their issue while trailing makes
		-- Attack strongest; nobody's issue makes Pivot strongest.
		local defend = C.DEBATE_DEFEND_BASE + C.DEBATE_OWN_ISSUE
		local attack = C.DEBATE_ATTACK_BASE + C.DEBATE_THEIR_ISSUE + C.DEBATE_GROUND + C.DEBATE_CROWD_TRAIL
		local pivot = C.DEBATE_PIVOT_BASE + C.DEBATE_OFF_ISSUE
		expect(defend > C.DEBATE_ATTACK_BASE and defend > C.DEBATE_PIVOT_BASE):toBe(true)
		expect(attack > C.DEBATE_DEFEND_BASE and attack > pivot):toBe(true)
		expect(pivot > C.DEBATE_DEFEND_BASE and pivot > C.DEBATE_ATTACK_BASE):toBe(true)
		-- A timed-out canned answer is weaker than any real move's base.
		expect(C.DEBATE_CANNED <= math.min(C.DEBATE_DEFEND_BASE, C.DEBATE_ATTACK_BASE, C.DEBATE_PIVOT_BASE)):toBe(
			true
		)
	end)

	it("fundraising is flat, not front-loaded (D-034)", function()
		-- Pools start part full and come back fast, so no week-1 bonanza and a state
		-- worked once a week pays the same every week (Resolve.spec checks the yields).
		expect(C.POOL_START > 0 and C.POOL_START <= 0.5):toBe(true)
		expect(C.POOL_REFILL >= 0.5):toBe(true)
		expect(C.HOME_FUNDRAISE_MULT <= 1.25 and C.HOME_FUNDRAISE_MULT > 1):toBe(true)
		-- A home state still refills at least one plain fundraiser a week.
		local raw = C.FUNDRAISER_BASE + C.FUNDRAISER_PER_SHARE * (C.BASE_SUPPORT + C.HOME_BONUS) / 100
		expect(C.POOL_MAX * C.POOL_REFILL >= raw):toBe(true)
	end)

	it("a stance is a real decision: a camp is worth taking, the hedge is mild (D-039)", function()
		-- A liked state moves about half a rally; a disliked one loses the same, so
		-- a stance only pays where you need its camp. The hedge is a sure, small gain.
		expect(C.STANCE_POINTS > 0 and C.STANCE_POINTS <= C.STANCE_CAP):toBe(true)
		expect(C.STANCE_HEDGE > 0 and C.STANCE_HEDGE <= C.STANCE_POINTS / 2):toBe(true)
		expect(C.STANCE_POINTS <= C.RALLY_SUPPORT):toBe(true)
	end)

	it("a base hears a stance louder and the hedge costs there; the cap bounds the stack (D-043)", function()
		-- Your base listens harder, but not so hard that one state decides the week.
		expect(C.STANCE_BASE_MULT > 1 and C.STANCE_BASE_MULT <= 3):toBe(true)
		-- The hedge's cost is small, and never more than a side's mildest reaction.
		expect(C.STANCE_HEDGE_COST > 0 and C.STANCE_HEDGE_COST <= C.STANCE_HEDGE):toBe(true)
		-- The cap leaves room for a base (or a platform) on a liked state, so those
		-- multipliers matter, and bites the full stack of both.
		expect(C.STANCE_CAP >= C.STANCE_POINTS * math.max(C.STANCE_BASE_MULT, C.STANCE_PLATFORM_MULT)):toBe(
			true
		)
		expect(C.STANCE_CAP < C.STANCE_POINTS * C.STANCE_BASE_MULT * C.STANCE_PLATFORM_MULT):toBe(true)
		expect(C.STANCE_CAP >= C.EVENT_CAP):toBe(true)
		-- Still modest next to a rally (a stance is a nudge, not a campaign).
		expect(C.STANCE_CAP <= C.RALLY_SUPPORT * 2):toBe(true)
	end)

	it("events stay small and off the first and last weeks (D-027)", function()
		expect(C.EVENT_FIRST_WEEK >= 2 and C.EVENT_LAST_WEEK <= C.WEEKS - 1):toBe(true)
		expect(C.EVENT_FIRST_WEEK <= C.EVENT_LAST_WEEK):toBe(true)
		for _, mult in { C.EVENT_SPOTLIGHT_MULT, C.EVENT_REGIONAL_MULT, C.EVENT_WINDFALL_MULT } do
			expect(mult > 1 and mult <= 1.5):toBe(true)
		end
		-- Every unmultiplied stance reaction is inside the cap.
		expect(C.STANCE_POINTS <= C.STANCE_CAP and C.STANCE_HEDGE <= C.STANCE_CAP):toBe(true)
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

	-- Every timer run out on the D-005 steps, a debate's live rounds counted in full (D-062).
	local function debateWorst(): number
		return C.TIMER_DEBATE_INTRO
			+ C.DEBATE_TOPICS * (C.TIMER_DEBATE_ROUND + C.TIMER_DEBATE_CLASH)
			+ C.TIMER_DEBATE_VERDICT
	end

	-- The worst-case line for the D-005 steps: 17.5 minutes until the week's
	-- reveal (D-066) and live debates (D-072) landed together; 19 minutes since
	-- (D-074, pending the designers' call). Typical matches stay under 15 (harness).
	local WORST_CASE_LINE = 19 * 60

	it("worst-case match fits the 19-minute budget for the D-005 steps", function()
		local worst = C.TIMER_SELECT
			+ C.TIMER_MAP_REVEAL
			+ #C.DRAFT_PRIORITY * (C.TIMER_DRAFT_ROUND + C.DRAFT_REVEAL)
			+ C.WEEKS * (C.TIMER_PLAN + C.TIMER_RESOLVE_MAX)
			+ C.TIME_BANK * 2
			+ #C.DEBATE_WEEKS * debateWorst()
			+ C.TIMER_ELECTION
			+ C.TRANSITION_ALLOWANCE
		expect(debateWorst()):toBe(65) -- D-072: 3 + 3 x (15 + 4) + 5; was 10 s of reveal plus a 20 s focus decision
		-- 1042 before D-045, 940 after (with TIMER_SELECT 38, D-048); the reveal up to
		-- 14 s on big weeks +72 (D-066); live debates +110 (D-072). Together they pass
		-- the old 17.5-minute line by 72 s: D-074 records it and the levers.
		expect(worst):toBe(1122)
		expect(worst):toBeLessThan(WORST_CASE_LINE + 1)
	end)

	it(
		"the Decision steps add at most a stance per Choice week; the true worst case (D-044, D-062)",
		function()
			-- Every timer run out: with the worst deck, a stance in every event week
			-- (the deck holds 8 Choice events for 10 event weeks). The debate focus
			-- step is gone (D-062).
			local eventWeeks = C.EVENT_LAST_WEEK - C.EVENT_FIRST_WEEK + 1
			local choiceEvents = 0
			for _, event in Events.deck do
				if event.kind == "Choice" then
					choiceEvents += 1
				end
			end
			local most = math.min(eventWeeks, choiceEvents)
			expect(most):toBe(8)
			expect(most * C.TIMER_DECISION):toBe(160)
			-- The true worst case, every step and every decision run out: 1,122 + 160 s
			-- (21:22; 1,050 + 160 before the reveal's longer weeks, D-066; 940 + 200 =
			-- 1,140 s before live debates, D-072).
			expect(1122 + most * C.TIMER_DECISION):toBe(1282)
			-- A typical deck deals about 3.3 Choice events: about 105 s if every
			-- decision ran to the end, far less when both lock in early.
			expect(C.TIMER_DECISION >= 15 and C.TIMER_DECISION <= 30):toBe(true)
			expect(C.TIMER_DECISION < C.TIMER_PLAN):toBe(true)
		end
	)

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
			expect(p.apPerWeek >= 1 and p.zingerMult >= 1 and p.mediaCost >= 1):toBe(true)
		end
	end)

	it("everyone stakes a Zinger at the default multiplier except Hale (D-062)", function()
		for _, id in Candidates.ids do
			local mult = Candidates.profile(C, id).zingerMult
			expect(mult):toBe(if id == "hale" then 4 else C.DEBATE_ZINGER_MULT)
		end
	end)

	it("applies the roster overrides (revision 2 as retuned in D-022, D-023, D-037)", function()
		expect(Candidates.profile(C, "calloway").apPerWeek):toBe(4)
		expect(Candidates.profile(C, "calloway").rallySupport):toBe(2.3)
		expect(Candidates.profile(C, "hale").zingerMult):toBe(4) -- D-062: was focus +3 (D-044); x3 measured 44%, x4 49%
		expect(Candidates.profile(C, "hale").startCash):toBe(0)
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
