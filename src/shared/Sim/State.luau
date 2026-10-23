--!strict
-- The full simulation state of one match: everything the server knows, hidden
-- parts included. Only View.luau may turn this into something a client sees.
--
-- Per-player values are lists indexed by player index (1..#players), never
-- p1/p2 fields, so nothing assumes exactly two players.

local Candidates = require("./Candidates")
local Rng = require("./Rng")
local StateData = require("./StateData")
local Types = require("../Types")

export type Phase = "Select" | "MapReveal" | "Draft" | "Plan" | "Debate" | "Election" | "Done"

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
	gotv: { number }, -- ground-game units by player, exact at the end of the polled week (D-044: polls reveal ground game)
}

-- The latest ground game a player's own internal polls saw in one state (D-044).
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
	owner: number?, -- player who drafted it as home or stronghold
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
	color: string,
	pickedColor: string, -- the color asked for at Select; differs from color after a clash
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
	debatePrep: { number }?, -- prep for the next debate (hidden until it resolves)
	internalPolls: { InternalPoll }, -- results from last week's plan (private)
	scouted: { Scout }, -- latest ground game each own internal poll saw, one per state, StateData order (private)
	raised: number, -- money raised by fundraisers last week (private)
	card: WeekCard?, -- last week's public actions
}

export type DraftPick = {
	round: number, -- 0-based
	player: number,
	state: string,
	kind: "Home" | "Stronghold" | "Nominate",
}

export type DebateResult = {
	week: number,
	topics: { Types.Issue },
	prep: { { number } }, -- by player, revealed after the debate
	scores: { { number } }, -- [player][topic]
	winners: { number }, -- by topic; 0 = tie
	gaffes: { { boolean } }, -- [player][topic]: lost it with no prep
	national: { number }, -- flat points each player gained in every state (topic wins and a sweep)
	moves: { StateMove }, -- the state-targeted points (topic wins and gaffes), in StateData order
	flips: { PollFlip }, -- states whose public-poll leader changed when the polls were republished after the debate
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
	week: number, -- campaign week, 0 before week 1
	draftRound: number, -- 0-based round while drafting
	priorityA: number, -- player index with clash priority in "A" rounds
	players: { PlayerState },
	states: { StateSim }, -- in StateData.list order
	draftLog: { DraftPick },
	debateTopics: { [number]: { Types.Issue } }, -- by debate week
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
