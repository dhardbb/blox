--!strict
-- "Report a bug" (docs/DESIGN.md D-090): a small sheet where a player writes
-- what went wrong. Opened from the Lobby's corner (the bug toggle) and from the
-- in-match Help sheet ("Report a bug"), so it is always one or two taps away
-- and never in the way. Send checks the length here (Net/BugReport.clean, the
-- same rule as the server), then sends the text with the screen it was opened
-- from (ctx.net.bugReport); the server filters it (TextService), rate-limits
-- it, stores it with the game version and the match id, and says "Thanks" in
-- the toast. The counter shows characters used of BUG_REPORT_MAX_CHARS; text
-- past that is cut as it is typed.
--
-- Mounted once by App.client like ReportName (ZIndex 45). Never a primary:
-- Send is the sheet's one featured button, Cancel closes.
--
--   local bug = BugSheet.mount(parent, ctx)
--   bug.open(screen)   the screen tag sent with the report ("Lobby", "Campaign"…)
--   bug.close() · bug.isOpen() -> boolean
--   bug.root   Frame "BugOverlay" (Visible only while open; PrimaryOptional)
--   Elements: BugSheet (UI/Sheet), BugHint, BugText (TextBox), BugCount,
--   BugSend, BugCancel

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BugReport = require(ReplicatedStorage.Shared.Net.BugReport)
local Words = require(ReplicatedStorage.Shared.UI.Words.Lobby)

local Featured = require(script.Parent.Featured)
local Kit = require(script.Parent.Kit)
local Sheet = require(script.Parent.Sheet)
local Types = require(script.Parent.Parent.Screens.Types)

local BugSheet = {}

local Z = 45 -- above the Help sheet (40), below the toast (50)
local HEIGHT = 0.6 -- share of a portrait screen
local BOX_H = 80 -- px, the text box: three to four lines

export type BugSheet = {
	root: Frame,
	open: (screen: string?) -> (),
	close: () -> (),
	isOpen: () -> boolean,
}

function BugSheet.mount(parent: Instance, ctx: Types.Ctx): BugSheet
	local config = ctx.config
	local max = config.BUG_REPORT_MAX_CHARS
	local root = Kit.new("Frame", {
		Name = "BugOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = Z,
		Visible = false,
	}) :: Frame
	root:SetAttribute("PrimaryOptional", true)

	local isOpen = false
	local screen = "Unknown"
	local function hide()
		isOpen = false
		root.Visible = false
	end
	local sheet =
		Sheet.new(root, { title = Words.BUG_TITLE, name = "BugSheet", height = HEIGHT, onClose = hide })
	Kit.text(Words.BUG_HINT, {
		Name = "BugHint",
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Kit.colors.muted,
		Parent = sheet.body,
	})
	local box = Kit.new("TextBox", {
		Name = "BugText",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, BOX_H),
		BackgroundColor3 = Kit.colors.field,
		BorderSizePixel = 0,
		Font = Kit.font.body,
		TextSize = Kit.size.body,
		TextColor3 = Kit.colors.text,
		TextWrapped = true,
		MultiLine = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		PlaceholderText = Words.BUG_PLACEHOLDER,
		PlaceholderColor3 = Kit.colors.muted,
		ClearTextOnFocus = false,
		Text = "",
		Parent = sheet.body,
	}) :: TextBox
	Kit.corner(Kit.radius.control).Parent = box
	Kit.stroke(Kit.colors.line, 1).Parent = box
	Kit.pad(Kit.space.sm).Parent = box
	local count = Kit.caption("", {
		Name = "BugCount",
		LayoutOrder = 3,
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, Kit.size.caption + Kit.space.xs),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = sheet.body,
	})
	local function recount()
		local text = box.Text
		local length = utf8.len(text) or #text
		if length > max then
			-- Cut what is past the limit (at a character, never mid-byte).
			local cut = utf8.offset(text, max + 1)
			box.Text = if cut then string.sub(text, 1, cut - 1) else text
			return -- the change fires again with the cut text
		end
		count.Text = `{length}/{max}`
	end
	pcall(function()
		box:GetPropertyChangedSignal("Text"):Connect(recount)
	end)
	recount()

	local send = Kit.button(Words.BUG_SEND, function()
		recount()
		local text, why = BugReport.clean(box.Text, config)
		if text == nil then
			ctx.store.say(
				if why == BugReport.Reason.TooLong then Words.BUG_TOO_LONG else Words.BUG_TOO_SHORT,
				true
			)
			return
		end
		local net: any = ctx.net
		if type(net.bugReport) == "function" then
			net.bugReport(text, screen)
		else
			ctx.net.send("BugReport", { text = text, screen = screen })
		end
		box.Text = ""
		sheet:close()
		hide()
	end, { variant = "secondary", Name = "BugSend", LayoutOrder = 4, Parent = sheet.body })
	Featured.set(send, Kit.colors.accent)
	Kit.button(Words.BUG_CANCEL, function()
		sheet:close()
		hide()
	end, { variant = "ghost", Name = "BugCancel", LayoutOrder = 5, Parent = sheet.body })

	local function open(at: string?)
		screen = BugReport.screen(at)
		recount()
		isOpen = true
		root.Visible = true
		sheet:open()
	end

	root.Parent = parent
	return {
		root = root,
		open = open,
		close = function()
			sheet:close()
			hide()
		end,
		isOpen = function(): boolean
			return isOpen
		end,
	}
end

return BugSheet
