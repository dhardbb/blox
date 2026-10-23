--!strict
-- The campaign screen, where most of a match is played (UI overhaul §3.4). The
-- header runs across the top; the map fills the main area (left on 16:9, top on
-- phones); beside it (below on phones) a scrolling side column and, pinned under
-- it, the action bar with Lock in. The same screen plays the resolve reveal and
-- the debate reveal.
--
-- Side column, top to bottom: the reveal panel (during reveals), the event card
-- (first in Choice weeks), the state card, the event card (other weeks), debate
-- prep (the week before a debate), the plan list, the week card. The parts live
-- in Screens/CampaignParts; this file owns the model, the layout, the map, the
-- action bar, and the routing between moments.
--
-- Reads only ctx.store (the player's own View) and sends only through ctx.net.
-- The plan is previewed with Shared/UI/PlanDraft, which mirrors the server's
-- checks; the server still validates whatever is sent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Colors = require(Shared.UI.Colors)
local Explain = require(Shared.UI.Explain)
local MapLayout = require(Shared.UI.MapLayout)
local Plan = require(Shared.Sim.Plan)
local PlanDraft = require(Shared.UI.PlanDraft)
local Session = require(Shared.Net.Session)
local SharedTypes = require(Shared.Types)
local Swing = require(Shared.UI.Swing)
local ViewModule = require(Shared.Sim.View)

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local AutoLock = require(script.Parent.Common.AutoLock)
local EventCard = require(script.Parent.CampaignParts.EventCard)
local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.Parent.Map.MapInterface)
local Messages = require(script.Parent.Common.Messages)
local Model = require(script.Parent.CampaignParts.Model)
local NodeMap = require(script.Parent.Parent.Map.NodeMap)
local PlanList = require(script.Parent.CampaignParts.PlanList)
local Prep = require(script.Parent.CampaignParts.Prep)
local Reveal = require(script.Parent.CampaignParts.Reveal)
local StateCard = require(script.Parent.CampaignParts.StateCard)
local SwingMarks = require(script.Parent.CampaignParts.SwingMarks)
local TopBar = require(script.Parent.CampaignParts.TopBar)
local Types = require(script.Parent.Types)

type View = ViewModule.View
type Payload = Session.StatePayload

local Screen = {}

local GAP = Kit.space.sm -- px between the big blocks
local CAPTION_H = 20 -- px, the line above the map
local MAP_SHARE = 0.62 -- share of the width the map takes on 16:9
local PORTRAIT_MAP_MAX = 0.42 -- most of the body height the map may take on phones
local MOMENTUM_ARROW = 0.5 -- momentum lead that earns the leader a ▲ on the map (display only)
local BACK_SECONDS = 4 -- how long "Opponent: back" shows after a reconnect

-- LayoutOrder of each side-column panel.
local ORDER = {
	reveal = 0,
	choiceEvent = 1, -- the event card in a Choice week: the answer comes first
	prep = 2, -- only shown when prep is due; above the tall state card so it is seen (B2)
	card = 3,
	event = 4,
	plan = 5,
	week = 6,
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
		peekChoice = nil,
		stanceMap = false,
		revealSwing = nil,
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

	-- Map area: a caption line, then the map.
	local mapArea = Kit.box({ Name = "MapArea", Parent = body })
	local caption = Kit.text("", {
		Name = "Caption",
		Size = UDim2.new(1, 0, 0, CAPTION_H),
		TextSize = Kit.size.caption,
		TextScaled = true,
		TextColor3 = Kit.colors.muted,
		Parent = mapArea,
	})
	local mapHolder = Kit.box({
		Name = "MapHolder",
		Position = UDim2.fromOffset(0, CAPTION_H + Kit.space.xs),
		Size = UDim2.new(1, 0, 1, -(CAPTION_H + Kit.space.xs)),
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
		model.render()
	end

	local bar = ActionBar.new(sideColumn, {
		primary = "Lock in",
		onPrimary = function() end,
		secondary = "Bank",
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
		caption = function(text: string)
			caption.Text = text
			caption.TextColor3 = Kit.colors.text
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
	})
	local eventCard = EventCard.new(side, model)
	local card = StateCard.new(side, model, ORDER.card)
	local prep = Prep.new(side, model, ORDER.prep)
	local planList = PlanList.new(side, model, ORDER.plan)
	local weekCard = EventCard.week(side, model, ORDER.week)

	-- ------------------------------------------------------------ layout

	local function placeBody(isPortrait: boolean, topHeight: number)
		body.Position = UDim2.fromOffset(0, topHeight + GAP)
		body.Size = UDim2.new(1, 0, 1, -(topHeight + GAP))
		if isPortrait then
			local width = body.AbsoluteSize.X
			local height = body.AbsoluteSize.Y
			local mapHeight = math.floor(math.min(width / MapLayout.ASPECT, height * PORTRAIT_MAP_MAX))
			local areaHeight = mapHeight + CAPTION_H + Kit.space.xs
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
		local starred = if event then PlanDraft.eventStates(event) else {}
		local me, rival = view.you, Model.opponentOf(view)
		-- Marks carry `arrow` for the momentum leader; a map that does not draw
		-- arrows yet ignores the field.
		local marks: { [string]: any } = {}
		for _, s in view.states do
			local parts: { string } = {}
			if s.isHome and s.owner then
				table.insert(parts, "H")
			end
			if s.battleground then
				table.insert(parts, "B")
			end
			local units = s.gotv + Model.plannedUnits(model, s.id)
			if units > 0 then
				table.insert(parts, `G{units}`)
			end
			-- Their ground game, where your polls saw some (D-044).
			local scout = Explain.scoutOf(view, s.id)
			local theirs = if scout then scout.gotv[rival] or 0 else 0
			if theirs > 0 then
				table.insert(parts, `opp G{theirs}`)
			end
			if starred[s.id] then
				table.insert(parts, "*")
			end
			local ring = if s.owner then Kit.playerColor(view, s.owner) else nil
			local lead = (s.momentum[me] or 0) - (s.momentum[rival] or 0)
			local leader = if lead >= MOMENTUM_ARROW then me elseif lead <= -MOMENTUM_ARROW then rival else nil
			if ring or #parts > 0 or leader then
				marks[s.id] = {
					ring = ring,
					badge = if #parts > 0 then table.concat(parts, " ") else nil,
					arrow = if leader then "up" else nil,
					arrowColor = if leader then Kit.playerColor(view, leader) else nil,
				}
			end
		end
		-- A reveal shows what moved; a Choice week previews the stance (D-042).
		local swing = model.revealSwing
		local stance: SharedTypes.Choice? = if live then Model.previewStance(model, live) else nil
		if swing then
			marks = SwingMarks.reveal(view, swing.net, swing.flips, marks)
		elseif stance then
			marks = SwingMarks.preview(view, Swing.stance(config, view, stance), marks)
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

	local function planStatus(p: Payload): string
		local view = p.view
		local cost = PlanDraft.cost(config, view, model.draft)
		local profile = PlanDraft.profile(config, view)
		local _, cash = PlanDraft.remaining(config, view, model.draft)
		local text = `AP {cost.ap}/{profile.apPerWeek} · {Model.money(cash)} left · {Model.plural(
			cost.flights,
			"flight"
		)}`
		local prepText = prep:summary()
		if prepText then
			text ..= ` · {prepText}`
		end
		return text
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
				bar:setPrimary("Lock in", true)
				local turnedDown = rejection
				if turnedDown and turnedDown.step == p.step then
					bar:setStatus(turnedDown.text, "bad")
				else
					bar:setStatus(planStatus(p), "muted")
				end
			end
			local seat = p.seats[p.you]
			local bank = if seat then seat.bank else 0
			local chunk = config.TIME_BANK_CHUNK
			if canEdit and bank >= chunk then
				bar:setSecondary(`Bank +{chunk}s`, true)
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

	local function renderCaption(p: Payload)
		if p.reveal ~= nil then
			return
		end
		caption.TextColor3 = Kit.colors.muted
		local stance = Model.previewStance(model, p)
		if stance then
			caption.Text =
				`Map: stance {stance} · badge = support for you · red = a loss · FLIP = poll leader changes`
		elseif Model.planning(p) and Model.isLocked(model, p) then
			caption.Text = "Locked in · waiting for opponent"
		elseif Model.planning(p) then
			caption.Text = "Tap a state to see its polls and plan actions there"
		else
			caption.Text = ""
		end
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
		end
		reveal:render(p)
		card:render(p)
		local choosing = Model.planning(p) and PlanDraft.isChoiceWeek(view)
		eventCard:render(p, if choosing then ORDER.choiceEvent else ORDER.event)
		-- The open event card in a Choice week turns the map into the stance preview.
		model.stanceMap = choosing and eventCard:showsStances()
		if not model.stanceMap then
			model.peekChoice = nil
		end
		if p.reveal == nil or p.reveal == "Debate" then
			paintMapFor(view, view)
			map:select(model.selected)
		end
		paintRoute(p)
		prep:render(p)
		planList:render(p)
		weekCard:render(p)
		renderBar(p, now)
		if top:render(now) then
			relayout(true)
		end
		renderCaption(p)
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
		local view = p.view
		if Model.prepWanted(view) then
			local points = PlanDraft.profile(config, view).debatePrep
			local saved = view.debatePrep
			if saved and #saved == config.DEBATE_TOPICS then
				model.draft.prep = table.clone(saved)
			else
				model.draft.prep = Plan.defaultPrep(config, points)
			end
		end
		-- The hedge (C) is what the server assumes for a missing stance, so it starts selected.
		model.draft.choice = if PlanDraft.isChoiceWeek(view) then "C" else nil
		if model.selected == nil then
			model.selected = view.players[view.you].location
		end
	end

	model.selectState = function(id: string)
		if not alive then
			return
		end
		if model.selected ~= id then
			model.chosenIssue = nil
			model.moreIssues = false
			model.pivotStage = nil
		end
		model.selected = id
		-- On a phone the list covers the card: close it. On 16:9 it stays open.
		if model.portrait then
			card:closeList()
		end
		render()
		map:select(id)
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
