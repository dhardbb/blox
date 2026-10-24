--!strict
-- The Lobby's "1,234 online" (docs/DESIGN.md D-083; rules in Net/Online).
-- Every Matchmaking.ONLINE_PERIOD seconds this server writes its player count
-- to the sorted map ONLINE_MAP (key = its JobId, expiring after ONLINE_TTL)
-- and reads the shared total; if the total is older than a period it sums the
-- map (GetRangeAsync pages of up to 200) and writes the total back. Cost per
-- server: about 2 requests a period, plus one unit per server in the game for
-- whichever server recomputes the total.
--
-- Where memory stores are off (Studio, an unpublished place) the count is
-- this server's players. When a live read fails the last good total is kept
-- for two periods, then the count is unknown (nil) and the Lobby hides it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matchmaking = require(ReplicatedStorage.Shared.Net.Matchmaking)
local Online = require(ReplicatedStorage.Shared.Net.Online)
local Memory = require(script.Parent.Memory)

local OnlineCount = {}

local TOTAL_KEY = "Total"
local MAX_PAGES = 5 -- 1,000 servers: more than this game will see

local total: number? = nil
local totalAt = -math.huge -- os.time() of the last good total
local listeners: { (number?) -> () } = {}
local running = false

local function jobKey(): string
	return if game.JobId == "" then "studio" else string.sub(game.JobId, 1, 100)
end

local function here(): number
	return #Players:GetPlayers()
end

-- What the Lobby shows now, or nil while unknown.
function OnlineCount.get(): number?
	if not Memory.available() then
		return here()
	end
	if total == nil or os.time() - totalAt > 2 * Matchmaking.ONLINE_PERIOD + 5 then
		return nil
	end
	return Online.shown(total, here())
end

-- Calls `listener(count)` whenever the shown count may have changed.
function OnlineCount.onChanged(listener: (number?) -> ())
	table.insert(listeners, listener)
end

local function changed()
	local shown = OnlineCount.get()
	for _, listener in listeners do
		task.spawn(listener, shown)
	end
end

local function sumAll(map: any, now: number): number?
	local rows: { any } = {}
	local lower: any = nil
	for _ = 1, MAX_PAGES do
		local ok, page = Memory.call("online range", function(): any
			return map:GetRangeAsync(Enum.SortDirection.Ascending, Matchmaking.ONLINE_PAGE, lower)
		end)
		if not ok or type(page) ~= "table" then
			return nil
		end
		for _, row in page do
			table.insert(rows, row)
		end
		if #page < Matchmaking.ONLINE_PAGE then
			break
		end
		local last = page[#page]
		lower = { key = last.key }
	end
	return Online.sum(rows, now, Matchmaking.ONLINE_TTL)
end

-- One period: report, read (and maybe recompute) the total. Yields.
function OnlineCount.step()
	if not Memory.available() then
		changed()
		return
	end
	local map = Memory.sorted(Matchmaking.ONLINE_MAP)
	local totals = Memory.hash(Matchmaking.ONLINE_TOTAL)
	if map == nil or totals == nil then
		changed()
		return
	end
	local now = os.time()
	Memory.call("online report", function(): any
		return map:SetAsync(jobKey(), Online.report(here(), now), Matchmaking.ONLINE_TTL)
	end)
	local ok, stored = Memory.call("online total", function(): any
		return totals:GetAsync(TOTAL_KEY)
	end)
	if ok then
		if Online.due(stored, now, Matchmaking.ONLINE_PERIOD) then
			local sum = sumAll(map, now)
			if sum then
				Memory.call("online total write", function(): any
					return totals:SetAsync(TOTAL_KEY, Online.report(sum, now), 4 * Matchmaking.ONLINE_PERIOD)
				end)
				total, totalAt = sum, now
			end
		else
			total, totalAt = stored.n, now
		end
	end
	changed()
end

-- Starts the loop (once). The first report goes out at once.
function OnlineCount.start()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while true do
			local ok, err = pcall(function(): string?
				OnlineCount.step()
				return nil
			end)
			if not ok then
				warn(`[270] online count: {err}`)
			end
			task.wait(Matchmaking.ONLINE_PERIOD)
		end
	end)
	-- A player joining or leaving changes at least this server's share.
	Players.PlayerAdded:Connect(changed)
	Players.PlayerRemoving:Connect(function()
		task.defer(changed)
	end)
	pcall(function()
		game:BindToClose(function()
			if Memory.available() then
				local map = Memory.sorted(Matchmaking.ONLINE_MAP)
				if map then
					pcall(function()
						map:RemoveAsync(jobKey())
					end)
				end
			end
		end)
	end)
end

return OnlineCount
