--!strict
-- A thin helper for building UI in code: one `new` that sets properties and
-- parents children, plus the design-system tokens and the components every
-- screen uses (docs/DESIGN.md D-030). Buttons never go under 44 px.
--
-- Tokens
--   Kit.size     caption 13 · body 16 · heading 20 · title 28 · hero 48. Nothing
--                else: screens never write a TextSize literal (tests/ui/Tokens.spec).
--   Kit.space    xs 4 · sm 8 · md 12 · lg 16 · xl 24 (px)
--   Kit.radius   control 8 · panel 12 · pill 999 (Kit.round() stays for circles)
--   Kit.MIN_TOUCH 44, Kit.PRIMARY_H 56, Kit.BAR_H 84, Kit.HEADER_H 44,
--   Kit.MIN_TEXT 12 (floor of every UITextSizeConstraint), Kit.MAP_NODE_MIN 36,
--   Kit.TIMER_WARN 10 (seconds; timers turn danger below it).
--   Kit.colors   every Colors token as a Color3 (background, surface, raised,
--                raisedHover, line, text, muted, neutral, undecided, accent,
--                danger, good, onAccent, field, warn, disabledText).
--
-- Components
--   Kit.new(className, props?, children?) -> Instance
--   Kit.corner(radius?) · Kit.round() · Kit.pad(px) · Kit.stroke(color, thickness?)
--   Kit.list(direction?, gap?, align?) -> UIListLayout
--   Kit.panel(props?, children?) -> Frame        surface, padding md, corner panel
--   Kit.box(props?, children?) -> Frame          transparent container
--   Kit.text(text, props?) -> TextLabel          body size, wraps
--   Kit.caption(text, props?) -> TextLabel       caption size, muted, wraps, grows in Y
--   Kit.heading(text, props?) -> TextLabel       heading size, bold
--   Kit.stat(parent, label, value, name?) -> (Frame, TextLabel)
--                caption label over a body value; returns the cell and the value label
--   Kit.button(text, onActivate, props?) -> TextButton
--                props.variant: "primary" | "secondary" (default) | "danger" | "chip"
--   Kit.iconButton(glyph, onActivate, props?) -> TextButton   44x44 secondary
--   Kit.setEnabled(button, enabled)   variant-aware disabled look
--   Kit.setSelected(button, selected) chip: 2 px accent stroke + raisedHover
--   Kit.playerColor(view, p) -> Color3
--   Kit.clock(seconds) -> "0:34"
--
-- Variants (one accent-filled button per screen: the primary action; selection
-- is an outline, never a fill):
--   primary    accent bg, onAccent bold text; full width x PRIMARY_H by default.
--              Disabled: raised bg, muted text (looks like a disabled secondary).
--   secondary  raised bg, text. Disabled: surface bg, muted text.
--   danger     surface bg, danger text, 1 px danger stroke. Disabled: muted text, line stroke.
--   chip       raised bg, text. Selected: 2 px accent stroke and raisedHover bg.
--              Disabled: muted text.
--
-- Shared components (each module's header has the details):
--   ActionBar.new(parent, { primary, onPrimary, secondary?, onSecondary?,
--       primaryName?, secondaryName?, name? }) -> bar
--     bar:setPrimary(text, enabled) · bar:setSecondary(text?, enabled)
--     bar:setStatus(text, "muted" | "ok" | "warn" | "bad") · bar:setOpponent(text?)
--     bar.root (BAR_H, pinned to the bottom) · bar.primary (attribute PrimaryAction)
--     bar.secondary · bar.status · bar.opponent
--   Header.new(parent, { title, subtitle?, name? }) -> header
--     header:setTitle(text) · header:setSubtitle(text?)
--     header:setTimer(secondsLeft?, warnBelow?) · header:setTimerLabel(label?)
--     header.root (HEADER_H) · header.title · header.subtitle · header.timer
--   Toast.mount(parent, store) -> { root, frame, label, destroy }   (App.client only)
--   Collapsible.new(parent, { title, expanded?, name?, order?, onToggle? }) -> card
--     card:setTitle(text) · card:setExpanded(expanded) · card:isExpanded()
--     card.root · card.toggle (44 px title row) · card.body
--   Screen roots: set attribute PrimaryOptional = true on the screen's holder
--   frame for a moment with nothing to press (UI/Audit rule "primary").
--
-- Style v2 (docs/UI-STYLE.md, the rulebook for every screen):
--   Kit.MAX_TEXT_SIZES 4 (distinct sizes on one screen), Kit.MAX_LABEL_WORDS 8
--   (a button label), Kit.MAX_TEXT_WORDS 30 (one text outside a details area),
--   Kit.PILL_H 24, Kit.NOW_H 32 (the "what to do now" line), Kit.SHEET_MAX_W 560,
--   Kit.SCRIM_TRANSPARENCY 0.35, Kit.motion { fast 0.12, base 0.2, slow 0.35 } s.
--   Kit.colors.bad (= danger) and Kit.colors.warn (orange, text only).
--   Kit.glyph       the glyphs known to render in Gotham (no ▾ ▴, no emoji)
--   Kit.tone(name) -> Color3   "text" | "muted" | "accent" | "good" | "bad" | "warn"
--   Kit.title(text, props?) -> TextLabel          title size, bold
--   Kit.stack(props?, direction?, gap?) -> Frame  transparent, list layout, grows in Y
--   Kit.card(props?, children?) -> Frame          surface, panel corner, padding md,
--                                                 vertical list (gap sm), grows in Y
--   Kit.cardButton(onActivate, props?) -> TextButton  a tappable card (chip look:
--                                                 Kit.setSelected outlines it)
--   Kit.chip(text, onActivate, props?) -> TextButton  Kit.button variant "chip"
--   Kit.pill(text, tone?, props?) -> TextLabel    a 24 px read-only tag
--   Kit.divider(props?) -> Frame                  a 1 px line
--   Kit.details(container) -> container           marks a details area (a sheet or
--                                                 an expander body): long text OK
--   Kit.dataColor(inst) -> inst                   marks a data-colored element (map
--                                                 fills, feed tints): any color OK
--   Kit.words(text) -> number
--   Kit.tween(inst, goals, duration?)             TweenService (Quad Out), or set
--                                                 at once where there is none
--   Variant "ghost": no fill, text color, for tertiary actions ("More", "Back").
--   New modules: UI/Sheet (bottom sheet on phones, centered panel on wide screens),
--   UI/CoachTip (first-match tips, shown once), Header option `now` (the "what to do
--   now" line) and a timer bar (setTimer's third argument).
--
-- A button made without `props.variant` keeps the v0.3 behavior: setEnabled
-- only fades it (transparency) and never touches its colors, because legacy
-- screens color such buttons themselves. Screens move to explicit variants in
-- the UI overhaul packages; the legacy path goes when the last caller does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)

local Kit = {}

export type Variant = "primary" | "secondary" | "danger" | "chip" | "ghost"
export type Tone = "text" | "muted" | "accent" | "good" | "bad" | "warn"

Kit.MIN_TOUCH = 44 -- px, smallest button in either direction (PLAN.md touch targets)
Kit.PRIMARY_H = 56 -- px, the one pinned primary button
Kit.BAR_H = 84 -- px, action bar: 20 status + 4 gap + 56 buttons + 4
Kit.HEADER_H = 44 -- px, the standard one-row header
Kit.MIN_TEXT = 12 -- px, floor for every UITextSizeConstraint
Kit.MAP_NODE_MIN = 36 -- px, smallest map tap target
Kit.TIMER_WARN = 10 -- s, timers turn danger below this
Kit.MAX_TEXT_SIZES = 4 -- distinct text sizes one screen may show (UI audit textSizes)
Kit.MAX_LABEL_WORDS = 8 -- words on one button label (UI audit labelWords)
Kit.MAX_TEXT_WORDS = 30 -- words in one text outside a details area (UI audit wallOfText)
Kit.PILL_H = 24 -- px, a read-only tag
Kit.NOW_H = 32 -- px, the header's "what to do now" line
Kit.SHEET_MAX_W = 560 -- px, widest a sheet gets on a wide screen
Kit.SCRIM_TRANSPARENCY = 0.35 -- the dimmed layer behind a sheet

-- Durations in seconds; every tween is one of these (docs/UI-STYLE.md, Motion).
Kit.motion = {
	fast = 0.12, -- press feedback, chip selection
	base = 0.2, -- panels and sheets opening, a value changing
	slow = 0.35, -- a reveal step, a big number counting
}

-- Glyphs that render in Roblox's Gotham (▾ and ▴ do not; no emoji anywhere).
Kit.glyph = {
	dot = "·",
	bullet = "•",
	close = "×",
	plus = "+",
	minus = "−",
	up = "▲",
	down = "▼",
	arrow = "→",
	more = "…",
	check = "✓",
	flight = "✈",
}

Kit.font = {
	body = Enum.Font.Gotham,
	bold = Enum.Font.GothamBold,
	medium = Enum.Font.GothamMedium,
	mono = Enum.Font.Code,
}

-- The type scale: the only text sizes a screen may use.
Kit.size = {
	caption = 13, -- stat lines, tags, hints, legend, feed rows
	body = 16, -- buttons, sentences, list rows
	heading = 20, -- panel titles, state name, timer
	title = 28, -- screen titles, EV counters
	hero = 48, -- "270" on the Lobby, "You won", the private match code
}

Kit.space = {
	xs = 4, -- rows inside a panel
	sm = 8, -- between the big blocks of a screen, list gaps
	md = 12, -- panel padding
	lg = 16,
	xl = 24,
}

Kit.radius = {
	control = 8, -- buttons, chips, fields
	panel = 12, -- panels, cards, toasts
	pill = 999, -- tags
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
	neutral = Kit.color(Colors.neutral),
	undecided = Kit.color(Colors.undecided),
	accent = Kit.color(Colors.accent),
	danger = Kit.color(Colors.danger),
	good = Kit.color(Colors.good),
	onAccent = Kit.color(Colors.onAccent),
	field = Kit.color(Colors.field),
	warn = Kit.color(Colors.warn),
	disabledText = Kit.color(Colors.disabledText),
}
Kit.colors.bad = Kit.colors.danger -- the semantic name for a loss or an error

-- The text color for a semantic tone.
function Kit.tone(name: Tone): Color3
	return (Kit.colors :: any)[name] or Kit.colors.text
end

-- A player's color by index in the View (neutral before Select ends).
function Kit.playerColor(view: any, p: number): Color3
	local player = view.players[p]
	return Kit.color(Colors.of(if player then player.color else nil))
end

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
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or Kit.radius.control) })
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
		Padding = UDim.new(0, gap or Kit.space.sm),
	})
	if align == "Center" then
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	return layout
end

local function merged(base: { [string]: any }, props: { [string]: any }?): { [string]: any }
	if props then
		for key, value in props do
			base[key] = value
		end
	end
	return base
end

-- A panel: a rounded surface with padding.
function Kit.panel(props: { [string]: any }?, children: { Instance }?): Frame
	local base = merged({
		BackgroundColor3 = Kit.colors.surface,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, props)
	local frame = Kit.new("Frame", base, children)
	Kit.corner(Kit.radius.panel).Parent = frame
	Kit.pad(Kit.space.md).Parent = frame
	return frame
end

-- A transparent container.
function Kit.box(props: { [string]: any }?, children: { Instance }?): Frame
	local base = merged({
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, props)
	return Kit.new("Frame", base, children)
end

-- A text label. Wraps by default; pass `TextScaled = true` for short labels that
-- should shrink to fit their box (never below MIN_TEXT).
function Kit.text(text: string, props: { [string]: any }?): TextLabel
	local base = merged({
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
	}, props)
	local label = Kit.new("TextLabel", base)
	if base.TextScaled then
		Kit.new("UITextSizeConstraint", {
			MaxTextSize = math.max(base.TextSize, Kit.MIN_TEXT),
			MinTextSize = Kit.MIN_TEXT,
			Parent = label,
		})
	end
	return label
end

-- A wrapped caption-size line (muted unless props say otherwise) that grows to
-- fit its text.
function Kit.caption(text: string, props: { [string]: any }?): TextLabel
	return Kit.text(
		text,
		merged({
			Size = UDim2.new(1, 0, 0, Kit.size.caption + 4),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = Kit.size.caption,
			TextColor3 = Kit.colors.muted,
			TextYAlignment = Enum.TextYAlignment.Top,
		}, props)
	)
end

-- A bold heading-size line: panel titles, the state name.
function Kit.heading(text: string, props: { [string]: any }?): TextLabel
	return Kit.text(
		text,
		merged({
			Size = UDim2.new(1, 0, 0, Kit.size.heading + 8),
			Font = Kit.font.bold,
			TextSize = Kit.size.heading,
		}, props)
	)
end

-- A stat cell: a caption label over a body value (the state card's grid).
-- Returns the cell and the value label, which the caller updates.
function Kit.stat(parent: Instance, label: string, value: string, name: string?): (Frame, TextLabel)
	local cell = Kit.box({
		Name = name or "Stat",
		Size = UDim2.new(1, 0, 0, Kit.size.caption + 4 + Kit.size.body + 6),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	Kit.list("Vertical", 0).Parent = cell
	Kit.caption(label, { Name = "Label", LayoutOrder = 1, Parent = cell })
	local valueLabel = Kit.text(value, {
		Name = "Value",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = cell,
	})
	cell.Parent = parent
	return cell, valueLabel
end

-- What each variant owns: its enabled and disabled colors.
type Look = {
	bg: Color3,
	text: Color3,
	disabledBg: Color3,
	disabledText: Color3,
	stroke: Color3?,
	disabledStroke: Color3?,
}

local PRIMARY: Look = {
	bg = Kit.colors.accent,
	text = Kit.colors.onAccent,
	disabledBg = Kit.colors.raised,
	disabledText = Kit.colors.disabledText,
}
local SECONDARY: Look = {
	bg = Kit.colors.raised,
	text = Kit.colors.text,
	disabledBg = Kit.colors.surface,
	disabledText = Kit.colors.disabledText,
}
local DANGER: Look = {
	bg = Kit.colors.surface,
	text = Kit.colors.danger,
	disabledBg = Kit.colors.surface,
	disabledText = Kit.colors.disabledText,
	stroke = Kit.colors.danger,
	disabledStroke = Kit.colors.line,
}
local CHIP: Look = {
	bg = Kit.colors.raised,
	text = Kit.colors.text,
	disabledBg = Kit.colors.raised,
	disabledText = Kit.colors.disabledText,
}

local GHOST: Look = {
	bg = Kit.colors.raised, -- only shows on press (the button has no fill)
	text = Kit.colors.text,
	disabledBg = Kit.colors.raised,
	disabledText = Kit.colors.disabledText,
}

local LOOKS: { [string]: Look } = {
	primary = PRIMARY,
	secondary = SECONDARY,
	danger = DANGER,
	chip = CHIP,
	ghost = GHOST,
}

-- Every variant by name, so a string from props or an attribute becomes a Variant.
local VARIANTS: { [string]: Variant } = {
	primary = "primary",
	secondary = "secondary",
	danger = "danger",
	chip = "chip",
	ghost = "ghost",
}

local function variantOf(button: Instance): Variant?
	local value = button:GetAttribute("Variant")
	return if type(value) == "string" then VARIANTS[value] else nil
end

local function strokeOf(button: Instance): UIStroke?
	local stroke = button:FindFirstChild("VariantStroke")
	return if stroke then stroke :: UIStroke else nil
end

-- A button with a label that shrinks to fit, at least MIN_TOUCH px both ways.
-- `props.variant` picks the look (see the header); other props are set on the
-- TextButton as usual and win over the variant's defaults.
function Kit.button(text: string, onActivate: () -> (), props: { [string]: any }?): TextButton
	local variant: Variant? = nil
	local rest: { [string]: any } = {}
	if props then
		for key, value in props do
			if key == "variant" then
				variant = if type(value) == "string" then VARIANTS[value] else nil
			else
				rest[key] = value
			end
		end
	end
	local look = if variant then LOOKS[variant] else SECONDARY
	local base = merged({
		BackgroundColor3 = look.bg,
		BackgroundTransparency = if variant == "ghost" then 1 else 0,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, if variant == "primary" then Kit.PRIMARY_H else Kit.MIN_TOUCH),
		Font = if variant == "primary" then Kit.font.bold else Kit.font.medium,
		TextSize = Kit.size.body,
		TextColor3 = look.text,
		TextScaled = true,
		Text = text,
		Name = text,
	}, rest)
	local button = Kit.new("TextButton", base)
	if variant then
		button:SetAttribute("Variant", variant)
	end
	Kit.corner(Kit.radius.control).Parent = button
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, Kit.space.sm),
		PaddingRight = UDim.new(0, Kit.space.sm),
		PaddingTop = UDim.new(0, Kit.space.xs),
		PaddingBottom = UDim.new(0, Kit.space.xs),
		Parent = button,
	})
	Kit.new("UITextSizeConstraint", {
		MaxTextSize = math.max(base.TextSize, Kit.MIN_TEXT),
		MinTextSize = Kit.MIN_TEXT,
		Parent = button,
	})
	Kit.new("UISizeConstraint", { MinSize = Vector2.new(Kit.MIN_TOUCH, Kit.MIN_TOUCH), Parent = button })
	if variant == "danger" or variant == "chip" then
		Kit.new("UIStroke", {
			Name = "VariantStroke",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = if variant == "chip" then Kit.colors.accent else look.stroke,
			Thickness = if variant == "chip" then 2 else 1,
			Enabled = variant == "danger",
			Parent = button,
		})
	end
	button.Activated:Connect(onActivate)
	return button
end

-- A 44x44 secondary button for a glyph: "×", "+", "−".
function Kit.iconButton(glyph: string, onActivate: () -> (), props: { [string]: any }?): TextButton
	return Kit.button(
		glyph,
		onActivate,
		merged({
			variant = "secondary",
			Size = UDim2.fromOffset(Kit.MIN_TOUCH, Kit.MIN_TOUCH),
			Font = Kit.font.bold,
		}, props)
	)
end

-- Sets a button's enabled look and whether it responds. Touches only what the
-- button's variant owns, so a disabled primary looks like a disabled secondary
-- (never faded gold). Buttons made without a variant only fade (legacy look).
function Kit.setEnabled(button: TextButton, enabled: boolean)
	button.Active = enabled
	button.AutoButtonColor = enabled
	local variant = variantOf(button)
	if variant == nil then
		button.TextTransparency = if enabled then 0 else 0.55
		button.BackgroundTransparency = if enabled then 0 else 0.4
		return
	end
	local look = LOOKS[variant]
	button.TextColor3 = if enabled then look.text else look.disabledText
	if variant == "chip" then
		-- A chip's background shows selection; enabling never clears it.
		local selected = button:GetAttribute("Selected") == true
		button.BackgroundColor3 = if selected then Kit.colors.raisedHover else look.bg
	else
		button.BackgroundColor3 = if enabled then look.bg else look.disabledBg
	end
	local stroke = strokeOf(button)
	if stroke and variant == "danger" then
		stroke.Color = if enabled then look.stroke :: Color3 else look.disabledStroke :: Color3
	end
end

-- Shows a chip as selected (2 px accent stroke, raisedHover bg) or not. Other
-- variants only record the Selected attribute.
function Kit.setSelected(button: TextButton, selected: boolean)
	button:SetAttribute("Selected", selected)
	if variantOf(button) ~= "chip" then
		return
	end
	button.BackgroundColor3 = if selected then Kit.colors.raisedHover else CHIP.bg
	local stroke = strokeOf(button)
	if stroke then
		stroke.Enabled = selected
	end
end

-- ---------------------------------------------------------------- style v2

-- A bold title-size line: a screen's one big heading.
function Kit.title(text: string, props: { [string]: any }?): TextLabel
	return Kit.text(
		text,
		merged({
			Size = UDim2.new(1, 0, 0, Kit.size.title + 8),
			Font = Kit.font.bold,
			TextSize = Kit.size.title,
		}, props)
	)
end

-- A transparent frame whose children stack in a list ("Vertical" by default,
-- gap sm) and that grows in Y with them. Full width unless props say otherwise.
function Kit.stack(props: { [string]: any }?, direction: string?, gap: number?): Frame
	local frame = Kit.box(merged({
		Name = "Stack",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, props))
	Kit.list(direction, gap or Kit.space.sm).Parent = frame
	return frame
end

-- A card: the one container style for grouped content. Surface fill, panel
-- corner, padding md, a vertical list (gap sm); grows in Y with its content.
function Kit.card(props: { [string]: any }?, children: { Instance }?): Frame
	local frame = Kit.panel(merged({
		Name = "Card",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, props))
	Kit.list("Vertical", Kit.space.sm).Parent = frame
	if children then
		for _, child in children do
			child.Parent = frame
		end
	end
	return frame
end

-- A tappable card (a candidate, a stance, a topic): the chip look (raised,
-- selected = accent outline via Kit.setSelected), padding md, a vertical list
-- (gap xs) for the caller's labels, grows in Y. Put Kit.text/caption inside.
function Kit.cardButton(onActivate: () -> (), props: { [string]: any }?): TextButton
	local button = Kit.button(
		"",
		onActivate,
		merged({
			variant = "chip",
			Name = "CardButton",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextScaled = false,
		}, props)
	)
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0, Kit.radius.panel)
	end
	local pad = button:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingTop = UDim.new(0, Kit.space.md)
		pad.PaddingBottom = UDim.new(0, Kit.space.md)
		pad.PaddingLeft = UDim.new(0, Kit.space.md)
		pad.PaddingRight = UDim.new(0, Kit.space.md)
	end
	Kit.list("Vertical", Kit.space.xs).Parent = button
	return button
end

-- A toggle chip: Kit.button with variant "chip" (Kit.setSelected shows it picked).
function Kit.chip(text: string, onActivate: () -> (), props: { [string]: any }?): TextButton
	return Kit.button(text, onActivate, merged({ variant = "chip" }, props))
end

-- A read-only tag, Kit.PILL_H tall and as wide as its text: "Your platform",
-- "Battleground", "Locked in". The tone colors the text; the fill stays raised.
function Kit.pill(text: string, tone: Tone?, props: { [string]: any }?): TextLabel
	local label = Kit.text(
		text,
		merged({
			Name = "Pill",
			Size = UDim2.fromOffset(0, Kit.PILL_H),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 0,
			BackgroundColor3 = Kit.colors.raised,
			Font = Kit.font.medium,
			TextSize = Kit.size.caption,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Kit.tone(tone or "text"),
		}, props)
	)
	Kit.corner(Kit.PILL_H // 2).Parent = label
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, Kit.space.sm),
		PaddingRight = UDim.new(0, Kit.space.sm),
		Parent = label,
	})
	return label
end

-- A 1 px divider line, full width.
function Kit.divider(props: { [string]: any }?): Frame
	return Kit.new(
		"Frame",
		merged({
			Name = "Divider",
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Kit.colors.line,
			BorderSizePixel = 0,
		}, props)
	)
end

-- Marks `container` as a details area (a sheet body, an expander body): texts
-- inside may run past Kit.MAX_TEXT_WORDS, because the player asked to see them.
function Kit.details<T>(container: T): T
	(container :: any):SetAttribute("Details", true)
	return container
end

-- Marks `inst` (and what is inside it) as data-colored: map fills, player-tinted
-- feed rows, EV bars. The UI audit's tokenColor rule skips it.
function Kit.dataColor<T>(inst: T): T
	(inst :: any):SetAttribute("DataColor", true)
	return inst
end

-- Words in a text (runs of non-space characters).
function Kit.words(text: string): number
	local n = 0
	for _ in string.gmatch(text, "%S+") do
		n += 1
	end
	return n
end

local tweenService: any = nil
do
	local ok, service = pcall(function()
		return game:GetService("TweenService")
	end)
	tweenService = if ok then service else nil
end

-- Tweens `inst` to `goals` over `duration` (default Kit.motion.base), Quad Out.
-- Without a TweenService (the headless test engine) the goals apply at once.
function Kit.tween(inst: Instance, goals: { [string]: any }, duration: number?)
	if tweenService == nil then
		for key, value in goals do
			(inst :: any)[key] = value
		end
		return
	end
	local info = TweenInfo.new(duration or Kit.motion.base, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tweenService:Create(inst, info, goals):Play()
end

-- Seconds left as "0:34".
function Kit.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return Kit
