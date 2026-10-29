--!strict
-- The week's plan as slots (D-093, Words.planSlots): one tile per action, the
-- action's icon and its state ("OH"), repeats merged ("OH ×2"), and an outlined
-- empty tile for each action slot still free; money-only actions (ads, polls,
-- ground game) follow as tiles of their own.
--
--   local slots = PlanSlots.new(parent, { mini = true?, name = "...", order = n?, onTap = fn? })
--   slots:render(list, view, enabled)   -- list: { Words.Slot }
--   slots.root   Frame
--
-- `mini` is the action bar's status row (20 px, read only, in place of the
-- old "Plan: Rally OH · Ad PA" line); the full size is the plan card's row of
-- 44 px tiles, three a row; tapping a filled one calls onTap(slot) (it removes
-- that action). Element names: Slot<k> (filled), SlotEmpty<k>, SlotLabel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Words = require(ReplicatedStorage.Shared.UI.Words.Campaign)

local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Parent.Common.Layout)

local PlanSlots = {}

local MINI_H = 20 -- px, a tile in the action bar's status row
local MINI_ICON = 14 -- px, its icon
local MINI_EMPTY_W = 34 -- px, an empty tile there
local TILE_ICON = 20 -- px, a full tile's icon
local COLUMNS = 3 -- full tiles a row

export type Options = {
	mini: boolean?,
	name: string,
	order: number?,
	onTap: ((slot: Words.Slot) -> ())?,
}

export type PlanSlots = {
	root: Frame,
	render: (self: PlanSlots, list: { Words.Slot }, enabled: boolean) -> (),
}

-- An outlined, unfilled tile: the "dashed" empty slot (a light outline).
local function hollow(frame: GuiObject)
	frame.BackgroundTransparency = 1
	local stroke = Kit.stroke(Kit.colors.muted, 1)
	stroke.Transparency = 0.35
	stroke.Parent = frame
	Kit.corner(Kit.radius.control).Parent = frame
end

function PlanSlots.new(parent: Instance, options: Options): PlanSlots
	local mini = options.mini == true
	local root: Frame
	if mini then
		root = Kit.box({
			Name = options.name,
			Size = UDim2.new(1, 0, 0, MINI_H),
			Parent = parent,
		})
		local list = Kit.list("Horizontal", Kit.space.xs)
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Parent = root
	else
		local frame, layout = Layout.grid(parent, options.name, options.order or 0)
		Layout.setGrid(layout, COLUMNS, Kit.MIN_TOUCH, Kit.space.xs)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		root = frame
	end
	root:SetAttribute("Slots", true)

	local function clear()
		for _, child in root:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	-- The icon and the label, side by side, in `holder`.
	local function content(holder: GuiObject, slot: Words.Slot, px: number, textSize: number, color: Color3)
		local row = Kit.box({ Name = "SlotContent", Size = UDim2.fromScale(1, 1), Parent = holder })
		local list = Kit.list("Horizontal", Kit.space.xs)
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.HorizontalAlignment = if mini
			then Enum.HorizontalAlignment.Left
			else Enum.HorizontalAlignment.Center
		list.Parent = row
		local iconName = if slot.kind then Kit.actionIcon(slot.kind) else nil
		if iconName then
			local icon = Kit.icon(iconName, px, color)
			icon.LayoutOrder = 1
			icon.Parent = row
		end
		Kit.text(slot.label, {
			Name = "SlotLabel",
			LayoutOrder = 2,
			Size = UDim2.fromOffset(0, px + 4),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = textSize,
			Font = Kit.font.bold,
			TextColor3 = color,
			TextWrapped = false,
			Parent = row,
		})
	end

	local slots: PlanSlots = {
		root = root,
		render = function(_self: PlanSlots, list: { Words.Slot }, enabled: boolean)
			clear()
			for k, slot in list do
				if mini then
					local tile = Kit.box({
						Name = if slot.kind then `Slot{k}` else `SlotEmpty{k}`,
						LayoutOrder = k,
						Size = UDim2.fromOffset(if slot.kind then 0 else MINI_EMPTY_W, MINI_H),
						AutomaticSize = if slot.kind then Enum.AutomaticSize.X else Enum.AutomaticSize.None,
						Parent = root,
					})
					if slot.kind then
						tile.BackgroundTransparency = 0
						tile.BackgroundColor3 = Kit.colors.raised
						Kit.corner(Kit.radius.control).Parent = tile
						Kit.new("UIPadding", {
							PaddingLeft = UDim.new(0, Kit.space.xs),
							PaddingRight = UDim.new(0, Kit.space.xs),
							Parent = tile,
						})
						local row = Kit.list("Horizontal", Kit.space.xs)
						row.VerticalAlignment = Enum.VerticalAlignment.Center
						row.Parent = tile
						local iconName = Kit.actionIcon(slot.kind)
						if iconName then
							local icon = Kit.icon(iconName, MINI_ICON, Kit.colors.text)
							icon.LayoutOrder = 1
							icon.Parent = tile
						end
						Kit.text(slot.label, {
							Name = "SlotLabel",
							LayoutOrder = 2,
							Size = UDim2.fromOffset(0, MINI_H),
							AutomaticSize = Enum.AutomaticSize.X,
							TextSize = Kit.size.caption,
							Font = Kit.font.bold,
							TextWrapped = false,
							Parent = tile,
						})
					else
						hollow(tile)
					end
				elseif slot.kind then
					local button: TextButton
					button = Kit.button("", function()
						local onTap = options.onTap
						if onTap and button.Active ~= false then
							onTap(slot)
						end
					end, {
						variant = "secondary",
						Name = `Slot{k}`,
						LayoutOrder = k,
						TextScaled = false,
						Parent = root,
					})
					content(
						button,
						slot,
						TILE_ICON,
						Kit.size.body,
						if enabled then Kit.colors.text else Kit.colors.disabledText
					)
					Kit.setEnabled(button, enabled)
				else
					local tile = Kit.box({ Name = `SlotEmpty{k}`, LayoutOrder = k, Parent = root })
					hollow(tile)
					Kit.text("Action", {
						Name = "SlotLabel",
						Size = UDim2.fromScale(1, 1),
						TextSize = Kit.size.caption,
						TextColor3 = Kit.colors.muted,
						TextXAlignment = Enum.TextXAlignment.Center,
						Parent = tile,
					})
				end
			end
		end,
	}
	return slots
end

return PlanSlots
