--!strict
-- The campaign screen, where most of a match is played. The map fills the main
-- area (left in 16:9, top on phones); beside it (below on phones) sit the selected
-- state's card with the action buttons, the week's plan tray, debate prep in the
-- week before a debate, and the week card. The same screen plays the resolve
-- reveal (the week's events, then the new polls) and the debate reveal.
--
-- Reads only ctx.store (the player's own View) and sends only through ctx.net.
-- The plan is previewed with Shared/UI/PlanDraft, which mirrors the server's
-- checks; the server still validates whatever is sent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Candidates = require(Shared.Sim.Candidates)
local Colors = require(Shared.UI.Colors)
local ConfigModule = require(Shared.Sim.Config)
local Events = require(Shared.Sim.Events)
local Issues = require(Shared.Sim.Issues)
local MapLayout = require(Shared.UI.MapLayout)
local Plan = require(Shared.Sim.Plan)
local PlanDraft = require(Shared.UI.PlanDraft)
local Resolve = require(Shared.Sim.Resolve)
local Session = require(Shared.Net.Session)
local SimState = require(Shared.Sim.State)
local StateOrder = require(Shared.UI.StateOrder)
local StateData = require(Shared.Sim.StateData)
local SharedTypes = require(Shared.Types)
local ViewModule = require(Shared.Sim.View)

local AutoLock = require(script.Parent.Common.AutoLock)
local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.Parent.Map.MapInterface)
local Messages = require(script.Parent.Common.Messages)
local NodeMap = require(script.Parent.Parent.Map.NodeMap)
local Types = require(script.Parent.Types)

type Config = ConfigModule.Config
type View = ViewModule.View
type Payload = Session.StatePayload
type Issue = SharedTypes.Issue
type Event = SimState.Event
type Action = Plan.Action

local Screen = {}

-- ---------------------------------------------------------------- layout numbers

local GAP = 8 -- px between the big blocks
local ROW_H = 26 -- px, one top-bar row
local NOTICE_H = 24 -- px, the disconnected notice
local CAPTION_H = 28 -- px, the line above the map
local BUTTON_H = 44 -- px, every button (Kit.MIN_TOUCH)
local LOCK_H = 52 -- px, the Lock in button
local MAP_SHARE = 0.64 -- share of the width the map takes in 16:9
local PORTRAIT_MAP_MAX = 0.42 -- most of the body height the map may take on phones

-- Reveal pacing.
local REVEAL_TAIL = 2 -- seconds kept at the end of the resolve reveal for the new polls
local REVEAL_BEAT = 0.25 -- fastest pace: one tick of the router
local REVEAL_SLOW = 0.8 -- slowest pace, when there are few events
local REVEAL_LINES = 8 -- event lines listed in the side panel
local DEBATE_BEAT = 2 -- seconds per debate topic
local TOAST_SECONDS = 4 -- how long a new message stays above the map
local FEED_MESSAGES = 3 -- latest messages listed in the week card
local SWINGS = 3 -- biggest poll swings named after the resolve reveal

-- Short reasons shown on a greyed-out action button.
local SHORT_REASON: { [string]: string } = {
	NotEnoughAP = "no AP",
	NotEnoughMoney = "no $",
	GotvCap = "max",
	DuplicatePoll = "polled",
	PivotUsed = "used",
	TooManyActions = "full",
}

-- ---------------------------------------------------------------- text helpers

local function opponentOf(view: View): number
	return if view.you == 1 then 2 else 1
end

local function candidateName(config: Config, view: View, p: number): string
	local player = view.players[p]
	if player == nil or player.candidate == nil or not Candidates.exists(player.candidate) then
		return `Player {p}`
	end
	return Candidates.profile(config, player.candidate).name
end

local function stateName(id: string?): string
	if id == nil then
		return "?"
	end
	local record = StateData.byId[id]
	return if record then record.name else id
end

local function issueName(issue: string?): string
	if issue == nil then
		return "?"
	end
	return Issues.displayName[issue :: Issue] or issue
end

local function money(amount: number): string
	return string.format("$%.1f", amount)
end

local function plural(n: number, word: string): string
	return `{n} {word}{if n == 1 then "" else "s"}`
end

local function playerColor(view: View, p: number): Color3
	local player = view.players[p]
	return Kit.color(Colors.of(if player then player.color else nil))
end

-- One line for a resolve event, or nil for events the reveal does not show.
local function eventCaption(config: Config, view: View, event: Event): string?
	local who = "Someone"
	if event.player == view.you then
		who = "You"
	elseif event.player ~= nil then
		who = candidateName(config, view, event.player)
	end
	local kind = event.kind
	local amount = event.amount or 0
	if kind == "Rally" then
		return `{who} rallied in {stateName(event.state)} on {issueName(event.issue)}`
	elseif kind == "Fundraise" then
		return `{who} held a fundraiser in {stateName(event.state)}`
	elseif kind == "Media" then
		return `{who} ran ads in {stateName(event.state)} on {issueName(event.issue)}`
	elseif kind == "Attack" then
		return `{who} ran an attack ad in {stateName(event.state)} on {issueName(event.issue)}`
	elseif kind == "Backlash" then
		return `Backlash in {stateName(event.state)}: too many attacks cost {who} support`
	elseif kind == "Pivot" then
		return `{who} pivoted the platform to {issueName(event.issue)}`
	elseif kind == "Flights" then
		return `{who} took {plural(amount, "flight")}`
	elseif kind == "Raised" then
		return `You raised {money(amount)} from fundraisers`
	elseif kind == "InternalPolls" then
		return `Your {plural(amount, "internal poll")} came back`
	elseif kind == "Polls" then
		return "New public polls are in"
	elseif kind == "Choice" then
		-- The event's Choice answers, revealed with the week (D-027).
		local name = "Event"
		for _, result in view.eventLog do
			local definition = Events.byId[result.id]
			if result.week == view.week - 1 and definition then
				name = definition.name
			end
		end
		return `{name}: {who} {PlanDraft.choiceVerb(event.issue or "Ignore")} ({PlanDraft.points(amount)} national points)`
	end
	return nil
end

-- What the opponent did in public last week (their week card).
local function opponentCard(config: Config, view: View): string
	local them = opponentOf(view)
	local name = candidateName(config, view, them)
	local card = view.players[them].card
	if card == nil then
		return `{name} has no public moves yet.`
	end
	local parts: { string } = {}
	local rallies: { string } = {}
	for _, rally in card.rallies do
		table.insert(rallies, `{rally.state} ({issueName(rally.issue)})`)
	end
	if #rallies > 0 then
		table.insert(parts, "rallies in " .. table.concat(rallies, ", "))
	end
	if #card.fundraisers > 0 then
		table.insert(parts, "fundraisers in " .. table.concat(card.fundraisers, ", "))
	end
	local ads: { string } = {}
	local attacks: { string } = {}
	for _, media in card.media do
		table.insert(if media.attack then attacks else ads, `{media.state} ({issueName(media.issue)})`)
	end
	if #ads > 0 then
		table.insert(parts, "ads in " .. table.concat(ads, ", "))
	end
	if #attacks > 0 then
		table.insert(parts, "attack ads in " .. table.concat(attacks, ", "))
	end
	if card.pivot then
		table.insert(parts, `pivoted from {issueName(card.pivot.drop)} to {issueName(card.pivot.add)}`)
	end
	if card.flights > 0 then
		table.insert(parts, plural(card.flights, "flight"))
	end
	if #parts == 0 then
		return `{name} made no public moves last week.`
	end
	return `{name} last week: {table.concat(parts, "; ")}.`
end

-- One plan action as a tray line.
local function actionText(config: Config, action: Action, flight: boolean): string
	local kind = action.kind
	local where = stateName(action.state)
	local text = kind :: string
	if kind == "Rally" then
		text = `Rally · {where} · {issueName(action.issue)}`
	elseif kind == "Fundraise" then
		text = `Fundraiser · {where}`
	elseif kind == "Media" then
		text = `Ad · {where} · {issueName(action.issue)}`
	elseif kind == "Attack" then
		text = `Attack ad · {where} · {issueName(action.issue)}`
	elseif kind == "Poll" then
		text = `Internal poll · {where}`
	elseif kind == "RegionPoll" then
		text = `Region poll · {if action.region then Issues.regionName[action.region] else "?"}`
	elseif kind == "Gotv" then
		text = `Ground game +{action.units or 1} · {where}`
	elseif kind == "Pivot" then
		text = `Pivot: drop {issueName(action.drop)}, add {issueName(action.add)}`
	end
	if flight then
		text ..= ` · flight {money(config.FLIGHT_COST)}`
	end
	return text
end

-- This week's event, unless the screen is replaying last week (the Resolve
-- reveal carries the next week's view, and its event is not for show yet).
local function shownEvent(p: Payload): ViewModule.EventView?
	if p.reveal == "Resolve" then
		return nil
	end
	return p.view.event
end

-- Is debate prep due in this plan (the week before a debate)?
local function prepWanted(view: View): boolean
	local debate = view.nextDebate
	return view.phase == "Plan" and debate ~= nil and debate.week == view.week + 1
end

-- ---------------------------------------------------------------- UI helpers

-- A wrapped label that grows to fit its text (sentences).
local function sentence(parent: Instance, order: number, name: string, props: { [string]: any }?): TextLabel
	local base: { [string]: any } = {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Kit.size.body,
		Parent = parent,
	}
	if props then
		for key, value in props do
			base[key] = value
		end
	end
	return Kit.text("", base)
end

-- A one-line label that shrinks its text to fit (short labels).
local function scaled(parent: Instance?, order: number, name: string, props: { [string]: any }?): TextLabel
	local base: { [string]: any } = {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW_H),
		TextScaled = true,
		TextWrapped = false,
		TextSize = Kit.size.large,
		Font = Kit.font.medium,
		Parent = parent,
	}
	if props then
		for key, value in props do
			base[key] = value
		end
	end
	return Kit.text("", base)
end

-- A panel that grows with its contents, children stacked top to bottom.
local function panel(parent: Instance, order: number, name: string): Frame
	local frame = Kit.panel({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Kit.list("Vertical", 6).Parent = frame
	return frame
end

-- A transparent box that grows with its stacked contents.
local function stack(parent: Instance, order: number, name: string, gap: number?): Frame
	local frame = Kit.box({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Kit.list("Vertical", gap or 6).Parent = frame
	return frame
end

-- A fixed-height row, children side by side.
local function row(parent: Instance, order: number, name: string, height: number?): Frame
	local frame = Kit.box({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, height or BUTTON_H),
		Parent = parent,
	})
	Kit.list("Horizontal", 6).Parent = frame
	return frame
end

-- Width of one of `n` equal cells in a row with 6 px gaps.
local function cell(n: number): UDim2
	return UDim2.new(1 / n, -math.ceil(6 * (n - 1) / n), 1, 0)
end

local function setVisible(inst: GuiObject, visible: boolean)
	inst.Visible = visible
end

-- Removes the GUI children of `frame`, keeping its layout objects.
local function clearChildren(frame: Instance)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- ---------------------------------------------------------------- the screen

function Screen.mount(parent: Frame, ctx: Types.Ctx): Types.Screen
	local config = ctx.config
	local alive = true

	-- Current data.
	local payload: Payload? = nil
	local messages: { Types.Message } = {}

	-- The plan being built (kept for the whole Input stage, keyed by step).
	local draft = PlanDraft.new()
	local draftStep: number? = nil
	local selected: string? = nil
	local chosenIssue: Issue? = nil -- the rally/ad message picked by hand, for `selected`
	local pickerOpen = false
	local pivotStage: string? = nil -- nil, "drop" or "add"
	local pivotDrop: Issue? = nil
	local lockStep: number? = nil -- step we pressed Lock in for (before the server confirms)
	local lockMessageId = 0 -- id of the newest message when we pressed Lock in
	local autoLock = AutoLock.new()
	local statesOpen = false -- the state list is expanded
	local sortMode: StateOrder.Mode = "Closest"
	local skipStep: number? = nil -- step we pressed Skip for

	-- Reveal state.
	local planView: View? = nil -- the last plan-stage view (the polls before a resolve)
	local revealStep: number? = nil
	local revealItems: { { caption: string, state: string?, polls: boolean } } = {}
	local revealLines: { string } = {}
	local revealShown = -1
	local revealOldView: View? = nil

	-- Messages.
	local seenMessageId = 0
	local toast: string? = nil
	local toastUntil = 0

	local portrait: boolean? = nil
	local lastBodySize = Vector2.new(-1, -1)

	-- Re-renders everything from `payload` and the draft (defined below).
	local render: () -> ()
	-- Selects a state, as a tap on the map or on the list does (defined below).
	local selectState: (id: string) -> ()

	-- ------------------------------------------------------------ build: frame

	Kit.list("Vertical", GAP).Parent = parent

	local topBar =
		Kit.box({ Name = "TopBar", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 2 * ROW_H), Parent = parent })
	Kit.list("Vertical", 4).Parent = topBar
	local topRows: { Frame } = {}
	for k = 1, 3 do
		topRows[k] = row(topBar, k, `TopRow{k}`, ROW_H)
	end
	local notice = scaled(topBar, 4, "OpponentNotice", {
		Size = UDim2.new(1, 0, 0, NOTICE_H),
		TextColor3 = Kit.colors.danger,
		Visible = false,
	})

	local top = {
		week = scaled(nil, 1, "WeekLabel", { Font = Kit.font.bold }),
		stage = scaled(nil, 2, "StageLabel", { TextColor3 = Kit.colors.accent }),
		countdown = scaled(nil, 3, "Countdown", {
			Font = Kit.font.bold,
			TextColor3 = Kit.colors.accent,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
		money = scaled(nil, 4, "MoneyLabel", { TextColor3 = Kit.colors.good }),
		ap = scaled(nil, 5, "APLabel"),
		you = scaled(nil, 6, "YouLabel", { Font = Kit.font.bold }),
		vs = scaled(
			nil,
			7,
			"VsLabel",
			{ TextColor3 = Kit.colors.muted, TextXAlignment = Enum.TextXAlignment.Center }
		),
		them = scaled(
			nil,
			8,
			"ThemLabel",
			{ Font = Kit.font.bold, TextXAlignment = Enum.TextXAlignment.Right }
		),
		oppMoney = scaled(nil, 9, "OppMoney", { TextColor3 = Kit.colors.muted }),
		oppStatus = scaled(nil, 10, "OppStatus", { TextColor3 = Kit.colors.muted }),
	}
	top.vs.Text = "vs"

	-- Which top-bar labels go in which row, with their width share.
	type Slot = { label: TextLabel, width: number }
	local TOP_LANDSCAPE: { { Slot } } = {
		{
			{ label = top.week, width = 0.16 },
			{ label = top.stage, width = 0.3 },
			{ label = top.countdown, width = 0.12 },
			{ label = top.money, width = 0.22 },
			{ label = top.ap, width = 0.2 },
		},
		{
			{ label = top.you, width = 0.32 },
			{ label = top.vs, width = 0.06 },
			{ label = top.them, width = 0.32 },
			{ label = top.oppMoney, width = 0.16 },
			{ label = top.oppStatus, width = 0.14 },
		},
	}
	local TOP_PORTRAIT: { { Slot } } = {
		{
			{ label = top.week, width = 0.3 },
			{ label = top.stage, width = 0.45 },
			{ label = top.countdown, width = 0.25 },
		},
		{
			{ label = top.money, width = 0.28 },
			{ label = top.ap, width = 0.22 },
			{ label = top.oppMoney, width = 0.28 },
			{ label = top.oppStatus, width = 0.22 },
		},
		{
			{ label = top.you, width = 0.44 },
			{ label = top.vs, width = 0.1 },
			{ label = top.them, width = 0.46 },
		},
	}

	local body = Kit.box({ Name = "Body", LayoutOrder = 2, Parent = parent })
	local bodyList = Kit.list("Horizontal", GAP)
	bodyList.Parent = body

	-- Map area: a caption line, then the map.
	local mapArea = Kit.box({ Name = "MapArea", LayoutOrder = 1, Parent = body })
	Kit.list("Vertical", 4).Parent = mapArea
	local caption = scaled(mapArea, 1, "Caption", { Size = UDim2.new(1, 0, 0, CAPTION_H) })
	local mapHolder = Kit.box({
		Name = "MapHolder",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 1, -(CAPTION_H + 4)),
		Parent = mapArea,
	})
	local map: MapInterface.Map = NodeMap.new()
	map.root.AnchorPoint = Vector2.new(0.5, 0.5)
	map.root.Position = UDim2.fromScale(0.5, 0.5)
	map.root.Parent = mapHolder

	-- Side panel: scrolls when its contents are taller than the screen.
	local side = Kit.new("ScrollingFrame", {
		Name = "Side",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		Parent = body,
	})
	Kit.list("Vertical", GAP).Parent = side
	Kit.new("UIPadding", { PaddingRight = UDim.new(0, 10), Parent = side })

	-- ------------------------------------------------------------ build: event banner

	local banner = panel(side, 0, "EventBanner")
	local bannerKind = sentence(
		banner,
		1,
		"EventKind",
		{ TextSize = Kit.size.small, TextColor3 = Kit.colors.accent, Font = Kit.font.medium }
	)
	local bannerTitle =
		scaled(banner, 2, "EventTitle", { Size = UDim2.new(1, 0, 0, 30), Font = Kit.font.bold })
	local bannerText = sentence(banner, 3, "EventText", { TextColor3 = Kit.colors.muted })
	local bannerEffect = sentence(banner, 4, "EventEffect", { Font = Kit.font.medium })
	local bannerMapNote =
		sentence(banner, 5, "EventMapNote", { TextSize = Kit.size.small, TextColor3 = Kit.colors.muted })
	local answerRow = row(banner, 6, "ChoiceRow")
	local choiceButtons: { [string]: TextButton } = {}
	for k = 1, #Events.CHOICES do
		local answer: SharedTypes.Choice = Events.CHOICES[k]
		local button: TextButton
		button = Kit.button(answer, function()
			if button.Active == false then
				return
			end
			draft.choice = answer
			render()
		end, { Name = `Choice{answer}`, LayoutOrder = k, Size = cell(3), Parent = answerRow })
		choiceButtons[answer] = button
	end
	local choiceNote =
		sentence(banner, 7, "ChoiceNote", { TextSize = Kit.size.small, TextColor3 = Kit.colors.muted })

	-- ------------------------------------------------------------ build: reveal panel

	local revealPanel = panel(side, 1, "RevealPanel")
	local revealTitle =
		scaled(revealPanel, 1, "RevealTitle", { Size = UDim2.new(1, 0, 0, 30), Font = Kit.font.bold })
	local revealList = stack(revealPanel, 2, "RevealLines", 4)
	local revealLabels: { TextLabel } = {}
	for k = 1, REVEAL_LINES do
		revealLabels[k] = sentence(revealList, k, `RevealLine{k}`, { Visible = false })
	end
	local revealSummary = sentence(revealPanel, 3, "RevealSummary", { TextColor3 = Kit.colors.accent })
	local skipButton: TextButton
	skipButton = Kit.button("Skip", function()
		if skipButton.Active == false or payload == nil then
			return
		end
		skipStep = (payload :: Payload).step
		ctx.net.skip()
		render()
	end, { Name = "SkipButton", LayoutOrder = 4, Parent = revealPanel })

	-- ------------------------------------------------------------ build: state card

	local card = panel(side, 2, "StateCard")
	local cardTitle = scaled(card, 1, "CardTitle", { Size = UDim2.new(1, 0, 0, 30), Font = Kit.font.bold })

	-- The state list: every state as a row, for the ones the phone map hides.
	local statesToggle = Kit.button("", function()
		statesOpen = not statesOpen
		render()
	end, { Name = "StatesToggle", LayoutOrder = 2, Parent = card })
	local statePicker = stack(card, 3, "StatePicker", 4)
	statePicker.Visible = false
	local statesSort = Kit.button("", function()
		sortMode = StateOrder.nextMode(sortMode)
		render()
	end, { Name = "StatesSort", LayoutOrder = 0, Parent = statePicker })
	type PickerRow = {
		index: number,
		button: TextButton,
		stroke: UIStroke,
		code: TextLabel,
		name: TextLabel,
		ev: TextLabel,
		margin: TextLabel,
		momentum: TextLabel,
	}
	local pickerRows: { [string]: PickerRow } = {}
	for index, record in StateData.list do
		local id = record.id
		local button = Kit.new("TextButton", {
			Name = `Row_{id}`,
			Size = UDim2.new(1, 0, 0, BUTTON_H),
			BackgroundColor3 = Kit.colors.raised,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Text = "",
			LayoutOrder = index,
			Parent = statePicker,
		}) :: TextButton
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
		local function pickerCell(name: string, x: number, w: number, props: { [string]: any }): TextLabel
			local base: { [string]: any } = {
				Name = name,
				Position = UDim2.fromScale(x, 0),
				Size = UDim2.fromScale(w, 1),
				TextScaled = true,
				TextSize = 15,
				Parent = button,
			}
			for key, value in props do
				base[key] = value
			end
			return Kit.text("", base)
		end
		local entry: PickerRow = {
			index = index,
			button = button,
			stroke = stroke,
			code = pickerCell("Code", 0, 0.1, { Font = Kit.font.bold, TextSize = 18 }),
			name = pickerCell("Name", 0.1, 0.36, {}),
			ev = pickerCell("EV", 0.46, 0.12, { TextXAlignment = Enum.TextXAlignment.Center }),
			margin = pickerCell("Margin", 0.58, 0.24, {
				Font = Kit.font.medium,
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
			momentum = pickerCell("Momentum", 0.82, 0.18, {
				TextColor3 = Kit.colors.muted,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}
		entry.code.Text = id
		entry.name.Text = record.name
		entry.ev.Text = `{record.ev} EV`
		button.Activated:Connect(function()
			selectState(id)
		end)
		pickerRows[id] = entry
	end

	local cardDetails = stack(card, 4, "CardDetails", 2)
	local cardTags =
		sentence(cardDetails, 1, "CardTags", { TextSize = Kit.size.small, TextColor3 = Kit.colors.accent })
	local cardIssues = sentence(cardDetails, 2, "CardIssues", { TextSize = Kit.size.small })
	local cardPoll = sentence(cardDetails, 3, "CardPoll", { TextSize = Kit.size.small })
	local cardMomentum = sentence(cardDetails, 4, "CardMomentum", { TextSize = Kit.size.small })
	local cardLean = sentence(cardDetails, 5, "CardLean", { TextSize = Kit.size.small })
	local cardInternal =
		sentence(cardDetails, 6, "CardInternal", { TextSize = Kit.size.small, TextColor3 = Kit.colors.good })
	local cardGround = sentence(cardDetails, 7, "CardGround", { TextSize = Kit.size.small })
	local cardMove =
		sentence(cardDetails, 8, "CardMove", { TextSize = Kit.size.small, TextColor3 = Kit.colors.muted })

	local actionsBox = stack(card, 5, "Actions", 6)
	local issueRow = row(actionsBox, 1, "IssueRow")
	local issueButton: TextButton
	issueButton = Kit.button("Message", function()
		if issueButton.Active == false then
			return
		end
		pickerOpen = not pickerOpen
		render()
	end, { Name = "IssueButton", Size = cell(1), Parent = issueRow })
	local picker = stack(actionsBox, 2, "IssuePicker", 6)
	local pickerButtons: { [string]: TextButton } = {}
	for k = 1, #Issues.list, 2 do
		local pickerRow = row(picker, k, `IssuePickerRow{k}`)
		for j = k, math.min(k + 1, #Issues.list) do
			local issue: Issue = Issues.list[j]
			local button: TextButton
			button = Kit.button(issueName(issue), function()
				if button.Active == false then
					return
				end
				chosenIssue = issue
				pickerOpen = false
				render()
			end, { Name = `Issue{issue}`, LayoutOrder = j, Size = cell(2), Parent = pickerRow })
			pickerButtons[issue] = button
		end
	end

	local ACTIONS = { "Rally", "Fundraise", "Ad", "Attack", "Poll", "Gotv" }
	local actionButtons: { [string]: TextButton } = {}
	local actionRows = { row(actionsBox, 3, "ActionRow1"), row(actionsBox, 4, "ActionRow2") }
	local addAction: (name: string) -> ()
	for k, name in ACTIONS do
		local button: TextButton
		button = Kit.button(name, function()
			if button.Active == false then
				return
			end
			addAction(name)
		end, {
			Name = name,
			LayoutOrder = k,
			Size = cell(3),
			Parent = actionRows[if k <= 3 then 1 else 2],
		})
		actionButtons[name] = button
	end
	local actionHint =
		sentence(actionsBox, 5, "ActionHint", { TextColor3 = Kit.colors.muted, TextSize = Kit.size.small })

	-- ------------------------------------------------------------ build: debate prep

	local prepPanel = panel(side, 4, "PrepPanel")
	local prepTitle = sentence(prepPanel, 1, "PrepTitle", { Font = Kit.font.bold })
	local prepRows: { { topic: TextLabel, value: TextLabel, minus: TextButton, plus: TextButton } } = {}
	local stepPrep: (topic: number, delta: number) -> ()
	for t = 1, config.DEBATE_TOPICS do
		local prepRow = row(prepPanel, 1 + t, `PrepRow{t}`)
		local topic = Kit.text("", {
			Name = `PrepTopic{t}`,
			LayoutOrder = 1,
			Size = UDim2.new(1, -(3 * BUTTON_H + 18), 1, 0),
			TextSize = Kit.size.small,
			Parent = prepRow,
		})
		local minus: TextButton
		minus = Kit.button(
			"-",
			function()
				if minus.Active == false then
					return
				end
				stepPrep(t, -1)
			end,
			{ Name = `PrepMinus{t}`, LayoutOrder = 2, Size = UDim2.new(0, BUTTON_H, 1, 0), Parent = prepRow }
		)
		local value = scaled(prepRow, 3, `PrepValue{t}`, {
			Size = UDim2.new(0, BUTTON_H, 1, 0),
			Font = Kit.font.bold,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		local plus: TextButton
		plus = Kit.button("+", function()
			if plus.Active == false then
				return
			end
			stepPrep(t, 1)
		end, { Name = `PrepPlus{t}`, LayoutOrder = 4, Size = UDim2.new(0, BUTTON_H, 1, 0), Parent = prepRow })
		prepRows[t] = { topic = topic, value = value, minus = minus, plus = plus }
	end
	local prepTotal =
		sentence(prepPanel, 10, "PrepTotal", { TextColor3 = Kit.colors.muted, TextSize = Kit.size.small })

	-- ------------------------------------------------------------ build: plan tray

	local tray = panel(side, 3, "Tray")
	scaled(tray, 1, "TrayTitle", { Size = UDim2.new(1, 0, 0, 30), Font = Kit.font.bold }).Text =
		"Your plan this week"
	local items = stack(tray, 8, "PlanItems", 4)
	local trayEmpty = sentence(tray, 9, "TrayEmpty", { TextColor3 = Kit.colors.muted })
	trayEmpty.Text = "Tap a state, then an action, to add it here."
	local trayCost = sentence(tray, 2, "TrayCost", { Font = Kit.font.medium })
	local trayProblem = sentence(tray, 3, "TrayProblem", { TextColor3 = Kit.colors.danger, Visible = false })
	local lockedNote = sentence(
		tray,
		4,
		"LockedNote",
		{ TextColor3 = Kit.colors.accent, Font = Kit.font.bold, Visible = false }
	)
	lockedNote.Text = "Locked — waiting for opponent"

	-- Sends the plan as drafted (the Lock in button, or the timer about to end).
	local function lockPlan()
		local current = payload
		if current == nil then
			return
		end
		lockStep = current.step
		lockMessageId = Messages.lastId(ctx.store.get())
		pickerOpen = false
		pivotStage = nil
		autoLock:spent(current)
		ctx.net.submit(PlanDraft.payload(draft))
		render()
	end

	local lockButton: TextButton
	lockButton = Kit.button("Lock in", function()
		if lockButton.Active == false then
			return
		end
		lockPlan()
	end, {
		Name = "LockIn",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, LOCK_H),
		BackgroundColor3 = Kit.colors.accent,
		TextColor3 = Kit.colors.background,
		Font = Kit.font.bold,
		TextSize = Kit.size.large,
		Parent = tray,
	})

	local trayRow = row(tray, 6, "TrayButtons")
	local bankButton: TextButton
	bankButton = Kit.button("Bank", function()
		if bankButton.Active == false then
			return
		end
		ctx.net.bank()
	end, { Name = "BankButton", LayoutOrder = 1, Size = cell(3), Parent = trayRow })
	local clearButton: TextButton
	clearButton = Kit.button("Clear", function()
		if clearButton.Active == false then
			return
		end
		draft.actions = {}
		pivotStage = nil
		render()
	end, { Name = "ClearButton", LayoutOrder = 2, Size = cell(3), Parent = trayRow })
	local pivotButton: TextButton
	pivotButton = Kit.button("Pivot", function()
		if pivotButton.Active == false then
			return
		end
		pivotStage = if pivotStage == nil then "drop" else nil
		pivotDrop = nil
		render()
	end, { Name = "PivotButton", LayoutOrder = 3, Size = cell(3), Parent = trayRow })

	local pivotPanel = stack(tray, 7, "PivotChooser", 6)
	local pivotTitle = sentence(pivotPanel, 1, "PivotTitle", { TextColor3 = Kit.colors.accent })
	local pivotChoices = stack(pivotPanel, 2, "PivotChoices", 6)

	-- ------------------------------------------------------------ build: week card

	local feed = panel(side, 5, "Feed")
	scaled(feed, 1, "FeedTitle", { Size = UDim2.new(1, 0, 0, 30), Font = Kit.font.bold }).Text = "Week card"
	local feedOpponent = sentence(feed, 2, "FeedOpponent")
	local feedEvent = sentence(feed, 3, "FeedEvent", { TextColor3 = Kit.colors.accent })
	local feedRaised = sentence(feed, 4, "FeedRaised", { TextColor3 = Kit.colors.good })
	local feedPolls = sentence(feed, 5, "FeedPolls")
	local feedDebate = sentence(feed, 6, "FeedDebate", { TextColor3 = Kit.colors.accent })
	local feedMessages =
		sentence(feed, 7, "FeedMessages", { TextColor3 = Kit.colors.muted, TextSize = Kit.size.small })

	-- ------------------------------------------------------------ layout

	local function topHeight(rows: number): number
		local height = rows * ROW_H + (rows - 1) * 4
		if notice.Visible then
			height += NOTICE_H + 4
		end
		return height
	end

	local function placeTop(isPortrait: boolean)
		local spec: { { Slot } } = if isPortrait then TOP_PORTRAIT else TOP_LANDSCAPE
		for k, topRow in topRows do
			local slots: { Slot }? = spec[k]
			setVisible(topRow, slots ~= nil)
			if slots then
				for order = 1, #slots do
					local slot = slots[order]
					slot.label.LayoutOrder = order
					slot.label.Size = UDim2.new(slot.width, -6, 1, 0)
					slot.label.Parent = topRow
				end
			end
		end
		local height = topHeight(#spec)
		topBar.Size = UDim2.new(1, 0, 0, height)
		body.Size = UDim2.new(1, 0, 1, -(height + GAP))
	end

	local function placeBody(isPortrait: boolean)
		if isPortrait then
			bodyList.FillDirection = Enum.FillDirection.Vertical
			local width = body.AbsoluteSize.X
			local height = body.AbsoluteSize.Y
			local mapHeight = math.floor(math.min(width / MapLayout.ASPECT, height * PORTRAIT_MAP_MAX))
			local areaHeight = mapHeight + CAPTION_H + 4
			mapArea.Size = UDim2.new(1, 0, 0, areaHeight)
			side.Size = UDim2.new(1, 0, 1, -(areaHeight + GAP))
			lastBodySize = body.AbsoluteSize
		else
			bodyList.FillDirection = Enum.FillDirection.Horizontal
			mapArea.Size = UDim2.new(MAP_SHARE, -GAP // 2, 1, 0)
			side.Size = UDim2.new(1 - MAP_SHARE, -GAP // 2, 1, 0)
		end
	end

	local function relayout(force: boolean?)
		local isPortrait = ctx.portrait()
		if isPortrait ~= portrait or force then
			portrait = isPortrait
			placeTop(isPortrait)
			placeBody(isPortrait)
		elseif
			isPortrait and (body.AbsoluteSize.X ~= lastBodySize.X or body.AbsoluteSize.Y ~= lastBodySize.Y)
		then
			placeBody(true)
		end
	end

	-- ------------------------------------------------------------ plan logic

	local function current(): (Payload?, View?)
		local p = payload
		if p == nil then
			return nil, nil
		end
		return p, p.view
	end

	-- Locked in (the server says so, or we just pressed Lock in this step).
	local function isLocked(p: Payload): boolean
		local seat = p.seats[p.you]
		return (seat ~= nil and seat.locked) or lockStep == p.step
	end

	local function planning(p: Payload): boolean
		return p.stage == "Input" and p.view.phase == "Plan"
	end

	local function editable(p: Payload): boolean
		return planning(p) and not isLocked(p)
	end

	-- The problem the draft would have with `action` added.
	local function trial(view: View, action: Action): string?
		local test: PlanDraft.Draft =
			{ actions = table.clone(draft.actions), prep = draft.prep, choice = draft.choice }
		table.insert(test.actions, action)
		return PlanDraft.problem(config, view, test)
	end

	local function messageIssue(view: View, id: string): Issue
		if chosenIssue ~= nil then
			return chosenIssue
		end
		local best: Issue = PlanDraft.bestIssue(config, view, id)
		return best
	end

	-- The action a card button would add for state `id`.
	local function actionFor(view: View, name: string, id: string): Action
		if name == "Rally" then
			return { kind = "Rally", state = id, issue = messageIssue(view, id) }
		elseif name == "Fundraise" then
			return { kind = "Fundraise", state = id }
		elseif name == "Ad" then
			return { kind = "Media", state = id, issue = messageIssue(view, id) }
		elseif name == "Attack" then
			local issue: Issue = PlanDraft.bestAttackIssue(config, view, id)
			return { kind = "Attack", state = id, issue = issue, target = opponentOf(view) }
		elseif name == "Poll" then
			return { kind = "Poll", state = id }
		end
		return { kind = "Gotv", state = id, units = 1 }
	end

	addAction = function(name: string)
		local p, view = current()
		local id = selected
		if p == nil or view == nil or id == nil or not editable(p) then
			return
		end
		local action = actionFor(view, name, id)
		if trial(view, action) ~= nil then
			return
		end
		if action.kind == "Gotv" then
			-- One tray line per state: +1 adds a unit to it.
			for _, existing in draft.actions do
				if existing.kind == "Gotv" and existing.state == id then
					existing.units = (existing.units or 0) + 1
					render()
					return
				end
			end
		end
		PlanDraft.add(draft, action)
		render()
	end

	local function removeAction(index: number)
		local p = payload
		if p == nil or not editable(p) or draft.actions[index] == nil then
			return
		end
		PlanDraft.remove(draft, index)
		render()
	end

	stepPrep = function(t: number, delta: number)
		local p = payload
		local prep = draft.prep
		if p == nil or prep == nil or not editable(p) then
			return
		end
		local max = config.DEBATE_MAX_PER_TOPIC
		-- Keep the total: take a point from (or give one to) another topic.
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
		render()
	end

	local function startDraft(p: Payload)
		draft = PlanDraft.new()
		draftStep = p.step
		chosenIssue = nil
		pickerOpen = false
		pivotStage = nil
		pivotDrop = nil
		local view = p.view
		if prepWanted(view) then
			local points = PlanDraft.profile(config, view).debatePrep
			local saved = view.debatePrep
			if saved and #saved == config.DEBATE_TOPICS then
				draft.prep = table.clone(saved)
			else
				draft.prep = Plan.defaultPrep(config, points)
			end
		end
		-- Ignore is what the server assumes for a missing answer, so it starts selected.
		draft.choice = if PlanDraft.isChoiceWeek(view) then "Ignore" else nil
		if selected == nil then
			selected = view.players[view.you].location
		end
	end

	-- ------------------------------------------------------------ render: top bar

	local function renderTop(now: number)
		local p, view = current()
		if p == nil or view == nil then
			return
		end
		local you, them = view.you, opponentOf(view)
		local week = view.week
		local stage = "Plan your week"
		if p.reveal == "Resolve" then
			week -= 1
			stage = "Results"
		elseif p.reveal == "Debate" then
			stage = "Debate"
		elseif p.stage ~= "Input" then
			stage = "Campaign"
		elseif isLocked(p) then
			stage = "Locked in"
		end
		top.week.Text = `Week {math.clamp(week, 1, config.WEEKS)} of {config.WEEKS}`
		top.stage.Text = stage
		local left = p.deadline - now
		top.countdown.Text = Kit.clock(left)
		top.countdown.TextColor3 = if p.stage == "Input" and left < 10
			then Kit.colors.danger
			else Kit.colors.accent

		local ap, cash = PlanDraft.remaining(config, view, draft)
		local profile = PlanDraft.profile(config, view)
		top.money.Text = `Money {money(cash)}`
		top.money.TextColor3 = if cash < 0 then Kit.colors.danger else Kit.colors.good
		top.ap.Text = `AP {ap} of {profile.apPerWeek}`
		top.ap.TextColor3 = if ap < 0 then Kit.colors.danger else Kit.colors.text

		local ev = view.projectedEV
		top.you.Text = `{candidateName(config, view, you)} · {ev[you] or 0} EV`
		top.you.TextColor3 = playerColor(view, you)
		top.them.Text = `{ev[them] or 0} EV · {candidateName(config, view, them)}`
		top.them.TextColor3 = playerColor(view, them)
		top.oppMoney.Text = `Their money: {view.players[them].money}`

		local seat = p.seats[them]
		local status = "Watching"
		if seat == nil then
			status = ""
		elseif not seat.connected then
			status = "Disconnected"
		elseif p.stage == "Input" then
			status = if seat.locked then "Locked in" else "Thinking..."
		elseif p.reveal == "Resolve" and seat.skip then
			status = "Skipped"
		end
		top.oppStatus.Text = status
		top.oppStatus.TextColor3 = if status == "Locked in"
			then Kit.colors.good
			elseif status == "Disconnected" then Kit.colors.danger
			else Kit.colors.muted

		local away = seat ~= nil and not seat.connected
		if away then
			local grace = (seat :: Session.SeatInfo).graceUntil
			notice.Text = if grace ~= nil and grace > now
				then `Opponent disconnected · their moves auto-submit in {Kit.clock(grace - now)}`
				else "Opponent disconnected"
		end
		if notice.Visible ~= away then
			notice.Visible = away
			placeTop(portrait == true)
		end
	end

	-- ------------------------------------------------------------ render: map

	local function plannedUnits(id: string): number
		local units = 0
		for _, action in draft.actions do
			if action.kind == "Gotv" and action.state == id then
				units += action.units or 0
			end
		end
		return units
	end

	local function paintMap(view: View, shown: View)
		local colors: { Colors.RGB } = {}
		for p, player in view.players do
			colors[p] = Colors.of(player.color)
		end
		map:setView(shown, colors)
		local live = payload
		local event = if live then shownEvent(live) else nil
		local starred = if event then PlanDraft.eventStates(event) else {}
		local marks: { [string]: MapInterface.Mark } = {}
		for _, s in view.states do
			local parts: { string } = {}
			if s.isHome and s.owner then
				table.insert(parts, "H")
			end
			if s.battleground then
				table.insert(parts, "B")
			end
			local units = s.gotv + plannedUnits(s.id)
			if units > 0 then
				table.insert(parts, `G{units}`)
			end
			if starred[s.id] then
				table.insert(parts, "*")
			end
			local ring = if s.owner then playerColor(view, s.owner) else nil
			if ring or #parts > 0 then
				marks[s.id] = { ring = ring, badge = if #parts > 0 then table.concat(parts, " ") else nil }
			end
		end
		map:setMarks(marks)
	end

	local function paintRoute(p: Payload)
		local view = p.view
		if not planning(p) then
			map:setRoute({}, {})
			return
		end
		local ids: { string } = {}
		local flights: { boolean } = {}
		local start = view.players[view.you].location
		if start then
			table.insert(ids, start)
			table.insert(flights, false)
		end
		for _, stop in PlanDraft.route(view, draft) do
			table.insert(ids, stop.state)
			table.insert(flights, stop.flight)
		end
		if #ids < 2 then
			map:setRoute({}, {})
		else
			map:setRoute(ids, flights)
		end
	end

	-- ------------------------------------------------------------ render: state card

	local function renderCard(p: Payload)
		local view = p.view
		local id = selected
		local index = if id then SimState.indexOf[id] else nil
		local canEdit = editable(p)
		if id == nil or index == nil then
			cardTitle.Text = "Tap a state on the map"
			setVisible(cardDetails, false)
			setVisible(actionsBox, false)
			return
		end
		setVisible(cardDetails, true)
		setVisible(actionsBox, planning(p))
		local you, them = view.you, opponentOf(view)
		local s = view.states[index]
		local record: SharedTypes.StateRecord = StateData.byId[id]
		cardTitle.Text = `{record.name} · {record.ev} EV`

		local tags: { string } = {}
		if s.battleground then
			table.insert(tags, "Battleground")
		end
		if s.owner then
			local whose = if s.owner == you then "Your" else "Their"
			table.insert(tags, `{whose} {if s.isHome then "home state" else "stronghold"}`)
		end
		if view.players[you].location == id then
			table.insert(tags, "You are here")
		end
		if view.players[them].location == id then
			table.insert(tags, "Opponent is here")
		end
		cardTags.Text = table.concat(tags, " · ")
		setVisible(cardTags, #tags > 0)

		local issueNames: { string } = {}
		for _, issue in record.issues do
			table.insert(issueNames, issueName(issue))
		end
		cardIssues.Text = `Top issues: {table.concat(issueNames, ", ")}`

		local poll = s.poll
		cardPoll.Text = if poll
			then `Public poll: you {poll.support[you] or 0} - {poll.support[them] or 0} them · {poll.undecided} undecided`
			else "No public poll yet"
		cardMomentum.Text =
			string.format("Momentum: you %.1f · them %.1f", s.momentum[you] or 0, s.momentum[them] or 0)
		if s.leanTo ~= nil and s.lean > 0 then
			cardLean.Text = `Lean: {s.lean} toward {if s.leanTo == you then "you" else "them"}`
		else
			cardLean.Text = "Lean: none"
		end

		local internal = nil
		for _, result in view.internalPolls do
			if result.state == id then
				internal = result
			end
		end
		if internal then
			cardInternal.Text = string.format(
				"Your internal poll: you %.1f - %.1f them · %.1f undecided",
				internal.support[you] or 0,
				internal.support[them] or 0,
				internal.undecided
			)
		end
		setVisible(cardInternal, internal ~= nil)

		local profile = PlanDraft.profile(config, view)
		local planned = plannedUnits(id)
		cardGround.Text = `Ground game: {s.gotv} of {profile.gotvMaxUnits} units`
			.. (if planned > 0 then ` (+{planned} planned)` else "")
			.. ` · pool size {money(s.capacity)}`
		local from = PlanDraft.location(view, draft)
		cardMove.Text = if Plan.isAdjacent(from, id)
			then "Rally or fundraise here: no flight needed"
			else `Rally or fundraise here: flight from {stateName(from)} ({money(config.FLIGHT_COST)})`

		if not planning(p) then
			return
		end

		-- The message (issue) for rallies and ads, with its multiplier here.
		local platform: { Issue } = view.players[you].platform or {}
		local message: Issue = messageIssue(view, id)
		local mult = Resolve.issueMult(config, platform, record.issues, message)
		issueButton.Text = string.format("Message: %s ×%.1f (change)", issueName(message), mult)
		Kit.setEnabled(issueButton, canEdit)
		setVisible(picker, pickerOpen and canEdit)
		for k = 1, #Issues.list do
			local issue: Issue = Issues.list[k]
			local button = pickerButtons[issue]
			local m = Resolve.issueMult(config, platform, record.issues, issue)
			button.Text = string.format("%s ×%.1f", issueName(issue), m)
			Kit.setEnabled(button, canEdit)
			button.BackgroundColor3 = if issue == message then Kit.colors.raisedHover else Kit.colors.raised
		end

		local base = PlanDraft.cost(config, view, draft)
		local hint: string? = nil
		for _, name in ACTIONS do
			local button = actionButtons[name]
			local action = actionFor(view, name, id)
			local problem = trial(view, action)
			local label = if name == "Gotv" then "GOTV +1" elseif name == "Ad" then "Ad" else name
			if problem then
				button.Text = `{label} ({SHORT_REASON[problem] or "no"})`
				if hint == nil then
					hint = `Greyed out: {ctx.net.reasonText(problem)}`
				end
			else
				local test: PlanDraft.Draft =
					{ actions = table.clone(draft.actions), prep = draft.prep, choice = draft.choice }
				table.insert(test.actions, action)
				local extra = PlanDraft.cost(config, view, test).cash - base.cash
				button.Text = if extra > 1e-9 then `{label} {money(extra)}` else label
			end
			Kit.setEnabled(button, canEdit and problem == nil)
		end
		if not canEdit then
			hint = "Your plan is locked in."
		end
		actionHint.Text = hint
			or "Rally and Fundraise move your candidate (1 AP each). Ads, polls and GOTV cost money."
	end

	-- ------------------------------------------------------------ render: state list

	local function renderPicker(p: Payload)
		local view = p.view
		statesToggle.Text = if statesOpen then "Hide the state list" else "Pick a state from the list"
		setVisible(statePicker, statesOpen)
		if not statesOpen then
			return
		end
		statesSort.Text = `Sorted: {StateOrder.label(sortMode)} (tap to change)`
		local you, them = view.you, opponentOf(view)
		for rank, id in StateOrder.sort(view, sortMode) do
			local entry = pickerRows[id]
			local sv = view.states[entry.index]
			local chosen = id == selected
			entry.button.LayoutOrder = rank
			entry.button.BackgroundColor3 = if chosen then Kit.colors.raisedHover else Kit.colors.raised
			entry.stroke.Thickness = if chosen then 2 else 0
			entry.code.TextColor3 = if sv.owner ~= nil then playerColor(view, sv.owner) else Kit.colors.text
			entry.margin.Text = StateOrder.marginText(view, sv)
			local margin = StateOrder.margin(view, sv)
			entry.margin.TextColor3 = if margin > 0
				then playerColor(view, you)
				elseif margin < 0 then playerColor(view, them)
				else Kit.colors.muted
			entry.momentum.Text = StateOrder.momentumText(view, sv)
		end
	end

	-- ------------------------------------------------------------ render: event banner

	local function renderEvent(p: Payload)
		local event = shownEvent(p)
		setVisible(banner, event ~= nil)
		if event == nil then
			return
		end
		bannerKind.Text = `This week's event · {event.kind}`
		bannerTitle.Text = event.name
		bannerText.Text = event.text
		bannerEffect.Text = PlanDraft.eventEffect(config, event)
		local mapNote = PlanDraft.eventMapNote(event)
		bannerMapNote.Text = mapNote or ""
		setVisible(bannerMapNote, mapNote ~= nil)
		local choosing = event.kind == "Choice" and planning(p)
		setVisible(answerRow, choosing)
		setVisible(choiceNote, choosing)
		if not choosing then
			return
		end
		choiceNote.Text = PlanDraft.choiceNote(config)
		local canEdit = editable(p)
		for answer, button in choiceButtons do
			local picked = draft.choice == answer
			button.BackgroundColor3 = if picked then Kit.colors.accent else Kit.colors.raised
			button.TextColor3 = if picked then Kit.colors.background else Kit.colors.text
			Kit.setEnabled(button, canEdit)
		end
	end

	-- ------------------------------------------------------------ render: debate prep

	local function renderPrep(p: Payload)
		local view = p.view
		local prep = draft.prep
		local show = planning(p) and prepWanted(view) and prep ~= nil
		setVisible(prepPanel, show)
		if not show or prep == nil then
			return
		end
		local debate = view.nextDebate :: { week: number, topics: { Issue } }
		local points = PlanDraft.profile(config, view).debatePrep
		local max = config.DEBATE_MAX_PER_TOPIC
		local canEdit = editable(p)
		prepTitle.Text = `Debate prep for week {debate.week}: share {points} points, at most {max} per topic`
		local mine: { Issue } = view.players[view.you].platform or {}
		local theirs: { Issue } = view.players[opponentOf(view)].platform or {}
		local total = 0
		for t, controls in prepRows do
			local topic: Issue? = debate.topics[t]
			local tags: { string } = {}
			if topic and table.find(mine, topic) then
				table.insert(tags, "your platform")
			end
			if topic and table.find(theirs, topic) then
				table.insert(tags, "their platform")
			end
			controls.topic.Text = issueName(topic)
				.. (if #tags > 0 then ` ({table.concat(tags, ", ")})` else "")
			local value = prep[t] or 0
			total += value
			controls.value.Text = tostring(value)
			local othersHave, othersRoom = false, false
			for k = 1, #prep do
				if k ~= t then
					othersHave = othersHave or prep[k] > 0
					othersRoom = othersRoom or prep[k] < max
				end
			end
			Kit.setEnabled(controls.plus, canEdit and value < max and othersHave)
			Kit.setEnabled(controls.minus, canEdit and value > 0 and othersRoom)
		end
		prepTotal.Text = `{total} of {points} points placed. Losing a topic with 0 prep is a gaffe.`
	end

	-- ------------------------------------------------------------ render: tray

	local function renderPivot(p: Payload, canEdit: boolean)
		local view = p.view
		local platform: { Issue } = view.players[view.you].platform or {}
		local show = pivotStage ~= nil and canEdit
		setVisible(pivotPanel, show)
		clearChildren(pivotChoices)
		if not show then
			return
		end
		local choices: { Issue } = {}
		if pivotStage == "drop" then
			pivotTitle.Text = "Pivot (1 AP, once per match, costs national support). Drop which issue?"
			for k = 1, #platform do
				local issue: Issue = platform[k]
				table.insert(choices, issue)
			end
		else
			pivotTitle.Text = `Drop {issueName(pivotDrop)}. Add which issue?`
			for k = 1, #Issues.list do
				local issue: Issue = Issues.list[k]
				if not table.find(platform, issue) then
					table.insert(choices, issue)
				end
			end
		end
		local choiceRow: Frame? = nil
		for k = 1, #choices do
			local issue: Issue = choices[k]
			if (k - 1) % 2 == 0 then
				choiceRow = row(pivotChoices, k, `PivotRow{k}`)
			end
			local name = if pivotStage == "drop" then `PivotDrop{issue}` else `PivotAdd{issue}`
			local button: TextButton
			button = Kit.button(issueName(issue), function()
				if button.Active == false then
					return
				end
				if pivotStage == "drop" then
					pivotDrop = issue
					pivotStage = "add"
				elseif pivotDrop ~= nil then
					local now = payload
					local action: Action = { kind = "Pivot", drop = pivotDrop, add = issue }
					pivotStage = nil
					if now and trial(now.view, action) == nil then
						PlanDraft.add(draft, action)
					end
				end
				render()
			end, { Name = name, LayoutOrder = k, Size = cell(2), Parent = choiceRow })
			Kit.setEnabled(button, true)
		end
		local cancel: TextButton
		cancel = Kit.button("Cancel", function()
			pivotStage = nil
			render()
		end, { Name = "PivotCancel", LayoutOrder = 100, Parent = pivotChoices })
		Kit.setEnabled(cancel, true)
	end

	local function renderTray(p: Payload)
		local view = p.view
		local show = planning(p)
		setVisible(tray, show)
		if not show then
			return
		end
		local canEdit = editable(p)
		local locked = isLocked(p)
		local flights: { [number]: boolean } = {}
		for _, stop in PlanDraft.route(view, draft) do
			flights[stop.index] = stop.flight
		end
		clearChildren(items)
		for k, action in draft.actions do
			local itemRow = row(items, k, `PlanItemRow{k}`)
			Kit.text(`{k}. {actionText(config, action, flights[k] == true)}`, {
				Name = `PlanItem{k}`,
				LayoutOrder = 1,
				Size = UDim2.new(1, -(BUTTON_H + 6), 1, 0),
				TextSize = Kit.size.small,
				Parent = itemRow,
			})
			local remove = Kit.button("×", function()
				removeAction(k)
			end, {
				Name = `RemoveItem{k}`,
				LayoutOrder = 2,
				Size = UDim2.new(0, BUTTON_H, 1, 0),
				TextColor3 = Kit.colors.danger,
				Parent = itemRow,
			})
			Kit.setEnabled(remove, canEdit)
		end
		setVisible(trayEmpty, #draft.actions == 0 and canEdit)

		local cost = PlanDraft.cost(config, view, draft)
		local profile = PlanDraft.profile(config, view)
		local cash = view.players[view.you].cash or 0
		trayCost.Text =
			`AP used {cost.ap}/{profile.apPerWeek} · spent {money(cost.cash)} of {money(cash)} · {plural(
				cost.flights,
				"flight"
			)}`
		local problem = PlanDraft.problem(config, view, draft)
		trayProblem.Text = if problem then ctx.net.reasonText(problem) else ""
		setVisible(trayProblem, problem ~= nil)
		setVisible(lockedNote, locked)

		lockButton.Text = if locked then "Locked" else "Lock in"
		Kit.setEnabled(lockButton, canEdit and problem == nil)

		local seat = p.seats[p.you]
		local bank = if seat then seat.bank else 0
		local chunk = config.TIME_BANK_CHUNK
		bankButton.Text = `Bank +{chunk}s ({bank}s left)`
		Kit.setEnabled(bankButton, canEdit and bank >= chunk)
		Kit.setEnabled(clearButton, canEdit and #draft.actions > 0)

		local me = view.players[view.you]
		local hasPivot = false
		for _, action in draft.actions do
			if action.kind == "Pivot" then
				hasPivot = true
			end
		end
		local platform: { Issue } = me.platform or {}
		local pivotOk = false
		if not me.pivotUsed and not hasPivot and #platform > 0 then
			local probe: Action = { kind = "Pivot", drop = platform[1], add = platform[1] }
			pivotOk = trial(view, probe) == nil
		end
		setVisible(pivotButton, not me.pivotUsed and not hasPivot)
		pivotButton.Text = if pivotStage then "Pivot (close)" else "Pivot"
		Kit.setEnabled(pivotButton, canEdit and pivotOk)
		if not pivotOk then
			pivotStage = nil
		end
		renderPivot(p, canEdit)
	end

	-- ------------------------------------------------------------ render: week card

	local function renderFeed(p: Payload)
		local view = p.view
		local you, them = view.you, opponentOf(view)
		feedOpponent.Text = opponentCard(config, view)
		local lastEvent = PlanDraft.lastEventLine(view)
		feedEvent.Text = lastEvent or ""
		setVisible(feedEvent, lastEvent ~= nil)
		feedRaised.Text = `You raised {money(view.raised)} from fundraisers last week.`
		setVisible(feedRaised, view.raised > 0)
		local polls: { string } = {}
		for _, result in view.internalPolls do
			table.insert(
				polls,
				string.format(
					"%s %.1f-%.1f",
					result.state,
					result.support[you] or 0,
					result.support[them] or 0
				)
			)
		end
		feedPolls.Text = `Your internal polls (you-them): {table.concat(polls, ", ")}`
		setVisible(feedPolls, #polls > 0)
		local debate = view.nextDebate
		if debate then
			local names: { string } = {}
			for _, topic in debate.topics do
				table.insert(names, issueName(topic))
			end
			feedDebate.Text = `Next debate, week {debate.week}: {table.concat(names, ", ")}`
		end
		setVisible(feedDebate, debate ~= nil)
		local latest: { string } = {}
		for k = math.max(1, #messages - FEED_MESSAGES + 1), #messages do
			table.insert(latest, messages[k].text)
		end
		feedMessages.Text = table.concat(latest, "\n")
		setVisible(feedMessages, #latest > 0)
	end

	-- ------------------------------------------------------------ render: reveals

	local function swingsText(old: View, new: View): string?
		local you, them = new.you, opponentOf(new)
		local swings: { { id: string, delta: number } } = {}
		for i, s in new.states do
			local before = old.states[i]
			if s.poll and before and before.poll then
				local now = (s.poll.support[you] or 0) - (s.poll.support[them] or 0)
				local was = (before.poll.support[you] or 0) - (before.poll.support[them] or 0)
				if now ~= was then
					table.insert(swings, { id = s.id, delta = now - was })
				end
			end
		end
		if #swings == 0 then
			return nil
		end
		table.sort(swings, function(a, b)
			return math.abs(a.delta) > math.abs(b.delta)
		end)
		local parts: { string } = {}
		for k = 1, math.min(SWINGS, #swings) do
			local swing = swings[k]
			local toward = if swing.delta > 0 then "you" else "them"
			table.insert(parts, `{swing.id} {math.abs(swing.delta)} toward {toward}`)
		end
		return `Biggest poll swings: {table.concat(parts, ", ")}.`
	end

	local function showRevealLines()
		local first = math.max(1, #revealLines - REVEAL_LINES + 1)
		for k = 1, REVEAL_LINES do
			local text = revealLines[first + k - 1]
			revealLabels[k].Text = text or ""
			setVisible(revealLabels[k], text ~= nil)
		end
	end

	local function startResolve(p: Payload)
		revealStep = p.step
		revealItems = {}
		revealLines = {}
		revealShown = -1
		for k, label in revealLabels do
			label.Name = `RevealLine{k}`
		end
		local view = p.view
		for _, event in p.events do
			local text = eventCaption(config, view, event)
			if text then
				table.insert(
					revealItems,
					{ caption = text, state = event.state, polls = event.kind == "Polls" }
				)
			end
		end
		local old = planView
		revealOldView = if old and old.week == view.week - 1 then old else nil
		revealTitle.Text = `Week {math.max(1, view.week - 1)} results`
		revealSummary.Text = ""
	end

	local function tickResolve(p: Payload, now: number)
		local view = p.view
		local n = #revealItems
		local duration = math.max(REVEAL_BEAT, p.deadline - p.stageStart)
		local window = math.max(REVEAL_BEAT, duration - REVEAL_TAIL)
		local beats = math.max(1, math.floor(window / REVEAL_BEAT))
		local perBeat = math.max(1, math.ceil(n / beats))
		local steps = math.max(1, math.ceil(n / perBeat))
		local interval = math.clamp(window / steps, REVEAL_BEAT, REVEAL_SLOW)
		local elapsed = math.max(0, now - p.stageStart)
		local shown = math.min(n, (math.floor(elapsed / interval) + 1) * perBeat)
		if shown == revealShown then
			return
		end
		revealShown = shown
		revealLines = {}
		local pollsIn = revealOldView == nil
		local focus: string? = nil
		for k = 1, shown do
			local item = revealItems[k]
			table.insert(revealLines, item.caption)
			if item.polls then
				pollsIn = true
			end
			if item.state then
				focus = item.state
			end
		end
		showRevealLines()
		local last = revealItems[shown]
		caption.Text = if last then last.caption else "New public polls are in"
		caption.TextColor3 = Kit.colors.text
		paintMap(view, if pollsIn then view else revealOldView :: View)
		map:select(if shown < n then focus else nil)
		if shown >= n then
			local old = revealOldView
			local swings = if old then swingsText(old, view) else nil
			local you, them = view.you, opponentOf(view)
			revealSummary.Text = (swings or "The map shows the new public polls.")
				.. ` Projected EV: you {view.projectedEV[you] or 0} - {view.projectedEV[them] or 0} them.`
		end
	end

	local function startDebate(p: Payload)
		revealStep = p.step
		revealShown = -1
		revealLines = {}
		revealSummary.Text = ""
		revealTitle.Text = `Debate · week {p.view.week}`
	end

	local function tickDebate(p: Payload, now: number)
		local view = p.view
		local result = view.debates[#view.debates]
		if result == nil then
			revealTitle.Text = "Debate"
			return
		end
		local you, them = view.you, opponentOf(view)
		local topics = #result.topics
		local elapsed = math.max(0, now - p.stageStart)
		local shown = math.min(topics, math.floor(elapsed / DEBATE_BEAT) + 1)
		if shown == revealShown then
			return
		end
		revealShown = shown
		revealLines = {}
		local themName = candidateName(config, view, them)
		for t = 1, shown do
			local topic = result.topics[t]
			local winner = result.winners[t]
			local verdict = if winner == you
				then "you win"
				elseif winner == 0 then "tie"
				else `{themName} wins`
			local mine = result.scores[you] and result.scores[you][t] or 0
			local theirs = result.scores[them] and result.scores[them][t] or 0
			table.insert(revealLines, `{issueName(topic)}: you {mine} - {theirs} them · {verdict}`)
		end
		-- Lines are also exposed by topic for tests and agents (DebateTopic1..).
		showRevealLines()
		for t = 1, REVEAL_LINES do
			revealLabels[t].Name = if t <= shown then `DebateTopic{t}` else `RevealLine{t}`
		end
		caption.Text = revealLines[shown] or "Debate"
		caption.TextColor3 = Kit.colors.text
		if shown < topics then
			return
		end
		local callouts: { string } = {}
		for p2 = 1, #view.players do
			local who = if p2 == you then "You" else themName
			local sweep = topics > 0
			for t = 1, topics do
				if result.winners[t] ~= p2 then
					sweep = false
				end
				local prep = result.prep[p2]
				local winner = result.winners[t]
				if prep and prep[t] == 0 and winner ~= p2 and winner ~= 0 then
					table.insert(callouts, `Gaffe! {who} lost {issueName(result.topics[t])} with no prep.`)
				end
			end
			if sweep then
				table.insert(
					callouts,
					1,
					`Sweep! {who} won every topic: extra support and momentum in every battleground.`
				)
			end
		end
		revealSummary.Text = string.format(
			"National support: you %+.1f · them %+.1f.",
			result.national[you] or 0,
			result.national[them] or 0
		) .. (if #callouts > 0 then " " .. table.concat(callouts, " ") else "")
	end

	local function renderReveal(p: Payload)
		local show = p.reveal == "Resolve" or p.reveal == "Debate"
		setVisible(revealPanel, show)
		setVisible(card, not show)
		if not show then
			return
		end
		local resolving = p.reveal == "Resolve"
		setVisible(skipButton, resolving)
		if resolving then
			local seat = p.seats[p.you]
			local skipped = skipStep == p.step or (seat ~= nil and seat.skip)
			skipButton.Text = if skipped then "Waiting for opponent..." else "Skip"
			Kit.setEnabled(skipButton, not skipped)
		end
	end

	-- ------------------------------------------------------------ render: all

	local function renderCaption(now: number)
		local p = payload
		if p == nil or p.reveal ~= nil then
			return
		end
		if toast and now < toastUntil then
			caption.Text = toast
			caption.TextColor3 = Kit.colors.accent
		elseif isLocked(p) then
			caption.Text = "Locked in. Waiting for your opponent..."
			caption.TextColor3 = Kit.colors.muted
		else
			caption.Text = "Tap a state to see its polls and plan actions there"
			caption.TextColor3 = Kit.colors.muted
		end
	end

	render = function()
		local p = payload
		if p == nil or not alive then
			return
		end
		local view = p.view
		renderReveal(p)
		if p.reveal == nil then
			paintMap(view, view)
			map:select(selected)
		elseif p.reveal == "Debate" then
			paintMap(view, view)
			map:select(nil)
		end
		paintRoute(p)
		renderCard(p)
		renderPicker(p)
		renderEvent(p)
		renderPrep(p)
		renderTray(p)
		renderFeed(p)
		renderTop(ctx.now())
		renderCaption(ctx.now())
	end

	-- ------------------------------------------------------------ store updates

	selectState = function(id: string)
		if not alive then
			return
		end
		local p = payload
		if p and p.reveal ~= nil then
			return
		end
		if selected ~= id then
			chosenIssue = nil
			pickerOpen = false
		end
		selected = id
		statesOpen = false
		render()
	end

	map:onSelect(selectState)

	local function takeMessages(state: Types.State, now: number)
		local newest = Messages.newestAfter(state, seenMessageId)
		if newest ~= nil then
			toast = newest.text
			toastUntil = now + TOAST_SECONDS
			seenMessageId = newest.id
		end
		messages = state.messages
	end

	local function update(state: Types.State)
		if not alive then
			return
		end
		local p: Payload? = state.payload
		if p == nil then
			return
		end
		local now = ctx.now()
		takeMessages(state, now)
		payload = p
		relayout()

		if planning(p) then
			if draftStep ~= p.step then
				startDraft(p)
			end
			planView = p.view
			-- A rejection after Lock in: the seat is still open, so allow editing again.
			if
				lockStep == p.step
				and not p.seats[p.you].locked
				and Messages.rejectionAfter(state, lockMessageId) ~= nil
			then
				lockStep = nil
			end
		elseif draftStep ~= nil then
			-- The plan was sent and resolved: the View already includes it.
			draft = PlanDraft.new()
			draftStep = nil
		end
		if p.reveal == "Resolve" and revealStep ~= p.step then
			startResolve(p)
		elseif p.reveal == "Debate" and revealStep ~= p.step then
			startDebate(p)
		end
		render()
		if p.reveal == "Resolve" then
			tickResolve(p, now)
		elseif p.reveal == "Debate" then
			tickDebate(p, now)
		end
	end

	-- First messages already in the store are old news: no toast for them.
	seenMessageId = Messages.lastId(ctx.store.get())
	relayout(true)

	return {
		update = update,
		tick = function(now: number)
			local p = payload
			if not alive or p == nil then
				return
			end
			local before = portrait
			relayout()
			if before ~= portrait then
				render()
			end
			renderTop(now)
			if p.reveal == "Resolve" then
				tickResolve(p, now)
			elseif p.reveal == "Debate" then
				tickDebate(p, now)
			else
				renderCaption(now)
			end
			-- The timer is about to end on a plan that was never locked: lock the
			-- draft as it stands. A draft with a problem is left to the server's default.
			if planning(p) and draftStep == p.step and autoLock:due(p, now, isLocked(p)) then
				if PlanDraft.problem(config, p.view, draft) == nil then
					lockPlan()
				end
			end
		end,
		destroy = function()
			alive = false
			map:destroy()
		end,
	}
end

return Screen
