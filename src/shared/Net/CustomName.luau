--!strict
-- Custom candidate names (the Name Pass, docs/DESIGN.md D-063), the pure part:
-- cleaning up what a player typed and the length limit, each a
-- small function of its own so the server and the specs share them. The text
-- filter (TextService) and the server-only blocklist live in server/NameService;
-- who may use names lives in server/NameEligibility.
--
--   CustomName.normalize(text, config) -> (name?, reason?)
--     trims, collapses every run of whitespace to one space, and turns down
--     anything that is not a string, not UTF-8, holds a control character or
--     a "#" (Roblox's filter writes "#" over what it hides), is empty, or is
--     too long. Never throws.
--   CustomName.fitsLength(name, config) -> boolean   at most NAME_MAX_LENGTH characters
--   CustomName.wasFiltered(name, filtered) -> boolean
--     the filter changed the text or hid part of it
--   CustomName.blocked(name, list) -> boolean
--     the name contains an entry of `list` (letters only, case ignored)
--   CustomName.Reason   the reason codes a SetName request is turned down with

local ConfigModule = require("../Sim/Config")

type Config = ConfigModule.Config

local CustomName = {}

CustomName.Reason = table.freeze({
	NoNamePass = "NoNamePass", -- the pass is not set up, or the player does not own it
	NotEligible = "NameNotEligible", -- not eligible (Roblox does not let them chat)
	BadText = "NameBadText", -- not text, not UTF-8, a control character or "#"
	Empty = "NameEmpty", -- nothing left after trimming
	TooLong = "NameTooLong", -- over NAME_MAX_LENGTH characters
	Filtered = "NameFiltered", -- Roblox's filter (or the blocklist) hid part of it
	FilterFailed = "NameFilterFailed", -- the filter could not be reached: fail closed
	NotSaved = "NameNotSaved", -- the player's saved data is not loaded (the lobby; a match uses the name anyway)
})

-- Characters in `name` (UTF-8 code points), or nil when it is not UTF-8.
local function length(name: string): number?
	return utf8.len(name)
end

function CustomName.fitsLength(name: string, config: Config): boolean
	local n = length(name)
	return n ~= nil and n <= config.NAME_MAX_LENGTH
end

function CustomName.normalize(text: any, config: Config): (string?, string?)
	if type(text) ~= "string" or length(text) == nil then
		return nil, CustomName.Reason.BadText
	end
	-- Tabs and newlines are whitespace here; every other control character is not allowed.
	local spaced = string.gsub(text, "%s+", " ")
	if string.find(spaced, "%c") or string.find(spaced, "#", 1, true) then
		return nil, CustomName.Reason.BadText
	end
	local trimmed = string.match(spaced, "^ *(.-) *$") or ""
	if trimmed == "" then
		return nil, CustomName.Reason.Empty
	end
	if not CustomName.fitsLength(trimmed, config) then
		return nil, CustomName.Reason.TooLong
	end
	return trimmed, nil
end

function CustomName.wasFiltered(name: string, filtered: any): boolean
	return type(filtered) ~= "string" or filtered ~= name or string.find(filtered, "#", 1, true) ~= nil
end

-- Lower-case letters and digits only, so "B a d" and "b.a.d" match "bad".
local function squash(text: string): string
	return (string.gsub(string.lower(text), "[^%w]", ""))
end

function CustomName.blocked(name: string, list: { string }): boolean
	local plain = squash(name)
	for _, entry in list do
		local word = squash(entry)
		if word ~= "" and string.find(plain, word, 1, true) then
			return true
		end
	end
	return false
end

return table.freeze(CustomName)
