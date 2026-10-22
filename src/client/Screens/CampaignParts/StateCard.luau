--!strict
-- The selected state's card (UI overhaul §3.4): the state's name and tags, its
-- numbers as a 2x2 grid of stats, the message chips, the 3x3 action grid (or
-- the pivot chooser in its place), and the full state list behind a title row.
--
--   Ohio · 17 EV   [Battleground] [You are here]
--   Public poll                 Lean
--   you 35 – 37 them · 28 und.  +3 them
--   Momentum                    Ground game
--   ▲ you 2.0 · them 1.0        0 / 4 · pool size $8.9
--   You lead momentum: about +0.3 support drifts to you next week. Drift: ...
--   Your attack backlash here: 1 of 3. ...           (only with backlash)
--   Top issues: Jobs, Schools
--   Message for rallies and ads
--   [Jobs ×1.5] [Schools ×1.2] [Health ×1.0] [More +]
--   [Rally] [Fundraise] [Ad $3.0] / [Attack ad] [Poll] [Ground game +1] / [Region poll] [Pivot]
--   What each action does here –
--     Rally: about +3.9 you, -1.2 them here (Jobs ×1.5); +2 momentum; 1 AP
--     ... one line per action button (Shared/UI/Explain) ...
--   All states · sorted closest
--
-- During a reveal the card stays up read-only (numbers, no actions), so a player
-- can inspect a state while the results play.
--
--   local card = StateCard.new(parent, model, order)
--   card:render(p) · card:closeList() · card.root (Frame "StateCard")
--
-- Element names (tests and agents use them): CardTitle, CardTags, CardPoll,
-- CardLean, CardMomentum, CardMomentumNote, CardBacklash, CardGround,
-- CardInternal, CardIssues, ActionPreview (PreviewToggle, Preview<button name>), Issue<issue>
-- (message chips), MessageMore, Rally, Fundraise, Ad, Attack, Poll, Gotv,
-- RegionPoll, PivotButton, PivotDrop<issue>, PivotAdd<issue>, PivotCancel,
-- ActionHint, StatesToggle, StatePicker, Sort_<mode>, Row_<id>.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedFolder = ReplicatedStorage.Shared
local Explain = require(SharedFolder.UI.Explain)
local Issues = require(SharedFolder.Sim.Issues)
local Plan = require(SharedFolder.Sim.Plan)
local PlanDraft = require(SharedFolder.UI.PlanDraft)
local Resolve = require(SharedFolder.Sim.Resolve)
local SimState = require(SharedFolder.Sim.State)
local StateData = require(SharedFolder.Sim.StateData)
local StateOrder = require(SharedFolder.UI.StateOrder)
local SharedTypes = require(SharedFolder.Types)
local ViewModule = require(SharedFolder.Sim.View)

local Collapsible = require(script.Parent.Parent.Parent.UI.Collapsible)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Parent.Common.Layout)
local Model = require(script.Parent.Model)

type View = ViewModule.View
type Issue = SharedTypes.Issue
type Action = Plan.Action
type Payload = Model.Payload

local StateCard = {}

local GAP = Kit.space.sm
local TAG_H = 22 -- px, a tag pill
local MAX_TAGS = 4
local COLUMNS = 3 -- message chips, actions and pivot choices per row

-- The action grid in reading order: button name and player-facing label.
local ACTIONS: { { name: string, label: string } } = {
	{ name = "Rally", label = "Rally" },
	{ name = "Fundraise", label = "Fundraise" },
	{ name = "Ad", label = "Ad" },
	{ name = "Attack", label = "Attack ad" },
	{ name = "Poll", label = "Poll" },
	{ name = "Gotv", label = "Ground game +1" },
	{ name = "RegionPoll", label = "Region poll" },
	{ name = "PivotButton", label = "Pivot" },
}

-- Short reasons shown on a greyed-out action button.
local SHORT_REASON: { [string]: string } = {
	NotEnoughAP = "no AP",
	NotEnoughMoney = "no $",
	GotvCap = "max",
	DuplicatePoll = "polled",
	PivotUsed = "used",
	TooManyActions = "full",
}

export type StateCard = {
	root: Frame,
	render: (self: StateCard, p: Payload) -> (),
	closeList: (self: StateCard) -> (),
}

-- A grid frame whose cells are `columns` across and `height` tall; returns the
-- frame and the matching cell size (children carry it too, for the fake engine).
local function grid(parent: Instance, name: string, order: number, height: number): (Frame, UDim2)
	local frame, layout = Layout.grid(parent, name, order)
	Layout.setGrid(layout, COLUMNS, height, GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	return frame, layout.CellSize
end

-- A box that grows with its stacked contents.
local function stack(parent: Instance, order: number, name: string, gap: number): Frame
	local frame = Kit.box({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Kit.list("Vertical", gap).Parent = frame
	return frame
end

function StateCard.new(parent: Instance, model: Model.Model, order: number): StateCard
	local config = model.config

	local root = Kit.panel({
		Name = "StateCard",
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Kit.list("Vertical", GAP).Parent = root

	-- ------------------------------------------------------------ title and tags

	local title = Kit.heading("", { Name = "CardTitle", LayoutOrder = 1, Parent = root })
	local tagRow = Kit.box({
		Name = "CardTags",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, TAG_H),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	local tagList = Kit.list("Horizontal", Kit.space.xs)
	tagList.Wraps = true
	tagList.Parent = tagRow
	local tags: { TextLabel } = {}
	for k = 1, MAX_TAGS do
		local tag = Kit.text("", {
			Name = `Tag{k}`,
			LayoutOrder = k,
			Size = UDim2.fromOffset(0, TAG_H),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 0,
			BackgroundColor3 = Kit.colors.raised,
			TextSize = Kit.size.caption,
			Visible = false,
			Parent = tagRow,
		})
		Kit.corner(Kit.radius.pill).Parent = tag
		Kit.new("UIPadding", {
			PaddingLeft = UDim.new(0, Kit.space.sm),
			PaddingRight = UDim.new(0, Kit.space.sm),
			Parent = tag,
		})
		tags[k] = tag
	end

	-- ------------------------------------------------------------ stats

	local details = stack(root, 3, "CardDetails", Kit.space.xs)
	local function statRow(k: number): Frame
		local frame = Kit.box({
			Name = `StatRow{k}`,
			LayoutOrder = k,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = details,
		})
		Kit.list("Horizontal", GAP).Parent = frame
		return frame
	end
	local function stat(row: Frame, k: number, label: string, name: string): TextLabel
		local cell, value = Kit.stat(row, label, "", `{name}Cell`)
		cell.LayoutOrder = k
		cell.Size = UDim2.new(0.5, -GAP // 2, 0, cell.Size.Y.Offset)
		value.Name = name
		return value
	end
	local row1, row2 = statRow(1), statRow(2)
	local pollValue = stat(row1, 1, "Public poll", "CardPoll")
	local leanValue = stat(row1, 2, "Lean", "CardLean")
	local momentumValue = stat(row2, 1, "Momentum", "CardMomentum")
	local groundValue = stat(row2, 2, "Ground game", "CardGround")
	local momentumNote = Kit.caption("", { Name = "CardMomentumNote", LayoutOrder = 3, Parent = details })
	local backlashNote = Kit.caption("", {
		Name = "CardBacklash",
		LayoutOrder = 4,
		TextColor3 = Kit.colors.danger,
		Visible = false,
		Parent = details,
	})
	local internalCell, internalValue = Kit.stat(details, "Your internal poll", "", "CardInternalCell")
	internalCell.LayoutOrder = 5
	internalValue.Name = "CardInternal"
	internalValue.TextColor3 = Kit.colors.good
	local issuesLine = Kit.caption("", { Name = "CardIssues", LayoutOrder = 6, Parent = details })

	-- ------------------------------------------------------------ message chips

	local actionsBox = stack(root, 4, "Actions", GAP)
	Kit.caption(
		"Message for rallies and ads",
		{ Name = "MessageLabel", LayoutOrder = 1, Parent = actionsBox }
	)
	local chipGrid, chipSize = grid(actionsBox, "MessageChips", 2, Kit.MIN_TOUCH)
	local moreGrid = grid(actionsBox, "MoreIssues", 3, Kit.MIN_TOUCH)
	local issueChips: { [string]: TextButton } = {}
	for k = 1, #Issues.list do
		local issue: Issue = Issues.list[k]
		local button: TextButton
		button = Kit.button(Model.issueName(issue), function()
			if button.Active == false then
				return
			end
			model.chosenIssue = issue
			model.render()
		end, {
			variant = "chip",
			Name = `Issue{issue}`,
			LayoutOrder = k,
			Size = chipSize,
			TextWrapped = true,
			Parent = chipGrid,
		})
		issueChips[issue] = button
	end
	local moreChip: TextButton
	moreChip = Kit.button("More +", function()
		if moreChip.Active == false then
			return
		end
		model.moreIssues = not model.moreIssues
		model.render()
	end, { variant = "chip", Name = "MessageMore", LayoutOrder = 100, Size = chipSize, Parent = chipGrid })

	-- ------------------------------------------------------------ action grid

	local actionGrid, actionSize = grid(actionsBox, "ActionGrid", 4, Kit.MIN_TOUCH)
	local addAction: (name: string) -> ()
	local pivotOpen: () -> ()
	local actionButtons: { [string]: TextButton } = {}
	for k, entry in ACTIONS do
		local button: TextButton
		button = Kit.button(entry.label, function()
			if button.Active == false then
				return
			end
			if entry.name == "PivotButton" then
				pivotOpen()
			else
				addAction(entry.name)
			end
		end, {
			Name = entry.name,
			LayoutOrder = k,
			Size = actionSize,
			TextWrapped = true,
			Parent = actionGrid,
		})
		actionButtons[entry.name] = button
	end

	-- The pivot chooser takes the action grid's place: drop an issue, then add one.
	local pivotPanel = stack(actionsBox, 5, "PivotChooser", GAP)
	local pivotTitle = Kit.caption("", {
		Name = "PivotTitle",
		LayoutOrder = 1,
		TextColor3 = Kit.colors.text,
		Parent = pivotPanel,
	})
	local pivotChoices, pivotSize = grid(pivotPanel, "PivotChoices", 2, Kit.MIN_TOUCH)
	Kit.button("Cancel", function()
		model.pivotStage = nil
		model.pivotDrop = nil
		model.render()
	end, { variant = "secondary", Name = "PivotCancel", LayoutOrder = 3, Parent = pivotPanel })

	local hint = Kit.caption("", { Name = "ActionHint", LayoutOrder = 6, Parent = actionsBox })

	-- What each button would do here, worked out by Shared/UI/Explain: one line
	-- per button, so it works on touch (no hover needed).
	local preview = Collapsible.new(actionsBox, {
		title = "What each action does here",
		name = "ActionPreview",
		order = 7,
		expanded = true,
		onToggle = function()
			model.render()
		end,
	})
	preview.toggle.Name = "PreviewToggle"
	local previewLines: { [string]: TextLabel } = {}
	for k, entry in ACTIONS do
		previewLines[entry.name] = Kit.caption("", {
			Name = `Preview{entry.name}`,
			LayoutOrder = k,
			TextColor3 = Kit.colors.text,
			Parent = preview.body,
		})
	end

	-- ------------------------------------------------------------ state list

	local list = Collapsible.new(root, {
		title = "All states",
		name = "StateList",
		order = 5,
		onToggle = function()
			model.render()
		end,
	})
	list.toggle.Name = "StatesToggle"
	list.body.Name = "StatePicker"
	local sortGrid, sortSize = grid(list.body, "StatesSort", 0, Kit.MIN_TOUCH)
	local sortChips: { [string]: TextButton } = {}
	for k = 1, #StateOrder.MODES do
		local mode: StateOrder.Mode = StateOrder.MODES[k]
		local button = Kit.button(StateOrder.label(mode), function()
			model.sortMode = mode
			model.render()
		end, { variant = "chip", Name = `Sort_{mode}`, LayoutOrder = k, Size = sortSize, Parent = sortGrid })
		sortChips[mode] = button
	end
	local rowsBox = stack(list.body, 1, "StateRows", Kit.space.xs)

	type PickerRow = {
		index: number,
		button: TextButton,
		code: TextLabel,
		margin: TextLabel,
		momentum: TextLabel,
	}
	local pickerRows: { [string]: PickerRow } = {}
	for index, record in StateData.list do
		local id = record.id
		local button = Kit.button("", function()
			model.selectState(id)
		end, {
			variant = "chip",
			Name = `Row_{id}`,
			LayoutOrder = index,
			Parent = rowsBox,
		})
		local function cell(name: string, x: number, w: number, props: { [string]: any }): TextLabel
			local base: { [string]: any } = {
				Name = name,
				Position = UDim2.fromScale(x, 0),
				Size = UDim2.fromScale(w, 1),
				TextScaled = true,
				TextSize = Kit.size.body,
				Parent = button,
			}
			for key, value in props do
				base[key] = value
			end
			return Kit.text("", base)
		end
		local code = cell("Code", 0, 0.1, { Font = Kit.font.bold })
		cell("Name", 0.1, 0.36, {}).Text = record.name
		cell("EV", 0.46, 0.12, { TextXAlignment = Enum.TextXAlignment.Center }).Text = `{record.ev} EV`
		local margin = cell("Margin", 0.58, 0.24, {
			Font = Kit.font.medium,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local momentum = cell("Momentum", 0.82, 0.18, {
			TextSize = Kit.size.caption,
			TextColor3 = Kit.colors.muted,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		code.Text = id
		pickerRows[id] = { index = index, button = button, code = code, margin = margin, momentum = momentum }
	end

	-- ------------------------------------------------------------ plan logic

	-- The action a grid button adds for state `id`.
	local function actionFor(view: View, name: string, id: string): Action
		if name == "Rally" then
			return { kind = "Rally", state = id, issue = Model.messageIssue(model, view, id) }
		elseif name == "Fundraise" then
			return { kind = "Fundraise", state = id }
		elseif name == "Ad" then
			return { kind = "Media", state = id, issue = Model.messageIssue(model, view, id) }
		elseif name == "Attack" then
			local issue: Issue = PlanDraft.bestAttackIssue(config, view, id)
			return { kind = "Attack", state = id, issue = issue, target = Model.opponentOf(view) }
		elseif name == "Poll" then
			return { kind = "Poll", state = id }
		elseif name == "RegionPoll" then
			return { kind = "RegionPoll", region = PlanDraft.regionOf(id) }
		end
		return { kind = "Gotv", state = id, units = 1 }
	end

	-- A region already polled in the draft (the server would take it, but it
	-- would only spend the money twice).
	local function regionPlanned(action: Action): boolean
		for _, existing in model.draft.actions do
			if existing.kind == "RegionPoll" and existing.region == action.region then
				return true
			end
		end
		return false
	end

	-- Why an action can't be added right now, as a reason code, or nil.
	local function problemOf(view: View, action: Action): string?
		if action.kind == "RegionPoll" and regionPlanned(action) then
			return Plan.Reason.DuplicatePoll
		end
		return Model.trial(model, view, action)
	end

	addAction = function(name: string)
		local p = model.payload
		local id = model.selected
		if p == nil or id == nil or not Model.editable(model, p) then
			return
		end
		local view = p.view
		local action = actionFor(view, name, id)
		if problemOf(view, action) ~= nil then
			return
		end
		if action.kind == "Gotv" then
			-- One plan line per state: +1 adds a unit to it.
			for _, existing in model.draft.actions do
				if existing.kind == "Gotv" and existing.state == id then
					existing.units = (existing.units or 0) + 1
					model.render()
					return
				end
			end
		end
		PlanDraft.add(model.draft, action)
		model.render()
	end

	-- Can a pivot go into this plan? (nil, or the reason code.)
	local function pivotProblem(view: View): string?
		local me = view.players[view.you]
		local platform: { Issue } = me.platform or {}
		if me.pivotUsed then
			return Plan.Reason.PivotUsed
		end
		for _, action in model.draft.actions do
			if action.kind == "Pivot" then
				return Plan.Reason.PivotUsed
			end
		end
		if #platform == 0 then
			return Plan.Reason.BadPivot
		end
		local probe: Action = { kind = "Pivot", drop = platform[1], add = platform[1] }
		return Model.trial(model, view, probe)
	end

	pivotOpen = function()
		model.pivotStage = if model.pivotStage == nil then "drop" else nil
		model.pivotDrop = nil
		model.render()
	end

	-- ------------------------------------------------------------ render

	local function clearPivotChoices()
		for _, child in pivotChoices:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function renderPivot(view: View)
		clearPivotChoices()
		local platform: { Issue } = view.players[view.you].platform or {}
		local choices: { Issue } = {}
		local dropping = model.pivotStage == "drop"
		if dropping then
			pivotTitle.Text = "Pivot (1 AP, once per match, costs national support). Drop which issue?"
			for k = 1, #platform do
				table.insert(choices, platform[k])
			end
		else
			pivotTitle.Text = `Drop {Model.issueName(model.pivotDrop)}. Add which issue?`
			for k = 1, #Issues.list do
				local issue: Issue = Issues.list[k]
				if not table.find(platform, issue) then
					table.insert(choices, issue)
				end
			end
		end
		for k = 1, #choices do
			local issue: Issue = choices[k]
			Kit.button(Model.issueName(issue), function()
				if model.pivotStage == "drop" then
					model.pivotDrop = issue
					model.pivotStage = "add"
				elseif model.pivotDrop ~= nil then
					local now = model.payload
					local action: Action = { kind = "Pivot", drop = model.pivotDrop, add = issue }
					model.pivotStage = nil
					if now and Model.trial(model, now.view, action) == nil then
						PlanDraft.add(model.draft, action)
					end
				end
				model.render()
			end, {
				variant = "chip",
				Name = if dropping then `PivotDrop{issue}` else `PivotAdd{issue}`,
				LayoutOrder = k,
				Size = pivotSize,
				TextWrapped = true,
				Parent = pivotChoices,
			})
		end
	end

	local function renderMessages(view: View, id: string, canEdit: boolean)
		local record = StateData.byId[id]
		local platform: { Issue } = view.players[view.you].platform or {}
		local message = Model.messageIssue(model, view, id)
		local choices = PlanDraft.messageChoices(config, view, id)
		local offered: { [string]: number } = {}
		for k, choice in choices do
			offered[choice.issue] = k
		end
		local extra = 0
		for k = 1, #Issues.list do
			local issue: Issue = Issues.list[k]
			local button = issueChips[issue]
			local m = Resolve.issueMult(config, platform, record.issues, issue)
			button.Text = `{Model.issueName(issue)} {Model.mult(m)}`
			local at = offered[issue]
			if at then
				button.Parent = chipGrid
				button.LayoutOrder = at
				button.Visible = true
			else
				extra += 1
				button.Parent = moreGrid
				button.LayoutOrder = k
				button.Visible = true
			end
			Kit.setSelected(button, issue == message)
			Kit.setEnabled(button, canEdit)
		end
		moreChip.Visible = extra > 0
		moreChip.Text = if model.moreIssues then "Fewer –" else "More +"
		Kit.setEnabled(moreChip, canEdit)
		moreGrid.Visible = model.moreIssues and extra > 0
	end

	local function renderActions(p: Payload, id: string, canEdit: boolean)
		local view = p.view
		local hintText: string? = nil
		local from = PlanDraft.location(view, model.draft)
		local pivotWhy = pivotProblem(view)
		for _, entry in ACTIONS do
			local button = actionButtons[entry.name]
			local problem: string?
			local extra = 0
			if entry.name == "PivotButton" then
				problem = pivotWhy
			else
				local action = actionFor(view, entry.name, id)
				problem = problemOf(view, action)
				extra = Model.extraCash(model, view, action)
			end
			if problem then
				button.Text = `{entry.label} ({SHORT_REASON[problem] or "no"})`
				if hintText == nil then
					if entry.name == "RegionPoll" and problem == Plan.Reason.DuplicatePoll then
						hintText =
							`Greyed out: you already poll the {Model.regionName(PlanDraft.regionOf(id))} this week.`
					else
						hintText = `Greyed out: {model.ctx.net.reasonText(problem)}`
					end
				end
			else
				local moves = entry.name == "Rally" or entry.name == "Fundraise"
				local flight = moves and not Plan.isAdjacent(from, id)
				if flight then
					button.Text = `{entry.label} ✈ {Model.money(extra)}`
				elseif extra > 1e-9 then
					button.Text = `{entry.label} {Model.money(extra)}`
				else
					button.Text = entry.label
				end
			end
			Kit.setEnabled(button, canEdit and problem == nil)
		end
		if model.pivotStage ~= nil and (not canEdit or pivotWhy ~= nil) then
			model.pivotStage = nil
		end
		local choosing = model.pivotStage ~= nil
		actionGrid.Visible = not choosing
		pivotPanel.Visible = choosing
		if choosing then
			renderPivot(view)
		else
			clearPivotChoices()
		end
		if not canEdit then
			hintText = "Your plan is locked in."
		end
		hint.Text = hintText
			or "Rally and Fundraise move your candidate (1 AP each). Ads, polls and ground game cost money."
		if preview:isExpanded() then
			local message: Issue = Model.messageIssue(model, view, id)
			for _, entry in Explain.previews(config, view, model.draft, id, message) do
				local line = previewLines[entry.name]
				if line then
					line.Text = entry.text
				end
			end
		end
	end

	local function renderList(p: Payload)
		local view = p.view
		list:setTitle(`All states · sorted {string.lower(StateOrder.label(model.sortMode))}`)
		if not list:isExpanded() then
			return
		end
		for mode, button in sortChips do
			Kit.setSelected(button, mode == model.sortMode)
		end
		local me, rival = view.you, Model.opponentOf(view)
		for rank, id in StateOrder.sort(view, model.sortMode) do
			local entry = pickerRows[id]
			local sv = view.states[entry.index]
			entry.button.LayoutOrder = rank
			Kit.setSelected(entry.button, id == model.selected)
			entry.code.TextColor3 = if sv.owner ~= nil
				then Kit.playerColor(view, sv.owner)
				else Kit.colors.text
			entry.margin.Text = StateOrder.marginText(view, sv)
			local margin = StateOrder.margin(view, sv)
			entry.margin.TextColor3 = if margin > 0
				then Kit.playerColor(view, me)
				elseif margin < 0 then Kit.playerColor(view, rival)
				else Kit.colors.muted
			entry.momentum.Text = StateOrder.momentumText(view, sv)
		end
	end

	local card: StateCard = {
		root = root,
		closeList = function(_self: StateCard)
			list:setExpanded(false)
		end,
		render = function(_self: StateCard, p: Payload)
			local view = p.view
			renderList(p)
			local id = model.selected
			local index = if id then SimState.indexOf[id] else nil
			if id == nil or index == nil then
				title.Text = "Tap a state on the map"
				tagRow.Visible = false
				details.Visible = false
				actionsBox.Visible = false
				return
			end
			local planning = Model.planning(p)
			local canEdit = Model.editable(model, p)
			details.Visible = true
			actionsBox.Visible = planning
			local me, rival = view.you, Model.opponentOf(view)
			local s = view.states[index]
			local record: SharedTypes.StateRecord = StateData.byId[id]
			title.Text = `{record.name} · {record.ev} EV`

			local tagTexts: { string } = {}
			if s.battleground then
				table.insert(tagTexts, "Battleground")
			end
			if s.owner then
				local whose = if s.owner == me then "Your" else "Their"
				if s.battleground and not s.isHome then
					-- Nominated: the stronghold bonus is gone (playtest 1).
					table.insert(tagTexts, `Was {string.lower(whose)} stronghold`)
				else
					table.insert(tagTexts, `{whose} {if s.isHome then "home state" else "stronghold"}`)
				end
			end
			if view.players[me].location == id then
				table.insert(tagTexts, "You are here")
			end
			if view.players[rival].location == id then
				table.insert(tagTexts, "Opponent is here")
			end
			for k, tag in tags do
				tag.Text = tagTexts[k] or ""
				tag.Visible = tagTexts[k] ~= nil
			end
			tagRow.Visible = #tagTexts > 0

			local poll = s.poll
			pollValue.Text = if poll
				then `you {poll.support[me] or 0} – {poll.support[rival] or 0} them · {poll.undecided} undecided`
				else "No public poll yet"
			leanValue.Text = Explain.leanText(view, s)
			local mine, theirs = s.momentum[me] or 0, s.momentum[rival] or 0
			local lead = mine - theirs
			local glyph = if math.abs(lead) >= 0.05 then "▲ " else ""
			momentumValue.Text = string.format("%syou %.1f · them %.1f", glyph, mine, theirs)
			momentumValue.TextColor3 = if lead >= 0.05
				then Kit.playerColor(view, me)
				elseif lead <= -0.05 then Kit.playerColor(view, rival)
				else Kit.colors.text
			momentumNote.Text = Explain.momentumNote(config, view, s)
			local backlash = Explain.backlashNote(config, view, s)
			backlashNote.Text = backlash or ""
			backlashNote.Visible = backlash ~= nil
			local profile = PlanDraft.profile(config, view)
			local planned = Model.plannedUnits(model, id)
			groundValue.Text = `{s.gotv} / {profile.gotvMaxUnits}`
				.. (if planned > 0 then ` (+{planned} planned)` else "")
				.. ` · pool size {Model.money(s.capacity)}`

			local internal = nil
			for _, result in view.internalPolls do
				if result.state == id then
					internal = result
				end
			end
			if internal then
				internalValue.Text = string.format(
					"you %.1f – %.1f them · %.1f undecided",
					internal.support[me] or 0,
					internal.support[rival] or 0,
					internal.undecided
				)
			end
			internalCell.Visible = internal ~= nil
			local issueNames: { string } = {}
			for _, issue in record.issues do
				table.insert(issueNames, Model.issueName(issue))
			end
			issuesLine.Text = `Top issues: {table.concat(issueNames, ", ")}`

			if not planning then
				return
			end
			renderMessages(view, id, canEdit)
			renderActions(p, id, canEdit)
		end,
	}
	return card
end

return StateCard
