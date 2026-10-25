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
	DEBATE_WEEKS = { 4, 9 }, -- a debate opens these weeks, before the plan
	EV_TO_WIN = 270, -- electoral votes needed
	LANDSLIDE_EV_SHARE = 0.70, -- a win with strictly more than this share of all EV is a landslide (538: 377+; D-062)
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

	-- Draft (D-007, D-009, D-045)
	BIG_STATE_EV = 20, -- states at or above this EV get reduced draft bonuses and leans
	HOME_BONUS = 12, -- support added in the home state
	HOME_BONUS_BIG = 6, -- home bonus in a big state
	HOME_FUNDRAISE_MULT = 1.25, -- fundraiser yield multiplier at home, all game (1.5 -> 1.25 in D-034: home funding was the whole economy)
	STRONGHOLD_BONUS = 8, -- support added in a stronghold
	STRONGHOLD_BONUS_BIG = 4, -- stronghold bonus in a big state
	STRONGHOLD_COUNT = 5, -- strongholds each player is given at the map reveal: their strongest-leaning states (D-045; was 5 drafted rounds)
	NOMINATION_ROUNDS = 2, -- draft rounds 1-2 nominate battlegrounds (round 0 is the home state)
	DRAFT_PRIORITY = { 1, 2, 2 }, -- clash priority by round (player slot): A for the home, B for both nominations (Thue-Morse prefix)
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
	INTERNAL_POLL_COST = 0.5, -- money per single-state internal poll (1 -> 0.5, D-063: polls saw little use)
	REGION_POLL_COST = 1.5, -- money for an internal poll of a whole region (3 -> 1.5, D-063)
	INTERNAL_POLL_ERROR = 1, -- internal polls are within +/- this of the truth
	GOTV_COST = 2.5, -- money per ground-game unit (2 -> 2.5, D-049: $1.33 a point of margin was the cheapest point in the game)
	GOTV_PER_UNIT = 1.5, -- election-day margin per unit (D-003; 1.0 -> 1.5 in D-021 so ground game beats media where it should)
	GOTV_MAX_UNITS = 4, -- units per state per player
	PIVOT_AP = 1, -- AP cost of the once-per-match platform pivot
	PIVOT_PENALTY = 1, -- national support lost on a pivot
	PLAN_MAX_ACTIONS = 40, -- most actions one weekly plan may hold (payload sanity limit)

	-- Issue multipliers
	ISSUE_MULT_BOTH = 1.5, -- issue is in your platform and a state top issue, for an issue covering the mean EV (134.5); see ISSUE_NICHE_POWER
	ISSUE_MULT_STATE = 1.2, -- state top issue, not in your platform
	ISSUE_NICHE_POWER = 2.5, -- niche issues hit harder (D-047): the platform bonus over ISSUE_MULT_STATE is scaled by (mean EV / the issue's EV)^this; 2.5 makes the 3 biggest and 3 smallest issues win alike (x1.39 at 161 EV, x1.72 at 108)
	ISSUE_NICHE_MAX = 2.0, -- but a platform multiplier never exceeds this
	ISSUE_MULT_PLATFORM = 1.0, -- in your platform only
	ISSUE_MULT_NEITHER = 0.8, -- neither
	ISSUE_MULT_ATTACK = 1.5, -- attack on a state top issue the opponent's platform lacks

	-- Issue map: each state's two top issues are drawn per match from the seed (D-047)
	ISSUE_FLAVOR_WEIGHT = 4, -- a state's regional-flavor issues (StateData) are this many times as likely to be drawn
	ISSUE_EV_BAND = 0.2, -- every issue's total EV ends within +/- this share of the mean (134.5 EV): 108-161, against 106-160 fixed before; niche issues make up the rest (ISSUE_NICHE_POWER)
	ISSUE_MIN_STATES = 9, -- every issue is a top issue in at least this many states
	ISSUE_MAX_STATES = 17, -- and in at most this many
	ISSUE_DRAW_STEPS = 6000, -- seeded swap proposals the balancing search may try (it stops as soon as the map is in band)

	-- Momentum and drift
	MOMENTUM_DECAY = 0.5, -- share of momentum kept each week
	MOMENTUM_CAP = 6, -- maximum momentum per player per state
	DRIFT_RATE = 0.6, -- support drift per point of momentum lead
	DRIFT_CAP = 3, -- maximum drift per state per week

	-- Polls and election
	POLL_SIGMA = 3, -- spread of public poll error on margin and undecided
	POLL_RHO = 0.7, -- share of last week's poll error that carries over (D-002)
	ELECTION_SIGMA = 2, -- election-day noise on each state's margin

	-- Debates: three live rounds, one per topic (D-072). Each player picks Defend,
	-- Attack or Pivot; a move's strength is public arithmetic (Debate.board), the
	-- move that counters the other's gets DEBATE_COUNTER, the higher score wins.
	DEBATE_TOPICS = 3, -- topics per debate, one round each
	DEBATE_DEFEND_BASE = 2, -- Defend's strength before bonuses
	DEBATE_ATTACK_BASE = 2, -- Attack's strength before bonuses
	DEBATE_PIVOT_BASE = 4, -- Pivot's strength before bonuses (3 in the proposal: then always Defending beat the standard bot, 52%)
	DEBATE_OWN_ISSUE = 3, -- Defend: the topic is on your platform (4 in the first proposal pre-decided too many rounds)
	DEBATE_THEIR_ISSUE = 2, -- Attack: the topic is on an opponent's platform (their record to attack)
	DEBATE_OFF_ISSUE = 1, -- Pivot: the topic is not on your platform (somewhere better to go)
	DEBATE_GROUND = 1, -- Defend if you lead the topic's states (by EV led in the public poll), Attack if you trail them
	DEBATE_CROWD_TRAIL = 2, -- Attack: you trail the crowd meter (swing for the fences)
	DEBATE_COUNTER = { 2, 3, 3 }, -- by round: added to the move that counters the other's (Defend > Attack > Pivot > Defend); grows so later rounds are not a formality
	DEBATE_REPEAT = 2, -- taken off the move you played last round in this debate (the crowd saw it coming)
	DEBATE_ZINGERS = 1, -- Zingers per debate: stake one on a round
	DEBATE_ZINGER_MULT = 2, -- a staked round you win moves the map and the crowd this many times as much (Hale's profile has 4)
	DEBATE_CANNED = 2, -- a timed-out answer: Defend at this flat strength, never countered and never countering
	DEBATE_CANNED_CROWD = 1, -- most crowd a round won against a canned answer gains
	DEBATE_ROUND_WIN = 0.8, -- support points for the round's winner in each of its landing states (the topic's, or its pivot issue's); 1.0 had debates decide 26% of matches (target 15-25%)
	DEBATE_ROUND_SPLIT = 0.5, -- support points each tied player gets in its own landing states on an equal score
	DEBATE_BACKFIRE = 0.5, -- support points a player who lost to a counter loses in its own landing states
	DEBATE_CROWD_ROUND_MAX = 4, -- most crowd a won round gains before the Zinger (the round's margin, capped)
	DEBATE_OVATION = 8, -- a final crowd lead of at least this is a standing ovation
	DEBATE_OVATION_MOMENTUM = 2, -- momentum a standing ovation adds in every battleground (the old sweep's)
	DEBATE_PIVOT_CLOSE = 5, -- a Pivot lands on the platform issue whose states within this many poll points either way hold the most EV

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
	EVENT_CHOICE_ONLY = false, -- deal only Choice events into those weeks (the tutorial's one stance week, D-080)
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
	TIMER_SELECT = 38, -- two steps: claim a candidate, then pick the platform (30 -> 38, D-048: the most the 17.5-minute worst case allows; colors are dealt, D-047, D-055)
	TIMER_MAP_REVEAL = 5, -- leans shown before the draft
	TIMER_DRAFT_ROUND = 20, -- per blind draft round
	DRAFT_REVEAL = 2, -- reveal after each draft round
	TIMER_PLAN = 50, -- weekly plan
	TIMER_DECISION = 20, -- the debate focus or a Choice stance, each on its own screen before the plan (D-044: one pick, so well under TIMER_PLAN)
	TIME_BANK = 30, -- extra plan time per player per match
	TIME_BANK_CHUNK = 15, -- bank is taken in chunks of this size
	TIMER_RESOLVE = 8, -- resolve animation, the shortest (D-066: longer on weeks with more moves to show)
	TIMER_RESOLVE_BASE = 4.5, -- resolve animation: fixed part (intro, the new polls, What changed) before the per-step time (D-066)
	TIMER_RESOLVE_PER_STEP = 0.55, -- resolve animation: seconds per reveal step, so each move is seen to land (D-066)
	TIMER_RESOLVE_MAX = 14, -- resolve animation, the longest (D-066)
	TIMER_RESOLVE_SKIPPED = 3, -- resolve when both players tap skip
	TIMER_DEBATE_INTRO = 3, -- the debate stage before round 1 (D-072)
	TIMER_DEBATE_ROUND = 15, -- one debate round: pick a move (D-072; both locked in ends it)
	TIMER_DEBATE_CLASH = 4, -- the clash after each debate round
	TIMER_DEBATE_VERDICT = 5, -- the debate's verdict after round 3 (skippable)
	TIMER_ELECTION = 45, -- election night
	TRANSITION_ALLOWANCE = 10, -- total screen-transition time budgeted per match
	DISCONNECT_GRACE = 30, -- wait before auto-submitting a disconnected player's plan
	RECONNECT_WINDOW = 15, -- seconds a returning player gets to finish a turn already past its deadline
	GRACE_USES = 2, -- grace periods per player per match
	FORFEIT_MISSED_WEEKS = 2, -- consecutive missed weeks that forfeit
	-- Bot matches (D-075): every choice timer (Select, a draft round, a decision,
	-- a debate round, the plan) is multiplied by the bot's level; Hard and Extreme
	-- keep x1. Reveals, clashes, election night and the time bank are not scaled.
	-- The tutorial (a player's first bot match, or a replay) has no choice timer at all.
	BOT_TIME_MULT_EASY = 2, -- choice timers against an Easy bot (the designers' number)
	BOT_TIME_MULT_MEDIUM = 1.5, -- choice timers against a Medium bot (the designers' number)
	-- The Daily Race (D-082): one seeded race a UTC day, the same for everyone.
	DAILY_BOT_LEVEL = "Hard", -- the bot's level in every Daily Race, so its timers are Hard's x1
	DAILY_FORFEIT_MARGIN = -538, -- the score of a counted run left or abandoned after week 1 began: every vote lost
	-- The idle-money coach tip (D-086): a UI threshold, not a rule; nothing in Sim reads it.
	IDLE_CASH_TIP = 20, -- money at or above which a plan that spends none gets the one-time "ads and ground game cost money, not actions" tip
	IDLE_CASH_TIP_WEEK = 3, -- the first week that tip may show (weeks 1-2 have their own tips)
	-- Key states (D-088): a learning aid on the campaign map, read only by UI/KeyStates
	-- from the player's own public polls; nothing in Sim or Bot reads them.
	KEY_STATES = 3, -- most key states highlighted a week: the tipping state and the biggest states polling near it
	KEY_STATE_BAND = 10, -- points: a state is key when its public-poll margin is within this of the tipping state's

	-- The tutorial (D-075, D-080): a player's first bot match, or a replay from How
	-- to play. The same rules on a short schedule: Config.tutorial(config) puts
	-- each of these over the key it names; a normal match never reads them.
	TUTORIAL_WEEKS = 4, -- campaign weeks (WEEKS): one week each to learn the plan, a stance, a debate and the last push
	TUTORIAL_CHOICE_WEEK = 2, -- the tutorial's one event, a Choice stance, is this week (EVENT_FIRST_WEEK = EVENT_LAST_WEEK, EVENT_CHOICE_ONLY)
	TUTORIAL_DEBATE_WEEKS = { 3 }, -- its one live debate, three rounds (DEBATE_WEEKS)
	TUTORIAL_CLOSING_FROM_WEEK = 4, -- the closing bonus on rallies and ads in its last week (CLOSING_FROM_WEEK)
	TUTORIAL_START_CASH = 8, -- starting money (START_CASH)

	-- Practice bot difficulty (D-057). Medium is the standard (balance harness) bot
	-- and reads none of these. Every level decides from its own View only.
	BOT_EASY_NOISE = 0.45, -- Easy: spread (log scale) of a random weight on each state's worth, redrawn every plan
	BOT_EASY_SLIP = 0.5, -- Easy: chance a debate move or a Choice stance is picked at random
	BOT_HARD_WIN_CHANCE = 1, -- Hard: how far state worth follows the chance of reaching 270 rather than expected EV (0 = Medium's worth)
	BOT_HARD_FORESIGHT = 1, -- Hard: share of the opponent's predicted plan counted against this week's margins
	BOT_EXTREME_WIN_CHANCE = 3, -- Extreme: the same, pushed further (defends harder when ahead, reaches further when behind)
	BOT_EXTREME_FORESIGHT = 1, -- Extreme: share of the opponent's predicted plan counted against this week's margins
	BOT_FORESIGHT_CASH = { 2, 7, 13 }, -- Hard and up: the opponent's cash guessed from its Low / Medium / High money bracket
	BOT_DEBATE_READ = 0.15, -- Hard and up: weight on the opponent playing the debate move the standard bot would (rest spread evenly); 0.5 read Medium so well that Hard won 86%
	BOT_EXTREME_HISTORY = 0.5, -- Extreme: share of that prediction taken from the opponent's own past debate moves this match

	-- Custom candidate names (the Name Pass, D-069). Not rules: who may name a
	-- candidate, and how long a name may be.
	NAME_MAX_LENGTH = 16, -- characters in a custom name, after trimming (the "16" the designers asked for)
	NAME_SIMILAR_DISTANCE = 1, -- a name within this many letter edits of a blocklist entry counts as that entry (D-069)
	NAME_SIMILAR_MIN_LETTERS = 5, -- shorter blocklist entries must match exactly (one edit away from a short word is too many names)

	-- Reporting and reviewing custom names (D-069).
	NAME_REPORT_WAIT = 10, -- seconds one player waits between reports (rate limit)
	NAME_REPORTS_PER_DAY = 10, -- most reports one player sends in NAME_REPORT_WINDOW, kept in their profile (D-078)
	NAME_REPORT_WINDOW = 86400, -- seconds the report count runs before it starts again (a day)
	NAME_HIDDEN_MAX = 30, -- names a player reported and no longer sees, kept in their profile (oldest dropped)
	NAME_REVIEW_MAX = 200, -- reported names waiting for review (the oldest drop off a full queue)
	NAME_REVIEW_SHARDS = 8, -- DataStore keys the review queue is split over, so one key never limits reports (D-078)
	NAME_REPORTERS_MAX = 20, -- distinct reporters kept per reported name
	NAME_BLOCKLIST_MAX = 2000, -- names reviewers removed, kept as blocklist entries
	NAME_BLOCKLIST_REFRESH = 300, -- seconds between reloads of the reviewed blocklist on each server
	NAME_BLOCKLIST_RETRY = 20, -- seconds between tries while the reviewed blocklist has never loaded (names wait, D-078)
	SET_NAME_COOLDOWN = 2, -- seconds between one player's SetName requests (each may call the text filter)
	SET_COLOR_COOLDOWN = 1, -- seconds between one player's SetColor requests
	SET_TIMERS_OFF_COOLDOWN = 1, -- seconds between one admin's SetTimersOff requests (each writes saved data, D-081)

	-- Admins (D-069): free Color and Name Passes and the name review panel. The
	-- experience owner (game.CreatorId, or for a group-owned game its members of
	-- at least ADMIN_GROUP_RANK) always counts; these user ids count too.
	ADMIN_USER_IDS = {
		5618560436, -- the experience owner (also covered by game.CreatorId)
		479739965, -- "originalyellowboss", the partner
	},
	ADMIN_GROUP_RANK = 255, -- group-owned games: a role of this rank or above makes an admin (255 = the group owner)

	-- Meta
	ELO_K = 32, -- rating K-factor
	ELO_START = 1000, -- starting rating
	ELO_FLOOR = 100, -- ratings never fall below this (D-028)
	RATED_PAIR_DAILY_MAX = 3, -- rated games one pair of players may play in RATED_PAIR_WINDOW; more are unrated (D-077)
	RATED_PAIR_WINDOW = 86400, -- seconds that cap looks back (a day)
	MATCHES_PER_SERVER = 50, -- concurrent matches per server: a full 50-player server can all play the bot at once (D-083)

	-- Matchmaking (D-083)
	QUEUE_BOT_OFFER_SECONDS = 30, -- seconds in the queue before "Play a bot while you wait" is offered
	QUEUE_ACCEPT_SECONDS = 15, -- seconds a player in a bot game has to answer "Opponent found! Leave this bot game?"
	REMATCH_WINDOW_SECONDS = 20, -- seconds after a match against a person in which both may tap Rematch
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

-- The tutorial's config (D-080): `base` on the tutorial's short schedule. Only
-- the keys below change; everything else, EV_TO_WIN included, is `base`'s.
local function tutorial(base: Config): Config
	return with(base, {
		WEEKS = base.TUTORIAL_WEEKS,
		DEBATE_WEEKS = base.TUTORIAL_DEBATE_WEEKS,
		EVENT_FIRST_WEEK = base.TUTORIAL_CHOICE_WEEK,
		EVENT_LAST_WEEK = base.TUTORIAL_CHOICE_WEEK,
		EVENT_CHOICE_ONLY = true,
		CLOSING_FROM_WEEK = base.TUTORIAL_CLOSING_FROM_WEEK,
		START_CASH = base.TUTORIAL_START_CASH,
	})
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
	tutorial = tutorial,
	poolCapacity = poolCapacity,
})
