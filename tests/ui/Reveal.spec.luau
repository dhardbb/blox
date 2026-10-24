--!strict
-- The weekly reveal's three beats (polish WP-2, docs/UI-STYLE.md §2.7, D-053):
-- "Both plans are in" with who goes first, then the actions land one beat at a
-- time with the trailing player's first, then the new polls, the header's
-- score tallying up step by step. Debates have their own screen (D-072,
-- tests/ui/Debate.spec). Each case checks end states and the cues played,
-- never timings of a tween.

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local RevealSteps = require("@ui/RevealSteps")
local Rig = require("./Rig")
local Test = require("@testlib/Test")
local Words = require("@ui/Words/Reveal")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local function count(list: { string }, name: string): number
	local n = 0
	for _, entry in list do
		if entry == name then
			n += 1
		end
	end
	return n
end

-- From the week-3 plan (so the reveal knows the polls before the week), the
-- Resolve payload starting now.
local function resolveRig(options: Rig.FixtureOptions?): (FakeRoblox.World, FakeRoblox.Peer, any)
	local world, peer = Rig.fixture("Plan", nil, options)
	local before = Rig.payloadOf(world, peer).view
	local payload = Fixtures.payload(Config.defaults, "Resolve")
	local shift = world.clock - payload.stageStart
	payload.stageStart += shift
	payload.deadline += shift
	world.current = peer
	Rig.storeOf(world, peer).setPayload(payload)
	world.current = nil
	FakeRoblox.run(world, 0.2)
	return world, peer, before
end

local function shown(peer: FakeRoblox.Peer, name: string): boolean
	return Rig.shown(Rig.need(peer, "Campaign", name), "Campaign")
end

local function lines(peer: FakeRoblox.Peer, prefix: string): number
	local n = 0
	for k = 1, 6 do
		local line = Rig.findIn(peer, "Campaign", `{prefix}{k}`)
		if line and line.Visible ~= false and tostring(line.Text) ~= "" then
			n += 1
		end
	end
	return n
end

describe("Reveal: three beats", function()
	it("opens on Both plans are in and says who goes first", function()
		local world, peer, before = resolveRig()
		check(shown(peer, "RevealIntro"), "no Both plans are in")
		expect(Rig.textOf(peer, "Campaign", "RevealIntro")):toBe("Both plans are in")
		local first, trails = Words.revealFirst(before)
		local head = Rig.need(peer, "Campaign", "ThemHead"):FindFirstChild("Label")
		local them = string.match(tostring(head.Text), "^(.-)'s week$") or "?"
		expect(Rig.textOf(peer, "Campaign", "RevealOrder")):toBe(Words.orderLine(before, first, trails, them))
		check(not shown(peer, "RevealGroups"), "the actions show during the intro")
		expect(Rig.textOf(peer, "Campaign", "BarStatus")):toBe("Both plans are in")
		expect(count(Rig.sounds(peer), "whoosh")):toBe(1)
		Rig.noErrors(world)
	end)

	it("lands the trailing player's actions first", function()
		local world, peer, before = resolveRig()
		local first = Words.revealFirst(before)
		FakeRoblox.run(world, 0.4) -- past the 0.5 s intro: the first beat
		check(not shown(peer, "RevealIntro"), "the intro outstays its beat")
		local mine, theirs = lines(peer, "RevealLine"), lines(peer, "RevealThem")
		if first == before.you then
			check(mine > 0 and theirs == 0, `you trail, yet {mine} of yours and {theirs} of theirs`)
		else
			check(theirs > 0 and mine == 0, `they trail, yet {mine} of yours and {theirs} of theirs`)
		end
		Rig.noErrors(world)
	end)

	it("pops each landing beat and ends on the new polls", function()
		local world, peer = resolveRig()
		FakeRoblox.run(world, 7)
		local sounds = Rig.sounds(peer)
		check(count(sounds, "planAdd") >= 2, `only {count(sounds, "planAdd")} landing pops`)
		check(Rig.textOf(peer, "Campaign", "RevealSummary") ~= "", "the reveal never finished")
		check(lines(peer, "RevealLine") > 0 and lines(peer, "RevealThem") > 0, "a side is missing")
		Rig.noErrors(world)
	end)

	it("ends the same with reduced motion", function()
		local world, peer = resolveRig()
		local calmWorld, calmPeer = resolveRig({ reducedMotion = true })
		FakeRoblox.run(world, 7)
		FakeRoblox.run(calmWorld, 7)
		for _, name in { "RevealSummary", "RevealLine1", "RevealThem1", "RevealFlip1", "RevealTitle" } do
			expect(Rig.textOf(calmPeer, "Campaign", name)):toBe(Rig.textOf(peer, "Campaign", name))
		end
		Rig.noErrors(calmWorld)
	end)
end)

describe("Reveal: a running tally (D-063)", function()
	-- The score in the header, as numbers.
	local function score(peer: FakeRoblox.Peer): (number, number)
		return tonumber(Rig.textOf(peer, "Campaign", "YouVotes")) or -1,
			tonumber(Rig.textOf(peer, "Campaign", "ThemVotes")) or -1
	end

	-- When step k is on screen: the reveal's pace for this payload (Reveal.tickResolve).
	local function stepTime(payload: any, steps: number, k: number): number
		local window = payload.deadline - payload.stageStart - 2 - 0.5
		local interval = math.clamp(window / steps, 0.25, 0.8)
		return 0.5 + (k - 1) * interval + interval / 2
	end

	it("moves the header's score with each step and lands on the new polls", function()
		local world, peer, before = resolveRig({ reducedMotion = true })
		local payload = Rig.payloadOf(world, peer)
		local view = payload.view
		local them = 3 - view.you
		local tally = RevealSteps.build(Config.defaults, before, view, payload.events)
		local steps = tally.steps
		-- The intro: still the week's start, not the result.
		local mine, theirs = score(peer)
		expect(mine):toBe(before.projectedEV[view.you])
		expect(theirs):toBe(before.projectedEV[them])
		local start = payload.stageStart
		local changedMidway = false
		for k = 1, #steps - 1 do
			FakeRoblox.run(world, math.max(0, start + stepTime(payload, #steps, k) - world.clock))
			expect(Rig.textOf(peer, "Campaign", "BarStatus")):toBe(`Results · {k} of {#steps}`)
			mine, theirs = score(peer)
			expect(mine):toBe(steps[k].ev[view.you])
			expect(theirs):toBe(steps[k].ev[them])
			if mine ~= before.projectedEV[view.you] or theirs ~= before.projectedEV[them] then
				changedMidway = true
			end
			check(not shown(peer, "RevealPolls"), `the new polls show at step {k}`)
			local flip = steps[k].flips[1]
			if flip then
				local head = Rig.need(peer, "Campaign", "ThemHead"):FindFirstChild("Label")
				local rival = string.match(tostring(head.Text), "^(.-)'s week$") or "?"
				local now = Rig.textOf(peer, "Campaign", "NowText")
				check(
					Rig.contains(now, Words.leaderArrow(view, flip, rival)),
					`step {k} hides its flip: {now}`
				)
			end
			expect(Rig.textOf(peer, "Campaign", "RevealSummary")):toBe("")
		end
		check(changedMidway, "the score never moved before the polls settled")
		FakeRoblox.run(world, 7)
		mine, theirs = score(peer)
		expect(mine):toBe(view.projectedEV[view.you])
		expect(theirs):toBe(view.projectedEV[them])
		check(Rig.textOf(peer, "Campaign", "RevealSummary") ~= "", "the reveal never finished")
		-- The last step reads as the polls updating: its stamp, what they shifted, its header line.
		check(shown(peer, "RevealPolls"), "no New polls are in stamp")
		expect(Rig.textOf(peer, "Campaign", "RevealPollsStamp")):toBe(Words.SETTLE)
		expect(Rig.textOf(peer, "Campaign", "RevealPollsLine")):toBe(Words.pollShift(#steps[#steps].flips))
		expect(Rig.textOf(peer, "Campaign", "NowText")):toBe(Words.SETTLE)
		-- The estimates are explained once, behind Why?.
		expect(Rig.textOf(peer, "Campaign", "RevealEstimate")):toBe(Words.ESTIMATE_NOTE)
		check(not shown(peer, "RevealEstimate"), "the estimate line shows before Why?")
		Rig.noErrors(world)
	end)

	it("lands on the same numbers when both players skip", function()
		local world, peer = resolveRig({ reducedMotion = true })
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		-- Both skipped: the server ends the stage early (TIMER_RESOLVE_SKIPPED).
		payload.deadline = payload.stageStart + Config.defaults.TIMER_RESOLVE_SKIPPED
		Rig.push(world, peer, payload)
		FakeRoblox.run(world, Config.defaults.TIMER_RESOLVE_SKIPPED)
		local view = payload.view
		local mine, theirs = score(peer)
		expect(mine):toBe(view.projectedEV[view.you])
		expect(theirs):toBe(view.projectedEV[3 - view.you])
		check(Rig.textOf(peer, "Campaign", "RevealSummary") ~= "", "the skipped reveal never finished")
		Rig.noErrors(world)
	end)
end)
