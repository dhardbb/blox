--!strict
-- Draft screen: the map reveal (leans and the strongholds they give each player,
-- D-045), then three blind draft rounds: home state, then two battleground
-- nominations (PLAN.md "Draft"). Each round the player fills a ranked top 2 by
-- tapping the map or the state list and locks it in; after the round both picks
-- are revealed together. The screen reads only the player's own View and sends
-- only { choices = { first, second? } }.
--
-- Layout (docs/UI-STYLE.md §4.3), every big box explicitly positioned:
--   Header     title ("The map", "Round 2 of 3"), the round's kind as a subtitle
--              on wide screens, the "what to do now" line, the timer and its bar
--   map        the lens chips over it (with the two-dot legend beside them on
--              wide screens); 65 % of the width on wide screens (the drafted
--              board under it, in Below), min(width / ASPECT, 34 % of the
--              height) on a phone, with the panel right under it
--   panel      map reveal: the strongholds card and who wins ties.
--              picking: a coach tip, the round's pill and who wins ties (in a
--              battleground round, a caption on what one does), the
--              1st / 2nd slots, the best picks (8 rows; "Show all states"),
--              "How the draft works" (a sheet with the rules).
--              reveal: both picks side by side and the clash note.
--              On a phone a collapsed "Draft board" card ends the panel.
--   ActionBar  pinned under the panel while picking: status (tone bad for an
--              illegal tap, until the next tap), opponent, primary "Lock in".
--
-- The 0.17 pass (D-091): the map reveal gives the map more of the column and
-- lists each stronghold as a row under its player's portrait (two columns);
-- the choice slots are one row of two chips with a numbered badge each ("1 WY
-- · Wyoming", "2 Backup"); the first-pick tip floats over the map instead of
-- pushing the slots down; a battleground round warns that the rival can
-- nominate your strongholds too (RoundNote, with the caption); a refused tap
-- says why, with the rule, in a notice under the slots (Notice); a landscape
-- phone folds "ties go to …" into the header's subtitle. A round's reveal
-- counts each pick's votes up, pulses both states and shows the draft board
-- in a card under the picks. In the last seconds the Lock in drains
-- (Common/PickClock).
--
-- Motion and sound (docs/UI-STYLE.md §2.7.1): a legal tap pops its slot,
-- pulses the state and plays "planAdd" ("planRemove" when a tap takes a pick
-- back); an illegal tap shakes the status line with "error". When a round's
-- picks are revealed, both cards pop, each state rings in its taker's color,
-- and "whoosh" plays. Nothing waits on an animation.
--
-- Stable names for tests and agents: LockIn (the primary), Choice1, Choice2,
-- Clear1, Clear2, Row_<id>, the map nodes by id, Priority, RoundPill, RoundCaption,
-- StrongholdsCard (StrongholdsYou, StrongholdsThem), Explain (the header
-- subtitle), NowText, Timer, StateList, ShowAll, HowButton, DraftSheet,
-- HowItWorks, Board, Legend, LegendRow, BoardCard, RevealBox, YouPick, ThemPick,
-- ClashNote, BarStatus, BarOpponent, MapArea, Panel, Num (a slot's badge),
-- RoundNote (RoundCaption, StrongholdWarning), Notice, RevealBoard, Gain (a
-- pick card's votes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Draft = require(ReplicatedStorage.Shared.Sim.Draft)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local Drafted = require(ReplicatedStorage.Shared.UI.Drafted)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local View = require(ReplicatedStorage.Shared.Sim.View)
local Words = require(ReplicatedStorage.Shared.UI.Words.Setup)

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local Audio = require(script.Parent.Parent.UI.Audio)
local AutoLock = require(script.Parent.Common.AutoLock)
local Board = require(script.Parent.DraftParts.Board)
local CoachTip = require(script.Parent.Parent.UI.CoachTip)
local Collapsible = require(script.Parent.Parent.UI.Collapsible)
local Header = require(script.Parent.Parent.UI.Header)
local Kit = require(script.Parent.Parent.UI.Kit)
local LinkButton = require(script.Parent.Parent.UI.LinkButton)
local Lens = require(script.Parent.Parent.Map.Lens)
local LensToggle = require(script.Parent.Parent.Map.LensToggle)
local Logic = require(script.Parent.DraftParts.Logic)
local MapInterface = require(script.Parent.Parent.Map.MapInterface)
local Messages = require(script.Parent.Common.Messages)
local Motion = require(script.Parent.Parent.UI.Motion)
local NodeMap = require(script.Parent.Parent.Map.NodeMap)
local PickClock = require(script.Parent.Common.PickClock)
local Sheet = require(script.Parent.Parent.UI.Sheet)
local StateList = require(script.Parent.DraftParts.StateList)
local Types = require(script.Parent.Types)

local Screen = {}

local GAP = Kit.space.sm -- px, between the big blocks
local MAP_SHARE = 0.65 -- of the width, wide screens
local MAP_SHARE_REVEAL = 0.6 -- the same during the map reveal: the strongholds' two columns get more room (D-091)
local COMPACT_MAP_SHARE = 0.6 -- most of the width the map column takes on a landscape phone (D-089)
local MAP_HEIGHT_SHARE = 0.66 -- of the map column, wide screens (the rest is Below)
local REVEAL_MAP_HEIGHT_SHARE = 0.86 -- the same during the map and round reveals: only the legend's note is under it (D-091)
local MAP_SHARE_PORTRAIT = 0.34 -- of the height at most, phones (before the lens row)
local LENS_H = LensToggle.HEIGHT + Kit.space.xs -- px, the lens row over the map
local PICK_FROM = 0.92 -- scale a slot pops from when a state lands in it
local REVEAL_FROM = 0.85 -- scale the reveal cards pop from
local SLOT_BADGE = 24 -- px, a choice slot's numbered badge
local TIP_W = 360 -- px, widest the first-pick tip over the map gets
local NOTE_EDGE = 1.5 -- px, a note's outline (orange for a warning, D-091)
local GAIN_SECONDS = 0.6 -- a pick card's votes count up this long (none under reduced motion)

-- Panel order (PanelScroll's list).
local ORDER = {
	tip = 1, -- unused since D-091 (the tip floats over the map); kept so the order reads as before
	strongholds = 2, -- map reveal only
	slots = 3, -- first while picking (D-091)
	notice = 4, -- why the last tap was refused
	priority = 5,
	caption = 6, -- a battleground round only: what a battleground does (S4) and the stronghold warning
	reveal = 7,
	revealBoard = 8, -- the draft board in a card under a round's reveal
	list = 9,
	showAll = 10,
	legend = 11, -- map reveal on a phone
	how = 12,
	boardCard = 13, -- portrait only, always last
}

type Mode = "Map" | "Input" | "Reveal"

local function auto(): { [string]: any }
	return { Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y }
end

local function merge(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	for key, value in extra do
		base[key] = value
	end
	return base
end

function Screen.mount(parent: Frame, ctx: Types.Ctx): Types.Screen
	local config = ctx.config
	local totalRounds = Draft.rounds(config)

	-- What the screen remembers between updates.
	local current: Types.State? = nil
	local stepKey = ""
	local choices: Logic.Choices = {}
	local target: number? = nil -- slot the player aimed at by tapping Choice1 / Choice2
	local localLocked = false -- pressed Lock in; the server's lock arrives with the next payload
	local messageAtLock = 0 -- id of the newest message when Lock in was pressed
	local autoLock = AutoLock.new()
	local submitted: { round: number, choices: { string } }? = nil
	local hint: string? = nil -- why the last tap failed; stays until the next tap
	local refused: string? = nil -- the same with the rule behind it, for the notice (D-091)
	local laidOut = "" -- the shape applyLayout last laid out for
	local placed = "" -- where the legend and board last went
	local mode: Mode = "Map"
	local lastView: View.View? = nil
	local lastKind: Draft.Kind? = nil
	local showAll = false -- the list shows every state
	local tip: CoachTip.Tip? = nil
	local revealedRound = 0 -- the last round whose reveal popped in

	-- ------------------------------------------------------------ layout

	local root = Kit.box({ Name = "DraftRoot", Parent = parent })
	local header = Header.new(root, { title = "", now = true, onHelp = ctx.help })
	header.subtitle.Name = "Explain"

	local mapArea = Kit.box({ Name = "MapArea", Parent = root })
	local mapHolder = Kit.box({ Name = "MapHolder", Parent = mapArea })
	local map = NodeMap.new()
	map.root.AnchorPoint = Vector2.new(0.5, 0)
	map.root.Position = UDim2.new(0.5, 0, 0, LENS_H)
	map.root.Size = UDim2.new(1, 0, 1, -LENS_H)
	map.root.Parent = mapHolder
	-- Wide screens: the legend's two keys beside the lens chips.
	local legendSlot = Kit.box({
		Name = "LegendSlot",
		Size = UDim2.new(
			1,
			-(LensToggle.WIDTH + LensToggle.CLOSE_W + Kit.space.xs + Kit.space.md),
			0,
			LensToggle.HEIGHT
		),
		Parent = mapHolder,
	})

	-- Wide screens: the legend note and the board under the map.
	local below = Kit.new("ScrollingFrame", {
		Name = "Below",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = mapArea,
	})
	Kit.list("Vertical", Kit.space.xs).Parent = below

	local panel = Kit.panel({ Name = "Panel", Parent = root })
	local scroll = Kit.new("ScrollingFrame", {
		Name = "PanelScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = panel,
	})
	Kit.list("Vertical", GAP).Parent = scroll
	Kit.new("UIPadding", { PaddingRight = UDim.new(0, Kit.space.md), Parent = scroll })

	-- ------------------------------------------------------------ panel contents

	local strongholds = Board.newStrongholds()
	strongholds.root.LayoutOrder = ORDER.strongholds
	strongholds.root.BackgroundColor3 = Kit.colors.raised
	strongholds.root.Parent = scroll

	-- The round's kind as a pill, and who wins a state you both want.
	local priorityRow = Kit.box({
		Name = "PriorityRow",
		LayoutOrder = ORDER.priority,
		Size = UDim2.new(1, 0, 0, Kit.PILL_H),
		Parent = scroll,
	})
	local rowList = Kit.list("Horizontal", Kit.space.sm)
	rowList.VerticalAlignment = Enum.VerticalAlignment.Center
	rowList.Parent = priorityRow
	local roundPill = Kit.pill("", "text", { Name = "RoundPill", LayoutOrder = 1, Parent = priorityRow })
	local priority = Kit.text("", {
		Name = "Priority",
		LayoutOrder = 2,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = Kit.size.caption,
		TextColor3 = Kit.colors.muted,
		TextWrapped = false,
		Parent = priorityRow,
	})

	-- A note in the panel: a raised strip with its lines, outlined (orange for
	-- a warning); it grows with them.
	local function noteBox(name: string, order: number): (Frame, UIStroke)
		local frame = Kit.panel({
			Name = name,
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Kit.colors.raised,
			Visible = false,
			Parent = scroll,
		})
		local pad = frame:FindFirstChildOfClass("UIPadding")
		if pad then
			pad.PaddingTop = UDim.new(0, Kit.space.sm)
			pad.PaddingBottom = UDim.new(0, Kit.space.sm)
		end
		Kit.list("Vertical", Kit.space.xs).Parent = frame
		local edge = Kit.new("UIStroke", {
			Name = "Edge",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Kit.colors.warn,
			Thickness = NOTE_EDGE,
			Parent = frame,
		}) :: UIStroke
		return frame, edge
	end

	-- Under the header of a battleground round: what nominating does, for both,
	-- and (D-091, from playtests) that the rival may nominate your strongholds.
	local roundNote, roundBar = noteBox("RoundNote", ORDER.caption)
	local roundCaption = Kit.text(Words.battlegroundCaption(config), {
		Name = "RoundCaption",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Kit.size.caption,
		TextColor3 = Kit.colors.muted,
		Visible = false,
		Parent = roundNote,
	})
	local strongholdWarning = Kit.text("", {
		Name = "StrongholdWarning",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Kit.size.caption,
		Font = Kit.font.medium,
		Visible = false,
		Parent = roundNote,
	})
	-- Why the last tap was refused, with the rule behind it (D-091).
	local noticeBox = noteBox("Notice", ORDER.notice)
	local notice = Kit.text("", {
		Name = "NoticeText",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Kit.size.caption,
		Font = Kit.font.medium,
		Parent = noticeBox,
	})

	-- The ranked top 2: one row of two chips, each with a × once it is filled.
	local slots = Kit.box({
		Name = "Slots",
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		LayoutOrder = ORDER.slots,
		Parent = scroll,
	})
	local refresh: () -> () = function() end
	local tapState: (id: string) -> () = function(_id: string) end
	local lockInPressed: () -> () = function() end

	local choiceButtons: { TextButton } = {}
	local clearButtons: { TextButton } = {}
	local slotBadges: { TextLabel } = {}
	for slot = 1, 2 do
		local half = Kit.box({
			Name = `Slot{slot}`,
			Position = UDim2.new((slot - 1) * 0.5, if slot == 2 then GAP // 2 else 0, 0, 0),
			Size = UDim2.new(0.5, -GAP // 2, 1, 0),
			Parent = slots,
		})
		local button = Kit.button("", function()
			if mode == "Input" and not localLocked then
				target = if target == slot then nil else slot
				hint = nil
				refused = nil
				refresh()
			end
		end, {
			variant = "chip",
			Name = `Choice{slot}`,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = half,
		})
		-- The slot's number on a round badge in the chip's left padding (D-091):
		-- filled once a state is in it, an outline while it waits.
		local pad = button:FindFirstChildOfClass("UIPadding")
		if pad then
			pad.PaddingLeft = UDim.new(0, SLOT_BADGE + 2 * Kit.space.sm)
		end
		local badge = Kit.text(tostring(slot), {
			Name = "Num",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, -(SLOT_BADGE + Kit.space.sm), 0.5, 0),
			Size = UDim2.fromOffset(SLOT_BADGE, SLOT_BADGE),
			BackgroundTransparency = 0,
			BackgroundColor3 = Kit.colors.accent,
			Font = Kit.font.bold,
			TextSize = Kit.size.caption,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextColor3 = Kit.colors.onAccent,
			Parent = button,
		})
		Kit.round().Parent = badge
		Kit.new("UIStroke", {
			Name = "Ring",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Kit.colors.muted,
			Thickness = 2,
			Parent = badge,
		})
		slotBadges[slot] = badge
		choiceButtons[slot] = button
		clearButtons[slot] = Kit.iconButton(Kit.glyph.close, function()
			if mode == "Input" and not localLocked then
				choices = Logic.clear(choices, slot)
				target = nil
				hint = nil
				refused = nil
				refresh()
			end
		end, {
			Name = `Clear{slot}`,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Visible = false,
			Parent = half,
		})
	end

	-- The reveal: what each of you got, side by side, and the clash note.
	local revealBox = Kit.box(
		merge(auto(), { Name = "RevealBox", LayoutOrder = ORDER.reveal, Visible = false, Parent = scroll })
	)
	Kit.list("Vertical", Kit.space.sm).Parent = revealBox
	local revealRow = Kit.box(merge(auto(), { Name = "RevealRow", LayoutOrder = 1, Parent = revealBox }))
	Kit.list("Horizontal", GAP).Parent = revealRow
	-- A pick card: "You got WY" in the taker's readable color, the pick's kind
	-- as a tag (★ Battleground outlined, Home filled in the taker's color), the
	-- state's name; edged 2 px in the taker's color (fillCard).
	type PickCard = { frame: Frame, big: TextLabel, gain: TextLabel, small: TextLabel, kind: TextLabel }
	local function pickCard(name: string, order: number): PickCard
		local frame = Kit.panel({
			Name = name,
			Size = UDim2.new(0.5, -GAP // 2, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Kit.colors.raised,
			LayoutOrder = order,
			Parent = revealRow,
		})
		Kit.depth(frame, Kit.colors.raisedTop, Kit.colors.raised)
		Kit.list("Vertical", Kit.space.xs).Parent = frame
		Kit.stroke(Kit.colors.line, 2).Parent = frame
		-- One line that shrinks to fit a narrow card ("Buster got OH" never wraps).
		local big = Kit.heading("", {
			Name = "Title",
			LayoutOrder = 1,
			TextScaled = true,
			TextWrapped = false,
			Parent = frame,
		})
		-- The state's votes, counting up as the card lands (D-091).
		local gain = Kit.text("", {
			Name = "Gain",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, Kit.size.heading + 8),
			Font = Kit.font.display,
			TextSize = Kit.size.heading,
			TextWrapped = false,
			Parent = frame,
		})
		local kind = Kit.pill("", "text", { Name = "Kind", LayoutOrder = 3, Parent = frame })
		local small = Kit.caption("", { Name = "Sub", LayoutOrder = 4, Parent = frame })
		return { frame = frame, big = big, gain = gain, small = small, kind = kind }
	end
	local youCard = pickCard("YouPick", 1)
	local themCard = pickCard("ThemPick", 2)
	local clashNote = Kit.text("", merge(auto(), { Name = "ClashNote", LayoutOrder = 2, Parent = revealBox }))
	-- Under a round's picks: the draft board so far, in a card (D-091).
	local revealBoard = Kit.card({ Name = "RevealBoard", LayoutOrder = ORDER.revealBoard, Visible = false })
	Kit.text(
		"Draft board",
		{ Name = "BoardTitle", LayoutOrder = 0, Font = Kit.font.bold, Parent = revealBoard }
	)
	revealBoard.Parent = scroll

	local stateList = StateList.new(function(id: string)
		tapState(id)
	end)
	stateList.root.LayoutOrder = ORDER.list
	stateList.root.Parent = scroll

	local showAllButton = Kit.button("Show all states", function()
		showAll = not showAll
		refresh()
	end, { variant = "ghost", Name = "ShowAll", LayoutOrder = ORDER.showAll, Parent = scroll })

	-- How the draft works: the rules, one tap away.
	local sheet = Sheet.new(root, { title = "How the draft works", name = "DraftSheet" })
	Kit.text(Logic.howItWorks(config), {
		Name = "HowItWorks",
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = sheet.body,
	})
	for k, kind in { "Home", "Nominate" } do
		Kit.text(Words.roundRule(config, kind), {
			Name = `Rule{kind}`,
			LayoutOrder = 1 + k,
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = sheet.body,
		})
	end
	local sheetStrongholds = Kit.text("", {
		Name = "SheetStrongholds",
		LayoutOrder = 5,
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Kit.colors.muted,
		Parent = sheet.body,
	})
	local howButton = LinkButton.new("How the draft works", function()
		sheet:open()
	end, { Name = "HowButton", LayoutOrder = ORDER.how, Parent = scroll })

	-- Portrait: the legend and board in a card at the very end, collapsed.
	local boardCard = Collapsible.new(scroll, {
		title = "Draft board",
		name = "BoardCard",
		order = ORDER.boardCard,
		expanded = false,
	})

	local legend = Board.newLegend()
	local summary = Board.newSummary()

	-- Lock in, pinned under the scrolling panel (picking only).
	local bar = ActionBar.new(panel, {
		primary = "Pick a state",
		onPrimary = function()
			lockInPressed()
		end,
		primaryName = "LockIn",
	})
	local pickClock = PickClock.new(bar)

	-- ------------------------------------------------------------ orientation

	-- Lays the screen out for its current size (re-run when it changes). Phones
	-- get pixel math so the panel starts exactly GAP under the map.
	local function applyLayout()
		local portrait = ctx.portrait()
		local size = root.AbsoluteSize
		local compact = Kit.compact(size)
		local shape = `{portrait}:{compact}:{size.X}x{size.Y}:{mode}`
		if shape == laidOut then
			return
		end
		laidOut = shape
		local top = header.height + GAP
		if portrait then
			local maxH = MAP_SHARE_PORTRAIT * size.Y - LENS_H
			local mapH = LENS_H + math.floor(math.min(size.X / map:aspectFor(size.X, maxH), maxH))
			mapArea.Position = UDim2.fromOffset(0, top)
			mapArea.Size = UDim2.new(1, 0, 0, mapH)
			mapHolder.Size = UDim2.fromScale(1, 1)
			below.Visible = false
			panel.Position = UDim2.fromOffset(0, top + mapH + GAP)
			panel.Size = UDim2.new(1, 0, 1, -(top + mapH + GAP))
		elseif compact then
			-- A landscape phone (D-089): the map the whole height on the left,
			-- as wide as it is at that height (never narrower than its chips),
			-- the panel on the right; the legend and board go in the panel.
			local mapH = size.Y - top - LENS_H
			local maxW = math.floor(size.X * COMPACT_MAP_SHARE)
			local chipsW = LensToggle.WIDTH + LensToggle.CLOSE_W + Kit.space.xs
			local mapW = if maxW > 0 and mapH > 0
				then math.floor(math.min(maxW, mapH * map:aspectFor(maxW, mapH)))
				else maxW
			local areaW = math.clamp(mapW, math.min(chipsW, maxW), math.max(maxW, 0))
			mapArea.Position = UDim2.fromOffset(0, top)
			mapArea.Size = UDim2.new(0, areaW, 1, -top)
			mapHolder.Size = UDim2.fromScale(1, 1)
			below.Visible = false
			panel.Position = UDim2.fromOffset(areaW + GAP, top)
			panel.Size = UDim2.new(1, -(areaW + GAP), 1, -top)
		else
			-- The map reveal and a round's reveal have only the legend's note under
			-- the map (the board is in the panel): a bigger map.
			local share = if mode == "Input" then MAP_HEIGHT_SHARE else REVEAL_MAP_HEIGHT_SHARE
			mapArea.Position = UDim2.fromOffset(0, top)
			-- The map reveal's panel lists the strongholds in two columns: a bit wider.
			local across = if mode == "Map" then MAP_SHARE_REVEAL else MAP_SHARE
			mapArea.Size = UDim2.new(across, -GAP // 2, 1, -top)
			mapHolder.Size = UDim2.fromScale(1, share)
			below.Position = UDim2.new(0, 0, share, GAP)
			below.Size = UDim2.new(1, 0, 1 - share, -GAP)
			below.Visible = true
			panel.Position = UDim2.new(across, GAP // 2, 0, top)
			panel.Size = UDim2.new(1 - across, -GAP // 2, 1, -top)
		end
	end

	-- Where the legend and the board go. Wide: the legend's keys beside the lens
	-- chips, its note and the board under the map. Phone: the legend in the panel
	-- during the map reveal, else both in the collapsed board card.
	local function place()
		-- A landscape phone places them as a phone does (D-089).
		local portrait = ctx.portrait() or Kit.compact(root.AbsoluteSize)
		local key = `{portrait}:{mode}`
		if key == placed then
			return
		end
		placed = key
		if portrait then
			legend.row.Parent = legend.root
			legend.root.LayoutOrder = if mode == "Map" then ORDER.legend else 1
			legend.root.Parent = if mode == "Map" then scroll else boardCard.body
			summary.root.LayoutOrder = 2
			summary.root.Parent = boardCard.body
			summary.root.Visible = true
		else
			legend.row.Parent = legendSlot
			legend.root.LayoutOrder = 1
			legend.root.Parent = below
			summary.root.LayoutOrder = 2
			summary.root.Parent = below
			-- During the map reveal the Strongholds card says it all; the board
			-- (still all dashes) would only repeat it.
			summary.root.Visible = mode ~= "Map"
		end
		-- A round's reveal: the board in its own card under the picks (D-091).
		if mode == "Reveal" then
			summary.root.LayoutOrder = 1
			summary.root.Parent = revealBoard
			summary.root.Visible = true
		end
		revealBoard.Visible = mode == "Reveal"
		legendSlot.Visible = not portrait
		boardCard.root.Visible = portrait and mode == "Input"
	end

	-- ------------------------------------------------------------ actions

	local function stateView(id: string): View.StateView?
		local view = lastView
		if view == nil then
			return nil
		end
		for _, sv in view.states do
			if sv.id == id then
				return sv
			end
		end
		return nil
	end

	local function isLocked(): boolean
		local state = current
		local payload: Session.StatePayload? = if state then state.payload else nil
		if payload == nil then
			return localLocked
		end
		return localLocked or payload.seats[payload.you].locked
	end

	local function dismissTip()
		local shown = tip
		if shown then
			shown:dismiss()
			tip = nil
		end
	end

	-- A tap on a map node or a list row.
	tapState = function(id: string)
		local kind: Draft.Kind? = lastKind
		if mode ~= "Input" or kind == nil or isLocked() then
			return
		end
		local sv = stateView(id)
		if sv == nil then
			return
		end
		if not Logic.legal(kind, sv) then
			hint = Logic.reason(kind, sv)
			local view = lastView
			if view then
				refused = Logic.why(kind, sv, view.you, Board.who(config, view, Logic.opponent(view)))
			end
			refresh()
			Motion.shake(bar.status)
			Audio.play("error")
			return
		end
		dismissTip()
		choices = Logic.tap(choices, id, target)
		target = nil
		hint = nil
		refused = nil
		refresh()
		local slot = if choices.first == id then 1 elseif choices.second == id then 2 else nil
		if slot then
			Motion.pop(choiceButtons[slot], PICK_FROM)
			map:pulse(id)
			Audio.play("planAdd")
		else
			Audio.play("planRemove")
		end
	end

	lockInPressed = function()
		local state = current
		local view = lastView
		if state == nil or view == nil or mode ~= "Input" or isLocked() or choices.first == nil then
			return
		end
		local list = Logic.list(choices)
		submitted = { round = view.draftRound, choices = list }
		localLocked = true
		messageAtLock = Messages.lastId(state)
		hint = nil
		autoLock:spent(state.payload)
		ctx.net.submit({ choices = list })
		refresh()
	end

	map:onSelect(function(id: string)
		tapState(id)
	end)

	-- ------------------------------------------------------------ rendering

	-- Fills one card of the reveal: "You got OH" and what it makes the state.
	local function fillCard(card: PickCard, who: string, pick: Logic.Pick?, color: Color3)
		local stroke = card.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end
		card.big.TextColor3 = Kit.textColor(color)
		if pick == nil then
			card.big.Text = `{who} got nothing`
			card.gain.Text = ""
			card.gain.Visible = false
			card.small.Text = ""
			card.kind.Visible = false
			return
		end
		card.big.Text = `{who} got {pick.state}`
		card.gain.Visible = true
		if card.gain:GetAttribute("For") ~= pick.state then
			-- What is at stake there: its votes, counted up as the card lands.
			card.gain:SetAttribute("For", pick.state)
			local record = StateData.byId[pick.state]
			local ev = if record then record.ev else 0
			Motion.countTo(card.gain, 0, ev, function(n: number): string
				return Words.votes(math.floor(n + 0.5))
			end, GAIN_SECONDS)
		end
		card.small.Text = Logic.nameOf(pick.state)
		card.kind.Visible = true
		card.kind.Text = Words.roundKind(pick.kind)
		if pick.kind == "Home" then
			Kit.paintPill(card.kind, "text", true, color)
		else
			Kit.paintPill(card.kind, "white")
		end
	end

	-- The header's title: shorter in portrait, where the timer shares one row.
	local function titleText(view: View.View, revealRound: number?): string
		local portrait = ctx.portrait()
		if mode == "Map" then
			return "The map"
		elseif mode == "Input" then
			return `Round {view.draftRound + 1} of {totalRounds}`
		end
		local round = (revealRound or view.draftRound) + 1
		return if portrait
			then `Round {round} revealed`
			else `Round {round} of {totalRounds} · picks revealed`
	end

	-- The countdown and its bar (the stage's own length: a bot match scales the
	-- round, D-075); a round without a deadline (the tutorial) says so.
	local function showTimer(payload: Session.StatePayload, now: number)
		local deadline = payload.deadline
		if deadline == nil then
			header:setNoTimer(Header.noTimerText(payload))
			return
		end
		header:setTimer(deadline - now, if mode == "Input" then nil else 0, deadline - payload.stageStart)
	end

	local function render()
		local state = current
		if state == nil then
			return
		end
		local payload: Session.StatePayload? = state.payload
		if payload == nil then
			return
		end
		local newMode: Mode = "Map"
		if payload.reveal == "Draft" then
			newMode = "Reveal"
		elseif payload.stage == "Input" and payload.view.phase == "Draft" then
			newMode = "Input"
		end
		mode = newMode
		applyLayout()

		local view = payload.view
		lastView = view
		local you = payload.you
		local them = Logic.opponent(view)
		local opponent = Board.who(config, view, them)
		local opponentLabel = if opponent == "Opponent" then "your opponent" else opponent

		-- A new step (map reveal, a round, its reveal) starts with a clean slate.
		local key = `{payload.matchId}:{payload.step}`
		if key ~= stepKey then
			stepKey = key
			choices = {}
			target = nil
			localLocked = false
			hint = nil
			refused = nil
			showAll = false
		end

		place()
		-- Nothing to press during the map reveal and a round's reveal (UI/Audit rule "primary").
		parent:SetAttribute("PrimaryOptional", mode ~= "Input")

		local serverLocked = payload.seats[you].locked
		-- A rejected lock-in leaves a message and no lock: let the player fix it.
		local rejection = Messages.rejectionAfter(state, messageAtLock)
		if localLocked and not serverLocked and rejection ~= nil then
			localLocked = false
			hint = rejection.text
		end
		local locked = localLocked or serverLocked

		local kind: Draft.Kind? = if mode == "Input" then view.draftKind else nil
		lastKind = kind

		-- The coach tip, once, the first time there is something to pick.
		-- It floats over the map's upper left, under the lens chips (D-091), so
		-- the slots and the best picks keep the panel's first screen; the first
		-- tap dismisses it.
		if mode == "Input" and not locked and tip == nil then
			tip = CoachTip.show(mapArea, {
				id = "draft.pick",
				position = UDim2.fromOffset(0, LENS_H + Kit.space.xs),
				anchorPoint = Vector2.new(0, 0),
				width = math.max(0, math.min(TIP_W, mapArea.AbsoluteSize.X)),
			})
		elseif mode ~= "Input" then
			dismissTip()
		end

		-- Colors by player index.
		local rgb: { Colors.RGB } = {}
		local colors: { Color3 } = {}
		for p, player in view.players do
			rgb[p] = Colors.of(player.color)
			colors[p] = Kit.color(rgb[p])
		end

		-- What the reveal shows.
		local picks = Logic.picks(payload.events)
		local mine: Logic.Pick? = nil
		local theirs: Logic.Pick? = nil
		for _, pick in picks do
			if pick.player == you then
				mine = pick
			elseif pick.player == them then
				theirs = pick
			end
		end
		local revealRound = Logic.lastRound(view)

		-- Header, the now line and who wins ties.
		header:setTitle(titleText(view, revealRound))
		local portrait = ctx.portrait()
		local compactNow = not portrait and Kit.compact(root.AbsoluteSize)
		local priorityLine = ""
		if mode == "Map" then
			header:setSubtitle(nil)
			header:setNow(Words.NOW_MAP)
			local first = Logic.priorityPlayer(config, view, 0)
			priorityLine = `Round 1: {string.lower(Words.priority(first == you, opponent))}`
		elseif mode == "Input" and kind ~= nil then
			-- A landscape phone folds "ties go to …" into the subtitle and drops
			-- the pill row, so the slots and the list start higher (D-091).
			local ties = Words.priority((view.draftPriority or you) == you, opponent)
			header:setSubtitle(
				if portrait
					then nil
					elseif compactNow then `{Words.roundKind(kind)} · {string.lower(
						string.sub(ties, 1, 1)
					)}{string.sub(ties, 2)}`
					else Words.roundKind(kind)
			)
			header:setNow(
				if locked then Words.nowWaiting(opponentLabel) else Words.nowDraft(kind, choices.first ~= nil)
			)
			priorityLine = Words.priority((view.draftPriority or you) == you, opponent)
		else
			header:setSubtitle(nil)
			local round = revealRound or view.draftRound
			if round + 1 < totalRounds then
				local nextKind: Draft.Kind = Draft.kind(config, round + 1)
				header:setNow(`Next: round {round + 2}, {Logic.noun(nextKind)}`)
			else
				header:setNow("The draft is over. The campaign begins!")
			end
		end
		priority.Text = priorityLine
		roundPill.Text = if kind then Words.roundKind(kind) else ""
		-- A battleground round wears the battleground mark (★, white outline;
		-- D-058); the home round is a plain tag.
		Kit.paintPill(roundPill, if kind ~= nil and kind ~= "Home" then "white" else "text")
		roundPill.Visible = kind ~= nil
		priorityRow.Visible = priorityLine ~= "" and mode ~= "Reveal" and not (compactNow and mode == "Input")
		local battleground = mode == "Input" and kind ~= nil and kind ~= "Home"
		-- A landscape phone keeps only the warning: the subtitle says
		-- "Battleground" and the rule is in How the draft works.
		roundCaption.Visible = battleground and not compactNow
		-- Your strongholds still standing, which the rival may nominate (D-091).
		local standing = Drafted.strongholds(view, you)
		local warn = battleground and #standing > 0
		strongholdWarning.Visible = warn
		if warn then
			strongholdWarning.Text = Words.strongholdWarning(opponent, standing)
		end
		roundNote.Visible = roundCaption.Visible or warn
		roundBar.Color = if warn then Kit.colors.warn else Kit.colors.line
		noticeBox.Visible = mode == "Input" and refused ~= nil
		notice.Text = refused or ""

		strongholds.root.Visible = mode == "Map"
		strongholds:update(config, view, colors)
		sheetStrongholds.Text = Logic.strongholdsLine(view, you) or ""

		-- The ranked slots.
		slots.Visible = mode == "Input"
		for slot = 1, 2 do
			local id = if slot == 1 then choices.first else choices.second
			local button = choiceButtons[slot]
			button.Text = Logic.slotText(slot, id)
			-- The number's badge: filled once a state is in the slot.
			local badge = slotBadges[slot]
			badge.BackgroundTransparency = if id ~= nil then 0 else 1
			badge.TextColor3 = if id ~= nil then Kit.colors.onAccent else Kit.colors.muted
			local ring = badge:FindFirstChild("Ring") :: UIStroke?
			if ring then
				ring.Color = if id ~= nil then Kit.colors.accent else Kit.colors.muted
			end
			local filled = id ~= nil and not locked
			clearButtons[slot].Visible = filled
			button.Size = if filled
				then UDim2.new(1, -(Kit.MIN_TOUCH + Kit.space.xs), 1, 0)
				else UDim2.fromScale(1, 1)
			Kit.setEnabled(button, not locked)
			Kit.setSelected(button, target == slot and not locked)
			Kit.setEnabled(clearButtons[slot], filled)
		end

		-- The reveal.
		revealBox.Visible = mode == "Reveal"
		if mode == "Reveal" then
			fillCard(youCard, "You", mine, colors[you])
			fillCard(themCard, opponent, theirs, colors[them])
			local note: string? = nil
			if mine ~= nil and theirs ~= nil and revealRound ~= nil then
				local sub = submitted
				note = Logic.clashNote(
					mine.state,
					theirs.state,
					if sub and sub.round == revealRound then sub.choices else nil,
					Logic.priorityPlayer(config, view, revealRound) == them
				)
			end
			clashNote.Text = note or ""
			clashNote.Visible = note ~= nil
		end

		-- The action bar.
		bar.root.Visible = mode == "Input"
		scroll.Size = if mode == "Input"
			then UDim2.new(1, 0, 1, -(Kit.BAR_H + GAP))
			else UDim2.fromScale(1, 1)
		if locked then
			bar:setPrimary("Locked in", false)
		elseif choices.first == nil then
			bar:setPrimary("Pick a state", false)
		else
			bar:setPrimary("Lock in", true)
		end
		local why = hint
		if why ~= nil then
			bar:setStatus(why, "bad")
		elseif locked then
			bar:setStatus("Locked in", "muted")
		elseif choices.first == nil then
			bar:setStatus("Tap the map or a row", "muted")
		elseif choices.second == nil then
			bar:setStatus("A backup is optional", "muted")
		else
			bar:setStatus("Your 2nd is the backup", "muted")
		end
		local theirSeat = payload.seats[them]
		if theirSeat ~= nil and not theirSeat.connected then
			bar:setOpponent(`{opponent}: disconnected`)
		elseif theirSeat ~= nil and theirSeat.locked then
			bar:setOpponent(`{opponent}: locked in`)
		else
			bar:setOpponent(`{opponent}: picking`)
		end

		-- The map.
		map:setView(view, rgb)
		local marks: { [string]: MapInterface.Mark } = {}
		-- The Votes lens already stars a battleground's number ("★13") on a
		-- wide screen; the other lenses, and a phone's small circles (no number
		-- inside), need the star tag on the rim.
		local starTag = Lens.current() ~= "EV" or portrait
		for _, sv in view.states do
			local mark: MapInterface.Mark = {}
			local owner = sv.owner
			if owner ~= nil and colors[owner] then
				mark.ring = colors[owner]
			end
			-- Home: "H" filled in its owner's color. Battleground: the outlined
			-- star tag (D-058), never a white fill.
			if sv.isHome then
				mark.badge = "H"
				mark.badgeColor = if owner ~= nil then colors[owner] else nil
			elseif sv.battleground and starTag then
				mark.note = Kit.STAR
				mark.noteColor = Kit.colors.text
			end
			if kind ~= nil and not Logic.legal(kind, sv) then
				mark.dim = true
			end
			marks[sv.id] = mark
		end
		if mode == "Input" then
			local picked: { string } = Logic.list(choices)
			for slot, id in picked do
				local mark = marks[id]
				if mark then
					-- A pick is a selection: its number on a dark tag outlined in
					-- white, like the white ring around it.
					mark.badge = nil
					mark.note = tostring(slot)
					mark.noteColor = Kit.colors.accent
					mark.ring = Kit.colors.accent
				end
			end
		end
		if mode == "Reveal" then
			-- Light up what was just taken in its taker's color.
			for _, pick in picks do
				local mark = marks[pick.state]
				if mark and colors[pick.player] then
					mark.ring = colors[pick.player]
					if pick.kind == "Home" then
						mark.badge = "H"
						mark.badgeColor = colors[pick.player]
						mark.note = nil
					elseif pick.kind == "Nominate" and starTag then
						mark.badge = nil
						mark.note = Kit.STAR
						mark.noteColor = Kit.colors.text
					end
				end
			end
		end
		map:setMarks(marks)
		map:setLens(Lens.lines(Lens.current(), { config = config, view = view }))
		map:setLegend(Lens.mapLegend({ config = config, view = view }, Lens.current()))
		map:select(if mode == "Input" then choices.first elseif mine then mine.state else nil)

		-- A round's picks arriving: both cards pop, each state rings once.
		if mode == "Reveal" and revealRound ~= nil and revealRound ~= revealedRound then
			revealedRound = revealRound
			Motion.stagger({ youCard.frame, themCard.frame }, function(card, _index, delay)
				Motion.pop(card, REVEAL_FROM, delay)
			end)
			local landed: { Logic.Pick } = {}
			if mine then
				table.insert(landed, mine)
			end
			if theirs then
				table.insert(landed, theirs)
			end
			for _, pick in landed do
				local color = colors[pick.player]
				if color then
					map:ring(pick.state, color)
				end
				map:pulse(pick.state)
			end
			Audio.play("whoosh")
		end

		-- Legend, board and the list.
		legend:update(view, rgb, opponent)
		summary:update(config, view, colors)
		stateList:update({
			view = view,
			kind = kind,
			colors = colors,
			choices = if mode == "Input" then choices else {},
			interactive = mode == "Input" and not locked,
			showAll = showAll,
			opponent = opponent,
		})
		stateList.root.Visible = mode == "Input"
		showAllButton.Visible = mode == "Input" and (showAll or stateList:hidden() > 0)
		showAllButton.Text = if showAll then "Show fewer states" else "Show all states"
		howButton.Visible = mode ~= "Reveal"

		-- Countdown: it only warns while there is something to lock in.
		showTimer(payload, ctx.now())
	end
	refresh = render

	-- The lens chips over the map, at its right (Map/LensToggle, D-046).
	local chips = LensToggle.new(mapHolder, function()
		render()
	end)
	chips.root.AnchorPoint = Vector2.new(1, 0)
	chips.root.Position = UDim2.fromScale(1, 0)
	-- The Close filter left of them (D-079).
	local closeChip = LensToggle.close(mapHolder, function()
		render()
	end)
	LensToggle.row(mapHolder, chips, closeChip) -- narrows the tabs where both do not fit (D-092)

	return {
		update = function(state: Types.State)
			current = state
			render()
		end,
		tick = function(now: number)
			local state = current
			local payload: Session.StatePayload? = if state then state.payload else nil
			if payload == nil then
				return
			end
			local shape = laidOut
			applyLayout()
			if shape ~= laidOut then
				-- Rotated or resized: titles and the legend's place depend on it.
				render()
			end
			showTimer(payload, now)
			-- The last seconds: Lock in drains while there is a pick to lock.
			local deadline = payload.deadline
			pickClock:paint(
				if deadline then deadline - now else nil,
				mode == "Input" and not isLocked() and choices.first ~= nil
			)
			-- The timer is about to end with a pick that was never locked: lock it.
			if mode == "Input" and choices.first ~= nil and autoLock:due(payload, now, isLocked()) then
				lockInPressed()
			end
		end,
		destroy = function()
			map:destroy()
			root:Destroy()
		end,
	}
end

return Screen
