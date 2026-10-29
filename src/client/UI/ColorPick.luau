--!strict
-- The color option (docs/DESIGN.md D-055): a Lobby button that says your color
-- and opens a sheet with Auto (red or blue) and the six colors. Everything here
-- follows the server's lobby status: the button and sheet exist only while it
-- carries `colorPass` (the pass is set up), the outline marks the saved color,
-- and the server alone decides who owns the pass.
--
--   Without the pass: the swatches are shown but greyed, with one line and a
--   "Get the Color Pass" secondary (Roblox's purchase prompt; the server hears
--   the outcome and sends a new status).
--   With the pass: tapping a swatch saves it (ctx.net.setColor); Auto clears it.
--
--   local pick = ColorPick.new(screenRoot, ctx, { LayoutOrder = 5, Parent = column })
--   pick.button   TextButton "ColorButton" (a monogram and "Color: …"), hidden without the pass
--   pick.sheet    the Sheet "ColorSheet": ColorHint, ColorTie, Swatches (Swatch_Auto,
--                 Swatch_<Color>; attribute Locked on each while greyed), BuyColorPass
--
-- Each swatch shows the player's own initial as a monogram in that color
-- (Kit.monogram, D-056): "this is you in Teal".
--   pick.update(lobby)   from the screen's update
--   pick.open()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Words = require(ReplicatedStorage.Shared.UI.Words.Setup)

local Kit = require(script.Parent.Kit)
local Sheet = require(script.Parent.Sheet)

local ColorPick = {}

local DOT = 36 -- px, a swatch's monogram (36, not 40: "Crimson" keeps body size on a phone)
local BUTTON_DOT = 24 -- px, the Color button's monogram
local SWATCH_H = Kit.PRIMARY_H -- px, a row of swatches (a 40 px monogram and its padding)
local PER_ROW = 3 -- swatches in a row (three fit a 390 px phone)
local AUTO = "Auto" -- the swatch that clears the pick
local SHEET_HEIGHT = 0.55 -- share of a phone's screen
local LOCKED_FADE = 0.3 -- a locked swatch's dot transparency (its label goes muted)

export type ColorPick = {
	button: TextButton,
	sheet: Sheet.Sheet,
	update: (lobby: any?) -> (),
	open: () -> (),
}

-- The local player's name, for the monograms ("You" headless or before join).
local function playerName(): string
	local player = Players.LocalPlayer
	if player == nil then
		return "You"
	end
	local display = (player :: any).DisplayName
	return if type(display) == "string" and display ~= "" then display else player.Name
end

-- The player's monogram in a player color (neutral for nil).
local function dot(parent: Instance, color: string?, order: number, px: number?): Frame
	local frame = Kit.monogram(playerName(), Kit.color(Colors.of(color)), px or DOT)
	frame.Name = "Dot"
	frame.LayoutOrder = order
	frame.Parent = parent
	return frame
end

-- A chip with monograms then a label (the button's own text stays empty).
local function labelled(button: TextButton, dots: { string? }, text: string): TextLabel
	local content = Kit.box({ Name = "Content", Parent = button })
	local list = Kit.list("Horizontal", Kit.space.xs)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = content
	for k, color in dots do
		dot(content, color, k)
	end
	local used = #dots * (DOT + Kit.space.xs)
	local label = Kit.text(text, {
		Name = "Label",
		LayoutOrder = #dots + 1,
		Size = UDim2.new(1, -used, 1, 0),
		Font = Kit.font.medium,
		TextScaled = true,
		TextWrapped = false,
		Parent = content,
	})
	Kit.new("UITextSizeConstraint", {
		MaxTextSize = Kit.size.body,
		MinTextSize = Kit.MIN_TEXT,
		Parent = label,
	})
	return label
end

function ColorPick.new(screen: Instance, ctx: any, props: { [string]: any }?): ColorPick
	local p: { [string]: any } = props or {}
	local sheet = Sheet.new(screen, { title = Words.COLOR_TITLE, name = "ColorSheet", height = SHEET_HEIGHT })

	local passId: number? = nil
	local owned = false
	local saved: string? = nil

	local button = Kit.button("", function()
		sheet:open()
	end, {
		variant = "secondary",
		Name = "ColorButton",
		LayoutOrder = p.LayoutOrder or 0,
		Visible = false,
	})
	local buttonContent = Kit.box({ Name = "Content", Parent = button })
	local list = Kit.list("Horizontal", Kit.space.sm)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = buttonContent
	local buttonDot = dot(buttonContent, nil, 1, BUTTON_DOT)
	local buttonLabel = Kit.text("", {
		Name = "Label",
		LayoutOrder = 2,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Kit.font.medium,
		TextWrapped = false,
		Parent = buttonContent,
	})

	-- ------------------------------------------------------------ the sheet

	local body = sheet.body
	local hint = Kit.text("", {
		Name = "ColorHint",
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = body,
	})
	local tie = Kit.caption(Words.COLOR_TIE, { Name = "ColorTie", LayoutOrder = 2, Parent = body })

	local swatches =
		Kit.stack({ Name = "Swatches", LayoutOrder = 3, Parent = body }, "Vertical", Kit.space.sm)
	local buttons: { [string]: TextButton } = {}
	local labels: { [string]: TextLabel } = {}
	local function choose(name: string)
		if not owned then
			return
		end
		local setColor = ctx.net.setColor
		if setColor then
			setColor(if name == AUTO then nil else name)
		end
	end
	local function row(order: number): Frame
		local frame = Kit.box({
			Name = `Row{order}`,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, SWATCH_H),
			Parent = swatches,
		})
		Kit.list("Horizontal", Kit.space.sm).Parent = frame
		return frame
	end
	local gap = Kit.space.sm * (PER_ROW - 1) / PER_ROW
	local current: Frame? = nil
	for k, color in Candidates.colors do
		if (k - 1) % PER_ROW == 0 then
			current = row(math.floor((k - 1) / PER_ROW) + 1)
		end
		local swatch = Kit.chip("", function()
			choose(color)
		end, {
			Name = `Swatch_{color}`,
			LayoutOrder = k,
			Size = UDim2.new(1 / PER_ROW, -gap, 1, 0),
			Parent = current,
		})
		labels[color] = labelled(swatch, { color }, color)
		buttons[color] = swatch
	end
	local autoRow = row(math.ceil(#Candidates.colors / PER_ROW) + 1)
	local auto = Kit.chip("", function()
		choose(AUTO)
	end, { Name = `Swatch_{AUTO}`, LayoutOrder = 1, Size = UDim2.fromScale(1, 1), Parent = autoRow })
	labels[AUTO] = labelled(auto, { Candidates.colors[1], Candidates.colors[2] }, Words.COLOR_AUTO)
	buttons[AUTO] = auto

	local buy = Kit.button(Words.COLOR_BUY, function()
		local id = passId
		local buyPass = ctx.net.buyPass
		if id and buyPass then
			buyPass(id)
		end
	end, {
		variant = "secondary",
		Name = "BuyColorPass",
		-- Under the hint, over the (faded) swatches: on a landscape phone the
		-- sheet's end is under the edge, and the button is what the hint is about (fix17).
		LayoutOrder = 2,
		Parent = body,
	})

	local function render()
		local shown = if owned then saved else nil
		buttonLabel.Text = Words.colorButton(shown)
		local tint = Kit.color(Colors.of(shown))
		buttonDot.BackgroundColor3 = tint
		local edge = buttonDot:FindFirstChild("Edge") :: UIStroke?
		if edge then
			edge.Color = Kit.color(Colors.tint(Colors.of(shown), Colors.background, 0.35))
		end
		local initials = buttonDot:FindFirstChild("Initials") :: TextLabel?
		if initials then
			initials.TextColor3 = Kit.color(Colors.onColor(Colors.of(shown)))
		end
		buttonDot.Visible = shown ~= nil
		hint.Text = if owned then Words.COLOR_OWNED else Words.COLOR_LOCKED
		tie.Visible = owned
		buy.Visible = not owned
		local selected = shown or AUTO
		for name, swatch in buttons do
			Kit.setEnabled(swatch, owned)
			Kit.setSelected(swatch, name == selected)
			swatch:SetAttribute("Locked", not owned)
			labels[name].TextColor3 = if owned then Kit.colors.text else Kit.colors.muted
			for _, child in swatch:GetDescendants() do
				if child.Name == "Dot" and child:IsA("Frame") then
					child.BackgroundTransparency = if owned then 0 else LOCKED_FADE
					local letters = child:FindFirstChild("Initials") :: TextLabel?
					if letters then
						letters.TextTransparency = if owned then 0 else LOCKED_FADE
					end
				end
			end
		end
	end

	local function update(lobby: any?)
		local pass = if lobby then lobby.colorPass else nil
		passId = if pass then pass.id else nil
		owned = pass ~= nil and pass.owned == true
		local color = if lobby then lobby.color else nil
		saved = if type(color) == "string" and table.find(Candidates.colors, color) ~= nil then color else nil
		button.Visible = pass ~= nil
		if pass == nil and sheet:isOpen() then
			sheet:close()
		end
		render()
	end
	render()

	if p.Parent then
		Kit.outer(button).Parent = p.Parent
	end
	return {
		button = button,
		sheet = sheet,
		update = update,
		open = function()
			sheet:open()
		end,
	}
end

return ColorPick
