--!strict
-- The debate focus, on the Decision screen right before the debate (D-044,
-- docs/UI-STYLE.md §4.4). One tap picks the topic; Lock in sends it (or the
-- timer does).
--
--   Which topic will you prepare? You get +2 on it.
--   [ Schools · 14 states            ]   chip; selection = accent outline
--   [ <You win 81%>                  ]
--   [ Jobs · 11 states               ]
--   [ <You win 64%> <Your issue>     ]
--   ( Why? + )
--     Win a topic: +1.0 in every state where it is a top issue. ...
--     Schools: You need 4 of them (61 EV): trail OH by 2 · lead PA by 3.
--     Focus here: 4 vs their 2, plus a roll 0 to 3 each. You win 81% (...).
--     A win: +1.0 in each; could flip PA (+19 EV).
--
-- Holding a topic previews it on the map without selecting it; the map shows
-- the selected (or held) topic's states and what a win there would flip. Every
-- number comes from Shared/UI/Swing.focus, from the player's own View.
--
--   local focus = Focus.new(parent, model, order)
--   focus:render(p) · focus.root (Frame "FocusPanel")
--
-- Element names: FocusTitle, FocusTopic<t> (FocusChance<t>, FocusYours<t>),
-- FocusWhy (WhyToggle), FocusIntro, FocusName<t>, FocusNeed<t>, FocusOdds<t>,
-- FocusWin<t>.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Numbers = require(ReplicatedStorage.Shared.UI.Numbers)
local SharedTypes = require(ReplicatedStorage.Shared.Types)
local Swing = require(ReplicatedStorage.Shared.UI.Swing)
local Words = require(ReplicatedStorage.Shared.UI.Words.Campaign)

local Collapsible = require(script.Parent.Parent.Parent.UI.Collapsible)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Model = require(script.Parent.Model)

type Issue = SharedTypes.Issue

local Focus = {}

local TOPIC_H = 64 -- px, one topic chip: its name over its pills

export type Focus = {
	root: Frame,
	render: (self: Focus, p: Model.Payload) -> (),
}

type Row = {
	button: TextButton,
	chance: TextLabel,
	yours: TextLabel,
	name: TextLabel,
	need: TextLabel,
	odds: TextLabel,
	win: TextLabel,
}

function Focus.new(parent: Instance, model: Model.Model, order: number): Focus
	local config = model.config

	local root = Kit.card({ Name = "FocusPanel", LayoutOrder = order, Visible = false, Parent = parent })
	local title = Kit.text("", {
		Name = "FocusTitle",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.medium,
		Parent = root,
	})

	local why = Collapsible.new(root, { title = "Why?", name = "FocusWhy", order = 10 })
	why.toggle.Name = "WhyToggle"
	why.root.BackgroundTransparency = 1
	local whyPad = why.root:FindFirstChildOfClass("UIPadding")
	if whyPad then
		whyPad:Destroy()
	end
	local intro = Kit.caption("", {
		Name = "FocusIntro",
		LayoutOrder = 0,
		TextColor3 = Kit.colors.text,
		Parent = why.body,
	})

	local topics: { Issue } = {}
	local function held(input: InputObject): boolean
		local kind = input.UserInputType.Name
		return kind == "MouseButton1" or kind == "Touch"
	end

	local rows: { Row } = {}
	for t = 1, config.DEBATE_TOPICS do
		local button: TextButton
		button = Kit.chip("", function()
			local p = model.payload
			local topic: Issue? = topics[t]
			if button.Active == false or p == nil or topic == nil or not Model.editable(model, p) then
				return
			end
			model.focus = topic
			model.peekFocus = nil
			model.render()
		end, {
			Name = `FocusTopic{t}`,
			LayoutOrder = 1 + t,
			Size = UDim2.new(1, 0, 0, TOPIC_H),
			Font = Kit.font.bold,
			TextScaled = false,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = root,
		})
		local pad = button:FindFirstChildOfClass("UIPadding")
		if pad then
			pad.PaddingTop = UDim.new(0, Kit.space.sm)
			pad.PaddingBottom = UDim.new(0, Kit.space.sm)
			pad.PaddingLeft = UDim.new(0, Kit.space.md)
			pad.PaddingRight = UDim.new(0, Kit.space.md)
		end
		-- The odds and "your issue" as pills under the name.
		local tags = Kit.box({
			Name = "Tags",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, Kit.PILL_H),
			Parent = button,
		})
		Kit.list("Horizontal", Kit.space.xs).Parent = tags
		local chance = Kit.pill("", "text", { Name = `FocusChance{t}`, LayoutOrder = 1, Parent = tags })
		local yours =
			Kit.pill("Your issue", "good", { Name = `FocusYours{t}`, LayoutOrder = 2, Parent = tags })
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
		local name = Kit.text("", {
			Name = `FocusName{t}`,
			LayoutOrder = 10 * t,
			Font = Kit.font.bold,
			Parent = why.body,
		})
		local need = Kit.caption("", {
			Name = `FocusNeed{t}`,
			LayoutOrder = 10 * t + 1,
			TextColor3 = Kit.colors.text,
			Parent = why.body,
		})
		local odds = Kit.caption("", { Name = `FocusOdds{t}`, LayoutOrder = 10 * t + 2, Parent = why.body })
		local win = Kit.caption("", { Name = `FocusWin{t}`, LayoutOrder = 10 * t + 3, Parent = why.body })
		rows[t] = {
			button = button,
			chance = chance,
			yours = yours,
			name = name,
			need = need,
			odds = odds,
			win = win,
		}
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
			local platform: { Issue } = view.players[view.you].platform or {}
			title.Text = `Which topic will you prepare? You get +{edge} on it.`
			intro.Text =
				`Win a topic: {Numbers.signed(config.DEBATE_TOPIC_WIN)} in every state where it is a top issue. No focus in time: every topic you lose is a gaffe ({Numbers.signed(
					-config.DEBATE_GAFFE
				)} in its states).`
			for t, row in rows do
				local topic: Issue? = topics[t]
				for _, inst in { row.button, row.name, row.need, row.odds, row.win } :: { GuiObject } do
					inst.Visible = topic ~= nil
				end
				if topic then
					local info = Swing.focus(config, view, topic)
					row.button.Text = Words.focusHead(config, view, info)
					row.chance.Text = Words.focusOdds(info)
					row.yours.Visible = table.find(platform, topic) ~= nil
					row.name.Text = Model.issueName(topic)
					row.need.Text = info.needLine
					row.odds.Text = info.oddsLine
					row.win.Text = info.winLine
					Kit.setSelected(row.button, model.focus == topic)
					Kit.setEnabled(row.button, canEdit)
					row.chance.TextColor3 = if canEdit then Kit.colors.text else Kit.colors.disabledText
				end
			end
		end,
	}
	return part
end

return Focus
