--!strict
-- End to end: bug reports (D-090). The real MatchService and server/BugReports
-- on the fake Roblox engine: a report is filtered by TextService, stored in its
-- day's shard with the version, screen and match id, rate-limited, never
-- stored when the filter fails, and only admins can list them.

local process = require("@lune/process")

local Test = require("@testlib/Test")
local BugReport = require("@net/BugReport")
local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Version = require("@shared/Version")
local Support = require("./Support")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

-- Every stored report, in key order.
local function stored(rig: Support.Rig): { any }
	local out = {}
	for _, list in rig.world.data.stores[BugReport.STORE] or {} do
		for _, record in list do
			table.insert(out, record)
		end
	end
	return out
end

local function storeOf(rig: Support.Rig, peer: FakeRoblox.Peer): any
	return peer.modules[`{rig.world.root}/src/client/Store.luau`]
end

-- The newest message the client was told (a toast), or "".
local function lastSaid(rig: Support.Rig, peer: FakeRoblox.Peer): string
	local store = storeOf(rig, peer)
	if store == nil then
		return ""
	end
	local messages = store.get().messages
	local last = messages[#messages]
	return if last then tostring(last.text) else ""
end

describe("e2e: bug reports", function()
	it("filters and stores a report with the version, screen and match id", function()
		local rig = Support.new(process.cwd, 31)
		rig.world.text.hidden = { "zorp" }
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 2)
		Support.fire(rig, p1, { op = "BugReport", text = "  The map froze, zorp!  ", screen = "Campaign" })
		Support.run(rig, 2)
		local list = stored(rig)
		check(#list == 1, `{#list} reports stored`)
		local r = list[1]
		expect(r.text):toBe("The map froze, ####!")
		expect(r.screen):toBe("Campaign")
		expect(r.version):toBe(Version.VERSION)
		expect(r.userId):toBe(p1.player.UserId)
		expect(r.matchId):toBe(nil)
		check(rig.world.text.calls >= 1, "the text filter was never called")
		check(string.find(lastSaid(rig, p1), "Thanks", 1, true) ~= nil, `told: {lastSaid(rig, p1)}`)
	end)

	it("rate-limits a player and never stores a report the filter could not check", function()
		local rig = Support.new(process.cwd, 32)
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 2)
		rig.world.text.failures = 1
		Support.fire(rig, p1, { op = "BugReport", text = "Rematch button did nothing", screen = "Results" })
		Support.run(rig, 2)
		expect(#stored(rig)):toBe(0)
		-- The failed try does not count: the next one goes through at once.
		Support.fire(rig, p1, { op = "BugReport", text = "Rematch button did nothing", screen = "Results" })
		Support.run(rig, 2)
		expect(#stored(rig)):toBe(1)
		-- Too soon after it.
		Support.fire(rig, p1, { op = "BugReport", text = "Another thing broke here", screen = "Lobby" })
		Support.run(rig, 2)
		expect(#stored(rig)):toBe(1)
		Support.run(rig, C.BUG_REPORT_WAIT)
		Support.fire(rig, p1, { op = "BugReport", text = "Another thing broke here", screen = "Lobby" })
		Support.run(rig, 2)
		expect(#stored(rig)):toBe(2)
		-- Too short, and a screen tag that is not a word.
		Support.run(rig, C.BUG_REPORT_WAIT)
		Support.fire(rig, p1, { op = "BugReport", text = "hi", screen = "Lobby" })
		Support.fire(rig, p1, { op = "BugReport", text = "The timer froze at 0:03", screen = "../x" })
		Support.run(rig, 2)
		local list = stored(rig)
		expect(#list):toBe(3)
		expect(list[3].screen):toBe("Unknown")
	end)

	it("lists reports for admins only", function()
		local rig = Support.new(process.cwd, 33)
		FakeRoblox.setModuleField(rig.world, "src/server/Admins.luau", "userIds", { 2 })
		local p1 = Support.join(rig, "Player1")
		local admin = Support.join(rig, "Admin2")
		Support.run(rig, 2)
		Support.fire(rig, p1, { op = "BugReport", text = "The music never stops", screen = "Lobby" })
		Support.run(rig, 2)
		Support.fire(rig, p1, { op = "BugList" })
		Support.run(rig, 2)
		local mine = storeOf(rig, p1)
		if mine then
			expect(mine.get().bugs):toBe(nil)
		end
		Support.fire(rig, admin, { op = "BugList" })
		Support.run(rig, 3)
		local store = storeOf(rig, admin)
		check(store ~= nil, "the admin's Store is not loaded")
		local board = store.get().bugs
		check(board ~= nil and board.ok, "the admin got no bug list")
		expect(#board.entries):toBe(1)
		expect(board.entries[1].text):toBe("The music never stops")
		expect(board.entries[1].userId):toBe(tostring(p1.player.UserId))
		expect(board.entries[1].owner):toBe("Player1")
	end)
end)
