--!strict
-- The full simulation state of one match: everything the server knows, hidden
-- parts included. Only View.luau may turn this into something a client sees.
--
-- Per-player values are lists indexed by player index (1..#players), never
-- p1/p2 fields, so nothing assumes exactly two players.

local Candidates = require("./Candidates")
local IssueMap = require("./IssueMap")
local Rng = require("./Rng")
local StateData = require("./StateData")
local Types = require("../Types")

export type Phase = "Select" | "MapReveal" | "Draft" | "Decision" | "Plan" | "Debate" | "Election" | "Done"

-- What a Decision phase asks for (D-044): a stance on this week's Choice event,
-- right before the plan. (The debate focus it also asked for is gone: debates are
-- live rounds now, D-062.)
export type DecisionKind = "Stance"

-- A public poll as shown to everyone: whole-number shares that sum to 100.
export type Poll = {
	support: { number }, -- by player index
	undecided: number,
}

-- A private internal poll result (see Polls.internal).
export type InternalPoll = {
	state: string,
	support: { number }, -- true support, within INTERNAL_POLL_ERROR
	undecided: number, -- exact
	momentum: { number }, -- exact, every player
	gotv: { number }, -- ground-game units by player, exact at the end of the polled week (D-049: polls reveal ground game)
}

-- The latest ground game a player's own internal polls saw in one state (D-049).
-- Kept after the poll itself expires, so a reading from week 8 still shows in week 10.
export type Scout = {
	state: string,
	week: number, -- the week whose end the poll measured
	gotv: { number }, -- units by player at that time
}

export type StateSim = {
	id: string,
	ev: number,
	support: { number }, -- true support by player index (hidden)
	undecided: number, -- true undecided (hidden)
	lean: number, -- public lean, points of margin (0 = none)
	leanTo: number?, -- player index the lean favors
	capacity: number, -- fundraising pool capacity
	pool: number, -- money left in the pool (hidden: it reveals yields)
	battleground: boolean,
	owner: number?, -- player whose home or stronghold it is (strongholds are assigned from the leans, D-045)
	isHome: boolean,
	momentum: { number }, -- by player (public)
	backlash: { number }, -- attack backlash meter by player
	gotv: { number }, -- ground-game units by player (hidden from opponents)
	debateShift: { number }, -- support each player gained from debates so far (hidden; harness counterfactual)
	stanceShift: { number }, -- support each player gained from Choice stances so far (hidden; harness counterfactual)
	pollError: { number }, -- persistent public poll error on each share, zero-sum (hidden)
	pollErrorUndecided: number, -- persistent error on undecided (hidden)
	poll: Poll?, -- latest public poll (nil before the first one)
}

-- What one player did last week that everyone may see (the week card).
export type WeekCard = {
	rallies: { { state: string, issue: Types.Issue } },
	fundraisers: { string },
	media: { { state: string, issue: Types.Issue, attack: boolean } },
	pivot: { drop: Types.Issue, add: Types.Issue }?,
	flights: number,
	choice: Types.Choice?, -- stance taken on a Choice event, revealed after the week resolves
}

-- Support points an effect asked for in one state, per player, before the
-- undecided/opponent split (public arithmetic: D-039, D-040).
export type StateMove = {
	state: string,
	points: { number }, -- by player index
}

-- A change of public-poll leader in one state (0 = tied or nobody).
export type PollFlip = {
	state: string,
	from: number,
	to: number,
}

export type PlayerState = {
	id: string, -- opaque id from the server (e.g. a UserId as a string)
	candidate: string,
	color: string, -- claimed in Select by a Color Pass owner, else dealt: red or blue first (D-055, D-061); distinct per player
	colorPass: boolean, -- owns the Color Pass: may claim colors during Select (D-061)
	platform: { Types.Issue },
	profile: Candidates.Profile,
	cash: number, -- exact cash (opponents see only a bracket)
	location: string?, -- state id of the candidate
	home: string?,
	strongholds: { string },
	nominations: { string },
	pivotUsed: boolean,
	lead: number?, -- smoothed projected-EV lead over the best opponent (negative = trailing)
	underdogTier: number, -- 0, 1 or 2
	frontrunner: boolean, -- the candidate's frontrunner drawback is active
	debateMove: DebateInput?, -- this debate round's move (hidden until the round resolves, D-062)
	stance: Types.Choice?, -- stance on this week's Choice event, set in its Decision phase (hidden until the week resolves)
	internalPolls: { InternalPoll }, -- results from last week's plan (private)
	scouted: { Scout }, -- latest ground game each own internal poll saw, one per state, StateData order (private)
	raised: number, -- money raised by fundraisers last week (private)
	card: WeekCard?, -- last week's public actions
}

export type DraftPick = {
	round: number, -- 0-based
	player: number,
	state: string,
	kind: "Home" | "Nominate",
}

-- One player's answer in a debate round (D-062). `canned` marks the timeout
-- default, which only the server sets.
export type DebateInput = {
	move: Types.DebateMove,
	zinger: boolean,
	canned: boolean,
}

-- One finished debate round (D-062): public from its clash on. Every list is by
-- player index.
export type DebateRound = {
	round: number, -- 1-based
	topic: Types.Issue,
	picks: { Types.DebateMove }, -- each player's move (a canned answer is "Defend")
	canned: { boolean }, -- the player timed out (canned answer)
	zingers: { boolean }, -- the player staked its Zinger on this round
	strengths: { number }, -- each move's strength (Debate.board), before the counter
	countered: { boolean }, -- the player's move was countered by another player's
	safe: { boolean }, -- the player had a move that could not lose this round (public arithmetic, before Zingers)
	scores: { number }, -- strength plus the counter bonus
	winner: number, -- 0 = a split (equal top scores)
	margin: number, -- winner's score minus the runner-up's (0 on a split)
	split: { boolean }, -- shared the top score (a split)
	backfire: { boolean }, -- lost to a counter: lost DEBATE_BACKFIRE in its landing states
	mult: number, -- the winner's Zinger multiplier (1 without one)
	landing: { Types.Issue }, -- the issue whose states each player's move lands in (the topic, or the pivot issue)
	crowd: { number }, -- crowd each player gained this round
	moves: { StateMove }, -- the support points the round asked for, per state and player
	flips: { PollFlip }, -- public-poll leader changes when the polls were republished after the round
}

-- The debate in progress (D-062), during its week's Debate phase. Public except
-- each player's pending move, which lives in PlayerState.debateMove.
export type LiveDebate = {
	week: number,
	round: number, -- the round now asking for moves, 1-based
	topics: { Types.Issue },
	crowd: { number }, -- by player
	zingers: { number }, -- Zingers left, by player
	last: { [number]: Types.DebateMove }, -- by player: the move played last round (repeat penalty)
	rounds: { DebateRound },
	leaders: { number }, -- public-poll leader per state (StateData order) when the debate opened, for the whole debate's flips
}

-- A finished debate. Fields up to `flips` keep the shape older readers use: a
-- topic is a round (round t asked about topics[t]).
export type DebateResult = {
	week: number,
	topics: { Types.Issue },
	focus: { number }, -- by player: always 0 since live rounds (D-062; kept for older readers)
	prep: { { number } }, -- [player][topic]: always 0 since live rounds (kept for older readers)
	scores: { { number } }, -- [player][round]: the round's score
	winners: { number }, -- by round; 0 = a split
	gaffes: { { boolean } }, -- [player][round]: lost to a counter (a backfire)
	national: { number }, -- by player: always 0 since live rounds (no flat national part, D-062)
	moves: { StateMove }, -- every round's support points summed, per state and player, in StateData order
	flips: { PollFlip }, -- states whose public-poll leader differs from before the debate
	rounds: { DebateRound }, -- the three rounds in full
	crowd: { number }, -- final crowd by player
	ovation: number, -- the player who won a standing ovation, 0 = none
}

-- A resolved weekly event (D-027, D-039). Public from the end of its week.
export type EventResult = {
	week: number,
	id: string, -- Events.byId key
	choices: { Types.Choice }?, -- Choice events: each player's stance, by player index
	moves: { StateMove }?, -- Choice events: the points each stance asked for, per state and player
	flips: { PollFlip }?, -- Choice events: leader changes projected on the start-of-week public polls
}

export type StateResult = {
	state: string,
	winner: number, -- 0 if an exact tie (no EV awarded)
	margin: number, -- winner's final score minus the runner-up's
}

export type ElectionResult = {
	ev: { number }, -- by player
	statesWon: { number },
	popular: { number }, -- support x population, summed
	winner: number,
	decidedBy: "EV" | "States" | "Popular" | "Coin",
	results: { StateResult }, -- reveal order: safest first, closest last
}

export type MatchState = {
	seed: number,
	rng: Rng.Rng, -- root stream; never advanced, every system forks a labeled child
	phase: Phase,
	decision: DecisionKind?, -- during a Decision phase: what it asks for
	week: number, -- campaign week, 0 before week 1
	draftRound: number, -- 0-based round while drafting
	priorityA: number, -- player index with clash priority in "A" rounds
	players: { PlayerState },
	states: { StateSim }, -- in StateData.list order
	claims: { [string]: number }, -- Select: candidate id -> the player who claimed it (public; unique candidates, D-048)
	claimRounds: number, -- claim batches resolved so far (labels each batch's seeded coin flip)
	colorClaims: { [string]: number }, -- Select: color -> the Color Pass owner who claimed it (public, D-061)
	colorRounds: number, -- color claim batches resolved so far (labels each batch's seeded coin flip)
	issueMap: IssueMap.IssueMap, -- each state's two top issues this match, drawn from the seed (public, D-047)
	platformMults: { [string]: number }, -- rally/ad multiplier on a platform issue where it is a top issue, by issue (public, D-047)
	draftLog: { DraftPick },
	debateTopics: { [number]: { Types.Issue } }, -- by debate week
	debate: LiveDebate?, -- the debate in progress (phase Debate)
	debates: { DebateResult },
	eventDeck: { [number]: string }, -- week -> event id (hidden: only the current week's is shown)
	eventLog: { EventResult }, -- resolved events, oldest first
	election: ElectionResult?,
}

-- Something that happened, for the server to animate. Events with `private` set
-- are visible only to `player`; View.events does the filtering.
export type Event = {
	kind: string,
	player: number?,
	state: string?,
	issue: string?,
	amount: number?,
	private: boolean?,
}

local State = {}

-- State id -> position in MatchState.states (same as StateData.list order).
local indexOf: { [string]: number } = {}
for i, record in StateData.list do
	indexOf[record.id] = i
end
State.indexOf = table.freeze(indexOf)

-- The StateSim for a state id.
function State.get(match: MatchState, id: string): StateSim
	local i = indexOf[id]
	assert(i, `unknown state {id}`)
	return match.states[i]
end

-- Deep copy. Frozen tables (Config, profiles, StateData) are immutable and shared.
local function deepCopy(value: any): any
	if type(value) ~= "table" or table.isfrozen(value) then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

function State.clone(match: MatchState): MatchState
	return deepCopy(match)
end

State.deepCopy = deepCopy

-- Number of players in the match.
function State.count(match: MatchState): number
	return #match.players
end

-- A list of `n` copies of `value`.
function State.fill(n: number, value: number): { number }
	local list = table.create(n, value)
	return list
end

return table.freeze(State)
