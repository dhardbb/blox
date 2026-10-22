--!strict
-- The Results screen on the fake Roblox engine: the rating line of this match
-- (v0.3.1 bug hunt) and the UI overhaul (WP2, docs/UI-OVERHAUL.md §3.6): the
-- banner, the pinned action bar, the EV bar's 270 tick, collapsible sections.

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

-- ------------------------------------------------------------------ UI overhaul (WP2)

local function inScroll(inst: any): boolean
	local node = inst.Parent
	while node ~= nil do
		if node.ClassName == "ScrollingFrame" then
			return true
		end
		node = node.Parent
	end
	return false
end

local function strictAudit(world: FakeRoblox.World, peer: FakeRoblox.Peer): number
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	return Audit.run(Rig.need(peer, "Screens", "Results"), "Results", { strict = true })
end

-- Pushes the fixture again with another result.
local function withResult(world: FakeRoblox.World, peer: FakeRoblox.Peer, winner: number)
	local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
	payload.result = { winner = winner, reason = "Election" }
	Rig.push(world, peer, payload)
end

describe("Results layout", function()
	it("writes the banner in sentence case at hero size", function()
		local world, peer = Rig.fixture("Over", nil)
		local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
		local you = Rig.payloadOf(world, peer).you
		withResult(world, peer, you)
		expect(Rig.textOf(peer, "Results", "Banner")):toBe("You won")
		expect(Rig.need(peer, "Results", "Banner").TextSize):toBe(Kit.size.hero)
		withResult(world, peer, 3 - you)
		expect(Rig.textOf(peer, "Results", "Banner")):toBe("You lost")
		Rig.noErrors(world)
	end)

	it("pins Play vs Bot again and Back to lobby in the action bar", function()
		local world, peer = Rig.fixture("Over", Rig.PHONE)
		local again = Rig.need(peer, "Results", "PlayAgain")
		expect(again:GetAttribute("PrimaryAction")):toBe(true)
		expect(tostring(again.Text)):toBe("Play vs Bot again")
		check(not inScroll(again), "Play again scrolls")
		local back = Rig.need(peer, "Results", "BackToLobby")
		check(not inScroll(back), "Back to lobby scrolls")
		expect(back:GetAttribute("Variant")):toBe("secondary")
		Rig.noErrors(world)
	end)

	it("marks 270 on the EV bar", function()
		local world, peer = Rig.fixture("Over", nil)
		local bar = Rig.need(peer, "Results", "EVBar")
		local tick = Rig.need(peer, "Results", "Marker270")
		expect(tick.Parent):toBe(bar)
		expect(bar.AbsoluteSize.Y):toBe(14)
		Rig.noErrors(world)
	end)

	it("shows the closest states and the debates expanded, and folds them on a tap", function()
		local world, peer = Rig.fixture("Over", nil)
		local closest = Rig.need(peer, "Results", "Closest")
		local toggle = closest:FindFirstChild("Toggle")
		expect(toggle:GetAttribute("Expanded")):toBe(true)
		world.current = peer
		toggle.Activated.fire()
		world.current = nil
		FakeRoblox.run(world, 0.3)
		expect(toggle:GetAttribute("Expanded")):toBe(false)
		local debates = Rig.findIn(peer, "Results", "Debates")
		if debates then
			expect(debates:FindFirstChild("Toggle"):GetAttribute("Expanded")):toBe(true)
		end
		Rig.noErrors(world)
	end)

	it("keeps the rating line's room before the change arrives", function()
		local world, peer = Rig.fixture("Over", nil)
		local slot = Rig.need(peer, "Results", "RatingSlot")
		check(Rig.shown(slot, "Results"), "the rating line's room is not reserved")
		Rig.noErrors(world)
	end)

	it("audits clean, strictly, at both sizes", function()
		for _, screen in { Rig.PHONE, { x = 1280, y = 720 } } do
			local world, peer = Rig.fixture("Over", screen)
			expect(strictAudit(world, peer)):toBe(0)
			Rig.noErrors(world)
		end
	end)
end)
