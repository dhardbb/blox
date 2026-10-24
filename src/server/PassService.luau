--!strict
-- Who owns the game's passes, checked here and only here: the server never
-- takes a client's word for it. Two passes (Net/Products): the Color Pass
-- (D-055) and the Name Pass (D-069). Each player is checked once per pass when
-- they join (MarketplaceService:UserOwnsGamePassAsync, pcall'd and retried with
-- backoff) and the answer is cached for their visit. A purchase made in the
-- game marks them as owners at once (PromptGamePassPurchaseFinished on the
-- server, wasPurchased = true). A check that fails counts as "does not own":
-- that player gets the default (red or blue; the candidate's own name), never
-- an error. `refresh` / `refreshName` check again (MatchService calls them when
-- a player who is not known to own a pass tries to use it, e.g. after a failed
-- check or a purchase made outside the game).
--
-- While a pass id is 0 nothing is checked for it and nobody owns it, except
-- admins (server/Admins: the owner and Config.ADMIN_USER_IDS), who own both
-- passes for free, always, without asking MarketplaceService (D-069).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Products = require(ReplicatedStorage.Shared.Net.Products)
local Admins = require(script.Parent.Admins)

local PassService = {}

local CHECK_ATTEMPTS = 3 -- tries per check
local CHECK_WAIT = 2 -- seconds before the first retry; doubles each time

type Kind = string -- "Color" | "Name"
local KINDS: { Kind } = { "Color", "Name" }
local LABEL: { [Kind]: string } = { Color = "Color Pass", Name = "Name Pass" }

local owns: { [Kind]: { [string]: boolean } } = { Color = {}, Name = {} } -- pass -> player id -> owns it (absent: not known)
local present: { [string]: Player } = {} -- players in this server, by id
local listeners: { (id: string) -> () } = {}
local started = false

local function idOf(player: Player): string
	return tostring(player.UserId)
end

local function notify(id: string)
	for _, listener in listeners do
		task.spawn(listener, id)
	end
end

local function passId(kind: Kind): number?
	local id = if kind == "Color" then Products.COLOR_PASS_ID else Products.NAME_PASS_ID
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	return id
end

-- The Color Pass id, or nil while it is not set up.
function PassService.colorPassId(): number?
	return passId("Color")
end

-- The Name Pass id, or nil while it is not set up.
function PassService.namePassId(): number?
	return passId("Name")
end

local function isAdmin(id: string): boolean
	local userId = tonumber(id)
	return userId ~= nil and Admins.isAdminId(userId)
end

-- True if the server knows this player owns the Color Pass (an admin always
-- does). Never yields.
function PassService.ownsColorPass(id: string): boolean
	return isAdmin(id) or (passId("Color") ~= nil and owns["Color"][id] == true)
end

-- True if the server knows this player owns the Name Pass (an admin always
-- does). Never yields.
function PassService.ownsNamePass(id: string): boolean
	return isAdmin(id) or (passId("Name") ~= nil and owns["Name"][id] == true)
end

-- Whether this player is offered a pass's feature at all: it is set up, or
-- they are an admin (who has it free even while the id is 0).
function PassService.offered(kind: string, id: string): boolean
	return passId(kind) ~= nil or isAdmin(id)
end

-- Asks Roblox whether the player owns a pass and caches the answer (yields).
-- Returns the cached answer. A failure leaves an earlier answer alone.
local function refresh(kind: Kind, player: Player): boolean
	local pass = passId(kind)
	local id = idOf(player)
	if isAdmin(id) then
		return true
	end
	if pass == nil then
		return false
	end
	local known = owns[kind]
	for attempt = 1, CHECK_ATTEMPTS do
		local ok, result = pcall(function(): boolean
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass)
		end)
		if present[id] ~= player then
			return false -- they left while we asked
		end
		if ok then
			-- A purchase that landed while we asked wins over a stale "no".
			local before = known[id]
			known[id] = result == true or before == true
			if known[id] ~= before then
				notify(id)
			end
			return known[id]
		end
		warn(
			`[270] {LABEL[kind]} check for {player.Name} failed (try {attempt} of {CHECK_ATTEMPTS}): {tostring(
				result
			)}`
		)
		if attempt < CHECK_ATTEMPTS then
			task.wait(CHECK_WAIT * 2 ^ (attempt - 1))
		end
	end
	warn(`[270] could not check {player.Name}'s {LABEL[kind]}; they get the default for now`)
	return known[id] == true
end

-- The Color Pass check (see refresh above).
function PassService.refresh(player: Player): boolean
	return refresh("Color", player)
end

-- The Name Pass check (see refresh above).
function PassService.refreshName(player: Player): boolean
	return refresh("Name", player)
end

-- Calls `listener(id)` whenever a player's ownership of either pass becomes
-- known or changes.
function PassService.onChanged(listener: (id: string) -> ())
	table.insert(listeners, listener)
end

function PassService.start()
	if started then
		return
	end
	started = true
	local function join(player: Player)
		present[idOf(player)] = player
		for _, kind in KINDS do
			if passId(kind) ~= nil then
				task.spawn(refresh, kind, player)
			end
		end
	end
	Players.PlayerAdded:Connect(join)
	for _, player in Players:GetPlayers() do
		join(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local id = idOf(player)
		present[id] = nil
		for _, kind in KINDS do
			owns[kind][id] = nil
		end
	end)
	-- The server-side event carries the purchase's real outcome (docs:
	-- "should only be listened to in a server script").
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			local id = idOf(player)
			if not wasPurchased or present[id] ~= player then
				return
			end
			for _, kind in KINDS do
				local pass = passId(kind)
				if pass ~= nil and gamePassId == pass and owns[kind][id] ~= true then
					owns[kind][id] = true
					print(`[270] {player.Name} bought the {LABEL[kind]}`)
					notify(id)
				end
			end
		end
	)
end

return PassService
