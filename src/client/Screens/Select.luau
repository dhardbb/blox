--!strict
-- Select: the 30 second, simultaneous character select. Pick one of eight
-- candidates, one of six colors and exactly three of the eight platform issues,
-- then lock in. Nothing is shown to the opponent until both have locked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Issues = require(ReplicatedStorage.Shared.Sim.Issues)
local Session = require(ReplicatedStorage.Shared.Net.Session)

local AutoLock = require(script.Parent.Common.AutoLock)
local Data = require(script.Parent.Common.Data)
local Kit = require(script.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Common.Layout)
local Messages = require(script.Parent.Common.Messages)
local Types = require(script.Parent.Types)

local Screen = {}

local MAX_WIDTH = 1000 -- px
local HEADER = 52 -- px
local FOOTER = 64 -- px
local CELL_HEIGHT = 48 -- px, swatches and issue chips
local LOCK_WIDTH = 160 -- px
local WARNING_SECONDS = 5

local function cardHeight(portrait: boolean): number
	return if portrait then 224 else 170
end

function Screen.mount(parent: Frame, ctx: Types.Ctx): Types.Screen
	local platformSize = ctx.config.PLATFORM_SIZE
	local page = Layout.page(parent, { maxWidth = MAX_WIDTH, header = HEADER, footer = FOOTER })
	local content = page.content
	local header = page.header :: Frame
	local footer = page.footer :: Frame

	-- What the player has picked so far.
	local candidate: string? = nil
	local color: string? = nil
	local platform: { string } = {}
	local lockedLocal = false -- pressed Lock In (the offline fixtures never echo it back)
	local messageAtLock = 0 -- id of the newest message when Lock In was pressed
	local sentPick = "" -- the last complete pick sent as a PrePick
	local autoLock = AutoLock.new()
	local touched = false -- the player changed something, so stop applying the pre-pick
	local appliedPick: any = nil
	local payload: Session.StatePayload? = nil
	local lastPortrait: boolean? = nil

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

	-- ------------------------------------------------------------ header

	Kit.text("Choose your campaign", {
		Name = "Title",
		Size = UDim2.fromScale(0.6, 1),
		Font = Kit.font.bold,
		TextSize = Kit.size.title,
		TextScaled = true,
		Parent = header,
	})
	local timer = Kit.text("0:30", {
		Name = "Timer",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.34, 1),
		Font = Kit.font.bold,
		TextSize = Kit.size.title,
		TextScaled = true,
		TextColor3 = Kit.colors.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = header,
	})

	-- ------------------------------------------------------------ footer

	local status = Kit.text("", {
		Name = "Status",
		Size = UDim2.new(1, -(LOCK_WIDTH + 8), 1, 0),
		TextSize = Kit.size.caption,
		Parent = footer,
	})
	local lockIn: TextButton

	-- ------------------------------------------------------------ candidates

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	Layout.heading(content, "1. Candidate", nextOrder(), "CandidateHeading")
	local candidateGrid, candidateLayout = Layout.grid(content, "Candidates", nextOrder())
	local cards: { [string]: { button: TextButton, stroke: UIStroke } } = {}
	local refresh: () -> ()

	for index, id in Candidates.ids do
		local profile = Candidates.profile(ctx.config, id)
		local card = Kit.button("", function()
			if isLocked() then
				return
			end
			touched = true
			candidate = id
			refresh()
		end, {
			Name = `Candidate_{id}`,
			LayoutOrder = index,
			Text = "",
			TextScaled = false,
			Parent = candidateGrid,
		}) :: TextButton
		local stroke = Kit.stroke(Kit.colors.line, 1)
		stroke.Parent = card
		Kit.list("Vertical", 2).Parent = card
		Kit.text(profile.name, {
			Name = "Name",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 22),
			Font = Kit.font.bold,
			TextSize = Kit.size.heading,
			TextScaled = true,
			Parent = card,
		})
		Kit.text(profile.archetype, {
			Name = "Archetype",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 18),
			TextSize = Kit.size.caption,
			TextScaled = true,
			TextColor3 = Kit.colors.muted,
			Parent = card,
		})
		Kit.text(`+ {profile.perk}`, {
			Name = "Perk",
			LayoutOrder = 3,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = Kit.size.caption,
			TextColor3 = Kit.colors.good,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = card,
		})
		Kit.text(`- {profile.drawback}`, {
			Name = "Drawback",
			LayoutOrder = 4,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = Kit.size.caption,
			TextColor3 = Kit.colors.danger,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = card,
		})
		cards[id] = { button = card, stroke = stroke }
	end

	-- ------------------------------------------------------------ colors

	Layout.heading(content, "2. Color", nextOrder(), "ColorHeading")
	local colorGrid, colorLayout = Layout.grid(content, "Colors", nextOrder())
	local swatches: { [string]: { button: TextButton, stroke: UIStroke } } = {}
	for index, name in Candidates.colors do
		local swatch = Kit.button(name, function()
			if isLocked() then
				return
			end
			touched = true
			color = name
			refresh()
		end, {
			Name = `Color_{name}`,
			LayoutOrder = index,
			BackgroundColor3 = Kit.color(Colors.of(name)),
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeColor3 = Color3.new(0, 0, 0),
			TextStrokeTransparency = 0.5,
			Font = Kit.font.bold,
			Parent = colorGrid,
		}) :: TextButton
		local stroke = Kit.stroke(Kit.colors.text, 0)
		stroke.Parent = swatch
		swatches[name] = { button = swatch, stroke = stroke }
	end

	-- ------------------------------------------------------------ platform

	local platformHeading = Layout.heading(content, "3. Platform", nextOrder(), "PlatformHeading")
	Kit.text(
		"Pick three issues. The number is the electoral votes of the states that list it as a top issue.",
		{
			Name = "PlatformHint",
			LayoutOrder = nextOrder(),
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = Kit.size.caption,
			TextColor3 = Kit.colors.muted,
			Parent = content,
		}
	)
	local issueGrid, issueLayout = Layout.grid(content, "Issues", nextOrder())
	local chips: { [string]: TextButton } = {}
	local issueList: { string } = Issues.list :: any
	for index, issue in issueList do
		local chip = Kit.button(`{Data.issueName(issue)}\n{Data.evCoverage[issue] or 0} EV`, function()
			if isLocked() then
				return
			end
			touched = true
			local at = table.find(platform, issue)
			if at then
				table.remove(platform, at)
			elseif #platform < platformSize then
				table.insert(platform, issue)
			end
			refresh()
		end, {
			Name = `Issue_{issue}`,
			LayoutOrder = index,
			Parent = issueGrid,
		}) :: TextButton
		chips[issue] = chip
	end

	-- ------------------------------------------------------------ behavior

	local function lockPick()
		local pick = currentPick()
		if isLocked() or pick == nil then
			return
		end
		lockedLocal = true
		messageAtLock = Messages.lastId(ctx.store.get())
		autoLock:spent(payload)
		ctx.net.submit(pick)
		rememberPick()
		refresh()
	end

	lockIn = Kit.button("Lock In", lockPick, {
		Name = "LockIn",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(LOCK_WIDTH, 52),
		TextSize = Kit.size.heading,
		Parent = footer,
	}) :: TextButton

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
	end

	refresh = function()
		rememberPick()
		local locked = isLocked()
		for id, card in cards do
			local picked = id == candidate
			card.button.BackgroundColor3 = if picked then Kit.colors.raisedHover else Kit.colors.raised
			card.stroke.Color = if picked then Kit.colors.accent else Kit.colors.line
			card.stroke.Thickness = if picked then 3 else 1
		end
		for name, swatch in swatches do
			local picked = name == color
			swatch.stroke.Thickness = if picked then 4 else 0
			swatch.button.BackgroundTransparency = if locked and not picked then 0.5 else 0
		end
		local full = #platform >= platformSize
		for issue, chip in chips do
			local picked = table.find(platform, issue) ~= nil
			chip.BackgroundColor3 = if picked then Kit.colors.accent else Kit.colors.raised
			chip.TextColor3 = if picked then Kit.colors.background else Kit.colors.text
			chip.TextTransparency = if not picked and (full or locked) then 0.55 else 0
		end
		platformHeading.Text = `3. Platform ({#platform}/{platformSize})`

		local _, theirs = seats()
		local opponentText = "Opponent: choosing..."
		if theirs then
			if not theirs.connected then
				opponentText = "Opponent: disconnected"
			elseif theirs.locked then
				opponentText = "Opponent: locked in"
			end
		end
		local mine
		if locked then
			mine = "Locked — waiting for opponent"
		elseif isReady() then
			mine = "Ready. Lock in before time runs out."
		else
			local missing: { string } = {}
			if candidate == nil then
				table.insert(missing, "a candidate")
			end
			if color == nil then
				table.insert(missing, "a color")
			end
			if #platform < platformSize then
				table.insert(missing, `{platformSize - #platform} more issue(s)`)
			end
			mine = `Still to pick: {table.concat(missing, ", ")}`
		end
		status.Text = `{mine}\n{opponentText}`

		lockIn.Text = if locked then "Locked" else "Lock In"
		Kit.setEnabled(lockIn, isReady() and not locked)
	end

	local function relayout()
		local portrait = ctx.portrait()
		if portrait == lastPortrait then
			return
		end
		lastPortrait = portrait
		page.setPortrait(portrait)
		Layout.setGrid(candidateLayout, if portrait then 2 else 4, cardHeight(portrait))
		Layout.setGrid(colorLayout, if portrait then 3 else 6, CELL_HEIGHT)
		Layout.setGrid(issueLayout, if portrait then 2 else 4, CELL_HEIGHT)
	end

	local function updateTimer(now: number)
		local current = payload
		if current == nil then
			return
		end
		local left = current.deadline - now
		timer.Text = Kit.clock(left)
		timer.TextColor3 = if left <= WARNING_SECONDS then Kit.colors.danger else Kit.colors.accent
	end

	relayout()
	refresh()

	return {
		update = function(state: Types.State)
			payload = state.payload :: Session.StatePayload?
			-- A rejected lock-in leaves a message and no lock: let the player fix the pick.
			local mine = seats()
			if lockedLocal and not (mine ~= nil and mine.locked) then
				if Messages.rejectionAfter(state, messageAtLock) ~= nil then
					lockedLocal = false
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
