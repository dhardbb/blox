--!strict
-- Custom candidate names (the Name Pass, docs/DESIGN.md D-063), the pure part:
-- the character rules, the length limit, folding for the blocklist and the
-- blocklist match, each a small function of its own so the server and the
-- specs share them. The text filter (TextService), the blocklists themselves
-- (server/NameBlocklist, the reviewed DataStore list) and who may use names
-- (server/NameEligibility) are server-only.
--
--   CustomName.normalize(text, config) -> (name?, reason?)
--     Trims, collapses every run of whitespace to one space (a ’ becomes '),
--     then allows only letters (A-Z, a-z and the accented Latin letters
--     U+00C0-U+017F), spaces, hyphens, apostrophes and periods: no digits
--     (phone numbers, ages, dates, addresses), emoji, symbols, "@", "/", ":",
--     zero-width or combining marks. Also turned down: a period followed by two
--     letters (a domain such as ".com"; "J.R." is fine), fewer than two letters,
--     the same character three times in a row, and more than NAME_MAX_LENGTH
--     characters. Never throws.
--   CustomName.fitsLength(name, config) -> boolean   at most NAME_MAX_LENGTH characters
--   CustomName.fold(text) -> string
--     what a blocklist entry and a name are compared as: lower case, accents
--     dropped, look-alikes folded (0->o, 1/l/|/!->i, 3->e, 4/@->a, 5/$->s,
--     7->t, 8->b, 9->g, rn->m, vv->w), only the letters a-z kept
--   CustomName.blocked(name, entries, config) -> boolean
--     an entry "word" matches when the folded name contains it, or contains
--     something within NAME_SIMILAR_DISTANCE edits of it (entries of at least
--     NAME_SIMILAR_MIN_LETTERS letters; shorter ones must match exactly); an
--     entry "=word" or "=two words" matches only whole words of the name (or
--     the whole name), exactly (after folding), for short or common words and
--     surnames whose near misses are ordinary names ("you", "bush", "farage"
--     would catch "garage")
--   CustomName.wasFiltered(name, filtered) -> boolean
--     the filter changed the text or hid part of it
--   CustomName.Reason   the reason codes a name is turned down with

local ConfigModule = require("../Sim/Config")

type Config = ConfigModule.Config

local CustomName = {}

CustomName.Reason = table.freeze({
	NoNamePass = "NoNamePass", -- the pass is not set up, or the player does not own it
	NotEligible = "NameNotEligible", -- not eligible (Roblox does not let them chat)
	BadText = "NameBadText", -- a character outside the rules, or a domain
	Empty = "NameEmpty", -- nothing left after trimming
	TooShort = "NameTooShort", -- fewer than two letters
	Repeats = "NameRepeats", -- the same character three times in a row
	TooLong = "NameTooLong", -- over NAME_MAX_LENGTH characters
	Filtered = "NameFiltered", -- Roblox's filter or a blocklist turned it down
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

local function isAsciiLetter(c: number): boolean
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
end

-- A letter the rules allow: ASCII, Latin-1 letters (not × or ÷) and Latin Extended-A.
local function isLetter(c: number): boolean
	return isAsciiLetter(c) or (c >= 0xC0 and c <= 0x17F and c ~= 0xD7 and c ~= 0xF7)
end

local PUNCTUATION: { [number]: boolean } = { [32] = true, [45] = true, [39] = true, [46] = true } -- space - ' .

-- Accented Latin letters (U+00C0-U+017F) to their base letter, lower case.
local BASE: { [number]: string } = {}
do
	local groups: { [string]: { number } } = {
		a = {
			0xC0,
			0xC1,
			0xC2,
			0xC3,
			0xC4,
			0xC5,
			0xE0,
			0xE1,
			0xE2,
			0xE3,
			0xE4,
			0xE5,
			0x100,
			0x101,
			0x102,
			0x103,
			0x104,
			0x105,
		},
		c = { 0xC7, 0xE7, 0x106, 0x107, 0x108, 0x109, 0x10A, 0x10B, 0x10C, 0x10D },
		d = { 0xD0, 0xF0, 0x10E, 0x10F, 0x110, 0x111 },
		e = {
			0xC8,
			0xC9,
			0xCA,
			0xCB,
			0xE8,
			0xE9,
			0xEA,
			0xEB,
			0x112,
			0x113,
			0x114,
			0x115,
			0x116,
			0x117,
			0x118,
			0x119,
			0x11A,
			0x11B,
		},
		g = { 0x11C, 0x11D, 0x11E, 0x11F, 0x120, 0x121, 0x122, 0x123 },
		h = { 0x124, 0x125, 0x126, 0x127 },
		i = {
			0xCC,
			0xCD,
			0xCE,
			0xCF,
			0xEC,
			0xED,
			0xEE,
			0xEF,
			0x128,
			0x129,
			0x12A,
			0x12B,
			0x12C,
			0x12D,
			0x12E,
			0x12F,
			0x130,
			0x131,
		},
		j = { 0x134, 0x135 },
		k = { 0x136, 0x137, 0x138 },
		l = { 0x139, 0x13A, 0x13B, 0x13C, 0x13D, 0x13E, 0x13F, 0x140, 0x141, 0x142 },
		n = { 0xD1, 0xF1, 0x143, 0x144, 0x145, 0x146, 0x147, 0x148, 0x149, 0x14A, 0x14B },
		o = {
			0xD2,
			0xD3,
			0xD4,
			0xD5,
			0xD6,
			0xD8,
			0xF2,
			0xF3,
			0xF4,
			0xF5,
			0xF6,
			0xF8,
			0x14C,
			0x14D,
			0x14E,
			0x14F,
			0x150,
			0x151,
		},
		r = { 0x154, 0x155, 0x156, 0x157, 0x158, 0x159 },
		s = { 0xDF, 0x15A, 0x15B, 0x15C, 0x15D, 0x15E, 0x15F, 0x160, 0x161, 0x17F },
		t = { 0xDE, 0xFE, 0x162, 0x163, 0x164, 0x165, 0x166, 0x167 },
		u = {
			0xD9,
			0xDA,
			0xDB,
			0xDC,
			0xF9,
			0xFA,
			0xFB,
			0xFC,
			0x168,
			0x169,
			0x16A,
			0x16B,
			0x16C,
			0x16D,
			0x16E,
			0x16F,
			0x170,
			0x171,
			0x172,
			0x173,
		},
		w = { 0x174, 0x175 },
		y = { 0xDD, 0xFD, 0xFF, 0x176, 0x177, 0x178 },
		z = { 0x179, 0x17A, 0x17B, 0x17C, 0x17D, 0x17E },
	}
	for base, codes in groups do
		for _, code in codes do
			BASE[code] = base
		end
	end
	BASE[0xC6] = "ae"
	BASE[0xE6] = "ae"
	BASE[0x152] = "oe"
	BASE[0x153] = "oe"
	BASE[0x132] = "ij"
	BASE[0x133] = "ij"
end

-- Look-alikes, after lower-casing: digits and symbols that stand in for letters,
-- and l (which looks like I). Applied to names and entries alike.
local LOOKALIKE: { [string]: string } = {
	["0"] = "o",
	["1"] = "i",
	["l"] = "i",
	["|"] = "i",
	["!"] = "i",
	["3"] = "e",
	["4"] = "a",
	["@"] = "a",
	["5"] = "s",
	["$"] = "s",
	["7"] = "t",
	["8"] = "b",
	["9"] = "g",
}

function CustomName.fold(text: string): string
	local out = table.create(#text)
	local ok = pcall(function()
		for _, c in utf8.codes(text) do
			local base = BASE[c]
			if base then
				table.insert(out, base)
			elseif c < 128 then
				local ch = string.lower(string.char(c))
				table.insert(out, LOOKALIKE[ch] or ch)
			end
		end
	end)
	if not ok then
		return ""
	end
	local folded = table.concat(out)
	folded = string.gsub(folded, "[^a-z]", "")
	folded = string.gsub(folded, "rn", "m")
	folded = string.gsub(folded, "vv", "w")
	return folded
end

function CustomName.normalize(text: any, config: Config): (string?, string?)
	if type(text) ~= "string" or length(text) == nil then
		return nil, CustomName.Reason.BadText
	end
	local spaced = string.gsub(text, "\u{2019}", "'")
	spaced = string.gsub(spaced, "%s+", " ")
	local trimmed = string.match(spaced, "^ *(.-) *$") or ""
	if trimmed == "" then
		return nil, CustomName.Reason.Empty
	end
	local letters = 0
	local last: number? = nil
	local run = 0
	local afterPeriod = -1 -- letters since the last period, -1 = none yet
	for _, c in utf8.codes(trimmed) do
		local letter = isLetter(c)
		if not letter and not PUNCTUATION[c] then
			return nil, CustomName.Reason.BadText
		end
		if letter then
			letters += 1
			if afterPeriod >= 0 then
				afterPeriod += 1
				if afterPeriod >= 2 then
					return nil, CustomName.Reason.BadText -- ".com", "x.gg": a domain
				end
			end
		else
			afterPeriod = if c == 46 then 0 else -1
		end
		-- The same character (any case) three times in a row.
		local key = if isAsciiLetter(c) then string.byte(string.lower(string.char(c))) else c
		if key == last then
			run += 1
			if run >= 3 then
				return nil, CustomName.Reason.Repeats
			end
		else
			last, run = key, 1
		end
	end
	if letters < 2 then
		return nil, CustomName.Reason.TooShort
	end
	if not CustomName.fitsLength(trimmed, config) then
		return nil, CustomName.Reason.TooLong
	end
	return trimmed, nil
end

function CustomName.wasFiltered(name: string, filtered: any): boolean
	return type(filtered) ~= "string" or filtered ~= name or string.find(filtered, "#", 1, true) ~= nil
end

-- The fewest edits (insert, delete, change one letter) that turn `needle` into
-- some part of `hay` (approximate substring match).
local function partDistance(needle: string, hay: string): number
	local n, m = #needle, #hay
	local prev = table.create(m + 1, 0) -- row 0: a match may start anywhere
	for i = 1, n do
		local row = table.create(m + 1, 0)
		row[1] = i
		local a = string.byte(needle, i)
		for j = 1, m do
			local cost = if a == string.byte(hay, j) then 0 else 1
			row[j + 1] = math.min(prev[j] + cost, prev[j + 1] + 1, row[j] + 1)
		end
		prev = row
	end
	local best = n
	for j = 1, m + 1 do
		best = math.min(best, prev[j])
	end
	return best
end

-- How many edits an entry of `letters` letters tolerates.
local function tolerance(letters: number, config: Config): number
	return if letters >= config.NAME_SIMILAR_MIN_LETTERS then config.NAME_SIMILAR_DISTANCE else 0
end

-- The words of a name, each folded (empty ones dropped).
local function words(name: string): { string }
	local out = {}
	for word in string.gmatch(name, "[^%s%-'%.]+") do
		local folded = CustomName.fold(word)
		if folded ~= "" then
			table.insert(out, folded)
		end
	end
	return out
end

function CustomName.blocked(name: string, entries: { string }, config: Config): boolean
	local plain = CustomName.fold(name)
	local tokens: { string }? = nil
	for _, entry in entries do
		if string.sub(entry, 1, 1) == "=" then
			-- Whole words: the entry's words appear in a row, or make up the whole name.
			local want = words(string.sub(entry, 2))
			if #want == 0 then
				continue
			end
			if plain == table.concat(want) then
				return true
			end
			local have = tokens or words(name)
			tokens = have
			for start = 1, #have - #want + 1 do
				local all = true
				for k, word in want do
					if have[start + k - 1] ~= word then
						all = false
						break
					end
				end
				if all then
					return true
				end
			end
		else
			local word = CustomName.fold(entry)
			if word == "" then
				continue
			end
			if string.find(plain, word, 1, true) then
				return true
			end
			local allowed = tolerance(#word, config)
			if allowed > 0 and partDistance(word, plain) <= allowed then
				return true
			end
		end
	end
	return false
end

return table.freeze(CustomName)
