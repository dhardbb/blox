--!strict
-- The MVP map: one circle per state from Shared/UI/MapLayout, built from plain
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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local MapInterface = require(script.Parent.MapInterface)
local MapLayout = require(ReplicatedStorage.Shared.UI.MapLayout)
local Kit = require(script.Parent.Parent.UI.Kit)
local Motion = require(script.Parent.Parent.UI.Motion)
local View = require(ReplicatedStorage.Shared.Sim.View)

local NodeMap = {}

local MIN_TAP = Kit.MAP_NODE_MIN -- px, smallest tap target per state
local LINE_PX = 2
local LEADER_PX = 1
local ROUTE_PX = 4
local RING_PX = 2 -- the grey outline
local OWNER_RING_PX = 3 -- a home state's or stronghold's ring
local SELECTED_RING_PX = 3 -- the selected state's accent ring
local CIRCLE_SHARE = 0.88 -- the drawn circle's share of its layout diameter (room for the ring)
local TWO_LINES = 30 -- px, the smallest circle that shows its code and a lens value
local LABEL_H = 0.4 -- label band height, share of the tap target
local BAND_H = 0.3 -- arrow band (bottom), share of the tap target
local TAG_H = Kit.size.caption + 5 -- px, the tag's height
local TAG_PAD = 4 -- px, the tag's side padding
local DIM_FILL = 0.45 -- circle transparency of a dimmed state
local DIM_TEXT = 0.3 -- label transparency of a dimmed state
local ARROWS = { up = "▲", down = "▼" }
local HALO_SCALE = 1.45 -- the glow's diameter, share of the circle's (at most the tap target)
local HALO_SOFT = 0.6 -- glow transparency for a state that moves
local HALO_STRONG = 0.2 -- glow transparency for a state whose poll leader changes
local PART_H = Kit.size.caption + 5 -- px, a lens pill's height
local PART_PAD = 3 -- px, a lens pill's side padding
local PART_GAP = 2 -- px, between two lens pills
local LABEL_Y = 0.5 -- the label's center, share of the tap target
local LABEL_UP = 0.2 -- with a lens value: the label's center above the middle, share of the circle
local VALUE_DOWN = 0.2 -- ... the value's center below the middle, share of the circle
local LABEL_H_LENS = 0.36 -- ... the label's height, share of the circle
local PULSE_FROM = 1.15 -- a pulse's starting scale (it settles to 1)
local PLAN_BADGE_PX = 16 -- px, the planned-action badge
local BORDER_FADE = 0.4 -- land borders' transparency, so the nodes stand out
local TOP_SHADE = 0.08 -- the circle's transparency at its bottom (a top light of about 8 %)
local RING_DRAW = 0.1 -- s, the selected ring drawing in
local LENS_FADE = 0.15 -- s, the lens pills fading in on a lens switch
local PART_BG = 0.15 -- a lens pill's backing transparency at rest
local GHOST_STROKE = 0.5 -- the ghost tag's outline transparency

type Node = {
	id: string,
	r: number, -- layout radius, box widths
	k: number, -- the drawn circle's share of the tap target
	hit: TextButton,
	circle: Frame,
	halo: Frame,
	ring: UIStroke,
	label: TextLabel,
	badge: TextLabel,
	badgeStroke: UIStroke,
	arrow: TextLabel,
	lensRow: Frame,
	parts: { TextLabel },
}

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
local function newPart(row: Frame, k: number): TextLabel
	local part = Kit.text("", {
		Name = `Part{k}`,
		LayoutOrder = k,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, PART_H),
		TextSize = Kit.size.caption,
		Font = Kit.font.bold,
		BackgroundColor3 = Kit.colors.background,
		BackgroundTransparency = PART_BG,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		ZIndex = 6,
		Parent = row,
	})
	Kit.new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = part })
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, PART_PAD),
		PaddingRight = UDim.new(0, PART_PAD),
		Parent = part,
	})
	return part
end

-- Fills a node's lens row from `line` (nil or no parts, or a circle too small
-- for two lines: hidden).
local function paintLens(node: Node, line: MapInterface.LensLine?, roomy: boolean)
	local parts: { MapInterface.LensPart } = if line and roomy then line.parts else {}
	for k, spec in parts do
		if k > #node.parts then
			table.insert(node.parts, newPart(node.lensRow, k))
		end
		local part = node.parts[k]
		local color = spec.color or Kit.colors.text
		part.Visible = true
		part.Text = spec.text
		part.TextColor3 = if spec.filled then Kit.colors.background else color
		part.BackgroundColor3 = if spec.filled
			then color
			elseif spec.outlined then Kit.colors.field
			else Kit.colors.background
		-- The battleground mark's outline (D-058), made on first use.
		local outline = part:FindFirstChild("Outline") :: UIStroke?
		if spec.outlined and outline == nil then
			outline = Kit.new("UIStroke", {
				Name = "Outline",
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Kit.colors.text,
				Thickness = Kit.MARK_STROKE,
				Parent = part,
			})
		end
		if outline then
			outline.Enabled = spec.outlined == true
		end
	end
	for k = #parts + 1, #node.parts do
		node.parts[k].Visible = false
	end
	local shown = #parts > 0
	node.lensRow.Visible = shown
	local k = node.k
	node.label.Position = UDim2.fromScale(0.5, if shown then 0.5 - LABEL_UP * k else LABEL_Y)
	node.label.Size = UDim2.fromScale(MapLayout.LABEL_SCALE * k, if shown then LABEL_H_LENS * k else LABEL_H)
end

function NodeMap.new(): MapInterface.Map
	local root = Kit.new("Frame", {
		Name = "NodeMap",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = false,
	})
	Kit.new("UIAspectRatioConstraint", { AspectRatio = MapLayout.ASPECT, Parent = root })

	local lines = Kit.box({ Name = "Lines", ZIndex = 1, Parent = root })
	local leaders = Kit.box({ Name = "Leaders", ZIndex = 1, Parent = root })
	local routeLayer = Kit.box({ Name = "Route", ZIndex = 2, Parent = root })
	local nodeLayer = Kit.box({ Name = "Nodes", ZIndex = 3, Parent = root })
	local tagLayer = Kit.box({ Name = "Tags", ZIndex = 4, Parent = root })

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
		-- The glow sits behind the circle (lower ZIndex among the node's children).
		local halo = Kit.new("Frame", {
			Name = "Halo",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			-- Never wider than the tap target, so it stays inside the map.
			Size = UDim2.fromScale(math.min(1, k * HALO_SCALE), math.min(1, k * HALO_SCALE)),
			BackgroundColor3 = Kit.colors.accent,
			BackgroundTransparency = HALO_SOFT,
			BorderSizePixel = 0,
			ZIndex = 2,
			Visible = false,
			Parent = hit,
		})
		Kit.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = halo })
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
		-- Lit from the top: the fill (data) at the top; toward the bottom the dark
		-- board shows through a little, a shade darker. (Transparency, not Color, so
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
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			ZIndex = 4,
			Parent = hit,
		})
		-- The tag straddles the circle's top edge (or hangs inside it at the top
		-- of the map); its anchor follows the node across the map, so a wide tag
		-- near a side edge grows inward and stays inside the map.
		local rimY = n.y - n.r * MapLayout.ASPECT
		local badge = Kit.text("", {
			Name = n.id,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, TAG_H),
			AnchorPoint = Vector2.new(math.clamp(n.x, 0, 1), if rimY < 0.06 then 0 else 0.5),
			Position = UDim2.fromScale(n.x, math.max(rimY, 0)),
			TextSize = Kit.size.caption,
			Font = Kit.font.bold,
			TextColor3 = Kit.colors.accent,
			BackgroundColor3 = Kit.colors.background,
			BackgroundTransparency = 0.1,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			Visible = false,
			Parent = tagLayer,
		})
		Kit.new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = badge })
		Kit.new("UIPadding", {
			PaddingLeft = UDim.new(0, TAG_PAD),
			PaddingRight = UDim.new(0, TAG_PAD),
			Parent = badge,
		})
		local badgeStroke = Kit.stroke(Kit.colors.accent, 1)
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
			r = n.r,
			k = k,
			hit = hit,
			circle = circle,
			halo = halo,
			ring = ring,
			label = label,
			badge = badge,
			badgeStroke = badgeStroke,
			arrow = arrow,
			lensRow = newLensRow(hit, k),
			parts = {},
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

	local function paint(node: Node)
		local mark = marks[node.id]
		local line = lens[node.id]
		local isSelected = selected == node.id
		local dim = (mark ~= nil and mark.dim == true) or (line ~= nil and line.dim == true)
		node.circle.BackgroundColor3 = fills[node.id] or Kit.color(Colors.neutral)
		node.circle.BackgroundTransparency = if dim then DIM_FILL else 0
		node.label.TextTransparency = if dim then DIM_TEXT else 0
		paintLens(node, line, roomy(node))
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
		-- One tag holds the badge and the word: "+1.5", "FLIP" or "+1.5 FLIP".
		-- A word fills the tag in its color, so a flip reads at a glance.
		local badge = if mark then mark.badge else nil
		local word = if mark then mark.note else nil
		local tag = if badge and word then `{badge} {word}` else badge or word
		node.badge.Visible = tag ~= nil
		node.badge.Text = tag or ""
		local color = if mark and mark.badgeColor then mark.badgeColor else Kit.colors.accent
		if word then
			local fill = if mark and mark.noteColor then mark.noteColor else Kit.colors.text
			node.badge.BackgroundColor3 = fill
			node.badge.TextColor3 = Kit.colors.background
			node.badgeStroke.Color = fill
		else
			node.badge.BackgroundColor3 = Kit.colors.background
			node.badge.TextColor3 = color
			node.badgeStroke.Color = color
		end
		local halo = if mark then mark.halo else nil
		node.halo.Visible = halo ~= nil
		if halo then
			node.halo.BackgroundColor3 = halo
			node.halo.BackgroundTransparency = if mark and mark.haloStrong then HALO_STRONG else HALO_SOFT
		end
		local glyph = if mark and mark.arrow then ARROWS[mark.arrow] else nil
		node.arrow.Visible = glyph ~= nil
		node.arrow.Text = glyph or ""
		node.arrow.TextColor3 = if mark and mark.arrowColor then mark.arrowColor else Kit.colors.text
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
			if id ~= old then
				-- The accent ring draws in (instant under reduced motion).
				node.ring.Thickness = 0
				Motion.tween(node.ring, { Thickness = SELECTED_RING_PX }, RING_DRAW)
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
			BackgroundColor3 = Kit.colors.background,
			BorderSizePixel = 0,
			ZIndex = 7,
			Parent = node.hit,
		})
		badge:SetAttribute("Overhang", true)
		Kit.round().Parent = badge
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
				Font = Kit.font.bold,
				TextColor3 = Kit.colors.text,
				BackgroundColor3 = Kit.colors.background,
				BackgroundTransparency = 0.3,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextWrapped = false,
				ZIndex = 9,
				Parent = tagLayer,
			})
			Kit.new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = made })
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
		local n = layout[table.find(nodes, node) or 1]
		local rimY = n.y - n.r * MapLayout.ASPECT
		ghost.AnchorPoint = Vector2.new(math.clamp(n.x, 0, 1), if rimY < 0.06 then 0 else 0.5)
		ghost.Position = UDim2.fromScale(n.x, math.max(rimY, 0))
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

	function map.destroy(_self: any)
		handlers = {}
		root:Destroy()
	end

	return map :: MapInterface.Map
end

return NodeMap
