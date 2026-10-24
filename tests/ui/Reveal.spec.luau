--!strict
-- The weekly reveal's three beats (polish WP-2, docs/UI-STYLE.md §2.7, D-053):
-- "Both plans are in" with who goes first, then the actions land one beat at a
-- time with the trailing player's first, then the new polls. (Debates have their own screen since D-062.) The debate's rows
-- come in with their sound. Each case checks end states and the cues played,
-- never timings of a tween.

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
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
