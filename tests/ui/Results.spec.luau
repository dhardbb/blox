--!strict
-- The Results screen on the fake Roblox engine: the rating line of this match
-- (v0.3.1 bug hunt). The UI overhaul (WP2) adds its Results specs here.

local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

describe("Results rating line", function()
	it("FakeRoblox finds descendants with FindFirstChild(name, true)", function()
		local _, peer = Rig.fixture("Over", nil)
		local screens = FakeRoblox.find(peer, "Screens")
		check(screens:FindFirstChild("RatingChange") == nil, "RatingChange is not a direct child")
		check(screens:FindFirstChild("RatingChange", true) ~= nil, "the recursive search found nothing")
		check(screens:FindFirstChild("NoSuchThing", true) == nil, "found a thing that does not exist")
	end)

	it("shows the rating change of this match", function()
		local world, peer = Rig.fixture("Over", nil)
		local store = Rig.storeOf(world, peer)
		local matchId = Rig.payloadOf(world, peer).matchId
		check(
			not Rig.shown(Rig.need(peer, "Results", "RatingChange"), "Results"),
			"the rating line shows early"
		)
		world.current = peer
		store.setRating({ matchId = matchId, before = 1000, after = 1016 })
		world.current = nil
		FakeRoblox.run(world, 0.3)
		expect(Rig.textOf(peer, "Results", "RatingChange")):toBe("Rating 1000 → 1016 (+16)")
		check(Rig.shown(Rig.need(peer, "Results", "RatingChange"), "Results"), "the rating line is hidden")
		Rig.noErrors(world)
	end)

	it("writes a loss with a minus sign", function()
		local world, peer = Rig.fixture("Over", nil)
		local matchId = Rig.payloadOf(world, peer).matchId
		world.current = peer
		Rig.storeOf(world, peer).setRating({ matchId = matchId, before = 1016, after = 1004 })
		world.current = nil
		FakeRoblox.run(world, 0.3)
		expect(Rig.textOf(peer, "Results", "RatingChange")):toBe("Rating 1016 → 1004 (-12)")
	end)

	it("ignores a change that belongs to an earlier match", function()
		local world, peer = Rig.fixture("Over", nil)
		world.current = peer
		Rig.storeOf(world, peer).setRating({ matchId = "an-earlier-match", before = 900, after = 920 })
		world.current = nil
		FakeRoblox.run(world, 0.3)
		check(
			not Rig.shown(Rig.need(peer, "Results", "RatingChange"), "Results"),
			"a stale rating change is shown"
		)
		expect(Rig.textOf(peer, "Results", "RatingChange")):toBe("")
		Rig.noErrors(world)
	end)
end)
