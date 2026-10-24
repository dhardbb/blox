--!strict
-- Who may buy, set and see custom candidate names (the Name Pass, D-063).
--
-- The designers asked for "16+". Roblox exposes no age to scripts, so the
-- user chose a stand-in: Roblox's own chat permission. Text chat now needs an
-- age check, but a parent can also allow it, so this is close to, not the same
-- as, "age-checked 16+".
--   eligible(player)     TextChatService:CanUserChatAsync(player.UserId)
--   canSee(setter, viewer)  TextChatService:CanUsersChatAsync(setter, viewer):
--                        a viewer sees a setter's name only if the two may
--                        exchange chat messages (parental controls, blocks).
-- Docs (reference/engine/classes/TextChatService): both yield; CanUserChatAsync
-- errors when the user is not in this server; CanUsersChatAsync is server-only
-- and errors unless both are in this server. Every call is pcall'd and an
-- error counts as "no": this fails closed.
--
-- Answers are cached per player for their visit: `refresh` asks when they join
-- (MatchService), `forget` drops them when they leave, so a rejoin asks again.
-- `isEligible` only reads the cache (never yields: a match start must not wait
-- on it); while unknown it is false. `canSee` is cached per pair.
--
-- Studio: the chat APIs may not answer there. Set STUDIO_OVERRIDE = true (in
-- this file, never committed as true) to make everyone eligible and every pair
-- allowed, only while RunService:IsStudio() is true; a live server ignores it.

local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local NameEligibility = {}

-- Server-only test switch for Studio (see the header). Has no effect in a live server.
NameEligibility.STUDIO_OVERRIDE = false

local eligible: { [number]: boolean } = {} -- user id -> may chat (absent: not asked yet)
local pairs_: { [string]: boolean } = {} -- "from:to" -> may exchange messages

local function studioOverride(): boolean
	return NameEligibility.STUDIO_OVERRIDE == true and RunService:IsStudio()
end

-- Asks Roblox again whether `player` may chat and caches the answer (yields).
-- An error is "no".
function NameEligibility.refresh(player: Player): boolean
	if studioOverride() then
		eligible[player.UserId] = true
		return true
	end
	local ok, result = pcall(function(): boolean
		return TextChatService:CanUserChatAsync(player.UserId)
	end)
	local answer = ok and result == true
	if not ok then
		warn(`[270] name eligibility check failed for {player.UserId}: {tostring(result)}`)
	end
	eligible[player.UserId] = answer
	return answer
end

-- The cached answer; false while unknown. Never yields.
function NameEligibility.isEligible(player: Player): boolean
	return studioOverride() or eligible[player.UserId] == true
end

-- Whether `viewer` may see a name `setter` wrote: both eligible and allowed to
-- exchange messages. Cached per pair; yields the first time. An error is "no".
function NameEligibility.canSee(setter: Player, viewer: Player): boolean
	if not NameEligibility.isEligible(setter) or not NameEligibility.isEligible(viewer) then
		return false
	end
	if setter == viewer or studioOverride() then
		return true
	end
	local key = `{setter.UserId}:{viewer.UserId}`
	local cached = pairs_[key]
	if cached ~= nil then
		return cached
	end
	local ok, result = pcall(function(): boolean
		return TextChatService:CanUsersChatAsync(setter.UserId, viewer.UserId)
	end)
	if not ok then
		warn(`[270] name visibility check failed for {key}: {tostring(result)}`)
	end
	local answer = ok and result == true
	pairs_[key] = answer
	return answer
end

-- Drops everything cached about a player who left.
function NameEligibility.forget(player: Player)
	local id = player.UserId
	eligible[id] = nil
	for key in pairs_ do
		local from, to = string.match(key, "^(%-?%d+):(%-?%d+)$")
		if tonumber(from) == id or tonumber(to) == id then
			pairs_[key] = nil
		end
	end
end

return NameEligibility
