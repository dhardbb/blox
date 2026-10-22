--!strict
-- The design system's building blocks on the fake engine (docs/DESIGN.md
-- D-030): Kit tokens and button variants, ActionBar, Header, Toast and
-- Collapsible. Each module is loaded into a client the way a screen would load
-- it (FakeRoblox.require), and built into a sized test frame.

local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

type Client = {
	world: FakeRoblox.World,
	peer: FakeRoblox.Peer,
	Kit: any,
	stage: any, -- a frame the size of the screen to build into
}

-- A client on the Lobby fixture, with Kit loaded and an empty full-screen frame.
local function client(screen: { x: number, y: number }?): Client
	local world, peer = Rig.fixture("Lobby", screen)
	local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
	local gui = Kit.new("ScreenGui", { Name = "TestGui" })
	local stage = Kit.box({ Name = "Stage", Parent = gui })
	return { world = world, peer = peer, Kit = Kit, stage = stage }
end

local function load(c: Client, name: string): any
	return FakeRoblox.require(c.world, c.peer, `src/client/UI/{name}.luau`)
end

local function same(a: any, b: any): boolean
	return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
end

local function press(c: Client, button: any)
	c.world.current = c.peer
	button.Activated.fire()
	c.world.current = nil
	FakeRoblox.run(c.world, 0.05)
end

describe("Kit tokens", function()
	it("has exactly the five text sizes of the type scale", function()
		local c = client()
		local keys = 0
		for _ in c.Kit.size do
			keys += 1
		end
		expect(keys):toBe(5)
		expect(c.Kit.size.caption):toBe(13)
		expect(c.Kit.size.body):toBe(16)
		expect(c.Kit.size.heading):toBe(20)
		expect(c.Kit.size.title):toBe(28)
		expect(c.Kit.size.hero):toBe(48)
	end)

	it("has the spacing, shape and size constants", function()
		local Kit = client().Kit
		expect(Kit.space.xs):toBe(4)
		expect(Kit.space.sm):toBe(8)
		expect(Kit.space.md):toBe(12)
		expect(Kit.space.lg):toBe(16)
		expect(Kit.space.xl):toBe(24)
		expect(Kit.radius.control):toBe(8)
		expect(Kit.radius.panel):toBe(12)
		expect(Kit.MIN_TOUCH):toBe(44)
		expect(Kit.PRIMARY_H):toBe(56)
		expect(Kit.BAR_H):toBe(84)
		expect(Kit.HEADER_H):toBe(44)
		expect(Kit.MIN_TEXT):toBe(12)
		expect(Kit.MAP_NODE_MIN):toBe(36)
		expect(Kit.TIMER_WARN):toBe(10)
	end)

	it("mirrors the new color tokens and a player's color", function()
		local c = client()
		local Kit = c.Kit
		check(same(Kit.colors.onAccent, Kit.colors.background), "onAccent is not the background")
		check(same(Kit.colors.warn, Kit.colors.accent), "warn is not the accent")
		check(same(Kit.colors.disabledText, Kit.colors.muted), "disabledText is not muted")
		check(Kit.colors.field ~= nil and Kit.colors.neutral ~= nil, "field or neutral is missing")
		local view = { players = { { color = "Teal" }, { color = nil } } }
		check(same(Kit.playerColor(view, 1), Kit.color({ r = 24, g = 168, b = 178 })), "Teal is wrong")
		check(same(Kit.playerColor(view, 2), Kit.colors.neutral), "no color is not neutral")
	end)

	it("floors every text size constraint it creates at 12 px", function()
		local c = client()
		local Kit = c.Kit
		local noop = function() end
		Kit.text("a", { TextScaled = true, Parent = c.stage })
		Kit.text("b", { TextScaled = true, TextSize = Kit.size.caption, Parent = c.stage })
		Kit.caption("c", { TextScaled = true, Parent = c.stage })
		Kit.heading("d", { TextScaled = true, Parent = c.stage })
		for _, variant in { "primary", "secondary", "danger", "chip" } do
			Kit.button(variant, noop, { variant = variant, Parent = c.stage })
		end
		Kit.button("legacy", noop, { Parent = c.stage })
		Kit.iconButton("×", noop, { Parent = c.stage })
		local constraints = 0
		for _, inst in c.stage:GetDescendants() do
			if inst.ClassName == "UITextSizeConstraint" then
				constraints += 1
				expect(inst.MinTextSize):toBe(12)
			end
		end
		expect(constraints):toBe(10)
	end)
end)

describe("Kit buttons", function()
	local function make(c: Client, variant: string?): any
		return c.Kit.button("Go", function() end, { variant = variant, Parent = c.stage })
	end

	it("gives each variant its documented look", function()
		local c = client()
		local Kit = c.Kit
		local primary = make(c, "primary")
		check(same(primary.BackgroundColor3, Kit.colors.accent), "primary is not accent")
		check(same(primary.TextColor3, Kit.colors.onAccent), "primary text is not onAccent")
		expect(primary.Font.Name):toBe("GothamBold")
		expect(primary.AbsoluteSize.Y):toBe(56)
		local secondary = make(c, nil)
		check(same(secondary.BackgroundColor3, Kit.colors.raised), "the default is not raised")
		expect(secondary.AbsoluteSize.Y):toBe(44)
		local danger = make(c, "danger")
		check(same(danger.BackgroundColor3, Kit.colors.surface), "danger is not on surface")
		check(same(danger.TextColor3, Kit.colors.danger), "danger text is not danger")
		local stroke = danger:FindFirstChild("VariantStroke")
		check(stroke ~= nil and stroke.Enabled and stroke.Thickness == 1, "danger has no 1 px stroke")
		check(same(stroke.Color, Kit.colors.danger), "the danger stroke is not danger")
		local chip = make(c, "chip")
		check(same(chip.BackgroundColor3, Kit.colors.raised), "a chip is not raised")
		check(chip:FindFirstChild("VariantStroke").Enabled == false, "an unselected chip has a stroke")
		local icon = Kit.iconButton("+", function() end, { Parent = c.stage })
		expect(icon.AbsoluteSize.X):toBe(44)
		expect(icon.AbsoluteSize.Y):toBe(44)
	end)

	it("disables a primary into a grey button, never faded gold", function()
		local c = client()
		local Kit = c.Kit
		local primary = make(c, "primary")
		Kit.setEnabled(primary, false)
		check(same(primary.BackgroundColor3, Kit.colors.raised), "a disabled primary is not raised")
		check(same(primary.TextColor3, Kit.colors.muted), "a disabled primary's text is not muted")
		expect(primary.BackgroundTransparency):toBe(0)
		expect(primary.Active):toBe(false)
		Kit.setEnabled(primary, true)
		check(same(primary.BackgroundColor3, Kit.colors.accent), "re-enabling did not restore the accent")
		check(same(primary.TextColor3, Kit.colors.onAccent), "re-enabling did not restore the text")
		local secondary = make(c, "secondary")
		Kit.setEnabled(secondary, false)
		check(same(secondary.BackgroundColor3, Kit.colors.surface), "a disabled secondary is not surface")
		local danger = make(c, "danger")
		Kit.setEnabled(danger, false)
		check(same(danger:FindFirstChild("VariantStroke").Color, Kit.colors.line), "disabled danger stroke")
	end)

	it("keeps the legacy fade for buttons made without a variant", function()
		local c = client()
		local Kit = c.Kit
		local legacy = c.Kit.button("Old", function() end, {
			BackgroundColor3 = Kit.colors.accent,
			Parent = c.stage,
		})
		Kit.setEnabled(legacy, false)
		expect(legacy.BackgroundTransparency):toBe(0.4)
		check(same(legacy.BackgroundColor3, Kit.colors.accent), "the legacy path changed the color")
	end)

	it("selects a chip with a 2 px accent outline, not a fill", function()
		local c = client()
		local Kit = c.Kit
		local chip = make(c, "chip")
		Kit.setSelected(chip, true)
		local stroke = chip:FindFirstChild("VariantStroke")
		check(stroke.Enabled == true and stroke.Thickness == 2, "no 2 px stroke on a selected chip")
		check(same(stroke.Color, Kit.colors.accent), "the selection stroke is not accent")
		check(same(chip.BackgroundColor3, Kit.colors.raisedHover), "a selected chip is not raisedHover")
		expect(chip:GetAttribute("Selected")):toBe(true)
		Kit.setEnabled(chip, true)
		check(same(chip.BackgroundColor3, Kit.colors.raisedHover), "enabling cleared the selection")
		Kit.setSelected(chip, false)
		check(stroke.Enabled == false, "the stroke stays after deselecting")
		check(same(chip.BackgroundColor3, Kit.colors.raised), "the fill stays after deselecting")
	end)

	it("builds a stat cell of a caption over a body value", function()
		local c = client()
		local cell, value = c.Kit.stat(c.stage, "Lean", "+3 them", "CardLean")
		expect(cell.Name):toBe("CardLean")
		expect(cell:FindFirstChild("Label").TextSize):toBe(13)
		expect(value.TextSize):toBe(16)
		expect(value.Text):toBe("+3 them")
	end)
end)

describe("ActionBar", function()
	it("pins an 84 px bar to the bottom with one PrimaryAction", function()
		local c = client(Rig.PHONE)
		local ActionBar = load(c, "ActionBar")
		local presses = 0
		local bar = ActionBar.new(c.stage, {
			primary = "Lock in",
			onPrimary = function()
				presses += 1
			end,
			primaryName = "LockIn",
		})
		expect(bar.root.AbsoluteSize.Y):toBe(84)
		expect(bar.root.AbsolutePosition.Y + bar.root.AbsoluteSize.Y):toBe(844)
		expect(bar.primary.Name):toBe("LockIn")
		expect(bar.primary:GetAttribute("PrimaryAction")):toBe(true)
		expect(bar.primary.AbsoluteSize.Y):toBe(56)
		expect(bar.primary.AbsoluteSize.X):toBe(390)
		expect(bar.primary.AbsolutePosition.Y + 56 <= 844):toBe(true)
		expect(bar.secondary.Visible):toBe(false)
		press(c, bar.primary)
		expect(presses):toBe(1)
	end)

	it("gives the secondary 30 % and the primary the rest, and changes labels", function()
		local c = client()
		local Kit = c.Kit
		local ActionBar = load(c, "ActionBar")
		local bar = ActionBar.new(c.stage, {
			primary = "Lock in",
			onPrimary = function() end,
			secondary = "Bank +15s",
			onSecondary = function() end,
		})
		local width = c.stage.AbsoluteSize.X
		check(bar.secondary.Visible, "the secondary is hidden")
		check(bar.secondary.AbsoluteSize.X <= 0.3 * width, "the secondary is wider than 30 %")
		check(bar.primary.AbsoluteSize.X >= 0.6 * width, "the primary is narrower than 60 %")
		bar:setPrimary("Pick a state", false)
		expect(bar.primary.Text):toBe("Pick a state")
		check(same(bar.primary.BackgroundColor3, Kit.colors.raised), "the disabled primary is not grey")
		bar:setSecondary(nil, false)
		expect(bar.secondary.Visible):toBe(false)
		expect(bar.primary.AbsoluteSize.X):toBe(width)
		bar:setStatus("Not enough money", "bad")
		expect(bar.status.Text):toBe("Not enough money")
		check(same(bar.status.TextColor3, Kit.colors.danger), "a bad status is not danger")
		bar:setStatus("Locked in · waiting for opponent", "ok")
		check(same(bar.status.TextColor3, Kit.colors.good), "an ok status is not good")
		bar:setOpponent("Opponent: thinking")
		check(bar.opponent.Visible and bar.opponent.Text == "Opponent: thinking", "no opponent line")
		bar:setOpponent(nil)
		expect(bar.opponent.Visible):toBe(false)
	end)

	it("passes the strict UI audit on its own", function()
		local c = client(Rig.PHONE)
		local Audit = load(c, "Audit")
		local ActionBar = load(c, "ActionBar")
		local bar = ActionBar.new(c.stage, {
			primary = "Lock in",
			onPrimary = function() end,
			secondary = "Bank +15s",
			onSecondary = function() end,
		})
		bar:setStatus("Still to pick: a color (scroll down)", "muted")
		bar:setOpponent("Opponent: locked in")
		local findings = Audit.check(c.stage)
		local messages = {}
		for _, finding in findings do
			table.insert(messages, finding.message)
		end
		check(#findings == 0, table.concat(messages, "; "))
	end)
end)

describe("Header", function()
	it("shows the timer in accent, danger under 10 s, and hides it with nil", function()
		local c = client()
		local Kit = c.Kit
		local Header = load(c, "Header")
		local header = Header.new(c.stage, { title = "Choose your campaign" })
		expect(header.root.AbsoluteSize.Y):toBe(44)
		expect(header.title.Text):toBe("Choose your campaign")
		expect(header.timer.Visible):toBe(false)
		header:setTimer(10)
		expect(header.timer.Text):toBe("0:10")
		check(same(header.timer.TextColor3, Kit.colors.accent), "10 s is not accent")
		header:setTimer(9)
		check(same(header.timer.TextColor3, Kit.colors.danger), "9 s is not danger")
		header:setTimer(9, 5)
		check(same(header.timer.TextColor3, Kit.colors.accent), "a custom threshold is ignored")
		header:setTimer(nil)
		expect(header.timer.Visible):toBe(false)
	end)

	it("labels the timer and sets the subtitle", function()
		local c = client()
		local Header = load(c, "Header")
		local header = Header.new(c.stage, { title = "Election night", name = "ElectionHeader" })
		expect(header.root.Name):toBe("ElectionHeader")
		expect(header.subtitle.Visible):toBe(false)
		header:setSubtitle("35 of 51 states called")
		check(header.subtitle.Visible and header.subtitle.Text == "35 of 51 states called", "no subtitle")
		header:setTimerLabel("Results in")
		header:setTimer(32)
		expect(header.timer.Text):toBe("Results in 0:32")
		header:setTitle("Rex Calloway wins")
		expect(header.title.Text):toBe("Rex Calloway wins")
	end)
end)

describe("Toast", function()
	local function toastOf(peer: FakeRoblox.Peer): any
		-- The Lobby still has its own "Toast" label until WP2 removes it.
		local layer = FakeRoblox.find(peer, "ToastLayer")
		local frame = if layer then layer:FindFirstChild("Toast") else nil
		check(frame ~= nil, "the global toast is not mounted")
		return frame
	end

	it("shows the newest message, replaces it, and hides after 5 s", function()
		local world, peer = Rig.fixture("Plan", nil)
		local store = Rig.storeOf(world, peer)
		local toast = toastOf(peer)
		expect(toast.Visible):toBe(false)
		world.current = peer
		store.say("Your opponent is back.")
		world.current = nil
		FakeRoblox.run(world, 0.1)
		expect(toast.Visible):toBe(true)
		expect(toast:FindFirstChild("ToastText").Text):toBe("Your opponent is back.")
		FakeRoblox.run(world, 3)
		world.current = peer
		store.say("Not enough money", true)
		world.current = nil
		FakeRoblox.run(world, 0.1)
		expect(toast:FindFirstChild("ToastText").Text):toBe("Not enough money")
		expect(toast:GetAttribute("Rejected")):toBe(true)
		-- The first message's 5 s run out here; the newer one stays up.
		FakeRoblox.run(world, 3)
		expect(toast.Visible):toBe(true)
		FakeRoblox.run(world, 2.5)
		expect(toast.Visible):toBe(false)
		Rig.noErrors(world)
	end)

	it("strokes a rejection in danger and a notice in accent", function()
		local world, peer = Rig.fixture("Lobby", nil)
		local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
		local store = Rig.storeOf(world, peer)
		local toast = toastOf(peer)
		world.current = peer
		store.say("No match with that code", true)
		world.current = nil
		FakeRoblox.run(world, 0.1)
		check(same(toast:FindFirstChild("ToastStroke").Color, Kit.colors.danger), "a rejection is not danger")
		world.current = peer
		store.say("Opponent reconnected.")
		world.current = nil
		FakeRoblox.run(world, 0.1)
		check(same(toast:FindFirstChild("ToastStroke").Color, Kit.colors.accent), "a notice is not accent")
	end)

	it("stays visible during a Campaign reveal, outside every screen (B5)", function()
		local world, peer = Rig.fixture("Resolve", nil)
		local store = Rig.storeOf(world, peer)
		local toast = toastOf(peer)
		world.current = peer
		store.say("Rejected: nothing to skip", true)
		world.current = nil
		FakeRoblox.run(world, 0.1)
		expect(toast.Visible):toBe(true)
		check(toast:FindFirstAncestor("Screens") == nil, "the toast is inside the Screens container")
		check(toast:FindFirstAncestor("Background") ~= nil, "the toast is not in the game's safe area")
		Rig.noErrors(world)
	end)
end)

describe("Collapsible", function()
	it("toggles its body from a 44 px title row", function()
		local c = client()
		local Collapsible = load(c, "Collapsible")
		local toggled: { boolean } = {}
		local card = Collapsible.new(c.stage, {
			title = "Week card",
			name = "WeekCard",
			order = 3,
			onToggle = function(expanded: boolean)
				table.insert(toggled, expanded)
			end,
		})
		expect(card.root.Name):toBe("WeekCard")
		expect(card.root.LayoutOrder):toBe(3)
		expect(card.toggle.AbsoluteSize.Y):toBe(44)
		expect(card.toggle.Text):toBe("Week card +")
		expect(card.body.Visible):toBe(false)
		expect(card:isExpanded()):toBe(false)
		press(c, card.toggle)
		expect(card.body.Visible):toBe(true)
		expect(card.toggle.Text):toBe("Week card –")
		expect(card.toggle:GetAttribute("Expanded")):toBe(true)
		expect(#toggled):toBe(1)
		expect(toggled[1]):toBe(true)
		card:setExpanded(false)
		expect(card.body.Visible):toBe(false)
		expect(#toggled):toBe(1)
		card:setTitle("Event · Donor retreat")
		expect(card.toggle.Text):toBe("Event · Donor retreat +")
	end)

	it("can start expanded", function()
		local c = client()
		local Collapsible = load(c, "Collapsible")
		local card = Collapsible.new(c.stage, { title = "Event", expanded = true })
		expect(card.body.Visible):toBe(true)
		expect(card.root.Name):toBe("Collapsible")
		c.Kit.text("Choose how to respond", { Parent = card.body })
		expect(#card.body:GetChildren()):toBe(2)
	end)
end)
