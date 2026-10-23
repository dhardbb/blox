--!strict
-- Draft screen: the map reveal, then eight blind draft rounds (PLAN.md "Draft").
-- Each round the player fills a ranked top 2 by tapping the map or the state list
-- and locks it in; after the round both picks are revealed together. The screen
-- reads only the player's own View and sends only { choices = { first, second? } }.
--
-- Layout (docs/UI-OVERHAUL.md §3.3), every big box explicitly positioned:
--   Header     "Round 4 of 8 · Stronghold" · the round's help line · timer
--   16:9       map 65 % on the left (legend and draft board under it, in Below),
--              panel 35 % on the right
--   portrait   map on top, min(width / ASPECT, 34 % of the height) px tall, the
--              panel right under it (pixel math, no dead band)
--   panel      priority line → slots row (1st / 2nd chips, each with a ×) → the
--              state list → (portrait) a collapsed "Draft board" card at the end.
--              The map reveal shows the legend and how the draft works instead;
--              a round's reveal shows both picks above the list.
--   ActionBar  pinned under the panel while picking: status (tone bad for an
--              illegal tap, until the next tap), opponent, primary "Lock in".
--
-- Stable names for tests and agents: LockIn (the primary), Choice1, Choice2,
-- Clear1, Clear2, Row_<id>, the map nodes by id, Priority, Explain (the header
-- subtitle), Timer, StateList, Board, Legend, BoardCard, RevealBox, YouPick,
-- ThemPick, ClashNote, HowItWorks, BarStatus, BarOpponent, MapArea, Panel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Draft = require(ReplicatedStorage.Shared.Sim.Draft)
local MapLayout = require(ReplicatedStorage.Shared.UI.MapLayout)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local View = require(ReplicatedStorage.Shared.Sim.View)

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local AutoLock = require(script.Parent.Common.AutoLock)
local Board = require(script.Parent.DraftParts.Board)
local Collapsible = require(script.Parent.Parent.UI.Collapsible)
local Header = require(script.Parent.Parent.UI.Header)
local Kit = require(script.Parent.Parent.UI.Kit)
local Lens = require(script.Parent.Parent.Map.Lens)
local LensToggle = require(script.Parent.Parent.Map.LensToggle)
local Logic = require(script.Parent.DraftParts.Logic)
local MapInterface = require(script.Parent.Parent.Map.MapInterface)
local Messages = require(script.Parent.Common.Messages)
local NodeMap = require(script.Parent.Parent.Map.NodeMap)
local StateList = require(script.Parent.DraftParts.StateList)
local Types = require(script.Parent.Types)

local Screen = {}

local GAP = Kit.space.sm -- px, between the big blocks
local MAP_SHARE = 0.65 -- of the width, wide screens
local MAP_HEIGHT_SHARE = 0.66 -- of the map column, wide screens (the rest is Below)
local MAP_SHARE_PORTRAIT = 0.34 -- of the height at most, phones (before the lens row)
local LENS_H = LensToggle.HEIGHT + Kit.space.xs -- px, the lens row over the map

-- Panel order (PanelScroll's list).
local ORDER = {
	priority = 1,
	slots = 2,
	howItWorks = 3,
	legend = 4, -- map reveal only
	reveal = 5,
	list = 6,
	boardCard = 7, -- portrait only, always last
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
	local laidOut = "" -- the shape applyLayout last laid out for
	local placed = "" -- where the legend and board last went
	local mode: Mode = "Map"
	local lastView: View.View? = nil
	local lastKind: Draft.Kind? = nil

	-- ------------------------------------------------------------ layout

	local root = Kit.box({ Name = "DraftRoot", Parent = parent })
	local header = Header.new(root, { title = "", onHelp = ctx.help })
	header.subtitle.Name = "Explain"

	local mapArea = Kit.box({ Name = "MapArea", Parent = root })
	local mapHolder = Kit.box({ Name = "MapHolder", Parent = mapArea })
	local map = NodeMap.new()
	map.root.AnchorPoint = Vector2.new(0.5, 0)
	map.root.Position = UDim2.new(0.5, 0, 0, LENS_H)
	map.root.Size = UDim2.new(1, 0, 1, -LENS_H)
	map.root.Parent = mapHolder

	-- Wide screens: legend and board under the map (scrolls if the screen is short).
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

	local priority = Kit.caption("", { Name = "Priority", LayoutOrder = ORDER.priority, Parent = scroll })

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
	for slot = 1, 2 do
		local half = Kit.box({
			Name = `Slot{slot}`,
			Position = UDim2.new((slot - 1) * 0.5, if slot == 2 then GAP // 2 else 0, 0, 0),
			Size = UDim2.new(0.5, -GAP // 2, 1, 0),
			Parent = slots,
		})
		choiceButtons[slot] = Kit.button("", function()
			if mode == "Input" and not localLocked then
				target = if target == slot then nil else slot
				hint = nil
				refresh()
			end
		end, {
			variant = "chip",
			Name = `Choice{slot}`,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = half,
		})
		clearButtons[slot] = Kit.iconButton("×", function()
			if mode == "Input" and not localLocked then
				choices = Logic.clear(choices, slot)
				target = nil
				hint = nil
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

	-- The map reveal: how the draft works.
	local howItWorks = Kit.caption(Logic.howItWorks(totalRounds), {
		Name = "HowItWorks",
		TextColor3 = Kit.colors.text,
		LayoutOrder = ORDER.howItWorks,
		Visible = false,
		Parent = scroll,
	})

	-- The reveal: what each of you got, side by side, and the clash note.
	local revealBox = Kit.box(
		merge(auto(), { Name = "RevealBox", LayoutOrder = ORDER.reveal, Visible = false, Parent = scroll })
	)
	Kit.list("Vertical", Kit.space.xs).Parent = revealBox
	local revealRow = Kit.box(merge(auto(), { Name = "RevealRow", LayoutOrder = 1, Parent = revealBox }))
	Kit.list("Horizontal", GAP).Parent = revealRow
	local function pickCard(name: string, order: number): (Frame, TextLabel, TextLabel)
		local frame = Kit.panel({
			Name = name,
			Size = UDim2.new(0.5, -GAP // 2, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Kit.colors.raised,
			LayoutOrder = order,
			Parent = revealRow,
		})
		Kit.list("Vertical", Kit.space.xs).Parent = frame
		Kit.stroke(Kit.colors.accent, 2).Parent = frame
		local big = Kit.heading("", { Name = "Title", LayoutOrder = 1, Parent = frame })
		local small = Kit.caption("", { Name = "Sub", LayoutOrder = 2, Parent = frame })
		return frame, big, small
	end
	local youCard, youBig, youSmall = pickCard("YouPick", 1)
	local themCard, themBig, themSmall = pickCard("ThemPick", 2)
	local clashNote = Kit.text(
		"",
		merge(
			auto(),
			{ Name = "ClashNote", TextColor3 = Kit.colors.accent, LayoutOrder = 2, Parent = revealBox }
		)
	)

	local stateList = StateList.new(function(id: string)
		tapState(id)
	end)
	stateList.root.LayoutOrder = ORDER.list
	stateList.root.Parent = scroll

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

	-- ------------------------------------------------------------ orientation

	-- Lays the screen out for its current size (re-run when it changes). Phones
	-- get pixel math so the panel starts exactly GAP under the map.
	local function applyLayout()
		local portrait = ctx.portrait()
		local size = root.AbsoluteSize
		local shape = `{portrait}:{size.X}x{size.Y}`
		if shape == laidOut then
			return
		end
		laidOut = shape
		local top = Kit.HEADER_H + GAP
		if portrait then
			local mapH = LENS_H
				+ math.floor(math.min(size.X / MapLayout.ASPECT, MAP_SHARE_PORTRAIT * size.Y - LENS_H))
			mapArea.Position = UDim2.fromOffset(0, top)
			mapArea.Size = UDim2.new(1, 0, 0, mapH)
			mapHolder.Size = UDim2.fromScale(1, 1)
			below.Visible = false
			panel.Position = UDim2.fromOffset(0, top + mapH + GAP)
			panel.Size = UDim2.new(1, 0, 1, -(top + mapH + GAP))
		else
			mapArea.Position = UDim2.fromOffset(0, top)
			mapArea.Size = UDim2.new(MAP_SHARE, -GAP // 2, 1, -top)
			mapHolder.Size = UDim2.fromScale(1, MAP_HEIGHT_SHARE)
			below.Position = UDim2.new(0, 0, MAP_HEIGHT_SHARE, GAP)
			below.Size = UDim2.new(1, 0, 1 - MAP_HEIGHT_SHARE, -GAP)
			below.Visible = true
			panel.Position = UDim2.new(MAP_SHARE, GAP // 2, 0, top)
			panel.Size = UDim2.new(1 - MAP_SHARE, -GAP // 2, 1, -top)
		end
	end

	-- Where the legend and the board go: the map reveal shows the legend in the
	-- panel; otherwise both sit under the map (16:9) or in the board card (portrait).
	local function place()
		local portrait = ctx.portrait()
		local key = `{portrait}:{mode}`
		if key == placed then
			return
		end
		placed = key
		if mode == "Map" then
			legend.root.LayoutOrder = ORDER.legend
			legend.root.Parent = scroll
		else
			legend.root.LayoutOrder = 1
			legend.root.Parent = if portrait then boardCard.body else below
		end
		summary.root.LayoutOrder = 2
		summary.root.Parent = if portrait then boardCard.body else below
		boardCard.root.Visible = portrait
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
			refresh()
			return
		end
		choices = Logic.tap(choices, id, target)
		target = nil
		hint = nil
		refresh()
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
	local function fillCard(
		frame: Frame,
		big: TextLabel,
		small: TextLabel,
		who: string,
		pick: Logic.Pick?,
		color: Color3
	)
		local stroke = frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end
		big.TextColor3 = color
		if pick == nil then
			big.Text = `{who} got nothing`
			small.Text = ""
			return
		end
		big.Text = `{who} got {pick.state}`
		small.Text = `{Logic.nameOf(pick.state)} · {Logic.noun(pick.kind)}`
	end

	-- The header's title: shorter in portrait, where the timer shares one row.
	local function titleText(view: View.View, kind: Draft.Kind?, revealRound: number?): string
		local portrait = ctx.portrait()
		if mode == "Map" then
			return if portrait then "The map" else "The map for this match"
		elseif mode == "Input" and kind ~= nil then
			local round = `Round {view.draftRound + 1} of {totalRounds}`
			return if portrait then round else `{round} · {Logic.title(kind)}`
		end
		local round = (revealRound or view.draftRound) + 1
		return if portrait
			then `Round {round} revealed`
			else `Round {round} of {totalRounds} · picks revealed`
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
		applyLayout()

		local view = payload.view
		lastView = view
		local you = payload.you
		local them = Logic.opponent(view)

		-- A new step (map reveal, a round, its reveal) starts with a clean slate.
		local key = `{payload.matchId}:{payload.step}`
		if key ~= stepKey then
			stepKey = key
			choices = {}
			target = nil
			localLocked = false
			hint = nil
		end

		local newMode: Mode = "Map"
		if payload.reveal == "Draft" then
			newMode = "Reveal"
		elseif payload.stage == "Input" and view.phase == "Draft" then
			newMode = "Input"
		end
		mode = newMode
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

		-- Header and priority.
		header:setTitle(titleText(view, kind, revealRound))
		local priorityLine = ""
		if mode == "Map" then
			header:setSubtitle(
				"Each state leans a few points toward one candidate. Leans are exact and public."
			)
			priorityLine = Logic.priorityIn(Logic.priorityPlayer(config, view, 0), you, 0)
		elseif mode == "Input" and kind ~= nil then
			header:setSubtitle(Logic.help(config, kind))
			priorityLine = Logic.priorityText(view.draftPriority or you, you)
		else
			local round = revealRound or view.draftRound
			if round + 1 < totalRounds then
				local nextKind: Draft.Kind = Draft.kind(config, round + 1)
				header:setSubtitle(`Next: round {round + 2} of {totalRounds}, {Logic.noun(nextKind)}.`)
			else
				header:setSubtitle("The draft is over. Polls come out and the campaign begins.")
			end
			if revealRound ~= nil then
				priorityLine = Logic.priorityWas(Logic.priorityPlayer(config, view, revealRound), you)
			end
		end
		priority.Text = priorityLine
		priority.Visible = priorityLine ~= ""
		howItWorks.Visible = mode == "Map"

		-- The ranked slots.
		slots.Visible = mode == "Input"
		for slot = 1, 2 do
			local id = if slot == 1 then choices.first else choices.second
			local button = choiceButtons[slot]
			local label = if slot == 1 then "1st" else "2nd"
			button.Text = `{label}: {id or "—"}`
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
			fillCard(youCard, youBig, youSmall, "You", mine, colors[you])
			fillCard(themCard, themBig, themSmall, "They", theirs, colors[them])
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
			bar:setStatus("Locked in · waiting for opponent", "ok")
		elseif choices.first == nil then
			bar:setStatus("Choose your 1st choice", "muted")
		elseif choices.second == nil then
			bar:setStatus("Tap a backup (optional)", "muted")
		else
			bar:setStatus("Ready: your 2nd is the backup", "muted")
		end
		local theirSeat = payload.seats[them]
		if theirSeat ~= nil and not theirSeat.connected then
			bar:setOpponent("Opponent: disconnected")
		elseif theirSeat ~= nil and theirSeat.locked then
			bar:setOpponent("Opponent: locked in")
		else
			bar:setOpponent("Opponent: thinking")
		end

		-- The map.
		map:setView(view, rgb)
		local marks: { [string]: MapInterface.Mark } = {}
		for _, sv in view.states do
			local mark: MapInterface.Mark = {}
			local owner = sv.owner
			if owner ~= nil and colors[owner] then
				mark.ring = colors[owner]
			end
			if sv.isHome then
				mark.badge = "H"
			elseif sv.battleground then
				mark.badge = "B"
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
					mark.badge = tostring(slot)
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
					mark.badge = if pick.kind == "Home"
						then "H"
						elseif pick.kind == "Nominate" then "B"
						else mark.badge
				end
			end
		end
		map:setMarks(marks)
		map:setLens(Lens.lines(Lens.current(), { config = config, view = view }))
		map:select(if mode == "Input" then choices.first elseif mine then mine.state else nil)

		-- Legend, board and the list.
		legend:update(view, rgb)
		summary:update(config, view, colors)
		stateList:update({
			view = view,
			kind = kind,
			colors = colors,
			choices = if mode == "Input" then choices else {},
			interactive = mode == "Input" and not locked,
		})
		stateList.root.Visible = mode ~= "Map"

		-- Countdown: it only warns while there is something to lock in.
		header:setTimer(payload.deadline - ctx.now(), if mode == "Input" then nil else 0)
	end
	refresh = render

	-- The lens chips over the map (Map/LensToggle, D-044).
	LensToggle.bar(mapHolder, config, function()
		render()
	end)

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
			header:setTimer(payload.deadline - now, if mode == "Input" then nil else 0)
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
