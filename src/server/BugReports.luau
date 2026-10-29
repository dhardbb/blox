--!strict
-- Bug reports (docs/DESIGN.md D-090): the server side of the "Report a bug"
-- sheet. A report is cleaned (Net/BugReport.clean), rate-limited per player
-- (BUG_REPORT_WAIT between reports, BUG_REPORTS_PER_DAY a day, kept in this
-- server's memory), filtered by Roblox (TextService:FilterStringAsync with
-- the sender's user id, then TextFilterResult:GetNonChatStringForBroadcastAsync:
-- the text admins read is the text Roblox lets everyone see), and appended to
-- its day's shard in the DataStore Net/BugReport.STORE with the game version,
-- the screen and the match id. If the filter fails the report is not stored
-- (the docs: "If it fails, do not display the text to any user").
--
-- Admins (server/Admins, checked by MatchService on every request) read the
-- newest reports: every shard of the last BUG_REPORT_LIST_DAYS days, newest
-- first, at most BugReport.LIST_MAX.
--
-- Every DataStore call is pcall'd and retried with backoff like NameReview; a
-- failure is logged and the caller told, never an error.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local BugReport = require(ReplicatedStorage.Shared.Net.BugReport)
local Config = require(ReplicatedStorage.Shared.Sim.Config)
local Version = require(ReplicatedStorage.Shared.Version)

local BugReports = {}

local ATTEMPTS = 3 -- tries per DataStore call
local RETRY_WAIT = 1 -- seconds before the first retry; doubles each time

local config = Config.defaults
local sent: { [number]: { number } } = {} -- user id -> unix times of their recent reports (this server)

local function storeOf(): any?
	local ok, store = pcall(function(): any
		return DataStoreService:GetDataStore(BugReport.STORE)
	end)
	return if ok then store else nil
end

-- Runs `call` up to ATTEMPTS times; true if one try did not error.
local function attempt(label: string, call: (store: any) -> ()): boolean
	local store = storeOf()
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
		warn(`[270] bug report {label} failed (try {try} of {ATTEMPTS}): {tostring(err)}`)
		if try < ATTEMPTS then
			task.wait(RETRY_WAIT * 2 ^ (try - 1))
		end
	end
	return false
end

-- The text as Roblox's filter lets everyone see it, or nil if the filter
-- failed. Yields.
local function filtered(player: Player, text: string): string?
	local ok, result = pcall(function(): any
		return TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok or result == nil then
		warn(`[270] bug report filter failed: {tostring(result)}`)
		return nil
	end
	local shown: any = nil
	local done = pcall(function()
		shown = result:GetNonChatStringForBroadcastAsync()
	end)
	if not done or type(shown) ~= "string" then
		return nil
	end
	return shown
end

export type Context = {
	screen: string?, -- as the client sent it
	matchId: string?, -- the player's match, from the server's own records
}

-- Takes a report from `player`. Returns nil when it was stored, else a reason
-- code (Net/BugReport.Reason). Yields.
function BugReports.submit(player: Player, raw: any, context: Context, unix: number): string?
	local text, why = BugReport.clean(raw, config)
	if text == nil then
		return why
	end
	local userId = player.UserId
	local times = BugReport.recent(sent[userId] or {}, unix, config)
	local allowed, limit = BugReport.allowed(times, unix, config)
	if not allowed then
		return limit
	end
	-- Counted before the filter yields, so two quick taps send one report.
	table.insert(times, unix)
	sent[userId] = times
	local clean = filtered(player, text)
	if clean == nil then
		-- Not stored: the try does not count against the player.
		table.remove(times)
		return BugReport.Reason.Failed
	end
	local record: BugReport.Record = {
		at = unix,
		userId = userId,
		version = Version.VERSION,
		screen = BugReport.screen(context.screen),
		matchId = context.matchId,
		text = clean,
	}
	local saved = attempt("save", function(store: any)
		store:UpdateAsync(BugReport.key(unix, userId, config), function(old: any): any
			return BugReport.append(old, record, config)
		end)
	end)
	if not saved then
		table.remove(times)
		return BugReport.Reason.Failed
	end
	print(`[270] bug report from {userId} on {record.screen} saved`)
	return nil
end

-- The newest reports for the admins, or nil if a key could not be read. Reads
-- every key at once (one thread each). Yields.
function BugReports.list(unix: number): { BugReport.Record }?
	local keys = BugReport.keys(unix, config)
	local values: { any } = {}
	local left = #keys
	local failed = false
	for k, key in keys do
		task.spawn(function()
			local ok = attempt("read", function(store: any)
				values[k] = store:GetAsync(key) or false
			end)
			if not ok then
				failed = true
			end
			left -= 1
		end)
	end
	while left > 0 do
		task.wait(0.05)
	end
	if failed then
		return nil
	end
	local lists: { any } = {}
	for k = 1, #keys do
		table.insert(lists, values[k])
	end
	return BugReport.newest(lists, BugReport.LIST_MAX)
end

-- Forgets a player's rate-limit times (tests).
function BugReports.reset()
	table.clear(sent)
end

return BugReports
