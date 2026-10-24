--!strict
-- The Daily Race's scoring, streak and board (docs/DESIGN.md D-080). Pure: the
-- server's DailyService does the OrderedDataStore, the names and the profile
-- writes and uses these rules; Sim/Daily derives the race itself from the day.
--
-- Scoring. A counted run scores its final electoral-vote margin over the bot
-- (yours minus the bot's, -538 to +538). Equal margins are split by fewer weeks
-- behind in the weekly polls (the public projected votes, View.pollHistory),
-- then by who finished first that UTC day. One whole number carries all three
-- (Daily.score), so the board is one OrderedDataStore read. A counted run that
-- is left (or abandoned) after week 1 began scores Config.DAILY_FORFEIT_MARGIN.
--
-- One counted run a day: the first Daily Race run of the day that reaches week
-- 1 (D-077's line: leaving before then counts for nothing). Later runs that day
-- are practice and say so. The run is saved in the profile (Profile.daily).
--
-- Streak: consecutive UTC days with a counted run. A missed day just shows 0
-- again (Daily.streak); nothing else happens.

local ConfigModule = require("../Sim/Config")
local Leaderboard = require("./Leaderboard")

type Config = ConfigModule.Config

local Daily = {}

Daily.STORE = "DailyRace_v1" -- the OrderedDataStore's name; its scope is the day's "YYYY-MM-DD" (UTC)
Daily.TOP = Leaderboard.TOP -- entries the server caches and the sheet lists
Daily.REFRESH = Leaderboard.REFRESH -- seconds: the cached list is read again at most this often
Daily.MARGIN_MAX = 538 -- every electoral vote
Daily.BEHIND_MAX = 99 -- weeks behind counted (a match has 12 poll weeks)
Daily.TIME_SLOT = 100000 -- > the seconds in a day: the score's last digits are the finish time
local DAY = 86400

-- A player's Daily Race record, saved in their profile.
export type Record = {
	last: number, -- the day of their last counted run
	streak: number, -- consecutive days with a counted run, ending on `last`
	best: number, -- their longest streak
	margin: number?, -- day `last`'s counted run: its final margin; nil until it ends
	behind: number?, -- its weeks behind in the polls
	score: number?, -- its board value (Daily.score)
}

-- One row of a day's board.
export type Entry = {
	rank: number, -- 1 = the best score
	id: string, -- the player's UserId as a string
	name: string,
	margin: number,
	score: number,
}

export type Status = Leaderboard.Status

-- Where the viewer stands today. Absent until their counted run has a score.
export type You = {
	rank: number?, -- their place, when they are in the cached top list
	margin: number,
}

export type Board = {
	status: Status,
	entries: { Entry }, -- best first, at most TOP
	you: You?,
}

-- The run that just ended, for the Results screen.
export type Run = {
	matchId: string,
	counted: boolean, -- false: a practice run (today's counted run was already used, or could not be saved)
	margin: number,
	forfeit: boolean, -- left or abandoned: scored DAILY_FORFEIT_MARGIN
	rank: number?, -- the counted run's place today, when it made the cached top list
}

-- What one player is told about today's race (message kind "Daily").
export type Info = {
	day: number,
	date: string, -- "YYYY-MM-DD"
	candidate: string, -- everyone's candidate today
	botCandidate: string,
	level: string, -- the bot's level
	endsAt: number, -- Unix seconds (workspace:GetServerTimeNow() scale) the race ends
	played: boolean, -- today's counted run has begun: another run is practice
	margin: number?, -- today's counted run's margin, once it ended
	streak: number, -- shown streak: 0 once a day was missed
	best: number, -- longest streak
	board: Board,
	run: Run?, -- only right after a Daily Race run ends
}

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

local function whole(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return math.floor(value)
end

-- ------------------------------------------------------------------ scoring

-- Weeks the player trailed in the weekly polls: polls where their projected
-- votes were below someone else's. `history` is View.pollHistory (oldest first).
function Daily.weeksBehind(history: { any }?, me: number): number
	local behind = 0
	local points: { any } = history or {}
	for _, point in points do
		local ev = point.ev
		local mine = ev[me] or 0
		for p, votes in ev do
			if p ~= me and votes > mine then
				behind += 1
				break
			end
		end
	end
	return behind
end

-- The board value of a run on day `day`: margin first, then fewer weeks behind,
-- then an earlier finish (`finishedAt`, Unix seconds). Higher is better.
function Daily.score(margin: number, behind: number, finishedAt: number, day: number): number
	local m = clamp(math.floor(margin), -Daily.MARGIN_MAX, Daily.MARGIN_MAX) + Daily.MARGIN_MAX
	local b = Daily.BEHIND_MAX - clamp(math.floor(behind), 0, Daily.BEHIND_MAX)
	local t = DAY - 1 - clamp(math.floor(finishedAt - day * DAY), 0, DAY - 1)
	return (m * (Daily.BEHIND_MAX + 1) + b) * Daily.TIME_SLOT + t
end

-- A board value back as (margin, weeks behind, seconds into the day it finished).
function Daily.decode(score: number): (number, number, number)
	local t = score % Daily.TIME_SLOT
	local rest = (score - t) / Daily.TIME_SLOT
	local b = rest % (Daily.BEHIND_MAX + 1)
	local m = (rest - b) / (Daily.BEHIND_MAX + 1)
	return m - Daily.MARGIN_MAX, Daily.BEHIND_MAX - b, DAY - 1 - t
end

-- ------------------------------------------------------------------ streak

-- The streak to show on day `today`: the saved one while its last counted day
-- is today or yesterday, else 0 (a missed day resets it, nothing more).
function Daily.streak(record: Record?, today: number): number
	if record == nil or record.last < today - 1 then
		return 0
	end
	return record.streak
end

-- Has day `day`'s counted run begun?
function Daily.counted(record: Record?, day: number): boolean
	return record ~= nil and record.last >= day
end

-- The record once day `day`'s counted run begins (week 1): the streak grows by
-- one after yesterday, starts at 1 after a gap. Unchanged if it already began.
function Daily.begin(record: Record?, day: number): Record
	if record ~= nil and Daily.counted(record, day) then
		return record
	end
	local streak = if record ~= nil and record.last == day - 1 then record.streak + 1 else 1
	local best = math.max(streak, if record then record.best else 0)
	return { last = day, streak = streak, best = best, margin = nil, behind = nil, score = nil }
end

-- The record once day `day`'s counted run ended with `margin` (the first end
-- only: a later call, or one for another day, changes nothing).
function Daily.finish(record: Record?, day: number, margin: number, behind: number, score: number): Record?
	if record == nil or record.last ~= day or record.score ~= nil then
		return record
	end
	local out = table.clone(record)
	out.margin = math.floor(margin)
	out.behind = math.floor(behind)
	out.score = score
	return out
end

-- A stored record, cleaned (garbage defense), or nil.
function Daily.clean(raw: any): Record?
	if type(raw) ~= "table" then
		return nil
	end
	local last, streak = whole(raw.last), whole(raw.streak)
	if last == nil or streak == nil or streak < 1 then
		return nil
	end
	local best = math.max(whole(raw.best) or streak, streak)
	local margin, behind, score = whole(raw.margin), whole(raw.behind), whole(raw.score)
	if margin == nil or behind == nil or score == nil then
		margin, behind, score = nil, nil, nil
	end
	return {
		last = last,
		streak = streak,
		best = best,
		margin = if margin then clamp(margin, -Daily.MARGIN_MAX, Daily.MARGIN_MAX) else nil,
		behind = behind,
		score = score,
	}
end

-- ------------------------------------------------------------------ board

-- Best first; equal scores in a fixed order (the smaller id first), ranked and cut to TOP.
local function rank(entries: { Entry }): { Entry }
	table.sort(entries, function(a: Entry, b: Entry): boolean
		if a.score ~= b.score then
			return a.score > b.score
		end
		if #a.id ~= #b.id then
			return #a.id < #b.id
		end
		return a.id < b.id
	end)
	local out: { Entry } = {}
	for k, entry in entries do
		if k > Daily.TOP then
			break
		end
		table.insert(
			out,
			{ rank = k, id = entry.id, name = entry.name, margin = entry.margin, score = entry.score }
		)
	end
	return out
end

local function entryOf(id: string, name: string, score: number): Entry
	local margin = Daily.decode(score)
	return { rank = 0, id = id, name = name, margin = margin, score = score }
end

-- A store page ({ key, value } rows) as ranked entries. Keys and values this
-- game would not write are skipped; a repeated id keeps its first row.
function Daily.fromPage(rows: { any }, nameOf: (id: string) -> string): { Entry }
	local entries: { Entry } = {}
	local seen: { [string]: boolean } = {}
	for _, row in rows do
		if type(row) ~= "table" then
			continue
		end
		local id = Leaderboard.idOf(row.key)
		local score = whole(row.value)
		if id == nil or score == nil or score < 0 or seen[id] then
			continue
		end
		seen[id] = true
		table.insert(entries, entryOf(id, nameOf(id), score))
	end
	return rank(entries)
end

-- The list with one player's score in it, without waiting for the next read.
function Daily.patch(entries: { Entry }, id: string, name: string, score: number): { Entry }
	local out: { Entry } = {}
	for _, entry in entries do
		if entry.id ~= id then
			table.insert(out, table.clone(entry))
		end
	end
	table.insert(out, entryOf(id, name, math.floor(score)))
	return rank(out)
end

function Daily.rankOf(entries: { Entry }, id: string): number?
	for _, entry in entries do
		if entry.id == id then
			return entry.rank
		end
	end
	return nil
end

-- What viewer `id` is sent: the list, and where they stand once their counted
-- run today has a score (`record` is their saved record).
function Daily.board(status: Status, entries: { Entry }, id: string, record: Record?, day: number): Board
	local copy: { Entry } = {}
	for k, entry in entries do
		copy[k] = table.clone(entry)
	end
	local place = Daily.rankOf(entries, id)
	local you: You? = nil
	if place then
		you = { rank = place, margin = entries[place].margin }
	elseif record and record.last == day and record.margin ~= nil then
		you = { rank = nil, margin = record.margin }
	end
	return { status = status, entries = copy, you = you }
end

-- "+62", "-40", "0": a margin as the board shows it.
function Daily.marginText(margin: number): string
	if margin > 0 then
		return `+{margin}`
	elseif margin < 0 then
		return `-{-margin}`
	end
	return "0"
end

-- The forfeit score's margin (Config).
function Daily.forfeitMargin(config: Config?): number
	local c = config or ConfigModule.defaults
	return c.DAILY_FORFEIT_MARGIN
end

return table.freeze(Daily)
