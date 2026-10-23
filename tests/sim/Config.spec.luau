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

	-- Chance that a score edge of `edge` wins, ties and loses a topic against the
	-- uniform 0..DEBATE_ROLL_MAX roll each side adds.
	local function topicOdds(edge: number): (number, number, number)
		local win, tie, lose = 0, 0, 0
		for a = 0, C.DEBATE_ROLL_MAX do
			for b = 0, C.DEBATE_ROLL_MAX do
				local d = edge + a - b
				if d > 0 then
					win += 1
				elseif d == 0 then
					tie += 1
				else
					lose += 1
				end
			end
		end
		local n = (C.DEBATE_ROLL_MAX + 1) ^ 2
		return win / n, tie / n, lose / n
	end

	it("a topic win is felt in its states; the flat part and a sweep are small (D-040)", function()
		-- A topic win moves every state where the topic is a top issue by a visible
		-- amount (about a third of a rally), never more than the event cap; the flat
		-- national part is a nudge, so debates decide the states they are about.
		expect(C.DEBATE_TOPIC_WIN >= 1 and C.DEBATE_TOPIC_WIN <= C.EVENT_CAP):toBe(true)
		expect(C.DEBATE_TOPIC_NATIONAL > 0 and C.DEBATE_TOPIC_NATIONAL <= 0.3):toBe(true)
		expect(C.DEBATE_SWEEP > 0 and C.DEBATE_SWEEP <= 0.5):toBe(true)
		expect(C.DEBATE_GAFFE > 0 and C.DEBATE_GAFFE <= C.DEBATE_TOPIC_WIN):toBe(true)
	end)

	it(
		"the focus decides its topic often, not always; Hale's bigger focus more often (D-033, D-044)",
		function()
			local win, _, lose = topicOdds(C.DEBATE_FOCUS)
			expect(win >= 0.6 and win < 0.95):toBe(true)
			expect(lose <= 0.2):toBe(true)
			local hale = Candidates.profile(C, "hale").focusEdge
			expect(hale > C.DEBATE_FOCUS):toBe(true)
			expect((topicOdds(hale)) > win):toBe(true)
			local win4 = topicOdds(4)
			expect(win4 >= 0.99):toBe(true)
			-- The roll still matters: a one-point edge is a nudge, not a lock.
			local win1 = topicOdds(1)
			expect(win1 <= 0.7):toBe(true)
			expect(C.DEBATE_ROLL_MAX >= C.DEBATE_PLATFORM_BONUS):toBe(true)
		end
	)

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

	it(
		"the Decision steps add at most a debate focus per debate and a stance per Choice week (D-044)",
		function()
			-- Every timer run out: two focus steps and, with the worst deck, a stance in
			-- every event week (the deck holds 8 Choice events for 10 event weeks).
			local eventWeeks = C.EVENT_LAST_WEEK - C.EVENT_FIRST_WEEK + 1
			local choiceEvents = 0
			for _, event in Events.deck do
				if event.kind == "Choice" then
					choiceEvents += 1
				end
			end
			local most = #C.DEBATE_WEEKS + math.min(eventWeeks, choiceEvents)
			expect(most):toBe(10)
			expect(most * C.TIMER_DECISION):toBe(200)
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
			expect(p.apPerWeek >= 1 and p.focusEdge >= 1 and p.mediaCost >= 1):toBe(true)
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
		expect(Candidates.profile(C, "hale").focusEdge):toBe(C.DEBATE_FOCUS + 1) -- D-044: was 7 prep points of 6
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
