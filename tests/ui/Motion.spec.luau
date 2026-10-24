--!strict
-- UI/Motion (docs/DESIGN.md D-053) on the fake engine: its stub TweenService
-- applies a tween's goals when it plays and reports Completed on the next
-- step, and the Heartbeat-driven effects run on the simulated clock. The specs
-- assert end states, never timings.

local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check
local UDim2 = FakeRoblox.types.UDim2

type Client = {
	world: FakeRoblox.World,
	peer: FakeRoblox.Peer,
	Kit: any,
	Motion: any,
	stage: any,
}

local MOTION = "src/client/UI/Motion.luau"

local function client(reduced: boolean?): Client
	local world, peer = Rig.fixture("Lobby", nil, { reducedMotion = reduced == true })
	local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
	local Motion = FakeRoblox.require(world, peer, MOTION)
	local gui = Kit.new("ScreenGui", { Name = "TestGui" })
	local stage = Kit.box({ Name = "Stage", Parent = gui })
	return { world = world, peer = peer, Kit = Kit, Motion = Motion, stage = stage }
end

-- Runs `fn` as the client (so its threads and sounds belong to it).
local function as(c: Client, fn: () -> ())
	c.world.current = c.peer
	fn()
	c.world.current = nil
end

local function run(c: Client, seconds: number)
	FakeRoblox.run(c.world, seconds, 0.05)
end

local function input(kind: string): any
	return { UserInputType = { Name = kind } }
end

local function same(a: any, b: any): boolean
	return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
end

describe("Motion tokens", function()
	it("has the timings and easings of the plan", function()
		local Motion = client().Motion
		local want = {
			press = 0.07,
			release = 0.12,
			fast = 0.12,
			base = 0.2,
			enter = 0.25,
			exit = 0.15,
			pop = 0.22,
			count = 0.5,
			beat = 0.35,
			call = 0.4,
			hero = 0.45,
		}
		for name, seconds in want do
			expect(Motion.t[name]):toBe(seconds)
		end
		for name in Motion.t do
			check(want[name] ~= nil, `Motion.t.{name} is not in the plan`)
		end
		expect(Motion.ease.out.style.Name):toBe("Quad")
		expect(Motion.ease.out.direction.Name):toBe("Out")
		expect(Motion.ease.in_.direction.Name):toBe("In")
		expect(Motion.ease.soft.style.Name):toBe("Quart")
		expect(Motion.ease.back.style.Name):toBe("Back")
		expect(Motion.ease.linear.style.Name):toBe("Linear")
	end)

	it("runs with the fake TweenService (not headless) and starts with full motion", function()
		local Motion = client().Motion
		expect(Motion.headless):toBe(false)
		expect(Motion.reduced()):toBe(false)
	end)
end)

describe("Motion reduced-motion switch", function()
	it("follows the in-game toggle and Roblox's setting, firing changed", function()
		local c = client()
		local Motion = c.Motion
		local seen: { boolean } = {}
		Motion.changed:Connect(function(value: boolean)
			table.insert(seen, value)
		end)
		Motion.setReduced(true)
		expect(Motion.reduced()):toBe(true)
		Motion.setReduced(false)
		expect(Motion.reduced()):toBe(false)
		FakeRoblox.setReducedMotion(c.world, true)
		expect(Motion.reduced()):toBe(true)
		FakeRoblox.setReducedMotion(c.world, false)
		expect(#seen):toBe(4)
		expect(seen[1]):toBe(true)
		expect(seen[2]):toBe(false)
		expect(seen[3]):toBe(true)
		expect(seen[4]):toBe(false)
	end)
end)

describe("Motion tweens", function()
	it("lands on the goals and lets a newer tween on a property win", function()
		local c = client()
		local frame = c.Kit.box({ Parent = c.stage })
		as(c, function()
			local cancel = c.Motion.tween(frame, { BackgroundTransparency = 0.5 })
			expect(type(cancel)):toBe("function")
			c.Motion.tween(frame, { BackgroundTransparency = 0.25 }, 0.1, c.Motion.ease.back)
		end)
		run(c, 0.3)
		expect(frame.BackgroundTransparency):toBe(0.25)
		Rig.noErrors(c.world)
	end)

	it("keeps Kit.tween working through Motion", function()
		local c = client()
		local frame = c.Kit.box({ Parent = c.stage })
		c.Kit.tween(frame, { Size = UDim2.fromOffset(10, 20) })
		expect(frame.Size.Y.Offset):toBe(20)
	end)
end)

describe("Motion scale effects", function()
	it("presses a chip to 0.96 while held and springs back, Activated unchanged", function()
		local c = client()
		local pressed = 0
		local button = c.Kit.button("Go", function()
			pressed += 1
		end, { variant = "chip", Parent = c.stage })
		as(c, function()
			button.InputBegan.fire(input("Touch"))
		end)
		local scale = button:FindFirstChild("MotionScale")
		check(scale ~= nil, "no UIScale after a press")
		expect(scale.Scale):toBe(c.Motion.PRESS_SCALE)
		as(c, function()
			button.InputEnded.fire(input("Touch"))
			button.Activated.fire()
		end)
		run(c, 0.2)
		expect(scale.Scale):toBe(1)
		expect(pressed):toBe(1)
		-- Keyboard or gamepad input is not a press.
		as(c, function()
			button.InputBegan.fire(input("Keyboard"))
		end)
		expect(scale.Scale):toBe(1)
		Rig.noErrors(c.world)
	end)

	it("presses a lipped button down onto its lip at 0.98 and back up (D-056)", function()
		local c = client()
		local button = c.Kit.button("Go", function() end, { variant = "primary", Parent = c.stage })
		as(c, function()
			button.InputBegan.fire(input("Touch"))
		end)
		expect(button:FindFirstChild("MotionScale").Scale):toBe(c.Motion.LIP_PRESS_SCALE)
		expect(button.Position.Y.Offset):toBe(c.Kit.LIP_PRIMARY)
		-- The holder stays put: only the face travels.
		local outer = c.Kit.outer(button).Position
		check(outer == nil or outer.Y.Offset == 0, "the holder moved")
		as(c, function()
			button.InputEnded.fire(input("Touch"))
		end)
		run(c, 0.2)
		expect(button.Position.Y.Offset):toBe(0)
		expect(button:FindFirstChild("MotionScale").Scale):toBe(1)
		Rig.noErrors(c.world)
	end)

	it("does not press a disabled button", function()
		local c = client()
		local button = c.Kit.button("Go", function() end, { variant = "primary", Parent = c.stage })
		c.Kit.setEnabled(button, false)
		as(c, function()
			button.InputBegan.fire(input("MouseButton1"))
		end)
		check(button:FindFirstChild("MotionScale") == nil, "a disabled button shrank")
	end)

	it("pops from a scale back to 1", function()
		local c = client()
		local pill = c.Kit.pill("New", "accent", { Parent = c.stage })
		as(c, function()
			c.Motion.pop(pill, 0.6)
		end)
		run(c, 0.3)
		expect(c.Motion.scale(pill).Scale):toBe(1)
		expect(#pill:GetChildren() > 0):toBe(true)
	end)
end)

describe("Motion enter, exit and stagger", function()
	it("enters a label back to its own transparency and position", function()
		local c = client()
		local label = c.Kit.text("Hello", {
			Parent = c.stage,
			Position = UDim2.fromOffset(0, 40),
			TextTransparency = 0.2,
		})
		as(c, function()
			c.Motion.enter(label)
		end)
		run(c, 0.4)
		expect(label.TextTransparency):toBe(0.2)
		expect(label.Position.Y.Offset):toBe(40)
		Rig.noErrors(c.world)
	end)

	it("exits a frame and calls onDone once it is gone", function()
		local c = client()
		local frame = c.Kit.panel({ Parent = c.stage })
		local done = 0
		as(c, function()
			c.Motion.exit(frame, function()
				done += 1
			end)
		end)
		run(c, 0.3)
		expect(frame.BackgroundTransparency):toBe(1)
		expect(done):toBe(1)
	end)

	it("hands each item a delay, the last at most 0.3 s", function()
		local c = client()
		local list = {}
		for k = 1, 20 do
			list[k] = k
		end
		local delays: { number } = {}
		c.Motion.stagger(list, function(_item: number, index: number, delay: number)
			delays[index] = delay
		end)
		expect(#delays):toBe(20)
		expect(delays[1]):toBe(0)
		check(delays[20] <= 0.3 + 1e-9, `the last delay is {delays[20]}`)
		check(delays[2] > 0, "no stagger")
		local short: { number } = {}
		c.Motion.stagger({ "a", "b", "c" }, function(_item: string, index: number, delay: number)
			short[index] = delay
		end)
		check(math.abs(short[3] - 0.08) < 1e-9, `3 items: the last delay is {short[3]}`)
	end)
end)

describe("Motion timed effects", function()
	it("counts a label to its end value", function()
		local c = client()
		local label = c.Kit.text("0", { Parent = c.stage })
		local function format(n: number): string
			return tostring(math.floor(n + 0.5))
		end
		as(c, function()
			c.Motion.countTo(label, 0, 270, format)
		end)
		run(c, 0.1)
		local mid = tonumber(label.Text) or -1
		check(mid > 0 and mid < 270, `mid-count the label says {label.Text}`)
		run(c, 0.6)
		expect(label.Text):toBe("270")
	end)

	it("flashes a text color and puts it back", function()
		local c = client()
		local label = c.Kit.text("Locked in", { Parent = c.stage })
		as(c, function()
			c.Motion.flash(label, c.Kit.colors.accent)
		end)
		run(c, 0.1)
		check(not same(label.TextColor3, c.Kit.colors.text), "no flash")
		run(c, 0.4)
		check(same(label.TextColor3, c.Kit.colors.text), "the color did not come back")
	end)

	it("sends out a decorative ring that removes itself", function()
		local c = client()
		local node = c.Kit.box({ Parent = c.stage, Size = UDim2.fromOffset(40, 40) })
		local ring
		as(c, function()
			ring = c.Motion.ring(node, c.Kit.colors.accent)
		end)
		check(ring ~= nil and ring.Parent == node, "no ring")
		expect(ring:GetAttribute("Decor")):toBe(true)
		run(c, 0.7)
		expect(ring.Parent):toBe(nil)
	end)

	it("shakes back to the resting position", function()
		local c = client()
		local bar = c.Kit.box({ Parent = c.stage, Position = UDim2.fromOffset(10, 0) })
		as(c, function()
			c.Motion.shake(bar)
		end)
		run(c, 0.05)
		run(c, 0.4)
		expect(bar.Position.X.Offset):toBe(10)
	end)

	it("drops at most 60 confetti pieces and cleans up", function()
		local c = client()
		local layer
		as(c, function()
			layer = c.Motion.confetti(c.stage, { c.Kit.colors.accent, c.Kit.colors.good }, 500)
		end)
		check(layer ~= nil, "no confetti")
		expect(#layer:GetChildren()):toBe(60)
		expect(layer:GetAttribute("Decor")):toBe(true)
		run(c, 1.4)
		expect(layer.Parent):toBe(nil)
	end)

	it("types a label out and can be skipped", function()
		local c = client()
		local label = c.Kit.text("Both plans are in", { Parent = c.stage })
		local skip
		as(c, function()
			skip = c.Motion.typewriter(label)
		end)
		run(c, 0.1)
		local shown = label.MaxVisibleGraphemes
		check(shown >= 0 and shown < 17, `typing shows {shown}`)
		skip()
		expect(label.MaxVisibleGraphemes):toBe(-1)
		run(c, 1)
		expect(label.MaxVisibleGraphemes):toBe(-1)
		Rig.noErrors(c.world)
	end)
end)

describe("Motion without a TweenService", function()
	it("is headless and lands every effect at once", function()
		local c = client()
		-- A fresh copy of the module on an engine with no TweenService.
		rawget(c.peer.game, "_services").TweenService = nil
		c.peer.modules[`{c.world.root}/{MOTION}`] = nil
		local Motion = FakeRoblox.require(c.world, c.peer, MOTION)
		expect(Motion.headless):toBe(true)
		local label = c.Kit.text("0", { Parent = c.stage })
		Motion.countTo(label, 0, 5, tostring)
		expect(label.Text):toBe("5")
		local frame = c.Kit.box({ Parent = c.stage })
		Motion.tween(frame, { BackgroundTransparency = 0.3 })
		expect(frame.BackgroundTransparency):toBe(0.3)
		local done = false
		Motion.exit(frame, function()
			done = true
		end)
		expect(done):toBe(true)
		expect(Motion.ring(frame, c.Kit.colors.accent)):toBe(nil)
		expect(Motion.confetti(frame, { c.Kit.colors.accent })):toBe(nil)
	end)
end)

describe("NodeMap motion API (circles)", function()
	it("pulses, rings, badges and wipes a state without touching the others", function()
		local c = client()
		local NodeMap = FakeRoblox.require(c.world, c.peer, "src/client/Map/NodeMap.luau")
		local map
		as(c, function()
			map = NodeMap.circles()
			map.root.Parent = c.stage
			map:pulse("OH", c.Kit.colors.accent)
			map:ring("TX", c.Kit.colors.good)
			map:badge("OH", "megaphone")
			map:wipe("PA", c.Kit.colors.danger)
			map:pulse("NOPE")
		end)
		local oh = map.root:FindFirstChild("OH", true)
		check(oh:FindFirstChild("PlanBadge") ~= nil, "no plan badge on OH")
		expect(oh.PlanBadge.Icon:GetAttribute("Icon")):toBe("megaphone")
		check(oh.Circle:FindFirstChild("Ring") ~= nil, "no ring from the pulse")
		run(c, 0.6)
		expect(oh.Circle.MotionScale.Scale):toBe(1)
		check(oh.Circle:FindFirstChild("Ring") == nil, "the ring stayed")
		local pa = map.root:FindFirstChild("PA", true)
		check(same(pa.Circle.BackgroundColor3, c.Kit.colors.danger), "the wipe did not fill PA")
		as(c, function()
			map:badge("OH", nil)
		end)
		check(oh:FindFirstChild("PlanBadge") == nil, "the badge stayed after badge(nil)")
		Rig.noErrors(c.world)
	end)
end)

describe("NodeMap motion API (real map, D-070)", function()
	it("pulses, rings, badges and wipes a state without touching the others", function()
		local c = client()
		local NodeMap = FakeRoblox.require(c.world, c.peer, "src/client/Map/NodeMap.luau")
		local map
		as(c, function()
			map = NodeMap.new()
			map.root.Parent = c.stage
			map:pulse("OH", c.Kit.colors.accent)
			map:ring("TX", c.Kit.colors.good)
			map:badge("OH", "megaphone")
			map:wipe("PA", c.Kit.colors.danger)
			map:pulse("NOPE")
		end)
		expect(map.root:GetAttribute("Shapes")):toBe(true)
		local oh = map.root.Nodes.OH
		check(oh:FindFirstChild("PlanBadge") ~= nil, "no plan badge on OH")
		expect(oh.PlanBadge.Icon:GetAttribute("Icon")):toBe("megaphone")
		check(oh:FindFirstChild("Ring") ~= nil, "no ring from the pulse")
		local shape = map.root.Shapes.ShapeOH
		check(shape:FindFirstChild("MotionScale") ~= nil, "the shape did not pulse")
		run(c, 0.6)
		expect(shape.MotionScale.Scale):toBe(1)
		check(oh:FindFirstChild("Ring") == nil, "the ring stayed")
		check(same(map.root.Shapes.ShapePA.ImageColor3, c.Kit.colors.danger), "the wipe did not fill PA")
		check(not same(map.root.Shapes.ShapeOH.ImageColor3, c.Kit.colors.danger), "the wipe spilled")
		as(c, function()
			map:badge("OH", nil)
		end)
		check(oh:FindFirstChild("PlanBadge") == nil, "the badge stayed after badge(nil)")
		Rig.noErrors(c.world)
	end)
end)

describe("Motion front-page effects (D-056)", function()
	it("lands a stamp from 1.6 and fades it in, the label ending opaque", function()
		local c = client()
		local stamp = c.Kit.stamp("CALLED", c.Kit.colors.accent, { Parent = c.stage })
		as(c, function()
			c.Motion.stamp(stamp)
		end)
		local scale = stamp:FindFirstChild("MotionScale")
		check(scale ~= nil, "no scale on a stamp")
		run(c, 0.5)
		expect(scale.Scale):toBe(1)
		expect(stamp:FindFirstChild("Label", true).TextTransparency):toBe(0)
		Rig.noErrors(c.world)
	end)

	it("sweeps a shine over the primary and stops it on cancel", function()
		local c = client()
		local button = c.Kit.button("Go", function() end, { variant = "primary", Parent = c.stage })
		local stop
		as(c, function()
			stop = c.Motion.shine(button)
		end)
		local band = button:FindFirstChild("Shine")
		check(band ~= nil and band:GetAttribute("Decor") == true, "no decorative shine band")
		run(c, c.Motion.SHINE_EVERY + 1)
		stop()
		check(button:FindFirstChild("Shine") == nil, "the shine stayed after cancel")
		Rig.noErrors(c.world)
	end)

	it("breathes a property and pulses once, and both stop cleanly", function()
		local c = client()
		local glow = c.Kit.glow(c.stage, c.Kit.colors.accent, { transparency = 0.65 })
		local label = c.Kit.text("Your turn", { Parent = c.stage })
		local stop
		as(c, function()
			stop = c.Motion.breathe(glow, "ImageTransparency", 0.65, 0.72, 2.4)
			c.Motion.pulseOnce(label)
		end)
		run(c, 1)
		stop()
		expect(glow.ImageTransparency):toBe(0.65)
		check(label:FindFirstChild("MotionScale") ~= nil, "no pulse scale")
		Rig.noErrors(c.world)
	end)
end)
