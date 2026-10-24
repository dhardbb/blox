--!strict
-- The Decision screen (D-044): one decision on its own, with its own timer,
-- before the week's plan. The humans asked for it after playtest 3: "On weeks
-- with debates or event choices, they should be on a separate screen before the
-- week decisions with a separate timer."
--
--   Stance  in a Choice week: take a stance (the event card's chips, EventCard).
--   (The debate focus it also held is gone: debates have their own screen,
--   Screens/Debate, D-072.)
--
-- Layout (docs/UI-STYLE.md §4.4): the Campaign header (the week and the event or
-- "Debate prep", the countdown, the score on wide screens, and the "what to do
-- now" line), the map (left on 16:9, top on phones) previewing the selected
-- stance with a two-dot key over it, and one panel with the pinned action bar
-- under it: the question, the three stances as big chips with what each does in
-- a few words, and "Why?" for the rest. On a phone every option is on the first screen. Nothing else: no state
-- card, plan list or week card.
--
-- Motion and sound (docs/DESIGN.md D-053): a new decision's options pop in one
-- after another; a choice the server turns down shakes the action bar with the
-- "error" cue; the opponent's line names them ("Rex: thinking…", "Rex: locked
-- in ✓", which rises and pops in).
--
-- Reads only ctx.store (the player's own View) and sends only through ctx.net:
-- { choice = "A"|"B"|"C" }. The server validates it (Sim/Decision); a timer
-- that runs out sends the selection if there is one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Colors = require(Shared.UI.Colors)
local Session = require(Shared.Net.Session)
local SharedTypes = require(Shared.Types)
local Swing = require(Shared.UI.Swing)
local ViewModule = require(Shared.Sim.View)

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local Audio = require(script.Parent.Parent.UI.Audio)
local AutoLock = require(script.Parent.Common.AutoLock)
local CoachTip = require(script.Parent.Parent.UI.CoachTip)
local EventCard = require(script.Parent.CampaignParts.EventCard)
local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.Parent.Map.MapInterface)
local MapPins = require(script.Parent.Parent.Map.Pins)
local Messages = require(script.Parent.Common.Messages)
local Model = require(script.Parent.CampaignParts.Model)
local Motion = require(script.Parent.Parent.UI.Motion)
local NodeMap = require(script.Parent.Parent.Map.NodeMap)
local PlanDraft = require(Shared.UI.PlanDraft)
local SwingMarks = require(script.Parent.CampaignParts.SwingMarks)
local TopBar = require(script.Parent.CampaignParts.TopBar)
local Types = require(script.Parent.Types)

type View = ViewModule.View
type Payload = Session.StatePayload

local Screen = {}

local GAP = Kit.space.sm -- px between the big blocks
local CAPTION_H = 20 -- px, the map key above the map
local DOT = 12 -- px, a key dot
local MAP_SHARE = 0.55 -- share of the width the map takes on 16:9 (the panel gets more room than on the plan screen)
local PORTRAIT_MAP_MAX = 0.3 -- most of the body height the map may take on phones (the options come first)
local LOCKED_RISE = 4 -- px, the opponent's "locked in ✓" line rises this far

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

	local lockMessageId = 0
	local rejection: { step: number, text: string }? = nil
	local autoLock = AutoLock.new()
	local portrait: boolean? = nil
	local lastBodySize = Vector2.new(-1, -1)

	-- ------------------------------------------------------------ build

	local top = TopBar.new(parent, model)
	local body = Kit.box({ Name = "Body", Parent = parent })

	local mapArea = Kit.box({ Name = "MapArea", Parent = body })
	-- The map key: two rings, no sentence ("○ helps you  ○ hurts you"), in the
	-- green and orange the map outlines those states in (D-079).
	local legend = Kit.box({ Name = "MapLegend", Size = UDim2.new(1, 0, 0, CAPTION_H), Parent = mapArea })
	Kit.dataColor(legend)
	local legendList = Kit.list("Horizontal", Kit.space.xs)
	legendList.VerticalAlignment = Enum.VerticalAlignment.Center
	legendList.Parent = legend
	local function keyItem(order: number, name: string): (Frame, TextLabel)
		local dot = Kit.new("Frame", {
			Name = `{name}Dot`,
			LayoutOrder = order,
			Size = UDim2.fromOffset(DOT, DOT),
			BorderSizePixel = 0,
			Parent = legend,
		}) :: Frame
		Kit.round().Parent = dot
		dot.BackgroundTransparency = 1
		local ring = Kit.stroke(Kit.colors.good, 2)
		ring.Name = "Ring"
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = dot
		local label = Kit.text("", {
			Name = `{name}Text`,
			LayoutOrder = order + 1,
			Size = UDim2.fromOffset(0, CAPTION_H),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = Kit.size.caption,
			TextWrapped = false,
			TextColor3 = Kit.colors.muted,
			Parent = legend,
		})
		Kit.new("UIPadding", { PaddingRight = UDim.new(0, Kit.space.sm), Parent = label })
		return dot, label
	end
	local gainDot, gainText = keyItem(1, "Gain")
	local lossDot, lossText = keyItem(3, "Loss")
	lossDot.BackgroundColor3 = Kit.colors.loss
	local lossRing = lossDot:FindFirstChild("Ring") :: UIStroke
	lossRing.Color = Kit.colors.loss
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

	local eventCard = EventCard.new(side, model)

	-- The first-match coach tip for this decision, under the options (so they
	-- all stay on the first screen of a phone).
	local tip: CoachTip.Tip? = nil
	local function renderTip(p: Payload)
		local kind = Model.deciding(p)
		local want = if kind == "Stance" then "decision.stance" else nil
		if want and Model.editable(model, p) and tip == nil and not CoachTip.seen(want) then
			tip = CoachTip.show(side, { id = want, order = 2 })
		end
	end

	-- What Lock in would send now, or nil when nothing is picked yet.
	local function selection(p: Payload): any?
		if Model.deciding(p) == "Stance" then
			return { choice = model.choice or "C" }
		end
		return nil
	end

	local function lock()
		local p = model.payload
		if p == nil then
			return
		end
		local input = selection(p)
		if input == nil then
			return
		end
		model.lockStep = p.step
		lockMessageId = Messages.lastId(ctx.store.get())
		autoLock:spent(p)
		ctx.net.submit(input)
		model.render()
	end

	local bar = ActionBar.new(sideColumn, {
		primary = "Lock in",
		onPrimary = function() end,
		primaryName = "LockIn",
	})
	bar.primary.Activated:Connect(function()
		local p = model.payload
		if bar.primary.Active == false or p == nil or not Model.editable(model, p) then
			return
		end
		lock()
	end)

	-- ------------------------------------------------------------ layout

	local function placeBody(isPortrait: boolean, topHeight: number)
		body.Position = UDim2.fromOffset(0, topHeight + GAP)
		body.Size = UDim2.new(1, 0, 1, -(topHeight + GAP))
		if isPortrait then
			local width = body.AbsoluteSize.X
			local height = body.AbsoluteSize.Y
			local maxHeight = height * PORTRAIT_MAP_MAX
			local mapHeight = math.floor(math.min(width / map:aspectFor(width, maxHeight), maxHeight))
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
		elseif
			isPortrait and (body.AbsoluteSize.X ~= lastBodySize.X or body.AbsoluteSize.Y ~= lastBodySize.Y)
		then
			placeBody(true, top:place(true))
		end
	end

	-- ------------------------------------------------------------ render

	local function paintMap(p: Payload)
		local view = p.view
		local colors: { Colors.RGB } = {}
		for q, player in view.players do
			colors[q] = Colors.of(player.color)
		end
		map:setView(view, colors)
		local marks: { [string]: any } = {}
		for _, s in view.states do
			if s.owner then
				marks[s.id] = { ring = Kit.playerColor(view, s.owner) }
			end
		end
		local stance: SharedTypes.Choice? = Model.previewStance(model, p)
		gainDot.BackgroundColor3 = Kit.colors.good
		lossDot.Visible = stance ~= nil
		lossText.Visible = stance ~= nil
		gainDot.Visible = stance ~= nil
		if stance then
			marks = SwingMarks.preview(view, Swing.stance(config, view, stance), marks)
			gainText.Text = "Helps you"
			lossText.Text = "Hurts you"
		else
			gainText.Text = ""
		end
		map:setMarks(marks :: any)
		map:setRoute({}, {})
		map:setPins(MapPins.of(config, view))
	end

	local opponentWas: string? = nil -- the opponent's state at the last bar render

	local function renderBar(p: Payload)
		local them = Model.opponentOf(p.view)
		local seat = p.seats[them]
		local state = if seat == nil
			then nil
			elseif not seat.connected then "disconnected"
			elseif seat.locked then Model.OPPONENT_LOCKED
			else "thinking"
		local name = Model.firstName(config, p.view, them)
		bar:setOpponent(if state then Model.opponentLine(name, state, ctx.now(), Motion.reduced()) else nil)
		if state ~= opponentWas then
			if state == Model.OPPONENT_LOCKED and opponentWas ~= nil then
				-- They just locked in: the line rises into place and pops.
				Motion.enter(bar.opponent, LOCKED_RISE)
				Motion.pop(bar.opponent)
			end
			opponentWas = state
		end
		bar:setSecondary(nil, false)
		local kind = Model.deciding(p)
		if kind == nil then
			bar:setPrimary("Lock in", false)
			bar:setStatus("Waiting for the next step", "muted")
			return
		end
		if not Model.editable(model, p) then
			bar:setPrimary("Locked in", false)
			bar:setStatus("Locked in · waiting for opponent", "ok")
			return
		end
		local turnedDown = rejection
		if turnedDown and turnedDown.step == p.step then
			bar:setPrimary("Lock in", true)
			bar:setStatus(turnedDown.text, "bad")
		else
			bar:setPrimary("Lock in", true)
			bar:setStatus(`Stance {model.choice or "C"} · kept secret`, "muted")
		end
	end

	local function render()
		local p = model.payload
		if p == nil or not alive then
			return
		end
		local kind = Model.deciding(p)
		eventCard:render(p, 1)
		eventCard.root.Visible = kind == "Stance" and eventCard.root.Visible
		model.stanceMap = kind == "Stance" and eventCard:showsStances()
		if not model.stanceMap then
			model.peekChoice = nil
		end
		renderTip(p)
		paintMap(p)
		renderBar(p)
		if top:render(ctx.now()) then
			relayout(true)
		end
	end
	model.render = render

	local function update(state: Types.State)
		if not alive then
			return
		end
		local p: Payload? = state.payload
		if p == nil then
			return
		end
		model.messages = state.messages
		model.payload = p
		relayout()
		local fresh = false
		local refused = false
		if Model.deciding(p) ~= nil and model.draftStep ~= p.step then
			fresh = true
			-- A new decision: the hedge (C), the server's default, starts selected.
			model.draftStep = p.step
			model.choice = if Model.deciding(p) == "Stance" then "C" else nil
			model.peekChoice = nil
		end
		-- A rejection after Lock in: the seat is still open, so allow another try.
		local own = p.seats[p.you]
		if model.lockStep == p.step and not (own ~= nil and own.locked) then
			local turnedDown = Messages.rejectionAfter(state, lockMessageId)
			if turnedDown ~= nil then
				model.lockStep = nil
				rejection = { step = p.step, text = ctx.net.reasonText(turnedDown.reason) }
				refused = true
			end
		end
		render()
		if fresh then
			-- A new decision: its options pop in one after another.
			local options: { GuiObject } = {}
			for _, inst in side:GetDescendants() do
				local isOption = string.match(inst.Name, "^Choice[ABC]$") ~= nil
				if isOption and inst:IsA("GuiButton") and (inst :: GuiButton).Visible then
					table.insert(options, inst :: GuiButton)
				end
			end
			Motion.stagger(options, function(option: GuiObject, _index: number, delay: number)
				Motion.pop(option, Motion.POP_FROM, delay)
			end)
		end
		if refused then
			Motion.shake(bar.root)
			Motion.flash(bar.status, Kit.colors.text)
			Audio.play("error")
		end
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
			if top:render(now) then
				relayout(true)
			end
			renderBar(p)
			-- The timer is about to end: send what is picked.
			if Model.deciding(p) ~= nil and autoLock:due(p, now, Model.isLocked(model, p)) then
				if selection(p) ~= nil then
					lock()
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
