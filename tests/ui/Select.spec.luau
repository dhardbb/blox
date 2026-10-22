--!strict
-- The Select screen on the fake Roblox engine: the v0.3.1 bug-hunt cases
-- (auto-submit before the timer ends, the pre-pick, retrying a rejected lock-in,
-- the pinned footer). The UI overhaul (WP2) adds its Select specs here.

local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

describe("Select auto-submit before the timer ends", function()
	it("Select locks a complete, unlocked pick", function()
		local world, peer = Rig.practice(3)
		Rig.tap(world, peer, "Lobby", "Practice", 1)
		Rig.pickAll(world, peer)
		local calls = Rig.spySubmits(world, peer)
		Rig.waitFor(world, function()
			return Rig.payloadOf(world, peer).view.phase ~= "Select"
		end, 60, "the end of Select")
		local me = Rig.payloadOf(world, peer).view.players[1]
		expect(me.candidate):toBe("hale")
		expect(me.color):toBe("Teal")
		expect(#calls):toBe(1)
		Rig.noErrors(world)
	end)

	it("Select leaves an incomplete pick to the server", function()
		local world, peer = Rig.practice(3)
		Rig.tap(world, peer, "Lobby", "Practice", 1)
		Rig.tap(world, peer, "Select", "Candidate_hale")
		local calls = Rig.spySubmits(world, peer)
		Rig.waitFor(world, function()
			return Rig.payloadOf(world, peer).view.phase ~= "Select"
		end, 60, "the end of Select")
		expect(#calls):toBe(0)
		Rig.noErrors(world)
	end)

	it("Select sends the pre-pick as soon as the pick is complete", function()
		local world, peer = Rig.fixture("Select", nil)
		Rig.tap(world, peer, "Select", "Candidate_hale")
		Rig.tap(world, peer, "Select", "Color_Teal")
		Rig.tap(world, peer, "Select", "Issue_Jobs")
		Rig.tap(world, peer, "Select", "Issue_Health")
		expect(Rig.count(peer, "DEBUG_UI send PrePick")):toBe(0)
		Rig.tap(world, peer, "Select", "Issue_Schools")
		expect(Rig.count(peer, "DEBUG_UI send PrePick")):toBe(1)
		-- Locking the same pick does not send it again.
		Rig.tap(world, peer, "Select", "LockIn")
		expect(Rig.count(peer, "DEBUG_UI send PrePick")):toBe(1)
		expect(Rig.count(peer, "DEBUG_UI submit")):toBe(1)
		Rig.noErrors(world)
	end)
end)

describe("Select rejections", function()
	it("lets Select retry a rejected lock-in", function()
		local world, peer = Rig.practice(3)
		Rig.tap(world, peer, "Lobby", "Practice", 1)
		Rig.pickAll(world, peer)
		Rig.sabotageSubmits(world, peer, { candidate = "hale", color = "Teal", platform = { "Jobs" } })
		Rig.tap(world, peer, "Select", "LockIn", 1)
		expect(Rig.textOf(peer, "Select", "LockIn")):toBe("Lock In")
		check(Rig.enabled(peer, "Select", "LockIn"), "Lock In stays disabled after a rejection")
		Rig.noErrors(world)
	end)

	it("Select keeps a lock-in the server accepted", function()
		local world, peer = Rig.practice(3)
		Rig.tap(world, peer, "Lobby", "Practice", 1)
		Rig.pickAll(world, peer)
		local store = Rig.storeOf(world, peer)
		Rig.tap(world, peer, "Select", "LockIn", 0.01)
		-- An unrelated message arriving must not reopen a locked pick.
		store.say("Your opponent is back.")
		FakeRoblox.run(world, 0.05)
		if Rig.findIn(peer, "Select", "LockIn") then
			expect(Rig.textOf(peer, "Select", "LockIn")):toBe("Locked")
		end
		Rig.noErrors(world)
	end)
end)

describe("Select keeps no space for a Debug button", function()
	it("pins the Select footer to the bottom edge on a phone", function()
		local _, peer = Rig.fixture("Select", Rig.PHONE)
		local bar = Rig.need(peer, "Select", "FooterBar")
		expect(bar.Position.Y.Offset):toBe(0)
	end)

	it("leaves the footer full width on a wide screen", function()
		local _, peer = Rig.fixture("Select", nil)
		local bar = Rig.need(peer, "Select", "FooterBar")
		local pad = bar:FindFirstChildOfClass("UIPadding")
		check(pad == nil or pad.PaddingRight.Offset == 0, "the footer is padded away from the right edge")
	end)
end)
