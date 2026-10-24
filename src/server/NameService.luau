--!strict
-- Checks custom candidate names (the Name Pass, D-069) the way Roblox checks
-- chat, before anyone sees them, and fails closed: if anything cannot be
-- checked, the name is turned down and the candidate keeps its own.
--
-- At set time (and once per visit for a saved name): CustomName.normalize (the
-- character rules and the 16-character limit), the blocklists (the static
-- server/NameBlocklist and the names reviewers removed, server/NameReview),
-- then TextService:FilterStringAsync(name, setterId,
-- Enum.TextFilterContext.PublicChat). The result's
-- GetNonChatStringForBroadcastAsync() must come back unchanged (no "#").
--
-- Per viewer, like chat: each viewer gets the name through the same result's
-- GetNonChatStringForUserAsync(viewerId) ("properly filtered ... for the
-- specified UserId based on age and other details"; the docs' per-recipient
-- method for non-chat text; GetChatForUserAsync is deprecated and returns ""),
-- so every viewer gets their own filter level. A viewer whose string differs
-- (any "#") or whose call errors sees the candidate's own name.
--
-- Nothing filtered is stored: the profile keeps the name as typed, and it is
-- filtered again on each visit (the text-filtering guide: stored text "should
-- be filtered when retrieving"). The TextFilterResult lives only in this
-- server's memory while the setter is here (FilterStringAsync needs them in
-- the server).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Sim.Config)
local CustomName = require(ReplicatedStorage.Shared.Net.CustomName)
local NameBlocklist = require(script.Parent.NameBlocklist)

local NameService = {}

-- The static server-only list (server/NameBlocklist). Replaceable by specs.
NameService.BLOCKLIST = NameBlocklist :: { string }

-- Names reviewers removed (server/NameReview keeps it current), and whether it
-- has loaded at least once: until then no new name passes (fail closed).
local reviewed: { string } = {}
local reviewedReady = false

-- user id -> the name they last passed and its TextFilterResult (this visit only)
local results: { [number]: { name: string, result: any } } = {}
-- "setter:viewer:name" -> what that viewer sees (false = the candidate's own)
local shown: { [string]: string | false } = {}

-- Sets the reviewed list (entries from NameBlocklist_v1, CustomName.reviewEntry)
-- and marks it loaded.
function NameService.setReviewed(list: { string })
	reviewed = table.clone(list)
	reviewedReady = true
end

-- True once the reviewed list has loaded (NameReview).
function NameService.reviewedLoaded(): boolean
	return reviewedReady
end

-- True if `name` (already normalized) matches the static list (its own rules:
-- contains, near misses, "=" whole words) or the reviewed list (whole words
-- only, D-078).
function NameService.isBlocked(name: string): boolean
	return CustomName.blocked(name, NameService.BLOCKLIST, Config.defaults)
		or CustomName.blockedReviewed(name, reviewed, Config.defaults)
end

-- True if `name` is exactly a name a reviewer removed (D-078): only then is it
-- taken out of a player's saved data; a name that merely contains it is just
-- not used.
function NameService.isReviewedExact(name: string): boolean
	return CustomName.reviewedExact(name, reviewed)
end

-- Roblox's filter on `name` from `player`: (result, broadcast text) or nil
-- when it could not be reached. Yields.
local function filter(player: Player, name: string): (any, string?)
	local ok, result = pcall(function(): any
		return TextService:FilterStringAsync(name, player.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok or result == nil then
		warn(`[270] name filter failed for {player.UserId}: {tostring(result)}`)
		return nil, nil
	end
	local fine, text = pcall(function(): any
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not fine or type(text) ~= "string" then
		warn(`[270] name filter failed for {player.UserId}: {tostring(text)}`)
		return nil, nil
	end
	return result, text
end

-- Checks what `player` typed. Returns (name, nil) for a name that passed, or
-- (nil, reason) with a CustomName.Reason code. Yields; never throws.
function NameService.check(player: Player, text: any): (string?, string?)
	local name, reason = CustomName.normalize(text, Config.defaults)
	if name == nil then
		return nil, reason
	end
	if not reviewedReady then
		return nil, CustomName.Reason.FilterFailed -- the reviewed list has not loaded yet
	end
	if NameService.isBlocked(name) then
		return nil, CustomName.Reason.Filtered
	end
	local result, broadcast = filter(player, name)
	if result == nil then
		return nil, CustomName.Reason.FilterFailed
	end
	if CustomName.wasFiltered(name, broadcast) then
		return nil, CustomName.Reason.Filtered
	end
	results[player.UserId] = { name = name, result = result }
	return name, nil
end

-- What `viewer` sees of `setter`'s name `name`: the name, or nil for the
-- candidate's own (filtered for that viewer, an error, or never checked this
-- visit). Cached per viewer and name. Yields the first time; never throws.
function NameService.forViewer(setter: Player, viewer: Player, name: string): string?
	local entry = results[setter.UserId]
	if entry == nil or entry.name ~= name then
		return nil
	end
	local key = `{setter.UserId}:{viewer.UserId}:{name}`
	local cached = shown[key]
	if type(cached) == "string" then
		return cached
	elseif cached == false then
		return nil
	end
	local ok, text = pcall(function(): any
		return entry.result:GetNonChatStringForUserAsync(viewer.UserId)
	end)
	if not ok then
		warn(`[270] name filter for viewer {viewer.UserId} failed: {tostring(text)}`)
	end
	local seen = ok and not CustomName.wasFiltered(name, text)
	shown[key] = if seen then name else false
	return if seen then name else nil
end

-- Drops what this server holds about a player who left.
function NameService.forget(player: Player)
	local id = player.UserId
	results[id] = nil
	for key in shown do
		local from, to = string.match(key, "^(%-?%d+):(%-?%d+):")
		if tonumber(from) == id or tonumber(to) == id then
			shown[key] = nil
		end
	end
end

return NameService
