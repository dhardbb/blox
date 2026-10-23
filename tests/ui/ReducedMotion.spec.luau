--!strict
-- Reduced motion (docs/DESIGN.md D-053, GuiService.ReducedMotionEnabled): with
-- the player's setting on from the start, decorative motion (press, pop, ring,
-- shake, confetti) does nothing, informational motion lands on its end state,
-- and every screen ends up exactly as it does with full motion.

local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local function load(world: FakeRoblox.World, peer: FakeRoblox.Peer, path: string): any
	return FakeRoblox.require(world, peer, path)
end

-- Under a decorative frame (Motion's Ring, Confetti: Decor = true), which
-- full motion draws for a moment and reduced motion never does.
local function decor(inst: any, root: any): boolean
	local node = inst
	while node ~= nil and node ~= root do
		if node:GetAttribute("Decor") == true then
			return true
		end
		node = node.Parent
	end
	return false
end

-- What a screen shows, one line per visible element, in tree order.
local function picture(peer: FakeRoblox.Peer, screen: string): { string }
	local root = Rig.need(peer, "Screens", screen)
	local lines = {}
	for _, inst in root:GetDescendants() do
		if inst:IsA("GuiObject") and not decor(inst, root) then
			local text = if inst.ClassName == "TextLabel" or inst.ClassName == "TextButton"
				then tostring(inst.Text)
				else ""
			table.insert(
				lines,
				`{inst.Name}|{text}|{tostring(inst.Visible)}|{tostring(inst.BackgroundTransparency)}|{tostring(
					inst.TextTransparency
				)}|{tostring(inst.GroupTransparency)}`
			)
		end
	end
	return lines
end

describe("Reduced motion", function()
	it("is read from Roblox's setting", function()
		local world, peer = Rig.fixture("Select", nil, { reducedMotion = true })
		local Motion = load(world, peer, "src/client/UI/Motion.luau")
		expect(Motion.reduced()):toBe(true)
		Rig.noErrors(world)
	end)

	it("drops the decorative effects", function()
		local world, peer = Rig.fixture("Select", nil, { reducedMotion = true })
		local Kit = load(world, peer, "src/client/UI/Kit.luau")
		local Motion = load(world, peer, "src/client/UI/Motion.luau")
		world.current = peer
		local stage = Kit.box({ Name = "Stage", Parent = Kit.new("ScreenGui", { Name = "TestGui" }) })
		local button = Kit.button("Go", function() end, { variant = "primary", Parent = stage })
		button.InputBegan.fire({ UserInputType = { Name = "Touch" } })
		Motion.pop(button)
		Motion.shake(button)
		expect(Motion.ring(stage, Kit.colors.accent)):toBe(nil)
		expect(Motion.confetti(stage, { Kit.colors.accent })):toBe(nil)
		local NodeMap = load(world, peer, "src/client/Map/NodeMap.luau")
		local map = NodeMap.new()
		map.root.Parent = stage
		map:pulse("OH", Kit.colors.accent)
		map:badge("OH", "coins")
		world.current = nil
		check(button:FindFirstChild("MotionScale") == nil, "a button moved under reduced motion")
		local oh = map.root:FindFirstChild("OH", true)
		check(oh.PlanBadge ~= nil, "the badge itself is information: it must still show")
		check(oh.PlanBadge:FindFirstChild("MotionScale") == nil, "the badge popped")
		check(oh.Circle:FindFirstChild("Ring") == nil, "a ring under reduced motion")
		Rig.noErrors(world)
	end)

	it("lands the informational effects on their end state at once", function()
		local world, peer = Rig.fixture("Select", nil, { reducedMotion = true })
		local Kit = load(world, peer, "src/client/UI/Kit.luau")
		local Motion = load(world, peer, "src/client/UI/Motion.luau")
		local label = Kit.text("0")
		Motion.countTo(label, 0, 42, tostring)
		expect(label.Text):toBe("42")
		Motion.tween(label, { TextTransparency = 0.4 }, 5)
		expect(label.TextTransparency):toBe(0.4)
		local skip = Motion.typewriter(label)
		expect(label.MaxVisibleGraphemes):toBe(-1)
		skip()
		local done = false
		Motion.exit(label, function()
			done = true
		end)
		expect(done):toBe(true)
		local delays: { number } = {}
		Motion.stagger({ 1, 2, 3 }, function(_item: number, index: number, delay: number)
			delays[index] = delay
		end)
		expect(delays[3]):toBe(0)
	end)

	it("renders every fixture screen the same as with full motion", function()
		for _, moment in { "Lobby", "Select", "Plan", "Resolve", "Election", "Over" } do
			local world, peer = Rig.fixture(moment, nil)
			local reducedWorld, reducedPeer = Rig.fixture(moment, nil, { reducedMotion = true })
			FakeRoblox.run(world, 1)
			FakeRoblox.run(reducedWorld, 1)
			local Router = load(world, peer, "src/client/Router.luau")
			local screen = Router.pick(Rig.storeOf(world, peer).get())
			local full, reduced = picture(peer, screen), picture(reducedPeer, screen)
			check(#full == #reduced, `{moment}: {#full} elements vs {#reduced} under reduced motion`)
			for k, line in full do
				check(line == reduced[k], `{moment}: "{line}" vs "{reduced[k]}"`)
			end
			check(FakeRoblox.find(peer, "ScreenFade") == nil, `{moment}: the screen fade stayed`)
			Rig.noErrors(world)
			Rig.noErrors(reducedWorld)
		end
	end)

	it("follows the setting when it changes mid-match", function()
		local world, peer = Rig.fixture("Select", nil)
		local Motion = load(world, peer, "src/client/UI/Motion.luau")
		expect(Motion.reduced()):toBe(false)
		FakeRoblox.setReducedMotion(world, true)
		expect(Motion.reduced()):toBe(true)
		FakeRoblox.setReducedMotion(world, false)
		expect(Motion.reduced()):toBe(false)
	end)
end)
