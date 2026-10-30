--!strict
-- A thin helper for building UI in code: one `new` that sets properties and
-- parents children, plus the design-system tokens and the components every
-- screen uses (docs/DESIGN.md D-030). Buttons never go under 44 px.
--
-- Tokens
--   Kit.size     caption 14 · body 16 · heading 20 · title 28 · hero 48. Nothing
--                else: screens never write a TextSize literal (tests/ui/Tokens.spec).
--   Kit.space    xs 4 · sm 8 · md 12 · lg 16 · xl 24 (px)
--   Kit.radius   control 8 · panel 12 · pill 999 (Kit.round() stays for circles)
--   Kit.MIN_TOUCH 44, Kit.PRIMARY_H 56, Kit.BAR_H 84, Kit.HEADER_H 44,
--   Kit.MIN_TEXT 12 (floor of every UITextSizeConstraint), Kit.MAP_NODE_MIN 36,
--   Kit.TIMER_WARN 10 (seconds; timers turn loss orange below it), Kit.TIMER_CRITICAL 5
--   (a pop and a tick each second below it; the time bar turns orange).
--   Kit.colors   every Colors token as a Color3 (background, surface, raised,
--                raisedHover, line, text, muted, neutral, undecided, accent,
--                danger, good, onAccent, field, warn, disabledText, surfaceTop,
--                raisedTop, accentEdge).
--   Kit.font     body · medium · bold (Builder Sans, Gotham fallback) · display (Permanent Marker) · hand (Patrick Hand)
--                (Fredoka One: hero, title numbers, the primary's label) · mono
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
--     bar:setProgress(fraction?) · bar:lockFlash(pitch?)
--     bar.root (BAR_H, pinned to the bottom) · bar.primary (attribute PrimaryAction)
--     bar.secondary · bar.status · bar.opponent
--   Header.new(parent, { title, subtitle?, name? }) -> header
--     header:setTitle(text) · header:setSubtitle(text?)
--     header:setTimer(secondsLeft?, warnBelow?) · header:setTimerLabel(label?)
--     header.root (HEADER_H) · header.title · header.subtitle · header.timer · header.sound
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
--   Kit.colors.bad (= danger = warn = loss: one orange, D-056).
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
--   Kit.tween(inst, goals, duration?)             Motion.tween (Quad Out): instant
--                                                 under reduced motion or headless
--   Variant "ghost": no fill, text color, for tertiary actions ("More", "Back").
--   New modules: UI/Sheet (bottom sheet on phones, centered panel on wide screens),
--   UI/CoachTip (first-match tips, shown once), Header option `now` (the "what to do
--   now" line) and a timer bar (setTimer's third argument).
--
-- Polish (docs/DESIGN.md D-053; UI/Motion, UI/Audio, UI/Icons):
--   Every Kit.button shrinks while held (Motion.press) and plays a cue when
--   activated: "tap", or "select" for a chip. Primary, secondary and chip
--   buttons get a top-light UIGradient "Depth"; primary a 2 px accentEdge
--   UIStroke "Edge", secondary a 1 px line hairline "Edge" (0.5 transparent).
--   Kit.card gets the surfaceTop -> surface gradient and the hairline.
--   Kit.depth(inst, top, base)  fill `top` fading to `base` at the bottom
--   Kit.icon(name, size?, color?) -> ImageLabel | TextLabel   (UI/Icons)
--   Kit.actionIcon(kind) -> string?   the icon name for a plan action kind
--
-- Issue symbols (docs/DESIGN.md D-076; UI/IssueIcons):
--   Kit.issueIcon(issue, size?, color?) -> ImageLabel | TextLabel   the symbol
--     alone ("IssueIcon"); its short code as text until the image is uploaded
--   Kit.issueTag(issue, props?) -> Frame   symbol + full name (the name alone before)
--   Kit.issueLead(label, issue?, size?) -> GuiObject?   the symbol in front of a
--     label's or button's text, hiding while the box is too narrow for both;
--     again to swap, nil to remove. Kit.refitIssueLeads(root) re-checks the room
--   Kit.setIssueIcon(plate, issue?, size, color) -> GuiObject?   a map lens plate's symbol
--   Kit.issueName(issue), Kit.issueCode(issue), Kit.hasIssueIcon(issue)
--   Kit.ISSUE_ICON 20 (default size), Kit.MIN_ICON 14 (audit rule iconFloor)
--
-- Front-page foundation (docs/DESIGN.md D-056; docs/UI-STYLE.md §2):
--   Navy neutrals; orange `loss` (= warn = danger = bad) is the only "against
--   you" color; red is a player color and never means bad.
--   Kit.radius   + button 12 (primary, secondary) · sheet 16 (sheets, help)
--   Kit.size     + wordmark 72 (the Lobby's "LANDSLIDE" only; texts carry attribute Wordmark)
--   Kit.colors   + loss, lossEdge, onLoss, goodEdge, accentLip, raisedLip, glow
--   Kit.tone     + "loss" (preferred over "bad"/"warn") · "white" (text; the battleground pill)
--   Kit.playerText(view, p) -> Color3   a player color readable as text (Colors.textOn)
--   Kit.textColor(color) -> Color3      the same for any Color3
--   Chunky buttons: primary and secondary are a face (the TextButton returned,
--     with the Name, attributes and Activated) inside a transparent holder Frame
--     "<Name>Holder" (= button.Parent) that also holds the "Lip" under the face
--     (primary 4 px accentLip, secondary 3 px raisedLip; pressing moves the face
--     down onto it). The holder takes the caller's Parent, Size, Position,
--     AnchorPoint, LayoutOrder, Visible and ZIndex. Later changes to the face's
--     Size, Visible and LayoutOrder are passed on to the holder automatically;
--     move or reparent it with Kit.outer(button).Position / .Parent. Pass
--     props.lip = false for a secondary without a lip (and without a holder).
--     Primary label: Fredoka One at heading (20). Corners: Kit.radius.button.
--   Kit.outer(button) -> GuiObject       the holder of a lipped button, else the button
--   Kit.bevel(inst, base, thickness?, alpha?) -> UIStroke   the "Edge": a border
--     in `base` lit from the top (a UIGradient "EdgeLight" fades it from `text`),
--     the top highlight of every card, button and sheet
--   Kit.eyebrow(text, props?) -> TextLabel   caption, muted, upper case, medium
--   Kit.shadow(inst, opts?) -> ImageLabel?   a soft 9-slice shadow behind `inst`
--     (a sibling, ZIndex one under it, following its size, place and Visible);
--     opts { dy 4, spread 12, transparency 0.45 }. Nil when `inst` has no parent
--     or its parent lays children out (a list or grid would move the shadow):
--     cards in lists get their depth from the bevel instead
--   Kit.glow(parent, color, opts?) -> ImageLabel?   a radial glow centered in
--     `parent`, under its other children (ZIndex 0); opts { scale 1, px?,
--     transparency 0.6, stretch? }. Nil in a parent with a list or grid layout
--   Kit.stamp(text, color, props?) -> Frame "Stamp"   a tilted plate (−6°) with a
--     Fredoka label (props.size: a Kit.size token, default title) and a glow;
--     attribute Overhang; props.fit = px keeps it inside its parent (long
--     names: it narrows and its label scales). Animate it with Motion.stamp
--   Kit.monogram(name, color, px) -> Frame "Monogram"   a candidate's initials in
--     a lit circle of `color` (dataColor); the label is "Initials"
--   Kit.portrait(id, name, px, opts?) -> Frame "Portrait"   a candidate's illustrated
--     bust on a round neutral plate (D-068); opts { ring = player color?, fade? };
--     the initials of `name` while the asset id is 0. Kit.paintPortrait(root, opts)
--     repaints the ring and fade; Kit.portraitImage(id) -> "rbxassetid://…" or ""
--   Kit.raceBar(parent, opts) -> RaceBar   the two-sided vote bar with the 270 tick
--   Kit.wordmark(px?, props?, opts?) -> Frame "Wordmark"   the "LANDSLIDE" lockup: glow,
--     lip, outline, and the "RACE TO 270" ribbon (opts.tagline = false: none);
--     Kit.wordmarkHeight(px?, tagline?) is its height (D-064)
--   Kit.iconPlate(name, px?) -> Frame "IconPlate"   an icon in a field circle
--   Kit.pill(text, tone, { filled = true, fill = Color3? })   a filled tag: tone
--     (or `fill`, a data color) fill, readable text, a 1 px edge. Tone "white"
--     (D-058): the battleground mark, an outlined tag (field fill, Kit.MARK_STROKE
--     `text` stroke, white bold text after Kit.STAR); never a white fill, which
--     is the primary button's
--   Every ImageLabel from shadow and glow carries Decor = true (the audit skips
--   it) and Asset = "shadow" | "glow" (the snapshot renderer draws a stand-in).
--
-- A button made without `props.variant` keeps the v0.3 behavior: setEnabled
-- only fades it (transparency) and never touches its colors, because legacy
-- screens color such buttons themselves. Screens move to explicit variants in
-- the UI overhaul packages; the legacy path goes when the last caller does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(script.Parent.Assets)
local Audio = require(script.Parent.Audio)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local SetupWords = require(ReplicatedStorage.Shared.UI.Words.Setup)
local Icons = require(script.Parent.Icons)
local IssueIcons = require(script.Parent.IssueIcons)
local Issues = require(ReplicatedStorage.Shared.Sim.Issues)
local Board = require(script.Parent.Board)
local Motion = require(script.Parent.Motion)

local Kit = {}

export type Variant = "primary" | "secondary" | "danger" | "chip" | "ghost"
export type Tone = "text" | "muted" | "accent" | "good" | "bad" | "warn" | "loss" | "white"

Kit.MIN_TOUCH = 44 -- px, smallest button in either direction (PLAN.md touch targets)
Kit.PRIMARY_H = 56 -- px, the one pinned primary button
Kit.BAR_H = 84 -- px, action bar: 20 status + 4 gap + 56 buttons + 4
Kit.HEADER_H = 44 -- px, the standard one-row header
Kit.MIN_TEXT = 12 -- px, floor for every UITextSizeConstraint
Kit.MAP_NODE_MIN = 36 -- px, smallest map tap target
Kit.TIMER_WARN = 10 -- s, timers turn warn below this
Kit.TIMER_CRITICAL = 5 -- s, timers turn danger and tick below this
Kit.MAX_TEXT_SIZES = 4 -- distinct text sizes one screen may show (UI audit textSizes)
Kit.MAX_LABEL_WORDS = 8 -- words on one button label (UI audit labelWords)
Kit.MAX_TEXT_WORDS = 30 -- words in one text outside a details area (UI audit wallOfText)
Kit.PILL_H = 24 -- px, a read-only tag
Kit.STAR = "★" -- the battleground mark's glyph (D-058): on the white pill and the map's vote tag
Kit.MARK_STROKE = 1.5 -- px, the outline of a battleground tag (thinner than the 2 px selection)
Kit.NOW_H = 32 -- px, the header's "what to do now" line
Kit.SHEET_MAX_W = 560 -- px, widest a sheet gets on a wide screen
Kit.COMPACT_H = 500 -- px of game-area height: a wider-than-tall screen shorter than this is a landscape phone (D-089)
Kit.SCRIM_TRANSPARENCY = 0.3 -- the dimmed layer behind a sheet
Kit.LIP_PRIMARY = 4 -- px, the primary's lip (the face travels this far when pressed)
Kit.LIP_SECONDARY = 3 -- px, a secondary's or an icon button's lip

-- The size class of a game area (D-089): "portrait" (taller than wide),
-- "compact" (a landscape phone: wider than tall and under COMPACT_H high, so
-- height is the constraint: map left, a compact side column right) or "wide"
-- (an iPad, a desktop window).
export type SizeClass = "portrait" | "compact" | "wide"
function Kit.sizeClass(size: Vector2): SizeClass
	if size.Y > size.X then
		return "portrait"
	end
	if size.Y < Kit.COMPACT_H then
		return "compact"
	end
	return "wide"
end

-- True on a landscape phone (Kit.sizeClass(size) == "compact").
function Kit.compact(size: Vector2): boolean
	return Kit.sizeClass(size) == "compact"
end

Kit.TABLET_MIN = 600 -- px (pt), a touch screen's shorter side from which it is a tablet (D-100; Android's sw600dp)

-- Whether a device is a tablet (D-100): a touch screen whose shorter side,
-- notches left out (Camera.ViewportSize), is at least TABLET_MIN. The shorter
-- side does not change when the device turns, so the answer is the same held
-- either way. The largest phones are about 440 pt across; the smallest iPad
-- (mini) is 744. Tablets play landscape, phones portrait.
function Kit.isTablet(touch: boolean, screen: Vector2): boolean
	return touch and math.min(screen.X, screen.Y) >= Kit.TABLET_MIN
end

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
	sound = "♪",
}

-- The first of `names` this engine knows (an unknown Enum item errors in Roblox).
local function firstFont(names: { string }): Enum.Font
	for _, name in names do
		local ok, font = pcall(function()
			return (Enum.Font :: any)[name]
		end)
		if ok and font ~= nil then
			return font
		end
	end
	return Enum.Font.Gotham
end

-- Builder Sans for everything a player reads; the board's handwriting (D-102)
-- only for headings, stamps, big numbers and state codes: Permanent Marker
-- (display) and Patrick Hand (hand). Each with a fallback.
Kit.font = {
	body = firstFont({ "BuilderSans", "Gotham" }),
	medium = firstFont({ "BuilderSansMedium", "GothamMedium" }),
	bold = firstFont({ "BuilderSansBold", "GothamBold" }),
	display = firstFont({ "PermanentMarker", "FredokaOne", "BuilderSansExtraBold", "GothamBlack" }),
	hand = firstFont({ "PatrickHand", "BuilderSansBold", "GothamBold" }),
	mono = Enum.Font.Code,
}

-- The type scale: the only text sizes a screen may use.
Kit.size = {
	caption = 14, -- stat lines, tags, hints, legend, feed rows
	body = 16, -- buttons, sentences, list rows
	heading = 20, -- panel titles, state name, timer
	title = 28, -- screen titles, EV counters
	hero = 48, -- "You won", the private match code
	wordmark = 72, -- the Lobby's "LANDSLIDE" only (Kit.wordmark; the audit allows it on a Wordmark text, scaled down to fit)
}

Kit.space = {
	xs = 4, -- rows inside a panel
	sm = 8, -- between the big blocks of a screen, list gaps
	md = 12, -- panel padding
	lg = 16,
	xl = 24,
}

Kit.radius = {
	control = 8, -- chips, fields, icon buttons
	button = 12, -- primary and secondary buttons
	panel = 12, -- panels, cards, toasts
	sheet = 16, -- sheets, the help overlay
	pill = 999, -- tags
}

function Kit.color(rgb: Colors.RGB): Color3
	return Color3.fromRGB(rgb.r, rgb.g, rgb.b)
end

-- A Color3 back as 0-255 RGB, for the Colors helpers (tint, onColor, textOn).
function Kit.rgb(color: Color3): Colors.RGB
	local function c(v: number): number
		return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
	end
	return { r = c(color.R), g = c(color.G), b = c(color.B) }
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
	surfaceTop = Kit.color(Colors.surfaceTop),
	raisedTop = Kit.color(Colors.raisedTop),
	accentEdge = Kit.color(Colors.accentEdge),
	accentLip = Kit.color(Colors.accentLip),
	raisedLip = Kit.color(Colors.raisedLip),
	loss = Kit.color(Colors.loss),
	lossEdge = Kit.color(Colors.lossEdge),
	onLoss = Kit.color(Colors.onLoss),
	goodEdge = Kit.color(Colors.goodEdge),
	glow = Kit.color(Colors.glow),
	keyGold = Kit.color(Colors.keyGold), -- a key state's highlighter band on the map and its swatch (D-101, D-102)
	sticky = Kit.color(Colors.sticky), -- a sticky note on the board: coach tips, the week's event (D-102)
	highlight = Kit.color(Colors.highlight), -- gold: the Daily Race, first medals, the 270 badge (D-102)
}
Kit.colors.bad = Kit.colors.loss -- the semantic name for a loss or an error (orange, never red)

-- The text color for a semantic tone ("white" is text: the white pill's fill).
function Kit.tone(name: Tone): Color3
	if name == "white" then
		return Kit.colors.text
	end
	return (Kit.colors :: any)[name] or Kit.colors.text
end

-- A player's color by index in the View (neutral before Select ends).
function Kit.playerColor(view: any, p: number): Color3
	local player = view.players[p]
	return Kit.color(Colors.of(if player then player.color else nil))
end

-- The readable variant of any color for text on a dark surface (Colors.textOn).
function Kit.textColor(color: Color3): Color3
	return Kit.color(Colors.textOn(Kit.rgb(color)))
end

-- A player's color as text: names, "Buster leads +3". Fills, dots and bars keep
-- Kit.playerColor (D-056).
function Kit.playerText(view: any, p: number): Color3
	local player = view.players[p]
	return Kit.color(Colors.textOn(Colors.of(if player then player.color else nil)))
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

local SECONDARY_EDGE = 2 -- px, a secondary button's black marker outline (D-102)
local HAIRLINE_TRANSPARENCY = 0.5 -- a card's or secondary button's 1 px line edge
local EDGE_LIGHT_ALPHA = 0.45 -- how bright the top of an edge gets (a share of `text`)
local EDGE_LIGHT_SPAN = 0.3 -- the top share of an edge that fades from the light into its base

-- A top-light gradient that keeps the fill's token: the top shows the fill as
-- set, the bottom BUTTON_SHADE of it. UIGradient multiplies its parent's colors
-- (text included, so the shade stays light), and setEnabled/setSelected keep
-- changing BackgroundColor3 under it.
local BUTTON_SHADE = 0.96 -- D-102: a magnet on the board is nearly flat (was 0.8 on the navy stage)

local function shade(inst: Instance)
	local k = BUTTON_SHADE
	Kit.new("UIGradient", {
		Name = "Depth",
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(k, k, k)),
		Parent = inst,
	})
end

local function ratio(b: number, t: number): number
	return if t > 0 then math.clamp(b / t, 0, 1) else 1
end

-- Fills `inst` with `top` and adds a vertical UIGradient "Depth" that brings it
-- down to `base` at the bottom (cards: surfaceTop -> surface; elevated panels
-- such as the election spotlight: raisedTop -> raised). Returns `inst`.
function Kit.depth<T>(inst: T, top: Color3, base: Color3): T
	local target = inst :: any
	target.BackgroundColor3 = top
	local old = target:FindFirstChild("Depth")
	if old then
		old:Destroy()
	end
	Kit.new("UIGradient", {
		Name = "Depth",
		Rotation = 90,
		Color = ColorSequence.new(
			Color3.new(1, 1, 1),
			Color3.new(ratio(base.R, top.R), ratio(base.G, top.G), ratio(base.B, top.B))
		),
		Parent = target,
	})
	return inst
end

-- Paints an edge stroke: `base` at `alpha` (1 = opaque), lit from the top. The
-- stroke itself is `text`; its UIGradient "EdgeLight" multiplies it down to
-- `base` below the top EDGE_LIGHT_SPAN and carries the transparency. The
-- stroke's attributes Base and Alpha keep what was asked for.
local function paintEdge(stroke: UIStroke, base: Color3, thickness: number, alpha: number)
	-- D-102: marker on a board has no lit top: the "light" is the edge itself.
	local light = base
	stroke.Color = light
	stroke.Thickness = thickness
	stroke.Transparency = 0
	stroke:SetAttribute("Base", base)
	stroke:SetAttribute("Alpha", alpha)
	local gradient = stroke:FindFirstChild("EdgeLight") :: UIGradient?
	if gradient == nil then
		gradient = Kit.new("UIGradient", { Name = "EdgeLight", Rotation = 90, Parent = stroke })
	end
	local g = gradient :: UIGradient
	local k = Color3.new(ratio(base.R, light.R), ratio(base.G, light.G), ratio(base.B, light.B))
	local top = math.max(alpha, EDGE_LIGHT_ALPHA)
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(EDGE_LIGHT_SPAN, k),
		ColorSequenceKeypoint.new(1, k),
	})
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1 - top),
		NumberSequenceKeypoint.new(EDGE_LIGHT_SPAN, 1 - alpha),
		NumberSequenceKeypoint.new(1, 1 - alpha),
	})
end

-- The "Edge" of a card, button or sheet: a `thickness` px border in `base` at
-- `alpha` (default: a 1 px line hairline at 0.5), lit from the top (the top
-- highlight). Replaces an older Edge. Returns the UIStroke.
function Kit.bevel(inst: Instance, base: Color3?, thickness: number?, alpha: number?): UIStroke
	local old = inst:FindFirstChild("Edge")
	if old then
		old:Destroy()
	end
	local stroke = Kit.new("UIStroke", {
		Name = "Edge",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	}) :: UIStroke
	paintEdge(stroke, base or Kit.colors.line, thickness or 1, alpha or (1 - HAIRLINE_TRANSPARENCY))
	return stroke
end

local FILL = UDim2.fromScale(1, 1)
local REST = UDim2.fromOffset(0, 0)

local function isFill(size: UDim2): boolean
	return size.X.Scale == 1 and size.X.Offset == 0 and size.Y.Scale == 1 and size.Y.Offset == 0
end

-- The props a lipped button's holder takes from the caller.
local HOLDER_PROPS: { [string]: boolean } = {
	Parent = true,
	Size = true,
	Position = true,
	AnchorPoint = true,
	LayoutOrder = true,
	Visible = true,
	ZIndex = true,
	AutomaticSize = true,
	SizeConstraint = true,
}

-- The holder of a lipped button (its parent, a transparent Frame "<Name>Holder"
-- that also holds the Lip), or `inst` itself. Move, reparent or anchor a primary
-- or secondary through this.
function Kit.outer(inst: GuiObject): GuiObject
	local parent = inst.Parent
	if parent and parent:GetAttribute("LipHolder") == true and parent:IsA("GuiObject") then
		return parent :: GuiObject
	end
	return inst
end

-- Keeps a face and its holder together: Size, Visible and LayoutOrder set on
-- the face later go to the holder (the face always fills it); a destroyed face
-- takes the holder along; a face moved elsewhere leaves the holder (and its
-- lip) behind and keeps the size it had.
local function follow(face: GuiObject, holder: Frame)
	local outerSize = holder.Size
	pcall(function()
		face:GetPropertyChangedSignal("Size"):Connect(function()
			local size = face.Size
			if face.Parent == holder and not isFill(size) then
				outerSize = size
				holder.Size = size
				face.Size = FILL
			end
		end)
		face:GetPropertyChangedSignal("Visible"):Connect(function()
			holder.Visible = face.Visible
		end)
		face:GetPropertyChangedSignal("LayoutOrder"):Connect(function()
			holder.LayoutOrder = face.LayoutOrder
		end)
		face:GetPropertyChangedSignal("Parent"):Connect(function()
			local parent = face.Parent
			if parent == holder then
				return
			end
			holder:Destroy()
			if parent ~= nil then
				face.Size = outerSize
			end
		end)
	end)
end

-- A button with a label that shrinks to fit, at least MIN_TOUCH px both ways.
-- `props.variant` picks the look (see the header); other props are set on the
-- TextButton as usual and win over the variant's defaults. Primary and
-- secondary buttons come in a holder with a lip (see the header).
function Kit.button(text: string, onActivate: () -> (), props: { [string]: any }?): TextButton
	local variant: Variant? = nil
	local lipWanted = true
	local rest: { [string]: any } = {}
	if props then
		for key, value in props do
			if key == "variant" then
				variant = if type(value) == "string" then VARIANTS[value] else nil
			elseif key == "lip" then
				lipWanted = value ~= false
			else
				rest[key] = value
			end
		end
	end
	local look = if variant then LOOKS[variant] else SECONDARY
	local primary = variant == "primary"
	local lip = if primary
		then Kit.LIP_PRIMARY
		elseif variant == "secondary" and lipWanted then Kit.LIP_SECONDARY
		else 0
	local base = merged({
		BackgroundColor3 = look.bg,
		BackgroundTransparency = if variant == "ghost" then 1 else 0,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, if primary then Kit.PRIMARY_H else Kit.MIN_TOUCH),
		Font = if primary then Kit.font.display else Kit.font.medium,
		TextSize = if primary then Kit.size.heading else Kit.size.body,
		TextColor3 = look.text,
		TextScaled = true,
		Text = text,
		Name = text,
	}, rest)

	-- A lipped button: the caller's placement goes on the holder.
	local holder: Frame? = nil
	if lip > 0 then
		local outer: { [string]: any } = {
			Name = `{base.Name}Holder`,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}
		for key in HOLDER_PROPS do
			if base[key] ~= nil then
				outer[key] = base[key]
				-- The face keeps Visible and LayoutOrder too, so a later change shows.
				if key ~= "Visible" and key ~= "LayoutOrder" then
					base[key] = nil
				end
			end
		end
		local parent = outer.Parent
		outer.Parent = nil
		local frame = Kit.new("Frame", outer) :: Frame
		frame:SetAttribute("LipHolder", true)
		Kit.new("UISizeConstraint", { MinSize = Vector2.new(Kit.MIN_TOUCH, Kit.MIN_TOUCH), Parent = frame })
		local lipFrame = Kit.new("Frame", {
			Name = "Lip",
			Size = FILL,
			Position = UDim2.fromOffset(0, lip),
			BackgroundColor3 = if primary then Kit.colors.accentLip else Kit.colors.raisedLip,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = frame,
		})
		lipFrame:SetAttribute("Decor", true)
		Kit.corner(Kit.radius.button).Parent = lipFrame
		base.Size = FILL
		base.Position = REST
		base.Parent = frame
		holder = frame
		if parent then
			frame.Parent = parent
		end
	end

	local button = Kit.new("TextButton", base)
	if variant then
		button:SetAttribute("Variant", variant)
	end
	if variant == "danger" then
		-- Its orange label says what it destroys ("Cancel", "Clear"): a warning.
		button:SetAttribute("Warn", true)
	end
	if lip > 0 then
		button:SetAttribute("Lip", lip)
	end
	Kit.corner(if lip > 0 or variant == "danger" then Kit.radius.button else Kit.radius.control).Parent =
		button
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
	if primary then
		Kit.bevel(button, Kit.colors.accentEdge, 2, 1)
	elseif variant == "secondary" then
		Kit.bevel(button, Kit.colors.text, SECONDARY_EDGE, 1)
	end
	if primary or variant == "secondary" or variant == "chip" then
		shade(button)
	end
	if holder then
		follow(button, holder)
	end
	Motion.press(button)
	local cue = if variant == "chip" then "select" else "tap"
	button.Activated:Connect(function()
		Audio.play(cue)
	end)
	button.Activated:Connect(onActivate)
	return button
end

-- A 44x44 secondary button for a glyph or an icon: "×", "+", "−", "?". Corner
-- control (8), with the secondary's 3 px lip.
function Kit.iconButton(glyph: string, onActivate: () -> (), props: { [string]: any }?): TextButton
	local button = Kit.button(
		glyph,
		onActivate,
		merged({
			variant = "secondary",
			Size = UDim2.fromOffset(Kit.MIN_TOUCH, Kit.MIN_TOUCH),
			Font = Kit.font.bold,
		}, props)
	)
	local radius = UDim.new(0, Kit.radius.control)
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = radius
	end
	local lip = Kit.outer(button):FindFirstChild("Lip")
	local lipCorner = if lip then lip:FindFirstChildOfClass("UICorner") else nil
	if lipCorner then
		lipCorner.CornerRadius = radius
	end
	return button
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
	-- A color tween still running (ActionBar's lock-in flash) would land on the
	-- old look after this: stop it first.
	Motion.cancel(button)
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
	local edge = button:FindFirstChild("Edge")
	if edge and variant == "primary" then
		-- A disabled primary wears the secondary's hairline, not the accent edge.
		if enabled then
			paintEdge(edge :: UIStroke, Kit.colors.accentEdge, 2, 1)
		else
			paintEdge(edge :: UIStroke, Kit.colors.line, 1, 1 - HAIRLINE_TRANSPARENCY)
		end
	end
	local lip = Kit.outer(button):FindFirstChild("Lip")
	if lip and variant == "primary" then
		(lip :: Frame).BackgroundColor3 = if enabled then Kit.colors.accentLip else Kit.colors.raisedLip
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
		local was = stroke.Enabled
		stroke.Enabled = selected
		if selected and not was then
			-- The outline draws in (0 -> 2 px); instant under reduced motion.
			stroke.Thickness = 0
			Motion.tween(stroke, { Thickness = 2 }, Motion.t.fast)
		elseif not selected then
			Motion.cancel(stroke)
			stroke.Thickness = 2
		end
	end
end

-- ---------------------------------------------------------------- style v2

-- A bold title-size line: a screen's one big heading.
function Kit.title(text: string, props: { [string]: any }?): TextLabel
	return Kit.text(
		text,
		merged({
			Size = UDim2.new(1, 0, 0, Kit.size.title + 8),
			Font = Kit.font.display,
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

local CARD_PAD = 14 -- px, a card's padding (D-056: md 12 was tight next to the bevel)

-- A card: the one container style for grouped content. Surface gradient, panel
-- corner, the bevel edge, padding 14, a vertical list (gap sm); grows in Y
-- with its content.
function Kit.card(props: { [string]: any }?, children: { Instance }?): Frame
	local frame = Kit.panel(merged({
		Name = "Card",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, props))
	-- Depth on the plain surface card only: a caller's own fill stays flat.
	if props == nil or props.BackgroundColor3 == nil then
		Kit.depth(frame, Kit.colors.surfaceTop, Kit.colors.surface)
	end
	Kit.bevel(frame)
	local pad = frame:FindFirstChildOfClass("UIPadding")
	if pad then
		local px = UDim.new(0, CARD_PAD)
		pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = px, px, px, px
	end
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
-- "Battleground", "Locked in". The tone colors the text on a raised fill. With
-- props.filled = true the tone is the fill instead (props.fill: any data color,
-- marked dataColor) with readable text and a 1 px edge; tone "white" is the
-- battleground mark: "★ Battleground", outlined in white on a field fill (D-058).
local EDGE_TINT = 0.35 -- a data-colored fill's edge: this far toward the background
local EDGES: { [string]: Color3 } = {
	loss = Kit.colors.lossEdge,
	bad = Kit.colors.lossEdge,
	warn = Kit.colors.lossEdge,
	good = Kit.colors.goodEdge,
	accent = Kit.colors.accentEdge,
}

function Kit.pill(text: string, tone: Tone?, props: { [string]: any }?): TextLabel
	local name: Tone = tone or "text"
	local rest: { [string]: any } = {}
	local filled = false
	local fill: Color3? = nil
	if props then
		for key, value in props do
			if key == "filled" then
				filled = value == true
			elseif key == "fill" then
				fill = value
			else
				rest[key] = value
			end
		end
	end
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
			TextColor3 = Kit.tone(name),
		}, rest)
	)
	Kit.corner(Kit.PILL_H // 2).Parent = label
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, Kit.space.sm),
		PaddingRight = UDim.new(0, Kit.space.sm),
		Parent = label,
	})
	if filled or fill ~= nil or name == "white" then
		Kit.paintPill(label, name, filled or fill ~= nil, fill)
	end
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

-- Tweens `inst` to `goals` over `duration` (default Kit.motion.base), Quad Out,
-- through Motion.tween: instant under reduced motion or without a TweenService.
function Kit.tween(inst: Instance, goals: { [string]: any }, duration: number?)
	Motion.tween(inst, goals, duration or Kit.motion.base, Motion.ease.out)
end

-- The largest Kit.size token that fits in `px` (caption at least).
local function sizeFor(px: number): number
	local best = Kit.size.caption
	for _, token in { Kit.size.body, Kit.size.heading, Kit.size.title, Kit.size.hero } do
		if token <= px then
			best = token
		end
	end
	return best
end

-- An icon from UI/Icons, `size` px square (default 20), tinted `color` (default
-- text): an ImageLabel when the icon has an uploaded id, else its glyph as a
-- TextLabel (scaled, never under Kit.MIN_TEXT). Named "Icon", attribute Icon = name.
function Kit.icon(name: string, size: number?, color: Color3?): GuiObject
	local icon = Icons[name]
	local px = size or 20
	local tint = color or Kit.colors.text
	local inst: GuiObject
	if icon and icon.id ~= "" then
		inst = Kit.new("ImageLabel", {
			Name = "Icon",
			Size = UDim2.fromOffset(px, px),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = icon.id,
			ImageColor3 = tint,
			ScaleType = Enum.ScaleType.Fit,
		})
	else
		inst = Kit.text(if icon then icon.glyph else "?", {
			Name = "Icon",
			Size = UDim2.fromOffset(px, px),
			Font = Kit.font.bold,
			TextSize = sizeFor(px),
			TextScaled = true,
			TextWrapped = false,
			TextColor3 = tint,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
	end
	inst:SetAttribute("Icon", name)
	return inst
end

-- The icon for a plan action kind (Sim/Plan.Kind), nil for one without.
local ACTION_ICONS: { [string]: string } = {
	Rally = "megaphone",
	Fundraise = "coins",
	Media = "tv",
	Attack = "zap",
	Poll = "search",
	RegionPoll = "search",
	Gotv = "footprints",
}

function Kit.actionIcon(kind: string): string?
	return ACTION_ICONS[kind]
end

-- ---------------------------------------------------------------- issue symbols (D-076)

Kit.ISSUE_ICON = 20 -- px, an issue symbol's default size
Kit.MIN_ICON = 14 -- px, the smallest issue symbol a screen may show (UI audit iconFloor)
local ISSUE_GAP = 4 -- px between a symbol and its name

local issueNames: { [string]: string } = Issues.displayName :: any

-- An issue's full name ("Roads & Transit"); an unknown one as it is.
function Kit.issueName(issue: string): string
	return issueNames[issue] or issue
end

-- The short code a symbol alone falls back to before its upload ("JOB"); an
-- issue without one gets its first three letters.
function Kit.issueCode(issue: string): string
	local icon = IssueIcons.icons[issue]
	return if icon then icon.code else string.upper(string.sub(issue, 1, 3))
end

-- Whether the game can draw `issue`'s symbol (its image is uploaded, or the
-- tests preview it); if not, every helper below shows text instead.
function Kit.hasIssueIcon(issue: string): boolean
	local icon = IssueIcons.icons[issue]
	return icon ~= nil and (icon.id ~= "" or IssueIcons.preview == true)
end

-- An issue's symbol alone, `size` px square (default Kit.ISSUE_ICON), tinted
-- `color` (default text): ImageLabel "IssueIcon" with attributes IssueIcon =
-- the issue and IssueName = its name (the snapshot renderer draws
-- assets/issues/<file>.png). Use it alone only where the screen also says the
-- name (a tap, the map key). Without the image: a TextLabel "IssueIcon" with
-- the issue's code, `size` tall and as wide as the code (attribute IconFallback).
function Kit.issueIcon(issue: string, size: number?, color: Color3?): GuiObject
	local px = size or Kit.ISSUE_ICON
	local tint = color or Kit.colors.text
	local inst: GuiObject
	if Kit.hasIssueIcon(issue) then
		inst = Kit.new("ImageLabel", {
			Name = "IssueIcon",
			Size = UDim2.fromOffset(px, px),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = IssueIcons.icons[issue].id,
			ImageColor3 = tint,
			ScaleType = Enum.ScaleType.Fit,
		})
	else
		inst = Kit.text(Kit.issueCode(issue), {
			Name = "IssueIcon",
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, px),
			Font = Kit.font.hand,
			TextSize = Kit.size.caption,
			TextWrapped = false,
			TextColor3 = tint,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		inst:SetAttribute("IconFallback", true)
	end
	inst:SetAttribute("IssueIcon", issue)
	inst:SetAttribute("IssueName", Kit.issueName(issue))
	return inst
end

-- Puts `issue`'s symbol in front of a label's or a button's own text: the
-- symbol at the left of its padded box, `size` px (default: the text size,
-- at least Kit.MIN_ICON), tinted like the text (and following it), the text
-- left-aligned after it; centered on a one-line box, beside the first line of
-- a box that grows with its text (AutomaticSize Y). A word stays readable
-- first (docs/UI-STYLE.md §2.6): while the box is too narrow for the symbol and
-- the text at Kit.MIN_TEXT (ISSUE_EM estimate; wrapped lines count when the
-- text wraps), the symbol hides and the text keeps its old place; it is checked
-- again when the box, its text or its parent changes, and by
-- Kit.refitIssueLeads. Calling it again replaces the symbol; `issue` nil
-- removes it. Returns the symbol, or nil (the text alone) while the image is
-- missing: the text already names the issue.
local ISSUE_EM = 0.55 -- an average character's advance, in em (the fit estimate)

type Lead = {
	icon: GuiObject,
	fit: () -> (),
	left: number, -- the box's own left padding
	alignment: Enum.TextXAlignment, -- the text's own alignment
	connections: { RBXScriptConnection },
}
local leads: { [Instance]: Lead } = setmetatable({}, { __mode = "k" }) :: any

-- Checks again whether each issueLead label under `root` has room for its
-- symbol (call it after a layout change the label cannot see, such as its
-- grid being resized).
function Kit.refitIssueLeads(root: Instance)
	for _, inst in root:GetDescendants() do
		local lead = leads[inst]
		if lead then
			lead.fit()
		end
	end
end

function Kit.issueLead(inst: TextLabel | TextButton, issue: string?, size: number?): GuiObject?
	local target: any = inst
	local pad = inst:FindFirstChildOfClass("UIPadding")
	local old = leads[inst]
	if old then
		for _, connection in old.connections do
			connection:Disconnect()
		end
		old.icon:Destroy()
		if pad then
			pad.PaddingLeft = UDim.new(0, old.left)
		end
		target.TextXAlignment = old.alignment
		leads[inst] = nil
	end
	if issue == nil or not Kit.hasIssueIcon(issue) then
		return nil
	end
	local px = size or math.max(Kit.MIN_ICON, target.TextSize)
	if pad == nil then
		pad = Kit.new("UIPadding", { PaddingLeft = UDim.new(0, 0), Parent = inst })
	end
	local padding = pad :: UIPadding
	local function offset(u: UDim?): number
		return if u then u.Offset else 0
	end
	local left = offset(padding.PaddingLeft)
	local alignment = target.TextXAlignment
	local icon = Kit.issueIcon(issue, px, target.TextColor3)
	-- It sits in the label's own left padding: UIPadding moves children too.
	local auto: EnumItem? = target.AutomaticSize
	local autoName = if auto then auto.Name else "None"
	local grows = autoName == "Y" or autoName == "XY" -- the box grows with its lines
	if grows then
		icon.Position =
			UDim2.fromOffset(-(px + ISSUE_GAP), math.max(0, math.floor((target.TextSize + 4 - px) / 2)))
	else
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, -(px + ISSUE_GAP), 0.5, 0)
	end
	icon.ZIndex = target.ZIndex
	icon.Parent = inst
	local image = icon :: ImageLabel
	local function tint()
		image.ImageColor3 = target.TextColor3
		image.ImageTransparency = target.TextTransparency
	end
	-- Room for the symbol and the text (at the smallest size) in the box?
	local function roomy(): boolean
		local box = target.AbsoluteSize
		if box.X <= 0 then
			return true -- not laid out yet
		end
		local room = box.X - left - offset(padding.PaddingRight) - px - ISSUE_GAP
		local em = Kit.MIN_TEXT * ISSUE_EM
		local text = tostring(target.Text)
		for word in string.gmatch(text, "%S+") do
			if (utf8.len(word) or #word) * em > room then
				return false
			end
		end
		local high = box.Y - offset(padding.PaddingTop) - offset(padding.PaddingBottom)
		local lines = if grows
			then math.huge
			elseif target.TextWrapped then math.max(1, math.floor(high / (Kit.MIN_TEXT + 2)))
			else 1
		return (utf8.len(text) or #text) * em <= room * lines
	end
	local function fit()
		local show = roomy()
		image.Visible = show
		padding.PaddingLeft = UDim.new(0, if show then left + px + ISSUE_GAP else left)
		target.TextXAlignment = if show then Enum.TextXAlignment.Left else alignment
	end
	local connections = {
		inst:GetPropertyChangedSignal("TextColor3"):Connect(tint),
		inst:GetPropertyChangedSignal("TextTransparency"):Connect(tint),
	}
	for _, name in { "AbsoluteSize", "Text", "Parent" } do
		table.insert(connections, inst:GetPropertyChangedSignal(name):Connect(fit))
	end
	leads[inst] = { icon = icon, fit = fit, left = left, alignment = alignment, connections = connections }
	fit()
	return icon
end

-- Shows `issue`'s symbol, `size` px, centered in `label` (a map's lens plate)
-- and returns it; the caller clears the label's text and sizes the plate. Nil
-- `issue`, or a symbol the game cannot draw yet: removes the symbol and
-- returns nil (the caller shows its text). Repaints in place when called again.
function Kit.setIssueIcon(label: GuiObject, issue: string?, size: number, color: Color3): GuiObject?
	local old = label:FindFirstChild("IssueIcon") :: GuiObject?
	if issue == nil or not Kit.hasIssueIcon(issue) then
		if old then
			old:Destroy()
		end
		return nil
	end
	local icon: GuiObject
	if old and old:GetAttribute("IssueIcon") == issue and old.Size.X.Offset == size then
		icon = old
	else
		if old then
			old:Destroy()
		end
		icon = Kit.issueIcon(issue, size, color)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.ZIndex = label.ZIndex
		icon.Parent = label
	end
	(icon :: ImageLabel).ImageColor3 = color
	return icon
end

-- An issue's symbol and full name in a row, as wide as they are ("[leaf]
-- Environment"): Frame "IssueTag_<issue>" with the symbol ("IssueIcon") and the
-- name ("IssueText"). props: Name, LayoutOrder, Parent, Visible, `text` (a
-- label other than the name), `color` (text and symbol; default text),
-- `textSize` (default caption), `iconSize` (default the text size + 2, at
-- least Kit.MIN_ICON), `font` (default medium). Without the image: the name alone.
function Kit.issueTag(issue: string, props: { [string]: any }?): Frame
	local o: { [string]: any } = props or {}
	local textSize: number = o.textSize or Kit.size.caption
	local iconSize: number = o.iconSize or math.max(Kit.MIN_ICON, textSize + 2)
	local color: Color3 = o.color or Kit.colors.text
	local height = math.max(iconSize, textSize + 4)
	local row = Kit.box({
		Name = o.Name or `IssueTag_{issue}`,
		LayoutOrder = o.LayoutOrder or 0,
		Visible = if o.Visible == nil then true else o.Visible,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, height),
	})
	local list = Kit.list("Horizontal", ISSUE_GAP)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = row
	if Kit.hasIssueIcon(issue) then
		local icon = Kit.issueIcon(issue, iconSize, color)
		icon.LayoutOrder = 1
		icon.Parent = row
	end
	Kit.text(o.text or Kit.issueName(issue), {
		Name = "IssueText",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, height),
		TextSize = textSize,
		Font = o.font or Kit.font.medium,
		TextColor3 = color,
		TextWrapped = false,
		Parent = row,
	})
	if o.Parent then
		row.Parent = o.Parent
	end
	return row
end

-- ---------------------------------------------------------------- front page (D-056)

local SHADOW_DY = 4 -- px a shadow drops below its object
local SHADOW_SPREAD = 8 -- px a shadow reaches past its object on each side (D-102: paper sits close to the board)
local SHADOW_TRANSPARENCY = 0.85 -- D-102: a faint shadow on the white board (0.45 on the navy stage was a smear)
local SHADOW_SLICE = Rect.new(40, 40, 56, 56) -- ui-shadow.png's stretchable middle
local GLOW_INVISIBLE = 0.95 -- a glow this transparent or more is not drawn at all
local GLOW_TRANSPARENCY = 0.85 -- D-102: a faint wash on the white board (0.6 on navy read as a smudge here)
local STAMP_TILT = -6 -- degrees
local STAMP_RADIUS = 10 -- px
local STAMP_PAD_X = 14 -- px
local STAMP_PAD_Y = 8 -- px
local STAMP_WASH = 0.86 -- a stamp's fill: a light wash of its color on the board (D-102)
local STAMP_EDGE = 3 -- px, a stamp's marker outline (D-102)
local STAMP_CIRCLE = 1.3 -- the marker circle around a stamp, x its size (D-102)
local DISPLAY_EM = 0.66 -- Fredoka One's average advance, in em (a stamp's width estimate)
local MONOGRAM_TEXT = 0.42 -- a monogram's initials, x its size
local MONOGRAM_SHADE = 0.78 -- the bottom of a monogram's gradient
local MONOGRAM_SHEEN = 0.45 -- the top share of a monogram the sheen covers
local MONOGRAM_SHEEN_TRANSPARENCY = 0.82
local PORTRAIT_PLATE_TOP = Color3.fromRGB(104, 118, 156) -- a portrait's neutral plate, top of its gradient
local PORTRAIT_PLATE = Color3.fromRGB(66, 76, 108) -- ... and its bottom
local PORTRAIT_EDGE = Color3.fromRGB(32, 38, 60) -- the plate's edge when it has no ring
local PORTRAIT_RING = 0.06 -- a player-color ring's thickness, x the portrait's size (2 px at least)
local PORTRAIT_RING_MIN = 2 -- px
local PORTRAIT_EDGE_W = 1.5 -- px, the plain edge
local RACE_OVERHANG = 4 -- px the 270 tick reaches above and below the bar
local RACE_TICK_W = 3 -- px
local RACE_SHADE = 0.82 -- the bottom of a race bar segment's gradient
local RACE_CAPTION_W = 40 -- px, the "270" over the tick
local RIBBON_H = Kit.size.heading + 2 * 6 -- px, the tagline ribbon under the wordmark
local RIBBON_PAD_X = 18 -- px, the ribbon's text inset
local RIBBON_TILT = -2 -- degrees: a hand-drawn underline is never level
local RIBBON_OVERLAP = 12 -- px the ribbon rides up over the name's (empty) foot
local RIBBON_SLACK = 6 -- px under the ribbon: room for its tilt and shadow
local UNDERLINE_PX = 6 -- px, the blue marker stroke under the wordmark (D-102)
local UNDERLINE_DELAY = 0.15 -- s before the underline draws itself on
local ICON_PLATE = 24 -- px, an icon plate's default size

-- Whether `parent` lays its children out (a list or a grid moves every child).
local function laysOut(parent: Instance): boolean
	return parent:FindFirstChildOfClass("UIListLayout") ~= nil
		or parent:FindFirstChildOfClass("UIGridLayout") ~= nil
end

local function decor<T>(inst: T, asset: string): T
	local target = inst :: any
	target:SetAttribute("Decor", true)
	target:SetAttribute("Asset", asset)
	return inst
end

-- An eyebrow over a title: caption size, muted, upper case ("JUST CALLED").
function Kit.eyebrow(text: string, props: { [string]: any }?): TextLabel
	return Kit.caption(string.upper(text), merged({ Name = "Eyebrow", Font = Kit.font.medium }, props))
end

export type ShadowOptions = { dy: number?, spread: number?, transparency: number? }

-- A soft shadow behind `inst`: a sibling ImageLabel "Shadow" one ZIndex under
-- it that follows its Size, Position, AnchorPoint, Visible and background fade
-- (AbsoluteSize for an AutomaticSize object). Nil when `inst` has no parent yet
-- or its parent lays children out. Draws nothing until Assets.shadow is uploaded.
function Kit.shadow(inst: GuiObject, opts: ShadowOptions?): ImageLabel?
	local parent = inst.Parent
	if parent == nil or laysOut(parent) then
		return nil
	end
	local o: ShadowOptions = opts or {}
	local dy = o.dy or SHADOW_DY
	local spread = o.spread or SHADOW_SPREAD
	local transparency = o.transparency or SHADOW_TRANSPARENCY
	local shadow = decor(
		Kit.new("ImageLabel", {
			Name = "Shadow",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Assets.shadow.id,
			ImageColor3 = Color3.new(0, 0, 0),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = SHADOW_SLICE,
			SliceScale = 1,
		}),
		"shadow"
	) :: ImageLabel
	shadow:SetAttribute("Follow", inst.Name)
	shadow:SetAttribute("Dy", dy)
	shadow:SetAttribute("Spread", spread)
	local function place()
		local auto = inst.AutomaticSize
		local size: UDim2 = (inst :: any).Size or UDim2.fromScale(1, 1)
		if auto ~= nil and auto.Name ~= "None" then
			local abs = inst.AbsoluteSize
			size = UDim2.fromOffset(abs.X, abs.Y)
		end
		-- (Never nil in Roblox; an unset property in the fake engine.)
		local position: UDim2 = (inst :: any).Position or UDim2.new()
		local anchor: Vector2 = (inst :: any).AnchorPoint or Vector2.new(0, 0)
		shadow.AnchorPoint = anchor
		shadow.Size =
			UDim2.new(size.X.Scale, size.X.Offset + 2 * spread, size.Y.Scale, size.Y.Offset + 2 * spread)
		shadow.Position = UDim2.new(
			position.X.Scale,
			position.X.Offset + spread * (2 * anchor.X - 1),
			position.Y.Scale,
			position.Y.Offset + spread * (2 * anchor.Y - 1) + dy
		)
		shadow.Visible = inst.Visible
		shadow.ZIndex = ((inst :: any).ZIndex or 1) - 1
		local fade = math.clamp((inst :: any).BackgroundTransparency or 0, 0, 1)
		shadow.ImageTransparency = 1 - (1 - transparency) * (1 - fade)
	end
	place()
	pcall(function()
		for _, name in
			{
				"Size",
				"Position",
				"AnchorPoint",
				"Visible",
				"ZIndex",
				"BackgroundTransparency",
				"AbsoluteSize",
			}
		do
			inst:GetPropertyChangedSignal(name):Connect(place)
		end
		inst:GetPropertyChangedSignal("Parent"):Connect(function()
			if inst.Parent ~= shadow.Parent then
				shadow:Destroy()
			end
		end)
	end)
	shadow.Parent = parent
	return shadow
end

export type GlowOptions = { scale: number?, px: number?, transparency: number?, stretch: boolean? }

-- A radial glow centered in `parent`, under its other children (ZIndex 0):
-- `scale` x the parent (a circle as big as the parent's shorter side, or an
-- ellipse with `stretch`), or `px` square. Nil in a parent that lays children
-- out. Draws nothing until Assets.glow is uploaded.
function Kit.glow(parent: Instance, color: Color3, opts: GlowOptions?): ImageLabel?
	local o: GlowOptions = opts or {}
	-- A glow too faint to see still costs a full-size draw (fill rate on a
	-- phone): skip it (D-102's faint washes).
	if laysOut(parent) or (o.transparency or GLOW_TRANSPARENCY) >= GLOW_INVISIBLE then
		return nil
	end
	local scale = o.scale or 1
	return decor(
		Kit.new("ImageLabel", {
			Name = "Glow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = if o.px then UDim2.fromOffset(o.px, o.px) else UDim2.fromScale(scale, scale),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Assets.glow.id,
			ImageColor3 = color,
			ImageTransparency = o.transparency or GLOW_TRANSPARENCY,
			ScaleType = if o.stretch then Enum.ScaleType.Stretch else Enum.ScaleType.Fit,
			ZIndex = 0,
			Parent = parent,
		}),
		"glow"
	) :: ImageLabel
end

-- The edge of a fill in a data color: 35 % toward the background.
local function edgeOf(color: Color3): Color3
	return Kit.color(Colors.tint(Kit.rgb(color), Colors.background, EDGE_TINT))
end

-- `text` with the battleground star in front (`on`) or without it.
local STAR_PREFIX = Kit.STAR .. " "
local function starred(text: string, on: boolean): string
	local has = string.sub(text, 1, #STAR_PREFIX) == STAR_PREFIX
	if on and not has and text ~= "" then
		return STAR_PREFIX .. text
	elseif not on and has then
		return string.sub(text, #STAR_PREFIX + 1)
	end
	return text
end

-- The pill's 1 px "Edge" stroke, made on first use.
local function pillEdge(pill: TextLabel): UIStroke
	local edge = pill:FindFirstChild("Edge") :: UIStroke?
	if edge == nil then
		edge = Kit.new("UIStroke", {
			Name = "Edge",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Thickness = 1,
			Parent = pill,
		})
	end
	return edge :: UIStroke
end

-- Re-tones a Kit.pill: `tone` as the text on a raised fill, or with `filled`
-- the tone (or `fill`, a data color: the pill is marked dataColor) as the fill
-- with readable text and a 1 px edge. Tone "white" is the battleground mark
-- (D-058): a field fill, a Kit.MARK_STROKE `text` outline and bold `text` after
-- Kit.STAR (added to the pill's current text, and taken off again by any other
-- tone), so it never looks like the white primary or a selection. For pills
-- whose meaning changes (a verdict, a state's tags); set the Text first.
function Kit.paintPill(pill: TextLabel, tone: Tone, filled: boolean?, fill: Color3?)
	local mark = tone == "white"
	local solid = not mark and (filled == true or fill ~= nil)
	local edge = pill:FindFirstChild("Edge") :: UIStroke?
	pill:SetAttribute("Filled", solid)
	pill:SetAttribute("Outlined", mark)
	pill.Text = starred(pill.Text, mark)
	if mark then
		local stroke = pillEdge(pill)
		stroke.Enabled = true
		stroke.Color = Kit.colors.text
		stroke.Thickness = Kit.MARK_STROKE
		pill.BackgroundColor3 = Kit.colors.field
		pill.TextColor3 = Kit.colors.text
		pill.Font = Kit.font.bold
		return
	end
	if not solid then
		pill.BackgroundColor3 = Kit.colors.raised
		pill.TextColor3 = Kit.tone(tone)
		pill.Font = Kit.font.medium
		if edge then
			edge.Enabled = false
		end
		return
	end
	local color = fill or Kit.tone(tone)
	pill.BackgroundColor3 = color
	pill.TextColor3 = Kit.color(Colors.onColor(Kit.rgb(color)))
	pill.Font = Kit.font.bold
	local stroke = pillEdge(pill)
	stroke.Enabled = true
	stroke.Thickness = 1
	stroke.Color = if fill then edgeOf(fill) else (EDGES[tone] or Kit.colors.line)
	if fill then
		Kit.dataColor(pill)
	end
end

-- A stamp for the big moments ("CALLED", "270!", "You won"): a plate of
-- `color` tilted −6° with a Fredoka label in its readable color, a 2 px edge,
-- an outline on the label and a glow behind. props.size is the label's Kit.size
-- token (default title); other props go on the returned Frame "Stamp" (Name,
-- Position, AnchorPoint, LayoutOrder, ZIndex, Parent). Attribute Overhang, so
-- it may sit over an edge. The plate is "Plate", the label "Label".
-- props.fit (px): the stamp is never wider than its parent less `fit` on each
-- side (a long name on a phone): it spans that width up to its words' own
-- (a UISizeConstraint) and the label scales down to fit.
function Kit.stamp(text: string, color: Color3, props: { [string]: any }?): Frame
	local size = Kit.size.title
	local fit: number? = nil
	local rest: { [string]: any } = {}
	if props then
		for key, value in props do
			if key == "size" then
				size = value
			elseif key == "fit" then
				fit = value
			else
				rest[key] = value
			end
		end
	end
	local chars = utf8.len(text) or #text
	local width = math.ceil(chars * size * DISPLAY_EM) + 2 * STAMP_PAD_X
	local height = size + 2 * STAMP_PAD_Y + Kit.space.xs
	local parent = rest.Parent
	rest.Parent = nil
	local root = Kit.new(
		"Frame",
		merged({
			Name = "Stamp",
			Size = UDim2.fromOffset(width, height),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Rotation = STAMP_TILT,
		}, rest)
	) :: Frame
	root:SetAttribute("Overhang", true)
	if fit then
		root.Size = UDim2.new(1, -2 * fit, 0, height)
		Kit.new("UISizeConstraint", { MaxSize = Vector2.new(width, height), Parent = root })
	end
	-- Marker writing boxed on the board (D-102, was a filled slab with a glow):
	-- a light wash of the color, a thick marker outline in it, the word in its ink.
	local plate = Kit.dataColor(Kit.new("Frame", {
		Name = "Plate",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = STAMP_WASH,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = root,
	}))
	Kit.corner(STAMP_RADIUS).Parent = plate
	local stampEdge = Kit.new("UIStroke", {
		Name = "Edge",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color,
		Thickness = STAMP_EDGE,
		Parent = plate,
	}) :: UIStroke
	-- Once the scribble circle is uploaded the word is circled in marker
	-- instead of boxed (the brief's "circled, underlined marker writing").
	if Board.circle(root, color, { scale = STAMP_CIRCLE }) then
		stampEdge.Enabled = false
		plate.BackgroundTransparency = 1
	end
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, STAMP_PAD_X),
		PaddingRight = UDim.new(0, STAMP_PAD_X),
		PaddingTop = UDim.new(0, STAMP_PAD_Y),
		PaddingBottom = UDim.new(0, STAMP_PAD_Y),
		Parent = plate,
	})
	Kit.text(text, {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		Font = Kit.font.display,
		TextSize = size,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Kit.textColor(color),
		Parent = plate,
	})
	if parent then
		root.Parent = parent
	end
	return root
end

-- The initials of `name`: the first letters of its first two words, upper case.
local function initialsOf(name: string): string
	local initials = ""
	local count = 0
	for word in string.gmatch(name, "%S+") do
		initials ..= string.upper(string.match(word, utf8.charpattern) or "")
		count += 1
		if count == 2 then
			break
		end
	end
	return initials
end

-- A candidate's portrait until there is art: the initials of `name` (first
-- letters of the first two words) in Fredoka on a lit circle of `color`, `px`
-- wide: a top-light gradient, a 2 px darker edge and a sheen over the top.
-- Marked dataColor and Monogram (the audit allows its scaled initials).
function Kit.monogram(name: string, color: Color3, px: number): Frame
	local root = Kit.dataColor(Kit.new("Frame", {
		Name = "Monogram",
		Size = UDim2.fromOffset(px, px),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	})) :: Frame
	root:SetAttribute("Monogram", true)
	Kit.round().Parent = root
	Kit.new("UIGradient", {
		Name = "Depth",
		Rotation = 90,
		Color = ColorSequence.new(
			Color3.new(1, 1, 1),
			Color3.new(MONOGRAM_SHADE, MONOGRAM_SHADE, MONOGRAM_SHADE)
		),
		Parent = root,
	})
	Kit.new("UIStroke", {
		Name = "Edge",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = edgeOf(color),
		Thickness = 2,
		Parent = root,
	})
	local clip = Kit.box({
		Name = "SheenClip",
		Size = UDim2.fromScale(1, MONOGRAM_SHEEN),
		ClipsDescendants = true,
		ZIndex = 1,
		Parent = root,
	})
	clip:SetAttribute("Decor", true)
	local sheen = Kit.new("Frame", {
		Name = "Sheen",
		Size = UDim2.fromOffset(px, px),
		BackgroundColor3 = Kit.colors.text,
		BorderSizePixel = 0,
		Parent = clip,
	})
	Kit.round().Parent = sheen
	Kit.new("UIGradient", {
		Name = "Fade",
		Rotation = 90,
		Transparency = NumberSequence.new(MONOGRAM_SHEEN_TRANSPARENCY, 1),
		Parent = sheen,
	})
	local label = Kit.text(initialsOf(name), {
		Name = "Initials",
		Size = UDim2.fromScale(1, 1),
		Font = Kit.font.hand,
		TextSize = math.max(Kit.MIN_TEXT, math.floor(px * MONOGRAM_TEXT)),
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Kit.color(Colors.onColor(Kit.rgb(color))),
		ZIndex = 2,
		Parent = root,
	})
	label:SetAttribute("Monogram", true)
	return root
end

export type PortraitOptions = {
	ring: Color3?, -- a ring in this (player) color; nil = the plate's plain edge
	fade: number?, -- 0..1: dims the plate and the face (a taken candidate)
}

-- The asset id of a candidate's portrait, or "" while it is not uploaded.
function Kit.portraitImage(id: string?): string
	local number = if id then Assets.portraits[id] else nil
	if type(number) == "number" and number > 0 then
		return `rbxassetid://{number}`
	end
	return ""
end

-- Repaints a Kit.portrait: its ring (nil = the plain edge) and its fade.
function Kit.paintPortrait(root: Frame, opts: PortraitOptions?)
	local o: PortraitOptions = opts or {}
	local px = math.min(root.Size.X.Offset, root.Size.Y.Offset)
	local fade = o.fade or 0
	local ring = root:FindFirstChild("Ring") :: UIStroke?
	if ring then
		local color = o.ring
		ring.Color = color or PORTRAIT_EDGE
		ring.Thickness = if color
			then math.max(PORTRAIT_RING_MIN, math.floor(px * PORTRAIT_RING))
			else PORTRAIT_EDGE_W
		ring.Transparency = fade
	end
	root:SetAttribute("Ring", o.ring ~= nil)
	root.BackgroundTransparency = fade
	local face = root:FindFirstChild("Face") :: ImageLabel?
	if face then
		face.ImageTransparency = fade
	end
	local initials = root:FindFirstChild("Initials") :: TextLabel?
	if initials then
		initials.TextTransparency = fade
	end
end

-- A candidate's face (D-068): the bust from assets/portraits (UI/Assets
-- .portraits) on a round neutral plate, `px` wide, the image clipped to the
-- circle. opts.ring draws a ring in a player color (yours, a pick, a taken
-- one); without it the plate has a plain dark edge, so free candidates look
-- alike only in their frame. While the candidate's asset id is 0 the face is
-- empty and the initials of `name` show on the plate instead (a monogram);
-- `id` nil is a "?" plate (nobody picked yet). The root is Frame "Portrait"
-- (dataColor; attribute Portrait = the id), with "Face" (ImageLabel, attribute
-- Portrait: the snapshot renderer draws the local PNG), "Initials" (attribute
-- PortraitFallback) and the UIStroke "Ring". Repaint with Kit.paintPortrait.
function Kit.portrait(id: string?, name: string, px: number, opts: PortraitOptions?): Frame
	local root = Kit.dataColor(Kit.new("Frame", {
		Name = "Portrait",
		Size = UDim2.fromOffset(px, px),
		BorderSizePixel = 0,
	})) :: Frame
	Kit.depth(root, PORTRAIT_PLATE_TOP, PORTRAIT_PLATE)
	root:SetAttribute("Portrait", id or "")
	Kit.round().Parent = root
	Kit.new("UIStroke", {
		Name = "Ring",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = PORTRAIT_EDGE,
		Thickness = PORTRAIT_EDGE_W,
		Parent = root,
	})
	local image = Kit.portraitImage(id)
	local initials = Kit.text(if id then initialsOf(name) else "?", {
		Name = "Initials",
		Size = UDim2.fromScale(1, 1),
		Font = Kit.font.hand,
		TextSize = math.max(Kit.MIN_TEXT, math.floor(px * MONOGRAM_TEXT)),
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Kit.colors.text,
		Visible = image == "",
		ZIndex = 1,
		Parent = root,
	})
	initials:SetAttribute("Monogram", true)
	initials:SetAttribute("PortraitFallback", true)
	if id then
		local face = Kit.new("ImageLabel", {
			Name = "Face",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 2,
			Parent = root,
		})
		face:SetAttribute("Portrait", id)
		Kit.round().Parent = face
	end
	Kit.paintPortrait(root, opts)
	return root
end

export type RaceBarOptions = {
	h: number?, -- px, the bar's thickness (10 in the Campaign header, 14 on election night)
	mark: number?, -- where the tick sits, a share of the track (votes to win / all votes)
	caption: string?, -- a short label over the tick ("270"); nil for none
	name: string?, -- the root's Name (default "RaceBar")
	order: number?, -- the root's LayoutOrder
}

export type RaceBar = {
	root: Frame,
	track: Frame,
	left: Frame,
	right: Frame,
	tick: Frame,
	caption: TextLabel?,
	set: (self: RaceBar, left: number, right: number) -> (),
	setColors: (self: RaceBar, left: Color3, right: Color3) -> (),
	setMark: (self: RaceBar, share: number) -> (),
	cross: (self: RaceBar) -> (),
}

-- The race to 270 as one bar: a raised track, the left player's share growing
-- from the left end and the right player's from the right (each lit from the
-- top, rounded at the outer end; they never cover each other), and the tick at
-- `mark`, overhanging the bar RACE_OVERHANG px each way. The root (dataColor) is
-- full width and h + 8 px tall (+ the caption row). bar:set(l, r) takes shares
-- of the track (0..1) and slides there; bar:cross() flashes the tick to the
-- accent white with a white glow pulse (the crossing moment; the glow is decorative).
function Kit.raceBar(parent: Instance, opts: RaceBarOptions?): RaceBar
	local o: RaceBarOptions = opts or {}
	local h = o.h or 10
	local captionH = if o.caption then Kit.size.caption + Kit.space.xs else 0
	local mark = math.clamp(o.mark or 0.5, 0, 1)
	local root = Kit.dataColor(Kit.box({
		Name = o.name or "RaceBar",
		LayoutOrder = o.order or 0,
		Size = UDim2.new(1, 0, 0, captionH + h + 2 * RACE_OVERHANG),
	})) :: Frame
	local track = Kit.new("Frame", {
		Name = "Track",
		Position = UDim2.fromOffset(0, captionH + RACE_OVERHANG),
		Size = UDim2.new(1, 0, 0, h),
		BackgroundColor3 = Kit.colors.raised,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = root,
	}) :: Frame
	Kit.corner(Kit.radius.pill).Parent = track
	Kit.bevel(track)
	local function segment(name: string, right: boolean): Frame
		local fill = Kit.new("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(if right then 1 else 0, 0),
			Position = UDim2.fromScale(if right then 1 else 0, 0),
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = Kit.colors.muted,
			BorderSizePixel = 0,
			Parent = track,
		}) :: Frame
		Kit.corner(Kit.radius.pill).Parent = fill
		Kit.new("UIGradient", {
			Name = "Depth",
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(RACE_SHADE, RACE_SHADE, RACE_SHADE)),
			Parent = fill,
		})
		return fill
	end
	local left = segment("FillLeft", false)
	local right = segment("FillRight", true)
	local tick = Kit.new("Frame", {
		Name = "Tick",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(mark, 0, 0, captionH),
		Size = UDim2.fromOffset(RACE_TICK_W, h + 2 * RACE_OVERHANG),
		BackgroundColor3 = Kit.colors.text,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = root,
	}) :: Frame
	tick:SetAttribute("Overhang", true)
	Kit.corner(1).Parent = tick
	local caption: TextLabel? = nil
	if o.caption then
		caption = Kit.text(o.caption, {
			Name = "TickCaption",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(mark, 0),
			Size = UDim2.fromOffset(RACE_CAPTION_W, Kit.size.caption + 2),
			Font = Kit.font.hand,
			TextSize = Kit.size.caption,
			TextWrapped = false,
			TextColor3 = Kit.colors.muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = root,
		});
		(caption :: TextLabel):SetAttribute("Overhang", true)
	end
	local bar: RaceBar = {
		root = root,
		track = track,
		left = left,
		right = right,
		tick = tick,
		caption = caption,
		set = function(_self: RaceBar, l: number, r: number)
			local a = math.clamp(l, 0, 1)
			local b = math.clamp(r, 0, 1 - a)
			Motion.tween(left, { Size = UDim2.fromScale(a, 1) }, Motion.t.call, Motion.ease.out)
			Motion.tween(right, { Size = UDim2.fromScale(b, 1) }, Motion.t.call, Motion.ease.out)
		end,
		setColors = function(_self: RaceBar, l: Color3, r: Color3)
			left.BackgroundColor3 = l
			right.BackgroundColor3 = r
		end,
		setMark = function(_self: RaceBar, share: number)
			local m = math.clamp(share, 0, 1)
			tick.Position = UDim2.new(m, 0, 0, captionH)
			if caption then
				caption.Position = UDim2.fromScale(m, 0)
			end
		end,
		cross = function(_self: RaceBar)
			tick.BackgroundColor3 = Kit.colors.accent
			Motion.tween(tick, { BackgroundColor3 = Kit.colors.text }, Motion.t.call, Motion.ease.in_)
			if Motion.headless or Motion.reduced() then
				return
			end
			local pulse =
				Kit.glow(tick, Kit.colors.accent, { px = (h + 2 * RACE_OVERHANG) * 3, transparency = 0.3 })
			if pulse then
				Motion.tween(pulse, { ImageTransparency = 1 }, Motion.t.call, Motion.ease.in_)
				task.delay(Motion.t.call, function()
					pulse:Destroy()
				end)
			end
		end,
	}
	root.Parent = parent
	return bar
end

-- The game's lockup (D-064): the name "LANDSLIDE" in Fredoka One at up to `px`
-- (default Kit.size.wordmark; scaled down to fit a narrow column, never under
-- Kit.size.title) in `text`, lit from the top, a 3 px slate (accentLip) outline,
-- a 6 px `line` drop under it (the button lip, in type) and a soft white glow
-- behind (D-058). Under it, overlapping the name's foot, the tagline "RACE TO
-- 270" on a ribbon tilted -3°: split Cobalt | Crimson (the two default player
-- colors: the race), Fredoka at heading size with a navy outline, a navy edge
-- and a shadow. Returns the Frame "Wordmark" (full width, Kit.wordmarkHeight(px)
-- tall); the name is "Mark" (attribute Wordmark, so the audit knows its size),
-- the ribbon "Ribbon" with its label "Tagline". opts.tagline = false leaves the
-- ribbon out (the frame is then px + 16 tall, as before).
function Kit.wordmark(px: number?, props: { [string]: any }?, opts: { tagline: boolean? }?): Frame
	local size = px or Kit.size.wordmark
	local withTagline = not (opts and opts.tagline == false)
	local markH = size + 2 * Kit.space.sm
	local root = Kit.box(merged({
		Name = "Wordmark",
		Size = UDim2.new(1, 0, 0, Kit.wordmarkHeight(size, withTagline)),
	}, props))
	-- The headline in red marker on the board (D-102, photo 3 of the brief): no
	-- glow, no drop, no outline; the red is a data color (the audit skips it).
	local mark = Kit.dataColor(Kit.text(string.upper(SetupWords.GAME_NAME), {
		Name = "Mark",
		Size = UDim2.new(1, 0, 0, markH),
		Font = Kit.font.display,
		TextSize = size,
		TextScaled = true,
		TextWrapped = false,
		TextColor3 = Kit.color(Colors.player.Crimson),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
		Parent = root,
	}))
	mark:SetAttribute("Wordmark", true)
	Kit.new("UITextSizeConstraint", {
		MinTextSize = Kit.size.title,
		MaxTextSize = size,
		Parent = mark,
	})
	if not withTagline then
		return root
	end
	-- The "ribbon" is now a blue marker underline with the tagline in black
	-- hand-lettering under it.
	local text = string.upper(SetupWords.TAGLINE)
	local chars = utf8.len(text) or #text
	local tagSize = Kit.size.heading
	local width = math.ceil(chars * tagSize * DISPLAY_EM) + 2 * RIBBON_PAD_X
	local ribbon = Kit.new("Frame", {
		Name = "Ribbon",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, markH - RIBBON_OVERLAP),
		Size = UDim2.fromOffset(width, RIBBON_H),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Rotation = RIBBON_TILT,
		ZIndex = 3,
		Parent = root,
	}) :: Frame
	ribbon:SetAttribute("Overhang", true)
	-- Part of the logo: its size is not one of the screen's text sizes (UI audit).
	ribbon:SetAttribute("Lockup", true)
	local underline = Kit.dataColor(Kit.new("Frame", {
		Name = "Underline",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(1, RIBBON_PAD_X, 0, UNDERLINE_PX),
		BackgroundColor3 = Kit.color(Colors.player.Cobalt),
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = ribbon,
	}))
	underline:SetAttribute("Decor", true)
	Kit.corner(UNDERLINE_PX).Parent = underline
	Motion.drawOn(underline, UNDERLINE_DELAY)
	Kit.text(text, {
		Name = "Tagline",
		Position = UDim2.fromOffset(0, UNDERLINE_PX),
		Size = UDim2.new(1, 0, 1, -UNDERLINE_PX),
		Font = Kit.font.hand,
		TextSize = tagSize,
		TextWrapped = false,
		TextColor3 = Kit.colors.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
		Parent = ribbon,
	})
	return root
end

-- The height of Kit.wordmark(px) (default Kit.size.wordmark), with the tagline
-- ribbon unless `tagline` is false.
function Kit.wordmarkHeight(px: number?, tagline: boolean?): number
	local markH = (px or Kit.size.wordmark) + 2 * Kit.space.sm
	if tagline == false then
		return markH
	end
	return markH - RIBBON_OVERLAP + RIBBON_H + RIBBON_SLACK
end

-- An icon in a round `field` plate (default 24 px): the state card's action
-- buttons, the help rows, the settings chips. The icon is two thirds of the plate.
function Kit.iconPlate(name: string, px: number?, color: Color3?): Frame
	local size = px or ICON_PLATE
	local plate = Kit.new("Frame", {
		Name = "IconPlate",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = Kit.colors.field,
		BorderSizePixel = 0,
	}) :: Frame
	Kit.round().Parent = plate
	local icon = Kit.icon(name, math.floor(size * 2 / 3), color)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Parent = plate
	return plate
end

-- Seconds left as "0:34".
function Kit.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return Kit
