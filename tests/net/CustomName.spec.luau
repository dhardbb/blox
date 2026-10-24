--!strict
-- Custom candidate names (D-069), the pure part: the character rules, the
-- length limit, folding, the filter check, the blocklist match, the profile
-- field and Session's per-viewer names.

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local CustomName = require("@net/CustomName")
local Profile = require("@net/Profile")

local describe, it, expect = Test.describe, Test.it, Test.expect

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

local C = Config.defaults
local R = CustomName.Reason

describe("CustomName.normalize: the character rules", function()
	local function reason(text: any): string?
		local name, why = CustomName.normalize(text, C)
		expect(name):toBe(nil)
		return why
	end

	it("keeps fictional names, trimmed and with single spaces", function()
		for text, want in
			{
				["  Captain   Zed "] = "Captain Zed",
				["Big\tWave"] = "Big Wave",
				["Mary-Jo O'Neil"] = "Mary-Jo O'Neil",
				["Mary-Jo O\u{2019}Neil"] = "Mary-Jo O'Neil",
				["Dr. Zed"] = "Dr. Zed",
				["J.R. Hawk"] = "J.R. Hawk",
				["Zoë Brandt"] = "Zoë Brandt",
				["Łukasz Nowak"] = "Łukasz Nowak",
				["Ana"] = "Ana",
				["Lee"] = "Lee",
				["Trumpet Joe"] = "Trumpet Joe",
			}
		do
			expect(CustomName.normalize(text, C)):toBe(want)
		end
	end)

	it("turns down empty names", function()
		for _, text in { "", "   ", "\t \n" } do
			expect(reason(text)):toBe(R.Empty)
		end
	end)

	it("turns down digits, symbols, emoji, URLs, handles and invisible marks", function()
		for _, text in
			{
				42,
				true,
				{},
				"bad\0name",
				"a\27b",
				"Zed #1",
				"\255\254",
				"Agent 47",
				"555 1234",
				"Zed@home",
				"@zed",
				"zed.com",
				"Go to x.gg",
				"Zed/Zork",
				"Zed:Zork",
				"Zed_Zork",
				"Zed!",
				"Zed 😀",
				"Ze\u{200B}d",
				"Ze\u{0301}d",
				"Zed\u{FF21}",
				"Дмитрий",
				"Zed & Co",
			}
		do
			local why = reason(text)
			check(why == R.BadText, `{tostring(text)}: {why}`)
		end
	end)

	it("needs two letters, and no character three times in a row", function()
		expect(reason("Z")):toBe(R.TooShort)
		expect(reason("Z.")):toBe(R.TooShort)
		expect(reason("- ' -")):toBe(R.TooShort)
		expect(reason("Zeee")):toBe(R.Repeats)
		expect(reason("ZzZed")):toBe(R.Repeats)
		expect(reason("Zed...")):toBe(R.Repeats)
		expect(CustomName.normalize("Zee", C)):toBe("Zee")
	end)

	it("counts characters, not bytes, against the limit", function()
		expect(CustomName.normalize("Abcdefghijklmnop", C)):toBe("Abcdefghijklmnop")
		expect(reason("Abcdefghijklmnopq")):toBe(R.TooLong)
		-- 16 two-byte letters are 32 bytes and still fit.
		local accented = "éàéàéàéàéàéàéàéà"
		expect(CustomName.normalize(accented, C)):toBe(accented)
		-- Spaces trimmed off the ends do not count.
		expect(CustomName.normalize("  Abcdefghijklmnop  ", C)):toBe("Abcdefghijklmnop")
	end)
end)

describe("CustomName limits", function()
	it("fitsLength follows NAME_MAX_LENGTH (default 16)", function()
		expect(C.NAME_MAX_LENGTH):toBe(16)
		expect(CustomName.fitsLength("Sixteen chars ok", C)):toBe(true)
		expect(CustomName.fitsLength("Seventeen chars!!", C)):toBe(false)
		local short = Config.with(C, { NAME_MAX_LENGTH = 4 })
		expect(CustomName.fitsLength("Abcd", short)):toBe(true)
		expect(CustomName.fitsLength("Abcde", short)):toBe(false)
	end)
end)

describe("CustomName.fold", function()
	it("lower-cases, drops accents and punctuation, and folds look-alikes", function()
		expect(CustomName.fold("Captain Zed")):toBe("captainzed")
		expect(CustomName.fold("Zoë-Brandt")):toBe("zoebrandt")
		expect(CustomName.fold("R0B1OX")):toBe(CustomName.fold("roblox"))
		expect(CustomName.fold("Rob Lox")):toBe(CustomName.fold("roblox"))
		expect(CustomName.fold("$n@pch4t")):toBe(CustomName.fold("snapchat"))
		expect(CustomName.fold("TRUMP")):toBe("trump")
		expect(CustomName.fold("tvvitch")):toBe("twitch")
		expect(CustomName.fold("rnod")):toBe("mod")
		expect(CustomName.fold("\255")):toBe("")
	end)
end)

describe("CustomName filter and blocklist checks", function()
	it("wasFiltered: any change, any #, or no text at all", function()
		expect(CustomName.wasFiltered("Captain Zed", "Captain Zed")):toBe(false)
		expect(CustomName.wasFiltered("Captain Zed", "Captain ###")):toBe(true)
		expect(CustomName.wasFiltered("Captain Zed", "Captain")):toBe(true)
		expect(CustomName.wasFiltered("Captain Zed", nil)):toBe(true)
	end)

	it("blocked: contains, look-alikes and one-letter near misses of long entries", function()
		local list = { "roblox", "zork" }
		expect(CustomName.blocked("Captain Zed", list, C)):toBe(false)
		expect(CustomName.blocked("The ROBLOX", list, C)):toBe(true)
		expect(CustomName.blocked("R.o.b-l-o-x", list, C)):toBe(true)
		expect(CustomName.blocked("Robiox Fan", list, C)):toBe(true)
		expect(CustomName.blocked("Rablox", list, C)):toBe(true) -- one edit from a 6-letter entry
		expect(CustomName.blocked("Zorkus", list, C)):toBe(true) -- contains
		expect(CustomName.blocked("Zark", list, C)):toBe(false) -- 4 letters: exact only
		expect(CustomName.blocked("Anything", {}, C)):toBe(false)
		expect(CustomName.blocked("Anything", { "", "=" }, C)):toBe(false)
		expect(CustomName.blocked("Rablox", list, Config.with(C, { NAME_SIMILAR_DISTANCE = 0 }))):toBe(false)
	end)

	it("blocked: '=' entries match whole words only", function()
		local list = { "=you", "=bush", "=dm me", "=trump" }
		expect(CustomName.blocked("You", list, C)):toBe(true)
		expect(CustomName.blocked("Y.O.U", list, C)):toBe(true)
		expect(CustomName.blocked("Young Zed", list, C)):toBe(false)
		expect(CustomName.blocked("Mr Bush", list, C)):toBe(true)
		expect(CustomName.blocked("Bushnell", list, C)):toBe(false)
		expect(CustomName.blocked("Pls dm me", list, C)):toBe(true)
		expect(CustomName.blocked("Dm Zed", list, C)):toBe(false)
		expect(CustomName.blocked("Trumq Zed", list, C)):toBe(false) -- whole words match exactly
		expect(CustomName.blocked("Trumpet Joe", list, C)):toBe(false)
	end)
end)

describe("Profile.customName", function()
	it("is absent on a new profile and survives a load", function()
		expect(Profile.new().customName):toBe(nil)
		local saved = Profile.withCustomName(Profile.new(), "Captain Zed")
		expect(saved.customName):toBe("Captain Zed")
		expect(Profile.migrate(saved).customName):toBe("Captain Zed")
	end)

	it("drops a saved name that is not a valid name any more", function()
		for _, bad in { 7, "", "   ", "Zed #1", string.rep("x", C.NAME_MAX_LENGTH + 1) } do
			local raw: any = Profile.new()
			raw.customName = bad
			expect(Profile.migrate(raw).customName):toBe(nil)
		end
		local raw: any = Profile.new()
		raw.customName = "  Captain   Zed "
		expect(Profile.migrate(raw).customName):toBe("Captain Zed")
	end)

	it("withCustomName(nil) goes back to the candidate's own name", function()
		local named = Profile.withCustomName(Profile.new(), "Captain Zed")
		expect(Profile.withCustomName(named, nil).customName):toBe(nil)
		expect(named.customName):toBe("Captain Zed") -- the original is untouched
	end)
end)

describe("Session custom names (D-069)", function()
	local Session = require("@net/Session")
	local View = require("@sim/View")

	local function session(): any
		return Session.new(C, "m1", 7, {
			{
				id = "a",
				kind = "Human",
				seesNames = true,
				namePass = { id = 1, owned = true },
				customName = "Captain Zed",
			},
			{ id = "b", kind = "Human", namePass = { id = 1, owned = false } },
			{ id = "bot", kind = "Bot", candidate = "hale", customName = "Sneaky" } :: any,
		}, 0)
	end

	it("puts names only in the views of players who may see them", function()
		local s = session()
		expect(Session.payload(s, 1).view.players[1].customName):toBe("Captain Zed")
		expect(Session.payload(s, 2).view.players[1].customName):toBe(nil)
		expect(Session.payload(s, 1).view.players[3].customName):toBe(nil) -- a bot is never named
		expect(Session.payload(s, 1).naming.name):toBe("Captain Zed")
		expect(Session.payload(s, 2).naming.owned):toBe(false)
		expect(Session.payload(s, 3).naming):toBe(nil)
		-- View.build without names never carries one.
		expect(View.build(C, s.match, 1).players[1].customName):toBe(nil)
	end)

	it("shows another seat's name only as filtered for the viewer (showName)", function()
		local s = Session.new(C, "m2", 7, {
			{ id = "a", kind = "Human", seesNames = true, customName = "Captain Zed" },
			{ id = "b", kind = "Human", seesNames = true, namePass = { id = 1, owned = true } },
		}, 0)
		expect(Session.payload(s, 2).view.players[1].customName):toBe(nil) -- not shared yet
		Session.showName(s, 2, 1, "Captain Zed", "Captain Zed")
		expect(Session.payload(s, 2).view.players[1].customName):toBe("Captain Zed")
		Session.showName(s, 2, 1, "Old Name", nil) -- stale: ignored
		expect(Session.payload(s, 2).view.players[1].customName):toBe("Captain Zed")
		-- A's view of B follows B's new name only once it is shared.
		Session.setName(s, 2, "Big Wave")
		expect(Session.payload(s, 1).view.players[2].customName):toBe(nil)
		expect(Session.payload(s, 2).view.players[2].customName):toBe("Big Wave")
	end)

	it("setName needs Select, the pass and a human seat", function()
		local s = session()
		expect(Session.setName(s, 1, "Big Wave")):toBe(true)
		expect(Session.payload(s, 1).view.players[1].customName):toBe("Big Wave")
		local ok, reason = Session.setName(s, 2, "Nope")
		expect(ok):toBe(false)
		expect(reason):toBe(R.NoNamePass)
		expect((Session.setName(s, 3, "Bot"))):toBe(false)
		Session.setNamePass(s, 2, { id = 1, owned = true })
		expect(Session.setName(s, 2, "Now Mine")):toBe(true)
		expect(Session.setName(s, 1, nil)):toBe(true)
		expect(Session.payload(s, 1).view.players[1].customName):toBe(nil)
	end)
end)

describe("NameBlocklist (server-only, D-069)", function()
	local NameBlocklist = require("../../src/server/NameBlocklist")

	it("lets fictional names through", function()
		for _, name in
			{
				"Captain Zed",
				"Big Wave",
				"Mary-Jo O'Neil",
				"Trumpet Joe",
				"Dana Okafor",
				"Rex Calloway",
				"Priya Venkat",
				"Marcus Hale",
				"June Alvarado",
				"Tomas Reyes",
				"Helen Strand",
				"Walt Begay",
				"Melanie Frost",
				"Corbin Vale",
				"Mr Macaron",
				"Defender Dan",
				"Garage Band",
				"Young Gun",
				"Senator Zed",
				"President Wave",
				"Bushnell",
				"Modesta",
				"Abbott",
				"Tiernan",
			}
		do
			check(not CustomName.blocked(name, NameBlocklist, C), `{name} is blocked`)
		end
	end)

	it("stops real politicians, parties, slogans, Roblox staff, contact bait and the game's words", function()
		for _, name in
			{
				"Donald Trump",
				"Trump",
				"Senator Trump",
				"Joe Biden",
				"Obama Fan",
				"Kamala",
				"Keir Starmer",
				"Putin",
				"Zelensky",
				"MAGA",
				"Brexit Bob",
				"Labour",
				"Tory Boy",
				"Roblox Staff",
				"Rob lox",
				"Builderman",
				"Admin",
				"Mod",
				"Official Zed",
				"Discord Zed",
				"Snap",
				"Free Robux",
				"Dm me",
				"Add me",
				"YouTube Star",
				"You",
				"Rival",
				"Bot",
				"Tie",
				"Nobody",
			}
		do
			check(CustomName.blocked(name, NameBlocklist, C), `{name} is not blocked`)
		end
	end)
end)
