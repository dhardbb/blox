--!strict
-- Bug reports (D-090), the pure part: cleaning the text, the screen tag, the
-- rate limit, the storage keys (one per day and shard), the size cap per key
-- and the admins' list order. The server (server/BugReports) adds the text
-- filter and the DataStore around these.

local Test = require("@testlib/Test")
local BugReport = require("@net/BugReport")
local Config = require("@sim/Config")
local Schemas = require("@net/Schemas")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local DAY = 86400

local function record(at: number, userId: number, text: string?): BugReport.Record
	return {
		at = at,
		userId = userId,
		version = "0.17.0",
		screen = "Lobby",
		matchId = nil,
		text = text or `report at {at}`,
	}
end

describe("BugReport.clean: the text", function()
	it("trims, folds runs of spaces and keeps single line breaks", function()
		local text = BugReport.clean("  The map  froze\n\n\n\nafter week 3  ", C)
		expect(text):toBe("The map froze\n\nafter week 3")
	end)

	it("turns down text that is too short, too long or not text", function()
		local short, why = BugReport.clean("  hi ", C)
		expect(short):toBe(nil)
		expect(why):toBe("BugTooShort")
		local long, why2 = BugReport.clean(string.rep("a", C.BUG_REPORT_MAX_CHARS + 1), C)
		expect(long):toBe(nil)
		expect(why2):toBe("BugTooLong")
		local bad, why3 = BugReport.clean(42 :: any, C)
		expect(bad):toBe(nil)
		expect(why3):toBe("BugTooShort")
	end)

	it("counts characters, not bytes, and drops control characters", function()
		local accents = string.rep("é", C.BUG_REPORT_MAX_CHARS)
		expect(BugReport.clean(accents, C)):toBe(accents)
		expect(BugReport.clean("Tap\0ped Play\7 twice", C)):toBe("Tapped Play twice")
		expect(BugReport.clean("bad \255\254 bytes here", C)):toBe(nil)
	end)
end)

describe("BugReport.screen: the screen tag", function()
	it("keeps a short word and replaces anything else", function()
		expect(BugReport.screen("Campaign")):toBe("Campaign")
		expect(BugReport.screen("Lobby/Queue")):toBe("Unknown")
		expect(BugReport.screen(string.rep("A", BugReport.MAX_SCREEN + 1))):toBe("Unknown")
		expect(BugReport.screen(nil)):toBe("Unknown")
	end)
end)

describe("BugReport.allowed: the rate limit", function()
	it("waits BUG_REPORT_WAIT between reports", function()
		local t = 1000000
		expect(BugReport.allowed({}, t, C)):toBe(true)
		local ok, why = BugReport.allowed({ t }, t + C.BUG_REPORT_WAIT - 1, C)
		expect(ok):toBe(false)
		expect(why):toBe("BugTooSoon")
		expect(BugReport.allowed({ t }, t + C.BUG_REPORT_WAIT, C)):toBe(true)
	end)

	it("allows BUG_REPORTS_PER_DAY in any day, then again a day later", function()
		local t = 1000000
		local times: { number } = {}
		for k = 1, C.BUG_REPORTS_PER_DAY do
			table.insert(times, t + (k - 1) * C.BUG_REPORT_WAIT)
		end
		local last = times[#times]
		local ok, why = BugReport.allowed(times, last + C.BUG_REPORT_WAIT, C)
		expect(ok):toBe(false)
		expect(why):toBe("BugLimit")
		expect(BugReport.allowed(times, t + DAY, C)):toBe(true)
	end)

	it("keeps only the times that still count", function()
		local t = 1000000
		local kept = BugReport.recent({ t - DAY - 1, t - 10, t }, t, C)
		expect(#kept):toBe(2)
	end)
end)

describe("BugReport keys: one per day and shard", function()
	it("puts a player's reports in their own shard of the day", function()
		local t = 20000 * DAY + 5
		expect(BugReport.key(t, 7, C)):toBe(`Day_20000_{7 % C.BUG_REPORT_SHARDS + 1}`)
		expect(BugReport.key(t + DAY, 7, C)):toBe(`Day_20001_{7 % C.BUG_REPORT_SHARDS + 1}`)
	end)

	it("lists the last BUG_REPORT_LIST_DAYS days, newest first, every shard", function()
		local keys = BugReport.keys(20000 * DAY, C)
		expect(#keys):toBe(C.BUG_REPORT_LIST_DAYS * C.BUG_REPORT_SHARDS)
		expect(keys[1]):toBe("Day_20000_1")
		expect(keys[#keys]):toBe(`Day_{20000 - C.BUG_REPORT_LIST_DAYS + 1}_{C.BUG_REPORT_SHARDS}`)
	end)
end)

describe("BugReport.append: a key stays small", function()
	it("adds a report and drops the oldest past BUG_REPORTS_PER_KEY", function()
		local list: { BugReport.Record } = {}
		for k = 1, C.BUG_REPORTS_PER_KEY + 3 do
			list = BugReport.append(list, record(k, 1), C)
		end
		expect(#list):toBe(C.BUG_REPORTS_PER_KEY)
		expect(list[1].at):toBe(4)
		expect(list[#list].at):toBe(C.BUG_REPORTS_PER_KEY + 3)
	end)

	it("treats a damaged stored value as empty and skips bad entries", function()
		expect(#BugReport.append("junk" :: any, record(1, 1), C)):toBe(1)
		local mixed = BugReport.append({ { at = "x" } :: any, record(2, 1) }, record(3, 1), C)
		expect(#mixed):toBe(2)
	end)

	it("stays well under the DataStore's 4 MB value limit when full", function()
		local list: { BugReport.Record } = {}
		local long = string.rep("é", C.BUG_REPORT_MAX_CHARS)
		for k = 1, C.BUG_REPORTS_PER_KEY do
			local r = record(k, 123456789012, long)
			r.matchId = string.rep("m", 40)
			list = BugReport.append(list, r, C)
		end
		local size = 0
		for _, r in list do
			size += #r.text + #r.version + #r.screen + #(r.matchId or "") + 64
		end
		expect(size < 4 * 1024 * 1024 / 10):toBe(true)
	end)
end)

describe("BugReport.newest: the admins' list", function()
	it("merges keys newest first and caps the list", function()
		local a = { record(5, 1), record(9, 2) }
		local b = { record(7, 3) }
		local list = BugReport.newest({ a, b, "junk" :: any }, 2)
		expect(#list):toBe(2)
		expect(list[1].at):toBe(9)
		expect(list[2].at):toBe(7)
	end)
end)

describe("Schemas: BugReport and BugList", function()
	it("accepts a report longer than other strings, up to the byte cap", function()
		local text = string.rep("é", C.BUG_REPORT_MAX_CHARS)
		local ok, _, request = Schemas.request({ op = "BugReport", text = text, screen = "Lobby" })
		expect(ok):toBe(true)
		expect((request :: any).text):toBe(text)
		expect((request :: any).screen):toBe("Lobby")
	end)

	it("turns down a report that is not text or far too long", function()
		expect((Schemas.request({ op = "BugReport", text = 5 }))):toBe(false)
		expect((Schemas.request({ op = "BugReport", text = string.rep("a", BugReport.MAX_BYTES + 1) }))):toBe(
			false
		)
		expect((Schemas.request({ op = "BugReport", text = "fine", screen = {} }))):toBe(false)
	end)

	it("knows BugList (no fields)", function()
		expect((Schemas.request({ op = "BugList" }))):toBe(true)
	end)
end)
