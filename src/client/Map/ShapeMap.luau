--!strict
-- The real map (docs/DESIGN.md D-062): every state's true shape from the
-- generated atlases (Shared/UI/MapShape, scripts/mapgen/make.py), tinted by
-- the same rules as the circles (Colors.bandFill toward the public-poll leader,
-- the lean before the first poll), thin dark borders from one overlay image,
-- Alaska and Hawaii in insets under the West, and the nine small Northeast
-- states (MapLayout.LADDER) as callout chips in a column at the right edge,
-- each with a thin leader line to where it really is.
--
-- Each state is an ImageLabel ("Shapes" layer, "Shape<id>") showing its rect
-- of an atlas (ImageRectOffset / ImageRectSize) tinted with ImageColor3. Its
-- label, lens row and marks sit at its anchor (the middle of the biggest circle
-- inside it), in a tap square at least Kit.MAP_NODE_MIN px each way (the
-- TextButton named by the id in "Nodes"); a callout state's tap target is its
-- chip. Under the squares one button covers the whole map ("MapTaps"). Every
-- tap is resolved by MapShape.resolve: inside a state's outline picks that
-- state, so a neighbor's square never steals it; the chip column picks the
-- nearest chip; a border or the sea goes to the square that was pressed.
--
-- Selection, an owner's ring and a moved state's halo draw the state's outline
-- ("Outlines" layer: thin rotated frames along MapShapeData edges; a chip's own
-- border for a callout state). The lens row is shown where the state has room
-- (LENS_ROOM px inside it, or a wide chip); the Polls extras (▲ momentum, ground-
-- game pips; Map/Lens) go under it. Candidate pins (Map/Pins) stand on the
-- label; a callout state's pin stands on its real place. The legend row
-- (setLegend) uses the strip under the map.
--
-- Everything else matches NodeMap's API and names (Nodes/<id> with Label, Lens,
-- Arrow; Tags/<id>; PlanBadge; GhostTag), so screens and specs drive both alike.
-- The root is named "NodeMap" (the audit's map rules key on it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local MapShape = require(ReplicatedStorage.Shared.UI.MapShape)
local View = require(ReplicatedStorage.Shared.Sim.View)

local Assets = require(script.Parent.Parent.UI.Assets)
local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.MapInterface)
local Motion = require(script.Parent.Parent.UI.Motion)
local Legend = require(script.Parent.Legend)
local Pins = require(script.Parent.Pins)

local ShapeMap = {}

local ASPECT = MapShape.ASPECT
local MIN_TAP = Kit.MAP_NODE_MIN -- px, smallest tap target per state
local LENS_ROOM = 24 -- px, the smallest inner circle that shows a lens value under the code
local CHIP_LENS_W = 56 -- px, the narrowest chip that shows a lens value beside its code
local STAR_CHIP = 12 -- px more a chip needs to keep a battleground value's ★
local LABEL_MIN, LABEL_MAX = 14, 22 -- px, the code label's height range
local LABEL_SHARE = 0.4 -- the label's height, share of the state's inner circle
local PART_H = Kit.size.caption + 2 -- px, a lens plate's height
local PART_PAD = 3 -- px, a lens pill's side padding
local PART_GAP = 2 -- px, between two lens pills
local ROW_GAP = 1 -- px, between the label and the rows under it
local EXTRA_H = 12 -- px, the Polls extras row (▲ and pips)
local PIP = 6 -- px, one ground-game pip on a phone's map
local PIP_BIG = 9 -- px, ... at most, on a big map
local PIP_SHARE = 0.011 -- a pip's size, share of the map's width (between the two)
local PIP_GAP = 2 -- px, between pips
local PIP_RUN_GAP = 4 -- px, between your pips and theirs
local PIP_MAX = 6 -- pips drawn per run (GOTV max units is 4, 6 for one candidate)
local OUTLINE_PX = 2 -- an owner's or a halo's outline
local SELECTED_PX = 3 -- the selected state's accent outline
local CHIP_RING_PX = 1 -- a chip's resting edge
local CHIP_PAD_X, CHIP_PAD_Y = 2, 2 -- px between a chip and its cell's edges
local CHIP_RADIUS = 6 -- px, a chip's corners
local LEADER_PX = 1
local ROUTE_PX = 4
local TAG_H = Kit.size.caption + 5 -- px, the tag's height
local TAG_PAD = 4 -- px, the tag's side padding
local TAG_RADIUS = 6 -- px, a tag's and a lens plate's corners
local TAG_DIP = 4 -- px a tag reaches down into its label's top
local PLAN_BADGE_PX = 16 -- px, the planned-action badge
local DIM_FILL = 0.45 -- shape transparency of a dimmed state
local DIM_TEXT = 0.3 -- label transparency of a dimmed state
local TOP_SHADE = 0.18 -- the shape's transparency at its bottom (a top light over the navy)
local BORDER_FADE = 0 -- the border overlay's transparency
local LABEL_STROKE = 0.4 -- the code's dark outline, so it reads on a pale fill
local PART_EDGE = 0.5 -- a lens plate's hairline transparency
local PART_BG = 0 -- a lens plate's backing transparency at rest
local FLIP_EDGE = 2 -- px, a FLIP tag's edge in the new leader's color
local GHOST_STROKE = 0.5
local GHOST_BG = 0.3
local PULSE_FROM = 1.08 -- a pulse's starting scale (a shape is big: a small bump)
local RING_DRAW = 0.1 -- s, the selected outline drawing in
local LENS_FADE = 0.15 -- s, the lens pills fading in on a lens switch
local STAGE_GLOW = 1.35 -- the board's backdrop glow, share of the map
local STAGE_GLOW_FADE = 0.3
local SELECT_GLOW = 1.5 -- the selected state's accent glow, share of its rect
local SELECT_GLOW_FADE = 0.15
local SELECT_GLOW_DIM = 0.45
local SELECT_BREATH = 0.9 -- s, one breath of the selected glow (decorative)
local HALO_W = 40 -- px, the moved-state plate behind the code (at least)
local HALO_PAD = 3 -- px around the code and rows
local HALO_SOFT = 0.55 -- the plate's transparency for a state that moves
local HALO_STRONG = 0.25 -- ... for a state whose poll leader changes
local BLOOM_SCALE = 1.6 -- a moved state's bloom, share of its rect
local BLOOM_SOFT = 0.4
local BLOOM_STRONG = 0.1
local PIN_MIN, PIN_MAX = 18, 28 -- px, a pin's face
local PIN_SHARE = 0.045 -- the face's size, share of the map's width
local PIN_SPREAD = 0.2 -- two close pins stand at least (1 + this) faces apart
local ARROWS = { up = "▲", down = "▼" }
local PREVIEW_BG = 0.35 -- the plan preview tag's backing transparency (a ghost)
local PREVIEW_TEXT = 0.1 -- ... its number's transparency
local PREVIEW_EDGE = 0.45 -- ... its edge's transparency
local PREVIEW_GAP = 2 -- px between the label stack and the preview tag
local ARROW_PX = 18 -- px, a mark's arrow box
local ARROW_GAP = 12 -- px from the code's middle to its arrow

type Part = { label: TextLabel, edge: UIStroke }

type Node = {
	id: string,
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
	halo: Frame,
	lensRow: Frame,
	parts: { Part },
	extras: Frame,
	up: TextLabel,
	pips: Frame,
	arrow: TextLabel,
	badge: TextLabel,
	badgeStroke: UIStroke,
	outline: Frame?,
	outlineParts: { Frame },
	stackH: number, -- px, the label stack's height at the last paint
	preview: TextLabel?, -- the plan preview's tag (D-063), made on first use
	bloom: ImageLabel?,
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

-- A thin rotated frame from (x1, y1) to (x2, y2) in box fractions, `px` thick
-- and `px` longer than the gap (so joints close).
local function segment(
	parent: Instance,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	px: number,
	color: Color3,
	name: string?
): Frame
	local dx = x2 - x1
	local dy = (y2 - y1) / ASPECT -- in box-width units
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
		LayoutOrder = k,
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
	return { label = label, edge = edge }
end

local function hrow(name: string, height: number, parent: Instance): Frame
	local row = Kit.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
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

function ShapeMap.new(): MapInterface.Map
	local data = MapShape.data
	local root = Kit.new("Frame", {
		Name = "NodeMap",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = false,
	})
	root:SetAttribute("Shapes", true)
	Kit.new("UIAspectRatioConstraint", { AspectRatio = ASPECT, Parent = root })

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
	local routeLayer = Kit.box({ Name = "Route", ZIndex = 5, Parent = root })
	local nodeLayer = Kit.box({ Name = "Nodes", ZIndex = 6, Parent = root })
	local tagLayer = Kit.box({ Name = "Tags", ZIndex = 7, Parent = root })
	local pinLayer = Kit.box({ Name = "Pins", ZIndex = 8, Parent = root })
	local legendLayer = Legend.new(root, data.legend)
	-- The plan preview (D-063) on top of everything, so it reads in every lens.
	local previewLayer = Kit.box({ Name = "Preview", ZIndex = 9, Parent = root })

	local selectGlow =
		Kit.glow(glowLayer, Kit.colors.accent, { transparency = SELECT_GLOW_FADE, stretch = true })
	if selectGlow then
		selectGlow.Name = "SelectGlow"
		selectGlow.Visible = false
	end
	local stopBreath: () -> () = function() end

	-- The borders: one white-lines image over the land, tinted the stage navy.
	local b = data.borders
	local borders = Kit.new("ImageLabel", {
		Name = "BorderLines",
		Position = UDim2.fromScale(b.x, b.y),
		Size = UDim2.fromScale(b.w, b.h),
		BackgroundTransparency = 1,
		Image = assetId("mapBorders"),
		ImageColor3 = Kit.colors.background,
		ImageTransparency = BORDER_FADE,
		ScaleType = Enum.ScaleType.Stretch,
		Parent = borderLayer,
	})
	borders:SetAttribute("Asset", "mapBorders")
	borders:SetAttribute("Decor", true)

	local nodes: { Node } = {}
	local byId: { [string]: Node } = {}
	local handlers: { (string) -> () } = {}
	local selected: string? = nil
	local marks: { [string]: MapInterface.Mark } = {}
	local lens: { [string]: MapInterface.LensLine } = {}
	local fills: { [string]: Color3 } = {}
	local pins: { MapInterface.Pin } = {}
	local previews: { [string]: MapInterface.PreviewTag } = {}
	local lastWidth = -1

	local function widthPx(): number
		return root.AbsoluteSize.X
	end

	-- The box in px, as its children are laid out.
	local function boxPx(): (number, number)
		local size = root.AbsoluteSize
		return size.X, size.Y
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
		fire(MapShape.resolve(x, y, pressed))
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

	-- Callout leaders first (under every square).
	for _, shape in MapShape.list() do
		local chip = shape.chip
		if chip then
			segment(
				leaders,
				chip.x,
				chip.y + chip.h / 2,
				shape.lx,
				shape.ly,
				LEADER_PX,
				Kit.colors.line,
				`Leader{shape.id}`
			)
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
		local atlas = data.atlases[shape.atlas]
		local image = Kit.new("ImageLabel", {
			Name = `Shape{id}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(shape.x + shape.w / 2, shape.y + shape.h / 2),
			Size = UDim2.fromScale(shape.w, shape.h),
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
		local lx, ly = MapShape.labelAt(id)
		-- The tap square: a callout's chip cell, else a square on the anchor the
		-- inner circle's size; 36 px at least, growing inward at the map's edges
		-- (the anchor is the square's place in its free range) so it never pokes out.
		local sx = if chip then chip.w else shape.room
		local sy = if chip then chip.h else shape.room * ASPECT
		local ax = math.clamp((lx - sx / 2) / math.max(1 - sx, 1e-6), 0, 1)
		local ay = math.clamp((ly - sy / 2) / math.max(1 - sy, 1e-6), 0, 1)
		local hit: TextButton = Kit.new("TextButton", {
			Name = id,
			AnchorPoint = Vector2.new(ax, ay),
			Position = UDim2.fromScale(lx + (ax - 0.5) * sx, ly + (ay - 0.5) * sy),
			Size = UDim2.fromScale(sx, sy),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = if chip then 3 else 2,
			Parent = nodeLayer,
		})
		Kit.new("UISizeConstraint", { MinSize = Vector2.new(MIN_TAP, MIN_TAP), Parent = hit })

		local chipFrame: Frame? = nil
		local chipStroke: UIStroke? = nil
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
		end

		-- A state a stance or a debate moves: a plate in the mover's color behind
		-- its code (and the outline, in paint).
		local halo = Kit.new("Frame", {
			Name = "Halo",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(HALO_W, LABEL_MIN + 2 * HALO_PAD),
			BackgroundColor3 = Kit.colors.accent,
			BackgroundTransparency = HALO_SOFT,
			BorderSizePixel = 0,
			ZIndex = 4,
			Visible = false,
			Parent = hit,
		})
		halo:SetAttribute("Overhang", true)
		Kit.new("UICorner", { CornerRadius = UDim.new(0, TAG_RADIUS), Parent = halo })

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

		local extras = hrow("Extras", EXTRA_H, hit)
		local up = Kit.text("", {
			Name = "Momentum",
			LayoutOrder = 1,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, EXTRA_H),
			TextSize = Kit.size.caption,
			Font = Kit.font.bold,
			TextStrokeColor3 = Kit.colors.background,
			TextStrokeTransparency = 0.2,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			ZIndex = 6,
			Visible = false,
			Parent = extras,
		})
		Kit.dataColor(up)
		local pipRow = Kit.dataColor(Kit.box({
			Name = "Pips",
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, PIP),
			Visible = false,
			Parent = extras,
		})) :: Frame
		Kit.list("Horizontal", PIP_GAP).Parent = pipRow

		-- A mark's arrow: right of the code (a chip: left of the chip, toward the coast).
		local arrow = Kit.text("", {
			Name = "Arrow",
			AnchorPoint = if chip then Vector2.new(1, 0.5) else Vector2.new(0, 0.5),
			Position = if chip then UDim2.new(0, -CHIP_PAD_X, 0.5, 0) else UDim2.new(0.5, ARROW_GAP, 0.5, 0),
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
			Position = UDim2.fromScale(lx, ly),
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

		local node: Node = {
			id = id,
			shape = shape,
			ladder = chip ~= nil,
			lx = lx,
			ly = ly,
			ax = ax,
			ay = ay,
			sx = sx,
			sy = sy,
			image = image,
			hit = hit,
			chip = chipFrame,
			chipStroke = chipStroke,
			label = label,
			halo = halo,
			lensRow = hrow("Lens", PART_H, hit),
			parts = {},
			extras = extras,
			up = up,
			pips = pipRow,
			arrow = arrow,
			badge = badge,
			badgeStroke = badgeStroke,
			outline = nil,
			outlineParts = {},
			stackH = LABEL_MIN,
			preview = nil,
			bloom = nil,
		}
		table.insert(nodes, node)
		byId[id] = node
		hit.Activated:Connect(function(input: any)
			press(id, input)
		end)
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
		return math.clamp(math.floor(roomPx(node) * LABEL_SHARE), LABEL_MIN, LABEL_MAX)
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

	-- A share of the laid-out width as a size (px when the square grew).
	local function across(node: Node, share: number, pad: number): UDim
		local w, _, growX = natural(node)
		return if growX then UDim.new(0, share * w - pad) else UDim.new(share, -pad)
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

	local function setOutline(node: Node, color: Color3?, px: number)
		if node.ladder then
			local stroke = node.chipStroke :: UIStroke
			stroke.Color = color or Kit.color(Colors.undecided)
			stroke.Thickness = if color then px else CHIP_RING_PX
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
		for _, part in node.outlineParts do
			part.BackgroundColor3 = color
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

	-- Fills a node's lens row from `line` (hidden when the state has no room).
	local function paintLens(node: Node, line: MapInterface.LensLine?)
		local room = roomPx(node)
		local chipW = if node.ladder then (chipPx(node)) else 0
		local roomy = if node.ladder then chipW >= CHIP_LENS_W else room >= LENS_ROOM
		-- A value may reach past a state's edge (unlike a circle's), so a shown
		-- battleground value keeps its ★; a chip needs the width for it.
		local starRoom = if node.ladder then chipW >= CHIP_LENS_W + STAR_CHIP else roomy
		local parts: { MapInterface.LensPart } = if line and roomy then line.parts else {}
		for i, spec in parts do
			if i > #node.parts then
				table.insert(node.parts, newPart(node.lensRow, i))
			end
			local part = node.parts[i]
			local color = spec.color or Kit.colors.text
			part.label.Visible = true
			local star = string.sub(spec.text, 1, #Kit.STAR) == Kit.STAR
			part.label.Text = if star and not starRoom
				then string.sub(spec.text, #Kit.STAR + 1)
				else spec.text
			part.label.TextColor3 = if spec.filled then onFill(color) else color
			part.label.BackgroundColor3 = if spec.filled then color else Kit.colors.field
			part.edge.Color = if spec.filled
				then edgeOf(color)
				elseif spec.outlined then Kit.colors.text
				else Kit.colors.line
			part.edge.Transparency = if spec.filled or spec.outlined then 0 else PART_EDGE
			part.edge.Thickness = if spec.outlined then Kit.MARK_STROKE else 1
		end
		for i = #parts + 1, #node.parts do
			node.parts[i].label.Visible = false
		end
		node.lensRow.Visible = #parts > 0

		-- The Polls extras: ▲ in the momentum leader's color, then the pips.
		local momentum = if line then line.momentum else nil
		node.up.Visible = momentum ~= nil
		if momentum then
			node.up.Text = if line and line.momentumStrong then "▲▲" else "▲"
			node.up.TextColor3 = momentum
		end
		for _, child in node.pips:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local runs: { MapInterface.Pips } = if line and line.pips then line.pips else {}
		local pipPx = math.clamp(math.floor(widthPx() * PIP_SHARE), PIP, PIP_BIG)
		node.pips.Size = UDim2.fromOffset(0, pipPx)
		local slot = 0
		for r, run in runs do
			if r > 1 then
				slot += 1
				Kit.box({
					Name = "Gap",
					LayoutOrder = slot,
					Size = UDim2.fromOffset(PIP_RUN_GAP - 2 * PIP_GAP, pipPx),
					Parent = node.pips,
				})
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
			end
		end
		node.pips.Visible = #runs > 0
		node.extras.Visible = node.up.Visible or node.pips.Visible

		-- Stack the label and rows on the anchor (a chip: code and value side by side).
		local lh = labelPx(node)
		node.label.Size = UDim2.new(1, 0, 0, lh)
		if node.ladder then
			local _, h, _, growY = natural(node)
			local chip = node.chip :: Frame
			local height = if growY then UDim.new(0, h - 2 * CHIP_PAD_Y) else UDim.new(1, -2 * CHIP_PAD_Y)
			chip.Size = UDim2.new(across(node, 1, 2 * CHIP_PAD_X), height)
			chip.Position = onAnchor(node, 0.5, 0)
			-- A moved callout state: the plate glows around its chip.
			node.halo.ZIndex = 2
			node.halo.Size = UDim2.new(
				chip.Size.X.Scale,
				chip.Size.X.Offset + 2 * HALO_PAD,
				height.Scale,
				height.Offset + 2 * HALO_PAD
			)
			node.halo.Position = chip.Position
			local side = node.lensRow.Visible
			node.label.Size =
				UDim2.new(across(node, if side then 0.5 else 1, CHIP_PAD_X), UDim.new(0, math.min(lh, h)))
			node.label.Position = onAnchor(node, if side then 0.27 else 0.5, 0)
			node.lensRow.Size = UDim2.new(across(node, 0.5, CHIP_PAD_X), UDim.new(0, PART_H))
			node.lensRow.Position = onAnchor(node, 0.73, 0)
			-- Extras beside the chip, toward the coast.
			node.extras.AnchorPoint = Vector2.new(1, 0.5)
			node.extras.Size = UDim2.fromOffset(0, EXTRA_H)
			node.extras.AutomaticSize = Enum.AutomaticSize.X
			node.extras.Position = onAnchor(node, 0, 0)
			return
		end
		local rows: { { inst: GuiObject, h: number } } = { { inst = node.label :: GuiObject, h = lh } }
		if node.lensRow.Visible then
			table.insert(rows, { inst = node.lensRow :: GuiObject, h = PART_H })
		end
		if node.extras.Visible then
			table.insert(rows, { inst = node.extras :: GuiObject, h = EXTRA_H })
		end
		local total = 0
		for k, row in rows do
			total += row.h + (if k > 1 then ROW_GAP else 0)
		end
		node.stackH = total
		node.halo.Size = UDim2.fromOffset(HALO_W, total + 2 * HALO_PAD)
		node.halo.Position = onAnchor(node, 0.5, 0)
		local y = -total / 2
		for k, row in rows do
			if k > 1 then
				y += ROW_GAP
			end
			row.inst.Position = onAnchor(node, 0.5, y + row.h / 2)
			y += row.h
		end
	end

	-- Where a node's tag sits: on top of its label (a chip: at its left edge).
	local function placeTag(node: Node, tag: GuiObject)
		if node.ladder then
			-- Left of the chip, over the sea between the coast and the column.
			local chip = node.shape.chip :: MapShape.Rect
			tag.AnchorPoint = Vector2.new(1, 0.5)
			tag.Position = UDim2.fromScale(chip.x, node.ly)
			return
		end
		local lh = labelPx(node)
		local up = lh / 2 + (if node.lensRow.Visible then (PART_H + ROW_GAP) / 2 else 0)
		local _, bh = boxPx()
		local topPx = node.ly * bh - up
		local ax = math.clamp(node.lx, 0.1, 0.9)
		if bh > 0 and topPx - TAG_H + TAG_DIP < 0 then
			tag.AnchorPoint = Vector2.new(ax, 0)
			tag.Position = UDim2.fromScale(node.lx, 0)
		else
			tag.AnchorPoint = Vector2.new(ax, 1)
			tag.Position = UDim2.new(node.lx, 0, node.ly, -up + TAG_DIP)
		end
	end

	local function paint(node: Node)
		local mark = marks[node.id]
		local line = lens[node.id]
		local isSelected = selected == node.id
		local dim = (mark ~= nil and mark.dim == true) or (line ~= nil and line.dim == true)
		local fill = fills[node.id] or Kit.color(Colors.neutral)
		node.image.ImageColor3 = fill
		node.image.ImageTransparency = if dim then DIM_FILL else 0
		if node.chip then
			local chip = node.chip :: Frame
			chip.BackgroundColor3 = fill
			chip.BackgroundTransparency = if dim then DIM_FILL else 0
		end
		node.label.TextTransparency = if dim then DIM_TEXT else 0
		node.label.TextStrokeTransparency = if dim then 1 else LABEL_STROKE
		node.label.Visible = true
		paintLens(node, line)

		local halo = if mark then mark.halo else nil
		local strong = mark ~= nil and mark.haloStrong == true
		if isSelected then
			setOutline(node, Kit.colors.accent, SELECTED_PX)
		elseif mark and mark.ring then
			setOutline(node, mark.ring, SELECTED_PX)
		elseif halo then
			setOutline(node, halo, if strong then SELECTED_PX else OUTLINE_PX)
		else
			setOutline(node, nil, 0)
		end
		node.halo.Visible = halo ~= nil
		if halo then
			node.halo.BackgroundColor3 = halo
			node.halo.BackgroundTransparency = if strong then HALO_STRONG else HALO_SOFT
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
			node.badge.TextColor3 = Kit.colors.text
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

	local function paintPins()
		for _, child in pinLayer:GetChildren() do
			child:Destroy()
		end
		local bw, bh = boxPx()
		local px = math.clamp(math.floor((if bw > 0 then bw else 600) * PIN_SHARE), PIN_MIN, PIN_MAX)
		-- Each pin's tip in px: on its state's label top (a callout state: on its
		-- real place), never above the map's top edge (a pin on WA or ME then
		-- covers its code).
		type Spot = { pin: MapInterface.Pin, x: number, y: number, frame: Frame }
		local spots: { Spot } = {}
		for _, pin in pins do
			local node = byId[pin.state]
			if node then
				local frame = Pins.build(pin, px)
				local s = node.shape
				local up = if node.ladder then 0 else labelPx(node) / 2
				local tall = frame.Size.Y.Offset
				local y = s.ly * bh - up
				if bh > 0 then
					y = math.max(y, tall)
				end
				table.insert(spots, { pin = pin, x = s.lx * bw, y = y, frame = frame })
			end
		end
		-- Two pins that would cover each other (the same state, or neighbors)
		-- stand side by side, each half the overlap away.
		local wide = px * (1 + PIN_SPREAD)
		for i = 1, #spots do
			for j = i + 1, #spots do
				local p, q = spots[i], spots[j]
				local dx = q.x - p.x
				if math.abs(dx) < wide and math.abs(q.y - p.y) < px * 2 then
					local push = (wide - math.abs(dx)) / 2
					local sign = if dx >= 0 then 1 else -1
					p.x -= sign * push
					q.x += sign * push
				end
			end
		end
		local half = px / 2 + Pins.FLAG_H
		for _, spot in spots do
			local x = if bw > 0 then math.clamp(spot.x, half, bw - half) else spot.x
			spot.frame.Position = if bw > 0
				then UDim2.fromScale(x / bw, spot.y / bh)
				else UDim2.fromScale(0.5, 0.5)
			spot.frame.ZIndex = if spot.pin.you then 2 else 1
			spot.frame.Parent = pinLayer
		end
	end

	-- The plan preview's tag: just under the state's label stack (a chip: left
	-- of it, past its badge), turned over the code near the map's bottom.
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
		if node.ladder then
			local chip = node.shape.chip :: MapShape.Rect
			local past = if node.badge.Visible then node.badge.AbsoluteSize.X + 2 else 0
			label.AnchorPoint = Vector2.new(1, 0.5)
			label.Position = UDim2.new(chip.x, -2 - past, node.ly, 0)
			return
		end
		local _, bh = boxPx()
		local below = node.stackH / 2 + PREVIEW_GAP
		if bh > 0 and node.ly * bh + below + TAG_H > bh then
			-- Near the bottom: over the code instead.
			label.AnchorPoint = Vector2.new(0.5, 1)
			label.Position = UDim2.new(node.lx, 0, node.ly, -below)
		else
			label.AnchorPoint = Vector2.new(0.5, 0)
			label.Position = UDim2.new(node.lx, 0, node.ly, below)
		end
	end

	local function paintAll()
		for _, node in nodes do
			paint(node)
			paintPreview(node)
		end
		paintPins()
	end

	local map = {} :: any
	map.root = root

	-- Repaint when the map's size changes: rooms, labels, chips and pins are in px.
	pcall(function()
		(root :: any):GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if root.AbsoluteSize.X ~= lastWidth then
				lastWidth = root.AbsoluteSize.X
				paintAll()
			end
		end)
	end)

	function map.setView(_self: any, view: View.View, colors: { Colors.RGB })
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
			fills[s.id] = Kit.color(fill)
			local node = byId[s.id]
			if node then
				paint(node)
				paintPreview(node)
			end
		end
	end

	function map.setMarks(_self: any, newMarks: { [string]: MapInterface.Mark })
		marks = newMarks
		for _, node in nodes do
			paint(node)
			paintPreview(node)
		end
	end

	function map.setLens(_self: any, newLens: { [string]: MapInterface.LensLine }, fade: boolean?)
		lens = newLens
		for _, node in nodes do
			paint(node)
			paintPreview(node)
			if fade and node.lensRow.Visible then
				for _, part in node.parts do
					if part.label.Visible then
						part.label.TextTransparency = 1
						part.label.BackgroundTransparency = 1
						Motion.tween(
							part.label,
							{ TextTransparency = 0, BackgroundTransparency = PART_BG },
							LENS_FADE
						)
					end
				end
			end
		end
		paintPins()
	end

	function map.setRoute(_self: any, stops: { string }, flights: { boolean })
		for _, child in routeLayer:GetChildren() do
			child:Destroy()
		end
		local px, py = nil, nil
		for k, id in stops do
			local shape = MapShape.get(id)
			if shape then
				if px and py then
					local line = segment(routeLayer, px, py, shape.lx, shape.ly, ROUTE_PX, Kit.colors.accent)
					line.BackgroundTransparency = if flights[k] then 0.55 else 0
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
		placeTag(node, ghost)
		ghost.Text = text
		ghost.Visible = true
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
		pins = newPins
		paintPins()
	end

	function map.setLegend(_self: any, items: { MapInterface.LegendItem }?)
		Legend.fill(legendLayer, items)
	end

	function map.setPreview(_self: any, tags: { [string]: MapInterface.PreviewTag }?)
		previews = tags or {}
		for _, node in nodes do
			paintPreview(node)
		end
	end

	function map.destroy(_self: any)
		handlers = {}
		stopBreath()
		root:Destroy()
	end

	paintAll()
	return map :: MapInterface.Map
end

return ShapeMap
