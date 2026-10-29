--!strict
-- A player's saved record: rating, win/loss totals, per-candidate stats and the
-- last matches. Pure data in, pure data out: DataService stores it, MatchService
-- applies results to it. Every function returns new tables and never mutates its
-- arguments, so a profile that is being saved is never changed under the save.
--
-- The record is plain data (tables, numbers, strings, booleans) so it can go
-- straight into a DataStore. See docs/DESIGN.md D-028 for the format.

local Candidates = require("../Sim/Candidates")
local ConfigModule = require("../Sim/Config")
local CustomName = require("./CustomName")
local Daily = require("./Daily")
local Rating = require("./Rating")

type Config = ConfigModule.Config

export type Reason = "Election" | "Forfeit" | "Abandoned"

export type CandidateRecord = {
	wins: number,
	losses: number,
}

-- One finished rated match, from this player's side.
export type Recent = {
	at: number, -- Unix time the match ended
	opponentRating: number, -- the opponent's rating before the match
	candidate: string, -- who this player ran
	opponentCandidate: string,
	won: boolean,
	evFor: number?, -- final electoral votes; absent when there was no election night (forfeit)
	evAgainst: number?,
	reason: "Election" | "Forfeit",
}

export type Profile = {
	version: number,
	rating: number,
	games: number, -- rated games played
	wins: number,
	losses: number,
	perCandidate: { [string]: CandidateRecord }, -- rated games by candidate id
	recent: { Recent }, -- oldest first, at most Profile.RECENT_MAX
	practice: { games: number, wins: number, losses: number }, -- vs the bot; never rated
	-- The player's chosen color, one of Candidates.colors; nil = auto (red or blue).
	-- Saved for anyone, used only while they own the Color Pass (D-055). Added
	-- after version 1 without a bump: older profiles simply have none.
	color: string?,
	-- The player's custom name for their candidate (the Name Pass, D-069), as they
	-- typed it after CustomName.normalize. Saved for anyone, used only while they
	-- own the pass and are eligible, and filtered again (TextService) every time
	-- a match uses it. Optional, like `color`: no version bump.
	customName: string?,
	-- Names this player reported (D-069): setter user id -> the name. They see
	-- the candidate's own name instead, in every later match against that player.
	-- At most NAME_HIDDEN_MAX, oldest dropped. Optional: no version bump.
	hiddenNames: { [string]: string }?,
	hiddenOrder: { string }?, -- the setter ids in hiddenNames, oldest first
	-- The tutorial (D-075): true once the player's tutorial bot match ended (an
	-- election or a forfeit; an abandoned one does not count). Optional: no
	-- version bump; a profile without it that has any game recorded counts as
	-- done (Profile.needsTutorial).
	tutorialDone: boolean?,
	-- Ids of the last results applied (newest last, at most SETTLED_MAX), so a
	-- result that reaches a profile twice (from another server's pending list,
	-- DataService) counts once. Optional: no version bump.
	settled: { string }?,
	-- Opponent player id -> Unix times of rated games against them within
	-- RATED_PAIR_WINDOW (D-077: at most RATED_PAIR_DAILY_MAX are rated). Optional.
	ratedWith: { [string]: { number } }?,
	-- Reports this player sent since `at` (D-078: NAME_REPORTS_PER_DAY per
	-- NAME_REPORT_WINDOW, kept here so a rejoin does not reset it). Optional.
	reportLog: { at: number, count: number }?,
	-- An admin's "Timers off" toggle (D-081): true turns the choice timers off
	-- in their matches where every human is an admin. Saved for anyone, used
	-- only while the server counts them as an admin. Optional: no version bump.
	adminTimersOff: boolean?,
	-- The Daily Race (D-082): the last counted run's day, its margin once it
	-- ended, and the streak of consecutive days. Never touches the rating, the
	-- practice record or the tutorial. Optional: no version bump.
	daily: Daily.Record?,
	-- Fuller stats and the public landslide count (D-094). Optional, no profile
	-- version bump (see Profile.VERSION); the block has its own schema version
	-- `v` (Profile.STATS_VERSION), cleaned by Profile.cleanStats.
	stats: Stats?,
}

-- Fuller per-player stats (D-094), kept from 0.17 on. Counted only for results
-- that reach Profile.applyResult (rated and practice matches; never the Daily
-- Race, which keeps its own record, or an abandoned match).
export type Stats = {
	v: number, -- this block's schema version (Profile.STATS_VERSION)
	since: number, -- Unix time counting began for this player
	landslides: number, -- PUBLIC: rated matches from the public queue won by a landslide (D-094)
	landslidesAll: number, -- every recorded match won by a landslide (private, practice and tutorial too)
	publicGames: number, -- rated matches from the public queue (and their rematches)
	privateGames: number, -- rated matches from a private code (and their rematches)
	elections: number, -- recorded matches that reached election night
	forfeitWins: number, -- recorded matches won because the other side left
	forfeitLosses: number, -- recorded matches this player left (or timed out of)
	evFor: number, -- electoral votes won, summed over elections
	evAgainst: number, -- electoral votes conceded, summed over elections
	bestEV: number, -- most electoral votes in one election
	lastAt: number?, -- Unix time of the last recorded match
	onboard: number?, -- analytics (D-094): the last onboarding-funnel step logged; set only for players new since 0.17
}

-- What the lobby shows.
export type Summary = {
	rating: number,
	games: number,
	wins: number,
	losses: number,
	landslides: number?, -- the public landslide count (D-094); absent = none yet
}

-- A finished match, from one player's side.
export type Result = {
	at: number,
	reason: Reason,
	rated: boolean, -- a human opponent, so the rating moves; false for practice
	won: boolean,
	candidate: string?,
	opponentCandidate: string?,
	opponentRating: number?, -- before the match; required when rated
	evFor: number?,
	evAgainst: number?,
	opponent: string?, -- the opponent's player id: rated games count per pair (D-077)
	tutorial: boolean?, -- the tutorial match (D-075): applying it marks the tutorial done
	-- D-094 (optional; older pending results have neither):
	landslide: boolean?, -- this player won by a landslide (Election.landslide)
	public: boolean?, -- a rated match from the public queue: a landslide here counts publicly
}

-- A result waiting in a stored record for the server that holds the player's
-- data (DataService): `id` is unique per match and player.
export type Pending = {
	id: string,
	result: Result,
}

-- What applying a result did to the rating.
export type Change = {
	before: number,
	after: number,
	rated: boolean, -- false: nothing about the rating changed
}

local Profile = {}

-- Bump when the saved shape changes (a rename or a reshape), and teach migrate
-- the old one. An added optional field needs no bump: `color` (D-055) did not,
-- because a bump makes servers still on the old version read such a profile as
-- "from the future" and stop saving that player's results.
Profile.VERSION = 1
Profile.RECENT_MAX = 10 -- matches kept in `recent`
Profile.SETTLED_MAX = 30 -- result ids kept in `settled`
Profile.PENDING_MAX = 20 -- results kept waiting in a stored record (DataService)
-- The `stats` block's own schema version (D-094). Bump it when a stats field is
-- renamed or reshaped and teach cleanStats the old shape; a block from a newer
-- version is kept as it was and never written over (Profile.applyResult).
Profile.STATS_VERSION = 1
Profile.ONBOARD_MAX = 100 -- analytics funnels allow steps 1-100 (AnalyticsService docs)
local MAX_CANDIDATES = 64 -- most perCandidate entries kept (garbage defense)
local MAX_ID = 32 -- longest candidate id kept
local MAX_KEY = 64 -- longest result id or player id kept
local RATED_WITH_MAX = 50 -- most opponents kept in `ratedWith` (the longest ago drops)

function Profile.new(config: Config?): Profile
	local c = config or ConfigModule.defaults
	return {
		version = Profile.VERSION,
		rating = c.ELO_START,
		games = 0,
		wins = 0,
		losses = 0,
		perCandidate = {},
		recent = {},
		practice = { games = 0, wins = 0, losses = 0 },
		color = nil,
		customName = nil,
	}
end

-- True if `value` is one of the six player colors (Candidates.colors).
function Profile.isColor(value: any): boolean
	return type(value) == "string" and table.find(Candidates.colors, value) ~= nil
end

local function count(value: any): number?
	if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return nil
	end
	return math.floor(value)
end

local function finite(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function cleanRecent(raw: any): Recent?
	if type(raw) ~= "table" then
		return nil
	end
	local at, opponentRating = finite(raw.at), finite(raw.opponentRating)
	local candidate, opponentCandidate = raw.candidate, raw.opponentCandidate
	if at == nil or opponentRating == nil or type(raw.won) ~= "boolean" then
		return nil
	end
	if type(candidate) ~= "string" or type(opponentCandidate) ~= "string" then
		return nil
	end
	if raw.reason ~= "Election" and raw.reason ~= "Forfeit" then
		return nil
	end
	local reason: "Election" | "Forfeit" = if raw.reason == "Forfeit" then "Forfeit" else "Election"
	return {
		at = at,
		opponentRating = math.floor(opponentRating),
		candidate = string.sub(candidate, 1, MAX_ID),
		opponentCandidate = string.sub(opponentCandidate, 1, MAX_ID),
		won = raw.won,
		evFor = count(raw.evFor),
		evAgainst = count(raw.evAgainst),
		reason = reason,
	}
end

local STAT_COUNTS = {
	"landslides",
	"landslidesAll",
	"publicGames",
	"privateGames",
	"elections",
	"forfeitWins",
	"forfeitLosses",
	"evFor",
	"evAgainst",
	"bestEV",
}

-- A fresh stats block, counting from `now` (D-094).
function Profile.newStats(now: number): Stats
	return {
		v = Profile.STATS_VERSION,
		since = now,
		landslides = 0,
		landslidesAll = 0,
		publicGames = 0,
		privateGames = 0,
		elections = 0,
		forfeitWins = 0,
		forfeitLosses = 0,
		evFor = 0,
		evAgainst = 0,
		bestEV = 0,
		lastAt = nil,
		onboard = nil,
	}
end

-- A stored stats block, cleaned (D-094): nil for anything that is not a table;
-- every count defaults to 0. A block from a newer STATS_VERSION keeps every
-- plain field as it is (and its `v`; the known counts still read as numbers),
-- so this server can show it, saves it unchanged, and Profile.applyResult
-- leaves it alone.
function Profile.cleanStats(raw: any): Stats?
	if type(raw) ~= "table" then
		return nil
	end
	local since = finite(raw.since) or 0
	local out = Profile.newStats(since)
	local v = count(raw.v) or 0
	if v > Profile.STATS_VERSION then
		-- From a newer game version: kept field for field (plain values only),
		-- so saving this profile here does not lose what that version added.
		local kept = out :: any
		for key, value in raw do
			local kind = type(value)
			if type(key) == "string" and #key <= MAX_KEY and (kind == "string" or kind == "boolean") then
				kept[key] = if kind == "string" then string.sub(value, 1, MAX_KEY) else value
			elseif type(key) == "string" and #key <= MAX_KEY and kind == "number" and finite(value) then
				kept[key] = value
			end
		end
		for _, name in STAT_COUNTS do
			kept[name] = count(kept[name]) or 0
		end
		kept.since = finite(kept.since) or 0
		kept.lastAt = finite(kept.lastAt)
		kept.onboard = count(kept.onboard)
		out.v = v
		return out
	end
	-- Version 0 or 1: the same names. Add a step here when a later version
	-- renames or reshapes a field.
	local fields = out :: any
	for _, name in STAT_COUNTS do
		fields[name] = count(raw[name]) or 0
	end
	out.landslidesAll = math.max(out.landslidesAll, out.landslides)
	out.lastAt = finite(raw.lastAt)
	local onboard = count(raw.onboard)
	if onboard and onboard >= 1 then
		out.onboard = math.min(onboard, Profile.ONBOARD_MAX)
	end
	return out
end

-- The public landslide count (D-094): 0 without stats.
function Profile.landslides(profile: Profile?): number
	local stats = if profile then profile.stats else nil
	return if stats then stats.landslides else 0
end

-- Turns whatever was stored (nil, garbage, or any older version) into a valid
-- current profile. Keeps every field it can read and defaults the rest. Never
-- throws and never returns a table it was given.
function Profile.migrate(raw: any, config: Config?): Profile
	local c = config or ConfigModule.defaults
	local out = Profile.new(c)
	if type(raw) ~= "table" then
		return out
	end
	-- Versions before 1 (or none) used the same field names; add a step here when
	-- a later version renames or reshapes one.
	local rating = finite(raw.rating)
	if rating then
		out.rating = math.max(c.ELO_FLOOR, math.floor(rating))
	end
	out.wins = count(raw.wins) or 0
	out.losses = count(raw.losses) or 0
	out.games = math.max(count(raw.games) or 0, out.wins + out.losses)

	if type(raw.perCandidate) == "table" then
		local kept = 0
		for id, record in raw.perCandidate do
			if
				type(id) == "string"
				and #id <= MAX_ID
				and type(record) == "table"
				and kept < MAX_CANDIDATES
			then
				kept += 1
				out.perCandidate[id] = { wins = count(record.wins) or 0, losses = count(record.losses) or 0 }
			end
		end
	end

	if type(raw.recent) == "table" then
		local entries: { Recent } = {}
		for k = 1, #raw.recent do
			local entry = cleanRecent(raw.recent[k])
			if entry then
				table.insert(entries, entry)
			end
		end
		for k = math.max(1, #entries - Profile.RECENT_MAX + 1), #entries do
			table.insert(out.recent, entries[k])
		end
	end

	if type(raw.practice) == "table" then
		out.practice.wins = count(raw.practice.wins) or 0
		out.practice.losses = count(raw.practice.losses) or 0
		out.practice.games = math.max(count(raw.practice.games) or 0, out.practice.wins + out.practice.losses)
	end

	if Profile.isColor(raw.color) then
		out.color = raw.color
	end
	if raw.customName ~= nil then
		out.customName = (CustomName.normalize(raw.customName, c))
	end
	if raw.tutorialDone == true then
		out.tutorialDone = true
	end
	if raw.adminTimersOff == true then
		out.adminTimersOff = true
	end
	if type(raw.hiddenNames) == "table" and type(raw.hiddenOrder) == "table" then
		local names: { [string]: string } = {}
		local order: { string } = {}
		for _, id in raw.hiddenOrder do
			local name = if type(id) == "string" then raw.hiddenNames[id] else nil
			if type(name) == "string" and #name <= 64 and names[id] == nil then
				names[id] = name
				table.insert(order, id)
			end
		end
		while #order > c.NAME_HIDDEN_MAX do
			names[table.remove(order, 1) :: string] = nil
		end
		if #order > 0 then
			out.hiddenNames = names
			out.hiddenOrder = order
		end
	end
	if type(raw.settled) == "table" then
		local ids: { string } = {}
		for k = 1, #raw.settled do
			local id = raw.settled[k]
			if type(id) == "string" and #id <= MAX_KEY then
				table.insert(ids, id)
			end
		end
		while #ids > Profile.SETTLED_MAX do
			table.remove(ids, 1)
		end
		if #ids > 0 then
			out.settled = ids
		end
	end
	if type(raw.ratedWith) == "table" then
		local pairsOut: { [string]: { number } } = {}
		local kept = 0
		for id, times in raw.ratedWith do
			if
				type(id) == "string"
				and #id <= MAX_KEY
				and type(times) == "table"
				and kept < RATED_WITH_MAX
			then
				local list: { number } = {}
				for k = 1, #times do
					local at = finite(times[k])
					if at then
						table.insert(list, at)
					end
				end
				while #list > c.RATED_PAIR_DAILY_MAX * 2 do
					table.remove(list, 1)
				end
				if #list > 0 then
					kept += 1
					pairsOut[id] = list
				end
			end
		end
		if kept > 0 then
			out.ratedWith = pairsOut
		end
	end
	if type(raw.reportLog) == "table" then
		local at, n = finite(raw.reportLog.at), count(raw.reportLog.count)
		if at and n then
			out.reportLog = { at = at, count = n }
		end
	end
	out.daily = Daily.clean(raw.daily)
	out.stats = Profile.cleanStats(raw.stats)
	return out
end

local RESULT_REASONS: { [string]: boolean } = { Election = true, Forfeit = true, Abandoned = true }

local function optionalString(value: any): string?
	return if type(value) == "string" and #value <= MAX_KEY then value else nil
end

-- A stored pending list, cleaned: entries that are not a well-formed result are
-- dropped (garbage defense), at most PENDING_MAX kept (the newest).
function Profile.cleanPending(raw: any): { Pending }
	local out: { Pending } = {}
	if type(raw) ~= "table" then
		return out
	end
	for k = 1, #raw do
		local entry = raw[k]
		local result = if type(entry) == "table" then entry.result else nil
		if
			type(entry) == "table"
			and type(entry.id) == "string"
			and #entry.id <= MAX_KEY
			and type(result) == "table"
			and finite(result.at) ~= nil
			and RESULT_REASONS[result.reason] == true
			and type(result.rated) == "boolean"
			and type(result.won) == "boolean"
		then
			table.insert(out, {
				id = entry.id,
				result = {
					at = result.at,
					reason = result.reason,
					rated = result.rated,
					won = result.won,
					candidate = optionalString(result.candidate),
					opponentCandidate = optionalString(result.opponentCandidate),
					opponentRating = finite(result.opponentRating),
					evFor = count(result.evFor),
					evAgainst = count(result.evAgainst),
					opponent = optionalString(result.opponent),
					tutorial = if result.tutorial == true then true else nil,
					landslide = if result.landslide == true then true else nil,
					public = if result.public == true then true else nil,
				},
			})
		end
	end
	while #out > Profile.PENDING_MAX do
		table.remove(out, 1)
	end
	return out
end

-- True if `raw` was saved by a newer version of the game than this one. Saving
-- over it would lose fields this version doesn't know, so DataService reads it
-- but doesn't write.
function Profile.isFromFuture(raw: any): boolean
	return type(raw) == "table" and type(raw.version) == "number" and raw.version > Profile.VERSION
end

local function copy(profile: Profile): Profile
	local out = table.clone(profile)
	out.perCandidate = {}
	for id, record in profile.perCandidate do
		out.perCandidate[id] = table.clone(record)
	end
	out.recent = table.clone(profile.recent)
	out.practice = table.clone(profile.practice)
	if profile.settled then
		out.settled = table.clone(profile.settled)
	end
	if profile.ratedWith then
		local pairsOut: { [string]: { number } } = {}
		for id, times in profile.ratedWith do
			pairsOut[id] = table.clone(times)
		end
		out.ratedWith = pairsOut
	end
	if profile.reportLog then
		out.reportLog = table.clone(profile.reportLog)
	end
	if profile.daily then
		out.daily = table.clone(profile.daily)
	end
	if profile.stats then
		out.stats = table.clone(profile.stats)
	end
	return out
end

-- Rated games this player played against `opponent` within RATED_PAIR_WINDOW of `now` (D-077).
function Profile.ratedGamesWith(profile: Profile?, opponent: string, now: number, config: Config?): number
	local c = config or ConfigModule.defaults
	local none: { number } = {}
	local times: { number } = if profile and profile.ratedWith
		then profile.ratedWith[opponent] or none
		else none
	local n = 0
	for _, at in times do
		if now - at < c.RATED_PAIR_WINDOW then
			n += 1
		end
	end
	return n
end

-- Records a rated game against `opponent` at `at`, dropping times past the window.
local function addRatedWith(out: Profile, opponent: string, at: number, c: Config)
	local pairsOut: { [string]: { number } } = {}
	local kept = 0
	local before: { [string]: { number } } = out.ratedWith or {}
	for id, times in before do
		local list: { number } = {}
		for _, t in times do
			if at - t < c.RATED_PAIR_WINDOW then
				table.insert(list, t)
			end
		end
		if #list > 0 and id ~= opponent then
			pairsOut[id] = list
			kept += 1
		end
	end
	local mine: { number } = {}
	local earlier: { number } = before[opponent] or {}
	for _, t in earlier do
		if at - t < c.RATED_PAIR_WINDOW then
			table.insert(mine, t)
		end
	end
	table.insert(mine, at)
	while #mine > c.RATED_PAIR_DAILY_MAX * 2 do
		table.remove(mine, 1)
	end
	-- Too many opponents: the one played longest ago drops.
	while kept >= RATED_WITH_MAX do
		local oldestId, oldest = nil, math.huge
		for id, times in pairsOut do
			local last = times[#times]
			if last < oldest then
				oldestId, oldest = id, last
			end
		end
		if oldestId == nil then
			break
		end
		pairsOut[oldestId] = nil
		kept -= 1
	end
	pairsOut[opponent] = mine
	out.ratedWith = pairsOut
end

-- Counts one decided result in the stats block (D-094), creating it on the
-- first. A block from a newer STATS_VERSION is left as it is.
local function addStats(out: Profile, result: Result)
	local stats: Stats = if out.stats then table.clone(out.stats :: Stats) else Profile.newStats(result.at)
	if stats.v > Profile.STATS_VERSION then
		return
	end
	local rated = result.rated and result.opponentRating ~= nil
	local public = rated and result.public == true
	if rated then
		if public then
			stats.publicGames += 1
		else
			stats.privateGames += 1
		end
	end
	if result.reason == "Election" then
		stats.elections += 1
		local evFor = result.evFor or 0
		stats.evFor += evFor
		stats.evAgainst += result.evAgainst or 0
		stats.bestEV = math.max(stats.bestEV, evFor)
		if result.won and result.landslide == true then
			stats.landslidesAll += 1
			if public then
				stats.landslides += 1
			end
		end
	elseif result.reason == "Forfeit" then
		if result.won then
			stats.forfeitWins += 1
		else
			stats.forfeitLosses += 1
		end
	end
	stats.lastAt = result.at
	out.stats = stats
end

-- Applies one finished match. Only a rated match with a decided result (Election
-- or Forfeit) moves the rating, the totals, the per-candidate record and `recent`.
-- Practice only adds to `practice`. An abandoned match changes nothing.
-- Returns the new profile and what happened to the rating.
function Profile.applyResult(profile: Profile, result: Result, config: Config?): (Profile, Change)
	local c = config or ConfigModule.defaults
	local unchanged: Change = { before = profile.rating, after = profile.rating, rated = false }
	if result.reason == "Abandoned" then
		return profile, unchanged
	end
	local out = copy(profile)
	addStats(out, result)
	if not result.rated or result.opponentRating == nil then
		out.practice.games += 1
		if result.won then
			out.practice.wins += 1
		else
			out.practice.losses += 1
		end
		return out, unchanged
	end

	local after = Rating.next(c, profile.rating, result.opponentRating, result.won)
	out.rating = after
	out.games += 1
	if result.won then
		out.wins += 1
	else
		out.losses += 1
	end
	if result.candidate then
		local record = out.perCandidate[result.candidate] or { wins = 0, losses = 0 }
		if result.won then
			record.wins += 1
		else
			record.losses += 1
		end
		out.perCandidate[result.candidate] = record
	end
	table.insert(out.recent, {
		at = result.at,
		opponentRating = result.opponentRating,
		candidate = result.candidate or "?",
		opponentCandidate = result.opponentCandidate or "?",
		won = result.won,
		evFor = result.evFor,
		evAgainst = result.evAgainst,
		reason = if result.reason == "Forfeit" then "Forfeit" else "Election",
	})
	while #out.recent > Profile.RECENT_MAX do
		table.remove(out.recent, 1)
	end
	if result.opponent then
		addRatedWith(out, result.opponent, result.at, c)
	end
	return out, { before = profile.rating, after = after, rated = true }
end

-- Applies result `id` once: a result already in `settled` changes nothing (the
-- third value is false). Otherwise as applyResult, and the id is remembered.
function Profile.settle(
	profile: Profile,
	id: string,
	result: Result,
	config: Config?
): (Profile, Change, boolean)
	if profile.settled and table.find(profile.settled, id) then
		return profile, { before = profile.rating, after = profile.rating, rated = false }, false
	end
	local out, change = Profile.applyResult(profile, result, config)
	if out == profile then
		out = copy(profile)
	end
	if result.tutorial then
		out = Profile.withTutorialDone(out)
	end
	local settled = table.clone(profile.settled or {})
	table.insert(settled, id)
	while #settled > Profile.SETTLED_MAX do
		table.remove(settled, 1)
	end
	out.settled = settled
	return out, change, true
end

-- Whether this player may send another report at `now` (D-078).
function Profile.canReport(profile: Profile?, now: number, config: Config?): boolean
	local c = config or ConfigModule.defaults
	local log = if profile then profile.reportLog else nil
	if log == nil or now - log.at >= c.NAME_REPORT_WINDOW or now < log.at then
		return true
	end
	return log.count < c.NAME_REPORTS_PER_DAY
end

-- The profile with one more report sent at `now` (a new window when the last one ran out).
function Profile.withReport(profile: Profile, now: number, config: Config?): Profile
	local c = config or ConfigModule.defaults
	local out = copy(profile)
	local log = profile.reportLog
	if log == nil or now - log.at >= c.NAME_REPORT_WINDOW or now < log.at then
		out.reportLog = { at = now, count = 1 }
	else
		out.reportLog = { at = log.at, count = log.count + 1 }
	end
	return out
end

-- The profile with `color` as the chosen color (nil = back to auto). A name that
-- is not one of the six is refused: returns the profile unchanged and false.
function Profile.withColor(profile: Profile, color: string?): (Profile, boolean)
	if color ~= nil and not Profile.isColor(color) then
		return profile, false
	end
	local out = copy(profile)
	out.color = color
	return out, true
end

-- The profile with `name` as the custom candidate name (nil = the candidate's
-- own name). The caller has already normalized and filtered it (server/NameService).
function Profile.withCustomName(profile: Profile, name: string?): Profile
	local out = copy(profile)
	out.customName = name
	return out
end

-- The profile with `setterId`'s name `name` hidden from this player (they
-- reported it, D-069); the oldest entry drops past NAME_HIDDEN_MAX.
function Profile.withHiddenName(profile: Profile, setterId: string, name: string, config: Config?): Profile
	local c = config or ConfigModule.defaults
	local out = copy(profile)
	local names = table.clone(profile.hiddenNames or {})
	local order = table.clone(profile.hiddenOrder or {})
	local at = table.find(order, setterId)
	if at then
		table.remove(order, at)
	end
	table.insert(order, setterId)
	names[setterId] = name
	while #order > c.NAME_HIDDEN_MAX do
		names[table.remove(order, 1) :: string] = nil
	end
	out.hiddenNames = names
	out.hiddenOrder = order
	return out
end

-- True if this player reported `setterId`'s name `name`.
function Profile.hides(profile: Profile?, setterId: string, name: string): boolean
	return profile ~= nil and profile.hiddenNames ~= nil and profile.hiddenNames[setterId] == name
end

-- True if this player's next bot match is the tutorial (D-075): their profile
-- is loaded, they have not finished the tutorial, and they have no game on
-- record at all (players from before the tutorial existed skip it). No
-- profile (still loading, or the DataStore is down): false, a normal match.
function Profile.needsTutorial(profile: Profile?): boolean
	if profile == nil or profile.tutorialDone == true then
		return false
	end
	return profile.games == 0 and profile.practice.games == 0
end

-- The profile with the tutorial marked done (D-075).
function Profile.withTutorialDone(profile: Profile): Profile
	local out = copy(profile)
	out.tutorialDone = true
	return out
end

-- The profile with the admin "Timers off" toggle set (D-081); off is stored as
-- no field at all.
function Profile.withTimersOff(profile: Profile, on: boolean): Profile
	local out = copy(profile)
	out.adminTimersOff = if on then true else nil
	return out
end

-- The profile once day `day`'s counted Daily Race run begins (D-082; week 1).
function Profile.withDailyBegun(profile: Profile, day: number): Profile
	local out = copy(profile)
	out.daily = Daily.begin(profile.daily, day)
	return out
end

-- The profile once day `day`'s counted run ended (D-082). The first end only.
function Profile.withDailyResult(
	profile: Profile,
	day: number,
	margin: number,
	behind: number,
	score: number
): Profile
	local out = copy(profile)
	out.daily = Daily.finish(profile.daily, day, margin, behind, score)
	return out
end

function Profile.summary(profile: Profile): Summary
	local landslides = Profile.landslides(profile)
	return {
		rating = profile.rating,
		games = profile.games,
		wins = profile.wins,
		losses = profile.losses,
		landslides = if landslides > 0 then landslides else nil,
	}
end

-- The profile with the onboarding funnel (D-094) at `step`: started for a new
-- player (step 1), or moved on. Never moves back.
function Profile.withOnboard(profile: Profile, step: number, now: number): Profile
	if profile.stats and profile.stats.v > Profile.STATS_VERSION then
		return profile
	end
	local out = copy(profile)
	local stats: Stats = if profile.stats then table.clone(profile.stats :: Stats) else Profile.newStats(now)
	stats.onboard = math.clamp(math.max(stats.onboard or 0, math.floor(step)), 1, Profile.ONBOARD_MAX)
	out.stats = stats
	return out
end

return table.freeze(Profile)
