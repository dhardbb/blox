--!strict
-- The campaign screen, where most of a match is played (docs/UI-STYLE.md §4.5).
-- The header runs across the top with the "what to do now" line; right under it,
-- full width, the week's event strip (CampaignParts/EventCard.strip, D-065:
-- seen without scrolling on every screen; a tap opens its details); the map is the
-- hero (left on 16:9, top on phones) with the lens chips and a "Map key" button
-- over it; beside it (below on phones) a scrolling side column and, pinned under
-- it, the action bar with Lock in. The same screen plays the resolve reveal and
-- the debate reveal.
--
-- A landscape phone (D-089, Kit.compact): the map column is a chip rail (Key,
-- Close, the lenses 2 x 2) beside the map, the full height under the header;
-- the event strip is the first thing in the side column, and steps aside with
-- the key states line while a state's card is open.
--
-- Side column, top to bottom: the reveal panel (during reveals), the key states
-- line while planning (CampaignParts/KeyRow, D-088: the same states glow on the
-- map), a first-match coach tip, the state card (only once a state is tapped),
-- the plan list, the week card, the full state list. The debate focus and a Choice stance are not
-- here: they have their own Decision screen before the plan (Screens/Decision,
-- D-044); the event strip repeats the stance you took in one line. The parts live in Screens/CampaignParts; this file owns the model, the
-- layout, the map, the action bar, and the routing between moments.
--
-- Motion and sound (docs/DESIGN.md D-053, UI/Motion, UI/Audio): tapping a state
-- plays "select" (its ring draws in, its card slides in); each planned state
-- wears its action's icon badge on the map; a lens switch fades the lens pills;
-- a plan the server turns down, or a tap on a Lock in greyed out by a problem,
-- shakes the action bar with the "error" cue. The opponent's line names them:
-- "Rex: thinking…" (the dots move unless motion is reduced), "Rex: locked in ✓".
--
-- Reads only ctx.store (the player's own View) and sends only through ctx.net.
-- The plan is previewed with Shared/UI/PlanDraft, which mirrors the server's
-- checks; the server still validates whatever is sent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Colors = require(Shared.UI.Colors)
local Issues = require(Shared.Sim.Issues)
local KeyStates = require(Shared.UI.KeyStates)
local Numbers = require(Shared.UI.Numbers)
local Plan = require(Shared.Sim.Plan)
local PlanDraft = require(Shared.UI.PlanDraft)
local PlanPreview = require(Shared.UI.PlanPreview)
local Session = require(Shared.Net.Session)
local ViewModule = require(Shared.Sim.View)

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local Audio = require(script.Parent.Parent.UI.Audio)
local AutoLock = require(script.Parent.Common.AutoLock)
local CoachTip = require(script.Parent.Parent.UI.CoachTip)
local EventCard = require(script.Parent.CampaignParts.EventCard)
local KeyRow = require(script.Parent.CampaignParts.KeyRow)
local Kit = require(script.Parent.Parent.UI.Kit)
local Lens = require(script.Parent.Parent.Map.Lens)
local LensToggle = require(script.Parent.Parent.Map.LensToggle)
local MapInterface = require(script.Parent.Parent.Map.MapInterface)
local MapPins = require(script.Parent.Parent.Map.Pins)
local Messages = require(script.Parent.Common.Messages)
local Model = require(script.Parent.CampaignParts.Model)
local Motion = require(script.Parent.Parent.UI.Motion)
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
local KEY_W = 88 -- px, the map key chip
local KEY_NARROW = Kit.MIN_TOUCH -- px, ... its icon alone (a phone, so the Close chip fits)
local KEY_ICON = 24 -- px, its icon plate
local MAP_SHARE = 0.62 -- share of the width the map takes on 16:9
local COMPACT_MAP_SHARE = 0.6 -- share of the width the map and its chip rail take on a landscape phone (D-089)
local RAIL_W = 2 * LensToggle.BUTTON_W + Kit.space.xs -- px, a landscape phone's chip rail left of the map: two chips a row
local PORTRAIT_MAP_MAX = 0.57 -- most of the body height the map may take on phones (D-079: room for the tall map and its two chip rows)
local BACK_SECONDS = 4 -- how long "<name>: back" shows after a reconnect
local SWATCH = 20 -- px, a color step's dot in the map key
local KEY_ROW_H = 24 -- px, one color step's row in the map key
local LOCKED_RISE = 4 -- px, the opponent's "locked in ✓" line rises this far
local LOCKED_WORD = Model.OPPONENT_LOCKED

-- LayoutOrder of each side-column panel.
local ORDER = {
	strip = -1, -- the event strip, on a landscape phone only (D-089)
	reveal = 0,
	keys = 1, -- the key states line while planning (D-088)
	tip = 2, -- a coach tip before anything is picked
	card = 3,
	tipAfter = 4, -- a coach tip once the plan has an action
	plan = 5,
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
		revealEV = nil,
		caption = nil,
		moreActions = false,
		details = false,
		messages = {},
		render = function() end,
		selectState = function(_id: string) end,
	}

	local lockMessageId = 0 -- id of the newest message when we pressed Lock in
	local lensFade = false -- the next map paint fades the lens pills in (a lens switch)
	local badges: { [string]: string } = {} -- state -> the icon its PlanBadge shows
	local opponentWas: string? = nil -- the opponent's state at the last bar render
	local rejection: { step: number, text: string }? = nil -- the server turned the lock down
	local autoLock = AutoLock.new()
	local portrait: boolean? = nil
	local lastBodySize = Vector2.new(-1, -1)
	local placedStrip = -1 -- the event strip's height when the body was last placed
	local away = false -- the opponent's seat was disconnected at the last look
	local backUntil = 0 -- "Opponent: back" shows until then

	-- ------------------------------------------------------------ build: frame

	local top = TopBar.new(parent, model)
	-- The week's event, right under the score (D-065); its details sheet opens over the screen.
	local eventStrip = EventCard.strip(parent, parent, model)

	local body = Kit.box({ Name = "Body", Parent = parent })

	-- Map area: the "Map key" button beside the lens chips, then the map.
	local mapArea = Kit.box({ Name = "MapArea", Parent = body })
	local keySheet: Sheet.Sheet? = nil
	-- A chip like the lens chips beside it: the search icon on its plate and "Key".
	local keyButton = Kit.chip("", function()
		local sheet = keySheet
		if sheet then
			sheet:open()
		end
	end, {
		Name = "MapKey",
		Size = UDim2.fromOffset(KEY_W, LENS_H),
		Parent = mapArea,
	})
	local keyContent = Kit.box({ Name = "Content", Parent = keyButton })
	local keyList = Kit.list("Horizontal", Kit.space.xs)
	keyList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	keyList.VerticalAlignment = Enum.VerticalAlignment.Center
	keyList.Parent = keyContent
	Kit.iconPlate("search", KEY_ICON, Kit.colors.text).Parent = keyContent
	local keyLabel = Kit.text("Key", {
		Name = "Label",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, LENS_H),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Kit.font.medium,
		TextWrapped = false,
		Parent = keyContent,
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
		lensFade = true
		model.render()
		lensFade = false
	end)
	lensToggle.root.AnchorPoint = Vector2.new(1, 0)
	lensToggle.root.Position = UDim2.fromScale(1, 0)
	-- The key chip keeps its own width (KEY_W); the lens chips take the right end.
	-- Between them, the Close filter (D-079): only the states still in play.
	local closeChip = LensToggle.close(mapArea, function()
		lensFade = true
		model.render()
		lensFade = false
	end)
	-- On a phone the key chip is its icon alone, so Close fits beside the lenses.
	local function placeChips(width: number)
		if model.compact == true then
			-- A landscape phone (D-089): the chips are a rail left of the map,
			-- Key and Close on top, the four lenses two by two under them, so
			-- the map takes the whole height.
			local chipW = LensToggle.BUTTON_W
			keyButton.Size = UDim2.fromOffset(chipW, LENS_H)
			keyLabel.Visible = false
			closeChip.root.Position = UDim2.fromOffset(chipW + Kit.space.xs, 0)
			LensToggle.setColumns(lensToggle, 2)
			lensToggle.root.AnchorPoint = Vector2.new(0, 0)
			lensToggle.root.Position = UDim2.fromOffset(0, LENS_H + Kit.space.xs)
			mapHolder.Position = UDim2.fromOffset(RAIL_W + GAP, 0)
			mapHolder.Size = UDim2.new(1, -(RAIL_W + GAP), 1, 0)
			return
		end
		LensToggle.setColumns(lensToggle, nil)
		lensToggle.root.AnchorPoint = Vector2.new(1, 0)
		lensToggle.root.Position = UDim2.fromScale(1, 0)
		mapHolder.Position = UDim2.fromOffset(0, LENS_H + Kit.space.xs)
		mapHolder.Size = UDim2.new(1, 0, 1, -(LENS_H + Kit.space.xs))
		local full = KEY_W + LensToggle.CLOSE_W + LensToggle.WIDTH + 2 * Kit.space.xs <= width
		local keyW = if full then KEY_W else KEY_NARROW
		keyButton.Size = UDim2.fromOffset(keyW, LENS_H)
		keyLabel.Visible = full
		closeChip.root.Position = UDim2.fromOffset(keyW + Kit.space.xs, 0)
	end

	-- A plan that can't go: the bar shakes, its status flashes, one "error".
	local bar: ActionBar.ActionBar
	local function refuse()
		Motion.shake(bar.root)
		Motion.flash(bar.status, Kit.colors.text)
		Audio.play("error")
	end

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

	bar = ActionBar.new(sideColumn, {
		primary = "Lock in",
		onPrimary = function() end,
		secondary = "+15 s",
		onSecondary = function() end,
		primaryName = "LockIn",
		secondaryName = "BankButton",
	})
	bar.primary.Activated:Connect(function()
		local p = model.payload
		if p == nil then
			return
		end
		if bar.primary.Active == false then
			-- Greyed out by a problem in the plan (the status says which): say no.
			if
				Model.planning(p)
				and Model.editable(model, p)
				and PlanDraft.problem(config, p.view, model.draft) ~= nil
			then
				refuse()
			end
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
		caption = function(text: string, polls: boolean?)
			model.caption = text
			model.captionPolls = polls == true
			top:render(ctx.now())
		end,
		-- The map and the header's score show the same moment of the reveal.
		paint = function(view: View)
			local p = model.payload
			if p then
				paintMapFor(p.view, view)
				model.revealEV = view.projectedEV
				top:render(ctx.now())
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
	local keyRow = KeyRow.new(side, model, ORDER.keys)
	local card = StateCard.new(side, model, ORDER.card, ORDER.list)
	local planList = PlanList.new(side, model, ORDER.plan)
	local weekCard = EventCard.week(side, model, ORDER.week)

	-- How to read the map: one tap away, never a caption line over it.
	local key = Sheet.new(parent, { title = "How to read the map", name = "MapKeySheet", height = 0.6 })
	local keyLines: { TextLabel } = {}
	for k = 1, 10 do
		keyLines[k] = Kit.text("", {
			Name = `KeyLine{k}`,
			-- The color steps come right after the first line (what color means);
			-- the issue symbols (KeyIssues) right after the third (the Issues lens's).
			LayoutOrder = if k == 1 then 1 else 10 + 2 * k,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = key.body,
		})
	end
	-- One row per color step (Colors.BANDS): your dot, their dot, what it means.
	type KeyBand = { name: string, mine: Frame, theirs: Frame }
	local keyBands: { KeyBand } = {}
	for k, band in Words.bands() do
		local row = Kit.box({
			Name = `KeyBand{k}`,
			LayoutOrder = 1 + k,
			Size = UDim2.new(1, 0, 0, KEY_ROW_H),
			Parent = key.body,
		})
		Kit.dataColor(row)
		local function dot(name: string, x: number): Frame
			local frame = Kit.new("Frame", {
				Name = name,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, x, 0.5, 0),
				Size = UDim2.fromOffset(SWATCH, SWATCH),
				BorderSizePixel = 0,
				Parent = row,
			}) :: Frame
			Kit.round().Parent = frame
			return frame
		end
		local mine = dot("Mine", 0)
		local theirs = dot("Theirs", SWATCH + Kit.space.xs)
		local textX = 2 * SWATCH + Kit.space.xs + Kit.space.sm
		Kit.text(band.text, {
			Name = "BandText",
			Position = UDim2.fromOffset(textX, 0),
			Size = UDim2.new(1, -textX, 1, 0),
			TextScaled = true,
			TextWrapped = false,
			Parent = row,
		})
		table.insert(keyBands, { name = band.name, mine = mine, theirs = theirs })
	end
	-- The Issues lens (D-076): every issue's symbol with its name, two columns.
	local keyIssues = Kit.box({
		Name = "KeyIssues",
		LayoutOrder = 17,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = key.body,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -Kit.space.xs, 0, KEY_ROW_H),
		CellPadding = UDim2.fromOffset(Kit.space.sm, Kit.space.xs),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = keyIssues,
	})
	for k, issue in Issues.list do
		local cell = Kit.box({ Name = `KeyIssue_{issue}`, LayoutOrder = k, Parent = keyIssues })
		local row = Kit.list("Horizontal", Kit.space.sm)
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.Parent = cell
		local icon = Kit.issueIcon(issue, SWATCH)
		icon.LayoutOrder = 1
		icon.Parent = cell
		Kit.text(Kit.issueName(issue), {
			Name = "IssueText",
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, KEY_ROW_H),
			TextWrapped = false,
			Parent = cell,
		})
	end
	keySheet = key
	local function renderKey(p: Payload)
		keyIssues.Visible = Lens.current() == "Issues"
		local lines = Words.key(Lens.current())
		for k, label in keyLines do
			label.Text = lines[k] or ""
			label.Visible = lines[k] ~= nil
		end
		local view = p.view
		local mineColor = Colors.of(view.players[view.you].color)
		local theirColor = Colors.of(view.players[Model.opponentOf(view)].color)
		for _, row in keyBands do
			local share = 0
			for _, band in Colors.BANDS do
				if band.name == row.name then
					share = band.share
				end
			end
			row.mine.BackgroundColor3 = Kit.color(Colors.tint(Colors.neutral, mineColor, share))
			row.theirs.BackgroundColor3 = Kit.color(Colors.tint(Colors.neutral, theirColor, share))
			-- A toss-up is grey for both: one dot says it.
			row.theirs.Visible = share > 0
		end
	end

	-- First-match coach tips (UI/CoachTip), one at a time at the top of the column.
	local tip: CoachTip.Tip? = nil
	local tipId: string? = nil
	local function renderTip(p: Payload)
		local want: string? = nil
		local spare: number? = nil
		if Model.planning(p) and Model.editable(model, p) then
			-- The map first; once there is a plan, how to finish it; the lenses
			-- from week 2, when nothing is picked. Never over the state's actions.
			-- The tutorial's last week leads with ground game (D-080; the tip
			-- exists only in the tutorial's copy, CoachTip.has). Idle money
			-- (D-086) gets its tip whatever is picked, under the state card.
			local last = p.view.week >= config.WEEKS
			spare = PlanDraft.idleCash(config, p.view, model.draft)
			local order: { string } = if #model.draft.actions > 0
				then { "campaign.actions" }
				elseif model.selected then {}
				elseif last then { "campaign.ground", "campaign.map", "campaign.keys", "campaign.lens" }
				else { "campaign.map", "campaign.keys", "campaign.lens" }
			if spare ~= nil then
				-- After the map tip, before the lenses; first once the plan has an action.
				table.insert(order, table.find(order, "campaign.lens") or 1, "campaign.cash")
			end
			for _, id in order do
				if
					CoachTip.has(id)
					and not CoachTip.seen(id)
					and (id ~= "campaign.lens" or p.view.week >= 2)
				then
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
			-- The idle-money tip is shown once: gone (money spent, locked in) is seen.
			if tipId == "campaign.cash" then
				CoachTip.markSeen("campaign.cash")
			end
			tip, tipId = nil, nil
		end
		if want and tip == nil then
			-- The first tip names the header's score, with its numbers (M4).
			local ev = p.view.projectedEV
			local rival = Model.opponentOf(p.view)
			tip = CoachTip.show(side, {
				id = want,
				text = if want == "campaign.map"
					then Words.mapTip(ev[p.view.you] or 0, ev[rival] or 0)
					elseif want == "campaign.cash" and spare ~= nil then CoachTip.fill(
						want,
						Numbers.money(spare)
					)
					else nil,
				order = if want == "campaign.actions" or want == "campaign.cash"
					then ORDER.tipAfter
					else ORDER.tip,
			})
			tipId = if tip then want else nil
		end
	end

	-- ------------------------------------------------------------ layout

	local function placeBody(isPortrait: boolean, topHeight: number)
		local stripHeight = eventStrip:height()
		placedStrip = stripHeight
		if model.compact == true then
			-- A landscape phone (D-089): the body right under the header, the map
			-- and its chip rail on the left the whole height, and the event strip
			-- first in the side column (still seen without scrolling, D-065).
			if eventStrip.root.Parent ~= side then
				eventStrip.root.Parent = side
				eventStrip.root.LayoutOrder = ORDER.strip
			end
			body.Position = UDim2.fromOffset(0, topHeight + GAP)
			body.Size = UDim2.new(1, 0, 1, -(topHeight + GAP))
			-- The map column is as wide as the map at this height (up to
			-- COMPACT_MAP_SHARE); the side column takes the rest.
			local bodyW = parent.AbsoluteSize.X
			local height = parent.AbsoluteSize.Y - (topHeight + GAP)
			local maxW = math.floor(bodyW * COMPACT_MAP_SHARE) - RAIL_W - GAP
			local mapW = if maxW > 0 and height > 0
				then math.floor(math.min(maxW, height * map:aspectFor(maxW, height)))
				else maxW
			local areaW = RAIL_W + GAP + math.max(mapW, 0)
			mapArea.Size = UDim2.new(0, areaW, 1, 0)
			sideColumn.Position = UDim2.fromOffset(areaW + GAP, 0)
			sideColumn.Size = UDim2.new(1, -(areaW + GAP), 1, 0)
			placeChips(areaW)
			lastBodySize = body.AbsoluteSize
			return
		end
		if eventStrip.root.Parent ~= parent then
			eventStrip.root.Parent = parent
		end
		-- The event strip under the header, then the body under it.
		eventStrip.root.Position = UDim2.fromOffset(0, topHeight + GAP)
		local bodyTop = topHeight + GAP + (if stripHeight > 0 then stripHeight + GAP else 0)
		body.Position = UDim2.fromOffset(0, bodyTop)
		body.Size = UDim2.new(1, 0, 1, -bodyTop)
		if isPortrait then
			local width = body.AbsoluteSize.X
			local height = body.AbsoluteSize.Y
			-- The map's box for this room (D-079: it stands up on a phone, 1.25 instead of 1.6).
			local maxHeight = height * PORTRAIT_MAP_MAX
			local mapHeight = math.floor(math.min(width / map:aspectFor(width, maxHeight), maxHeight))
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
		placeChips(mapArea.AbsoluteSize.X)
	end

	local function relayout(force: boolean?)
		local isPortrait = ctx.portrait()
		local isCompact = Kit.compact(parent.AbsoluteSize)
		if isPortrait ~= portrait or isCompact ~= (model.compact == true) or force then
			portrait = isPortrait
			model.portrait = isPortrait
			model.compact = isCompact
			placeBody(isPortrait, top:place(isPortrait))
			weekCard:setPortrait(isPortrait)
		elseif
			eventStrip:height() ~= placedStrip
			or (isPortrait or isCompact)
				and (body.AbsoluteSize.X ~= lastBodySize.X or body.AbsoluteSize.Y ~= lastBodySize.Y)
		then
			placeBody(isPortrait, top:place(isPortrait))
		end
	end

	-- ------------------------------------------------------------ the map

	-- The key states while you plan (D-088): from your own View's public polls.
	local function keysFor(p: Payload): { KeyStates.Key }
		if Model.planning(p) then
			return KeyStates.of(config, p.view)
		end
		return {}
	end

	-- Paints the map from `shown`'s polls with the marks for `view`.
	paintMapFor = function(view: View, shown: View)
		local colors: { Colors.RGB } = {}
		for p, player in view.players do
			colors[p] = Colors.of(player.color)
		end
		local live = model.payload
		-- During a reveal the fills tween to each step's polls (D-079): the map
		-- tells the story, the tags only name the flips and biggest moves.
		map:setView(shown, colors, live ~= nil and live.reveal ~= nil)
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
		-- The key states glow while you plan (D-088), in every lens.
		local keys: { KeyStates.Key } = if live and shown == view then keysFor(live) else {}
		for _, keyState in keys do
			local mark = marks[keyState.id] or {}
			mark.key = true
			marks[keyState.id] = mark
		end
		map:setLens(
			Lens.lines(Lens.current(), { config = config, view = shown, draft = model.draft }),
			lensFade
		)
		-- Polls explains its extra marks in the legend row; the pins show in every lens (D-070).
		local legend: { MapInterface.LegendItem } = Lens.mapLegend(
			{ config = config, view = shown },
			Lens.current()
		) or {}
		if #keys > 0 then
			local keyItem: MapInterface.LegendItem = { mark = "key", text = Words.KEY_LEGEND }
			table.insert(legend, 1, keyItem)
		end
		-- The plan preview (D-071): while you draft, what the plan would move.
		local tags = {}
		if live and shown == view and Model.planning(live) and not Model.isLocked(model, live) then
			local line
			tags, line = PlanPreview.build(config, view, model.draft)
			if line then
				-- The lens's own legend makes room for the plan line on a phone;
				-- the caveat goes first (the Map key always says it).
				for _, item in legend do
					item.drop = 1
				end
				local planLine: MapInterface.LegendItem = { mark = "none", text = line }
				local caveat: MapInterface.LegendItem =
					{ mark = "none", text = PlanPreview.CAVEAT, color = Kit.colors.muted, drop = 2 }
				table.insert(legend, 1, planLine)
				table.insert(legend, 2, caveat)
			end
		end
		map:setLegend(legend)
		map:setPreview(tags)
		map:setPins(MapPins.of(config, shown))
		-- A reveal shows what moved (D-042); the stance preview is on the Decision screen (D-044).
		local swing = model.revealSwing
		if swing then
			marks = if swing.step
				then SwingMarks.step(view, swing.net, swing.flips, marks)
				else SwingMarks.reveal(view, swing.net, swing.flips, marks)
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

	-- Each planned state wears the icon of its latest action (Kit.actionIcon); a
	-- state leaving the plan loses it. Only while planning: the reveals badge
	-- the map themselves, so outside planning this only takes its own badges off.
	local function syncBadges(p: Payload)
		local want: { [string]: string } = {}
		if Model.planning(p) and model.draftStep == p.step then
			for _, action in model.draft.actions do
				local icon = Kit.actionIcon(action.kind)
				if action.state and icon then
					want[action.state] = icon
				end
			end
		end
		for id, icon in badges do
			if want[id] ~= icon then
				map:badge(id, want[id])
				badges[id] = want[id]
			end
		end
		for id, icon in want do
			if badges[id] == nil then
				map:badge(id, icon)
				badges[id] = icon
			end
		end
	end

	-- ------------------------------------------------------------ the action bar

	-- The opponent's state in a word: what the bar says after their name.
	local function opponentState(p: Payload, now: number): string?
		local them = Model.opponentOf(p.view)
		local seat = p.seats[them]
		if seat == nil then
			return nil
		elseif not seat.connected then
			return "disconnected"
		elseif now < backUntil then
			return "back"
		elseif p.stage == "Input" then
			return if seat.locked then LOCKED_WORD else "thinking"
		elseif p.reveal == "Resolve" and seat.skip then
			return "skipped"
		end
		return "watching"
	end

	local function opponentText(p: Payload, now: number): string?
		local state = opponentState(p, now)
		if state == nil then
			return nil
		end
		local name = Model.firstName(config, p.view, Model.opponentOf(p.view))
		return Model.opponentLine(name, state, now, Motion.reduced())
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
		local opponentNow = opponentState(p, now)
		if opponentNow ~= opponentWas then
			if opponentNow == LOCKED_WORD and opponentWas ~= nil then
				-- They just locked in: the line rises into place and pops.
				Motion.enter(bar.opponent, LOCKED_RISE)
				Motion.pop(bar.opponent)
			end
			opponentWas = opponentNow
		end
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
			-- No "+15 s" in a plan without a deadline (the tutorial, D-075).
			if canEdit and bank >= chunk and p.deadline ~= nil then
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
			-- A step with nothing to press cannot be skipped (debates have their own screen).
			primary.Name = "SkipButton"
			primary.Visible = false
			bar:setSecondary(nil, false)
			bar:setStatus("Campaign", "muted")
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
			model.revealEV = nil
			model.caption = nil
			model.captionPolls = nil
		end
		syncBadges(p)
		reveal:render(p)
		keyRow:render(p, keysFor(p))
		card:render(p)
		eventStrip:render(p)
		if model.compact == true and model.selected ~= nil then
			-- A landscape phone (D-089): an open card takes the strip's place in
			-- the short side column, as it takes the key states line's.
			eventStrip.root.Visible = false
		end
		if p.reveal == nil or p.reveal == "Debate" then
			paintMapFor(view, view)
			map:select(model.selected)
		end
		paintRoute(p)
		planList:render(p)
		weekCard:render(p)
		renderTip(p)
		renderKey(p)
		lensToggle.refresh()
		closeChip.refresh()
		renderBar(p, now)
		if top:render(now) or eventStrip:height() ~= placedStrip then
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
		Audio.play("select")
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
	model.ghost = function(id: string, text: string?)
		map:ghost(id, text)
	end

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
		local refused = false
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
			local own = p.seats[p.you]
			if model.lockStep == p.step and not (own ~= nil and own.locked) then
				local turnedDown = Messages.rejectionAfter(state, lockMessageId)
				if turnedDown ~= nil then
					model.lockStep = nil
					rejection = {
						step = p.step,
						text = if turnedDown.reason
							then problemText(p, turnedDown.reason)
							else turnedDown.text,
					}
					refused = true
				end
			end
		elseif model.draftStep ~= nil then
			-- The plan was sent and resolved: the View already includes it.
			model.draft = PlanDraft.new()
			model.draftStep = nil
		end
		if p.reveal == "Resolve" then
			-- The reveal sets the header's score (the week's start) before it renders.
			reveal:tick(p, now)
		end
		render()
		reveal:tick(p, now)
		renderBar(p, now)
		if refused then
			refuse()
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
