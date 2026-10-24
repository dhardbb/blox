--!strict
-- Reporting custom names and the owners' review (docs/DESIGN.md D-069), end to
-- end on the fake engine with the real server and clients: a report hides the
-- name from the reporter at once and for later matches and queues it for
-- review (NameReports_v1); admins (and only admins) keep or remove it; a
-- removed name is cleared, blocked with names like it (NameBlocklist_v1,
-- MessagingService), and a saved name that matches the reviewed blocklist is
-- cleared when its owner joins.

local Test = require("@testlib/Test")
local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")

local describe, it, expect = Test.describe, Test.it, Test.expect

local PASS = 5551234
local PROFILES = "PlayerData_v1"
local REPORTS = "NameReports_v1"
local BLOCKLIST = "NameBlocklist_v1"

local check = Rig.check

type Trio = {
	world: FakeRoblox.World,
	a: FakeRoblox.Peer, -- named "Captain Zed"
	b: FakeRoblox.Peer, -- sees A's name
	r: FakeRoblox.Peer?, -- an admin in the lobby (when asked for)
	ids: { number }, -- user ids of a, b, r
}

-- A and B, both eligible, queue into one match; A owns the pass and is named.
-- With `reviewer`, a third player R joins as an admin and stays in the lobby.
local function trio(seed: number, reviewer: boolean?, saved: any?): Trio
	local world = Rig.newWorld(seed)
	FakeRoblox.setNamePass(world, PASS)
	local first = world.nextUserId
	local ids = { first, first + 1, first + 2 }
	for _, id in ids do
		FakeRoblox.setCanChat(world, id, true)
	end
	FakeRoblox.setOwnsPass(world, first, PASS, true)
	FakeRoblox.setModuleField(world, "src/server/Admins.luau", "userIds", { first + 2 })
	world.data.stores[PROFILES] = world.data.stores[PROFILES] or {}
	world.data.stores[PROFILES][`Player_{first}`] = { data = saved or { customName = "Captain Zed" } }
	local a = FakeRoblox.join(world, "A")
	local b = FakeRoblox.join(world, "B")
	local r = if reviewer then FakeRoblox.join(world, "R") else nil
	FakeRoblox.run(world, 12)
	FakeRoblox.fire(world, a, { op = "Queue" })
	FakeRoblox.fire(world, b, { op = "Queue" })
	FakeRoblox.run(world, 2)
	check(Rig.payloadOf(world, a) ~= nil and Rig.payloadOf(world, b) ~= nil, "the match did not start")
	return { world = world, a = a, b = b, r = r, ids = ids }
end

-- What `viewer` sees as A's custom name.
local function nameOfA(t: Trio, viewer: FakeRoblox.Peer): string?
	local seatA = Rig.payloadOf(t.world, t.a).you
	return Rig.payloadOf(t.world, viewer).view.players[seatA].customName
end

local function rejected(world: FakeRoblox.World, peer: FakeRoblox.Peer, reason: string): boolean
	for _, message in Rig.storeOf(world, peer).get().messages do
		if message.rejected and message.reason == reason then
			return true
		end
	end
	return false
end

local function said(world: FakeRoblox.World, peer: FakeRoblox.Peer, text: string): boolean
	for _, message in Rig.storeOf(world, peer).get().messages do
		if string.find(message.text, text, 1, true) then
			return true
		end
	end
	return false
end

local function fire(world: FakeRoblox.World, peer: FakeRoblox.Peer, request: any, seconds: number?)
	FakeRoblox.fire(world, peer, request)
	FakeRoblox.run(world, seconds or 1)
end

local function queueEntry(t: Trio): any
	local record = t.world.data.stores[REPORTS] and t.world.data.stores[REPORTS].Queue
	return if record then record[tostring(t.ids[1])] else nil
end

describe("Reporting a custom name (D-069)", function()
	it("hides it from the reporter at once, queues it, and A keeps it", function()
		local t = trio(1)
		expect(nameOfA(t, t.b)):toBe("Captain Zed")
		fire(t.world, t.b, { op = "ReportName", userId = tostring(t.ids[1]) })
		expect(nameOfA(t, t.b)):toBe(nil)
		expect(nameOfA(t, t.a)):toBe("Captain Zed")
		check(said(t.world, t.b, "Thanks for the report"), "no thanks notice")
		local entry = queueEntry(t)
		check(entry ~= nil, "the report was not queued")
		expect(entry.name):toBe("Captain Zed")
		check(entry.reporters[tostring(t.ids[2])] ~= nil, "the reporter is not recorded")
		local profile = t.world.data.stores[PROFILES][`Player_{t.ids[2]}`].data
		expect(profile.hiddenNames[tostring(t.ids[1])]):toBe("Captain Zed")
		Rig.noErrors(t.world)
	end)

	it("turns down yourself, a name you were not shown, bad ids and a second report too soon", function()
		local t = trio(2)
		fire(t.world, t.a, { op = "ReportName", userId = tostring(t.ids[1]) })
		expect(rejected(t.world, t.a, "ReportSelf")):toBe(true)
		fire(t.world, t.a, { op = "ReportName", userId = "424242" })
		expect(rejected(t.world, t.a, "ReportNoName")):toBe(true)
		fire(t.world, t.a, { op = "ReportName", userId = "bot" })
		expect(rejected(t.world, t.a, "BadShape")):toBe(true)
		-- B reports, A picks a new name in Select, B reports again at once.
		fire(t.world, t.b, { op = "ReportName", userId = tostring(t.ids[1]) })
		fire(t.world, t.a, { op = "SetName", name = "Big Wave" })
		expect(nameOfA(t, t.b)):toBe("Big Wave")
		fire(t.world, t.b, { op = "ReportName", userId = tostring(t.ids[1]) }, 0.5)
		expect(rejected(t.world, t.b, "ReportTooSoon")):toBe(true)
		expect(nameOfA(t, t.b)):toBe("Big Wave")
		FakeRoblox.run(t.world, 10)
		fire(t.world, t.b, { op = "ReportName", userId = tostring(t.ids[1]) })
		expect(nameOfA(t, t.b)):toBe(nil)
		expect(queueEntry(t).name):toBe("Big Wave")
		Rig.noErrors(t.world)
	end)

	it("keeps hiding it in the next match against that player", function()
		local t = trio(3)
		fire(t.world, t.b, { op = "ReportName", userId = tostring(t.ids[1]) })
		local payload = Rig.payloadOf(t.world, t.b)
		fire(t.world, t.b, { op = "Forfeit", matchId = payload.matchId }, 3)
		FakeRoblox.run(t.world, 5)
		fire(t.world, t.a, { op = "Queue" })
		fire(t.world, t.b, { op = "Queue" }, 3)
		check(Rig.payloadOf(t.world, t.a).matchId ~= payload.matchId, "no second match")
		expect(nameOfA(t, t.a)):toBe("Captain Zed")
		expect(nameOfA(t, t.b)):toBe(nil)
		Rig.noErrors(t.world)
	end)

	it("the Help sheet offers Report and the confirmation sends it", function()
		local t = trio(4)
		Rig.tap(t.world, t.b, "Select", "HelpButton")
		local report = Rig.need(t.b, "HelpOverlay", "HelpReport")
		check(Rig.shown(report, "HelpOverlay"), "no Report button in Help")
		expect(tostring(report.Text)):toBe('Report "Captain Zed"')
		Rig.tap(t.world, t.b, "HelpOverlay", "HelpReport")
		local overlay = FakeRoblox.find(t.b, "ReportOverlay")
		check(overlay.Visible == true, "the confirmation did not open")
		check(
			string.find(Rig.textOf(t.b, "ReportOverlay", "ReportRoblox"), "Roblox's own Report", 1, true)
				~= nil,
			"no pointer to Roblox's own Report"
		)
		Rig.tap(t.world, t.b, "ReportOverlay", "ReportConfirm", 1)
		expect(nameOfA(t, t.b)):toBe(nil)
		-- A player who sees no custom name gets no Report button.
		Rig.tap(t.world, t.b, "Select", "HelpButton")
		expect(Rig.shown(Rig.need(t.b, "HelpOverlay", "HelpReport"), "HelpOverlay")):toBe(false)
		Rig.noErrors(t.world)
	end)
end)

describe("Reviewing reported names (D-069)", function()
	local function board(t: Trio): any
		return Rig.storeOf(t.world, t.r :: FakeRoblox.Peer).get().review
	end

	it("is for admins only: the button, and every request on the server", function()
		local t = trio(5, true)
		local r = t.r :: FakeRoblox.Peer
		check(Rig.storeOf(t.world, r).get().lobby.review ~= nil, "no review count for the admin")
		check(Rig.shown(Rig.need(r, "Lobby", "ReviewButton"), "Lobby"), "no Review button for the admin")
		expect(Rig.storeOf(t.world, t.b).get().lobby.review):toBe(nil)
		for _, op in { "ReviewList", "ReviewKeep", "ReviewRemove" } do
			fire(t.world, t.b, { op = op, userId = tostring(t.ids[1]) })
			check(rejected(t.world, t.b, "NotAdmin"), `{op} from a non-admin was not turned down`)
		end
		check(queueEntry(t) == nil, "a non-admin changed something")
		Rig.noErrors(t.world)
	end)

	it("lists a report, and Keep dismisses it while the name stays", function()
		local t = trio(6, true)
		local r = t.r :: FakeRoblox.Peer
		fire(t.world, t.b, { op = "ReportName", userId = tostring(t.ids[1]) })
		fire(t.world, r, { op = "ReviewList" })
		local list = board(t)
		check(list ~= nil and list.ok, "no review list")
		expect(#list.entries):toBe(1)
		expect(list.entries[1].name):toBe("Captain Zed")
		expect(list.entries[1].owner):toBe("A")
		expect(list.entries[1].count):toBe(1)
		fire(t.world, r, { op = "ReviewKeep", userId = tostring(t.ids[1]) })
		expect(#board(t).entries):toBe(0)
		expect(queueEntry(t)):toBe(nil)
		expect(nameOfA(t, t.a)):toBe("Captain Zed")
		Rig.noErrors(t.world)
	end)

	it("Remove clears the name, tells its owner, and blocks it and names like it", function()
		local t = trio(7, true)
		local r = t.r :: FakeRoblox.Peer
		fire(t.world, t.b, { op = "ReportName", userId = tostring(t.ids[1]) })
		-- The panel, as the admin sees it.
		Rig.tap(t.world, r, "Lobby", "ReviewButton", 1)
		check(Rig.findIn(r, "Lobby", `ReviewRow_{t.ids[1]}`) ~= nil, "no row for the reported name")
		Rig.tap(t.world, r, "Lobby", "ReviewRemove", 2)
		expect(nameOfA(t, t.a)):toBe(nil)
		check(said(t.world, t.a, "Your custom name was removed"), "no notice to the owner")
		expect(t.world.data.stores[PROFILES][`Player_{t.ids[1]}`].data.customName):toBe(nil)
		local list = t.world.data.stores[BLOCKLIST].Entries
		check(list ~= nil and table.find(list, "captainzed") ~= nil, "not on the reviewed blocklist")
		check(
			#t.world.published >= 1 and t.world.published[1].data == "captainzed",
			"not sent to other servers"
		)
		expect(#board(t).entries):toBe(0)
		-- Blocked now: the name, a look-alike, and one letter off.
		for _, name in { "Captain Zed", "CAPTAIN  ZED", "Captain Zeb" } do
			fire(t.world, t.a, { op = "SetName", name = name })
			check(rejected(t.world, t.a, "NameFiltered"), `{name} was allowed`)
		end
		fire(t.world, t.a, { op = "SetName", name = "Big Wave" })
		expect(nameOfA(t, t.a)):toBe("Big Wave")
		Rig.noErrors(t.world)
	end)

	it("clears a saved name that matches the reviewed blocklist when its owner joins", function()
		local world = Rig.newWorld(8)
		FakeRoblox.setNamePass(world, PASS)
		local id = world.nextUserId
		FakeRoblox.setCanChat(world, id, true)
		FakeRoblox.setOwnsPass(world, id, PASS, true)
		-- Into the tables the server's stores already hold (the server opened them at start).
		world.data.stores[BLOCKLIST] = world.data.stores[BLOCKLIST] or {}
		world.data.stores[BLOCKLIST].Entries = { "captainzed" }
		world.data.stores[PROFILES] = world.data.stores[PROFILES] or {}
		world.data.stores[PROFILES][`Player_{id}`] = { data = { customName = "Captain Zeb" } }
		local peer = FakeRoblox.join(world, "A")
		FakeRoblox.run(world, 12)
		expect(world.data.stores[PROFILES][`Player_{id}`].data.customName):toBe(nil)
		check(said(world, peer, "Your custom name was removed"), "no notice")
		Rig.noErrors(world)
	end)
end)
