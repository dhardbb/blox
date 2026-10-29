--!strict
-- The key states line (docs/DESIGN.md D-088): at the top of the Campaign side
-- column while you plan, "Key states" and one chip per key state ("PA 19"),
-- biggest first. The same states glow on the map (Map/MapInterface Mark.key).
-- Tapping a chip selects that state, as tapping it on the map does. On a phone
-- (and a landscape phone, D-089) the line steps aside while a state's card is open, so the card's actions stay
-- in view.
--
-- Reads only the player's own View through Shared/UI/KeyStates (public polls).
--
--   local row = KeyRow.new(parent, model, order)
--   row:render(p, keys) · row.root (Frame "KeyStates", attribute Count)
--   Elements: KeyStatesMark (the map's glowing swatch), KeyStatesLabel,
--   Key_<id> (a chip; selected while its state is).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KeyStates = require(ReplicatedStorage.Shared.UI.KeyStates)
local Words = require(ReplicatedStorage.Shared.UI.Words.Campaign)

local CoachTip = require(script.Parent.Parent.Parent.UI.CoachTip)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Legend = require(script.Parent.Parent.Parent.Map.Legend)
local Model = require(script.Parent.Model)

local KeyRow = {}

local CHIP_PAD = 10 -- px each side of a chip's text
local CHAR_W = 9 -- px, an estimated chip character (body size, medium)

export type KeyRow = {
	root: Frame,
	render: (self: KeyRow, p: Model.Payload, keys: { KeyStates.Key }) -> (),
}

function KeyRow.new(parent: Instance, model: Model.Model, order: number): KeyRow
	local root = Kit.box({
		Name = "KeyStates",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Visible = false,
		Parent = parent,
	})
	local list = Kit.list("Horizontal", Kit.space.xs)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = root

	Legend.keySwatch(root, 1).Name = "KeyStatesMark"

	Kit.text(Words.KEY_STATES, {
		Name = "KeyStatesLabel",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, Kit.MIN_TOUCH),
		TextSize = Kit.size.caption,
		Font = Kit.font.bold,
		TextColor3 = Kit.colors.muted,
		TextWrapped = false,
		Parent = root,
	})

	local chips: { [string]: TextButton } = {}
	local shown = ""

	local self = { root = root } :: any

	function self.render(_: KeyRow, _p: Model.Payload, keys: { KeyStates.Key })
		-- On a phone an open card takes the line's place.
		local visible = #keys > 0
			and not ((model.portrait or model.compact == true) and model.selected ~= nil)
		root.Visible = visible
		root:SetAttribute("Count", #keys)
		local ids: { string } = {}
		for _, key in keys do
			table.insert(ids, key.id)
		end
		local signature = table.concat(ids, " ")
		if signature ~= shown then
			shown = signature
			for _, chip in chips do
				chip:Destroy()
			end
			chips = {}
			for k, key in keys do
				local id = key.id
				local text = Words.keyChip(id, key.ev)
				chips[id] = Kit.chip(text, function()
					CoachTip.markSeen("campaign.keys")
					model.selectState(id)
				end, {
					Name = `Key_{id}`,
					LayoutOrder = 2 + k,
					Size = UDim2.fromOffset(#text * CHAR_W + 2 * CHIP_PAD, Kit.MIN_TOUCH),
					Parent = root,
				})
			end
		end
		for id, chip in chips do
			Kit.setSelected(chip, model.selected == id)
		end
	end

	return self :: KeyRow
end

return KeyRow
