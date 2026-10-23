--!strict
-- "How to play" (UI/Help, docs/UI-STYLE.md §4.10, WP-C) on the fake engine: a
-- sheet with five short tabs, each a picture and at most 60 words, the exact
-- numbers one tap away, the tab for the moment, the step's countdown, closed by
-- its × or the scrim, never a primary action, and strictly clean (layout and
-- style rules) at phone, iPad and desktop sizes. How to win starts with the
-- Settings row (WP-3): its chips flip Audio.muted() and Motion.reduced() and
-- follow the header's sound button; the action rows carry their icons.

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Test = require("@testlib/Test")
local Words = require("@ui/Words/Reveal")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local C = Config.defaults
local SIZES = {
	{ name = "phone", screen = Rig.PHONE },
	{ name = "ipad", screen = { x = 1024, y = 768 } },
	{ name = "desktop", screen = { x = 1280, y = 720 } },
}
local OVERLAY = "HelpOverlay"

local function open(moment: string, screen: { x: number, y: number }?): (FakeRoblox.World, FakeRoblox.Peer)
	local world, peer = Rig.fixture(moment, screen)
	local holder = if moment == "Stance" or moment == "Focus" then "Decision" else "Campaign"
	Rig.tap(world, peer, holder, "HelpButton")
	return world, peer
end

local function overlay(peer: FakeRoblox.Peer): any
	local root = FakeRoblox.find(peer, OVERLAY)
	check(root ~= nil, "no help overlay")
	return root
end

local function shown(peer: FakeRoblox.Peer, name: string): boolean
	return Rig.shown(Rig.need(peer, OVERLAY, name), OVERLAY)
end

local function shownTab(peer: FakeRoblox.Peer): string?
	local found: string? = nil
	for _, tab in Words.help(C) do
		if shown(peer, `HelpPage_{tab.id}`) then
			check(found == nil, "two tabs show at once")
			found = tab.id
		end
	end
	return found
end

local function findings(world: FakeRoblox.World, peer: FakeRoblox.Peer): { string }
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	local out = {}
	for _, finding in Audit.check(overlay(peer), { style = true }) do
		table.insert(out, `{finding.rule}: {finding.message}`)
	end
	return out
end

describe("Help: How to play", function()
	it("opens as a sheet with five tabs, on the tab for the moment", function()
		local world, peer = open("Plan", nil)
		check(overlay(peer).Visible == true, "help did not open")
		check(shown(peer, "HelpSheet"), "no sheet")
		for _, tab in Words.help(C) do
			check(shown(peer, `HelpTab_{tab.id}`), `no {tab.id} tab`)
		end
		expect(shownTab(peer)):toBe("turn")
		expect(Rig.need(peer, OVERLAY, "HelpTab_turn"):GetAttribute("Selected")):toBe(true)
		Rig.noErrors(world)

		local world2, peer2 = open("Stance", nil)
		expect(shownTab(peer2)):toBe("events")
		Rig.noErrors(world2)
	end)

	it("switches tabs with one tap and keeps each one short", function()
		local world, peer = open("Plan", nil)
		for _, tab in Words.help(C) do
			Rig.tap(world, peer, OVERLAY, `HelpTab_{tab.id}`)
			expect(shownTab(peer)):toBe(tab.id)
			expect(Rig.textOf(peer, OVERLAY, `HelpIntro_{tab.id}`)):toBe(tab.text)
			check(
				Rig.need(peer, OVERLAY, `HelpTab_{tab.id}`):GetAttribute("Selected") == true,
				"tab not selected"
			)
			check(shown(peer, `HelpArt_{tab.id}`), `the {tab.id} tab has no picture`)
			check(not shown(peer, `HelpMore_{tab.id}`), `the {tab.id} numbers show before the tap`)
		end
		Rig.noErrors(world)
	end)

	it("shows the exact numbers behind a tap", function()
		local world, peer = open("Plan", nil)
		Rig.tap(world, peer, OVERLAY, "HelpTab_actions")
		Rig.tap(world, peer, OVERLAY, "HelpMoreButton_actions")
		check(shown(peer, "HelpMore_actions"), "All the numbers did not open")
		check(shown(peer, "HelpText_actions"), "the Actions numbers are hidden")
		check(
			Rig.contains(Rig.textOf(peer, OVERLAY, "HelpText_actions"), "Rally"),
			Rig.textOf(peer, OVERLAY, "HelpText_actions")
		)
		Rig.tap(world, peer, OVERLAY, "HelpMoreButton_actions")
		check(not shown(peer, "HelpMore_actions"), "All the numbers did not close")
		Rig.noErrors(world)
	end)

	it("keeps the countdown and holds no primary", function()
		local world, peer = open("Plan", nil)
		local timer = Rig.need(peer, OVERLAY, "HelpTimer")
		check(shown(peer, "HelpTimer"), "no countdown")
		check(string.match(tostring(timer.Text), "^%d+:%d%d$") ~= nil, `timer says {timer.Text}`)
		for _, inst in overlay(peer):GetDescendants() do
			check(inst:GetAttribute("PrimaryAction") ~= true, `{inst.Name} is a primary`)
		end
		Rig.noErrors(world)
	end)

	it("closes with the × and with a tap outside", function()
		local world, peer = open("Plan", nil)
		Rig.tap(world, peer, OVERLAY, "HelpClose")
		check(overlay(peer).Visible == false, "the × did not close help")
		Rig.tap(world, peer, "Campaign", "HelpButton")
		check(overlay(peer).Visible == true, "help did not open again")
		Rig.tap(world, peer, OVERLAY, "Scrim")
		check(overlay(peer).Visible == false, "a tap outside did not close help")
		Rig.noErrors(world)
	end)

	it("starts How to win with Sound and Reduce motion chips that flip the settings", function()
		local world, peer = open("Plan", nil)
		Rig.tap(world, peer, OVERLAY, "HelpTab_win")
		check(shown(peer, "HelpSettings"), "no Settings row")
		local Audio = FakeRoblox.require(world, peer, "src/client/UI/Audio.luau")
		local Motion = FakeRoblox.require(world, peer, "src/client/UI/Motion.luau")
		local sound = Rig.need(peer, OVERLAY, "SoundChip")
		local motion = Rig.need(peer, OVERLAY, "MotionChip")
		expect(Audio.muted()):toBe(false)
		expect(sound:GetAttribute("On")):toBe(true)
		expect(sound:GetAttribute("Selected")):toBe(true)
		expect(Motion.reduced()):toBe(false)
		expect(motion:GetAttribute("On")):toBe(false)

		Rig.tap(world, peer, OVERLAY, "SoundChip")
		expect(Audio.muted()):toBe(true)
		expect(sound:GetAttribute("On")):toBe(false)
		Rig.tap(world, peer, OVERLAY, "SoundChip")
		expect(Audio.muted()):toBe(false)
		expect(sound:GetAttribute("On")):toBe(true)

		Rig.tap(world, peer, OVERLAY, "MotionChip")
		expect(Motion.reduced()):toBe(true)
		expect(motion:GetAttribute("On")):toBe(true)
		expect(motion:GetAttribute("Selected")):toBe(true)
		Rig.tap(world, peer, OVERLAY, "MotionChip")
		expect(Motion.reduced()):toBe(false)
		expect(motion:GetAttribute("On")):toBe(false)
		Rig.noErrors(world)
	end)

	it("follows the header's sound button", function()
		local world, peer = open("Plan", nil)
		Rig.tap(world, peer, OVERLAY, "HelpTab_win")
		local chip = Rig.need(peer, OVERLAY, "SoundChip")
		expect(chip:GetAttribute("On")):toBe(true)
		Rig.tap(world, peer, OVERLAY, "HelpClose")
		Rig.tap(world, peer, "Campaign", "SoundButton")
		Rig.tap(world, peer, "Campaign", "HelpButton")
		Rig.tap(world, peer, OVERLAY, "HelpTab_win")
		expect(chip:GetAttribute("On")):toBe(false)
		expect(chip:GetAttribute("Selected")):toBe(false)
		local icon = chip:FindFirstChild("Content"):FindFirstChild("Icon", true)
		expect(icon:GetAttribute("Icon")):toBe("volume-x")
		Rig.noErrors(world)
	end)

	it("shows Reduce motion on when Roblox's setting is on", function()
		local world, peer = Rig.fixture("Plan", nil, { reducedMotion = true })
		Rig.tap(world, peer, "Campaign", "HelpButton")
		Rig.tap(world, peer, OVERLAY, "HelpTab_win")
		expect(Rig.need(peer, OVERLAY, "MotionChip"):GetAttribute("On")):toBe(true)
		Rig.noErrors(world)
	end)

	it("draws each action's icon beside its name", function()
		local world, peer = open("Plan", nil)
		Rig.tap(world, peer, OVERLAY, "HelpTab_actions")
		local art = Rig.need(peer, OVERLAY, "HelpArt_actions")
		local icons = {}
		for _, inst in art:GetDescendants() do
			local name = inst:GetAttribute("Icon")
			if name then
				table.insert(icons, name)
			end
		end
		expect(#icons):toBe(6)
		check(table.find(icons, "megaphone") ~= nil, "no Rally icon")
		check(table.find(icons, "footprints") ~= nil, "no Ground game icon")
		Rig.noErrors(world)
	end)

	for _, size in SIZES do
		it(`is strictly clean on every tab ({size.name})`, function()
			local world, peer = open("Plan", size.screen)
			for _, tab in Words.help(C) do
				Rig.tap(world, peer, OVERLAY, `HelpTab_{tab.id}`)
				Rig.tap(world, peer, OVERLAY, `HelpMoreButton_{tab.id}`)
				local problems = findings(world, peer)
				check(#problems == 0, `{tab.id}: ` .. table.concat(problems, "; "))
			end
			local close = Rig.need(peer, OVERLAY, "HelpClose")
			check(close.AbsolutePosition.Y >= 0, "the × is off screen")
			Rig.noErrors(world)
		end)
	end
end)
