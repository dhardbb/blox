--!strict
-- The map's lens switch (D-046): four chips side by side, Votes / Issues /
-- Polls / Money, each a full touch target (Kit.MIN_TOUCH tall), the current lens selected.
-- Picking one remembers it for the session (Map/Lens) and calls `onChange`, which
-- repaints the map.
--
--   LensToggle.new(parent, onChange) -> Toggle   the chips alone (the caller places root)
--   LensToggle.bar(parent, config, onChange) -> Toggle   a full-width row: legend, then chips
--   LensToggle.setColumns(toggle, n)   lay a toggle's chips out n to a row (a
--                                        landscape phone's 2 x 2 rail, D-089); n nil
--                                        or ≥ 4: the one row again
--   LensToggle.close(parent, onChange) -> Toggle  the "Close" filter chip (D-079):
--                                        on, only the states within Lens.CLOSE
--                                        points keep their fill and value;
--                                        remembered for the session like the lens
--
-- Buttons are named Lens<Id> ("LensEV", "LensIssues", "LensPolls", "LensMoney")
-- and LensClose.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)

local Kit = require(script.Parent.Parent.UI.Kit)
local Lens = require(script.Parent.Lens)

local LensToggle = {}

local BUTTON_W = 60 -- px, one chip ("Issues", "Money" fit at body size; 60 leaves a phone room for Close)
local GAP = Kit.space.xs -- px, between chips
LensToggle.HEIGHT = Kit.MIN_TOUCH
LensToggle.WIDTH = #Lens.ORDER * BUTTON_W + (#Lens.ORDER - 1) * GAP
LensToggle.CLOSE_W = 60 -- px, the Close chip
LensToggle.BUTTON_W = BUTTON_W

export type Toggle = {
	root: Frame,
	legend: TextLabel?, -- bar only
	refresh: () -> (), -- shows Lens.current() as selected (and its legend)
}

local function chip(id: Lens.Id, order: number, onTap: (Lens.Id) -> ()): TextButton
	local button = Kit.button(Lens.LABEL[id], function()
		onTap(id)
	end, {
		variant = "chip",
		Name = `Lens{id}`,
		LayoutOrder = order,
		Size = UDim2.fromOffset(BUTTON_W, LensToggle.HEIGHT),
	})
	local pad = button:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingLeft = UDim.new(0, Kit.space.xs)
		pad.PaddingRight = UDim.new(0, Kit.space.xs)
	end
	return button
end

function LensToggle.new(parent: Instance, onChange: (Lens.Id) -> ()): Toggle
	local root = Kit.box({
		Name = "LensToggle",
		Size = UDim2.fromOffset(LensToggle.WIDTH, LensToggle.HEIGHT),
		Parent = parent,
	})
	Kit.list("Horizontal", GAP).Parent = root
	local buttons: { [string]: TextButton } = {}
	local toggle: Toggle

	local function refresh()
		for id, button in buttons do
			Kit.setSelected(button, id == Lens.current())
		end
	end

	local function pick(id: Lens.Id)
		if id == Lens.current() then
			return
		end
		Lens.set(id)
		toggle.refresh()
		onChange(id)
	end

	for order, id in Lens.ORDER do
		local button = chip(id :: Lens.Id, order, pick)
		button.Parent = root
		buttons[id] = button
	end
	toggle = { root = root, refresh = refresh }
	refresh()
	return toggle
end

-- Lays `toggle`'s chips out `columns` to a row (D-089: two on a landscape
-- phone's rail beside the map), or in one row when `columns` is nil or covers
-- them all. The root takes the grid's size.
function LensToggle.setColumns(toggle: Toggle, columns: number?)
	local root = toggle.root
	local n = #Lens.ORDER
	local cols = math.clamp(columns or n, 1, n)
	local rows = math.ceil(n / cols)
	local list = root:FindFirstChildOfClass("UIListLayout")
	local grid = root:FindFirstChildOfClass("UIGridLayout")
	if cols >= n then
		if grid then
			grid:Destroy()
		end
		if list == nil then
			Kit.list("Horizontal", GAP).Parent = root
		end
	else
		if list then
			list:Destroy()
		end
		local g = grid
			or Kit.new("UIGridLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = root,
			}) :: UIGridLayout
		g.CellSize = UDim2.fromOffset(BUTTON_W, LensToggle.HEIGHT)
		g.CellPadding = UDim2.fromOffset(GAP, GAP)
	end
	root.Size =
		UDim2.fromOffset(cols * BUTTON_W + (cols - 1) * GAP, rows * LensToggle.HEIGHT + (rows - 1) * GAP)
end

-- The Close filter chip: selected while the filter is on; a tap flips it,
-- remembers it (Lens.setClose) and calls `onChange`.
function LensToggle.close(parent: Instance, onChange: (on: boolean) -> ()): Toggle
	local button: TextButton
	local function refresh()
		Kit.setSelected(button, Lens.close())
	end
	button = Kit.button("Close", function()
		Lens.setClose(not Lens.close())
		refresh()
		onChange(Lens.close())
	end, {
		variant = "chip",
		Name = "LensClose",
		Size = UDim2.fromOffset(LensToggle.CLOSE_W, LensToggle.HEIGHT),
		Parent = parent,
	})
	local pad = button:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingLeft = UDim.new(0, Kit.space.xs)
		pad.PaddingRight = UDim.new(0, Kit.space.xs)
	end
	refresh()
	return { root = button :: any, refresh = refresh }
end

function LensToggle.bar(parent: Instance, config: ConfigModule.Config, onChange: (Lens.Id) -> ()): Toggle
	local root = Kit.box({
		Name = "LensBar",
		Size = UDim2.new(1, 0, 0, LensToggle.HEIGHT),
		Parent = parent,
	})
	local legend = Kit.text("", {
		Name = "LensLegend",
		Size = UDim2.new(1, -(LensToggle.WIDTH + Kit.space.sm), 1, 0),
		TextSize = Kit.size.caption,
		TextScaled = true,
		TextColor3 = Kit.colors.muted,
		Parent = root,
	})
	local chips = LensToggle.new(root, function(id: Lens.Id)
		legend.Text = Lens.legend(config, id)
		onChange(id)
	end)
	chips.root.AnchorPoint = Vector2.new(1, 0)
	chips.root.Position = UDim2.fromScale(1, 0)
	local function refresh()
		chips.refresh()
		legend.Text = Lens.legend(config, Lens.current())
	end
	local toggle: Toggle = { root = root, legend = legend, refresh = refresh }
	refresh()
	return toggle
end

return LensToggle
