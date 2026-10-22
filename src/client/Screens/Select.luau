--!strict
-- Select: the 30 second, simultaneous character select. Pick one of eight
-- candidates, one of six colors and exactly three of the eight platform issues,
-- then lock in. Nothing is shown to the opponent until both have locked.
--
-- Layout (docs/UI-OVERHAUL.md §3.2): the standard Header with the timer, a
-- scroll area, and the pinned ActionBar with "Lock in". The scroll content is
-- stacked with explicit pixel positions (no list layout), so the fake engine
-- can measure it and the status line knows when the issues are below the fold
-- ("Still to pick: 2 issues ▾"). On 16:9 everything fits without scrolling; on
-- a phone the issues scroll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Issues = require(ReplicatedStorage.Shared.Sim.Issues)
local Session = require(ReplicatedStorage.Shared.Net.Session)

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local AutoLock = require(script.Parent.Common.AutoLock)
local Data = require(script.Parent.Common.Data)
local Header = require(script.Parent.Parent.UI.Header)
local Kit = require(script.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Common.Layout)
local Messages = require(script.Parent.Common.Messages)
local Types = require(script.Parent.Types)

local Screen = {}

local MAX_WIDTH = 1000 -- px
local HEADING_H = 26 -- px, a section heading (Layout.heading)
local CARD_H = 112 -- px, a candidate card on 16:9
local CARD_H_PORTRAIT = 124 -- px, a candidate card on a phone
local CELL_H = Kit.MIN_TOUCH -- px, color swatches and issue chips
local HINT_H = 20 -- px, the platform hint on one line
local HINT_H_PORTRAIT = 34 -- px, the platform hint wrapped to two lines
local SELECTED_STROKE = 3 -- px, the outline of the picked card and swatch
local SWAP_HINT_SECONDS = 3 -- how long "tap one to swap it" stays up
local CHECK = "✓ "

-- Where each block of the scroll content sits, for one orientation.
type Stack = {
	total: number, -- content height
	issuesTop: number,
	issuesBottom: number,
}

function Screen.mount(parent: Frame, ctx: Types.Ctx): Types.Screen
	local platformSize = ctx.config.PLATFORM_SIZE
	local page = Layout.page(parent, { maxWidth = MAX_WIDTH, header = Kit.HEADER_H, footer = Kit.BAR_H })
	local content = page.content
	local scroll = page.scroll
	-- Explicit positions instead of the page's list layout (see the header comment).
	local pageList = content:FindFirstChildOfClass("UIListLayout")
	if pageList then
		pageList:Destroy()
	end
	content.AutomaticSize = Enum.AutomaticSize.None
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None

	-- What the player has picked so far.
	local candidate: string? = nil
	local color: string? = nil
	local platform: { string } = {}
	local lockedLocal = false -- pressed Lock in (the offline fixtures never echo it back)
	local messageAtLock = 0 -- id of the newest message when Lock in was pressed
	local sentPick = "" -- the last complete pick sent as a PrePick
	local autoLock = AutoLock.new()
	local touched = false -- the player changed something, so stop applying the pre-pick
	local appliedPick: any = nil
	local prePickLoaded = false -- the pre-pick filled the whole pick and nothing changed since
	local rejection: string? = nil -- why the server turned the last lock-in down
	local swapHintUntil = 0 -- ctx.now() until which the status shows the swap hint
	local payload: Session.StatePayload? = nil
	local lastPortrait: boolean? = nil
	local stack: Stack = { total = 0, issuesTop = 0, issuesBottom = 0 }

	local function seats(): (Session.SeatInfo?, Session.SeatInfo?)
		local current = payload
		if current == nil then
			return nil, nil
		end
		local _, theirs = Data.opponent(current)
		return current.seats[current.you], theirs
	end

	local function isLocked(): boolean
		local mine = seats()
		return lockedLocal or (mine ~= nil and mine.locked)
	end

	local function isReady(): boolean
		return candidate ~= nil and color ~= nil and #platform == platformSize
	end

	-- The complete pick as the server wants it, or nil while something is missing.
	local function currentPick(): { candidate: string?, color: string?, platform: { string } }?
		if not isReady() then
			return nil
		end
		return { candidate = candidate, color = color, platform = table.clone(platform) }
	end

	local function pickKey(pick: { candidate: string?, color: string?, platform: { string } }): string
		local issues = table.clone(pick.platform)
		table.sort(issues)
		return `{pick.candidate}|{pick.color}|{table.concat(issues, ",")}`
	end

	-- Remembers a complete pick for the next match (and for a Select that times out
	-- before the next one), once per distinct pick.
	local function rememberPick()
		local pick = currentPick()
		if pick == nil then
			return
		end
		local key = pickKey(pick)
		if key == sentPick then
			return
		end
		sentPick = key
		ctx.net.send("PrePick", { pick = pick })
		ctx.store.setPrePick(pick)
	end

	-- The player changed the pick by hand.
	local function changed()
		touched = true
		prePickLoaded = false
		rejection = nil
	end

	-- ------------------------------------------------------------ header and bar

	local header = Header.new(page.header :: Frame, { title = "Choose your campaign" })
	local refresh: () -> ()
	local lockPick: () -> ()
	local bar = ActionBar.new(page.footer :: Frame, {
		primary = "Lock in",
		onPrimary = function()
			lockPick()
		end,
		primaryName = "LockIn",
	})

	-- ------------------------------------------------------------ candidates

	local candidateHeading = Layout.heading(content, "1. Candidate", 1, "CandidateHeading")
	local candidateGrid, candidateLayout = Layout.grid(content, "Candidates", 2)
	local cards: { [string]: TextButton } = {}

	for index, id in Candidates.ids do
		local profile = Candidates.profile(ctx.config, id)
		local card = Kit.button("", function()
			if isLocked() then
				return
			end
			changed()
			candidate = id
			refresh()
		end, {
			variant = "chip",
			Name = `Candidate_{id}`,
			LayoutOrder = index,
			Text = "",
			TextScaled = false,
			ClipsDescendants = true,
			Parent = candidateGrid,
		}) :: TextButton
		local pad = card:FindFirstChildOfClass("UIPadding")
		if pad then
			pad.PaddingTop = UDim.new(0, Kit.space.sm)
			pad.PaddingBottom = UDim.new(0, Kit.space.sm)
		end
		Kit.list("Vertical", 0).Parent = card
		Kit.text(profile.name, {
			Name = "Name",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, Kit.size.heading + 2),
			Font = Kit.font.bold,
			TextSize = Kit.size.heading,
			TextScaled = true,
			Parent = card,
		})
		Kit.caption(profile.archetype, { Name = "Archetype", LayoutOrder = 2, Parent = card })
		Kit.caption(`+ {profile.perk}`, {
			Name = "Perk",
			LayoutOrder = 3,
			TextColor3 = Kit.colors.good,
			Parent = card,
		})
		Kit.caption(`− {profile.drawback}`, {
			Name = "Drawback",
			LayoutOrder = 4,
			TextColor3 = Kit.colors.danger,
			Parent = card,
		})
		cards[id] = card
	end

	-- ------------------------------------------------------------ colors

	local colorHeading = Layout.heading(content, "2. Color", 3, "ColorHeading")
	local colorGrid, colorLayout = Layout.grid(content, "Colors", 4)
	local swatches: { [string]: TextButton } = {}
	-- Six across a phone leaves ~54 px a swatch: "Cr", "Co", ... there.
	local function swatchLabel(name: string, picked: boolean): string
		local label = if lastPortrait then string.sub(name, 1, 2) else name
		return if picked then CHECK .. label else label
	end
	for index, name in Candidates.colors do
		local rgb = Colors.of(name)
		local swatch = Kit.button(name, function()
			if isLocked() then
				return
			end
			changed()
			color = name
			refresh()
		end, {
			variant = "chip",
			Name = `Color_{name}`,
			LayoutOrder = index,
			BackgroundColor3 = Kit.color(rgb),
			TextColor3 = Kit.color(Colors.onColor(rgb)),
			Font = Kit.font.bold,
			Parent = colorGrid,
		}) :: TextButton
		-- A swatch keeps its color: its outline is the text color, not the accent.
		local stroke = swatch:FindFirstChild("VariantStroke") :: UIStroke?
		if stroke then
			stroke.Color = Kit.colors.text
			stroke.Thickness = SELECTED_STROKE
		end
		swatches[name] = swatch
	end

	-- ------------------------------------------------------------ platform

	local platformHeading = Layout.heading(content, "3. Platform", 5, "PlatformHeading")
	local platformHint = Kit.caption(
		"Pick three. EV: electoral votes of the states where it is a top issue.",
		{ Name = "PlatformHint", LayoutOrder = 6, AutomaticSize = Enum.AutomaticSize.None, Parent = content }
	)
	local issueGrid, issueLayout = Layout.grid(content, "Issues", 7)
	local chips: { [string]: TextButton } = {}
	local issueList: { string } = Issues.list :: any
	local function chipLabel(issue: string): string
		return `{Data.issueName(issue)} · {Data.evCoverage[issue] or 0} EV`
	end
	for index, issue in issueList do
		local chip = Kit.button(chipLabel(issue), function()
			if isLocked() then
				return
			end
			local at = table.find(platform, issue)
			if at then
				changed()
				table.remove(platform, at)
			elseif #platform < platformSize then
				changed()
				table.insert(platform, issue)
			else
				-- Full: say how to swap instead of doing nothing.
				swapHintUntil = ctx.now() + SWAP_HINT_SECONDS
			end
			refresh()
		end, {
			variant = "chip",
			Name = `Issue_{issue}`,
			LayoutOrder = index,
			Parent = issueGrid,
		}) :: TextButton
		chips[issue] = chip
	end

	-- ------------------------------------------------------------ layout

	-- Stacks the blocks top to bottom and sizes the scroll canvas to fit them.
	local function placeBlocks(portrait: boolean)
		local cardColumns = if portrait then 2 else 4
		local cardH = if portrait then CARD_H_PORTRAIT else CARD_H
		local cardRows = math.ceil(#Candidates.ids / cardColumns)
		local issueColumns = if portrait then 2 else 4
		local issueRows = math.ceil(#issueList / issueColumns)
		local gap = Layout.GAP
		Layout.setGrid(candidateLayout, cardColumns, cardH)
		Layout.setGrid(colorLayout, #Candidates.colors, CELL_H)
		Layout.setGrid(issueLayout, issueColumns, CELL_H)

		local y = 0
		local function place(block: GuiObject, height: number, after: number)
			block.Position = UDim2.fromOffset(0, y)
			block.Size = UDim2.new(1, 0, 0, height)
			block.AutomaticSize = Enum.AutomaticSize.None
			y += height + after
		end
		place(candidateHeading, HEADING_H, Kit.space.xs)
		place(candidateGrid, cardRows * cardH + (cardRows - 1) * gap, gap)
		place(colorHeading, HEADING_H, Kit.space.xs)
		place(colorGrid, CELL_H, gap)
		place(platformHeading, HEADING_H, 0)
		place(platformHint, if portrait then HINT_H_PORTRAIT else HINT_H, Kit.space.xs)
		local issuesTop = y
		place(issueGrid, issueRows * CELL_H + (issueRows - 1) * gap, 0)
		stack = { total = y, issuesTop = issuesTop, issuesBottom = y }
		content.Size = UDim2.new(1, 0, 0, y)
		scroll.CanvasSize = UDim2.fromOffset(0, y + Kit.space.md)
	end

	-- Part of the issue grid is under the bottom edge of the scroll area.
	local function issuesBelowFold(): boolean
		local canvas = (scroll :: any).CanvasPosition
		local top = if canvas then canvas.Y else 0
		return stack.issuesBottom > top + scroll.AbsoluteSize.Y + 1
	end

	-- ------------------------------------------------------------ behavior

	lockPick = function()
		local pick = currentPick()
		if isLocked() or pick == nil then
			return
		end
		lockedLocal = true
		rejection = nil
		messageAtLock = Messages.lastId(ctx.store.get())
		autoLock:spent(payload)
		ctx.net.submit(pick)
		rememberPick()
		refresh()
	end

	local function applyPrePick()
		local pick: any = ctx.store.get().prePick
		if touched or pick == appliedPick or type(pick) ~= "table" then
			return
		end
		appliedPick = pick
		if type(pick.candidate) == "string" and Candidates.exists(pick.candidate) then
			candidate = pick.candidate
		end
		if type(pick.color) == "string" and table.find(Candidates.colors, pick.color) then
			color = pick.color
		end
		local list: { string } = {}
		if type(pick.platform) == "table" then
			for _, issue in pick.platform do
				if
					type(issue) == "string"
					and Issues.isIssue(issue)
					and not table.find(list, issue)
					and #list < platformSize
				then
					table.insert(list, issue)
				end
			end
		end
		platform = list
		-- The pre-pick is already remembered: do not send it back.
		local applied = currentPick()
		if applied then
			sentPick = pickKey(applied)
		end
		prePickLoaded = applied ~= nil
	end

	local function plural(n: number, word: string): string
		return if n == 1 then `{n} {word}` else `{n} {word}s`
	end

	-- The status line, which also depends on the clock (swap hint) and the scroll.
	local function renderStatus()
		local missingIssues = platformSize - #platform
		if isLocked() then
			bar:setStatus("Locked in · waiting for opponent", "ok")
		elseif ctx.now() < swapHintUntil then
			bar:setStatus(`You already have {platformSize}; tap one to swap it`, "warn")
		elseif rejection then
			bar:setStatus(rejection, "bad")
		elseif isReady() then
			if prePickLoaded then
				bar:setStatus("Your last pick is loaded · Lock in or change it", "ok")
			else
				bar:setStatus("Ready", "ok")
			end
		else
			local missing: { string } = {}
			if candidate == nil then
				table.insert(missing, "a candidate")
			end
			if color == nil then
				table.insert(missing, "a color")
			end
			if missingIssues > 0 then
				table.insert(missing, plural(missingIssues, "issue"))
			end
			local below = if missingIssues > 0 and issuesBelowFold() then " ▾" else ""
			bar:setStatus(`Still to pick: {table.concat(missing, ", ")}{below}`, "muted")
		end
	end

	refresh = function()
		rememberPick()
		local locked = isLocked()
		for id, card in cards do
			local picked = id == candidate
			Kit.setSelected(card, picked)
			Kit.setEnabled(card, not locked)
			local stroke = card:FindFirstChild("VariantStroke") :: UIStroke?
			if stroke then
				stroke.Thickness = SELECTED_STROKE
			end
		end
		for name, swatch in swatches do
			local picked = name == color
			-- Not Kit.setSelected/setEnabled: those repaint a chip's background, and a
			-- swatch's background is its color.
			swatch:SetAttribute("Selected", picked)
			swatch.Text = swatchLabel(name, picked)
			swatch.Active = not locked
			swatch.AutoButtonColor = not locked
			swatch.BackgroundTransparency = if locked and not picked then 0.5 else 0
			local stroke = swatch:FindFirstChild("VariantStroke") :: UIStroke?
			if stroke then
				stroke.Enabled = picked
			end
		end
		local full = #platform >= platformSize
		for issue, chip in chips do
			local picked = table.find(platform, issue) ~= nil
			chip.Text = if picked then CHECK .. chipLabel(issue) else chipLabel(issue)
			Kit.setSelected(chip, picked)
			Kit.setEnabled(chip, not locked)
			-- Full: the others look quieter but stay tappable (for the swap hint).
			if not locked and full and not picked then
				chip.TextColor3 = Kit.colors.muted
			end
		end
		platformHeading.Text = `3. Platform ({#platform}/{platformSize})`

		local _, theirs = seats()
		local opponentText = "Opponent: thinking"
		if theirs then
			if not theirs.connected then
				opponentText = "Opponent: disconnected"
			elseif theirs.locked then
				opponentText = "Opponent: locked in"
			end
		end
		bar:setOpponent(opponentText)

		if locked then
			bar:setPrimary("Locked in", false)
		elseif candidate == nil then
			bar:setPrimary("Pick a candidate", false)
		elseif color == nil then
			bar:setPrimary("Pick a color", false)
		elseif #platform < platformSize then
			bar:setPrimary(`Pick {plural(platformSize - #platform, "more issue")}`, false)
		else
			bar:setPrimary("Lock in", true)
		end
		renderStatus()
	end

	local function relayout()
		local portrait = ctx.portrait()
		if portrait == lastPortrait then
			return
		end
		lastPortrait = portrait
		page.setPortrait(portrait)
		placeBlocks(portrait)
		for name, swatch in swatches do
			swatch.Text = swatchLabel(name, name == color)
		end
	end

	local function updateTimer(now: number)
		local current = payload
		if current == nil then
			header:setTimer(nil)
			return
		end
		header:setTimer(current.deadline - now)
	end

	relayout()
	refresh()

	return {
		update = function(state: Types.State)
			payload = state.payload :: Session.StatePayload?
			-- A rejected lock-in leaves a message and no lock: say why (the global
			-- toast shows it too) and let the player fix the pick.
			local mine = seats()
			if lockedLocal and not (mine ~= nil and mine.locked) then
				local rejected = Messages.rejectionAfter(state, messageAtLock)
				if rejected ~= nil then
					lockedLocal = false
					rejection = rejected.text
				end
			end
			relayout()
			applyPrePick()
			refresh()
			updateTimer(ctx.now())
		end,
		tick = function(now: number)
			relayout()
			updateTimer(now)
			renderStatus()
			-- The timer is about to end with a complete pick that was never locked.
			local current = payload
			if current ~= nil and isReady() and autoLock:due(current, now, isLocked()) then
				lockPick()
			end
		end,
		destroy = function() end,
	}
end

return Screen
