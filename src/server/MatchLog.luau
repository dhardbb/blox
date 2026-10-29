--!strict
-- Match records for balance analysis (docs/DESIGN.md D-094): one record per
-- finished match, written to the DataStore "MatchRecords_v1" under
-- Net/MatchRecord.key ("<YYYYMMDD>_<server>_<match>_<seed>"). The humans export
-- them with Open Cloud and summarize them with tests/harness/records.luau
-- (docs/TESTING.md, "Match records").
--
-- Never in a match's way: MatchLog.record builds the record in a pcall, queues
-- it and returns at once; one writer thread drains the queue. Each write
-- checks the server's DataStore write budget first and leaves RESERVE for
-- player saves (DataService), waiting while the budget is low; a failed write
-- is retried with exponential backoff, then dropped with a warning. A full
-- queue drops its oldest record. Nothing here can throw into MatchService.
--
-- Limits (create.roblox.com, data stores "Error codes and limits"): a key name
-- is at most 50 characters, a value at most 4,194,304 characters (records are
-- cut to MatchRecord.MAX_CHARS, typically 3-5 KB); SetAsync shares the
-- server's StandardWrite budget of 60 + 40 per player a minute with the
-- profile saves; each key takes one write ever, far under the per-key 4 MB a
-- minute. Storage counts towards the experience's quota (500 MB + 1 MB per
-- lifetime user): the humans delete old days after exporting them.
--
-- In an unpublished Studio place, or with Studio API access off, the first
-- write fails as "unavailable": the log turns itself off for the session with
-- one warning, and each record's size is still printed.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchRecord = require(ReplicatedStorage.Shared.Net.MatchRecord)

local MatchLog = {}

local QUEUE_MAX = 30 -- records waiting to be written; the oldest drops past this
local ATTEMPTS = 5 -- tries per record after errors, RETRY_WAIT * 2^n apart
local RETRY_WAIT = 2 -- seconds
local RESERVE = 20 -- StandardWrite budget left for player saves: wait while the budget is at or under this
local BUDGET_WAIT = 5 -- seconds between budget checks
local BUDGET_TRIES = 24 -- budget checks before writing anyway (two minutes)
local SHUTDOWN_WAIT = 10 -- seconds BindToClose waits for the queue (DataService waits 25 of Roblox's 30)

-- The DataStore call this uses. Tests supply their own.
export type Store = {
	SetAsync: (self: any, key: string, value: any) -> any,
}

export type Options = {
	store: Store?, -- default: DataStoreService:GetDataStore(MatchRecord.STORE)
	budget: (() -> number)?, -- default: GetRequestBudgetForRequestType(StandardWrite)
}

type Item = { key: string, record: MatchRecord.Record, size: number }

local store: Store? = nil
local override: Store? = nil
local budgetOf: (() -> number)? = nil
local queue: { Item } = {}
local writing = false
local disabled = false
local stats = { written = 0, dropped = 0, failed = 0 }

local UNAVAILABLE = { "publish this place", "studio access to apis", "api services", "studioaccesstoapis" }

local function isUnavailable(err: string): boolean
	local lower = string.lower(err)
	for _, phrase in UNAVAILABLE do
		if string.find(lower, phrase, 1, true) then
			return true
		end
	end
	return false
end

local function getStore(): Store
	if store == nil then
		store = override
		if store == nil then
			local DataStoreService = game:GetService("DataStoreService")
			store = DataStoreService:GetDataStore(MatchRecord.STORE) :: any
		end
	end
	return store :: Store
end

-- The server's write budget now; math.huge when it cannot be read (then the
-- write simply tries, and a throttle comes back as an error to retry).
local function budget(): number
	local ok, value = pcall(function(): number
		if budgetOf then
			return budgetOf()
		end
		local DataStoreService = game:GetService("DataStoreService")
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.StandardWrite)
	end)
	return if ok and type(value) == "number" then value else math.huge
end

local function measure(value: any): number
	return #HttpService:JSONEncode(value)
end

-- Writes one record, waiting for budget and retrying errors. Yields.
local function write(item: Item)
	for _ = 1, BUDGET_TRIES do
		if budget() > RESERVE then
			break
		end
		task.wait(BUDGET_WAIT)
	end
	for attempt = 1, ATTEMPTS do
		local ok, err = pcall(function(): string?
			getStore():SetAsync(item.key, item.record)
			return nil
		end)
		if ok then
			stats.written += 1
			print(`[270] match record saved: {MatchRecord.STORE}/{item.key} ({item.size} chars)`)
			return
		end
		local message = tostring(err)
		if isUnavailable(message) then
			disabled = true
			warn(
				`[270] match records are off this session: no data store here (publish the place and enable Studio API access). {message}`
			)
			return
		end
		if attempt == ATTEMPTS then
			stats.failed += 1
			warn(`[270] could not save match record {item.key}: {message}`)
		else
			task.wait(RETRY_WAIT * 2 ^ (attempt - 1))
		end
	end
end

local function drain()
	while #queue > 0 and not disabled do
		local item = table.remove(queue, 1) :: Item
		local ok, err = pcall(function(): string?
			write(item)
			return nil
		end)
		if not ok then
			stats.failed += 1
			warn(`[270] match record {item.key} failed: {err}`)
		end
	end
	if disabled then
		queue = {}
	end
	writing = false
end

-- Queues the record of a finished session (MatchRecord.build) and returns its
-- key, or nil when it could not be built or the log is off. Never yields and
-- never throws.
function MatchLog.record(session: MatchRecord.SessionLike, info: MatchRecord.Info): string?
	local ok, result = pcall(function(): Item?
		local built = MatchRecord.build(session, info)
		local record, size = MatchRecord.fit(built, measure)
		if record == nil then
			warn(`[270] match record for {session.id} is too big to save ({size} chars)`)
			return nil
		end
		return { key = MatchRecord.key(record), record = record, size = size }
	end)
	if not ok then
		warn(`[270] could not build the match record for {session.id}: {result}`)
		return nil
	end
	local item = result :: Item?
	if item == nil then
		return nil
	end
	if disabled then
		print(`[270] match record {item.key} ({item.size} chars) not saved: match records are off`)
		return nil
	end
	table.insert(queue, item)
	while #queue > QUEUE_MAX do
		local gone = table.remove(queue, 1) :: Item
		stats.dropped += 1
		warn(`[270] match record queue full: dropped {gone.key}`)
	end
	if not writing then
		writing = true
		task.spawn(drain)
	end
	return item.key
end

-- Counts so far (tests and the debug log): written, dropped, failed.
function MatchLog.counts(): { written: number, dropped: number, failed: number }
	return table.clone(stats)
end

-- Records waiting to be written.
function MatchLog.pending(): number
	return #queue + (if writing then 1 else 0)
end

-- Sets the store and budget (tests) and waits for the queue on shutdown.
function MatchLog.start(options: Options?)
	if options then
		override = options.store
		budgetOf = options.budget
	end
	game:BindToClose(function()
		local waited = 0
		while (#queue > 0 or writing) and not disabled and waited < SHUTDOWN_WAIT do
			task.wait(0.25)
			waited += 0.25
		end
	end)
end

return MatchLog
