--!strict
-- The short copy of the moments where things happen (docs/UI-STYLE.md §4.7 to
-- §4.10, WP-C): the week's reveal grouped into "Your week" / "Their week" /
-- "What changed", election-night calls, the three
-- reasons on Results, and the five Help tabs. Pure: works from Config, fixed
-- state data and the player's own View, never from hidden numbers. The long
-- explanations stay in Shared/UI/Explain and Swing; this module only says the
-- headline in plain words ("votes", not "EV"; the opponent by name).
--
--   Words.group(view, events, upto, eventName?) -> Groups   a week's events, merged
--   Words.pollChanges(old, new) -> Changes             flips and biggest moves between two public polls
--   Words.flipLine(view, flip, them) -> string          "Ohio flips to you · 17 votes"
--   Words.movePill(move, them) -> string                "TX +3.0 for you"
--   Words.mark(up) -> string                            "▲" (good for you) or "▼" (against you)
--   Words.marked(text, up) -> string                    "▲ Texas flips to you · 40 votes"
--   Words.flipHeadline(view, flips, them) -> string     "You flipped 2 · Rex flipped 1"
--   Words.topMarks(net, flips, n?) -> { [id]: number }  what the map badges: flips and the n biggest moves
--   Words.inVotes(line) -> string                       "+6 EV" -> "+6 votes" (Swing's lines, said plainly)
--   Words.plain(text) -> string                         inVotes, and "AP" said as actions (Explain's rules)
--   Words.stateLine(id) -> string                       "Ohio · 17 votes"
--   Words.callLine(result, names) -> string             "Dana by 2.9 points"
--   Words.keyReasons(config, view, winner, names) -> { string }   at most 3, the winner's side
--   Words.nextTime(config, view, winner, names) -> string?  the loser's one "Try next time" line
--   Words.revealFirst(view) -> (player, trails)         whose actions land first in a week's reveal
--   Words.orderLine(view, first, trails, them) -> string "Rex trails, so Rex's actions land first"
--   Words.SETTLE · ESTIMATE_NOTE · pollShift(flips) · leaderArrow(view, flip, them)  the running tally (D-063)
--   Words.help(config) -> { Tab }                       the five Help tabs
--
-- `them` is the opponent's display name ("Rex"); `names` is display names by
-- player index. Tones are Kit tone names ("good", "loss", "text", "muted");
-- "bad" is the old name of "loss" (both are the loss orange, D-056).

local ConfigModule = require("../../Sim/Config")
local Events = require("../../Sim/Events")
local Issues = require("../../Sim/Issues")
local Numbers = require("../Numbers")
local SimState = require("../../Sim/State")
local StateData = require("../../Sim/StateData")
local Swing = require("../Swing")
local Types = require("../../Types")
local ViewModule = require("../../Sim/View")

type Config = ConfigModule.Config
type View = ViewModule.View

local Words = {}

Words.MOVE_PILLS = 3 -- biggest poll moves shown as pills after a week (a row holds 3)
Words.FLIP_LINES = 4 -- poll-leader flips listed one per line before "+N more"
Words.MAP_MARKS = 3 -- moved states badged on the map besides the flips (UI-STYLE §4.6: about 8 marks at most)
Words.CLOSE = 2 -- points: an election-night margin under this is a close race
Words.HELP_WORDS = 60 -- most words in one Help tab's text
Words.REASON_WORDS = 10 -- most words in one Results reason

export type Tone = "good" | "loss" | "bad" | "text" | "muted"

Words.UP = "▲" -- marks a line that went your way (the glyph rule: orange never alone)
Words.DOWN = "▼" -- marks a line that went against you
export type Groups = { mine: { string }, theirs: { string } }
export type Move = { state: string, delta: number, ev: number } -- delta: margin points toward you
export type Changes = { flips: { Swing.Flip }, moves: { Move } }
export type Tab = {
	id: string,
	label: string, -- the tab chip
	title: string,
	text: string, -- at most HELP_WORDS words
	sections: { string }, -- Explain.help section ids for "All the numbers"
}

-- ---------------------------------------------------------------- basics

local function evOf(id: string): number
	local record = StateData.byId[id]
	return if record then record.ev else 0
end

local function nameOf(id: string?): string
	if id == nil then
		return "?"
	end
	local record = StateData.byId[id]
	return if record then record.name else id
end

local function issueName(issue: string?): string
	if issue == nil then
		return "?"
	end
	return Issues.displayName[issue :: Types.Issue] or issue
end

local function plural(n: number, word: string): string
	return `{n} {word}{if n == 1 then "" else "s"}`
end

local function rivalOf(view: View): number
	return if view.you == 1 then 2 else 1
end

-- ---------------------------------------------------------------- the week

-- Rank of each kind in a group: the stance first, then the actions in the
-- order they happened, then money, polls and flights.
local RANK: { [string]: number } = {
	Choice = 0,
	Rally = 1,
	Media = 1,
	Attack = 1,
	Fundraise = 1,
	Pivot = 1,
	Backlash = 2,
	Raised = 3,
	InternalPolls = 4,
	Flights = 5,
}

type Entry = {
	key: string,
	kind: string,
	state: string?,
	issue: string?,
	count: number,
	amount: number,
	first: number,
}

local function entryText(view: View, entry: Entry, eventName: string?): string
	local kind = entry.kind
	local times = if entry.count > 1 then ` ×{entry.count}` else ""
	local where = nameOf(entry.state)
	if kind == "Rally" then
		return `Rally in {where}{times} · {issueName(entry.issue)}`
	elseif kind == "Media" then
		return `Ad in {where}{times} · {issueName(entry.issue)}`
	elseif kind == "Attack" then
		return `Attack ad in {where}{times} · {issueName(entry.issue)}`
	elseif kind == "Fundraise" then
		return `Fundraiser in {where}{times}`
	elseif kind == "Pivot" then
		return `Swapped in a new issue: {issueName(entry.issue)}`
	elseif kind == "Backlash" then
		return `Backlash in {where}: too many attacks`
	elseif kind == "Raised" then
		return `Raised {Numbers.money(entry.amount)} in all`
	elseif kind == "InternalPolls" then
		return `{plural(entry.amount, "private poll")} came back`
	elseif kind == "Flights" then
		return `Took {plural(entry.amount, "flight")}`
	elseif kind == "Choice" then
		local id: Types.Choice = if Events.isChoice(entry.issue) then entry.issue :: any else "C"
		local stanceName: string = id
		for _, result in view.eventLog do
			local definition = Events.byId[result.id]
			if result.week == view.week - 1 and definition then
				local stance = Events.stance(definition, id)
				if stance then
					stanceName = `{id} · {stance.name}`
				end
			end
		end
		return `{eventName or "Event"}: stance {stanceName}`
	end
	return kind
end

-- The name of last week's event (the one a Choice line answers).
local function lastEventName(view: View): string?
	for _, result in view.eventLog do
		local definition = Events.byId[result.id]
		if result.week == view.week - 1 and definition then
			return definition.name
		end
	end
	return nil
end

-- Whether an event belongs in the week's groups.
function Words.shows(event: SimState.Event): boolean
	return RANK[event.kind] ~= nil
end

-- The first `upto` events (default all), merged per side: the same action in
-- the same state on the same issue is one line ("Rally in Texas ×2 · Jobs").
function Words.group(view: View, events: { SimState.Event }, upto: number?): Groups
	local eventName = lastEventName(view)
	local sides: { { Entry } } = { {}, {} }
	local byKey: { { [string]: Entry } } = { {}, {} }
	local n = math.min(upto or #events, #events)
	for k = 1, n do
		local event = events[k]
		if RANK[event.kind] == nil then
			continue
		end
		local player = event.player
		local side = if player == nil or player == view.you then 1 else 2
		local key = event.kind
		if event.kind ~= "Raised" and event.kind ~= "InternalPolls" and event.kind ~= "Flights" then
			key = `{event.kind}|{event.state or ""}|{event.issue or ""}`
		end
		local entry = byKey[side][key]
		if entry == nil then
			entry = {
				key = key,
				kind = event.kind,
				state = event.state,
				issue = event.issue,
				count = 0,
				amount = 0,
				first = k,
			}
			byKey[side][key] = entry
			table.insert(sides[side], entry)
		end
		entry.count += 1
		entry.amount += event.amount or 0
	end
	local out: { { string } } = {}
	for side = 1, 2 do
		local list = sides[side]
		table.sort(list, function(a: Entry, b: Entry): boolean
			local ra, rb = RANK[a.kind], RANK[b.kind]
			if ra ~= rb then
				return ra < rb
			end
			return a.first < b.first
		end)
		local lines: { string } = {}
		for _, entry in list do
			table.insert(lines, entryText(view, entry, eventName))
		end
		out[side] = lines
	end
	return { mine = out[1], theirs = out[2] }
end

-- ---------------------------------------------------------------- what changed

-- Your public-poll margin over your best rival in `s`, or nil without a poll.
local function marginOf(view: View, s: ViewModule.StateView): number?
	local poll = s.poll
	if poll == nil then
		return nil
	end
	local mine = poll.support[view.you] or 0
	local best = 0
	for p, share in poll.support do
		if p ~= view.you and share > best then
			best = share
		end
	end
	return mine - best
end

-- Who leads a margin: you, your rival, or 0 for a tie.
local function leaderOf(view: View, margin: number): number
	if margin > 0 then
		return view.you
	elseif margin < 0 then
		return rivalOf(view)
	end
	return 0
end

-- What moved between two public polls: every state whose leader changed
-- (biggest votes first) and every margin that moved (biggest move first).
function Words.pollChanges(old: View, new: View): Changes
	local flips: { Swing.Flip } = {}
	local moves: { Move } = {}
	for i, s in new.states do
		local before = old.states[i]
		local now = marginOf(new, s)
		local was = if before then marginOf(new, before) else nil
		if now and was then
			local delta = now - was
			if math.abs(delta) >= 0.05 then
				table.insert(moves, { state = s.id, delta = delta, ev = evOf(s.id) })
			end
			local from, to = leaderOf(new, was), leaderOf(new, now)
			if from ~= to then
				table.insert(flips, { state = s.id, from = from, to = to, ev = evOf(s.id) })
			end
		end
	end
	table.sort(flips, function(a: Swing.Flip, b: Swing.Flip): boolean
		if a.ev ~= b.ev then
			return a.ev > b.ev
		end
		return a.state < b.state
	end)
	table.sort(moves, function(a: Move, b: Move): boolean
		if math.abs(a.delta) ~= math.abs(b.delta) then
			return math.abs(a.delta) > math.abs(b.delta)
		end
		return a.state < b.state
	end)
	return { flips = flips, moves = moves }
end

-- "Ohio flips to you · 17 votes", "Ohio flips to Rex · 17 votes",
-- "Ohio slips to a tie · 17 votes".
function Words.flipLine(view: View, flip: Swing.Flip, them: string): string
	local votes = plural(flip.ev, "vote")
	if flip.to == view.you then
		return `{nameOf(flip.state)} flips to you · {votes}`
	elseif flip.to == 0 then
		return `{nameOf(flip.state)} slips to a tie · {votes}`
	end
	return `{nameOf(flip.state)} flips to {them} · {votes}`
end

-- The tone of a flip for you.
function Words.flipTone(view: View, flip: Swing.Flip): Tone
	if flip.to == view.you then
		return "good"
	elseif flip.to == 0 and flip.from ~= view.you then
		return "good"
	end
	return "loss"
end

-- The glyph for a change that went your way (▲) or against you (▼).
function Words.mark(up: boolean): string
	return if up then Words.UP else Words.DOWN
end

-- `text` led by its ▲ or ▼: "▲ Texas flips to you · 40 votes".
function Words.marked(text: string, up: boolean): string
	return `{Words.mark(up)} {text}`
end

-- The reveal's headline once the new polls are in: who flipped how many
-- states. "You flipped 2 · Rex flipped 1", "Rex flipped 1 state",
-- "2 states slipped to a tie", "No state changed leader".
function Words.flipHeadline(view: View, flips: { Swing.Flip }, them: string): string
	local mine, theirs, ties = 0, 0, 0
	for _, flip in flips do
		if flip.to == view.you then
			mine += 1
		elseif flip.to == 0 then
			ties += 1
		else
			theirs += 1
		end
	end
	if mine > 0 and theirs > 0 then
		return `You flipped {mine} · {them} flipped {theirs}`
	elseif mine > 0 then
		return `You flipped {plural(mine, "state")}`
	elseif theirs > 0 then
		return `{them} flipped {plural(theirs, "state")}`
	elseif ties > 0 then
		return `{plural(ties, "state")} slipped to a tie`
	end
	return "No state changed leader"
end

-- "TX +3.0 for you" or "OH +2.0 for Rex".
function Words.movePill(move: Move, them: string): string
	local who = if move.delta > 0 then "you" else them
	return `{move.state} {Numbers.signed(math.abs(move.delta))} for {who}`
end

-- What the map badges after a reveal: every flipped state that moved, plus the
-- `n` (default MAP_MARKS) biggest other moves. Never 30 badges at once.
function Words.topMarks(net: { [string]: number }, flips: { Swing.Flip }, n: number?): { [string]: number }
	local out: { [string]: number } = {}
	for _, flip in flips do
		local points = net[flip.state]
		if points ~= nil then
			out[flip.state] = points
		end
	end
	local rest: { string } = {}
	for id in net do
		if out[id] == nil then
			table.insert(rest, id)
		end
	end
	table.sort(rest, function(a: string, b: string): boolean
		local da, db = math.abs(net[a]), math.abs(net[b])
		if da ~= db then
			return da > db
		end
		if evOf(a) ~= evOf(b) then
			return evOf(a) > evOf(b)
		end
		return a < b
	end)
	for k = 1, math.min(n or Words.MAP_MARKS, #rest) do
		out[rest[k]] = net[rest[k]]
	end
	return out
end

-- ---------------------------------------------------------------- election night

-- A line from the shared helpers (Swing) with "EV" said as "votes".
function Words.inVotes(line: string): string
	return (string.gsub(line, "(%d) EV", "%1 votes"))
end

-- Explain's exact rules in plain words: "3 AP (unused AP is lost)" ->
-- "3 actions (unused actions are lost)", "1 AP" -> "1 action", "EV" -> "votes".
function Words.plain(text: string): string
	local out = Words.inVotes(text)
	out = string.gsub(out, "unused AP is lost", "unused actions are lost")
	out = string.gsub(out, "%f[%w](%d+) AP%f[%W]", function(n: string): string
		return if n == "1" then "1 action" else `{n} actions`
	end)
	out = string.gsub(out, "extra AP%f[%W]", "extra action")
	out = string.gsub(out, "%f[%w]AP%f[%W]", "actions")
	out = string.gsub(out, "%+ EV%f[%W]", "+ votes")
	out = string.gsub(out, "%f[%w]EV%f[%W]", "votes")
	return out
end

function Words.stateLine(id: string): string
	return `{nameOf(id)} · {plural(evOf(id), "vote")}`
end

-- "Dana by 2.9 points", or "Dead heat: no votes".
function Words.callLine(result: SimState.StateResult, names: { string }): string
	if result.winner <= 0 then
		return "Dead heat: no votes"
	end
	return `{names[result.winner] or "?"} by {string.format("%.1f", result.margin)} points`
end

-- ---------------------------------------------------------------- results

-- `tip`: what the loser could try next time against this reason (Words.nextTime).
type Reason = { text: string, weight: number, tip: string }

-- Every reason the winner won, biggest first, from what both players saw:
-- debate topics and the flips debates and stances made, close races, the
-- biggest prize, your own ground game, and the state count.
local function reasonsFor(config: Config, view: View, winner: number, names: { string }): { Reason }
	local election = view.election
	if election == nil or winner <= 0 then
		return {}
	end
	local you = view.you
	local loser = if winner == 1 then 2 else 1
	local who = if winner == you then "You" else names[winner] or "They"
	local whom = if winner == you then "you" else names[winner] or "them"
	local reasons: { Reason } = {}

	-- Debates: topics won, and the poll flips they made.
	local topics, theirTopics, total, flipEV = 0, 0, 0, 0
	for _, result in view.debates do
		for t = 1, #result.topics do
			total += 1
			if result.winners[t] == winner then
				topics += 1
			elseif result.winners[t] == loser then
				theirTopics += 1
			end
		end
		for _, flip in result.flips do
			if flip.to == winner then
				flipEV += evOf(flip.state)
			elseif flip.from == winner then
				flipEV -= evOf(flip.state)
			end
		end
	end
	if total > 0 and topics > theirTopics then
		local text = `{who} won {topics} of {total} debate topics`
		if flipEV > 0 then
			text ..= ` (+{flipEV} votes)`
		end
		table.insert(reasons, {
			text = text,
			weight = 10 * (topics - theirTopics) + math.max(0, flipEV),
			tip = "in debates, pick the move that can't lose",
		})
	end

	-- Stances: the flips both stances made, toward the winner.
	local stanceFlips, stanceEV = 0, 0
	for _, entry in view.eventLog do
		if entry.choices ~= nil then
			local flips: { SimState.PollFlip } = entry.flips or {}
			for _, flip in flips do
				if flip.to == winner then
					stanceFlips += 1
					stanceEV += evOf(flip.state)
				end
			end
		end
	end
	if stanceFlips > 0 then
		table.insert(reasons, {
			text = `Stances flipped {plural(stanceFlips, "state")} to {whom}`,
			weight = stanceEV,
			tip = "pick stances your big states care about",
		})
	end

	-- Close races and the biggest prize.
	local close: { SimState.StateResult } = {}
	local biggest: string? = nil
	local won = 0
	for _, r in election.results do
		if r.winner == winner then
			won += 1
			if r.margin < Words.CLOSE then
				table.insert(close, r)
			end
			if biggest == nil or evOf(r.state) > evOf(biggest :: string) then
				biggest = r.state
			end
		end
	end
	if #close == 1 then
		local r = close[1]
		table.insert(reasons, {
			text = `{who} held {nameOf(r.state)} by {string.format("%.1f", r.margin)} points`,
			weight = evOf(r.state),
			tip = `ground game in close states like {nameOf(r.state)}`,
		})
	elseif #close > 1 then
		local ev = 0
		for _, r in close do
			ev += evOf(r.state)
		end
		table.insert(reasons, {
			text = `{who} won {#close} close races (+{ev} votes)`,
			weight = ev,
			tip = "ground game in the closest states",
		})
	end
	if biggest then
		table.insert(reasons, {
			text = `{who} carried {nameOf(biggest)}, worth {evOf(biggest)} votes`,
			weight = 0.6 * evOf(biggest),
			tip = `fight for {nameOf(biggest)} early`,
		})
	end

	-- Your own ground game, where it made the difference.
	if winner == you then
		local swung: { string } = {}
		for _, r in election.results do
			local i = SimState.indexOf[r.state]
			local s = if i then view.states[i] else nil
			if r.winner == you and s and s.gotv > 0 and r.margin < s.gotv * config.GOTV_PER_UNIT then
				table.insert(swung, r.state)
			end
		end
		if #swung > 0 then
			local ev = 0
			for _, id in swung do
				ev += evOf(id)
			end
			local text = if #swung == 1
				then `Your ground game won {nameOf(swung[1])}`
				else `Your ground game won {#swung} states (+{ev} votes)`
			table.insert(reasons, { text = text, weight = ev, tip = "ground game where you are close" })
		end
	end

	-- Always something: the state count (fewer states can still win on votes).
	local lost = election.statesWon[loser] or 0
	table.insert(reasons, {
		text = if won >= lost
			then `{who} carried {won} states to {lost}`
			else `{who} won the bigger states ({won} to {lost})`,
		weight = 1,
		tip = "rally in states where the polls are close",
	})

	table.sort(reasons, function(a: Reason, b: Reason): boolean
		if a.weight ~= b.weight then
			return a.weight > b.weight
		end
		return a.text < b.text
	end)
	return reasons
end

-- At most three short reasons the winner won, biggest first.
function Words.keyReasons(config: Config, view: View, winner: number, names: { string }): { string }
	local reasons = reasonsFor(config, view, winner, names)
	local out: { string } = {}
	for k = 1, math.min(3, #reasons) do
		table.insert(out, reasons[k].text)
	end
	return out
end

-- One line for the player who lost, against the biggest reason they lost:
-- "Try next time: ground game in the closest states". Nil when you won or
-- nobody did (a winner sees no advice).
function Words.nextTime(config: Config, view: View, winner: number, names: { string }): string?
	if winner <= 0 or winner == view.you then
		return nil
	end
	local top = reasonsFor(config, view, winner, names)[1]
	return if top then `Try next time: {top.tip}` else nil
end

-- ---------------------------------------------------------------- reveal order

-- Whose actions land first in a week's reveal: the player behind on the
-- public polls of `view` (votes of the states each leads), so the leader's
-- answer comes last. On a tie each player sees their own first, so neither
-- screen favors a seat. Returns the player and whether they trail.
function Words.revealFirst(view: View): (number, boolean)
	local rival = rivalOf(view)
	local votes = { [view.you] = 0, [rival] = 0 }
	for _, s in view.states do
		local margin = marginOf(view, s)
		if margin then
			local leader = leaderOf(view, margin)
			if leader ~= 0 then
				votes[leader] += evOf(s.id)
			end
		end
	end
	if votes[view.you] < votes[rival] then
		return view.you, true
	elseif votes[rival] < votes[view.you] then
		return rival, true
	end
	return view.you, false
end

-- The running tally (D-063, Shared/UI/RevealSteps): the last step's name, the
-- line behind "Why?" on the per-move numbers, what the new polls changed, and
-- a leader change at a glance.
Words.SETTLE = "New polls are in"
Words.ESTIMATE_NOTE =
	"≈ Each move's points are estimated from the polls you both saw. The new polls are the real numbers."

-- "Polls shifted 4 states" (the leader changes the new polls made on top of the moves).
function Words.pollShift(flips: number): string
	if flips == 0 then
		return "Polls moved a little · no state changed hands"
	end
	return `Polls shifted {plural(flips, "state")}`
end

-- A leader change in a few characters: "OH → you +17", "OH → Rex +17", "OH → tie".
function Words.leaderArrow(view: View, flip: Swing.Flip, them: string): string
	if flip.to == 0 then
		return `{flip.state} → tie`
	end
	local who = if flip.to == view.you then "you" else them
	return `{flip.state} → {who} +{flip.ev}`
end

-- The line under "Both plans are in": who goes first, and why.
function Words.orderLine(view: View, first: number, trails: boolean, them: string): string
	if first ~= view.you then
		return `{them} trails, so {them}'s actions land first`
	elseif trails then
		return "You trail, so your actions land first"
	end
	return "Your actions land first"
end

-- ---------------------------------------------------------------- help

function Words.help(config: Config): { Tab }
	local debateWeeks: { string } = {}
	for _, week in config.DEBATE_WEEKS do
		table.insert(debateWeeks, tostring(week))
	end
	return {
		{
			id = "win",
			label = "How to win",
			title = "How to win",
			text = `Every state is worth votes. Win a state and you get all of its votes. After week {config.WEEKS}, election night counts them: the first to {config.EV_TO_WIN} wins. Polls show who leads each state, but they can be a few points off, so close states can go either way.`,
			sections = { "election" },
		},
		{
			id = "turn",
			label = "Your turn",
			title = "Your turn",
			text = `Each week you get {config.AP_PER_WEEK} actions and some money. Tap a state, pick an action, repeat, then press Lock in. Your opponent plans at the same time, in secret. When both lock in, the week plays out and new polls come in. Rallies move you; a far stop costs a flight.`,
			sections = { "flights", "map" },
		},
		{
			id = "actions",
			label = "Actions",
			title = "Actions",
			text = "Rallies and ads count extra on your 3 issues, in states that care about them. Money pays for ads, polls and ground game, so fundraise when you run low.",
			sections = { "actions" },
		},
		{
			id = "events",
			label = "Events",
			title = "Events & debates",
			text = `Most weeks have an event. Some boost an issue or a region. Others make you take a side, A, B or C, in secret; states that care react. Debates come in weeks {table.concat(
				debateWeeks,
				" and "
			)}: three live rounds. Pick Defend, Attack or Pivot; each shows how it does. Win a round and its states swing your way.`,
			sections = { "events", "debates" },
		},
		{
			id = "polls",
			label = "Polls",
			title = "Polls & ground game",
			text = "Public polls are a rough guide: they can be a few points off for weeks. Your own poll shows the real numbers in a state, and your opponent's hidden ground game there. Ground game adds votes only on election night, so use it in close states.",
			sections = { "polls", "ground" },
		},
	}
end

-- The six actions for the Help "Actions" tab: name and one short line.
Words.ACTIONS = table.freeze({
	{ name = "Rally", text = "Win support in one state" },
	{ name = "Fundraise", text = "Raise money, more where you lead" },
	{ name = "Ad", text = "Win support from anywhere" },
	{ name = "Attack ad", text = "Cut your opponent's support" },
	{ name = "Poll", text = "See the real numbers in a state" },
	{ name = "Ground game", text = "Extra votes on election night" },
})

return table.freeze(Words)
