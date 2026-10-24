--!strict
-- The match state machine: Select -> MapReveal (strongholds assigned, D-045) -> Draft
-- (home, then nominations) -> week n -> ... -> Election -> Done, where a week is
--   [Decision "Focus" -> Debate] -> [Decision "Stance"] -> Plan
-- (the focus only in debate weeks, the stance only in Choice weeks; D-044, Sim/Decision).
--
-- Pure: Match.new(config, seed, playerIds, colorPass?) builds a match; Match.advance(config,
-- match, inputs) returns a new state plus events and never mutates its argument.
-- The server collects one input per player for the current phase (validated with
-- Match.validate); anyone missing gets Match.default, the same thing the server
-- submits when a timer runs out.

local Candidates = require("./Candidates")
local ConfigModule = require("./Config")
local Debate = require("./Debate")
local Decision = require("./Decision")
local Draft = require("./Draft")
local Election = require("./Election")
local Events = require("./Events")
local IssueMap = require("./IssueMap")
local Issues = require("./Issues")
local Leans = require("./Leans")
local Plan = require("./Plan")
local Polls = require("./Polls")
local Resolve = require("./Resolve")
local Rng = require("./Rng")
local State = require("./State")
local StateData = require("./StateData")
local Types = require("../Types")

type Config = ConfigModule.Config
type MatchState = State.MatchState
type Event = State.Event

export type Selection = {
	candidate: string,
	platform: { Types.Issue },
}

local Match = {}

-- The default colors, in the order players without a claimed color are dealt
-- them (D-055): red and blue first, so two players without a claim are always
-- one Crimson and one Cobalt.
Match.DEFAULT_COLORS = table.freeze({ "Crimson", "Cobalt" })

-- A Color Pass owner, as the server passes them to Match.new (D-055, D-061).
-- `favorite` is their saved color (the Lobby's Color sheet), claimed for them
-- as Select opens; nil = no favorite.
export type ColorPass = {
	favorite: string?,
}

-- The color player p has claimed this Select, or nil (D-061).
function Match.colorClaimOf(match: MatchState, p: number): string?
	for color, owner in match.colorClaims do
		if owner == p then
			return color
		end
	end
	return nil
end

-- Deals a color to every player without a claimed color (D-055, D-061): in a
-- seeded seat order, from Crimson and Cobalt (their order a seeded coin flip)
-- and then the other four in a seeded order (fork "colors"), skipping claimed
-- colors. Distinct, and no seat is favored (D-001). The root stream is never
-- advanced, so the same claims always deal the same colors: a player's dealt
-- color changes only when someone claims it. Mutates `match`.
local function dealColors(match: MatchState)
	local n = #match.players
	assert(n <= #Candidates.colors, "more players than colors")
	local taken: { [string]: boolean } = {}
	local open: { number } = {}
	for p, player in match.players do
		local claimed = Match.colorClaimOf(match, p)
		if claimed ~= nil then
			player.color = claimed
			taken[claimed] = true
		else
			table.insert(open, p)
		end
	end

	local deal = Rng.fork(match.rng, "colors")
	local order: { string } = table.clone(Match.DEFAULT_COLORS) :: { string }
	if Rng.nextInt(deal, 1, 2) == 2 then
		order[1], order[2] = order[2], order[1]
	end
	local rest: { string } = {}
	for _, color in Candidates.colors do
		if table.find(Match.DEFAULT_COLORS, color) == nil then
			table.insert(rest, color)
		end
	end
	Rng.shuffle(deal, rest)
	for _, color in rest do
		table.insert(order, color)
	end
	-- Shuffle every seat (claimed or not) so the draw count, and so each open
	-- seat's place in line, never depends on who has claimed.
	local seats: { number } = {}
	for p = 1, n do
		seats[p] = p
	end
	Rng.shuffle(deal, seats)
	local k = 1
	for _, p in seats do
		if table.find(open, p) ~= nil then
			while taken[order[k]] do
				k += 1
			end
			match.players[p].color = order[k]
			taken[order[k]] = true
			k += 1
		end
	end
end

-- Can player p claim `color` now? (true, nil) or (false, reasonCode). Only a
-- Color Pass owner may, during Select, and only a color nobody else holds
-- (D-061). Holding a color already is fine: re-claiming it changes nothing.
function Match.canClaimColor(match: MatchState, p: number, color: any): (boolean, string?)
	if match.phase ~= "Select" then
		return false, "WrongPhase"
	end
	local player = match.players[p]
	if player == nil then
		return false, "UnknownPlayer"
	end
	if not player.colorPass then
		return false, "NoColorPass"
	end
	if type(color) ~= "string" or table.find(Candidates.colors, color) == nil then
		return false, "UnknownColor"
	end
	local owner = match.colorClaims[color]
	if owner ~= nil and owner ~= p then
		return false, "ColorTaken"
	end
	return true, nil
end

-- Settles one batch of color claims in place (see Match.claimColor).
local function settleColorClaims(match: MatchState, requests: { [number]: any }): { [number]: string }
	local outcomes: { [number]: string } = {}
	local order = {}
	for p in match.players do
		if requests[p] ~= nil then
			table.insert(order, p)
		end
	end
	if #order == 0 then
		return outcomes
	end
	Rng.shuffle(Rng.fork(match.rng, `colorClaims:{match.colorRounds}`), order)
	match.colorRounds += 1
	for _, p in order do
		local color = requests[p]
		local ok, reason = Match.canClaimColor(match, p, color)
		if ok then
			-- A new claim releases the old one (a change of mind, D-061).
			local old = Match.colorClaimOf(match, p)
			if old ~= nil then
				match.colorClaims[old] = nil
			end
			match.colorClaims[color] = p
		else
			outcomes[p] = reason or "Rejected"
		end
	end
	dealColors(match)
	return outcomes
end

-- Claims colors during Select (D-061: Color Pass owners pick their color first
-- come, first served, like candidates, D-048). `requests` maps player -> color
-- for one batch of claims that arrived together (the same server step). They
-- are settled in a seeded order, a coin flip that never favors a seat (D-001):
-- the first claim on a free color gets it, a later one on the same color is
-- turned down with "ColorTaken" and the loser keeps their old color (or the
-- one dealt to them) and may claim another. A claim releases the claimant's
-- previous color. Every player without a claim is then dealt a color again,
-- skipping claimed ones. Pure: returns the new state and each request's
-- outcome (nil = claimed, or a reason code); the argument is not modified.
function Match.claimColor(
	_config: Config,
	current: MatchState,
	requests: { [number]: any }
): (MatchState, { [number]: string })
	local match = State.clone(current)
	local outcomes = settleColorClaims(match, requests)
	return match, outcomes
end

-- A new match in the Select phase. Leans, the issue map, colors, debate topics and
-- the event deck are seeded now (the issue map and colors are public from Select,
-- so players pick a platform against this match's map, D-047; leans are shown from
-- MapReveal on; each event only in its own week).
-- `colorPass` (optional, by player id): the Color Pass owners (D-055). They may
-- claim colors during Select, and a favorite is claimed for them now, as Select
-- opens; two owners with the same favorite settle it with the seeded coin flip,
-- and the loser starts without a claim and picks another color (D-061).
-- A private lobby with events off passes Config.with(config, { EVENTS_ENABLED = false }).
function Match.new(
	config: Config,
	seed: number,
	playerIds: { string },
	colorPass: { [string]: ColorPass }?
): MatchState
	local n = #playerIds
	assert(n >= 2, "a match needs at least two players")
	local rng = Rng.new(seed)
	local placeholder = Candidates.ids[1]
	local players: { State.PlayerState } = {}
	for p, id in playerIds do
		players[p] = {
			id = id,
			candidate = placeholder,
			color = "", -- dealt below
			colorPass = colorPass ~= nil and colorPass[id] ~= nil,
			platform = {},
			profile = Candidates.profile(config, placeholder),
			cash = 0,
			location = nil,
			home = nil,
			strongholds = {},
			nominations = {},
			pivotUsed = false,
			lead = nil,
			underdogTier = 0,
			frontrunner = false,
			debateFocus = nil,
			stance = nil,
			internalPolls = {},
			scouted = {},
			raised = 0,
			card = nil,
		}
	end

	local issueMap = IssueMap.draw(config, Rng.fork(rng, "issues"))
	local leans = Leans.generate(config, Rng.fork(rng, "leans"), n)
	local states: { State.StateSim } = {}
	for i, record in StateData.list do
		local capacity = ConfigModule.poolCapacity(config, record.pop)
		states[i] = {
			id = record.id,
			ev = record.ev,
			support = Leans.startingSupport(config, leans[i], n),
			undecided = config.BASE_UNDECIDED,
			lean = leans[i].lean,
			leanTo = leans[i].leanTo,
			capacity = capacity,
			pool = capacity * config.POOL_START,
			battleground = false,
			owner = nil,
			isHome = false,
			momentum = table.create(n, 0),
			backlash = table.create(n, 0),
			gotv = table.create(n, 0),
			debateShift = table.create(n, 0),
			stanceShift = table.create(n, 0),
			pollError = table.create(n, 0),
			pollErrorUndecided = 0,
			poll = nil,
		}
	end

	local match: MatchState = {
		seed = seed,
		rng = rng,
		phase = "Select",
		decision = nil,
		week = 0,
		draftRound = 0,
		priorityA = Rng.nextInt(Rng.fork(rng, "priority"), 1, n),
		players = players,
		states = states,
		claims = {},
		claimRounds = 0,
		colorClaims = {},
		colorRounds = 0,
		issueMap = issueMap,
		platformMults = IssueMap.platformMults(config, issueMap),
		draftLog = {},
		debateTopics = Debate.drawTopics(config, rng),
		debates = {},
		eventDeck = Events.draw(config, rng),
		eventLog = {},
		pollHistory = {},
		election = nil,
	}
	-- Red and blue by default; a Color Pass owner's favorite is claimed as
	-- Select opens, like a PrePick (D-055, D-061). Distinct, deterministic, no
	-- seat favored (D-001).
	local favorites: { [number]: string } = {}
	if colorPass ~= nil then
		for p, id in playerIds do
			local pass = colorPass[id]
			local favorite = if pass ~= nil then pass.favorite else nil
			if type(favorite) == "string" and table.find(Candidates.colors, favorite) ~= nil then
				favorites[p] = favorite
			end
		end
	end
	settleColorClaims(match, favorites)
	dealColors(match)
	return match
end

-- Phases that wait for player input.
function Match.wantsInput(match: MatchState): boolean
	return match.phase == "Select"
		or match.phase == "Draft"
		or match.phase == "Decision"
		or match.phase == "Plan"
end

-- The candidate player p has claimed this Select, or nil.
function Match.claimOf(match: MatchState, p: number): string?
	for candidate, owner in match.claims do
		if owner == p then
			return candidate
		end
	end
	return nil
end

-- Candidates nobody has claimed yet, in Candidates.ids order.
function Match.freeCandidates(match: MatchState): { string }
	local out = {}
	for _, id in Candidates.ids do
		if match.claims[id] == nil then
			table.insert(out, id)
		end
	end
	return out
end

-- Can player p claim `candidate` now? (true, nil) or (false, reasonCode).
function Match.canClaim(match: MatchState, p: number, candidate: any): (boolean, string?)
	if match.phase ~= "Select" then
		return false, "WrongPhase"
	end
	if match.players[p] == nil then
		return false, "UnknownPlayer"
	end
	if type(candidate) ~= "string" or not Candidates.exists(candidate) then
		return false, "UnknownCandidate"
	end
	local owner = match.claims[candidate]
	if owner == p then
		return true, nil
	elseif owner ~= nil then
		return false, "CandidateTaken"
	end
	if Match.claimOf(match, p) ~= nil then
		return false, "AlreadyClaimed"
	end
	return true, nil
end

-- Claims candidates during Select (D-048: two players never share a candidate).
-- `requests` maps player -> candidate for one batch of claims that arrived
-- together (the same server step). They are settled in a seeded order, a coin
-- flip that never favors a seat (D-001): the first claim on a free candidate
-- gets it, a later one on the same candidate is turned down with
-- "CandidateTaken". Pure: returns the new state and each request's outcome
-- (nil = claimed, or a reason code); the argument is not modified.
function Match.claim(
	_config: Config,
	current: MatchState,
	requests: { [number]: any }
): (MatchState, { [number]: string })
	local match = State.clone(current)
	local outcomes: { [number]: string } = {}
	local order = {}
	for p in match.players do
		if requests[p] ~= nil then
			table.insert(order, p)
		end
	end
	if #order == 0 then
		return match, outcomes
	end
	Rng.shuffle(Rng.fork(match.rng, `claims:{match.claimRounds}`), order)
	match.claimRounds += 1
	for _, p in order do
		local candidate = requests[p]
		local ok, reason = Match.canClaim(match, p, candidate)
		if ok then
			match.claims[candidate] = p
		else
			outcomes[p] = reason or "Rejected"
		end
	end
	return match, outcomes
end

local function validateSelection(
	config: Config,
	match: MatchState,
	p: number,
	input: any
): (boolean, string?, Selection?)
	if match.phase ~= "Select" then
		return false, "WrongPhase", nil
	end
	if type(input) ~= "table" then
		return false, "BadShape", nil
	end
	-- Any other field (an old client's `color`) is ignored: colors are claimed
	-- with Match.claimColor or dealt (D-047, D-055, D-061).
	local candidate, platform = input.candidate, input.platform
	if type(candidate) ~= "string" or not Candidates.exists(candidate) then
		return false, "UnknownCandidate", nil
	end
	-- A claimed candidate is yours alone (D-048); with a claim, it is the only one
	-- you may lock in.
	local claimed = Match.claimOf(match, p)
	local owner = match.claims[candidate]
	if (owner ~= nil and owner ~= p) or (claimed ~= nil and claimed ~= candidate) then
		return false, "CandidateTaken", nil
	end
	if type(platform) ~= "table" then
		return false, "BadShape", nil
	end
	local count = 0
	for key in platform do
		if type(key) ~= "number" then
			return false, "BadShape", nil
		end
		count += 1
	end
	if count ~= config.PLATFORM_SIZE or #platform ~= count then
		return false, "BadPlatform", nil
	end
	local issues: { Types.Issue } = {}
	for _, issue in platform do
		if type(issue) ~= "string" or not Issues.isIssue(issue) then
			return false, "UnknownIssue", nil
		end
		if table.find(issues, issue :: Types.Issue) then
			return false, "BadPlatform", nil
		end
		table.insert(issues, issue :: Types.Issue)
	end
	return true, nil, { candidate = candidate, platform = issues }
end

-- Validates player p's input for the current phase. Never throws: returns
-- (true, nil, normalized) or (false, reasonCode, nil).
function Match.validate(config: Config, match: MatchState, p: number, input: any): (boolean, string?, any)
	if type(p) ~= "number" or match.players[p] == nil then
		return false, "UnknownPlayer", nil
	end
	local ok, valid, reason, normalized = pcall(function(): (boolean, string?, any)
		if match.phase == "Select" then
			return validateSelection(config, match, p, input)
		elseif match.phase == "Draft" then
			local draftOk, draftReason, choices = Draft.validate(config, match, p, input)
			return draftOk, draftReason, if choices then { choices = choices } else nil
		elseif match.phase == "Decision" then
			return Decision.validate(config, match, p, input)
		elseif match.phase == "Plan" then
			return Plan.validate(config, match, p, input)
		end
		return false, "WrongPhase", nil
	end)
	if not ok then
		return false, "Internal", nil
	end
	return valid, reason, normalized
end

-- What player p gets if they submit nothing this phase.
function Match.default(config: Config, match: MatchState, p: number): any
	if match.phase == "Select" then
		-- Your claim if you made one, else a free candidate drawn from the seed (D-048).
		local rng = Rng.fork(match.rng, `select-default:{p}`)
		local issues = table.clone(Issues.list) :: { Types.Issue }
		Rng.shuffle(rng, issues)
		local free = Match.freeCandidates(match)
		local pick = Rng.nextInt(rng, 1, math.max(1, #free))
		return {
			candidate = Match.claimOf(match, p) or free[pick] or Candidates.ids[1],
			platform = table.move(issues, 1, config.PLATFORM_SIZE, 1, {}),
		} :: Selection
	elseif match.phase == "Draft" then
		return { choices = Draft.autofill(config, match, p, {}) }
	elseif match.phase == "Decision" then
		return Decision.default(config, match, p)
	elseif match.phase == "Plan" then
		return Plan.empty()
	end
	return nil
end

-- Normalized input for every player: a valid submission, or the default.
local function collect(config: Config, match: MatchState, inputs: { [number]: any }): { any }
	local out = {}
	for p in match.players do
		local raw = inputs[p]
		local ok, _, normalized = false, nil, nil
		if raw ~= nil then
			ok, _, normalized = Match.validate(config, match, p, raw)
		end
		out[p] = if ok then normalized else Match.default(config, match, p)
	end
	return out
end

-- Reveals every player's candidate and platform. Colors stand as claimed or
-- dealt during Select (D-061): a player without a claim keeps the color dealt
-- from the default order, which already skips every claimed color.
-- Candidates are unique (D-048): claims stand; every other selection is settled
-- in a seeded order (no seat is favored, D-001), and one whose candidate is
-- already taken gets a free candidate drawn from the seed.
local function resolveSelect(config: Config, match: MatchState, selections: { Selection }): { Event }
	local events: { Event } = {}
	local order = {}
	for p in match.players do
		if Match.claimOf(match, p) == nil then
			table.insert(order, p)
		end
	end
	Rng.shuffle(Rng.fork(match.rng, "select-order"), order)
	for _, p in order do
		local wanted = selections[p].candidate
		if match.claims[wanted] ~= nil then
			local free = Match.freeCandidates(match)
			wanted = free[Rng.nextInt(Rng.fork(match.rng, `select-free:{p}`), 1, #free)]
		end
		match.claims[wanted] = p
	end
	for p, player in match.players do
		local choice = selections[p]
		player.candidate = Match.claimOf(match, p) or choice.candidate
		player.platform = table.clone(choice.platform)
		player.profile = Candidates.profile(config, player.candidate)
		player.cash = player.profile.startCash
		table.insert(events, { kind = "Selected", player = p })
	end
	dealColors(match)
	return events
end

-- Opens a decision, or goes straight to the plan when `kind` is nil.
local function decideOrPlan(match: MatchState, kind: Decision.Kind?)
	match.decision = kind
	match.phase = if kind ~= nil then "Decision" else "Plan"
end

-- Keeps the projected votes on the polls just published (D-066): the end-of-match
-- chart's week-by-week line. Reads public numbers only; draws nothing from the seed.
local function recordPolls(match: MatchState)
	table.insert(match.pollHistory, { week = match.week, ev = Polls.projectedEV(match) })
end

local function enterWeek(config: Config, match: MatchState, week: number)
	match.week = week
	if week > config.WEEKS then
		match.decision = nil
		match.phase = "Election"
		match.election = Election.count(config, match)
	else
		decideOrPlan(match, Decision.opening(config, match, week))
	end
end

-- Advances the match by one phase. Returns the new state and its events; the
-- argument is not modified.
function Match.advance(
	config: Config,
	current: MatchState,
	inputs: { [number]: any }?
): (MatchState, { Event })
	local match = State.clone(current)
	local given = inputs or {}
	local events: { Event } = {}
	local phase = match.phase

	if phase == "Select" then
		events = resolveSelect(config, match, collect(config, match, given))
		-- Strongholds come from the leans, which are shown from the map reveal on
		-- (D-045): both players see them before the home round.
		Draft.assignStrongholds(config, match)
		match.phase = "MapReveal"
	elseif phase == "MapReveal" then
		match.phase = "Draft"
		match.draftRound = 0
	elseif phase == "Draft" then
		local raw = collect(config, match, given)
		local choices = {}
		for p in match.players do
			choices[p] = Draft.autofill(config, match, p, raw[p].choices)
		end
		for _, pick in Draft.resolveRound(config, match, choices) do
			table.insert(
				events,
				{ kind = "Pick", player = pick.player, state = pick.state, issue = pick.kind :: string }
			)
		end
		if match.draftRound + 1 < Draft.rounds(config) then
			match.draftRound += 1
		else
			Draft.applyBonuses(config, match)
			Polls.update(config, match, true)
			Polls.updateUnderdog(config, match)
			recordPolls(match)
			table.insert(events, { kind = "Polls" })
			enterWeek(config, match, 1)
		end
	elseif phase == "Decision" then
		Decision.apply(config, match, collect(config, match, given))
		if match.decision == "Focus" then
			match.decision = nil
			match.phase = "Debate"
		else
			decideOrPlan(match, nil)
		end
	elseif phase == "Plan" then
		events = Resolve.week(config, match, collect(config, match, given))
		recordPolls(match)
		enterWeek(config, match, match.week + 1)
	elseif phase == "Debate" then
		local result = Debate.resolve(config, match)
		for t, winner in result.winners do
			table.insert(
				events,
				{ kind = "DebateTopic", player = winner, issue = result.topics[t] :: string }
			)
		end
		-- The polls were republished with the debate's shifts (D-040): say which
		-- states changed public leader, with their EV.
		for _, flip in result.flips do
			table.insert(events, {
				kind = "PollFlip",
				player = flip.to,
				state = flip.state,
				issue = "Debate",
				amount = StateData.byId[flip.state].ev,
			})
		end
		decideOrPlan(match, Decision.afterDebate(match))
	elseif phase == "Election" then
		match.phase = "Done"
	else
		error(`cannot advance a match in phase {phase}`)
	end
	return match, events
end

return table.freeze(Match)
