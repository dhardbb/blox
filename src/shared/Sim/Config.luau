--!strict
-- Every gameplay tunable, one line comment each. Money is in $ millions, support in
-- percentage points, times in seconds. Starting values come from docs/PLAN.md
-- (revision 2); every change needs a line in docs/DESIGN.md saying why.
--
-- The simulation takes a Config as a parameter, so the balance harness can run
-- variants (see Config.with). Game code uses the frozen defaults returned here.

local Config = {
	-- Match shape
	WEEKS = 12, -- campaign weeks
	DEBATE_WEEKS = { 4, 9 }, -- debates resolve at the start of these weeks
	EV_TO_WIN = 270, -- electoral votes needed
	PLATFORM_SIZE = 3, -- issues each player picks out of eight

	-- Resources
	AP_PER_WEEK = 3, -- action points, use or lose
	START_CASH = 8, -- starting money
	PASSIVE_INCOME = 4, -- flat income per week (underdog cash cut, D-006)
	OPPONENT_MONEY_LOW = 4, -- opponent's cash shown as Low below this
	OPPONENT_MONEY_HIGH = 10, -- and High above this; Medium in between

	-- Support model
	BASE_SUPPORT = 35, -- each player's starting support in every state
	BASE_UNDECIDED = 30, -- starting undecided share
	SUPPORT_CAP = 72, -- saturation ceiling for one player's support
	SATURATION_FLOOR = 0.15, -- minimum gain multiplier near the cap
	GAIN_FROM_UNDECIDED = 0.7, -- share of a positive gain taken from undecided (rest from opponents)
	UNDECIDED_FLOOR = 10, -- below this undecided, gains come entirely from opponents
	ATTACK_TO_UNDECIDED = 0.6, -- share of an attack's loss that goes to undecided (rest to attacker)

	-- Leans (D-008)
	LEAN_STATE_COUNT = 30, -- states that get a seeded lean each match
	LEAN_MIN = 2, -- smallest lean, points of margin
	LEAN_MAX = 6, -- largest lean
	LEAN_BIG_STATE_CAP = 3, -- largest lean for a big state
	LEAN_MAX_EV_IMBALANCE = 15, -- reroll if |sum of EV x lean| exceeds this

	-- Draft (D-007, D-009)
	BIG_STATE_EV = 20, -- states at or above this EV get reduced draft bonuses and leans
	HOME_BONUS = 12, -- support added in the home state
	HOME_BONUS_BIG = 6, -- home bonus in a big state
	HOME_FUNDRAISE_MULT = 1.25, -- fundraiser yield multiplier at home, all game (1.5 -> 1.25 in D-034: home funding was the whole economy)
	STRONGHOLD_BONUS = 8, -- support added in a stronghold
	STRONGHOLD_BONUS_BIG = 4, -- stronghold bonus in a big state
	STRONGHOLD_ROUNDS = 5, -- draft rounds 1-5 pick strongholds
	NOMINATION_ROUNDS = 2, -- draft rounds 6-7 nominate battlegrounds
	DRAFT_PRIORITY = { 1, 2, 2, 1, 2, 1, 1, 2 }, -- clash priority by round (player slot), Thue-Morse
	BATTLEGROUND_MULT = 1.5, -- multiplier on every campaign effect in a battleground

	-- Actions
	RALLY_SUPPORT = 3.0, -- base support from a rally
	RALLY_MOMENTUM = 2, -- momentum from a rally
	FLIGHT_COST = 2, -- money for a non-adjacent hop on the route
	FUNDRAISER_BASE = 2, -- fundraiser yield before support share
	FUNDRAISER_PER_SHARE = 6, -- extra yield x (your support / 100)
	POOL_BASE = 6, -- state fundraising pool capacity: base
	POOL_PER_MILLION = 0.25, -- plus this per million population
	POOL_MAX = 12, -- capped so no state funds three fundraisers in one week (D-012, D-015)
	POOL_START = 0.5, -- share of capacity a pool holds when the match starts (D-034: no week-1 bonanza)
	POOL_REFILL = 0.5, -- share of capacity refilled each week (0.25 -> 0.5 in D-034: a state worked weekly pays the same every week)
	MEDIA_COST = 3, -- money per media buy
	MEDIA_SUPPORT = 1.6, -- base support from a media buy
	MEDIA_MOMENTUM = 1, -- momentum from a positive media buy
	MEDIA_SATURATION = 0.6, -- each extra buy in the same state and week is worth this much of the previous
	ATTACK_LOSS = 1.6, -- base support an attack removes from the opponent
	ATTACK_MOMENTUM = 0, -- attacks earn no momentum (D-004)
	BACKLASH_THRESHOLD = 3, -- backlash meter level at which attacks start costing you
	BACKLASH_PENALTY = 0.8, -- your support lost per attack at or over the threshold
	BACKLASH_DECAY = 1, -- backlash meter decay per week
	INTERNAL_POLL_COST = 1, -- money per single-state internal poll
	REGION_POLL_COST = 3, -- money for an internal poll of a whole region
	INTERNAL_POLL_ERROR = 1, -- internal polls are within +/- this of the truth
	GOTV_COST = 2.5, -- money per ground-game unit (2 -> 2.5, D-044: $1.33 a point of margin was the cheapest point in the game)
	GOTV_PER_UNIT = 1.5, -- election-day margin per unit (D-003; 1.0 -> 1.5 in D-021 so ground game beats media where it should)
	GOTV_MAX_UNITS = 4, -- units per state per player
	PIVOT_AP = 1, -- AP cost of the once-per-match platform pivot
	PIVOT_PENALTY = 1, -- national support lost on a pivot
	PLAN_MAX_ACTIONS = 40, -- most actions one weekly plan may hold (payload sanity limit)

	-- Issue multipliers
	ISSUE_MULT_BOTH = 1.5, -- issue is in your platform and a state top issue
	ISSUE_MULT_STATE = 1.2, -- state top issue, not in your platform
	ISSUE_MULT_PLATFORM = 1.0, -- in your platform only
	ISSUE_MULT_NEITHER = 0.8, -- neither
	ISSUE_MULT_ATTACK = 1.5, -- attack on a state top issue the opponent's platform lacks

	-- Momentum and drift
	MOMENTUM_DECAY = 0.5, -- share of momentum kept each week
	MOMENTUM_CAP = 6, -- maximum momentum per player per state
	DRIFT_RATE = 0.6, -- support drift per point of momentum lead
	DRIFT_CAP = 3, -- maximum drift per state per week

	-- Polls and election
	POLL_SIGMA = 3, -- spread of public poll error on margin and undecided
	POLL_RHO = 0.7, -- share of last week's poll error that carries over (D-002)
	ELECTION_SIGMA = 2, -- election-day noise on each state's margin

	-- Debates (D-010, D-011)
	DEBATE_TOPICS = 3, -- topics per debate
	DEBATE_PREP = 6, -- default prep points per debate
	DEBATE_MAX_PER_TOPIC = 4, -- prep cap on one topic
	DEBATE_PLATFORM_BONUS = 2, -- score bonus when the topic is in your platform
	DEBATE_ROLL_MAX = 3, -- seeded roll 0..this added to each topic score (2 -> 6 in D-019, 6 -> 3 in D-033: a 2-point prep edge wins 81%, a 1-point edge 62%)
	DEBATE_STAT = 1, -- default debate stat
	DEBATE_MAX_STAT_GAP = 2, -- no candidate's stat may exceed another's by more
	DEBATE_TOPIC_WIN = 1.0, -- support points per topic won, in every state where the topic is a top issue (D-040: debates move states, not a national average; 1.2 sat on the 25% decide line)
	DEBATE_TOPIC_NATIONAL = 0.1, -- flat support points in every state per topic won (the small national part, D-040)
	DEBATE_SWEEP = 0.2, -- flat national points in every state for a 3-0 sweep (D-040)
	DEBATE_SWEEP_MOMENTUM = 2, -- momentum in every battleground for a sweep
	DEBATE_GAFFE = 0.6, -- support points lost in every state where the topic is a top issue, for losing an unprepped topic (D-040)

	-- Anti-snowball (D-006)
	CLOSING_MULT = 1.15, -- rallies and media in the closing weeks
	CLOSING_FROM_WEEK = 10, -- first closing week
	UNDERDOG_EV_1 = 40, -- projected EV deficit for tier 1
	UNDERDOG_EV_2 = 100, -- projected EV deficit for tier 2
	UNDERDOG_FUND_1 = 1.15, -- tier 1 fundraiser multiplier
	UNDERDOG_RALLY_1 = 1.10, -- tier 1 rally multiplier
	UNDERDOG_FUND_2 = 1.25, -- tier 2 fundraiser multiplier
	UNDERDOG_RALLY_2 = 1.20, -- tier 2 rally multiplier
	UNDERDOG_SMOOTHING = 0.4, -- EMA weight on the newest week's projected gap (0.5 -> 0.4, D-020)
	UNDERDOG_HYSTERESIS = 30, -- EV below a threshold before leaving its tier (20 -> 30, D-020)

	-- Events (Phase 5, D-027)
	EVENTS_ENABLED = true, -- draw a weekly event deck (private lobbies may turn it off)
	EVENT_FIRST_WEEK = 2, -- first week with an event (none in week 1)
	EVENT_LAST_WEEK = 11, -- last week with an event (none in week 12)
	EVENT_CAP = 2, -- most an event adds for one player in one state per week (support points; $ for Windfall); Choice payoffs are clamped to +/- this
	EVENT_SPOTLIGHT_MULT = 1.3, -- rallies and positive media on the spotlight issue, every state
	EVENT_REGIONAL_MULT = 1.5, -- rallies in the event's region
	EVENT_WINDFALL_MULT = 1.2, -- fundraisers where the fundraiser trails in the public poll (PLAN 1.5 -> 1.2, D-027: cheap media turned it into a Venkat edge)
	-- Choice events are stances on an issue (D-039). Only states where the event's
	-- issue is a top issue react, by their other top issue: liked +STANCE_POINTS,
	-- disliked -STANCE_POINTS, otherwise +STANCE_HEDGE, all x STANCE_PLATFORM_MULT
	-- for a candidate whose platform carries the issue. A side counts
	-- STANCE_BASE_MULT in the taker's own home and strongholds; the hedge costs
	-- STANCE_HEDGE_COST in those of them that have the issue (D-043).
	STANCE_POINTS = 1.5, -- support points a stance adds (or costs) in a state that likes (dislikes) it
	STANCE_HEDGE = 0.5, -- support points a side gives in an indifferent state where the issue is a top issue (D-041)
	STANCE_HEDGE_COST = 0.5, -- support points the hedge costs in each of your home and strongholds with the issue (was +0.5 everywhere; D-043: the hedge was never wrong)
	STANCE_BASE_MULT = 2, -- a side's reaction in your own home and strongholds (they listen hardest; D-043: makes each player's right answer their own)
	STANCE_CAP = 3, -- most a stance moves one state for one player, either way (was EVENT_CAP 2; D-043)
	STANCE_PLATFORM_MULT = 1.5, -- every reaction in the issue's states is this much stronger when the issue is on your platform (states listen harder; capped at STANCE_CAP)
	STANCE_SPILL = 0.5, -- a state without the issue still moves this much per top issue of its own that a side likes (+) or dislikes (-); the hedge spills nothing (D-041: the stakes that make the stance a skill)

	-- Timers (D-005)
	TIMER_SELECT = 30, -- candidate, color and platform
	TIMER_MAP_REVEAL = 5, -- leans shown before the draft
	TIMER_DRAFT_ROUND = 20, -- per blind draft round
	DRAFT_REVEAL = 2, -- reveal after each draft round
	TIMER_PLAN = 50, -- weekly plan
	TIME_BANK = 30, -- extra plan time per player per match
	TIME_BANK_CHUNK = 15, -- bank is taken in chunks of this size
	TIMER_RESOLVE = 8, -- resolve animation
	TIMER_RESOLVE_SKIPPED = 3, -- resolve when both players tap skip
	TIMER_DEBATE = 10, -- debate sequence
	TIMER_ELECTION = 45, -- election night
	TRANSITION_ALLOWANCE = 10, -- total screen-transition time budgeted per match
	DISCONNECT_GRACE = 30, -- wait before auto-submitting a disconnected player's plan
	RECONNECT_WINDOW = 15, -- seconds a returning player gets to finish a turn already past its deadline
	GRACE_USES = 2, -- grace periods per player per match
	FORFEIT_MISSED_WEEKS = 2, -- consecutive missed weeks that forfeit

	-- Meta
	ELO_K = 32, -- rating K-factor
	ELO_START = 1000, -- starting rating
	ELO_FLOOR = 100, -- ratings never fall below this (D-028)
	MATCHES_PER_SERVER = 10, -- concurrent matches per server (20 players)
}

export type Config = typeof(Config)

-- Returns a frozen copy of `base` with `changes` applied. Unknown keys are an error,
-- so a typo in a harness variant fails loudly instead of being ignored.
local function with(base: Config, changes: { [string]: any }): Config
	local copy = table.clone(base) :: any
	for key, value in changes do
		assert(copy[key] ~= nil, `unknown Config key {key}`)
		copy[key] = value
	end
	return table.freeze(copy)
end

-- Fundraising pool capacity of a state with `pop` million people (D-014).
local function poolCapacity(config: Config, pop: number): number
	return math.min(config.POOL_MAX, config.POOL_BASE + config.POOL_PER_MILLION * pop)
end

for _, value in Config :: any do
	if type(value) == "table" then
		table.freeze(value)
	end
end
local defaults = table.freeze(Config)

return table.freeze({
	defaults = defaults,
	with = with,
	poolCapacity = poolCapacity,
})
