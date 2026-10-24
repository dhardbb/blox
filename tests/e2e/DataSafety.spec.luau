--!strict
-- End to end: saved data from the 0.13 security review. A loss follows a
-- player who leaves a rated match for another server; locks stay fresh;
-- request spam cannot burn the DataStore budget; a forfeit before week 1 and a
-- pair's fourth rated game in a day are unrated (D-077). Two fake worlds with
-- one set of DataStore keys stand for two servers of the experience.

local process = require("@lune/process")

local Test = require("@testlib/Test")
local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("../ui/Rig")
local Support = require("./Support")

local describe, it, expect = Test.describe, Test.it, Test.expect

local MATCH_LIMIT = 600
local STORE = "PlayerData_v1"
local LOCK_TTL = 120 -- DataService's

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

-- A rig on a world with its own JobId; `stores` shares another world's DataStore keys.
local function rigOn(seed: number, jobId: string, stores: any?): Support.Rig
	local world = FakeRoblox.world({ root = process.cwd, seed = seed, jobId = jobId, stores = stores })
	return { world = world, peers = {}, history = {}, last = {}, logBoxes = {} }
end

local function saved(rig: Support.Rig, userId: number): any
	local keys = rig.world.data.stores[STORE]
	return if keys then keys[`Player_{userId}`] else nil
end

local function status(peer: FakeRoblox.Peer): string
	return FakeRoblox.screen(peer).status
end

local function noErrors(rig: Support.Rig)
	check(#rig.world.errors == 0, "script errors: " .. table.concat(rig.world.errors, " | "))
end

-- Runs two worlds side by side (whichever is behind steps next) for `seconds`,
-- or until `predicate()` holds. Returns whether it did.
local function runBoth(a: Support.Rig, b: Support.Rig, seconds: number, predicate: (() -> boolean)?): boolean
	local target = math.max(a.world.clock, b.world.clock) + seconds
	while a.world.clock < target - 1e-9 or b.world.clock < target - 1e-9 do
		if predicate and predicate() then
			return true
		end
		if a.world.clock <= b.world.clock then
			Support.run(a, 0.1)
		else
			Support.run(b, 0.1)
		end
	end
	return predicate == nil or predicate()
end

local function seedProfile(rig: Support.Rig, userId: number, data: any)
	rig.world.data.stores[STORE] = rig.world.data.stores[STORE] or {}
	rig.world.data.stores[STORE][`Player_{userId}`] = { data = data }
end

describe("e2e: a result follows the player to another server", function()
	it("a player who leaves a rated match and joins another server still takes the loss", function()
		local a = rigOn(17, "job-1")
		local b = rigOn(17, "job-2", a.world.data.stores)
		seedProfile(a, 2, { version = 1, rating = 1100, games = 2, wins = 2, losses = 0 })
		local p1, p2 = Support.join(a, "Player1"), Support.join(a, "Player2")
		Support.queueMatch(a, p1, p2)
		Support.press(a, p1, "Autoplay")
		check(Support.untilStatus(a, p1, "Week 1 Plan · Input", 400), "never reached Week 1")

		-- P2 leaves; A saves and lets go of their data; P2 joins server B, which takes it.
		Support.leave(a, p2)
		runBoth(a, b, 3)
		local back = Support.join(b, "Player2", 2)
		runBoth(a, b, 3)
		expect(saved(a, 2).lock.jobId):toBe("job-2")
		check(string.find(status(back), "Rating 1100 (2-0)", 1, true) ~= nil, `B shows {status(back)}`)

		-- A's match ends in P2's forfeit while B holds P2's data.
		check(
			runBoth(a, b, MATCH_LIMIT, function()
				return Support.said(a, p1, "match over")
			end),
			"the match never ended"
		)
		runBoth(a, b, 150) -- B picks the result up within a lock refresh
		noErrors(a)
		noErrors(b)
		local data = saved(a, 2).data
		expect(data.losses):toBe(1)
		expect(data.games):toBe(3)
		check(data.rating < 1100, `P2's rating did not drop: {data.rating}`)
		expect(data.recent[#data.recent].reason):toBe("Forfeit")
		expect(saved(a, 2).pending):toBe(nil)
		check(
			string.find(status(back), `Rating {data.rating} (2-1)`, 1, true) ~= nil,
			`B's lobby shows {status(back)}`
		)
		-- B's leaderboard has the new rating, not the one it loaded.
		expect(b.world.data.ordered.Leaderboard_v1.Player_2):toBe(data.rating)

		-- B's last save keeps it.
		Support.leave(b, back)
		runBoth(a, b, 5)
		expect(saved(a, 2).data.rating):toBe(data.rating)
		expect(saved(a, 2).data.losses):toBe(1)
		expect(saved(a, 2).lock):toBe(nil)
	end)

	it("keeps a player's lock fresh while they stay, without saving unchanged data", function()
		local a = rigOn(12, "job-1")
		Support.join(a, "Player1")
		Support.run(a, 3)
		local writes = a.world.data.writes
		Support.run(a, 300)
		local lock = saved(a, 1).lock
		check(lock ~= nil and lock.jobId == "job-1", "no lock")
		check(
			math.floor(a.world.clock) - lock.at < LOCK_TTL,
			`the lock went stale: {lock.at} at {a.world.clock}`
		)
		-- About one refresh a minute, not a save per tick.
		check(a.world.data.writes - writes <= 6, `{a.world.data.writes - writes} writes in 300 s`)
		noErrors(a)
	end)
end)

describe("e2e: request spam and the DataStore budget", function()
	it("SetColor spam is cooled down and an unchanged profile is not saved", function()
		local rig = rigOn(12, "job-1")
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 3)
		local writes = rig.world.data.writes
		for _ = 1, 20 do
			Support.fire(rig, p1, { op = "SetColor" }) -- auto, which it already is
		end
		Support.run(rig, 2)
		expect(rig.world.data.writes - writes):toBe(0)
		check(#Support.outputLines(rig.world.server, "rejected SetColor") > 0, "no cooldown")
		noErrors(rig)
	end)

	it("an admin's color changes are cooled down and saved in one batch", function()
		local rig = rigOn(12, "job-1")
		FakeRoblox.setModuleField(rig.world, "src/server/Admins.luau", "userIds", { 1 })
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 3)
		local writes = rig.world.data.writes
		for k = 1, 20 do
			Support.fire(rig, p1, { op = "SetColor", color = if k % 2 == 0 then "Teal" else "Amber" })
		end
		check(rig.world.data.writes - writes <= 1, `{rig.world.data.writes - writes} writes while spamming`)
		Support.run(rig, 40)
		check(saved(rig, 1).data.color ~= nil, "the color was never saved")
		check(rig.world.data.writes - writes <= 3, `{rig.world.data.writes - writes} writes in all`)
		noErrors(rig)
	end)

	it("SetName spam is cooled down before the text filter", function()
		local rig = rigOn(12, "job-1")
		FakeRoblox.setNamePass(rig.world, 5551234)
		FakeRoblox.setCanChat(rig.world, 1, true)
		FakeRoblox.setOwnsPass(rig.world, 1, 5551234, true)
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 5)
		local calls = rig.world.text.calls
		for k = 1, 10 do
			Support.fire(rig, p1, { op = "SetName", name = `Name {string.rep("a", k % 3 + 2)}` })
		end
		check(rig.world.text.calls - calls <= 1, `{rig.world.text.calls - calls} filter calls`)
		noErrors(rig)
	end)
end)

describe("e2e: unrated matches (D-077)", function()
	it("a forfeit during Select leaves both ratings alone and says so", function()
		local rig = rigOn(12, "job-1")
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.queueMatch(rig, p1, p2)
		local payload = Rig.payloadOf(rig.world, p2)
		check(payload ~= nil, "no match")
		Support.fire(rig, p2, { op = "Forfeit", matchId = payload.matchId })
		Support.run(rig, 5)
		noErrors(rig)
		expect(saved(rig, 1).data.rating):toBe(1000)
		expect(saved(rig, 2).data.rating):toBe(1000)
		expect(saved(rig, 1).data.games):toBe(0)
		expect(Support.said(rig, p1, "Rating 1000 →")):toBe(false)
		check(Support.said(rig, p1, "ForfeitUnrated"), "no unrated notice")
	end)

	it("a pair's fourth rated game in 24 hours is unrated, and says so", function()
		local rig = rigOn(17, "job-1")
		local now = math.floor(rig.world.clock)
		-- Three rated games against each other in the last day (one is older and no longer counts).
		seedProfile(rig, 1, {
			version = 1,
			rating = 1000,
			games = 4,
			wins = 2,
			losses = 2,
			ratedWith = { ["2"] = { now - 90000, now - 3000, now - 2000, now - 1000 } },
		})
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.queueMatch(rig, p1, p2)
		check(Support.said(rig, p1, "MatchUnrated"), "P1 was not told")
		check(Support.said(rig, p2, "MatchUnrated"), "P2 was not told")
		check(#Support.outputLines(rig.world.server, "is unrated") == 1, "the server did not log it")
		local payload = Rig.payloadOf(rig.world, p2)
		Support.press(rig, p1, "Autoplay")
		Support.press(rig, p2, "Autoplay")
		check(Support.untilStatus(rig, p1, "Week 1 Plan · Input", 400), "never reached Week 1")
		Support.fire(rig, p2, { op = "Forfeit", matchId = payload.matchId })
		Support.run(rig, 5)
		noErrors(rig)
		expect(saved(rig, 1).data.rating):toBe(1000)
		expect(saved(rig, 1).data.games):toBe(4)
	end)

	it("records each rated game against the pair, so the cap counts it", function()
		local rig = rigOn(17, "job-1")
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.queueMatch(rig, p1, p2)
		local payload = Rig.payloadOf(rig.world, p2)
		Support.press(rig, p1, "Autoplay")
		Support.press(rig, p2, "Autoplay")
		check(Support.untilStatus(rig, p1, "Week 1 Plan · Input", 400), "never reached Week 1")
		Support.fire(rig, p2, { op = "Forfeit", matchId = payload.matchId })
		Support.run(rig, 5)
		expect(saved(rig, 1).data.rating):toBe(1016)
		expect(#saved(rig, 1).data.ratedWith["2"]):toBe(1)
		expect(#saved(rig, 2).data.ratedWith["1"]):toBe(1)
	end)
end)
