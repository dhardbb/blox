--!strict
-- Which states a Choice stance or a debate moves, and what that does to the
-- public-poll leaders, in words a player reads at a glance (D-042). Pure: works
-- from Config, fixed state data and the player's own View only, and reuses the
-- sim's own public arithmetic read-only (Events.stanceEffects, Debate.topicStates,
-- Polls.projectFlips), so a rules change flows through without edits here.
--
-- "States you need" is defined on public information only: a state is in play
-- when its public-poll margin between you and your best rival is within
-- Swing.CLOSE points either way (Explain.IN_PLAY; the line quotes how often a
-- lead that size holds on election night, Explain.leadWinChance). A stance that
-- gains there helps; a stance that loses where you lead puts a state you rely
-- on at risk.
--
--   Swing.CLOSE                                        in-play margin, points
--   Swing.margin(view, id) -> number?                  you minus best rival, public poll
--   Swing.inPlay(view) -> { InPlay }                   states within CLOSE, biggest EV first
--   Swing.needText(config, view) -> string             the "States you need" line
--   Swing.debateBoard(config, view) -> DebateBoard?    this debate round's moves as the debate screen shows them (D-072)
--   Swing.partName(kind) -> string                     "your issue", "you trail the crowd"...
--   Swing.debateRound(config, view, round) -> Topic     one finished round: what it swung, backfires, flips
--   Swing.stance(config, view, id) -> Preview          one stance on the map, your side only
--   Swing.stanceSummary(config, view, preview) -> string
--   Swing.flipPhrase(view, flip) -> string             "PA flipped to you (+19 EV)"
--   Swing.flips(pollFlips) -> { Flip }                 the same flips with each state's EV
--   Swing.debateTopic(config, view, result, t) -> Topic   round t of a finished debate (Swing.debateRound)
--   Swing.debateOther(view, result) -> { Flip }        flips of the whole debate that no single round shows
--   Swing.net(moves, view) -> { [string]: number }     points toward you minus toward the rival, per state
--   Swing.debateNet(config, view, result, upto)        the same for debate rounds 1..upto
--   Swing.choiceLines(config, view, entry) -> { string }  a resolved Choice week, both sides
--   Swing.lastChoice(view) -> EventResult?             last week's resolved Choice event
--   Swing.decided(config, view) -> { string }          the Results screen's "What decided it"
--   Swing.scoutLine(view) -> string?                   the ground game your polls found, and how those states went (D-049)

local ConfigModule = require("../Sim/Config")
local Debate = require("../Sim/Debate")
local Events = require("../Sim/Events")
local Explain = require("./Explain")
local Issues = require("../Sim/Issues")
local Numbers = require("./Numbers")
local Polls = require("../Sim/Polls")
local SimState = require("../Sim/State")
local StateData = require("../Sim/StateData")
local Types = require("../Types")
local ViewModule = require("../Sim/View")

type Config = ConfigModule.Config
type View = ViewModule.View

local Swing = {}

Swing.CLOSE = Explain.IN_PLAY -- points of public-poll margin, either way, that make a state "in play" (display only)
Swing.LIST_MAX = 5 -- states named in one list before "+N more"

export type Flip = { state: string, from: number, to: number, ev: number }

export type InPlay = { state: string, margin: number, ev: number }

export type Preview = {
	id: Types.Choice,
	name: string,
	hedge: boolean,
	effects: { [string]: number }, -- state id -> support points for you
	gains: { string }, -- biggest EV first
	losses: { string },
	gainTotal: number,
	lossTotal: number, -- negative
	needed: { string }, -- gains that are in play
	leadsHurt: { string }, -- losses in states you lead in the public poll
	flips: { Flip }, -- leader changes on today's polls from your stance alone
}

-- One move on this debate round's board (D-072), as its button shows it.
export type MoveRow = {
	move: Types.DebateMove,
	strength: number,
	parts: { Debate.Part },
	cells: { number }, -- your score minus theirs against their Defend, Attack, Pivot
	beats: Types.DebateMove, -- the move it counters
	safe: boolean, -- no cell below 0: it cannot lose this round
	landing: Types.Issue, -- the issue whose states a win lands in
	states: { string }, -- those states, biggest EV first
	effects: { [string]: number }, -- what a win gives you, per state (the map preview)
	flips: { Flip }, -- leader changes a win would make on today's polls
	winLine: string, -- "A win: +1.0 in OH, PA, MI +5 more; could flip PA (+19 EV)"
}

-- This debate round for you (D-072): your three moves against your best rival's.
export type DebateBoard = {
	round: number,
	rounds: number,
	topic: Types.Issue,
	counter: number,
	rival: number,
	rows: { MoveRow }, -- Defend, Attack, Pivot
	theirs: { number }, -- the rival's strengths, same order
	zingers: number, -- yours left
	theirZingers: number,
	zingerMult: number,
	crowd: number, -- yours
	theirCrowd: number,
	ground: number, -- 1 = you lead the topic's states, -1 = you trail
	ownsTopic: boolean,
	theirTopic: boolean,
	topicStates: { string }, -- biggest EV first
}

-- One finished debate round (D-072), for the clash, the verdict and the logs.
export type Topic = {
	topic: Types.Issue,
	winner: number, -- 0 = a split
	states: { string }, -- the winner's landing states (the topic's on a split), biggest EV first
	points: number, -- what the winner gained in each (0 on a split)
	gaffes: { { player: number, points: number } }, -- backfires: who lost what in their own landing states
	flips: { Flip }, -- leader changes when the polls were republished after the round
	line: string, -- "Your Defend won Jobs by 3: +2.0 in OH, MI, PA (Zinger x2) - PA flipped to you (+19 EV)"
	gaffeLines: { string }, -- "Their Attack backfired: -0.5 in OH, MI"
}

-- ---------------------------------------------------------------- basics

local function evOf(id: string): number
	local record = StateData.byId[id]
	return if record then record.ev else 0
end

local function byEv(ids: { string }): { string }
	local out = table.clone(ids)
	table.sort(out, function(a: string, b: string): boolean
		local ea, eb = evOf(a), evOf(b)
		if ea ~= eb then
			return ea > eb
		end
		return a < b
	end)
	return out
end

-- "OH, PA, MI, WI, GA +3 more"
local function list(ids: { string }): string
	local shown: { string } = {}
	for k = 1, math.min(#ids, Swing.LIST_MAX) do
		table.insert(shown, ids[k])
	end
	local text = table.concat(shown, ", ")
	if #ids > Swing.LIST_MAX then
		text ..= ` +{#ids - Swing.LIST_MAX} more`
	end
	return text
end

local function plural(n: number, word: string): string
	return `{n} {word}{if n == 1 then "" else "s"}`
end

local function issueName(issue: string): string
	return Issues.displayName[issue :: Types.Issue] or issue
end

-- The best rival's share in a poll (the highest share that is not yours).
local function rivalShare(support: { number }, you: number): number
	local best = 0
	for p, share in support do
		if p ~= you and share > best then
			best = share
		end
	end
	return best
end

local function rivalOf(view: View): number
	return if view.you == 1 then 2 else 1
end

local function stateView(view: View, id: string): ViewModule.StateView?
	local i = SimState.indexOf[id]
	return if i then view.states[i] else nil
end

function Swing.margin(view: View, id: string): number?
	local s = stateView(view, id)
	local poll = if s then s.poll else nil
	if poll == nil then
		return nil
	end
	return (poll.support[view.you] or 0) - rivalShare(poll.support, view.you)
end

function Swing.inPlay(view: View): { InPlay }
	local out: { InPlay } = {}
	for _, s in view.states do
		local margin = Swing.margin(view, s.id)
		if margin ~= nil and math.abs(margin) <= Swing.CLOSE then
			table.insert(out, { state = s.id, margin = margin, ev = evOf(s.id) })
		end
	end
	table.sort(out, function(a: InPlay, b: InPlay): boolean
		if a.ev ~= b.ev then
			return a.ev > b.ev
		end
		return a.state < b.state
	end)
	return out
end

local function inPlaySet(view: View): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, entry in Swing.inPlay(view) do
		set[entry.state] = true
	end
	return set
end

-- "States you need (within 5 points in the public poll): you trail WI by 2, MI by 4 · you lead OH by 3 · tied NV. You project 251 EV; 270 wins."
function Swing.needText(config: Config, view: View): string
	local trail: { string } = {}
	local lead: { string } = {}
	local tied: { string } = {}
	for _, entry in Swing.inPlay(view) do
		local by = math.abs(entry.margin)
		if entry.margin > 0 then
			table.insert(lead, `{entry.state} by {by}`)
		elseif entry.margin < 0 then
			table.insert(trail, `{entry.state} by {by}`)
		else
			table.insert(tied, entry.state)
		end
	end
	local parts: { string } = {}
	if #trail > 0 then
		table.insert(parts, `you trail {list(trail)}`)
	end
	if #lead > 0 then
		table.insert(parts, `you lead {list(lead)}`)
	end
	if #tied > 0 then
		table.insert(parts, `tied {list(tied)}`)
	end
	local head =
		`States you need (within {Swing.CLOSE} points in the public poll; a {Swing.CLOSE}-point lead holds about {math.floor(
			Explain.leadWinChance(config, Swing.CLOSE) * 100 + 0.5
		)}% on election night)`
	local ev = view.projectedEV[view.you] or 0
	local tail = ` You project {ev} EV; {config.EV_TO_WIN} wins.`
	if #parts == 0 then
		return `{head}: none right now.{tail}`
	end
	return `{head}: {table.concat(parts, " · ")}.{tail}`
end

-- ---------------------------------------------------------------- flips

function Swing.flipPhrase(view: View, flip: Flip): string
	local you = view.you
	if flip.to == you then
		return `{flip.state} flipped to you (+{flip.ev} EV)`
	elseif flip.to == 0 and flip.from == you then
		return `{flip.state} slipped from you to a tie (-{flip.ev} EV)`
	elseif flip.to == 0 then
		return `{flip.state} slipped from them to a tie`
	end
	return `{flip.state} flipped to them ({flip.ev} EV)`
end

-- Poll flips with each state's EV.
function Swing.flips(flips: { SimState.PollFlip }?): { Flip }
	local out: { Flip } = {}
	if flips then
		for _, flip in flips do
			table.insert(out, { state = flip.state, from = flip.from, to = flip.to, ev = evOf(flip.state) })
		end
	end
	return out
end
local withEv = Swing.flips

-- ---------------------------------------------------------------- debate rounds

local MOVE_ORDER: { Types.DebateMove } = { "Defend", "Attack", "Pivot" }

local PART_NAMES: { [string]: string } = {
	Base = "base",
	OwnIssue = "your issue",
	LeadStates = "you lead its states",
	TheirIssue = "their issue",
	TrailStates = "you trail its states",
	TrailCrowd = "you trail the crowd",
	OffIssue = "not your issue",
	Repeat = "same as last round",
}

function Swing.partName(kind: string): string
	return PART_NAMES[kind] or kind
end

-- A win of `points` in `states` for you, as map effects and the flips it would
-- make on today's polls.
local function winPreview(view: View, states: { string }, points: number): ({ [string]: number }, { Flip })
	local effects: { [string]: number } = {}
	local moves: { SimState.StateMove } = {}
	for _, id in states do
		effects[id] = points
		local row = table.create(#view.players, 0)
		row[view.you] = points
		table.insert(moves, { state = id, points = row })
	end
	return effects, Swing.flips(Polls.projectFlips({ states = view.states } :: any, moves))
end

function Swing.debateBoard(config: Config, view: View): DebateBoard?
	local live = view.debate
	if live == nil then
		return nil
	end
	local board = live.board
	local me, rival = view.you, rivalOf(view)
	local mine, theirs = board.players[me], board.players[rival]
	if mine == nil or theirs == nil then
		return nil
	end
	local rows: { MoveRow } = {}
	local theirStrengths: { number } = {}
	for k = 1, #MOVE_ORDER do
		local move: Types.DebateMove = MOVE_ORDER[k]
		local info = Debate.info(mine, move)
		local cells: { number } = {}
		local safe = true
		for b = 1, #MOVE_ORDER do
			local other: Types.DebateMove = MOVE_ORDER[b]
			cells[b] = Debate.versus(config, board, me, move, rival, other)
			if cells[b] < 0 then
				safe = false
			end
		end
		theirStrengths[k] = Debate.info(theirs, move).strength
		local landing: Types.Issue = (Debate.landing(board, me, move) :: any) :: Types.Issue
		local states = byEv(Debate.topicStates(view.issueMap, landing))
		local effects, flips = winPreview(view, states, config.DEBATE_ROUND_WIN)
		local flipText: { string } = {}
		for _, flip in flips do
			if flip.to == me then
				table.insert(flipText, `flip {flip.state} (+{flip.ev} EV)`)
			elseif flip.to == 0 then
				table.insert(flipText, `pull level in {flip.state}`)
			end
		end
		rows[k] = {
			move = move,
			strength = info.strength,
			parts = info.parts,
			cells = cells,
			beats = Debate.BEATS[move],
			safe = safe,
			landing = landing,
			states = states,
			effects = effects,
			flips = flips,
			winLine = `A win: {Numbers.signed(config.DEBATE_ROUND_WIN)} in {list(states)}`
				.. (if #flipText > 0 then `; could {table.concat(flipText, ", ")}` else ""),
		}
	end
	return {
		round = live.round,
		rounds = #live.topics,
		topic = board.topic,
		counter = board.counter,
		rival = rival,
		rows = rows,
		theirs = theirStrengths,
		zingers = mine.zingers,
		theirZingers = theirs.zingers,
		zingerMult = mine.zingerMult,
		crowd = live.crowd[me] or 0,
		theirCrowd = live.crowd[rival] or 0,
		ground = mine.ground,
		ownsTopic = mine.ownsTopic,
		theirTopic = theirs.ownsTopic,
		topicStates = byEv(board.topicStates),
	}
end

-- ---------------------------------------------------------------- stances

function Swing.stance(config: Config, view: View, id: Types.Choice): Preview
	local event = view.event
	local definition = if event then Events.byId[event.id] else nil
	local stance = if definition then Events.stance(definition, id) else nil
	local platform = view.players[view.you].platform or {}
	local base = Events.baseOf(view.players[view.you])
	local effects: { [string]: number } = if definition
		then Events.stanceEffects(config, view.issueMap, definition, id, platform, base)
		else {}
	local preview: Preview = {
		id = id,
		name = if stance then stance.name else id,
		hedge = if stance then stance.hedge else false,
		effects = effects,
		gains = {},
		losses = {},
		gainTotal = 0,
		lossTotal = 0,
		needed = {},
		leadsHurt = {},
		flips = {},
	}
	local close = inPlaySet(view)
	local moves: { SimState.StateMove } = {}
	for _, record in StateData.list do
		local points = effects[record.id]
		if points ~= nil then
			local margin = Swing.margin(view, record.id)
			if points > 0 then
				table.insert(preview.gains, record.id)
				preview.gainTotal += points
				if close[record.id] then
					table.insert(preview.needed, record.id)
				end
			elseif points < 0 then
				table.insert(preview.losses, record.id)
				preview.lossTotal += points
				if margin ~= nil and margin > 0 then
					table.insert(preview.leadsHurt, record.id)
				end
			end
			local row = table.create(#view.players, 0)
			row[view.you] = points
			table.insert(moves, { state = record.id, points = row })
		end
	end
	preview.gains = byEv(preview.gains)
	preview.losses = byEv(preview.losses)
	preview.needed = byEv(preview.needed)
	-- Leads at risk: the closest first, the ones you rely on most.
	table.sort(preview.leadsHurt, function(a: string, b: string): boolean
		local ma, mb = Swing.margin(view, a) or 0, Swing.margin(view, b) or 0
		if ma ~= mb then
			return ma < mb
		end
		return evOf(a) > evOf(b)
	end)
	-- The sim's own projection, on the public polls the View carries (StateView
	-- has the `id` and `poll` it reads, in the same order as the match).
	local standIn = { states = view.states } :: any
	preview.flips = withEv(Polls.projectFlips(standIn, moves))
	return preview
end

-- "Stance A · Stand with the plant: +6.0 total over 9 states (4 you need: OH, PA…) · -3.0 total over 5 states (2 you lead: KY by 3, AL by 8) · could flip PA (+19 EV), lose WI (-10 EV)"
function Swing.stanceSummary(_config: Config, view: View, preview: Preview): string
	local label = `Stance {preview.id} · {preview.name}{if preview.hedge then " (the hedge)" else ""}`
	local parts: { string } = {}
	if #preview.gains > 0 then
		local need = if #preview.needed > 0
			then `{#preview.needed} you need: {list(preview.needed)}`
			else "none you need"
		table.insert(
			parts,
			`{Numbers.signed(preview.gainTotal)} total over {plural(#preview.gains, "state")} ({need})`
		)
	end
	if #preview.losses > 0 then
		local hurt: { string } = {}
		for _, id in preview.leadsHurt do
			table.insert(hurt, `{id} by {Swing.margin(view, id) or 0}`)
		end
		local at = if #hurt > 0 then `{#hurt} you lead: {list(hurt)}` else "none you lead"
		table.insert(
			parts,
			`{Numbers.signed(preview.lossTotal)} total over {plural(#preview.losses, "state")} ({at})`
		)
	elseif #preview.gains > 0 then
		table.insert(parts, "no state loses")
	end
	if #parts == 0 then
		table.insert(parts, "no state moves")
	end
	local flips: { string } = {}
	for _, flip in preview.flips do
		if flip.to == view.you then
			table.insert(flips, `flip {flip.state} (+{flip.ev} EV)`)
		elseif flip.from == view.you then
			table.insert(flips, `lose {flip.state} (-{flip.ev} EV)`)
		elseif flip.to == 0 then
			table.insert(flips, `pull level in {flip.state}`)
		else
			table.insert(flips, `hand {flip.state} to them`)
		end
	end
	if #flips > 0 then
		table.insert(parts, `could {table.concat(flips, ", ")}`)
	else
		table.insert(parts, "no poll leader would change")
	end
	return `{label}: {table.concat(parts, " · ")}`
end

-- ---------------------------------------------------------------- debates

local function playerWord(view: View, p: number, you: string, them: string): string
	return if p == view.you then you else them
end

local function moveWord(move: string): string
	return move
end

function Swing.debateRound(config: Config, view: View, round: SimState.DebateRound): Topic
	local topic: Types.Issue = round.topic
	local name = issueName(topic)
	local winner = round.winner
	local flips = withEv(round.flips)
	local line: string
	local states: { string }
	local points = 0
	if winner == 0 then
		states = byEv(Debate.topicStates(view.issueMap, topic))
		local split = config.DEBATE_ROUND_SPLIT
		line = `{name} was a split: {Numbers.signed(split)} each in your own states`
	else
		local landing: Types.Issue = round.landing[winner] or topic
		states = byEv(Debate.topicStates(view.issueMap, landing))
		points = config.DEBATE_ROUND_WIN * (round.mult or 1)
		local who = playerWord(view, winner, "Your", "Their")
		local move = moveWord(round.picks[winner])
		local where = if landing ~= topic then ` (to {issueName(landing)})` else ""
		local zinger = if (round.mult or 1) > 1 then ` (Zinger ×{round.mult})` else ""
		line =
			`{who} {move}{where} won {name} by {round.margin}: {Numbers.signed(points)} in {list(states)}{zinger}`
	end
	if #flips > 0 then
		local phrases: { string } = {}
		for _, flip in flips do
			table.insert(phrases, Swing.flipPhrase(view, flip))
		end
		line ..= ` - {table.concat(phrases, ", ")}`
	end
	local gaffes: { { player: number, points: number } } = {}
	local gaffeLines: { string } = {}
	for p = 1, #view.players do
		if round.backfire[p] then
			local landing: Types.Issue = round.landing[p] or topic
			local lost = byEv(Debate.topicStates(view.issueMap, landing))
			table.insert(gaffes, { player = p, points = -config.DEBATE_BACKFIRE })
			table.insert(
				gaffeLines,
				`{playerWord(view, p, "Your", "Their")} {moveWord(round.picks[p])} backfired: {Numbers.signed(
					-config.DEBATE_BACKFIRE
				)} in {list(lost)}`
			)
		end
	end
	return {
		topic = topic,
		winner = winner,
		states = states,
		points = points,
		gaffes = gaffes,
		flips = flips,
		line = line,
		gaffeLines = gaffeLines,
	}
end

function Swing.debateTopic(config: Config, view: View, result: SimState.DebateResult, t: number): Topic
	local round = result.rounds and result.rounds[t]
	if round then
		return Swing.debateRound(config, view, round)
	end
	local topic: Types.Issue = result.topics[t]
	return {
		topic = topic,
		winner = result.winners[t] or 0,
		states = byEv(Debate.topicStates(view.issueMap, topic)),
		points = 0,
		gaffes = {},
		flips = {},
		line = `{issueName(topic)}: no record`,
		gaffeLines = {},
	}
end

-- Flips of the whole debate that no round's own flips show (a state that
-- changed leader across rounds, e.g. flipped and stayed after a later round).
function Swing.debateOther(_view: View, result: SimState.DebateResult): { Flip }
	local seen: { [string]: boolean } = {}
	for _, round in result.rounds do
		for _, flip in round.flips do
			seen[flip.state] = true
		end
	end
	local rest: { SimState.PollFlip } = {}
	for _, flip in result.flips do
		if not seen[flip.state] then
			table.insert(rest, flip)
		end
	end
	return withEv(rest)
end

-- Points toward you minus points toward your best rival, per state that moved.
function Swing.net(moves: { SimState.StateMove }?, view: View): { [string]: number }
	local out: { [string]: number } = {}
	if moves then
		for _, move in moves do
			local mine = move.points[view.you] or 0
			local theirs = 0
			for p, points in move.points do
				if p ~= view.you and math.abs(points) > math.abs(theirs) then
					theirs = points
				end
			end
			local net = mine - theirs
			if math.abs(net) >= 0.05 then
				out[move.state] = net
			end
		end
	end
	return out
end

-- The points of debate rounds 1..upto, as points toward you minus toward the rival.
function Swing.debateNet(
	_config: Config,
	view: View,
	result: SimState.DebateResult,
	upto: number
): { [string]: number }
	local sums: { [string]: { number } } = {}
	local order: { string } = {}
	for t = 1, math.min(upto, #(result.rounds or {})) do
		for _, move in result.rounds[t].moves do
			local row = sums[move.state]
			if row == nil then
				row = table.create(#view.players, 0)
				sums[move.state] = row
				table.insert(order, move.state)
			end
			for p, points in move.points do
				row[p] += points
			end
		end
	end
	local moves: { SimState.StateMove } = {}
	for _, id in order do
		table.insert(moves, { state = id, points = sums[id] })
	end
	return Swing.net(moves, view)
end

-- ---------------------------------------------------------------- Choice results

function Swing.lastChoice(view: View): SimState.EventResult?
	for k = #view.eventLog, 1, -1 do
		local entry = view.eventLog[k]
		if entry.week == view.week - 1 and entry.choices ~= nil then
			return entry
		end
	end
	return nil
end

-- One side's stance in a resolved Choice week: "+6.0 in 9 states, -3.0 in 5".
local function sideText(moves: { SimState.StateMove }, p: number): string
	local gain, loss, up, down = 0, 0, 0, 0
	for _, move in moves do
		local points = move.points[p] or 0
		if points > 0 then
			gain += points
			up += 1
		elseif points < 0 then
			loss += points
			down += 1
		end
	end
	local parts: { string } = {}
	if up > 0 then
		table.insert(parts, `{Numbers.signed(gain)} total over {plural(up, "state")}`)
	end
	if down > 0 then
		table.insert(parts, `{Numbers.signed(loss)} total over {plural(down, "state")}`)
	end
	return if #parts > 0 then table.concat(parts, ", ") else "no state moved"
end

function Swing.choiceLines(_config: Config, view: View, entry: SimState.EventResult): { string }
	local definition = Events.byId[entry.id]
	local choices, moves = entry.choices, entry.moves
	if choices == nil or moves == nil then
		return {}
	end
	local function stanceName(id: Types.Choice): string
		local stance = if definition then Events.stance(definition, id) else nil
		return if stance then `{id} · {stance.name}` else id
	end
	local you, them = view.you, rivalOf(view)
	local out: { string } = {}
	local mine: Types.Choice? = choices[you]
	local theirs: Types.Choice? = choices[them]
	if mine then
		table.insert(out, `You took {stanceName(mine)}: {sideText(moves, you)}.`)
	end
	if theirs then
		table.insert(out, `They took {stanceName(theirs)}: {sideText(moves, them)}.`)
	end
	local flips = withEv(entry.flips)
	if #flips > 0 then
		local phrases: { string } = {}
		for _, flip in flips do
			table.insert(phrases, Swing.flipPhrase(view, flip))
		end
		table.insert(out, `On the polls you both saw, the stances flipped: {table.concat(phrases, ", ")}.`)
	else
		table.insert(out, "On the polls you both saw, the stances flipped no state.")
		-- The same side for both (not the hedge, which moves nobody): the two
		-- gains mostly cancelled on the margin (M2).
		local stance = if definition and mine then Events.stance(definition, mine) else nil
		if mine ~= nil and mine == theirs and stance ~= nil and not stance.hedge then
			table.insert(out, "Same side, so most of it cancelled.")
		end
	end
	return out
end

-- ---------------------------------------------------------------- results

-- "Debates: OH, PA flipped to you (+36 EV) · WI to them (10 EV) · held on election night: OH, PA"
local function sourceLine(view: View, label: string, flips: { Flip }): string
	if #flips == 0 then
		return `{label}: no state changed poll leader.`
	end
	local you = view.you
	local toYou, toThem, slipped = {}, {}, {}
	local evYou, evThem = 0, 0
	for _, flip in flips do
		if flip.to == you then
			table.insert(toYou, flip.state)
			evYou += flip.ev
		elseif flip.to ~= 0 then
			table.insert(toThem, flip.state)
			evThem += flip.ev
		else
			table.insert(slipped, flip.state)
		end
	end
	local parts: { string } = {}
	if #toYou > 0 then
		table.insert(parts, `{list(toYou)} flipped to you (+{evYou} EV)`)
	end
	if #toThem > 0 then
		table.insert(parts, `{list(toThem)} to them ({evThem} EV)`)
	end
	if #slipped > 0 then
		table.insert(parts, `{list(slipped)} to a tie`)
	end
	local election = view.election
	if election then
		local held: { string } = {}
		local finalWinner: { [string]: number } = {}
		for _, r in election.results do
			finalWinner[r.state] = r.winner
		end
		local seen: { [string]: boolean } = {}
		for k = #flips, 1, -1 do
			local flip = flips[k]
			if not seen[flip.state] then
				seen[flip.state] = true
				if flip.to ~= 0 and finalWinner[flip.state] == flip.to then
					table.insert(held, 1, flip.state)
				end
			end
		end
		if #held > 0 then
			table.insert(parts, `kept on election night: {list(held)}`)
		end
	end
	return `{label}: {table.concat(parts, " · ")}.`
end

-- "Your polls found their ground game in OH (3 units; you had 4, won it), PA (1
-- unit; you had 0, lost it)." Nil before election night or when no poll saw any.
function Swing.scoutLine(view: View): string?
	local election = view.election
	if election == nil then
		return nil
	end
	local them = rivalOf(view)
	local winner: { [string]: number } = {}
	for _, r in election.results do
		winner[r.state] = r.winner
	end
	local found: { { id: string, units: number } } = {}
	for _, scout in (view.scouted or {}) :: { SimState.Scout } do
		local units = scout.gotv[them] or 0
		if units > 0 then
			table.insert(found, { id = scout.state, units = units })
		end
	end
	if #found == 0 then
		return nil
	end
	table.sort(found, function(a, b)
		if evOf(a.id) ~= evOf(b.id) then
			return evOf(a.id) > evOf(b.id)
		end
		return a.id < b.id
	end)
	local parts: { string } = {}
	for _, entry in found do
		local s = stateView(view, entry.id)
		local mine = if s then s.gotv else 0
		local result = if winner[entry.id] == view.you
			then "won it"
			elseif winner[entry.id] == 0 then "tied"
			else "lost it"
		table.insert(parts, `{entry.id} ({plural(entry.units, "unit")}; you had {mine}, {result})`)
	end
	return `Your polls found their ground game in {table.concat(parts, ", ")}.`
end

function Swing.decided(_config: Config, view: View): { string }
	local debates: { Flip } = {}
	for _, result in view.debates do
		for _, flip in withEv(result.flips) do
			table.insert(debates, flip)
		end
	end
	local stances: { Flip } = {}
	for _, entry in view.eventLog do
		if entry.choices ~= nil then
			for _, flip in withEv(entry.flips) do
				table.insert(stances, flip)
			end
		end
	end
	local out = {
		sourceLine(view, "Debates", debates),
		sourceLine(view, "Choice stances", stances),
	}
	local scouting = Swing.scoutLine(view)
	if scouting then
		table.insert(out, scouting)
	end
	local election = view.election
	if election then
		local you, them = view.you, rivalOf(view)
		local gap = (election.ev[you] or 0) - (election.ev[them] or 0)
		local function swung(flips: { Flip }): number
			local net = 0
			for _, flip in flips do
				if flip.to == you then
					net += flip.ev
				elseif flip.from == you then
					net -= flip.ev
				end
				if flip.to == them then
					net -= flip.ev
				elseif flip.from == them then
					net += flip.ev
				end
			end
			return net
		end
		local net = swung(debates) + swung(stances)
		table.insert(
			out,
			`Final gap: {if gap >= 0 then "+" else ""}{gap} EV for you; together they moved the projected gap {if net
					>= 0
				then "+"
				else ""}{net} EV your way.`
		)
	end
	return out
end

return table.freeze(Swing)
