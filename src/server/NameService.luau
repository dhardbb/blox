--!strict
-- Checks a custom candidate name before anyone sees it (the Name Pass, D-063):
-- CustomName.normalize (trim, collapse spaces, the 16-character limit), this
-- server's blocklist, then Roblox's text filter. It fails closed: if the filter
-- cannot be reached, the name is turned down and the candidate keeps its own.
--
-- The filter, as the docs describe it (reference/engine/classes/TextService,
-- TextFilterResult; ui/text-filtering): TextService:FilterStringAsync(text,
-- fromUserId, Enum.TextFilterContext.PublicChat) yields and may throw (do not
-- retry: it retries on its own; it throws if the user is not in this server),
-- and returns a TextFilterResult whose GetNonChatStringForBroadcastAsync() gives
-- the text "in a properly filtered manner for all users": non-chat text every
-- user can see, which a candidate's name is. Hidden characters come back as
-- "#". Any change at all turns the name down ("try another name"). A saved name
-- is filtered again each time a match uses it ("stored text ... should be
-- filtered when retrieving them").

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.Shared.Sim.Config)
local CustomName = require(ReplicatedStorage.Shared.Net.CustomName)

local NameService = {}

-- Server-only: names or parts of names to turn down that Roblox's filter lets
-- through (a real politician's name, a slur the filter misses, a scam phrase).
-- Matched anywhere in the name, ignoring case, spaces and punctuation
-- (CustomName.blocked). Never sent to clients. Empty on purpose: add entries
-- as playtests and reports find them.
NameService.BLOCKLIST = {} :: { string }

-- Roblox's filter on `name` from `player`: the broadcast text, or nil when the
-- filter could not be reached. Yields.
local function filter(player: Player, name: string): string?
	local ok, result = pcall(function(): any
		return TextService:FilterStringAsync(name, player.UserId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok or result == nil then
		warn(`[270] name filter failed for {player.UserId}: {tostring(result)}`)
		return nil
	end
	local shown, text = pcall(function(): any
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not shown or type(text) ~= "string" then
		warn(`[270] name filter failed for {player.UserId}: {tostring(text)}`)
		return nil
	end
	return text
end

-- Checks what `player` typed. Returns (name, nil) for a name everyone may see,
-- or (nil, reason) with a CustomName.Reason code. Yields; never throws.
function NameService.check(player: Player, text: any): (string?, string?)
	local name, reason = CustomName.normalize(text, Config.defaults)
	if name == nil then
		return nil, reason
	end
	if CustomName.blocked(name, NameService.BLOCKLIST) then
		return nil, CustomName.Reason.Filtered
	end
	local filtered = filter(player, name)
	if filtered == nil then
		return nil, CustomName.Reason.FilterFailed
	end
	if CustomName.wasFiltered(name, filtered) then
		return nil, CustomName.Reason.Filtered
	end
	return name, nil
end

return NameService
