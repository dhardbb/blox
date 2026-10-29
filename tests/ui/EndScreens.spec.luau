--!strict
-- The debate, election night and end screen pass of D-098 on the fake engine:
-- a landscape phone's debate shows its three moves as tiles and the clash's
-- stamp and both moves above the bar; the verdict names the crowd's winner with
-- their face and a colored chip per round; election night's 270 is a
-- full-width banner that never covers a vote count, a deciding state is tagged
-- in gold while it counts, Skip is quiet, and a phone gets the tip as one line;
-- the end screen stands in two columns on an iPad with the vote counts above
-- the bar, and its map tags only the states the polls missed.

local process = require("@lune/process")

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local PollMiss = require("@ui/PollMiss")
local Rig = require("./Rig")
local Test = require("@testlib/Test")
local Words = require("@ui/Words/Debate")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local C = Config.defaults
local IPAD = { x = 1024, y = 768 }

local function bottom(inst: any): number
	return inst.AbsolutePosition.Y + inst.AbsoluteSize.Y
end

-- Do the two rectangles overlap?
local function overlaps(a: any, b: any): boolean
	local ax, ay = a.AbsolutePosition.X, a.AbsolutePosition.Y
	local bx, by = b.AbsolutePosition.X, b.AbsolutePosition.Y
	return ax < bx + b.AbsoluteSize.X
		and bx < ax + a.AbsoluteSize.X
		and ay < by + b.AbsoluteSize.Y
		and by < ay + a.AbsoluteSize.Y
end

describe("Words.Debate (D-098)", function()
	it("packs a tile's cells and names each round's winner on its chip", function()
		expect(Words.cellsShort({ cells = { 4, 0, -5 } } :: any)):toBe("D+4 A= P−5")
		local view: any = { you = 1 }
		local text, winner = Words.roundChip(view, { topic = "Safety", winner = 0 } :: any, "Buster")
		expect(text):toBe("Safety · Split")
		expect(winner):toBe(0)
		expect((Words.roundChip(view, { topic = "Jobs", winner = 1 } :: any, "Buster"))):toBe("Jobs · You")
		expect((Words.roundChip(view, { topic = "Health", winner = 2 } :: any, "Buster"))):toBe(
			"Health · Buster"
		)
		expect((Words.roundChip(view, { topic = "Health", winner = 2 } :: any, "Bartholomew Zork"))):toBe(
			"Health · Them"
		)
	end)
end)

describe("Debate on a landscape phone (D-098)", function()
	it("stands the three moves side by side, all above the bar", function()
		local world, peer = Rig.fixture("DebateRound", Rig.PHONE)
		local barTop = Rig.need(peer, "Debate", "ActionBar").AbsolutePosition.Y
		local y: number? = nil
		for _, move in { "Defend", "Attack", "Pivot" } do
			local button = Rig.need(peer, "Debate", `Move{move}`)
			check(Rig.shown(button, "Debate"), `{move} is hidden`)
			check(bottom(button) <= barTop + 0.5, `{move} ends under the bar`)
			check(
				y == nil or math.abs(button.AbsolutePosition.Y - (y :: number)) < 1,
				`{move} is not in the row`
			)
			y = button.AbsolutePosition.Y
		end
		Rig.noErrors(world)
	end)

	it("leads the clash with the stamp, then both moves, all above the bar", function()
		local world, peer = Rig.fixture("Clash", Rig.PHONE)
		local barTop = Rig.need(peer, "Debate", "ActionBar").AbsolutePosition.Y
		local row = Rig.need(peer, "Debate", "StampRow")
		local cards = Rig.need(peer, "Debate", "ClashCards")
		check(row.LayoutOrder < cards.LayoutOrder, "the moves come before the stamp")
		check(bottom(cards) <= barTop + 0.5, `the moves end at {bottom(cards)}, under the bar at {barTop}`)
		check(Rig.shown(Rig.need(peer, "Debate", "ClashStamp"), "Debate"), "no stamp")
		Rig.noErrors(world)
	end)

	it("lands the stamp at once under reduced motion", function()
		local world = FakeRoblox.world({ root = process.cwd, seed = 3, screen = Rig.PHONE })
		world.reducedMotion = true
		local peer = FakeRoblox.join(world, "P", { DebugScreen = "Clash" })
		FakeRoblox.run(world, 1)
		local stamp = Rig.need(peer, "Debate", "ClashStamp")
		local scale = stamp:FindFirstChild("MotionScale")
		check(scale == nil or scale.Scale == 1, "the stamp is still landing")
		Rig.noErrors(world)
	end)
end)

describe("Debate verdict (D-098)", function()
	it("puts a chip per round in its winner's color", function()
		local world, peer = Rig.fixture("Debate", nil)
		local view = Rig.payloadOf(world, peer).view
		local result = view.debates[#view.debates]
		for k, round in result.rounds do
			local chip = Rig.need(peer, "Debate", `VerdictRound{k}`)
			check(Rig.shown(chip, "Debate"), `round {k}'s chip is hidden`)
			expect(chip:GetAttribute("Filled") == true):toBe(round.winner ~= 0)
		end
		-- Skip is quiet (D-098): not the bright primary, still tappable.
		local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
		local skip = Rig.need(peer, "Debate", "LockIn")
		expect(tostring(skip.Text)):toBe("Skip")
		check(
			skip.Active ~= false and skip.BackgroundColor3 ~= Kit.colors.accent,
			"Skip is the bright primary"
		)
		Rig.noErrors(world)
	end)

	it("shows the crowd's winner's face beside the stamp, none on an even crowd", function()
		local world, peer = Rig.fixture("Debate", nil)
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		local face = Rig.need(peer, "Debate", "VerdictFace")
		local result = payload.view.debates[#payload.view.debates]
		local even = (result.crowd[1] or 0) == (result.crowd[2] or 0)
		expect(face.Visible ~= false):toBe(not even)
		local them = 3 - payload.you
		result.crowd[them] = (result.crowd[payload.you] or 0) + 3
		payload.step += 1
		Rig.push(world, peer, payload)
		FakeRoblox.run(world, 0.5)
		check(face.Visible ~= false, "no face for the crowd's winner")
		check(face:FindFirstChild("CrowdWinnerFace") ~= nil, "the face slot is empty")
		Rig.noErrors(world)
	end)
end)

-- Election night, `warmup` seconds in.
local function election(
	screen: { x: number, y: number }?,
	warmup: number?
): (FakeRoblox.World, FakeRoblox.Peer)
	local world = FakeRoblox.world({ root = process.cwd, seed = 3, screen = screen })
	local peer = FakeRoblox.join(world, "P", { DebugScreen = "Election" })
	FakeRoblox.run(world, warmup or 1)
	return world, peer
end

describe("Election night (D-098)", function()
	it("crosses 270 with a full-width banner that covers neither count", function()
		local world, peer = election(nil, 0)
		local banner: any = nil
		for _ = 1, 600 do
			FakeRoblox.run(world, 0.1)
			banner = Rig.findIn(peer, "Election", "Stamp270")
			if banner then
				break
			end
		end
		check(banner ~= nil, "no 270 banner")
		local text = tostring(banner:FindFirstChild("Label", true).Text)
		check(string.find(text, "WIN", 1, true) ~= nil and string.find(text, "270!", 1, true) ~= nil, text)
		local strip = Rig.need(peer, "Election", "Counters")
		check(banner.AbsoluteSize.X >= strip.AbsoluteSize.X * 0.9, "the banner is not full width")
		for _, name in { "EvYou", "EvThem" } do
			check(not overlaps(banner, Rig.need(peer, "Election", name)), `the banner covers {name}`)
		end
		Rig.noErrors(world)
	end)

	it("counts with pulsing dots and tags the deciding state in gold", function()
		local world, peer = election(nil, 0)
		local seen = false
		for _ = 1, 600 do
			FakeRoblox.run(world, 0.1)
			local tag = Rig.findIn(peer, "Election", "DecidingTag")
			if tag and tag.Visible ~= false then
				seen = true
				expect(tostring(tag.Text)):toBe("DECIDING STATE")
				check(Rig.need(peer, "Election", "CountingDots").Visible ~= false, "no counting dots")
				check(Rig.need(peer, "Election", "SpotPortrait").Visible == false, "the empty portrait shows")
				break
			end
		end
		check(seen, "the deciding state was never tagged")
		Rig.noErrors(world)
	end)

	it("keeps Skip quiet: not the white primary, still tappable", function()
		local world, peer = election(nil, 1)
		local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
		local skip = Rig.need(peer, "Election", "SkipButton")
		check(skip.Active ~= false, "Skip is disabled")
		check(skip.BackgroundColor3 ~= Kit.colors.accent, "Skip is the bright primary")
		expect(skip.TextColor3):toEqual(Kit.colors.text)
		Rig.noErrors(world)
	end)

	it("says the tip in one line on a phone instead of a card over the calls", function()
		local world, peer = election(Rig.PHONE, 1)
		expect(Rig.findIn(peer, "Election", "CoachTip")):toBe(nil)
		check(
			Rig.contains(Rig.textOf(peer, "Election", "BarStatus"), `First to {C.EV_TO_WIN} wins`),
			Rig.textOf(peer, "Election", "BarStatus")
		)
		-- The spotlight sits whole above the bar.
		local spot = Rig.need(peer, "Election", "Spotlight")
		local bar = Rig.need(peer, "Election", "ActionBar")
		check(bottom(spot) <= bar.AbsolutePosition.Y + 0.5, "the bar covers the spotlight")
		Rig.noErrors(world)
	end)
end)

describe("Results (D-098)", function()
	-- The fake engine places list children at their parent's corner, so this
	-- checks the layout's settings; the snapshots show the result.
	for _, case in
		{ { name = "iPad", screen = IPAD, two = true }, { name = "phone", screen = Rig.PHONE, two = false } }
	do
		it(`stands in {if case.two then "two columns" else "one column"} on a {case.name}`, function()
			local world, peer = Rig.fixture("Over", case.screen)
			local columns = Rig.need(peer, "Results", "Columns")
			local list = columns:FindFirstChildOfClass("UIListLayout")
			expect(list.FillDirection.Name):toBe(if case.two then "Horizontal" else "Vertical")
			for _, name in { "SummaryLeft", "SummaryRight" } do
				expect(Rig.need(peer, "Results", name).Size.X.Scale):toBe(if case.two then 0.5 else 1)
			end
			-- Both candidates side by side, each card a fixed, compact height.
			for _, card in { "Player_You", "Player_Opponent" } do
				local made = Rig.need(peer, "Results", card)
				expect(made.Size.X.Scale):toBe(0.5)
				check(made.Size.Y.Offset <= 140, `{card} is {made.Size.Y.Offset} px tall`)
			end
			Rig.noErrors(world)
		end)
	end

	it("drops the repeated vote line after an ordinary win", function()
		local world, peer = Rig.fixture("Over", nil)
		check(not Rig.shown(Rig.need(peer, "Results", "Reason"), "Results"), "the vote line shows")
		Rig.noErrors(world)
	end)

	it("tags only the states the polls missed on the map", function()
		local world, peer = Rig.fixture("Over", Rig.PHONE)
		local view = Rig.payloadOf(world, peer).view
		local missed: { [string]: boolean } = {}
		for _, row in PollMiss.misses(PollMiss.rows(view)) do
			missed[row.id] = true
		end
		Rig.tap(world, peer, "Results", "Tab_Map")
		local map = Rig.need(peer, "Results", "NodeMap")
		for _, node in map.Nodes:GetChildren() do
			local lens = node:FindFirstChild("Lens")
			if lens and lens.Visible ~= false and not missed[node.Name] then
				local part = lens:FindFirstChild("Part1")
				check(
					part == nil or part.Visible == false or tostring(part.Text) == "",
					`{node.Name} has a tag`
				)
			end
		end
		Rig.noErrors(world)
	end)
end)
