--!strict
-- End to end: the real src/server and src/client scripts on the fake Roblox
-- engine (tests/lib/FakeRoblox.luau), with simulated players on a simulated
-- clock. Automates the Phase 2 flows in docs/TESTING.md. Each spec builds its
-- own world.

local process = require("@lune/process")

local Test = require("@testlib/Test")
local FakeRoblox = require("@testlib/FakeRoblox")
local Support = require("./Support")

local describe, it, expect = Test.describe, Test.it, Test.expect

local MATCH_LIMIT = 400 -- simulated seconds for a whole autoplayed match

local function newRig(seed: number, screen: { x: number, y: number }?): Support.Rig
	return Support.new(process.cwd, seed, screen)
end

-- Fails the spec with a readable message.
local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function finished(rig: Support.Rig, peer: FakeRoblox.Peer): () -> boolean
	return function()
		return Support.said(rig, peer, "match over")
	end
end

local function noErrors(rig: Support.Rig)
	check(#rig.world.errors == 0, "script errors: " .. table.concat(rig.world.errors, " | "))
	check(#rig.world.wireWarnings == 0, "wire warnings: " .. table.concat(rig.world.wireWarnings, " | "))
end

-- Both players press Queue, then reach Week 1 Plan with the Auto button.
local function toWeekOnePlan(rig: Support.Rig): (FakeRoblox.Peer, FakeRoblox.Peer)
	local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
	Support.queueMatch(rig, p1, p2)
	check(
		Support.autoUntil(rig, { p1, p2 }, "Week 1 Plan · Input", 300),
		"never reached the Week 1 Plan input"
	)
	return p1, p2
end

describe("e2e: full matches", function()
	it("plays a practice match to the election", function()
		local rig = newRig(11)
		local p1 = Support.join(rig, "Player1")
		Support.press(rig, p1, "Practice")
		Support.run(rig, 1)
		Support.press(rig, p1, "Autoplay")
		check(Support.untilStatus(rig, p1, "Election · Show", MATCH_LIMIT), "election night never began")
		check(Support.runUntil(rig, finished(rig, p1), MATCH_LIMIT), "the match never finished")

		expect(Support.said(rig, p1, "match over: Election")):toBe(true)
		expect(#Support.outputLines(rig.world.server, "match m1 started (Practice)")):toBe(1)
		expect(#Support.outputLines(rig.world.server, "over: Election")):toBe(1)
		noErrors(rig)
		local you, them = Support.electionScore(p1)
		check(you ~= nil and them ~= nil, "no election line on the board: " .. FakeRoblox.screen(p1).board)
		expect((you :: number) + (them :: number)):toBe(538)
		expect(Support.said(rig, p1, "rejected")):toBe(false)
	end)

	it("a Practice request picks the bot's difficulty; the button plays Medium (D-057)", function()
		local rig = newRig(12)
		Support.returning(rig) -- not the tutorial, which always plays Easy (D-080)
		local p1 = Support.join(rig, "Player1")
		Support.fire(rig, p1, { op = "Practice", difficulty = "Extreme" })
		local started = Support.outputLines(rig.world.server, "match m1 started (Practice)")
		check(#started == 1, "the practice match never started")
		check(string.find(started[1], "bot Extreme", 1, true) ~= nil, `not an Extreme bot: {started[1]}`)
		Support.press(rig, p1, "Autoplay")
		check(Support.runUntil(rig, finished(rig, p1), MATCH_LIMIT), "the Extreme match never finished")
		expect(Support.said(rig, p1, "rejected")):toBe(false)

		Support.press(rig, p1, "Autoplay")
		Support.press(rig, p1, "Practice")
		local second = Support.outputLines(rig.world.server, "match m2 started (Practice)")
		check(#second == 1, "the second practice match never started")
		check(string.find(second[1], "bot Medium", 1, true) ~= nil, `not a Medium bot: {second[1]}`)
		noErrors(rig)
	end)

	it("autoplay acts on the same step number in a second match", function()
		local rig = newRig(21)
		Support.returning(rig) -- timed bot matches: not the tutorial (D-075)
		local p1 = Support.join(rig, "Player1")
		-- Match 1: autoplay sees the first draft round (step 3), then goes off.
		Support.press(rig, p1, "Practice")
		Support.press(rig, p1, "Autoplay")
		check(Support.untilStatus(rig, p1, "Draft round 1", 30), "match 1 never reached the draft")
		Support.press(rig, p1, "Autoplay")
		check(Support.runUntil(rig, finished(rig, p1), 3000), "match 1 never finished")

		-- Match 2: play Select by hand, then switch autoplay on during the map
		-- reveal, so the first state autoplay sees is that same step 3.
		Support.press(rig, p1, "Practice")
		Support.press(rig, p1, "Auto")
		check(Support.untilStatus(rig, p1, "MapReveal", 10), "match 2 never reached MapReveal")
		Support.press(rig, p1, "Autoplay")
		check(Support.untilStatus(rig, p1, "Draft round 1", 10), "match 2 never reached the draft")
		Support.run(rig, 1)
		-- Autoplay locked the pick (the bot already had), so round 1 is over.
		expect(string.find(FakeRoblox.screen(p1).status, "Draft round 1", 1, true)):toBe(nil)

		check(
			Support.runUntil(rig, function()
				return #Support.outputLines(rig.world.server, "match m2 over") > 0
			end, MATCH_LIMIT),
			"match 2 never finished"
		)
		expect(Support.said(rig, p1, "rejected")):toBe(false)
		noErrors(rig)
	end)

	it("plays a queued two-player match with mirrored results", function()
		local rig = newRig(12)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.queueMatch(rig, p1, p2)
		Support.press(rig, p1, "Autoplay")
		Support.press(rig, p2, "Autoplay")
		local done = function()
			return Support.said(rig, p1, "match over") and Support.said(rig, p2, "match over")
		end
		check(Support.runUntil(rig, done, MATCH_LIMIT), "the match never finished for both players")

		noErrors(rig)
		local a, b = Support.electionScore(p1)
		local c, d = Support.electionScore(p2)
		check(a ~= nil and c ~= nil, "a board is missing the election line")
		expect(a):toBe(d)
		expect(b):toBe(c)
		expect((a :: number) + (b :: number)):toBe(538)
		expect(Support.said(rig, p1, "rejected")):toBe(false)
		expect(Support.said(rig, p2, "rejected")):toBe(false)
	end)
end)

describe("e2e: typed input", function()
	it("locks a hand-typed Select and moves on to MapReveal", function()
		local rig = newRig(13)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.queueMatch(rig, p1, p2)
		expect(Support.shows(p1, "Select")):toBe(true)

		Support.type(rig, p1, "select hale jobs farms safety")
		expect(string.find(FakeRoblox.screen(p1).status, "LOCKED", 1, true) ~= nil):toBe(true)
		Support.press(rig, p2, "Auto")

		check(Support.untilStatus(rig, p1, "MapReveal", 10), "Player1 never reached MapReveal")
		check(Support.untilStatus(rig, p2, "MapReveal", 10), "Player2 never reached MapReveal")
		expect(string.find(FakeRoblox.screen(p1).board, "Marcus Hale", 1, true) ~= nil):toBe(true)
		expect(Support.said(rig, p1, "rejected")):toBe(false)
		noErrors(rig)
	end)

	it("rejects an over-cap plan, then locks a valid one", function()
		local rig = newRig(14)
		local p1 = toWeekOnePlan(rig)

		Support.type(rig, p1, "plan gotv OH 9")
		expect(Support.said(rig, p1, "rejected Submit: GotvCap")):toBe(true)
		local warns = {}
		for _, line in Support.outputLines(rig.world.server, "rejected Submit") do
			if string.find(line, "GotvCap", 1, true) and string.sub(line, 1, 5) == "WARN " then
				table.insert(warns, line)
			end
		end
		expect(#warns):toBe(1)
		expect(string.find(FakeRoblox.screen(p1).status, "LOCKED", 1, true)):toBe(nil)

		local home = Support.homeState(p1)
		check(home ~= nil, "no home state on the YOU line: " .. FakeRoblox.screen(p1).board)
		Support.type(rig, p1, `plan rally {home} jobs; fund {home}; poll OH`)
		check(
			string.find(FakeRoblox.screen(p1).status, "LOCKED", 1, true) ~= nil,
			"a plan using the home state did not lock; status: "
				.. FakeRoblox.screen(p1).status
				.. " | log: "
				.. table.concat(rig.history[p1], " / ")
		)
		noErrors(rig)
	end)

	it("takes 15 s from the time bank and shows it to the opponent", function()
		local rig = newRig(15)
		local p1, p2 = toWeekOnePlan(rig)

		local before = Support.countdown(p1)
		check(before ~= nil, "no countdown in the status: " .. FakeRoblox.screen(p1).status)
		Support.press(rig, p1, "Bank")
		local after = Support.countdown(p1)
		check(after ~= nil, "no countdown after Bank")
		-- The press also lets 0.2 s pass, and the display rounds up.
		expect((after :: number) - (before :: number)):toBeGreaterThan(13)
		expect((after :: number) - (before :: number)):toBeLessThan(16.5)

		local oppLine = ""
		for line in string.gmatch(FakeRoblox.screen(p2).board, "[^\n]+") do
			if string.sub(line, 1, 3) == "OPP" then
				oppLine = line
			end
		end
		expect(string.find(oppLine, "bank 15s", 1, true) ~= nil):toBe(true)
		noErrors(rig)
	end)
end)

describe("e2e: lobby", function()
	it("starts a match from a private code and rejects an unknown one", function()
		local rig = newRig(16)
		local p1, p2, p3 =
			Support.join(rig, "Player1"), Support.join(rig, "Player2"), Support.join(rig, "Player3")
		Support.press(rig, p1, "Host")
		local code = string.match(FakeRoblox.screen(p1).status, "your code (%w+)")
		check(
			code ~= nil and #code == 5,
			"no 5-character code in the status: " .. FakeRoblox.screen(p1).status
		)

		Support.type(rig, p3, "join ZZZZZ")
		expect(Support.said(rig, p3, "rejected Join: NoSuchCode")):toBe(true)

		Support.type(rig, p2, `join {code}`)
		check(Support.untilStatus(rig, p1, "Select", 5), "no match started for the host")
		check(Support.untilStatus(rig, p2, "Select", 5), "no match started for the joiner")
		expect(#Support.outputLines(rig.world.server, "started (")):toBe(1)
		noErrors(rig)
	end)
end)

describe("e2e: events", function()
	it("shows the week's event, and a host can play a private match without events (D-027)", function()
		local rig = newRig(19)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.queueMatch(rig, p1, p2)
		check(Support.autoUntil(rig, { p1, p2 }, "Week 2 Plan · Input", 400), "never reached week 2")
		expect(Support.shows(p1, "Event this week: ")):toBe(true)
		noErrors(rig)

		rig = newRig(20)
		p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.type(rig, p1, "host noevents")
		local code = string.match(FakeRoblox.screen(p1).status, "your code (%w+)")
		check(code ~= nil, "no code in the status: " .. FakeRoblox.screen(p1).status)
		Support.type(rig, p2, `join {code}`)
		check(Support.autoUntil(rig, { p1, p2 }, "Week 2 Plan · Input", 400), "never reached week 2")
		expect(Support.shows(p1, "Event this week")):toBe(false)
		expect(Support.shows(p2, "Event this week")):toBe(false)
		noErrors(rig)
	end)
end)

describe("e2e: disconnect", function()
	it("forfeits a match when the opponent leaves for good", function()
		local rig = newRig(17)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.queueMatch(rig, p1, p2)
		Support.press(rig, p1, "Autoplay")
		check(
			Support.untilStatus(rig, p1, "Week 1 Plan · Input", 400),
			"never reached the Week 1 Plan input"
		)

		Support.leave(rig, p2)
		Support.run(rig, 1)
		expect(Support.said(rig, p1, "Opponent disconnected")):toBe(true)
		check(
			Support.runUntil(rig, finished(rig, p1), MATCH_LIMIT),
			"the match never ended after the disconnect"
		)
		expect(string.find(FakeRoblox.screen(p1).board, "YOU WON (Forfeit)", 1, true) ~= nil):toBe(true)
		noErrors(rig)
	end)
end)

describe("e2e: hostile clients", function()
	it("rejects bad payloads without script errors and keeps the match going", function()
		local rig = newRig(18)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.queueMatch(rig, p1, p2)
		local matchId = string.match(FakeRoblox.screen(p1).status, "^(%S+)")
		check(matchId ~= nil, "no match id in the status")

		local junk = {}
		for k = 1, 1000 do
			junk[k] = { kind = "Rally", state = "OH", issue = "Jobs", support = k }
		end
		local cases: { { name: string, payload: any } } = {
			{
				name = "wrong matchId",
				payload = { op = "Submit", matchId = "m999", step = 1, input = { actions = {} } },
			},
			{
				name = "stale step",
				payload = { op = "Submit", matchId = matchId, step = 0, input = { actions = {} } },
			},
			{
				name = "1000-entry junk",
				payload = { op = "Submit", matchId = matchId, step = 1, input = junk },
			},
			{
				name = "function value",
				payload = { op = "Submit", matchId = matchId, step = 1, input = function() end },
			},
			{ name = "unknown op", payload = { op = "Teleport", matchId = matchId, step = 1 } },
		}
		for _, case in cases do
			local before = #Support.outputLines(rig.world.server, "rejected")
			Support.fire(rig, p1, case.payload)
			local lines = Support.outputLines(rig.world.server, "rejected")
			check(#lines > before, `{case.name}: the server logged no rejection`)
			check(
				string.sub(lines[#lines], 1, 5) == "WARN ",
				`{case.name}: the rejection is not a warn(): {lines[#lines]}`
			)
			check(
				#rig.world.errors == 0,
				`{case.name}: script error: {table.concat(rig.world.errors, " | ")}`
			)
		end
		-- Only the function value may trip the wire check.
		expect(#rig.world.wireWarnings):toBeGreaterThan(0)

		-- The match is still healthy: both players can lock Select and move on.
		Support.press(rig, p1, "Auto")
		Support.press(rig, p2, "Auto")
		check(Support.untilStatus(rig, p1, "MapReveal", 10), "the match stalled after the bad payloads")
		expect(#rig.world.errors):toBe(0)
	end)
end)

describe("e2e: rate limit", function()
	it("warns and replies once per window, then drops the rest quietly", function()
		local rig = newRig(22)
		local p1 = Support.join(rig, "Player1")
		-- 100 requests inside one simulated instant: 40 pass, 60 are over the limit.
		for _ = 1, 100 do
			FakeRoblox.fire(rig.world, p1, { op = "Resync" })
		end
		Support.run(rig, 0.5)
		expect(#Support.outputLines(rig.world.server, "RateLimited")):toBe(1)
		local replies = 0
		for _, line in rig.history[p1] do
			if string.find(line, "RateLimited", 1, true) then
				replies += 1
			end
		end
		expect(replies):toBe(1)

		-- A window later the player is heard again, and told once more if still over.
		Support.run(rig, 11)
		for _ = 1, 100 do
			FakeRoblox.fire(rig.world, p1, { op = "Resync" })
		end
		Support.run(rig, 0.5)
		expect(#Support.outputLines(rig.world.server, "RateLimited")):toBe(2)
	end)
end)

describe("e2e: debug UI layout", function()
	it("has no size or truncation warnings at 1280x720", function()
		local rig = newRig(19, { x = 1280, y = 720 })
		local p1 = Support.join(rig, "Player1", { DebugText = true })
		Support.run(rig, 2)
		expect(#Support.outputLines(p1, "under 44px")):toBe(0)
		expect(#Support.outputLines(p1, "truncated")):toBe(0)
		expect(#Support.outputLines(p1, "debug UI sizes")):toBe(1)
	end)

	it("runs at 390x844 without script errors", function()
		local rig = newRig(20, { x = 390, y = 844 })
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 2)
		local warnings = 0
		for _, line in p1.log do
			if string.sub(line, 1, 5) == "WARN " then
				warnings += 1
			end
		end
		print(`390x844: {warnings} debug UI warning(s)`)
		expect(#rig.world.errors):toBe(0)
	end)
end)
