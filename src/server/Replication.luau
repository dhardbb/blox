--!strict
-- The wire: creates the two RemoteEvents, rate-limits and schema-checks every
-- client request before handing it on, and sends server messages to players.
-- Rejected requests are logged and answered with a "Rejected" message; a player
-- over the rate limit gets that once per window, and the rest are dropped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Schemas = require(ReplicatedStorage.Shared.Net.Schemas)

local Replication = {}

local RATE_WINDOW = 10 -- seconds
local RATE_LIMIT = 40 -- requests per player per window (a plan is one request)

local toClient: RemoteEvent? = nil
local recent: { [Player]: { number } } = {}
local limitedAt: { [Player]: number } = {} -- when each player was last told they are rate limited

-- Sends one message to a player by id, if they are in this server.
function Replication.send(id: string, message: Remotes.Message)
	local userId = tonumber(id)
	local remote = toClient
	if userId == nil or remote == nil then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		remote:FireClient(player, message)
	end
end

function Replication.reject(player: Player, op: string, reason: string)
	warn(`[270] rejected {op} from {player.Name} ({player.UserId}): {reason}`)
	Replication.send(tostring(player.UserId), { kind = "Rejected", op = op, reason = reason })
end

local function rateLimited(player: Player, now: number): boolean
	local times = recent[player] or {}
	recent[player] = times
	while times[1] and times[1] < now - RATE_WINDOW do
		table.remove(times, 1)
	end
	if #times >= RATE_LIMIT then
		return true
	end
	table.insert(times, now)
	return false
end

-- Creates the remotes and routes every valid request to `handler`.
function Replication.init(handler: (player: Player, request: Remotes.Request) -> ())
	local folder = Instance.new("Folder")
	folder.Name = Remotes.FOLDER
	local toServer = Instance.new("RemoteEvent")
	toServer.Name = Remotes.TO_SERVER
	toServer.Parent = folder
	local remote = Instance.new("RemoteEvent")
	remote.Name = Remotes.TO_CLIENT
	remote.Parent = folder
	folder.Parent = ReplicatedStorage
	toClient = remote

	toServer.OnServerEvent:Connect(function(player: Player, raw: any)
		local clock = os.clock()
		if rateLimited(player, clock) then
			local told = limitedAt[player]
			if told == nil or clock - told >= RATE_WINDOW then
				limitedAt[player] = clock
				Replication.reject(player, "?", "RateLimited")
			end
			return
		end
		local ok, reason, request = Schemas.request(raw)
		if not ok or request == nil then
			local op = if type(raw) == "table" and type(raw.op) == "string"
				then string.sub(raw.op, 1, 16)
				else "?"
			Replication.reject(player, op, reason or "BadShape")
			return
		end
		local handled, err = pcall(function(): string?
			handler(player, request)
			return nil
		end)
		if not handled then
			warn(`[270] error handling {request.op} from {player.Name}: {err}`)
			Replication.reject(player, request.op, "Internal")
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		recent[player] = nil
		limitedAt[player] = nil
	end)
end

return Replication
