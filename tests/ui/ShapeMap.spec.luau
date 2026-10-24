--!strict
-- The real map (src/client/Map/ShapeMap.luau, D-062) on the fake engine: one
-- tinted shape per state from its atlas rect, a 36 px tap square per state and
-- a chip per callout state, taps settled by outline, outlines for selection and
-- rings, the Polls extras, candidate pins, the legend, and a clean strict audit.

local FakeRoblox = require("@testlib/FakeRoblox")
local MapLayout = require("@ui/MapLayout")
local MapShape = require("@ui/MapShape")
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

-- Two colors equal to the 1/255 (the fake engine's Color3s are tables).
local function same(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
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

	it("gives every state a tap target of at least 36 px; callouts get chips with leaders", function()
		for _, size in { { 390, 244 }, { 340, 212 } } do
			local m = mount(size[1], size[2])
			for _, shape in MapShape.list() do
				local hit = button(m, shape.id)
				local s = hit.AbsoluteSize
				check(s.X >= 35.5 and s.Y >= 35.5, `{shape.id} is {s.X}x{s.Y} at {size[1]}`)
			end
			for _, id in MapLayout.LADDER do
				check(button(m, id):FindFirstChild("Chip") ~= nil, `{id} has no chip`)
				check(m.map.root.Leaders:FindFirstChild(`Leader{id}`) ~= nil, `{id} has no leader`)
			end
			expect(#m.map.root.Leaders:GetChildren()):toBe(#MapLayout.LADDER)
		end
	end)

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

	it("shows the lens value where the state has room and the Polls extras under it", function()
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
		})
		local tx = button(m, "TX")
		expect(tx.Lens.Visible):toBe(true)
		expect(tx.Lens.Part1.Text):toBe("+5")
		expect(tx.Extras.Visible):toBe(true)
		expect(tx.Extras.Momentum.Text):toBe("▲▲")
		expect(tx.Extras.Momentum.TextColor3):toBe(red)
		local yours, theirs = 0, 0
		for _, pip in tx.Extras.Pips:GetChildren() do
			if pip.Name == "Yours" then
				yours += 1
			elseif pip.Name == "Theirs" then
				theirs += 1
				expect(pip.BackgroundTransparency):toBe(1)
			end
		end
		expect(yours):toBe(2)
		expect(theirs):toBe(3)
		expect(button(m, "OH").Extras.Visible):toBe(false)
		m.map:setLens({})
		expect(tx.Lens.Visible):toBe(false)
		expect(tx.Extras.Visible):toBe(false)
	end)

	it("pins each candidate on their state, yours flagged You, and shows the legend", function()
		local m = mount(832, 520)
		local blue, red = rgb(m, 70, 110, 220), rgb(m, 220, 70, 80)
		m.map:setPins({
			{ state = "PA", name = "Rex Calloway", color = red, tag = "Rex" },
			{ state = "OH", name = "Dana Okafor", color = blue, tag = "You", you = true },
		})
		local pins = m.map.root.Pins
		local mine = pins:FindFirstChild("PinOH")
		check(mine ~= nil, "no pin on Ohio")
		expect(mine.Flag.Text):toBe("You")
		expect(mine.Flag.BackgroundColor3):toBe(blue)
		check(mine:FindFirstChild("Monogram", true) ~= nil or mine:FindFirstChild("Face") ~= nil, "no face")
		expect(pins:FindFirstChild("PinPA").Flag.Text):toBe("Rex")
		-- Both in one state: side by side.
		m.map:setPins({
			{ state = "OH", name = "Rex Calloway", color = red, tag = "Rex" },
			{ state = "OH", name = "Dana Okafor", color = blue, tag = "You", you = true },
		})
		local xs = {}
		for _, pin in pins:GetChildren() do
			table.insert(xs, pin.Position.X.Scale)
		end
		check(#xs == 2 and xs[1] ~= xs[2], "two pins in one state overlap")
		m.map:setLegend({
			{ mark = "up", text = "momentum" },
			{ mark = "hollow", color = red, text = "ground game" },
		})
		expect(m.map.root.MapLegend.Visible):toBe(true)
		expect(#m.map.root.MapLegend:GetChildren() >= 2):toBe(true)
	end)

	it("shows the plan preview's faint tags on top: green gains, orange losses (D-063)", function()
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
		local layer = m.map.root.Preview
		check(layer.ZIndex > m.map.root.Pins.ZIndex, "the preview is not on top")
		local tx, oh, ri = layer.TX, layer.OH, layer.RI
		expect(tx.Text):toBe("+4.1")
		check(same(tx.TextColor3, m.Kit.colors.good), "a gain is not green")
		check(same(oh.TextColor3, m.Kit.colors.loss), "a loss is not orange")
		-- Under Texas's whole stack (code, lead, Polls row), so the marks stay readable.
		local extras = button(m, "TX").Extras
		check(
			tx.AbsolutePosition.Y >= extras.AbsolutePosition.Y + extras.AbsoluteSize.Y - 1,
			"the tag covers the Polls row"
		)
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
		for _, size in { { 390, 244 }, { 620, 388 }, { 832, 520 }, { 300, 188 } } do
			local m = mount(size[1], size[2])
			local blue, red = rgb(m, 70, 110, 220), rgb(m, 220, 70, 80)
			m.map:setMarks({
				OH = { badge = "H B G3 *", ring = m.Kit.colors.accent, arrow = "up" },
				DC = { badge = "1", dim = true, arrow = "down" },
				CA = { badge = "B", arrow = "up", halo = red, haloStrong = true },
				ME = { badge = "+1.5", note = "FLIP", noteColor = red },
				WA = { badge = "+2" },
			})
			m.map:setLens({
				TX = { parts = { { text = "+5", color = red, filled = true } }, momentum = red },
				PA = { parts = { { text = "tie" } }, pips = { { count = 4, color = blue } } },
				VT = { parts = { { text = "★3", outlined = true } } },
			})
			m.map:setPins({
				{ state = "WA", name = "Rex Calloway", color = red, tag = "Rex" },
				{ state = "FL", name = "Dana Okafor", color = blue, tag = "You", you = true },
			})
			m.map:setLegend({
				{ mark = "none", text = "Plan: 268 → 281 votes" },
				{ mark = "none", text = "if nothing else changes", optional = true },
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
