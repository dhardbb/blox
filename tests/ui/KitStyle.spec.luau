--!strict
-- Style v2 building blocks (docs/UI-STYLE.md): the new Kit tokens and
-- components, Header's "now" line and time bar, Sheet, CoachTip, and the UI
-- audit's style rules on hand-built trees. Each module is loaded into a client
-- the way a screen would load it (FakeRoblox.require).

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
	stage: any,
}

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

local function noop() end

describe("Kit style v2 tokens", function()
	it("has the style limits, motion and glyphs", function()
		local Kit = client().Kit
		expect(Kit.MAX_TEXT_SIZES):toBe(4)
		expect(Kit.MAX_LABEL_WORDS):toBe(8)
		expect(Kit.MAX_TEXT_WORDS):toBe(30)
		expect(Kit.PILL_H):toBe(24)
		expect(Kit.NOW_H):toBe(32)
		check(
			Kit.motion.fast < Kit.motion.base and Kit.motion.base < Kit.motion.slow,
			"motion is not ordered"
		)
		check(Kit.motion.slow <= 0.4, "motion is too slow")
		expect(Kit.glyph.close):toBe("×")
		expect(Kit.glyph.minus):toBe("−")
	end)

	it("has semantic tones, with warn apart from the accent", function()
		local Kit = client().Kit
		check(same(Kit.tone("bad"), Kit.colors.danger), "bad is not danger")
		check(same(Kit.tone("good"), Kit.colors.good), "good is wrong")
		check(not same(Kit.tone("warn"), Kit.colors.accent), "warn is the accent")
		check(same(Kit.tone("muted"), Kit.colors.muted), "muted is wrong")
	end)

	it("counts words", function()
		local Kit = client().Kit
		expect(Kit.words("")):toBe(0)
		expect(Kit.words("  Lock   in ")):toBe(2)
		expect(Kit.words("Pick 3 issues, then Lock in")):toBe(6)
	end)
end)

describe("Kit style v2 components", function()
	it("makes a ghost button with no fill that keeps it when disabled", function()
		local c = client()
		local ghost = c.Kit.button("More", noop, { variant = "ghost", Parent = c.stage })
		expect(ghost.BackgroundTransparency):toBe(1)
		expect(ghost:GetAttribute("Variant")):toBe("ghost")
		c.Kit.setEnabled(ghost, false)
		expect(ghost.BackgroundTransparency):toBe(1)
		check(same(ghost.TextColor3, c.Kit.colors.disabledText), "disabled ghost text is not muted")
		expect(ghost.AbsoluteSize.Y):toBe(44)
	end)

	it("makes cards, card buttons, chips, pills, stacks and dividers", function()
		local c = client()
		local Kit = c.Kit
		local card = Kit.card({ Parent = c.stage })
		expect(card.Name):toBe("Card")
		expect(card.AutomaticSize.Name):toBe("Y")
		check(card:FindFirstChildOfClass("UIListLayout") ~= nil, "a card has no list")
		local picked = 0
		local option = Kit.cardButton(function()
			picked += 1
		end, { Name = "OptionA", Parent = c.stage })
		Kit.text("Side with the staff", { Parent = option })
		press(c, option)
		expect(picked):toBe(1)
		Kit.setSelected(option, true)
		check(option.VariantStroke.Enabled, "a selected card button has no outline")
		local chip = Kit.chip("Jobs", noop, { Parent = c.stage })
		expect(chip:GetAttribute("Variant")):toBe("chip")
		local pill = Kit.pill("Battleground", "warn", { Parent = c.stage })
		expect(pill.AbsoluteSize.Y):toBe(Kit.PILL_H)
		expect(pill.TextFits):toBe(true)
		check(same(pill.TextColor3, Kit.colors.warn), "the pill tone is not applied")
		local stack = Kit.stack({ Parent = c.stage }, "Horizontal", Kit.space.xs)
		expect(stack:FindFirstChildOfClass("UIListLayout").FillDirection.Name):toBe("Horizontal")
		expect(Kit.divider({ Parent = c.stage }).AbsoluteSize.Y):toBe(1)
		expect(Kit.title("Week 3", { Parent = c.stage }).TextSize):toBe(Kit.size.title)
	end)

	it("marks details areas and data colors", function()
		local c = client()
		local box = c.Kit.details(c.Kit.box({ Parent = c.stage }))
		expect(box:GetAttribute("Details")):toBe(true)
		local fill = c.Kit.dataColor(c.Kit.box({ Parent = c.stage }))
		expect(fill:GetAttribute("DataColor")):toBe(true)
	end)

	it("applies a tween's goals at once without a TweenService", function()
		local c = client()
		local frame = c.Kit.box({ Parent = c.stage })
		c.Kit.tween(frame, { BackgroundTransparency = 0.5 })
		expect(frame.BackgroundTransparency):toBe(0.5)
	end)
end)

describe("Header now line and time bar", function()
	it("adds the now line under the row only when asked", function()
		local c = client()
		local Header = load(c, "Header")
		local plain = Header.new(c.stage, { title = "Draft" })
		expect(plain.height):toBe(c.Kit.HEADER_H)
		expect(plain.now):toBe(nil)
		plain:setNow("ignored") -- no line: a no-op
		local header = Header.new(c.stage, { title = "Week 3", now = true, name = "NowHeader" })
		expect(header.height):toBe(c.Kit.HEADER_H + c.Kit.NOW_H)
		expect(header.root.AbsoluteSize.Y):toBe(c.Kit.HEADER_H + c.Kit.NOW_H)
		header:setNow("Tap a state, then Lock in")
		expect(header.now.Text):toBe("Tap a state, then Lock in")
		expect(header.timer.AbsoluteSize.Y):toBe(c.Kit.HEADER_H)
	end)

	it("shows a time bar only with a total, danger under the warning", function()
		local c = client()
		local Header = load(c, "Header")
		local header = Header.new(c.stage, { title = "Week 3" })
		local bar = header.root.TimerBar
		header:setTimer(30)
		expect(bar.Visible):toBe(false)
		header:setTimer(25, nil, 50)
		expect(bar.Visible):toBe(true)
		expect(bar.Fill.Size.X.Scale):toBe(0.5)
		check(same(bar.Fill.BackgroundColor3, c.Kit.colors.accent), "the bar is not accent")
		header:setTimer(5, nil, 50)
		check(same(bar.Fill.BackgroundColor3, c.Kit.colors.danger), "the bar is not danger under 10 s")
		header:setTimer(nil)
		expect(bar.Visible):toBe(false)
	end)
end)

describe("Sheet", function()
	it("opens from the bottom on a phone and closes from the scrim or ×", function()
		local c = client(Rig.PHONE)
		local Sheet = load(c, "Sheet")
		local closed = 0
		local sheet = Sheet.new(c.stage, {
			title = "Ohio",
			name = "StateSheet",
			onClose = function()
				closed += 1
			end,
		})
		expect(sheet.root.Visible):toBe(false)
		expect(sheet.body:GetAttribute("Details")):toBe(true)
		sheet:open()
		expect(sheet:isOpen()):toBe(true)
		expect(sheet.root.Visible):toBe(true)
		expect(sheet.panel.AnchorPoint.Y):toBe(1)
		expect(sheet.panel.AbsoluteSize.X):toBe(390)
		press(c, sheet.root.Scrim)
		expect(sheet:isOpen()):toBe(false)
		expect(closed):toBe(1)
		sheet:open()
		press(c, sheet.closeButton)
		expect(sheet.root.Visible):toBe(false)
		expect(closed):toBe(2)
		sheet:close() -- already closed: no second callback
		expect(closed):toBe(2)
	end)

	it("is a centered panel no wider than SHEET_MAX_W on a wide screen", function()
		local c = client({ x = 1280, y = 720 })
		local Sheet = load(c, "Sheet")
		local sheet = Sheet.new(c.stage, { title = "How it works" })
		sheet:open()
		expect(sheet.panel.AnchorPoint.Y):toBe(0.5)
		expect(sheet.panel.AbsoluteSize.X):toBe(c.Kit.SHEET_MAX_W)
		sheet:setTitle("Rules")
		expect(sheet.title.Text):toBe("Rules")
	end)
end)

describe("CoachTip", function()
	it("shows a tip once, until it is dismissed", function()
		local c = client()
		local CoachTip = load(c, "CoachTip")
		CoachTip.reset()
		local tip = CoachTip.show(c.stage, { id = "campaign.map" })
		check(tip ~= nil, "the tip did not show")
		expect(tip.root:GetAttribute("TipId")):toBe("campaign.map")
		expect(tip.root.Row.TipText.Text):toBe(CoachTip.TIPS["campaign.map"])
		expect(tip.button.AbsoluteSize.Y):toBe(44)
		press(c, tip.button)
		expect(tip.root.Parent):toBe(nil)
		expect(CoachTip.seen("campaign.map")):toBe(true)
		expect(CoachTip.show(c.stage, { id = "campaign.map" })):toBe(nil)
		expect(CoachTip.show(c.stage, { id = "no.such.tip" })):toBe(nil)
	end)

	it("can be turned off and can use another store", function()
		local c = client()
		local CoachTip = load(c, "CoachTip")
		CoachTip.reset()
		CoachTip.setEnabled(false)
		expect(CoachTip.show(c.stage, { id = "select.issues" })):toBe(nil)
		CoachTip.setEnabled(true)
		local saved: { [string]: boolean } = { ["select.issues"] = true }
		CoachTip.useStore({
			get = function(id: string): boolean
				return saved[id] == true
			end,
			set = function(id: string)
				saved[id] = true
			end,
		})
		expect(CoachTip.show(c.stage, { id = "select.issues" })):toBe(nil)
		CoachTip.markSeen("draft.pick")
		expect(saved["draft.pick"]):toBe(true)
		CoachTip.useStore(nil)
	end)

	it("keeps every tip short", function()
		local c = client()
		local CoachTip = load(c, "CoachTip")
		for id, text in CoachTip.TIPS do
			check(c.Kit.words(text) <= 12, `tip {id} has {c.Kit.words(text)} words`)
		end
	end)
end)

describe("UI audit style rules", function()
	type Tree = { c: Client, Audit: any, root: any }

	local function tree(): Tree
		local c = client()
		local Audit = load(c, "Audit")
		local root = c.Kit.box({ Name = "TestScreen", Size = UDim2.fromOffset(400, 300), Parent = c.stage })
		root:SetAttribute("PrimaryOptional", true)
		return { c = c, Audit = Audit, root = root }
	end

	local function styleRules(t: Tree): { string }
		local list = {}
		for _, finding in t.Audit.check(t.root, { style = true }) do
			if t.Audit.STYLE[finding.rule] then
				table.insert(list, finding.rule)
			end
		end
		table.sort(list)
		return list
	end

	it("leaves the style rules out of a plain check", function()
		local t = tree()
		t.c.Kit.new("Frame", {
			BackgroundColor3 = FakeRoblox.types.Color3.fromRGB(1, 2, 3),
			Size = UDim2.fromOffset(10, 10),
			Parent = t.root,
		})
		expect(#t.Audit.check(t.root)):toBe(0)
		expect(table.concat(styleRules(t), ",")):toBe("tokenColor")
	end)

	it("allows tokens, player colors and marked data colors", function()
		local t = tree()
		local Kit = t.c.Kit
		Kit.panel({ Size = UDim2.fromOffset(100, 100), Parent = t.root })
		Kit.text("Amber", {
			TextColor3 = Kit.color({ r = 232, g = 164, b = 40 }),
			Size = UDim2.fromOffset(100, 22),
			Parent = t.root,
		})
		local row = Kit.dataColor(Kit.box({ Size = UDim2.fromOffset(100, 30), Parent = t.root }))
		Kit.new("Frame", {
			BackgroundColor3 = FakeRoblox.types.Color3.fromRGB(90, 70, 40),
			Size = UDim2.fromOffset(10, 10),
			Parent = row,
		})
		expect(#styleRules(t)):toBe(0)
		local stroke = Kit.new("UIStroke", { Color = FakeRoblox.types.Color3.fromRGB(9, 9, 9) })
		stroke.Parent = Kit.box({ Size = UDim2.fromOffset(10, 10), Parent = t.root })
		expect(table.concat(styleRules(t), ",")):toBe("tokenColor")
	end)

	it("flags long labels and walls of text outside details", function()
		local t = tree()
		local Kit = t.c.Kit
		Kit.button("one two three four five six seven eight nine", noop, {
			Size = UDim2.fromOffset(300, 44),
			Parent = t.root,
		})
		local long = string.rep("word ", 31)
		Kit.text(long, { Size = UDim2.fromOffset(300, 100), Parent = t.root })
		local details = Kit.details(Kit.box({ Size = UDim2.fromOffset(300, 100), Parent = t.root }))
		Kit.text(long, { Size = UDim2.fromScale(1, 1), Parent = details })
		expect(table.concat(styleRules(t), ",")):toBe("labelWords,wallOfText")
	end)

	it("flags a fifth text size", function()
		local t = tree()
		local Kit = t.c.Kit
		local y = 0
		for _, size in { Kit.size.caption, Kit.size.body, Kit.size.heading, Kit.size.title } do
			Kit.text("Aa", {
				TextSize = size,
				Size = UDim2.fromOffset(100, 50),
				Position = UDim2.fromOffset(0, y),
				Parent = t.root,
			})
			y += 50
		end
		expect(#styleRules(t)):toBe(0)
		Kit.text("Aa", {
			TextSize = Kit.size.hero,
			Size = UDim2.fromOffset(100, 50),
			Position = UDim2.fromOffset(200, 0),
			Parent = t.root,
		})
		expect(table.concat(styleRules(t), ",")):toBe("textSizes")
	end)

	it("keeps pending style rules as notes even when strict", function()
		local t = tree()
		local Kit = t.c.Kit
		Kit.text(string.rep("word ", 31), { Size = UDim2.fromOffset(300, 100), Parent = t.root })
		expect(t.Audit.run(t.root, "Brand new screen", { strict = true })):toBe(1)
		t.Audit.PENDING["Brand new screen"] = { wallOfText = true }
		expect(t.Audit.run(t.root, "Brand new screen", { strict = true })):toBe(0)
		t.Audit.PENDING["Brand new screen"] = nil
	end)
end)
