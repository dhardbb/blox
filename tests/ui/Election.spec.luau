--!strict
-- The Election Night screen on the fake Roblox engine: it renders the "Election"
-- fixture offline (DebugScreen), calls states on the clock, ticks the EV
-- counters, shows the banner, and sends Skip. Also plays a live practice match to
-- election night. The UI overhaul (WP4) cases check the explicitly positioned
-- boxes the fake engine can measure: the clock, the feed above the action bar,
-- the opponent's skip, the 270 tick inside its bar, and a strict audit.

local process = require("@lune/process")

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Support = require("../e2e/Support")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local AUDIT_OK = "UI audit Election: 0 problem(s)"
local FULL_TIME = 50 -- s, past the 45 s stage
local PHONE = { x = 390, y = 844 }
local BAR_H = 84 -- px, Kit.BAR_H
local STRIP_H = 72 -- px, the counters strip

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

-- `name` inside the Election screen's holder (FakeRoblox.find searches the whole
-- PlayerGui, where other layers reuse names like "Timer").
local function inScreen(peer: FakeRoblox.Peer, name: string): any
	local holder = FakeRoblox.find(peer, "Election")
	check(holder ~= nil, "the Election screen is not mounted")
	for _, inst in holder:GetDescendants() do
		if inst.Name == name then
			return inst
		end
	end
	error(`the Election screen has no element {name}`, 0)
end

local function storeOf(rig: Rig): any
	local store = rig.peer.modules[`{rig.world.root}/src/client/Store.luau`]
	check(store ~= nil, "could not reach the client Store")
	return store
end

local function push(rig: Rig, payload: any)
	rig.world.current = rig.peer
	storeOf(rig).setPayload(payload)
	rig.world.current = nil
	FakeRoblox.run(rig.world, 0.3)
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in value do
		out[key] = deepCopy(child)
	end
	return out
end

-- Every audit finding off the map (the map is WP1's), with the PENDING list ignored.
local function strictFindings(rig: Rig): { string }
	local Audit = FakeRoblox.require(rig.world, rig.peer, "src/client/UI/Audit.luau")
	local out = {}
	for _, finding in Audit.check(FakeRoblox.find(rig.peer, "Election")) do
		if not finding.onMap then
			table.insert(out, `{finding.rule}: {finding.message}`)
		end
	end
	return out
end

local function bottom(inst: any): number
	return inst.AbsolutePosition.Y + inst.AbsoluteSize.Y
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
			string.find(text(rig.peer, "SkipButton"), "Waiting for opponent", 1, true) ~= nil,
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

describe("Election screen: UI overhaul (WP4)", function()
	for _, phone in { false, true } do
		local label = if phone then "on a phone" else "at 16:9"
		it(`passes the strict audit {label}, counting and at the end`, function()
			local rig = fixtureRig(if phone then PHONE else nil)
			FakeRoblox.run(rig.world, 10)
			local during = strictFindings(rig)
			check(#during == 0, "while counting: " .. table.concat(during, " | "))
			FakeRoblox.run(rig.world, FULL_TIME)
			local after = strictFindings(rig)
			check(#after == 0, "at the end: " .. table.concat(after, " | "))
			noErrors(rig.world)
		end)

		it(`keeps the whole feed above the action bar {label} (B6)`, function()
			local rig = fixtureRig(if phone then PHONE else nil)
			FakeRoblox.run(rig.world, FULL_TIME)
			local feed, side = inScreen(rig.peer, "Feed"), inScreen(rig.peer, "Side")
			check(
				bottom(feed) <= bottom(side) - BAR_H,
				`feed ends at {bottom(feed)}, the bar starts at {bottom(side) - BAR_H}`
			)
			local padding = feed:FindFirstChildOfClass("UIPadding")
			check(padding ~= nil and padding.PaddingBottom.Offset >= 8, "the feed has no bottom padding")
			local skip = inScreen(rig.peer, "SkipButton")
			check(skip:GetAttribute("PrimaryAction") == true, "Skip is not the pinned primary")
			check(skip.AbsolutePosition.Y >= bottom(feed), "Skip overlaps the feed")
		end)

		it(`has a 72 px counters strip with the 270 tick inside its bar {label} (B9)`, function()
			local rig = fixtureRig(if phone then PHONE else nil)
			expect(inScreen(rig.peer, "Counters").AbsoluteSize.Y):toBe(STRIP_H)
			local marker = inScreen(rig.peer, "Marker270")
			local box = marker.Parent
			check(marker.AbsolutePosition.Y >= box.AbsolutePosition.Y, "the tick pokes out above its bar")
			check(bottom(marker) <= bottom(box), "the tick pokes out below its bar")
			check(visible(rig.peer, "Goal"), "the 270 to win label is hidden")
		end)
	end

	it("counts down to the results in the header (B8)", function()
		local rig = fixtureRig()
		local Kit = FakeRoblox.require(rig.world, rig.peer, "src/client/UI/Kit.luau")
		local deadline = storeOf(rig).get().payload.deadline
		for _ = 1, 4 do
			FakeRoblox.run(rig.world, 3)
			local shown = tostring(inScreen(rig.peer, "Timer").Text)
			local now = rig.world.clock
			-- The screen ticks four times a second, so the clock may be one tick old.
			local fresh = `Results in {Kit.clock(deadline - now)}`
			local stale = `Results in {Kit.clock(deadline - now + 0.25)}`
			check(shown == fresh or shown == stale, `timer says "{shown}", want "{fresh}"`)
			check(inScreen(rig.peer, "Timer").Visible ~= false, "the timer is hidden")
		end
	end)

	it("shows when the opponent has skipped (B7)", function()
		local rig = fixtureRig()
		local base = storeOf(rig).get().payload
		local them = if base.you == 1 then 2 else 1
		local watching = deepCopy(base)
		watching.seats[them].skip = false
		push(rig, watching)
		expect(tostring(inScreen(rig.peer, "BarOpponent").Text)):toBe("Opponent: watching")
		local skipped = deepCopy(base)
		skipped.seats[them].skip = true
		push(rig, skipped)
		expect(tostring(inScreen(rig.peer, "BarOpponent").Text)):toBe("Opponent: skipped")
		-- Our own button is unaffected: we have not skipped.
		expect(tostring(inScreen(rig.peer, "SkipButton").Text)):toBe("Skip to results")
		noErrors(rig.world)
	end)

	it("says what is being called in the header and in the bar", function()
		local rig = fixtureRig()
		expect(tostring(inScreen(rig.peer, "Title").Text)):toBe("Election night")
		FakeRoblox.run(rig.world, 10)
		local status = tostring(inScreen(rig.peer, "CallStatus").Text)
		check(
			string.find(status, "states called", 1, true) ~= nil
				or string.find(status, "Too close", 1, true) ~= nil,
			`call status says "{status}"`
		)
		expect(tostring(inScreen(rig.peer, "BarStatus").Text)):toBe("Safe states first, closest last")
	end)
end)
