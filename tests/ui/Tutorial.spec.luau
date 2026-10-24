--!strict
-- The tutorial and bot timers on screen (D-075): a step without a deadline
-- reads "No timer" (no countdown, no bar, no "+15 s", never locks itself), an
-- Easy bot's plan counts down from twice the time, How to play's "Play the
-- tutorial" asks for it and brings the coach tips back, and the Lobby's Sound
-- and Reduce motion toggles sit in the top-right corner.

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")

local describe, it, expect = Test.describe, Test.it, Test.expect

local check, need, tap, shown = Rig.check, Rig.need, Rig.tap, Rig.shown
local C = Config.defaults

local SIZES = {
	{ name = "phone", screen = { x = 390, y = 844 } },
	{ name = "iPad", screen = { x = 1024, y = 768 } },
	{ name = "desktop", screen = { x = 1280, y = 720 } },
}

local function strictAudit(world: FakeRoblox.World, peer: FakeRoblox.Peer, screen: string): number
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	return Audit.run(FakeRoblox.find(peer, screen), screen, { strict = true })
end

-- Records every Net.send the client makes (the real one still runs).
local function spySends(world: FakeRoblox.World, peer: FakeRoblox.Peer): { { op: string, fields: any } }
	local sent = {}
	local net = Rig.netOf(world, peer)
	local real = net.send
	net.send = function(op: string, fields: any?)
		table.insert(sent, { op = op, fields = fields })
		real(op, fields)
	end
	return sent
end

local function rect(inst: any): (number, number, number, number)
	local pos, size = inst.AbsolutePosition, inst.AbsoluteSize
	return pos.X, pos.Y, pos.X + size.X, pos.Y + size.Y
end

local function overlaps(a: any, b: any): boolean
	local ax0, ay0, ax1, ay1 = rect(a)
	local bx0, by0, bx1, by1 = rect(b)
	return ax0 < bx1 - 0.5 and bx0 < ax1 - 0.5 and ay0 < by1 - 0.5 and by0 < ay1 - 0.5
end

describe("The tutorial on screen (D-075)", function()
	for _, size in SIZES do
		it(`the tutorial's plan reads "No timer", with no +15 s, on {size.name}`, function()
			local world, peer = Rig.fixture("PlanTutorial", size.screen)
			local payload = Rig.payloadOf(world, peer)
			expect(payload.deadline):toBe(nil)
			local timer = need(peer, "Campaign", "Countdown")
			check(shown(timer, "Campaign"), "the timer's place is empty")
			expect(timer.Text):toBe("No timer")
			expect(timer:GetAttribute("NoTimer")):toBe(true)
			expect(timer:GetAttribute("Warn")):toBe(false)
			local bar = Rig.findIn(peer, "Campaign", "TimerBar")
			check(bar == nil or not shown(bar, "Campaign"), "a time bar shows with no deadline")
			local bank = Rig.findIn(peer, "Campaign", "BankButton")
			check(bank == nil or not shown(bank, "Campaign"), "+15 s shows with no deadline")
			expect(strictAudit(world, peer, "Campaign")):toBe(0)
			Rig.noErrors(world)
		end)
	end

	it("a step with no deadline never locks itself, however long the player thinks", function()
		local world, peer = Rig.fixture("PlanTutorial", nil)
		local submits = Rig.spySubmits(world, peer)
		tap(world, peer, "Campaign", "OH") -- pick something, so there is a plan to lock
		FakeRoblox.run(world, 300)
		expect(#submits):toBe(0)
		expect(need(peer, "Campaign", "Countdown").Text):toBe("No timer")
		Rig.noErrors(world)
	end)

	it("the Easy bot's plan counts down from twice the plan timer, +15 s still there", function()
		local world, peer = Rig.fixture("PlanEasy", nil)
		local payload = Rig.payloadOf(world, peer)
		local length = payload.deadline - payload.stageStart
		check(math.abs(length - C.TIMER_PLAN * C.BOT_TIME_MULT_EASY) < 1e-6, `the plan is {length} s`)
		local timer = need(peer, "Campaign", "Countdown")
		check(string.match(timer.Text, "^1:%d%d$") ~= nil, `the countdown reads {timer.Text}`)
		expect(timer:GetAttribute("NoTimer")):toBe(nil)
		check(shown(need(peer, "Campaign", "BankButton"), "Campaign"), "no +15 s against the Easy bot")
		expect(strictAudit(world, peer, "Campaign")):toBe(0)
		Rig.noErrors(world)
	end)

	it("live: a new player's first bot match says No timer on Select and in the draft", function()
		local world, peer = Rig.practice(71, { tutorial = true })
		Rig.toDraftInput(world, peer)
		expect(Rig.payloadOf(world, peer).deadline):toBe(nil)
		expect(need(peer, "Draft", "Timer").Text):toBe("No timer")
		Rig.noErrors(world)
	end)
end)

describe("How to play: Play the tutorial (D-075)", function()
	it("asks for the tutorial against the Easy bot, brings the tips back and closes", function()
		local world, peer = Rig.practice(73)
		local CoachTip = FakeRoblox.require(world, peer, "src/client/UI/CoachTip.luau")
		CoachTip.markSeen("campaign.map")
		local sent = spySends(world, peer)
		tap(world, peer, "Lobby", "HowToPlay")
		local button = need(peer, "Lobby", "PlayTutorial")
		check(shown(button, "Lobby"), "no Play the tutorial button")
		expect(button.Text):toBe("Play the tutorial")
		check(
			string.find(need(peer, "Lobby", "TutorialHint").Text, "Easy bot", 1, true) ~= nil,
			"the hint does not say it is the Easy bot"
		)
		expect(strictAudit(world, peer, "Lobby")):toBe(0)
		tap(world, peer, "Lobby", "PlayTutorial")
		local practice = nil
		for _, entry in sent do
			if entry.op == "Practice" then
				practice = entry
			end
		end
		check(practice ~= nil, "no Practice request")
		expect(practice and practice.fields.tutorial):toBe(true)
		expect(practice and practice.fields.difficulty):toBe("Easy")
		expect(CoachTip.seen("campaign.map")):toBe(false)
		check(FakeRoblox.find(peer, "Select") ~= nil, "the tutorial did not start")
		Rig.noErrors(world)
	end)

	it("is on every page of the sheet", function()
		local world, peer = Rig.fixture("Lobby", nil)
		tap(world, peer, "Lobby", "HowToPlay")
		for _ = 1, 4 do
			check(shown(need(peer, "Lobby", "PlayTutorial"), "Lobby"), "Play the tutorial is missing")
			tap(world, peer, "Lobby", "HowToNext")
		end
		check(shown(need(peer, "Lobby", "PlayTutorial"), "Lobby"), "Play the tutorial is missing")
		Rig.noErrors(world)
	end)

	it("live: the replay starts a tutorial against the Easy bot", function()
		local world, peer = Rig.practice(72)
		tap(world, peer, "Lobby", "HowToPlay")
		tap(world, peer, "Lobby", "PlayTutorial", 1)
		check(FakeRoblox.find(peer, "Select") ~= nil, "the tutorial did not start")
		expect(Rig.count(world.server, "bot Easy, tutorial")):toBe(1)
		expect(Rig.payloadOf(world, peer).deadline):toBe(nil)
		expect(need(peer, "Select", "Timer").Text):toBe("No timer")
		Rig.noErrors(world)
	end)
end)

describe("Lobby: Sound and Reduce motion in the corner (D-075)", function()
	for _, size in SIZES do
		it(`sits top-right, clear of the column and the leaderboard, on {size.name}`, function()
			local world, peer = Rig.fixture("Lobby", size.screen)
			check(Rig.findIn(peer, "Lobby", "SoundChip") == nil, "the old Sound chip is still in the column")
			check(Rig.findIn(peer, "Lobby", "Settings") == nil, "the old settings row is still in the column")
			local corner = need(peer, "Lobby", "Toggles")
			local screen = FakeRoblox.find(peer, "Lobby")
			local sx0, sy0, sx1 = rect(screen)
			local cx0, cy0, cx1, cy1 = rect(corner)
			check(cx1 <= sx1 + 0.5 and cx1 >= sx1 - 1, `the corner ends at x {cx1}, the screen at {sx1}`)
			check(cy0 >= sy0 - 0.5 and cy0 <= sy0 + 1, `the corner starts at y {cy0}, the screen at {sy0}`)
			check(cx0 > (sx0 + sx1) / 2, "the corner is not on the right")
			check(cy1 - cy0 >= 44 - 0.5, "the corner is shorter than a touch target")
			for _, name in { "SoundToggle", "MotionToggle" } do
				local toggle = need(peer, "Lobby", name)
				check(
					toggle.AbsoluteSize.X >= 44 - 0.5 and toggle.AbsoluteSize.Y >= 44 - 0.5,
					`{name} is small`
				)
				check(shown(toggle, "Lobby"), `{name} is hidden`)
			end
			-- The leaderboard card beside the column (wide screens) is placed by
			-- hand, so the fake engine knows where it is; the column's list layout
			-- it does not lay out (the snapshots show the phone column).
			local card = Rig.findIn(peer, "Lobby", "LeaderboardCard")
			if card and card.Parent == screen and shown(card, "Lobby") then
				local ox0, oy0, ox1, oy1 = rect(card)
				check(
					not overlaps(corner, card),
					`the corner ({cx0},{cy0})-({cx1},{cy1}) covers the card ({ox0},{oy0})-({ox1},{oy1})`
				)
			end
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
			Rig.noErrors(world)
		end)
	end

	it("flips each setting, labels its state, and says what changed after a tap", function()
		local world, peer = Rig.fixture("Lobby", Rig.PHONE)
		local Audio = FakeRoblox.require(world, peer, "src/client/UI/Audio.luau")
		local Motion = FakeRoblox.require(world, peer, "src/client/UI/Motion.luau")
		local sound = need(peer, "Lobby", "SoundToggle")
		local motion = need(peer, "Lobby", "MotionToggle")
		local tip = need(peer, "Lobby", "SettingsTip")
		expect(sound:GetAttribute("On")):toBe(true)
		expect(sound:GetAttribute("Label")):toBe("Sound on")
		expect(motion:GetAttribute("On")):toBe(false)
		expect(motion:GetAttribute("Label")):toBe("Reduce motion off")
		check(not shown(tip, "Lobby"), "the tooltip shows before anything happened")

		tap(world, peer, "Lobby", "SoundToggle")
		expect(Audio.muted()):toBe(true)
		expect(sound:GetAttribute("On")):toBe(false)
		expect(sound:GetAttribute("Selected")):toBe(false)
		check(shown(tip, "Lobby"), "no tooltip after the tap")
		expect(tip.Text):toBe("Sound off")
		FakeRoblox.run(world, 2)
		check(not shown(tip, "Lobby"), "the tooltip never went away")

		tap(world, peer, "Lobby", "MotionToggle")
		expect(Motion.reduced()):toBe(true)
		expect(motion:GetAttribute("On")):toBe(true)
		expect(motion:GetAttribute("Selected")):toBe(true)
		expect(tip.Text):toBe("Reduce motion on")

		-- Hover (a mouse or a gamepad) shows the label until it leaves.
		world.current = peer
		sound.MouseEnter.fire()
		world.current = nil
		FakeRoblox.run(world, 3)
		check(shown(tip, "Lobby"), "no tooltip while hovering")
		expect(tip.Text):toBe("Sound off")
		world.current = peer
		sound.MouseLeave.fire()
		world.current = nil
		FakeRoblox.run(world, 0.2)
		check(not shown(tip, "Lobby"), "the tooltip stayed after the mouse left")

		tap(world, peer, "Lobby", "SoundToggle")
		tap(world, peer, "Lobby", "MotionToggle")
		expect(Audio.muted()):toBe(false)
		expect(Motion.reduced()):toBe(false)
		expect(strictAudit(world, peer, "Lobby")):toBe(0)
		Rig.noErrors(world)
	end)
end)
