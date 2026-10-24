--!strict
-- End to end: the Daily Race (D-082) on the real server and client. A run gets
-- the day's seed, candidate and Hard bot (never the tutorial); leaving before
-- week 1 counts for nothing; the first run past week 1 is the day's run, saved
-- in the profile with its streak and written to the day's OrderedDataStore;
-- later runs that day are practice; the card's request answers with the board.

local process = require("@lune/process")

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local SimDaily = require("@sim/Daily")
local Support = require("./Support")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local PLAYER_DATA = "PlayerData_v1"
local MATCH_LIMIT = 400 -- simulated seconds for a whole autoplayed match

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function noErrors(rig: Support.Rig)
	check(#rig.world.errors == 0, "script errors: " .. table.concat(rig.world.errors, " | "))
	check(#rig.world.wireWarnings == 0, "wire warnings: " .. table.concat(rig.world.wireWarnings, " | "))
end

local function state(rig: Support.Rig, peer: FakeRoblox.Peer): any
	local module = peer.modules[`{rig.world.root}/src/client/Store.luau`]
	check(module ~= nil, "the client Store is not loaded")
	return module.get()
end

local function saved(rig: Support.Rig, userId: number): any
	local keys = rig.world.data.stores[PLAYER_DATA]
	local record = if keys then keys[`Player_{userId}`] else nil
	return if record then record.data else nil
end

local function serverSaid(rig: Support.Rig, text: string): number
	return #Support.outputLines(rig.world.server, text)
end

local function told(rig: Support.Rig, peer: FakeRoblox.Peer, text: string): boolean
	for _, message in state(rig, peer).messages do
		if string.find(message.text, text, 1, true) then
			return true
		end
	end
	return false
end

-- The day's board in the fake engine (store "DailyRace_v1", scope the date).
local function board(rig: Support.Rig, day: number): { [string]: number }
	return rig.world.data.ordered[`DailyRace_v1/{SimDaily.dateKey(day)}`] or {}
end

-- Autoplays the player's current match to its end.
local function playOut(rig: Support.Rig, peer: FakeRoblox.Peer, matchId: string)
	Support.press(rig, peer, "Autoplay")
	check(
		Support.runUntil(rig, function()
			return serverSaid(rig, `match {matchId} over`) > 0
		end, MATCH_LIMIT),
		`match {matchId} never finished`
	)
	Support.press(rig, peer, "Autoplay") -- off again
	Support.run(rig, 16) -- the batched save (every 15 s) writes the profile
end

describe("e2e: the Daily Race (D-082)", function()
	it(
		"plays the day's race: its candidate, the Hard bot, no tutorial; leaving early counts for nothing",
		function()
			local rig = Support.new(process.cwd, 71)
			local p1 = Support.join(rig, "Player1")
			local day = SimDaily.dayOf(math.floor(rig.world.clock))
			local race = SimDaily.race(C, day)
			Support.fire(rig, p1, { op = "DailyRace" })
			Support.run(rig, 1)
			expect(serverSaid(rig, "match m1 started (Practice)")):toBe(1)
			expect(serverSaid(rig, `seed {race.seed}, bot Hard, daily race`)):toBe(1)
			expect(serverSaid(rig, "tutorial")):toBe(0) -- a brand-new player, yet no tutorial
			check(told(rig, p1, "Daily Race: this run counts"), "the player was not told the run counts")
			local payload = state(rig, p1).payload
			expect(payload.daily):toEqual({ day = day, counted = true })
			expect(payload.view.claims[race.candidate]):toBe(payload.you)
			expect(payload.view.claims[race.botCandidate] ~= nil):toBe(true)
			check(
				math.abs(payload.deadline - payload.stageStart - C.TIMER_SELECT) < 1e-6,
				"the Daily Race's Select is not the Hard bot's x1 timer"
			)

			-- Leaving in Select: nothing saved, the next run still counts.
			Support.fire(rig, p1, { op = "Forfeit", matchId = "m1" })
			Support.run(rig, 3)
			local data = saved(rig, 1)
			expect(if data then data.daily else nil):toBe(nil)
			expect(next(board(rig, day))):toBe(nil)
			Support.fire(rig, p1, { op = "DailyRace" })
			Support.run(rig, 1)
			expect(state(rig, p1).payload.daily.counted):toBe(true)
			noErrors(rig)
		end
	)

	it(
		"counts the first run past week 1: profile, streak and the day's board; later runs are practice",
		function()
			local rig = Support.new(process.cwd, 72)
			local p1 = Support.join(rig, "Player1")
			local day = SimDaily.dayOf(math.floor(rig.world.clock))
			Support.fire(rig, p1, { op = "DailyRace" })
			Support.run(rig, 1)
			playOut(rig, p1, "m1")
			expect(serverSaid(rig, "match m1 over: Election")):toBe(1)

			local data = saved(rig, 1)
			check(data ~= nil and data.daily ~= nil, "the run was not saved in the profile")
			expect(data.daily.last):toBe(day)
			expect(data.daily.streak):toBe(1)
			local score = board(rig, day).Player_1
			check(score ~= nil, "the run was not written to the day's board")
			expect(data.daily.score):toBe(score)
			-- The margin is the election's.
			local payload = state(rig, p1).payload
			local election = payload.view.election
			local them = if payload.you == 1 then 2 else 1
			expect(data.daily.margin):toBe(election.ev[payload.you] - election.ev[them])
			-- Nothing else moved: no rating, no practice game, the tutorial still ahead.
			expect(data.games or 0):toBe(0)
			expect(if data.practice then data.practice.games else 0):toBe(0)
			expect(data.tutorialDone):toBe(nil)
			-- The client heard about the run.
			local run = state(rig, p1).dailyRun
			check(run ~= nil, "no Daily message with the run reached the client")
			expect(run.counted):toBe(true)
			expect(run.margin):toBe(data.daily.margin)
			local info = state(rig, p1).daily
			expect(info.played):toBe(true)
			expect(info.streak):toBe(1)
			expect(info.margin):toBe(data.daily.margin)

			-- A second run the same day is practice: told so, nothing saved. It
			-- starts from Results' Rematch (D-082): today's race again, same seed.
			Support.fire(rig, p1, { op = "Rematch", matchId = "m1" })
			Support.run(rig, 1)
			expect(serverSaid(rig, "rematch of m1")):toBe(1)
			local race = SimDaily.race(C, day)
			expect(serverSaid(rig, `seed {race.seed}, bot Hard, daily race`)):toBe(2)
			check(told(rig, p1, "Practice run"), "the second run was not called practice")
			expect(state(rig, p1).payload.daily.counted):toBe(false)
			playOut(rig, p1, "m2")
			expect(board(rig, day).Player_1):toBe(score)
			expect(saved(rig, 1).daily.score):toBe(score)
			expect(state(rig, p1).dailyRun.counted):toBe(false)

			-- The card's request answers with today's board and the player on it.
			Support.fire(rig, p1, { op = "Daily" })
			Support.run(rig, 3)
			info = state(rig, p1).daily
			expect(info.board.status):toBe("Ok")
			expect(info.board.you.rank):toBe(1)
			expect(info.board.entries[1].id):toBe("1")

			-- The next bot match is still the tutorial: the Daily Race never was.
			Support.fire(rig, p1, { op = "Practice" })
			Support.run(rig, 1)
			expect(serverSaid(rig, "match m3 started (Practice)")):toBe(1)
			expect(serverSaid(rig, "tutorial")):toBe(1)
			noErrors(rig)
		end
	)

	it("a counted run abandoned after week 1 began scores as a full loss", function()
		local rig = Support.new(process.cwd, 74)
		local p1 = Support.join(rig, "Player1")
		local day = SimDaily.dayOf(math.floor(rig.world.clock))
		Support.fire(rig, p1, { op = "DailyRace" })
		Support.run(rig, 1)
		check(Support.autoUntil(rig, { p1 }, "Week 1 Plan · Input", 300), "never reached week 1")
		Support.run(rig, 16)
		local data = saved(rig, 1)
		check(data ~= nil and data.daily ~= nil, "reaching week 1 did not save the day's run")
		expect(data.daily.streak):toBe(1)
		expect(data.daily.margin):toBe(nil)
		Support.leave(rig, p1)
		Support.run(rig, C.DISCONNECT_GRACE + 20)
		expect(serverSaid(rig, "match m1 over: Abandoned")):toBe(1)
		Support.run(rig, 5)
		data = saved(rig, 1)
		expect(data.daily.margin):toBe(C.DAILY_FORFEIT_MARGIN)
		check(board(rig, day).Player_1 ~= nil, "the abandoned run is not on the day's board")
		noErrors(rig)
	end)

	it("gives two players the same seed and candidate that day", function()
		local rig = Support.new(process.cwd, 73)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.fire(rig, p1, { op = "DailyRace" })
		Support.fire(rig, p2, { op = "DailyRace" })
		Support.run(rig, 1)
		local race = SimDaily.race(C, SimDaily.dayOf(math.floor(rig.world.clock)))
		expect(serverSaid(rig, `seed {race.seed}, bot Hard, daily race`)):toBe(2)
		for _, peer in { p1, p2 } do
			local payload = state(rig, peer).payload
			expect(payload.view.claims[race.candidate]):toBe(payload.you)
		end
		noErrors(rig)
	end)
end)
