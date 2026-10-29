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
--   LensToggle.setNarrow(toggle, on)   one row of the rail's narrow cells, each icon
--                                        over its word (LensToggle.NARROW_W wide), where
--                                        the full row does not fit (D-092)
--   LensToggle.fillNarrow(toggle, left)  the narrow cells sharing the row right of
--                                        `left` px equally (a phone's lens row, D-100)
--   LensToggle.row(parent, tabs, close)  the tabs at the parent's right edge and the
--                                        Close races toggle left of them, narrowing the
--                                        tabs while the parent is too narrow for both
--   LensToggle.close(parent, onChange) -> Toggle  the "Close races" filter (D-079):
--                                        on, only the states within Lens.CLOSE
--                                        points keep their fill and value;
--                                        remembered for the session like the lens.
--                                        A toggle with a switch (D-092), so it never
--                                        reads as a fifth tab
--
-- Each tab carries its icon beside its word (D-092; on the 2 x 2 rail, over it).
-- Buttons are named Lens<Id> ("LensEV", "LensIssues", "LensPolls", "LensMoney")
-- and LensClose (its switch: "Switch", with a "Knob").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)

local Kit = require(script.Parent.Parent.UI.Kit)
local Lens = require(script.Parent.Lens)

local LensToggle = {}

local BUTTON_W = 60 -- px, one cell of the landscape phone's 2 x 2 rail (D-089): the icon over the word
-- px, each tab in a row: its icon, then its word at body size (D-092)
local TAB_W: { [string]: number } = { EV = 82, Issues = 90, Polls = 76, Money = 88 }
local GAP = Kit.space.xs -- px, between chips
local ICON = 16 -- px, a tab's icon in a row
local ICON_STACKED = 14 -- px, ... over its word on the rail
local ICON_PAD = 8 -- px, from a tab's left edge to its icon (and from the icon to the word: Kit.space.xs)
local SWITCH_W, SWITCH_H = 26, 14 -- px, the Close races switch's track
local KNOB = 10 -- px, its knob
LensToggle.HEIGHT = Kit.MIN_TOUCH
LensToggle.WIDTH = (function(): number
	local w = (#Lens.ORDER - 1) * GAP
	for _, id in Lens.ORDER do
		w += TAB_W[id]
	end
	return w
end)()
LensToggle.CLOSE_W = 132 -- px, the Close races toggle: its switch, then "Close races"
LensToggle.BUTTON_W = BUTTON_W
local NARROW_CELL = 56 -- px, a tab in the narrow row (setNarrow): its icon over its word at caption size
LensToggle.NARROW_W = #Lens.ORDER * NARROW_CELL + (#Lens.ORDER - 1) * GAP
LensToggle.CLOSE_NARROW_W = 96 -- px, the Close races toggle with its switch over its word

-- Each lens's tab icon (UI/Icons, D-092): Votes the ballot, Issues the scales,
-- Polls the bar chart, Money the coins.
LensToggle.ICONS = table.freeze({ EV = "vote", Issues = "scale", Polls = "chart-column", Money = "coins" })

export type Toggle = {
	root: Frame,
	legend: TextLabel?, -- bar only
	refresh: () -> (), -- shows Lens.current() as selected (and its legend)
}

-- Lays a tab out with its icon beside its word (a row) or over it (`stacked`,
-- the rail's 60 px cells).
local function layoutTab(button: TextButton, stacked: boolean)
	local pad = button:FindFirstChildOfClass("UIPadding")
	local icon = button:FindFirstChild("TabIcon") :: GuiObject?
	if pad then
		pad.PaddingLeft = UDim.new(0, if stacked then 2 else ICON_PAD + ICON + Kit.space.xs)
		pad.PaddingRight = UDim.new(0, if stacked then 2 else ICON_PAD)
		pad.PaddingTop = UDim.new(0, if stacked then ICON_STACKED + 7 else 0)
		pad.PaddingBottom = UDim.new(0, if stacked then 2 else 0)
	end
	button.TextSize = if stacked then Kit.size.caption else Kit.size.body
	button.TextXAlignment = if stacked then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	-- (A UIPadding moves every child too: the icon sits in the padding,
	-- measured back from the padded box's edge.)
	if icon then
		if stacked then
			icon.AnchorPoint = Vector2.new(0.5, 1)
			icon.Position = UDim2.new(0.5, 0, 0, -1)
			icon.Size = UDim2.fromOffset(ICON_STACKED, ICON_STACKED)
		else
			icon.AnchorPoint = Vector2.new(1, 0.5)
			icon.Position = UDim2.new(0, -Kit.space.xs, 0.5, 0)
			icon.Size = UDim2.fromOffset(ICON, ICON)
		end
	end
end

local function chip(id: Lens.Id, order: number, onTap: (Lens.Id) -> ()): TextButton
	local button = Kit.button(Lens.LABEL[id], function()
		onTap(id)
	end, {
		variant = "chip",
		Name = `Lens{id}`,
		LayoutOrder = order,
		Size = UDim2.fromOffset(TAB_W[id], LensToggle.HEIGHT),
	})
	button:SetAttribute("Lens", id)
	local icon = Kit.icon(LensToggle.ICONS[id], ICON, Kit.colors.text)
	icon.Name = "TabIcon"
	icon.Parent = button
	layoutTab(button, false)
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
	local stacked = cols < n
	for _, child in root:GetChildren() do
		if child:IsA("TextButton") then
			layoutTab(child, stacked)
			local id = (child:GetAttribute("Lens") :: string?) or ""
			child.Size =
				UDim2.fromOffset(if stacked then BUTTON_W else TAB_W[id] or BUTTON_W, LensToggle.HEIGHT)
		end
	end
	if cols >= n then
		if grid then
			grid:Destroy()
		end
		if list == nil then
			Kit.list("Horizontal", GAP).Parent = root
		end
		root.Size = UDim2.fromOffset(LensToggle.WIDTH, LensToggle.HEIGHT)
		return
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

-- One row of narrow cells (`on`), each icon over its word, or the full row.
function LensToggle.setNarrow(toggle: Toggle, on: boolean)
	local root = toggle.root
	if root:FindFirstChildOfClass("UIGridLayout") then
		return -- the rail's grid already uses the narrow cells
	end
	for _, child in root:GetChildren() do
		if child:IsA("TextButton") then
			local id = (child:GetAttribute("Lens") :: string?) or ""
			layoutTab(child, on)
			child.Size =
				UDim2.fromOffset(if on then NARROW_CELL else TAB_W[id] or BUTTON_W, LensToggle.HEIGHT)
		end
	end
	root.Size = UDim2.fromOffset(if on then LensToggle.NARROW_W else LensToggle.WIDTH, LensToggle.HEIGHT)
end

-- The narrow cells (setNarrow) sharing the row right of `left` px of the
-- parent equally (D-100: a phone's lens row shares its width with the Map
-- key and Close races, which did not fit beside four 56 px cells). Sized by
-- scale, so the row follows its parent; at a 390 pt phone a cell is about 52.
function LensToggle.fillNarrow(toggle: Toggle, left: number)
	local root = toggle.root
	if root:FindFirstChildOfClass("UIGridLayout") then
		return
	end
	local n = #Lens.ORDER
	for _, child in root:GetChildren() do
		if child:IsA("TextButton") then
			layoutTab(child, true)
			child.Size = UDim2.new(1 / n, -math.ceil((n - 1) * GAP / n), 0, LensToggle.HEIGHT)
		end
	end
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.fromScale(1, 0)
	root.Size = UDim2.new(1, -left, 0, LensToggle.HEIGHT)
end

-- The Close races toggle with its switch over its word (`on`, where a row is
-- short of room: LensToggle.CLOSE_NARROW_W wide), or beside it.
function LensToggle.setCloseNarrow(close: Toggle, on: boolean)
	local button = close.root :: any
	local pad = button:FindFirstChildOfClass("UIPadding")
	local track = button:FindFirstChild("Switch")
	button.Size =
		UDim2.fromOffset(if on then LensToggle.CLOSE_NARROW_W else LensToggle.CLOSE_W, LensToggle.HEIGHT)
	button.TextSize = if on then Kit.size.caption else Kit.size.body
	button.TextXAlignment = if on then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	if pad then
		pad.PaddingLeft = UDim.new(0, if on then 2 else ICON_PAD + SWITCH_W + Kit.space.xs + 2)
		pad.PaddingRight = UDim.new(0, if on then 2 else Kit.space.xs)
		pad.PaddingTop = UDim.new(0, if on then SWITCH_H + 6 else 0)
		pad.PaddingBottom = UDim.new(0, if on then 2 else 0)
	end
	if track then
		track.AnchorPoint = if on then Vector2.new(0.5, 1) else Vector2.new(1, 0.5)
		track.Position = if on then UDim2.new(0.5, 0, 0, -2) else UDim2.new(0, -(Kit.space.xs + 2), 0.5, 0)
	end
end

-- The tabs at `parent`'s right edge and the Close races toggle left of them;
-- while the parent is narrower than both in full, the tabs take the narrow
-- cells (setNarrow). Follows the parent's size.
function LensToggle.row(parent: GuiObject, tabs: Toggle, close: Toggle)
	local function place()
		local w = parent.AbsoluteSize.X
		local full = LensToggle.WIDTH + GAP + LensToggle.CLOSE_W <= w
		LensToggle.setNarrow(tabs, not full)
		LensToggle.setCloseNarrow(close, LensToggle.NARROW_W + GAP + LensToggle.CLOSE_W > w and not full)
		tabs.root.AnchorPoint = Vector2.new(1, 0)
		tabs.root.Position = UDim2.fromScale(1, 0)
		close.root.AnchorPoint = Vector2.new(1, 0)
		close.root.Position = UDim2.new(1, -(tabs.root.Size.X.Offset + GAP), 0, 0)
	end
	place()
	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
end

-- The Close races toggle (D-092; the Close filter, D-079): a switch, then
-- "Close races", on while the filter is on; a tap flips it, remembers it
-- (Lens.setClose) and calls `onChange`.
function LensToggle.close(parent: Instance, onChange: (on: boolean) -> ()): Toggle
	local button: TextButton
	local track: Frame
	local knob: Frame
	local function refresh()
		local on = Lens.close()
		Kit.setSelected(button, on)
		track.BackgroundColor3 = if on then Kit.colors.accent else Kit.colors.field
		knob.Position = if on then UDim2.new(1, -2, 0.5, 0) else UDim2.new(0, 2, 0.5, 0)
		knob.AnchorPoint = if on then Vector2.new(1, 0.5) else Vector2.new(0, 0.5)
		knob.BackgroundColor3 = if on then Kit.colors.onAccent else Kit.colors.muted
	end
	button = Kit.button("Close races", function()
		Lens.setClose(not Lens.close())
		refresh()
		onChange(Lens.close())
	end, {
		variant = "chip",
		Name = "LensClose",
		Size = UDim2.fromOffset(LensToggle.CLOSE_W, LensToggle.HEIGHT),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	})
	button:SetAttribute("Toggle", true)
	local pad = button:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingLeft = UDim.new(0, ICON_PAD + SWITCH_W + Kit.space.xs + 2)
		pad.PaddingRight = UDim.new(0, Kit.space.xs)
	end
	track = Kit.new("Frame", {
		Name = "Switch",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -(Kit.space.xs + 2), 0.5, 0), -- in the padding, left of the word
		Size = UDim2.fromOffset(SWITCH_W, SWITCH_H),
		BorderSizePixel = 0,
		Parent = button,
	}) :: Frame
	track:SetAttribute("Decor", true)
	Kit.round().Parent = track
	local edge = Kit.stroke(Kit.colors.line, 1)
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = track
	knob = Kit.new("Frame", {
		Name = "Knob",
		Size = UDim2.fromOffset(KNOB, KNOB),
		BorderSizePixel = 0,
		Parent = track,
	}) :: Frame
	Kit.round().Parent = knob
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
