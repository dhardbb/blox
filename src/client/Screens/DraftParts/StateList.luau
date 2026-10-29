--!strict
-- The Draft screen's list picker: one tappable row per state ("Row_OH"), biggest
-- first, with its votes and its lean as a pill filled in that player's color
-- ("+2 you" on your color, "+2 Buster" on his; "Even" a raised tag). It
-- is the phone-friendly twin of tapping the map, and shares its choice slots.
-- By default it shows only the best picks (the biggest states this round
-- allows, plus anything chosen); "Show all states" shows every row, the ones
-- the round does not allow faded with a tag ("your home"). Rows are
-- Kit.MIN_TOUCH tall; a chosen row shows the accent outline, never a fill.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Draft = require(ReplicatedStorage.Shared.Sim.Draft)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local View = require(ReplicatedStorage.Shared.Sim.View)
local Words = require(ReplicatedStorage.Shared.UI.Words.Setup)

local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Logic = require(script.Parent.Logic)

export type Info = {
	view: View.View,
	kind: Draft.Kind?, -- the round's kind while picking; nil when nothing is pickable
	colors: { Color3 }, -- by player index
	choices: Logic.Choices,
	interactive: boolean, -- rows respond to taps
	showAll: boolean?, -- every state, not only the best picks
	opponent: string?, -- the opponent's first name, for the lean pills
}

export type List = {
	root: Frame,
	update: (self: List, info: Info) -> (),
	hidden: (self: List) -> number, -- rows the short list leaves out
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
	fitVotes: () -> (), -- ends the votes cell at the lean pill's left
}

local StateList = {}

StateList.SHORT = 8 -- rows the default list shows
local ROW_HEIGHT = Kit.MIN_TOUCH -- px

-- Columns as fractions of the row width: rank, code, name, votes; the lean pill
-- sits at the right edge, in the last quarter.
local X_RANK, W_RANK = 0, 0.07
local X_CODE, W_CODE = 0.07, 0.12
local X_NAME, W_NAME = 0.19, 0.33
local X_EV, W_EV = 0.52, 0.23
local PILL_CHAR_W = 8 -- px, a caption character in the lean pill (an estimate, on the wide side)

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
		TextScaled = true, -- one line that shrinks to fit (never below Kit.MIN_TEXT)
		TextWrapped = false,
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
	Kit.list("Vertical", Kit.space.xs).Parent = root
	local title = Kit.caption("", {
		Name = "ListTitle",
		LayoutOrder = 0,
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
		Kit.corner(Kit.radius.control).Parent = button
		local stroke = Kit.stroke(Kit.colors.accent, 2)
		stroke.Thickness = 0
		stroke.Parent = button
		Kit.new("UIPadding", {
			PaddingLeft = UDim.new(0, Kit.space.sm),
			PaddingRight = UDim.new(0, Kit.space.sm),
			PaddingTop = UDim.new(0, Kit.space.xs),
			PaddingBottom = UDim.new(0, Kit.space.xs),
			Parent = button,
		})
		local row: Row = {
			id = id,
			button = button,
			stroke = stroke,
			rank = cell(button, "Rank", X_RANK, W_RANK, 0, 1, {
				Font = Kit.font.bold,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			code = cell(button, "Code", X_CODE, W_CODE, 0, 1, { Font = Kit.font.bold }),
			name = cell(button, "Name", X_NAME, W_NAME, 0, 1, {}),
			tag = cell(button, "Tag", X_NAME, W_NAME, 0.6, 0.4, {
				TextSize = Kit.size.caption,
				TextColor3 = Kit.colors.muted,
				Visible = false,
			}),
			ev = cell(button, "EV", X_EV, W_EV, 0, 1, {
				TextColor3 = Kit.colors.muted,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
			lean = Kit.pill("", "muted", {
				Name = "Lean",
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				Parent = button,
			}),
			index = indexOf[id],
			fitVotes = function() end,
		}
		row.code.Text = id
		row.name.Text = record.name
		row.ev.Text = Words.votes(record.ev)
		-- The votes end where the lean pill starts: "+2 Buster" is wider than
		-- the last quarter, and ran over "30 votes" on an iPad (fix17).
		-- (Estimated from its text: an AutomaticSize width is not known until
		-- the next frame.)
		row.fitVotes = function()
			local text = row.lean.Text
			local pillW = (utf8.len(text) or #text) * PILL_CHAR_W + 2 * Kit.space.sm
			row.ev.Size = UDim2.new(1 - X_EV, -(pillW + Kit.space.sm), 1, 0)
		end
		button.Activated:Connect(function()
			onTap(id)
		end)
		table.insert(rows, row)
	end
	local hiddenCount = 0
	local list = {} :: any
	list.root = root

	function list.hidden(_self: List): number
		return hiddenCount
	end

	function list.update(_self: List, info: Info)
		local view = info.view
		local you = view.you
		local opponent = info.opponent or "them"
		local shown = 0
		hiddenCount = 0
		title.Text = if info.showAll then "All states, biggest first" else "Best picks, biggest first"
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
			local visible = info.showAll == true or chosen or (legal and shown < StateList.SHORT)
			if visible and not chosen and legal then
				shown += 1
			end
			if not visible then
				hiddenCount += 1
			end
			row.button.Visible = visible
			local fade = if legal then 0 else 0.55
			local tag = Logic.statusTag(sv, you)

			row.rank.Text = rank
			row.stroke.Thickness = if chosen then 2 else 0
			row.button.BackgroundColor3 = if chosen then Kit.colors.raisedHover else Kit.colors.raised
			row.button.BackgroundTransparency = if legal then 0 else 0.5
			row.button.AutoButtonColor = legal and info.interactive

			local owner = sv.owner
			row.code.TextColor3 = if owner ~= nil and info.colors[owner]
				then Kit.textColor(info.colors[owner])
				else Kit.colors.text
			row.code.TextTransparency = fade
			row.name.TextTransparency = fade
			row.ev.TextTransparency = fade
			row.tag.TextTransparency = fade
			row.name.Size = UDim2.fromScale(W_NAME, if tag then 0.6 else 1)
			row.tag.Visible = tag ~= nil
			row.tag.Text = tag or ""

			local to = sv.leanTo
			row.lean.Text = Words.lean(sv.lean, if to == nil then nil else to == you, opponent)
			row.fitVotes()
			-- A lean is filled in its player's color ("+2 Buster" on red, "+2 you"
			-- on blue) with readable text; "Even" stays a quiet raised tag.
			local leanColor = if to ~= nil and sv.lean > 0 then info.colors[to] else nil
			if leanColor then
				Kit.paintPill(row.lean, "text", true, leanColor)
			else
				Kit.paintPill(row.lean, "muted")
			end
			row.lean.TextTransparency = fade
			row.lean.BackgroundTransparency = fade
		end
	end

	return list :: List
end

return StateList
