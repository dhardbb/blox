--!strict
-- The map's small legend row (D-062): a mark and a word or two per item
-- ("▲ momentum", "● ○ ground game"), in a strip of the map box that holds no
-- land. Both maps use it (MapInterface.setLegend).
--
--   Legend.new(root, rect) -> Frame "MapLegend"   hidden until filled
--   Legend.fill(frame, items?)                 nil or {} hides it

local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.MapInterface)

local Legend = {}

local GAP = 8 -- px between items
local CHAR_W = 6.8 -- px, an estimated caption character (to drop optional items on a phone)
local PIP = 8 -- px, a pip mark
local ROW_H = Kit.size.caption + 2 -- px

export type Rect = { x: number, y: number, w: number, h: number }

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
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
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
	-- Drop optional items, last first, until the row fits the strip.
	local list = table.clone(all)
	local function width(): number
		local w = 0
		for k, item in list do
			w += (utf8.len(item.text) or #item.text) * CHAR_W + (if item.mark == "none" then 0 else PIP + 3) + (if k
					> 1
				then GAP
				else 0)
		end
		return w
	end
	local room = frame.AbsoluteSize.X
	if room > 0 then
		for k = #list, 1, -1 do
			if width() <= room then
				break
			end
			if list[k].optional then
				table.remove(list, k)
			end
		end
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
