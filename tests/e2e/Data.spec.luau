--!strict
-- End to end: ratings and saved stats. The real DataService, MatchService and
-- debug UI on the fake Roblox engine, whose DataStoreService is a world-level
-- table (world.data) with switches for an unpublished place and failures.

local process = require("@lune/process")

local Test = require("@testlib/Test")
local Candidates = require("@sim/Candidates")
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

-- What is saved for a user id right now (nil if nothing).
local function saved(rig: Support.Rig, userId: number): any
	local keys = rig.world.data.stores[STORE]
	return if keys then keys[`Player_{userId}`] else nil
end

local function noErrors(rig: Support.Rig)
	check(#rig.world.errors == 0, "script errors: " .. table.concat(rig.world.errors, " | "))
	check(#rig.world.wireWarnings == 0, "wire warnings: " .. table.concat(rig.world.wireWarnings, " | "))
end

local function warnings(rig: Support.Rig, text: string): { string }
	local out = {}
	for _, line in Support.outputLines(rig.world.server, text) do
		if string.sub(line, 1, 5) == "WARN " then
			table.insert(out, line)
		end
	end
	return out
end

-- Two players queue, autoplay, and play to the end. Returns them.
local function playQueuedMatch(rig: Support.Rig, p1: FakeRoblox.Peer, p2: FakeRoblox.Peer)
	Support.queueMatch(rig, p1, p2)
	Support.press(rig, p1, "Autoplay")
	Support.press(rig, p2, "Autoplay")
	local done = function()
		return Support.said(rig, p1, "match over") and Support.said(rig, p2, "match over")
	end
	check(Support.runUntil(rig, done, MATCH_LIMIT), "the match never finished for both players")
	Support.run(rig, 3) -- let the saves finish
end

local function status(peer: FakeRoblox.Peer): string
	return FakeRoblox.screen(peer).status
end

describe("e2e: ratings and saved stats", function()
	it("saves both profiles after a queued match, equal and opposite", function()
		local rig = newRig(12)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		expect(string.find(status(p1), "Rating 1000 (0-0)", 1, true) ~= nil):toBe(true)
		expect(string.find(status(p2), "Rating 1000 (0-0)", 1, true) ~= nil):toBe(true)

		playQueuedMatch(rig, p1, p2)
		noErrors(rig)

		local a, b = saved(rig, 1), saved(rig, 2)
		check(a ~= nil and b ~= nil, "a profile was not saved")
		local winner, loser = a.data, b.data
		if a.data.rating < b.data.rating then
			winner, loser = b.data, a.data
		end
		expect(winner.rating):toBe(1016)
		expect(loser.rating):toBe(984)
		expect(winner.rating + loser.rating):toBe(2000)
		expect(winner.wins):toBe(1)
		expect(winner.losses):toBe(0)
		expect(loser.wins):toBe(0)
		expect(loser.losses):toBe(1)
		expect(winner.games):toBe(1)
		expect(loser.games):toBe(1)
		expect(winner.version):toBe(1)

		for _, record in { a, b } do
			local ids = {}
			for id in record.data.perCandidate do
				table.insert(ids, id)
			end
			expect(#ids):toBe(1)
			check(table.find(Candidates.ids, ids[1]) ~= nil, `unknown candidate {ids[1]}`)
			expect(#record.data.recent):toBe(1)
			local last = record.data.recent[1]
			expect(last.reason):toBe("Election")
			expect(last.opponentRating):toBe(1000)
			expect(last.evFor + last.evAgainst):toBe(538)
			expect(last.candidate):toBe(ids[1])
			expect(record.lock.jobId):toBe("job-1")
		end
		-- The two players' candidate records mirror each other's recent matches.
		expect(a.data.recent[1].candidate):toBe(b.data.recent[1].opponentCandidate)
		expect(a.data.recent[1].evFor):toBe(b.data.recent[1].evAgainst)
		expect(a.data.recent[1].won):toBe(not b.data.recent[1].won)
	end)

	it("shows the rating change after the match and the new rating in the lobby", function()
		local rig = newRig(12)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		playQueuedMatch(rig, p1, p2)

		local a = saved(rig, 1).data
		local expectedLine = if a.rating > 1000 then "Rating 1000 → 1016" else "Rating 1000 → 984"
		expect(Support.said(rig, p1, expectedLine)):toBe(true)
		expect(string.find(FakeRoblox.screen(p1).board, expectedLine, 1, true) ~= nil):toBe(true)
		local wins, losses = a.wins, a.losses
		expect(string.find(status(p1), `Rating {a.rating} ({wins}-{losses})`, 1, true) ~= nil):toBe(true)
		-- The other player sees the mirror image.
		local b = saved(rig, 2).data
		expect(Support.said(rig, p2, `Rating 1000 → {b.rating}`)):toBe(true)
		expect(string.find(status(p2), `Rating {b.rating} ({b.wins}-{b.losses})`, 1, true) ~= nil):toBe(true)
	end)

	it("a practice match does not change the rating", function()
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
		noErrors(rig)

		local record = saved(rig, 1)
		check(record ~= nil, "nothing was saved")
		expect(record.data.rating):toBe(1000)
		expect(record.data.games):toBe(0)
		expect(#record.data.recent):toBe(0)
		expect(next(record.data.perCandidate)):toBe(nil)
		expect(record.data.practice.games):toBe(1)
		expect(record.data.practice.wins + record.data.practice.losses):toBe(1)
		expect(Support.said(rig, p1, "Rating 1000 →")):toBe(false)
		expect(string.find(status(p1), "Rating 1000 (0-0)", 1, true) ~= nil):toBe(true)
	end)

	it("gives a returning player their saved profile and releases the lock when they leave", function()
		local rig = newRig(12)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		playQueuedMatch(rig, p1, p2)
		local rating = saved(rig, 1).data.rating
		local wins, losses = saved(rig, 1).data.wins, saved(rig, 1).data.losses

		Support.leave(rig, p1)
		Support.run(rig, 3)
		check(saved(rig, 1).lock == nil, "the lock was not released")
		expect(saved(rig, 1).data.rating):toBe(rating)

		local again = Support.join(rig, "Player1", 1)
		Support.run(rig, 2)
		expect(string.find(status(again), `Rating {rating} ({wins}-{losses})`, 1, true) ~= nil):toBe(true)
		expect(saved(rig, 1).lock.jobId):toBe("job-1")
		noErrors(rig)
	end)

	it("charges a rated forfeit to the player who left, after they have gone", function()
		local rig = newRig(17)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.queueMatch(rig, p1, p2)
		Support.press(rig, p1, "Autoplay")
		check(Support.untilStatus(rig, p1, "Week 1 Plan · Input", 400), "never reached Week 1")

		Support.leave(rig, p2)
		check(
			Support.runUntil(rig, function()
				return Support.said(rig, p1, "match over")
			end, MATCH_LIMIT),
			"the match never ended after the disconnect"
		)
		Support.run(rig, 10) -- the leaver's record is updated on its own thread
		noErrors(rig)

		expect(saved(rig, 1).data.rating):toBe(1016)
		expect(saved(rig, 2).data.rating):toBe(984)
		expect(saved(rig, 2).data.losses):toBe(1)
		expect(saved(rig, 2).data.recent[1].reason):toBe("Forfeit")
		expect(saved(rig, 2).data.recent[1].evFor):toBe(nil)
		expect(saved(rig, 2).lock):toBe(nil)
		expect(Support.said(rig, p1, "Rating 1000 → 1016")):toBe(true)
	end)
end)

describe("e2e: saved data when things go wrong", function()
	it("an unpublished place warns once and still plays, in memory", function()
		local rig = newRig(12)
		rig.world.data.unpublished = true
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.run(rig, 2)

		local lines = warnings(rig, "DataStore unavailable")
		expect(#lines):toBe(1)
		expect(lines[1]):toBe(
			"WARN [270] DataStore unavailable (publish the place and enable Studio API access to save); using memory"
		)
		expect(string.find(status(p1), "Rating 1000 (0-0)", 1, true) ~= nil):toBe(true)

		playQueuedMatch(rig, p1, p2)
		noErrors(rig)
		expect(#warnings(rig, "DataStore unavailable")):toBe(1)
		expect(rig.world.data.writes):toBe(0)
		local total = 0
		for _, peer in { p1, p2 } do
			local rating = tonumber(string.match(status(peer), "Rating (%d+)"))
			check(
				rating ~= nil and rating ~= 1000,
				`{peer.name} rating did not move in memory: {status(peer)}`
			)
			total += rating :: number
		end
		expect(total):toBe(2000)
		-- Nothing reached the real store, so a restart starts from scratch (the warning says so).
		expect(saved(rig, 1)):toBe(nil)
	end)

	it("recognises the other 'API access is off' error as well", function()
		local rig = newRig(12)
		rig.world.data.unpublished = true
		rig.world.data.unpublishedMessage = "403: Studio access to APIs is not allowed."
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 2)
		expect(#warnings(rig, "DataStore unavailable")):toBe(1)
		expect(string.find(status(p1), "Rating 1000 (0-0)", 1, true) ~= nil):toBe(true)
	end)

	it("retries a transient failure on load and still loads", function()
		local rig = newRig(12)
		rig.world.data.failures = 2
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 1)
		expect(string.find(status(p1), "Rating", 1, true)):toBe(nil) -- still waiting on the backoff
		Support.run(rig, 6)
		expect(string.find(status(p1), "Rating 1000 (0-0)", 1, true) ~= nil):toBe(true)
		expect(#warnings(rig, "DataStore load for Player1 failed")):toBe(2)
		expect(#warnings(rig, "DataStore unavailable")):toBe(0)
		expect(saved(rig, 1).lock.jobId):toBe("job-1")
	end)

	it("retries transient failures on save, so the result is still written", function()
		local rig = newRig(12)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		rig.world.data.failures = 3
		Support.queueMatch(rig, p1, p2)
		Support.press(rig, p1, "Autoplay")
		Support.press(rig, p2, "Autoplay")
		check(
			Support.runUntil(rig, function()
				return Support.said(rig, p1, "match over") and Support.said(rig, p2, "match over")
			end, MATCH_LIMIT),
			"the match never finished"
		)
		Support.run(rig, 15)
		noErrors(rig)
		expect(#warnings(rig, "DataStore save for")):toBe(3)
		expect(saved(rig, 1).data.rating + saved(rig, 2).data.rating):toBe(2000)
		expect(saved(rig, 1).data.games):toBe(1)
		expect(saved(rig, 2).data.games):toBe(1)
	end)

	it("survives UpdateAsync calling its callback twice", function()
		local rig = newRig(12)
		rig.world.data.reruns = 2
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		expect(string.find(status(p1), "Rating 1000 (0-0)", 1, true) ~= nil):toBe(true)
		expect(string.find(status(p2), "Rating 1000 (0-0)", 1, true) ~= nil):toBe(true)
		expect(saved(rig, 1).data.rating):toBe(1000)
	end)

	it("never saves the loser's penalty twice when a save is slow", function()
		local rig = newRig(12)
		rig.world.data.latency = 3 -- every request takes 3 s
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.run(rig, 10)
		playQueuedMatch(rig, p1, p2)
		Support.run(rig, 10)
		noErrors(rig)
		expect(saved(rig, 1).data.games):toBe(1)
		expect(saved(rig, 1).data.rating + saved(rig, 2).data.rating):toBe(2000)
	end)

	it("respects a fresh lock from another server: read-only, unrated, unchanged", function()
		local rig = newRig(12)
		local now = math.floor(rig.world.clock)
		rig.world.data.stores[STORE] = {
			Player_1 = {
				lock = { jobId = "other-server", at = now },
				data = { version = 1, rating = 1500, games = 4, wins = 3, losses = 1 },
			},
		}
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.run(rig, 20) -- the retries with backoff give up
		check(#warnings(rig, "in use by another server") == 1, "no read-only warning")
		expect(string.find(status(p1), "Rating 1500 (3-1)", 1, true) ~= nil):toBe(true)

		playQueuedMatch(rig, p1, p2)
		noErrors(rig)
		expect(#Support.outputLines(rig.world.server, "is unrated")):toBe(1)
		expect(Support.said(rig, p1, "Rating 1500 →")):toBe(false)
		expect(Support.said(rig, p2, "Rating 1000 →")):toBe(false)

		-- The other server's record is untouched, and the opponent's did not move.
		expect(saved(rig, 1).lock.jobId):toBe("other-server")
		expect(saved(rig, 1).data.rating):toBe(1500)
		expect(saved(rig, 1).data.games):toBe(4)
		expect(saved(rig, 2).data.rating):toBe(1000)
		expect(saved(rig, 2).data.games):toBe(0)
	end)

	it("takes the lock once the other server lets go within the retry window", function()
		local rig = newRig(12)
		rig.world.data.stores[STORE] = {
			Player_1 = {
				lock = { jobId = "other-server", at = math.floor(rig.world.clock) },
				data = { version = 1, rating = 1210, games = 2, wins = 2, losses = 0 },
			},
		}
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 2)
		expect(string.find(status(p1), "Rating", 1, true)):toBe(nil) -- waiting for the lock
		rig.world.data.stores[STORE].Player_1.lock = nil -- the other server saved and released
		Support.run(rig, 8)
		expect(string.find(status(p1), "Rating 1210 (2-0)", 1, true) ~= nil):toBe(true)
		expect(saved(rig, 1).lock.jobId):toBe("job-1")
		expect(#warnings(rig, "in use by another server")):toBe(0)
	end)

	it("takes over a stale lock from a crashed server", function()
		local rig = newRig(12)
		rig.world.clock += 1000
		rig.world.data.stores[STORE] = {
			Player_1 = {
				lock = { jobId = "crashed-server", at = math.floor(rig.world.clock) - 500 },
				data = { version = 1, rating = 1111, games = 1, wins = 1, losses = 0 },
			},
		}
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 1)
		expect(string.find(status(p1), "Rating 1111 (1-0)", 1, true) ~= nil):toBe(true)
		expect(saved(rig, 1).lock.jobId):toBe("job-1")
	end)

	it("repairs a garbage record instead of crashing", function()
		local rig = newRig(12)
		rig.world.data.stores[STORE] = { Player_1 = { data = "oops" }, Player_2 = 42 }
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.run(rig, 1)
		expect(string.find(status(p1), "Rating 1000 (0-0)", 1, true) ~= nil):toBe(true)
		expect(string.find(status(p2), "Rating 1000 (0-0)", 1, true) ~= nil):toBe(true)
		noErrors(rig)
	end)

	it("leaves data from a newer version alone", function()
		local rig = newRig(12)
		rig.world.data.stores[STORE] = {
			Player_1 = { data = { version = 99, rating = 1777, wins = 9, losses = 0, extra = "keep me" } },
		}
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 2)
		expect(string.find(status(p1), "Rating 1777 (9-0)", 1, true) ~= nil):toBe(true)
		Support.leave(rig, p1)
		Support.run(rig, 3)
		expect(saved(rig, 1).data.extra):toBe("keep me")
		expect(saved(rig, 1).data.version):toBe(99)
	end)

	it("saves and releases everyone when the server shuts down", function()
		local rig = newRig(12)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		playQueuedMatch(rig, p1, p2)
		check(saved(rig, 1).lock ~= nil, "expected the lock to be held while the player is here")
		rig.world.data.latency = 2
		expect(FakeRoblox.shutdown(rig.world)):toBe(true)
		expect(saved(rig, 1).lock):toBe(nil)
		expect(saved(rig, 2).lock):toBe(nil)
		expect(saved(rig, 1).data.games):toBe(1)
	end)

	it("gives up on a shutdown save that cannot finish, within Roblox's 30 seconds", function()
		local rig = newRig(12)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		playQueuedMatch(rig, p1, p2)
		rig.world.data.failures = 1000
		rig.world.data.latency = 10 -- each failed try takes 10 s, so the retries can't all fit
		expect(FakeRoblox.shutdown(rig.world)):toBe(true)
		check(#warnings(rig, "shutting down with") > 0, "no warning about the unfinished saves")
	end)
end)
