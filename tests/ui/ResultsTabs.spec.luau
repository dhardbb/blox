--!strict
-- The end screen's tabs (D-073): Summary stays the first view; Map compares the
-- final polls with the real result and marks the states the polls missed;
-- Graph draws both players' projected votes week by week, then the result.

local Config = require("@sim/Config")
local EVChart = require("@ui/EVChart")
local FakeRoblox = require("@testlib/FakeRoblox")
local PollMiss = require("@ui/PollMiss")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local C = Config.defaults

local function selected(peer: FakeRoblox.Peer, name: string): boolean
	return Rig.need(peer, "Results", name):GetAttribute("Selected") == true
end

-- First names as Results shows them, by player.
local function names(world: FakeRoblox.World, peer: FakeRoblox.Peer): { string }
	local Data = FakeRoblox.require(world, peer, "src/client/Screens/Common/Data.luau")
	local view = Rig.payloadOf(world, peer).view
	local out = {}
	for p, entry in view.players do
		local full = Data.candidateName(C, entry.candidate)
		out[p] = string.match(full, "^(%S+)") or full
	end
	return out
end

local function strictAudit(world: FakeRoblox.World, peer: FakeRoblox.Peer): number
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	return Audit.run(Rig.need(peer, "Screens", "Results"), "Results", { strict = true })
end

describe("Results tabs", function()
	it("opens on Summary, with Map and Graph one tap away", function()
		local world, peer = Rig.fixture("Over", Rig.PHONE)
		check(Rig.shown(Rig.need(peer, "Results", "Tabs"), "Results"), "no tabs after an election")
		check(selected(peer, "Tab_Summary"), "Summary is not the first tab")
		check(Rig.shown(Rig.need(peer, "Results", "Banner"), "Results"), "the banner is hidden")
		check(not Rig.shown(Rig.need(peer, "Results", "MapTab"), "Results"), "the map tab shows first")
		check(not Rig.shown(Rig.need(peer, "Results", "GraphTab"), "Results"), "the graph tab shows first")
		Rig.tap(world, peer, "Results", "Tab_Map")
		check(selected(peer, "Tab_Map") and not selected(peer, "Tab_Summary"), "Map is not selected")
		check(Rig.shown(Rig.need(peer, "Results", "MapTab"), "Results"), "the map tab is hidden")
		check(not Rig.shown(Rig.need(peer, "Results", "Banner"), "Results"), "Summary still shows")
		Rig.tap(world, peer, "Results", "Tab_Graph")
		check(Rig.shown(Rig.need(peer, "Results", "GraphTab"), "Results"), "the graph tab is hidden")
		check(not Rig.shown(Rig.need(peer, "Results", "MapTab"), "Results"), "the map tab still shows")
		Rig.tap(world, peer, "Results", "Tab_Summary")
		check(Rig.shown(Rig.need(peer, "Results", "Banner"), "Results"), "back to Summary failed")
		check(
			Rig.need(peer, "Results", "PlayAgain"):GetAttribute("PrimaryAction") == true,
			"a tab took the primary"
		)
		Rig.noErrors(world)
	end)

	it("keeps the tab through a repeat of the same match and resets for a new one", function()
		local world, peer = Rig.fixture("Over", nil)
		Rig.tap(world, peer, "Results", "Tab_Graph")
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		Rig.push(world, peer, payload)
		check(selected(peer, "Tab_Graph"), "a repeat payload left the Graph tab")
		check(Rig.shown(Rig.need(peer, "Results", "GraphTab"), "Results"), "the graph hid on a repeat")
		local fresh = Rig.deepCopy(payload)
		fresh.matchId = "another-match"
		Rig.push(world, peer, fresh)
		check(selected(peer, "Tab_Summary"), "a new match did not open on Summary")
		Rig.noErrors(world)
	end)

	it("has no tabs without an election (a forfeit)", function()
		local world, peer = Rig.fixture("Over", nil)
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		payload.matchId = "forfeit"
		payload.result = { winner = payload.you, reason = "Forfeit" }
		payload.view.election = nil
		payload.view.pollHistory = nil
		Rig.push(world, peer, payload)
		check(not Rig.shown(Rig.need(peer, "Results", "Tabs"), "Results"), "tabs without an election")
		check(Rig.shown(Rig.need(peer, "Results", "Banner"), "Results"), "no banner after a forfeit")
		Rig.noErrors(world)
	end)
end)

describe("Results map tab", function()
	it("switches between the final polls and the real results", function()
		local world, peer = Rig.fixture("Over", Rig.PHONE)
		local payload = Rig.payloadOf(world, peer)
		local view = payload.view
		local rows = PollMiss.rows(view)
		local who = names(world, peer)
		Rig.tap(world, peer, "Results", "Tab_Map")
		check(selected(peer, "Mode_Polls"), "the map does not open on the final polls")
		expect(Rig.textOf(peer, "Results", "ModeVotes")):toBe(
			PollMiss.votesLine("Polls", view.projectedEV, payload.you, who)
		)
		expect(Rig.textOf(peer, "Results", "MissLine")):toBe(PollMiss.summary(PollMiss.misses(rows)))
		check(Rig.findIn(peer, "Results", "NodeMap") ~= nil, "no map on the map tab")
		Rig.tap(world, peer, "Results", "Mode_Result")
		check(
			selected(peer, "Mode_Result") and not selected(peer, "Mode_Polls"),
			"Real results is not selected"
		)
		expect(Rig.textOf(peer, "Results", "ModeVotes")):toBe(
			PollMiss.votesLine("Result", view.election.ev, payload.you, who)
		)
		Rig.noErrors(world)
	end)

	it("tags every missed state MISS, in both modes", function()
		local world, peer = Rig.fixture("Over", nil)
		local misses = PollMiss.misses(PollMiss.rows(Rig.payloadOf(world, peer).view))
		check(#misses > 0, "the Over fixture has no missed state: pick another seed")
		local function tagged(): number
			local n = 0
			for _, inst in FakeRoblox.find(peer, "Results"):GetDescendants() do
				if inst.ClassName == "TextLabel" and inst.Text == "MISS" and Rig.shown(inst, "Results") then
					n += 1
				end
			end
			return n
		end
		Rig.tap(world, peer, "Results", "Tab_Map")
		expect(tagged()):toBe(#misses)
		Rig.tap(world, peer, "Results", "Mode_Result")
		expect(tagged()):toBe(#misses)
		Rig.noErrors(world)
	end)

	it("compares a tapped state's final poll with its result", function()
		local world, peer = Rig.fixture("Over", nil)
		local payload = Rig.payloadOf(world, peer)
		local misses = PollMiss.misses(PollMiss.rows(payload.view))
		Rig.tap(world, peer, "Results", "Tab_Map")
		local id = misses[1].id
		Rig.tap(world, peer, "Results", id)
		expect(Rig.textOf(peer, "Results", "StateLine")):toBe(
			PollMiss.stateLine(misses[1], payload.you, names(world, peer))
		)
		check(
			Rig.contains(Rig.textOf(peer, "Results", "StateLine"), "The polls missed it."),
			"no miss in the line"
		)
		Rig.tap(world, peer, "Results", id)
		check(
			Rig.contains(Rig.textOf(peer, "Results", "StateLine"), "Tap a state"),
			"a second tap kept the state"
		)
		Rig.noErrors(world)
	end)
end)

describe("Results graph tab", function()
	it("draws a line and a point a week for each player, the 270 line and the result", function()
		local world, peer = Rig.fixture("Over", Rig.PHONE)
		local view = Rig.payloadOf(world, peer).view
		local points = EVChart.points(view)
		expect(#points):toBe(C.WEEKS + 2)
		Rig.tap(world, peer, "Results", "Tab_Graph")
		check(Rig.findIn(peer, "Results", "Line270") ~= nil, "no 270 line")
		local turned = 0
		for p = 1, #view.players do
			for k = 1, #points do
				Rig.need(peer, "Results", `Dot_{p}_{k}`)
			end
			for k = 1, #points - 1 do
				local piece = Rig.need(peer, "Results", `Line_{p}_{k}`)
				if piece.Rotation ~= 0 then
					turned += 1
				end
			end
			check(Rig.findIn(peer, "Results", `Line_{p}_{#points}`) == nil, "a line past the result")
		end
		check(turned > 0, "no line piece is turned")
		-- The result's points are ringed in white.
		check(
			Rig.need(peer, "Results", `Dot_1_{#points}`):FindFirstChildOfClass("UIStroke") ~= nil,
			"no ring on the result"
		)
		check(
			Rig.contains(Rig.textOf(peer, "Results", "ChartSummary"), "on election night"),
			"no summary line"
		)
		Rig.noErrors(world)
	end)

	it("puts the line pieces where EVChart says", function()
		local world, peer = Rig.fixture("Over", nil)
		Rig.tap(world, peer, "Results", "Tab_Graph")
		local plot = Rig.need(peer, "Results", "Plot")
		local view = Rig.payloadOf(world, peer).view
		local points = EVChart.points(view)
		local w, h = plot.Size.X.Offset, plot.Size.Y.Offset
		local lo, hi = EVChart.range(points, 270)
		local xs = EVChart.xs(points, w)
		local seg = EVChart.segment(
			xs[3],
			EVChart.y(points[3].ev[1], lo, hi, h),
			xs[4],
			EVChart.y(points[4].ev[1], lo, hi, h)
		)
		local piece = Rig.need(peer, "Results", "Line_1_3")
		expect(piece.Rotation):toBeCloseTo(seg.rotation)
		expect(piece.Position.X.Offset):toBeCloseTo(seg.x)
		expect(piece.Position.Y.Offset):toBeCloseTo(seg.y)
		Rig.noErrors(world)
	end)

	it("says what happened on a debate or stance week when its marker is tapped", function()
		local world, peer = Rig.fixture("Over", Rig.PHONE)
		local view = Rig.payloadOf(world, peer).view
		local markers = EVChart.markers(view, names(world, peer))
		check(#markers > 0, "the Over fixture has no debate")
		Rig.tap(world, peer, "Results", "Tab_Graph")
		local hint = Rig.textOf(peer, "Results", "ChartNote")
		for _, marker in markers do
			local name = `Marker_{marker.week}_{marker.kind}`
			local button = Rig.need(peer, "Results", name)
			check(button.AbsoluteSize.X >= 44 and button.AbsoluteSize.Y >= 44, `{name} is a small target`)
			Rig.tap(world, peer, "Results", name)
			expect(Rig.textOf(peer, "Results", "ChartNote")):toBe(marker.line)
		end
		local last = markers[#markers]
		Rig.tap(world, peer, "Results", `Marker_{last.week}_{last.kind}`)
		expect(Rig.textOf(peer, "Results", "ChartNote")):toBe(hint)
		Rig.noErrors(world)
	end)
end)

describe("Results tabs audit", function()
	it("audits clean, strictly, on every tab at phone, iPad and desktop size", function()
		for _, screen in { Rig.PHONE, { x = 1024, y = 768 }, { x = 1280, y = 720 } } do
			local world, peer = Rig.fixture("Over", screen)
			for _, tab in { "Tab_Map", "Tab_Graph" } do
				Rig.tap(world, peer, "Results", tab)
				expect(strictAudit(world, peer)):toBe(0)
			end
			Rig.tap(world, peer, "Results", "Mode_Result")
			Rig.tap(world, peer, "Results", "Tab_Map")
			expect(strictAudit(world, peer)):toBe(0)
			Rig.noErrors(world)
		end
	end)
end)
