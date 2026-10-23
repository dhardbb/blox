--!strict
-- The debate focus, on the Decision screen right before the debate (D-044).
-- One tap picks the topic; Lock in sends it (or the timer does).
--
--   Debate focus · week 4
--   Pick one topic: +2 on it. ...
--   [ Jobs (your platform) · 11 states, 142 EV ]            chip; selection = accent outline
--   You need 4 of them (61 EV): trail OH by 2 · lead PA by 3.
--   Focus here: 4 vs their 2, plus a roll 0 to 3 each. You win 81% (38% if they focus here too).
--   A win: +1.0 in each; could flip PA (+19 EV).
--   ... one block per topic ...
--
-- Holding a topic previews it on the map without selecting it; the map shows
-- the selected (or held) topic's states and what a win there would flip. Every
-- line comes from Shared/UI/Swing.focus, from the player's own View.
--
--   local focus = Focus.new(parent, model, order)
--   focus:render(p) · focus.root (Frame "FocusPanel")
--
-- Element names: FocusTitle, FocusIntro, FocusTopic<t>, FocusNeed<t>, FocusOdds<t>,
-- FocusWin<t>.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Numbers = require(ReplicatedStorage.Shared.UI.Numbers)
local SharedTypes = require(ReplicatedStorage.Shared.Types)
local Swing = require(ReplicatedStorage.Shared.UI.Swing)

local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Model = require(script.Parent.Model)

type Issue = SharedTypes.Issue

local Focus = {}

export type Focus = {
	root: Frame,
	render: (self: Focus, p: Model.Payload) -> (),
}

type Row = {
	button: TextButton,
	need: TextLabel,
	odds: TextLabel,
	win: TextLabel,
}

function Focus.new(parent: Instance, model: Model.Model, order: number): Focus
	local config = model.config

	local root = Kit.panel({
		Name = "FocusPanel",
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = parent,
	})
	Kit.list("Vertical", Kit.space.sm).Parent = root
	local title = Kit.heading(
		"",
		{ Name = "FocusTitle", LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.Y, Parent = root }
	)
	local intro = Kit.caption("", { Name = "FocusIntro", LayoutOrder = 2, Parent = root })

	local topics: { Issue } = {}
	local function held(input: InputObject): boolean
		local kind = input.UserInputType.Name
		return kind == "MouseButton1" or kind == "Touch"
	end

	local rows: { Row } = {}
	for t = 1, config.DEBATE_TOPICS do
		local box = Kit.box({
			Name = `FocusRow{t}`,
			LayoutOrder = 2 + t,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = root,
		})
		Kit.list("Vertical", Kit.space.xs).Parent = box
		local button: TextButton
		button = Kit.button("", function()
			local p = model.payload
			local topic: Issue? = topics[t]
			if button.Active == false or p == nil or topic == nil or not Model.editable(model, p) then
				return
			end
			model.focus = topic
			model.peekFocus = nil
			model.render()
		end, {
			variant = "chip",
			Name = `FocusTopic{t}`,
			LayoutOrder = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = box,
		})
		-- Press and hold: preview this topic on the map without picking it.
		button.InputBegan:Connect(function(input: InputObject)
			local topic: Issue? = topics[t]
			if held(input) and topic and model.peekFocus ~= topic then
				model.peekFocus = topic
				model.render()
			end
		end)
		button.InputEnded:Connect(function(input: InputObject)
			if held(input) and model.peekFocus ~= nil and model.peekFocus == topics[t] then
				model.peekFocus = nil
				model.render()
			end
		end)
		local need = Kit.caption("", {
			Name = `FocusNeed{t}`,
			LayoutOrder = 2,
			TextColor3 = Kit.colors.text,
			Parent = box,
		})
		local odds = Kit.caption("", { Name = `FocusOdds{t}`, LayoutOrder = 3, Parent = box })
		local win = Kit.caption("", { Name = `FocusWin{t}`, LayoutOrder = 4, Parent = box })
		rows[t] = { button = button, need = need, odds = odds, win = win }
	end

	local part: Focus = {
		root = root,
		render = function(_self: Focus, p: Model.Payload)
			local view = p.view
			local debate = view.nextDebate
			local show = Model.deciding(p) == "Focus" and debate ~= nil
			root.Visible = show
			if not show or debate == nil then
				return
			end
			topics = debate.topics :: { Issue }
			local canEdit = Model.editable(model, p)
			local edge = (Swing.focus(config, view, topics[1])).edge
			title.Text = `Debate focus · week {debate.week}`
			intro.Text =
				`Pick one topic: +{edge} on it. Win a topic: {Numbers.signed(config.DEBATE_TOPIC_WIN)} in every state where it is a top issue. No focus in time: every topic you lose is a gaffe ({Numbers.signed(
					-config.DEBATE_GAFFE
				)} in its states).`
			for t, row in rows do
				local topic: Issue? = topics[t]
				row.button.Visible = topic ~= nil
				row.need.Visible = topic ~= nil
				row.odds.Visible = topic ~= nil
				row.win.Visible = topic ~= nil
				if topic then
					local info = Swing.focus(config, view, topic)
					row.button.Text = info.head
					row.need.Text = info.needLine
					row.odds.Text = info.oddsLine
					row.win.Text = info.winLine
					Kit.setSelected(row.button, model.focus == topic)
					Kit.setEnabled(row.button, canEdit)
				end
			end
		end,
	}
	return part
end

return Focus
