--!strict
-- The global leaderboard (docs/DESIGN.md D-059): players ranked by their saved
-- rating. Pure: the server's LeaderboardService does the OrderedDataStore and
-- name lookups and uses these helpers to read a page, keep its cached top list
-- and build what one viewer sees (message kind "Leaderboard").
--
-- Only ratings are stored (key "Player_<UserId>", the rating as a whole number),
-- and only a rated human-vs-human match writes one: bot matches never move a
-- rating, so nobody climbs by farming the bot, and a player with no rated games
-- is never listed.

local Leaderboard = {}

Leaderboard.STORE = "Leaderboard_v1" -- the OrderedDataStore's name
Leaderboard.KEY_PREFIX = "Player_" -- key = prefix .. UserId
Leaderboard.TOP = 50 -- entries the server caches and the full sheet lists
Leaderboard.SHORT = 10 -- entries the Lobby shows on a wide screen
Leaderboard.COMPACT = 3 -- entries the Lobby shows on a phone
Leaderboard.REFRESH = 60 -- seconds: the cached list is read again at most this often
Leaderboard.MAX_NAME = 32 -- longest name kept (Roblox usernames are at most 20)

export type Status = "Ok" | "Loading" | "Unavailable"

export type Entry = {
	rank: number, -- 1 = the highest rating
	id: string, -- the player's UserId as a string
	name: string,
	rating: number,
}

-- Where the viewer stands. Absent when they have no rated games.
export type You = {
	rank: number?, -- their place, when they are in the cached top list
	rating: number,
}

-- What one viewer is sent.
export type Board = {
	status: Status, -- "Ok": `entries` is the last good list (possibly empty)
	entries: { Entry }, -- best first, at most TOP
	you: You?,
}

-- A raw page row from DataStorePages:GetCurrentPage(): { key, value }.
export type Row = {
	key: string,
	value: number,
}

-- The player id behind a store key, or nil for a key this game did not write.
function Leaderboard.idOf(key: any): string?
	if type(key) ~= "string" then
		return nil
	end
	local id = string.match(key, "^" .. Leaderboard.KEY_PREFIX .. "(%d+)$")
	return id
end

function Leaderboard.keyOf(id: string): string
	return Leaderboard.KEY_PREFIX .. id
end

local function wholeNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return math.floor(value)
end

-- Best first; equal ratings in a fixed order (the smaller id first), then ranked
-- 1, 2, 3… and cut to TOP.
local function rank(entries: { Entry }): { Entry }
	table.sort(entries, function(a: Entry, b: Entry): boolean
		if a.rating ~= b.rating then
			return a.rating > b.rating
		end
		if #a.id ~= #b.id then
			return #a.id < #b.id
		end
		return a.id < b.id
	end)
	local out: { Entry } = {}
	for k, entry in entries do
		if k > Leaderboard.TOP then
			break
		end
		table.insert(out, { rank = k, id = entry.id, name = entry.name, rating = entry.rating })
	end
	return out
end

-- Turns a store page into ranked entries. Rows with a key or value this game
-- would not write are skipped; a repeated id keeps its first row. `nameOf`
-- gives each id's display name (the caller's cache).
function Leaderboard.fromPage(rows: { any }, nameOf: (id: string) -> string): { Entry }
	local entries: { Entry } = {}
	local seen: { [string]: boolean } = {}
	for _, row in rows do
		if type(row) ~= "table" then
			continue
		end
		local id = Leaderboard.idOf(row.key)
		local rating = wholeNumber(row.value)
		if id == nil or rating == nil or seen[id] then
			continue
		end
		seen[id] = true
		table.insert(entries, { rank = 0, id = id, name = nameOf(id), rating = rating })
	end
	return rank(entries)
end

-- The list with one player's new rating in it (after a rated match), without
-- waiting for the next read: their row moves, or joins if it makes the top.
function Leaderboard.patch(entries: { Entry }, id: string, name: string, rating: number): { Entry }
	local out: { Entry } = {}
	for _, entry in entries do
		if entry.id ~= id then
			table.insert(out, table.clone(entry))
		end
	end
	table.insert(out, { rank = 0, id = id, name = name, rating = math.floor(rating) })
	return rank(out)
end

-- The viewer's place in the list, or nil.
function Leaderboard.rankOf(entries: { Entry }, id: string): number?
	for _, entry in entries do
		if entry.id == id then
			return entry.rank
		end
	end
	return nil
end

-- What viewer `id` is sent. `rating` is their own saved rating when they have
-- rated games (nil otherwise: they are not on the board).
function Leaderboard.board(status: Status, entries: { Entry }, id: string, rating: number?): Board
	local copy: { Entry } = {}
	for k, entry in entries do
		copy[k] = table.clone(entry)
	end
	local place = Leaderboard.rankOf(entries, id)
	local you: You? = nil
	if place then
		you = { rank = place, rating = entries[place].rating }
	elseif rating then
		you = { rank = nil, rating = rating }
	end
	return { status = status, entries = copy, you = you }
end

-- A name fit for the board: a non-empty string, at most MAX_NAME characters.
function Leaderboard.cleanName(name: any, id: string): string
	if type(name) ~= "string" or name == "" then
		return `Player {id}`
	end
	return string.sub(name, 1, Leaderboard.MAX_NAME)
end

return table.freeze(Leaderboard)
