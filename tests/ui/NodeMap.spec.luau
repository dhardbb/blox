--!strict
-- The node map (src/client/Map/NodeMap.luau) on the fake engine: 36 px tap
-- targets (B13), leaders for the Northeast ladder (B12), the momentum arrow
-- (Mark.arrow), and a clean strict audit on a phone-size map.

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

-- A NodeMap filling a `w` x `h` frame on a client.
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

	it("keeps each badge next to its label (Campaign reads the * badges this way)", function()
		local m = mount(390, 244)
		m.map:setMarks({ OH = { badge = "H *" } })
		local badge = hit(m, "OH"):FindFirstChild("Badge")
		expect(badge.Visible):toBe(true)
		expect(badge.Text):toBe("H *")
		expect(badge.Parent:FindFirstChild("Label").Text):toBe("OH")
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
end)
