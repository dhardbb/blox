--!strict
-- Who owns the Color Pass (D-055), checked here and only here: the server
-- never takes a client's word for it. Each player is checked once when they
-- join (MarketplaceService:UserOwnsGamePassAsync, pcall'd and retried with
-- backoff) and the answer is cached for their visit. A purchase made in the
-- game marks them as owners at once (PromptGamePassPurchaseFinished on the
-- server, wasPurchased = true). A check that fails counts as "does not own":
-- that player is dealt red or blue, never an error. `refresh` checks again
-- (MatchService calls it when a player who is not known to own the pass tries
-- to save a color, e.g. after a failed check or a purchase made outside the game).
--
-- While Net/Products.COLOR_PASS_ID is 0 nothing is checked and nobody owns it.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Products = require(ReplicatedStorage.Shared.Net.Products)

local PassService = {}

local CHECK_ATTEMPTS = 3 -- tries per check
local CHECK_WAIT = 2 -- seconds before the first retry; doubles each time

local owns: { [string]: boolean } = {} -- player id -> owns the pass (absent: not known)
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

-- The pass id, or nil while it is not set up.
function PassService.colorPassId(): number?
	local id = Products.COLOR_PASS_ID
	if type(id) ~= "number" or id <= 0 then
		return nil
	end
	return id
end

-- True if the server knows this player owns the Color Pass. Never yields.
function PassService.ownsColorPass(id: string): boolean
	return PassService.colorPassId() ~= nil and owns[id] == true
end

-- Asks Roblox whether the player owns the pass and caches the answer (yields).
-- Returns the cached answer. A failure leaves an earlier answer alone.
function PassService.refresh(player: Player): boolean
	local passId = PassService.colorPassId()
	local id = idOf(player)
	if passId == nil then
		return false
	end
	for attempt = 1, CHECK_ATTEMPTS do
		local ok, result = pcall(function(): boolean
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if present[id] ~= player then
			return false -- they left while we asked
		end
		if ok then
			-- A purchase that landed while we asked wins over a stale "no".
			local before = owns[id]
			owns[id] = result == true or before == true
			if owns[id] ~= before then
				notify(id)
			end
			return owns[id]
		end
		warn(
			`[270] Color Pass check for {player.Name} failed (try {attempt} of {CHECK_ATTEMPTS}): {tostring(
				result
			)}`
		)
		if attempt < CHECK_ATTEMPTS then
			task.wait(CHECK_WAIT * 2 ^ (attempt - 1))
		end
	end
	warn(`[270] could not check {player.Name}'s Color Pass; they get the default colors for now`)
	return owns[id] == true
end

-- Calls `listener(id)` whenever a player's ownership becomes known or changes.
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
		if PassService.colorPassId() ~= nil then
			task.spawn(PassService.refresh, player)
		end
	end
	Players.PlayerAdded:Connect(join)
	for _, player in Players:GetPlayers() do
		join(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local id = idOf(player)
		present[id] = nil
		owns[id] = nil
	end)
	-- The server-side event carries the purchase's real outcome (docs:
	-- "should only be listened to in a server script").
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamePassId: number, wasPurchased: boolean)
			local passId = PassService.colorPassId()
			local id = idOf(player)
			if passId == nil or gamePassId ~= passId or not wasPurchased or present[id] ~= player then
				return
			end
			if owns[id] ~= true then
				owns[id] = true
				print(`[270] {player.Name} bought the Color Pass`)
				notify(id)
			end
		end
	)
end

return PassService
