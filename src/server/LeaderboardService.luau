--!strict
-- The global leaderboard (docs/DESIGN.md D-059): players ranked by their saved
-- rating, in an OrderedDataStore ("Leaderboard_v1", key "Player_<UserId>",
-- the rating as a whole number). Net/Leaderboard holds the pure rules.
--
-- Writes: a rating is written when a rated match changes it (MatchService) and
-- when a player with rated games loads in (so ratings saved before the board
-- existed appear too). Only rated human-vs-human matches move a rating, so a
-- bot match never touches the board.
--
-- Reads: the server keeps the top Leaderboard.TOP in memory and reads the store
-- again at most every Leaderboard.REFRESH seconds, and only when someone asks
-- (op "Leaderboard": the Lobby asks when it opens). A read that fails keeps the
-- last good list; with none, the board says "Unavailable". Names come from
-- Players:GetNameFromUserIdAsync (usernames), cached for the server's life.
-- Every engine call is pcall'd: nothing here can throw into a request.
--
-- Request budget (create.roblox.com, data stores "Error codes and limits"):
-- GetSortedAsync allows 5 + 2 per player each minute and this makes at most
-- one; SetAsync on an ordered store allows 30 + 5 per player each minute and
-- this makes one per rated result and one per join of a ranked player.
--
-- In an unpublished Studio place, or with "Enable Studio Access to API
-- Services" off, every read fails and the board says "Unavailable".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Leaderboard = require(ReplicatedStorage.Shared.Net.Leaderboard)

local LeaderboardService = {}

local WRITE_ATTEMPTS = 3 -- tries per rating write, RETRY_WAIT * 2^n apart
local RETRY_WAIT = 1 -- seconds
local NAME_WAIT = 10 -- seconds a read waits for name lookups before using what it has

-- The calls this service makes; an OrderedDataStore has them. Tests supply their own.
export type Store = {
	SetAsync: (self: any, key: string, value: number) -> any,
	GetSortedAsync: (self: any, ascending: boolean, pageSize: number) -> any,
}

export type Options = {
	store: Store?, -- default: DataStoreService:GetOrderedDataStore(Leaderboard.STORE)
	now: (() -> number)?, -- default: workspace:GetServerTimeNow()
	send: ((id: string, board: Leaderboard.Board) -> ())?, -- how a board reaches a player
	ratingOf: ((id: string) -> number?)?, -- a player's own rating when they have rated games
}

local store: Store? = nil
local override: Store? = nil
local send: (id: string, board: Leaderboard.Board) -> () = function(
	_id: string,
	_board: Leaderboard.Board
)
end
local ratingOf: (id: string) -> number? = function(_id: string): number?
	return nil
end
local clock: () -> number = function()
	return workspace:GetServerTimeNow()
end

local entries: { Leaderboard.Entry } = {}
local everRead = false -- a read has succeeded at least once
local failed = false -- the last read failed (only shown while nothing was ever read)
local readAt = -math.huge -- when the last read started
local reading = false
local waiting: { [string]: boolean } = {} -- players to send the board to when the read ends
local names: { [string]: string } = {} -- user id -> username, cached
local recent: { [string]: { rating: number, at: number } } = {} -- this server's latest writes

local function getStore(): Store?
	if store then
		return store
	end
	if override then
		store = override
		return store
	end
	local ok, result = pcall(function(): any
		return game:GetService("DataStoreService"):GetOrderedDataStore(Leaderboard.STORE)
	end)
	if ok and result then
		store = result :: any
		return store
	end
	warn(`[270] leaderboard store unavailable: {result}`)
	return nil
end

local function status(): Leaderboard.Status
	if everRead then
		return "Ok"
	end
	return if failed then "Unavailable" else "Loading"
end

-- The board as player `id` sees it.
function LeaderboardService.boardFor(id: string): Leaderboard.Board
	return Leaderboard.board(status(), entries, id, ratingOf(id))
end

-- A player's username: the cache, the player object when they are here, else
-- one web request. Yields; nil when the lookup fails (tried again next read).
local function lookUp(id: string): string?
	local cached = names[id]
	if cached then
		return cached
	end
	local userId = tonumber(id)
	if userId == nil then
		return nil
	end
	local here = Players:GetPlayerByUserId(userId)
	if here then
		names[id] = Leaderboard.cleanName(here.Name, id)
		return names[id]
	end
	local ok, name = pcall(function(): string
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" and name ~= "" then
		names[id] = Leaderboard.cleanName(name, id)
		return names[id]
	end
	return nil
end

-- Looks up every name a page needs at once (each on its own thread), waiting
-- at most NAME_WAIT seconds.
local function lookUpAll(rows: { any })
	local pending = 0
	for _, row in rows do
		local id = if type(row) == "table" then Leaderboard.idOf(row.key) else nil
		if id and names[id] == nil then
			pending += 1
			task.spawn(function()
				lookUp(id)
				pending -= 1
			end)
		end
	end
	local waited = 0
	while pending > 0 and waited < NAME_WAIT do
		task.wait(0.1)
		waited += 0.1
	end
end

local function nameOf(id: string): string
	return names[id] or Leaderboard.cleanName(nil, id)
end

-- The page of the top list, or nil when the store can't be read. Yields.
local function fetch(): { any }?
	local s = getStore()
	if s == nil then
		return nil
	end
	local ok, result = pcall(function(): { any }
		local pages = s:GetSortedAsync(false, Leaderboard.TOP)
		return pages:GetCurrentPage()
	end)
	if ok and type(result) == "table" then
		return result
	end
	warn(`[270] could not read the leaderboard: {result}`)
	return nil
end

-- Puts this server's own recent writes back over a fresh read: a write can
-- take a moment to show up in GetSortedAsync.
local function reapply()
	local now = clock()
	for id, write in recent do
		if now - write.at > 2 * Leaderboard.REFRESH then
			recent[id] = nil
		else
			entries = Leaderboard.patch(entries, id, nameOf(id), write.rating)
		end
	end
end

-- Reads the top list from the store, then sends it to everyone who asked.
-- Yields; runs on its own thread. Never throws.
local function read()
	local ok, err = pcall(function(): string?
		local rows = fetch()
		if rows then
			lookUpAll(rows)
			entries = Leaderboard.fromPage(rows, nameOf)
			reapply()
			everRead = true
			failed = false
		else
			failed = true
		end
		return nil
	end)
	if not ok then
		failed = true
		warn(`[270] leaderboard read failed: {err}`)
	end
	reading = false
	local told = waiting
	waiting = {}
	for id in told do
		pcall(send, id, LeaderboardService.boardFor(id))
	end
end

-- Player `id` asked for the board: they get the cached one now, and the fresh
-- one when a read is due (at most every Leaderboard.REFRESH seconds).
function LeaderboardService.request(id: string)
	send(id, LeaderboardService.boardFor(id))
	local now = clock()
	if reading then
		waiting[id] = true
	elseif now - readAt >= Leaderboard.REFRESH then
		reading = true
		readAt = now
		waiting[id] = true
		task.spawn(read)
	end
end

-- Writes player `id`'s rating (on its own thread) and moves them in the cached
-- list at once. Call it only for a player with rated games.
function LeaderboardService.record(id: string, rating: number)
	if tonumber(id) == nil then
		return -- a bot or a test label, never a Roblox user
	end
	local value = math.floor(rating)
	recent[id] = { rating = value, at = clock() }
	if everRead then
		local here = Players:GetPlayerByUserId(tonumber(id) :: number)
		if here and names[id] == nil then
			names[id] = Leaderboard.cleanName(here.Name, id)
		end
		entries = Leaderboard.patch(entries, id, nameOf(id), value)
	end
	task.spawn(function()
		local s = getStore()
		if s == nil then
			return
		end
		for attempt = 1, WRITE_ATTEMPTS do
			local ok, err = pcall(function(): string?
				s:SetAsync(Leaderboard.keyOf(id), value)
				return nil
			end)
			if ok then
				return
			end
			if attempt == WRITE_ATTEMPTS then
				warn(`[270] could not write player {id}'s rating to the leaderboard: {err}`)
			else
				task.wait(RETRY_WAIT * 2 ^ (attempt - 1))
			end
		end
	end)
end

-- Sets up where boards go and where ratings come from. Call once at start.
function LeaderboardService.start(options: Options?)
	if options then
		override = options.store
		if options.now then
			clock = options.now
		end
		if options.send then
			send = options.send
		end
		if options.ratingOf then
			ratingOf = options.ratingOf
		end
	end
end

return LeaderboardService
