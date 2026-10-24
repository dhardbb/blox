--!strict
-- Reported custom names and the owners' review (the Name Pass, D-069). Nothing
-- is removed automatically: a report puts the name in a review queue, and an
-- admin (server/Admins) keeps it or removes it. A removed name goes on the
-- reviewed blocklist, which blocks it and names with it as whole words
-- (CustomName.blockedReviewed, D-076) on every server.
--
-- Storage (DataStores, every call pcall'd and retried with backoff like
-- DataService; a failure is logged and the caller is told, never an error):
--   NameReports_v1 / "Queue_<k>"  { [setter user id]: { name, reporters =
--     { [reporter id]: unix time }, first, last } }, k = 1..NAME_REVIEW_SHARDS
--     by setter id (D-076): the queue is split over several keys so one key's
--     write throughput (4 MB a minute) never limits reports. Each key keeps at
--     most NAME_REVIEW_MAX / NAME_REVIEW_SHARDS names (the longest-quiet one
--     drops off) and NAME_REPORTERS_MAX reporters each. The single "Queue" key
--     of 0.13.0 is still read and emptied by reviews; nothing new goes there.
--   NameBlocklist_v1 / "Entries"  { entry }, at most NAME_BLOCKLIST_MAX, each
--     CustomName.reviewEntry (older entries are folded names without "=").
-- Sharing: MessagingService topic "NameBlocklist" (a 1 kB message: the entry)
-- tells every running server about a removal at once; each server also reads
-- the list before its first name check and then every NAME_BLOCKLIST_REFRESH
-- seconds, so a missed message is caught up, and a reload never drops an entry
-- this server already has. Until the first read succeeds no new name passes
-- (NameService fails closed) and the read is retried every
-- NAME_BLOCKLIST_RETRY seconds. MessagingService is optional (pcall'd).
--
-- Reviews act only on the name the admin saw (D-076): Keep and Remove carry it,
-- and a queue entry whose name changed since is left alone. Remove writes the
-- blocklist first and takes the queue entry only once that write succeeded, so
-- a failed write loses nothing and the admin can try again.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Sim.Config)
local CustomName = require(ReplicatedStorage.Shared.Net.CustomName)
local NameService = require(script.Parent.NameService)

local NameReview = {}

NameReview.REPORTS_STORE = "NameReports_v1"
NameReview.LEGACY_QUEUE_KEY = "Queue" -- 0.13.0's single key: read and emptied, never added to
NameReview.BLOCKLIST_STORE = "NameBlocklist_v1"
NameReview.BLOCKLIST_KEY = "Entries"
NameReview.TOPIC = "NameBlocklist"

local ATTEMPTS = 3 -- tries per DataStore call
local RETRY_WAIT = 1 -- seconds before the first retry; doubles each time

export type Entry = {
	userId: number, -- the setter
	name: string,
	count: number, -- distinct reporters
	first: number, -- unix time of the first report
	last: number, -- unix time of the latest report
}

-- Why a review did not happen (MatchService turns these into reason codes).
export type Failure = "Changed" | "Failed"
local CHANGED: Failure = "Changed"
local FAILED: Failure = "Failed"

local config = Config.defaults
local entries: { string } = {} -- the reviewed blocklist
local pending = 0 -- names waiting for review, as last read
local listeners: { (added: { string }) -> () } = {}
local started = false
local loaded = false -- the reviewed blocklist has been read at least once
local loading = false
local looping = false -- the reload loop is running

local function storeOf(name: string): any?
	local ok, store = pcall(function(): any
		return DataStoreService:GetDataStore(name)
	end)
	return if ok then store else nil
end

-- Runs `call` up to ATTEMPTS times; true if one try did not error.
local function attempt(label: string, call: (store: any) -> (), storeName: string): boolean
	local store = storeOf(storeName)
	if store == nil then
		return false
	end
	for try = 1, ATTEMPTS do
		local ok, err = pcall(function()
			call(store)
		end)
		if ok then
			return true
		end
		warn(`[270] name review {label} failed (try {try} of {ATTEMPTS}): {tostring(err)}`)
		if try < ATTEMPTS then
			task.wait(RETRY_WAIT * 2 ^ (try - 1))
		end
	end
	return false
end

local function cleanQueue(raw: any): { [string]: any }
	return if type(raw) == "table" then raw else {}
end

local function countOf(queue: { [string]: any }): number
	local n = 0
	for _ in queue do
		n += 1
	end
	return n
end

-- The queue key a setter's reports go to.
function NameReview.shardKey(setterId: number): string
	return `Queue_{setterId % config.NAME_REVIEW_SHARDS + 1}`
end

-- Every queue key, the legacy one first.
local function queueKeys(): { string }
	local keys = { NameReview.LEGACY_QUEUE_KEY }
	for k = 1, config.NAME_REVIEW_SHARDS do
		table.insert(keys, `Queue_{k}`)
	end
	return keys
end

-- Reads every queue key at once (one thread each). Returns the raw values by
-- key, or nil if any read failed. Yields.
local function readQueues(): { [string]: any }?
	local keys = queueKeys()
	local out: { [string]: any } = {}
	local left = #keys
	local failed = false
	for _, key in keys do
		task.spawn(function()
			local ok = attempt("queue read", function(store: any)
				out[key] = store:GetAsync(key)
			end, NameReview.REPORTS_STORE)
			if not ok then
				failed = true
			end
			left -= 1
		end)
	end
	while left > 0 do
		task.wait(0.05)
	end
	return if failed then nil else out
end

local function applyEntries(list: { string })
	entries = list
	-- NameService lets names through only once the stored list has been read:
	-- an entry from another server's message alone does not count.
	if loaded then
		NameService.setReviewed(list)
	end
end

local function notify(added: { string })
	for _, listener in listeners do
		task.spawn(listener, added)
	end
end

-- Adds entries this server did not have (a removal here or on another server).
local function addEntries(new: { string })
	local list = table.clone(entries)
	local added: { string } = {}
	for _, entry in new do
		if table.find(list, entry) == nil then
			table.insert(list, entry)
			table.insert(added, entry)
		end
	end
	while #list > config.NAME_BLOCKLIST_MAX do
		table.remove(list, 1)
	end
	if #added > 0 then
		applyEntries(list)
		notify(added)
	end
end

-- Calls `listener(added)` when the reviewed blocklist gains entries (here or
-- on another server), so the server can clear names that now match it.
function NameReview.onBlocklist(listener: (added: { string }) -> ())
	table.insert(listeners, listener)
end

-- The reviewed blocklist as this server has it.
function NameReview.blocklist(): { string }
	return table.clone(entries)
end

-- True once the reviewed blocklist has been read.
function NameReview.isLoaded(): boolean
	return loaded
end

-- Names waiting for review, as last read (for the admins' Lobby button).
function NameReview.pendingCount(): number
	return pending
end

-- Reloads the reviewed blocklist and merges it with the entries this server
-- already has (a stored list that lags never drops one); tells listeners about
-- new entries. Returns whether the read worked. Yields.
function NameReview.reload(): boolean
	local raw: any = nil
	local ok = attempt("blocklist read", function(store: any)
		raw = store:GetAsync(NameReview.BLOCKLIST_KEY)
	end, NameReview.BLOCKLIST_STORE)
	if not ok then
		return false
	end
	local stored: { string } = {}
	if type(raw) == "table" then
		for _, entry in raw do
			if type(entry) == "string" and entry ~= "" and #entry <= 64 then
				table.insert(stored, entry)
			end
		end
	end
	if not loaded then
		loaded = true
		applyEntries(entries) -- marks the list loaded in NameService, even when empty
	end
	addEntries(stored)
	return true
end

-- Re-reads how many names wait for review. Yields.
function NameReview.refreshCount(): number
	local raw = readQueues()
	if raw then
		local total = 0
		for _, value in raw do
			total += countOf(cleanQueue(value))
		end
		pending = total
	end
	return pending
end

-- Records that `reporterId` reported `setterId`'s name `name` (queue for
-- review). A second report of the same name by the same player changes
-- nothing. Returns false if it could not be saved. Yields; never throws.
function NameReview.report(setterId: number, reporterId: number, name: string, now: number): boolean
	local cap = math.ceil(config.NAME_REVIEW_MAX / config.NAME_REVIEW_SHARDS)
	return attempt("report", function(store: any)
		store:UpdateAsync(NameReview.shardKey(setterId), function(old: any): any
			local queue = cleanQueue(old)
			local key = tostring(setterId)
			local entry = queue[key]
			if type(entry) ~= "table" or entry.name ~= name or type(entry.reporters) ~= "table" then
				entry = { name = name, reporters = {}, first = now, last = now }
			end
			local who = tostring(reporterId)
			if entry.reporters[who] == nil and countOf(entry.reporters) < config.NAME_REPORTERS_MAX then
				entry.reporters[who] = now
			end
			entry.last = now
			queue[key] = entry
			-- A full key drops its longest-quiet name (it was seen least recently).
			while countOf(queue) > cap do
				local oldestKey, oldest = nil, math.huge
				for k, e in queue do
					local at = if type(e) == "table" and type(e.last) == "number" then e.last else 0
					if k ~= key and at < oldest then
						oldestKey, oldest = k, at
					end
				end
				if oldestKey == nil then
					break
				end
				queue[oldestKey] = nil
			end
			return queue
		end)
	end, NameReview.REPORTS_STORE)
end

-- The review queue, most recently reported first. Nil if it could not be read.
function NameReview.list(): { Entry }?
	local queues = readQueues()
	if queues == nil then
		return nil
	end
	local seen: { [number]: Entry } = {}
	for _, raw in queues do
		for id, entry in cleanQueue(raw) do
			local userId = tonumber(id)
			if userId and type(entry) == "table" and type(entry.name) == "string" then
				local found: Entry = {
					userId = userId,
					name = entry.name,
					count = if type(entry.reporters) == "table" then countOf(entry.reporters) else 0,
					first = if type(entry.first) == "number" then entry.first else 0,
					last = if type(entry.last) == "number" then entry.last else 0,
				}
				-- A setter in both the legacy key and a shard: the newer report wins.
				local before = seen[userId]
				if before == nil or found.last >= before.last then
					seen[userId] = found
				end
			end
		end
	end
	local out: { Entry } = {}
	for _, entry in seen do
		table.insert(out, entry)
	end
	table.sort(out, function(a: Entry, b: Entry): boolean
		if a.last ~= b.last then
			return a.last > b.last
		end
		return a.userId < b.userId
	end)
	pending = #out
	return out
end

-- The name waiting in the queue for `setterId` (its shard, else the legacy
-- key), and whether the store answered.
local function nameInQueue(setterId: number): (string?, boolean)
	local name: string? = nil
	for _, key in { NameReview.shardKey(setterId), NameReview.LEGACY_QUEUE_KEY } do
		local raw: any = nil
		local ok = attempt("queue read", function(store: any)
			raw = store:GetAsync(key)
		end, NameReview.REPORTS_STORE)
		if not ok then
			return nil, false
		end
		local entry = cleanQueue(raw)[tostring(setterId)]
		if type(entry) == "table" and type(entry.name) == "string" then
			name = entry.name
			break
		end
	end
	return name, true
end

-- Takes `setterId`'s entry off the queue if its name is still `name`. Returns
-- whether the store answered.
local function take(setterId: number, name: string): boolean
	local all = true
	for _, key in { NameReview.shardKey(setterId), NameReview.LEGACY_QUEUE_KEY } do
		local ok = attempt("queue update", function(store: any)
			store:UpdateAsync(key, function(old: any): any
				local queue = cleanQueue(old)
				local entry = queue[tostring(setterId)]
				if type(entry) ~= "table" or entry.name ~= name then
					return nil -- nothing to take here (or a newer report): leave the key alone
				end
				queue[tostring(setterId)] = nil
				return queue
			end)
		end, NameReview.REPORTS_STORE)
		all = all and ok
	end
	if all then
		pending = math.max(0, pending - 1)
	end
	return all
end

-- "Keep": dismisses the reports on `setterId`'s name, if it is still `name`.
-- Returns nil, or why not. Yields.
function NameReview.keep(setterId: number, name: string): Failure?
	local current, ok = nameInQueue(setterId)
	if not ok then
		return FAILED
	end
	if current ~= name then
		return CHANGED
	end
	if not take(setterId, name) then
		return FAILED
	end
	return nil
end

-- "Remove": if `setterId`'s queued name is still `name`, adds it to the
-- reviewed blocklist (saved first: a failed save changes nothing), then takes
-- it off the queue and tells every server. Returns the blocklist entry, or nil
-- and why not. Yields.
function NameReview.remove(setterId: number, name: string): (string?, Failure?)
	local current, ok = nameInQueue(setterId)
	if not ok then
		return nil, FAILED
	end
	if current ~= name then
		return nil, CHANGED
	end
	local entry = CustomName.reviewEntry(name)
	if entry ~= "" then
		local saved = attempt("blocklist write", function(store: any)
			store:UpdateAsync(NameReview.BLOCKLIST_KEY, function(old: any): any
				local list = if type(old) == "table" then old else {}
				if table.find(list, entry) == nil then
					table.insert(list, entry)
					while #list > config.NAME_BLOCKLIST_MAX do
						table.remove(list, 1)
					end
				end
				return list
			end)
		end, NameReview.BLOCKLIST_STORE)
		if not saved then
			-- Nothing changed anywhere: the report stays in the queue for another try.
			warn(`[270] could not save {entry} to the reviewed blocklist; the report stays queued`)
			return nil, FAILED
		end
	end
	if not take(setterId, name) then
		warn(`[270] {entry} is blocked, but its report could not be taken off the queue`)
	end
	if entry ~= "" then
		addEntries({ entry })
		pcall(function()
			game:GetService("MessagingService"):PublishAsync(NameReview.TOPIC, entry)
		end)
	end
	return entry, nil
end

-- Keeps reloading: every NAME_BLOCKLIST_RETRY seconds until the first read
-- works, then every NAME_BLOCKLIST_REFRESH seconds.
local function keepLoading()
	if looping then
		return
	end
	looping = true
	task.spawn(function()
		while true do
			task.wait(if loaded then config.NAME_BLOCKLIST_REFRESH else config.NAME_BLOCKLIST_RETRY)
			NameReview.reload()
		end
	end)
end

-- Reads the reviewed blocklist the first time a name is checked on this
-- server (a server where nobody uses names never touches the DataStore), then
-- keeps it current. Returns whether it has loaded; while it has not, no new
-- name passes (NameService). Yields the first time.
function NameReview.ensureLoaded(): boolean
	if loaded then
		return true
	end
	if loading then
		while loading do
			task.wait(0.1)
		end
		return loaded
	end
	loading = true
	NameReview.reload()
	loading = false
	keepLoading()
	return loaded
end

-- Listens for removals on other servers (MessagingService; no DataStore).
function NameReview.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		pcall(function()
			game:GetService("MessagingService"):SubscribeAsync(NameReview.TOPIC, function(message: any)
				local entry = if type(message) == "table" then message.Data else nil
				if type(entry) ~= "string" or entry == "" or #entry > 64 then
					return
				end
				addEntries({ entry })
			end)
		end)
	end)
end

return NameReview
