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
local UDim2 = FakeRoblox.types.UDim2

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
	it("has exactly the five text sizes of the type scale, plus the Lobby's wordmark", function()
		local c = client()
		local keys = 0
		for _ in c.Kit.size do
			keys += 1
		end
		expect(keys):toBe(6)
		expect(c.Kit.size.wordmark):toBe(72)
		expect(c.Kit.size.caption):toBe(14)
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
		expect(Kit.radius.button):toBe(12)
		expect(Kit.radius.panel):toBe(12)
		expect(Kit.radius.sheet):toBe(16)
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
		check(not same(Kit.colors.warn, Kit.colors.accent), "warn must not be the accent")
		check(same(Kit.colors.disabledText, Kit.colors.muted), "disabledText is not muted")
		check(Kit.colors.field ~= nil and Kit.colors.neutral ~= nil, "field or neutral is missing")
		local view = { players = { { color = "Teal" }, { color = nil } } }
		check(same(Kit.playerColor(view, 1), Kit.color({ r = 0, g = 164, b = 186 })), "Teal is wrong")
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
		expect(primary.Font.Name):toBe("FredokaOne") -- Kit.font.display
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
		expect(cell:FindFirstChild("Label").TextSize):toBe(14)
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
	it("shows the timer in accent, warn under 10 s, danger under 5 s, and hides it with nil", function()
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
		check(same(header.timer.TextColor3, Kit.colors.warn), "9 s is not warn")
		header:setTimer(5)
		check(same(header.timer.TextColor3, Kit.colors.warn), "5 s is not warn")
		header:setTimer(4)
		check(same(header.timer.TextColor3, Kit.colors.danger), "4 s is not danger")
		header:setTimer(9, 5)
		check(same(header.timer.TextColor3, Kit.colors.accent), "a custom threshold is ignored")
		header:setTimer(4, 0)
		check(same(header.timer.TextColor3, Kit.colors.accent), "warnBelow 0 does not turn urgency off")
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

	it("strokes a rejection in danger and a notice in muted, never the accent (D-058)", function()
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
		check(same(toast:FindFirstChild("ToastStroke").Color, Kit.colors.muted), "a notice is not muted")
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
		expect(card.toggle.Text):toBe("Week card −")
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

-- ------------------------------------------------------------------ polish (docs/DESIGN.md D-053)

describe("Kit polish: fonts, depth and edges", function()
	it("uses Builder Sans with Fredoka One for display", function()
		local Kit = client().Kit
		expect(Kit.font.body.Name):toBe("BuilderSans")
		expect(Kit.font.medium.Name):toBe("BuilderSansMedium")
		expect(Kit.font.bold.Name):toBe("BuilderSansBold")
		expect(Kit.font.display.Name):toBe("FredokaOne")
		expect(Kit.font.mono.Name):toBe("Code")
		expect(Kit.TIMER_CRITICAL):toBe(5)
	end)

	it("gives the primary an accent edge that a disabled primary trades for a hairline", function()
		local c = client()
		local Kit = c.Kit
		local primary = Kit.button("Lock in", function() end, { variant = "primary", Parent = c.stage })
		local edge = primary:FindFirstChild("Edge")
		check(edge ~= nil and edge.Thickness == 2, "no 2 px edge on the primary")
		check(same(edge:GetAttribute("Base"), Kit.colors.accentEdge), "the primary edge is not accentEdge")
		expect(edge:GetAttribute("Alpha")):toBe(1)
		check(edge:FindFirstChild("EdgeLight") ~= nil, "the primary edge is not lit from the top")
		expect(edge.ApplyStrokeMode.Name):toBe("Border")
		check(primary:FindFirstChild("Depth") ~= nil, "no top-light gradient on the primary")
		Kit.setEnabled(primary, false)
		check(
			same(edge:GetAttribute("Base"), Kit.colors.line) and edge.Thickness == 1,
			"a disabled primary keeps its edge"
		)
		expect(edge:GetAttribute("Alpha")):toBe(0.5)
		Kit.setEnabled(primary, true)
		check(same(edge:GetAttribute("Base"), Kit.colors.accentEdge), "re-enabling did not restore the edge")
	end)

	it("puts hairlines and depth on secondaries and cards only", function()
		local c = client()
		local Kit = c.Kit
		local secondary = Kit.button("Back", function() end, { variant = "secondary", Parent = c.stage })
		local edge = secondary:FindFirstChild("Edge")
		check(
			edge ~= nil
				and same(edge:GetAttribute("Base"), Kit.colors.line)
				and edge:GetAttribute("Alpha") == 0.5,
			"no hairline"
		)
		check(secondary:FindFirstChild("Depth") ~= nil, "no gradient on a secondary")
		local ghost = Kit.button("More", function() end, { variant = "ghost", Parent = c.stage })
		check(
			ghost:FindFirstChild("Edge") == nil and ghost:FindFirstChild("Depth") == nil,
			"a ghost has chrome"
		)
		local chip = Kit.chip("Jobs", function() end, { Parent = c.stage })
		check(chip:FindFirstChild("Edge") == nil, "a chip has a second stroke")
		check(chip:FindFirstChildOfClass("UIStroke").Name == "VariantStroke", "the chip's first stroke moved")
		local card = Kit.card({ Parent = c.stage })
		check(same(card.BackgroundColor3, Kit.colors.surfaceTop), "a card does not start at surfaceTop")
		local depth = card:FindFirstChild("Depth")
		check(depth ~= nil and depth.Rotation == 90, "no vertical gradient on a card")
		check(card:FindFirstChild("Edge") ~= nil, "no hairline on a card")
		expect(card:FindFirstChildOfClass("UIPadding").PaddingTop.Offset):toBe(14)
		local flat = Kit.card({ BackgroundColor3 = Kit.colors.raised, Parent = c.stage })
		check(flat:FindFirstChild("Depth") == nil, "a card with its own fill got a gradient")
		check(same(flat.BackgroundColor3, Kit.colors.raised), "a card's own fill was replaced")
	end)

	it("lets a chip's outline draw in when selected", function()
		local c = client()
		local chip = c.Kit.chip("Jobs", function() end, { Parent = c.stage })
		c.Kit.setSelected(chip, true)
		FakeRoblox.run(c.world, 0.2)
		local stroke = chip:FindFirstChild("VariantStroke")
		check(stroke.Enabled and stroke.Thickness == 2, "the outline did not land at 2 px")
	end)
end)

describe("Kit polish: icons", function()
	it("draws a glyph until an image id exists, then a tinted image", function()
		local c = client()
		local Kit = c.Kit
		local Icons = load(c, "Icons")
		local saved = { megaphone = Icons.megaphone.id, coins = Icons.coins.id }
		Icons.megaphone.id = ""
		local glyph = Kit.icon("megaphone", 16, Kit.colors.accent)
		Icons.megaphone.id = saved.megaphone
		glyph.Parent = c.stage
		expect(glyph.ClassName):toBe("TextLabel")
		expect(glyph.Text):toBe(Icons.megaphone.glyph)
		expect(glyph:GetAttribute("Icon")):toBe("megaphone")
		expect(glyph.AbsoluteSize.X):toBe(16)
		check(same(glyph.TextColor3, Kit.colors.accent), "the glyph is not tinted")
		local constraint = glyph:FindFirstChildOfClass("UITextSizeConstraint")
		check(constraint ~= nil and constraint.MinTextSize >= Kit.MIN_TEXT, "a glyph can shrink under 12 px")
		Icons.coins.id = "rbxassetid://1"
		local image = Kit.icon("coins", 20)
		Icons.coins.id = saved.coins
		expect(image.ClassName):toBe("ImageLabel")
		expect(image.Image):toBe("rbxassetid://1")
		check(same(image.ImageColor3, Kit.colors.text), "the image is not tinted text")
		expect(Kit.icon("no such icon").Text):toBe("?")
	end)

	it("names an icon for every plan action but Pivot", function()
		local c = client()
		local Icons = load(c, "Icons")
		for _, kind in { "Rally", "Fundraise", "Media", "Attack", "Poll", "RegionPoll", "Gotv" } do
			local name = c.Kit.actionIcon(kind)
			check(name ~= nil and Icons[name] ~= nil, `no icon for {kind}`)
		end
		expect(c.Kit.actionIcon("Pivot")):toBe(nil)
	end)

	it("lists the twelve Lucide icons, each with a glyph", function()
		local c = client()
		local Icons = load(c, "Icons")
		local n = 0
		for name, icon in Icons do
			n += 1
			check(icon.glyph ~= "", `{name} has no glyph`)
			check(icon.id == "" or string.match(icon.id, "^rbxassetid://%d+$") ~= nil, `{name} id {icon.id}`)
		end
		expect(n):toBe(12)
	end)
end)

-- ------------------------------------------------------------------ front page (docs/DESIGN.md D-056)

describe("Kit foundation: orange losses and chunky buttons", function()
	it("has one orange for loss, warn and bad, and readable player text", function()
		local c = client()
		local Kit = c.Kit
		check(same(Kit.colors.loss, Kit.color({ r = 255, g = 122, b = 40 })), "loss is not 255,122,40")
		for _, name in { "warn", "danger", "bad" } do
			check(same(Kit.colors[name], Kit.colors.loss), `{name} is not the loss orange`)
		end
		check(same(Kit.tone("loss"), Kit.colors.loss), "tone loss")
		check(same(Kit.tone("bad"), Kit.colors.loss), "tone bad")
		check(same(Kit.tone("white"), Kit.colors.text), "tone white")
		check(same(Kit.colors.background, Kit.color({ r = 11, g = 16, b = 34 })), "the stage is not navy")
		local view = { players = { { color = "Crimson" }, { color = "Cobalt" } } }
		check(same(Kit.playerText(view, 1), Kit.color({ r = 252, g = 76, b = 113 })), "Crimson text")
		check(same(Kit.playerColor(view, 1), Kit.color({ r = 212, g = 28, b = 66 })), "Crimson fill changed")
		check(same(Kit.textColor(Kit.playerColor(view, 2)), Kit.playerText(view, 2)), "textColor")
	end)

	it("puts a primary's and a secondary's face in a holder with a lip", function()
		local c = client()
		local Kit = c.Kit
		local primary = Kit.button("Lock in", function() end, {
			variant = "primary",
			Name = "LockIn",
			LayoutOrder = 3,
			Size = UDim2.new(1, 0, 0, Kit.PRIMARY_H),
			Parent = c.stage,
		})
		local holder = primary.Parent
		expect(holder.Name):toBe("LockInHolder")
		expect(holder.Parent):toBe(c.stage)
		expect(holder.LayoutOrder):toBe(3)
		expect(Kit.outer(primary)):toBe(holder)
		local lip = holder:FindFirstChild("Lip")
		check(lip ~= nil and same(lip.BackgroundColor3, Kit.colors.accentLip), "no accent lip")
		expect(lip.Position.Y.Offset):toBe(Kit.LIP_PRIMARY)
		expect(lip:GetAttribute("Decor")):toBe(true)
		expect(primary.AbsoluteSize.Y):toBe(56)
		expect(primary.TextSize):toBe(Kit.size.heading)
		expect(primary:FindFirstChildOfClass("UICorner").CornerRadius.Offset):toBe(Kit.radius.button)
		Kit.setEnabled(primary, false)
		check(same(lip.BackgroundColor3, Kit.colors.raisedLip), "a disabled primary keeps the accent lip")
		local secondary = Kit.button("Back", function() end, { variant = "secondary", Parent = c.stage })
		local secondLip = Kit.outer(secondary):FindFirstChild("Lip")
		check(secondLip ~= nil and same(secondLip.BackgroundColor3, Kit.colors.raisedLip), "no secondary lip")
		expect(secondLip.Position.Y.Offset):toBe(Kit.LIP_SECONDARY)
		for _, variant in { "chip", "danger", "ghost" } do
			local button = Kit.button(variant, function() end, { variant = variant, Parent = c.stage })
			expect(button.Parent):toBe(c.stage)
		end
		local flat = Kit.button(
			"Flat",
			function() end,
			{ variant = "secondary", lip = false, Parent = c.stage }
		)
		expect(flat.Parent):toBe(c.stage)
		local icon = Kit.iconButton("+", function() end, { Parent = c.stage })
		expect(icon:FindFirstChildOfClass("UICorner").CornerRadius.Offset):toBe(Kit.radius.control)
		check(Kit.outer(icon):FindFirstChild("Lip") ~= nil, "an icon button has no lip")
	end)

	it("passes later Size, Visible and LayoutOrder changes to the holder", function()
		local c = client()
		local Kit = c.Kit
		local button = Kit.button("Bank", function() end, {
			variant = "secondary",
			Visible = false,
			Parent = c.stage,
		})
		local holder = button.Parent
		expect(holder.Visible):toBe(false)
		button.Visible = true
		expect(holder.Visible):toBe(true)
		button.Size = UDim2.new(0.3, 0, 0, 56)
		expect(holder.Size.X.Scale):toBe(0.3)
		expect(button.Size.X.Scale):toBe(1)
		expect(button.AbsoluteSize.Y):toBe(56)
		button.LayoutOrder = 7
		expect(holder.LayoutOrder):toBe(7)
		button:Destroy()
		expect(holder.Parent):toBe(nil)
	end)

	it("makes filled pills, white pills, eyebrows, icon plates and bevels", function()
		local c = client()
		local Kit = c.Kit
		local loss = Kit.pill("−0.5", "loss", { filled = true, Parent = c.stage })
		check(same(loss.BackgroundColor3, Kit.colors.loss), "a filled loss pill is not orange")
		check(same(loss.TextColor3, Kit.colors.onLoss), "a filled loss pill's text is not dark")
		check(same(loss:FindFirstChild("Edge").Color, Kit.colors.lossEdge), "no lossEdge")
		-- D-058: the battleground mark is outlined, never a white fill (the primary's).
		local white = Kit.pill("Battleground", "white", { Parent = c.stage })
		expect(white.Text):toBe(`{Kit.STAR} Battleground`)
		check(same(white.BackgroundColor3, Kit.colors.field), "a battleground pill is not on a field fill")
		check(same(white.TextColor3, Kit.colors.text), "a battleground pill's text is not white")
		local outline = white:FindFirstChild("Edge")
		check(outline ~= nil and outline.Enabled, "a battleground pill has no outline")
		check(same(outline.Color, Kit.colors.text), "a battleground pill's outline is not white")
		expect(outline.Thickness):toBe(Kit.MARK_STROKE)
		expect(white:GetAttribute("Outlined")):toBe(true)
		-- Re-toned, the star and the outline go; back to white, one star again.
		Kit.paintPill(white, "muted")
		expect(white.Text):toBe("Battleground")
		check(not outline.Enabled, "a plain pill kept the outline")
		Kit.paintPill(white, "white")
		Kit.paintPill(white, "white")
		expect(white.Text):toBe(`{Kit.STAR} Battleground`)
		local verdict = Kit.pill("You win", "good", { filled = true, Parent = c.stage })
		expect(verdict:FindFirstChild("Edge").Thickness):toBe(1)
		local plain = Kit.pill("Your issue", "accent", { Parent = c.stage })
		check(
			same(plain.BackgroundColor3, Kit.colors.raised) and plain:FindFirstChild("Edge") == nil,
			"plain pill"
		)
		local data =
			Kit.pill("+2 Rex", "text", { fill = Kit.color({ r = 206, g = 52, b = 72 }), Parent = c.stage })
		expect(data:GetAttribute("DataColor")):toBe(true)
		local eyebrow = Kit.eyebrow("Just called", { Parent = c.stage })
		expect(eyebrow.Text):toBe("JUST CALLED")
		expect(eyebrow.TextSize):toBe(Kit.size.caption)
		local plate = Kit.iconPlate("megaphone", 24)
		plate.Parent = c.stage
		expect(plate.AbsoluteSize.X):toBe(24)
		check(plate:FindFirstChild("Icon") ~= nil, "no icon in the plate")
		local frame = Kit.box({ Parent = c.stage })
		local edge = Kit.bevel(frame)
		expect(edge.Name):toBe("Edge")
		check(edge:FindFirstChild("EdgeLight") ~= nil, "a bevel is not lit")
	end)

	it("casts shadows beside free-standing objects and glows inside them, never in a list", function()
		local c = client()
		local Kit = c.Kit
		local card = Kit.new("Frame", {
			Name = "Spot",
			Size = UDim2.fromOffset(200, 100),
			Position = UDim2.fromOffset(40, 40),
			ZIndex = 5,
			Parent = c.stage,
		})
		local shadow = Kit.shadow(card)
		check(shadow ~= nil and shadow.Parent == c.stage, "no shadow beside the card")
		expect(shadow.ZIndex):toBe(4)
		expect(shadow:GetAttribute("Decor")):toBe(true)
		expect(shadow:GetAttribute("Asset")):toBe("shadow")
		expect(shadow.Size.X.Offset):toBe(224)
		expect(shadow.Position.Y.Offset):toBe(40 - 12 + 4)
		card.Visible = false
		expect(shadow.Visible):toBe(false)
		local glow = Kit.glow(card, Kit.colors.accent, { scale = 2 })
		check(glow ~= nil and glow.Parent == card and glow.ZIndex == 0, "no glow under the card's children")
		expect(glow:GetAttribute("Asset")):toBe("glow")
		local stack = Kit.stack({ Parent = c.stage })
		local item = Kit.card({ Parent = stack })
		expect(Kit.shadow(item)):toBe(nil)
		expect(Kit.glow(stack, Kit.colors.accent)):toBe(nil)
	end)

	it("builds stamps, monograms, portraits, race bars and the wordmark", function()
		local c = client()
		local Kit = c.Kit
		local cobalt = Kit.color({ r = 52, g = 104, b = 214 })
		local stamp = Kit.stamp("CALLED", cobalt, { Parent = c.stage })
		expect(stamp.Name):toBe("Stamp")
		expect(stamp.Rotation):toBe(-6)
		expect(stamp:GetAttribute("Overhang")):toBe(true)
		local label = stamp:FindFirstChild("Label", true)
		expect(label.Text):toBe("CALLED")
		expect(label.TextSize):toBe(Kit.size.title)
		expect(label.Font.Name):toBe("FredokaOne")
		local hero = Kit.stamp("You lost", Kit.colors.loss, { size = Kit.size.hero, Parent = c.stage })
		check(
			same(hero:FindFirstChild("Label", true).TextColor3, Kit.colors.onLoss),
			"You lost is not dark on orange"
		)
		local mono = Kit.monogram("Dana Okafor", cobalt, 56)
		mono.Parent = c.stage
		expect(mono:FindFirstChild("Initials").Text):toBe("DO")
		expect(mono:GetAttribute("DataColor")):toBe(true)
		expect(mono.AbsoluteSize.X):toBe(56)
		-- A portrait (D-068): the bust on a plate; the initials while the id is 0.
		local face = Kit.portrait("okafor", "Dana Okafor", 48)
		face.Parent = c.stage
		expect(face.Name):toBe("Portrait")
		expect(face:GetAttribute("Portrait")):toBe("okafor")
		expect(face:GetAttribute("DataColor")):toBe(true)
		expect(face:GetAttribute("Ring")):toBe(false)
		expect(face.AbsoluteSize.X):toBe(48)
		local image = face:FindFirstChild("Face")
		expect(image.ClassName):toBe("ImageLabel")
		expect(image.Image):toBe(Kit.portraitImage("okafor"))
		expect(image:FindFirstChildOfClass("UICorner") ~= nil):toBe(true)
		local initials = face:FindFirstChild("Initials")
		expect(initials.Text):toBe("DO")
		expect(initials.Visible):toBe(Kit.portraitImage("okafor") == "")
		Kit.paintPortrait(face, { ring = cobalt, fade = 0.5 })
		expect(face:GetAttribute("Ring")):toBe(true)
		check(same(face:FindFirstChild("Ring").Color, cobalt), "the ring is not the player color")
		expect(face:FindFirstChild("Ring").Thickness >= 2):toBe(true)
		expect(image.ImageTransparency):toBe(0.5)
		local unknown = Kit.portrait(nil, "?", 24)
		expect(unknown:FindFirstChild("Face")):toBe(nil)
		expect(unknown:FindFirstChild("Initials").Text):toBe("?")
		expect(Kit.portraitImage(nil)):toBe("")
		local bar = Kit.raceBar(c.stage, { h = 14, mark = 270 / 538, caption = "270" })
		expect(bar.root.AbsoluteSize.Y):toBe(14 + 8 + Kit.size.caption + Kit.space.xs)
		bar:setColors(cobalt, Kit.color({ r = 206, g = 52, b = 72 }))
		bar:set(0.4, 0.3)
		expect(bar.left.Size.X.Scale):toBe(0.4)
		expect(bar.right.Size.X.Scale):toBe(0.3)
		bar:set(0.8, 0.5)
		expect(bar.right.Size.X.Scale < 0.21):toBe(true)
		check(math.abs(bar.tick.Position.X.Scale - 270 / 538) < 1e-6, "the tick is not at 270")
		bar:cross()
		-- The lockup (D-064): the name, scaled to fit but never over 72, and the
		-- tagline on a ribbon whose text size is part of the picture (Lockup).
		local mark = Kit.wordmark(nil, { Parent = c.stage })
		local text = mark:FindFirstChild("Mark")
		expect(text.Text):toBe("LANDSLIDE")
		expect(text.TextSize):toBe(72)
		expect(text.TextScaled):toBe(true)
		expect(text:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize):toBe(72)
		expect(text:GetAttribute("Wordmark")):toBe(true)
		local ribbon = mark:FindFirstChild("Ribbon")
		expect(ribbon:GetAttribute("Lockup")):toBe(true)
		expect(ribbon:FindFirstChild("Tagline").Text):toBe("RACE TO 270")
		expect(mark.Size.Y.Offset):toBe(Kit.wordmarkHeight())
		local bare = Kit.wordmark(nil, { Parent = c.stage }, { tagline = false })
		expect(bare:FindFirstChild("Ribbon")):toBe(nil)
		expect(bare.Size.Y.Offset):toBe(72 + 2 * Kit.space.sm)
		Rig.noErrors(c.world)
	end)
end)
