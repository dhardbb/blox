--!strict
-- The Landslide moment on Results (docs/DESIGN.md D-062): the pure decision and
-- words (Shared/UI/Landslide) and the stamp on the screen, for the winner, for
-- the loser (the rival's landslide) and never after an ordinary win.

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Landslide = require("@ui/Landslide")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local C = Config.defaults
local NAMES = { "Goldie", "Buster" }

local function share(payload: any): number
	local e = payload.view.election
	return e.ev[e.winner] / 538
end

describe("Landslide.moment", function()
	it("is nil after an ordinary win", function()
		local over = Fixtures.payload(C, "Over")
		check(share(over) <= C.LANDSLIDE_EV_SHARE, "the Over fixture is a landslide")
		expect(Landslide.moment(C, over.view, over.result, NAMES)):toBe(nil)
	end)

	it("is the viewer's own after a landslide win", function()
		local payload = Fixtures.payload(C, "Landslide")
		check(share(payload) > C.LANDSLIDE_EV_SHARE, "the Landslide fixture is not a landslide")
		local moment = Landslide.moment(C, payload.view, payload.result, NAMES)
		assert(moment ~= nil, "no landslide moment")
		expect(moment.winner):toBe(payload.you)
		expect(moment.mine):toBe(true)
		expect(moment.stamp):toBe("LANDSLIDE")
		expect(moment.eyebrow):toBe("You won by a")
		local ev = payload.view.election.ev[payload.you]
		expect(moment.line):toBe(`You took {ev} of 538 votes, over 70%.`)
	end)

	it("names the rival after their landslide", function()
		local payload = Fixtures.payload(C, "LandslideLoss")
		expect(payload.you):toBe(1)
		local moment = Landslide.moment(C, payload.view, payload.result, NAMES)
		assert(moment ~= nil, "no landslide moment for the loser")
		expect(moment.winner):toBe(2)
		expect(moment.mine):toBe(false)
		expect(moment.eyebrow):toBe("Buster won by a")
		check(string.find(moment.line, "^Buster took %d+ of 538 votes, over 70%%%.$") ~= nil, moment.line)
	end)

	it("is nil without an election result", function()
		local payload = Fixtures.payload(C, "Landslide")
		expect(Landslide.moment(C, payload.view, nil, NAMES)):toBe(nil)
		-- A forfeit is never a landslide, whatever the board says.
		expect(Landslide.moment(C, payload.view, { winner = payload.you, reason = "Forfeit" }, NAMES)):toBe(
			nil
		)
		-- The result and the count disagree: no stamp.
		expect(Landslide.moment(C, payload.view, { winner = 3 - payload.you, reason = "Election" }, NAMES)):toBe(
			nil
		)
	end)
end)

local function strictAudit(world: FakeRoblox.World, peer: FakeRoblox.Peer): number
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	return Audit.run(Rig.need(peer, "Screens", "Results"), "Results", { strict = true })
end

local function plateColor(peer: FakeRoblox.Peer): Color3
	local stamp = Rig.need(peer, "Results", "LandslideStamp")
	return stamp:FindFirstChild("Plate").BackgroundColor3
end

local function count(list: { string }, name: string): number
	local n = 0
	for _, entry in list do
		if entry == name then
			n += 1
		end
	end
	return n
end

describe("Results: the Landslide stamp", function()
	it("is not there after an ordinary win", function()
		local world, peer = Rig.fixture("Over", nil)
		expect(Rig.findIn(peer, "Results", "LandslideBox")):toBe(nil)
		expect(Rig.textOf(peer, "Results", "Banner")):toBe("You won")
		Rig.noErrors(world)
	end)

	it("stamps LANDSLIDE in the winner's color after a landslide win", function()
		local world, peer = Rig.fixture("Landslide", nil)
		local payload = Rig.payloadOf(world, peer)
		check(Rig.shown(Rig.need(peer, "Results", "LandslideBox"), "Results"), "no landslide box")
		expect(Rig.textOf(peer, "Results", "Banner")):toBe("You won")
		expect(Rig.textOf(peer, "Results", "LandslideLabel")):toBe("LANDSLIDE")
		expect(Rig.textOf(peer, "Results", "LandslideEyebrow")):toBe("YOU WON BY A")
		check(
			string.find(Rig.textOf(peer, "Results", "LandslideLine"), "of 538 votes, over 70%", 1, true)
				~= nil,
			Rig.textOf(peer, "Results", "LandslideLine")
		)
		local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
		expect(plateColor(peer)):toEqual(Kit.playerColor(payload.view, payload.you))
		-- It comes right under the banner, before the reason line.
		local box = Rig.need(peer, "Results", "LandslideBox")
		local banner = Rig.need(peer, "Results", "BannerBox")
		local reason = Rig.need(peer, "Results", "Reason")
		check(box.LayoutOrder == banner.LayoutOrder + 1, "the stamp is not right under the banner")
		check(reason.LayoutOrder > box.LayoutOrder, "the reason comes before the stamp")
		Rig.noErrors(world)
	end)

	it("plays the win, then a second hit as the stamp lands", function()
		local world, peer = Rig.fixture("Landslide", nil)
		FakeRoblox.run(world, 2)
		local sounds = Rig.sounds(peer)
		expect(count(sounds, "victory")):toBe(1)
		expect(count(sounds, "debateWin")):toBe(1)
		expect(count(sounds, "defeat")):toBe(0)
		Rig.noErrors(world)
	end)

	it("shows the loser the rival's landslide, in the rival's color, quietly", function()
		local world, peer = Rig.fixture("LandslideLoss", nil)
		local payload = Rig.payloadOf(world, peer)
		expect(Rig.textOf(peer, "Results", "Banner")):toBe("You lost")
		expect(Rig.textOf(peer, "Results", "LandslideLabel")):toBe("LANDSLIDE")
		expect(Rig.textOf(peer, "Results", "LandslideEyebrow")):toBe("BUSTER WON BY A")
		local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
		expect(plateColor(peer)):toEqual(Kit.playerColor(payload.view, 2))
		FakeRoblox.run(world, 2)
		local sounds = Rig.sounds(peer)
		expect(count(sounds, "defeat")):toBe(1)
		expect(count(sounds, "debateWin")):toBe(0)
		Rig.noErrors(world)
	end)

	it("audits clean, strictly, on a phone, an iPad and a desktop", function()
		for _, moment in { "Landslide", "LandslideLoss" } do
			for _, screen in { Rig.PHONE, { x = 1024, y = 768 }, { x = 1280, y = 720 } } do
				local world, peer = Rig.fixture(moment, screen)
				expect(strictAudit(world, peer)):toBe(0)
				Rig.noErrors(world)
			end
		end
	end)

	it("sweeps its light inside the tilted stamp, never past it", function()
		local world, peer = Rig.fixture("Landslide", nil)
		local Motion = FakeRoblox.require(world, peer, "src/client/UI/Motion.luau")
		FakeRoblox.run(world, Motion.SHINE_EVERY + 1)
		local plate = Rig.need(peer, "Results", "LandslideStamp"):FindFirstChild("Plate")
		local shine = plate:FindFirstChild("Shine")
		check(shine ~= nil, "no shine on the winner's stamp")
		-- A rotated parent clips nothing (GuiObject.ClipsDescendants): the light
		-- is a layer the plate's own size and shape, and only its gradient moves.
		expect(shine.Size):toEqual(FakeRoblox.types.UDim2.fromScale(1, 1))
		local at = shine.Position
		check(at == nil or (at.X.Scale == 0 and at.X.Offset == 0), "the light moved off the plate")
		local gradient = shine:FindFirstChildOfClass("UIGradient")
		check(gradient ~= nil and gradient.Offset.X > 0.5, "the gradient did not sweep across")
		local corner = plate:FindFirstChildOfClass("UICorner")
		if corner then
			local round = shine:FindFirstChildOfClass("UICorner")
			check(
				round ~= nil and round.CornerRadius == corner.CornerRadius,
				"the light's corners are square"
			)
		end
		Rig.noErrors(world)
	end)

	it("stops the shine and the breathing glow when the screen goes", function()
		local world = Rig.newWorld(3)
		-- Stand-ins for the two loops (set before the client loads Motion), each
		-- counting its stop. Only the stamp's: the action bar's primary has its own.
		local started, stopped = 0, 0
		for _, name in { "shine", "breathe" } do
			FakeRoblox.setModuleField(world, "src/client/UI/Motion.luau", name, function(inst: any): () -> ()
				if name == "shine" and inst.Name ~= "Plate" then
					return function() end
				end
				started += 1
				return function()
					stopped += 1
				end
			end)
		end
		local peer = FakeRoblox.join(world, "P", { DebugScreen = "Landslide" })
		FakeRoblox.run(world, 1.5)
		check(started >= 2, `the winner's stamp did not shine and breathe ({started})`)
		expect(stopped):toBe(0)
		Rig.tap(world, peer, "Results", "BackToLobby", 1)
		expect(Rig.findIn(peer, "Results", "LandslideStamp")):toBe(nil)
		expect(stopped):toBe(started)
		Rig.noErrors(world)
	end)

	it("lands at once under reduced motion", function()
		local world, peer = Rig.fixture("Landslide", nil, { reducedMotion = true })
		local label = Rig.need(peer, "Results", "LandslideLabel")
		expect(label.TextTransparency or 0):toBe(0)
		local scale = Rig.need(peer, "Results", "LandslideStamp"):FindFirstChild("MotionScale")
		check(scale == nil or scale.Scale == 1, "the stamp is still landing")
		Rig.noErrors(world)
	end)
end)
