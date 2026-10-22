--!strict
-- Debate prep, in the week before a debate (UI overhaul §3.4, bug B2): it sits
-- right under the event card, above the plan list, so it is seen before Lock in.
--
--   Debate prep · week 9 · 6 points
--   Schools  (your platform)                     [−]  2  [+]
--   ●●○○                                                      dot strip: the allocation
--   take from another topic                                   why a stepper is greyed
--   ... one row per topic ...
--   0 prep on a lost topic is a gaffe.
--
-- The steppers keep the total: + takes a point from the topic with the most, −
-- gives one to the topic with the least.
--
--   local prep = Prep.new(parent, model, order)
--   prep:render(p) · prep:summary() -> "prep 2/2/2" or nil · prep.root (Frame "PrepPanel")
--
-- Element names: PrepTitle, PrepRow<t>, PrepTopic<t>, PrepMinus<t>, PrepValue<t>,
-- PrepPlus<t>, PrepDots<t>, PrepNote<t>, PrepTotal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlanDraft = require(ReplicatedStorage.Shared.UI.PlanDraft)
local SharedTypes = require(ReplicatedStorage.Shared.Types)

local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Model = require(script.Parent.Model)

type Issue = SharedTypes.Issue

local Prep = {}

local DOT = 8 -- px, one cell of the allocation strip
local TOPIC_H = 24 -- px, the topic line beside the steppers

export type Prep = {
	root: Frame,
	render: (self: Prep, p: Model.Payload) -> (),
	summary: (self: Prep) -> string?,
}

type Row = {
	topic: TextLabel,
	value: TextLabel,
	minus: TextButton,
	plus: TextButton,
	dots: { Frame },
	note: TextLabel,
}

function Prep.new(parent: Instance, model: Model.Model, order: number): Prep
	local config = model.config
	local max = config.DEBATE_MAX_PER_TOPIC

	local root = Kit.panel({
		Name = "PrepPanel",
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = parent,
	})
	Kit.list("Vertical", Kit.space.sm).Parent = root
	local title = Kit.heading(
		"",
		{ Name = "PrepTitle", LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.Y, Parent = root }
	)

	-- Moves one point onto (delta 1) or off (delta -1) topic t, keeping the total.
	local function step(t: number, delta: number)
		local p = model.payload
		local prep = model.draft.prep
		if p == nil or prep == nil or not Model.editable(model, p) then
			return
		end
		local other: number? = nil
		for k = 1, #prep do
			if k ~= t then
				local giver = delta > 0 and prep[k] > 0 and (other == nil or prep[k] > prep[other])
				local taker = delta < 0 and prep[k] < max and (other == nil or prep[k] < prep[other])
				if giver or taker then
					other = k
				end
			end
		end
		local nextValue = prep[t] + delta
		if other == nil or nextValue < 0 or nextValue > max then
			return
		end
		prep[t] = nextValue
		prep[other] -= delta
		model.render()
	end

	local rows: { Row } = {}
	local controlsW = 3 * Kit.MIN_TOUCH + 2 * Kit.space.xs
	for t = 1, config.DEBATE_TOPICS do
		local box = Kit.box({
			Name = `PrepRow{t}`,
			LayoutOrder = 1 + t,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = root,
		})
		Kit.list("Vertical", Kit.space.xs).Parent = box
		local controls = Kit.box({
			Name = `PrepControls{t}`,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
			Parent = box,
		})
		local topic = Kit.text("", {
			Name = `PrepTopic{t}`,
			Size = UDim2.new(1, -(controlsW + Kit.space.sm), 0, TOPIC_H),
			TextScaled = true,
			Parent = controls,
		})
		local dotStrip = Kit.box({
			Name = `PrepDots{t}`,
			Position = UDim2.fromOffset(0, TOPIC_H + Kit.space.xs),
			Size = UDim2.fromOffset(max * (DOT + Kit.space.xs), DOT),
			Parent = controls,
		})
		local dots: { Frame } = {}
		for k = 1, max do
			local dot = Kit.new("Frame", {
				Name = `Dot{k}`,
				Position = UDim2.fromOffset((k - 1) * (DOT + Kit.space.xs), 0),
				Size = UDim2.fromOffset(DOT, DOT),
				BorderSizePixel = 0,
				BackgroundColor3 = Kit.colors.raised,
				Parent = dotStrip,
			}) :: Frame
			Kit.round().Parent = dot
			dots[k] = dot
		end
		local minus: TextButton
		minus = Kit.iconButton("−", function()
			if minus.Active == false then
				return
			end
			step(t, -1)
		end, {
			Name = `PrepMinus{t}`,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(2 * (Kit.MIN_TOUCH + Kit.space.xs)), 0, 0),
			Parent = controls,
		})
		local value = Kit.text("", {
			Name = `PrepValue{t}`,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(Kit.MIN_TOUCH + Kit.space.xs), 0, 0),
			Size = UDim2.fromOffset(Kit.MIN_TOUCH, Kit.MIN_TOUCH),
			Font = Kit.font.bold,
			TextSize = Kit.size.heading,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = controls,
		})
		local plus: TextButton
		plus = Kit.iconButton("+", function()
			if plus.Active == false then
				return
			end
			step(t, 1)
		end, {
			Name = `PrepPlus{t}`,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Parent = controls,
		})
		local note = Kit.caption("", { Name = `PrepNote{t}`, LayoutOrder = 2, Visible = false, Parent = box })
		rows[t] = { topic = topic, value = value, minus = minus, plus = plus, dots = dots, note = note }
	end
	local total = Kit.caption("0 prep on a lost topic is a gaffe.", {
		Name = "PrepTotal",
		LayoutOrder = 10,
		Parent = root,
	})

	local prepPart: Prep = {
		root = root,
		summary = function(_self: Prep): string?
			local prep = model.draft.prep
			if not root.Visible or prep == nil then
				return nil
			end
			local parts: { string } = {}
			for k = 1, #prep do
				table.insert(parts, tostring(prep[k]))
			end
			return `prep {table.concat(parts, "/")}`
		end,
		render = function(_self: Prep, p: Model.Payload)
			local view = p.view
			local prep = model.draft.prep
			local show = Model.planning(p) and Model.prepWanted(view) and prep ~= nil
			root.Visible = show
			if not show or prep == nil then
				return
			end
			local debate = view.nextDebate :: { week: number, topics: { Issue } }
			local points = PlanDraft.profile(config, view).debatePrep
			local canEdit = Model.editable(model, p)
			title.Text = `Debate prep · week {debate.week} · {points} points`
			local mine: { Issue } = view.players[view.you].platform or {}
			local theirs: { Issue } = view.players[Model.opponentOf(view)].platform or {}
			local placed = 0
			for t, row in rows do
				local topic: Issue? = debate.topics[t]
				local tags: { string } = {}
				if topic and table.find(mine, topic) then
					table.insert(tags, "your platform")
				end
				if topic and table.find(theirs, topic) then
					table.insert(tags, "their platform")
				end
				row.topic.Text = Model.issueName(topic)
					.. (if #tags > 0 then ` ({table.concat(tags, ", ")})` else "")
				local value = prep[t] or 0
				placed += value
				row.value.Text = tostring(value)
				for k, dot in row.dots do
					dot.BackgroundColor3 = if k <= value then Kit.colors.text else Kit.colors.raised
				end
				local othersHave, othersRoom = false, false
				for k = 1, #prep do
					if k ~= t then
						othersHave = othersHave or prep[k] > 0
						othersRoom = othersRoom or prep[k] < max
					end
				end
				local canPlus = value < max and othersHave
				local canMinus = value > 0 and othersRoom
				Kit.setEnabled(row.plus, canEdit and canPlus)
				Kit.setEnabled(row.minus, canEdit and canMinus)
				-- Say why a stepper is greyed out (not when the whole plan is locked).
				local why: { string } = {}
				if canEdit and not canPlus then
					table.insert(
						why,
						if value >= max then `+: max {max}` else "+: take from another topic first"
					)
				end
				if canEdit and not canMinus then
					table.insert(
						why,
						if value <= 0 then "−: none to take" else "−: the other topics are full"
					)
				end
				row.note.Text = table.concat(why, " · ")
				row.note.Visible = #why > 0
			end
			total.Text = `{placed} of {points} points placed. 0 prep on a lost topic is a gaffe.`
		end,
	}
	return prepPart
end

return Prep
