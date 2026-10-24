--!strict
-- The Decision screen (D-044, src/client/Screens/Decision.luau) on the fake
-- engine: a Choice stance gets its own screen with its own countdown, a pinned
-- Lock in and nothing else (no state card, plan list or week card); one tap
-- picks, Lock in sends exactly { choice }; the map previews the pick; strict UI
-- audit at 16:9 and on a phone. (The debate focus is gone: D-072.)

local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local SIZES = {
	{ name = "16:9", screen = { x = 1280, y = 720 } },
	{ name = "phone", screen = Rig.PHONE },
}

local check = Rig.check
local function need(peer: FakeRoblox.Peer, name: string): any
	return Rig.need(peer, "Decision", name)
end
local function shown(inst: any): boolean
	return Rig.shown(inst, "Decision")
end
local function tap(world: FakeRoblox.World, peer: FakeRoblox.Peer, name: string)
	Rig.tap(world, peer, "Decision", name, 0.1)
end
local function textOf(peer: FakeRoblox.Peer, name: string): string
	return Rig.textOf(peer, "Decision", name)
end

local function strict(world: FakeRoblox.World, peer: FakeRoblox.Peer): { string }
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	local out = {}
	for _, finding in Audit.check(FakeRoblox.find(peer, "Decision")) do
		if not finding.onMap then
			table.insert(out, `{finding.rule}: {finding.message}`)
		end
	end
	return out
end

describe("Decision screen: on its own", function()
	for _, moment in { "Stance" } do
		for _, size in SIZES do
			it(`shows only the {moment} decision, its countdown and Lock in ({size.name})`, function()
				local world, peer = Rig.fixture(moment, size.screen)
				check(Rig.count(peer, "screen Decision") > 0, `{moment} did not route to the Decision screen`)
				check(Rig.count(peer, "UI audit Decision: 0 problem(s)") > 0, "no clean UI audit")
				local problems = strict(world, peer)
				check(#problems == 0, table.concat(problems, "; "))
				for _, name in { "StateCard", "PlanList", "WeekCard", "BankButton" } do
					check(Rig.findIn(peer, "Decision", name) == nil, `{name} crowds the Decision screen`)
				end
				check(shown(need(peer, "Countdown")), "no countdown")
				local lock = need(peer, "LockIn")
				check(shown(lock), "Lock in is hidden")
				check(
					lock.AbsolutePosition.Y + 56 <= size.screen.y + 0.5,
					`Lock in ends at {lock.AbsolutePosition.Y + 56} on a {size.screen.y} px screen`
				)
				local stage = textOf(peer, "StageLabel")
				expect(stage):toBe("Take a stance")
				check(shown(need(peer, "ChoiceRow")), "no choices")
				expect(textOf(peer, "NowText")):toBe("Pick a side: A, B or C")
				-- Every option is on the first screen, above the pinned bar (UI-STYLE §4.4).
				local names = { "ChoiceA", "ChoiceB", "ChoiceC" }
				local barTop = need(peer, "ActionBar").AbsolutePosition.Y
				for _, name in names do
					local option = need(peer, name)
					check(shown(option), `{name} is hidden`)
					check(
						option.AbsolutePosition.Y + option.AbsoluteSize.Y <= barTop + 0.5,
						`{name} ends at {option.AbsolutePosition.Y + option.AbsoluteSize.Y}, under the bar at {barTop}`
					)
				end
				Rig.noErrors(world)
			end)
		end
	end
end)

describe("Decision screen: a Choice stance", function()
	it("starts on the hedge, sends the tapped stance, and nothing else", function()
		local world, peer = Rig.fixture("Stance", nil)
		check(need(peer, "ChoiceC"):GetAttribute("Selected") == true, "C is not preselected")
		tap(world, peer, "WhyToggle")
		check(shown(need(peer, "ChoiceNeed")), "no states-you-need line")
		check(shown(need(peer, "ChoiceSummary")), "no summary of the stance on the map")
		tap(world, peer, "ChoiceB")
		tap(world, peer, "LockIn")
		expect(Rig.count(peer, "[270] DEBUG_UI submit")):toBe(1)
		expect(Rig.count(peer, "[270] DEBUG_UI submit choice=B")):toBe(1)
		expect(textOf(peer, "BarStatus")):toBe("Locked in · waiting for opponent")
		Rig.noErrors(world)
	end)

	it("Lock in without a tap sends the hedge", function()
		local world, peer = Rig.fixture("Stance", nil)
		tap(world, peer, "LockIn")
		expect(Rig.count(peer, "[270] DEBUG_UI submit")):toBe(1)
		expect(Rig.count(peer, "[270] DEBUG_UI submit choice=C")):toBe(1)
		Rig.noErrors(world)
	end)
end)

describe("Decision screen: a live practice match", function()
	it(
		"plays each debate round on the Debate screen and the stance in Choice weeks, then the plan",
		function()
			local world, peer = Rig.practice(5)
			Rig.toPlanInput(world, peer)
			local seen: { [string]: boolean } = {}
			local driven: { [number]: boolean } = {}
			local finished = FakeRoblox.runUntil(world, function()
				local p = Rig.payloadOf(world, peer)
				if p == nil then
					return false
				end
				if p.stage == "Over" or (p.view.phase == "Plan" and p.view.week >= 10) then
					return true
				end
				if p.stage == "Input" and not driven[p.step] then
					driven[p.step] = true
					if p.view.phase == "Decision" then
						seen[p.view.decision] = true
						if Rig.findIn(peer, "Decision", "LockIn") == nil then
							error(`the {p.view.decision} decision did not mount the Decision screen`)
						end
						Rig.tap(world, peer, "Decision", "LockIn", 0.05)
					elseif p.view.phase == "Debate" then
						seen.Debate = true
						if Rig.findIn(peer, "Debate", "LockIn") == nil then
							error("a debate round did not mount the Debate screen")
						end
						Rig.tap(world, peer, "Debate", "MoveAttack", 0.05)
						Rig.tap(world, peer, "Debate", "LockIn", 0.05)
					elseif p.view.phase == "Plan" then
						Rig.tap(world, peer, "Campaign", "LockIn", 0.05)
					end
				end
				return false
			end, Rig.MATCH_LIMIT)
			check(finished, "the match never reached week 10")
			check(seen.Debate == true, "no debate round came up")
			check(seen.Stance == true, "no stance came up")
			local debates = Rig.payloadOf(world, peer).view.debates
			check(#debates >= 2, "fewer than two debates")
			expect(debates[1].rounds[1].picks[Rig.payloadOf(world, peer).you]):toBe("Attack")
			Rig.noErrors(world)
		end
	)
end)

describe("Decision motion", function()
	it("pops a new decision's options in, and not under Reduce Motion", function()
		for _, moment in { "Stance" } do
			local world, peer = Rig.fixture(moment, nil)
			local options = {}
			for _, inst in Rig.need(peer, "Screens", "Decision"):GetDescendants() do
				if string.match(inst.Name, "^Choice[ABC]$") then
					if inst.Visible ~= false and inst:IsA("GuiButton") then
						table.insert(options, inst)
					end
				end
			end
			check(#options >= 2, `{moment}: {#options} options`)
			for _, option in options do
				local scale = option:FindFirstChild("MotionScale")
				check(scale ~= nil, `{moment}: {option.Name} did not pop in`)
				expect(scale.Scale):toBe(1)
			end
			Rig.noErrors(world)
			local calm, calmPeer = Rig.fixture(moment, nil, { reducedMotion = true })
			for _, inst in Rig.need(calmPeer, "Screens", "Decision"):GetDescendants() do
				check(inst.Name ~= "MotionScale", `{moment}: {inst.Parent.Name} moved under Reduce Motion`)
			end
			Rig.noErrors(calm)
		end
	end)
end)
