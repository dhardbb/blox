--!strict
-- The end screen's map (docs/DESIGN.md D-073): the final public polls against
-- election night, state by state, and the states the polls called wrong. Pure;
-- reads only the player's own View once the election is in (`view.election`).
--
--   PollMiss.rows(view) -> { Row }              every state, in View order
--   PollMiss.misses(rows) -> { Row }            the states the polls got wrong, most votes first
--   PollMiss.summary(misses) -> string          "Polls missed 3 states: NV, WI, AZ"
--   PollMiss.mapStates(view, rows, mode)        the View's states as the map paints them
--   PollMiss.votes(rows, mode, players)         votes by player: projected (polls) or won (result)
--   PollMiss.lead(row, mode) -> (number, number) the shown leader and their lead in points
--   PollMiss.leadText(lead) -> string            the map's pill: "+3", "+0.4"
--   PollMiss.votesLine(mode, ev, you, names)     "Final polls: you 290, Rex 248"
--   PollMiss.stateLine(row, you, names)          a tapped state: its poll, its result, a miss
--
-- "Final polls" is each state's last public poll (the one published after the
-- last week, View.states[i].poll): its leader and lead, as both players saw it.
-- "Real results" is election night (`view.election.results`): winner and margin.
-- A state is a miss when the poll had a leader, the count had a winner, and they
-- differ. A tied poll called nobody, so it cannot miss.

local ViewModule = require("../Sim/View")
local StateData = require("../Sim/StateData")

type View = ViewModule.View
type StateView = ViewModule.StateView

export type Mode = "Polls" | "Result"

export type Row = {
	id: string,
	ev: number,
	pollLeader: number, -- 0: tied, or no poll
	pollLead: number, -- points: the leader's share minus the runner-up's (0 on a tie)
	winner: number, -- election night's winner, 0 on an exact tie
	margin: number, -- points: the winner's final score minus the runner-up's
	miss: boolean,
}

local PollMiss = {}

PollMiss.MODES = table.freeze({ "Polls", "Result" } :: { Mode })
PollMiss.LIST_MAX = 6 -- states named in the summary line; more read "+2 more"
-- The map paints a result at least this many points wide, so a narrow win still
-- shows its winner's color (a lead under 3 is a grey toss-up on the poll map).
PollMiss.RESULT_MIN_LEAD = 3

-- Leader (0 on a tie or with no shares) and the lead over the runner-up.
local function leaderOf(shares: { number }?): (number, number)
	if shares == nil or #shares == 0 then
		return 0, 0
	end
	local best, second, leader = -math.huge, -math.huge, 0
	for p, share in shares do
		if share > best then
			second, best, leader = best, share, p
		elseif share == best then
			second, leader = share, 0
		elseif share > second then
			second = share
		end
	end
	if leader == 0 then
		return 0, 0
	end
	if second == -math.huge then
		second = 0
	end
	return leader, best - second
end

function PollMiss.rows(view: View): { Row }
	local results: { [string]: { winner: number, margin: number } } = {}
	local election = view.election
	if election then
		for _, r in election.results do
			results[r.state] = { winner = r.winner, margin = r.margin }
		end
	end
	local rows: { Row } = {}
	for _, s in view.states do
		local record = StateData.byId[s.id]
		local poll = s.poll
		local leader, lead = leaderOf(if poll then poll.support else nil)
		local result = results[s.id]
		local winner = if result then result.winner else 0
		table.insert(rows, {
			id = s.id,
			ev = if record then record.ev else 0,
			pollLeader = leader,
			pollLead = lead,
			winner = winner,
			margin = if result then result.margin else 0,
			miss = leader ~= 0 and winner ~= 0 and leader ~= winner,
		})
	end
	return rows
end

-- The misses, most votes first (then by state id, so the order is stable).
function PollMiss.misses(rows: { Row }): { Row }
	local out: { Row } = {}
	for _, row in rows do
		if row.miss then
			table.insert(out, row)
		end
	end
	table.sort(out, function(a, b)
		if a.ev ~= b.ev then
			return a.ev > b.ev
		end
		return a.id < b.id
	end)
	return out
end

-- One line under the map: "Polls missed 3 states: NV, WI, AZ" (the first
-- LIST_MAX by votes, then "+2 more"), "Polls missed 1 state: NV", or "The final
-- polls called every state right."
function PollMiss.summary(misses: { Row }): string
	local n = #misses
	if n == 0 then
		return "The final polls called every state right."
	end
	local ids: { string } = {}
	for k = 1, math.min(n, PollMiss.LIST_MAX) do
		table.insert(ids, misses[k].id)
	end
	local list = table.concat(ids, ", ")
	if n > PollMiss.LIST_MAX then
		list ..= ` +{n - PollMiss.LIST_MAX} more`
	end
	return `Polls missed {n} {if n == 1 then "state" else "states"}: {list}`
end

-- The leader and the lead a mode shows for a state.
function PollMiss.lead(row: Row, mode: Mode): (number, number)
	if mode == "Polls" then
		return row.pollLeader, row.pollLead
	end
	return row.winner, row.margin
end

-- Votes each player gets in a mode: the final polls' projection (tied states for
-- nobody, as the header counted) or what election night awarded.
function PollMiss.votes(rows: { Row }, mode: Mode, players: number): { number }
	local ev = table.create(players, 0)
	for _, row in rows do
		local leader = PollMiss.lead(row, mode)
		if leader ~= 0 and ev[leader] ~= nil then
			ev[leader] += row.ev
		end
	end
	return ev
end

-- The View's states as the map paints a mode: the polls as they were, or each
-- state's result as a poll whose lead is its margin (at least RESULT_MIN_LEAD),
-- an exact tie as an even split. Leans are cleared in the result mode, so a
-- state is never painted by its lean. Copies; the View is not changed.
function PollMiss.mapStates(view: View, rows: { Row }, mode: Mode): { StateView }
	local byId: { [string]: Row } = {}
	for _, row in rows do
		byId[row.id] = row
	end
	local n = #view.players
	local out: { StateView } = {}
	for i, s in view.states do
		local copy = table.clone(s)
		local row = byId[s.id]
		if mode == "Result" and row then
			copy.lean = 0
			copy.leanTo = nil
			local support = table.create(n, 50)
			if row.winner ~= 0 then
				local lead = math.max(row.margin, PollMiss.RESULT_MIN_LEAD)
				for p = 1, n do
					support[p] = if p == row.winner then 50 + lead / 2 else 50 - lead / 2
				end
			end
			copy.poll = { support = support, undecided = 0 }
		end
		out[i] = copy
	end
	return out
end

-- The lead on a state's pill: whole points, or one decimal under 1 point (a
-- real 0.4-point win is not a tie).
function PollMiss.leadText(lead: number): string
	if lead < 0.95 then
		return string.format("+%.1f", lead)
	end
	return `+{math.floor(lead + 0.5)}`
end

local MODE_TITLE: { [Mode]: string } = { Polls = "Final polls", Result = "Election night" }

local function nameOf(p: number, you: number, names: { string }): string
	return if p == you then "you" else (names[p] or `Player {p}`)
end

-- "Final polls: you 290, Rex 248" / "Election night: you 302, Rex 236": you first.
function PollMiss.votesLine(mode: Mode, ev: { number }, you: number, names: { string }): string
	local parts = { `you {ev[you] or 0}` }
	for p, votes in ev do
		if p ~= you then
			table.insert(parts, `{nameOf(p, you, names)} {votes}`)
		end
	end
	return `{MODE_TITLE[mode]}: {table.concat(parts, ", ")}`
end

-- A tapped state: "Nevada · 6 votes. Final poll: Rex +1. Result: you by 2.4
-- points. The polls missed it."
function PollMiss.stateLine(row: Row, you: number, names: { string }): string
	local record = StateData.byId[row.id]
	local title =
		`{if record then record.name else row.id} · {row.ev} {if row.ev == 1 then "vote" else "votes"}`
	local poll = if row.pollLeader == 0
		then "Final poll: tied"
		else `Final poll: {nameOf(row.pollLeader, you, names)} {PollMiss.leadText(row.pollLead)}`
	local result = if row.winner == 0
		then "Result: tied"
		else `Result: {nameOf(row.winner, you, names)} by {string.format("%.1f", row.margin)} points`
	local tail = if row.miss then " The polls missed it." else ""
	return `{title}. {poll}. {result}.{tail}`
end

return table.freeze(PollMiss)
