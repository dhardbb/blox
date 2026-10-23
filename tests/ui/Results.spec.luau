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
		-- Kit.raceBar: a 14 px track; the tick overhangs it.
		expect(bar:FindFirstChild("Track").AbsoluteSize.Y):toBe(14)
		Rig.noErrors(world)
	end)

	it("stamps You won in green and You lost in orange with dark text (D-056)", function()
		local world, peer = Rig.fixture("Over", nil)
		local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
		local you = Rig.payloadOf(world, peer).you
		local function plate(): any
			return Rig.need(peer, "Results", "BannerStamp"):FindFirstChild("Plate")
		end
		withResult(world, peer, you)
		expect(plate().BackgroundColor3):toBe(Kit.colors.good)
		withResult(world, peer, 3 - you)
		expect(plate().BackgroundColor3):toBe(Kit.colors.loss)
		check(
			Rig.need(peer, "Results", "Banner").TextColor3 ~= Kit.colors.loss,
			"orange text on the orange stamp"
		)
		Rig.noErrors(world)
	end)

	it("puts a monogram on each player card", function()
		local world, peer = Rig.fixture("Over", nil)
		for _, name in { "Player_You", "Player_Opponent" } do
			local card = Rig.need(peer, "Results", name)
			check(card:FindFirstChild("Monogram") ~= nil, `{name} has no monogram`)
		end
		Rig.noErrors(world)
	end)

	it("keeps the closest states and the debates in the Full breakdown sheet (WP-C)", function()
		local world, peer = Rig.fixture("Over", nil)
		local sheet = Rig.need(peer, "Results", "BreakdownSheet")
		check(not Rig.shown(sheet, "Results"), "the breakdown is open before the tap")
		Rig.tap(world, peer, "Results", "FullBreakdown", 0.3)
		check(Rig.shown(sheet, "Results"), "Full breakdown did not open the sheet")
		check(Rig.shown(Rig.need(peer, "Results", "Closest"), "Results"), "no closest states in the sheet")
		local debates = Rig.findIn(peer, "Results", "Debates")
		check(debates == nil or Rig.shown(debates, "Results"), "the debates are hidden in the sheet")
		check(
			Rig.need(peer, "Results", "PlayAgain"):GetAttribute("PrimaryAction") == true,
			"the sheet took the primary"
		)
		Rig.tap(world, peer, "Results", "Close", 0.3)
		check(not Rig.shown(sheet, "Results"), "the × did not close the sheet")
		Rig.noErrors(world)
	end)

	it("says why the winner won in three short reasons (WP-C)", function()
		local world, peer = Rig.fixture("Over", nil)
		local you = Rig.payloadOf(world, peer).you
		withResult(world, peer, you)
		expect(Rig.textOf(peer, "Results", "WhyHead")):toBe("Why you won")
		for k = 1, 3 do
			local text = Rig.textOf(peer, "Results", `Reason_{k}`)
			check(text ~= "", `reason {k} is empty`)
			check(#string.split(text, " ") <= 12, `reason {k} is long: {text}`)
		end
		-- Votes, not "EV", in sentences; the player color stays on the dot.
		check(Rig.contains(Rig.textOf(peer, "Results", "EV"), " votes"), Rig.textOf(peer, "Results", "EV"))
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

-- ------------------------------------------------------------------ the moment (polish WP-2)

local function count(list: { string }, name: string): number
	local n = 0
	for _, entry in list do
		if entry == name then
			n += 1
		end
	end
	return n
end

local function confettiIn(peer: FakeRoblox.Peer): number
	local n = 0
	for _, inst in FakeRoblox.find(peer, "Screens"):GetDescendants() do
		if inst.Name == "Confetti" then
			n += 1
		end
	end
	return n
end

-- The Over fixture as a new match that `winner` won, pushed onto the screen.
local function newMatch(world: FakeRoblox.World, peer: FakeRoblox.Peer, winner: number, id: string)
	local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
	payload.matchId = id
	payload.result = { winner = winner, reason = "Election" }
	world.current = peer
	Rig.storeOf(world, peer).setPayload(payload)
	world.current = nil
	FakeRoblox.run(world, 0.1)
end

describe("Results moment", function()
	it("plays victory once on a win, with confetti, and never defeat", function()
		local world, peer = Rig.fixture("Over", nil)
		local you = Rig.payloadOf(world, peer).you
		newMatch(world, peer, you, "won-match")
		expect(confettiIn(peer)):toBe(1)
		-- A later payload of the same match redraws quietly.
		local again = Rig.deepCopy(Rig.payloadOf(world, peer))
		Rig.push(world, peer, again)
		FakeRoblox.run(world, 2)
		local sounds = Rig.sounds(peer)
		expect(count(sounds, "victory") >= 1):toBe(true)
		local before = count(sounds, "victory")
		Rig.push(world, peer, Rig.deepCopy(Rig.payloadOf(world, peer)))
		expect(count(Rig.sounds(peer), "victory")):toBe(before)
		expect(confettiIn(peer)):toBe(0) -- it cleared itself
		Rig.noErrors(world)
	end)

	it("plays defeat once on a loss, with no confetti and no victory", function()
		local world, peer = Rig.fixture("Over", nil)
		local you = Rig.payloadOf(world, peer).you
		local victories = count(Rig.sounds(peer), "victory")
		newMatch(world, peer, 3 - you, "lost-match")
		expect(confettiIn(peer)):toBe(0)
		Rig.push(world, peer, Rig.deepCopy(Rig.payloadOf(world, peer)))
		local sounds = Rig.sounds(peer)
		expect(count(sounds, "defeat")):toBe(1)
		expect(count(sounds, "victory")):toBe(victories)
		expect(Rig.textOf(peer, "Results", "Banner")):toBe("You lost")
		Rig.noErrors(world)
	end)

	it("plays exactly one stinger per match, never both", function()
		-- The Over fixture is a win for this player: one victory, no defeat.
		local world, peer = Rig.fixture("Over", nil)
		local you = Rig.payloadOf(world, peer).you
		expect(Rig.payloadOf(world, peer).result.winner):toBe(you)
		FakeRoblox.run(world, 2)
		expect(count(Rig.sounds(peer), "victory")):toBe(1)
		expect(count(Rig.sounds(peer), "defeat")):toBe(0)
		-- The next match, lost (past the stingers' 10 s cooldown): one defeat.
		FakeRoblox.run(world, 10)
		newMatch(world, peer, 3 - you, "next-match")
		FakeRoblox.run(world, 2)
		expect(count(Rig.sounds(peer), "victory")):toBe(1)
		expect(count(Rig.sounds(peer), "defeat")):toBe(1)
		Rig.noErrors(world)
	end)

	it("counts both vote totals up to the final numbers", function()
		local world, peer = Rig.fixture("Over", nil)
		local you = Rig.payloadOf(world, peer).you
		newMatch(world, peer, you, "count-match")
		FakeRoblox.run(world, 1)
		local election = Rig.payloadOf(world, peer).view.election
		local mine = Rig.need(peer, "Player_You", "EV")
		expect(tostring(mine.Text)):toBe(`{election.ev[you]} votes`)
		Rig.noErrors(world)
	end)

	it("says what to try next time after a loss, and nothing after a win", function()
		local world, peer = Rig.fixture("Over", nil)
		local you = Rig.payloadOf(world, peer).you
		newMatch(world, peer, 3 - you, "tip-loss")
		local tip = Rig.textOf(peer, "Results", "NextTime")
		check(string.sub(tip, 1, 15) == "Try next time: ", `tip says "{tip}"`)
		check(#string.split(tip, " ") <= 12, `the tip is long: {tip}`)
		newMatch(world, peer, you, "tip-win")
		check(Rig.findIn(peer, "Results", "NextTime") == nil, "a winner gets advice")
		Rig.noErrors(world)
	end)

	it("drops no confetti and still lands on the end state with reduced motion", function()
		local world, peer = Rig.fixture("Over", nil, { reducedMotion = true })
		local you = Rig.payloadOf(world, peer).you
		newMatch(world, peer, you, "calm-win")
		expect(confettiIn(peer)):toBe(0)
		expect(Rig.textOf(peer, "Results", "Banner")):toBe("You won")
		local election = Rig.payloadOf(world, peer).view.election
		expect(tostring(Rig.need(peer, "Player_You", "EV").Text)):toBe(`{election.ev[you]} votes`)
		expect(count(Rig.sounds(peer), "victory") >= 1):toBe(true)
		expect(strictAudit(world, peer)):toBe(0)
		Rig.noErrors(world)
	end)
end)
