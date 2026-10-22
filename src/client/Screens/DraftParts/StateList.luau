--!strict
-- The Draft screen's list picker: every state, biggest first, one tappable row
-- each ("Row_OH") with its lean and who drafted it. It is the phone-friendly twin
-- of tapping the map, and shares its choice slots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Draft = require(ReplicatedStorage.Shared.Sim.Draft)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local View = require(ReplicatedStorage.Shared.Sim.View)

local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Logic = require(script.Parent.Logic)

export type Info = {
	view: View.View,
	kind: Draft.Kind?, -- the round's kind while picking; nil when nothing is pickable
	colors: { Color3 }, -- by player index
	choices: Logic.Choices,
	interactive: boolean, -- rows respond to taps
}

export type List = {
	root: Frame,
	update: (self: List, info: Info) -> (),
}

type Row = {
	id: string,
	button: TextButton,
	stroke: UIStroke,
	rank: TextLabel,
	code: TextLabel,
	name: TextLabel,
	tag: TextLabel,
	ev: TextLabel,
	lean: TextLabel,
	index: number, -- position in view.states
}

local StateList = {}

local ROW_HEIGHT = 48

-- Columns as fractions of the row width: rank, code, name, EV, lean.
local X_RANK, W_RANK = 0, 0.08
local X_CODE, W_CODE = 0.08, 0.13
local X_NAME, W_NAME = 0.21, 0.37
local X_EV, W_EV = 0.58, 0.14
local X_LEAN, W_LEAN = 0.72, 0.28

local function cell(
	parent: Instance,
	name: string,
	x: number,
	w: number,
	y: number,
	h: number,
	props: { [string]: any }
): TextLabel
	local base: { [string]: any } = {
		Name = name,
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromScale(w, h),
		TextScaled = true,
		Parent = parent,
	}
	for key, value in props do
		base[key] = value
	end
	return Kit.text("", base)
end

function StateList.new(onTap: (id: string) -> ()): List
	local root = Kit.box({
		Name = "StateList",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	Kit.list("Vertical", 4).Parent = root
	Kit.text("All states, biggest first. Tap one to pick it.", {
		Name = "ListTitle",
		Font = Kit.font.bold,
		LayoutOrder = 0,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		Parent = root,
	})

	local records = table.clone(StateData.list)
	table.sort(records, function(a, b)
		if a.ev ~= b.ev then
			return a.ev > b.ev
		end
		return a.id < b.id
	end)
	local indexOf: { [string]: number } = {}
	for i, record in StateData.list do
		indexOf[record.id] = i
	end

	local rows: { Row } = {}
	for order, record in records do
		local id = record.id
		local button = Kit.new("TextButton", {
			Name = `Row_{id}`,
			Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
			BackgroundColor3 = Kit.colors.raised,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Text = "",
			LayoutOrder = order,
			Parent = root,
		})
		Kit.corner(8).Parent = button
		local stroke = Kit.stroke(Kit.colors.accent, 2)
		stroke.Thickness = 0
		stroke.Parent = button
		Kit.new("UIPadding", {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			PaddingTop = UDim.new(0, 3),
			PaddingBottom = UDim.new(0, 3),
			Parent = button,
		})
		local row: Row = {
			id = id,
			button = button,
			stroke = stroke,
			rank = cell(button, "Rank", X_RANK, W_RANK, 0, 1, {
				Font = Kit.font.bold,
				TextSize = 20,
				TextColor3 = Kit.colors.accent,
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
			code = cell(button, "Code", X_CODE, W_CODE, 0, 1, { Font = Kit.font.bold, TextSize = 20 }),
			name = cell(button, "Name", X_NAME, W_NAME, 0, 1, { TextSize = 16 }),
			tag = cell(button, "Tag", X_NAME, W_NAME, 0.62, 0.38, {
				TextSize = 11,
				TextColor3 = Kit.colors.muted,
				Visible = false,
			}),
			ev = cell(
				button,
				"EV",
				X_EV,
				W_EV,
				0,
				1,
				{ TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center }
			),
			lean = cell(button, "Lean", X_LEAN, W_LEAN, 0, 1, {
				TextSize = 15,
				Font = Kit.font.medium,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
			index = indexOf[id],
		}
		row.code.Text = id
		row.name.Text = record.name
		row.ev.Text = `{record.ev} EV`
		button.Activated:Connect(function()
			onTap(id)
		end)
		table.insert(rows, row)
	end

	local list = {} :: any
	list.root = root

	function list.update(_self: List, info: Info)
		local view = info.view
		local you = view.you
		for _, row in rows do
			local sv = view.states[row.index]
			local legal = info.kind == nil or Logic.legal(info.kind, sv)
			local rank = ""
			if info.choices.first == row.id then
				rank = "1"
			elseif info.choices.second == row.id then
				rank = "2"
			end
			local chosen = rank ~= ""
			local fade = if legal then 0 else 0.55
			local tag = Logic.statusTag(sv, you)

			row.rank.Text = rank
			row.stroke.Thickness = if chosen then 2 else 0
			row.button.BackgroundColor3 = if chosen then Kit.colors.raisedHover else Kit.colors.raised
			row.button.BackgroundTransparency = if legal then 0 else 0.5
			row.button.AutoButtonColor = legal and info.interactive

			local owner = sv.owner
			row.code.TextColor3 = if owner ~= nil and info.colors[owner]
				then info.colors[owner]
				else Kit.colors.text
			row.code.TextTransparency = fade
			row.name.TextTransparency = fade
			row.ev.TextTransparency = fade
			row.tag.TextTransparency = fade
			row.name.Size = UDim2.fromScale(W_NAME, if tag then 0.62 else 1)
			row.tag.Visible = tag ~= nil
			row.tag.Text = tag or ""

			local text, favored = Logic.leanText(sv, you)
			row.lean.Text = text
			row.lean.TextColor3 = if favored ~= nil and info.colors[favored]
				then info.colors[favored]
				else Kit.colors.muted
			row.lean.TextTransparency = fade
		end
	end

	return list :: List
end

return StateList
