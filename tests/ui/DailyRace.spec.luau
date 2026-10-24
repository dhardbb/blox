--!strict
-- The Daily Race on the fake engine (D-080): the Lobby's card (today's
-- candidate, the countdown, the streak, Play / Practice), its board sheet with
-- "You: #N", Play starting the real server's race straight on the issues step,
-- and the Results summary of a counted and a practice run. Strict audit 0 at
-- phone, iPad and desktop.

local Test = require("@testlib/Test")
local FakeRoblox = require("@testlib/FakeRoblox")
local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Fixtures = require("@ui/Fixtures")
local SimDaily = require("@sim/Daily")
local Rig = require("./Rig")

local describe, it, expect = Test.describe, Test.it, Test.expect

local check, need, tap, textOf = Rig.check, Rig.need, Rig.tap, Rig.textOf
local C = Config.defaults
local SIZES = { Rig.PHONE, { x = 1024, y = 768 }, { x = 1280, y = 720 } }

local function strictAudit(world: FakeRoblox.World, peer: FakeRoblox.Peer, screen: string): number
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	return Audit.run(FakeRoblox.find(peer, screen), screen, { strict = true })
end

local function setDaily(world: FakeRoblox.World, peer: FakeRoblox.Peer, info: any)
	world.current = peer
	Rig.storeOf(world, peer).setDaily(info)
	world.current = nil
	FakeRoblox.run(world, 0.3)
end

-- How many times the offline client (DEBUG_UI) sent `op`.
local function sentCount(peer: FakeRoblox.Peer, op: string): number
	return Rig.count(peer, `DEBUG_UI send {op}`)
end

local function today(): any
	return SimDaily.race(C, Fixtures.DAILY_DAY)
end

describe("Lobby: the Daily Race card (D-080)", function()
	it("shows today's candidate for everyone, the time left and the streak", function()
		local world, peer = Rig.fixture("Lobby", Rig.PHONE)
		setDaily(world, peer, Fixtures.daily({ now = world.clock }))
		local name = Candidates.profile(C, today().candidate).name
		expect(textOf(peer, "Lobby", "DailyWho")):toBe(`Everyone plays as {name} today`)
		expect(textOf(peer, "Lobby", "DailyTitle")):toBe("Daily Race · Sat, Oct 24")
		local info = textOf(peer, "Lobby", "DailyInfo")
		check(string.find(info, "5h 1", 1, true) ~= nil, `no countdown in "{info}"`)
		check(string.find(info, "3-day streak", 1, true) ~= nil, `no streak in "{info}"`)
		check(string.find(info, "Not played yet", 1, true) ~= nil, `no run line in "{info}"`)
		expect(textOf(peer, "Lobby", "DailyPlay")):toBe("Play today's race")
		expect(need(peer, "Lobby", "Portrait"):GetAttribute("Portrait") ~= nil):toBe(true)
		-- The countdown runs.
		FakeRoblox.run(world, 61)
		check(textOf(peer, "Lobby", "DailyInfo") ~= info, "the countdown did not move")
		Rig.noErrors(world)
	end)

	it("after today's run: the margin, and Play becomes practice", function()
		local world, peer = Rig.fixture("Lobby", Rig.PHONE)
		setDaily(world, peer, Fixtures.daily({ now = world.clock, played = true, margin = 62, you = 7 }))
		local info = textOf(peer, "Lobby", "DailyInfo")
		check(string.find(info, "Won by 62 today", 1, true) ~= nil, `no margin in "{info}"`)
		expect(textOf(peer, "Lobby", "DailyPlay")):toBe("Practice today's race")
		Rig.noErrors(world)
	end)

	it("opens the day's board: the top 50 by margin and You: #N", function()
		local world, peer = Rig.fixture("Lobby", Rig.PHONE)
		setDaily(world, peer, Fixtures.daily({ now = world.clock, played = true, margin = 184, you = 7 }))
		local before = sentCount(peer, "Daily")
		tap(world, peer, "Lobby", "DailyBoard")
		expect(sentCount(peer, "Daily")):toBe(before + 1)
		check(Rig.shown(need(peer, "Lobby", "DailySheet"), "Lobby"), "the sheet did not open")
		expect(textOf(peer, "Lobby", "DailyYou")):toBe("You: #7 · +184")
		check(Rig.findIn(peer, "Lobby", "DailyRow_50") ~= nil, "the sheet does not list 50 rows")
		expect(need(peer, "Lobby", "DailyRow_7"):GetAttribute("You")):toBe(true)
		expect(strictAudit(world, peer, "Lobby")):toBe(0)
		Rig.noErrors(world)
	end)

	it("says so when nobody has finished yet, or the board can't be read", function()
		local world, peer = Rig.fixture("Lobby", Rig.PHONE)
		setDaily(world, peer, Fixtures.daily({ now = world.clock, count = 0 }))
		tap(world, peer, "Lobby", "DailyBoard")
		expect(textOf(peer, "Lobby", "DailyStatus")):toBe(
			"Nobody has finished today's race yet. Be the first!"
		)
		setDaily(world, peer, Fixtures.daily({ now = world.clock, count = 0, status = "Unavailable" }))
		expect(textOf(peer, "Lobby", "DailyStatus")):toBe("Today's board is unavailable")
		Rig.noErrors(world)
	end)

	it("audits clean at phone, iPad and desktop", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Lobby", size)
			setDaily(world, peer, Fixtures.daily({ now = world.clock }))
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
			check(Rig.shown(need(peer, "Lobby", "DailyPlay"), "Lobby"), `Play is hidden at {size.x}x{size.y}`)
			check(need(peer, "Lobby", "DailyPlay").AbsoluteSize.Y >= 44, "Play is under 44 px")
			Rig.noErrors(world)
		end
	end)

	it("Play starts the real server's race on today's candidate, straight to the issues", function()
		local world, peer = Rig.practice(81)
		FakeRoblox.run(world, 1)
		local store = Rig.storeOf(world, peer)
		local info = store.get().daily
		check(info ~= nil, "the server sent no Daily message to the card")
		local race = SimDaily.race(C, SimDaily.dayOf(math.floor(world.clock)))
		expect(info.candidate):toBe(race.candidate)
		tap(world, peer, "Lobby", "DailyPlay")
		FakeRoblox.run(world, 1)
		check(FakeRoblox.find(peer, "Select") ~= nil, "the race did not start")
		local payload = Rig.payloadOf(world, peer)
		expect(payload.daily.counted):toBe(true)
		expect(payload.view.claims[race.candidate]):toBe(payload.you)
		-- Step 2 (the issues) at once: no candidate cards to pick from.
		check(Rig.shown(need(peer, "Select", "Issues"), "Select"), "the issues step is not showing")
		local first = string.match(Candidates.profile(C, race.candidate).name, "^(%S+)")
		expect(textOf(peer, "Select", "BarStatus")):toBe(`Daily Race: everyone is {first} today`)
		Rig.noErrors(world)
	end)
end)

describe("Results: the Daily Race summary (D-080)", function()
	local function over(world: FakeRoblox.World, peer: FakeRoblox.Peer, counted: boolean): string
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		payload.daily = { day = Fixtures.DAILY_DAY, counted = counted }
		Rig.push(world, peer, payload)
		return payload.matchId
	end

	it("a counted run: the margin, the rank today and the streak; Rematch is practice", function()
		local world, peer = Rig.fixture("Over", Rig.PHONE)
		local matchId = over(world, peer, true)
		expect(textOf(peer, "Results", "DailyLine")):toBe("Saving your run…")
		setDaily(
			world,
			peer,
			Fixtures.daily({
				now = world.clock,
				played = true,
				margin = 62,
				you = 7,
				run = { matchId = matchId, counted = true, margin = 62, forfeit = false, rank = 7 },
			})
		)
		expect(textOf(peer, "Results", "DailyLine")):toBe("You won by 62 votes.")
		expect(textOf(peer, "Results", "DailyMore")):toBe("Rank today: #7 · 3-day streak")
		expect(textOf(peer, "Results", "Rematch")):toBe("Rematch")
		expect(textOf(peer, "Results", "BarStatus")):toBe("Rematch plays today's race as practice.")
		tap(world, peer, "Results", "Rematch")
		expect(Rig.count(peer, "DEBUG_UI rematch")):toBe(1) -- the server starts today's race again (D-082)
		Rig.noErrors(world)
	end)

	it("a practice run says it does not count", function()
		local world, peer = Rig.fixture("Over", Rig.PHONE)
		local matchId = over(world, peer, false)
		setDaily(
			world,
			peer,
			Fixtures.daily({
				now = world.clock,
				played = true,
				margin = 62,
				run = { matchId = matchId, counted = false, margin = -30, forfeit = false },
			})
		)
		expect(textOf(peer, "Results", "DailyLine")):toBe("Practice run: you lost by 30 votes.")
		expect(textOf(peer, "Results", "DailyMore")):toBe("Only your first run counts. Today: won by 62.")
		Rig.noErrors(world)
	end)

	it("audits clean at phone, iPad and desktop", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Over", size)
			local matchId = over(world, peer, true)
			setDaily(
				world,
				peer,
				Fixtures.daily({
					now = world.clock,
					played = true,
					margin = 62,
					run = { matchId = matchId, counted = true, margin = 62, forfeit = false, rank = 7 },
				})
			)
			expect(strictAudit(world, peer, "Results")):toBe(0)
			Rig.noErrors(world)
		end
	end)
end)
