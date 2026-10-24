--!strict
-- "1,234 online" on the Lobby (docs/DESIGN.md D-083). Pure: server/OnlineCount
-- does the MemoryStore side. Every server writes its player count to a sorted
-- map (key = its JobId, value = { n, at }) with a short expiry every
-- Matchmaking.ONLINE_PERIOD seconds; whichever server finds the shared total
-- older than that sums the map and writes the total back, and every server
-- reads the total. A crashed server's count expires on its own.

local Online = {}

export type Report = {
	n: number, -- players on that server
	at: number, -- unix time of the report
}

local MAX_PER_SERVER = 700 -- the largest Roblox server; a bigger number is not this game's

function Online.report(n: number, at: number): Report
	return { n = math.max(0, math.floor(n)), at = at }
end

-- True if `value` is a report or a total this game wrote.
function Online.isReport(value: any): boolean
	return type(value) == "table"
		and type(value.n) == "number"
		and value.n == math.floor(value.n)
		and value.n >= 0
		and type(value.at) == "number"
		and value.at == value.at
end

-- Sums the reports (GetRangeAsync items: { key, value }) no older than `ttl`
-- seconds at unix time `now`. Unreadable rows count nothing.
function Online.sum(rows: { any }, now: number, ttl: number): number
	local total = 0
	for _, row in rows do
		local value = if type(row) == "table" then row.value else nil
		if Online.isReport(value) and value.n <= MAX_PER_SERVER and now - value.at <= ttl then
			total += value.n
		end
	end
	return total
end

-- True if the shared total should be computed again: missing, unreadable, or
-- older than `period` seconds.
function Online.due(total: any, now: number, period: number): boolean
	return not Online.isReport(total) or now - total.at >= period
end

-- What the Lobby shows: the total, but never fewer than the players this
-- server can see (a total written before they joined).
function Online.shown(total: number?, here: number): number?
	if total == nil then
		return nil
	end
	return math.max(total, here)
end

-- "1 online", "1,234 online".
function Online.text(n: number): string
	local digits = tostring(math.max(0, math.floor(n)))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then
		grouped = string.sub(grouped, 2)
	end
	return `{grouped} online`
end

return table.freeze(Online)
