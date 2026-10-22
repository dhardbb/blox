--!strict
-- How the Campaign screen's state list orders and describes the states. Pure:
-- works from the player's own View (public polls and leans, their own momentum).

local StateData = require("../Sim/StateData")
local ViewModule = require("../Sim/View")

type View = ViewModule.View
type StateView = ViewModule.StateView

export type Mode = "Closest" | "Biggest" | "Name"

local StateOrder = {}

StateOrder.MODES = table.freeze({ "Closest", "Biggest", "Name" } :: { Mode })

local LABELS: { [string]: string } = {
	Closest = "Closest first",
	Biggest = "Biggest first",
	Name = "A to Z",
}

-- The button text for a sort mode.
function StateOrder.label(mode: Mode): string
	return LABELS[mode]
end

-- The mode after `mode`.
function StateOrder.nextMode(mode: Mode): Mode
	for k, candidate in StateOrder.MODES do
		if candidate == mode then
			return StateOrder.MODES[k % #StateOrder.MODES + 1]
		end
	end
	return StateOrder.MODES[1]
end

-- You minus them: the latest public poll, or the lean (a lean of L counts as a
-- margin of L) before the first poll. Positive favors `view.you`.
function StateOrder.margin(view: View, sv: StateView): number
	local you = view.you
	local poll = sv.poll
	if poll then
		local them = if you == 1 then 2 else 1
		return (poll.support[you] or 0) - (poll.support[them] or 0)
	end
	if sv.leanTo == nil then
		return 0
	end
	return if sv.leanTo == you then sv.lean else -sv.lean
end

-- Your momentum there.
function StateOrder.momentum(view: View, sv: StateView): number
	return sv.momentum[view.you] or 0
end

-- "You +3" / "Them +2" / "Tied", marked as a lean when there is no poll yet.
function StateOrder.marginText(view: View, sv: StateView): string
	local margin = StateOrder.margin(view, sv)
	local text
	if margin > 0 then
		text = `You +{margin}`
	elseif margin < 0 then
		text = `Them +{-margin}`
	else
		text = "Tied"
	end
	if sv.poll == nil then
		return if margin == 0 then "No poll" else `Lean: {text}`
	end
	return text
end

-- "Mom +0.5" with a sign, never "-0.0".
function StateOrder.momentumText(view: View, sv: StateView): string
	local value = StateOrder.momentum(view, sv)
	if math.abs(value) < 0.05 then
		return "Mom 0"
	end
	return string.format("Mom %+.1f", value)
end

-- Every state id in the order the list shows them.
function StateOrder.sort(view: View, mode: Mode): { string }
	local rows: { { id: string, ev: number, name: string, gap: number } } = {}
	for i, record in StateData.list do
		local sv = view.states[i]
		table.insert(rows, {
			id = record.id,
			ev = record.ev,
			name = record.name,
			gap = if sv then math.abs(StateOrder.margin(view, sv)) else 0,
		})
	end
	table.sort(rows, function(a, b)
		if mode == "Closest" then
			if a.gap ~= b.gap then
				return a.gap < b.gap
			end
			if a.ev ~= b.ev then
				return a.ev > b.ev
			end
		elseif mode == "Biggest" then
			if a.ev ~= b.ev then
				return a.ev > b.ev
			end
		else
			if a.name ~= b.name then
				return a.name < b.name
			end
		end
		return a.id < b.id
	end)
	local ids: { string } = {}
	for k, row in rows do
		ids[k] = row.id
	end
	return ids
end

return StateOrder
