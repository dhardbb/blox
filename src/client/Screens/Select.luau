--!strict
-- Select: the simultaneous character select, in two steps (D-048).
--
--   Step 1: pick one of eight candidates and press "Next: issues". That claims
--   the candidate on the server (Net.claim): first come, first served, so two
--   players never share one. A candidate the opponent holds shows "Taken" and
--   cannot be picked. A claim that loses a same-moment coin flip comes back
--   with a notice and the player picks again.
--   Step 2: pick exactly three of the eight platform issues and lock in. Each
--   chip shows what the issue is worth this match: the EV of the states where it
--   is a top issue (drawn per match, View.issueMap) and the multiplier a rally
--   or ad on it earns there when it is on your platform (View.platformMults:
--   niche issues hit harder, D-047).
--
-- Your color is drawn from the match seed (D-047) and shown as a line in both
-- steps. The opponent's platform stays hidden until both have locked.
--
-- Layout (docs/UI-OVERHAUL.md §3.2): the standard Header with the timer, a
-- scroll area, and the pinned ActionBar. The scroll content is stacked with
-- explicit pixel positions (no list layout), so the fake engine can measure it
-- and the status line knows when the issues are below the fold ("Still to pick:
-- 2 issues (scroll down)").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local IssueMap = require(ReplicatedStorage.Shared.Sim.IssueMap)
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
local ISSUE_H = 56 -- px, an issue chip: the name over its EV and multiplier
local COLOR_H = 28 -- px, the drawn-color line
local HINT_H = 34 -- px, the platform hint (two lines)
local HINT_H_PORTRAIT = 64 -- px, the platform hint wrapped on a phone
local SELECTED_STROKE = 3 -- px, the outline of the picked card
local SWATCH_W = 44 -- px, the color chip on the drawn-color line
local SWAP_HINT_SECONDS = 3 -- how long "tap one to swap it" stays up
local CHECK = "• " -- the Gotham font has no ✓

-- Where each block of the scroll content sits, for one orientation and step.
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
	local platform: { string } = {}
	local claiming: string? = nil -- a claim sent and not yet answered
	local messageAtClaim = 0 -- id of the newest message when the claim was sent
	local lockedLocal = false -- pressed Lock in (the offline fixtures never echo it back)
	local messageAtLock = 0 -- id of the newest message when Lock in was pressed
	local sentPick = "" -- the last complete pick sent as a PrePick
	local autoLock = AutoLock.new()
	local touched = false -- the player changed something, so stop applying the pre-pick
	local appliedPick: any = nil
	local prePickLoaded = false -- the pre-pick filled the whole pick and nothing changed since
	local rejection: string? = nil -- why the server turned the last claim or lock-in down
	local swapHintUntil = 0 -- ctx.now() until which the status shows the swap hint
	local payload: Session.StatePayload? = nil
	local lastPortrait: boolean? = nil
	local lastStep = 0
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

	-- Who holds a candidate: "mine", "theirs" or nil (free).
	local function holder(id: string): string?
		local current = payload
		if current == nil or current.view.claims == nil then
			return nil
		end
		local owner = current.view.claims[id]
		if owner == nil then
			return nil
		end
		return if owner == current.you then "mine" else "theirs"
	end

	-- The candidate this player has claimed, if any.
	local function claimed(): string?
		for _, id in Candidates.ids do
			if holder(id) == "mine" then
				return id
			end
		end
		return nil
	end

	-- Step 2 once the server confirms the claim.
	local function step(): number
		return if claimed() ~= nil then 2 else 1
	end

	local function isReady(): boolean
		return candidate ~= nil and holder(candidate) ~= "theirs" and #platform == platformSize
	end

	-- The complete pick as the server wants it, or nil while something is missing.
	local function currentPick(): { candidate: string?, platform: { string } }?
		if not isReady() then
			return nil
		end
		return { candidate = candidate, platform = table.clone(platform) }
	end

	local function pickKey(pick: { candidate: string?, platform: { string } }): string
		local issues = table.clone(pick.platform)
		table.sort(issues)
		return `{pick.candidate}|{table.concat(issues, ",")}`
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

	local header = Header.new(page.header :: Frame, { title = "Choose your campaign", onHelp = ctx.help })
	local refresh: () -> ()
	local lockPick: () -> ()
	local claimPick: () -> ()
	local bar = ActionBar.new(page.footer :: Frame, {
		primary = "Next: issues",
		onPrimary = function()
			if step() == 1 then
				claimPick()
			else
				lockPick()
			end
		end,
		primaryName = "LockIn",
	})

	-- ------------------------------------------------------------ step 1: candidates

	local candidateHeading = Layout.heading(content, "1. Pick your candidate", 1, "CandidateHeading")
	local candidateGrid, candidateLayout = Layout.grid(content, "Candidates", 2)
	local cards: { [string]: TextButton } = {}
	local takenTags: { [string]: TextLabel } = {}

	for index, id in Candidates.ids do
		local profile = Candidates.profile(ctx.config, id)
		local card = Kit.button("", function()
			if isLocked() or step() ~= 1 or claiming ~= nil or holder(id) == "theirs" then
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
		takenTags[id] = Kit.caption("Taken by your opponent", {
			Name = "Taken",
			LayoutOrder = 2,
			Font = Kit.font.bold,
			TextColor3 = Kit.colors.danger,
			Visible = false,
			Parent = card,
		})
		Kit.caption(profile.archetype, { Name = "Archetype", LayoutOrder = 3, Parent = card })
		Kit.caption(`+ {profile.perk}`, {
			Name = "Perk",
			LayoutOrder = 4,
			TextColor3 = Kit.colors.good,
			Parent = card,
		})
		Kit.caption(`− {profile.drawback}`, {
			Name = "Drawback",
			LayoutOrder = 5,
			TextColor3 = Kit.colors.danger,
			Parent = card,
		})
		cards[id] = card
	end

	-- ------------------------------------------------------------ color (drawn)

	-- Colors are drawn from the match seed (D-047): a line, not a choice.
	local colorRow = Kit.box({ Name = "ColorRow", LayoutOrder = 3, Parent = content })
	local swatch = Kit.box({
		Name = "ColorSwatch",
		Size = UDim2.new(0, SWATCH_W, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.colors.neutral,
		Parent = colorRow,
	})
	Kit.corner(Kit.radius.control).Parent = swatch
	local colorLine = Kit.caption("", {
		Name = "ColorLine",
		Position = UDim2.fromOffset(SWATCH_W + Kit.space.sm, 0),
		Size = UDim2.new(1, -(SWATCH_W + Kit.space.sm), 1, 0),
		AutomaticSize = Enum.AutomaticSize.None,
		Parent = colorRow,
	})
	local shownColor: string? = nil
	local function renderColor()
		local current = payload
		local me = if current then current.view.players[current.you] else nil
		local name = if me then me.color else nil
		if name == shownColor then
			return
		end
		shownColor = name
		swatch.BackgroundColor3 = Kit.color(Colors.of(name))
		colorLine.Text = if name
			then `Your color this match: {name} (drawn at random)`
			else "Your color is drawn at random"
	end

	-- ------------------------------------------------------------ step 2: platform

	local platformHeading = Layout.heading(content, "2. Pick three issues", 5, "PlatformHeading")
	local platformHint = Kit.caption(
		"Top issues are drawn new each match. EV: votes in the states where it is a top issue. ×: what a rally or ad on it earns there once it is on your platform. Niche issues hit harder.",
		{ Name = "PlatformHint", LayoutOrder = 6, AutomaticSize = Enum.AutomaticSize.None, Parent = content }
	)
	local issueGrid, issueLayout = Layout.grid(content, "Issues", 7)
	local chips: { [string]: TextButton } = {}
	local issueList: { string } = Issues.list :: any
	local coverage: { [string]: number } = {} -- EV per issue on this match's map
	local mults: { [string]: number } = {} -- platform multiplier per issue this match
	local function chipLabel(issue: string): string
		local ev, mult = coverage[issue], mults[issue]
		if ev == nil or mult == nil then
			return Data.issueName(issue)
		end
		return `{Data.issueName(issue)}\n{ev} EV · ×{string.format("%.2f", mult)}`
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

	-- Stacks the current step's blocks top to bottom and sizes the scroll canvas.
	local function placeBlocks(portrait: boolean, current: number)
		local cardColumns = if portrait then 2 else 4
		local cardH = if portrait then CARD_H_PORTRAIT else CARD_H
		local cardRows = math.ceil(#Candidates.ids / cardColumns)
		local issueColumns = if portrait then 2 else 4
		local issueRows = math.ceil(#issueList / issueColumns)
		local gap = Layout.GAP
		Layout.setGrid(candidateLayout, cardColumns, cardH)
		Layout.setGrid(issueLayout, issueColumns, ISSUE_H)

		local first = current == 1
		for _, block in { candidateHeading, candidateGrid } :: { GuiObject } do
			block.Visible = first
		end
		for _, block in { platformHeading, platformHint, issueGrid } :: { GuiObject } do
			block.Visible = not first
		end

		local y = 0
		local function place(block: GuiObject, height: number, after: number)
			block.Position = UDim2.fromOffset(0, y)
			block.Size = UDim2.new(1, 0, 0, height)
			block.AutomaticSize = Enum.AutomaticSize.None
			y += height + after
		end
		local issuesTop = 0
		if first then
			place(candidateHeading, HEADING_H, Kit.space.xs)
			place(candidateGrid, cardRows * cardH + (cardRows - 1) * gap, gap)
			place(colorRow, COLOR_H, 0)
			issuesTop = y
		else
			place(colorRow, COLOR_H, gap)
			place(platformHeading, HEADING_H, 0)
			place(platformHint, if portrait then HINT_H_PORTRAIT else HINT_H, Kit.space.xs)
			issuesTop = y
			place(issueGrid, issueRows * ISSUE_H + (issueRows - 1) * gap, 0)
		end
		stack = { total = y, issuesTop = issuesTop, issuesBottom = y }
		content.Size = UDim2.new(1, 0, 0, y)
		scroll.CanvasSize = UDim2.fromOffset(0, y + Kit.space.md)
	end

	-- Part of the issue grid is under the bottom edge of the scroll area.
	local function issuesBelowFold(): boolean
		if step() ~= 2 then
			return false
		end
		local canvas = (scroll :: any).CanvasPosition
		local top = if canvas then canvas.Y else 0
		return stack.issuesBottom > top + scroll.AbsoluteSize.Y + 1
	end

	-- ------------------------------------------------------------ behavior

	claimPick = function()
		local pick = candidate
		if isLocked() or pick == nil or claiming ~= nil or holder(pick) == "theirs" then
			return
		end
		claiming = pick
		rejection = nil
		messageAtClaim = Messages.lastId(ctx.store.get())
		ctx.net.claim(pick)
		refresh()
	end

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
		if
			candidate == nil
			and type(pick.candidate) == "string"
			and Candidates.exists(pick.candidate)
			and holder(pick.candidate) ~= "theirs"
		then
			candidate = pick.candidate
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
		elseif step() == 1 then
			if claiming ~= nil then
				bar:setStatus("Claiming your candidate…", "muted")
			elseif candidate == nil then
				bar:setStatus("Step 1 of 2 · Still to pick: a candidate", "muted")
			else
				bar:setStatus("Step 1 of 2 · Next: your issues", "ok")
			end
		elseif isReady() then
			if prePickLoaded then
				bar:setStatus("Your last pick is loaded · Lock in or change it", "ok")
			else
				bar:setStatus("Ready", "ok")
			end
		else
			local below = if missingIssues > 0 and issuesBelowFold() then " (scroll down)" else ""
			bar:setStatus(`Step 2 of 2 · Still to pick: {plural(missingIssues, "issue")}{below}`, "muted")
		end
	end

	local function relayout()
		local portrait = ctx.portrait()
		local current = step()
		if portrait == lastPortrait and current == lastStep then
			return
		end
		lastPortrait, lastStep = portrait, current
		page.setPortrait(portrait)
		placeBlocks(portrait, current)
	end

	refresh = function()
		relayout()
		local mine = claimed()
		if mine ~= nil then
			candidate = mine
		end
		rememberPick()
		local locked = isLocked()
		local first = step() == 1
		for id, card in cards do
			local taken = holder(id) == "theirs"
			if taken and candidate == id and mine == nil then
				candidate = nil
			end
			Kit.setSelected(card, id == candidate)
			Kit.setEnabled(card, not locked and first and claiming == nil and not taken)
			card.BackgroundTransparency = if taken then 0.5 else 0
			takenTags[id].Visible = taken
			local stroke = card:FindFirstChild("VariantStroke") :: UIStroke?
			if stroke then
				stroke.Thickness = SELECTED_STROKE
			end
		end
		renderColor()
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
		local name = if mine then Candidates.profile(ctx.config, mine).name else nil
		platformHeading.Text = if name
			then `2. Issues for {name} ({#platform}/{platformSize})`
			else `2. Pick three issues ({#platform}/{platformSize})`

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
		elseif first then
			if claiming ~= nil then
				bar:setPrimary("Claiming…", false)
			elseif candidate == nil then
				bar:setPrimary("Pick a candidate", false)
			else
				bar:setPrimary("Next: issues", true)
			end
		elseif #platform < platformSize then
			bar:setPrimary(`Pick {plural(platformSize - #platform, "more issue")}`, false)
		else
			bar:setPrimary("Lock in", true)
		end
		renderStatus()
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
			local current = payload
			if current and current.view.issueMap then
				coverage = IssueMap.evByIssue(current.view.issueMap)
				mults = current.view.platformMults or {}
			else
				coverage, mults = {}, {}
			end
			-- A claim is answered by the next payload: granted (step 2), turned down
			-- at once (a rejection), or lost to a same-moment claim (a notice).
			local pending = claiming
			if pending ~= nil then
				local answer = Messages.newestAfter(state, messageAtClaim)
				if holder(pending) == "mine" then
					claiming = nil
				elseif holder(pending) == "theirs" then
					claiming = nil
					rejection = ctx.net.reasonText("CandidateTaken")
				elseif answer ~= nil and answer.rejected then
					claiming = nil
					rejection = answer.text
				end
			end
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
