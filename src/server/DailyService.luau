--!strict
-- The Daily Race on the server (docs/DESIGN.md D-080). Sim/Daily derives the
-- race from the UTC day; Net/Daily holds the scoring, streak and board rules;
-- this module does the clock, the profile writes, the day's OrderedDataStore
-- and what each player is told (message kind "Daily", Net/Daily.Info).
--
-- A run's life (MatchService calls these):
--   DailyService.race()             today's race, for a new run
--   DailyService.canCount(id, day)  the player's counted run today is still open
--   DailyService.watch(session)     after every flush: the counted run reaching
--                                   week 1 is saved in the profile (the streak grows)
--   DailyService.settle(session)    when it ends: its margin is saved and, for
--                                   the counted run, written to the day's board
--
-- The board: OrderedDataStore "DailyRace_v1", scope "YYYY-MM-DD" (UTC), key
-- "Player_<UserId>", value Net/Daily.score. The server keeps the day's top
-- Daily.TOP and reads it again at most every Daily.REFRESH seconds, only when
-- someone asks (op "Daily": the Lobby's card asks when it opens). One counted
-- run per player a day means one SetAsync per player a day. Request budget
-- (create.roblox.com, data stores "Error codes and limits"): GetSortedAsync
-- allows 5 + 2 per player a minute per server; this board and the global one
-- make at most one each. Every engine call is pcall'd.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Sim.Config)
local DailyNet = require(ReplicatedStorage.Shared.Net.Daily)
local Leaderboard = require(ReplicatedStorage.Shared.Net.Leaderboard)
local Profile = require(ReplicatedStorage.Shared.Net.Profile)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local SimDaily = require(ReplicatedStorage.Shared.Sim.Daily)
local DataService = require(script.Parent.DataService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local Replication = require(script.Parent.Replication)

local DailyService = {}

local WRITE_ATTEMPTS = 3 -- tries per score write, RETRY_WAIT * 2^n apart
local RETRY_WAIT = 1 -- seconds

local config = Config.defaults

-- The calls this service makes on a day's store; an OrderedDataStore has them.
export type Store = {
	SetAsync: (self: any, key: string, value: number) -> any,
	GetSortedAsync: (self: any, ascending: boolean, pageSize: number) -> any,
}

-- The day's board as this server knows it.
type Cache = {
	day: number,
	entries: { DailyNet.Entry },
	everRead: boolean,
	failed: boolean,
	readAt: number,
	reading: boolean,
	waiting: { [string]: boolean }, -- players to send the board to when the read ends
	recent: { [string]: { score: number, at: number } }, -- this server's own writes
}

local caches: { [number]: Cache } = {}
local stores: { [number]: Store } = {}
local marked: { [string]: boolean } = {} -- match id -> its counted run reached week 1 (saved)

local function unixNow(): number
	return os.time()
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

-- Today's day number (UTC).
function DailyService.today(): number
	return SimDaily.dayOf(unixNow())
end

-- Today's race.
function DailyService.race(): SimDaily.Race
	return SimDaily.race(config, DailyService.today())
end

local function cacheOf(day: number): Cache
	local cache = caches[day]
	if cache == nil then
		cache = {
			day = day,
			entries = {},
			everRead = false,
			failed = false,
			readAt = -math.huge,
			reading = false,
			waiting = {},
			recent = {},
		}
		caches[day] = cache
		-- Only today and yesterday (a run that ended after midnight) are kept.
		for old in caches do
			if old < day - 1 then
				caches[old] = nil
				stores[old] = nil
			end
		end
	end
	return cache
end

local function storeOf(day: number): Store?
	local found = stores[day]
	if found then
		return found
	end
	local ok, result = pcall(function(): any
		return game:GetService("DataStoreService"):GetOrderedDataStore(DailyNet.STORE, SimDaily.dateKey(day))
	end)
	if ok and result then
		stores[day] = result :: any
		return result :: any
	end
	warn(`[270] daily race store unavailable: {result}`)
	return nil
end

local function statusOf(cache: Cache): Leaderboard.Status
	if cache.everRead then
		return "Ok"
	end
	return if cache.failed then "Unavailable" else "Loading"
end

-- The player's saved Daily Race record, when their profile is loaded.
local function recordOf(id: string): DailyNet.Record?
	local profile = DataService.profile(id)
	return if profile then profile.daily else nil
end

-- What player `id` is told about today's race; `run` is the run that just ended.
function DailyService.info(id: string, run: DailyNet.Run?): DailyNet.Info
	local race = DailyService.race()
	local day = race.day
	local record = recordOf(id)
	local cache = cacheOf(day)
	return {
		day = day,
		date = race.date,
		candidate = race.candidate,
		botCandidate = race.botCandidate,
		level = race.level,
		endsAt = race.endsAt,
		played = DailyNet.counted(record, day),
		margin = if record and record.last == day then record.margin else nil,
		streak = DailyNet.streak(record, day),
		best = if record then record.best else 0,
		board = DailyNet.board(statusOf(cache), cache.entries, id, record, day),
		run = run,
	}
end

local function send(id: string, run: DailyNet.Run?)
	pcall(function(): string?
		Replication.send(id, { kind = "Daily", daily = DailyService.info(id, run) })
		return nil
	end)
end

-- Sends player `id` what this server knows about today's race (no store read),
-- e.g. when their profile has loaded and their streak is known.
function DailyService.tell(id: string)
	send(id)
end

-- Puts this server's own recent writes back over a fresh read.
local function reapply(cache: Cache)
	local now = serverNow()
	for id, write in cache.recent do
		if now - write.at > 2 * DailyNet.REFRESH then
			cache.recent[id] = nil
		else
			cache.entries = DailyNet.patch(cache.entries, id, LeaderboardService.nameOf(id), write.score)
		end
	end
end

-- Reads day `cache.day`'s top list, then tells everyone who asked. Yields.
local function read(cache: Cache)
	local ok, err = pcall(function(): string?
		local s = storeOf(cache.day)
		local rows: { any }? = nil
		if s then
			local got, result = pcall(function(): { any }
				return s:GetSortedAsync(false, DailyNet.TOP):GetCurrentPage()
			end)
			if got and type(result) == "table" then
				rows = result
			else
				warn(`[270] could not read the daily race board: {result}`)
			end
		end
		if rows then
			LeaderboardService.lookUpNames(rows)
			cache.entries = DailyNet.fromPage(rows, LeaderboardService.nameOf)
			reapply(cache)
			cache.everRead = true
			cache.failed = false
		else
			cache.failed = true
		end
		return nil
	end)
	if not ok then
		cache.failed = true
		warn(`[270] daily race board read failed: {err}`)
	end
	cache.reading = false
	local told = cache.waiting
	cache.waiting = {}
	for id in told do
		send(id)
	end
end

-- Reads the day's board again when a read is due (at most every REFRESH s);
-- player `id` is told when it ends.
local function refresh(cache: Cache, id: string)
	local now = serverNow()
	if cache.reading then
		cache.waiting[id] = true
	elseif now - cache.readAt >= DailyNet.REFRESH then
		cache.reading = true
		cache.readAt = now
		cache.waiting[id] = true
		task.spawn(read, cache)
	end
end

-- Player `id` asked about today's race (op "Daily"): they get what this server
-- knows now, and the fresh board when a read is due.
function DailyService.request(id: string)
	send(id)
	refresh(cacheOf(DailyService.today()), id)
end

-- Can player `id`'s next run of day `day` be their counted run? Their profile
-- must be loaded and saveable here, and no counted run of that day begun.
function DailyService.canCount(id: string, day: number): boolean
	if DataService.rating(id) == nil then
		return false -- not loaded, or read-only here: the run could not be saved
	end
	return not DailyNet.counted(recordOf(id), day)
end

local function humanSeat(session: Session.Session): number?
	for p, seat in session.seats do
		if seat.kind == "Human" then
			return p
		end
	end
	return nil
end

-- Tells the player as a run starts whether it counts (notice DailyCounted or DailyPractice).
function DailyService.started(session: Session.Session)
	local run = session.daily
	local p = humanSeat(session)
	if run == nil or p == nil then
		return
	end
	local id = session.seats[p].id
	Replication.send(
		id,
		{ kind = "Notice", notice = if run.counted then "DailyCounted" else "DailyPractice" }
	)
	print(
		`[270] match {session.id}: daily race {SimDaily.dateKey(run.day)} ({if run.counted
			then "counted"
			else "practice"})`
	)
end

-- After every flush: a counted run that has reached week 1 is now the player's
-- run of the day (D-080). Saved once; the streak grows.
function DailyService.watch(session: Session.Session)
	local run = session.daily
	if run == nil or not run.counted or marked[session.id] or session.match.week < 1 then
		return
	end
	local p = humanSeat(session)
	if p == nil then
		return
	end
	marked[session.id] = true
	local id = session.seats[p].id
	local day = run.day
	DataService.update(id, function(profile: Profile.Profile): Profile.Profile
		return Profile.withDailyBegun(profile, day)
	end)
	send(id)
end

-- Writes a counted run's score to the day's board (on its own thread) and
-- moves the player in the cached list at once.
local function record(id: string, day: number, score: number)
	if tonumber(id) == nil then
		return -- a bot or a test label, never a Roblox user
	end
	local cache = cacheOf(day)
	cache.recent[id] = { score = score, at = serverNow() }
	if cache.everRead then
		cache.entries = DailyNet.patch(cache.entries, id, LeaderboardService.nameOf(id), score)
	end
	task.spawn(function()
		local s = storeOf(day)
		if s == nil then
			return
		end
		for attempt = 1, WRITE_ATTEMPTS do
			local ok, err = pcall(function(): string?
				s:SetAsync(Leaderboard.keyOf(id), score)
				return nil
			end)
			if ok then
				return
			end
			if attempt == WRITE_ATTEMPTS then
				warn(`[270] could not write player {id}'s daily race score: {err}`)
			else
				task.wait(RETRY_WAIT * 2 ^ (attempt - 1))
			end
		end
	end)
end

-- A Daily Race run ended (MatchService.settle). The counted run (it reached
-- week 1) is scored: its margin at election night, or DAILY_FORFEIT_MARGIN when
-- it was left or abandoned; the score is saved in the profile and on the day's
-- board. A practice run is only reported back. Never touches the rating, the
-- practice record or the tutorial. The player is sent the run and their place.
function DailyService.settle(session: Session.Session)
	local run = session.daily
	local p = humanSeat(session)
	local counted = run ~= nil and run.counted and marked[session.id] == true
	marked[session.id] = nil
	if run == nil or p == nil then
		return
	end
	local id = session.seats[p].id
	local result = session.result
	local election = if result and result.reason == "Election" then session.match.election else nil
	local margin, behind, forfeit
	if election then
		local best = 0
		for q, votes in election.ev do
			if q ~= p then
				best = math.max(best, votes)
			end
		end
		margin = election.ev[p] - best
		behind = DailyNet.weeksBehind(session.match.pollHistory, p)
		forfeit = false
	else
		margin = config.DAILY_FORFEIT_MARGIN
		behind = DailyNet.BEHIND_MAX
		forfeit = true
	end
	if not counted then
		-- A practice run, or a counted one left before week 1 (it never counted).
		if session.match.week >= 1 or election then
			send(
				id,
				{ matchId = session.id, counted = false, margin = margin, forfeit = forfeit, rank = nil }
			)
		else
			send(id)
		end
		return
	end
	local day = run.day
	local score = DailyNet.score(margin, behind, unixNow(), day)
	DataService.update(id, function(profile: Profile.Profile): Profile.Profile
		return Profile.withDailyResult(profile, day, margin, behind, score)
	end)
	record(id, day, score)
	print(`[270] match {session.id}: daily race {SimDaily.dateKey(day)} scored {DailyNet.marginText(margin)}`)
	local cache = cacheOf(day)
	-- A place only from a board this server has read: before that, the read
	-- below tells the player (Daily.board's `you`).
	local rank = if cache.everRead then DailyNet.rankOf(cache.entries, id) else nil
	if Players:GetPlayerByUserId(tonumber(id) or 0) then
		send(id, { matchId = session.id, counted = true, margin = margin, forfeit = forfeit, rank = rank })
		if day == DailyService.today() then
			refresh(cache, id)
		end
	end
end

return DailyService
