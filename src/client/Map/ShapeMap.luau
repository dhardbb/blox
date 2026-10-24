--!strict
-- The real map (docs/DESIGN.md D-070, D-075): every state's true shape from
-- the generated atlases (Shared/UI/MapShape, scripts/mapgen/make.py), tinted by
-- the same rules as the circles (Colors.bandFill toward the public-poll leader,
-- the lean before the first poll), thin dark borders from one overlay image,
-- Alaska and Hawaii in hairline insets under the West, and the nine small
-- Northeast states (MapLayout.LADDER) as callout chips.
--
-- Two layouts (MapShape.layout): "wide" (the box at 1.6, the chips in a column
-- at the right edge) and "tall" (the box at 1.25, the chips in a row under the
-- land), picked from the size of the frame the map sits in (MapShape.fit), so
-- a phone in portrait gets a bigger map. One bracket ties the chips to the
-- coast; a chip's own leader line shows only while it is selected or hovered.
--
-- Each state is an ImageLabel ("Shapes" layer, "Shape<id>") showing its rect
-- of an atlas (ImageRectOffset / ImageRectSize) tinted with ImageColor3. Its
-- label, lens row and marks sit at its anchor (the middle of the biggest circle
-- inside it), in a tap square at least Kit.MAP_NODE_MIN px each way (the
-- TextButton named by the id in "Nodes"); a callout state's tap target is its
-- chip. Under the squares one button covers the whole map ("MapTaps"). Every
-- tap is resolved by the layout: inside a state's outline picks that state, so
-- a neighbor's square never steals it; the chip band picks the nearest chip; a
-- border or the sea goes to the square that was pressed.
--
-- Labels: on a big map the code sits on the anchor and the lens value under it
-- where the state has LENS_ROOM px of room. On a compact map (narrower than
-- COMPACT_W: a phone) each state gets one line: "PA 19", or the value alone
-- where the state is smaller than LENS_ROOM, nudged off its anchor (with a thin
-- leader) rather than over a neighbor's. A chip shows its code and value side
-- by side when it is wide, stacked when it is tall enough, else its code.
-- The Polls lens is one pill per state: the lead, then ▲ momentum and the
-- ground-game pips inside the same pill; nothing of it shows without the lead.
--
-- Selection, an owner's ring and a moved state's halo draw the state's outline
-- ("Outlines" layer: thin rotated frames along the layout's edges; a chip's own
-- border for a callout state); a Mark can dash it (a poll that missed) or draw
-- the state hollow (not called yet). Candidate pins (Map/Pins) stand beside the
-- label: a face at rest, the name tab while their state is selected or when
-- the pin asks for it. The legend row (setLegend) uses the strip under the map.
--
-- Everything else matches NodeMap's API and names (Nodes/<id> with Label, Lens,
-- Arrow; Tags/<id>; PlanBadge; GhostTag), so screens and specs drive both alike.
-- The root is named "NodeMap" (the audit's map rules key on it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local MapShape = require(ReplicatedStorage.Shared.UI.MapShape)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local View = require(ReplicatedStorage.Shared.Sim.View)

local Assets = require(script.Parent.Parent.UI.Assets)
local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.MapInterface)
local Motion = require(script.Parent.Parent.UI.Motion)
local Legend = require(script.Parent.Legend)
local Pins = require(script.Parent.Pins)

local ShapeMap = {}

local MIN_TAP = Kit.MAP_NODE_MIN -- px, smallest tap target per state
ShapeMap.COMPACT_W = MapShape.TALL_BELOW -- px: a map narrower than this labels each state on one line
local COMPACT_W = ShapeMap.COMPACT_W
ShapeMap.LENS_ROOM = 24 -- px, the smallest inner circle that shows a value under (big map) or beside (compact) its code
local LENS_ROOM = ShapeMap.LENS_ROOM
local CHIP_LENS_W = 56 -- px, the narrowest chip that shows a lens value beside its code
local STAR_CHIP = 12 -- px more a chip needs to keep a battleground value's ★ beside its code
local LABEL_MIN, LABEL_MAX = 14, 22 -- px, the code label's height range on a big map
local COMPACT_MIN, COMPACT_MAX = 12, 16 -- px, ... on a compact map
local CHIP_LABEL_MIN = 12 -- px, a stacked chip's code at least
local LABEL_SHARE = 0.4 -- the label's height, share of the state's inner circle
local PART_H = Kit.size.caption + 2 -- px, a lens plate's height
local DISC = 24 -- px, an icon part's disc (a lens slot that holds a 20 px icon)
local DISC_ICON = 20 -- px, the icon on it
local PART_PAD = 3 -- px, a lens pill's side padding
local PART_GAP = 2 -- px, between two lens pills (and a lead and its suffix)
local ROW_PAD = 2 -- px, a Polls pill's padding around its lead and suffix
local UNIT_GAP = 2 -- px, between a compact label's code and its value
local UNIT_MARGIN = 1.5 -- px, a compact label's clearance from its neighbors (text widths are estimates)
local ROW_GAP = 1 -- px, between a stacked chip's code and its value
local PIP = 6 -- px, one ground-game pip on a phone's map
local PIP_BIG = 9 -- px, ... at most, on a big map
local PIP_SHARE = 0.011 -- a pip's size, share of the map's width (between the two)
local PIP_GAP = 2 -- px, between pips
local PIP_RUN_GAP = 4 -- px, between your pips and theirs
local PIP_MAX = 6 -- pips drawn per run (GOTV max units is 4, 6 for one candidate)
local OUTLINE_PX = 2 -- an owner's or a halo's outline, a missed poll's dashes
local SELECTED_PX = 3 -- the selected state's accent outline (and a flip's)
local HAIRLINE_PX = 1 -- an uncalled state's outline, the insets' boxes
local DASH_EVERY = 2 -- a dashed outline shows one segment in this many
local CHIP_RING_PX = 1 -- a chip's resting edge
local CHIP_PAD_X, CHIP_PAD_Y = 2, 2 -- px between a chip and its cell's edges
local CHIP_RADIUS = 6 -- px, a chip's corners
local LEADER_PX = 1 -- the callout bracket
local SELECT_LEADER_PX = 2 -- a selected or hovered chip's leader to its state
local BRACKET_FADE = 0.4 -- the bracket's transparency
local INSET_FADE = 0.55 -- the Alaska and Hawaii boxes' transparency
local ROUTE_PX = 2 -- the planned route: thin and dim, under every mark
local ROUTE_FADE = 0.5 -- its transparency (a flight's: ROUTE_FLIGHT)
local ROUTE_FLIGHT = 0.75
local MARK_GAP = 2 -- px between a code and a mark beside it
local GRID = 48 -- px, the mark layout's lookup cells
local MARK_LEADER_FADE = 0.5 -- a mark leader's transparency
local CODE_COST = 1000 -- layout score per px² of a mark over a code or off the map
local MARK_COST = 20 -- ... per px² over another mark
local FAR_COST = 40 -- ... for each step farther from the code
local NUDGES = { 3, 6, 10, 15, 21, 28 } -- px a compact label may move off its anchor
local NUDGE_COST = 25 -- layout score per px a compact label moves
local SMALL_REACH = 10 -- px a small state's full line ("PA 19") may move; farther, it shows its value alone
local CODE_CHAR = 0.72 -- a code character's width, share of its height (bold capitals)
local PART_CHAR = 8 -- px, an estimated character of a lens value (Fredoka 14)
local TAG_CHAR = 8 -- px, ... of a tag
local TAG_H = Kit.size.caption + 5 -- px, the tag's height
local TAG_PAD = 4 -- px, the tag's side padding
local TAG_RADIUS = 6 -- px, a tag's and a lens plate's corners
local PLAN_BADGE_PX = 16 -- px, the planned-action badge
local DIM_FILL = 0.4 -- shape transparency of a dimmed state: 60 % of its band fill (D-075)
local QUIET_FILL = 0.6 -- ... of a state the Close filter quiets: 40 % (D-075)
local HOLLOW_FILL = 0.35 -- ... of a state not called yet (filled with the stage's field color)
local DIM_TEXT = 0.3 -- label transparency of a dimmed state
local TOP_SHADE = 0.18 -- the shape's transparency at its bottom (a top light over the navy)
local BORDER_FADE = 0 -- the border overlay's transparency
local LABEL_STROKE = 0.4 -- the code's dark outline, so it reads on a pale fill
local PART_EDGE = 0.5 -- a lens plate's hairline transparency
local PART_BG = 0 -- a lens plate's backing transparency at rest
local FLIP_EDGE = 2 -- px, a note tag's edge in its color
local GHOST_STROKE = 0.5
local GHOST_BG = 0.3
local PULSE_FROM = 1.08 -- a pulse's starting scale (a shape is big: a small bump)
local RING_DRAW = 0.1 -- s, the selected outline drawing in
local LENS_FADE = 0.15 -- s, the lens pills fading in on a lens switch
local FILL_TWEEN = Motion.t.beat -- s, a fill changing color during a reveal
local STAGE_GLOW = 1.35 -- the board's backdrop glow, share of the map
local STAGE_GLOW_FADE = 0.3
local SELECT_GLOW = 1.5 -- the selected state's accent glow, share of its rect
local SELECT_GLOW_FADE = 0.15
local SELECT_GLOW_DIM = 0.45
local SELECT_BREATH = 0.9 -- s, one breath of the selected glow (decorative)
local HALO_PAD = 3 -- px, a moved callout state's plate around its chip
local HALO_SOFT = 0.55 -- the plate's transparency for a state that moves
local HALO_STRONG = 0.25 -- ... for a state whose poll leader changes
local BLOOM_SCALE = 1.6 -- a moved state's bloom, share of its rect
local BLOOM_SOFT = 0.4
local BLOOM_STRONG = 0.1
local PIN_MIN, PIN_MAX = 14, 20 -- px, a pin's face
local PIN_SHARE = 0.03 -- the face's size, share of the map's width
local PIN_YOU = 2 -- px more your own pin's face is (it is drawn on top, too)
local ARROWS = { up = "▲", down = "▼" }
local PREVIEW_BG = 0.35 -- the plan preview tag's backing transparency (a ghost)
local PREVIEW_TEXT = 0.1 -- ... its number's transparency
local PREVIEW_EDGE = 0.45 -- ... its edge's transparency
local ARROW_PX = 18 -- px, a mark's arrow box
local GLYPH_NOTES = { ["▲"] = true, ["▼"] = true } -- notes drawn in their color (a flip's direction)

type Part = { label: TextLabel, edge: UIStroke, icon: GuiObject? }

-- Where the last mark layout put a state's code and lens row (px from its anchor).
type Place = {
	code: boolean,
	codeX: number,
	codeY: number,
	row: boolean,
	rowX: number,
	rowY: number,
	rowW: number,
	rowH: number,
}

type Node = {
	id: string,
	ev: number,
	shape: MapShape.Shape,
	ladder: boolean,
	lx: number, -- label anchor, box fractions
	ly: number,
	ax: number, -- the tap square's AnchorPoint (it grows from there when the 36 px minimum applies)
	ay: number,
	sx: number, -- the tap square's laid-out size, box fractions
	sy: number,
	image: ImageLabel,
	hit: TextButton,
	chip: Frame?,
	chipStroke: UIStroke?,
	label: TextLabel,
	halo: Frame?,
	lensRow: Frame,
	rowEdge: UIStroke,
	parts: { Part },
	up: TextLabel,
	pips: Frame,
	arrow: TextLabel,
	badge: TextLabel,
	badgeStroke: UIStroke,
	outline: Frame?,
	outlineParts: { Frame },
	preview: TextLabel?, -- the plan preview's tag (D-071), made on first use
	bloom: ImageLabel?,
	wantRow: boolean, -- the lens line has something to show here
	rowKey: string, -- what the lens row shows (the layout redoes itself when it changes)
	rowW: number, -- px, the row's estimated size
	rowH: number,
	place: Place?,
}

-- Every atlas and the borders uploaded (in `assets`, default UI/Assets): the
-- real map can show. Otherwise NodeMap.new() keeps the circles.
function ShapeMap.ready(assets: { [string]: Assets.Asset }?): boolean
	local list: any = assets or Assets
	for k in MapShape.data.atlases do
		local asset = list[`mapStates{k}`]
		if asset == nil or asset.id == "" then
			return false
		end
	end
	local borders = list.mapBorders
	return borders ~= nil and borders.id ~= ""
end

local function assetId(name: string): string
	local asset = (Assets :: any)[name]
	return if asset then asset.id else ""
end

-- The edge of a solid tag in `fill` (as NodeMap's).
local function edgeOf(fill: Color3): Color3
	if fill == Kit.colors.loss then
		return Kit.colors.lossEdge
	elseif fill == Kit.colors.text then
		return Kit.colors.line
	end
	return Kit.color(Colors.tint(Kit.rgb(fill), Colors.background, 0.35))
end

-- The readable text on a solid `fill`.
local function onFill(fill: Color3): Color3
	if fill == Kit.colors.loss then
		return Kit.colors.onLoss
	end
	return Kit.color(Colors.onColor(Kit.rgb(fill)))
end

-- A thin rotated frame from (x1, y1) to (x2, y2) in box fractions of a box at
-- `aspect`, `px` thick and `px` longer than the gap (so joints close).
local function segment(
	parent: Instance,
	aspect: number,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	px: number,
	color: Color3,
	name: string?
): Frame
	local dx = x2 - x1
	local dy = (y2 - y1) / aspect -- in box-width units
	local length = math.sqrt(dx * dx + dy * dy)
	return Kit.new("Frame", {
		Name = name or "Segment",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2),
		Size = UDim2.new(length, px, 0, px),
		Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	})
end

-- A dark field plate with a hairline and a Fredoka value (as NodeMap's).
local function newPart(row: Frame, k: number): Part
	local label = Kit.text("", {
		Name = `Part{k}`,
		LayoutOrder = 2 * k, -- an inline icon goes just before it (2k - 1)
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, PART_H),
		TextSize = Kit.size.caption,
		Font = Kit.font.display,
		BackgroundColor3 = Kit.colors.field,
		BackgroundTransparency = PART_BG,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		ZIndex = 6,
		Parent = row,
	})
	Kit.new("UICorner", { CornerRadius = UDim.new(0, TAG_RADIUS), Parent = label })
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, PART_PAD),
		PaddingRight = UDim.new(0, PART_PAD),
		Parent = label,
	})
	local edge = Kit.stroke(Kit.colors.line, 1)
	edge.Name = "Edge"
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Transparency = PART_EDGE
	edge.Parent = label
	return { label = label, edge = edge, icon = nil }
end

local function hrow(name: string, height: number, parent: Instance): Frame
	local row = Kit.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		BackgroundColor3 = Kit.colors.field,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, height),
		ZIndex = 6,
		Visible = false,
		Parent = parent,
	})
	row:SetAttribute("Overhang", true) -- a value may reach past a small state's square
	local list = Kit.list("Horizontal", PART_GAP)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = row
	return row
end

-- An estimated text width (layout only; AutomaticSize draws it).
local function textW(text: string, perChar: number): number
	return (utf8.len(text) or #text) * perChar
end

function ShapeMap.new(): MapInterface.Map
	local geo: MapShape.Layout = MapShape.layout("wide")
	local root = Kit.new("Frame", {
		Name = "NodeMap",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = false,
	})
	root:SetAttribute("Shapes", true)
	root:SetAttribute("Layout", geo.kind)
	local aspectBox = Kit.new("UIAspectRatioConstraint", { AspectRatio = geo.aspect, Parent = root })

	local stage = Kit.glow(root, Kit.colors.glow, {
		scale = STAGE_GLOW,
		transparency = STAGE_GLOW_FADE,
		stretch = true,
	})
	if stage then
		stage.Name = "StageGlow"
	end
	local glowLayer = Kit.box({ Name = "Shadows", ZIndex = 1, Parent = root })
	local shapeLayer = Kit.dataColor(Kit.box({ Name = "Shapes", ZIndex = 2, Parent = root }))
	local borderLayer = Kit.box({ Name = "Borders", ZIndex = 3, Parent = root })
	local outlineLayer = Kit.box({ Name = "Outlines", ZIndex = 4, Parent = root })
	local leaders = Kit.box({ Name = "Leaders", ZIndex = 4, Parent = root })
	local routeLayer = Kit.box({ Name = "Route", ZIndex = 4, Parent = root })
	local markLeaders = Kit.box({ Name = "MarkLeaders", ZIndex = 5, Parent = root })
	local nodeLayer = Kit.box({ Name = "Nodes", ZIndex = 6, Parent = root })
	local tagLayer = Kit.box({ Name = "Tags", ZIndex = 7, Parent = root })
	local pinLayer = Kit.box({ Name = "Pins", ZIndex = 8, Parent = root })
	local legendLayer = Legend.new(root, geo.legend)
	-- The plan preview (D-071) on top of everything, so it reads in every lens.
	local previewLayer = Kit.box({ Name = "Preview", ZIndex = 9, Parent = root })

	local selectGlow =
		Kit.glow(glowLayer, Kit.colors.accent, { transparency = SELECT_GLOW_FADE, stretch = true })
	if selectGlow then
		selectGlow.Name = "SelectGlow"
		selectGlow.Visible = false
	end
	local stopBreath: () -> () = function() end

	-- The borders: one white-lines image over the land, tinted the stage navy.
	local borders = Kit.new("ImageLabel", {
		Name = "BorderLines",
		BackgroundTransparency = 1,
		Image = assetId("mapBorders"),
		ImageColor3 = Kit.colors.background,
		ImageTransparency = BORDER_FADE,
		ScaleType = Enum.ScaleType.Stretch,
		Parent = borderLayer,
	})
	borders:SetAttribute("Asset", "mapBorders")
	borders:SetAttribute("Decor", true)

	-- Alaska's and Hawaii's inset boxes: hairlines, so the two read as insets.
	local insetFrames: { [string]: Frame } = {}
	for _, id in { "AK", "HI" } do
		local frame = Kit.box({ Name = `Inset{id}`, Parent = borderLayer })
		frame:SetAttribute("Decor", true)
		Kit.new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = frame })
		local edge = Kit.stroke(Kit.colors.line, HAIRLINE_PX)
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Transparency = INSET_FADE
		edge.Parent = frame
		insetFrames[id] = frame
	end

	local nodes: { Node } = {}
	local byId: { [string]: Node } = {}
	local handlers: { (string) -> () } = {}
	local selected: string? = nil
	local hovered: string? = nil
	local marks: { [string]: MapInterface.Mark } = {}
	local lens: { [string]: MapInterface.LensLine } = {}
	local fills: { [string]: Color3 } = {}
	local tweening: { [string]: number } = {} -- state -> the fill tween running on it (a token)
	local pins: { MapInterface.Pin } = {}
	local previews: { [string]: MapInterface.PreviewTag } = {}
	local lastWidth = -1
	local connections: { any } = {}

	-- The box's size, read once per update (every px rule below needs it).
	local cachedSize: Vector2? = nil
	local function sizeNow(): Vector2
		return cachedSize or root.AbsoluteSize
	end

	local function widthPx(): number
		return sizeNow().X
	end

	-- The box in px, as its children are laid out.
	local function boxPx(): (number, number)
		local size = sizeNow()
		return size.X, size.Y
	end

	-- The box as drawn (the aspect constraint already fits AbsoluteSize; this
	-- keeps the mark layout honest if it ever does not).
	local function boxDims(): (number, number)
		local bw, bh = boxPx()
		local w = math.min(bw, bh * geo.aspect)
		return w, w / geo.aspect
	end

	-- A phone-size map: one line per state (see the header).
	local function compact(): boolean
		local w = widthPx()
		return w > 0 and w < COMPACT_W
	end

	local function fire(id: string?)
		if id == nil then
			return
		end
		for _, handler in handlers do
			task.spawn(handler, id)
		end
	end

	-- Where a tap landed, in box fractions, or nil when the input has no
	-- position (a keyboard or gamepad press, the headless engine). The app's
	-- ScreenGui ignores the top bar inset while InputObject.Position counts it
	-- (docs: InputObject.Position), so the inset is added back there.
	local function tapPoint(input: any): (number?, number?)
		if typeof(input) ~= "Instance" and type(input) ~= "table" then
			return nil, nil
		end
		local ok, position, kind = pcall(function()
			return input.Position, input.UserInputType
		end)
		if not ok or position == nil then
			return nil, nil
		end
		-- Only a click or a touch has a place; a gamepad's A press picks its square.
		if kind ~= nil and kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return nil, nil
		end
		local x, y = position.X, position.Y
		local gui = root:FindFirstAncestorWhichIsA("ScreenGui")
		if gui and gui.IgnoreGuiInset then
			local inset = game:GetService("GuiService"):GetGuiInset()
			x += inset.X
			y += inset.Y
		end
		local bw, bh = boxPx()
		if bw <= 0 then
			return nil, nil
		end
		local at = root.AbsolutePosition
		return (x - at.X) / bw, (y - at.Y) / bh
	end

	-- A press on `pressed` (a state's square, or nil for open map).
	local function press(pressed: string?, input: any)
		local x, y = tapPoint(input)
		if x == nil or y == nil or x < 0 or x > 1 or y < 0 or y > 1 then
			fire(pressed)
			return
		end
		fire(geo.resolve(x, y, pressed))
	end

	local taps = Kit.new("TextButton", {
		Name = "MapTaps",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Selectable = false, -- gamepad selection walks the states' squares
		ZIndex = 1,
		Parent = nodeLayer,
	})
	taps.Activated:Connect(function(input: any)
		press(nil, input)
	end)

	-- The bracket that ties the chips to the coast, and the selected (or
	-- hovered) chip's own leader to its state.
	local function drawLeaders()
		for _, child in leaders:GetChildren() do
			child:Destroy()
		end
		for k, line in geo.bracket do
			for i = 1, #line - 3, 2 do
				local piece = segment(
					leaders,
					geo.aspect,
					line[i],
					line[i + 1],
					line[i + 2],
					line[i + 3],
					LEADER_PX,
					Kit.colors.line,
					`Bracket{k}_{i}`
				)
				piece.BackgroundTransparency = BRACKET_FADE
			end
		end
		for _, id in { hovered, selected } do
			local path = if id then geo.leader(id) else nil
			if id and path then
				for i = 1, #path - 3, 2 do
					segment(
						leaders,
						geo.aspect,
						path[i],
						path[i + 1],
						path[i + 2],
						path[i + 3],
						SELECT_LEADER_PX,
						Kit.colors.accent,
						`Leader{id}`
					)
				end
			end
		end
	end

	-- Squares: biggest first, so the smaller of two overlapping squares is on top;
	-- chips last (on top of everything).
	local order = table.clone(MapShape.list())
	table.sort(order, function(a: MapShape.Shape, c: MapShape.Shape): boolean
		local ca, cc = a.chip ~= nil, c.chip ~= nil
		if ca ~= cc then
			return cc
		end
		if a.room ~= c.room then
			return a.room > c.room
		end
		return a.id < c.id
	end)

	for _, shape in order do
		local id = shape.id
		local atlas = MapShape.data.atlases[shape.atlas]
		local image = Kit.new("ImageLabel", {
			Name = `Shape{id}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Image = assetId(`mapStates{shape.atlas}`),
			ImageRectOffset = Vector2.new(shape.ox, shape.oy),
			ImageRectSize = Vector2.new(shape.ow, shape.oh),
			ImageColor3 = Kit.color(Colors.neutral),
			ScaleType = Enum.ScaleType.Stretch,
			Parent = shapeLayer,
		})
		image:SetAttribute("Asset", "mapShape")
		image:SetAttribute("MapShape", id)
		image:SetAttribute("Atlas", atlas and atlas.file or "")
		Kit.new("UIGradient", {
			Name = "Depth",
			Rotation = 90,
			Transparency = NumberSequence.new(0, TOP_SHADE),
			Parent = image,
		})

		local chip = shape.chip
		local hit: TextButton = Kit.new("TextButton", {
			Name = id,
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = if chip then 3 else 2,
			Parent = nodeLayer,
		})
		Kit.new("UISizeConstraint", { MinSize = Vector2.new(MIN_TAP, MIN_TAP), Parent = hit })

		local chipFrame: Frame? = nil
		local chipStroke: UIStroke? = nil
		local halo: Frame? = nil
		if chip then
			local frame = Kit.dataColor(Kit.new("Frame", {
				Name = "Chip",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -2 * CHIP_PAD_X, 1, -2 * CHIP_PAD_Y),
				BackgroundColor3 = Kit.color(Colors.neutral),
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = hit,
			})) :: Frame
			Kit.new("UICorner", { CornerRadius = UDim.new(0, CHIP_RADIUS), Parent = frame })
			Kit.new("UIGradient", {
				Name = "Depth",
				Rotation = 90,
				Transparency = NumberSequence.new(0, TOP_SHADE),
				Parent = frame,
			})
			local stroke = Kit.stroke(Kit.color(Colors.undecided), CHIP_RING_PX)
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = frame
			chipFrame, chipStroke = frame, stroke
			-- A moved callout state: a plate in the mover's color glows around its chip.
			local plate = Kit.new("Frame", {
				Name = "Halo",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, 2 * HALO_PAD, 1, 2 * HALO_PAD),
				BackgroundColor3 = Kit.colors.accent,
				BackgroundTransparency = HALO_SOFT,
				BorderSizePixel = 0,
				ZIndex = 2,
				Visible = false,
				Parent = hit,
			})
			plate:SetAttribute("Overhang", true)
			Kit.new("UICorner", { CornerRadius = UDim.new(0, CHIP_RADIUS + 2), Parent = plate })
			halo = plate
		end

		local label = Kit.text(id, {
			Name = "Label",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, LABEL_MIN),
			TextScaled = true,
			TextSize = Kit.size.heading,
			Font = Kit.font.bold,
			TextStrokeColor3 = Kit.colors.background,
			TextStrokeTransparency = LABEL_STROKE,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			ZIndex = 5,
			Parent = hit,
		})
		label:SetAttribute("Overhang", true)

		-- The lens row: the value pills, then (Polls) ▲ momentum and the pips,
		-- all on one plate when there is a suffix (one pill per state).
		local lensRow = hrow("Lens", PART_H, hit)
		Kit.new("UICorner", { CornerRadius = UDim.new(0, TAG_RADIUS), Parent = lensRow })
		Kit.new("UIPadding", {
			PaddingLeft = UDim.new(0, ROW_PAD),
			PaddingRight = UDim.new(0, ROW_PAD),
			Parent = lensRow,
		})
		local rowEdge = Kit.stroke(Kit.colors.line, 1)
		rowEdge.Name = "Edge"
		rowEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rowEdge.Transparency = PART_EDGE
		rowEdge.Enabled = false
		rowEdge.Parent = lensRow
		local up = Kit.text("", {
			Name = "Momentum",
			LayoutOrder = 50,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, PART_H),
			TextSize = Kit.size.caption,
			Font = Kit.font.bold,
			TextStrokeColor3 = Kit.colors.background,
			TextStrokeTransparency = 0.2,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			ZIndex = 6,
			Visible = false,
			Parent = lensRow,
		})
		Kit.dataColor(up)
		local pipRow = Kit.dataColor(Kit.box({
			Name = "Pips",
			LayoutOrder = 51,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, PIP),
			Visible = false,
			Parent = lensRow,
		})) :: Frame
		local pipList = Kit.list("Horizontal", PIP_GAP)
		pipList.VerticalAlignment = Enum.VerticalAlignment.Center
		pipList.Parent = pipRow

		-- A mark's arrow: right of the code (a chip: left of the chip, toward the coast).
		local arrow = Kit.text("", {
			Name = "Arrow",
			AnchorPoint = if chip then Vector2.new(1, 0.5) else Vector2.new(0, 0.5),
			Position = if chip then UDim2.new(0, -CHIP_PAD_X, 0.5, 0) else UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(ARROW_PX, ARROW_PX),
			TextScaled = true,
			TextSize = Kit.size.caption,
			Font = Kit.font.bold,
			TextStrokeColor3 = Kit.colors.background,
			TextStrokeTransparency = 0.3,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			ZIndex = 6,
			Visible = false,
			Parent = label,
		})
		arrow:SetAttribute("Overhang", true)

		local badge = Kit.text("", {
			Name = id,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, TAG_H),
			AnchorPoint = Vector2.new(0.5, 1),
			TextSize = Kit.size.caption,
			Font = Kit.font.display,
			TextColor3 = Kit.colors.onAccent,
			BackgroundColor3 = Kit.colors.accent,
			BackgroundTransparency = 0,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			Visible = false,
			Parent = tagLayer,
		})
		Kit.new("UICorner", { CornerRadius = UDim.new(0, TAG_RADIUS), Parent = badge })
		Kit.new("UIPadding", {
			PaddingLeft = UDim.new(0, TAG_PAD),
			PaddingRight = UDim.new(0, TAG_PAD),
			Parent = badge,
		})
		local badgeStroke = Kit.stroke(Kit.colors.accentEdge, 1)
		badgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		badgeStroke.Parent = badge

		local record = StateData.byId[id]
		local node: Node = {
			id = id,
			ev = if record then record.ev else 0,
			shape = shape,
			ladder = chip ~= nil,
			lx = 0,
			ly = 0,
			ax = 0.5,
			ay = 0.5,
			sx = 0,
			sy = 0,
			image = image,
			hit = hit,
			chip = chipFrame,
			chipStroke = chipStroke,
			label = label,
			halo = halo,
			lensRow = lensRow,
			rowEdge = rowEdge,
			parts = {},
			up = up,
			pips = pipRow,
			arrow = arrow,
			badge = badge,
			badgeStroke = badgeStroke,
			outline = nil,
			outlineParts = {},
			preview = nil,
			bloom = nil,
			wantRow = false,
			rowKey = "",
			rowW = 0,
			rowH = PART_H,
			place = nil,
		}
		table.insert(nodes, node)
		byId[id] = node
		hit.Activated:Connect(function(input: any)
			press(id, input)
		end)
		if chip then
			-- A chip's leader also shows while the pointer is over it (desktop).
			pcall(function()
				table.insert(
					connections,
					(hit :: any).MouseEnter:Connect(function()
						hovered = id
						drawLeaders()
					end)
				)
				table.insert(
					connections,
					(hit :: any).MouseLeave:Connect(function()
						if hovered == id then
							hovered = nil
							drawLeaders()
						end
					end)
				)
			end)
		end
	end

	-- ---------------------------------------------------------------- layouts

	-- Puts a node's sprite, tap square and tag where the current layout has them.
	local function placeNode(node: Node)
		local shape = geo.get(node.id) :: MapShape.Shape
		node.shape = shape
		local chip = shape.chip
		local lx, ly = geo.labelAt(node.id)
		-- The tap square: a callout's chip cell, else a square on the anchor the
		-- inner circle's size; 36 px at least, growing inward at the map's edges
		-- (the anchor is the square's place in its free range) so it never pokes out.
		local sx = if chip then chip.w else shape.room
		local sy = if chip then chip.h else shape.room * geo.aspect
		local ax = math.clamp((lx - sx / 2) / math.max(1 - sx, 1e-6), 0, 1)
		local ay = math.clamp((ly - sy / 2) / math.max(1 - sy, 1e-6), 0, 1)
		node.lx, node.ly, node.sx, node.sy, node.ax, node.ay = lx, ly, sx, sy, ax, ay
		node.image.Position = UDim2.fromScale(shape.x + shape.w / 2, shape.y + shape.h / 2)
		node.image.Size = UDim2.fromScale(shape.w, shape.h)
		node.hit.AnchorPoint = Vector2.new(ax, ay)
		node.hit.Position = UDim2.fromScale(lx + (ax - 0.5) * sx, ly + (ay - 0.5) * sy)
		node.hit.Size = UDim2.fromScale(sx, sy)
		node.badge.Position = UDim2.fromScale(lx, ly)
		node.place = nil
		-- Outlines and blooms follow the shape: made again on next use.
		if node.outline then
			(node.outline :: Frame):Destroy()
			node.outline = nil
			table.clear(node.outlineParts)
		end
		if node.bloom then
			(node.bloom :: ImageLabel):Destroy()
			node.bloom = nil
		end
	end

	local lastSignature = ""
	local lastPins = ""

	local function placeAll()
		root:SetAttribute("Layout", geo.kind)
		aspectBox.AspectRatio = geo.aspect
		local land = geo.land
		borders.Position = UDim2.fromScale(land.x, land.y)
		borders.Size = UDim2.fromScale(land.w, land.h)
		local legendRect = geo.legend
		legendLayer.Position = UDim2.fromScale(legendRect.x, legendRect.y)
		legendLayer.Size = UDim2.fromScale(legendRect.w, legendRect.h)
		for id, frame in insetFrames do
			local box = geo.insets[id]
			frame.Visible = box ~= nil
			if box then
				frame.Position = UDim2.fromScale(box.x, box.y)
				frame.Size = UDim2.fromScale(box.w, box.h)
			end
		end
		for _, node in nodes do
			placeNode(node)
		end
		drawLeaders()
		for _, child in markLeaders:GetChildren() do
			child:Destroy()
		end
		lastSignature = ""
		lastPins = ""
	end
	placeAll()

	-- The layout the map's room calls for: MapShape.fit on the box its Size
	-- gives it in its parent (before the aspect constraint fits it).
	local function wantedKind(): MapShape.Kind
		local parent = root.Parent
		if parent and parent:IsA("GuiObject") then
			local size = (parent :: GuiObject).AbsoluteSize
			local s = root.Size
			local w = size.X * s.X.Scale + s.X.Offset
			local h = size.Y * s.Y.Scale + s.Y.Offset
			if w > 0 and h > 0 then
				local kind: MapShape.Kind = MapShape.fit(w, h)
				return kind
			end
		end
		return geo.kind
	end

	local paintAll: () -> ()

	-- Runs one update with the box's size read once (after switching layouts
	-- if the frame now calls for the other one: then everything repaints).
	local function measured(work: () -> ())
		local outer = cachedSize
		local kind: MapShape.Kind = wantedKind()
		local switched = kind ~= geo.kind
		if switched then
			geo = MapShape.layout(kind)
			placeAll()
		end
		cachedSize = root.AbsoluteSize
		work()
		if switched then
			paintAll()
		end
		cachedSize = outer
	end

	-- ---------------------------------------------------------------- pixel layout

	local function roomPx(node: Node): number
		local w = widthPx()
		if w <= 0 then
			return 60 -- before the first layout: assume a roomy map
		end
		return node.shape.room * w
	end

	-- The label's height for this state at the map's current size.
	local function labelPx(node: Node): number
		if node.ladder then
			return LABEL_MIN
		end
		local lo, hi = LABEL_MIN, LABEL_MAX
		if compact() then
			lo, hi = COMPACT_MIN, COMPACT_MAX
		end
		return math.clamp(math.floor(roomPx(node) * LABEL_SHARE), lo, hi)
	end

	-- The tap square's laid-out size in px, and whether the 36 px minimum grew
	-- it in each direction.
	local function natural(node: Node): (number, number, boolean, boolean)
		local bw, bh = boxPx()
		local w, h = node.sx * bw, node.sy * bh
		return w, h, bw > 0 and w < MIN_TAP, bh > 0 and h < MIN_TAP
	end

	-- A spot in the node's tap square: `fx` across its laid-out width (0.5: the
	-- anchor) and `dy` px down from the anchor. A square the 36 px minimum grew
	-- is measured from its AnchorPoint, where the laid-out square and the grown
	-- one agree; one that did not grow is measured in scale only.
	local function onAnchor(node: Node, fx: number, dy: number): UDim2
		local w, h, growX, growY = natural(node)
		local x = if growX then UDim.new(node.ax, (fx - node.ax) * w) else UDim.new(fx, 0)
		local y = if growY then UDim.new(node.ay, (0.5 - node.ay) * h + dy) else UDim.new(0.5, dy)
		return UDim2.new(x, y)
	end

	-- `dx`, `dy` px from the node's anchor, inside its tap square.
	local function onAnchorAt(node: Node, dx: number, dy: number): UDim2
		local at = onAnchor(node, 0.5, dy)
		return UDim2.new(at.X.Scale, at.X.Offset + dx, at.Y.Scale, at.Y.Offset)
	end

	-- A share of the laid-out width as a size (px when the square grew).
	local function across(node: Node, share: number, pad: number): UDim
		local w, _, growX = natural(node)
		return if growX then UDim.new(0, share * w - pad) else UDim.new(share, -pad)
	end

	-- The code's width in px (its two letters at the label's size).
	local function codeWidth(node: Node): number
		local lh = labelPx(node)
		return math.ceil((utf8.len(node.id) or 2) * math.min(lh, Kit.size.heading) * CODE_CHAR) + 2
	end

	-- The chip's size in px, from its cell (not its tap square, which may be bigger).
	local function chipPx(node: Node): (number, number)
		local w, h = natural(node)
		if w <= 0 then
			return 40, 24
		end
		return w - 2 * CHIP_PAD_X, h - 2 * CHIP_PAD_Y
	end

	local function outlineOf(node: Node): Frame
		local existing = node.outline
		if existing then
			return existing
		end
		local frame = Kit.box({ Name = `Outline{node.id}`, Visible = false, Parent = outlineLayer })
		for r, ring in node.shape.edges do
			local n = #ring
			for i = 1, n, 2 do
				local j = if i + 2 > n then 1 else i + 2
				table.insert(
					node.outlineParts,
					segment(
						frame,
						geo.aspect,
						ring[i],
						ring[i + 1],
						ring[j],
						ring[j + 1],
						OUTLINE_PX,
						Kit.colors.accent,
						`E{r}_{i}`
					)
				)
			end
		end
		node.outline = frame
		return frame
	end

	-- The state's outline in `color` (nil: none), `px` thick; `dashed` shows
	-- one segment in DASH_EVERY; `fade` its transparency.
	local function setOutline(node: Node, color: Color3?, px: number, dashed: boolean?, fade: number?)
		if node.ladder then
			local stroke = node.chipStroke :: UIStroke
			stroke.Color = color or Kit.color(Colors.undecided)
			stroke.Thickness = if color then px else CHIP_RING_PX
			stroke.Transparency = fade or 0
			return
		end
		if color == nil then
			if node.outline then
				(node.outline :: Frame).Visible = false
			end
			return
		end
		local frame = outlineOf(node)
		frame.Visible = true
		for k, part in node.outlineParts do
			part.BackgroundColor3 = color
			part.BackgroundTransparency = fade or 0
			part.Visible = not dashed or k % DASH_EVERY == 1
			local size = part.Size
			part.Size = UDim2.new(size.X.Scale, px, 0, px)
		end
	end

	local function bloomOf(node: Node): ImageLabel?
		if node.bloom then
			return node.bloom
		end
		local s = node.shape
		local glow = Kit.glow(glowLayer, Kit.colors.accent, { transparency = BLOOM_SOFT, stretch = true })
		if glow then
			glow.Name = `Bloom{node.id}`
			glow.Position = UDim2.fromScale(s.x + s.w / 2, s.y + s.h / 2)
			glow.Size = UDim2.fromScale(s.w * BLOOM_SCALE, s.h * BLOOM_SCALE)
			glow.Visible = false
		end
		node.bloom = glow
		return glow
	end

	-- Puts a node's code and lens row where the last layout placed them (a
	-- callout state's are set by paintLens).
	local function applyPlace(node: Node)
		if node.ladder then
			return
		end
		local place = node.place
		local lh = labelPx(node)
		node.label.Size = UDim2.fromOffset(codeWidth(node), lh)
		if place == nil then
			node.label.Visible = true
			node.label.Position = onAnchor(node, 0.5, 0)
			-- Hidden until the layout finds the row a spot (next frame).
			node.lensRow.Visible = false
			return
		end
		node.label.Visible = place.code
		node.label.Position = onAnchorAt(node, place.codeX, place.codeY)
		node.lensRow.Visible = place.row and node.wantRow
		node.lensRow.Size = UDim2.fromOffset(place.rowW, place.rowH)
		node.lensRow.Position = onAnchorAt(node, place.rowX, place.rowY)
	end

	-- The pips of `runs`, `pipPx` each, into the row's Pips frame; returns their width.
	local function fillPips(node: Node, runs: { MapInterface.Pips }, pipPx: number): number
		for _, child in node.pips:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		node.pips.Size = UDim2.fromOffset(0, pipPx)
		local slot, width = 0, 0
		for r, run in runs do
			if r > 1 then
				slot += 1
				local gap = PIP_RUN_GAP - 2 * PIP_GAP
				Kit.box({
					Name = "Gap",
					LayoutOrder = slot,
					Size = UDim2.fromOffset(gap, pipPx),
					Parent = node.pips,
				})
				width += gap + PIP_GAP
			end
			for _ = 1, math.min(run.count, PIP_MAX) do
				slot += 1
				local pip = Kit.new("Frame", {
					Name = if run.hollow then "Theirs" else "Yours",
					LayoutOrder = slot,
					Size = UDim2.fromOffset(pipPx, pipPx),
					BackgroundColor3 = run.color,
					BackgroundTransparency = if run.hollow then 1 else 0,
					BorderSizePixel = 0,
					ZIndex = 6,
					Parent = node.pips,
				})
				Kit.round().Parent = pip
				local edge = Kit.stroke(if run.hollow then run.color else Kit.colors.background, 1.5)
				edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				edge.Parent = pip
				width += pipPx + PIP_GAP
			end
		end
		return math.max(0, width - PIP_GAP)
	end

	-- Fills a node's lens row from `line`: the value pills and, on Polls, the
	-- ▲ and pips inside the same pill (never without the lead). A callout
	-- state's chip lays out its code and row here; the others are placed by
	-- layoutMarks (applyPlace).
	local function paintLens(node: Node, line: MapInterface.LensLine?)
		local chipW, chipH = 0, 0
		if node.ladder then
			chipW, chipH = chipPx(node)
		end
		local lh = labelPx(node)
		-- A chip's room: side by side when wide, stacked when tall enough.
		local side = node.ladder and chipW >= CHIP_LENS_W
		local stackLabel = math.clamp(chipH - PART_H - ROW_GAP - 2, CHIP_LABEL_MIN, LABEL_MIN)
		local stacked = node.ladder and not side and chipH >= CHIP_LABEL_MIN + ROW_GAP + PART_H
		-- (Alaska and Hawaii always show theirs: their insets have the room.)
		local roomy = if node.ladder
			then side or stacked
			elseif compact() then true
			else roomPx(node) >= LENS_ROOM or geo.insets[node.id] ~= nil
		local starRoom = if node.ladder
			then (side and chipW >= CHIP_LENS_W + STAR_CHIP) or (stacked and chipW >= 30)
			else true
		local parts: { MapInterface.LensPart } = if line and roomy then line.parts else {}
		if node.ladder and #parts > 1 then
			-- A chip keeps the parts that fit it, first to last.
			local room = if side then chipW / 2 - CHIP_PAD_X else chipW - 2
			local kept: { MapInterface.LensPart } = {}
			local used = 0
			for i, spec in parts do
				used += textW(spec.text, PART_CHAR) + 2 * PART_PAD + (if i > 1 then PART_GAP else 0)
				if i > 1 and used > room then
					break
				end
				table.insert(kept, spec)
			end
			parts = kept
		end
		local valueW, rowH = 0, PART_H
		local inline = false -- a part has an icon before its text
		for i, spec in parts do
			if i > #node.parts then
				table.insert(node.parts, newPart(node.lensRow, i))
			end
			local part = node.parts[i]
			local color = spec.color or Kit.colors.text
			part.label.Visible = true
			local star = string.sub(spec.text, 1, #Kit.STAR) == Kit.STAR
			local text = if star and not starRoom then string.sub(spec.text, #Kit.STAR + 1) else spec.text
			part.label.Text = text
			part.label.TextColor3 = if spec.filled then onFill(color) else color
			part.label.BackgroundColor3 = if spec.filled then color else Kit.colors.field
			part.edge.Color = if spec.filled
				then edgeOf(color)
				elseif spec.outlined then Kit.colors.text
				else Kit.colors.line
			part.edge.Transparency = if spec.filled or spec.outlined then 0 else PART_EDGE
			part.edge.Thickness = if spec.outlined then Kit.MARK_STROKE else 1
			-- An icon (a coin, an issue): before the text in the row, which then
			-- wears the plate; or alone at DISC_ICON px on a DISC px disc.
			local iconName = (spec :: any).icon :: string?
			if iconName and node.ladder and not (spec :: any).disc then
				-- A chip shows the icon only if the pill still fits it.
				local room = if side then chipW / 2 - CHIP_PAD_X else chipW - 2
				if
					textW(text, PART_CHAR) + 2 * PART_PAD + Kit.size.caption + PART_GAP + 2 * ROW_PAD > room
				then
					iconName = nil
				end
			end
			local disc = (spec :: any).disc == true
			if part.icon then
				(part.icon :: GuiObject):Destroy()
				part.icon = nil
			end
			local pad = part.label:FindFirstChildOfClass("UIPadding")
			if pad then
				pad.PaddingLeft = UDim.new(0, if disc then 0 else PART_PAD)
				pad.PaddingRight = UDim.new(0, if disc then 0 else PART_PAD)
			end
			if iconName then
				local px = if disc then DISC_ICON else Kit.size.caption
				local icon = Kit.icon(iconName, px, (spec :: any).iconColor or color)
				icon.ZIndex = 7
				if disc then
					icon.AnchorPoint = Vector2.new(0.5, 0.5)
					icon.Position = UDim2.fromScale(0.5, 0.5)
					icon.Parent = part.label
					rowH = math.max(rowH, DISC)
				else
					icon.Name = `Icon{i}`
					icon.LayoutOrder = 2 * i - 1
					icon.Parent = node.lensRow
					inline = true
					valueW += px + PART_GAP
				end
				part.icon = icon
			end
			part.label.Size = UDim2.fromOffset(if disc then DISC else 0, if disc then DISC else PART_H)
			valueW += (if disc then DISC else textW(text, PART_CHAR) + 2 * PART_PAD) + (if i > 1
				then PART_GAP
				else 0)
		end
		for i = #parts + 1, #node.parts do
			local part = node.parts[i]
			part.label.Visible = false
			if part.icon then
				(part.icon :: GuiObject):Destroy()
				part.icon = nil
			end
		end

		-- The Polls suffix (▲ and pips), only beside a value.
		local momentum = if line and #parts > 0 then line.momentum else nil
		local runs: { MapInterface.Pips } = if line and line.pips and #parts > 0 then line.pips else {}
		local pipPx = math.clamp(math.floor(widthPx() * PIP_SHARE), PIP, PIP_BIG)
		local upText = if momentum then (if line and line.momentumStrong then "▲▲" else "▲") else ""
		local suffixW = 0
		if momentum then
			suffixW += textW(upText, PART_CHAR + 2) + PART_GAP
		end
		local pipsW = 0
		if #runs > 0 then
			for r, run in runs do
				pipsW += math.min(run.count, PIP_MAX) * (pipPx + PIP_GAP) + (if r > 1 then PIP_RUN_GAP else 0)
			end
			suffixW += pipsW
		end
		-- A chip keeps its suffix only if the whole pill fits it.
		if node.ladder and suffixW > 0 then
			local room = if side then chipW / 2 - CHIP_PAD_X else chipW - 2
			if valueW + suffixW + 2 * ROW_PAD > room then
				momentum, runs, suffixW = nil, {}, 0
			end
		end
		node.up.Visible = momentum ~= nil
		if momentum then
			node.up.Text = upText
			node.up.TextColor3 = momentum
		end
		fillPips(node, runs, pipPx)
		node.pips.Visible = #runs > 0
		-- One pill per state: a suffix (▲, pips, a miss's ×) shares the lead's plate.
		local plated = suffixW > 0 or #parts > 1 or inline
		node.lensRow.BackgroundTransparency = if plated then 0 else 1
		node.rowEdge.Enabled = plated
		for i = 1, #parts do
			local part = node.parts[i]
			if plated and not parts[i].filled and not parts[i].outlined then
				-- Inside the pill's plate: no second plate.
				part.label.BackgroundTransparency = 1
				part.edge.Transparency = 1
			else
				part.label.BackgroundTransparency = PART_BG
			end
		end
		node.wantRow = #parts > 0
		node.rowW = math.max(1, valueW + suffixW + (if plated then 2 * ROW_PAD else 0))
		node.rowH = rowH
		local keys = { upText, tostring(#runs) }
		for _, spec in parts do
			table.insert(keys, spec.text)
		end
		node.rowKey = table.concat(keys, ",")

		if not node.ladder then
			applyPlace(node)
			return
		end

		-- A callout chip: code and value side by side, stacked, or the code alone.
		local _, h, _, growY = natural(node)
		local chip = node.chip :: Frame
		local height = if growY then UDim.new(0, h - 2 * CHIP_PAD_Y) else UDim.new(1, -2 * CHIP_PAD_Y)
		chip.Size = UDim2.new(across(node, 1, 2 * CHIP_PAD_X), height)
		chip.Position = onAnchor(node, 0.5, 0)
		local halo = node.halo :: Frame
		halo.Size = UDim2.new(
			chip.Size.X.Scale,
			chip.Size.X.Offset + 2 * HALO_PAD,
			height.Scale,
			height.Offset + 2 * HALO_PAD
		)
		halo.Position = chip.Position
		node.label.Visible = true
		local showRow = node.wantRow
		node.lensRow.Visible = showRow
		node.lensRow.Size = UDim2.fromOffset(node.rowW, rowH)
		if showRow and side then
			node.label.Size = UDim2.new(across(node, 0.5, CHIP_PAD_X), UDim.new(0, math.min(lh, h)))
			node.label.Position = onAnchor(node, 0.27, 0)
			node.lensRow.Position = onAnchor(node, 0.73, 0)
		elseif showRow then
			local total = stackLabel + ROW_GAP + rowH
			node.label.Size = UDim2.new(across(node, 1, 2 * CHIP_PAD_X), UDim.new(0, stackLabel))
			node.label.Position = onAnchor(node, 0.5, -total / 2 + stackLabel / 2)
			node.lensRow.Position = onAnchor(node, 0.5, total / 2 - rowH / 2)
		else
			node.label.Size = UDim2.new(across(node, 1, CHIP_PAD_X), UDim.new(0, math.min(lh, h)))
			node.label.Position = onAnchor(node, 0.5, 0)
		end
	end

	-- A callout state's tag sits beside its chip toward the land (left of a
	-- column chip, over a row chip); the others' tags are placed by layoutMarks.
	local function placeTag(node: Node, tag: GuiObject)
		if node.ladder then
			local chip = node.shape.chip :: MapShape.Rect
			if geo.row then
				tag.AnchorPoint = Vector2.new(0.5, 1)
				tag.Position = UDim2.fromScale(node.lx, chip.y)
			else
				tag.AnchorPoint = Vector2.new(1, 0.5)
				tag.Position = UDim2.fromScale(chip.x, node.ly)
			end
		end
	end

	local function paint(node: Node)
		local mark = marks[node.id]
		local line = lens[node.id]
		local isSelected = selected == node.id
		local dim = mark ~= nil and mark.dim == true or (line ~= nil and line.dim == true)
		local quiet = line ~= nil and (line :: any).quiet == true
		local hollow = mark ~= nil and (mark :: any).hollow == true
		local fill = fills[node.id] or Kit.color(Colors.neutral)
		local shown = if hollow then Kit.colors.field else fill
		local fade = if hollow then HOLLOW_FILL elseif quiet then QUIET_FILL elseif dim then DIM_FILL else 0
		if tweening[node.id] == nil then
			node.image.ImageColor3 = shown
		end
		node.image.ImageTransparency = fade
		if node.chip then
			local chip = node.chip :: Frame
			if tweening[node.id] == nil then
				chip.BackgroundColor3 = shown
			end
			chip.BackgroundTransparency = fade
		end
		local faded = dim or quiet
		node.label.TextTransparency = if faded then DIM_TEXT else 0
		node.label.TextStrokeTransparency = if faded then 1 else LABEL_STROKE
		paintLens(node, line)

		local halo = if mark then mark.halo else nil
		local strong = mark ~= nil and mark.haloStrong == true
		local dashed = mark ~= nil and (mark :: any).dashed == true
		-- What moved (a preview, a reveal) outranks an owner's ring while it shows.
		if isSelected then
			setOutline(node, Kit.colors.accent, SELECTED_PX)
		elseif halo then
			setOutline(node, halo, if strong then SELECTED_PX else OUTLINE_PX)
		elseif mark and mark.ring then
			setOutline(node, mark.ring, if dashed then OUTLINE_PX else SELECTED_PX, dashed)
		elseif hollow then
			setOutline(node, Kit.colors.line, HAIRLINE_PX, false, PART_EDGE)
		else
			setOutline(node, nil, 0)
		end
		if node.halo then
			local plate = node.halo :: Frame
			plate.Visible = halo ~= nil
			if halo then
				plate.BackgroundColor3 = halo
				plate.BackgroundTransparency = if strong then HALO_STRONG else HALO_SOFT
			end
		end
		local lit = halo == nil and mark ~= nil and mark.ring == Kit.colors.accent and not isSelected
		if halo or lit or node.bloom then
			local bloom = bloomOf(node)
			if bloom then
				bloom.Visible = halo ~= nil or lit
				bloom.ImageColor3 = halo or Kit.colors.accent
				bloom.ImageTransparency = if halo and not strong then BLOOM_SOFT else BLOOM_STRONG
			end
		end

		-- One solid tag holds the badge and the word (as NodeMap's).
		local badge = if mark then mark.badge else nil
		local word = if mark then mark.note else nil
		local tag = if badge and word then `{badge} {word}` else badge or word
		node.badge.Visible = tag ~= nil
		node.badge.Text = tag or ""
		placeTag(node, node.badge)
		if word then
			local note = if mark then mark.noteColor else nil
			node.badge.BackgroundColor3 = Kit.colors.field
			-- A flip's ▲ / ▼ alone: the glyph in its color.
			node.badge.TextColor3 = if badge == nil
					and GLYPH_NOTES[word]
					and note
				then Kit.textColor(note)
				else Kit.colors.text
			node.badgeStroke.Color = note or Kit.colors.line
			node.badgeStroke.Thickness = FLIP_EDGE
		else
			local fillTag = if mark and mark.badgeColor then mark.badgeColor else Kit.colors.accent
			node.badge.BackgroundColor3 = fillTag
			node.badge.TextColor3 = onFill(fillTag)
			node.badgeStroke.Color = edgeOf(fillTag)
			node.badgeStroke.Thickness = 1
		end
		local glyph = if mark and mark.arrow then ARROWS[mark.arrow] else nil
		node.arrow.Visible = glyph ~= nil
		node.arrow.Text = glyph or ""
		node.arrow.TextColor3 = if mark and mark.arrowColor then mark.arrowColor else Kit.colors.text
	end

	-- Builds the pins; layoutMarks places them. A pin is its face at rest; its
	-- name tab shows while its state is selected or when the pin asks for it.
	local pinFrames: { { pin: MapInterface.Pin, frame: Frame } } = {}

	local function paintPins()
		local bw = boxDims()
		local px = math.clamp(math.floor((if bw > 0 then bw else 600) * PIN_SHARE), PIN_MIN, PIN_MAX)
		local keys = { tostring(px) }
		local tabs: { boolean } = {}
		for k, pin in pins do
			tabs[k] = (pin :: any).label == true or selected == pin.state
			table.insert(
				keys,
				`{pin.state}:{pin.candidate}:{pin.name}:{pin.tag}:{pin.color}:{pin.you}:{tabs[k]}`
			)
		end
		local key = table.concat(keys, "|")
		if key == lastPins then
			return -- the same pins: keep them where the layout put them
		end
		lastPins = key
		lastSignature = "" -- new frames need placing
		-- Until the layout places them, new frames stand where the old ones did.
		local was: { [string]: UDim2 } = {}
		for _, entry in pinFrames do
			was[`{entry.pin.state}:{entry.pin.you}`] = entry.frame.Position
		end
		for _, child in pinLayer:GetChildren() do
			child:Destroy()
		end
		table.clear(pinFrames)
		for k, pin in pins do
			local node = byId[pin.state]
			if node then
				local frame = Pins.build(pin, if pin.you then px + PIN_YOU else px, tabs[k])
				frame.ZIndex = if pin.you then 2 else 1
				frame.Position = was[`{pin.state}:{pin.you}`] or UDim2.fromScale(node.shape.lx, node.shape.ly)
				frame.Parent = pinLayer
				table.insert(pinFrames, { pin = pin, frame = frame })
			end
		end
	end

	-- The plan preview's tag (placed by layoutMarks).
	local function paintPreview(node: Node)
		local spec = previews[node.id]
		local tag = node.preview
		if spec == nil then
			if tag then
				tag.Visible = false
			end
			return
		end
		if tag == nil then
			local made = Kit.text("", {
				Name = node.id,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, TAG_H),
				TextSize = Kit.size.caption,
				Font = Kit.font.display,
				BackgroundColor3 = Kit.colors.field,
				BackgroundTransparency = PREVIEW_BG,
				TextTransparency = PREVIEW_TEXT,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = false,
				Parent = previewLayer,
			})
			Kit.new("UICorner", { CornerRadius = UDim.new(0, TAG_RADIUS), Parent = made })
			Kit.new("UIPadding", {
				PaddingLeft = UDim.new(0, TAG_PAD),
				PaddingRight = UDim.new(0, TAG_PAD),
				Parent = made,
			})
			local stroke = Kit.stroke(Kit.colors.line, 1)
			stroke.Name = "Edge"
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = made
			Kit.dataColor(made)
			node.preview = made
			tag = made
		end
		local label = tag :: TextLabel
		label.Visible = true
		label.Text = spec.text
		local color = if spec.negative then Kit.colors.loss else Kit.colors.good
		label.TextColor3 = color
		local edge = label:FindFirstChild("Edge") :: UIStroke?
		if edge then
			edge.Color = color
			edge.Transparency = PREVIEW_EDGE
		end
	end

	-- ---------------------------------------------------------------- mark layout

	-- Every label and mark is placed so it covers no state's code, and as
	-- little as possible of the marks placed before it. On a compact map the
	-- labels go first, biggest states first: each "PA 19" (or "19") stands on
	-- its anchor or is nudged a few px off it, never over another label. On a
	-- big map the codes stay on their anchors and each lens row tries spots
	-- around its own code (under first). Then pins, tags, plan badges and the
	-- preview tags, each trying spots around its code in its own order, then the
	-- same spots farther with a thin leader back to the code. No later mark
	-- covers a code or a value row; pins and preview tags cover no mark at all.
	type Box = { x0: number, y0: number, x1: number, y1: number }
	type Dir = { number }
	local BELOW: { Dir } =
		{ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
	local BESIDE: { Dir } =
		{ { 1, 0 }, { -1, 0 }, { 1, 1 }, { -1, 1 }, { 0, 1 }, { 1, -1 }, { -1, -1 }, { 0, -1 } }
	local ABOVE: { Dir } =
		{ { 0, -1 }, { 1, -1 }, { -1, -1 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 1, 1 }, { -1, 1 } }
	local CORNER: { Dir } =
		{ { 1, -1 }, { -1, -1 }, { 1, 0 }, { -1, 0 }, { 1, 1 }, { -1, 1 }, { 0, -1 }, { 0, 1 } }
	local LEFT: { Dir } = { { -1, 0 } }
	local UP: { Dir } = { { 0, -1 }, { -1, -1 }, { 1, -1 } }
	-- A compact label's nudges: down and up first (along the label), then sideways.
	local NUDGE_DIRS: { Dir } =
		{ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
	-- Spot distances, shares of the gap to the code's edge: marks stay close
	-- (a short leader at most); pins may go a little farther.
	local NEAR = { 1, 1.6 }
	local PIN_REACH = { 1, 1.6, 2.3, 3.2, 4.2 } -- pins go farther rather than cover a code or a value
	local PIN_GAP = 2 -- px between pins that share a state
	local occupied: { Box } = {} -- the codes and the marks of the last layout
	local grid: { [number]: { number } } = {} -- occupied indices by GRID px cell
	local stamp: { number } = {} -- occupied index -> the last query that saw it
	local query = 0

	local function cells(box: Box, visit: (key: number) -> ())
		for gx = math.floor(box.x0 / GRID), math.floor(box.x1 / GRID) do
			for gy = math.floor(box.y0 / GRID), math.floor(box.y1 / GRID) do
				visit((gx + 1024) * 4096 + gy + 1024)
			end
		end
	end

	local function occupy(box: Box)
		table.insert(occupied, box)
		local index = #occupied
		cells(box, function(key: number)
			local list = grid[key]
			if list == nil then
				list = {}
				grid[key] = list
			end
			table.insert(list, index)
		end)
	end
	local lastCodeCount = 0
	local codes: { [string]: Box } = {}

	local function overlap(a: Box, b: Box): number
		local w = math.min(a.x1, b.x1) - math.max(a.x0, b.x0)
		local h = math.min(a.y1, b.y1) - math.max(a.y0, b.y0)
		return if w > 0 and h > 0 then w * h else 0
	end

	-- The score of `box`: what it covers (codes and the map's edge at
	-- CODE_COST, other marks at MARK_COST) and whether it covers a code.
	local function cost(box: Box, codeCount: number): (number, boolean)
		local bw, bh = boxDims()
		local w, h = box.x1 - box.x0, box.y1 - box.y0
		local outside = w * h
			- math.max(0, math.min(box.x1, bw) - math.max(box.x0, 0))
				* math.max(0, math.min(box.y1, bh) - math.max(box.y0, 0))
		local bad = outside > 1
		local score = outside * CODE_COST
		query += 1
		cells(box, function(key: number)
			local list: { number } = grid[key] or {}
			for _, i in list do
				if stamp[i] ~= query then
					stamp[i] = query
					local area = overlap(box, occupied[i])
					if area > 0 then
						score += area * (if i <= codeCount then CODE_COST else MARK_COST)
						bad = bad or (i <= codeCount and area > 1)
					end
				end
			end
		end)
		return score, bad
	end

	-- The best spot for a `w` x `h` mark around code box `c`: its center in px
	-- and whether it is far enough to want a leader.
	local function bestSpot(
		c: Box,
		w: number,
		h: number,
		dirs: { Dir },
		codeCount: number,
		reaches: { number }?
	): (number, number, boolean, boolean)
		local cx, cy = (c.x0 + c.x1) / 2, (c.y0 + c.y1) / 2
		local hw, hh = (c.x1 - c.x0) / 2, (c.y1 - c.y0) / 2
		local best, bx, by, far, covers = math.huge, cx, cy + hh + h / 2 + MARK_GAP, false, true
		local steps: { number } = reaches or NEAR
		for r, reach in steps do
			for k, dir in dirs do
				local x = cx + dir[1] * (hw + MARK_GAP + w / 2) * reach
				local y = cy + dir[2] * (hh + MARK_GAP + h / 2) * reach
				local score, bad =
					cost({ x0 = x - w / 2, y0 = y - h / 2, x1 = x + w / 2, y1 = y + h / 2 }, codeCount)
				score += (r - 1) * FAR_COST + k
				if score < best then
					best, bx, by, far, covers = score, x, y, r > 1, bad
				end
			end
		end
		return bx, by, far, covers
	end

	-- The best spot for a `w` x `h` compact label centered near (x, y): on it,
	-- or nudged up to the last NUDGES step; returns its center and whether it
	-- still covers a label.
	local function nudgeSpot(
		x: number,
		y: number,
		w: number,
		h: number,
		reach: number?
	): (number, number, boolean, number)
		local best, bx, by, covers = math.huge, x, y, true
		-- Tested a little bigger than drawn: text widths are estimates.
		local hw, hh = w / 2 + UNIT_MARGIN, h / 2 + UNIT_MARGIN
		local function try(px: number, py: number, moved: number)
			local score, bad = cost({ x0 = px - hw, y0 = py - hh, x1 = px + hw, y1 = py + hh }, #occupied)
			score += moved * NUDGE_COST
			if score < best then
				best, bx, by, covers = score, px, py, bad
			end
		end
		try(x, y, 0)
		for _, d in NUDGES do
			if not covers or d > (reach or math.huge) then
				break -- a clean spot nearer the anchor already (or as far as this label may go)
			end
			for _, dir in NUDGE_DIRS do
				local len = math.sqrt(dir[1] * dir[1] + dir[2] * dir[2])
				try(x + dir[1] * d / len, y + dir[2] * d / len, d)
			end
		end
		return bx, by, covers, best
	end

	-- A thin line from a code to a mark that stands off it.
	local function leader(fromX: number, fromY: number, toX: number, toY: number)
		local dx, dy = toX - fromX, toY - fromY
		Kit.new("Frame", {
			Name = "MarkLeader",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((fromX + toX) / 2, (fromY + toY) / 2),
			Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), LEADER_PX),
			Rotation = math.deg(math.atan2(dy, dx)),
			BackgroundColor3 = Kit.colors.text,
			BackgroundTransparency = MARK_LEADER_FADE,
			BorderSizePixel = 0,
			Parent = markLeaders,
		})
	end

	-- Everything the layout depends on, as one string (the same: nothing to do).
	local function signature(bw: number, bh: number): string
		local parts = { `{geo.kind}:{bw}x{bh}:{legendLayer.Visible}` }
		for _, node in nodes do
			local bits = { node.id, if node.arrow.Visible then "a" else "", node.rowKey }
			if node.badge.Visible then
				table.insert(bits, "t" .. node.badge.Text)
			end
			local tag = node.preview
			if tag and tag.Visible then
				table.insert(bits, "p" .. tag.Text)
			end
			if node.hit:FindFirstChild("PlanBadge") then
				table.insert(bits, "b")
			end
			table.insert(parts, table.concat(bits, ","))
		end
		for _, entry in pinFrames do
			table.insert(parts, `{entry.pin.state}:{entry.pin.tag}:{entry.frame.Size.X.Offset}`)
		end
		return table.concat(parts, "|")
	end

	local function layoutMarks()
		local bw, bh = boxDims()
		if bw <= 0 then
			return
		end
		local now = signature(bw, bh)
		if now == lastSignature then
			-- Same marks: keep the spots (a repaint already put the labels back).
			return
		end
		lastSignature = now
		for _, child in markLeaders:GetChildren() do
			child:Destroy()
		end
		table.clear(occupied)
		table.clear(grid)
		table.clear(stamp)
		table.clear(codes)
		local isCompact = compact()

		-- The chips and the legend strip, fixed.
		for _, node in nodes do
			if node.ladder then
				local chip = node.shape.chip :: MapShape.Rect
				local box = {
					x0 = chip.x * bw,
					y0 = chip.y * bh,
					x1 = (chip.x + chip.w) * bw,
					y1 = (chip.y + chip.h) * bh,
				}
				codes[node.id] = box
				occupy(box)
			end
		end
		if legendLayer.Visible then
			local r = geo.legend
			occupy({ x0 = r.x * bw, y0 = r.y * bh, x1 = (r.x + r.w) * bw, y1 = (r.y + r.h) * bh })
		end

		local function placeOf(node: Node): Place
			return {
				code = true,
				codeX = 0,
				codeY = 0,
				row = false,
				rowX = 0,
				rowY = 0,
				rowW = node.rowW,
				rowH = node.rowH,
			}
		end

		if isCompact then
			-- One line per state, biggest states first: "PA 19", the value alone
			-- on a state under LENS_ROOM, nudged off its anchor rather than over
			-- a neighbor's; if nothing fits, the code alone on its anchor.
			local byEV = {}
			for _, node in nodes do
				if not node.ladder then
					table.insert(byEV, node)
				end
			end
			-- The states your plan moves first (their lines carry its numbers),
			-- then the rest, most votes first.
			local function planned(node: Node): boolean
				local tag = node.preview
				return tag ~= nil and tag.Visible
			end
			table.sort(byEV, function(a: Node, b: Node): boolean
				local pa, pb = planned(a), planned(b)
				if pa ~= pb then
					return pa
				end
				if a.ev ~= b.ev then
					return a.ev > b.ev
				end
				return a.id < b.id
			end)
			for _, node in byEV do
				local lh = labelPx(node)
				local codeW = textW(node.id, math.min(lh, Kit.size.heading) * CODE_CHAR)
					+ 2
					+ (if node.arrow.Visible then ARROW_PX else 0)
				local ax, ay = node.lx * bw, node.ly * bh
				-- Alaska and Hawaii keep their codes: the inset's title.
				local small = roomPx(node) < LENS_ROOM and geo.insets[node.id] == nil
				-- A small state tries its full line only on or right by its anchor
				-- (where the map is quiet: Money's few values, Close), else its value.
				local tries: { { code: boolean, row: boolean, reach: number? } } = {}
				if node.wantRow then
					table.insert(
						tries,
						{ code = true, row = true, reach = if small then SMALL_REACH else nil }
					)
					table.insert(tries, { code = false, row = true })
				else
					-- With a value, the last resort is the value alone: a code alone
					-- beside a neighbor's value would read as that value's.
					table.insert(tries, { code = true, row = false })
				end
				-- The plan preview's number rides at the end of the line (D-071's
				-- tag, D-075's place for it on a phone): never dropped.
				local tag = node.preview
				local tagW = if tag and tag.Visible then textW(tag.Text, TAG_CHAR) + 2 * TAG_PAD else 0
				local chosen: Place? = nil
				local box: Box? = nil
				for k, try in tries do
					local w = (if try.code then codeW else 0)
						+ (if try.code and try.row then UNIT_GAP else 0)
						+ (if try.row then node.rowW else 0)
					local lineW = w + (if tagW > 0 then UNIT_GAP + tagW else 0)
					local h = math.max(
						if try.code then lh else 0,
						if try.row then node.rowH else 0,
						if tagW > 0 then TAG_H else 0
					)
					-- (Nothing fits: the last try takes its least crowded spot.)
					local x, y, covers = nudgeSpot(ax, ay, lineW, h, try.reach)
					if not covers or k == #tries then
						-- Never off the map, whatever it covers.
						x = math.clamp(x, lineW / 2, math.max(lineW / 2, bw - lineW / 2))
						y = math.clamp(y, h / 2, math.max(h / 2, bh - h / 2))
						local place = placeOf(node)
						place.code = try.code
						place.row = try.row
						local left = x - lineW / 2
						place.codeX = left + codeW / 2 - ax
						place.codeY = y - ay
						place.rowX = (if try.code then left + codeW + UNIT_GAP else left) + node.rowW / 2 - ax
						place.rowY = y - ay
						if tag and tagW > 0 then
							tag.AnchorPoint = Vector2.new(0.5, 0.5)
							tag.Position =
								UDim2.new(node.lx, left + w + UNIT_GAP + tagW / 2 - ax, node.ly, y - ay)
						end
						chosen = place
						box = { x0 = x - lineW / 2, y0 = y - h / 2, x1 = x + lineW / 2, y1 = y + h / 2 }
						break
					end
				end
				local b = box :: Box
				node.place = chosen
				codes[node.id] = b
				occupy(b)
				-- Moved off its state's anchor: a thin leader back to it.
				if ax < b.x0 - 1 or ax > b.x1 + 1 or ay < b.y0 - 1 or ay > b.y1 + 1 then
					leader(ax, ay, math.clamp(ax, b.x0, b.x1), math.clamp(ay, b.y0, b.y1))
				end
				applyPlace(node)
			end
		else
			-- The codes, fixed on their anchors.
			for _, node in nodes do
				if not node.ladder then
					local lh = labelPx(node)
					local w = textW(node.id, math.min(lh, Kit.size.heading) * CODE_CHAR)
						+ (if node.arrow.Visible then ARROW_PX else 0)
					local x, y = node.lx * bw, node.ly * bh
					local box = { x0 = x - w / 2, y0 = y - lh / 2, x1 = x + w / 2, y1 = y + lh / 2 }
					codes[node.id] = box
					occupy(box)
				end
			end
		end
		local codeCount = #occupied
		lastCodeCount = codeCount

		-- Places a `w` x `h` mark around box `c`, whose anchor is (fx, fy) in box
		-- fractions: returns the mark's center as px from that anchor, and
		-- whether every spot covered a code (an `optional` mark is then left out).
		local function placeAround(
			c: Box,
			fx: number,
			fy: number,
			w: number,
			h: number,
			dirs: { Dir },
			reaches: { number }?,
			optional: boolean?,
			hard: number? -- occupied boxes up to this index count as codes (default: the codes)
		): (number, number, boolean)
			local x, y, far, covers = bestSpot(c, w, h, dirs, hard or codeCount, reaches)
			local ax, ay = fx * bw, fy * bh
			if covers and optional then
				return x - ax, y - ay, true
			end
			occupy({ x0 = x - w / 2, y0 = y - h / 2, x1 = x + w / 2, y1 = y + h / 2 })
			if far then
				leader(ax, ay, x, y)
			end
			return x - ax, y - ay, covers
		end

		-- One mark of `node`, around its code (a callout state: its chip).
		local function place(
			node: Node,
			w: number,
			h: number,
			dirs: { Dir },
			optional: boolean?,
			hard: number?
		): (number, number, boolean)
			return placeAround(codes[node.id], node.lx, node.ly, w, h, dirs, nil, optional, hard)
		end

		if not isCompact then
			-- The lens rows (biggest states first: they have the room).
			local byRoom = table.clone(nodes)
			table.sort(byRoom, function(a: Node, b: Node): boolean
				if a.shape.room ~= b.shape.room then
					return a.shape.room > b.shape.room
				end
				return a.id < b.id
			end)
			for _, node in byRoom do
				if not node.ladder then
					local spot = placeOf(node)
					if node.wantRow and (roomPx(node) >= LENS_ROOM or geo.insets[node.id] ~= nil) then
						local dx, dy, covers = place(node, node.rowW, node.rowH, BELOW, true)
						-- No room near the code on this map: the state card has the numbers.
						spot.row = not covers
						spot.rowX, spot.rowY = dx, dy
					end
					node.place = spot
					applyPlace(node)
				end
			end
		end

		-- The codes and the value rows: no later mark may cover them.
		local values = #occupied

		-- Pins: yours last, so it is drawn over the rival's. Pins that share a
		-- state stand side by side as one group, placed as one mark. A pin never
		-- covers a code, a value row or another pin: those count as codes here.
		local groups: { { state: string, frames: { Frame } } } = {}
		local groupOf: { [string]: { state: string, frames: { Frame } } } = {}
		for _, entry in pinFrames do
			local group = groupOf[entry.pin.state]
			if group == nil then
				group = { state = entry.pin.state, frames = {} }
				groupOf[entry.pin.state] = group
				table.insert(groups, group)
			end
			table.insert(group.frames, entry.frame)
		end
		for _, group in groups do
			local node = byId[group.state]
			local w, h = 0, 0
			for k, frame in group.frames do
				w += frame.Size.X.Offset + (if k > 1 then PIN_GAP else 0)
				h = math.max(h, frame.Size.Y.Offset)
			end
			-- Beside the code (a callout state's pins: beside its real place on the coast).
			local fx, fy = node.lx, node.ly
			local c = codes[node.id]
			if node.ladder then
				fx, fy = node.shape.lx, node.shape.ly
				c = { x0 = fx * bw, y0 = fy * bh, x1 = fx * bw, y1 = fy * bh }
			end
			local dx, dy = placeAround(c, fx, fy, w, h, BESIDE, PIN_REACH, false, #occupied)
			-- Left to right in the group; each frame's AnchorPoint is the pointer
			-- under its face: move it there.
			local left = dx - w / 2
			for _, frame in group.frames do
				local fw, fh = frame.Size.X.Offset, frame.Size.Y.Offset
				local anchor = frame.AnchorPoint
				frame.Position = UDim2.new(fx, left + anchor.X * fw, fy, dy + h / 2 - fh + anchor.Y * fh)
				left += fw + PIN_GAP
			end
		end

		-- Tags and plan badges (a callout chip's tag: beside it, toward the
		-- land). Tags are few (SwingMarks keeps them to 8): none covers another.
		for _, node in nodes do
			if node.ladder then
				if node.badge.Visible then
					local w = textW(node.badge.Text, TAG_CHAR) + 2 * TAG_PAD
					local dx, dy = place(node, w, TAG_H, if geo.row then UP else LEFT, false, #occupied)
					node.badge.AnchorPoint = Vector2.new(0.5, 0.5)
					node.badge.Position = UDim2.new(node.lx, dx, node.ly, dy)
				end
			else
				if node.badge.Visible then
					local w = textW(node.badge.Text, TAG_CHAR) + 2 * TAG_PAD
					local dx, dy = place(node, w, TAG_H, ABOVE, false, #occupied)
					node.badge.AnchorPoint = Vector2.new(0.5, 0.5)
					node.badge.Position = UDim2.new(node.lx, dx, node.ly, dy)
				end
				local planBadge = node.hit:FindFirstChild("PlanBadge") :: GuiObject?
				if planBadge then
					local dx, dy = place(node, PLAN_BADGE_PX, PLAN_BADGE_PX, CORNER, false, values)
					planBadge.Position = onAnchorAt(node, dx, dy)
				end
			end
		end
		-- The plan preview, last: a tag never covers a code, a value or another
		-- preview tag (they count as codes), so two neighbors' numbers stay apart.
		for _, node in nodes do
			local tag = node.preview
			-- (On a compact map a state's preview already rides on its label line.)
			if tag and tag.Visible and not (isCompact and not node.ladder) then
				local w = textW(tag.Text, TAG_CHAR) + 2 * TAG_PAD
				local dirs = if node.ladder then (if geo.row then UP else LEFT) else BESIDE
				local dx, dy = place(node, w, TAG_H, dirs, false, #occupied)
				tag.AnchorPoint = Vector2.new(0.5, 0.5)
				tag.Position = UDim2.new(node.lx, dx, node.ly, dy)
			end
		end
	end

	-- One layout per frame, after every update of that frame (a screen sets
	-- the view, lens, marks, pins and preview one after another).
	local layoutQueued = false
	local function requestLayout()
		if layoutQueued then
			return
		end
		layoutQueued = true
		task.defer(function()
			layoutQueued = false
			measured(layoutMarks)
		end)
	end

	paintAll = function()
		for _, node in nodes do
			paint(node)
			paintPreview(node)
		end
		paintPins()
		requestLayout()
	end

	local map = {} :: any
	map.root = root

	-- Repaint when the map's size changes: rooms, labels, chips and pins are in
	-- px; and when its frame changes, which may call for the other layout.
	pcall(function()
		(root :: any):GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if root.AbsoluteSize.X ~= lastWidth then
				lastWidth = root.AbsoluteSize.X
				measured(paintAll)
			end
		end)
	end)
	local parentWatch: any = nil
	local function watchParent()
		if parentWatch then
			pcall(function()
				parentWatch:Disconnect()
			end)
			parentWatch = nil
		end
		local parent = root.Parent
		if parent and parent:IsA("GuiObject") then
			pcall(function()
				parentWatch = (parent :: any):GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
					if wantedKind() ~= geo.kind then
						measured(function() end)
					end
				end)
			end)
		end
	end
	pcall(function()
		(root :: any):GetPropertyChangedSignal("Parent"):Connect(watchParent)
	end)

	-- `animate` (a reveal): fills that change tween to their new color.
	function map.setView(_self: any, view: View.View, colors: { Colors.RGB }, animate: boolean?)
		measured(function()
			for _, s in view.states do
				local fill: Colors.RGB
				if s.poll then
					fill = Colors.bandFill(s.poll.support, colors)
				elseif s.leanTo then
					local support = table.create(#colors, 0)
					support[s.leanTo] = s.lean
					fill = Colors.bandFill(support, colors)
				else
					fill = Colors.neutral
				end
				local color = Kit.color(fill)
				local old = fills[s.id]
				fills[s.id] = color
				local node = byId[s.id]
				if node and animate and old and old ~= color and not Motion.reduced() then
					local token = (tweening[s.id] or 0) + 1
					tweening[s.id] = token
					Motion.tween(node.image, { ImageColor3 = color }, FILL_TWEEN, Motion.ease.soft)
					if node.chip then
						Motion.tween(
							node.chip :: Frame,
							{ BackgroundColor3 = color },
							FILL_TWEEN,
							Motion.ease.soft
						)
					end
					task.delay(FILL_TWEEN, function()
						if tweening[s.id] == token then
							tweening[s.id] = nil
						end
					end)
				end
				if node then
					paint(node)
					paintPreview(node)
				end
			end
			requestLayout()
		end)
	end

	function map.setMarks(_self: any, newMarks: { [string]: MapInterface.Mark })
		measured(function()
			marks = newMarks
			for _, node in nodes do
				paint(node)
				paintPreview(node)
			end
			requestLayout()
		end)
	end

	function map.setLens(_self: any, newLens: { [string]: MapInterface.LensLine }, fade: boolean?)
		measured(function()
			lens = newLens
			for _, node in nodes do
				paint(node)
				paintPreview(node)
				if fade and node.wantRow then
					for _, part in node.parts do
						if part.label.Visible then
							local resting = part.label.BackgroundTransparency
							part.label.TextTransparency = 1
							part.label.BackgroundTransparency = 1
							Motion.tween(
								part.label,
								{ TextTransparency = 0, BackgroundTransparency = resting },
								LENS_FADE
							)
						end
					end
				end
			end
			paintPins()
			requestLayout()
		end)
	end

	function map.setRoute(_self: any, stops: { string }, flights: { boolean })
		for _, child in routeLayer:GetChildren() do
			child:Destroy()
		end
		local px, py = nil, nil
		for k, id in stops do
			local shape = geo.get(id)
			if shape then
				if px and py then
					local line = segment(
						routeLayer,
						geo.aspect,
						px,
						py,
						shape.lx,
						shape.ly,
						ROUTE_PX,
						Kit.colors.accent
					)
					line.BackgroundTransparency = if flights[k] then ROUTE_FLIGHT else ROUTE_FADE
				end
				px, py = shape.lx, shape.ly
			end
		end
	end

	function map.select(_self: any, id: string?)
		local old = selected
		selected = id
		if old and byId[old] then
			paint(byId[old])
		end
		if old ~= id then
			drawLeaders()
			-- A pin's name tab shows while its state is selected (placed now, so
			-- the new tab never shows a frame unplaced).
			measured(function()
				paintPins()
				layoutMarks()
			end)
		end
		local node = if id then byId[id] else nil
		if node then
			paint(node)
			local s = node.shape
			local glow = selectGlow
			if glow then
				if node.ladder then
					local chip = s.chip :: MapShape.Rect
					glow.Position = UDim2.fromScale(chip.x + chip.w / 2, chip.y + chip.h / 2)
					glow.Size = UDim2.fromScale(chip.w * 2 * SELECT_GLOW, chip.h * 2 * SELECT_GLOW)
				else
					glow.Position = UDim2.fromScale(s.x + s.w / 2, s.y + s.h / 2)
					glow.Size = UDim2.fromScale(s.w * SELECT_GLOW, s.h * SELECT_GLOW)
				end
				glow.Visible = true
			end
			if id ~= old then
				-- The accent outline draws in (instant under reduced motion).
				if node.ladder and node.chipStroke then
					local stroke = node.chipStroke :: UIStroke
					stroke.Thickness = 0
					Motion.tween(stroke, { Thickness = SELECTED_PX }, RING_DRAW)
				end
				stopBreath()
				if glow then
					glow.ImageTransparency = SELECT_GLOW_FADE
					stopBreath = Motion.breathe(
						glow,
						"ImageTransparency",
						SELECT_GLOW_FADE,
						SELECT_GLOW_DIM,
						SELECT_BREATH
					)
				end
			end
		else
			stopBreath()
			stopBreath = function() end
			if selectGlow then
				selectGlow.Visible = false
			end
		end
	end

	function map.onSelect(_self: any, handler: (string) -> ())
		table.insert(handlers, handler)
	end

	function map.pulse(_self: any, id: string, color: Color3?)
		local node = byId[id]
		if node == nil then
			return
		end
		Motion.pop(if node.chip then node.chip :: Frame else node.image, PULSE_FROM)
		if color then
			Motion.ring(node.hit, color)
		end
	end

	function map.ring(_self: any, id: string, color: Color3)
		local node = byId[id]
		if node then
			Motion.ring(node.hit, color)
		end
	end

	-- A short shake of the state and its label (an election call landing);
	-- nothing under reduced motion (Motion.shake).
	function map.shake(_self: any, id: string)
		local node = byId[id]
		if node == nil then
			return
		end
		if not node.ladder then
			Motion.shake(node.image)
		end
		Motion.shake(node.hit)
	end

	function map.badge(_self: any, id: string, icon: string?)
		local node = byId[id]
		if node == nil then
			return
		end
		local old = node.hit:FindFirstChild("PlanBadge")
		if old then
			old.Name = "PlanBadgeLeaving"
			if icon == nil then
				local glyph = old:FindFirstChild("Icon")
				if glyph then
					Motion.exit(glyph, function() end)
				end
				Motion.exit(old, function()
					old:Destroy()
				end)
			else
				old:Destroy()
			end
		end
		if icon == nil then
			return
		end
		local badge = Kit.new("Frame", {
			Name = "PlanBadge",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.95, 0.05),
			Size = UDim2.fromOffset(PLAN_BADGE_PX, PLAN_BADGE_PX),
			BackgroundColor3 = Kit.colors.field,
			BorderSizePixel = 0,
			ZIndex = 7,
			Parent = node.hit,
		})
		badge:SetAttribute("Overhang", true)
		Kit.round().Parent = badge
		local edge = Kit.stroke(Kit.colors.accent, 1)
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = badge
		local glyph = Kit.icon(icon, PLAN_BADGE_PX, Kit.colors.accent)
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.ZIndex = 8
		glyph.Parent = badge
		badge.Position = UDim2.fromScale(0.95, 0.05)
		requestLayout()
		Motion.pop(badge, 0.6)
	end

	local ghostTag: TextLabel? = nil
	function map.ghost(_self: any, id: string, text: string?)
		local node = byId[id]
		local tag = ghostTag
		if text == nil or node == nil then
			if tag then
				tag.Visible = false
			end
			return
		end
		if tag == nil then
			local made = Kit.text("", {
				Name = "GhostTag",
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, TAG_H),
				TextSize = Kit.size.caption,
				Font = Kit.font.display,
				TextColor3 = Kit.colors.text,
				BackgroundColor3 = Kit.colors.field,
				BackgroundTransparency = GHOST_BG,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = false,
				ZIndex = 9,
				Parent = tagLayer,
			})
			Kit.new("UICorner", { CornerRadius = UDim.new(0, TAG_RADIUS), Parent = made })
			Kit.new("UIPadding", {
				PaddingLeft = UDim.new(0, TAG_PAD),
				PaddingRight = UDim.new(0, TAG_PAD),
				Parent = made,
			})
			local stroke = Kit.stroke(Kit.colors.accent, 1)
			stroke.Transparency = GHOST_STROKE
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = made
			ghostTag = made
			tag = made
		end
		local ghost = tag :: TextLabel
		ghost.Text = text
		ghost.Visible = true
		if node.ladder then
			placeTag(node, ghost)
		else
			-- Over the code, where the last layout left room (it is not kept).
			local bw, bh = boxDims()
			local c = codes[node.id]
			if c and bw > 0 then
				local x, y = bestSpot(c, #text * TAG_CHAR + 2 * TAG_PAD, TAG_H, ABOVE, lastCodeCount)
				ghost.AnchorPoint = Vector2.new(0.5, 0.5)
				ghost.Position = UDim2.new(node.lx, x - node.lx * bw, node.ly, y - node.ly * bh)
			end
		end
	end

	function map.wipe(_self: any, id: string, color: Color3)
		local node = byId[id]
		if node == nil then
			return
		end
		fills[id] = color
		Motion.tween(node.image, { ImageColor3 = color }, Motion.t.call, Motion.ease.soft)
		if node.chip then
			Motion.tween(node.chip :: Frame, { BackgroundColor3 = color }, Motion.t.call, Motion.ease.soft)
		end
		Motion.ring(node.hit, color)
	end

	function map.setPins(_self: any, newPins: { MapInterface.Pin })
		measured(function()
			pins = newPins
			paintPins()
			requestLayout()
		end)
	end

	function map.setLegend(_self: any, items: { MapInterface.LegendItem }?)
		Legend.fill(legendLayer, items)
		requestLayout()
	end

	function map.setPreview(_self: any, tags: { [string]: MapInterface.PreviewTag }?)
		measured(function()
			previews = tags or {}
			for _, node in nodes do
				paintPreview(node)
			end
			requestLayout()
		end)
	end

	-- The aspect the map's box takes in a frame up to `widthPx` x `heightPx`.
	function map.aspectFor(_self: any, frameW: number, frameH: number?): number
		local _, aspect = MapShape.fit(frameW, frameH or 0)
		return aspect
	end

	function map.destroy(_self: any)
		handlers = {}
		stopBreath()
		for _, connection in connections do
			pcall(function()
				connection:Disconnect()
			end)
		end
		if parentWatch then
			pcall(function()
				parentWatch:Disconnect()
			end)
		end
		root:Destroy()
	end

	measured(paintAll)
	return map :: MapInterface.Map
end

return ShapeMap
