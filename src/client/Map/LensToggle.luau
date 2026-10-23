--!strict
-- The map's lens switch (D-044): four chips side by side, EV / Issues / Polls /
-- $, each a full touch target (Kit.MIN_TOUCH tall), the current lens selected.
-- Picking one remembers it for the session (Map/Lens) and calls `onChange`, which
-- repaints the map.
--
--   LensToggle.new(parent, onChange) -> Toggle   the chips alone (the caller places root)
--   LensToggle.bar(parent, config, onChange) -> Toggle   a full-width row: legend, then chips
--
-- Buttons are named Lens<Id> ("LensEV", "LensIssues", "LensPolls", "LensMoney").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)

local Kit = require(script.Parent.Parent.UI.Kit)
local Lens = require(script.Parent.Lens)

local LensToggle = {}

local BUTTON_W = 54 -- px, one chip ("Issues" fits at body size)
local GAP = Kit.space.xs -- px, between chips
LensToggle.HEIGHT = Kit.MIN_TOUCH
LensToggle.WIDTH = #Lens.ORDER * BUTTON_W + (#Lens.ORDER - 1) * GAP

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
