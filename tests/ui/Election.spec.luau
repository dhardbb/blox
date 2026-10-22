--!strict
-- The Election Night screen on the fake Roblox engine: it renders the "Election"
-- fixture offline (DebugScreen), calls states on the clock, ticks the EV
-- counters, shows the banner, and sends Skip. Also plays a live practice match to
-- election night. The fake layout is rough, so nothing here asserts pixels.

local process = require("@lune/process")

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Support = require("../e2e/Support")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local AUDIT_OK = "UI audit Election: 0 problem(s)"
local FULL_TIME = 50 -- s, past the 45 s stage

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

type Rig = { world: FakeRoblox.World, peer: FakeRoblox.Peer }

-- A client showing the fixture, `warmup` seconds after it started.
local function fixtureRig(screen: { x: number, y: number }?, warmup: number?): Rig
	local world = FakeRoblox.world({ root = process.cwd, seed = 3, screen = screen })
	local peer = FakeRoblox.join(world, "P", { DebugScreen = "Election" })
	FakeRoblox.run(world, warmup or 1)
	return { world = world, peer = peer }
end

local function noErrors(world: FakeRoblox.World)
	check(#world.errors == 0, "script errors: " .. table.concat(world.errors, " | "))
end

local function text(peer: FakeRoblox.Peer, name: string): string
	local inst = FakeRoblox.find(peer, name)
	check(inst ~= nil, `no element named {name}`)
	return tostring(inst.Text)
end

local function number(peer: FakeRoblox.Peer, name: string): number
	local n = tonumber(text(peer, name))
	check(n ~= nil, `{name} is not a number: {text(peer, name)}`)
	return n :: number
end

local function visible(peer: FakeRoblox.Peer, name: string): boolean
	local inst = FakeRoblox.find(peer, name)
	check(inst ~= nil, `no element named {name}`)
	return inst.Visible ~= false
end

local function feedLines(peer: FakeRoblox.Peer): number
	local feed = FakeRoblox.find(peer, "Feed")
	check(feed ~= nil, "no Feed")
	local count = 0
	for _, child in feed:GetChildren() do
		if string.sub(child.Name, 1, 4) == "Line" then
			count += 1
		end
	end
	return count
end

local expected = Fixtures.payload(Config.defaults, "Election")
local election = expected.view.election
assert(election, "the Election fixture has no election result")

describe("Election screen", function()
	it("mounts cleanly and passes the UI audit", function()
		local rig = fixtureRig()
		FakeRoblox.run(rig.world, 1)
		noErrors(rig.world)
		expect(#Support.outputLines(rig.peer, AUDIT_OK)):toBe(1)
		expect(#Support.outputLines(rig.peer, "WARN [270] UI audit Election")):toBe(0)
		for _, name in { "SkipButton", "EvYou", "EvThem", "Feed", "Banner" } do
			check(FakeRoblox.find(rig.peer, name) ~= nil, `missing element {name}`)
		end
	end)

	it("starts with nothing called and no banner", function()
		local rig = fixtureRig(nil, 0.3)
		expect(number(rig.peer, "EvYou")):toBe(0)
		expect(number(rig.peer, "EvThem")):toBe(0)
		expect(feedLines(rig.peer)):toBe(0)
		expect(visible(rig.peer, "BannerPanel")):toBe(false)
	end)

	it("shows partial totals halfway through", function()
		local rig = fixtureRig()
		FakeRoblox.run(rig.world, 19)
		local you, them = number(rig.peer, "EvYou"), number(rig.peer, "EvThem")
		expect(you + them > 0):toBe(true)
		expect(you + them < election.ev[1] + election.ev[2]):toBe(true)
		expect(you <= election.ev[1]):toBe(true)
		expect(them <= election.ev[2]):toBe(true)
		local lines = feedLines(rig.peer)
		expect(lines > 0):toBe(true)
		expect(lines < #election.results):toBe(true)
		expect(visible(rig.peer, "BannerPanel")):toBe(false)
		noErrors(rig.world)
	end)

	it("calls every state, ends on the final totals and names the winner", function()
		local rig = fixtureRig()
		FakeRoblox.run(rig.world, FULL_TIME)
		noErrors(rig.world)
		expect(number(rig.peer, "EvYou")):toBe(election.ev[1])
		expect(number(rig.peer, "EvThem")):toBe(election.ev[2])
		expect(feedLines(rig.peer)):toBe(#election.results)
		expect(visible(rig.peer, "BannerPanel")):toBe(true)
		local banner = text(rig.peer, "Banner")
		local loser = if election.winner == 1 then 2 else 1
		local score = `{election.ev[election.winner]}–{election.ev[loser]}`
		check(string.find(banner, score, 1, true) ~= nil, `banner "{banner}" lacks the score {score}`)
		check(string.find(banner, " wins ", 1, true) ~= nil, `banner "{banner}" does not say who won`)
	end)

	it("only ever counts up", function()
		local rig = fixtureRig()
		local lastYou, lastThem, lastLines = 0, 0, 0
		for _ = 1, 100 do
			FakeRoblox.run(rig.world, 0.5)
			local you, them, lines =
				number(rig.peer, "EvYou"), number(rig.peer, "EvThem"), feedLines(rig.peer)
			check(you >= lastYou and them >= lastThem and lines >= lastLines, "a counter went backwards")
			lastYou, lastThem, lastLines = you, them, lines
		end
		expect(lastLines):toBe(#election.results)
	end)

	it("sends Skip and then waits for the opponent", function()
		local rig = fixtureRig()
		expect(#Support.outputLines(rig.peer, "DEBUG_UI skip")):toBe(0)
		FakeRoblox.press(rig.world, rig.peer, "SkipButton")
		FakeRoblox.run(rig.world, 0.5)
		expect(#Support.outputLines(rig.peer, "DEBUG_UI skip")):toBe(1)
		check(
			string.find(text(rig.peer, "SkipButton"), "Waiting for opponent to skip", 1, true) ~= nil,
			`skip button says "{text(rig.peer, "SkipButton")}"`
		)
		-- A second press does not send again.
		FakeRoblox.press(rig.world, rig.peer, "SkipButton")
		expect(#Support.outputLines(rig.peer, "DEBUG_UI skip")):toBe(1)
		noErrors(rig.world)
	end)

	it("explains a tiebreak", function()
		local rig = fixtureRig()
		local storePath = `{rig.world.root}/src/client/Store.luau`
		local Store = rig.peer.modules[storePath]
		check(Store ~= nil, "could not reach the client Store")
		local payload = table.clone(Store.get().payload)
		local tied = table.clone(election)
		tied.ev = { 269, 269 }
		tied.statesWon = { 26, 24 }
		tied.winner = 1
		tied.decidedBy = "States"
		local view = table.clone(payload.view)
		view.election = tied
		payload.view = view
		rig.world.current = rig.peer
		Store.setPayload(payload)
		rig.world.current = nil
		FakeRoblox.run(rig.world, FULL_TIME)
		noErrors(rig.world)
		check(string.find(text(rig.peer, "Banner"), "269–269", 1, true) ~= nil, "banner lacks 269–269")
		local note = text(rig.peer, "Tiebreak")
		check(string.find(note, "more states", 1, true) ~= nil, `tiebreak note says "{note}"`)
		expect(visible(rig.peer, "Tiebreak")):toBe(true)
	end)

	it("mounts in phone portrait without errors", function()
		local rig = fixtureRig({ x = 390, y = 844 })
		FakeRoblox.run(rig.world, 1)
		noErrors(rig.world)
		expect(#Support.outputLines(rig.peer, AUDIT_OK)):toBe(1)
		FakeRoblox.run(rig.world, FULL_TIME)
		noErrors(rig.world)
		expect(number(rig.peer, "EvYou")):toBe(election.ev[1])
		expect(number(rig.peer, "EvThem")):toBe(election.ev[2])
	end)

	it("shows up in a live practice match and passes the audit", function()
		local rig = Support.new(process.cwd, 11)
		local p1 = Support.join(rig, "Player1")
		Support.press(rig, p1, "Practice")
		Support.run(rig, 1)
		Support.press(rig, p1, "Autoplay")
		check(Support.untilStatus(rig, p1, "Election", 400), "the election phase never began")
		-- Autoplay would skip election night within 0.3 s, before the router's
		-- 0.5 s layout audit; switch it off to let the screen stay up.
		Support.type(rig, p1, "autoplay off")
		check(Support.untilStatus(rig, p1, "Election · Show", 30), "election night never began")
		Support.run(rig, 2)
		noErrors(rig.world)
		expect(#Support.outputLines(p1, AUDIT_OK)):toBe(1)
		expect(#Support.outputLines(p1, "WARN [270] UI audit Election")):toBe(0)
	end)
end)
