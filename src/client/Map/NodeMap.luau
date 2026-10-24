--!strict
-- The map every screen mounts: NodeMap.new() returns the real map (Map/ShapeMap,
-- D-070) once its images are uploaded (UI/Assets mapStates*, mapBorders), and
-- these circles until then, so the game always has a map. NodeMap.preview = true
-- (the headless specs and snapshots) takes the real map without the uploads;
-- NodeMap.circles() always builds the circles.
--
-- The circle map: one circle per state from Shared/UI/MapLayout, built from plain
-- frames (no art assets). Fill steps toward the public-poll leader's color in
-- four bands by the lead in points (Colors.bandFill: toss-up grey, lean, likely,
-- safe; the Campaign "Map key" shows them), lit a little from the top; a
-- thin grey ring outlines it (an owner's ring in their color, the selected
-- state's in the accent); thin lines are land borders. The nine small Northeast
-- states stand in a ladder at the right edge (MapLayout.LADDER), each with a
-- thin leader line to where it really is. The circle is drawn a little inside
-- its layout radius so rings never touch a neighbor's (docs/UI-STYLE.md §4.6).
--
-- A screen's marks can add a badge in any color ("+1.5" in a player's color),
-- a word ("FLIP") and a glow behind the circle: the Choice preview and the
-- reveals use them to show which states moved (D-042). Badge and word share one
-- solid tag on the circle's top edge, drawn in the Tags layer above every node,
-- so no neighbor's circle hides it and it never sits on another state's label.
--
-- The lens value (Map/Lens, D-046) sits inside the circle, under the state's
-- code: one short pill ("17", "JOB", "+3", "$2.4") on a dark backing so it reads
-- on any fill. Nothing pokes out of the circle into a neighbor. A circle too
-- small for two lines (under TWO_LINES px across, e.g. the small states on a
-- phone) shows only its code; its card has the numbers.
--
-- Each state is one invisible tap target (a TextButton named by the state id)
-- at least Kit.MAP_NODE_MIN px in both directions. Everything drawn for the
-- state lives inside it except its tag: the circle with its label, then the
-- momentum arrow band at the bottom. Smaller states are created last, so where two
-- tap targets overlap the smaller state gets the tap.
--
-- Motion API (UI/Motion, docs/DESIGN.md D-053): map:pulse(id, color?) bumps a
-- circle, map:ring(id, color) sends a ring out of it, map:badge(id, icon?) pins
-- a 16 px action icon at the node's top-right ("PlanBadge"; nil removes it),
-- map:wipe(id, color) turns a circle's fill (an election call; it holds until
-- the next setView). The drawing above is unchanged by them.
--
-- Board motion (WP-1): the selected state's accent ring draws in (0 -> 3 px);
-- a removed PlanBadge fades out; map:ghost(id, text?) shows what a held action
-- button would do ("+4.1") as a see-through tag on the node ("GhostTag"), nil
-- hides it; setLens(lines, true) fades the lens pills in (a lens switch, 0.15 s).
-- Nodes never move.
--
-- The stage (front-page pass, docs/DESIGN.md D-056): a navy glow behind the
-- whole board (StageGlow), a soft contact shadow under every circle (the
-- Shadows layer, under the lines' ends and every node), a visible top light on
-- the circle, a breathing accent glow under the selected state (SelectGlow),
-- and solid tags: lens values on a dark field plate in Fredoka (a battleground's
-- "★13" outlined in white: a white fill means only "selected"), marks filled
-- in their color with readable text (a loss orange with a dark number), a FLIP
-- a dark plate with a 2 px edge in the new leader's color. Every glow and
-- shadow is Decor (UI/Kit glow).
--
-- The drawn circle keeps its layout size (CIRCLE_SHARE of the layout diameter)
-- even where the 36 px tap minimum makes the tap target bigger than the layout
-- (a phone): the circle shrinks inside its grown target, so neighbors' rings
-- and letters never overlap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local MapInterface = require(script.Parent.MapInterface)
local MapLayout = require(ReplicatedStorage.Shared.UI.MapLayout)
local Kit = require(script.Parent.Parent.UI.Kit)
local Legend = require(script.Parent.Legend)
local Motion = require(script.Parent.Parent.UI.Motion)
local Pins = require(script.Parent.Pins)
local ShapeMap = require(script.Parent.ShapeMap)
local View = require(ReplicatedStorage.Shared.Sim.View)

local NodeMap = {}

-- Build the real map even before its images are uploaded (tests and snapshots).
NodeMap.preview = false

local MIN_TAP = Kit.MAP_NODE_MIN -- px, smallest tap target per state
local LINE_PX = 2
local LEADER_PX = 1
local ROUTE_PX = 4
local RING_PX = 2 -- the grey outline
local OWNER_RING_PX = 3 -- a home state's or stronghold's ring
local SELECTED_RING_PX = 3 -- the selected state's accent ring
local CIRCLE_SHARE = 0.88 -- the drawn circle's share of its layout diameter (room for the ring)
local TWO_LINES = 30 -- px, the smallest circle that shows its code and a lens value
local STAR_ROOM = 40 -- px, the smallest circle whose battleground value keeps its ★
local LABEL_H = 0.4 -- label band height, share of the tap target
local BAND_H = 0.3 -- arrow band (bottom), share of the tap target
local TAG_H = Kit.size.caption + 5 -- px, the tag's height
local TAG_PAD = 4 -- px, the tag's side padding
local TAG_DIP = 8 -- px a tag reaches into its circle's rim
local TAG_TOP = 0.06 -- a circle whose top is this close to the map's top (box heights) pins its tag there
local DIM_FILL = 0.45 -- circle transparency of a dimmed state
local DIM_TEXT = 0.3 -- label transparency of a dimmed state
local ARROWS = { up = "▲", down = "▼" }
local HALO_SCALE = 1.32 -- a moved state's aura disc, share of the circle (at most the tap target)
local HALO_SOFT = 0.55 -- aura transparency for a state that moves
local HALO_STRONG = 0.25 -- aura transparency for a state whose poll leader changes
local BLOOM_SCALE = 2.6 -- the soft bloom under a moved state, share of the circle's diameter
local BLOOM_SOFT = 0.4 -- bloom transparency for a state that moves
local BLOOM_STRONG = 0.1 -- bloom transparency for a state whose poll leader changes
local PART_H = Kit.size.caption + 2 -- px, a lens plate's height (snug, so code and value fit a 30 px circle)
local PART_PAD = 3 -- px, a lens pill's side padding
local PART_GAP = 2 -- px, between two lens pills
local LABEL_Y = 0.5 -- the label's center, share of the tap target
local LABEL_UP = 0.21 -- with a lens value: the label's center above the middle, share of the circle
local VALUE_DOWN = 0.21 -- ... the value's center below the middle, share of the circle
local LABEL_H_LENS = 0.36 -- ... the label's height, share of the circle
local PULSE_FROM = 1.15 -- a pulse's starting scale (it settles to 1)
local PLAN_BADGE_PX = 16 -- px, the planned-action badge
local BORDER_FADE = 0.55 -- land borders' transparency, so the nodes stand out
local TOP_SHADE = 0.22 -- the circle's transparency at its bottom: the darker lip shows through (a top light)
local LIP_DY = 3 -- px, the lip under a circle
local LIP_SHADE = 0.55 -- the lip: the ring's color this far toward the background
local STAGE_GLOW = 1.35 -- the board's backdrop glow, share of the map (an ellipse)
local STAGE_GLOW_FADE = 0.3 -- its transparency
local SHADOW_SCALE = 1.7 -- a node's contact shadow, share of the circle's diameter
local SHADOW_DY = 5 -- px the contact shadow drops below the circle
local SHADOW_FADE = 0.25 -- the contact shadow's transparency (the glow image fades fast)
local SELECT_GLOW = 2.6 -- the selected state's accent glow, share of the circle's diameter
local SELECT_GLOW_FADE = 0.15 -- its transparency at its brightest
local SELECT_GLOW_DIM = 0.45 -- ... and at the low point of its breath
local SELECT_BREATH = 0.9 -- s, one breath of the selected glow (decorative)
local TAG_RADIUS = 6 -- px, a tag's and a lens plate's corners
local PART_EDGE = 0.5 -- a lens plate's hairline transparency
local LABEL_STROKE = 0.55 -- the state code's dark outline, so it reads on a pale fill
local FLIP_EDGE = 2 -- px, a FLIP tag's edge in the new leader's color
local RING_DRAW = 0.1 -- s, the selected ring drawing in
local LENS_FADE = 0.15 -- s, the lens pills fading in on a lens switch
local PART_BG = 0 -- a lens plate's backing transparency at rest
local GHOST_STROKE = 0.5 -- the ghost tag's outline transparency
local GHOST_BG = 0.3 -- the ghost tag's backing transparency
local PIN_PX = 22 -- px, a candidate pin's face on the circle map
local PREVIEW_LOW = 0.85 -- a circle whose bottom is below this (box heights) shows its plan preview over it
local LEGEND_RECT = { x = 0.3, y = 0.9, w = 0.5, h = 0.09 } -- the legend strip (under the Gulf)

type Node = {
	id: string,
	x: number, -- center, box widths
	y: number, -- center, box heights
	r: number, -- layout radius, box widths
	h: number, -- the tap target's half side, box widths (MapLayout.hitRadius)
	k: number, -- the drawn circle's share of the tap target as laid out
	hit: TextButton,
	circle: Frame,
	halo: Frame,
	bloom: ImageLabel,
	shadow: ImageLabel,
	lip: Frame,
	ring: UIStroke,
	label: TextLabel,
	badge: TextLabel,
	badgeStroke: UIStroke,
	arrow: TextLabel,
	lensRow: Frame,
	parts: { TextLabel },
	edges: { UIStroke },
}

-- The edge of a solid tag in `fill`: the loss orange's own edge token, else
-- the fill 35 % toward the background (as Kit.pill's data-colored edge).
local function edgeOf(fill: Color3): Color3
	if fill == Kit.colors.loss then
		return Kit.colors.lossEdge
	elseif fill == Kit.colors.text then
		return Kit.colors.line
	end
	return Kit.color(Colors.tint(Kit.rgb(fill), Colors.background, 0.35))
end

-- The readable text on a solid `fill` (dark on light, white on dark).
local function onFill(fill: Color3): Color3
	if fill == Kit.colors.loss then
		return Kit.colors.onLoss
	end
	return Kit.color(Colors.onColor(Kit.rgb(fill)))
end

-- A thin rotated frame from (x1, y1) to (x2, y2) in box fractions.
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
	local dy = (y2 - y1) / MapLayout.ASPECT -- in box-width units
	local length = math.sqrt(dx * dx + dy * dy)
	return Kit.new("Frame", {
		Name = name or "Frame",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale((x1 + x2) / 2, (y1 + y2) / 2),
		Size = UDim2.new(length, 0, 0, px),
		Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = parent,
	})
end

-- The lens value's row inside the circle, under the code, centered.
local function newLensRow(hit: Instance, k: number): Frame
	local row = Kit.new("Frame", {
		Name = "Lens",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5 + VALUE_DOWN * k),
		Size = UDim2.new(1, 0, 0, PART_H),
		ZIndex = 6,
		Visible = false,
		Parent = hit,
	})
	local list = Kit.list("Horizontal", PART_GAP)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = row
	return row
end

-- One pill of a lens row (made on first use, then reused).
-- Where a node's tag sits: on the drawn circle's top edge, dipping TAG_DIP px
-- into it, so it rarely covers the state's code; a circle at the very top of
-- the map pins its tag to the map's top edge instead (it stays inside the map).
-- Its x anchor follows the node across the map, so a wide tag near a side edge
-- grows inward and stays inside the map.
local function tagPlace(n: MapLayout.Node): (Vector2, UDim2)
	local top = n.y - n.r * CIRCLE_SHARE * MapLayout.ASPECT -- the drawn circle's top, box heights
	local ax = math.clamp(n.x, 0, 1)
	if top < TAG_TOP then
		return Vector2.new(ax, 0), UDim2.fromScale(n.x, 0)
	end
	return Vector2.new(ax, 1), UDim2.new(n.x, 0, top, TAG_DIP)
end

-- A dark field plate with a hairline and a Fredoka number (the EV tag).
local function newPart(row: Frame, k: number): (TextLabel, UIStroke)
	local part = Kit.text("", {
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
	Kit.new("UICorner", { CornerRadius = UDim.new(0, TAG_RADIUS), Parent = part })
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, PART_PAD),
		PaddingRight = UDim.new(0, PART_PAD),
		Parent = part,
	})
	local edge = Kit.stroke(Kit.colors.line, 1)
	edge.Name = "Edge"
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Transparency = PART_EDGE
	edge.Parent = part
	return part, edge
end

-- Fills a node's lens row from `line` (nil or no parts, or a circle too small
-- for two lines: hidden).
-- `k` is the drawn circle's share of the tap target.
-- `starRoom`: the circle is wide enough for "★13"; a smaller one shows the
-- battleground by its white outline alone ("13"), so the plate fits inside.
local function paintLens(
	node: Node,
	line: MapInterface.LensLine?,
	roomy: boolean,
	k: number,
	starRoom: boolean
)
	local parts: { MapInterface.LensPart } = if line and roomy then line.parts else {}
	for i, spec in parts do
		if i > #node.parts then
			local part, edge = newPart(node.lensRow, i)
			table.insert(node.parts, part)
			table.insert(node.edges, edge)
		end
		local part, edge = node.parts[i], node.edges[i]
		local color = spec.color or Kit.colors.text
		part.Visible = true
		local star = string.sub(spec.text, 1, #Kit.STAR) == Kit.STAR
		part.Text = if star and not starRoom then string.sub(spec.text, #Kit.STAR + 1) else spec.text
		-- Filled: a solid plate in the color with readable text and its edge
		-- (an issue of yours, a poll lead). Outlined: the dark plate with a
		-- Kit.MARK_STROKE white edge (the battleground mark, D-058).
		part.TextColor3 = if spec.filled then onFill(color) else color
		part.BackgroundColor3 = if spec.filled then color else Kit.colors.field
		edge.Color = if spec.filled
			then edgeOf(color)
			elseif spec.outlined then Kit.colors.text
			else Kit.colors.line
		edge.Transparency = if spec.filled or spec.outlined then 0 else PART_EDGE
		edge.Thickness = if spec.outlined then Kit.MARK_STROKE else 1
	end
	for i = #parts + 1, #node.parts do
		node.parts[i].Visible = false
	end
	local shown = #parts > 0
	node.lensRow.Visible = shown
	node.lensRow.Position = UDim2.fromScale(0.5, 0.5 + VALUE_DOWN * k)
	node.label.Position = UDim2.fromScale(0.5, if shown then 0.5 - LABEL_UP * k else LABEL_Y)
	node.label.Size = UDim2.fromScale(MapLayout.LABEL_SCALE * k, if shown then LABEL_H_LENS * k else LABEL_H)
end

-- The real map when it can show, else the circles.
function NodeMap.new(): MapInterface.Map
	if NodeMap.preview or ShapeMap.ready() then
		return ShapeMap.new()
	end
	return NodeMap.circles()
end

function NodeMap.circles(): MapInterface.Map
	local root = Kit.new("Frame", {
		Name = "NodeMap",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = false,
	})
	Kit.new("UIAspectRatioConstraint", { AspectRatio = MapLayout.ASPECT, Parent = root })

	-- The stage: a wide navy glow under everything, so the board reads as a lit table.
	local stage = Kit.glow(root, Kit.colors.glow, {
		scale = STAGE_GLOW,
		transparency = STAGE_GLOW_FADE,
		stretch = true,
	})
	if stage then
		stage.Name = "StageGlow"
	end
	local lines = Kit.box({ Name = "Lines", ZIndex = 1, Parent = root })
	local leaders = Kit.box({ Name = "Leaders", ZIndex = 1, Parent = root })
	-- Contact shadows and the selected glow: under every node, so a glow never
	-- tints a neighbor's circle.
	local shadowLayer = Kit.box({ Name = "Shadows", ZIndex = 2, Parent = root })
	local routeLayer = Kit.box({ Name = "Route", ZIndex = 3, Parent = root })
	local nodeLayer = Kit.box({ Name = "Nodes", ZIndex = 4, Parent = root })
	local tagLayer = Kit.box({ Name = "Tags", ZIndex = 5, Parent = root })
	local selectGlow =
		Kit.glow(shadowLayer, Kit.colors.accent, { transparency = SELECT_GLOW_FADE }) :: ImageLabel
	selectGlow.Name = "SelectGlow"
	selectGlow.ZIndex = 2
	selectGlow.Visible = false
	local stopBreath: () -> () = function() end

	local layout = MapLayout.nodes()
	-- Borders between projected states; a ladder state gets its leader instead.
	for _, edge in MapLayout.edges() do
		local a, b = layout[edge[1]], layout[edge[2]]
		if not a.ladder and not b.ladder then
			local border = segment(lines, a.x, a.y, b.x, b.y, LINE_PX, Kit.colors.line)
			border.BackgroundTransparency = BORDER_FADE
		end
	end
	for _, n in layout do
		if n.ladder then
			segment(leaders, n.x, n.y, n.cx, n.cy, LEADER_PX, Kit.colors.line, `Leader{n.id}`)
		end
	end

	local nodes: { Node } = {}
	local byId: { [string]: Node } = {}
	local handlers: { (string) -> () } = {}
	local selected: string? = nil

	-- Biggest first, so the smaller of two overlapping tap targets is on top.
	local order: { number } = {}
	for i in layout do
		table.insert(order, i)
	end
	table.sort(order, function(a: number, b: number): boolean
		if layout[a].r ~= layout[b].r then
			return layout[a].r > layout[b].r
		end
		return a < b
	end)

	for _, i in order do
		local n = layout[i]
		local h = MapLayout.hitRadius(n)
		local k = n.r / h * CIRCLE_SHARE -- the drawn circle's share of the tap target
		-- Centered on the node; on a map so small that MIN_TAP clamps the target,
		-- the anchor (the node's place in its free range) makes it grow inward,
		-- so it never pokes out of the map.
		local sx, sy = 2 * h, 2 * h * MapLayout.ASPECT
		local ax = math.clamp((n.x - sx / 2) / (1 - sx), 0, 1)
		local ay = math.clamp((n.y - sy / 2) / (1 - sy), 0, 1)
		local hit = Kit.new("TextButton", {
			Name = n.id,
			AnchorPoint = Vector2.new(ax, ay),
			Position = UDim2.fromScale(n.x + (ax - 0.5) * sx, n.y + (ay - 0.5) * sy),
			Size = UDim2.fromScale(sx, sy),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 3,
			Parent = nodeLayer,
		})
		Kit.new("UISizeConstraint", { MinSize = Vector2.new(MIN_TAP, MIN_TAP), Parent = hit })
		-- The contact shadow: in the Shadows layer, sized to the drawn circle in
		-- map units (the circle never grows past its layout size), dropped a little.
		local reach = 2 * n.r * CIRCLE_SHARE * SHADOW_SCALE
		local shadow =
			Kit.glow(shadowLayer, Kit.colors.background, { transparency = SHADOW_FADE }) :: ImageLabel
		shadow.Name = `Shadow{n.id}`
		shadow.Position = UDim2.new(n.x, 0, n.y, SHADOW_DY)
		shadow.Size = UDim2.fromScale(reach, reach * MapLayout.ASPECT)
		shadow.ZIndex = 1
		-- The lip: a darker disc (the ring's color, toward the background) just
		-- below the circle, so a node reads as a chunky token, like Kit's buttons.
		local lip = Kit.new("Frame", {
			Name = `Lip{n.id}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(n.x, 0, n.y, LIP_DY),
			Size = UDim2.new(
				2 * n.r * CIRCLE_SHARE,
				2 * RING_PX,
				2 * n.r * CIRCLE_SHARE * MapLayout.ASPECT,
				2 * RING_PX
			),
			BackgroundColor3 = Kit.colors.raisedLip,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = shadowLayer,
		})
		Kit.round().Parent = lip
		-- A state a stance or a debate moves: a soft bloom in the Shadows layer
		-- (under every node, so it never tints a neighbor) and an aura disc just
		-- behind the circle (lower ZIndex among the node's children); paint sizes it.
		local bloomReach = 2 * n.r * CIRCLE_SHARE * BLOOM_SCALE
		local bloom = Kit.glow(shadowLayer, Kit.colors.accent, { transparency = BLOOM_SOFT }) :: ImageLabel
		bloom.Name = `Bloom{n.id}`
		bloom.Position = UDim2.fromScale(n.x, n.y)
		bloom.Size = UDim2.fromScale(bloomReach, bloomReach * MapLayout.ASPECT)
		bloom.ZIndex = 0
		bloom.Visible = false
		local halo = Kit.new("Frame", {
			Name = "Halo",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = Kit.colors.accent,
			BackgroundTransparency = HALO_SOFT,
			BorderSizePixel = 0,
			ZIndex = 2,
			Visible = false,
			Parent = hit,
		})
		Kit.round().Parent = halo
		local circle = Kit.new("Frame", {
			Name = "Circle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(k, k),
			BackgroundColor3 = Kit.color(Colors.neutral),
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = hit,
		})
		Kit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = circle })
		Kit.round().Parent = circle
		-- Lit from the top: the fill (data) at the top; toward the bottom the darker
		-- lip under it shows through, a shade darker. (Transparency, not Color, so
		-- the fill stays the data color and no color literal is needed.)
		Kit.new("UIGradient", {
			Name = "Depth",
			Rotation = 90,
			Transparency = NumberSequence.new(0, TOP_SHADE),
			Parent = circle,
		})
		local ring = Kit.stroke(Kit.color(Colors.undecided), RING_PX)
		ring.Parent = circle
		local label = Kit.text(n.id, {
			Name = "Label",
			Size = UDim2.fromScale(MapLayout.LABEL_SCALE * k, LABEL_H),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, LABEL_Y),
			TextScaled = true,
			TextSize = Kit.size.heading,
			Font = Kit.font.bold,
			TextStrokeColor3 = Kit.colors.background,
			TextStrokeTransparency = LABEL_STROKE,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			ZIndex = 4,
			Parent = hit,
		})
		local anchor, place = tagPlace(n)
		local badge = Kit.text("", {
			Name = n.id,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, TAG_H),
			AnchorPoint = anchor,
			Position = place,
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
		local arrow = Kit.text("", {
			Name = "Arrow",
			Size = UDim2.fromScale(1, BAND_H),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			TextScaled = true,
			TextSize = Kit.size.body,
			Font = Kit.font.bold,
			TextStrokeColor3 = Kit.colors.background,
			TextStrokeTransparency = 0.3,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			ZIndex = 5,
			Visible = false,
			Parent = hit,
		})
		local node: Node = {
			id = n.id,
			x = n.x,
			y = n.y,
			r = n.r,
			h = h,
			k = k,
			hit = hit,
			circle = circle,
			halo = halo,
			bloom = bloom,
			shadow = shadow,
			lip = lip,
			ring = ring,
			label = label,
			badge = badge,
			badgeStroke = badgeStroke,
			arrow = arrow,
			lensRow = newLensRow(hit, k),
			parts = {},
			edges = {},
		}
		nodes[i] = node
		byId[n.id] = node
		hit.Activated:Connect(function()
			for _, handler in handlers do
				task.spawn(handler, n.id)
			end
		end)
	end

	local marks: { [string]: MapInterface.Mark } = {}
	local lens: { [string]: MapInterface.LensLine } = {}
	local fills: { [string]: Color3 } = {}

	-- Is this node's circle big enough on screen for its code and a lens value?
	-- (Before the first layout the size is unknown: assume it is.)
	local function roomy(node: Node): boolean
		local width = root.AbsoluteSize.X
		return width <= 0 or 2 * node.r * CIRCLE_SHARE * width >= TWO_LINES
	end

	-- ... and for a starred battleground value ("★13")?
	local function starRoom(node: Node): boolean
		local width = root.AbsoluteSize.X
		return width <= 0 or 2 * node.r * CIRCLE_SHARE * width >= STAR_ROOM
	end

	-- The drawn circle's share of the tap target as laid out: k, unless the
	-- 36 px minimum grew the target past its layout size (a phone), where the
	-- circle keeps its layout size inside it.
	local function shareOf(node: Node): number
		local width = root.AbsoluteSize.X
		if width <= 0 then
			return node.k
		end
		local natural = 2 * node.h * width
		return node.k * natural / math.max(natural, MIN_TAP)
	end

	local function paint(node: Node)
		local mark = marks[node.id]
		local line = lens[node.id]
		local isSelected = selected == node.id
		local dim = (mark ~= nil and mark.dim == true) or (line ~= nil and line.dim == true)
		local k = shareOf(node)
		node.circle.Size = UDim2.fromScale(k, k)
		node.circle.BackgroundColor3 = fills[node.id] or Kit.color(Colors.neutral)
		node.circle.BackgroundTransparency = if dim then DIM_FILL else 0
		node.label.TextTransparency = if dim then DIM_TEXT else 0
		node.label.TextStrokeTransparency = if dim then 1 else LABEL_STROKE
		node.shadow.ImageTransparency = if dim then 1 - (1 - SHADOW_FADE) / 2 else SHADOW_FADE
		paintLens(node, line, roomy(node), k, starRoom(node))
		if isSelected then
			node.ring.Color = Kit.colors.accent
			node.ring.Thickness = SELECTED_RING_PX
		elseif mark and mark.ring then
			node.ring.Color = mark.ring
			node.ring.Thickness = OWNER_RING_PX
		else
			node.ring.Color = Kit.color(Colors.undecided)
			node.ring.Thickness = RING_PX
		end
		node.lip.BackgroundColor3 =
			Kit.color(Colors.tint(Kit.rgb(node.ring.Color), Colors.background, LIP_SHADE))
		node.lip.BackgroundTransparency = if dim then DIM_FILL else 0
		-- One solid tag holds the badge and the word: "+1.5", "FLIP" or "+1.5 FLIP".
		-- A badge fills the tag in its color with readable text (a loss: orange
		-- with a dark number); a word makes it a dark plate with a 2 px edge in
		-- its color, so a flip reads at a glance.
		local badge = if mark then mark.badge else nil
		local word = if mark then mark.note else nil
		local tag = if badge and word then `{badge} {word}` else badge or word
		node.badge.Visible = tag ~= nil
		node.badge.Text = tag or ""
		if word then
			local note = if mark then mark.noteColor else nil
			node.badge.BackgroundColor3 = Kit.colors.field
			node.badge.TextColor3 = Kit.colors.text
			node.badgeStroke.Color = note or Kit.colors.line
			node.badgeStroke.Thickness = FLIP_EDGE
		else
			local fill = if mark and mark.badgeColor then mark.badgeColor else Kit.colors.accent
			node.badge.BackgroundColor3 = fill
			node.badge.TextColor3 = onFill(fill)
			node.badgeStroke.Color = edgeOf(fill)
			node.badgeStroke.Thickness = 1
		end
		local halo = if mark then mark.halo else nil
		local strong = mark ~= nil and mark.haloStrong == true
		node.halo.Visible = halo ~= nil
		-- An accent ring (the screen's own highlight: the next call on election
		-- night, a draft pick) blooms in the accent too, as the selection does.
		local lit = halo == nil and mark ~= nil and mark.ring == Kit.colors.accent and not isSelected
		node.bloom.Visible = halo ~= nil or lit
		if lit then
			node.bloom.ImageColor3 = Kit.colors.accent
			node.bloom.ImageTransparency = SELECT_GLOW_FADE
		end
		if halo then
			local size = math.min(1, k * HALO_SCALE)
			node.halo.Size = UDim2.fromScale(size, size)
			node.halo.BackgroundColor3 = halo
			node.halo.BackgroundTransparency = if strong then HALO_STRONG else HALO_SOFT
			node.bloom.ImageColor3 = halo
			node.bloom.ImageTransparency = if strong then BLOOM_STRONG else BLOOM_SOFT
		end
		local glyph = if mark and mark.arrow then ARROWS[mark.arrow] else nil
		local arrowColor = if mark and mark.arrowColor then mark.arrowColor else Kit.colors.text
		if glyph == nil and line and line.momentum then
			-- The Polls lens's momentum (D-070); the circles have no room for pips.
			glyph, arrowColor = ARROWS.up, line.momentum
		end
		node.arrow.Visible = glyph ~= nil
		node.arrow.Text = glyph or ""
		node.arrow.TextColor3 = arrowColor
	end

	local map = {} :: any
	map.root = root

	-- Repaint when the map's size changes: a circle may gain or lose room for
	-- its lens value. (The headless test engine has no property signals.)
	pcall(function()
		(root :: any):GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			for _, node in nodes do
				paint(node)
			end
		end)
	end)

	function map.setView(_self: any, view: View.View, colors: { Colors.RGB })
		for i, s in view.states do
			local id = s.id
			local fill: Colors.RGB
			if s.poll then
				fill = Colors.bandFill(s.poll.support, colors)
			elseif s.leanTo then
				-- Before the first poll, show the lean (a lean of L is a margin of L).
				local support = table.create(#colors, 0)
				support[s.leanTo] = s.lean
				fill = Colors.bandFill(support, colors)
			else
				fill = Colors.neutral
			end
			fills[id] = Kit.color(fill)
			local node = nodes[i]
			if node then
				paint(node)
			end
		end
	end

	function map.setMarks(_self: any, newMarks: { [string]: MapInterface.Mark })
		marks = newMarks
		for _, node in nodes do
			paint(node)
		end
	end

	function map.setLens(_self: any, newLens: { [string]: MapInterface.LensLine }, fade: boolean?)
		lens = newLens
		for _, node in nodes do
			paint(node)
			if fade and node.lensRow.Visible then
				-- A lens switch: the pills fade in; the nodes stay where they are.
				for _, part in node.parts do
					if part.Visible then
						part.TextTransparency = 1
						part.BackgroundTransparency = 1
						Motion.tween(
							part,
							{ TextTransparency = 0, BackgroundTransparency = PART_BG },
							LENS_FADE
						)
					end
				end
			end
		end
	end

	function map.setRoute(_self: any, stops: { string }, flights: { boolean })
		for _, child in routeLayer:GetChildren() do
			child:Destroy()
		end
		local previous: any = nil
		for k, id in stops do
			local i = nil
			for j, n in layout do
				if n.id == id then
					i = j
				end
			end
			if i then
				local n = layout[i]
				if previous then
					local line =
						segment(routeLayer, previous.x, previous.y, n.x, n.y, ROUTE_PX, Kit.colors.accent)
					line.BackgroundTransparency = if flights[k] then 0.55 else 0
				end
				previous = n
			end
		end
	end

	function map.select(_self: any, id: string?)
		local old = selected
		selected = id
		if old and byId[old] then
			Motion.cancel(byId[old].ring)
			paint(byId[old])
		end
		if id and byId[id] then
			local node = byId[id]
			paint(node)
			-- The accent glow under the selected state, breathing (decorative).
			local reach = 2 * node.r * CIRCLE_SHARE * SELECT_GLOW
			selectGlow.Position = UDim2.fromScale(node.x, node.y)
			selectGlow.Size = UDim2.fromScale(reach, reach * MapLayout.ASPECT)
			selectGlow.Visible = true
			if id ~= old then
				-- The accent ring draws in (instant under reduced motion).
				node.ring.Thickness = 0
				Motion.tween(node.ring, { Thickness = SELECTED_RING_PX }, RING_DRAW)
				stopBreath()
				selectGlow.ImageTransparency = SELECT_GLOW_FADE
				stopBreath = Motion.breathe(
					selectGlow,
					"ImageTransparency",
					SELECT_GLOW_FADE,
					SELECT_GLOW_DIM,
					SELECT_BREATH
				)
			end
		else
			stopBreath()
			stopBreath = function() end
			selectGlow.Visible = false
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
		Motion.pop(node.circle, PULSE_FROM)
		if color then
			Motion.ring(node.circle, color)
		end
	end

	function map.ring(_self: any, id: string, color: Color3)
		local node = byId[id]
		if node then
			Motion.ring(node.circle, color)
		end
	end

	function map.badge(_self: any, id: string, icon: string?)
		local node = byId[id]
		if node == nil then
			return
		end
		local old = node.hit:FindFirstChild("PlanBadge")
		if old then
			-- Renamed at once, so a new badge never finds the leaving one.
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
			-- Centered near the top-right corner, so it sits on the ring and leaves
			-- the state's letters readable on a phone's small circles (it may
			-- overhang the node, never the screen: Audit's Overhang).
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

	-- A see-through tag at the node's top-right while an action button is held.
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
		-- Above the node's circle, growing inward near a side edge.
		local anchor, place = tagPlace(layout[table.find(nodes, node) or 1])
		ghost.AnchorPoint = anchor
		ghost.Position = place
		ghost.Text = text
		ghost.Visible = true
	end

	function map.wipe(_self: any, id: string, color: Color3)
		local node = byId[id]
		if node == nil then
			return
		end
		fills[id] = color
		Motion.tween(node.circle, { BackgroundColor3 = color }, Motion.t.call, Motion.ease.soft)
		Motion.ring(node.circle, color)
	end

	-- Candidate pins stand on the circle's top edge (D-070).
	local pinLayer = Kit.box({ Name = "Pins", ZIndex = 6, Parent = root })
	function map.setPins(_self: any, pins: { MapInterface.Pin })
		for _, child in pinLayer:GetChildren() do
			child:Destroy()
		end
		local seen: { [string]: number } = {}
		for _, pin in pins do
			local node = byId[pin.state]
			if node then
				local k = (seen[pin.state] or 0) + 1
				seen[pin.state] = k
				local frame = Pins.build(pin, PIN_PX)
				local top = node.y - node.r * CIRCLE_SHARE * MapLayout.ASPECT
				frame.Position = UDim2.new(node.x, (k - 1) * PIN_PX, top, 0)
				frame.ZIndex = if pin.you then 2 else 1
				frame.Parent = pinLayer
			end
		end
	end

	-- The plan preview (D-071): a faint tag under each circle it moves, on top.
	local previewLayer = Kit.box({ Name = "Preview", ZIndex = 7, Parent = root })
	function map.setPreview(_self: any, tags: { [string]: MapInterface.PreviewTag }?)
		for _, child in previewLayer:GetChildren() do
			child:Destroy()
		end
		local list: { [string]: MapInterface.PreviewTag } = tags or {}
		for id, spec in list do
			local node = byId[id]
			if node then
				local color = if spec.negative then Kit.colors.loss else Kit.colors.good
				-- Under the circle; over it near the map's bottom (Alaska, Hawaii).
				local ry = node.r * CIRCLE_SHARE * MapLayout.ASPECT
				local low = node.y + ry > PREVIEW_LOW
				local tag = Kit.text(spec.text, {
					Name = id,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, TAG_H),
					AnchorPoint = Vector2.new(0.5, if low then 1 else 0),
					Position = if low
						then UDim2.new(node.x, 0, node.y - ry, TAG_DIP)
						else UDim2.new(node.x, 0, node.y + ry, -TAG_DIP),
					TextSize = Kit.size.caption,
					Font = Kit.font.display,
					TextColor3 = color,
					BackgroundColor3 = Kit.colors.field,
					BackgroundTransparency = GHOST_BG,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextWrapped = false,
					Parent = previewLayer,
				})
				Kit.dataColor(tag)
				Kit.new("UICorner", { CornerRadius = UDim.new(0, TAG_RADIUS), Parent = tag })
				Kit.new("UIPadding", {
					PaddingLeft = UDim.new(0, TAG_PAD),
					PaddingRight = UDim.new(0, TAG_PAD),
					Parent = tag,
				})
			end
		end
	end

	local legend = Legend.new(root, LEGEND_RECT)
	function map.setLegend(_self: any, items: { MapInterface.LegendItem }?)
		Legend.fill(legend, items)
	end

	function map.destroy(_self: any)
		handlers = {}
		stopBreath()
		root:Destroy()
	end

	return map :: MapInterface.Map
end

return NodeMap
