--!strict
-- Saved player data: one Net/Profile per player in a DataStore, session-locked
-- so two servers never write the same player at once. It loads on join, saves a
-- match result at once, batches every other change into a save every
-- SAVE_INTERVAL (an unchanged profile is not saved), refreshes the lock at least
-- every LOCK_REFRESH, saves when the player leaves, and flushes on shutdown.
-- Nothing here runs inside a turn: callers get answers from memory, and every
-- DataStore request happens on its own thread, retried with exponential backoff.
--
-- Record format (key "Player_<UserId>" in the DataStore "PlayerData_v1"):
--   { lock = { jobId = string, at = unix seconds }?, data = <Profile>,
--     pending = { Profile.Pending }? }
-- `lock` is set while a server has the player loaded and cleared when it lets go.
-- A lock older than LOCK_TTL is a crashed server's and is taken over.
-- `pending`: match results another server could not apply because a server
-- holds the lock (the player left a match for another server). Whoever holds
-- the lock merges them into the profile on its next load or save, once each
-- (Profile.settle, by result id), so a result is never lost or overwritten.
--
-- DataStores don't work in an unpublished Studio place. The first request that
-- fails that way switches the whole service to an in-memory store, with one
-- warning, so play still works (nothing survives the session).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Profile = require(ReplicatedStorage.Shared.Net.Profile)

local DataService = {}

local STORE_NAME = "PlayerData_v1"
local KEY_PREFIX = "Player_"
local LOCK_TTL = 120 -- seconds before another server's lock counts as dead
local LOCK_ATTEMPTS = 4 -- tries to get a held lock, waiting LOCK_WAIT * 2^n between them
local LOCK_WAIT = 1.5 -- seconds
local ERROR_ATTEMPTS = 5 -- tries per request after errors, waiting RETRY_WAIT * 2^n between them
local RETRY_WAIT = 1 -- seconds
local SHUTDOWN_WAIT = 25 -- seconds to wait for saves in BindToClose (Roblox allows 30)
local SAVE_INTERVAL = 15 -- seconds between batched saves of changed profiles
local LOCK_REFRESH = 60 -- seconds: a lock this old is refreshed by a save (well inside LOCK_TTL)

-- The two calls this service uses; DataStore has both. Tests and the memory
-- fallback supply their own.
export type Store = {
	GetAsync: (self: any, key: string) -> (any, any),
	UpdateAsync: (self: any, key: string, transform: (any, any) -> any) -> (any, any),
}

export type Options = {
	store: Store?, -- default: DataStoreService:GetDataStore("PlayerData_v1")
	jobId: string?, -- default: game.JobId
}

type Entry = {
	id: string,
	key: string,
	name: string,
	profile: Profile.Profile?, -- nil if loading failed
	writable: boolean, -- false: read-only (locked elsewhere, newer data, or a failed load)
	loaded: boolean,
	leaving: boolean, -- the player left; finish and drop the entry
	saving: boolean, -- a save loop is running
	dirty: boolean, -- changed since the last save started
	release: boolean, -- the next save also clears the lock
	lastWrite: number, -- os.time() of the last write of this record (the lock's age)
	queued: { Queued }, -- changes that arrived before the load finished, applied in order once it does
}

type Queued = {
	transform: (Profile.Profile) -> Profile.Profile,
	applied: (() -> ())?,
	pending: Profile.Pending?, -- a match result: if this server cannot save it, it goes to the record's pending list
}

local store: Store? = nil
local memory: Store? = nil
local override: Store? = nil
local jobId = "studio"
local started = false
local warnedMemory = false
local entries: { [string]: Entry } = {}
-- Loads waiting on an earlier visit's entry, by player id. A player who leaves
-- meanwhile cancels the load, so it never takes a lock nobody would release.
local pending: { [string]: { cancelled: boolean } } = {}
local inflight = 0 -- save and offline-update threads running
local listeners: { (id: string) -> () } = {}
local resultListeners: { (id: string, change: Profile.Change) -> () } = {}

-- ---------------------------------------------------------------- helpers

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in value do
		out[key] = deepCopy(child)
	end
	return out
end

local function same(a: any, b: any): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in a do
		if not same(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function newMemoryStore(): Store
	local keys: { [string]: any } = {}
	return {
		GetAsync = function(_self: any, key: string): (any, any)
			return deepCopy(keys[key]), nil
		end,
		UpdateAsync = function(_self: any, key: string, transform: (any, any) -> any): (any, any)
			local old = deepCopy(keys[key])
			local new = transform(old, nil)
			if new == nil then
				return old, nil
			end
			keys[key] = deepCopy(new)
			return deepCopy(new), nil
		end,
	}
end

local function waitUntil(condition: () -> boolean, limit: number)
	local waited = 0
	while not condition() and waited < limit do
		task.wait(0.1)
		waited += 0.1
	end
end

local UNAVAILABLE = { "publish this place", "studio access to apis", "api services", "studioaccesstoapis" }

-- True if a DataStore error says the place can't use DataStores at all (not
-- published, or Studio API access is off), as opposed to a passing failure.
local function isUnavailable(err: string): boolean
	local lower = string.lower(err)
	for _, phrase in UNAVAILABLE do
		if string.find(lower, phrase, 1, true) then
			return true
		end
	end
	return false
end

-- Swaps to the in-memory store, warning once. Only in Studio, where it is the
-- expected state of an unpublished place; a live server keeps retrying instead
-- of silently dropping saves. Returns true if a request should be retried now.
local function fallBackToMemory(): boolean
	if not RunService:IsStudio() then
		return false
	end
	if memory == nil then
		memory = newMemoryStore()
	end
	if store == memory then
		return false
	end
	store = memory
	if not warnedMemory then
		warnedMemory = true
		warn(
			"[270] DataStore unavailable (publish the place and enable Studio API access to save); using memory"
		)
	end
	return true
end

local function getStore(): Store
	if store == nil then
		store = override
		if store == nil then
			local DataStoreService = game:GetService("DataStoreService")
			store = DataStoreService:GetDataStore(STORE_NAME) :: any
		end
	end
	return store :: Store
end

-- Calls `call` with the store, retrying errors with exponential backoff. An
-- "unavailable" error switches to memory and retries at once without using up
-- an attempt. Returns (true, nil) or (false, the last error).
local function attempt(label: string, name: string, attempts: number, call: (Store) -> ()): (boolean, string?)
	local lastError: string? = nil
	local tries = 0
	while tries < attempts do
		tries += 1
		local ok, err = pcall(function(): string?
			call(getStore())
			return nil
		end)
		if ok then
			return true, nil
		end
		local message: string = tostring(err)
		lastError = message
		if isUnavailable(message) and fallBackToMemory() then
			tries -= 1
		elseif tries < attempts then
			warn(`[270] DataStore {label} for {name} failed (try {tries} of {attempts}): {message}`)
			task.wait(RETRY_WAIT * 2 ^ (tries - 1))
		end
	end
	return false, lastError
end

-- True if `old` (a stored record) is locked by a different, live server.
local function lockedElsewhere(old: any, at: number): boolean
	if type(old) ~= "table" or type(old.lock) ~= "table" then
		return false
	end
	local lock = old.lock
	if lock.jobId == jobId or type(lock.at) ~= "number" then
		return false
	end
	local age = at - lock.at
	return age < LOCK_TTL and age > -LOCK_TTL
end

local function recordData(old: any): any
	if type(old) == "table" then
		return old.data
	end
	return nil
end

local function recordPending(old: any): { Profile.Pending }
	return Profile.cleanPending(if type(old) == "table" then old.pending else nil)
end

-- Merges a record's pending results into `profile`, once each. Returns the new
-- profile and the results that changed it.
local function mergePending(
	profile: Profile.Profile,
	list: { Profile.Pending }
): (Profile.Profile, { Profile.Pending })
	local merged: { Profile.Pending } = {}
	for _, item in list do
		local nextProfile, _, applied = Profile.settle(profile, item.id, item.result)
		if applied then
			profile = nextProfile
			table.insert(merged, item)
		end
	end
	return profile, merged
end

local function announce(id: string, change: Profile.Change)
	for _, listener in resultListeners do
		task.spawn(listener, id, change)
	end
end

-- ---------------------------------------------------------------- loading

-- Takes the lock and reads the profile. A held lock is retried with backoff,
-- then the profile is read without it and left read-only.
local function acquire(entry: Entry): { Profile.Pending }
	local blockedBy: any = nil
	local newer = false
	local loaded: Profile.Profile? = nil
	local merged: { Profile.Pending } = {}
	local lockedAt = 0
	for round = 1, LOCK_ATTEMPTS do
		local ok, err = attempt("load", entry.name, ERROR_ATTEMPTS, function(s: Store)
			s:UpdateAsync(entry.key, function(old: any): any
				-- UpdateAsync may call this more than once: start clean every time.
				blockedBy, newer, loaded, merged = nil, false, nil, {}
				local at = os.time()
				if lockedElsewhere(old, at) then
					blockedBy = old.lock.jobId
					return nil
				end
				if Profile.isFromFuture(recordData(old)) then
					newer = true
					return nil
				end
				-- Results that waited for whoever holds this player's data come in now.
				local profile, list = mergePending(Profile.migrate(recordData(old)), recordPending(old))
				merged = list
				loaded = profile
				lockedAt = at
				return { lock = { jobId = jobId, at = at }, data = profile }
			end)
		end)
		if not ok then
			warn(`[270] could not load data for {entry.name}, playing without saved stats: {err}`)
			return {}
		end
		if loaded then
			entry.profile = loaded
			entry.writable = true
			entry.lastWrite = lockedAt
			return merged
		end
		if newer or round == LOCK_ATTEMPTS then
			break
		end
		task.wait(LOCK_WAIT * 2 ^ (round - 1))
	end

	-- Read-only: show what is saved, but never write it.
	local raw: any = nil
	local ok, err = attempt("read", entry.name, ERROR_ATTEMPTS, function(s: Store)
		raw = s:GetAsync(entry.key)
	end)
	if not ok then
		warn(`[270] could not read data for {entry.name}, playing without saved stats: {err}`)
		return {}
	end
	entry.profile = Profile.migrate(raw ~= nil and recordData(raw) or nil)
	entry.writable = false
	if newer then
		warn(
			`[270] {entry.name}'s data was saved by a newer version of the game; read-only, nothing will be saved`
		)
	else
		warn(
			`[270] {entry.name}'s data is in use by another server ({tostring(blockedBy)}); `
				.. "loaded read-only, nothing will be saved"
		)
	end
	return {}
end

-- ---------------------------------------------------------------- saving

local function write(entry: Entry, release: boolean)
	local snapshot = entry.profile
	if snapshot == nil or not entry.writable then
		return
	end
	local lost = false
	local merged: { Profile.Pending } = {}
	local wroteAt = 0
	local ok, err = attempt("save", entry.name, ERROR_ATTEMPTS, function(s: Store)
		s:UpdateAsync(entry.key, function(old: any): any
			lost, merged = false, {}
			local at = os.time()
			if lockedElsewhere(old, at) then
				lost = true
				return nil
			end
			-- Merge, never overwrite: results another server left for this player.
			local data, list = mergePending(snapshot :: Profile.Profile, recordPending(old))
			merged = list
			wroteAt = at
			return { lock = if release then nil else { jobId = jobId, at = at }, data = data }
		end)
	end)
	if not ok then
		warn(`[270] could not save data for {entry.name}: {err}`)
	elseif lost then
		entry.writable = false
		warn(`[270] another server took {entry.name}'s data; this server will not save it again`)
	else
		entry.lastWrite = wroteAt
		-- The saved data has them: so does the profile in memory, and the player hears.
		for _, item in merged do
			local profile = entry.profile
			if profile then
				local nextProfile, change, applied = Profile.settle(profile, item.id, item.result)
				if applied then
					entry.profile = nextProfile
					announce(entry.id, change)
				end
			end
		end
	end
end

-- Saves the entry's latest profile, one save at a time per player. A request that
-- arrives mid-save marks the entry dirty and the running loop saves again. Yields.
local function persist(entry: Entry)
	entry.dirty = true
	if entry.saving then
		return
	end
	entry.saving = true
	inflight += 1
	while entry.dirty do
		entry.dirty = false
		write(entry, entry.release)
	end
	entry.saving = false
	inflight -= 1
end

-- Last save for a player who left: saves, clears the lock, forgets them. Yields.
local function finalize(entry: Entry)
	entry.release = true
	if entry.writable then
		persist(entry)
		waitUntil(function()
			return not entry.saving
		end, SHUTDOWN_WAIT)
	end
	if entries[entry.id] == entry then
		entries[entry.id] = nil
	end
end

-- Applies `transform` to a stored record of a player who is no longer here (a
-- change that is not a match result). Results already waiting in the record
-- are merged first, so none is dropped. Yields; runs on its own thread.
local function updateOffline(
	id: string,
	key: string,
	name: string,
	transform: (Profile.Profile) -> Profile.Profile
)
	inflight += 1
	local blocked = false
	for round = 1, LOCK_ATTEMPTS do
		local ok, err = attempt("update", name, ERROR_ATTEMPTS, function(s: Store)
			s:UpdateAsync(key, function(old: any): any
				blocked = false
				local at = os.time()
				if lockedElsewhere(old, at) or Profile.isFromFuture(recordData(old)) then
					blocked = true
					return nil
				end
				local lock = if type(old) == "table" then old.lock else nil
				local profile = mergePending(Profile.migrate(recordData(old)), recordPending(old))
				return { lock = lock, data = transform(profile) }
			end)
		end)
		if not ok then
			warn(`[270] could not save a change for {name}: {err}`)
			break
		end
		if not blocked then
			break
		end
		if round == LOCK_ATTEMPTS then
			warn(`[270] could not save a change for {name} ({id}): their data is in use by another server`)
			break
		end
		task.wait(LOCK_WAIT * 2 ^ (round - 1))
	end
	inflight -= 1
end

-- Records match result `item` for a player whose data this server does not
-- hold (they left, or it is read-only here). If another server holds the lock
-- (or the data is from a newer version), the result joins the record's pending
-- list for that server to merge; otherwise it is applied to the stored profile
-- now, with any results already waiting. Never blocked by a lock. Yields; runs
-- on its own thread.
local function recordOffline(id: string, key: string, name: string, item: Profile.Pending)
	inflight += 1
	local waiting = false
	local ok, err = attempt("result", name, ERROR_ATTEMPTS, function(s: Store)
		s:UpdateAsync(key, function(old: any): any
			local at = os.time()
			local list = recordPending(old)
			waiting = lockedElsewhere(old, at) or Profile.isFromFuture(recordData(old))
			if waiting then
				local known = false
				for _, other in list do
					if other.id == item.id then
						known = true
					end
				end
				if not known then
					table.insert(list, item)
				end
				while #list > Profile.PENDING_MAX do
					table.remove(list, 1)
				end
				return { lock = old.lock, data = recordData(old), pending = list }
			end
			local profile = mergePending(Profile.migrate(recordData(old)), list)
			profile = Profile.settle(profile, item.id, item.result)
			local lock = if type(old) == "table" then old.lock else nil
			return { lock = lock, data = profile }
		end)
	end)
	if not ok then
		warn(`[270] could not record a result for {name} ({id}): {err}`)
	elseif waiting then
		print(`[270] result {item.id} for {id} waits for the server that holds their data`)
	end
	inflight -= 1
end

-- ---------------------------------------------------------------- public API

-- Applies the changes that arrived while the profile was loading, in order.
-- A profile that can't be saved (read-only, or never loaded) sends a match
-- result to the stored record's pending list and drops anything else with a warning.
local function applyQueued(entry: Entry)
	local queued = entry.queued
	entry.queued = {}
	for _, item in queued do
		local profile = entry.profile
		local pendingItem = item.pending
		if profile and entry.writable then
			entry.profile = item.transform(profile)
			entry.dirty = true
			local applied = item.applied
			if applied then
				applied()
			end
		elseif pendingItem then
			task.spawn(recordOffline, entry.id, entry.key, entry.name, pendingItem)
		else
			warn(`[270] could not save a change for {entry.name}: their data is not writable`)
		end
	end
end

-- Loads a player's profile (yields). Call it from its own thread.
function DataService.load(id: string, name: string)
	-- A previous visit may still be saving and releasing the lock.
	local ticket = { cancelled = false }
	pending[id] = ticket
	waitUntil(function()
		return entries[id] == nil or ticket.cancelled
	end, SHUTDOWN_WAIT)
	if pending[id] == ticket then
		pending[id] = nil
	end
	if ticket.cancelled then
		return -- the player left again before this load began
	end
	local entry: Entry = {
		id = id,
		key = KEY_PREFIX .. id,
		name = name,
		profile = nil,
		writable = false,
		loaded = false,
		leaving = false,
		saving = false,
		dirty = false,
		release = false,
		lastWrite = 0,
		queued = {},
	}
	entries[id] = entry
	local merged = acquire(entry)
	entry.loaded = true
	applyQueued(entry)
	if entry.leaving then
		finalize(entry)
		return
	end
	if entry.dirty then
		task.spawn(persist, entry)
	end
	local profile = entry.profile
	if profile then
		print(
			`[270] loaded {name}: rating {profile.rating} ({profile.wins}-{profile.losses})`
				.. if entry.writable then "" else ", read-only"
		)
	end
	if #merged > 0 then
		print(`[270] {name}: {#merged} result(s) from another server merged on load`)
	end
	for _, listener in listeners do
		listener(id)
	end
end

-- The player left: saves, releases the lock, forgets them (on its own thread).
-- A load still waiting on an earlier visit is cancelled.
function DataService.remove(id: string)
	local waiting = pending[id]
	if waiting then
		waiting.cancelled = true
		pending[id] = nil
	end
	local entry = entries[id]
	if entry == nil or entry.leaving then
		return
	end
	entry.leaving = true
	if entry.loaded then
		task.spawn(finalize, entry)
	end
end

-- Calls `listener(id)` each time a player's profile finishes loading.
function DataService.onLoaded(listener: (id: string) -> ())
	table.insert(listeners, listener)
end

-- The player's profile, or nil while loading or if it could not be loaded.
function DataService.profile(id: string): Profile.Profile?
	local entry = entries[id]
	if entry and entry.loaded and not entry.leaving then
		return entry.profile
	end
	return nil
end

function DataService.summary(id: string): Profile.Summary?
	local profile = DataService.profile(id)
	return if profile then Profile.summary(profile) else nil
end

-- The player's rating if it is loaded and can be saved, else nil. A match is
-- rated only if both players have one.
function DataService.rating(id: string): number?
	local entry = entries[id]
	if entry and entry.loaded and entry.writable and not entry.leaving and entry.profile then
		return entry.profile.rating
	end
	return nil
end

-- Calls `listener(id, change)` when results another server left for a player
-- here are merged into their profile (on load or on a save).
function DataService.onResult(listener: (id: string, change: Profile.Change) -> ())
	table.insert(resultListeners, listener)
end

-- Applies match result `resultId` (unique per match and player) to a player's
-- profile, once, and saves it at once:
--   "Live": the player is here; in memory now, the save is under way.
--   "Queued": their profile is still loading; applied when it finishes.
--   "Offline": the player has left, or their data is read-only here; the
--     stored record gets it (now, or as a pending result for the server that
--     holds it).
-- `applied(change)` is called once the change is in memory here ("Live" at
-- once, "Queued" after the load); never for "Offline".
function DataService.applyResult(
	id: string,
	resultId: string,
	result: Profile.Result,
	applied: ((Profile.Change) -> ())?
): string
	local item: Profile.Pending = { id = resultId, result = result }
	local entry = entries[id]
	if entry and not entry.loaded then
		local change: Profile.Change? = nil
		table.insert(entry.queued, {
			transform = function(profile: Profile.Profile): Profile.Profile
				local nextProfile, made = Profile.settle(profile, resultId, result)
				change = made
				return nextProfile
			end,
			applied = function()
				if applied and change then
					applied(change)
				end
			end,
			pending = item,
		})
		return "Queued"
	end
	local profile = if entry then entry.profile else nil
	if entry == nil or not entry.writable or profile == nil then
		task.spawn(recordOffline, id, KEY_PREFIX .. id, if entry then entry.name else id, item)
		return "Offline"
	end
	local nextProfile, change, did = Profile.settle(profile, resultId, result)
	if did then
		entry.profile = nextProfile
		task.spawn(persist, entry)
	end
	if applied then
		applied(change)
	end
	return "Live"
end

-- Applies `transform` to a player's profile; the batched save writes it.
--   "Live": the player is here; the change is in memory now (a change that
--     leaves the profile as it was is not saved).
--   "Queued": their profile is still loading; the change is applied, in order,
--     the moment the load finishes (and dropped with a warning if it can't be saved).
--   "Offline": the player has left; their stored record is updated on its own thread.
--   "Skipped": their data is not writable; nothing changed.
-- `applied` is called once the change is in memory: at once for "Live", after the
-- load for "Queued", never otherwise. `transform` must not mutate its argument and
-- may run more than once (for "Offline").
function DataService.update(
	id: string,
	transform: (Profile.Profile) -> Profile.Profile,
	applied: (() -> ())?
): string
	local entry = entries[id]
	if entry == nil then
		task.spawn(updateOffline, id, KEY_PREFIX .. id, id, transform)
		return "Offline"
	end
	if not entry.loaded then
		table.insert(entry.queued, { transform = transform, applied = applied })
		return "Queued"
	end
	local profile = entry.profile
	if not entry.writable or profile == nil then
		return "Skipped"
	end
	local changed = transform(profile)
	if not same(changed, profile) then
		entry.profile = changed
		entry.dirty = true
		if entry.leaving then
			task.spawn(persist, entry) -- their last save is under way: make sure it has this
		end
	end
	if applied then
		applied()
	end
	return "Live"
end

-- Saves every loaded player and releases their locks, waiting up to `limit`
-- seconds for all saves to finish. For game:BindToClose.
function DataService.flushAll(limit: number)
	for _, entry in entries do
		if entry.loaded and entry.writable then
			entry.release = true
			task.spawn(persist, entry)
		end
	end
	local waited = 0
	while inflight > 0 and waited < limit do
		task.wait(0.1)
		waited += 0.1
	end
	if inflight > 0 then
		warn(`[270] shutting down with {inflight} save(s) unfinished`)
	end
end

-- Starts loading players as they join and saving as they leave.
function DataService.start(options: Options?)
	if started then
		return
	end
	started = true
	override = if options then options.store else nil
	local id = if options then options.jobId else nil
	if id == nil then
		id = game.JobId
	end
	jobId = if id == "" or id == nil then "studio" else id

	local function join(player: Player)
		task.spawn(DataService.load, tostring(player.UserId), player.Name)
	end
	Players.PlayerAdded:Connect(join)
	for _, player in Players:GetPlayers() do
		join(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		DataService.remove(tostring(player.UserId))
	end)
	game:BindToClose(function()
		DataService.flushAll(SHUTDOWN_WAIT)
	end)
	-- Batched saves: a changed profile, or a lock due a refresh (which also
	-- merges results another server left meanwhile).
	task.spawn(function()
		while true do
			task.wait(SAVE_INTERVAL)
			local at = os.time()
			for _, entry in entries do
				if
					entry.loaded
					and entry.writable
					and not entry.leaving
					and not entry.saving
					and (entry.dirty or at - entry.lastWrite >= LOCK_REFRESH)
				then
					task.spawn(persist, entry)
				end
			end
		end
	end)
end

return DataService
