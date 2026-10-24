--!strict
-- The Debate screen (docs/DESIGN.md D-072): a debate is its own event, three
-- live rounds on a stage. The designers asked for it after playtest feedback:
-- debates "kinda feel like glorified stance questions rather than their own
-- thing."
--
--   intro    the stage, the three topics (Show, TIMER_DEBATE_INTRO)
--   round    pick Defend, Attack or Pivot, maybe stake the Zinger (Input, 15 s)
--   clash    both moves flip, the counter, the stamp, the map moves (Reveal)
--   verdict  who won the crowd, a line per round (Reveal, skippable)
--
-- Layout (docs/UI-STYLE.md §4.4, like the Decision screen): the Campaign
-- header, the map (left on 16:9, top on phones) showing what the held or
-- picked move would land on, or what the clash moved, and one column with the
-- stage, the moves (or the clash) and the pinned action bar.
--
--   phone 390 wide                       wide / iPad
--   Week 4 · Debate          0:12        Week 4 · Debate round 1 of 3   0:12
--   ▌Pick Defend, Attack or Pivot        ▌Pick Defend, Attack or Pivot
--   [         map (25%)         ]        [   map   ] | (DO) Dana ◀▓▓|░░▶ Rex (RC)
--   (DO) Dana ◀▓▓▓|░░░▶ Rex (RC)         [   map   ] | ROUND 1 OF 3 · JOBS ...
--   ROUND 1 OF 3 · JOBS "..."            [   map   ] | [Defend 6] [Attack 2] ...
--   [Defend 6 · vs D +4 ...]             [   map   ] | (Stake Zinger) (Why? +)
--   [Attack 2 ...] [Pivot → Safety 3]    ---------------------------------------
--   (Stake Zinger: a win counts ×2)      Rex: thinking…            [ Lock in ]
--   Rex: thinking…        [ Lock in ]
--
-- Reads only ctx.store (the player's own View) and sends only through ctx.net:
-- { move = "Defend"|"Attack"|"Pivot", zinger = boolean }, or a skip on the
-- verdict. The server validates it (Sim/Debate); a timer that runs out sends
-- the picked move if there is one, else the server plays a canned answer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Colors = require(Shared.UI.Colors)
local MapLayout = require(Shared.UI.MapLayout)
local SharedTypes = require(Shared.Types)
local Swing = require(Shared.UI.Swing)

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local Audio = require(script.Parent.Parent.UI.Audio)
local AutoLock = require(script.Parent.Common.AutoLock)
local Clash = require(script.Parent.DebateParts.Clash)
local CoachTip = require(script.Parent.Parent.UI.CoachTip)
local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.Parent.Map.MapInterface)
local Messages = require(script.Parent.Common.Messages)
local Model = require(script.Parent.CampaignParts.Model)
local Moves = require(script.Parent.DebateParts.Moves)
local Motion = require(script.Parent.Parent.UI.Motion)
local NodeMap = require(script.Parent.Parent.Map.NodeMap)
local PlanDraft = require(Shared.UI.PlanDraft)
local Stage = require(script.Parent.DebateParts.Stage)
local SwingMarks = require(script.Parent.CampaignParts.SwingMarks)
local TopBar = require(script.Parent.CampaignParts.TopBar)
local Types = require(script.Parent.Types)

type Payload = Model.Payload

local Screen = {}

local GAP = Kit.space.sm -- px between the big blocks
local MAP_SHARE = 0.5 -- share of the width the map takes on 16:9
local PORTRAIT_MAP_MAX = 0.24 -- most of the body height the map may take on phones (the moves come first; under about 170 px a top-row tag pokes out)
local LOCKED_RISE = 4 -- px, the opponent's "locked in ✓" line rises this far
local MAP_INSET = 24 -- px above the map (room for a top-row state's tag)

-- The first debate of this session tags the safe moves (the coach tip says why).
local safeWeek: string? = nil

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
	local pick: Moves.Pick = { move = nil, held = nil, zinger = false, showSafe = false }

	local lockMessageId = 0
	local rejection: { step: number, text: string }? = nil
	local autoLock = AutoLock.new()
	local portrait: boolean? = nil
	local lastBodySize = Vector2.new(-1, -1)

	-- ------------------------------------------------------------ build

	local top = TopBar.new(parent, model)
	local body = Kit.box({ Name = "Body", Parent = parent })
	local mapArea = Kit.box({ Name = "MapArea", Parent = body })
	-- A margin above the map, so a tag on a top-row state stays inside it.
	local mapHolder = Kit.box({
		Name = "MapHolder",
		Position = UDim2.fromOffset(0, MAP_INSET),
		Size = UDim2.new(1, 0, 1, -MAP_INSET),
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

	local stage = Stage.new(side, model, 1)
	local moves = Moves.new(side, model, pick, 2)
	local clash = Clash.new(side, model, 3)

	local tip: CoachTip.Tip? = nil
	local function renderTip(p: Payload)
		if not Model.debating(p) or not Model.editable(model, p) or tip ~= nil then
			return
		end
		local want = if pick.showSafe then "debate.safe" else "debate.moves"
		if not CoachTip.seen(want) then
			tip = CoachTip.show(side, { id = want, order = 4 })
		end
	end

	local function selection(): any?
		if pick.move == nil then
			return nil
		end
		return { move = pick.move, zinger = pick.zinger }
	end

	local function lock()
		local p = model.payload
		local input = selection()
		if p == nil or input == nil then
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
		if bar.primary.Active == false or p == nil then
			return
		end
		if Model.debateReveal(p) == "Verdict" then
			model.skipStep = p.step
			ctx.net.skip()
			model.render()
			return
		end
		if Model.editable(model, p) then
			lock()
		end
	end)

	-- ------------------------------------------------------------ layout

	local function placeBody(isPortrait: boolean, topHeight: number)
		body.Position = UDim2.fromOffset(0, topHeight + GAP)
		body.Size = UDim2.new(1, 0, 1, -(topHeight + GAP))
		if isPortrait then
			local width = body.AbsoluteSize.X
			local height = body.AbsoluteSize.Y
			local mapHeight = math.floor(math.min(width / MapLayout.ASPECT, height * PORTRAIT_MAP_MAX))
				+ MAP_INSET
			mapArea.Size = UDim2.new(1, 0, 0, mapHeight)
			sideColumn.Position = UDim2.fromOffset(0, mapHeight + GAP)
			sideColumn.Size = UDim2.new(1, 0, 1, -(mapHeight + GAP))
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

	local function paintMap(p: Payload, round: any?)
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
		local reveal = Model.debateReveal(p)
		if reveal == "Clash" and round then
			marks = SwingMarks.reveal(view, Swing.net(round.moves, view), Swing.flips(round.flips), marks)
		elseif reveal == "Verdict" then
			local result = view.debates[#view.debates]
			if result then
				marks = SwingMarks.reveal(
					view,
					Swing.debateNet(config, view, result, #(result.rounds or {})),
					Swing.flips(result.flips),
					marks
				)
			end
		elseif Model.debating(p) then
			local board = Swing.debateBoard(config, view)
			local shown: SharedTypes.DebateMove? = pick.held or pick.move
			if board then
				if shown then
					for k, row in board.rows do
						if row.move == shown then
							marks = SwingMarks.preview(view, board.rows[k], marks)
						end
					end
				else
					-- Nothing picked yet: light the topic's states.
					local set: { [string]: number } = {}
					for _, id in board.topicStates do
						set[id] = config.DEBATE_ROUND_WIN
					end
					marks = SwingMarks.preview(view, { effects = set, flips = {} }, marks)
				end
			end
		end
		map:setMarks(marks :: any)
		map:setRoute({}, {})
	end

	local opponentWas: string? = nil

	local function renderBar(p: Payload)
		local them = Model.opponentOf(p.view)
		local seat = p.seats[them]
		local reveal = Model.debateReveal(p)
		local state = if seat == nil
			then nil
			elseif not seat.connected then "disconnected"
			elseif reveal == "Verdict" and seat.skip then "skipped"
			elseif reveal == nil and seat.locked then Model.OPPONENT_LOCKED
			elseif reveal == nil then "thinking"
			else nil
		local name = Model.firstName(config, p.view, them)
		bar:setOpponent(if state then Model.opponentLine(name, state, ctx.now(), Motion.reduced()) else nil)
		if state ~= opponentWas then
			if state == Model.OPPONENT_LOCKED and opponentWas ~= nil then
				Motion.enter(bar.opponent, LOCKED_RISE)
				Motion.pop(bar.opponent)
			end
			opponentWas = state
		end
		bar:setSecondary(nil, false)
		if reveal == "Verdict" then
			local skipped = model.skipStep == p.step or (p.seats[p.you] ~= nil and p.seats[p.you].skip)
			bar:setPrimary(if skipped then "Waiting for opponent…" else "Skip", not skipped)
			bar:setStatus("The debate is over: the map shows what it moved", "muted")
			return
		elseif reveal == "Clash" then
			bar:setPrimary("The clash!", false)
			bar:setStatus("Both moves are out", "muted")
			return
		elseif reveal == "DebateIntro" then
			bar:setPrimary("Get ready", false)
			bar:setStatus("Round 1 is about to start", "muted")
			return
		end
		if not Model.debating(p) then
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
		if pick.move == nil then
			bar:setPrimary("Pick a move", false)
			bar:setStatus(`No move: a weak Defend ({config.DEBATE_CANNED})`, "warn")
		elseif turnedDown and turnedDown.step == p.step then
			bar:setPrimary("Lock in", true)
			bar:setStatus(turnedDown.text, "bad")
		else
			bar:setPrimary("Lock in", true)
			local z = if pick.zinger then " + Zinger" else ""
			bar:setStatus(`{pick.move}{z} · kept secret`, "muted")
		end
	end

	local function render()
		local p = model.payload
		if p == nil or not alive then
			return
		end
		stage:render(p)
		moves:render(p)
		local round = clash:render(p)
		renderTip(p)
		paintMap(p, round)
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
		if Model.debating(p) and model.draftStep ~= p.step then
			fresh = true
			-- A new round: nothing picked (the default is a canned answer), no Zinger.
			model.draftStep = p.step
			pick.move = nil
			pick.held = nil
			pick.zinger = false
			local week = `{p.matchId}:{p.view.week}`
			if safeWeek == nil and not CoachTip.seen("debate.safe") then
				safeWeek = week
			end
			pick.showSafe = safeWeek == week
		end
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
			local options: { GuiObject } = {}
			for _, inst in side:GetDescendants() do
				if
					string.match(inst.Name, "^Move%u")
					and inst:IsA("GuiButton")
					and (inst :: GuiButton).Visible
				then
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
			-- The timer is about to end: send the picked move, if any.
			if Model.debating(p) and autoLock:due(p, now, Model.isLocked(model, p)) then
				if selection() ~= nil then
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
