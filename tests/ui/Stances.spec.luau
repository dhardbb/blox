--!strict
-- The screens for stances and debates (D-042) on the fake engine: a Choice week
-- previews the selected (or held) stance on the map with badges, glows and FLIP
-- calls, and says which states you need; the debate reveal names the states each
-- topic swung and calls out every flip and gaffe; the resolve reveal after a
-- Choice week does the same for both stances; Results says what debates and
-- stances decided. Every moment passes the strict UI audit at 1280x720, 844x390
-- and 390x844. The words themselves are Swing.spec's job: here the screens must
-- show exactly what Shared/UI/Swing says.

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Numbers = require("@ui/Numbers")
local Rig = require("./Rig")
local State = require("@sim/State")
local Swing = require("@ui/Swing")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local SIZES = {
	{ name = "1280x720", screen = { x = 1280, y = 720 } },
	{ name = "844x390", screen = { x = 844, y = 390 } },
	{ name = "390x844", screen = Rig.PHONE },
}
local DEBATE_DONE = 8 -- s, every debate topic is shown by then
local RESOLVE_DONE = 30 -- s, the resolve reveal has listed every event by then

local check = Rig.check

-- The screen the helpers look in: the stance is taken on the Decision screen
-- (D-044), everything else here is on Campaign. `open` sets it.
local SCREEN = "Campaign"

local function open(moment: string, screen: { x: number, y: number }?): (FakeRoblox.World, FakeRoblox.Peer)
	SCREEN = if moment == "Stance" or moment == "Focus" then "Decision" else "Campaign"
	return Rig.fixture(moment, screen)
end

local function need(peer: FakeRoblox.Peer, name: string): any
	return Rig.need(peer, SCREEN, name)
end
local function textOf(peer: FakeRoblox.Peer, name: string): string
	return Rig.textOf(peer, SCREEN, name)
end
local function shown(inst: any): boolean
	return Rig.shown(inst, SCREEN)
end
local function tap(world: FakeRoblox.World, peer: FakeRoblox.Peer, name: string)
	Rig.tap(world, peer, SCREEN, name, 0.1)
end

local function same(a: any, b: any): boolean
	return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
end

local function kitOf(world: FakeRoblox.World, peer: FakeRoblox.Peer): any
	return FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
end

-- The map node for state `id` and one of its parts (Badge, Arrow, Halo). The
-- badge is the node's tag in the map's Tags layer.
local function nodePart(peer: FakeRoblox.Peer, id: string, part: string): any
	local map = need(peer, "NodeMap")
	if part == "Badge" then
		local tag = map:FindFirstChild("Tags"):FindFirstChild(id)
		check(tag ~= nil, `no tag on map node {id}`)
		return tag
	end
	for _, inst in map:GetDescendants() do
		if inst.Name == id and inst.ClassName == "TextButton" then
			for _, child in inst:GetChildren() do
				if child.Name == part then
					return child
				end
			end
		end
	end
	error(`no {part} on map node {id}`)
end

-- The number in a state's tag, without the " FLIP" a flip adds.
local function badgeOf(peer: FakeRoblox.Peer, id: string): string?
	local badge = nodePart(peer, id, "Badge")
	return if badge.Visible then (string.gsub(badge.Text, " FLIP$", "")) else nil
end

-- The color a state's tag is in: its text, or its fill once it says FLIP.
local function tagColor(peer: FakeRoblox.Peer, id: string): Color3
	local badge = nodePart(peer, id, "Badge")
	return if string.find(badge.Text, "FLIP", 1, true) then badge.BackgroundColor3 else badge.TextColor3
end

local function strict(world: FakeRoblox.World, peer: FakeRoblox.Peer, rootName: string): { string }
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	local root = FakeRoblox.find(peer, rootName)
	check(root ~= nil, `no {rootName}`)
	local out = {}
	for _, finding in Audit.check(root) do
		if not finding.onMap then
			table.insert(out, `{finding.rule}: {finding.message}`)
		end
	end
	return out
end

local function fire(inst: any, signal: string, inputType: string)
	inst[signal].fire({ UserInputType = { Name = inputType } })
end

local function viewOf(world: FakeRoblox.World, peer: FakeRoblox.Peer): any
	return Rig.payloadOf(world, peer).view
end

-- A stance with a gain state worth more than a point, which you can be made to
-- trail by 1 (so it flips rather than ties).
local function flippable(view: any): (string, string)
	for _, id in { "A", "B" } do
		local preview = Swing.stance(C, view, id :: any)
		for _, state in preview.gains do
			if preview.effects[state] > 1 then
				return id, state
			end
		end
	end
	error("no stance with a big gain")
end

describe("Stances: the Choice week", function()
	it("labels each stance chip and the hedge, with C selected by default", function()
		local world, peer = open("Stance", nil)
		local view = viewOf(world, peer)
		for _, stance in view.event.stances do
			local text = textOf(peer, `Choice{stance.id}`)
			check(Rig.contains(text, `{stance.id} · {stance.name}`), text)
		end
		check(Rig.contains(textOf(peer, "ChoiceC"), "hedge, default"), textOf(peer, "ChoiceC"))
		check(need(peer, "ChoiceC"):GetAttribute("Selected") == true, "C is not preselected")
		expect(textOf(peer, "ChoiceNeed")):toBe(Swing.needText(C, view))
		expect(textOf(peer, "ChoiceSummary")):toBe(Swing.stanceSummary(C, view, Swing.stance(C, view, "C")))
		Rig.noErrors(world)
	end)

	it("previews the selected stance on the map: gains in your color, losses in red", function()
		local world, peer = open("Stance", nil)
		local Kit = kitOf(world, peer)
		local view = viewOf(world, peer)
		tap(world, peer, "ChoiceA")
		local preview = Swing.stance(C, view, "A")
		expect(textOf(peer, "ChoiceSummary")):toBe(Swing.stanceSummary(C, view, preview))
		check(#preview.gains > 0 and #preview.losses > 0, "stance A moves no state both ways")
		local mine = Kit.playerColor(view, view.you)
		for _, id in preview.gains do
			expect(badgeOf(peer, id)):toBe(Numbers.signed(preview.effects[id]))
			check(same(tagColor(peer, id), mine), `{id}'s badge is not in your color`)
			check(nodePart(peer, id, "Halo").Visible == true, `{id} does not glow`)
		end
		for _, id in preview.losses do
			expect(badgeOf(peer, id)):toBe(Numbers.signed(preview.effects[id]))
			check(same(tagColor(peer, id), Kit.colors.danger), `{id}'s badge is not red`)
		end
		check(Rig.contains(textOf(peer, "Caption"), "stance A"), textOf(peer, "Caption"))
		Rig.noErrors(world)
	end)

	it("calls out a state the stance would flip", function()
		local world, peer = open("Stance", nil)
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		local view = payload.view
		local id, state = flippable(view)
		local you, them = view.you, 3 - view.you
		local support = { 0, 0 }
		support[you], support[them] = 40, 41
		view.states[State.indexOf[state]].poll = { support = support, undecided = 19 }
		Rig.push(world, peer, payload)
		tap(world, peer, `Choice{id}`)
		local tag = nodePart(peer, state, "Badge")
		check(
			tag.Visible == true and string.find(tag.Text, "FLIP", 1, true) ~= nil,
			`{state} shows "{tag.Text}", not FLIP`
		)
		local summary = textOf(peer, "ChoiceSummary")
		check(Rig.contains(summary, `flip {state}`), summary)
		Rig.noErrors(world)
	end)

	it("previews a stance while it is held, without selecting it", function()
		local world, peer = open("Stance", nil)
		local view = viewOf(world, peer)
		local chip = need(peer, "ChoiceB")
		world.current = peer
		fire(chip, "InputBegan", "Touch")
		world.current = nil
		FakeRoblox.run(world, 0.2)
		expect(textOf(peer, "ChoiceSummary")):toBe(Swing.stanceSummary(C, view, Swing.stance(C, view, "B")))
		check(need(peer, "ChoiceC"):GetAttribute("Selected") == true, "holding B selected it")
		world.current = peer
		fire(chip, "InputEnded", "Touch")
		world.current = nil
		FakeRoblox.run(world, 0.2)
		expect(textOf(peer, "ChoiceSummary")):toBe(Swing.stanceSummary(C, view, Swing.stance(C, view, "C")))
		Rig.noErrors(world)
	end)

	it("gives the normal map back when the event card is collapsed", function()
		local world, peer = open("Stance", nil)
		local view = viewOf(world, peer)
		tap(world, peer, "ChoiceA")
		local preview = Swing.stance(C, view, "A")
		local id = preview.losses[1]
		check(badgeOf(peer, id) ~= nil, "no preview badge to start with")
		tap(world, peer, "EventToggle")
		check(badgeOf(peer, id) ~= Numbers.signed(preview.effects[id]), `{id} still shows the preview`)
		Rig.noErrors(world)
	end)
end)

describe("Stances: the debate reveal", function()
	it("names the states each topic swung, and every flip", function()
		local world, peer = open("Debate", nil)
		FakeRoblox.run(world, DEBATE_DONE)
		local Kit = kitOf(world, peer)
		local view = viewOf(world, peer)
		local result = view.debates[#view.debates]
		local flips = 0
		for t = 1, #result.topics do
			local entry = Swing.debateTopic(C, view, result, t)
			local label = need(peer, `DebateSwing{t}`)
			expect(label.Text):toBe(entry.line)
			check(shown(label), `DebateSwing{t} is hidden`)
			if #entry.flips > 0 then
				flips += 1
				expect(label.TextSize):toBe(Kit.size.heading)
				for _, flip in entry.flips do
					local tag = nodePart(peer, flip.state, "Badge").Text
					check(string.find(tag, "FLIP", 1, true) ~= nil, `{flip.state} shows "{tag}", not FLIP`)
				end
			end
			if entry.winner ~= 0 then
				local net = Swing.debateNet(C, view, result, #result.topics)
				local first = entry.states[1]
				expect(badgeOf(peer, first)):toBe(Numbers.signed(net[first]))
			end
		end
		check(flips > 0, "the fixture debate flips no state (pick another seed)")
		Rig.noErrors(world)
	end)

	it("calls out a gaffe in the topic's states", function()
		local world, peer = open("Debate", nil)
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		local view = payload.view
		local result = view.debates[#view.debates]
		result.gaffes[view.you][2] = true
		payload.step += 1
		Rig.push(world, peer, payload)
		FakeRoblox.run(world, DEBATE_DONE)
		local entry = Swing.debateTopic(C, view, result, 2)
		local label = need(peer, "DebateGaffe2")
		expect(label.Text):toBe(entry.gaffeLines[1])
		check(shown(label), "the gaffe line is hidden")
		Rig.noErrors(world)
	end)
end)

describe("Stances: the resolve reveal after a Choice week", function()
	it("says what both stances moved and flipped, on the panel and the map", function()
		local world, peer = open("ChoiceResolve", nil)
		FakeRoblox.run(world, RESOLVE_DONE)
		local view = viewOf(world, peer)
		local entry = Swing.lastChoice(view) :: any
		check(entry ~= nil, "no Choice result in the view")
		local lines = Swing.choiceLines(C, view, entry)
		local label = need(peer, "RevealChoice")
		expect(label.Text):toBe(table.concat(lines, "\n"))
		check(shown(label), "the stance lines are hidden")
		for id, net in Swing.net(entry.moves, view) do
			expect(badgeOf(peer, id)):toBe(Numbers.signed(net))
		end
		check(Rig.contains(textOf(peer, "FeedEvent"), lines[1]), textOf(peer, "FeedEvent"))
		Rig.noErrors(world)
	end)
end)

describe("Stances: Results", function()
	it("says what debates and stances decided", function()
		local world, peer = open("Over", nil)
		local view = viewOf(world, peer)
		local lines = Swing.decided(C, view)
		check(Rig.shown(Rig.need(peer, "Results", "Decided"), "Results"), "no What decided it section")
		for k, line in lines do
			expect(Rig.textOf(peer, "Results", `Decided_{k}`)):toBe(line)
		end
		Rig.noErrors(world)
	end)
end)

describe("Stances: strict UI audit", function()
	for _, size in SIZES do
		it(
			`keeps the stance and focus screens, the Choice week, both reveals and Results strict ({size.name})`,
			function()
				local world, peer = open("Stance", size.screen)
				tap(world, peer, "ChoiceA")
				local problems = strict(world, peer, "Decision")
				check(#problems == 0, "Stance: " .. table.concat(problems, "; "))

				world, peer = open("Focus", size.screen)
				tap(world, peer, "FocusTopic2")
				problems = strict(world, peer, "Decision")
				check(#problems == 0, "Focus: " .. table.concat(problems, "; "))

				world, peer = open("ChoiceWeek", size.screen)
				problems = strict(world, peer, "Campaign")
				check(#problems == 0, "ChoiceWeek: " .. table.concat(problems, "; "))

				world, peer = open("Debate", size.screen)
				FakeRoblox.run(world, DEBATE_DONE)
				problems = strict(world, peer, "Campaign")
				check(#problems == 0, "Debate: " .. table.concat(problems, "; "))

				world, peer = open("ChoiceResolve", size.screen)
				FakeRoblox.run(world, RESOLVE_DONE)
				problems = strict(world, peer, "Campaign")
				check(#problems == 0, "ChoiceResolve: " .. table.concat(problems, "; "))

				world, peer = open("Over", size.screen)
				local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
				expect(Audit.run(Rig.need(peer, "Screens", "Results"), "Results", { strict = true })):toBe(0)
				Rig.noErrors(world)
			end
		)
	end
end)
