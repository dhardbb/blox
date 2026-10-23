--!strict
-- The week's plan as a list (docs/UI-STYLE.md §4.5): a title row "Your plan ·
-- 2 of 3 actions" with a two-tap Clear (the first tap asks "Clear? tap again" for
-- PlanList.CONFIRM_SECONDS), then one row per action with a × to remove it. The
-- plan in one line lives in the action bar's status (so a phone sees it without
-- scrolling); the actions and money left are on the header's now line. Shown
-- only while planning.
--
--   local plan = PlanList.new(parent, model, order)
--   plan:render(p) · plan:tick(now) · plan.root (Frame "PlanList")
--
-- Element names: PlanTitle, ClearButton, PlanItems, PlanItem<k>, RemoveItem<k>,
-- PlanEmpty.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlanDraft = require(ReplicatedStorage.Shared.UI.PlanDraft)

local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Model = require(script.Parent.Model)

local PlanList = {}

PlanList.CONFIRM_SECONDS = 3 -- s the "Clear? tap again" label waits for the second tap

local CLEAR_W = 120 -- px, the Clear button

export type PlanList = {
	root: Frame,
	render: (self: PlanList, p: Model.Payload) -> (),
	tick: (self: PlanList, now: number) -> (),
}

function PlanList.new(parent: Instance, model: Model.Model, order: number): PlanList
	local config = model.config
	local root = Kit.card({ Name = "PlanList", LayoutOrder = order, Parent = parent })

	local titleRow = Kit.box({
		Name = "PlanTitleRow",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = root,
	})
	local title = Kit.text("", {
		Name = "PlanTitle",
		Size = UDim2.new(1, -(CLEAR_W + Kit.space.sm), 1, 0),
		Font = Kit.font.bold,
		TextScaled = true,
		TextWrapped = false,
		Parent = titleRow,
	})
	local armedUntil: number? = nil
	local clear: TextButton
	clear = Kit.button("Clear", function()
		if clear.Active == false then
			return
		end
		local now = model.ctx.now()
		if armedUntil ~= nil and now <= armedUntil then
			armedUntil = nil
			model.draft.actions = {}
			model.pivotStage = nil
		else
			armedUntil = now + PlanList.CONFIRM_SECONDS
		end
		model.render()
	end, {
		variant = "danger",
		Name = "ClearButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, CLEAR_W, 1, 0),
		Parent = titleRow,
	})

	local items = Kit.box({
		Name = "PlanItems",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	Kit.list("Vertical", Kit.space.xs).Parent = items
	local empty =
		Kit.caption("Tap a state, then an action.", { Name = "PlanEmpty", LayoutOrder = 3, Parent = root })

	local function clearItems()
		for _, child in items:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function renderClear(canEdit: boolean, now: number)
		local armed = armedUntil ~= nil and now <= armedUntil
		if not armed then
			armedUntil = nil
		end
		clear.Text = if armed then "Clear? tap again" else "Clear"
		clear.Visible = #model.draft.actions > 0
		Kit.setEnabled(clear, canEdit and #model.draft.actions > 0)
	end

	local plan: PlanList = {
		root = root,
		render = function(_self: PlanList, p: Model.Payload)
			local view = p.view
			local show = Model.planning(p)
			root.Visible = show
			if not show then
				armedUntil = nil
				return
			end
			local canEdit = Model.editable(model, p)
			local cost = PlanDraft.cost(config, view, model.draft)
			local profile = PlanDraft.profile(config, view)
			title.Text = `Your plan · {cost.ap} of {profile.apPerWeek} actions`
			local flights: { [number]: boolean } = {}
			for _, stop in PlanDraft.route(view, model.draft) do
				flights[stop.index] = stop.flight
			end
			clearItems()
			for k, action in model.draft.actions do
				local row = Kit.box({
					Name = `PlanItemRow{k}`,
					LayoutOrder = k,
					Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
					Parent = items,
				})
				Kit.text(`{k}. {Model.actionText(config, action, flights[k] == true)}`, {
					Name = `PlanItem{k}`,
					Size = UDim2.new(1, -(Kit.MIN_TOUCH + Kit.space.sm), 1, 0),
					Parent = row,
				})
				local remove = Kit.iconButton("×", function()
					local now = model.payload
					if now == nil or not Model.editable(model, now) or model.draft.actions[k] == nil then
						return
					end
					PlanDraft.remove(model.draft, k)
					model.render()
				end, {
					Name = `RemoveItem{k}`,
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Parent = row,
				})
				Kit.setEnabled(remove, canEdit)
			end
			empty.Visible = #model.draft.actions == 0 and canEdit
			-- An empty list takes no gap of its own under the title.
			items.Visible = #model.draft.actions > 0
			renderClear(canEdit, model.ctx.now())
		end,
		tick = function(_self: PlanList, now: number)
			local p = model.payload
			if armedUntil ~= nil and now > armedUntil and p ~= nil then
				renderClear(Model.editable(model, p), now)
			end
		end,
	}
	return plan
end

return PlanList
