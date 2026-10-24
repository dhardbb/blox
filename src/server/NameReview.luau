--!strict
-- Reported custom names and the owners' review (the Name Pass, D-069). Nothing
-- is removed automatically: a report puts the name in a review queue, and an
-- admin (server/Admins) keeps it or removes it. A removed name goes on the
-- reviewed blocklist, which blocks it and names like it (CustomName.blocked:
-- folded, contains, one edit away) on every server.
--
-- Storage (DataStores, every call pcall'd and retried with backoff like
-- DataService; a failure is logged and the caller is told, never an error):
--   NameReports_v1 / "Queue"     { [setter user id]: { name, reporters =
--     { [reporter id]: unix time }, first, last } }, at most NAME_REVIEW_MAX
--     names (the longest-quiet one drops off) and NAME_REPORTERS_MAX reporters
--     each. One key keeps the queue to one UpdateAsync per report; reports are
--     rate-limited per player (MatchService), well inside the write budget.
--   NameBlocklist_v1 / "Entries"  { folded entry }, at most NAME_BLOCKLIST_MAX.
-- Sharing: MessagingService topic "NameBlocklist" (a 1 kB message: the folded
-- entry) tells every running server about a removal at once; each server also
-- reads the list before its first name check and then every
-- NAME_BLOCKLIST_REFRESH seconds, so a missed message is caught up. MessagingService is optional (pcall'd): without
-- it the periodic reload does the job.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Sim.Config)
local CustomName = require(ReplicatedStorage.Shared.Net.CustomName)
local NameService = require(script.Parent.NameService)

local NameReview = {}

NameReview.REPORTS_STORE = "NameReports_v1"
NameReview.QUEUE_KEY = "Queue"
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

local config = Config.defaults
local entries: { string } = {} -- the reviewed blocklist, folded
local pending = 0 -- names waiting for review, as last read
local listeners: { (added: { string }) -> () } = {}
local started = false
local loaded = false -- the reviewed blocklist has been read once
local loading = false

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

local function applyEntries(list: { string })
	entries = list
	NameService.setReviewed(list)
end

local function notify(added: { string })
	for _, listener in listeners do
		task.spawn(listener, added)
	end
end

-- Calls `listener(added)` when the reviewed blocklist gains entries (here or
-- on another server), so the server can clear names that now match it.
function NameReview.onBlocklist(listener: (added: { string }) -> ())
	table.insert(listeners, listener)
end

-- The reviewed blocklist as this server has it (folded entries).
function NameReview.blocklist(): { string }
	return table.clone(entries)
end

-- Names waiting for review, as last read (for the admins' Lobby button).
function NameReview.pendingCount(): number
	return pending
end

-- Reloads the reviewed blocklist; tells listeners about new entries. Yields.
function NameReview.reload(): boolean
	local raw: any = nil
	local ok = attempt("blocklist read", function(store: any)
		raw = store:GetAsync(NameReview.BLOCKLIST_KEY)
	end, NameReview.BLOCKLIST_STORE)
	if not ok then
		return false
	end
	local list: { string } = {}
	local known: { [string]: boolean } = {}
	for _, entry in entries do
		known[entry] = true
	end
	local added: { string } = {}
	if type(raw) == "table" then
		for _, entry in raw do
			if type(entry) == "string" and entry ~= "" and #list < config.NAME_BLOCKLIST_MAX then
				table.insert(list, entry)
				if not known[entry] then
					table.insert(added, entry)
				end
			end
		end
	end
	applyEntries(list)
	if #added > 0 then
		notify(added)
	end
	return true
end

-- Re-reads how many names wait for review. Yields.
function NameReview.refreshCount(): number
	attempt("queue read", function(store: any)
		pending = countOf(cleanQueue(store:GetAsync(NameReview.QUEUE_KEY)))
	end, NameReview.REPORTS_STORE)
	return pending
end

-- Records that `reporterId` reported `setterId`'s name `name` (queue for
-- review). A second report of the same name by the same player changes
-- nothing. Returns false if it could not be saved. Yields; never throws.
function NameReview.report(setterId: number, reporterId: number, name: string, now: number): boolean
	return attempt("report", function(store: any)
		store:UpdateAsync(NameReview.QUEUE_KEY, function(old: any): any
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
			-- A full queue drops the longest-quiet name (it was seen least recently).
			while countOf(queue) > config.NAME_REVIEW_MAX do
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
			pending = countOf(queue)
			return queue
		end)
	end, NameReview.REPORTS_STORE)
end

-- The review queue, most recently reported first. Nil if it could not be read.
function NameReview.list(): { Entry }?
	local raw: any = nil
	local ok = attempt("queue read", function(store: any)
		raw = store:GetAsync(NameReview.QUEUE_KEY)
	end, NameReview.REPORTS_STORE)
	if not ok then
		return nil
	end
	local out: { Entry } = {}
	for key, entry in cleanQueue(raw) do
		local userId = tonumber(key)
		if userId and type(entry) == "table" and type(entry.name) == "string" then
			table.insert(out, {
				userId = userId,
				name = entry.name,
				count = if type(entry.reporters) == "table" then countOf(entry.reporters) else 0,
				first = if type(entry.first) == "number" then entry.first else 0,
				last = if type(entry.last) == "number" then entry.last else 0,
			})
		end
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

-- Takes `setterId`'s entry off the queue; returns the name it had (nil if
-- there was none) and whether the store answered.
local function take(setterId: number): (string?, boolean)
	local name: string? = nil
	local ok = attempt("queue update", function(store: any)
		store:UpdateAsync(NameReview.QUEUE_KEY, function(old: any): any
			local queue = cleanQueue(old)
			local entry = queue[tostring(setterId)]
			name = if type(entry) == "table" and type(entry.name) == "string" then entry.name else nil
			queue[tostring(setterId)] = nil
			pending = countOf(queue)
			return queue
		end)
	end, NameReview.REPORTS_STORE)
	return name, ok
end

-- "Keep": dismisses the reports on `setterId`'s name. Yields.
function NameReview.keep(setterId: number): boolean
	local _, ok = take(setterId)
	return ok
end

-- "Remove": takes the name off the queue and adds it (folded) to the reviewed
-- blocklist on every server. Returns the removed name, or nil. Yields.
function NameReview.remove(setterId: number): string?
	local name, ok = take(setterId)
	if not ok or name == nil then
		return nil
	end
	local folded = CustomName.fold(name)
	if folded == "" then
		return name
	end
	local saved = attempt("blocklist write", function(store: any)
		store:UpdateAsync(NameReview.BLOCKLIST_KEY, function(old: any): any
			local list = if type(old) == "table" then old else {}
			if table.find(list, folded) == nil then
				table.insert(list, folded)
				while #list > config.NAME_BLOCKLIST_MAX do
					table.remove(list, 1)
				end
			end
			return list
		end)
	end, NameReview.BLOCKLIST_STORE)
	if not saved then
		warn(
			`[270] could not save {folded} to the reviewed blocklist; this server blocks it until it restarts`
		)
	end
	if table.find(entries, folded) == nil then
		local list = table.clone(entries)
		table.insert(list, folded)
		applyEntries(list)
		notify({ folded })
	end
	pcall(function()
		game:GetService("MessagingService"):PublishAsync(NameReview.TOPIC, folded)
	end)
	return name
end

-- Reads the reviewed blocklist the first time a name is checked on this
-- server (a server where nobody uses names never touches the DataStore), then
-- reloads it every NAME_BLOCKLIST_REFRESH seconds. Yields the first time.
function NameReview.ensureLoaded()
	if loaded then
		return
	end
	if loading then
		while loading do
			task.wait(0.1)
		end
		return
	end
	loading = true
	NameReview.reload()
	loaded = true
	loading = false
	task.spawn(function()
		while true do
			task.wait(config.NAME_BLOCKLIST_REFRESH)
			NameReview.reload()
		end
	end)
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
				local folded = if type(message) == "table" then message.Data else nil
				if type(folded) ~= "string" or folded == "" or #folded > 64 then
					return
				end
				if table.find(entries, folded) == nil then
					local list = table.clone(entries)
					table.insert(list, folded)
					applyEntries(list)
					notify({ folded })
				end
			end)
		end)
	end)
end

return NameReview
