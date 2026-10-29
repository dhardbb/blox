--!strict
-- The real map (src/client/Map/ShapeMap.luau, D-070, D-079) on the fake engine:
-- one tinted shape per state from its atlas rect, a 36 px tap square per state
-- and a chip per callout state, taps settled by outline, outlines for selection
-- and rings (dashed, hollow), the Polls pill, quiet candidate pins, the legend,
-- the tall layout on a phone with one-line labels that never overlap, and a
-- clean strict audit.

local FakeRoblox = require("@testlib/FakeRoblox")
local MapLayout = require("@ui/MapLayout")
local MapShape = require("@ui/MapShape")
local StateData = require("@sim/StateData")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local UDim2 = FakeRoblox.types.UDim2

type Mounted = {
	world: FakeRoblox.World,
	peer: FakeRoblox.Peer,
	Kit: any,
	Audit: any,
	stage: any,
	map: any,
}

-- The real map filling a `w` x `h` frame on a client (Rig turns NodeMap.preview on).
local function mount(w: number, h: number): Mounted
	local world, peer = Rig.fixture("Lobby", nil)
	local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	local NodeMap = FakeRoblox.require(world, peer, "src/client/Map/NodeMap.luau")
	local gui = Kit.new("ScreenGui", { Name = "TestGui" })
	local stage = Kit.box({ Name = "Stage", Size = UDim2.fromOffset(w, h), Parent = gui })
	stage:SetAttribute("PrimaryOptional", true)
	local map = NodeMap.new()
	map.root.Parent = stage
	return { world = world, peer = peer, Kit = Kit, Audit = Audit, stage = stage, map = map }
end

-- Do two GUI objects' boxes overlap (by more than a pixel)?
local function overlaps(a: any, b: any): boolean
	local p, q = a.AbsolutePosition, b.AbsolutePosition
	local s, t = a.AbsoluteSize, b.AbsoluteSize
	return p.X + 1 < q.X + t.X and q.X + 1 < p.X + s.X and p.Y + 1 < q.Y + t.Y and q.Y + 1 < p.Y + s.Y
end

-- Two colors equal to the 1/255 (the fake engine's Color3s are tables).
local function same(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
end

-- Lets the map's once-a-frame mark layout run.
local function settle(m: Mounted)
	FakeRoblox.run(m.world, 0.05)
end

local function rgb(m: Mounted, r: number, g: number, b: number): Color3
	return m.Kit.color({ r = r, g = g, b = b })
end

local function button(m: Mounted, id: string): any
	local found = m.map.root.Nodes:FindFirstChild(id)
	check(found ~= nil, `no tap target {id}`)
	return found
end

-- Presses `pressed` (a state's square, or the open map) at box fraction (x, y);
-- `inset`: the px the top bar takes, which InputObject.Position leaves out.
local function tapAt(m: Mounted, pressed: string?, x: number, y: number, inset: number?): { string }
	local got = {}
	m.map:onSelect(function(id: string)
		table.insert(got, id)
	end)
	local root = m.map.root
	local at, size = root.AbsolutePosition, root.AbsoluteSize
	local input =
		{ Position = { X = at.X + x * size.X, Y = at.Y + y * size.X / MapShape.ASPECT - (inset or 0) } }
	local target = if pressed then button(m, pressed) else root.Nodes.MapTaps
	m.world.current = m.peer
	target.Activated.fire(input)
	m.world.current = nil
	FakeRoblox.run(m.world, 0.1)
	return got
end

describe("ShapeMap", function()
	it("draws every state as a tinted rect of its atlas", function()
		local m = mount(390, 244)
		expect(m.map.root.Name):toBe("NodeMap")
		expect(m.map.root:GetAttribute("Shapes")):toBe(true)
		for _, shape in MapShape.list() do
			local image = m.map.root.Shapes:FindFirstChild(`Shape{shape.id}`)
			check(image ~= nil, `no shape for {shape.id}`)
			expect(image:GetAttribute("MapShape")):toBe(shape.id)
			expect(image.ImageRectOffset.X):toBe(shape.ox)
			expect(image.ImageRectSize.Y):toBe(shape.oh)
		end
		local borders = m.map.root.Borders.BorderLines
		expect(borders:GetAttribute("Asset")):toBe("mapBorders")
		expect(borders.ImageColor3):toBe(m.Kit.colors.background)
	end)

	it("fills each state like the circles: poll leader's band, lean before polls", function()
		local m = mount(390, 244)
		local blue = { r = 70, g = 110, b = 220 }
		local red = { r = 220, g = 70, b = 80 }
		local Colors = require("@ui/Colors")
		local view = {
			states = {
				{ id = "OH", poll = { support = { 52, 40 }, undecided = 8 } },
				{ id = "TX", leanTo = 2, lean = 5 },
				{ id = "VT" },
			},
		}
		m.map:setView(view :: any, { blue, red })
		local root = m.map.root
		check(
			same(root.Shapes.ShapeOH.ImageColor3, m.Kit.color(Colors.bandFill({ 52, 40 }, { blue, red }))),
			"OH fill"
		)
		check(
			same(root.Shapes.ShapeTX.ImageColor3, m.Kit.color(Colors.bandFill({ 0, 5 }, { blue, red }))),
			"TX fill"
		)
		check(same(root.Shapes.ShapeVT.ImageColor3, m.Kit.color(Colors.neutral)), "VT fill")
		-- A callout state's chip wears the same fill.
		check(same(button(m, "VT").Chip.BackgroundColor3, m.Kit.color(Colors.neutral)), "VT chip fill")
	end)

	it("gives every state a tap target of at least 36 px; callouts get chips and one bracket", function()
		for _, size in { { 390, 244 }, { 340, 212 }, { 390, 312 }, { 340, 272 } } do
			local m = mount(size[1], size[2])
			settle(m)
			for _, shape in MapShape.list() do
				local hit = button(m, shape.id)
				local s = hit.AbsoluteSize
				check(s.X >= 35.5 and s.Y >= 35.5, `{shape.id} is {s.X}x{s.Y} at {size[1]}x{size[2]}`)
			end
			-- At rest: the bracket, no leader of its own on any chip.
			for _, id in MapLayout.LADDER do
				check(button(m, id):FindFirstChild("Chip") ~= nil, `{id} has no chip`)
				check(m.map.root.Leaders:FindFirstChild(`Leader{id}`) == nil, `{id} has a leader at rest`)
			end
			check(m.map.root.Leaders:FindFirstChild("Bracket1_1") ~= nil, "no bracket")
			-- Selected: its leader to its state.
			m.map:select("RI")
			check(m.map.root.Leaders:FindFirstChild("LeaderRI") ~= nil, "the selected chip has no leader")
			m.map:select(nil)
			check(
				m.map.root.Leaders:FindFirstChild("LeaderRI") == nil,
				"the leader stays after the selection"
			)
		end
	end)

	it("stands up on a phone in portrait: the tall layout, chips in two rows under the land", function()
		local m = mount(390, 400)
		m.map:setLens({})
		settle(m)
		local root = m.map.root
		expect(root:GetAttribute("Layout")):toBe("tall")
		local size = root.AbsoluteSize
		check(math.abs(size.X / size.Y - MapShape.TALL_ASPECT) < 0.02, `the box is {size.X}x{size.Y}`)
		local chips = {}
		for _, id in MapLayout.LADDER do
			table.insert(chips, button(m, id).Chip.AbsolutePosition)
		end
		-- Two rows, north to south in reading order (D-079: room for the plates).
		for k = 2, #chips do
			local sameRow = math.abs(chips[k].Y - chips[k - 1].Y) < 1
			check(
				(sameRow and chips[k].X > chips[k - 1].X) or chips[k].Y > chips[k - 1].Y + 1,
				"the chips are out of order"
			)
		end
		check(chips[#chips].Y > chips[1].Y + 1, "the chips are not in two rows")
		-- An iPad's map column keeps the wide layout.
		local wide = mount(620, 600)
		wide.map:setLens({})
		settle(wide)
		expect(wide.map.root:GetAttribute("Layout")):toBe("wide")
		-- The frame narrowing switches it.
		wide.stage.Size = UDim2.fromOffset(372, 400)
		wide.map:setLens({})
		settle(wide)
		expect(wide.map.root:GetAttribute("Layout")):toBe("tall")
		local hi = wide.map.root:FindFirstChild("InsetHI", true)
		check(hi ~= nil, "no Hawaii inset")
		-- Hawaii's islands are specks: its box is filled in its color, like a chip.
		check(hi.BackgroundTransparency < 1, "Hawaii's inset is not filled")
		expect(hi.BackgroundColor3):toBe(wide.map.root.Shapes.ShapeHI.ImageColor3)
	end)

	-- One plate per state (D-079): the code, then the value right after it on
	-- the same line, the same text size and spacing for every state, chips
	-- and insets included; a plate that does not fit moves whole.
	local function plateForm(m: Mounted, label: string): (number, number)
		local size, offs = nil, 0
		for _, record in StateData.list do
			local node = button(m, record.id)
			local plate, code, row = node.Plate, node.Label, node.Lens
			check(plate.Visible and code.Visible and row.Visible, `{label} {record.id}: no plate`)
			local p, c, r = plate.AbsolutePosition, code.AbsolutePosition, row.AbsolutePosition
			local ps, cs, rs = plate.AbsoluteSize, code.AbsoluteSize, row.AbsoluteSize
			-- The code first, the value right after it, on one line, inside the plate.
			check(
				c.X >= p.X - 0.5 and r.X + rs.X <= p.X + ps.X + 0.5,
				`{label} {record.id}: outside its plate`
			)
			check(math.abs((r.X - (c.X + cs.X)) - 2) < 0.6, `{label} {record.id}: not code then value`)
			check(
				math.abs((r.Y + rs.Y / 2) - (c.Y + cs.Y / 2)) < 0.6,
				`{label} {record.id}: the value is not on its code's line`
			)
			size = size or cs.Y
			check(math.abs(cs.Y - (size :: number)) < 0.5, `{label} {record.id}: a different size`)
			check(cs.Y >= 12 - 1e-6, `{label} {record.id}: under the 12 px floor`)
			if not MapShape.get(record.id).chip then
				local root = m.map.root
				local s = MapShape.layout(root:GetAttribute("Layout")).get(record.id) :: MapShape.Shape
				local ax = root.AbsolutePosition.X + s.lx * root.AbsoluteSize.X
				local ay = root.AbsolutePosition.Y + s.ly * root.AbsoluteSize.Y
				if ax < p.X or ax > p.X + ps.X or ay < p.Y or ay > p.Y + ps.Y then
					offs += 1
				end
			end
		end
		return size :: number, offs
	end

	it(
		"gives every state the same plate, code then votes, and no two overlap (phone, iPad, desktop)",
		function()
			for _, size in { { 390, 360 }, { 390, 244 }, { 620, 388 }, { 832, 520 } } do
				local m = mount(size[1], size[2])
				local lines = {}
				for _, record in StateData.list do
					local s = record.ev
					lines[record.id] = {
						parts = {
							{
								text = if s >= 13 then m.Kit.STAR .. tostring(s) else tostring(s),
								outlined = s >= 13,
							},
						},
					}
				end
				m.map:setLens(lines)
				settle(m)
				local label = `{size[1]}x{size[2]}`
				local px, offs = plateForm(m, label)
				expect(m.map.root:GetAttribute("PlateSize")):toBe(math.floor(px + 0.5))
				expect(m.map.root:GetAttribute("PlateLeaders")):toBe(offs)
				for i, a in StateData.list do
					for j = i + 1, #StateData.list do
						local b = StateData.list[j]
						local pa, pb = button(m, a.id).Plate, button(m, b.id).Plate
						check(not overlaps(pa, pb), `{label}: {a.id}'s plate overlaps {b.id}'s`)
					end
				end
			end
		end
	)

	it("settles a tap by outline, not by whichever square was pressed", function()
		local m = mount(390, 244)
		local oh = MapShape.get("OH") :: MapShape.Shape
		-- Inside Ohio, pressed through Indiana's square: Ohio.
		expect(tapAt(m, "IN", oh.lx, oh.ly)):toEqual({ "OH" })
		-- Under a ScreenGui that ignores the top bar (the app's), the inset is added back.
		m.stage.Parent.IgnoreGuiInset = true
		expect(tapAt(m, "IN", oh.lx, oh.ly, 58)):toEqual({ "OH" })
		m.stage.Parent.IgnoreGuiInset = false
		-- The open map inside Texas: Texas.
		local tx = MapShape.get("TX") :: MapShape.Shape
		expect(tapAt(m, nil, tx.lx, tx.ly)):toEqual({ "TX" })
		-- The open sea, nothing pressed: nothing.
		expect(tapAt(m, nil, 0.5, 0.995)):toEqual({})
		-- A chip's cell, through its neighbor's grown square: the nearest chip.
		local cx, cy = MapShape.labelAt("RI")
		expect(tapAt(m, "MA", cx, cy)):toEqual({ "RI" })
		-- No position (a gamepad press): the pressed square.
		local got = {}
		m.map:onSelect(function(id: string)
			table.insert(got, id)
		end)
		m.world.current = m.peer
		button(m, "WV").Activated.fire()
		m.world.current = nil
		FakeRoblox.run(m.world, 0.1)
		check(table.find(got, "WV") ~= nil, "a press without a position lost its state")
	end)

	it("outlines the selection in the accent and an owner's state in their color", function()
		local m = mount(390, 244)
		local red = rgb(m, 220, 70, 80)
		m.map:setMarks({ TX = { ring = red } })
		local tx = m.map.root.Outlines:FindFirstChild("OutlineTX")
		check(tx ~= nil and tx.Visible, "no ring around Texas")
		expect(tx:GetChildren()[1].BackgroundColor3):toBe(red)
		m.map:select("OH")
		local oh = m.map.root.Outlines:FindFirstChild("OutlineOH")
		check(oh ~= nil and oh.Visible, "no selection outline")
		expect(oh:GetChildren()[1].BackgroundColor3):toBe(m.Kit.colors.accent)
		expect(m.map.root.Shadows.SelectGlow.Visible):toBe(true)
		m.map:select(nil)
		expect(oh.Visible):toBe(false)
		-- A callout state's ring is its chip's edge.
		m.map:select("RI")
		expect(button(m, "RI").Chip:FindFirstChildOfClass("UIStroke").Color):toBe(m.Kit.colors.accent)
	end)

	it("shows the lens value where the state has room, the Polls marks in the same pill", function()
		local m = mount(832, 520)
		local blue, red = rgb(m, 70, 110, 220), rgb(m, 220, 70, 80)
		m.map:setLens({
			TX = {
				parts = { { text = "+5", color = red, filled = true } },
				momentum = red,
				momentumStrong = true,
				pips = { { count = 2, color = blue }, { count = 3, color = red, hollow = true } },
			},
			OH = { parts = { { text = "tie" } } },
			-- No value: no ▲, no pips (D-079).
			PA = { parts = {}, momentum = red, pips = { { count = 2, color = blue } } },
		})
		settle(m)
		local tx = button(m, "TX")
		expect(tx.Lens.Visible):toBe(true)
		expect(tx.Lens.Part1.Text):toBe("+5")
		expect(tx.Lens.Momentum.Visible):toBe(true)
		expect(tx.Lens.Momentum.Text):toBe("▲▲")
		expect(tx.Lens.Momentum.TextColor3):toBe(red)
		-- One plate: the code, the lead and its suffix.
		expect(tx.Plate.Visible):toBe(true)
		local yours, theirs = 0, 0
		for _, pip in tx.Lens.Pips:GetChildren() do
			if pip.Name == "Yours" then
				yours += 1
			elseif pip.Name == "Theirs" then
				theirs += 1
				expect(pip.BackgroundTransparency):toBe(1)
			end
		end
		expect(yours):toBe(2)
		expect(theirs):toBe(3)
		expect(button(m, "OH").Lens.Momentum.Visible):toBe(false)
		expect(button(m, "OH").Lens.BackgroundTransparency):toBe(1)
		expect(button(m, "PA").Lens.Visible):toBe(false)
		expect(button(m, "PA").Lens.Momentum.Visible):toBe(false)
		m.map:setLens({})
		settle(m)
		expect(tx.Lens.Visible):toBe(false)
	end)

	it("draws a missed poll dashed, an uncalled state hollow, a quiet state faded", function()
		local m = mount(832, 520)
		local red = rgb(m, 220, 70, 80)
		m.map:setMarks({ TX = { ring = red, dashed = true }, OH = { hollow = true } })
		m.map:setLens({ CA = { parts = {}, quiet = true } })
		settle(m)
		local root = m.map.root
		local tx = root.Outlines:FindFirstChild("OutlineTX")
		check(tx ~= nil and tx.Visible, "no dashed outline on Texas")
		local shown, hidden = 0, 0
		for _, part in tx:GetChildren() do
			if part.Visible then
				shown += 1
				expect(part.BackgroundColor3):toBe(red)
			else
				hidden += 1
			end
		end
		check(shown > 0 and hidden > 0, `Texas's outline is not dashed ({shown} on, {hidden} off)`)
		check(same(root.Shapes.ShapeOH.ImageColor3, m.Kit.colors.field), "Ohio is not hollow")
		local oh = root.Outlines:FindFirstChild("OutlineOH")
		check(oh ~= nil and oh.Visible, "a hollow state has no hairline")
		check(root.Shapes.ShapeCA.ImageTransparency > 0.5, "a quiet state is not faded")
	end)

	it("pins each candidate as a face, named only when the state is selected or the pin asks", function()
		local m = mount(832, 520)
		local blue, red = rgb(m, 70, 110, 220), rgb(m, 220, 70, 80)
		m.map:setPins({
			{ state = "PA", name = "Buster Cannonball", color = red, tag = "Buster" },
			{ state = "OH", name = "Goldie Pennywhistle", color = blue, tag = "You", you = true },
		})
		settle(m)
		local pins = m.map.root.Pins
		local mine = pins:FindFirstChild("PinOH")
		check(mine ~= nil, "no pin on Ohio")
		check(mine:FindFirstChild("Flag") == nil, "your pin is named at rest")
		check(mine:FindFirstChild("Monogram", true) ~= nil or mine:FindFirstChild("Face") ~= nil, "no face")
		-- Yours is a little bigger.
		check(
			mine.Face.AbsoluteSize.X > pins:FindFirstChild("PinPA").Face.AbsoluteSize.X,
			"your pin is not bigger"
		)
		-- Selecting its state names it.
		m.map:select("OH")
		settle(m)
		mine = pins:FindFirstChild("PinOH")
		expect(mine.Flag.Text):toBe("You")
		expect(mine.Flag.BackgroundColor3):toBe(blue)
		check(pins:FindFirstChild("PinPA"):FindFirstChild("Flag") == nil, "the rival's pin is named")
		m.map:select(nil)
		-- The first week names both (Pin.label).
		m.map:setPins({
			{
				state = "PA",
				name = "Buster Cannonball",
				candidate = "calloway",
				color = red,
				tag = "Buster",
				label = true,
			},
			{
				state = "OH",
				name = "Goldie Pennywhistle",
				candidate = "okafor",
				color = blue,
				tag = "You",
				you = true,
				label = true,
			},
		})
		settle(m)
		expect(pins:FindFirstChild("PinPA").Flag.Text):toBe("Buster")
		local face = pins:FindFirstChild("PinOH").Face
		local portrait = face:FindFirstChild("Portrait")
		check(portrait ~= nil, "no portrait on your pin")
		expect(portrait:GetAttribute("Portrait")):toBe("okafor")
		expect(portrait.Ring.Color):toBe(blue)
		expect(pins:FindFirstChild("PinPA").Face.Portrait:GetAttribute("Portrait")):toBe("calloway")
		-- Both in one state: side by side.
		m.map:setPins({
			{ state = "OH", name = "Buster Cannonball", color = red, tag = "Buster" },
			{ state = "OH", name = "Goldie Pennywhistle", color = blue, tag = "You", you = true },
		})
		settle(m)
		local both = pins:GetChildren()
		check(#both == 2 and not overlaps(both[1].Face, both[2].Face), "two pins in one state overlap")
		-- Pins never sit on a state's code.
		for _, pin in both do
			check(not overlaps(pin.Face, button(m, "OH").Label), "a pin covers Ohio's code")
		end
		m.map:setLegend({
			{ mark = "up", text = "momentum" },
			{ mark = "hollow", color = red, text = "ground game" },
		})
		expect(m.map.root.MapLegend.Visible):toBe(true)
		expect(#m.map.root.MapLegend:GetChildren() >= 2):toBe(true)
	end)

	it("shows the plan preview's faint tags on top: green gains, orange losses (D-071)", function()
		local m = mount(390, 244)
		m.map:setLens({
			TX = {
				parts = { { text = "+5" } },
				momentum = rgb(m, 220, 70, 80),
				pips = { { count = 2, color = rgb(m, 70, 110, 220) } },
			},
		})
		m.map:setPreview({
			TX = { text = "+4.1" },
			OH = { text = "-0.6", negative = true },
			RI = { text = "+1.2" },
		})
		settle(m)
		local layer = m.map.root.Preview
		check(layer.ZIndex > m.map.root.Pins.ZIndex, "the preview is not on top")
		local tx, oh, ri = layer.TX, layer.OH, layer.RI
		expect(tx.Text):toBe("+4.1")
		check(same(tx.TextColor3, m.Kit.colors.good), "a gain is not green")
		check(same(oh.TextColor3, m.Kit.colors.loss), "a loss is not orange")
		-- Beside Texas's code and its pill (on its line, on a phone), never on them.
		local tex = button(m, "TX")
		check(not overlaps(tx, tex.Lens), "the tag covers the lead")
		check(not overlaps(tx, tex.Label), "the tag covers the code")
		-- Two neighbors' preview tags never cover each other (D-079).
		m.map:setPreview({ PA = { text = "+9.4" }, OH = { text = "+5.4" }, WV = { text = "+1.2" } })
		settle(m)
		check(not overlaps(layer.PA, layer.OH), "PA's and OH's preview tags overlap")
		check(not overlaps(layer.OH, layer.WV), "OH's and WV's preview tags overlap")
		m.map:setPreview({
			TX = { text = "+4.1" },
			OH = { text = "-0.6", negative = true },
			RI = { text = "+1.2" },
		})
		settle(m)
		-- A callout's tag stands left of its chip.
		check(
			ri.AbsolutePosition.X + ri.AbsoluteSize.X <= button(m, "RI").Chip.AbsolutePosition.X + 1,
			"RI's tag covers its chip"
		)
		m.map:setPreview(nil)
		expect(tx.Visible):toBe(false)
		expect(oh.Visible):toBe(false)
	end)

	it("passes the strict audit on phone, iPad and smaller maps", function()
		for _, size in { { 390, 244 }, { 390, 312 }, { 340, 272 }, { 620, 388 }, { 832, 520 }, { 300, 188 } } do
			local m = mount(size[1], size[2])
			local blue, red = rgb(m, 70, 110, 220), rgb(m, 220, 70, 80)
			m.map:setMarks({
				OH = { badge = "H B G3 *", ring = m.Kit.colors.accent, arrow = "up" },
				DC = { badge = "1", dim = true, arrow = "down" },
				CA = { badge = "B", arrow = "up", halo = red, haloStrong = true },
				ME = { badge = "+1.5", note = "FLIP", noteColor = red },
				WA = { badge = "+2" },
				TX = { ring = red, dashed = true },
				NV = { hollow = true },
				NJ = { note = "▲", noteColor = blue },
			})
			m.map:setLens({
				TX = { parts = { { text = "+5", color = red, filled = true } }, momentum = red },
				PA = { parts = { { text = "tie" } }, pips = { { count = 4, color = blue } } },
				VT = { parts = { { text = "★3", outlined = true } } },
				CA = { parts = { { text = "$7.1", icon = "coins", iconColor = red } } },
				NY = { parts = { { text = "+3", color = blue, filled = true }, { text = "×" } } },
				KS = { parts = {}, quiet = true },
			})
			m.map:setPins({
				{ state = "WA", name = "Buster Cannonball", color = red, tag = "Buster" },
				{ state = "FL", name = "Goldie Pennywhistle", color = blue, tag = "You", you = true },
			})
			m.map:setLegend({
				{ mark = "none", text = "Plan: 268 → 281 votes" },
				{ mark = "none", text = "if nothing else changes", drop = 2 },
				{ mark = "up", text = "momentum" },
			})
			m.map:setPreview({
				TX = { text = "+4.1" },
				FL = { text = "-0.6", negative = true },
				DC = { text = "+1.0" },
				WA = { text = "+2.0" },
			})
			m.map:setRoute({ "OH", "PA", "NJ", "NY" }, { false, false, true, false })
			m.map:select("RI")
			m.map:badge("TX", "megaphone")
			settle(m)
			local problems = {}
			for _, finding in m.Audit.check(m.stage) do
				table.insert(problems, finding.message)
			end
			check(#problems == 0, `{size[1]}x{size[2]}: {table.concat(problems, " | ")}`)
			expect(m.Audit.run(m.stage, "NodeMap", { strict = true })):toBe(0)
			Rig.noErrors(m.world)
		end
	end)
end)
