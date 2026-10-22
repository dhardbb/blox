--!strict
-- A thin helper for building UI in code: one `new` that sets properties and
-- parents children, plus the handful of components every screen uses. Sizes are
-- scale-based; buttons never go under 44 px tall (PLAN.md touch targets).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)

local Kit = {}

Kit.MIN_TOUCH = 44 -- px

Kit.font = {
	body = Enum.Font.Gotham,
	bold = Enum.Font.GothamBold,
	medium = Enum.Font.GothamMedium,
	mono = Enum.Font.Code,
}

Kit.size = {
	small = 14,
	body = 16,
	large = 20,
	title = 28,
	huge = 40,
}

function Kit.color(rgb: Colors.RGB): Color3
	return Color3.fromRGB(rgb.r, rgb.g, rgb.b)
end

Kit.colors = {
	background = Kit.color(Colors.background),
	surface = Kit.color(Colors.surface),
	raised = Kit.color(Colors.raised),
	raisedHover = Kit.color(Colors.raisedHover),
	line = Kit.color(Colors.line),
	text = Kit.color(Colors.text),
	muted = Kit.color(Colors.muted),
	accent = Kit.color(Colors.accent),
	danger = Kit.color(Colors.danger),
	good = Kit.color(Colors.good),
}

-- Creates an instance, sets `props` (Parent last), and parents `children`.
function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Kit.corner(radius: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 8) })
end

function Kit.round(): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

function Kit.pad(px: number): UIPadding
	return Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

function Kit.stroke(color: Color3, thickness: number?): UIStroke
	return Kit.new("UIStroke", { Color = color, Thickness = thickness or 1 })
end

-- A list layout. `direction` is "Vertical" (default) or "Horizontal".
function Kit.list(direction: string?, gap: number?, align: string?): UIListLayout
	local horizontal = direction == "Horizontal"
	local layout = Kit.new("UIListLayout", {
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap or 8),
	})
	if align == "Center" then
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	return layout
end

-- A panel: a rounded surface with padding.
function Kit.panel(props: { [string]: any }?, children: { Instance }?): Frame
	local base: { [string]: any } = {
		BackgroundColor3 = Kit.colors.surface,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}
	if props then
		for key, value in props do
			base[key] = value
		end
	end
	local frame = Kit.new("Frame", base, children)
	Kit.corner(10).Parent = frame
	Kit.pad(10).Parent = frame
	return frame
end

-- A transparent container.
function Kit.box(props: { [string]: any }?, children: { Instance }?): Frame
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}
	if props then
		for key, value in props do
			base[key] = value
		end
	end
	return Kit.new("Frame", base, children)
end

-- A text label. Wraps by default; pass `TextScaled = true` for short labels that
-- should shrink to fit their box.
function Kit.text(text: string, props: { [string]: any }?): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, Kit.size.body + 6),
		Font = Kit.font.body,
		TextSize = Kit.size.body,
		TextColor3 = Kit.colors.text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Text = text,
	}
	if props then
		for key, value in props do
			base[key] = value
		end
	end
	local label = Kit.new("TextLabel", base)
	if base.TextScaled then
		Kit.new("UITextSizeConstraint", { MaxTextSize = base.TextSize, MinTextSize = 9, Parent = label })
	end
	return label
end

-- A button with a label that shrinks to fit, at least MIN_TOUCH px tall.
function Kit.button(text: string, onActivate: () -> (), props: { [string]: any }?): TextButton
	local base: { [string]: any } = {
		BackgroundColor3 = Kit.colors.raised,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Font = Kit.font.medium,
		TextSize = Kit.size.body,
		TextColor3 = Kit.colors.text,
		TextScaled = true,
		Text = text,
		Name = text,
	}
	if props then
		for key, value in props do
			base[key] = value
		end
	end
	local button = Kit.new("TextButton", base)
	Kit.corner(8).Parent = button
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = button,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = base.TextSize, MinTextSize = 10, Parent = button })
	Kit.new("UISizeConstraint", { MinSize = Vector2.new(Kit.MIN_TOUCH, Kit.MIN_TOUCH), Parent = button })
	button.Activated:Connect(onActivate)
	return button
end

-- Sets a button's enabled look and whether it responds.
function Kit.setEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency = if enabled then 0 else 0.55
	button.BackgroundTransparency = if enabled then 0 else 0.4
end

-- Seconds left as "0:34".
function Kit.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return Kit
