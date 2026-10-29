--!strict
-- The week's plan (docs/UI-STYLE.md §4.5): its action slots first (D-093,
-- CampaignParts/PlanSlots: one tile per action with its icon and state, repeats
-- merged "×2", an outlined tile per free action slot; a tap on a tile removes
-- that action), then one row per action with its details and a × to remove
-- it, and a two-tap Clear (the first tap asks "Clear? tap again" for
-- PlanList.CONFIRM_SECONDS). The slots also stand in the action bar's status
-- row (so a phone sees them without scrolling); the actions and money left are
-- on the header's now line. Shown only while planning.
--
--   local plan = PlanList.new(parent, model, order)
--   plan:render(p) · plan:tick(now) · plan.root (Frame "PlanList")
--
-- Motion and sound (docs/DESIGN.md D-053): a new row (or a ground-game row
-- gaining a unit) slides in with the "planAdd" cue; a removed row fades out
-- where it was ("PlanItemLeaving", decorative) with "planRemove". One cue per
-- change, whichever part of the screen made it (the state card, the pivot
-- chooser, ×, Clear). A new draft (a new week) starts quietly.
--
-- Element names: PlanSlots (Slot<k>, SlotEmpty<k>), PlanTitle (hidden: "2 of 3
-- actions"), ClearButton, PlanItems, PlanItem<k>, RemoveItem<k>, PlanEmpty.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Plan = require(ReplicatedStorage.Shared.Sim.Plan)
local PlanDraft = require(ReplicatedStorage.Shared.UI.PlanDraft)
local Words = require(ReplicatedStorage.Shared.UI.Words.Campaign)

local Audio = require(script.Parent.Parent.Parent.UI.Audio)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Model = require(script.Parent.Model)
local Motion = require(script.Parent.Parent.Parent.UI.Motion)
local PlanSlots = require(script.Parent.PlanSlots)

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

	-- The slots replace the "Your plan · 2 of 3 actions" title (D-093).
	local slots = PlanSlots.new(root, {
		name = "PlanSlots",
		order = 0,
		onTap = function(slot)
			local now = model.payload
			local index = slot.index
			if
				now == nil
				or not Model.editable(model, now)
				or index == nil
				or model.draft.actions[index] == nil
			then
				return
			end
			local action = model.draft.actions[index]
			if action.kind == "Gotv" and (action.units or 1) > 1 then
				action.units = (action.units or 1) - 1
			else
				PlanDraft.remove(model.draft, index)
			end
			model.render()
		end,
	})
	local titleRow = Kit.box({
		Name = "PlanTitleRow",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = root,
	})
	local title = Kit.text("", {
		Name = "PlanTitle",
		Size = UDim2.new(1, -(CLEAR_W + Kit.space.sm), 1, 0),
		Font = Kit.font.bold,
		TextScaled = true,
		TextWrapped = false,
		Visible = false,
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
		Kit.caption("Tap a state, then an action.", { Name = "PlanEmpty", LayoutOrder = 1, Parent = root })

	local function clearItems()
		for _, child in items:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	-- What the rows showed at the last render, to spot what changed: each action
	-- (by identity) with its units, its row's text and place.
	type Seen = { units: number, text: string, k: number }
	local seenDraft: PlanDraft.Draft? = nil
	local seen: { [Plan.Action]: Seen } = {}

	-- A removed row fading out where it was (layout orders: rows 2k, this 2k-1).
	local function leaving(entry: Seen)
		local row = Kit.text(entry.text, {
			Name = "PlanItemLeaving",
			LayoutOrder = 2 * entry.k - 1,
			Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
			TextColor3 = Kit.colors.muted,
			Parent = items,
		})
		row:SetAttribute("Decor", true)
		Motion.exit(row, function()
			row:Destroy()
		end)
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
				seenDraft = nil
				return
			end
			local canEdit = Model.editable(model, p)
			local cost = PlanDraft.cost(config, view, model.draft)
			local profile = PlanDraft.profile(config, view)
			title.Text = `{cost.ap} of {profile.apPerWeek} actions`
			slots:render(Words.planSlots(model.draft.actions, profile.apPerWeek, config.PIVOT_AP), canEdit)
			local flights: { [number]: boolean } = {}
			for _, stop in PlanDraft.route(view, model.draft) do
				flights[stop.index] = stop.flight
			end
			clearItems()
			local quiet = seenDraft ~= model.draft
			seenDraft = model.draft
			local was = seen
			seen = {}
			local added = false
			for k, action in model.draft.actions do
				local text = `{k}. {Model.actionText(config, action, flights[k] == true)}`
				local before = was[action]
				local units = action.units or 0
				seen[action] = { units = units, text = text, k = k }
				local row = Kit.box({
					Name = `PlanItemRow{k}`,
					LayoutOrder = 2 * k,
					Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
					Parent = items,
				})
				local label = Kit.text(text, {
					Name = `PlanItem{k}`,
					Size = UDim2.new(1, -(Kit.MIN_TOUCH + Kit.space.sm), 1, 0),
					Parent = row,
				})
				if not quiet and (before == nil or units > before.units) then
					-- New (or one more unit): the line slides up into its row.
					added = true
					Motion.enter(label)
				end
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
			local removed = false
			if not quiet then
				for action, entry in was do
					if seen[action] == nil then
						removed = true
						leaving(entry)
					end
				end
			end
			if added then
				Audio.play("planAdd")
			elseif removed then
				Audio.play("planRemove")
			end
			empty.Visible = #model.draft.actions == 0 and canEdit
			-- An empty list takes no gap of its own under the title (a row still
			-- fading out keeps it open).
			items.Visible = #model.draft.actions > 0 or removed
			renderClear(canEdit, model.ctx.now())
			titleRow.Visible = clear.Visible
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
