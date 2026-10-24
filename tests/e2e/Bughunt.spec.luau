--!strict
-- End to end: regressions found by the server bug hunt (D-028 and D-026).
-- Saved data under slow or interleaved requests, what a finished match writes
-- to a profile, and the lobby status every idle player sees.

local process = require("@lune/process")

local Config = require("@sim/Config")
local Test = require("@testlib/Test")
local FakeRoblox = require("@testlib/FakeRoblox")
local Support = require("./Support")

local describe, it, expect = Test.describe, Test.it, Test.expect

local MATCH_LIMIT = 400 -- simulated seconds for a whole autoplayed match
local STORE = "PlayerData_v1"

local function newRig(seed: number): Support.Rig
	return Support.new(process.cwd, seed)
end

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function saved(rig: Support.Rig, userId: number): any
	local keys = rig.world.data.stores[STORE]
	return if keys then keys[`Player_{userId}`] else nil
end

local function status(peer: FakeRoblox.Peer): string
	return FakeRoblox.screen(peer).status
end

local function hasRating(peer: FakeRoblox.Peer): boolean
	return string.find(status(peer), "Rating", 1, true) ~= nil
end

describe("e2e bug hunt: a result is never dropped", function()
	it("records a result for a player whose profile is reloading, so ratings stay zero-sum", function()
		local rig = newRig(17)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.queueMatch(rig, p1, p2)
		check(Support.autoUntil(rig, { p1, p2 }, "Election", 600), "never reached election night")

		-- Player 2 drops and comes back while every request takes 8 s: their old
		-- record is still saving, and the new load has barely started.
		rig.world.data.latency = 8
		Support.leave(rig, p2)
		Support.run(rig, 0.2)
		local back = Support.join(rig, "Player2", 2)
		Support.run(rig, 9)
		check(not hasRating(back), "expected player 2's profile to still be loading")

		Support.press(rig, p1, "Skip")
		Support.press(rig, back, "Skip")
		Support.run(rig, 60)

		expect(#Support.outputLines(rig.world.server, "could not record")):toBe(0)
		local a, b = saved(rig, 1), saved(rig, 2)
		expect(a.data.games):toBe(1)
		expect(b.data.games):toBe(1)
		expect(a.data.rating + b.data.rating):toBe(2000)
		expect(a.data.rating ~= 1000):toBe(true)
		expect(a.data.wins + b.data.wins):toBe(1)
		expect(a.data.losses + b.data.losses):toBe(1)
		-- The returning player is told how their rating moved.
		expect(Support.said(rig, back, "Rating 1000 →")):toBe(true)
		expect(#rig.world.errors):toBe(0)
	end)
end)

describe("e2e bug hunt: leaving twice during a slow save", function()
	it("releases the lock and lets the next join load at normal speed", function()
		local rig = newRig(12)
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 3)
		rig.world.data.latency = 3
		Support.leave(rig, p1) -- the old entry is saving (3 s)
		Support.run(rig, 0.5)
		local again = Support.join(rig, "Player1", 1) -- its load waits for the old entry
		Support.run(rig, 0.2)
		Support.leave(rig, again) -- gone again before that load began
		Support.run(rig, 60)
		rig.world.data.latency = 0.2

		expect(saved(rig, 1).lock):toBe(nil)
		local third = Support.join(rig, "Player1", 1)
		check(
			Support.runUntil(rig, function()
				return hasRating(third)
			end, 5),
			"the third join did not load promptly: the earlier entry leaked"
		)
		expect(#Support.outputLines(rig.world.server, "shutting down")):toBe(0)
	end)
end)

describe("e2e bug hunt: unrated and abandoned matches", function()
	it("an unrated human match changes nothing, not even the practice record", function()
		local rig = newRig(12)
		rig.world.data.stores[STORE] = {
			Player_1 = {
				lock = { jobId = "other-server", at = math.floor(rig.world.clock) },
				data = { version = 1, rating = 1500, games = 4, wins = 3, losses = 1 },
			},
		}
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.run(rig, 20) -- player 1 settles for read-only
		Support.queueMatch(rig, p1, p2)
		Support.press(rig, p1, "Autoplay")
		Support.press(rig, p2, "Autoplay")
		check(
			Support.runUntil(rig, function()
				return Support.said(rig, p1, "match over") and Support.said(rig, p2, "match over")
			end, MATCH_LIMIT),
			"the match never finished"
		)
		Support.run(rig, 5)

		check(#Support.outputLines(rig.world.server, "is unrated") == 1, "the match should be unrated")
		local profile = saved(rig, 2).data
		expect(profile.rating):toBe(1000)
		expect(profile.games):toBe(0)
		expect(profile.practice.games):toBe(0)
		expect(profile.practice.wins + profile.practice.losses):toBe(0)
		expect(#profile.recent):toBe(0)
	end)

	it("a match against the bot still counts as practice", function()
		local rig = newRig(11)
		local p1 = Support.join(rig, "Player1")
		Support.press(rig, p1, "Practice")
		Support.press(rig, p1, "Autoplay")
		check(
			Support.runUntil(rig, function()
				return Support.said(rig, p1, "match over")
			end, MATCH_LIMIT),
			"the practice match never finished"
		)
		Support.run(rig, 3)
		expect(saved(rig, 1).data.practice.games):toBe(1)
		expect(saved(rig, 1).data.games):toBe(0)
	end)

	for _, seed in { 5, 12 } do
		it(`a forfeit after the last plan records no election result (seed {seed})`, function()
			local rig = newRig(seed)
			local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
			Support.queueMatch(rig, p1, p2)
			Support.press(rig, p1, "Autoplay")
			Support.press(rig, p2, "Autoplay")
			check(Support.untilStatus(rig, p1, "Week 11 Plan · Input", 1500), "never reached week 11")
			Support.leave(rig, p2)
			check(
				Support.runUntil(rig, function()
					return Support.said(rig, p1, "match over")
				end, 900),
				"the match never ended after the disconnect"
			)
			Support.run(rig, 10)

			expect(#Support.outputLines(rig.world.server, "over: Forfeit")):toBe(1)
			for _, userId in { 1, 2 } do
				local last = saved(rig, userId).data.recent[1]
				expect(last.reason):toBe("Forfeit")
				expect(last.evFor):toBe(nil)
				expect(last.evAgainst):toBe(nil)
			end
		end)
	end
end)

describe("e2e bug hunt: DataService guards", function()
	it("does not overwrite a record another live server took over mid-session", function()
		local rig = newRig(12)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.run(rig, 2)
		local theirs = {
			lock = { jobId = "other-server", at = math.floor(rig.world.clock) },
			data = { version = 1, rating = 1400, games = 7, wins = 5, losses = 2 },
		}
		rig.world.data.stores[STORE].Player_1 = theirs
		Support.queueMatch(rig, p1, p2)
		Support.press(rig, p1, "Autoplay")
		Support.press(rig, p2, "Autoplay")
		check(
			Support.runUntil(rig, function()
				return Support.said(rig, p1, "match over") and Support.said(rig, p2, "match over")
			end, MATCH_LIMIT),
			"the match never finished"
		)
		Support.run(rig, 5)
		expect(saved(rig, 1).lock.jobId):toBe("other-server")
		expect(saved(rig, 1).data.rating):toBe(1400)
		expect(saved(rig, 1).data.games):toBe(7)
	end)

	it("a player who is leaving is not rated into a match", function()
		local rig = newRig(12)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.run(rig, 3)
		rig.world.data.latency = 3
		Support.leave(rig, p1) -- the old record is still saving
		Support.run(rig, 0.5)
		local again = Support.join(rig, "Player1", 1)
		Support.queueMatch(rig, again, p2)
		check(#Support.outputLines(rig.world.server, "started (Match)") == 1, "the match did not start")
		expect(#Support.outputLines(rig.world.server, "is unrated")):toBe(1)
	end)
end)

describe("e2e bug hunt: the lobby status stays current", function()
	it("idle players see the queue count change", function()
		local rig = newRig(12)
		local p1, p2, p3 =
			Support.join(rig, "Player1"), Support.join(rig, "Player2"), Support.join(rig, "Player3")
		Support.run(rig, 2)
		check(Support.shows(p3, "0 in queue"), "expected an empty queue")
		Support.press(rig, p1, "Queue")
		check(Support.shows(p3, "1 in queue"), `an idle player did not see the queue grow: {status(p3)}`)
		Support.press(rig, p2, "Queue")
		check(Support.shows(p3, "0 in queue"), `an idle player did not see the pair leave: {status(p3)}`)
	end)

	it("clears 'server full' when a match ends, for players who were not in it", function()
		local rig = newRig(12)
		local fillers = {}
		-- One practice match per filler fills every match slot (D-083: 50).
		for k = 1, Config.defaults.MATCHES_PER_SERVER do
			table.insert(fillers, Support.join(rig, `Filler{k}`))
		end
		for _, peer in fillers do
			Support.press(rig, peer, "Practice")
		end
		local late = Support.join(rig, "Late")
		Support.run(rig, 2)
		check(Support.shows(late, "server full"), `expected a full server: {status(late)}`)
		for _, peer in fillers do
			Support.leave(rig, peer)
		end
		-- Nobody is left in any match: they are abandoned once the grace runs out.
		Support.run(rig, 60)
		check(not Support.shows(late, "server full"), `still shows a full server: {status(late)}`)
	end)
end)
