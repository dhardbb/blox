--!strict
-- Draft screen: the map reveal, then eight blind draft rounds (PLAN.md "Draft").
-- Each round the player fills a ranked top 2 by tapping the map or the state list
-- and locks it in; after the round both picks are revealed together. The screen
-- reads only the player's own View and sends only { choices = { first, second? } }.
--
-- Wide screens: map on the left with the legend and draft board under it, the
-- panel (round info, choice slots, state list) on the right. Phones in portrait:
-- map on top, the same panel below it. The Lock In bar stays pinned at the bottom
-- of the panel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Draft = require(ReplicatedStorage.Shared.Sim.Draft)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local View = require(ReplicatedStorage.Shared.Sim.View)

local AutoLock = require(script.Parent.Common.AutoLock)
local Board = require(script.Parent.DraftParts.Board)
local Kit = require(script.Parent.Parent.UI.Kit)
local Logic = require(script.Parent.DraftParts.Logic)
local MapInterface = require(script.Parent.Parent.Map.MapInterface)
local Messages = require(script.Parent.Common.Messages)
local NodeMap = require(script.Parent.Parent.Map.NodeMap)
local StateList = require(script.Parent.DraftParts.StateList)
local Types = require(script.Parent.Types)

local Screen = {}

local LOCK_BAR = 104 -- px, the pinned Lock In bar
local GAP = 8
local HINT_SECONDS = 3 -- how long a "can't pick that" hint stays up

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
	local localLocked = false -- pressed Lock In; the server's lock arrives with the next payload
	local messageAtLock = 0 -- id of the newest message when Lock In was pressed
	local autoLock = AutoLock.new()
	local submitted: { round: number, choices: { string } }? = nil
	local hint: string? = nil
	local hintUntil = 0
	local portraitMode: boolean? = nil
	local mode: Mode = "Map"
	local lastView: View.View? = nil
	local lastKind: Draft.Kind? = nil

	-- ------------------------------------------------------------ layout

	local root = Kit.box({ Name = "DraftRoot", Parent = parent })

	local mapArea = Kit.box({ Name = "MapArea", Parent = root })
	local mapHolder = Kit.box({ Name = "MapHolder", Parent = mapArea })
	local map = NodeMap.new()
	map.root.AnchorPoint = Vector2.new(0.5, 0)
	map.root.Position = UDim2.fromScale(0.5, 0)
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
	Kit.list("Vertical", 6).Parent = below

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
	Kit.new("UIPadding", { PaddingRight = UDim.new(0, 10), Parent = scroll })

	-- ------------------------------------------------------------ panel contents

	local header = Kit.text(
		"",
		merge(auto(), {
			Name = "Header",
			Font = Kit.font.bold,
			TextSize = 22,
			LayoutOrder = 1,
			Parent = scroll,
		})
	)
	local explain = Kit.text(
		"",
		merge(auto(), {
			Name = "Explain",
			TextSize = 15,
			TextColor3 = Kit.colors.muted,
			LayoutOrder = 2,
			Parent = scroll,
		})
	)

	local infoRow = Kit.box({
		Name = "InfoRow",
		Size = UDim2.new(1, 0, 0, 48),
		LayoutOrder = 3,
		Parent = scroll,
	})
	local priority = Kit.text("", {
		Name = "Priority",
		Size = UDim2.new(1, -96, 1, 0),
		Font = Kit.font.medium,
		Parent = infoRow,
	})
	local timer = Kit.text("", {
		Name = "Timer",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 90, 1, 0),
		Font = Kit.font.bold,
		TextScaled = true,
		TextSize = 30,
		TextColor3 = Kit.colors.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = infoRow,
	})

	-- The ranked top 2.
	local slots = Kit.box(merge(auto(), { Name = "Slots", LayoutOrder = 4, Parent = scroll }))
	Kit.list("Vertical", 6).Parent = slots
	local refresh: () -> () = function() end
	local tapState: (id: string) -> () = function(_id: string) end
	local lockInPressed: () -> () = function() end

	local choiceButtons: { TextButton } = {}
	local clearButtons: { TextButton } = {}
	for slot = 1, 2 do
		local row = Kit.box({
			Name = `SlotRow{slot}`,
			Size = UDim2.new(1, 0, 0, 48),
			LayoutOrder = slot,
			Parent = slots,
		})
		choiceButtons[slot] = Kit.button("", function()
			if mode == "Input" and not localLocked then
				target = if target == slot then nil else slot
				refresh()
			end
		end, {
			Name = `Choice{slot}`,
			Size = UDim2.new(1, -80, 1, 0),
			TextWrapped = true,
			Parent = row,
		})
		clearButtons[slot] = Kit.button("Clear", function()
			if mode == "Input" and not localLocked then
				choices = Logic.clear(choices, slot)
				target = nil
				refresh()
			end
		end, {
			Name = `Clear{slot}`,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 72, 1, 0),
			Parent = row,
		})
	end
	local clearAll = Kit.button("Clear both", function()
		if mode == "Input" and not localLocked then
			choices = {}
			target = nil
			refresh()
		end
	end, { Name = "ClearChoices", LayoutOrder = 3, Parent = slots })
	local hintLabel = Kit.text(
		"",
		merge(auto(), {
			Name = "Hint",
			TextSize = Kit.size.caption,
			LayoutOrder = 4,
			Parent = slots,
		})
	)

	-- The reveal: what each of you got.
	local revealBox =
		Kit.box(merge(auto(), { Name = "RevealBox", LayoutOrder = 5, Visible = false, Parent = scroll }))
	Kit.list("Vertical", 6).Parent = revealBox
	local function chip(name: string, order: number): (Frame, TextLabel, TextLabel)
		local frame = Kit.panel(
			merge(
				auto(),
				{ Name = name, BackgroundColor3 = Kit.colors.raised, LayoutOrder = order, Parent = revealBox }
			)
		)
		Kit.list("Vertical", 2).Parent = frame
		local stroke = Kit.stroke(Kit.colors.accent, 2)
		stroke.Parent = frame
		local big = Kit.text(
			"",
			merge(
				auto(),
				{ Name = "Title", Font = Kit.font.bold, TextSize = 22, LayoutOrder = 1, Parent = frame }
			)
		)
		local small = Kit.text(
			"",
			merge(auto(), {
				Name = "Sub",
				TextSize = Kit.size.caption,
				TextColor3 = Kit.colors.muted,
				LayoutOrder = 2,
				Parent = frame,
			})
		)
		return frame, big, small
	end
	local youChip, youBig, youSmall = chip("YouPick", 1)
	local themChip, themBig, themSmall = chip("ThemPick", 2)
	local clashNote = Kit.text(
		"",
		merge(
			auto(),
			{ Name = "ClashNote", TextColor3 = Kit.colors.accent, LayoutOrder = 3, Parent = revealBox }
		)
	)

	local legend = Board.newLegend()
	local summary = Board.newSummary()

	local stateList = StateList.new(function(id: string)
		tapState(id)
	end)
	stateList.root.LayoutOrder = 8
	stateList.root.Parent = scroll

	-- Lock In, pinned under the scrolling panel.
	local lockBar = Kit.box({
		Name = "LockBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, LOCK_BAR),
		Visible = false,
		Parent = panel,
	})
	Kit.list("Vertical", 4).Parent = lockBar
	local lockIn = Kit.button("Lock In", function()
		lockInPressed()
	end, {
		Name = "LockIn",
		Size = UDim2.new(1, 0, 0, 52),
		TextSize = 20,
		Font = Kit.font.bold,
		BackgroundColor3 = Kit.colors.accent,
		TextColor3 = Kit.colors.background,
		LayoutOrder = 1,
		Parent = lockBar,
	})
	local lockStatus = Kit.text("", {
		Name = "LockStatus",
		Size = UDim2.new(1, 0, 0, 20),
		TextScaled = true,
		TextSize = 15,
		Font = Kit.font.medium,
		LayoutOrder = 2,
		Parent = lockBar,
	})
	local opponentStatus = Kit.text("", {
		Name = "OpponentStatus",
		Size = UDim2.new(1, 0, 0, 20),
		TextScaled = true,
		TextSize = 15,
		TextColor3 = Kit.colors.muted,
		LayoutOrder = 3,
		Parent = lockBar,
	})

	-- ------------------------------------------------------------ orientation

	-- Lays the screen out for the current orientation (re-run when it changes).
	local function applyLayout()
		local portrait = ctx.portrait()
		if portrait == portraitMode then
			return
		end
		portraitMode = portrait
		if portrait then
			mapArea.Position = UDim2.fromScale(0, 0)
			mapArea.Size = UDim2.fromScale(1, 0.3)
			mapHolder.Size = UDim2.fromScale(1, 1)
			below.Visible = false
			panel.Position = UDim2.fromScale(0, 0.31)
			panel.Size = UDim2.fromScale(1, 0.69)
			legend.root.LayoutOrder = 6
			legend.root.Parent = scroll
			summary.root.LayoutOrder = 7
			summary.root.Parent = scroll
		else
			mapArea.Position = UDim2.fromScale(0, 0)
			mapArea.Size = UDim2.fromScale(0.65, 1)
			mapHolder.Size = UDim2.fromScale(1, 0.66)
			below.Position = UDim2.fromScale(0, 0.68)
			below.Size = UDim2.fromScale(1, 0.32)
			below.Visible = true
			panel.Position = UDim2.fromScale(0.665, 0)
			panel.Size = UDim2.fromScale(0.335, 1)
			legend.root.LayoutOrder = 1
			legend.root.Parent = below
			summary.root.LayoutOrder = 2
			summary.root.Parent = below
		end
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
			hintUntil = ctx.now() + HINT_SECONDS
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

	-- Fills one chip of the reveal: "You got OH" and what it makes the state.
	local function fillChip(
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

		local serverLocked = payload.seats[you].locked
		-- A rejected lock-in leaves a message and no lock: let the player fix it.
		local rejection = Messages.rejectionAfter(state, messageAtLock)
		if localLocked and not serverLocked and rejection ~= nil then
			localLocked = false
			hint = rejection.text
			hintUntil = ctx.now() + HINT_SECONDS
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

		-- Header, explanation, priority.
		local priorityLine = ""
		if mode == "Map" then
			header.Text = "The map for this match"
			explain.Text =
				"Each state leans toward one candidate by a few points. Leans are exact and public. The draft starts when the timer ends."
			priorityLine = Logic.priorityIn(Logic.priorityPlayer(config, view, 0), you, 0)
		elseif mode == "Input" and kind ~= nil then
			header.Text = `Round {view.draftRound + 1} of {totalRounds} — {Logic.title(kind)}`
			explain.Text = Logic.help(config, kind)
			priorityLine = Logic.priorityText(view.draftPriority or you, you)
		else
			local round = revealRound or view.draftRound
			header.Text = `Round {round + 1} of {totalRounds} — picks revealed`
			if round + 1 < totalRounds then
				local nextKind: Draft.Kind = Draft.kind(config, round + 1)
				explain.Text = `Next: round {round + 2} of {totalRounds}, {Logic.noun(nextKind)}.`
			else
				explain.Text = "The draft is over. Polls come out and the campaign begins."
			end
			if revealRound ~= nil then
				priorityLine = Logic.priorityWas(Logic.priorityPlayer(config, view, revealRound), you)
			end
		end
		priority.Text = priorityLine

		-- The ranked slots.
		slots.Visible = mode == "Input"
		for slot = 1, 2 do
			local id = if slot == 1 then choices.first else choices.second
			local label = if slot == 1 then "1st choice" else "2nd choice (backup)"
			local button = choiceButtons[slot]
			if id ~= nil then
				local record = StateData.byId[id]
				button.Text = `{label}: {record.name} ({id}), {record.ev} EV`
			else
				button.Text = `{label}: tap a state`
			end
			button.BackgroundColor3 = if target == slot then Kit.colors.raisedHover else Kit.colors.raised
			Kit.setEnabled(button, not locked)
			Kit.setEnabled(clearButtons[slot], not locked and id ~= nil)
		end
		Kit.setEnabled(clearAll, not locked and choices.first ~= nil)
		local hintText = hint
		if hintText ~= nil then
			hintLabel.TextColor3 = Kit.colors.danger
		elseif locked then
			hintText = "Your picks are locked in."
			hintLabel.TextColor3 = Kit.colors.muted
		elseif choices.first == nil then
			hintText =
				"Tap states on the map or in the list. Your 2nd choice is the backup if you both want the same state."
			hintLabel.TextColor3 = Kit.colors.muted
		elseif choices.second == nil then
			hintText =
				"No backup picked: if you both want your 1st choice and they have priority, we pick one for you."
			hintLabel.TextColor3 = Kit.colors.muted
		else
			hintText =
				"If you both want your 1st choice, the player with priority gets it and you get your 2nd."
			hintLabel.TextColor3 = Kit.colors.muted
		end
		hintLabel.Text = hintText or ""

		-- The reveal.
		revealBox.Visible = mode == "Reveal"
		if mode == "Reveal" then
			fillChip(youChip, youBig, youSmall, "You", mine, colors[you])
			fillChip(themChip, themBig, themSmall, "They", theirs, colors[them])
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

		-- Lock bar.
		lockBar.Visible = mode == "Input"
		scroll.Size = if mode == "Input" then UDim2.new(1, 0, 1, -(LOCK_BAR + GAP)) else UDim2.fromScale(1, 1)
		if locked then
			lockIn.Text = "Locked"
			Kit.setEnabled(lockIn, false)
			lockStatus.Text = "Locked — waiting for opponent"
			lockStatus.TextColor3 = Kit.colors.good
		else
			lockIn.Text = if choices.first == nil then "Pick a state to lock in" else "Lock In"
			Kit.setEnabled(lockIn, choices.first ~= nil)
			lockStatus.Text = if choices.first == nil then "Choose your 1st choice" else "Ready to lock in"
			lockStatus.TextColor3 = Kit.colors.text
		end
		local theirSeat = payload.seats[them]
		if theirSeat ~= nil and not theirSeat.connected then
			opponentStatus.Text = "Opponent: disconnected"
		elseif theirSeat ~= nil and theirSeat.locked then
			opponentStatus.Text = "Opponent: locked in"
		else
			opponentStatus.Text = "Opponent: still choosing"
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

		-- Countdown.
		timer.Text = Kit.clock(payload.deadline - ctx.now())
	end
	refresh = render

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
			applyLayout()
			local left = payload.deadline - now
			timer.Text = Kit.clock(left)
			timer.TextColor3 = if mode == "Input" and left <= 5 then Kit.colors.danger else Kit.colors.accent
			if hint ~= nil and now > hintUntil then
				hint = nil
				render()
			end
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
