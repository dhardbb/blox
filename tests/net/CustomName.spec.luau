--!strict
-- Custom candidate names (D-063), the pure part: cleaning, the length limit,
-- the age rule, the filter check, the blocklist match and the profile field.

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local CustomName = require("@net/CustomName")
local Profile = require("@net/Profile")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local R = CustomName.Reason

describe("CustomName.normalize", function()
	it("trims and collapses spaces", function()
		expect(CustomName.normalize("  Captain   Zed ", C)):toBe("Captain Zed")
		expect(CustomName.normalize("Big\tWave", C)):toBe("Big Wave")
	end)

	it("turns down empty names", function()
		for _, text in { "", "   ", "\t \n" } do
			local name, reason = CustomName.normalize(text, C)
			expect(name):toBe(nil)
			expect(reason):toBe(R.Empty)
		end
	end)

	it("turns down what is not plain text", function()
		for _, text in { 42, true, {}, "bad\0name", "a\27b", "Zed #1", "\255\254" } do
			local name, reason = CustomName.normalize(text :: any, C)
			expect(name):toBe(nil)
			expect(reason):toBe(R.BadText)
		end
	end)

	it("counts characters, not bytes, against the limit", function()
		expect(CustomName.normalize(string.rep("a", C.NAME_MAX_LENGTH), C)):toBe(
			string.rep("a", C.NAME_MAX_LENGTH)
		)
		local name, reason = CustomName.normalize(string.rep("a", C.NAME_MAX_LENGTH + 1), C)
		expect(name):toBe(nil)
		expect(reason):toBe(R.TooLong)
		-- 16 two-byte letters are 32 bytes and still fit.
		local accented = string.rep("é", C.NAME_MAX_LENGTH)
		expect(CustomName.normalize(accented, C)):toBe(accented)
		-- Spaces trimmed off the ends do not count.
		expect(CustomName.normalize("  " .. string.rep("b", C.NAME_MAX_LENGTH) .. "  ", C)):toBe(
			string.rep("b", C.NAME_MAX_LENGTH)
		)
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

	it("eligibleAge needs a verified age of NAME_MIN_AGE (16) or more; unknown is no", function()
		expect(C.NAME_MIN_AGE):toBe(16)
		expect(CustomName.eligibleAge(nil, C)):toBe(false)
		expect(CustomName.eligibleAge(13, C)):toBe(false)
		expect(CustomName.eligibleAge(15, C)):toBe(false)
		expect(CustomName.eligibleAge(16, C)):toBe(true)
		expect(CustomName.eligibleAge(40, C)):toBe(true)
		expect(CustomName.eligibleAge(17, Config.with(C, { NAME_MIN_AGE = 18 }))):toBe(false)
	end)
end)

describe("CustomName filter and blocklist checks", function()
	it("wasFiltered: any change, any #, or no text at all", function()
		expect(CustomName.wasFiltered("Captain Zed", "Captain Zed")):toBe(false)
		expect(CustomName.wasFiltered("Captain Zed", "Captain ###")):toBe(true)
		expect(CustomName.wasFiltered("Captain Zed", "Captain")):toBe(true)
		expect(CustomName.wasFiltered("Captain Zed", nil)):toBe(true)
	end)

	it("blocked: an entry anywhere in the name, case and punctuation ignored", function()
		local list = { "Zork" }
		expect(CustomName.blocked("Captain Zed", list)):toBe(false)
		expect(CustomName.blocked("The ZORK", list)):toBe(true)
		expect(CustomName.blocked("z.o r-k", list)):toBe(true)
		expect(CustomName.blocked("Anything", {})):toBe(false)
		expect(CustomName.blocked("Anything", { "", "  " })):toBe(false)
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

describe("Session custom names (D-063)", function()
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
