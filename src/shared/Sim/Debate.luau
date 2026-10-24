--!strict
-- Debates as live rounds (docs/DESIGN.md D-062). Topics are drawn from the seed
-- when the match starts and announced weeks ahead (View.nextDebate). A debate
-- week opens with its Debate phase: one round per topic, each an input phase in
-- which every player picks a move at once.
--
-- Strength of each move (Debate.board, public arithmetic on public facts):
--   Defend = DEFEND_BASE + OWN_ISSUE (topic on your platform) + GROUND (you lead its states)
--   Attack = ATTACK_BASE + THEIR_ISSUE (topic on an opponent's platform)
--            + GROUND (you trail its states) + CROWD_TRAIL (you trail the crowd)
--   Pivot  = PIVOT_BASE + OFF_ISSUE (topic not on your platform)
--   minus DEBATE_REPEAT for the move you played last round.
-- "Lead the topic's states": the EV of the topic's states where you lead the
-- public poll is more than every other player's.
--
-- Defend beats Attack, Attack beats Pivot, Pivot beats Defend: a move that
-- counters another player's move adds DEBATE_COUNTER[round]. The highest score
-- wins the round; equal top scores are a split. There is no dice roll.
--
-- What a round moves (one snapshot, applied together, D-001): the winner gains
-- DEBATE_ROUND_WIN in each of its landing states, times its Zinger multiplier if
-- it staked its Zinger; on a split each tied player gains DEBATE_ROUND_SPLIT in
-- its own; a player who lost to a counter loses DEBATE_BACKFIRE in its own.
-- Defend and Attack land in the topic's states, Pivot in the states of the
-- player's pivot issue (its platform issue, not this topic, whose states within
-- DEBATE_PIVOT_CLOSE poll points hold the most EV). The polls are republished
-- after every round with the same error terms, so the map shows it live.
--
-- The crowd: a round's winner gains its margin (at most DEBATE_CROWD_ROUND_MAX)
-- times the Zinger multiplier. A final lead of DEBATE_OVATION or more is a
-- standing ovation: momentum in every battleground.
--
-- A canned answer (the timeout default) is Defend at a flat DEBATE_CANNED: it
-- is never countered and never counters, never backfires, and a round won
-- against nothing but canned answers gains at most DEBATE_CANNED_CROWD crowd.

local ConfigModule = require("./Config")
local IssueMap = require("./IssueMap")
local Issues = require("./Issues")
local Plan = require("./Plan")
local Polls = require("./Polls")
local Rng = require("./Rng")
local State = require("./State")
local StateData = require("./StateData")
local Support = require("./Support")
local Types = require("../Types")

type Config = ConfigModule.Config
type MatchState = State.MatchState
type Move = Types.DebateMove

local Debate = {}

local MOVES: { Move } = { "Defend", "Attack", "Pivot" }
Debate.MOVES = table.freeze(MOVES)

-- The move each move beats.
local BEATS: { [string]: Move } = { Defend = "Attack", Attack = "Pivot", Pivot = "Defend" }
Debate.BEATS = table.freeze(BEATS)

-- One part of a move's strength, for the "why" sheet.
export type PartKind =
	"Base"
	| "OwnIssue"
	| "LeadStates"
	| "TheirIssue"
	| "TrailStates"
	| "TrailCrowd"
	| "OffIssue"
	| "Repeat"

export type Part = { kind: PartKind, points: number }

export type MoveInfo = {
	strength: number,
	parts: { Part },
}

-- One player's side of the board.
export type PlayerBoard = {
	defend: MoveInfo,
	attack: MoveInfo,
	pivot: MoveInfo,
	pivotIssue: Types.Issue, -- where a Pivot lands this round
	ground: number, -- 1 = you lead the topic's states, -1 = you trail, 0 = even
	groundEV: number, -- EV of the topic's states where you lead the public poll
	trailsCrowd: boolean,
	ownsTopic: boolean,
	zingers: number, -- Zingers left
	zingerMult: number,
	last: Move?, -- the move played last round
}

-- Everything public about the round now asking for moves.
export type Board = {
	week: number,
	round: number,
	topic: Types.Issue,
	counter: number, -- this round's counter bonus
	topicStates: { string },
	players: { PlayerBoard },
}

-- Seeded topics for every debate week.
function Debate.drawTopics(config: Config, rng: Rng.Rng): { [number]: { Types.Issue } }
	local topics: { [number]: { Types.Issue } } = {}
	for _, week in config.DEBATE_WEEKS do
		local pool: { Types.Issue } = table.clone(Issues.list)
		Rng.shuffle(Rng.fork(rng, `debate-topics:{week}`), pool)
		local chosen: { Types.Issue } = {}
		for k = 1, config.DEBATE_TOPICS do
			chosen[k] = pool[k]
		end
		topics[week] = chosen
	end
	return topics
end

-- The next debate week at or after `week`, or nil.
function Debate.nextWeek(config: Config, week: number): number?
	for _, w in config.DEBATE_WEEKS do
		if w >= week then
			return w
		end
	end
	return nil
end

-- Ids of the states where `topic` is a top issue on this match's issue map, in
-- StateData order. Public.
function Debate.topicStates(issueMap: IssueMap.IssueMap, topic: Types.Issue): { string }
	local out: { string } = {}
	for i, record in StateData.list do
		if table.find(issueMap[i], topic) then
			table.insert(out, record.id)
		end
	end
	return out
end

-- Whether `value` is a move.
function Debate.isMove(value: any): boolean
	return type(value) == "string" and BEATS[value] ~= nil
end

-- The info for one move on a player's board.
function Debate.info(side: PlayerBoard, move: Move): MoveInfo
	if move == "Defend" then
		return side.defend
	elseif move == "Attack" then
		return side.attack
	end
	return side.pivot
end

-- The counter bonus in round `round`.
function Debate.counter(config: Config, round: number): number
	local list = config.DEBATE_COUNTER
	return list[math.clamp(round, 1, #list)]
end

-- ---------------------------------------------------------------- the board

-- Public facts the board is built from (the match, or a View: both carry them).
export type BoardInput = {
	week: number,
	round: number,
	topic: Types.Issue,
	issueMap: IssueMap.IssueMap,
	platforms: { { Types.Issue } }, -- by player
	polls: { State.Poll? }, -- by state, StateData order
	crowd: { number },
	zingers: { number },
	zingerMults: { number },
	last: { [number]: Move },
}

local function margin(poll: State.Poll?, p: number): number?
	if poll == nil then
		return nil
	end
	local best = -math.huge
	for q, share in poll.support do
		if q ~= p and share > best then
			best = share
		end
	end
	return (poll.support[p] or 0) - (if best == -math.huge then 0 else best)
end

-- The platform issue (not `topic`) whose states within DEBATE_PIVOT_CLOSE public
-- poll points either way hold the most EV for player p; ties go to platform order.
local function pivotIssue(config: Config, input: BoardInput, p: number): Types.Issue
	local best: Types.Issue? = nil
	local bestEV = -1
	local platform = input.platforms[p]
	for k = 1, #platform do
		local issue: Types.Issue = platform[k]
		if issue ~= input.topic then
			local ev = 0
			for i, record in StateData.list do
				if table.find(input.issueMap[i], issue) then
					local m = margin(input.polls[i], p)
					if m ~= nil and math.abs(m) <= config.DEBATE_PIVOT_CLOSE then
						ev += record.ev
					end
				end
			end
			if ev > bestEV then
				best, bestEV = issue, ev
			end
		end
	end
	return best or input.topic
end

local function part(parts: { Part }, kind: PartKind, points: number): number
	if points ~= 0 then
		table.insert(parts, { kind = kind, points = points })
	end
	return points
end

-- The board for the round described by `input`. Pure; the server, the View, the
-- bots, the client and the duel harness all read it.
function Debate.boardFrom(config: Config, input: BoardInput): Board
	local n = #input.platforms
	local topic: Types.Issue = input.topic
	local states: { string } = {}
	local groundEV = table.create(n, 0)
	for i, record in StateData.list do
		if table.find(input.issueMap[i], topic) then
			table.insert(states, record.id)
			local leader = Polls.leader(input.polls[i])
			if leader > 0 then
				groundEV[leader] += record.ev
			end
		end
	end
	local topCrowd = -math.huge
	for p = 1, n do
		topCrowd = math.max(topCrowd, input.crowd[p] or 0)
	end
	local players: { PlayerBoard } = {}
	for p = 1, n do
		local ground = 0
		local above, below = true, false
		for q = 1, n do
			if q ~= p then
				if groundEV[q] >= groundEV[p] then
					above = false
				end
				if groundEV[q] > groundEV[p] then
					below = true
				end
			end
		end
		if above then
			ground = 1
		elseif below then
			ground = -1
		end
		local owns = table.find(input.platforms[p], topic) ~= nil
		local theirs = false
		for q = 1, n do
			if q ~= p and table.find(input.platforms[q], topic) then
				theirs = true
			end
		end
		local trails = (input.crowd[p] or 0) < topCrowd
		local last: Move? = input.last[p]
		local function build(move: Move): MoveInfo
			local parts: { Part } = {}
			local s = 0
			if move == "Defend" then
				s += part(parts, "Base", config.DEBATE_DEFEND_BASE)
				s += part(parts, "OwnIssue", if owns then config.DEBATE_OWN_ISSUE else 0)
				s += part(parts, "LeadStates", if ground == 1 then config.DEBATE_GROUND else 0)
			elseif move == "Attack" then
				s += part(parts, "Base", config.DEBATE_ATTACK_BASE)
				s += part(parts, "TheirIssue", if theirs then config.DEBATE_THEIR_ISSUE else 0)
				s += part(parts, "TrailStates", if ground == -1 then config.DEBATE_GROUND else 0)
				s += part(parts, "TrailCrowd", if trails then config.DEBATE_CROWD_TRAIL else 0)
			else
				s += part(parts, "Base", config.DEBATE_PIVOT_BASE)
				s += part(parts, "OffIssue", if owns then 0 else config.DEBATE_OFF_ISSUE)
			end
			s += part(parts, "Repeat", if last == move then -config.DEBATE_REPEAT else 0)
			return { strength = s, parts = parts }
		end
		players[p] = {
			defend = build("Defend"),
			attack = build("Attack"),
			pivot = build("Pivot"),
			pivotIssue = pivotIssue(config, input, p),
			ground = ground,
			groundEV = groundEV[p],
			trailsCrowd = trails,
			ownsTopic = owns,
			zingers = input.zingers[p] or 0,
			zingerMult = input.zingerMults[p] or config.DEBATE_ZINGER_MULT,
			last = last,
		}
	end
	return {
		week = input.week,
		round = input.round,
		topic = topic,
		counter = Debate.counter(config, input.round),
		topicStates = states,
		players = players,
	}
end

-- The board of the match's debate round now asking for moves.
function Debate.board(config: Config, match: MatchState): Board
	local live = match.debate
	assert(live, "no debate in progress")
	local platforms: { { Types.Issue } } = {}
	local mults: { number } = {}
	for p, player in match.players do
		platforms[p] = player.platform
		mults[p] = player.profile.zingerMult
	end
	local polls: { State.Poll? } = {}
	for i, s in match.states do
		polls[i] = s.poll
	end
	return Debate.boardFrom(config, {
		week = live.week,
		round = live.round,
		topic = live.topics[live.round],
		issueMap = match.issueMap,
		platforms = platforms,
		polls = polls,
		crowd = live.crowd,
		zingers = live.zingers,
		zingerMults = mults,
		last = live.last,
	})
end

-- ---------------------------------------------------------------- the clash

export type Clash = {
	strengths: { number },
	countered: { boolean },
	scores: { number },
	winner: number, -- 0 = split
	margin: number,
	split: { boolean },
	backfire: { boolean },
}

-- Who wins a round on `board` with these inputs (every player's). Pure.
function Debate.clash(config: Config, board: Board, inputs: { State.DebateInput }): Clash
	local n = #board.players
	local strengths = table.create(n, 0)
	local counters = table.create(n, false)
	local countered = table.create(n, false)
	for p = 1, n do
		local input = inputs[p]
		strengths[p] = if input.canned
			then config.DEBATE_CANNED
			else Debate.info(board.players[p], input.move).strength
	end
	for p = 1, n do
		for q = 1, n do
			if q ~= p and not inputs[p].canned and not inputs[q].canned then
				if BEATS[inputs[p].move] == inputs[q].move then
					counters[p] = true
					countered[q] = true
				end
			end
		end
	end
	local scores = table.create(n, 0)
	local top = -math.huge
	for p = 1, n do
		scores[p] = strengths[p] + (if counters[p] then board.counter else 0)
		top = math.max(top, scores[p])
	end
	local tops: { number } = {}
	local second = -math.huge
	for p = 1, n do
		if scores[p] == top then
			table.insert(tops, p)
		else
			second = math.max(second, scores[p])
		end
	end
	local winner = if #tops == 1 then tops[1] else 0
	local split = table.create(n, false)
	if winner == 0 then
		for _, p in tops do
			split[p] = true
		end
	end
	local backfire = table.create(n, false)
	for p = 1, n do
		backfire[p] = p ~= winner and not split[p] and countered[p]
	end
	return {
		strengths = strengths,
		countered = countered,
		scores = scores,
		winner = winner,
		margin = if winner > 0 then top - second else 0,
		split = split,
		backfire = backfire,
	}
end

-- Player p's score minus q's when p plays `mine` and q plays `theirs`, the
-- others aside (the result cells on a move's button). Pure.
function Debate.versus(_config: Config, board: Board, p: number, mine: Move, q: number, theirs: Move): number
	local a = Debate.info(board.players[p], mine).strength
	local b = Debate.info(board.players[q], theirs).strength
	if BEATS[mine] == theirs then
		a += board.counter
	elseif BEATS[theirs] == mine then
		b += board.counter
	end
	return a - b
end

-- Whether player p has a move that wins or splits against every reply of every
-- other player on `board` (public arithmetic; Zingers never change who wins).
function Debate.hasSafe(config: Config, board: Board, p: number): boolean
	for a = 1, #MOVES do
		local mine: Move = MOVES[a]
		local safe = true
		for q in board.players do
			if q ~= p then
				for b = 1, #MOVES do
					local theirs: Move = MOVES[b]
					if Debate.versus(config, board, p, mine, q, theirs) < 0 then
						safe = false
					end
				end
			end
		end
		if safe then
			return true
		end
	end
	return false
end

-- The issue whose states a move by player p lands in.
function Debate.landing(board: Board, p: number, move: Move, canned: boolean?): Types.Issue
	if move == "Pivot" and not canned then
		return board.players[p].pivotIssue
	end
	return board.topic
end

-- The support points a round asks for, per state and player, in StateData order.
-- Public arithmetic on the clash.
function Debate.moves(
	config: Config,
	issueMap: IssueMap.IssueMap,
	board: Board,
	inputs: { State.DebateInput },
	clash: Clash,
	mult: number
): { State.StateMove }
	local n = #board.players
	local wants = table.create(n, 0)
	local landing: { Types.Issue } = {}
	for p = 1, n do
		landing[p] = Debate.landing(board, p, inputs[p].move, inputs[p].canned)
		if p == clash.winner then
			wants[p] = config.DEBATE_ROUND_WIN * mult
		elseif clash.split[p] then
			wants[p] = config.DEBATE_ROUND_SPLIT
		elseif clash.backfire[p] then
			wants[p] = -config.DEBATE_BACKFIRE
		end
	end
	local out: { State.StateMove } = {}
	for i, record in StateData.list do
		local points = table.create(n, 0)
		local any = false
		for p = 1, n do
			if wants[p] ~= 0 and table.find(issueMap[i], landing[p]) then
				points[p] = wants[p]
				any = true
			end
		end
		if any then
			table.insert(out, { state = record.id, points = points })
		end
	end
	return out
end

-- ---------------------------------------------------------------- the phase

-- Opens the debate of the current week. Mutates `match`.
function Debate.start(_config: Config, match: MatchState)
	local week = match.week
	local topics = match.debateTopics[week]
	assert(topics, `no debate in week {week}`)
	local n = #match.players
	local zingers = table.create(n, 0)
	for p, player in match.players do
		zingers[p] = player.profile.zingers
	end
	local leaders = table.create(#match.states, 0)
	for i, s in match.states do
		leaders[i] = Polls.leader(s.poll)
	end
	match.debate = {
		week = week,
		round = 1,
		topics = table.clone(topics),
		crowd = table.create(n, 0),
		zingers = zingers,
		last = {},
		rounds = {},
		leaders = leaders,
	}
	for _, player in match.players do
		player.debateMove = nil
	end
end

local R = Plan.Reason

-- Validates player p's move for the round now asking. Returns (true, nil, input)
-- with a normalized input, or (false, reason, nil). Never throws.
function Debate.validate(
	_config: Config,
	match: MatchState,
	p: number,
	input: any
): (boolean, string?, State.DebateInput?)
	local live = match.debate
	if match.phase ~= "Debate" or live == nil then
		return false, R.WrongPhase, nil
	end
	if type(input) ~= "table" then
		return false, R.BadShape, nil
	end
	if not Debate.isMove(input.move) then
		return false, R.BadMove, nil
	end
	local zinger = input.zinger
	if zinger ~= nil and type(zinger) ~= "boolean" then
		return false, R.BadShape, nil
	end
	if zinger == true and (live.zingers[p] or 0) <= 0 then
		return false, R.ZingerSpent, nil
	end
	return true, nil, { move = input.move :: Move, zinger = zinger == true, canned = false }
end

-- What a player who sends nothing gets: the canned answer.
function Debate.default(): State.DebateInput
	return { move = "Defend", zinger = false, canned = true }
end

-- Plays the round now asking for moves with every player's input (missing ones
-- get the canned answer). Returns the round, and the finished debate after the
-- last round. Mutates `match`.
function Debate.round(
	config: Config,
	match: MatchState,
	given: { [number]: State.DebateInput? }
): (State.DebateRound, State.DebateResult?)
	local live = match.debate
	assert(live, "no debate in progress")
	local n = #match.players
	local board = Debate.board(config, match)
	local inputs: { State.DebateInput } = {}
	local zingers = table.create(n, false)
	for p = 1, n do
		local input = given[p] or Debate.default()
		if input.zinger and (live.zingers[p] or 0) <= 0 then
			input = { move = input.move, zinger = false, canned = input.canned }
		end
		inputs[p] = input
		if input.zinger then
			zingers[p] = true
			live.zingers[p] -= 1
		end
	end
	local clash = Debate.clash(config, board, inputs)
	local winner = clash.winner
	local mult = if winner > 0 and zingers[winner] then board.players[winner].zingerMult else 1

	local crowd = table.create(n, 0)
	if winner > 0 then
		local gain = math.min(clash.margin, config.DEBATE_CROWD_ROUND_MAX) * mult
		local onlyCanned = true
		for p = 1, n do
			if p ~= winner and not inputs[p].canned then
				onlyCanned = false
			end
		end
		if onlyCanned then
			gain = math.min(gain, config.DEBATE_CANNED_CROWD)
		end
		crowd[winner] = gain
		live.crowd[winner] += gain
	end

	-- Apply from one snapshot (D-001): gains use the normal split, losses go to
	-- undecided. Record what each state's support actually moved by, so the
	-- harness can recount the election without debates.
	local moves = Debate.moves(config, match.issueMap, board, inputs, clash, mult)
	local byState: { [string]: State.StateMove } = {}
	for _, move in moves do
		byState[move.state] = move
	end
	for _, s in match.states do
		local move = byState[s.id]
		if move then
			local before = table.clone(s.support)
			local delta = Support.zero(s)
			local du = 0
			for p = 1, n do
				local x = move.points[p]
				if x > 0 then
					du += Support.addGain(config, s, p, x, delta)
				elseif x < 0 then
					du += Support.addLoss(p, -x, delta)
				end
			end
			Support.apply(s, delta, du)
			for p = 1, n do
				s.debateShift[p] += s.support[p] - before[p]
			end
		end
	end
	local flips = Polls.refresh(match)

	local picks: { Move } = {}
	local canned: { boolean } = {}
	local landing: { Types.Issue } = {}
	local safe: { boolean } = {}
	for p = 1, n do
		safe[p] = Debate.hasSafe(config, board, p)
		picks[p] = inputs[p].move
		canned[p] = inputs[p].canned
		landing[p] = Debate.landing(board, p, inputs[p].move, inputs[p].canned)
		live.last[p] = inputs[p].move
	end
	local result: State.DebateRound = {
		round = live.round,
		topic = board.topic,
		picks = picks,
		canned = canned,
		zingers = zingers,
		strengths = clash.strengths,
		countered = clash.countered,
		safe = safe,
		scores = clash.scores,
		winner = winner,
		margin = clash.margin,
		split = clash.split,
		backfire = clash.backfire,
		mult = mult,
		landing = landing,
		crowd = crowd,
		moves = moves,
		flips = flips,
	}
	table.insert(live.rounds, result)
	for _, player in match.players do
		player.debateMove = nil
	end
	live.round += 1
	if live.round <= #live.topics then
		return result, nil
	end
	return result, Debate.finish(config, match)
end

-- Closes the debate after its last round: the standing ovation and the record.
-- Mutates `match`.
function Debate.finish(config: Config, match: MatchState): State.DebateResult
	local live = match.debate
	assert(live, "no debate in progress")
	local n = #match.players
	local top, second, leader = -math.huge, -math.huge, 0
	for p = 1, n do
		local c = live.crowd[p]
		if c > top then
			second, top, leader = top, c, p
		elseif c == top then
			second, leader = c, 0
		elseif c > second then
			second = c
		end
	end
	local ovation = 0
	if leader > 0 and top - second >= config.DEBATE_OVATION then
		ovation = leader
		for _, s in match.states do
			if s.battleground then
				s.momentum[leader] =
					math.min(config.MOMENTUM_CAP, s.momentum[leader] + config.DEBATE_OVATION_MOMENTUM)
			end
		end
	end

	local rounds = live.rounds
	local count = #rounds
	local scores: { { number } } = {}
	local gaffes: { { boolean } } = {}
	local prep: { { number } } = {}
	for p = 1, n do
		scores[p] = table.create(count, 0)
		gaffes[p] = table.create(count, false)
		prep[p] = table.create(count, 0)
	end
	local winners = table.create(count, 0)
	local sums: { [string]: { number } } = {}
	for t, round in rounds do
		winners[t] = round.winner
		for p = 1, n do
			scores[p][t] = round.scores[p]
			gaffes[p][t] = round.backfire[p]
		end
		for _, move in round.moves do
			local row = sums[move.state]
			if row == nil then
				row = table.create(n, 0)
				sums[move.state] = row
			end
			for p = 1, n do
				row[p] += move.points[p]
			end
		end
	end
	local moves: { State.StateMove } = {}
	local flips: { State.PollFlip } = {}
	for i, s in match.states do
		local row = sums[s.id]
		if row then
			table.insert(moves, { state = s.id, points = row })
		end
		local to = Polls.leader(s.poll)
		if to ~= live.leaders[i] then
			table.insert(flips, { state = s.id, from = live.leaders[i], to = to })
		end
	end
	local result: State.DebateResult = {
		week = live.week,
		topics = live.topics,
		focus = table.create(n, 0),
		prep = prep,
		scores = scores,
		winners = winners,
		gaffes = gaffes,
		national = table.create(n, 0),
		moves = moves,
		flips = flips,
		rounds = rounds,
		crowd = live.crowd,
		ovation = ovation,
	}
	table.insert(match.debates, result)
	match.debate = nil
	return result
end

return table.freeze(Debate)
