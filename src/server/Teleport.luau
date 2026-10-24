--!strict
-- Teleports for matching across servers (docs/DESIGN.md D-080), as the
-- "Teleport between places" guide recommends: TeleportAsync from the server in
-- a pcall, retried (Matchmaking.TELEPORT_ATTEMPTS), and TeleportInitFailed
-- (a teleport that started but failed, leaving the player here) retried with
-- the TeleportOptions the event hands back, for the failures worth retrying
-- (Failure, Flooded, IsTeleporting). After the last try the caller's
-- `failed(player)` runs so it can put the player back where they were.
--
-- TeleportService does not work in Studio playtests (Memory.available() is
-- false there, so nothing calls this).
--
-- Roblox APIs (checked against the engine reference): TeleportService:
-- ReserveServerAsync(placeId) -> (accessCode, privateServerId) (ReserveServer
-- is deprecated); TeleportAsync(placeId, players, options) (server only, at
-- most 50 players); TeleportOptions.ReservedServerAccessCode and
-- :SetTeleportData(data) (value types only; visible to the client);
-- TeleportInitFailed(player, teleportResult, errorMessage, placeId,
-- teleportOptions); Enum.TeleportResult.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Matchmaking = require(ReplicatedStorage.Shared.Net.Matchmaking)

local Teleport = {}

local RETRY_WAIT = 1 -- s between TeleportAsync tries
local FLOOD_WAIT = 5 -- s before retrying a Flooded teleport

type Pending = {
	tries: number,
	failed: (Player) -> (),
}

local pending: { [Player]: Pending } = {}
local started = false

local function service(): any
	return game:GetService("TeleportService")
end

-- A new reserved server of this place: (accessCode, privateServerId), or nil.
-- Yields.
function Teleport.reserve(): (string?, string?)
	local placeId = game.PlaceId
	for attempt = 1, Matchmaking.TELEPORT_ATTEMPTS do
		local ok, access, privateId = pcall(function(): (string, string)
			return service():ReserveServerAsync(placeId)
		end)
		if
			ok
			and type(access) == "string"
			and access ~= ""
			and type(privateId) == "string"
			and privateId ~= ""
		then
			return access, privateId
		end
		if not ok then
			warn(`[270] ReserveServerAsync failed (try {attempt}): {access}`)
		end
		task.wait(RETRY_WAIT * attempt)
	end
	return nil, nil
end

local function attempt(player: Player, options: Instance): boolean
	local ok, err = pcall(function()
		service():TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		warn(`[270] TeleportAsync for {player.UserId} failed: {err}`)
	end
	return ok
end

local function giveUp(player: Player)
	local entry = pending[player]
	pending[player] = nil
	if entry and player.Parent ~= nil then
		local ok, err = pcall(function(): string?
			entry.failed(player)
			return nil
		end)
		if not ok then
			warn(`[270] teleport failure handler: {err}`)
		end
	end
end

local function start()
	if started then
		return
	end
	started = true
	pcall(function()
		service().TeleportInitFailed:Connect(
			function(player: Player, result: EnumItem, message: string, _placeId: number, options: Instance)
				local entry = pending[player]
				if entry == nil then
					return
				end
				warn(`[270] teleport for {player.UserId} did not start: {result.Name} {message}`)
				local retry = result.Name == "Failure"
					or result.Name == "Flooded"
					or result.Name == "IsTeleporting"
				if not retry or entry.tries >= Matchmaking.TELEPORT_ATTEMPTS then
					giveUp(player)
					return
				end
				entry.tries += 1
				task.wait(if result.Name == "Flooded" then FLOOD_WAIT else RETRY_WAIT)
				if pending[player] == entry and player.Parent ~= nil and not attempt(player, options) then
					giveUp(player)
				end
			end
		)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
	end)
end

-- Sends `player` to the reserved server `access`, or with access nil to a
-- public server of this place (a lobby). `data` is the teleport data (plain
-- values, seen by the client). `failed(player)` runs if every try fails.
-- Returns false at once if the first round of tries failed (failed() has run).
-- Yields.
function Teleport.send(
	player: Player,
	access: string?,
	data: { [string]: any },
	failed: (Player) -> ()
): boolean
	start()
	local made, options = pcall(function(): Instance
		local o = Instance.new("TeleportOptions")
		if access then
			(o :: any).ReservedServerAccessCode = access
		end
		(o :: any):SetTeleportData(data)
		return o
	end)
	if not made then
		warn(`[270] could not build TeleportOptions: {options}`)
		pcall(failed, player)
		return false
	end
	local entry: Pending = { tries = 0, failed = failed }
	pending[player] = entry
	for try = 1, Matchmaking.TELEPORT_ATTEMPTS do
		entry.tries = try
		if player.Parent == nil then
			pending[player] = nil
			return true -- they left meanwhile (perhaps the teleport went through)
		end
		if attempt(player, options) then
			return true
		end
		task.wait(RETRY_WAIT * try)
	end
	giveUp(player)
	return false
end

return Teleport
