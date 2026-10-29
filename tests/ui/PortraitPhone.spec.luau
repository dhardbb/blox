--!strict
-- Phones play upright (D-100): at 390 x 844 with the notch, the top bar and
-- the home bar, the match screens keep what matters in view without a scroll.
-- Positions come from Snapshot.boxes (the snapshot renderer's layout, list
-- layouts included), the same pictures the designer reviews.

local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Snapshot = require("@testlib/Snapshot")
local Test = require("@testlib/Test")

local describe, it = Test.describe, Test.it

local check = Rig.check
local PHONE = Rig.PHONE_PORTRAIT
local TOP = PHONE.inset

type Box = Snapshot.Box

local function boxes(peer: FakeRoblox.Peer): { [string]: Box }
	return Snapshot.boxes(peer, { topInset = TOP })
end

local function box(all: { [string]: Box }, name: string): Box
	local b = all[name]
	check(b ~= nil, `nothing named {name} is drawn`)
	return b :: Box
end

local function overlaps(a: Box, b: Box): boolean
	return a.x < b.x + b.w - 0.5 and b.x < a.x + a.w - 0.5 and a.y < b.y + b.h - 0.5 and b.y < a.y + a.h - 0.5
end

-- Whole, in view (inside what its scrolling ancestors show) and above `limit`.
local function inView(all: { [string]: Box }, name: string, limit: number)
	local b = box(all, name)
	local c = b.clip
	check(b.y >= c.y - 0.5 and b.y + b.h <= c.y + c.h + 0.5, `{name} is cut off or scrolled away`)
	check(b.y + b.h <= limit + 0.5, `{name} ends at {b.y + b.h}, under the bar at {limit}`)
	check(b.y >= TOP - 0.5, `{name} starts under the top bar`)
end

local function audit(world: FakeRoblox.World, peer: FakeRoblox.Peer, screen: string)
	local problems = Rig.audit(peer, screen)
	check(#problems == 0, table.concat(problems, "; "))
	Rig.noErrors(world)
end

describe("Portrait phone (D-100)", function()
	it("puts the score on its own header row, the two numbers apart", function()
		local world, peer = Rig.fixture("Plan", PHONE)
		local all = boxes(peer)
		local week, mine, theirs = box(all, "WeekLabel"), box(all, "YouVotes"), box(all, "ThemVotes")
		local now = box(all, "NowText")
		check(mine.y >= week.y + week.h - 6, "the score shares the week's row")
		check(math.abs(mine.y - theirs.y) < 1, "the two scores are on different rows")
		check(mine.x + mine.w < theirs.x, "the two scores overprint each other")
		local bar = box(all, "EvBar")
		check(
			mine.x + mine.w <= bar.x + 0.5 and bar.x + bar.w <= theirs.x + 0.5,
			"a number sits on the race bar"
		)
		check(now.y >= mine.y + mine.h - 0.5, "the now line is not under the score")
		audit(world, peer, "Campaign")
	end)

	it("fits the map key, Close races and the four lenses in one row", function()
		local world, peer = Rig.fixture("Plan", PHONE)
		local all = boxes(peer)
		local names = { "MapKey", "LensClose", "LensEV", "LensIssues", "LensPolls", "LensMoney" }
		for i, a in names do
			local first = box(all, a)
			check(first.w >= 44 - 0.5 and first.h >= 44 - 0.5, `{a} is under 44 px`)
			check(first.x >= -0.5 and first.x + first.w <= PHONE.x + 0.5, `{a} is off the screen`)
			for j = i + 1, #names do
				check(not overlaps(first, box(all, names[j])), `{a} overlaps {names[j]}`)
			end
		end
		audit(world, peer, "Campaign")
	end)

	it("opens a state's card as a sheet: all six actions and Lock in in view, the map above", function()
		local world, peer = Rig.fixture("Plan", PHONE)
		Rig.tap(world, peer, "Campaign", "Key_TX")
		local all = boxes(peer)
		local lock = box(all, "LockIn")
		inView(all, "CardTitle", lock.y)
		for _, name in { "Rally", "Fundraise", "Ad", "Attack", "Poll", "Gotv" } do
			inView(all, name, lock.y)
		end
		local map, card = box(all, "NodeMap"), box(all, "StateCard")
		check(map.y + map.h <= card.y + 0.5, "the sheet covers the map")
		check(map.h >= 150, `the map is {map.h} px tall above the sheet`)
		-- Closing it gives the map its room back.
		Rig.tap(world, peer, "Campaign", "CloseCard")
		local closed = box(boxes(peer), "NodeMap")
		check(closed.h > map.h, "the map did not grow back")
		audit(world, peer, "Campaign")
	end)

	it("keeps a coach tip and its Got it above the action bar", function()
		local world, peer = Rig.fixture("Plan", PHONE)
		local all = boxes(peer)
		local primary = all.SkipButton or all.LockIn
		check(primary ~= nil, "no action bar button")
		inView(all, "GotIt", (primary :: Box).y)
		Rig.noErrors(world)
	end)

	it("shows the three stances above Lock in", function()
		local world, peer = Rig.fixture("Stance", PHONE)
		local all = boxes(peer)
		local lock = box(all, "LockIn")
		for _, id in { "A", "B", "C" } do
			inView(all, `Choice{id}`, lock.y)
		end
		audit(world, peer, "Decision")
	end)

	it("plays a debate round without the map, the three moves in view; the verdict shows it", function()
		local world, peer = Rig.fixture("DebateRound", PHONE)
		local all = boxes(peer)
		check(all.NodeMap == nil, "a round shows the map")
		local lock = box(all, "LockIn")
		for _, move in { "Defend", "Attack", "Pivot" } do
			inView(all, `Move{move}`, lock.y)
		end
		audit(world, peer, "Debate")
		local world2, peer2 = Rig.fixture("Debate", PHONE)
		check(boxes(peer2).NodeMap ~= nil, "the verdict has no map")
		Rig.noErrors(world2)
	end)
end)
