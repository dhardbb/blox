--!strict
-- The MVP map: one circle per state from Shared/UI/MapLayout, built from plain
-- frames (no art assets). Fill blends toward the public-poll leader's color; the
-- grey ring's thickness shows the undecided share; thin lines are land borders.
-- Each node sits on an invisible tap target at least MIN_TAP px wide so small
-- states stay tappable on phones.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local MapInterface = require(script.Parent.MapInterface)
local MapLayout = require(ReplicatedStorage.Shared.UI.MapLayout)
local Kit = require(script.Parent.Parent.UI.Kit)
local View = require(ReplicatedStorage.Shared.Sim.View)

local NodeMap = {}

local MIN_TAP = 30 -- px, smallest tap target per state (circles overlap beyond this)
local LINE_PX = 2
local ROUTE_PX = 4
local MAX_RING_PX = 5 -- ring width at 30+ undecided

type Node = {
	id: string,
	hit: TextButton,
	circle: Frame,
	ring: UIStroke,
	label: TextLabel,
	badge: TextLabel,
}

-- A thin rotated frame from (x1, y1) to (x2, y2) in box fractions.
local function segment(
	parent: Instance,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	px: number,
	color: Color3
): Frame
	local dx = x2 - x1
	local dy = (y2 - y1) / MapLayout.ASPECT -- in box-width units
	local length = math.sqrt(dx * dx + dy * dy)
	return Kit.new("Frame", {
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
	local routeLayer = Kit.box({ Name = "Route", ZIndex = 2, Parent = root })
	local nodeLayer = Kit.box({ Name = "Nodes", ZIndex = 3, Parent = root })

	local layout = MapLayout.nodes()
	for _, edge in MapLayout.edges() do
		local a, b = layout[edge[1]], layout[edge[2]]
		segment(lines, a.x, a.y, b.x, b.y, LINE_PX, Kit.colors.line)
	end

	local nodes: { Node } = {}
	local byId: { [string]: Node } = {}
	local handlers: { (string) -> () } = {}
	local selected: string? = nil

	for i, n in layout do
		local hit = Kit.new("TextButton", {
			Name = n.id,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(n.x, n.y),
			Size = UDim2.fromScale(2 * n.r, 2 * n.r * MapLayout.ASPECT),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 3,
			Parent = nodeLayer,
		})
		Kit.new("UISizeConstraint", { MinSize = Vector2.new(MIN_TAP, MIN_TAP), Parent = hit })
		local circle = Kit.new("Frame", {
			Name = "Circle",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
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
			Size = UDim2.fromScale(0.8, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			TextScaled = true,
			TextSize = 18,
			Font = Kit.font.bold,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			ZIndex = 4,
			Parent = circle,
		})
		local badge = Kit.text("", {
			Name = "Badge",
			Size = UDim2.fromScale(0.6, 0.45),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.05),
			TextScaled = true,
			TextSize = 16,
			Font = Kit.font.bold,
			TextColor3 = Kit.colors.accent,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			ZIndex = 5,
			Visible = false,
			Parent = circle,
		})
		local node: Node =
			{ id = n.id, hit = hit, circle = circle, ring = ring, label = label, badge = badge }
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
		node.circle.BackgroundTransparency = if mark and mark.dim then 0.65 else 0
		node.label.TextTransparency = if mark and mark.dim then 0.5 else 0
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
		node.badge.Visible = mark ~= nil and mark.badge ~= nil
		node.badge.Text = if mark and mark.badge then mark.badge else ""
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
