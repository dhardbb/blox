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
local PHONE = { x = 844, y = 390 }
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

	it("mounts in portrait without errors", function()
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

describe("Election screen: style v2 (WP-C)", function()
	-- The first close state after the first call (the screen builds suspense before it).
	local function closeAt(): number?
		for k, result in election.results do
			if result.margin < 2 and k > 1 then
				return k
			end
		end
		return nil
	end

	it("spotlights the latest call in votes and points, by first name", function()
		local rig = fixtureRig()
		FakeRoblox.run(rig.world, 19)
		local label = tostring(inScreen(rig.peer, "SpotLabel").Text)
		local state = tostring(inScreen(rig.peer, "SpotState").Text)
		local call = tostring(inScreen(rig.peer, "SpotCall").Text)
		check(label == "JUST CALLED" or label == "TOO CLOSE TO CALL", `spotlight label "{label}"`)
		check(string.find(state, " votes", 1, true) ~= nil, `spotlight state "{state}"`)
		if label == "JUST CALLED" then
			check(string.find(call, "Called for ", 1, true) ~= nil, `spotlight call "{call}"`)
			check(string.find(call, " points", 1, true) ~= nil, `spotlight call "{call}"`)
		end
		check(string.find(state .. call, " EV", 1, true) == nil, "the spotlight says EV")
		noErrors(rig.world)
	end)

	it("builds suspense before a close call", function()
		local k = closeAt()
		check(k ~= nil, "the fixture has no close state after the first call")
		local rig = fixtureRig()
		local seen = false
		for _ = 1, 200 do
			FakeRoblox.run(rig.world, 0.25)
			if tostring(inScreen(rig.peer, "SpotLabel").Text) == "TOO CLOSE TO CALL" then
				seen = true
				local state = tostring(inScreen(rig.peer, "SpotState").Text)
				check(string.find(state, "…", 1, true) ~= nil, `suspense state "{state}"`)
				break
			end
		end
		check(seen, "never showed Too close to call")
		noErrors(rig.world)
	end)

	it("writes feed rows as state and votes over the call, marked as data colors", function()
		local rig = fixtureRig()
		FakeRoblox.run(rig.world, FULL_TIME)
		local first = election.results[1]
		local line = inScreen(rig.peer, "Line1")
		expect(line:GetAttribute("DataColor")):toBe(true)
		local state = line:FindFirstChild("State", true)
		check(
			state ~= nil and string.find(tostring(state.Text), " votes", 1, true) ~= nil,
			"row has no votes"
		)
		local call = tostring(line:FindFirstChild("Text", true).Text)
		if first.winner > 0 then
			check(string.find(call, " points", 1, true) ~= nil, `row call "{call}"`)
		end
		noErrors(rig.world)
	end)

	it("uses first names in portrait and full names at 16:9 and on a landscape phone", function()
		local wide = fixtureRig(nil)
		local phone = fixtureRig({ x = 390, y = 844 })
		local landscape = fixtureRig(PHONE)
		local long = tostring(inScreen(landscape.peer, "YouSide"):FindFirstChild("Name").Text)
		check(string.find(long, " ", 1, true) ~= nil, `landscape phone name "{long}" is not the full name`)
		noErrors(landscape.world)
		local full = tostring(inScreen(wide.peer, "YouSide"):FindFirstChild("Name").Text)
		local short = tostring(inScreen(phone.peer, "YouSide"):FindFirstChild("Name").Text)
		check(string.find(full, " ", 1, true) ~= nil, `wide name "{full}" is not the full name`)
		check(string.find(short, " ", 1, true) == nil, `phone name "{short}" is not a first name`)
		check(string.sub(full, 1, #short) == short, `"{short}" is not the start of "{full}"`)
		noErrors(wide.world)
		noErrors(phone.world)
	end)

	it("shows the election-night coach tip once, above the calls", function()
		local rig = fixtureRig()
		FakeRoblox.run(rig.world, 10)
		local tip = inScreen(rig.peer, "CoachTip")
		expect(tip:GetAttribute("TipId")):toBe("election.night")
		expect(tip.Parent.Name):toBe("Feed")
		noErrors(rig.world)
	end)
end)

describe("Election screen: the show (polish WP-2)", function()
	local Rig = require("./Rig")
	local stage = Config.defaults.TIMER_ELECTION
	local need = Config.defaults.EV_TO_WIN

	local function schedule(rig: Rig): ({ number }, { [number]: boolean }, number?)
		local Election = FakeRoblox.require(rig.world, rig.peer, "src/client/Screens/Election.luau")
		local ends, slow = Election.schedule(election.results, need, stage)
		return ends, slow, Election.tippingCall(election.results, need)
	end

	-- Calls made so far: the feed, plus the one the spotlight shows (not in the feed).
	local function callsShown(peer: FakeRoblox.Peer): number
		local lines = feedLines(peer)
		local spot = inScreen(peer, "Spotlight")
		local label = tostring(inScreen(peer, "SpotLabel").Text)
		local waiting = label == "TOO CLOSE TO CALL"
			or label == "STILL COUNTING"
			or label == "POLLS HAVE CLOSED"
		if spot.Visible ~= false and not waiting then
			lines += 1
		end
		return lines
	end

	it("calls the safe states fast and the last 8 and the tipping state slowly", function()
		local rig = fixtureRig()
		local ends, slow, tipping = schedule(rig)
		local n = #election.results
		expect(#ends):toBe(n)
		expect(n):toBe(51)
		check(ends[n] <= stage - 5 + 1e-6, `the last call is at {ends[n]} s, past the end buffer`)
		for k = n - 7, n do
			check(slow[k] == true, `call {k} of the last 8 is not slow`)
		end
		check(tipping ~= nil and slow[tipping :: number] == true, "the tipping call is not slow")
		local fastBeat, fastCount = nil, 0
		for k = 1, n do
			local beat = ends[k] - (if k > 1 then ends[k - 1] else 0)
			check(beat > 0, `call {k} does not come after call {k - 1}`)
			if slow[k] then
				check(math.abs(beat - 1.2) < 1e-6, `slow call {k} takes {beat} s`)
			else
				fastCount += 1
				fastBeat = fastBeat or beat
				check(math.abs(beat - (fastBeat :: number)) < 1e-6, `fast call {k} takes {beat} s`)
			end
		end
		-- The quick calls take 60 % of the stage between them.
		check(
			math.abs((fastBeat :: number) * fastCount - 0.6 * stage) < 1e-6,
			"the quick calls are off the curve"
		)
		Rig.noErrors(rig.world)
	end)

	it("squeezes the curve into a short stage", function()
		local rig = fixtureRig()
		local Election = FakeRoblox.require(rig.world, rig.peer, "src/client/Screens/Election.luau")
		local ends = Election.schedule(election.results, need, 12)
		check(ends[#ends] <= 12 - 5 + 1e-6, `the last call is at {ends[#ends]} s of a 12 s stage`)
	end)

	it("makes the calls on the clock, every tick, all 51 before the deadline", function()
		local rig = fixtureRig(nil, 0)
		local ends = schedule(rig)
		local start = storeOf(rig).get().payload.stageStart
		local deadline = storeOf(rig).get().payload.deadline
		local last = 0
		while rig.world.clock < deadline - 0.5 do
			FakeRoblox.run(rig.world, 0.25)
			local position = rig.world.clock - start
			-- The screen ticks every 0.25 s, so it may be one tick behind the clock.
			local due, behind = 0, 0
			for k, finish in ends do
				if finish <= position + 1e-6 then
					due = k
				end
				if finish <= position - 0.25 - 1e-6 then
					behind = k
				end
			end
			local made = callsShown(rig.peer)
			check(made >= behind and made <= due, `{made} calls at {position} s, want {behind} to {due}`)
			check(made >= last, "a call was taken back")
			last = made
		end
		expect(last):toBe(#election.results)
		expect(feedLines(rig.peer)):toBe(#election.results)
		Rig.noErrors(rig.world)
	end)

	it("never shows the newest call in the spotlight and the feed at once", function()
		local rig = fixtureRig(nil, 0)
		for _ = 1, 180 do
			FakeRoblox.run(rig.world, 0.25)
			local label = tostring(inScreen(rig.peer, "SpotLabel").Text)
			if inScreen(rig.peer, "Spotlight").Visible ~= false and label ~= "TOO CLOSE TO CALL" then
				local state = tostring(inScreen(rig.peer, "SpotState").Text)
				for _, row in inScreen(rig.peer, "Feed"):GetChildren() do
					local rowState = row:FindFirstChild("State", true)
					check(
						rowState == nil or tostring(rowState.Text) ~= state,
						`{state} is in the spotlight and the feed`
					)
				end
			end
		end
		-- At the end the spotlight steps aside and the feed has every call.
		expect(inScreen(rig.peer, "Spotlight").Visible):toBe(false)
		expect(feedLines(rig.peer)):toBe(#election.results)
		Rig.noErrors(rig.world)
	end)

	it("plays one call per state, higher toward 270, and flashes 270 once", function()
		local rig = fixtureRig(nil, 0)
		FakeRoblox.run(rig.world, FULL_TIME)
		local calls, flips = 0, 0
		local pitches: { number } = {}
		local world: any = rig.world
		for _, entry in world.sounds do
			if entry.name == "call" then
				calls += 1
				table.insert(pitches, entry.speed)
			elseif entry.name == "flip" then
				flips += 1
			end
		end
		expect(calls):toBe(#election.results)
		expect(flips):toBe(1)
		-- Jitter is ±5 %, the rise 0.9 -> 1.2: the last call is clearly higher.
		check(pitches[#pitches] > pitches[1] * 1.15, "the call pitch does not rise")
		-- "Results in" never ticks: it is not a deadline to beat.
		expect(#Rig.sounds(rig.peer) > 0 and table.find(Rig.sounds(rig.peer), "tick") == nil):toBe(true)
		Rig.noErrors(rig.world)
	end)

	it("says who reaches 270 on the tipping call", function()
		local rig = fixtureRig(nil, 0)
		local seen = false
		-- Watch the whole show: the tipping call can come late (it is one of the slow calls).
		for _ = 1, 10 * FULL_TIME do
			FakeRoblox.run(rig.world, 0.1)
			local label = tostring(inScreen(rig.peer, "SpotLabel").Text)
			if string.find(label, "REACHES 270", 1, true) then
				seen = true
				break
			end
		end
		-- The fixture's tipping call is the last one: the banner takes over at once,
		-- so look for the line itself having been written at some point instead.
		local _, _, tipping = schedule(rig)
		check(seen or tipping == #election.results, "never said who reached 270")
		Rig.noErrors(rig.world)
	end)

	it("lands on the same end state with reduced motion", function()
		local world = FakeRoblox.world({ root = process.cwd, seed = 3 })
		world.reducedMotion = true
		local peer = FakeRoblox.join(world, "P", { DebugScreen = "Election" })
		FakeRoblox.run(world, FULL_TIME)
		local rig = { world = world, peer = peer }
		noErrors(world)
		expect(number(peer, "EvYou")):toBe(election.ev[1])
		expect(number(peer, "EvThem")):toBe(election.ev[2])
		expect(feedLines(peer)):toBe(#election.results)
		check(#strictFindings(rig) == 0, "audit findings with reduced motion")
	end)
end)

describe("Election screen: front-page moments (D-056, WP-3)", function()
	-- The first instance named `name` in the screen, or nil.
	local function maybe(peer: FakeRoblox.Peer, name: string): any
		local holder = FakeRoblox.find(peer, "Election")
		for _, inst in holder:GetDescendants() do
			if inst.Name == name then
				return inst
			end
		end
		return nil
	end

	it("stamps CALLED on the spotlight in the winner's color, none while counting", function()
		local rig = fixtureRig(nil, 0)
		local Kit = FakeRoblox.require(rig.world, rig.peer, "src/client/UI/Kit.luau")
		local seenCall, seenSuspense = false, false
		for _ = 1, 450 do
			FakeRoblox.run(rig.world, 0.1)
			local label = tostring(inScreen(rig.peer, "SpotLabel").Text)
			local stamp = maybe(rig.peer, "CalledStamp")
			if label == "JUST CALLED" then
				seenCall = true
				check(stamp ~= nil, "a call with no CALLED stamp")
				-- The spotlight's stroke is the winner's color; the stamp matches it.
				local fill = stamp:FindFirstChild("Plate").BackgroundColor3
				local want = inScreen(rig.peer, "Spotlight"):FindFirstChildOfClass("UIStroke").Color
				check(
					want ~= Kit.colors.line and want ~= Kit.colors.accent,
					"the spotlight is not in a player color"
				)
				check(fill == want, "the CALLED stamp is not in the winner's color")
			elseif label == "TOO CLOSE TO CALL" then
				seenSuspense = true
				check(stamp == nil, "a CALLED stamp during the suspense")
				check(
					inScreen(rig.peer, "SpotLabel"):GetAttribute("Warn") == true,
					"orange suspense without Warn"
				)
			end
			if seenCall and seenSuspense then
				break
			end
		end
		check(seenCall and seenSuspense, "never saw both a call and the suspense")
		noErrors(rig.world)
	end)

	it("stamps 270! over the tick after the crossing, before the banner", function()
		local rig = fixtureRig(nil, 0)
		local seen = false
		for _ = 1, 600 do
			FakeRoblox.run(rig.world, 0.1)
			if maybe(rig.peer, "Stamp270") then
				seen = true
				-- The strip holds for the stamp (also when the crossing is the last call).
				check(visible(rig.peer, "Counters"), "the banner hid the 270! stamp at once")
				check(not visible(rig.peer, "Goal"), "270 TO WIN peeks out under the stamp")
				break
			end
		end
		check(seen, "no 270! stamp")
		FakeRoblox.run(rig.world, FULL_TIME)
		expect(visible(rig.peer, "BannerPanel")):toBe(true)
		expect(feedLines(rig.peer)):toBe(#election.results)
		noErrors(rig.world)
	end)

	it("shows the 270! stamp at once with reduced motion", function()
		local world = FakeRoblox.world({ root = process.cwd, seed = 3 })
		world.reducedMotion = true
		local peer = FakeRoblox.join(world, "P", { DebugScreen = "Election" })
		local seen = false
		for _ = 1, 600 do
			FakeRoblox.run(world, 0.1)
			local stamp = maybe(peer, "Stamp270")
			if stamp then
				seen = true
				local scale = stamp:FindFirstChild("MotionScale")
				check(scale == nil or scale.Scale == 1, "the stamp is still scaling under reduced motion")
				break
			end
		end
		check(seen, "no 270! stamp with reduced motion")
		noErrors(world)
	end)
end)
