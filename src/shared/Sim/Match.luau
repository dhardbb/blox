--!strict
-- The match state machine: Select -> MapReveal -> Draft (rounds) -> Plan (week n)
-- [-> Debate] -> ... -> Election -> Done.
--
-- Pure: Match.new(config, seed, playerIds) builds a match; Match.advance(config,
-- match, inputs) returns a new state plus events and never mutates its argument.
-- The server collects one input per player for the current phase (validated with
-- Match.validate); anyone missing gets Match.default, the same thing the server
-- submits when a timer runs out.

local Candidates = require("./Candidates")
local ConfigModule = require("./Config")
local Debate = require("./Debate")
local Draft = require("./Draft")
local Election = require("./Election")
local Events = require("./Events")
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
	color: string,
	platform: { Types.Issue },
}

local Match = {}

-- A new match in the Select phase. Leans, debate topics and the event deck are
-- seeded now (leans are shown from MapReveal on; each event only in its own week).
-- A private lobby with events off passes Config.with(config, { EVENTS_ENABLED = false }).
function Match.new(config: Config, seed: number, playerIds: { string }): MatchState
	local n = #playerIds
	assert(n >= 2, "a match needs at least two players")
	local rng = Rng.new(seed)
	local placeholder = Candidates.ids[1]
	local players: { State.PlayerState } = {}
	for p, id in playerIds do
		players[p] = {
			id = id,
			candidate = placeholder,
			color = "",
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
			debatePrep = nil,
			internalPolls = {},
			raised = 0,
			card = nil,
		}
	end

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
			pool = capacity,
			battleground = false,
			owner = nil,
			isHome = false,
			momentum = table.create(n, 0),
			backlash = table.create(n, 0),
			gotv = table.create(n, 0),
			debateShift = table.create(n, 0),
			pollError = table.create(n, 0),
			pollErrorUndecided = 0,
			poll = nil,
		}
	end

	return {
		seed = seed,
		rng = rng,
		phase = "Select",
		week = 0,
		draftRound = 0,
		priorityA = Rng.nextInt(Rng.fork(rng, "priority"), 1, n),
		players = players,
		states = states,
		draftLog = {},
		debateTopics = Debate.drawTopics(config, rng),
		debates = {},
		eventDeck = Events.draw(config, rng),
		eventLog = {},
		election = nil,
	}
end

-- Phases that wait for player input.
function Match.wantsInput(match: MatchState): boolean
	return match.phase == "Select" or match.phase == "Draft" or match.phase == "Plan"
end

local function validateSelection(
	config: Config,
	match: MatchState,
	input: any
): (boolean, string?, Selection?)
	if match.phase ~= "Select" then
		return false, "WrongPhase", nil
	end
	if type(input) ~= "table" then
		return false, "BadShape", nil
	end
	local candidate, color, platform = input.candidate, input.color, input.platform
	if type(candidate) ~= "string" or not Candidates.exists(candidate) then
		return false, "UnknownCandidate", nil
	end
	if type(color) ~= "string" or not table.find(Candidates.colors, color) then
		return false, "UnknownColor", nil
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
	return true, nil, { candidate = candidate, color = color, platform = issues }
end

-- Validates player p's input for the current phase. Never throws: returns
-- (true, nil, normalized) or (false, reasonCode, nil).
function Match.validate(config: Config, match: MatchState, p: number, input: any): (boolean, string?, any)
	if type(p) ~= "number" or match.players[p] == nil then
		return false, "UnknownPlayer", nil
	end
	local ok, valid, reason, normalized = pcall(function(): (boolean, string?, any)
		if match.phase == "Select" then
			return validateSelection(config, match, input)
		elseif match.phase == "Draft" then
			local draftOk, draftReason, choices = Draft.validate(config, match, p, input)
			return draftOk, draftReason, if choices then { choices = choices } else nil
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
		local rng = Rng.fork(match.rng, `select-default:{p}`)
		local issues = table.clone(Issues.list) :: { Types.Issue }
		Rng.shuffle(rng, issues)
		return {
			candidate = Candidates.ids[Rng.nextInt(rng, 1, #Candidates.ids)],
			color = Candidates.colors[1],
			platform = table.move(issues, 1, config.PLATFORM_SIZE, 1, {}),
		} :: Selection
	elseif match.phase == "Draft" then
		return { choices = Draft.autofill(config, match, p, {}) }
	elseif match.phase == "Plan" then
		return Plan.empty(config, match, p)
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

-- Colors are unique: on a clash a seeded order decides, and anyone left out gets
-- the first free color.
local function resolveSelect(config: Config, match: MatchState, selections: { Selection }): { Event }
	local events: { Event } = {}
	local order = {}
	for p in match.players do
		order[p] = p
	end
	Rng.shuffle(Rng.fork(match.rng, "colors"), order)
	local used: { [string]: boolean } = {}
	for _, p in order do
		local choice = selections[p]
		local color = choice.color
		if used[color] then
			for _, c in Candidates.colors do
				if not used[c] then
					color = c
					break
				end
			end
		end
		used[color] = true
		local player = match.players[p]
		player.candidate = choice.candidate
		player.color = color
		player.platform = table.clone(choice.platform)
		player.profile = Candidates.profile(config, choice.candidate)
		player.cash = player.profile.startCash
		table.insert(events, { kind = "Selected", player = p })
	end
	return events
end

local function enterWeek(config: Config, match: MatchState, week: number)
	match.week = week
	if week > config.WEEKS then
		match.phase = "Election"
		match.election = Election.count(config, match)
	elseif table.find(config.DEBATE_WEEKS, week) then
		match.phase = "Debate"
	else
		match.phase = "Plan"
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
			table.insert(events, { kind = "Polls" })
			enterWeek(config, match, 1)
		end
	elseif phase == "Plan" then
		events = Resolve.week(config, match, collect(config, match, given))
		enterWeek(config, match, match.week + 1)
	elseif phase == "Debate" then
		local result = Debate.resolve(config, match)
		for t, winner in result.winners do
			table.insert(
				events,
				{ kind = "DebateTopic", player = winner, issue = result.topics[t] :: string }
			)
		end
		match.phase = "Plan"
	elseif phase == "Election" then
		match.phase = "Done"
	else
		error(`cannot advance a match in phase {phase}`)
	end
	return match, events
end

return table.freeze(Match)
