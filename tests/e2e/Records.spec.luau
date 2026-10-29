--!strict
-- End to end: match records, per-player stats and analytics (D-094) on the
-- real server and client. A record is written once, when the match ends, to
-- MatchRecords_v1; a failing or unavailable store, a low write budget or a
-- failing AnalyticsService never breaks a match or a profile save; a queued
-- match is public, a private code's is not; a new player's onboarding funnel
-- and every player's visit funnel and custom events are logged.

local process = require("@lune/process")

local Test = require("@testlib/Test")
local FakeRoblox = require("@testlib/FakeRoblox")
local Support = require("./Support")

local describe, it, expect = Test.describe, Test.it, Test.expect

local MATCH_LIMIT = 400 -- simulated seconds for a whole autoplayed match
local RECORDS = "MatchRecords_v1"
local PLAYER_DATA = "PlayerData_v1"

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function noErrors(rig: Support.Rig)
	check(#rig.world.errors == 0, "script errors: " .. table.concat(rig.world.errors, " | "))
	check(#rig.world.wireWarnings == 0, "wire warnings: " .. table.concat(rig.world.wireWarnings, " | "))
end

local function records(rig: Support.Rig): { [string]: any }
	return rig.world.data.stores[RECORDS] or {}
end

local function count(map: { [string]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

local function only(map: { [string]: any }): (string, any)
	local key, value = next(map)
	check(key ~= nil, "no match record was saved")
	return key :: string, value
end

local function saved(rig: Support.Rig, userId: number): any
	local keys = rig.world.data.stores[PLAYER_DATA]
	local record = if keys then keys[`Player_{userId}`] else nil
	return if record then record.data else nil
end

local function serverSaid(rig: Support.Rig, text: string): number
	return #Support.outputLines(rig.world.server, text)
end

-- Plays a queued match between the two to the end.
local function playQueued(rig: Support.Rig, p1: FakeRoblox.Peer, p2: FakeRoblox.Peer)
	Support.queueMatch(rig, p1, p2)
	Support.press(rig, p1, "Autoplay")
	Support.press(rig, p2, "Autoplay")
	check(
		Support.runUntil(rig, function()
			return Support.said(rig, p1, "match over") and Support.said(rig, p2, "match over")
		end, MATCH_LIMIT),
		"the match never finished"
	)
end

local function calls(rig: Support.Rig, method: string, userId: number?): { { any } }
	local out = {}
	for _, call in rig.world.analytics.calls do
		if call.method == method and (userId == nil or call.userId == userId) then
			table.insert(out, call.args)
		end
	end
	return out
end

local function onboardingSteps(rig: Support.Rig, userId: number): { number }
	local out = {}
	for _, args in calls(rig, "LogOnboardingFunnelStepEvent", userId) do
		table.insert(out, args[1])
	end
	return out
end

local function customEvents(rig: Support.Rig, userId: number, name: string): { { any } }
	local out = {}
	for _, args in calls(rig, "LogCustomEvent", userId) do
		if args[1] == name then
			table.insert(out, args)
		end
	end
	return out
end

describe("e2e: match records (D-094)", function()
	it("writes one record when a queued match ends, with stats in both profiles", function()
		local rig = Support.new(process.cwd, 94)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.queueMatch(rig, p1, p2)
		Support.press(rig, p1, "Autoplay")
		Support.press(rig, p2, "Autoplay")
		Support.run(rig, 60)
		expect(count(records(rig))):toBe(0) -- nothing while it is being played
		check(
			Support.runUntil(rig, function()
				return Support.said(rig, p1, "match over") and Support.said(rig, p2, "match over")
			end, MATCH_LIMIT),
			"the match never finished"
		)
		Support.run(rig, 5)
		noErrors(rig)
		local key, record = only(records(rig))
		expect(string.match(key, "^%d%d%d%d%d%d%d%d_job1_m1_%d+$") ~= nil):toBe(true)
		expect(record.mode):toBe("Queue")
		expect(record.rated):toBe(true)
		expect(record.seats[1].id):toBe("1")
		expect(record.seats[2].id):toBe("2")
		expect(record.reason):toBe("Election")
		expect(#record.plans):toBe(12)
		expect(#record.projected > 0):toBe(true)
		expect(record.version ~= nil):toBe(true)
		expect(serverSaid(rig, "match record saved: MatchRecords_v1/" .. key)):toBe(1)

		for userId = 1, 2 do
			local data = saved(rig, userId)
			check(data ~= nil and data.stats ~= nil, `player {userId} has no stats`)
			expect(data.stats.publicGames):toBe(1)
			expect(data.stats.privateGames):toBe(0)
			expect(data.stats.elections):toBe(1)
			local won = record.winner == userId
			local expected = if won and record.landslide then 1 else 0
			expect(data.stats.landslides):toBe(expected)
			expect(data.stats.evFor):toBe(record.ev[userId])
		end
	end)

	it("a private code's match is recorded as Private and is not public", function()
		local rig = Support.new(process.cwd, 95)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.run(rig, 2)
		FakeRoblox.fire(rig.world, p1, { op = "Host" })
		Support.run(rig, 1)
		local lobby = (p1.modules[`{rig.world.root}/src/client/Store.luau`] :: any).get().lobby
		FakeRoblox.fire(rig.world, p2, { op = "Join", code = lobby.code })
		Support.run(rig, 1)
		Support.press(rig, p1, "Autoplay")
		Support.press(rig, p2, "Autoplay")
		check(
			Support.runUntil(rig, function()
				return Support.said(rig, p1, "match over") and Support.said(rig, p2, "match over")
			end, MATCH_LIMIT),
			"the match never finished"
		)
		Support.run(rig, 5)
		noErrors(rig)
		local _, record = only(records(rig))
		expect(record.mode):toBe("Private")
		expect(record.rated):toBe(true)
		for userId = 1, 2 do
			local data = saved(rig, userId)
			expect(data.stats.publicGames):toBe(0)
			expect(data.stats.privateGames):toBe(1)
			expect(data.stats.landslides):toBe(0)
		end
	end)

	it("a failing record store never breaks the match or the profile saves", function()
		local rig = Support.new(process.cwd, 96)
		rig.world.data.storeFailures[RECORDS] = 1000
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		playQueued(rig, p1, p2)
		Support.run(rig, 120) -- every retry, with backoff
		noErrors(rig)
		expect(count(records(rig))):toBe(0)
		expect(saved(rig, 1).games):toBe(1)
		expect(saved(rig, 2).games):toBe(1)
		expect(#Support.outputLines(rig.world.server, "could not save match record")):toBe(1)
		-- The next match plays and saves as normal once the store is back.
		rig.world.data.storeFailures[RECORDS] = 0
		Support.fire(rig, p1, { op = "Queue" })
		Support.fire(rig, p2, { op = "Queue" })
		Support.run(rig, 1) -- autoplay is still on from the first match
		check(
			Support.runUntil(rig, function()
				local data = saved(rig, 1)
				return data ~= nil and data.games + data.practice.games >= 2 or count(records(rig)) > 0
			end, MATCH_LIMIT * 3),
			"the second match never finished: "
				.. table.concat(Support.outputLines(rig.world.server, "[270]"), "\n")
				.. "\n"
				.. table.concat(Support.outputLines(p1, "rejected"), "\n")
		)
		Support.run(rig, 5)
		noErrors(rig)
		expect(count(records(rig))):toBe(1)
	end)

	it("waits for write budget, then writes", function()
		local rig = Support.new(process.cwd, 97)
		rig.world.data.writeBudget = 5
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		playQueued(rig, p1, p2)
		Support.run(rig, 30)
		expect(count(records(rig))):toBe(0) -- held back: player saves keep their room
		expect(saved(rig, 1).games):toBe(1)
		rig.world.data.writeBudget = 200
		Support.run(rig, 10)
		expect(count(records(rig))):toBe(1)
		noErrors(rig)
	end)

	it("in an unpublished place the match plays on and the record is only logged", function()
		local rig = Support.new(process.cwd, 98)
		rig.world.data.unpublished = true
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		playQueued(rig, p1, p2)
		Support.run(rig, 5)
		noErrors(rig)
		expect(count(records(rig))):toBe(0)
		expect(#Support.outputLines(rig.world.server, "match records are off this session")):toBe(1)
	end)
end)

describe("e2e: analytics (D-094)", function()
	it("logs a new player's onboarding through the tutorial, once per step", function()
		local rig = Support.new(process.cwd, 99)
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 2)
		expect(onboardingSteps(rig, 1)):toEqual({ 1 })
		Support.fire(rig, p1, { op = "Practice" })
		Support.press(rig, p1, "Autoplay")
		check(
			Support.runUntil(rig, function()
				return Support.said(rig, p1, "match over")
			end, MATCH_LIMIT),
			"the tutorial never finished"
		)
		Support.run(rig, 3)
		noErrors(rig)
		expect(onboardingSteps(rig, 1)):toEqual({ 1, 2, 3, 4, 5, 6, 7 })
		expect(saved(rig, 1).stats.onboard):toBe(7)
		-- A real match next: step 8, then 9 when it ends.
		Support.fire(rig, p1, { op = "Practice", difficulty = "Easy" })
		Support.run(rig, 2)
		Support.fire(rig, p1, { op = "Forfeit", matchId = "m2" })
		Support.run(rig, 3)
		expect(onboardingSteps(rig, 1)):toEqual({ 1, 2, 3, 4, 5, 6, 7, 8, 9 })
		-- Custom events: two starts, two ends (the forfeit a loss).
		expect(#customEvents(rig, 1, "MatchStarted")):toBe(2)
		local ended = customEvents(rig, 1, "MatchEnded")
		expect(#ended):toBe(2)
		expect(ended[1][3].CustomField01):toBe("Tutorial")
		expect(ended[2][3].CustomField02):toBe("Forfeit")
		expect(ended[2][3].CustomField03):toBe("Lost")
		-- The visit funnel: lobby, looked, played, finished, again.
		local steps = {}
		for _, args in calls(rig, "LogFunnelStepEvent", 1) do
			expect(args[1]):toBe("Visit")
			table.insert(steps, args[3])
		end
		expect(steps):toEqual({ 1, 2, 3, 4, 5, 6 })
	end)

	it("moves forward only, and never starts for a player who has played before", function()
		local rig = Support.new(process.cwd, 100)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.run(rig, 2)
		-- Both are new: step 1. A queued match first: step 10 (the queue), then
		-- 11 (a rated match); 8 and 9 are behind it (Roblox counts them as done).
		playQueued(rig, p1, p2)
		Support.run(rig, 3)
		expect(onboardingSteps(rig, 1)):toEqual({ 1, 10, 11 })
		local queued = customEvents(rig, 1, "QueueJoined")
		expect(#queued):toBe(1)
		expect(#customEvents(rig, 1, "QueueLeft")):toBe(1)

		-- A veteran (games on record, no onboarding) logs no onboarding at all.
		local veteran = Support.new(process.cwd, 101)
		veteran.world.data.stores[PLAYER_DATA] = {
			Player_1 = { data = { version = 1, rating = 1040, games = 3, wins = 2, losses = 1 } },
		}
		Support.join(veteran, "Player1")
		Support.run(veteran, 2)
		expect(#onboardingSteps(veteran, 1)):toBe(0)
		expect(#calls(veteran, "LogFunnelStepEvent", 1)):toBe(1) -- the visit still counts
	end)

	it("a failing AnalyticsService breaks nothing", function()
		local rig = Support.new(process.cwd, 102)
		rig.world.analytics.failures = 100000
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		playQueued(rig, p1, p2)
		Support.run(rig, 5)
		noErrors(rig)
		expect(count(records(rig))):toBe(1)
		expect(saved(rig, 1).games):toBe(1)
		expect(#Support.outputLines(rig.world.server, "analytics call failed") > 0):toBe(true)
	end)
end)
