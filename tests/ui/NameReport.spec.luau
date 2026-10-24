--!strict
-- Reporting custom names and the owners' review (docs/DESIGN.md D-069), end to
-- end on the fake engine with the real server and clients: a report hides the
-- name from the reporter at once and for later matches and queues it for
-- review (NameReports_v1, split over keys by setter, D-076); admins (and only
-- admins) keep or remove it, acting only on the name they saw; a removed name
-- is cleared, blocked as whole words (NameBlocklist_v1, MessagingService), and
-- a saved name that is exactly a removed one is cleared when its owner joins
-- (one that only contains it is not used, but stays saved).

local Test = require("@testlib/Test")
local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")

local describe, it, expect = Test.describe, Test.it, Test.expect

local PASS = 5551234
local PROFILES = "PlayerData_v1"
local REPORTS = "NameReports_v1"
local BLOCKLIST = "NameBlocklist_v1"
local SHARDS = 8 -- Config.NAME_REVIEW_SHARDS
local SAVE_WAIT = 16 -- seconds for DataService's batched save to land

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
	local key = `Queue_{t.ids[1] % SHARDS + 1}`
	local record = t.world.data.stores[REPORTS] and t.world.data.stores[REPORTS][key]
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
		FakeRoblox.run(t.world, SAVE_WAIT)
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

-- The custom name `peer` plays a practice match under.
local function practiceName(world: FakeRoblox.World, peer: FakeRoblox.Peer): string?
	Rig.tap(world, peer, "Lobby", "Practice", 1)
	local payload = Rig.payloadOf(world, peer)
	check(payload ~= nil, "the practice match did not start")
	return payload.view.players[payload.you].customName
end

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
			fire(t.world, t.b, { op = op, userId = tostring(t.ids[1]), name = "Captain Zed" })
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
		fire(t.world, r, { op = "ReviewKeep", userId = tostring(t.ids[1]), name = "Captain Zed" })
		expect(#board(t).entries):toBe(0)
		expect(queueEntry(t)):toBe(nil)
		expect(nameOfA(t, t.a)):toBe("Captain Zed")
		Rig.noErrors(t.world)
	end)

	it("Remove clears the name, tells its owner, and blocks it as whole words", function()
		local t = trio(7, true)
		local r = t.r :: FakeRoblox.Peer
		fire(t.world, t.b, { op = "ReportName", userId = tostring(t.ids[1]) })
		-- The panel, as the admin sees it.
		Rig.tap(t.world, r, "Lobby", "ReviewButton", 1)
		check(Rig.findIn(r, "Lobby", `ReviewRow_{t.ids[1]}`) ~= nil, "no row for the reported name")
		Rig.tap(t.world, r, "Lobby", "ReviewRemove", 2)
		expect(nameOfA(t, t.a)):toBe(nil)
		check(said(t.world, t.a, "Your custom name was removed"), "no notice to the owner")
		FakeRoblox.run(t.world, SAVE_WAIT)
		expect(t.world.data.stores[PROFILES][`Player_{t.ids[1]}`].data.customName):toBe(nil)
		local list = t.world.data.stores[BLOCKLIST].Entries
		check(list ~= nil and table.find(list, "=captain zed") ~= nil, "not on the reviewed blocklist")
		check(
			#t.world.published >= 1 and t.world.published[1].data == "=captain zed",
			"not sent to other servers"
		)
		expect(#board(t).entries):toBe(0)
		-- Blocked now: the name, a look-alike, and a name with it as whole words.
		for _, name in { "Captain Zed", "CAPTAIN  ZED", "Captain Zed Jr" } do
			fire(t.world, t.a, { op = "SetName", name = name }, 2.5)
			check(rejected(t.world, t.a, "NameFiltered"), `{name} was allowed`)
		end
		-- One letter off is a different name now (D-076).
		fire(t.world, t.a, { op = "SetName", name = "Captain Zeb" }, 2.5)
		expect(nameOfA(t, t.a)):toBe("Captain Zeb")
		fire(t.world, t.a, { op = "SetName", name = "Big Wave" }, 2.5)
		expect(nameOfA(t, t.a)):toBe("Big Wave")
		Rig.noErrors(t.world)
	end)

	-- One eligible owner with saved name `saved` joins a server whose reviewed
	-- blocklist holds `entries`.
	local function owner(
		seed: number,
		entries: { string },
		saved: string
	): (FakeRoblox.World, FakeRoblox.Peer, number)
		local world = Rig.newWorld(seed)
		FakeRoblox.setNamePass(world, PASS)
		local id = world.nextUserId
		FakeRoblox.setCanChat(world, id, true)
		FakeRoblox.setOwnsPass(world, id, PASS, true)
		-- Into the tables the server's stores already hold (the server opened them at start).
		world.data.stores[BLOCKLIST] = world.data.stores[BLOCKLIST] or {}
		world.data.stores[BLOCKLIST].Entries = entries
		world.data.stores[PROFILES] = world.data.stores[PROFILES] or {}
		world.data.stores[PROFILES][`Player_{id}`] = { data = { customName = saved } }
		local peer = FakeRoblox.join(world, "A")
		FakeRoblox.run(world, 12 + SAVE_WAIT)
		return world, peer, id
	end

	it("clears a saved name that is exactly a removed one when its owner joins", function()
		for _, entry in { "=captain zed", "captainzed" } do -- 0.13.0 saved entries without "="
			local world, peer, id = owner(8, { entry }, "Captain Zed")
			expect(world.data.stores[PROFILES][`Player_{id}`].data.customName):toBe(nil)
			check(said(world, peer, "Your custom name was removed"), "no notice")
			Rig.noErrors(world)
		end
	end)

	it("does not use, but keeps, a saved name that only contains a removed one (D-076)", function()
		local world, peer, id = owner(9, { "=ann" }, "Ann Marie")
		expect(world.data.stores[PROFILES][`Player_{id}`].data.customName):toBe("Ann Marie")
		check(said(world, peer, "isn't allowed anymore"), "no notice")
		expect(practiceName(world, peer)):toBe(nil)
		Rig.noErrors(world)
		-- A name that merely has the letters in it is fine: "Ann" never blocks "Hannah".
		local world2, peer2 = owner(10, { "=ann" }, "Hannah")
		expect(practiceName(world2, peer2)):toBe("Hannah")
		Rig.noErrors(world2)
	end)
end)

describe("Reviews and reports hold up under failures (D-076)", function()
	local function board(t: Trio): any
		return Rig.storeOf(t.world, t.r :: FakeRoblox.Peer).get().review
	end

	it("acts only on the name the admin saw: a newer report is left alone", function()
		local t = trio(21, true)
		local r = t.r :: FakeRoblox.Peer
		fire(t.world, t.b, { op = "ReportName", userId = tostring(t.ids[1]) })
		fire(t.world, r, { op = "ReviewList" })
		expect(board(t).entries[1].name):toBe("Captain Zed")
		-- Meanwhile A renames and B reports the new name.
		fire(t.world, t.a, { op = "SetName", name = "Big Wave" }, 11)
		fire(t.world, t.b, { op = "ReportName", userId = tostring(t.ids[1]) })
		expect(queueEntry(t).name):toBe("Big Wave")
		-- The admin's click was for "Captain Zed".
		fire(t.world, r, { op = "ReviewRemove", userId = tostring(t.ids[1]), name = "Captain Zed" })
		check(rejected(t.world, r, "ReviewChanged"), "not turned down")
		expect(queueEntry(t).name):toBe("Big Wave")
		expect(nameOfA(t, t.a)):toBe("Big Wave")
		local list = t.world.data.stores[BLOCKLIST] and t.world.data.stores[BLOCKLIST].Entries
		expect(list == nil or #list == 0):toBe(true)
		fire(t.world, r, { op = "ReviewKeep", userId = tostring(t.ids[1]), name = "Captain Zed" })
		check(queueEntry(t) ~= nil, "Keep of an old name dismissed the new report")
		-- The list the admin gets back shows the name as it is now.
		expect(board(t).entries[1].name):toBe("Big Wave")
		Rig.noErrors(t.world)
	end)

	it("a blocklist write that fails changes nothing, and the admin can try again", function()
		local t = trio(22, true)
		local r = t.r :: FakeRoblox.Peer
		fire(t.world, t.b, { op = "ReportName", userId = tostring(t.ids[1]) })
		t.world.data.storeFailures[BLOCKLIST] = 3 -- every try of one write
		fire(t.world, r, { op = "ReviewRemove", userId = tostring(t.ids[1]), name = "Captain Zed" }, 8)
		check(rejected(t.world, r, "ReviewFailed"), "the failure was not reported")
		expect(queueEntry(t).name):toBe("Captain Zed")
		expect(nameOfA(t, t.a)):toBe("Captain Zed")
		expect(#t.world.published):toBe(0)
		-- A reload (5 minutes on) does not bring anything back or take anything away.
		FakeRoblox.run(t.world, 310)
		expect(nameOfA(t, t.a)):toBe("Captain Zed")
		fire(t.world, r, { op = "ReviewRemove", userId = tostring(t.ids[1]), name = "Captain Zed" }, 3)
		expect(nameOfA(t, t.a)):toBe(nil)
		expect(queueEntry(t)):toBe(nil)
		Rig.noErrors(t.world)
	end)

	it("a removal heard from another server survives a reload whose list lags", function()
		local t = trio(23)
		local messaging = t.world.server.game:GetService("MessagingService")
		t.world.current = t.world.server
		messaging:PublishAsync("NameBlocklist", "=captain zed")
		t.world.current = nil
		FakeRoblox.run(t.world, 2)
		expect(nameOfA(t, t.a)):toBe(nil)
		FakeRoblox.run(t.world, 310) -- the stored list never had it
		fire(t.world, t.a, { op = "SetName", name = "Captain Zed" }, 2.5)
		check(rejected(t.world, t.a, "NameFiltered"), "the name came back after a reload")
		Rig.noErrors(t.world)
	end)

	it("no new name passes until the reviewed blocklist has loaded, and it keeps trying", function()
		local world = Rig.newWorld(24)
		FakeRoblox.setNamePass(world, PASS)
		local id = world.nextUserId
		FakeRoblox.setCanChat(world, id, true)
		FakeRoblox.setOwnsPass(world, id, PASS, true)
		world.data.stores[BLOCKLIST] = world.data.stores[BLOCKLIST] or {}
		world.data.stores[BLOCKLIST].Entries = { "=captain zed" }
		world.data.storeFailures[BLOCKLIST] = 3 -- the first read fails every try
		local a = FakeRoblox.join(world, "A")
		FakeRoblox.run(world, 12)
		fire(world, a, { op = "SetName", name = "Captain Zed" }, 6) -- three tries with backoff
		check(rejected(world, a, "NameFilterFailed"), "a name passed before the list loaded")
		check(not rejected(world, a, "NameFiltered"), "checked against a list it never read")
		FakeRoblox.run(world, 30) -- the retry reads it
		fire(world, a, { op = "SetName", name = "Captain Zed" }, 2.5)
		check(rejected(world, a, "NameFiltered"), "the reviewed list was skipped")
		fire(world, a, { op = "SetName", name = "Big Wave" }, 2.5)
		FakeRoblox.run(world, SAVE_WAIT)
		expect(world.data.stores[PROFILES][`Player_{id}`].data.customName):toBe("Big Wave")
		Rig.noErrors(world)
	end)

	it("the daily report limit is saved, so rejoining does not reset it", function()
		local t = trio(25)
		-- B's saved data says they already sent the day's reports.
		local now = math.floor(t.world.clock)
		local record = t.world.data.stores[PROFILES][`Player_{t.ids[2]}`]
		check(record ~= nil, "B has no saved record")
		local userId = t.ids[2]
		FakeRoblox.leave(t.world, t.b)
		FakeRoblox.run(t.world, 3)
		t.world.data.stores[PROFILES][`Player_{userId}`].data.reportLog = { at = now, count = 10 }
		local b = FakeRoblox.join(t.world, "B", userId)
		FakeRoblox.run(t.world, 12)
		t.b = b
		fire(t.world, b, { op = "ReportName", userId = tostring(t.ids[1]) })
		check(rejected(t.world, b, "ReportLimit"), "the limit reset on rejoin")
		expect(queueEntry(t)):toBe(nil)
		Rig.noErrors(t.world)
	end)
end)
