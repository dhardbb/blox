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
	-- The player's custom name for their candidate (the Name Pass, D-063), as they
	-- typed it after CustomName.normalize. Saved for anyone, used only while they
	-- own the pass and are eligible, and filtered again (TextService) every time
	-- a match uses it. Optional, like `color`: no version bump.
	customName: string?,
}

-- What the lobby shows.
export type Summary = {
	rating: number,
	games: number,
	wins: number,
	losses: number,
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
local MAX_CANDIDATES = 64 -- most perCandidate entries kept (garbage defense)
local MAX_ID = 32 -- longest candidate id kept

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
	return out
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
	return out, { before = profile.rating, after = after, rated = true }
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

function Profile.summary(profile: Profile): Summary
	return { rating = profile.rating, games = profile.games, wins = profile.wins, losses = profile.losses }
end

return table.freeze(Profile)
