--!strict
-- The map's small legend row (D-070): a mark and a word or two per item
-- ("▲ momentum", "● ○ ground game"), in a strip of the map box that holds no
-- land. Both maps use it (MapInterface.setLegend).
--
--   Legend.new(root, rect) -> Frame "MapLegend"   hidden until filled
--   Legend.fill(frame, items?)                 nil or {} hides it

local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.MapInterface)

local Legend = {}

local GAP = 6 -- px between items
local CHAR_W = 8 -- px, an estimated caption character (to drop items on a phone)
local PIP = 8 -- px, a pip mark
local ICON = Kit.MIN_ICON -- px, an issue symbol mark (D-076)
local KEY_W, KEY_H = 16, 10 -- px, a key state's swatch (D-088)
local KEY_LINE = 2 -- px, its gold edge (D-101)
local KEY_INNER_FADE = 0.3 -- the dark keyline inside it (ShapeMap.KEY_LINE_FADE)
local ROW_H = Kit.size.caption + 2 -- px

export type Rect = { x: number, y: number, w: number, h: number }

-- A key state's mark (D-101), as the map draws one: a solid gold edge with
-- the dark keyline inside it, KEY_W x KEY_H. The legend row and the Campaign's
-- key states line both use it.
function Legend.keySwatch(parent: Instance, order: number): Frame
	local swatch = Kit.new("Frame", {
		Name = "Mark",
		LayoutOrder = order,
		Size = UDim2.fromOffset(KEY_W, KEY_H),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = parent,
	}) :: Frame
	local function box(name: string, inset: number, px: number, color: Color3, fade: number)
		local w, h = KEY_W - 2 * inset, KEY_H - 2 * inset
		for k, bar in
			{
				{ 0, 0, w, px },
				{ 0, h - px, w, px },
				{ 0, px, px, h - 2 * px },
				{ w - px, px, px, h - 2 * px },
			}
		do
			Kit.new("Frame", {
				Name = `{name}{k}`,
				Position = UDim2.fromOffset(inset + bar[1], inset + bar[2]),
				Size = UDim2.fromOffset(bar[3], bar[4]),
				BackgroundColor3 = color,
				BackgroundTransparency = fade,
				BorderSizePixel = 0,
				Parent = swatch,
			})
		end
	end
	box("Edge", 0, KEY_LINE, Kit.colors.keyGold, 0)
	box("Line", KEY_LINE, 1, Kit.colors.background, KEY_INNER_FADE)
	return swatch
end

function Legend.new(root: Instance, rect: Rect): Frame
	local frame = Kit.box({
		Name = "MapLegend",
		Position = UDim2.fromScale(rect.x, rect.y),
		Size = UDim2.fromScale(rect.w, rect.h),
		ZIndex = 8,
		Visible = false,
		Parent = root,
	})
	Kit.dataColor(frame)
	local list = Kit.list("Horizontal", GAP)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = frame
	return frame
end

function Legend.fill(frame: Frame, items: { MapInterface.LegendItem }?)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local all: { MapInterface.LegendItem } = items or {}
	-- Too wide for the strip (a phone)? Drop the items with the highest `drop`
	-- first, a whole level at a time, until the row fits.
	local list = table.clone(all)
	local function width(): number
		local w = 0
		for k, item in list do
			local mark = if item.mark == "none"
				then 0
				elseif item.mark == "issue" then ICON + 3
				elseif item.mark == "key" then KEY_W + 3
				else PIP + 3
			w += (utf8.len(item.text) or #item.text) * CHAR_W + mark + (if k > 1 then GAP else 0)
		end
		return w
	end
	local room = frame.AbsoluteSize.X
	while room > 0 and width() > room do
		local level = 0
		for _, item in list do
			level = math.max(level, item.drop or 0)
		end
		if level == 0 then
			break
		end
		for k = #list, 1, -1 do
			if (list[k].drop or 0) == level then
				table.remove(list, k)
			end
		end
	end
	-- Still too wide with only the undroppable items (two of your issues and
	-- the key state on a landscape phone): the last ones go, rather than run
	-- under the small states' chips beside the strip (fix17).
	while room > 0 and #list > 1 and width() > room do
		table.remove(list)
	end
	frame.Visible = #list > 0
	for k, item in list do
		local row = Kit.box({
			Name = `Item{k}`,
			LayoutOrder = k,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, ROW_H),
			Parent = frame,
		})
		local inner = Kit.list("Horizontal", 3)
		inner.VerticalAlignment = Enum.VerticalAlignment.Center
		inner.Parent = row
		local color = item.color or Kit.colors.text
		if item.mark == "up" then
			Kit.text(Kit.glyph.up, {
				Name = "Mark",
				LayoutOrder = 1,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, ROW_H),
				TextSize = Kit.size.caption,
				Font = Kit.font.bold,
				TextColor3 = color,
				TextWrapped = false,
				Parent = row,
			})
		elseif item.mark == "issue" then
			local icon = Kit.issueIcon(item.issue or "", ICON, color)
			icon.Name = "Mark"
			icon.LayoutOrder = 1
			icon.Parent = row
		elseif item.mark == "key" then
			Legend.keySwatch(row, 1)
		elseif item.mark ~= "none" then
			local hollow = item.mark == "hollow"
			local pip = Kit.new("Frame", {
				Name = "Mark",
				LayoutOrder = 1,
				Size = UDim2.fromOffset(PIP, PIP),
				BackgroundColor3 = color,
				BackgroundTransparency = if hollow then 1 else 0,
				BorderSizePixel = 0,
				Parent = row,
			})
			Kit.round().Parent = pip
			local edge = Kit.stroke(if hollow then color else Kit.colors.background, 1.5)
			edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			edge.Parent = pip
		end
		if item.text ~= "" then
			Kit.text(item.text, {
				Name = "Text",
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, ROW_H),
				TextSize = Kit.size.caption,
				TextColor3 = if item.mark == "none" then color else Kit.colors.muted,
				TextWrapped = false,
				Parent = row,
			})
		end
	end
end

return Legend
