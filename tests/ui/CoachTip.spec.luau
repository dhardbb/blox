--!strict
-- UI/CoachTip placement (WP-C): a tip shown in a list (no `position`) gets an
-- explicit zero Position and AnchorPoint, so the headless engine and the UI
-- audit can lay it out (an empty Vector2 crashed the audit's rect math), and a
-- tip placed by `position` keeps what it was given. The copy rules are in
-- KitStyle.spec. Arrival (WP-3): a tip pops in and fades in to its resting
-- look, with a "select" pip unless it is quiet; under reduced motion it only
-- fades, and lands the same.

local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check
local UDim2 = FakeRoblox.types.UDim2
local Vector2 = FakeRoblox.types.Vector2

local function setup(): (FakeRoblox.World, FakeRoblox.Peer, any, any)
	local world, peer = Rig.fixture("Lobby", nil)
	local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
	local CoachTip = FakeRoblox.require(world, peer, "src/client/UI/CoachTip.luau")
	CoachTip.reset()
	CoachTip.setEnabled(true)
	local gui = Kit.new("ScreenGui", { Name = "TestGui" })
	local stage = Kit.stack({ Name = "Stage", Size = UDim2.fromScale(1, 1), Parent = gui })
	stage:SetAttribute("PrimaryOptional", true)
	return world, peer, CoachTip, stage
end

describe("CoachTip placement", function()
	it("sets a zero Position and AnchorPoint in a list, and the audit can measure it", function()
		local world, peer, CoachTip, stage = setup()
		local tip = CoachTip.show(stage, { id = "reveal.week", order = 1 })
		check(tip ~= nil, "the tip did not show")
		local root = tip.root
		expect(root.AnchorPoint.X):toBe(0)
		expect(root.AnchorPoint.Y):toBe(0)
		expect(root.Position.X.Scale):toBe(0)
		expect(root.Position.X.Offset):toBe(0)
		expect(root.Position.Y.Offset):toBe(0)
		local _ = root.AbsolutePosition -- crashed with an empty AnchorPoint
		local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
		local findings = Audit.check(stage, { style = true })
		local problems = {}
		for _, finding in findings do
			table.insert(problems, `{finding.rule}: {finding.message}`)
		end
		check(#problems == 0, table.concat(problems, "; "))
		Rig.noErrors(world)
	end)

	it("keeps a given position and anchor", function()
		local world, _, CoachTip, stage = setup()
		local tip = CoachTip.show(stage, {
			id = "election.night",
			position = UDim2.new(1, -8, 0, 8),
			anchorPoint = Vector2.new(1, 0),
			width = 300,
		})
		check(tip ~= nil, "the tip did not show")
		expect(tip.root.AnchorPoint.X):toBe(1)
		expect(tip.root.Position.X.Offset):toBe(-8)
		Rig.noErrors(world)
	end)
end)

describe("CoachTip arrival", function()
	local function selects(peer: FakeRoblox.Peer): number
		local n = 0
		for _, cue in Rig.sounds(peer) do
			if cue == "select" then
				n += 1
			end
		end
		return n
	end

	local function show(
		world: FakeRoblox.World,
		peer: FakeRoblox.Peer,
		CoachTip: any,
		stage: any,
		options: any
	): any
		world.current = peer
		local tip = CoachTip.show(stage, options)
		world.current = nil
		FakeRoblox.run(world, 0.5)
		return tip
	end

	it("pops and fades in to its resting look with one pip", function()
		local world, peer, CoachTip, stage = setup()
		local before = selects(peer)
		local tip = show(world, peer, CoachTip, stage, { id = "reveal.week", order = 1 })
		check(tip ~= nil, "the tip did not show")
		expect(selects(peer)):toBe(before + 1)
		expect(tip.root.BackgroundTransparency):toBe(0)
		local scale = tip.root:FindFirstChild("MotionScale")
		check(scale == nil or scale.Scale == 1, "the tip is still popping")
		Rig.noErrors(world)
	end)

	it("stays silent when quiet", function()
		local world, peer, CoachTip, stage = setup()
		local before = selects(peer)
		local tip = show(world, peer, CoachTip, stage, { id = "reveal.week", order = 1, quiet = true })
		check(tip ~= nil, "the tip did not show")
		expect(selects(peer)):toBe(before)
		Rig.noErrors(world)
	end)

	it("lands the same under reduced motion", function()
		local world, peer, CoachTip, stage = setup()
		FakeRoblox.setReducedMotion(world, true)
		local tip = show(world, peer, CoachTip, stage, { id = "election.night", order = 1 })
		check(tip ~= nil, "the tip did not show")
		expect(tip.root.BackgroundTransparency):toBe(0)
		local scale = tip.root:FindFirstChild("MotionScale")
		check(scale == nil or scale.Scale == 1, "the tip popped under reduced motion")
		Rig.noErrors(world)
	end)
end)
