--!strict
-- The Decision screen (D-044, src/client/Screens/Decision.luau) on the fake
-- engine: the debate focus and a Choice stance each get their own screen with
-- its own countdown, a pinned Lock in and nothing else (no state card, plan list
-- or week card); one tap picks, Lock in sends exactly { focus } or { choice };
-- the map previews the pick; strict UI audit at 16:9 and on a phone.

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Numbers = require("@ui/Numbers")
local Rig = require("./Rig")
local Swing = require("@ui/Swing")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
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

-- The number in a state's map tag, without the " FLIP" a flip adds.
local function badgeOf(peer: FakeRoblox.Peer, id: string): string?
	local tag = need(peer, "NodeMap"):FindFirstChild("Tags"):FindFirstChild(id)
	check(tag ~= nil, `no tag on map node {id}`)
	return if tag.Visible then (string.gsub(tag.Text, " FLIP$", "")) else nil
end

describe("Decision screen: on its own", function()
	for _, moment in { "Focus", "Stance" } do
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
				expect(stage):toBe(if moment == "Focus" then "Debate focus" else "Take a stance")
				check(
					shown(need(peer, if moment == "Focus" then "FocusPanel" else "ChoiceRow")),
					"no choices"
				)
				Rig.noErrors(world)
			end)
		end
	end
end)

describe("Decision screen: the debate focus", function()
	it("shows each topic's states, EV and the ones you need, as Swing.focus says", function()
		local world, peer = Rig.fixture("Focus", nil)
		local view = Rig.payloadOf(world, peer).view
		local topics = view.nextDebate.topics
		expect(#topics):toBe(C.DEBATE_TOPICS)
		for t, topic in topics do
			local info = Swing.focus(C, view, topic)
			local button = need(peer, `FocusTopic{t}`)
			expect(button.Text):toBe(info.head)
			check(button.AbsoluteSize.Y >= 44 - 0.5, `FocusTopic{t} is {button.AbsoluteSize.Y}px tall`)
			expect(textOf(peer, `FocusNeed{t}`)):toBe(info.needLine)
			expect(textOf(peer, `FocusOdds{t}`)):toBe(info.oddsLine)
			expect(textOf(peer, `FocusWin{t}`)):toBe(info.winLine)
		end
		Rig.noErrors(world)
	end)

	it("needs one tap on a topic, then Lock in sends exactly that focus", function()
		local world, peer = Rig.fixture("Focus", nil)
		local topics = Rig.payloadOf(world, peer).view.nextDebate.topics
		-- Nothing picked: Lock in says what is missing (the default is no focus).
		check(need(peer, "LockIn").Active == false, "Lock in is enabled with no topic picked")
		expect(textOf(peer, "LockIn")):toBe("Pick a topic")
		tap(world, peer, "FocusTopic2")
		check(need(peer, "FocusTopic2"):GetAttribute("Selected") == true, "the tapped topic is not selected")
		check(need(peer, "FocusTopic1"):GetAttribute("Selected") ~= true, "another topic is selected")
		check(need(peer, "LockIn").Active ~= false, "Lock in is still disabled")
		tap(world, peer, "LockIn")
		expect(Rig.count(peer, "[270] DEBUG_UI submit")):toBe(1)
		expect(Rig.count(peer, `[270] DEBUG_UI submit focus={topics[2]}`)):toBe(1)
		for t = 1, C.DEBATE_TOPICS do
			check(need(peer, `FocusTopic{t}`).Active == false, `FocusTopic{t} is still enabled after locking`)
		end
		expect(textOf(peer, "BarStatus")):toBe("Locked in · waiting for opponent")
		Rig.noErrors(world)
	end)

	it("previews the picked topic's states on the map", function()
		local world, peer = Rig.fixture("Focus", nil)
		local view = Rig.payloadOf(world, peer).view
		local topic = view.nextDebate.topics[1]
		tap(world, peer, "FocusTopic1")
		local info = Swing.focus(C, view, topic)
		for _, id in info.states do
			expect(badgeOf(peer, id)):toBe(Numbers.signed(C.DEBATE_TOPIC_WIN))
		end
		check(Rig.contains(textOf(peer, "Caption"), "win"), textOf(peer, "Caption"))
		Rig.noErrors(world)
	end)
end)

describe("Decision screen: a Choice stance", function()
	it("starts on the hedge, sends the tapped stance, and nothing else", function()
		local world, peer = Rig.fixture("Stance", nil)
		check(need(peer, "ChoiceC"):GetAttribute("Selected") == true, "C is not preselected")
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
	it("plays the focus before each debate and the stance in Choice weeks, then the plan", function()
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
					if p.view.decision == "Focus" then
						Rig.tap(world, peer, "Decision", "FocusTopic1", 0.05)
					end
					Rig.tap(world, peer, "Decision", "LockIn", 0.05)
				elseif p.view.phase == "Plan" then
					Rig.tap(world, peer, "Campaign", "LockIn", 0.05)
				end
			end
			return false
		end, Rig.MATCH_LIMIT)
		check(finished, "the match never reached week 10")
		check(seen.Focus == true, "no debate focus came up")
		check(seen.Stance == true, "no stance came up")
		local debates = Rig.payloadOf(world, peer).view.debates
		check(#debates >= 2, "fewer than two debates")
		expect(debates[1].focus[Rig.payloadOf(world, peer).you]):toBe(1)
		Rig.noErrors(world)
	end)
end)
