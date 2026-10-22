--!strict
-- The DEBUG_UI layout audit (src/client/UI/Audit.luau) on small hand-built
-- trees: a compliant tree has no findings, each kind of violation gives exactly
-- one, the transitional PENDING list turns known findings into notes, and the
-- Router runs the audit only in Studio or debug mode, again after a rotation.

local process = require("@lune/process")

local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local UDim2 = FakeRoblox.types.UDim2

type Tree = {
	world: FakeRoblox.World,
	peer: FakeRoblox.Peer,
	Kit: any,
	Audit: any,
	root: any, -- a 400x300 screen root
	primary: any, -- its one pinned primary button
}

local function noop() end

-- A compliant 400x300 screen: a heading, a caption, a secondary and a primary.
local function tree(): Tree
	local world, peer = Rig.fixture("Lobby", nil)
	local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	local gui = Kit.new("ScreenGui", { Name = "TestGui" })
	local root = Kit.box({ Name = "TestScreen", Size = UDim2.fromOffset(400, 300), Parent = gui })
	Kit.heading("Choose your campaign", { Parent = root })
	Kit.caption("Pick a candidate, a color and three issues.", { Parent = root })
	Kit.button("Back", noop, {
		variant = "secondary",
		Size = UDim2.fromOffset(100, 44),
		Position = UDim2.fromOffset(0, 120),
		Parent = root,
	})
	local primary = Kit.button("Lock in", noop, {
		variant = "primary",
		Size = UDim2.fromOffset(400, 56),
		Position = UDim2.fromOffset(0, 240),
		Parent = root,
	})
	primary:SetAttribute("PrimaryAction", true)
	return { world = world, peer = peer, Kit = Kit, Audit = Audit, root = root, primary = primary }
end

local function rules(t: Tree): { string }
	local list = {}
	for _, finding in t.Audit.check(t.root) do
		table.insert(list, finding.rule)
	end
	table.sort(list)
	return list
end

local function expectRules(t: Tree, want: { string })
	local got = rules(t)
	table.sort(want)
	check(
		table.concat(got, ",") == table.concat(want, ","),
		`findings {table.concat(got, ",")}, want {table.concat(want, ",")}`
	)
end

describe("UI audit rules", function()
	it("finds nothing wrong with a compliant screen", function()
		expectRules(tree(), {})
	end)

	it("flags a button under 44 px tall or wide", function()
		local t = tree()
		t.Kit.new("TextButton", { Text = "", Size = UDim2.fromOffset(100, 30), Parent = t.root })
		expectRules(t, { "buttonHeight" })
		t = tree()
		t.Kit.new("TextButton", { Text = "", Size = UDim2.fromOffset(30, 50), Parent = t.root })
		expectRules(t, { "buttonWidth" })
	end)

	it("holds map nodes to 36 px instead of 44", function()
		local t = tree()
		local map = t.Kit.box({ Name = "NodeMap", Size = UDim2.fromOffset(200, 100), Parent = t.root })
		t.Kit.new("TextButton", { Name = "OH", Text = "", Size = UDim2.fromOffset(38, 38), Parent = map })
		expectRules(t, {})
		t.Kit.new("TextButton", { Name = "RI", Text = "", Size = UDim2.fromOffset(30, 40), Parent = map })
		expectRules(t, { "mapNodes" })
		expect(t.Audit.check(t.root)[1].onMap):toBe(true)
	end)

	it("flags truncated text", function()
		local t = tree()
		t.Kit.new("TextLabel", {
			Text = string.rep("x", 40),
			TextSize = 16,
			TextWrapped = false,
			Size = UDim2.fromOffset(60, 20),
			Parent = t.root,
		})
		expectRules(t, { "truncated" })
	end)

	it("flags scaled text that can shrink under 12 px", function()
		local t = tree()
		t.Kit.new("TextLabel", {
			Text = "0:21",
			TextSize = 16,
			TextScaled = true,
			Size = UDim2.fromOffset(60, 20),
			Parent = t.root,
		})
		expectRules(t, { "textFloor" })
		t = tree()
		local label = t.Kit.new("TextLabel", {
			Text = "0:21",
			TextSize = 16,
			TextScaled = true,
			Size = UDim2.fromOffset(60, 20),
			Parent = t.root,
		})
		t.Kit.new("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 16, Parent = label })
		expectRules(t, { "textFloor" })
	end)

	it("flags text under 12 px and sizes off the type scale", function()
		local t = tree()
		t.Kit.text("your home", { TextSize = 11, Parent = t.root })
		expectRules(t, { "textFloor", "typeScale" })
		t = tree()
		t.Kit.text("Round 4 of 8", { TextSize = 22, Parent = t.root })
		expectRules(t, { "typeScale" })
		t = tree()
		t.Kit.text(
			"270",
			{ TextSize = 72, TextScaled = true, Size = UDim2.fromOffset(200, 60), Parent = t.root }
		)
		expectRules(t, { "typeScale" })
	end)

	it("flags a box outside the screen or overhanging a fixed parent", function()
		local t = tree()
		t.Kit.panel({ Size = UDim2.fromOffset(50, 50), Position = UDim2.fromOffset(-10, 0), Parent = t.root })
		expectRules(t, { "contained" })
		t = tree()
		local bar = t.Kit.new("Frame", { Name = "Bar", Size = UDim2.fromOffset(100, 14), Parent = t.root })
		t.Kit.new("Frame", {
			Name = "Marker270",
			Size = UDim2.new(0, 3, 1, 8),
			AnchorPoint = FakeRoblox.types.Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Parent = bar,
		})
		expectRules(t, { "contained" })
	end)

	it("lets a scroll area overflow downwards but not sideways", function()
		local t = tree()
		local scroll = t.Kit.new("ScrollingFrame", { Size = UDim2.fromOffset(200, 100), Parent = t.root })
		t.Kit.box({ Name = "Tall", Size = UDim2.fromOffset(150, 600), Parent = scroll })
		expectRules(t, {})
		t.Kit.box({ Name = "Wide", Size = UDim2.fromOffset(260, 40), Parent = scroll })
		expectRules(t, { "contained" })
	end)

	it("wants exactly one pinned PrimaryAction unless the screen says it has none", function()
		local t = tree()
		t.primary:SetAttribute("PrimaryAction", nil)
		expectRules(t, { "primary" })
		t.root:SetAttribute("PrimaryOptional", true)
		expectRules(t, {})
		t = tree()
		local other = t.Kit.button("Skip", noop, {
			Size = UDim2.fromOffset(100, 44),
			Position = UDim2.fromOffset(200, 120),
			Parent = t.root,
		})
		other:SetAttribute("PrimaryAction", true)
		expectRules(t, { "primary" })
		t = tree()
		local scroll = t.Kit.new("ScrollingFrame", { Size = UDim2.fromOffset(400, 200), Parent = t.root })
		t.primary.Position = UDim2.fromOffset(0, 0)
		t.primary.Parent = scroll
		expectRules(t, { "primary" })
		t = tree()
		t.primary.Position = UDim2.fromOffset(0, 280)
		expectRules(t, { "contained", "primary" })
	end)

	it("allows one accent-filled button per screen", function()
		local t = tree()
		t.Kit.button("Ignore", noop, {
			BackgroundColor3 = t.Kit.colors.accent,
			Size = UDim2.fromOffset(100, 44),
			Position = UDim2.fromOffset(120, 120),
			Parent = t.root,
		})
		expectRules(t, { "oneAccent" })
	end)

	it("ignores hidden objects", function()
		local t = tree()
		local hidden = t.Kit.box({ Visible = false, Parent = t.root })
		t.Kit.new("TextButton", { Text = "", Size = UDim2.fromOffset(10, 10), Parent = hidden })
		t.Kit.text("tiny", { TextSize = 9, Visible = false, Parent = t.root })
		expectRules(t, {})
	end)
end)

describe("UI audit output and the transition list", function()
	local function lines(peer: FakeRoblox.Peer, part: string): number
		local n = 0
		for _, line in peer.log do
			if string.find(line, part, 1, true) then
				n += 1
			end
		end
		return n
	end

	it("reports a pending rule as a note, and as a problem when strict", function()
		local t = tree()
		t.primary:SetAttribute("PrimaryAction", nil)
		-- This world's own copy of Audit, so the entry does not leak into other specs.
		t.Audit.PENDING.Select = { primary = true }
		expect(t.Audit.run(t.root, "Select")):toBe(0)
		expect(lines(t.peer, "[270] UI audit Select pending primary: 1")):toBe(1)
		expect(lines(t.peer, "[270] UI audit Select: 0 problem(s), 1 pending")):toBe(1)
		expect(lines(t.peer, "WARN [270] UI audit Select")):toBe(0)
		expect(t.Audit.run(t.root, "Select", { strict = true })):toBe(1)
		expect(lines(t.peer, "WARN [270] UI audit Select: no visible PrimaryAction button")):toBe(1)
		expect(lines(t.peer, "[270] UI audit Select: 1 problem(s), 0 pending")):toBe(1)
	end)

	it("counts everything for a label with no pending entry", function()
		local t = tree()
		t.Kit.new("TextButton", { Text = "", Size = UDim2.fromOffset(100, 30), Parent = t.root })
		expect(t.Audit.run(t.root, "Brand new screen")):toBe(1)
		expect(lines(t.peer, "WARN [270] UI audit Brand new screen: button TextButton is 30px tall")):toBe(1)
	end)

	it("files map findings under NodeMap on every screen", function()
		local t = tree()
		local map = t.Kit.box({ Name = "NodeMap", Size = UDim2.fromOffset(200, 100), Parent = t.root })
		t.Kit.new("TextButton", { Name = "RI", Text = "", Size = UDim2.fromOffset(30, 30), Parent = map })
		-- The map itself is strict since WP1; pretend it is pending to test the filing.
		local saved = t.Audit.PENDING.NodeMap
		t.Audit.PENDING.NodeMap = { mapNodes = true }
		expect(t.Audit.run(t.root, "Brand new screen")):toBe(0)
		expect(t.Audit.run(t.root, "Brand new screen", { strict = true })):toBe(1)
		t.Audit.PENDING.NodeMap = saved
		expect(t.Audit.run(t.root, "Brand new screen")):toBe(1)
	end)

	it("does not judge a rotated segment by its unrotated box", function()
		local t = tree()
		local line = t.Kit.new("Frame", {
			AnchorPoint = FakeRoblox.types.Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(390, 150),
			Size = UDim2.fromOffset(200, 2),
			Parent = t.root,
		})
		expectRules(t, { "contained" })
		line.Rotation = 80
		expectRules(t, {})
	end)

	it("prints the number of distinct text sizes", function()
		local t = tree()
		t.Audit.run(t.root, "Sizes")
		-- heading 20, caption 13, button labels 16
		expect(lines(t.peer, "[270] UI audit Sizes: 0 problem(s), 0 pending, 3 text size(s)")):toBe(1)
	end)

	it("only lists screens and rules that exist", function()
		local t = tree()
		local known: { [string]: boolean } = {}
		for _, rule in t.Audit.RULES do
			known[rule] = true
		end
		local labels = { "NodeMap", "Lobby", "Select", "Draft", "Campaign", "Election", "Results" }
		for label, pending in t.Audit.PENDING do
			check(table.find(labels, label) ~= nil, `PENDING has an unknown screen {label}`)
			for rule in pending do
				check(known[rule] == true, `PENDING.{label} has an unknown rule {rule}`)
			end
		end
	end)
end)

describe("Router audit gating (B15)", function()
	local function audits(peer: FakeRoblox.Peer): number
		local n = 0
		for _, line in peer.log do
			if
				string.find(line, "[270] UI audit ", 1, true) and string.find(line, " problem(s)", 1, true)
			then
				n += 1
			end
		end
		return n
	end

	it("does not audit a live client outside Studio", function()
		local world = FakeRoblox.world({ root = process.cwd, seed = 3 })
		world.studio = false
		local peer = FakeRoblox.join(world, "A")
		FakeRoblox.run(world, 2)
		expect(audits(peer)):toBe(0)
		Rig.noErrors(world)
	end)

	it("audits outside Studio when DebugText or DebugScreen is set", function()
		local world = FakeRoblox.world({ root = process.cwd, seed = 3 })
		world.studio = false
		local text = FakeRoblox.join(world, "A", { DebugText = true })
		local screen = FakeRoblox.join(world, "B", { DebugScreen = "Select" })
		FakeRoblox.run(world, 2)
		expect(audits(text)):toBe(1)
		expect(audits(screen)):toBe(1)
	end)

	it("audits in Studio, and again after the screen rotates", function()
		local world, peer = Rig.fixture("Select", nil)
		expect(audits(peer)):toBe(1)
		FakeRoblox.run(world, 2)
		expect(audits(peer)):toBe(1)
		world.screen = Rig.PHONE
		FakeRoblox.run(world, 1.5)
		expect(audits(peer)):toBe(2)
		Rig.noErrors(world)
	end)
end)
