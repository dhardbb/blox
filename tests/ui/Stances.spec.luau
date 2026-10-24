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
local Words = require("@ui/Words/Reveal")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local SIZES = {
	{ name = "1280x720", screen = { x = 1280, y = 720 } },
	{ name = "844x390", screen = { x = 844, y = 390 } },
	{ name = "390x844", screen = Rig.PHONE },
}
local RESOLVE_DONE = 30 -- s, the resolve reveal has listed every event by then

local check = Rig.check

-- The screen the helpers look in: the stance is taken on the Decision screen
-- (D-044), a debate on the Debate screen (D-072), everything else here is on
-- Campaign. `open` sets it.
local SCREEN = "Campaign"

local function open(moment: string, screen: { x: number, y: number }?): (FakeRoblox.World, FakeRoblox.Peer)
	SCREEN = if moment == "Stance"
		then "Decision"
		elseif moment == "DebateRound" or moment == "Clash" or moment == "Debate" then "Debate"
		else "Campaign"
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

-- The color a state's tag is in: its fill, or its edge once it says FLIP.
local function tagColor(peer: FakeRoblox.Peer, id: string): Color3
	local badge = nodePart(peer, id, "Badge")
	if string.find(badge.Text, "FLIP", 1, true) then
		return badge:FindFirstChildOfClass("UIStroke").Color
	end
	return badge.BackgroundColor3
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
		check(Rig.contains(textOf(peer, "ChoiceC"), "(safe)"), textOf(peer, "ChoiceC"))
		check(need(peer, "ChoiceC"):GetAttribute("Selected") == true, "C is not preselected")
		expect(textOf(peer, "ChoiceNeed")):toBe(Swing.needText(C, view))
		expect(textOf(peer, "ChoiceSummary")):toBe(Swing.stanceSummary(C, view, Swing.stance(C, view, "C")))
		Rig.noErrors(world)
	end)

	it("previews the selected stance on the map: gains in your color, losses in orange", function()
		local world, peer = open("Stance", nil)
		local Kit = kitOf(world, peer)
		local view = viewOf(world, peer)
		tap(world, peer, "ChoiceA")
		local preview = Swing.stance(C, view, "A")
		expect(textOf(peer, "ChoiceSummary")):toBe(Swing.stanceSummary(C, view, preview))
		check(#preview.gains > 0 and #preview.losses > 0, "stance A moves no state both ways")
		local mine = Kit.playerColor(view, view.you)
		-- Every moved state glows; only the biggest moves (and flips) carry a badge.
		local badges = 0
		local function look(id: string, color: Color3, what: string)
			local halo = nodePart(peer, id, "Halo")
			check(halo.Visible == true, `{id} does not glow`)
			check(same(halo.BackgroundColor3, color), `{id} does not glow {what}`)
			local badge = badgeOf(peer, id)
			if badge ~= nil then
				badges += 1
				expect(badge):toBe(Numbers.signed(preview.effects[id]))
				check(same(tagColor(peer, id), color), `{id}'s badge is not {what}`)
			end
		end
		for _, id in preview.gains do
			look(id, mine, "in your color")
		end
		for _, id in preview.losses do
			look(id, Kit.colors.loss, "orange")
			-- A loss tag is orange with a dark number (D-056).
			local badge = nodePart(peer, id, "Badge")
			if badge.Visible and not string.find(badge.Text, "FLIP", 1, true) then
				check(same(badge.TextColor3, Kit.colors.onLoss), `{id}'s loss tag text is not dark`)
			end
		end
		check(badges > 0 and badges <= 5 + #preview.flips, `{badges} badges on the map`)
		check(Rig.contains(textOf(peer, "GainText"), "Helps you"), textOf(peer, "GainText"))
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

	it("previews only on the Decision screen: the plan screen's map is back to normal", function()
		local world, peer = open("ChoiceWeek", nil)
		local view = viewOf(world, peer)
		local preview = Swing.stance(C, view, "A")
		for _, id in preview.losses do
			check(badgeOf(peer, id) ~= Numbers.signed(preview.effects[id]), `{id} still shows the preview`)
		end
		Rig.noErrors(world)
	end)
end)

describe("Stances: the debate on the map (D-072)", function()
	it("the clash badges what the round moved, and every flip says FLIP", function()
		local world, peer = open("Clash", nil)
		local view = viewOf(world, peer)
		local rounds = if view.debate then view.debate.rounds else view.debates[#view.debates].rounds
		local round = rounds[#rounds]
		local entry = Swing.debateRound(C, view, round)
		expect(textOf(peer, "ClashLine")):toBe(entry.line)
		for _, flip in entry.flips do
			local tag = nodePart(peer, flip.state, "Badge").Text
			check(string.find(tag, "FLIP", 1, true) ~= nil, `{flip.state} shows "{tag}", not FLIP`)
		end
		local moved: { [string]: boolean } = {}
		for _, move in round.moves do
			moved[move.state] = true
		end
		for _, flip in round.flips do
			moved[flip.state] = true
		end
		local badges = 0
		for _, s in view.states do
			if badgeOf(peer, s.id) ~= nil then
				badges += 1
				check(moved[s.id] == true, `{s.id} has a badge but the round did not touch it`)
			end
		end
		check(badges <= 5 + #entry.flips, `{badges} badges on the map`)
		Rig.noErrors(world)
	end)

	it("calls out a backfire in the states the move aimed at", function()
		local world, peer = open("Clash", nil)
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		local view = payload.view
		local rounds = if view.debate then view.debate.rounds else view.debates[#view.debates].rounds
		local round = rounds[#rounds]
		round.backfire[view.you] = true
		payload.step += 1
		Rig.push(world, peer, payload)
		FakeRoblox.run(world, 0.5)
		local entry = Swing.debateRound(C, view, round)
		local label = need(peer, "ClashExtra1")
		expect(label.Text):toBe(entry.gaffeLines[1])
		check(shown(label), "the backfire line is hidden")
		Rig.noErrors(world)
	end)

	it("the verdict badges the whole debate's moves and flips", function()
		local world, peer = open("Debate", nil)
		local view = viewOf(world, peer)
		local result = view.debates[#view.debates]
		for _, flip in Swing.flips(result.flips) do
			local tag = nodePart(peer, flip.state, "Badge").Text
			check(string.find(tag, "FLIP", 1, true) ~= nil, `{flip.state} shows "{tag}", not FLIP`)
		end
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
		check(not shown(label), "the stance numbers show before Why?")
		tap(world, peer, "WhyButton")
		check(shown(label), "Why? does not show the stance lines")
		-- Without last week's polls (a fixture), the map badges what the stances
		-- moved: the flips and the biggest moves only.
		local flips = Swing.flips(entry.flips)
		local flipped: { [string]: boolean } = {}
		for _, flip in flips do
			flipped[flip.state] = true
		end
		local marks = Words.topMarks(Swing.net(entry.moves, view), flips)
		for id, net in marks do
			expect(badgeOf(peer, id)):toBe(if flipped[id] then "FLIP" else Numbers.signed(net))
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
		Rig.tap(world, peer, "Results", "FullBreakdown")
		check(Rig.shown(Rig.need(peer, "Results", "Decided"), "Results"), "no What decided it section")
		for k, line in lines do
			expect(Rig.textOf(peer, "Results", `Decided_{k}`)):toBe(Words.inVotes(line))
			check(
				not string.find(Rig.textOf(peer, "Results", `Decided_{k}`), "%d EV"),
				"EV in What decided it"
			)
		end
		Rig.noErrors(world)
	end)
end)

describe("Stances: strict UI audit", function()
	for _, size in SIZES do
		it(
			`keeps the stance and debate screens, the Choice week, the reveals and Results strict ({size.name})`,
			function()
				local world, peer = open("Stance", size.screen)
				tap(world, peer, "ChoiceA")
				local problems = strict(world, peer, "Decision")
				check(#problems == 0, "Stance: " .. table.concat(problems, "; "))

				world, peer = open("DebateRound", size.screen)
				tap(world, peer, "MoveAttack")
				problems = strict(world, peer, "Debate")
				check(#problems == 0, "DebateRound: " .. table.concat(problems, "; "))

				world, peer = open("ChoiceWeek", size.screen)
				problems = strict(world, peer, "Campaign")
				check(#problems == 0, "ChoiceWeek: " .. table.concat(problems, "; "))

				world, peer = open("Debate", size.screen)
				problems = strict(world, peer, "Debate")
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
