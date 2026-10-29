--!strict
-- One finished match as a record for balance analysis (docs/DESIGN.md D-094).
-- Pure: the server's MatchLog builds it from the session when the match ends,
-- checks its size and writes it to the "MatchRecords_v1" DataStore under
-- MatchRecord.key (one key per match, prefixed by its UTC date so a day's
-- records list with one prefix). tests/harness/records.luau reads exported
-- records back (JSON lines) and prints a balance summary.
--
-- What it holds: plain data only (strings, numbers, booleans, arrays and
-- string-keyed tables), so it goes straight into a DataStore and out as JSON.
-- No names, custom names or chat: a human is their UserId (as a string), a
-- bot is "bot". Everything else is what both players saw by the end of the
-- match (the plans, stances and moves are revealed by then) plus the seed.
--
-- Plans are compact strings, one per action ("Rally:OH:Jobs", "Gotv:PA:3",
-- "Pivot:Health>Transit", "RegionPoll:West", "Attack:OH:Jobs"), so a 12-week
-- record stays a few kilobytes. MatchRecord.fit drops detail (plans, then
-- debate rounds) if a record ever passes MAX_CHARS.

local Candidates = require("../Sim/Candidates")
local ConfigModule = require("../Sim/Config")
local Election = require("../Sim/Election")
local State = require("../Sim/State")

type Config = ConfigModule.Config

local MatchRecord = {}

MatchRecord.SCHEMA = 1 -- bump when a field is renamed or reshaped; readers check `v`
MatchRecord.STORE = "MatchRecords_v1" -- the DataStore's name
-- Largest record written, in JSON characters. DataStore values may be up to
-- 4,194,304 characters, but every write counts towards the experience's 4 MB a
-- minute per key and its storage quota (500 MB + 1 MB per lifetime user), so
-- records are kept small: a typical one is 3-5 KB.
MatchRecord.MAX_CHARS = 64000
MatchRecord.MAX_KEY = 50 -- DataStore key names are at most 50 characters

-- How the match was made.
export type Mode =
	"Queue" -- the public queue, a match server it made, or a rematch of one
	| "Private" -- a private code (or its rematch)
	| "Practice" -- against the bot from the Lobby
	| "WaitBot" -- against the bot while waiting in the queue (D-083)
	| "Tutorial" -- the tutorial (D-075)
	| "Daily" -- the Daily Race (D-082)

-- What the server knows about a match beyond its session.
export type Info = {
	mode: Mode,
	rated: boolean, -- moved ratings (human vs human, both ratings known, not unrated)
	version: string, -- the game version (Version.VERSION)
	at: number, -- Unix time it ended
	ended: number, -- server time it ended (the clock the session's startedAt is on)
	server: string, -- an id unique per server (its JobId, or "studio")
}

export type Seat = {
	id: string, -- a UserId as a string, or "bot"
	kind: "Human" | "Bot",
	candidate: string,
	platform: { string },
	home: string?,
	strongholds: { string },
	level: string?, -- a bot's practice level (D-057)
	style: string?, -- a bot's play style
}

export type Stance = { week: number, event: string, choices: { string } }

export type Round = {
	topic: string,
	picks: { string }, -- by seat
	zingers: { boolean },
	canned: { boolean }, -- timed out: the canned answer
	winner: number, -- 0 = a split
}

export type Debate = {
	week: number,
	rounds: { Round },
	crowd: { number }, -- by seat
	ovation: number, -- 0 = none
}

export type Record = {
	v: number, -- MatchRecord.SCHEMA
	id: string, -- unique across servers
	version: string,
	mode: Mode,
	rated: boolean,
	level: string?, -- the bot's level in a bot match
	deck: boolean, -- the event deck was on (D-027)
	tutorial: boolean,
	seed: number,
	at: number, -- Unix time it ended
	duration: number, -- seconds from the session's start to its end
	weeks: number, -- campaign weeks planned (12 when it reached election night; the tutorial plays fewer)
	seats: { Seat },
	draft: { string }, -- "round:seat:STATE:Home|Nominate", in order
	plans: { { { string } } }?, -- [week][seat] -> actions; nil when MatchRecord.fit dropped them
	stances: { Stance },
	debates: { Debate },
	events: { string }, -- "week:eventId", every resolved event
	projected: { { number } }, -- [k] = { week, ev seat 1, ev seat 2, ... } each time the weekly polls came out
	ev: { number }?, -- final electoral votes by seat; nil without an election night
	decidedBy: string?, -- "EV" | "States" | "Popular" | "Coin"
	reason: string, -- "Election" | "Forfeit" | "Abandoned"
	winner: number, -- seat index, 0 = nobody or shared
	landslide: boolean,
	unrated: boolean?, -- why a human match did not move ratings (D-077, D-081)
	forfeits: { number }, -- seats that forfeited or were dropped for missing weeks
	timeouts: { string }, -- "Phase:week:seat" for every input stage a seat let run out
	trimmed: boolean?, -- MatchRecord.fit dropped detail to stay under MAX_CHARS
}

-- Anything the session needs to provide (a Net/Session.Session fits).
export type SessionLike = {
	id: string,
	config: Config,
	match: State.MatchState,
	seats: { any },
	result: any?,
	tutorial: boolean,
	startedAt: number,
	log: { plans: { any }, timeouts: { any } },
}

-- ---------------------------------------------------------------- helpers

local function text(value: any, limit: number?): string
	local s = if type(value) == "string" then value else tostring(value)
	return string.sub(s, 1, limit or 32)
end

-- One plan action as a compact string.
function MatchRecord.action(action: any): string
	if type(action) ~= "table" then
		return "?"
	end
	local kind = text(action.kind, 16)
	if kind == "Pivot" then
		return `Pivot:{text(action.drop)}>{text(action.add)}`
	elseif kind == "RegionPoll" then
		return `RegionPoll:{text(action.region)}`
	end
	local out = `{kind}:{text(action.state or "?", 4)}`
	if action.issue ~= nil then
		out ..= `:{text(action.issue)}`
	end
	if action.units ~= nil then
		out ..= `:{text(action.units, 6)}`
	end
	if action.target ~= nil and kind == "Attack" then
		out ..= `@{text(action.target, 4)}`
	end
	return out
end

local function strings(list: { any }?): { string }
	local out: { string } = {}
	local items: { any } = list or {}
	for k, value in items do
		out[k] = text(value)
	end
	return out
end

local function booleans(list: { any }?, n: number): { boolean }
	local out: { boolean } = {}
	for k = 1, n do
		out[k] = (list or {})[k] == true
	end
	return out
end

-- Days since 1970-01-01 to a civil date (proleptic Gregorian, H. Hinnant's
-- days_from_civil inverse). Pure: no os.date.
local function civil(days: number): (number, number, number)
	local z = days + 719468
	local era = (if z >= 0 then z else z - 146096) // 146097
	local doe = z - era * 146097
	local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
	local y = yoe + era * 400
	local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
	local mp = (5 * doy + 2) // 153
	local d = doy - (153 * mp + 2) // 5 + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	if m <= 2 then
		y += 1
	end
	return y, m, d
end

-- "YYYYMMDD" for Unix time `at` (UTC).
function MatchRecord.day(at: number): string
	local y, m, d = civil(math.floor(at / 86400))
	return string.format("%04d%02d%02d", y, m, d)
end

-- The record's DataStore key: "<YYYYMMDD>_<server>_<match id>_<seed>" (the
-- server's id cut to 8 letters and digits), at most MAX_KEY characters. The
-- date leads, so Open Cloud's list filter `id.startsWith("20261029_")` returns
-- one day's records.
function MatchRecord.key(record: Record): string
	local parts = string.split(record.id, "/")
	local server = string.sub(string.gsub(parts[1] or "", "[^%w]", ""), 1, 8)
	local match = string.sub(string.gsub(parts[2] or "", "[^%w]", ""), 1, 10)
	local key = `{MatchRecord.day(record.at)}_{server}_{match}_{record.seed}`
	return string.sub(key, 1, MatchRecord.MAX_KEY)
end

-- ---------------------------------------------------------------- build

-- The record for a finished session. Never throws on a well-formed session;
-- the server still calls it in a pcall.
function MatchRecord.build(session: SessionLike, info: Info): Record
	local match = session.match
	local config = session.config
	local seats: { Seat } = {}
	for p, seat in session.seats do
		local player = match.players[p]
		local human = seat.kind == "Human"
		seats[p] = {
			id = if human then text(seat.id) else "bot",
			kind = if human then "Human" else "Bot",
			candidate = if player then text(player.candidate) else "?",
			platform = if player then strings(player.platform) else {},
			home = if player and player.home then text(player.home, 4) else nil,
			strongholds = if player then strings(player.strongholds) else {},
			level = if not human and seat.botDifficulty then text(seat.botDifficulty) else nil,
			style = if not human and seat.botStyle then text(seat.botStyle) else nil,
		}
	end
	local n = #seats

	local draft: { string } = {}
	for _, pick in match.draftLog do
		table.insert(draft, `{pick.round}:{pick.player}:{pick.state}:{pick.kind}`)
	end

	local plans: { { { string } } } = {}
	for _, entry in session.log.plans do
		local week = math.max(1, math.floor(entry.week))
		for w = #plans + 1, week do
			plans[w] = {}
			for p = 1, n do
				plans[w][p] = {}
			end
		end
		local actions: { string } = {}
		local plan = entry.plan
		if type(plan) == "table" and type(plan.actions) == "table" then
			for _, action in plan.actions do
				table.insert(actions, MatchRecord.action(action))
			end
		end
		if plans[week][entry.seat] ~= nil then
			plans[week][entry.seat] = actions
		end
	end

	local stances: { Stance } = {}
	local events: { string } = {}
	for _, event in match.eventLog do
		table.insert(events, `{event.week}:{event.id}`)
		if event.choices then
			table.insert(
				stances,
				{ week = event.week, event = text(event.id), choices = strings(event.choices) }
			)
		end
	end

	local debates: { Debate } = {}
	for _, debate in match.debates do
		local rounds: { Round } = {}
		local played: { any } = debate.rounds or {}
		for _, round in played do
			table.insert(rounds, {
				topic = text(round.topic),
				picks = strings(round.picks),
				zingers = booleans(round.zingers, n),
				canned = booleans(round.canned, n),
				winner = round.winner,
			})
		end
		table.insert(debates, {
			week = debate.week,
			rounds = rounds,
			crowd = table.clone(debate.crowd or {}),
			ovation = debate.ovation or 0,
		})
	end

	local projected: { { number } } = {}
	for _, point in match.pollHistory do
		local row = { point.week }
		for p = 1, n do
			table.insert(row, point.ev[p] or 0)
		end
		table.insert(projected, row)
	end

	local result = session.result or { winner = 0, reason = "Abandoned" }
	-- Only an election shown to the players counts (a forfeit can follow the
	-- last plan, after the election was computed but before anyone saw it).
	local election = if result.reason == "Election" then match.election else nil
	local landslide = election ~= nil and Election.landslide(config, election) ~= nil

	local forfeits: { number } = {}
	if result.reason == "Forfeit" then
		local winners = result.winners or (if result.winner ~= 0 then { result.winner } else {})
		for p = 1, n do
			if table.find(winners, p) == nil then
				table.insert(forfeits, p)
			end
		end
	end
	local timeouts: { string } = {}
	for _, t in session.log.timeouts do
		table.insert(timeouts, `{t.phase}:{t.week}:{t.seat}`)
	end

	local bot: Seat? = nil
	for _, seat in seats do
		if seat.kind == "Bot" then
			bot = seat
		end
	end

	return {
		v = MatchRecord.SCHEMA,
		id = `{text(info.server, 40)}/{text(session.id)}/{match.seed}`,
		version = text(info.version, 16),
		mode = info.mode,
		rated = info.rated,
		level = if bot then bot.level else nil,
		deck = config.EVENTS_ENABLED ~= false,
		tutorial = session.tutorial,
		seed = match.seed,
		at = math.floor(info.at),
		duration = math.max(0, math.floor(info.ended - session.startedAt + 0.5)),
		weeks = #plans,
		seats = seats,
		draft = draft,
		plans = plans,
		stances = stances,
		debates = debates,
		events = events,
		projected = projected,
		ev = if election then table.clone(election.ev) else nil,
		decidedBy = if election then election.decidedBy else nil,
		reason = text(result.reason),
		winner = result.winner or 0,
		landslide = landslide,
		unrated = if result.unrated then true else nil,
		forfeits = forfeits,
		timeouts = timeouts,
		trimmed = nil,
	}
end

-- `record`, cut down until `measure(record)` (its JSON length) is at most
-- MAX_CHARS: first the plans go, then each debate's rounds. Returns the record
-- and its size; nil if even the cut-down record is too big.
function MatchRecord.fit(record: Record, measure: (any) -> number): (Record?, number)
	local size = measure(record)
	if size <= MatchRecord.MAX_CHARS then
		return record, size
	end
	local out = table.clone(record)
	out.trimmed = true
	out.plans = nil
	size = measure(out)
	if size <= MatchRecord.MAX_CHARS then
		return out, size
	end
	local debates: { Debate } = {}
	for k, debate in out.debates do
		debates[k] = { week = debate.week, rounds = {}, crowd = debate.crowd, ovation = debate.ovation }
	end
	out.debates = debates
	size = measure(out)
	if size <= MatchRecord.MAX_CHARS then
		return out, size
	end
	return nil, size
end

-- The candidate's display name for a summary (records hold ids).
function MatchRecord.candidateName(id: string): string
	if Candidates.exists(id) then
		return Candidates.profile(ConfigModule.defaults, id).name
	end
	return id
end

return table.freeze(MatchRecord)
