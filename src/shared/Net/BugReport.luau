--!strict
-- Bug reports (docs/DESIGN.md D-090), the pure part. A player writes a few
-- lines in the "Report a bug" sheet; the server (server/BugReports) cleans
-- them here, runs them through Roblox's text filter, and stores them with the
-- game version, the screen and the match id. Admins read the newest in the
-- Lobby. Nothing here touches Roblox.
--
-- Storage: DataStore STORE, one key per UTC day and shard,
-- "Day_<unix day>_<k>" with k = userId % BUG_REPORT_SHARDS + 1, so one player
-- only ever fills their own shard. A key holds at most BUG_REPORTS_PER_KEY
-- reports (the oldest drop off): at 400 characters each that is far under the
-- DataStore's 4 MB per value. The admins' list reads the last
-- BUG_REPORT_LIST_DAYS days of every shard.

local ConfigModule = require("../Sim/Config")

type Config = ConfigModule.Config

local BugReport = {}

BugReport.STORE = "BugReports_v1"
BugReport.MAX_SCREEN = 24 -- characters in the screen tag
BugReport.MAX_BYTES = 2048 -- bytes a BugReport request's text may have before cleaning (Schemas)
BugReport.LIST_MAX = 60 -- reports the admins' list shows at most

local DAY = 86400

-- One stored report.
export type Record = {
	at: number, -- unix time (server)
	userId: number, -- who sent it
	version: string, -- Version.VERSION of the server that took it
	screen: string, -- the screen the player was on (BugReport.screen)
	matchId: string?, -- their match, if they were in one
	text: string, -- filtered by Roblox (TextFilterResult:GetNonChatStringForBroadcastAsync)
}

-- Reason codes for a report that was turned down (client Net words them).
BugReport.Reason = table.freeze({
	TooShort = "BugTooShort",
	TooLong = "BugTooLong",
	TooSoon = "BugTooSoon",
	Limit = "BugLimit",
	Failed = "BugFailed",
})

-- The text as it will be filtered and stored: valid UTF-8, no control
-- characters but line breaks, runs of spaces folded, at most two line breaks
-- in a row, trimmed; between BUG_REPORT_MIN_CHARS and BUG_REPORT_MAX_CHARS
-- characters. Returns (text, nil) or (nil, reason).
function BugReport.clean(raw: any, config: Config): (string?, string?)
	if type(raw) ~= "string" or utf8.len(raw) == nil then
		return nil, BugReport.Reason.TooShort -- not text (or broken UTF-8): nothing to keep
	end
	local text = string.gsub(raw, "\r\n?", "\n")
	text = string.gsub(text, "\t", " ")
	text = string.gsub(text, "[%z\1-\9\11-\31\127]", "")
	text = string.gsub(text, " +", " ")
	text = string.gsub(text, " ?\n ?", "\n")
	text = string.gsub(text, "\n\n\n+", "\n\n")
	text = string.match(text, "^%s*(.-)%s*$") or ""
	local length = utf8.len(text) or 0
	if length < config.BUG_REPORT_MIN_CHARS then
		return nil, BugReport.Reason.TooShort
	end
	if length > config.BUG_REPORT_MAX_CHARS then
		return nil, BugReport.Reason.TooLong
	end
	return text, nil
end

-- The screen tag as sent by the client: letters and digits, at most
-- MAX_SCREEN, else "Unknown".
function BugReport.screen(raw: any): string
	if
		type(raw) == "string"
		and #raw >= 1
		and #raw <= BugReport.MAX_SCREEN
		and string.match(raw, "^%w+$")
	then
		return raw
	end
	return "Unknown"
end

-- The report times that still count for the limit at `now` (the last day).
function BugReport.recent(times: { number }, now: number, _config: Config): { number }
	local out: { number } = {}
	for _, at in times do
		if now - at < DAY then
			table.insert(out, at)
		end
	end
	return out
end

-- May a player whose recent reports were at `times` send one at `now`?
-- Returns (true, nil) or (false, reason).
function BugReport.allowed(times: { number }, now: number, config: Config): (boolean, string?)
	local kept = BugReport.recent(times, now, config)
	local last = -math.huge
	for _, at in kept do
		last = math.max(last, at)
	end
	if #kept >= config.BUG_REPORTS_PER_DAY then
		return false, BugReport.Reason.Limit
	end
	if now - last < config.BUG_REPORT_WAIT then
		return false, BugReport.Reason.TooSoon
	end
	return true, nil
end

-- The key a report by `userId` at unix time `at` goes to.
function BugReport.key(at: number, userId: number, config: Config): string
	return `Day_{math.floor(at / DAY)}_{userId % config.BUG_REPORT_SHARDS + 1}`
end

-- Every key the admins' list reads at unix time `now`: today's shards first,
-- then each earlier day's, for BUG_REPORT_LIST_DAYS days.
function BugReport.keys(now: number, config: Config): { string }
	local today = math.floor(now / DAY)
	local out: { string } = {}
	for d = 0, config.BUG_REPORT_LIST_DAYS - 1 do
		for k = 1, config.BUG_REPORT_SHARDS do
			table.insert(out, `Day_{today - d}_{k}`)
		end
	end
	return out
end

-- True for a stored value shaped like a Record.
function BugReport.isRecord(value: any): boolean
	return type(value) == "table"
		and type(value.at) == "number"
		and type(value.userId) == "number"
		and type(value.version) == "string"
		and type(value.screen) == "string"
		and type(value.text) == "string"
		and (value.matchId == nil or type(value.matchId) == "string")
end

-- The key's new value: the old list (bad entries dropped) with `record` at the
-- end, the oldest dropped past BUG_REPORTS_PER_KEY.
function BugReport.append(old: any, record: Record, config: Config): { Record }
	local list: { Record } = {}
	if type(old) == "table" then
		for _, value in old do
			if BugReport.isRecord(value) then
				table.insert(list, value)
			end
		end
	end
	table.insert(list, record)
	while #list > config.BUG_REPORTS_PER_KEY do
		table.remove(list, 1)
	end
	return list
end

-- Every report in `lists` (the values read from the keys), newest first, at
-- most `max`.
function BugReport.newest(lists: { any }, max: number): { Record }
	local out: { Record } = {}
	for _, list in lists do
		if type(list) == "table" then
			for _, value in list do
				if BugReport.isRecord(value) then
					table.insert(out, value)
				end
			end
		end
	end
	table.sort(out, function(a: Record, b: Record): boolean
		if a.at ~= b.at then
			return a.at > b.at
		end
		return a.userId < b.userId
	end)
	while #out > max do
		table.remove(out)
	end
	return out
end

return table.freeze(BugReport)
