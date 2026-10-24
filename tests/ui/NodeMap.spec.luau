--!strict
-- The circle map (src/client/Map/NodeMap.luau, NodeMap.circles: the fallback
-- until the real map's images are uploaded, D-062) on the fake engine: 36 px tap
-- targets (B13), leaders for the Northeast ladder (B12), the momentum arrow
-- (Mark.arrow), and a clean strict audit on a phone-size map. NodeMap.new()
-- picks the real map or the circles (last block); the real map is ShapeMap.spec.

local FakeRoblox = require("@testlib/FakeRoblox")
local MapLayout = require("@ui/MapLayout")
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
	stage: any, -- the frame the map fills
	map: any,
}

-- The circle map filling a `w` x `h` frame on a client.
local function mount(w: number, h: number): Mounted
	local world, peer = Rig.fixture("Lobby", nil)
	local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	local NodeMap = FakeRoblox.require(world, peer, "src/client/Map/NodeMap.luau")
	local gui = Kit.new("ScreenGui", { Name = "TestGui" })
	local stage = Kit.box({ Name = "Stage", Size = UDim2.fromOffset(w, h), Parent = gui })
	stage:SetAttribute("PrimaryOptional", true)
	local map = NodeMap.circles()
	map.root.Parent = stage
	return { world = world, peer = peer, Kit = Kit, Audit = Audit, stage = stage, map = map }
end

local function hits(m: Mounted): { any }
	local list = {}
	for _, child in m.map.root.Nodes:GetChildren() do
		if child:IsA("TextButton") then
			table.insert(list, child)
		end
	end
	return list
end

local function hit(m: Mounted, id: string): any
	local button = m.map.root.Nodes:FindFirstChild(id)
	check(button ~= nil, `no tap target {id}`)
	return button
end

describe("NodeMap", function()
	it("gives every state a tap target of at least 36 px (B13)", function()
		local m = mount(390, 244)
		expect(m.Kit.MAP_NODE_MIN):toBe(36)
		expect(MapLayout.MIN_HIT):toBe(m.Kit.MAP_NODE_MIN)
		local list = hits(m)
		expect(#list):toBe(#MapLayout.nodes())
		for _, button in list do
			local constraint = button:FindFirstChildOfClass("UISizeConstraint")
			check(constraint ~= nil, `{button.Name} has no size constraint`)
			check(
				constraint.MinSize.X >= 36 and constraint.MinSize.Y >= 36,
				`{button.Name} min size is {constraint.MinSize}`
			)
			local size = button.AbsoluteSize
			check(size.X >= 36 - 0.5 and size.Y >= 36 - 0.5, `{button.Name} is {size.X}x{size.Y}`)
		end
	end)

	it("draws a leader for each of the nine ladder states and no borders for them", function()
		local m = mount(390, 244)
		local leaders = m.map.root.Leaders:GetChildren()
		expect(#leaders):toBe(#MapLayout.LADDER)
		for _, id in MapLayout.LADDER do
			check(m.map.root.Leaders:FindFirstChild(`Leader{id}`) ~= nil, `no leader for {id}`)
		end
		local at: { [number]: boolean } = {}
		for i, n in MapLayout.nodes() do
			at[i] = n.ladder
		end
		local borders = 0
		for _, edge in MapLayout.edges() do
			if not at[edge[1]] and not at[edge[2]] then
				borders += 1
			end
		end
		expect(#m.map.root.Lines:GetChildren()):toBe(borders)
	end)

	it("puts each badge in a tag named by its state, above every node", function()
		local m = mount(390, 244)
		m.map:setMarks({ OH = { badge = "H *" } })
		local badge = m.map.root.Tags:FindFirstChild("OH")
		expect(badge.Visible):toBe(true)
		expect(badge.Text):toBe("H *")
		check(m.map.root.Tags.ZIndex > m.map.root.Nodes.ZIndex, "tags are under the nodes")
		expect(m.map.root.Tags:FindFirstChild("PA").Visible):toBe(false)
	end)

	it("joins a word to the badge and edges the tag in its color; a badge fills it", function()
		local m = mount(390, 244)
		local orange = m.Kit.colors.loss
		m.map:setMarks({ PA = { badge = "-1.5", badgeColor = orange, note = "FLIP", noteColor = orange } })
		local tag = m.map.root.Tags:FindFirstChild("PA")
		local edge = tag:FindFirstChildOfClass("UIStroke")
		expect(tag.Text):toBe("-1.5 FLIP")
		-- A flip: a dark plate, white text, a 2 px edge in the word's color.
		expect(tag.BackgroundColor3):toBe(m.Kit.colors.field)
		expect(tag.TextColor3):toBe(m.Kit.colors.text)
		expect(edge.Color):toBe(orange)
		expect(edge.Thickness):toBe(2)
		expect(hit(m, "PA"):FindFirstChild("Arrow").Visible):toBe(false)
		-- A loss: filled orange with a dark number and its own edge.
		m.map:setMarks({ PA = { badge = "-1.5", badgeColor = orange } })
		expect(tag.Text):toBe("-1.5")
		expect(tag.BackgroundColor3):toBe(orange)
		expect(tag.TextColor3):toBe(m.Kit.colors.onLoss)
		expect(edge.Color):toBe(m.Kit.colors.lossEdge)
		expect(edge.Thickness):toBe(1)
	end)

	it("lights the board: a stage glow, a shadow and a lip per state, a glow under the selection", function()
		local m = mount(390, 244)
		local root = m.map.root
		local stage = root:FindFirstChild("StageGlow")
		check(stage ~= nil and stage:GetAttribute("Decor") == true, "no decorative stage glow")
		local shadows = root.Shadows
		for _, n in MapLayout.nodes() do
			local shadow = shadows:FindFirstChild(`Shadow{n.id}`)
			check(shadow ~= nil and shadow:GetAttribute("Decor") == true, `{n.id} has no contact shadow`)
			check(shadows:FindFirstChild(`Lip{n.id}`) ~= nil, `{n.id} has no lip`)
		end
		check(shadows.ZIndex < root.Nodes.ZIndex, "the shadows are over the nodes")
		local glow = shadows:FindFirstChild("SelectGlow")
		expect(glow.Visible):toBe(false)
		m.map:select("OH")
		expect(glow.Visible):toBe(true)
		expect(glow.ImageColor3):toBe(m.Kit.colors.accent)
		m.map:select(nil)
		expect(glow.Visible):toBe(false)
	end)

	it("keeps each circle inside its layout size when the 36 px minimum grows its target", function()
		-- 340 px: narrower than MapLayout.PHONE_WIDTH, so small targets clamp to 36 px.
		local m = mount(340, 212)
		m.map:setMarks({})
		local width = m.map.root.AbsoluteSize.X
		for _, n in MapLayout.nodes() do
			local circle = hit(m, n.id).Circle
			local drawn = circle.AbsoluteSize.X
			check(
				drawn <= 2 * n.r * width + 0.5,
				`{n.id}'s circle is {drawn} px, its layout {2 * n.r * width}`
			)
		end
	end)

	it("keeps every tag inside the map", function()
		for _, size in { { 390, 244 }, { 1280, 800 } } do
			local m = mount(size[1], size[2])
			local marks = {}
			for _, button in hits(m) do
				marks[button.Name] = { badge = "+1.5", note = "FLIP" }
			end
			m.map:setMarks(marks)
			local box = m.map.root
			for _, tag in box.Tags:GetChildren() do
				local p, s = tag.AbsolutePosition, tag.AbsoluteSize
				check(
					p.X >= box.AbsolutePosition.X - 1
						and p.Y >= box.AbsolutePosition.Y - 1
						and p.X + s.X <= box.AbsolutePosition.X + box.AbsoluteSize.X + 1
						and p.Y + s.Y <= box.AbsolutePosition.Y + box.AbsoluteSize.Y + 1,
					`{tag.Name}'s tag leaves the map at {size[1]}x{size[2]}`
				)
			end
		end
	end)

	it("shows the momentum arrow only where a mark asks for it", function()
		local m = mount(390, 244)
		local arrow = hit(m, "PA"):FindFirstChild("Arrow")
		expect(arrow.Visible):toBe(false)
		local color = m.Kit.colors.danger
		m.map:setMarks({ PA = { arrow = "up", arrowColor = color }, OH = { ring = m.Kit.colors.accent } })
		expect(arrow.Visible):toBe(true)
		expect(arrow.Text):toBe("▲")
		expect(arrow.TextColor3):toBe(color)
		expect(hit(m, "OH"):FindFirstChild("Arrow").Visible):toBe(false)
		m.map:setMarks({ PA = { arrow = "down" } })
		expect(arrow.Text):toBe("▼")
		expect(arrow.TextColor3):toBe(m.Kit.colors.text)
		m.map:setMarks({})
		expect(arrow.Visible):toBe(false)
	end)

	it("puts the smaller of two overlapping targets on top", function()
		local m = mount(390, 244)
		local order: { [string]: number } = {}
		for k, button in hits(m) do
			order[button.Name] = k
		end
		check(
			order.RI > order.MA and order.DE > order.PA and order.WY > order.CA,
			"small states are not on top"
		)
	end)

	it("passes the strict audit on phone, desktop and smaller maps", function()
		-- 240x150: a landscape phone's map, where the 36 px minimum kicks in;
		-- 560x180: a box the aspect constraint would fix (the fake engine skips it).
		for _, size in { { 390, 244 }, { 832, 520 }, { 240, 150 }, { 560, 180 } } do
			local m = mount(size[1], size[2])
			m.map:setMarks({
				OH = { badge = "H B G3 *", ring = m.Kit.colors.accent, arrow = "up" },
				DC = { badge = "1", dim = true, arrow = "down" },
				CA = { badge = "B", arrow = "up" },
			})
			m.map:setRoute({ "OH", "PA", "NJ", "NY" }, { false, false, true, false })
			m.map:select("RI")
			local problems = {}
			for _, finding in m.Audit.check(m.stage) do
				table.insert(problems, finding.message)
			end
			check(#problems == 0, `{size[1]}x{size[2]}: {table.concat(problems, " | ")}`)
			expect(m.Audit.run(m.stage, "NodeMap", { strict = true })):toBe(0)
			Rig.noErrors(m.world)
		end
	end)

	it("is no longer pending in the audit", function()
		local m = mount(390, 244)
		expect(m.Audit.PENDING.NodeMap):toBe(nil)
	end)

	it("stands candidate pins on the circles and shows the legend row (D-062)", function()
		local m = mount(390, 244)
		local blue = m.Kit.color({ r = 70, g = 110, b = 220 })
		m.map:setPins({ { state = "OH", name = "Dana Okafor", color = blue, tag = "You", you = true } })
		local pin = m.map.root.Pins:FindFirstChild("PinOH")
		check(pin ~= nil, "no pin on OH")
		expect(pin.Flag.Text):toBe("You")
		m.map:setPins({})
		expect(#m.map.root.Pins:GetChildren()):toBe(0)
		m.map:setLegend({ { mark = "up", text = "momentum" } })
		expect(m.map.root.MapLegend.Visible):toBe(true)
		m.map:setLegend(nil)
		expect(m.map.root.MapLegend.Visible):toBe(false)
	end)

	it("shows the Polls lens's momentum as the arrow when no mark sets one", function()
		local m = mount(390, 244)
		local red = m.Kit.color({ r = 220, g = 70, b = 80 })
		m.map:setLens({ PA = { parts = {}, momentum = red } })
		local arrow = hit(m, "PA"):FindFirstChild("Arrow")
		expect(arrow.Visible):toBe(true)
		expect(arrow.TextColor3):toBe(red)
	end)
end)

describe("NodeMap.new", function()
	it("keeps the circles until the real map's images are uploaded", function()
		local world = FakeRoblox.world({ root = require("@lune/process").cwd, seed = 3 })
		local peer = FakeRoblox.join(world, "P", { DebugScreen = "Lobby" })
		FakeRoblox.run(world, 1)
		local NodeMap = FakeRoblox.require(world, peer, "src/client/Map/NodeMap.luau")
		local ShapeMap = FakeRoblox.require(world, peer, "src/client/Map/ShapeMap.luau")
		expect(ShapeMap.ready()):toBe(false)
		expect(NodeMap.preview):toBe(false)
		local circles = NodeMap.new()
		expect(circles.root:GetAttribute("Shapes")):toBe(nil)
		check(circles.root:FindFirstChild("Lines") ~= nil, "not the circle map")
		NodeMap.preview = true
		local shapes = NodeMap.new()
		expect(shapes.root:GetAttribute("Shapes")):toBe(true)
		expect(shapes.root.Name):toBe("NodeMap")
	end)
end)
