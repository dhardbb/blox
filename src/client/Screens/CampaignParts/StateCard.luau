--!strict
-- The selected state's card (docs/UI-STYLE.md §4.5): compact, so its actions
-- are on the first screen on a phone. It shows only once the player taps a
-- state; × (or tapping the state again) closes it.
--
--   Ohio · 17 votes                                  [×]
--   <Battleground> <Your stronghold> <You are here>          at most 3 pills
--   Dana 36 ━━━━━━━━━━━░░░░░░━━━━━━━━━ 35 Rex                the public poll
--   [ Rally        ] [ Fundraise    ] [ Ad           ]       big buttons: what
--   [ +3.9 support ] [ +$2.4        ] [ +2.1 support ]       each does, in words
--   Message  (Jobs) (Health) (More +)                        rallies and ads talk about
--   ( More actions + )                ( Details + )
--
-- A phone shows Rally, Fundraise and Ad; a wide screen also Attack ad, Poll and
-- Ground game. "More actions" adds the rest (Region poll, Pivot). Pivot opens
-- its chooser in place of the buttons. "Details" opens the numbers: the polls,
-- momentum and its drift, ground game, top issues, and one line per action with
-- the full math (Shared/UI/Explain), a details area.
--
-- Each action button leads with its icon on a round plate (Kit.iconPlate,
-- UI/Icons; the word stays), so the six read as a set.
-- Motion (docs/DESIGN.md D-053): a newly tapped state's card fades in and its
-- action buttons pop in one after another; an added action pops its button;
-- holding an action button shows what it would do on the map (model.ghost).
--
-- During a reveal the card stays up read-only (title, poll, Details), so a
-- player can inspect a state while the results play.
--
-- The full state list ("All states", sortable) is a separate collapsible panel
-- in the same column, at `listOrder`.
--
--   local card = StateCard.new(parent, model, order, listOrder)
--   card:render(p) · card:closeList() · card.root (Frame "StateCard")
--
-- Element names (tests and agents use them): CardTitle, CloseCard, CardTags,
-- CardLead (LeadYou, LeadThem, LeadBar, LeadNote), Actions, ActionGrid, Rally,
-- Fundraise, Ad, Attack, Poll, Gotv, RegionPoll, PivotButton (each with
-- <name>Label and <name>Effect), MessageRow, MessageChips, Issue<issue>,
-- MessageMore, MoreIssues, MoreActions, DetailsToggle, ActionHint, PivotChooser,
-- PivotDrop<issue>, PivotAdd<issue>, PivotCancel, CardDetails, CardPoll,
-- CardLean, CardMomentum, CardMomentumNote, CardBacklash, CardGround,
-- CardInternal, CardScout, CardIssues, Preview<button name>; StateList,
-- StatesToggle, StatePicker, Sort_<mode>, Row_<id>.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedFolder = ReplicatedStorage.Shared
local Explain = require(SharedFolder.UI.Explain)
local IssueMap = require(SharedFolder.Sim.IssueMap)
local Issues = require(SharedFolder.Sim.Issues)
local Plan = require(SharedFolder.Sim.Plan)
local PlanDraft = require(SharedFolder.UI.PlanDraft)
local SimState = require(SharedFolder.Sim.State)
local StateData = require(SharedFolder.Sim.StateData)
local StateOrder = require(SharedFolder.UI.StateOrder)
local SharedTypes = require(SharedFolder.Types)
local ViewModule = require(SharedFolder.Sim.View)
local Words = require(SharedFolder.UI.Words.Campaign)

local Collapsible = require(script.Parent.Parent.Parent.UI.Collapsible)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Parent.Common.Layout)
local Model = require(script.Parent.Model)
local Motion = require(script.Parent.Parent.Parent.UI.Motion)

type View = ViewModule.View
type Issue = SharedTypes.Issue
type Action = Plan.Action
type Payload = Model.Payload

local StateCard = {}

local GAP = Kit.space.sm
local MAX_PILLS = 3
local COLUMNS = 3 -- action buttons, message chips and pivot choices per row
local ACTION_H = 64 -- px, one action button: its name over what it does
local MAIN_PHONE = 3 -- action buttons a phone shows before "More actions"
local MAIN_WIDE = 6 -- ... a wide screen
local LEAD_NAMES_H = 18 -- px, the names over the poll bar
local LEAD_BAR_H = 6 -- px, the poll bar (a mini Kit.raceBar; its tick overhangs 4 px each way)
local MESSAGE_LABEL_W = 76 -- px, "Message" before the chips
local ICON_PX = 20 -- px, an action button's icon plate (Kit.iconPlate)
local CARD_RISE = 8 -- px, the card sliding in on a new state
local ADD_POP = 1.06 -- an action button's size as it adds (it settles to 1)

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

function StateCard.new(parent: Instance, model: Model.Model, order: number, listOrder: number?): StateCard
	local config = model.config

	local root = Kit.card({ Name = "StateCard", LayoutOrder = order, Visible = false, Parent = parent })

	-- ------------------------------------------------------------ title, pills, poll

	local titleRow = Kit.box({
		Name = "CardTitleRow",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = root,
	})
	local title = Kit.heading("", {
		Name = "CardTitle",
		Size = UDim2.new(1, -(Kit.MIN_TOUCH + Kit.space.sm), 1, 0),
		TextScaled = true,
		Parent = titleRow,
	})
	Kit.iconButton(Kit.glyph.close, function()
		local id = model.selected
		if id then
			model.selectState(id) -- tapping the selected state again closes the card
		end
	end, {
		Name = "CloseCard",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Parent = titleRow,
	})

	local tagRow =
		Kit.stack({ Name = "CardTags", LayoutOrder = 2, Parent = root }, "Horizontal", Kit.space.xs)
	local pills: { TextLabel } = {}
	for k = 1, MAX_PILLS do
		pills[k] =
			Kit.pill("", "text", { Name = `Pill{k}`, LayoutOrder = k, Visible = false, Parent = tagRow })
	end

	-- Who leads the public poll: names and numbers over one bar.
	local leadBox = Kit.box({
		Name = "CardLead",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, LEAD_NAMES_H + Kit.space.xs + LEAD_BAR_H + 8),
		Parent = root,
	})
	Kit.dataColor(leadBox)
	local function leadName(name: string, align: Enum.TextXAlignment): TextLabel
		return Kit.text("", {
			Name = name,
			Size = UDim2.new(0.5, -Kit.space.xs, 0, LEAD_NAMES_H),
			TextSize = Kit.size.caption,
			TextScaled = true,
			Font = Kit.font.bold,
			TextXAlignment = align,
			Parent = leadBox,
		})
	end
	local leadYou = leadName("LeadYou", Enum.TextXAlignment.Left)
	local leadThem = leadName("LeadThem", Enum.TextXAlignment.Right)
	leadThem.AnchorPoint = Vector2.new(1, 0)
	leadThem.Position = UDim2.fromScale(1, 0)
	-- The public poll as a mini race bar: each side's share from its end, the
	-- tick at the halfway mark.
	local leadRace = Kit.raceBar(leadBox, { h = LEAD_BAR_H, mark = 0.5, name = "LeadBar" })
	leadRace.root.Position = UDim2.fromOffset(0, LEAD_NAMES_H + Kit.space.xs)
	leadRace.left.Name = "YouShare"
	leadRace.right.Name = "ThemShare"
	local leadBar = leadRace.root
	local leadNote = Kit.text("", {
		Name = "LeadNote",
		Size = UDim2.fromScale(1, 1),
		TextSize = Kit.size.caption,
		TextScaled = true,
		TextColor3 = Kit.colors.muted,
		Visible = false,
		Parent = leadBox,
	})

	-- ------------------------------------------------------------ actions

	local actionsBox = Kit.stack({ Name = "Actions", LayoutOrder = 4, Parent = root }, "Vertical", GAP)
	local actionGrid, actionSize = grid(actionsBox, "ActionGrid", 1, ACTION_H)
	local addAction: (name: string) -> ()
	local pivotOpen: () -> ()
	type ActionButton = { button: TextButton, label: TextLabel, effect: TextLabel, icon: GuiObject? }
	local actionButtons: { [string]: ActionButton } = {}
	for k, entry in Words.ACTIONS do
		local button: TextButton
		button = Kit.button("", function()
			if button.Active == false then
				return
			end
			if entry.name == "PivotButton" then
				pivotOpen()
			else
				addAction(entry.name)
			end
		end, {
			variant = "secondary",
			Name = entry.name,
			LayoutOrder = k,
			Size = actionSize,
			TextScaled = false,
		})
		local list = Kit.list("Vertical", 2)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Left
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Parent = button
		-- The name line: the action's icon, then its word.
		local head = Kit.box({
			Name = `{entry.name}Head`,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, Kit.size.body + 4),
			Parent = button,
		})
		-- (Pivot has no icon: its word lines up with the others.)
		local iconName = Kit.actionIcon(entry.kind)
		local icon: GuiObject? = nil
		if iconName then
			local plate = Kit.iconPlate(iconName, ICON_PX, Kit.colors.text)
			plate.AnchorPoint = Vector2.new(0, 0.5)
			plate.Position = UDim2.fromScale(0, 0.5)
			plate.Parent = head
			-- The glyph or image inside the plate (tinted when the action is off).
			for _, child in plate:GetChildren() do
				if child:IsA("GuiObject") then
					icon = child
				end
			end
		end
		local label = Kit.text(entry.label, {
			Name = `{entry.name}Label`,
			Position = UDim2.fromOffset(ICON_PX + Kit.space.xs, 0),
			Size = UDim2.new(1, -(ICON_PX + Kit.space.xs), 1, 0),
			Font = Kit.font.bold,
			TextScaled = true,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = head,
		})
		local effect = Kit.caption("", {
			Name = `{entry.name}Effect`,
			LayoutOrder = 2,
			TextColor3 = Kit.colors.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = button,
		})
		-- Held (not yet released): the map shows what this action would do.
		if entry.name ~= "PivotButton" then
			button.InputBegan:Connect(function(input: InputObject)
				local kind = (input :: any).UserInputType
				local pressed = kind ~= nil and (kind.Name == "MouseButton1" or kind.Name == "Touch")
				local ghost, id = model.ghost, model.selected
				if pressed and ghost and id and button.Active ~= false then
					ghost(id, Words.gain(effect.Text))
				end
			end)
			button.InputEnded:Connect(function()
				local ghost, id = model.ghost, model.selected
				if ghost and id then
					ghost(id, nil)
				end
			end)
		end
		Kit.outer(button).Parent = actionGrid
		actionButtons[entry.name] = { button = button, label = label, effect = effect, icon = icon }
	end

	-- The pivot chooser takes the buttons' place: drop an issue, then add one.
	local pivotPanel =
		Kit.stack({ Name = "PivotChooser", LayoutOrder = 2, Parent = actionsBox }, "Vertical", GAP)
	local pivotTitle = Kit.text("", {
		Name = "PivotTitle",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = pivotPanel,
	})
	local pivotChoices, pivotSize = grid(pivotPanel, "PivotChoices", 2, Kit.MIN_TOUCH)
	Kit.button("Cancel", function()
		model.pivotStage = nil
		model.pivotDrop = nil
		model.render()
	end, { variant = "secondary", Name = "PivotCancel", LayoutOrder = 3, Parent = pivotPanel })

	-- The message for rallies and ads: the best ones as chips, the rest behind More.
	local messageRow = Kit.box({
		Name = "MessageRow",
		LayoutOrder = 3,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = actionsBox,
	})
	Kit.text("Message", {
		Name = "MessageLabel",
		Size = UDim2.fromOffset(MESSAGE_LABEL_W, Kit.MIN_TOUCH),
		TextSize = Kit.size.caption,
		TextColor3 = Kit.colors.muted,
		Parent = messageRow,
	})
	local chipsBox = Kit.stack({
		Name = "MessageBox",
		Position = UDim2.fromOffset(MESSAGE_LABEL_W, 0),
		Size = UDim2.new(1, -MESSAGE_LABEL_W, 0, 0),
		Parent = messageRow,
	}, "Vertical", GAP)
	local chipGrid, chipSize = grid(chipsBox, "MessageChips", 1, Kit.MIN_TOUCH)
	local moreGrid = grid(chipsBox, "MoreIssues", 2, Kit.MIN_TOUCH)
	local issueChips: { [string]: TextButton } = {}
	for k = 1, #Issues.list do
		local issue: Issue = Issues.list[k]
		local button: TextButton
		button = Kit.chip(Model.issueName(issue), function()
			if button.Active == false then
				return
			end
			model.chosenIssue = issue
			model.render()
		end, {
			Name = `Issue{issue}`,
			LayoutOrder = k,
			Size = chipSize,
			TextWrapped = true,
			Parent = chipGrid,
		})
		Kit.issueLead(button, issue) -- the issue's symbol before its name (D-076)
		issueChips[issue] = button
	end
	local moreChip: TextButton
	moreChip = Kit.chip("More +", function()
		if moreChip.Active == false then
			return
		end
		model.moreIssues = not model.moreIssues
		model.render()
	end, { Name = "MessageMore", LayoutOrder = 100, Size = chipSize, Parent = chipGrid })

	local hint =
		Kit.caption("", { Name = "ActionHint", LayoutOrder = 4, Visible = false, Parent = actionsBox })

	-- ------------------------------------------------------------ toggles

	local toggles = Kit.box({
		Name = "CardToggles",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = root,
	})
	local moreActions = Kit.button("More actions +", function()
		model.moreActions = not model.moreActions
		model.render()
	end, {
		variant = "ghost",
		Name = "MoreActions",
		Size = UDim2.new(0.5, -Kit.space.xs, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = toggles,
	})
	local detailsToggle = Kit.button("Details +", function()
		model.details = not model.details
		model.render()
	end, {
		variant = "ghost",
		Name = "DetailsToggle",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.5, -Kit.space.xs, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = toggles,
	})

	-- ------------------------------------------------------------ details

	local details = Kit.stack(
		{ Name = "CardDetails", LayoutOrder = 6, Visible = false, Parent = root },
		"Vertical",
		Kit.space.xs
	)
	Kit.details(details)
	Kit.divider({ LayoutOrder = 0, Parent = details })
	local function statRow(k: number): Frame
		local frame = Kit.stack({ Name = `StatRow{k}`, LayoutOrder = k, Parent = details }, "Horizontal", GAP)
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
	-- Their ground game, as your polls saw it (D-049), or the hint that a poll shows it.
	local scoutNote = Kit.caption("", { Name = "CardScout", LayoutOrder = 6, Parent = details })
	-- The state's top issues (D-076): "Top issues:", then each one's symbol and name.
	local issuesRow = Kit.box({
		Name = "CardIssueRow",
		LayoutOrder = 7,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = details,
	})
	local issuesFlow = Kit.list("Horizontal", Kit.space.sm)
	issuesFlow.Wraps = true
	issuesFlow.VerticalAlignment = Enum.VerticalAlignment.Center
	issuesFlow.Parent = issuesRow
	Kit.caption("Top issues:", {
		Name = "CardIssues",
		LayoutOrder = 0,
		Size = UDim2.fromOffset(0, Kit.size.caption + 4),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		Parent = issuesRow,
	})
	-- What each button would do here, worked out by Shared/UI/Explain: one line
	-- per button, the full math.
	local preview =
		Kit.stack({ Name = "ActionPreview", LayoutOrder = 8, Parent = details }, "Vertical", Kit.space.xs)
	Kit.text("What each action does here", {
		Name = "PreviewTitle",
		LayoutOrder = 0,
		Font = Kit.font.bold,
		Parent = preview,
	})
	local previewLines: { [string]: TextLabel } = {}
	for k, entry in Words.ACTIONS do
		previewLines[entry.name] = Kit.caption("", {
			Name = `Preview{entry.name}`,
			LayoutOrder = k,
			TextColor3 = Kit.colors.text,
			Parent = preview,
		})
	end

	-- ------------------------------------------------------------ state list

	local list = Collapsible.new(parent, {
		title = "All states",
		name = "StateList",
		order = listOrder or order + 10,
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
		local button = Kit.chip(StateOrder.label(mode), function()
			model.sortMode = mode
			model.render()
		end, { Name = `Sort_{mode}`, LayoutOrder = k, Size = sortSize, Parent = sortGrid })
		sortChips[mode] = button
	end
	local rowsBox =
		Kit.stack({ Name = "StateRows", LayoutOrder = 1, Parent = list.body }, "Vertical", Kit.space.xs)

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
		local button = Kit.chip("", function()
			if model.selected ~= id then
				model.selectState(id)
			elseif model.portrait then
				list:setExpanded(false)
				model.render()
			end
		end, {
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
		cell("EV", 0.46, 0.14, { TextXAlignment = Enum.TextXAlignment.Center }).Text = `{record.ev} votes`
		local margin = cell("Margin", 0.6, 0.24, {
			Font = Kit.font.medium,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local momentum = cell("Momentum", 0.84, 0.16, {
			TextSize = Kit.size.caption,
			TextColor3 = Kit.colors.muted,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		code.Text = id
		Kit.dataColor(button)
		pickerRows[id] = { index = index, button = button, code = code, margin = margin, momentum = momentum }
	end

	-- ------------------------------------------------------------ plan logic

	-- The action a button adds for state `id`.
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
		local ghost = model.ghost
		if ghost then
			ghost(id, nil)
		end
		Motion.pop(actionButtons[name].button, ADD_POP)
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
			pivotTitle.Text = "Pivot: drop which issue?"
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
			local chip = Kit.chip(Model.issueName(issue), function()
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
				Name = if dropping then `PivotDrop{issue}` else `PivotAdd{issue}`,
				LayoutOrder = k,
				Size = pivotSize,
				TextWrapped = true,
				Parent = pivotChoices,
			})
			Kit.issueLead(chip, issue)
		end
	end

	local function renderMessages(view: View, id: string, canEdit: boolean)
		local message = Model.messageIssue(model, view, id)
		local choices = PlanDraft.messageChoices(config, view, id)
		local offered: { [string]: number } = {}
		for k, choice in choices do
			if k < COLUMNS then
				offered[choice.issue] = k
			end
		end
		-- A picked message from "More" joins the row, so the choice stays in sight.
		if offered[message] == nil and not model.moreIssues then
			offered[message] = COLUMNS - 1
			for issue, k in offered do
				if k == COLUMNS - 1 and issue ~= message then
					offered[issue] = nil
				end
			end
		end
		local extra = 0
		for k = 1, #Issues.list do
			local issue: Issue = Issues.list[k]
			local button = issueChips[issue]
			local at = offered[issue]
			if at then
				button.Parent = chipGrid
				button.LayoutOrder = at
			else
				extra += 1
				button.Parent = moreGrid
				button.LayoutOrder = k
			end
			button.Visible = true
			Kit.setSelected(button, issue == message)
			Kit.setEnabled(button, canEdit)
		end
		moreChip.Visible = extra > 0
		moreChip.Text = if model.moreIssues then `Fewer {Kit.glyph.minus}` else "More +"
		Kit.setEnabled(moreChip, canEdit)
		moreGrid.Visible = model.moreIssues and extra > 0
		Kit.refitIssueLeads(chipsBox)
	end

	local function renderActions(p: Payload, id: string, canEdit: boolean)
		local view = p.view
		local hintText: string? = nil
		local from = PlanDraft.location(view, model.draft)
		local pivotWhy = pivotProblem(view)
		local message: Issue = Model.messageIssue(model, view, id)
		local opponent = Model.firstName(config, view, Model.opponentOf(view))
		local main = if model.portrait then MAIN_PHONE else MAIN_WIDE
		for k, entry in Words.ACTIONS do
			local parts = actionButtons[entry.name]
			local problem: string?
			local extra = 0
			if entry.name == "PivotButton" then
				problem = pivotWhy
			else
				local action = actionFor(view, entry.name, id)
				problem = problemOf(view, action)
				extra = Model.extraCash(model, view, action)
			end
			local shown = k <= main or model.moreActions
			parts.button.Visible = shown
			local enabled = canEdit and problem == nil
			if problem then
				parts.effect.Text = Words.reason(problem)
				if hintText == nil and shown then
					if entry.name == "RegionPoll" and problem == Plan.Reason.DuplicatePoll then
						hintText =
							`Greyed out: you already poll the {Model.regionName(PlanDraft.regionOf(id))} this week.`
					else
						hintText = `Greyed out: {model.ctx.net.reasonText(problem)}`
					end
				end
			else
				local issue: Issue? = if entry.name == "Rally" or entry.name == "Ad" then message else nil
				local moves = entry.name == "Rally" or entry.name == "Fundraise"
				local flight = moves and not Plan.isAdjacent(from, id)
				local effect = Words.effect(config, view, model.draft, id, entry.name, issue, opponent)
				local cost = Words.cost(extra, flight, entry.name == "Poll")
				parts.effect.Text = if cost then `{effect}\n{cost}` else effect
			end
			Kit.setEnabled(parts.button, enabled)
			parts.label.TextColor3 = if enabled then Kit.colors.text else Kit.colors.disabledText
			local icon: any = parts.icon
			local tint = if enabled then Kit.colors.text else Kit.colors.disabledText
			if icon and icon:IsA("ImageLabel") then
				icon.ImageColor3 = tint
			elseif icon then
				icon.TextColor3 = tint
			end
			parts.effect.TextColor3 = if enabled then Kit.colors.text else Kit.colors.disabledText
		end
		local hidden = #Words.ACTIONS - main
		moreActions.Visible = hidden > 0
		moreActions.Text = if model.moreActions then `Fewer actions {Kit.glyph.minus}` else "More actions +"
		if model.pivotStage ~= nil and (not canEdit or pivotWhy ~= nil) then
			model.pivotStage = nil
		end
		local choosing = model.pivotStage ~= nil
		actionGrid.Visible = not choosing
		pivotPanel.Visible = choosing
		messageRow.Visible = not choosing
		if choosing then
			renderPivot(view)
		else
			clearPivotChoices()
		end
		if not canEdit then
			hintText = "Your plan is locked in."
		end
		hint.Text = hintText or ""
		hint.Visible = hintText ~= nil
		do
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
		list:setTitle(`All states · {string.lower(StateOrder.label(model.sortMode))}`)
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
				then Kit.playerText(view, sv.owner)
				else Kit.colors.text
			entry.margin.Text = StateOrder.marginText(view, sv)
			local margin = StateOrder.margin(view, sv)
			entry.margin.TextColor3 = if margin > 0
				then Kit.playerText(view, me)
				elseif margin < 0 then Kit.playerText(view, rival)
				else Kit.colors.muted
			entry.momentum.Text = StateOrder.momentumText(view, sv)
		end
	end

	-- The pills: at most three, the most useful first.
	local function renderPills(view: View, s: ViewModule.StateView, id: string)
		local me, rival = view.you, Model.opponentOf(view)
		local theirName = Model.firstName(config, view, rival)
		local items: { { text: string, tone: Kit.Tone } } = {}
		if s.battleground then
			table.insert(items, { text = "Battleground", tone = "white" })
		end
		if s.owner then
			local whose = if s.owner == me then "Your" else `{theirName}'s`
			if s.battleground and not s.isHome then
				-- Nominated: the stronghold bonus is gone (playtest 1).
				table.insert(
					items,
					{ text = `Was {if s.owner == me then "your" else whose} stronghold`, tone = "muted" }
				)
			else
				table.insert(
					items,
					{ text = `{whose} {if s.isHome then "home" else "stronghold"}`, tone = "text" }
				)
			end
		end
		if view.players[me].location == id then
			table.insert(items, { text = "You are here", tone = "good" })
		elseif view.players[rival].location == id then
			table.insert(items, { text = `{theirName} is here`, tone = "muted" })
		end
		local platform: { Issue } = view.players[me].platform or {}
		for _, issue in IssueMap.of(view.issueMap, id) do
			if table.find(platform, issue) then
				table.insert(items, { text = "Your issue", tone = "good" })
				break
			end
		end
		for k, pill in pills do
			local item = items[k]
			pill.Visible = item ~= nil
			if item then
				pill.Text = item.text
				Kit.paintPill(pill, item.tone)
			end
		end
		tagRow.Visible = #items > 0
	end

	-- The lead bar: the public poll, or the lean before the first poll.
	local function renderLead(view: View, s: ViewModule.StateView)
		local me, rival = view.you, Model.opponentOf(view)
		local poll = s.poll
		local myColor, theirColor = Kit.playerColor(view, me), Kit.playerColor(view, rival)
		leadYou.Visible = poll ~= nil
		leadThem.Visible = poll ~= nil
		leadBar.Visible = poll ~= nil
		leadNote.Visible = poll == nil
		if poll == nil then
			local lean = math.floor(s.lean + 0.5)
			leadNote.Text = if s.leanTo and lean > 0
				then `No poll yet · leans {if s.leanTo == me
					then "your way"
					else Model.firstName(config, view, rival)} +{lean}`
				else "No poll yet · no lean"
			return
		end
		local mine, theirs = poll.support[me] or 0, poll.support[rival] or 0
		leadYou.Text = `{Model.firstName(config, view, me)} {mine}`
		leadThem.Text = `{theirs} {Model.firstName(config, view, rival)}`
		leadYou.TextColor3 = Kit.textColor(myColor)
		leadThem.TextColor3 = Kit.textColor(theirColor)
		leadRace:setColors(myColor, theirColor)
		leadRace:set(mine / 100, theirs / 100)
	end

	local function renderDetails(view: View, s: ViewModule.StateView, id: string)
		local me, rival = view.you, Model.opponentOf(view)
		local theirName = Model.firstName(config, view, rival)
		local poll = s.poll
		pollValue.Text = if poll
			then `you {poll.support[me] or 0} – {poll.support[rival] or 0} {theirName} · {poll.undecided} undecided`
			else "No public poll yet"
		leanValue.Text = Explain.leanText(view, s)
		local mine, theirs = s.momentum[me] or 0, s.momentum[rival] or 0
		local lead = mine - theirs
		local glyph = if math.abs(lead) >= 0.05 then `{Kit.glyph.up} ` else ""
		momentumValue.Text = string.format("%syou %.1f · %s %.1f", glyph, mine, theirName, theirs)
		momentumValue.TextColor3 = if lead >= 0.05
			then Kit.playerText(view, me)
			elseif lead <= -0.05 then Kit.playerText(view, rival)
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
				"you %.1f – %.1f %s · %.1f undecided",
				internal.support[me] or 0,
				internal.support[rival] or 0,
				theirName,
				internal.undecided
			)
		end
		internalCell.Visible = internal ~= nil
		scoutNote.Text = Explain.scoutNote(config, view, id)
		local scout = Explain.scoutOf(view, id)
		scoutNote.TextColor3 = if scout and (scout.gotv[rival] or 0) > 0
			then Kit.colors.danger
			else Kit.colors.muted
		for _, child in issuesRow:GetChildren() do
			if child:IsA("GuiObject") and child.Name ~= "CardIssues" then
				child:Destroy()
			end
		end
		for k, issue in IssueMap.of(view.issueMap, id) do
			Kit.issueTag(issue, { LayoutOrder = k, Parent = issuesRow })
		end
	end

	local shownId: string? = nil -- the state the card showed at the last render

	local card: StateCard = {
		root = root,
		closeList = function(_self: StateCard)
			list:setExpanded(false)
		end,
		render = function(_self: StateCard, p: Payload)
			local view = p.view
			renderList(p)
			list.root.Visible = Model.planning(p) or p.reveal == "Resolve"
			local id = model.selected
			local index = if id then SimState.indexOf[id] else nil
			if id == nil or index == nil then
				root.Visible = false
				shownId = nil
				return
			end
			root.Visible = true
			local planning = Model.planning(p)
			local arriving = id ~= shownId
			shownId = id
			local canEdit = Model.editable(model, p)
			local s = view.states[index]
			local record: SharedTypes.StateRecord = StateData.byId[id]
			title.Text = `{record.name} · {record.ev} votes`
			renderPills(view, s, id)
			renderLead(view, s)
			actionsBox.Visible = planning
			moreActions.Visible = planning
			detailsToggle.Text = if model.details then `Details {Kit.glyph.minus}` else "Details +"
			details.Visible = model.details
			preview.Visible = planning
			-- Filled in even while closed, so opening Details shows them at once.
			renderDetails(view, s, id)
			if planning then
				renderMessages(view, id, canEdit)
				renderActions(p, id, canEdit)
			end
			if arriving then
				-- A new state: the card fades in, its action buttons pop in one by one.
				Motion.enter(root, CARD_RISE)
				local shown: { TextButton } = {}
				if planning then
					for _, entry in Words.ACTIONS do
						local button = actionButtons[entry.name].button
						if button.Visible then
							table.insert(shown, button)
						end
					end
				end
				Motion.stagger(shown, function(button: TextButton, _index: number, delay: number)
					Motion.pop(button, Motion.POP_FROM, delay)
				end)
			end
		end,
	}
	return card
end

return StateCard
