--!strict
-- The explanations on the real screens (fake engine): action previews and
-- viewer-side labels on the state card, the "How it works" overlay from the
-- Campaign, Select and Draft headers, Choice payoffs on the event card, debate
-- scores split into prep and roll, and the strict UI audit on the overlay at
-- 1280x720, 844x390 and 390x844. The numbers themselves are Explain.spec's job;
-- here the screens must show exactly what Explain says.

local Config = require("@sim/Config")
local Events = require("@sim/Events")
local Explain = require("@ui/Explain")
local FakeRoblox = require("@testlib/FakeRoblox")
local PlanDraft = require("@ui/PlanDraft")
local Rig = require("./Rig")
local State = require("@sim/State")
local Test = require("@testlib/Test")
local Words = require("@ui/Words/Reveal")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local SIZES = {
	{ name = "1280x720", screen = { x = 1280, y = 720 } },
	{ name = "844x390", screen = { x = 844, y = 390 } },
	{ name = "390x844", screen = Rig.PHONE },
}

local check = Rig.check

local function need(peer: FakeRoblox.Peer, name: string): any
	return Rig.need(peer, "Campaign", name)
end
local function tap(world: FakeRoblox.World, peer: FakeRoblox.Peer, screen: string, name: string)
	Rig.tap(world, peer, screen, name, 0.1)
end
local function textOf(peer: FakeRoblox.Peer, name: string): string
	return Rig.textOf(peer, "Campaign", name)
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

local function overlayShown(peer: FakeRoblox.Peer): boolean
	local overlay = FakeRoblox.find(peer, "HelpOverlay")
	return overlay ~= nil and overlay.Visible == true
end

describe("Explained: the state card", function()
	it("previews every action in the selected state, as Explain computes it", function()
		local world, peer = Rig.fixture("Plan", nil)
		tap(world, peer, "Campaign", "OH")
		tap(world, peer, "Campaign", "DetailsToggle")
		local view = Rig.payloadOf(world, peer).view
		local message = PlanDraft.bestIssue(C, view, "OH")
		for _, entry in Explain.previews(C, view, PlanDraft.new(), "OH", message) do
			local label = need(peer, `Preview{entry.name}`)
			expect(label.Text):toBe(entry.text)
			check(Rig.shown(label, "Campaign"), `Preview{entry.name} is hidden`)
		end
		-- A second ad in the same state is worth less: the preview says so.
		tap(world, peer, "Campaign", "Ad")
		check(Rig.contains(textOf(peer, "PreviewAd"), "repeat"), textOf(peer, "PreviewAd"))
		Rig.noErrors(world)
	end)

	it("follows the message chip", function()
		local world, peer = Rig.fixture("Plan", nil)
		tap(world, peer, "Campaign", "OH")
		local view = Rig.payloadOf(world, peer).view
		local choices = PlanDraft.messageChoices(C, view, "OH")
		local pick = choices[#choices].issue
		tap(world, peer, "Campaign", `Issue{pick}`)
		local want = Explain.action(C, view, PlanDraft.new(), "OH", "Rally", pick).text
		expect(textOf(peer, "PreviewRally")):toBe(want)
	end)

	it("says who a lean favors and what momentum and backlash do", function()
		local world, peer = Rig.fixture("Plan", nil)
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		local s = payload.view.states[State.indexOf.OH]
		s.lean, s.leanTo, s.backlash = 3, payload.view.you, 2
		s.momentum[payload.view.you] = 2
		Rig.push(world, peer, payload)
		tap(world, peer, "Campaign", "OH")
		tap(world, peer, "Campaign", "DetailsToggle")
		expect(textOf(peer, "CardLean")):toBe("leans you +3")
		expect(textOf(peer, "CardMomentumNote")):toBe(Explain.momentumNote(C, payload.view, s))
		expect(textOf(peer, "CardBacklash")):toBe(Explain.backlashNote(C, payload.view, s))
		check(Rig.shown(need(peer, "CardBacklash"), "Campaign"), "backlash is hidden")
		Rig.noErrors(world)
	end)

	it("names the underdog tier in the week card", function()
		local world, peer = Rig.fixture("Plan", nil)
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		payload.view.players[payload.view.you].underdogTier = 1
		Rig.push(world, peer, payload)
		tap(world, peer, "Campaign", "WeekToggle")
		local text = textOf(peer, "FeedUnderdog")
		expect(text):toBe(Explain.underdogText(C, payload.view, payload.view.you))
		check(Rig.shown(need(peer, "FeedUnderdog"), "Campaign"), "the underdog line is hidden")
	end)
end)

describe("Explained: the help overlay", function()
	it("opens from the Campaign header and closes with its ×, never a primary", function()
		local world, peer = Rig.fixture("Plan", nil)
		check(not overlayShown(peer), "help is open before the tap")
		tap(world, peer, "Campaign", "HelpButton")
		check(overlayShown(peer), "help did not open")
		local view = Rig.payloadOf(world, peer).view
		for _, section in Explain.help(C, view) do
			local title = Rig.need(peer, "HelpOverlay", `HelpTitle_{section.id}`)
			expect(title.Text):toBe(section.title)
			local body = Rig.need(peer, "HelpOverlay", `HelpText_{section.id}`)
			-- Every exact rule, said in plain words (no "AP", no "EV").
			expect(body.Text):toBe(Words.plain(table.concat(section.lines, "\n")))
			check(not string.find(body.Text, "%f[%w]AP%f[%W]"), `"AP" in {section.id}`)
		end
		-- Every tab's numbers are still there, behind "All the numbers" (UI-STYLE §4.10).
		local close = Rig.need(peer, "HelpOverlay", "HelpClose")
		check(close:GetAttribute("PrimaryAction") ~= true, "Help holds a primary action")
		check(Rig.shown(close, "HelpOverlay"), "the × is hidden")
		tap(world, peer, "HelpOverlay", "HelpClose")
		check(not overlayShown(peer), "help did not close")
		Rig.noErrors(world)
	end)

	for _, moment in { "Select", "Draft" } do
		it(`opens from the {moment} header too`, function()
			local world, peer = Rig.fixture(moment, nil)
			tap(world, peer, moment, "HelpButton")
			check(overlayShown(peer), `help did not open from {moment}`)
			Rig.noErrors(world)
		end)
	end

	for _, size in SIZES do
		it(`passes the strict UI audit ({size.name})`, function()
			local world, peer = Rig.fixture("Plan", size.screen)
			tap(world, peer, "Campaign", "HelpButton")
			local problems = strict(world, peer, "HelpOverlay")
			check(#problems == 0, table.concat(problems, "; "))
			local close = Rig.need(peer, "HelpOverlay", "HelpClose")
			check(
				close.AbsolutePosition.Y + close.AbsoluteSize.Y <= size.screen.y + 0.5,
				"Close is off screen"
			)
			Rig.noErrors(world)
		end)
	end

	for _, size in SIZES do
		it(`keeps the Campaign and Decision moments strict with the help button ({size.name})`, function()
			for _, moment in { "Plan", "Stance", "ChoiceWeek", "Resolve", "Focus", "Debate" } do
				local world, peer = Rig.fixture(moment, size.screen)
				local screen = if moment == "Stance" or moment == "Focus" then "Decision" else "Campaign"
				local problems = strict(world, peer, screen)
				check(#problems == 0, `{moment}: ` .. table.concat(problems, "; "))
			end
		end)
	end
end)

describe("Explained: events and debates", function()
	it("shows where each stance of the week's Choice event moves support", function()
		local world, peer = Rig.fixture("Stance", nil)
		local view = Rig.payloadOf(world, peer).view
		tap(world, peer, "Decision", "WhyToggle")
		for k, line in
			Explain.choiceLines(
				C,
				view.issueMap,
				view.event,
				view.players[view.you].platform,
				Events.baseOf(view.players[view.you])
			)
		do
			local label = Rig.need(peer, "Decision", `ChoicePay{k}`)
			expect(label.Text):toBe(line)
			check(Rig.shown(label, "Decision"), `ChoicePay{k} is hidden`)
		end
		Rig.noErrors(world)
	end)

	it("splits each debate topic into focus, platform, stat and roll", function()
		local world, peer = Rig.fixture("Debate", nil)
		FakeRoblox.run(world, 8)
		local view = Rig.payloadOf(world, peer).view
		local result = view.debates[#view.debates]
		for t = 1, #result.topics do
			expect(textOf(peer, `DebateParts{t}`)):toBe(Explain.debateLine(C, view, result, t))
		end
		Rig.noErrors(world)
	end)

	it("shows what a focus on each topic gives: the fixed score and the roll", function()
		local world, peer = Rig.fixture("Focus", nil)
		local text = Rig.textOf(peer, "Decision", "FocusOdds1")
		check(Rig.contains(text, "Focus here:"), text)
		check(Rig.contains(text, `roll 0 to {C.DEBATE_ROLL_MAX}`), text)
		Rig.noErrors(world)
	end)
end)
