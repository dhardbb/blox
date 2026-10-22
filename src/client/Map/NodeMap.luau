--!strict
-- The MVP map: one circle per state from Shared/UI/MapLayout, built from plain
-- frames (no art assets). Fill blends toward the public-poll leader's color; the
-- grey ring's thickness shows the undecided share; thin lines are land borders.
-- The nine small Northeast states stand in a ladder at the right edge
-- (MapLayout.LADDER), each with a thin leader line to where it really is.
--
-- A screen's marks can add a badge in any color ("+1.5" in a player's color),
-- a word ("FLIP") and a glow behind the circle: the Choice preview and the
-- reveals use them to show which states moved (D-042). Badge and word share one
-- solid tag on the circle's top edge, drawn in the Tags layer above every node,
-- so no neighbor's circle hides it and it never sits on another state's label.
--
-- Each state is one invisible tap target (a TextButton named by the state id)
-- at least Kit.MAP_NODE_MIN px in both directions. Everything drawn for the
-- state lives inside it except its tag: the circle with its label, then the
-- momentum arrow band at the bottom. Smaller states are created last, so where two
-- tap targets overlap the smaller state gets the tap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local MapInterface = require(script.Parent.MapInterface)
local MapLayout = require(ReplicatedStorage.Shared.UI.MapLayout)
local Kit = require(script.Parent.Parent.UI.Kit)
local View = require(ReplicatedStorage.Shared.Sim.View)

local NodeMap = {}

local MIN_TAP = Kit.MAP_NODE_MIN -- px, smallest tap target per state
local LINE_PX = 2
local LEADER_PX = 1
local ROUTE_PX = 4
local MAX_RING_PX = 5 -- ring width at 30+ undecided
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

type Node = {
	id: string,
	hit: TextButton,
	circle: Frame,
	halo: Frame,
	ring: UIStroke,
	label: TextLabel,
	badge: TextLabel,
	badgeStroke: UIStroke,
	arrow: TextLabel,
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
			segment(lines, a.x, a.y, b.x, b.y, LINE_PX, Kit.colors.line)
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
		local k = n.r / h -- the circle's share of the tap target
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
		local ring = Kit.stroke(Kit.color(Colors.undecided), 2)
		ring.Parent = circle
		local label = Kit.text(n.id, {
			Name = "Label",
			Size = UDim2.fromScale(MapLayout.LABEL_SCALE * k, LABEL_H),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
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
			hit = hit,
			circle = circle,
			halo = halo,
			ring = ring,
			label = label,
			badge = badge,
			badgeStroke = badgeStroke,
			arrow = arrow,
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
	local fills: { [string]: Color3 } = {}
	local rings: { [string]: number } = {}

	local function paint(node: Node)
		local mark = marks[node.id]
		local isSelected = selected == node.id
		node.circle.BackgroundColor3 = fills[node.id] or Kit.color(Colors.neutral)
		node.circle.BackgroundTransparency = if mark and mark.dim then DIM_FILL else 0
		node.label.TextTransparency = if mark and mark.dim then DIM_TEXT else 0
		if isSelected then
			node.ring.Color = Kit.colors.accent
			node.ring.Thickness = 4
		elseif mark and mark.ring then
			node.ring.Color = mark.ring
			node.ring.Thickness = 3
		else
			node.ring.Color = Kit.color(Colors.undecided)
			node.ring.Thickness = rings[node.id] or 1
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

	function map.setView(_self: any, view: View.View, colors: { Colors.RGB })
		for i, s in view.states do
			local id = s.id
			local fill: Colors.RGB
			if s.poll then
				fill = Colors.stateFill(s.poll.support, colors)
				rings[id] = math.clamp(s.poll.undecided / 30 * MAX_RING_PX, 1, MAX_RING_PX)
			elseif s.leanTo then
				-- Before the first poll, show the lean (a lean of L is a margin of L).
				local support = table.create(#colors, 0)
				support[s.leanTo] = s.lean
				fill = Colors.stateFill(support, colors)
				rings[id] = MAX_RING_PX
			else
				fill = Colors.neutral
				rings[id] = MAX_RING_PX
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
			paint(byId[old])
		end
		if id and byId[id] then
			paint(byId[id])
		end
	end

	function map.onSelect(_self: any, handler: (string) -> ())
		table.insert(handlers, handler)
	end

	function map.destroy(_self: any)
		handlers = {}
		root:Destroy()
	end

	return map :: MapInterface.Map
end

return NodeMap
