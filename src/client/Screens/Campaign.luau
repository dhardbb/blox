--!strict
-- The campaign screen, where most of a match is played (docs/UI-STYLE.md §4.5).
-- The header runs across the top with the "what to do now" line; the map is the
-- hero (left on 16:9, top on phones) with the lens chips and a "Map key" button
-- over it; beside it (below on phones) a scrolling side column and, pinned under
-- it, the action bar with Lock in. The same screen plays the resolve reveal and
-- the debate reveal.
--
-- Side column, top to bottom: the reveal panel (during reveals), a first-match
-- coach tip, the state card (only once a state is tapped), the plan list, the
-- event card, the week card, the full state list. The debate focus and a Choice
-- stance are not here: they have their own Decision screen before the plan
-- (Screens/Decision, D-044); the event card repeats the stance you took in one
-- line. The parts live in Screens/CampaignParts; this file owns the model, the
-- layout, the map, the action bar, and the routing between moments.
--
-- Reads only ctx.store (the player's own View) and sends only through ctx.net.
-- The plan is previewed with Shared/UI/PlanDraft, which mirrors the server's
-- checks; the server still validates whatever is sent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Colors = require(Shared.UI.Colors)
local MapLayout = require(Shared.UI.MapLayout)
local Plan = require(Shared.Sim.Plan)
local PlanDraft = require(Shared.UI.PlanDraft)
local Session = require(Shared.Net.Session)
local ViewModule = require(Shared.Sim.View)

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local AutoLock = require(script.Parent.Common.AutoLock)
local CoachTip = require(script.Parent.Parent.UI.CoachTip)
local EventCard = require(script.Parent.CampaignParts.EventCard)
local Kit = require(script.Parent.Parent.UI.Kit)
local Lens = require(script.Parent.Parent.Map.Lens)
local LensToggle = require(script.Parent.Parent.Map.LensToggle)
local MapInterface = require(script.Parent.Parent.Map.MapInterface)
local Messages = require(script.Parent.Common.Messages)
local Model = require(script.Parent.CampaignParts.Model)
local NodeMap = require(script.Parent.Parent.Map.NodeMap)
local PlanList = require(script.Parent.CampaignParts.PlanList)
local Reveal = require(script.Parent.CampaignParts.Reveal)
local StateCard = require(script.Parent.CampaignParts.StateCard)
local Sheet = require(script.Parent.Parent.UI.Sheet)
local SwingMarks = require(script.Parent.CampaignParts.SwingMarks)
local TopBar = require(script.Parent.CampaignParts.TopBar)
local Types = require(script.Parent.Types)
local Words = require(Shared.UI.Words.Campaign)

type View = ViewModule.View
type Payload = Session.StatePayload

local Screen = {}

local GAP = Kit.space.sm -- px between the big blocks
local LENS_H = LensToggle.HEIGHT -- px, the "Map key" button and the lens chips above the map
local MAP_SHARE = 0.62 -- share of the width the map takes on 16:9
local PORTRAIT_MAP_MAX = 0.42 -- most of the body height the map may take on phones
local BACK_SECONDS = 4 -- how long "Opponent: back" shows after a reconnect

-- LayoutOrder of each side-column panel.
local ORDER = {
	reveal = 0,
	tip = 1, -- a coach tip before anything is picked
	card = 2,
	tipAfter = 3, -- a coach tip once the plan has an action
	plan = 4,
	event = 5,
	week = 6,
	list = 7,
}

function Screen.mount(parent: Frame, ctx: Types.Ctx): Types.Screen
	local config = ctx.config
	local alive = true

	local model: Model.Model = {
		config = config,
		ctx = ctx,
		payload = nil,
		draft = PlanDraft.new(),
		draftStep = nil,
		selected = nil,
		chosenIssue = nil,
		moreIssues = false,
		pivotStage = nil,
		pivotDrop = nil,
		lockStep = nil,
		skipStep = nil,
		sortMode = "Closest",
		portrait = false,
		choice = nil,
		focus = nil,
		peekChoice = nil,
		peekFocus = nil,
		stanceMap = false,
		revealSwing = nil,
		caption = nil,
		moreActions = false,
		details = false,
		messages = {},
		render = function() end,
		selectState = function(_id: string) end,
	}

	local lockMessageId = 0 -- id of the newest message when we pressed Lock in
	local rejection: { step: number, text: string }? = nil -- the server turned the lock down
	local autoLock = AutoLock.new()
	local portrait: boolean? = nil
	local lastBodySize = Vector2.new(-1, -1)
	local away = false -- the opponent's seat was disconnected at the last look
	local backUntil = 0 -- "Opponent: back" shows until then

	-- ------------------------------------------------------------ build: frame

	local top = TopBar.new(parent, model)

	local body = Kit.box({ Name = "Body", Parent = parent })

	-- Map area: the "Map key" button beside the lens chips, then the map.
	local mapArea = Kit.box({ Name = "MapArea", Parent = body })
	local keySheet: Sheet.Sheet? = nil
	local keyButton = Kit.button("Map key", function()
		local sheet = keySheet
		if sheet then
			sheet:open()
		end
	end, {
		variant = "ghost",
		Name = "MapKey",
		Size = UDim2.fromOffset(96, LENS_H),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = mapArea,
	})
	local mapHolder = Kit.box({
		Name = "MapHolder",
		Position = UDim2.fromOffset(0, LENS_H + Kit.space.xs),
		Size = UDim2.new(1, 0, 1, -(LENS_H + Kit.space.xs)),
		Parent = mapArea,
	})
	local map: MapInterface.Map = NodeMap.new()
	map.root.AnchorPoint = Vector2.new(0.5, 0.5)
	map.root.Position = UDim2.fromScale(0.5, 0.5)
	map.root.Parent = mapHolder

	-- Side column: the scrolling panels over the pinned action bar.
	local sideColumn = Kit.box({ Name = "SideColumn", Parent = body })
	local side = Kit.new("ScrollingFrame", {
		Name = "Side",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, -(Kit.BAR_H + GAP)),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		Parent = sideColumn,
	})
	Kit.list("Vertical", GAP).Parent = side
	Kit.new("UIPadding", { PaddingRight = UDim.new(0, 10), Parent = side })

	-- Paints the map (defined below with the other map code).
	local paintMapFor: (view: View, shown: View) -> ()

	local lensToggle = LensToggle.new(mapArea, function()
		CoachTip.markSeen("campaign.lens")
		model.render()
	end)
	lensToggle.root.AnchorPoint = Vector2.new(1, 0)
	lensToggle.root.Position = UDim2.fromScale(1, 0)
	keyButton.Size = UDim2.new(1, -(LensToggle.WIDTH + Kit.space.sm), 0, LENS_H)

	-- Sends the plan as drafted (the Lock in button, or the timer about to end).
	local function lockPlan()
		local current = model.payload
		if current == nil then
			return
		end
		model.lockStep = current.step
		lockMessageId = Messages.lastId(ctx.store.get())
		model.pivotStage = nil
		autoLock:spent(current)
		ctx.net.submit(PlanDraft.payload(model.draft))
		CoachTip.markSeen("campaign.actions")
		model.render()
	end

	local bar = ActionBar.new(sideColumn, {
		primary = "Lock in",
		onPrimary = function() end,
		secondary = "+15 s",
		onSecondary = function() end,
		primaryName = "LockIn",
		secondaryName = "BankButton",
	})
	bar.primary.Activated:Connect(function()
		local p = model.payload
		if bar.primary.Active == false or p == nil then
			return
		end
		if Model.planning(p) then
			lockPlan()
		elseif p.reveal == "Resolve" then
			model.skipStep = p.step
			ctx.net.skip()
			model.render()
		end
	end)
	bar.secondary.Activated:Connect(function()
		local p = model.payload
		if bar.secondary.Active == false or p == nil or not Model.editable(model, p) then
			return
		end
		ctx.net.bank()
	end)

	local reveal = Reveal.new(side, model, ORDER.reveal, {
		-- The reveal's latest line becomes the header's now line.
		caption = function(text: string)
			model.caption = text
			top:render(ctx.now())
		end,
		paint = function(view: View)
			local p = model.payload
			if p then
				paintMapFor(p.view, view)
			end
		end,
		focus = function(id: string?)
			map:select(id)
		end,
		swing = function(swing: Model.RevealSwing?)
			model.revealSwing = swing
		end,
		map = map,
	})
	local eventCard = EventCard.new(side, model)
	local card = StateCard.new(side, model, ORDER.card, ORDER.list)
	local planList = PlanList.new(side, model, ORDER.plan)
	local weekCard = EventCard.week(side, model, ORDER.week)

	-- How to read the map: one tap away, never a caption line over it.
	local key = Sheet.new(parent, { title = "How to read the map", name = "MapKeySheet", height = 0.6 })
	local keyLines: { TextLabel } = {}
	for k = 1, 6 do
		keyLines[k] = Kit.text("", {
			Name = `KeyLine{k}`,
			LayoutOrder = k,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = key.body,
		})
	end
	keySheet = key
	local function renderKey()
		local lines = Words.key(Lens.current())
		for k, label in keyLines do
			label.Text = lines[k] or ""
			label.Visible = lines[k] ~= nil
		end
	end

	-- First-match coach tips (UI/CoachTip), one at a time at the top of the column.
	local tip: CoachTip.Tip? = nil
	local tipId: string? = nil
	local function renderTip(p: Payload)
		local want: string? = nil
		if Model.planning(p) and Model.editable(model, p) then
			-- The map first; once there is a plan, how to finish it; the lenses
			-- from week 2, when nothing is picked. Never over the state's actions.
			local order: { string } = if #model.draft.actions > 0
				then { "campaign.actions" }
				elseif model.selected then {}
				else { "campaign.map", "campaign.lens" }
			for _, id in order do
				if not CoachTip.seen(id) and (id ~= "campaign.lens" or p.view.week >= 2) then
					want = id
					break
				end
			end
		end
		local current = tip
		if current and (tipId ~= want or current.root.Parent == nil) then
			if current.root.Parent ~= nil then
				current.root:Destroy()
			end
			tip, tipId = nil, nil
		end
		if want and tip == nil then
			tip = CoachTip.show(side, {
				id = want,
				order = if want == "campaign.actions" then ORDER.tipAfter else ORDER.tip,
			})
			tipId = if tip then want else nil
		end
	end

	-- ------------------------------------------------------------ layout

	local function placeBody(isPortrait: boolean, topHeight: number)
		body.Position = UDim2.fromOffset(0, topHeight + GAP)
		body.Size = UDim2.new(1, 0, 1, -(topHeight + GAP))
		if isPortrait then
			local width = body.AbsoluteSize.X
			local height = body.AbsoluteSize.Y
			local mapHeight = math.floor(math.min(width / MapLayout.ASPECT, height * PORTRAIT_MAP_MAX))
			local areaHeight = mapHeight + LENS_H + Kit.space.xs
			mapArea.Size = UDim2.new(1, 0, 0, areaHeight)
			sideColumn.Position = UDim2.fromOffset(0, areaHeight + GAP)
			sideColumn.Size = UDim2.new(1, 0, 1, -(areaHeight + GAP))
			lastBodySize = body.AbsoluteSize
		else
			mapArea.Size = UDim2.new(MAP_SHARE, -GAP // 2, 1, 0)
			sideColumn.Position = UDim2.new(MAP_SHARE, GAP // 2, 0, 0)
			sideColumn.Size = UDim2.new(1 - MAP_SHARE, -GAP // 2, 1, 0)
		end
	end

	local function relayout(force: boolean?)
		local isPortrait = ctx.portrait()
		if isPortrait ~= portrait or force then
			portrait = isPortrait
			model.portrait = isPortrait
			placeBody(isPortrait, top:place(isPortrait))
			weekCard:setPortrait(isPortrait)
		elseif
			isPortrait and (body.AbsoluteSize.X ~= lastBodySize.X or body.AbsoluteSize.Y ~= lastBodySize.Y)
		then
			placeBody(true, top:place(true))
		end
	end

	-- ------------------------------------------------------------ the map

	-- Paints the map from `shown`'s polls with the marks for `view`.
	paintMapFor = function(view: View, shown: View)
		local colors: { Colors.RGB } = {}
		for p, player in view.players do
			colors[p] = Colors.of(player.color)
		end
		map:setView(shown, colors)
		local live = model.payload
		local event = if live then Model.shownEvent(live) else nil
		local starred = if event then PlanDraft.eventStates(event, view.issueMap) else {}
		-- Owner rings and the event's * stay in every lens; the rest is in the
		-- lens row under each label (Map/Lens, D-046).
		local marks: { [string]: any } = {}
		for _, s in view.states do
			local ring = if s.owner then Kit.playerColor(view, s.owner) else nil
			if ring or starred[s.id] then
				marks[s.id] = { ring = ring, badge = if starred[s.id] then "*" else nil }
			end
		end
		map:setLens(Lens.lines(Lens.current(), { config = config, view = shown, draft = model.draft }))
		-- A reveal shows what moved (D-042); the stance preview is on the Decision screen (D-044).
		local swing = model.revealSwing
		if swing then
			marks = SwingMarks.reveal(view, swing.net, swing.flips, marks)
		end
		map:setMarks(marks :: any)
	end

	local function paintRoute(p: Payload)
		local view = p.view
		if not Model.planning(p) then
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
		for _, stop in PlanDraft.route(view, model.draft) do
			table.insert(ids, stop.state)
			table.insert(flights, stop.flight)
		end
		if #ids < 2 then
			map:setRoute({}, {})
		else
			map:setRoute(ids, flights)
		end
	end

	-- ------------------------------------------------------------ the action bar

	local function opponentText(p: Payload, now: number): string?
		local them = Model.opponentOf(p.view)
		local seat = p.seats[them]
		if seat == nil then
			return nil
		elseif not seat.connected then
			return "Opponent: disconnected"
		elseif now < backUntil then
			return "Opponent: back"
		elseif p.stage == "Input" then
			return if seat.locked then "Opponent: locked in" else "Opponent: thinking"
		elseif p.reveal == "Resolve" and seat.skip then
			return "Opponent: skipped"
		end
		return "Opponent: watching"
	end

	-- The plan in one line, so a phone sees it without scrolling.
	local function planStatus(): string
		local actions = model.draft.actions
		if #actions == 0 then
			return "Nothing planned yet"
		end
		return `Plan: {Words.planLine(actions)}`
	end

	-- Why the plan can't lock in. Money problems say what the plan costs and what
	-- you have, from the plan and the View (the server sends only the code).
	local function problemText(p: Payload, reason: string): string
		if reason == Plan.Reason.NotEnoughMoney then
			return PlanDraft.moneyText(config, p.view, model.draft)
		end
		return ctx.net.reasonText(reason)
	end

	local function renderBar(p: Payload, now: number)
		local primary = bar.primary
		bar:setOpponent(opponentText(p, now))
		if Model.planning(p) then
			primary.Name = "LockIn"
			primary.Visible = true
			local canEdit = Model.editable(model, p)
			local problem = PlanDraft.problem(config, p.view, model.draft)
			if not canEdit then
				bar:setPrimary("Locked in", false)
				bar:setStatus("Locked in · waiting for opponent", "ok")
			elseif problem then
				bar:setPrimary(PlanDraft.shortProblem(problem), false)
				bar:setStatus(problemText(p, problem), "bad")
			else
				-- An empty plan still locks in with one tap: it skips the week.
				bar:setPrimary(if #model.draft.actions == 0 then "Skip this week" else "Lock in", true)
				local turnedDown = rejection
				if turnedDown and turnedDown.step == p.step then
					bar:setStatus(turnedDown.text, "bad")
				else
					bar:setStatus(planStatus(), "muted")
				end
			end
			local seat = p.seats[p.you]
			local bank = if seat then seat.bank else 0
			local chunk = config.TIME_BANK_CHUNK
			if canEdit and bank >= chunk then
				bar:setSecondary(`+{chunk} s`, true)
			else
				bar:setSecondary(nil, false)
			end
		elseif p.reveal == "Resolve" then
			primary.Name = "SkipButton"
			primary.Visible = true
			local seat = p.seats[p.you]
			local skipped = model.skipStep == p.step or (seat ~= nil and seat.skip)
			bar:setPrimary(if skipped then "Waiting for opponent…" else "Skip", not skipped)
			bar:setSecondary(nil, false)
			bar:setStatus(reveal:status(p), "muted")
		else
			-- The debate (and any step with nothing to press) cannot be skipped.
			primary.Name = "SkipButton"
			primary.Visible = false
			bar:setSecondary(nil, false)
			bar:setStatus(if p.reveal == "Debate" then reveal:status(p) else "Campaign", "muted")
		end
		parent:SetAttribute("PrimaryOptional", not primary.Visible)
	end

	-- ------------------------------------------------------------ render

	local function render()
		local p = model.payload
		if p == nil or not alive then
			return
		end
		local view = p.view
		local now = ctx.now()
		if p.reveal == nil then
			model.revealSwing = nil
			model.caption = nil
		end
		reveal:render(p)
		card:render(p)
		eventCard:render(p, ORDER.event)
		if p.reveal == nil or p.reveal == "Debate" then
			paintMapFor(view, view)
			map:select(model.selected)
		end
		paintRoute(p)
		planList:render(p)
		weekCard:render(p)
		renderTip(p)
		renderKey()
		lensToggle.refresh()
		renderBar(p, now)
		if top:render(now) then
			relayout(true)
		end
	end
	model.render = render

	-- ------------------------------------------------------------ plan steps

	local function startDraft(p: Payload)
		model.draft = PlanDraft.new()
		model.draftStep = p.step
		model.chosenIssue = nil
		model.moreIssues = false
		model.pivotStage = nil
		model.pivotDrop = nil
		-- Each week starts on the map: no card until a state is tapped.
		model.selected = nil
		model.moreActions = false
	end

	-- Tapping a state opens its card; tapping the selected state again closes it.
	model.selectState = function(id: string)
		if not alive then
			return
		end
		local p = model.payload
		local planning = p ~= nil and Model.planning(p)
		local closing = model.selected == id and (planning or p == nil)
		model.chosenIssue = nil
		model.moreIssues = false
		model.pivotStage = nil
		model.selected = if closing then nil else id
		CoachTip.markSeen("campaign.map")
		-- On a phone the list covers the card: close it. On 16:9 it stays open.
		if model.portrait then
			card:closeList()
		end
		render()
		map:select(model.selected)
	end

	map:onSelect(function(id: string)
		model.selectState(id)
	end)

	local function watchSeat(p: Payload, now: number)
		local seat = p.seats[Model.opponentOf(p.view)]
		local gone = seat ~= nil and not seat.connected
		if away and not gone then
			backUntil = now + BACK_SECONDS
		end
		away = gone
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
		model.messages = state.messages
		model.payload = p
		watchSeat(p, now)
		relayout()

		if Model.planning(p) then
			if model.draftStep ~= p.step then
				startDraft(p)
			end
			reveal:remember(p.view)
			-- A rejection after Lock in: the seat is still open, so allow editing again.
			if model.lockStep == p.step and not p.seats[p.you].locked then
				local turnedDown = Messages.rejectionAfter(state, lockMessageId)
				if turnedDown ~= nil then
					model.lockStep = nil
					rejection = {
						step = p.step,
						text = if turnedDown.reason
							then problemText(p, turnedDown.reason)
							else turnedDown.text,
					}
				end
			end
		elseif model.draftStep ~= nil then
			-- The plan was sent and resolved: the View already includes it.
			model.draft = PlanDraft.new()
			model.draftStep = nil
		end
		render()
		reveal:tick(p, now)
		renderBar(p, now)
	end

	relayout(true)

	return {
		update = update,
		tick = function(now: number)
			local p = model.payload
			if not alive or p == nil then
				return
			end
			local before = portrait
			relayout()
			if before ~= portrait then
				render()
			end
			watchSeat(p, now)
			if top:render(now) then
				relayout(true)
			end
			reveal:tick(p, now)
			planList:tick(now)
			renderBar(p, now)
			-- The timer is about to end on a plan that was never locked: lock the
			-- draft as it stands. A draft with a problem is left to the server's default.
			if
				Model.planning(p)
				and model.draftStep == p.step
				and autoLock:due(p, now, Model.isLocked(model, p))
			then
				if PlanDraft.problem(config, p.view, model.draft) == nil then
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
