--!strict
-- A sheet (docs/UI-STYLE.md, progressive disclosure): the one place for details
-- that do not fit the screen's main job, such as a state's full numbers, the
-- rules behind a number, or the whole results breakdown. On a phone (portrait)
-- it slides up from the bottom, full width; on a wide screen it is a centered
-- panel at most Kit.SHEET_MAX_W wide. A dimmed scrim covers the screen behind
-- it; tapping the scrim or the × closes it.
--
--   local sheet = Sheet.new(screenRoot, { title = "Ohio", name = "StateSheet",
--       height = 0.5 })                          -- height: share of the screen, optional
--   Kit.text("…", { Parent = sheet.body })      -- fill the body (a list, gap sm)
--   sheet:open() · sheet:close() · sheet:isOpen() -> boolean
--   sheet:setTitle(text)
--   sheet:setPortrait(portrait?)  -- nil: decide from the parent's size at open()
--   sheet.root    Frame (opts.name, default "Sheet"), full size, ZIndex 30, hidden
--                 while closed
--   sheet.panel   Frame "Panel"; sheet.body Frame "Body" (a details area: long
--                 text is fine here); sheet.closeButton TextButton "Close"
--
-- Look (D-056): elevation 3. The panel is card-lit (surfaceTop -> surface), with
-- Kit.radius.sheet (16) corners, a 1 px line edge lit from the top and a deep
-- shadow (dy 8, spread 20); the scrim is the background at 0.3. On a wide
-- screen the panel scales in from 0.96; on a phone it carries a 36 x 4 px
-- drag handle ("Handle") at the top.
--
-- Rules: a sheet never holds the screen's primary action (the screen's pinned
-- Lock in stays the only accent button); put at most one secondary action at the
-- end of the body. Mount it as the last child of the screen root so it draws
-- above everything else on the screen.

local Kit = require(script.Parent.Kit)
local Motion = require(script.Parent.Motion)

local Sheet = {}

local Z = 30 -- above the screen (Help is 40, the toast 50)
local PORTRAIT_HEIGHT = 0.7 -- share of the screen a phone sheet takes
local WIDE_HEIGHT = 0.8 -- share of the screen height on a wide screen
local COMPACT_HEIGHT = 1 -- share of the screen height on a landscape phone: every sheet takes it all (D-089)
local SHADOW_DY = 8 -- px
local SHADOW_SPREAD = 20 -- px
local OPEN_FROM = 0.96 -- the panel's scale as it opens on a wide screen
local HANDLE_W = 36 -- px, the phone sheet's drag handle
local HANDLE_H = 4 -- px
local HANDLE_TOP = 6 -- px from the panel's top edge

export type Options = {
	title: string,
	name: string?,
	onClose: (() -> ())?, -- after the sheet closes (× or scrim)
	portrait: boolean?, -- force a layout; nil decides at open()
	height: number?, -- share of the screen height (default 0.7 on a phone, 0.8 wide)
}

export type Sheet = {
	root: Frame,
	panel: Frame,
	body: Frame,
	title: TextLabel,
	closeButton: TextButton,
	open: (self: Sheet) -> (),
	close: (self: Sheet) -> (),
	isOpen: (self: Sheet) -> boolean,
	setTitle: (self: Sheet, text: string) -> (),
	setPortrait: (self: Sheet, portrait: boolean?) -> (),
}

function Sheet.new(parent: Instance, options: Options): Sheet
	local forced: boolean? = options.portrait
	local opened = false

	local root = Kit.box({
		Name = options.name or "Sheet",
		ZIndex = Z,
		Visible = false,
	})

	local sheet: Sheet
	local scrim = Kit.new("TextButton", {
		Name = "Scrim",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.colors.background,
		BackgroundTransparency = Kit.SCRIM_TRANSPARENCY,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = Z,
		Parent = root,
	}) :: TextButton
	scrim.Activated:Connect(function()
		sheet:close()
	end)

	local panel = Kit.new("Frame", {
		Name = "Panel",
		BorderSizePixel = 0,
		ZIndex = Z + 2,
		Parent = root,
	}) :: Frame
	Kit.depth(panel, Kit.colors.surfaceTop, Kit.colors.surface)
	Kit.corner(Kit.radius.sheet).Parent = panel
	Kit.bevel(panel, Kit.colors.line, 1, 1)
	Kit.pad(Kit.space.md).Parent = panel
	Kit.shadow(panel, { dy = SHADOW_DY, spread = SHADOW_SPREAD })
	local handle = Kit.new("Frame", {
		Name = "Handle",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, HANDLE_TOP - Kit.space.md),
		Size = UDim2.fromOffset(HANDLE_W, HANDLE_H),
		BackgroundColor3 = Kit.colors.line,
		BorderSizePixel = 0,
		Visible = false,
		Parent = panel,
	})
	handle:SetAttribute("Decor", true)
	Kit.corner(Kit.radius.pill).Parent = handle
	local widthCap = Kit.new("UISizeConstraint", { Parent = panel }) :: UISizeConstraint

	local titleRow = Kit.box({
		Name = "TitleRow",
		Size = UDim2.new(1, 0, 0, Kit.HEADER_H),
		Parent = panel,
	})
	local title = Kit.heading(options.title, {
		Name = "Title",
		Size = UDim2.new(1, -(Kit.MIN_TOUCH + Kit.space.sm), 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		TextScaled = true,
		Parent = titleRow,
	})
	local closeButton = Kit.iconButton(Kit.glyph.close, function()
		sheet:close()
	end, {
		Name = "Close",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Parent = titleRow,
	})

	local scroll = Kit.new("ScrollingFrame", {
		Name = "Scroll",
		Position = UDim2.fromOffset(0, Kit.HEADER_H + Kit.space.sm),
		Size = UDim2.new(1, 0, 1, -(Kit.HEADER_H + Kit.space.sm)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		Parent = panel,
	})
	local body = Kit.stack({ Name = "Body", Parent = scroll })
	Kit.details(body)

	local function portrait(): boolean
		if forced ~= nil then
			return forced
		end
		local holder = root.Parent
		if holder and holder:IsA("GuiObject") then
			local size = (holder :: GuiObject).AbsoluteSize
			return size.Y > size.X
		end
		return false
	end

	local function layout()
		local phone = portrait()
		handle.Visible = phone
		if phone then
			panel.AnchorPoint = Vector2.new(0.5, 1)
			panel.Position = UDim2.fromScale(0.5, 1)
			panel.Size = UDim2.fromScale(1, options.height or PORTRAIT_HEIGHT)
			widthCap.MaxSize = Vector2.new(math.huge, math.huge)
		else
			-- A landscape phone (D-089): height is what is short, so the panel
			-- takes the whole height whatever share the sheet asked for.
			local holder = root.Parent
			local short = holder ~= nil
				and holder:IsA("GuiObject")
				and Kit.compact((holder :: GuiObject).AbsoluteSize)
			panel.AnchorPoint = Vector2.new(0.5, 0.5)
			panel.Position = UDim2.fromScale(0.5, 0.5)
			panel.Size = UDim2.fromScale(1, if short then COMPACT_HEIGHT else options.height or WIDE_HEIGHT)
			widthCap.MaxSize = Vector2.new(Kit.SHEET_MAX_W, math.huge)
		end
	end

	sheet = {
		root = root,
		panel = panel,
		body = body,
		title = title,
		closeButton = closeButton,
		open = function(_self: Sheet)
			layout()
			opened = true
			root.Visible = true
			scrim.BackgroundTransparency = 1
			Kit.tween(scrim, { BackgroundTransparency = Kit.SCRIM_TRANSPARENCY }, Kit.motion.base)
			if not portrait() then
				Motion.pop(panel, OPEN_FROM)
			end
		end,
		close = function(_self: Sheet)
			if not opened then
				return
			end
			opened = false
			root.Visible = false
			local handler = options.onClose
			if handler then
				handler()
			end
		end,
		isOpen = function(_self: Sheet): boolean
			return opened
		end,
		setTitle = function(_self: Sheet, text: string)
			title.Text = text
		end,
		setPortrait = function(_self: Sheet, value: boolean?)
			forced = value
			if opened then
				layout()
			end
		end,
	}
	layout()
	root.Parent = parent
	return sheet
end

return Sheet
