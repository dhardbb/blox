--!strict
-- Admin "Timers off" (D-081) on the real server and client: the Lobby's corner
-- toggle (admins only) is saved in the profile; a bot match then has no choice
-- deadline and the header reads "No timer (admin)"; a non-admin's request is
-- turned down; a match with a non-admin keeps its timers and the "?" sheet says
-- why; two admins in a private match lose their timers mid-match from the
-- sheet, and a match where that happened is unrated.

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local C = Config.defaults
local ADMIN_HEADER = "No timer\n(admin)"

local function rejected(world: FakeRoblox.World, peer: FakeRoblox.Peer, reason: string): boolean
	for _, message in Rig.storeOf(world, peer).get().messages do
		if message.rejected and message.reason == reason then
			return true
		end
	end
	return false
end

local function told(world: FakeRoblox.World, peer: FakeRoblox.Peer, part: string): boolean
	for _, message in Rig.storeOf(world, peer).get().messages do
		if string.find(message.text, part, 1, true) then
			return true
		end
	end
	return false
end

local function saved(world: FakeRoblox.World, userId: number): any
	local keys = world.data.stores.PlayerData_v1
	local record = if keys then keys[`Player_{userId}`] else nil
	return if record then record.data else nil
end

-- A world whose next `admins` players are admins (by Config's list, as the
-- server reads it). Everyone joining has played before (no tutorial).
local function world(seed: number, admins: number): FakeRoblox.World
	local w = Rig.newWorld(seed)
	local ids = {}
	for k = 0, admins - 1 do
		table.insert(ids, w.nextUserId + k)
	end
	FakeRoblox.setModuleField(w, "src/server/Admins.luau", "userIds", ids)
	return w
end

local function join(w: FakeRoblox.World, name: string): (FakeRoblox.Peer, number)
	local id = w.nextUserId
	local keys = w.data.stores.PlayerData_v1 or {}
	w.data.stores.PlayerData_v1 = keys
	keys[`Player_{id}`] = { data = { version = 1, tutorialDone = true } }
	local peer = FakeRoblox.join(w, name)
	FakeRoblox.run(w, 1)
	return peer, id
end

local function fire(w: FakeRoblox.World, peer: FakeRoblox.Peer, payload: any)
	FakeRoblox.fire(w, peer, payload)
	FakeRoblox.run(w, 0.5)
end

-- Host a private match with `a` and join it with `b`.
local function private(w: FakeRoblox.World, a: FakeRoblox.Peer, b: FakeRoblox.Peer)
	fire(w, a, { op = "Host" })
	local code = Rig.storeOf(w, a).get().lobby.code
	check(type(code) == "string", "no code to join")
	fire(w, b, { op = "Join", code = code })
	FakeRoblox.run(w, 1)
end

describe("Admin Timers off: the Lobby toggle (D-081)", function()
	it("shows only to admins, saves to the profile, and is checked on the server", function()
		local w = world(80, 1)
		local admin, adminId = join(w, "A")
		local other, otherId = join(w, "B")
		local lobby = Rig.storeOf(w, admin).get().lobby
		check(lobby.admin ~= nil, "the admin's lobby has no admin settings")
		expect(lobby.admin.timersOff):toBe(false)
		expect(Rig.storeOf(w, other).get().lobby.admin):toBe(nil)
		local toggle = Rig.need(admin, "Lobby", "TimersToggle")
		check(Rig.shown(toggle, "Lobby"), "no Timers toggle for the admin")
		expect(toggle:GetAttribute("Label")):toBe("Timers on (admin)")
		check(not Rig.shown(Rig.need(other, "Lobby", "TimersToggle"), "Lobby"), "a non-admin sees the toggle")

		Rig.tap(w, admin, "Lobby", "TimersToggle", 0.5)
		expect(Rig.storeOf(w, admin).get().lobby.admin.timersOff):toBe(true)
		expect(Rig.need(admin, "Lobby", "TimersToggle"):GetAttribute("On")):toBe(true)
		-- A second tap inside the cooldown is turned down, and the toggle goes
		-- back to what the server saved.
		Rig.tap(w, admin, "Lobby", "TimersToggle", 0.3)
		check(rejected(w, admin, "RateLimited"), "a tap inside the cooldown was not turned down")
		expect(Rig.storeOf(w, admin).get().lobby.admin.timersOff):toBe(true)
		expect(Rig.need(admin, "Lobby", "TimersToggle"):GetAttribute("On")):toBe(true)
		FakeRoblox.run(w, 16) -- the batched save
		expect((saved(w, adminId) or {}).adminTimersOff):toBe(true)

		-- A non-admin asking anyway is turned down and nothing is saved.
		fire(w, other, { op = "SetTimersOff", on = true })
		check(rejected(w, other, "AdminOnly"), "a non-admin's SetTimersOff was not turned down")
		FakeRoblox.run(w, 16)
		expect((saved(w, otherId) or {}).adminTimersOff):toBe(nil)
		-- A malformed one never reaches the handler.
		fire(w, admin, { op = "SetTimersOff", on = "yes" })
		check(rejected(w, admin, "BadShape"), "a malformed SetTimersOff was not turned down")
		Rig.noErrors(w)
	end)
end)

describe("Admin Timers off in a match (D-081)", function()
	it("against the bot: no deadline, 'No timer (admin)' in the header, the sheet's toggle", function()
		local w = world(81, 1)
		local admin = join(w, "A")
		fire(w, admin, { op = "SetTimersOff", on = true })
		FakeRoblox.run(w, 1.2) -- past the cooldown
		Rig.tap(w, admin, "Lobby", "Practice", 1)
		local payload = Rig.payloadOf(w, admin)
		expect(payload.stage):toBe("Input")
		expect(payload.deadline):toBe(nil)
		expect(payload.adminNoTimer):toBe(true)
		check(told(w, admin, "Timers off (admin)"), "the admin was not told")
		FakeRoblox.run(w, 1)
		expect(Rig.textOf(admin, "Select", "Timer")):toBe(ADMIN_HEADER)
		-- Ten idle minutes later Select is still waiting.
		FakeRoblox.run(w, 600)
		payload = Rig.payloadOf(w, admin)
		expect(payload.view.phase):toBe("Select")
		-- The "?" sheet: on, and a tap turns the timers back on with a full Select timer.
		Rig.tap(w, admin, "Select", "HelpButton", 0.5)
		local chip = Rig.need(admin, "HelpOverlay", "HelpAdminTimers")
		check(Rig.shown(chip, "HelpOverlay"), "no admin toggle in the sheet")
		expect(chip:GetAttribute("On")):toBe(true)
		Rig.tap(w, admin, "HelpOverlay", "HelpAdminTimers", 0.5)
		payload = Rig.payloadOf(w, admin)
		check(payload.deadline ~= nil, "the timers did not come back")
		local length = payload.deadline - payload.stageStart
		check(math.abs(length - C.TIMER_SELECT * C.BOT_TIME_MULT_MEDIUM) < 0.01, `a {length} s Select timer`)
		expect(payload.adminNoTimer):toBe(nil)
		check(told(w, admin, "Timers back on"), "the admin was not told the timers are back")
		Rig.noErrors(w)
	end)

	it("never against a non-admin: the timers run and the sheet says why", function()
		local w = world(82, 1)
		local admin = join(w, "A")
		local other = join(w, "B")
		fire(w, admin, { op = "SetTimersOff", on = true })
		private(w, admin, other)
		for _, peer in { admin, other } do
			local payload = Rig.payloadOf(w, peer)
			check(payload ~= nil and payload.view.phase == "Select", "the match did not start")
			check(payload.deadline ~= nil, "a match with a non-admin lost its timer")
			expect(payload.adminNoTimer):toBe(nil)
		end
		expect(Rig.payloadOf(w, other).adminTimers):toBe(nil)
		check(Rig.textOf(admin, "Select", "Timer") ~= ADMIN_HEADER, "the admin header showed")
		Rig.tap(w, admin, "Select", "HelpButton", 0.5)
		local note = Rig.textOf(admin, "HelpOverlay", "HelpAdminNote")
		expect(note):toBe("Only in games where every player is an admin.")
		-- The non-admin's sheet has no admin row at all.
		Rig.tap(w, other, "Select", "HelpButton", 0.5)
		check(
			not Rig.shown(Rig.need(other, "HelpOverlay", "HelpAdmin"), "HelpOverlay"),
			"a non-admin sees it"
		)
		Rig.noErrors(w)
	end)

	it("two admins: off mid-match for both from the sheet; the match is then unrated", function()
		local w = world(83, 2)
		local a, aId = join(w, "A")
		local b = join(w, "B")
		private(w, a, b)
		check(Rig.payloadOf(w, a).deadline ~= nil, "timers off before anyone asked")
		Rig.tap(w, b, "Select", "HelpButton", 0.5)
		Rig.tap(w, b, "HelpOverlay", "HelpAdminTimers", 0.5)
		for _, peer in { a, b } do
			local payload = Rig.payloadOf(w, peer)
			expect(payload.deadline):toBe(nil)
			expect(payload.adminNoTimer):toBe(true)
			check(told(w, peer, "This match is unrated"), "a player was not told it is unrated")
		end
		FakeRoblox.run(w, 1)
		expect(Rig.textOf(a, "Select", "Timer")):toBe(ADMIN_HEADER)
		-- Back on (after the cooldown) so the timers carry the match into week 1.
		FakeRoblox.run(w, 1.2)
		fire(w, b, { op = "SetTimersOff", on = false })
		check(Rig.payloadOf(w, a).deadline ~= nil, "the timers did not come back")
		Rig.waitFor(w, function()
			local p = Rig.payloadOf(w, a)
			return p ~= nil and p.view.phase == "Plan"
		end, Rig.MATCH_LIMIT, "week 1")
		fire(w, a, { op = "Forfeit", matchId = Rig.payloadOf(w, a).matchId })
		FakeRoblox.run(w, 2)
		check(told(w, a, "Timers were off (admin)"), "no unrated notice at the end")
		check(told(w, b, "Timers were off (admin)"), "no unrated notice at the end")
		FakeRoblox.run(w, 16)
		local data = saved(w, aId) or {}
		expect(data.games or 0):toBe(0)
		Rig.noErrors(w)
	end)
end)
