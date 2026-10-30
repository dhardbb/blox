--!strict
-- The map's label budget and focus tools (docs/DESIGN.md D-079,
-- docs/UI-STYLE.md §4.6: "never more than ~8 labels on the map at once"):
-- SwingMarks keeps every preview, reveal and reveal step to 8 tags, the 5
-- biggest flips (by votes) as a ▲ / ▼ tag and the biggest moves; a stance
-- preview outlines in the legend's green and orange; the Close filter quiets
-- the safe states and is remembered; election night draws uncalled states
-- hollow, outlines the tipping state before its call and carries no tags;
-- pins are named in the first week only.

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Rig = require("./Rig")
local StateData = require("@sim/StateData")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local C = Config.defaults

local function load(world: FakeRoblox.World, peer: FakeRoblox.Peer, path: string): any
	return FakeRoblox.require(world, peer, path)
end

local function same(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
end

local function tags(marks: { [string]: any }): number
	local n = 0
	for _, mark in marks do
		if mark.badge ~= nil or mark.note ~= nil then
			n += 1
		end
	end
	return n
end

-- Every state moved, a dozen flipped: far more than the map should label.
local function busy(view: any): ({ [string]: number }, { any })
	local net: { [string]: number } = {}
	local flips = {}
	for k, s in view.states do
		net[s.id] = if k % 2 == 0 then k / 10 else -k / 10
		if k <= 12 then
			table.insert(flips, { state = s.id, from = 2, to = 1, ev = StateData.byId[s.id].ev })
		end
	end
	return net, flips
end

describe("Map labels (D-079)", function()
	it(
		"keeps a reveal, a step and a preview to 8 tags: the 5 biggest flips ▲ / ▼, then the biggest moves",
		function()
			local world, peer = Rig.fixture("Plan")
			local SwingMarks = load(world, peer, "src/client/Screens/CampaignParts/SwingMarks.luau")
			local Kit = load(world, peer, "src/client/UI/Kit.luau")
			local view = Fixtures.payload(C, "Plan").view
			local net, flips = busy(view)
			local byEv = table.clone(flips)
			table.sort(byEv, function(a: any, b: any): boolean
				if a.ev ~= b.ev then
					return a.ev > b.ev
				end
				return a.state < b.state
			end)
			local top: { [string]: boolean } = {}
			for k = 1, 5 do
				top[byEv[k].state] = true
			end
			for _, kind in { "reveal", "step" } do
				local marks = SwingMarks[kind](view, net, flips, {})
				check(tags(marks) <= SwingMarks.LABELS, `{kind}: {tags(marks)} tags`)
				expect(SwingMarks.LABELS):toBe(8)
				local flipTags = 0
				for _, flip in flips do
					local mark = marks[flip.state]
					-- Every flip: a 3 px outline in the new leader's color.
					expect(mark.haloStrong):toBe(true)
					check(same(mark.halo, Kit.playerColor(view, flip.to)), `{kind}: {flip.state}'s outline`)
					if mark.note then
						flipTags += 1
						check(
							top[flip.state] == true,
							`{kind}: {flip.state} is tagged but not among the biggest`
						)
						-- To the viewer (player 1 here, flip.to = 1): ▲.
						expect(mark.note):toBe(if flip.to == view.you then SwingMarks.UP else SwingMarks.DOWN)
						expect(mark.badge):toBe(nil)
					end
				end
				expect(flipTags):toBe(5)
				-- The rest of the room goes to the biggest moves.
				local moves = tags(marks) - flipTags
				expect(moves):toBe(3)
			end
			-- A preview: gains green, losses orange, the biggest gains tagged.
			local preview = SwingMarks.preview(view, { effects = net, flips = {} }, {})
			local gainTags = 0
			for id, points in net do
				local mark = preview[id]
				check(
					same(mark.halo, if points > 0 then Kit.colors.good else Kit.colors.loss),
					`{id}'s preview outline`
				)
				if mark.badge then
					gainTags += 1
					check(points > 0, `{id}: a loss is tagged`)
					check(same(mark.badgeColor, Kit.colors.good), `{id}'s tag is not green`)
				end
			end
			expect(gainTags):toBe(SwingMarks.MOVES)
			Rig.noErrors(world)
		end
	)

	it("never shows more than 8 tags on the map at the end of a reveal", function()
		for _, moment in { "Resolve", "Debate", "Clash", "ChoiceResolve" } do
			local world, peer = Rig.fixture(moment, Rig.PHONE)
			FakeRoblox.run(world, 30)
			local map = FakeRoblox.find(peer, "NodeMap")
			check(map ~= nil, `{moment}: no map`)
			local shown = 0
			for _, tag in map.Tags:GetChildren() do
				if tag.Visible ~= false and tag.Name ~= "GhostTag" then
					shown += 1
				end
			end
			check(shown <= 8, `{moment}: {shown} tags on the map`)
			Rig.noErrors(world)
		end
	end)
end)

describe("The Close filter (D-079)", function()
	it("quiets every state more than 8 points from close, in any lens, and is remembered", function()
		local world, peer = Rig.fixture("Plan", Rig.PHONE)
		local Lens = load(world, peer, "src/client/Map/Lens.luau")
		local view = Fixtures.payload(C, "Plan").view
		expect(Lens.close()):toBe(false)
		local quiet, kept = 0, 0
		for _, id in Lens.ORDER do
			local lines = Lens.lines(id, { config = C, view = view }, true)
			for _, s in view.states do
				local line = lines[s.id]
				if Lens.isClose(s) then
					check(line.quiet ~= true, `{id}: {s.id} is close but quiet`)
					kept += 1
				else
					expect(line.quiet):toBe(true)
					expect(#line.parts):toBe(0)
					quiet += 1
				end
			end
		end
		check(quiet > 0 and kept > 0, `the fixture has {quiet} safe and {kept} close state lines`)
		-- The chip turns it on; the map's safe states fade and lose their values.
		Rig.tap(world, peer, "Campaign", "LensClose")
		expect(Lens.close()):toBe(true)
		check(Rig.need(peer, "Campaign", "LensClose"):GetAttribute("Selected") == true, "the chip is not on")
		FakeRoblox.run(world, 0.1)
		local map = Rig.need(peer, "Campaign", "NodeMap")
		for _, s in view.states do
			local shape = map.Shapes:FindFirstChild(`Shape{s.id}`)
			if Lens.isClose(s) then
				check(shape:GetAttribute("Fade") < 0.5, `{s.id} is close but faded`)
			else
				check(shape:GetAttribute("Fade") > 0.5, `{s.id} is safe but not faded`)
				expect(map.Nodes:FindFirstChild(s.id).Lens.Visible):toBe(false)
			end
		end
		-- The chip and the lens chips fit beside the key on a phone (44 px each way).
		local chip = Rig.need(peer, "Campaign", "LensClose")
		check(chip.AbsoluteSize.X >= 44 and chip.AbsoluteSize.Y >= 44, "the Close chip is under 44 px")
		Rig.tap(world, peer, "Campaign", "LensClose")
		expect(Lens.close()):toBe(false)
		check(#Rig.audit(peer, "Campaign") == 0, table.concat(Rig.audit(peer, "Campaign"), "; "))
		Rig.noErrors(world)
	end)
end)

describe("Election night on the map (D-079)", function()
	it(
		"draws uncalled states hollow, outlines the tipping state before its call, and tags nothing",
		function()
			local world, peer = Rig.fixture("Election", Rig.PHONE)
			local Kit = load(world, peer, "src/client/UI/Kit.luau")
			local Screen = load(world, peer, "src/client/Screens/Election.luau")
			local view = Rig.payloadOf(world, peer).view
			local results = view.election.results
			local tipping = Screen.tippingCall(results, C.EV_TO_WIN)
			check(tipping ~= nil, "no tipping call in the fixture")
			local tipState = results[tipping].state
			local map = Rig.need(peer, "Election", "NodeMap")
			-- Early in the night: most states not called yet.
			local hollow = 0
			for _, s in view.states do
				local shape = map.Shapes:FindFirstChild(`Shape{s.id}`)
				if same(shape.ImageColor3, Kit.colors.field) then
					hollow += 1
				end
			end
			check(hollow > 10, `only {hollow} hollow states at the start of the night`)
			local outline = map.Outlines:FindFirstChild(`Outline{tipState}`)
			local chip = map.Nodes:FindFirstChild(tipState):FindFirstChild("Chip")
			if chip then
				check(
					same(chip:FindFirstChildOfClass("UIStroke").Color, Kit.colors.text),
					"the tipping chip is not white"
				)
			else
				check(outline ~= nil and outline.Visible, `{tipState} is not outlined before its call`)
				check(
					same(outline:GetChildren()[1].BackgroundColor3, Kit.colors.text),
					"the tipping outline is not white"
				)
			end
			for _ = 1, 30 do
				FakeRoblox.run(world, 1)
				for _, tag in map.Tags:GetChildren() do
					check(tag.Visible == false, `a tag on the election map: {tag.Name} "{tag.Text}"`)
				end
			end
			Rig.noErrors(world)
		end
	)
end)

describe("Pins (D-079)", function()
	it("names both pins in the first week only", function()
		local world, peer = Rig.fixture("Plan")
		local Pins = load(world, peer, "src/client/Map/Pins.luau")
		local view = Rig.deepCopy(Fixtures.payload(C, "Plan").view)
		view.week = 1
		for _, pin in Pins.of(C, view) do
			expect(pin.label):toBe(true)
		end
		view.week = 3
		for _, pin in Pins.of(C, view) do
			expect(pin.label):toBe(nil)
		end
		Rig.noErrors(world)
	end)
end)
