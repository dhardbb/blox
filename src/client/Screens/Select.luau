--!strict
-- Select: the simultaneous character select, in two steps (D-048).
--
--   Step 1: pick one of eight candidates and press "Next: issues". That claims
--   the candidate on the server (Net.claim): first come, first served, so two
--   players never share one. A candidate the opponent holds shows a "Taken"
--   pill, is dimmed and cannot be picked. A claim that loses a same-moment coin
--   flip comes back with a notice and the player picks again.
--   Step 2: pick exactly three of the eight platform issues and lock in. Each
--   chip shows what the issue is worth this match in plain words: the votes of
--   the states where it is a top issue (drawn per match, View.issueMap) and its
--   boost, what a rally or ad on it earns there once it is on your platform
--   (View.platformMults: niche issues hit harder, D-047).
--
-- Your color is shown as a dot and a line in both steps: red or blue, dealt
-- (D-055). A Color Pass owner (view.canPickColor) also gets a row of six
-- swatches under it (D-061): your color outlined, the one your opponent
-- claimed dimmed with "Taken", and a tap on any other claims it (Net.claimColor,
-- first come, first served; a same-moment clash comes back as the ColorTaken
-- notice). Owners may change color until Select ends, also after locking in.
-- The opponent's platform stays hidden until both have locked.
--
-- Layout (docs/UI-STYLE.md §4.2): the standard Header with the "what to do now"
-- line and the timer, a scroll area (a coach tip, the cards or chips, then the
-- color line with one ghost button for details), and the pinned ActionBar. Each
-- card shows the candidate's portrait (Kit.portrait, D-068) on a neutral plate,
-- ringed in a player color only once it is picked (yours) or taken (theirs,
-- dimmed), and a short strength and weakness (Shared/UI/Words/Setup); the exact
-- numbers are in a sheet ("About Goldie"), and "How issues work" explains votes
-- and boost.
--
-- Motion (docs/UI-STYLE.md §2.7.1): each step's cards pop in one after another
-- when it opens (Motion.stagger), and a card pops as it is picked; the outline
-- and the "select" cue come from Kit. Nothing waits on an animation.
--
-- Stable names: Candidate_<id> (with Portrait, Name, Archetype, Perk, Drawback, Taken),
-- Issue_<issue> (with IssueName, IssueLine), Candidates, Issues, ColorRow,
-- ColorDot, ColorLine, ColorPicker (ColorSwatch_<Color>, each with ColorName),
-- NameRow (NameLine, NameButton), NameSheet (NameBox, NameHint, NameStatus,
-- NameReset, NameSave),
-- Details, CandidateSheet, IssuesHelp, IssuesSheet, LockIn,
-- BarStatus, BarOpponent, NowText, Timer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local CustomName = require(ReplicatedStorage.Shared.Net.CustomName)
local IssueMap = require(ReplicatedStorage.Shared.Sim.IssueMap)
local Issues = require(ReplicatedStorage.Shared.Sim.Issues)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local Words = require(ReplicatedStorage.Shared.UI.Words.Setup)

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local AutoLock = require(script.Parent.Common.AutoLock)
local CoachTip = require(script.Parent.Parent.UI.CoachTip)
local Data = require(script.Parent.Common.Data)
local Header = require(script.Parent.Parent.UI.Header)
local Kit = require(script.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Common.Layout)
local Messages = require(script.Parent.Common.Messages)
local Motion = require(script.Parent.Parent.UI.Motion)
local Sheet = require(script.Parent.Parent.UI.Sheet)
local Types = require(script.Parent.Types)

local Screen = {}

local MAX_WIDTH = 1000 -- px
local CARD_H = 136 -- px, a candidate card: the portrait beside name and kind, then strength and weakness
local CARD_H_PORTRAIT = 102 -- px, the same on a phone (tighter padding, a smaller portrait)
local FACE = 56 -- px, a candidate's portrait (Kit.portrait) on a wide screen
local FACE_PORTRAIT = 40 -- px, on a phone
local ISSUE_H = 68 -- px, an issue chip: the name over "154 votes · +41% boost"
local ISSUE_H_PORTRAIT = 86 -- px, on a phone the votes and the boost take a line each
local DOT = 24 -- px, the color line's monogram (your candidate's initials in your color)
local DETAILS_W = 180 -- px, the ghost button beside the color line
local SWATCH = 36 -- px, a color swatch's monogram (Color Pass owners, D-061)
local SWATCH_CELL_MAX = 72 -- px, widest a swatch's cell gets (six in a row; a phone gives each about 56)
local SWATCH_NAME_H = 18 -- px, the color name (or "Taken") under a swatch
local SWAP_HINT_SECONDS = 3 -- how long "tap one to swap it" stays up
local NAME_BUTTON_W = 180 -- px, the name line's Rename / Get the Name Pass button (D-069)
local PICKED = Kit.glyph.bullet .. " " -- before a picked issue's name
local TAKEN_FADE = 0.5 -- a taken card's fill and text transparency
local ARRIVE_FROM = 0.92 -- scale a card pops in from when its step opens
local PICK_FROM = 0.95 -- scale a card pops from when it is picked

-- A coach tip in a list (CoachTip.show), with an explicit zero Position and
-- AnchorPoint: the headless test engine reads UDim2.new() and Vector2.new() as empty.
-- `quiet`: no pip (the match's first tip comes up with the screen, right after
-- the Play tap, so the match opens on one sound).
local function showTip(parent: Instance, id: string, order: number, quiet: boolean?): CoachTip.Tip?
	local tip = CoachTip.show(parent, { id = id, order = order, quiet = quiet })
	if tip then
		tip.root.Position = UDim2.fromOffset(0, 0)
		tip.root.AnchorPoint = Vector2.new(0, 0)
	end
	return tip
end

function Screen.mount(parent: Frame, ctx: Types.Ctx): Types.Screen
	local platformSize = ctx.config.PLATFORM_SIZE
	local page = Layout.page(parent, {
		maxWidth = MAX_WIDTH,
		header = Kit.HEADER_H + Kit.NOW_H,
		footer = Kit.BAR_H,
	})
	local content = page.content
	-- Tighter than the page's default gap, so step 1 fits a phone with its tip.
	local contentList = content:FindFirstChildOfClass("UIListLayout")
	if contentList then
		contentList.Padding = UDim.new(0, Kit.space.sm)
	end

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

	-- The opponent's custom name when this view carries one (D-069), else their
	-- candidate's first name once they hold one, else "your opponent".
	local function opponentName(): string
		local current = payload
		if current then
			local other = Data.opponent(current)
			local them = current.view.players[other]
			if them and them.customName then
				return them.customName
			end
		end
		for _, id in Candidates.ids do
			if holder(id) == "theirs" then
				return Words.firstName(Candidates.profile(ctx.config, id).name)
			end
		end
		return "your opponent"
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

	local header = Header.new(page.header :: Frame, {
		title = "Your candidate",
		now = true,
		onHelp = ctx.help,
	})
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

	local candidateTip = showTip(content, "select.candidate", 1, true)
	local candidateGrid, candidateLayout = Layout.grid(content, "Candidates", 2)
	local cards: { [string]: TextButton } = {}
	type CardParts = {
		name: TextLabel,
		archetype: TextLabel,
		perk: TextLabel,
		drawback: TextLabel,
		taken: TextLabel,
		top: Frame,
		who: Frame,
	}
	local parts: { [string]: CardParts } = {}

	for index, id in Candidates.ids do
		local profile = Candidates.profile(ctx.config, id)
		local short = Words.candidate(ctx.config, id)
		local card = Kit.cardButton(function()
			if isLocked() or step() ~= 1 or claiming ~= nil or holder(id) == "theirs" then
				return
			end
			changed()
			if candidate ~= id then
				Motion.pop(cards[id], PICK_FROM)
			end
			candidate = id
			if candidateTip then
				candidateTip:dismiss()
				candidateTip = nil
			end
			refresh()
		end, {
			Name = `Candidate_{id}`,
			LayoutOrder = index,
			AutomaticSize = Enum.AutomaticSize.None, -- the grid sizes it
			Parent = candidateGrid,
		})
		-- The top row: the candidate's portrait (painted in renderPortraits)
		-- beside the name over the kind.
		local top = Kit.box({
			Name = "Top",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, FACE),
			Parent = card,
		})
		local who = Kit.box({
			Name = "Who",
			Position = UDim2.fromOffset(FACE + Kit.space.sm, 0),
			Size = UDim2.new(1, -(FACE + Kit.space.sm), 1, 0),
			Parent = top,
		})
		local whoList = Kit.list("Vertical", 0)
		whoList.VerticalAlignment = Enum.VerticalAlignment.Center
		whoList.Parent = who
		local name = Kit.text(profile.name, {
			Name = "Name",
			LayoutOrder = 1,
			Font = Kit.font.bold,
			TextScaled = true,
			TextWrapped = false,
			Parent = who,
		})
		local archetype = Kit.caption(profile.archetype, {
			Name = "Archetype",
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.new(1, 0, 0, Kit.size.caption + 4),
			TextScaled = true,
			TextWrapped = false,
			Parent = who,
		})
		-- One line each, shrinking to fit a phone's narrow card.
		local line = {
			AutomaticSize = Enum.AutomaticSize.None,
			TextScaled = true,
			TextWrapped = false,
		}
		local perk = Kit.caption(`+ {short.strength}`, {
			Name = "Perk",
			LayoutOrder = 3,
			AutomaticSize = line.AutomaticSize,
			TextScaled = line.TextScaled,
			TextWrapped = line.TextWrapped,
			TextColor3 = Kit.colors.good,
			Parent = card,
		})
		local none = short.weakness == Words.NO_WEAKNESS
		local drawback = Kit.caption(`{Kit.glyph.minus} {short.weakness}`, {
			Name = "Drawback",
			LayoutOrder = 4,
			AutomaticSize = line.AutomaticSize,
			TextScaled = line.TextScaled,
			TextWrapped = line.TextWrapped,
			TextColor3 = if none then Kit.colors.muted else Kit.colors.bad,
			Parent = card,
		})
		local taken =
			Kit.pill("Taken", "muted", { Name = "Taken", LayoutOrder = 5, Visible = false, Parent = card })
		cards[id] = card
		parts[id] = {
			name = name,
			archetype = archetype,
			perk = perk,
			drawback = drawback,
			taken = taken,
			top = top,
			who = who,
		}
	end

	-- ------------------------------------------------------------ step 2: platform

	local issuesTip: CoachTip.Tip? = nil
	local issueGrid, issueLayout = Layout.grid(content, "Issues", 5)
	local chips: { [string]: TextButton } = {}
	local chipNames: { [string]: TextLabel } = {}
	local chipLines: { [string]: TextLabel } = {}
	local issueList: { string } = Issues.list :: any
	local coverage: { [string]: number } = {} -- votes per issue on this match's map
	local mults: { [string]: number } = {} -- platform multiplier per issue this match
	for index, issue in issueList do
		local chip = Kit.cardButton(function()
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
				Motion.pop(chips[issue], PICK_FROM)
			else
				-- Full: say how to swap instead of doing nothing.
				swapHintUntil = ctx.now() + SWAP_HINT_SECONDS
			end
			local tip = issuesTip
			if tip then
				tip:dismiss()
				issuesTip = nil
			end
			refresh()
		end, {
			Name = `Issue_{issue}`,
			LayoutOrder = index,
			AutomaticSize = Enum.AutomaticSize.None, -- the grid sizes it
			Parent = issueGrid,
		})
		chipNames[issue] = Kit.text(Data.issueName(issue), {
			Name = "IssueName",
			LayoutOrder = 1,
			Font = Kit.font.medium,
			TextScaled = true,
			TextWrapped = false,
			Parent = chip,
		})
		-- The issue's symbol before its name (D-076), the one players see on the map.
		Kit.issueLead(chipNames[issue], issue, Kit.ISSUE_ICON)
		chipLines[issue] = Kit.caption("", { Name = "IssueLine", LayoutOrder = 2, Parent = chip })
		chips[issue] = chip
	end

	-- ------------------------------------------------------------ color and details

	-- Colors are dealt at match start (D-055; picked in the Lobby with the Color
	-- Pass): a dot and a line, not a choice here.
	local colorRow = Kit.box({
		Name = "ColorRow",
		LayoutOrder = 9,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = content,
	})
	-- Your candidate's initials in your color (Kit.monogram), repainted when
	-- either changes (renderColor).
	local dotSlot = Kit.box({
		Name = "ColorSlot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Kit.space.xs, 0.5, 0),
		Size = UDim2.fromOffset(DOT, DOT),
		Parent = colorRow,
	})
	local colorLine = Kit.text("", {
		Name = "ColorLine",
		Position = UDim2.fromOffset(DOT + Kit.space.md, 0),
		Size = UDim2.new(1, -(DOT + Kit.space.md + DETAILS_W), 1, 0),
		Parent = colorRow,
	})

	-- One ghost at the right of the color line: the picked candidate's numbers
	-- (step 1) or how issues work (step 2), each in a sheet.
	local candidateSheet = Sheet.new(parent, { title = "", name = "CandidateSheet", height = 0.5 })
	local issuesSheet = Sheet.new(parent, { title = "How issues work", name = "IssuesSheet", height = 0.6 })
	for k, line in Words.ISSUES_HELP do
		Kit.text(line, {
			Name = `HelpLine{k}`,
			LayoutOrder = k,
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = issuesSheet.body,
		})
	end
	local detailLines: { TextLabel } = {}
	local function openCandidate(id: string)
		local profile = Candidates.profile(ctx.config, id)
		candidateSheet:setTitle(profile.name)
		for k, line in Words.candidateDetails(ctx.config, id) do
			local found: TextLabel? = detailLines[k]
			local label: TextLabel = if found
				then found
				else Kit.text("", {
					Name = `DetailLine{k}`,
					LayoutOrder = k,
					AutomaticSize = Enum.AutomaticSize.Y,
					Parent = candidateSheet.body,
				})
			detailLines[k] = label
			label.Text = line
			label.TextColor3 = if k <= 2 then Kit.colors.muted else Kit.colors.text
		end
		candidateSheet:open()
	end
	local details = Kit.button("", function()
		if step() == 1 then
			local id = candidate
			if id ~= nil then
				openCandidate(id)
			end
		else
			issuesSheet:open()
		end
	end, {
		variant = "ghost",
		Name = "Details",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, DETAILS_W, 1, 0),
		Parent = colorRow,
	})

	-- A monogram in `slot` for candidate `id` (or "?" before a pick) in
	-- `color`, rebuilt only when what it shows changed.
	local function paintMonogram(slot: Instance, name: string, label: string, color: Color3, px: number)
		local key = `{label}|{px}|{color.R},{color.G},{color.B}`
		if slot:GetAttribute("Painted") == key then
			return
		end
		slot:SetAttribute("Painted", key)
		local old = slot:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		local mono = Kit.monogram(label, color, px)
		mono.Name = name
		mono.Parent = slot
	end

	-- ------------------------------------------------------------ color picker (D-061)

	-- Six swatches in a row for a Color Pass owner, each a 44 px round chip with
	-- a monogram in that color over its name. Hidden for everyone else.
	local colorPending: string? = nil -- a color claim sent and not yet answered
	local messageAtColor = 0 -- id of the newest message when it was sent
	local picker = Kit.box({
		Name = "ColorPicker",
		LayoutOrder = 10,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH + SWATCH_NAME_H),
		Visible = false,
		Parent = content,
	})
	local swatchRow = Kit.box({ Name = "Swatches", Size = UDim2.fromScale(1, 1), Parent = picker })
	Kit.new("UISizeConstraint", {
		MaxSize = Vector2.new(SWATCH_CELL_MAX * #Candidates.colors, math.huge),
		Parent = swatchRow,
	})
	Kit.list("Horizontal", 0).Parent = swatchRow
	type Swatch = { cell: Frame, button: TextButton, slot: Frame, name: TextLabel }
	local swatches: { [string]: Swatch } = {}
	local claimColor: (color: string) -> ()
	for k, color in Candidates.colors do
		local cell = Kit.box({
			Name = `Cell_{color}`,
			LayoutOrder = k,
			Size = UDim2.fromScale(1 / #Candidates.colors, 1),
			Parent = swatchRow,
		})
		local button = Kit.chip("", function()
			claimColor(color)
		end, {
			Name = `ColorSwatch_{color}`,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(Kit.MIN_TOUCH, Kit.MIN_TOUCH),
			Parent = cell,
		})
		button.BackgroundTransparency = 1
		local corner = button:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0.5, 0)
		end
		local pad = button:FindFirstChildOfClass("UIPadding")
		if pad then
			pad:Destroy()
		end
		local slot = Kit.box({
			Name = "Slot",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(SWATCH, SWATCH),
			Parent = button,
		})
		local name = Kit.caption(color, {
			Name = "ColorName",
			AutomaticSize = Enum.AutomaticSize.None,
			Position = UDim2.new(0, 0, 1, -SWATCH_NAME_H),
			Size = UDim2.new(1, 0, 0, SWATCH_NAME_H),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = true,
			TextWrapped = false,
			Parent = cell,
		})
		Kit.new("UITextSizeConstraint", {
			MaxTextSize = Kit.size.caption,
			MinTextSize = Kit.MIN_TEXT,
			Parent = name,
		})
		swatches[color] = { cell = cell, button = button, slot = slot, name = name }
	end

	-- Each card's portrait (D-068) on a neutral plate, so the eight faces tell
	-- the candidates apart. A ring in a player color marks whose it is: yours
	-- (picked or claimed) in your color, the taken one in your opponent's
	-- (dimmed); free candidates have none.
	local function renderPortraits()
		local current = payload
		local mine: Color3? = nil
		local theirs: Color3? = nil
		if current then
			mine = Kit.playerColor(current.view, current.you)
			local other = Data.opponent(current)
			if current.view.players[other] then
				theirs = Kit.playerColor(current.view, other)
			end
		end
		local px = if lastPortrait then FACE_PORTRAIT else FACE
		for id, p in parts do
			local face = p.top:FindFirstChild("Portrait") :: Frame?
			if face == nil or face.Size.X.Offset ~= px then
				if face then
					face:Destroy()
				end
				face = Kit.portrait(id, Candidates.profile(ctx.config, id).name, px)
				local built = face :: Frame
				built.Parent = p.top
			end
			local who = holder(id)
			local ring = if who == "theirs"
				then theirs
				elseif who == "mine" or id == candidate then mine
				else nil
			Kit.paintPortrait(face :: Frame, {
				ring = ring or (if who ~= nil or id == candidate then Kit.colors.neutral else nil),
				fade = if who == "theirs" then TAKEN_FADE else 0,
			})
			p.top.Size = UDim2.new(1, 0, 0, px)
			p.who.Position = UDim2.fromOffset(px + Kit.space.sm, 0)
			p.who.Size = UDim2.new(1, -(px + Kit.space.sm), 1, 0)
		end
	end

	-- Who holds a color: "mine", "theirs" or nil (free, or only dealt).
	local function colorHolder(color: string): string?
		local current = payload
		local claims = if current then current.view.colorClaims else nil
		local owner = if claims then claims[color] else nil
		if owner == nil then
			return nil
		end
		return if owner == (current :: Session.StatePayload).you then "mine" else "theirs"
	end

	local function canPick(): boolean
		local current = payload
		return current ~= nil and current.view.canPickColor == true
	end

	claimColor = function(color: string)
		local current = payload
		if current == nil or not canPick() or colorPending ~= nil or colorHolder(color) == "theirs" then
			return
		end
		if current.view.players[current.you].color == color then
			return
		end
		colorPending = color
		messageAtColor = Messages.lastId(ctx.store.get())
		local send = ctx.net.claimColor
		if send then
			send(color)
		end
		Motion.pop(swatches[color].button, PICK_FROM)
		refresh()
	end

	-- The local player's name, for the swatches before a candidate is picked.
	local function playerName(): string
		local player = Players.LocalPlayer
		local display = if player then (player :: any).DisplayName else nil
		if type(display) == "string" and display ~= "" then
			return display
		end
		return if player then player.Name else "You"
	end

	local function renderPicker(mineName: string?)
		local shown = canPick()
		picker.Visible = shown
		if not shown then
			return
		end
		local id = candidate
		local label = if id then Candidates.profile(ctx.config, id).name else playerName()
		local theirsLabel = "?"
		for _, other in Candidates.ids do
			if holder(other) == "theirs" then
				theirsLabel = Candidates.profile(ctx.config, other).name
			end
		end
		local selected = colorPending or mineName
		for color, swatch in swatches do
			local taken = colorHolder(color) == "theirs"
			local tint = Kit.color(Colors.of(color))
			paintMonogram(swatch.slot, "Monogram", if taken then theirsLabel else label, tint, SWATCH)
			local mono = swatch.slot:FindFirstChild("Monogram") :: Frame?
			if mono then
				mono.BackgroundTransparency = if taken then TAKEN_FADE else 0
				local letters = mono:FindFirstChild("Initials") :: TextLabel?
				if letters then
					letters.TextTransparency = if taken then TAKEN_FADE else 0
				end
			end
			Kit.setSelected(swatch.button, color == selected)
			Kit.setEnabled(swatch.button, not taken and colorPending == nil)
			swatch.button.BackgroundTransparency = 1
			swatch.name.Text = if taken then Words.COLOR_TAKEN_TAG else color
			swatch.name.TextColor3 = if color == selected then Kit.colors.text else Kit.colors.muted
		end
	end

	local function renderColor()
		local current = payload
		local me = if current then current.view.players[current.you] else nil
		local name = if me then me.color else nil
		local id = candidate
		local label = if id then Candidates.profile(ctx.config, id).name else "?"
		paintMonogram(dotSlot, "ColorDot", label, Kit.color(Colors.of(name)), DOT)
		colorLine.Text = if name then `Your color: {name}` else "Your color: red or blue"
		renderPicker(name)
	end

	-- ------------------------------------------------------------ custom name (D-069)

	-- A line under the color for a player who may use the Name Pass (it is set
	-- up and they are a verified 16+ account: payload.naming): "Name: Captain
	-- Zed" and Rename (an owner: opens the name sheet) or Get the Name Pass
	-- (Roblox's purchase prompt; the server hears the outcome and the next State
	-- turns the button into Rename). Hidden for everyone else.
	local nameRow = Kit.box({
		Name = "NameRow",
		LayoutOrder = 11,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Visible = false,
		Parent = content,
	})
	local nameLine = Kit.text("", {
		Name = "NameLine",
		Position = UDim2.fromOffset(Kit.space.xs, 0),
		Size = UDim2.new(1, -(NAME_BUTTON_W + Kit.space.xs), 1, 0),
		TextScaled = true,
		TextWrapped = false,
		Parent = nameRow,
	})
	Kit.new(
		"UITextSizeConstraint",
		{ MaxTextSize = Kit.size.body, MinTextSize = Kit.MIN_TEXT, Parent = nameLine }
	)
	-- Under the offer (eligible, without the pass): names follow Roblox's rules.
	local nameRules = Kit.caption(Words.NAME_RULES, {
		Name = "NameRules",
		LayoutOrder = 12,
		Visible = false,
		Parent = content,
	})
	local nameSheet = Sheet.new(parent, { title = Words.NAME_TITLE, name = "NameSheet", height = 0.5 })
	local openNameSheet: (current: string?) -> ()
	local nameButton = Kit.button("", function()
		local current = payload
		local naming = if current then current.naming else nil
		if naming == nil then
			return
		end
		if naming.owned then
			openNameSheet(naming.name)
		else
			local buy = ctx.net.buyPass
			if buy then
				buy(naming.id)
			end
		end
	end, {
		variant = "ghost",
		Name = "NameButton",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, NAME_BUTTON_W, 1, 0),
		Parent = nameRow,
	})
	local nameBox = Kit.new("TextBox", {
		Name = "NameBox",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		BackgroundColor3 = Kit.colors.field,
		BorderSizePixel = 0,
		Font = Kit.font.medium,
		TextSize = Kit.size.body,
		TextColor3 = Kit.colors.text,
		PlaceholderColor3 = Kit.colors.muted,
		ClearTextOnFocus = false,
		Text = "",
		Parent = nameSheet.body,
	}) :: TextBox
	Kit.corner(Kit.radius.control).Parent = nameBox
	Kit.stroke(Kit.colors.line, 1).Parent = nameBox
	Kit.pad(Kit.space.md).Parent = nameBox
	-- Typing stops at the limit (the server checks it again after trimming).
	nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		local text = nameBox.Text
		local length = utf8.len(text)
		local max = ctx.config.NAME_MAX_LENGTH
		if length and length > max then
			nameBox.Text = string.sub(text, 1, (utf8.offset(text, max + 1) or (#text + 1)) - 1)
		end
	end)
	Kit.caption(Words.nameHint(ctx.config.NAME_MAX_LENGTH), {
		Name = "NameHint",
		LayoutOrder = 2,
		Parent = nameSheet.body,
	})
	Kit.caption(Words.NAME_RULES, { Name = "NameSheetRules", LayoutOrder = 3, Parent = nameSheet.body })
	local nameStatus = Kit.caption("", { Name = "NameStatus", LayoutOrder = 4, Parent = nameSheet.body })
	local namePending = false -- a SetName sent and not yet answered
	local nameWanted: string? = nil -- the name it asked for, cleaned as the server cleans it
	local messageAtName = 0 -- id of the newest message when it was sent
	local function sendName(name: string?)
		local send = ctx.net.setName
		if send == nil or namePending then
			return
		end
		namePending = true
		nameWanted = if name then (CustomName.normalize(name, ctx.config)) else nil
		messageAtName = Messages.lastId(ctx.store.get())
		nameStatus.Text = Words.NAME_SAVING
		nameStatus.TextColor3 = Kit.colors.muted
		nameStatus:SetAttribute("Warn", nil)
		send(name)
	end
	local nameActions = Kit.box({
		Name = "NameActions",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = nameSheet.body,
	})
	Kit.list("Horizontal", Kit.space.sm).Parent = nameActions
	Kit.button(Words.NAME_RESET, function()
		sendName(nil)
	end, {
		variant = "ghost",
		Name = "NameReset",
		LayoutOrder = 1,
		Size = UDim2.new(0.5, -Kit.space.sm / 2, 1, 0),
		Parent = nameActions,
	})
	Kit.button(Words.NAME_SAVE, function()
		sendName(nameBox.Text)
	end, {
		variant = "secondary",
		Name = "NameSave",
		LayoutOrder = 2,
		Size = UDim2.new(0.5, -Kit.space.sm / 2, 1, 0),
		Parent = nameActions,
	})

	openNameSheet = function(current: string?)
		nameBox.Text = current or ""
		if not namePending then
			nameStatus.Text = ""
			nameStatus:SetAttribute("Warn", nil)
		end
		nameSheet:open()
	end

	local function renderName()
		local current = payload
		local naming = if current then current.naming else nil
		nameRow.Visible = naming ~= nil
		nameRules.Visible = naming ~= nil and not naming.owned
		if naming == nil then
			if nameSheet:isOpen() then
				nameSheet:close()
			end
			return
		end
		local id = candidate
		local own = if id then Candidates.profile(ctx.config, id).name else nil
		nameLine.Text = Words.nameLine(naming.name or own)
		nameButton.Text = if naming.owned then Words.NAME_RENAME else Words.NAME_BUY
		nameBox.PlaceholderText = own or Words.NAME_TITLE
	end

	-- ------------------------------------------------------------ layout

	-- Shows the current step's blocks and sizes the grids for the orientation.
	local function placeBlocks(portrait: boolean, current: number)
		local columns = if portrait then 2 else 4
		Layout.setGrid(candidateLayout, columns, if portrait then CARD_H_PORTRAIT else CARD_H)
		Layout.setGrid(issueLayout, columns, if portrait then ISSUE_H_PORTRAIT else ISSUE_H)
		local inset = if portrait then Kit.space.sm else Kit.space.md
		for _, card in cards do
			local pad = card:FindFirstChildOfClass("UIPadding")
			if pad then
				pad.PaddingTop = UDim.new(0, inset)
				pad.PaddingBottom = UDim.new(0, inset)
			end
		end
		local first = current == 1
		candidateGrid.Visible = first
		issueGrid.Visible = not first
		if not first and issuesTip == nil and not isLocked() then
			issuesTip = showTip(content, "select.issues", 4)
		end
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

	-- The status line, which also depends on the clock (swap hint).
	local function renderStatus()
		if isLocked() then
			bar:setStatus("Locked in", "muted")
		elseif ctx.now() < swapHintUntil then
			bar:setStatus(`You already have {platformSize}; tap one to swap it`, "warn")
		elseif rejection then
			bar:setStatus(rejection, "bad")
		elseif step() == 1 then
			bar:setStatus(if claiming ~= nil then "Saving your pick…" else "Step 1 of 2", "muted")
		elseif isReady() and prePickLoaded then
			bar:setStatus("Your last pick is loaded", "muted")
		elseif payload ~= nil and payload.daily ~= nil and claimed() ~= nil then
			-- The Daily Race (D-082): the candidate is today's, for everyone.
			local name = Words.firstName(Candidates.profile(ctx.config, claimed() :: string).name)
			bar:setStatus(`Daily Race: everyone is {name} today`, "muted")
		else
			bar:setStatus("Step 2 of 2", "muted")
		end
	end

	-- The "what to do now" line under the header.
	local function renderNow()
		if isLocked() then
			header:setNow(Words.nowWaiting(opponentName()))
		elseif step() == 1 then
			header:setNow(if claiming ~= nil then Words.NOW_CLAIMING else Words.NOW_CANDIDATE)
		else
			header:setNow(Words.nowIssues(#platform, platformSize))
		end
	end

	-- A step's cards pop in one after another, in reading order.
	local function arrive(current: number)
		local list: { TextButton } = {}
		if current == 1 then
			for _, id in Candidates.ids do
				table.insert(list, cards[id])
			end
		else
			for _, issue in issueList do
				table.insert(list, chips[issue])
			end
		end
		Motion.stagger(list, function(card, _index, delay)
			Motion.pop(card, ARRIVE_FROM, delay)
		end)
	end

	-- Lays the page out again when the orientation or the step changed; says so.
	local function relayout(): boolean
		local portrait = ctx.portrait()
		local current = step()
		if portrait == lastPortrait and current == lastStep then
			return false
		end
		if current ~= lastStep then
			arrive(current)
		end
		lastPortrait, lastStep = portrait, current
		page.setPortrait(portrait)
		placeBlocks(portrait, current)
		return true
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
			card.BackgroundTransparency = if taken then TAKEN_FADE else 0
			local p = parts[id]
			p.taken.Visible = taken
			p.perk.Visible = not taken
			p.drawback.Visible = not taken
			p.name.TextTransparency = if taken then TAKEN_FADE else 0
			p.archetype.TextTransparency = if taken then TAKEN_FADE else 0
		end
		renderColor()
		renderPortraits()
		renderName()
		local full = #platform >= platformSize
		for issue, chip in chips do
			local picked = table.find(platform, issue) ~= nil
			local name = Data.issueName(issue)
			chipNames[issue].Text = if picked then PICKED .. name else name
			chipLines[issue].Text = Words.issueLine(coverage[issue], mults[issue], lastPortrait == true)
			Kit.setSelected(chip, picked)
			Kit.setEnabled(chip, not locked)
			-- Full: the others look quieter but stay tappable (for the swap hint).
			local quiet = locked or (full and not picked)
			chipNames[issue].TextColor3 = if quiet then Kit.colors.muted else Kit.colors.text
		end

		if first then
			header:setTitle("Your candidate")
			local id = candidate
			details.Visible = id ~= nil
			details.Text = if id
				then `About {Words.firstName(Candidates.profile(ctx.config, id).name)}`
				else ""
		else
			header:setTitle("Your issues")
			details.Visible = true
			details.Text = "How issues work"
		end

		local _, theirs = seats()
		local who = opponentName()
		local label = if who == "your opponent" then "Opponent" else who
		local opponentText = `{label}: picking`
		if theirs then
			if not theirs.connected then
				opponentText = `{label}: disconnected`
			elseif theirs.locked then
				opponentText = `{label}: locked in`
			end
		end
		bar:setOpponent(opponentText)

		if locked then
			bar:setPrimary("Locked in", false)
		elseif first then
			if claiming ~= nil then
				bar:setPrimary("Saving…", false)
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
		renderNow()
	end

	local function updateTimer(now: number)
		local current = payload
		if current == nil then
			header:setTimer(nil)
			return
		end
		local deadline = current.deadline
		if deadline == nil then
			header:setNoTimer(Header.noTimerText(current)) -- the tutorial (D-075), an admin (D-081)
			return
		end
		-- The bar runs over the stage's own length (a bot match scales it, D-075).
		header:setTimer(deadline - now, nil, deadline - current.stageStart)
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
			-- A color claim is answered by the next payload: granted (your color),
			-- taken first by the opponent, or turned down (a message; the toast says why).
			local wanted = colorPending
			if wanted ~= nil and current ~= nil then
				local answer = Messages.newestAfter(state, messageAtColor)
				local me = current.view.players[current.you]
				if
					(me ~= nil and me.color == wanted)
					or colorHolder(wanted) == "theirs"
					or not canPick()
					or answer ~= nil
				then
					colorPending = nil
				end
			end
			-- A SetName is answered by a new State (the name changed) or a
			-- rejection (a message): close the sheet, or say why in it.
			if namePending then
				local answer = Messages.newestAfter(state, messageAtName)
				local naming = if current then current.naming else nil
				if answer ~= nil and answer.rejected then
					namePending = false
					nameStatus.Text = answer.text
					nameStatus.TextColor3 = Kit.colors.loss
					nameStatus:SetAttribute("Warn", true)
				elseif naming ~= nil and naming.name == nameWanted then
					namePending = false
					nameStatus.Text = ""
					nameSheet:close()
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
			if relayout() then
				refresh() -- rotated: the chips' lines depend on the width
			end
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
