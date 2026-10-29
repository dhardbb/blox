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
-- The 0.17 pass (D-091): a pick wears a check badge that pops in (UI/CheckBadge;
-- an issue tile is also tinted in your color, its votes bold and its boost a
-- green pill); the iPad's portraits are bigger; the header's title is a
-- two-dot step indicator (Candidate, Issues) instead of repeating the "now"
-- line; links ("About Goldie", "Rename") are right-aligned with an arrow
-- (UI/LinkButton); the Color Pass swatches are plain dots with names; the name
-- line and the Name Pass offer are one card with a pencil and a gold pill; in
-- the last seconds the Lock in drains (Common/PickClock). A landscape phone
-- (Kit.compact) uses a `side` page: the cards or tiles get the full height on
-- the left in two columns (a compact card: the portrait beside name, strength
-- and weakness), and the right column holds the header, the tip, the color
-- line, the swatches and the name card over the action bar.
--
-- Stable names: Candidate_<id> (with Portrait, Name, Archetype, Perk, Drawback, Taken,
-- Check), Issue_<issue> (with IssueName, IssueLine, IssueBoost, Check),
-- Candidates, Issues, Steps (StepDot1/2, StepLabel1/2), SideExtras, ColorRow,
-- ColorDot, ColorLine, ColorPicker (ColorSwatch_<Color>, each with Dot and ColorName),
-- NameRow (Pencil, NameLine, NamePassPill, NameButton, NameRules), NameSheet
-- (NameBox, NameCount, NameSheetRules, NameStatus, NameSave, NameReset),
-- Details, CandidateSheet, IssuesHelp, IssuesSheet, LockIn,
-- BarStatus, BarOpponent, NowText, Timer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local CustomName = require(ReplicatedStorage.Shared.Net.CustomName)
local IssueMap = require(ReplicatedStorage.Shared.Sim.IssueMap)
local Issues = require(ReplicatedStorage.Shared.Sim.Issues)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local Words = require(ReplicatedStorage.Shared.UI.Words.Setup)

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local AutoLock = require(script.Parent.Common.AutoLock)
local CheckBadge = require(script.Parent.Parent.UI.CheckBadge)
local CoachTip = require(script.Parent.Parent.UI.CoachTip)
local Data = require(script.Parent.Common.Data)
local Header = require(script.Parent.Parent.UI.Header)
local Kit = require(script.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Common.Layout)
local LinkButton = require(script.Parent.Parent.UI.LinkButton)
local Messages = require(script.Parent.Common.Messages)
local Motion = require(script.Parent.Parent.UI.Motion)
local PickClock = require(script.Parent.Common.PickClock)
local Sheet = require(script.Parent.Parent.UI.Sheet)
local Types = require(script.Parent.Types)

local Screen = {}

local MAX_WIDTH = 1000 -- px
local CARD_H = 144 -- px, a candidate card: the portrait beside name and kind, then strength and weakness
local CARD_H_PORTRAIT = 102 -- px, the same on a portrait phone (tighter padding, a smaller portrait)
local CARD_H_COMPACT = 68 -- px, a landscape phone's card: the portrait beside name, strength and weakness (four rows fit)
local FACE = 72 -- px, a candidate's portrait (Kit.portrait) on a wide screen (an iPad, D-091: was 56)
local FACE_PORTRAIT = 40 -- px, on a portrait phone
local FACE_COMPACT = 44 -- px, on a landscape phone
local NAME_H = 20 -- px, a compact card's name line
local LINE_H = Kit.size.caption + 4 -- px, a strength or weakness line
local ISSUE_H = 80 -- px, an issue tile: symbol and name over the bold votes and the boost pill
local ISSUE_H_PORTRAIT = 104 -- px, on a portrait phone the votes and the boost take a line each
local ISSUE_H_COMPACT = 68 -- px, on a landscape phone (four rows fit)
local ISSUE_ICON = 26 -- px, an issue tile's symbol (D-091: was Kit.ISSUE_ICON, 20)
local ISSUE_ICON_SMALL = 22 -- px, the same on a phone
local ISSUE_TINT = 0.3 -- how far a picked tile's fill leans toward your color
local DOT = 24 -- px, the color line's monogram (your candidate's initials in your color)
local DETAILS_W = 200 -- px, the link beside the color line
local SWATCH = 28 -- px, a Color Pass swatch: a plain dot in its color (D-091: no initials)
local SWATCH_CELL_MAX = 72 -- px, widest a swatch's cell gets (six in a row; a phone gives each about 56)
local SWATCH_NAME_H = 18 -- px, the color name (or "Taken") under a swatch
local SWAP_HINT_SECONDS = 3 -- how long "tap one to swap it" stays up
local NAME_ROW_H = 32 -- px, the name card's first row: the pencil, the name and the gold pill
local PENCIL = 20 -- px, the pencil drawn before the name
local PASS_W = 100 -- px kept for the Name Pass's gold pill at the name row's right
local COUNT_W = 56 -- px, the name sheet's "16/16" count
local STEP_DOT = 12 -- px, a step indicator dot
local STEP_LABEL_W = { 92, 60 } -- px, room for "Candidate" (and a gap before the next dot) and "Issues" at body size
local SIDE_GAP = Kit.space.sm -- px, between the side column's blocks on a landscape phone
local SIDE_COLOR_H = 32 -- px, the color line there (its link takes the next row)
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
		side = true, -- a landscape phone: the header and the bar stand in a right column (D-089)
	})
	local content = page.content
	-- A landscape phone: the right column's middle, between the header and the
	-- bar, holds the tip, the color line, the swatches and the name card (D-091).
	local sideExtras = Kit.new("ScrollingFrame", {
		Name = "SideExtras",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		Visible = false,
		Parent = page.root,
	}) :: ScrollingFrame
	Kit.list("Vertical", SIDE_GAP).Parent = sideExtras
	Kit.new("UIPadding", { PaddingRight = UDim.new(0, Kit.space.sm), Parent = sideExtras })
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
	local lastClass: Kit.SizeClass? = nil
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
		title = "",
		now = true,
		onHelp = ctx.help,
	})
	-- The title's place shows where you are in the two steps (D-091): a dot
	-- per step, filled once reached, and its name, bold for the current one. The
	-- "now" line under it says what to do, so nothing is said twice.
	header.title.Visible = false
	local stepsBox = Kit.box({
		Name = "Steps",
		LayoutOrder = 0,
		Size = UDim2.new(0, 2 * STEP_DOT + STEP_LABEL_W[1] + STEP_LABEL_W[2] + 3 * Kit.space.xs, 1, 0),
		Parent = header.title.Parent,
	})
	local stepList = Kit.list("Horizontal", Kit.space.xs)
	stepList.VerticalAlignment = Enum.VerticalAlignment.Center
	stepList.Parent = stepsBox
	local stepDots: { Frame } = {}
	local stepLabels: { TextLabel } = {}
	for k, word in { "Candidate", "Issues" } do
		local dot = Kit.new("Frame", {
			Name = `StepDot{k}`,
			LayoutOrder = 2 * k - 1,
			Size = UDim2.fromOffset(STEP_DOT, STEP_DOT),
			BackgroundColor3 = Kit.colors.accent,
			BorderSizePixel = 0,
			Parent = stepsBox,
		}) :: Frame
		Kit.round().Parent = dot
		Kit.new("UIStroke", {
			Name = "Ring",
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Kit.colors.muted,
			Thickness = 2,
			Parent = dot,
		})
		stepDots[k] = dot
		stepLabels[k] = Kit.text(word, {
			Name = `StepLabel{k}`,
			LayoutOrder = 2 * k,
			Size = UDim2.new(0, STEP_LABEL_W[k], 1, 0),
			Font = Kit.font.bold,
			TextWrapped = false,
			Parent = stepsBox,
		})
	end
	local function renderSteps(current: number)
		for k, dot in stepDots do
			local reached = k <= current
			dot.BackgroundTransparency = if reached then 0 else 1
			local ring = dot:FindFirstChild("Ring") :: UIStroke?
			if ring then
				ring.Color = if reached then Kit.colors.accent else Kit.colors.muted
			end
			stepLabels[k].TextColor3 = if k == current then Kit.colors.text else Kit.colors.muted
			stepLabels[k].Font = if k == current then Kit.font.bold else Kit.font.medium
		end
	end
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
	local pickClock = PickClock.new(bar)

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
		check: Frame,
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
		-- Your pick: a check on the portrait's lower right (renderPortraits places it).
		local check = CheckBadge.new({ AnchorPoint = Vector2.new(0.5, 0.5), Parent = top })
		cards[id] = card
		parts[id] = {
			name = name,
			archetype = archetype,
			perk = perk,
			drawback = drawback,
			taken = taken,
			top = top,
			who = who,
			check = check,
		}
	end

	-- ------------------------------------------------------------ step 2: platform

	local issuesTip: CoachTip.Tip? = nil
	local issueGrid, issueLayout = Layout.grid(content, "Issues", 5)
	local chips: { [string]: TextButton } = {}
	local chipNames: { [string]: TextLabel } = {}
	local chipHeads: { [string]: Frame } = {}
	local chipRows: { [string]: Frame } = {}
	local chipRowLists: { [string]: UIListLayout } = {}
	local chipLines: { [string]: TextLabel } = {}
	local chipBoosts: { [string]: TextLabel } = {}
	local chipChecks: { [string]: Frame } = {}
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
		-- The head: the issue's symbol and name (D-076, the symbol players see on
		-- the map, bigger here: D-091), and the check once it is picked.
		local head = Kit.box({
			Name = "IssueHead",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, ISSUE_ICON),
			Parent = chip,
		})
		chipNames[issue] = Kit.text(Data.issueName(issue), {
			Name = "IssueName",
			Size = UDim2.new(1, -(CheckBadge.SIZE + Kit.space.xs), 1, 0),
			Font = Kit.font.bold,
			TextScaled = true,
			TextWrapped = false,
			Parent = head,
		})
		chipChecks[issue] = CheckBadge.new({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Parent = head,
		})
		-- What it is worth this match: the votes in bold, the boost a green pill
		-- (side by side; stacked on a portrait phone's half-width tile).
		local row = Kit.box({
			Name = "IssueRow",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, Kit.PILL_H),
			Parent = chip,
		})
		local rowList = Kit.list("Horizontal", Kit.space.sm)
		rowList.VerticalAlignment = Enum.VerticalAlignment.Center
		rowList.Parent = row
		chipLines[issue] = Kit.text("", {
			Name = "IssueLine",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(0, Kit.PILL_H),
			AutomaticSize = Enum.AutomaticSize.X,
			Font = Kit.font.bold,
			TextWrapped = false,
			Parent = row,
		})
		chipBoosts[issue] =
			Kit.pill("", "good", { Name = "IssueBoost", LayoutOrder = 2, filled = true, Parent = row })
		chipHeads[issue] = head
		chipRows[issue] = row
		chipRowLists[issue] = rowList
		chips[issue] = chip
	end

	-- ------------------------------------------------------------ color and details

	-- Colors are dealt at match start (D-055; picked in the Lobby with the Color
	-- Pass): a dot and a line, not a choice here.
	local colorRow = Kit.box({
		Name = "ColorRow",
		LayoutOrder = 8,
		Size = UDim2.new(1, 0, 0, LinkButton.HEIGHT),
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
	-- (On a landscape phone it stands on its own row under the color line.)
	local details = LinkButton.new("", function()
		if step() == 1 then
			local id = candidate
			if id ~= nil then
				openCandidate(id)
			end
		else
			issuesSheet:open()
		end
	end, {
		Name = "Details",
		LayoutOrder = 9,
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
	-- a plain dot in that color over its name (D-091: no initials, which read
	-- as one word repeated six times). Hidden for everyone else.
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
		local slot = Kit.dataColor(Kit.new("Frame", {
			Name = "Dot",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(SWATCH, SWATCH),
			BackgroundColor3 = Kit.color(Colors.of(color)),
			BorderSizePixel = 0,
			Parent = button,
		})) :: Frame
		Kit.round().Parent = slot
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
		local class = lastClass or "wide"
		local px = if class == "portrait"
			then FACE_PORTRAIT
			elseif class == "compact" then FACE_COMPACT
			else FACE
		-- A compact card's top holds the name, strength and weakness beside the face.
		local topH = if class == "compact" then NAME_H + 2 * LINE_H else px
		local faceY = (topH - px) // 2
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
			local built = face :: Frame
			built.Position = UDim2.fromOffset(0, faceY)
			local who = holder(id)
			local ring = if who == "theirs"
				then theirs
				elseif who == "mine" or id == candidate then mine
				else nil
			Kit.paintPortrait(built, {
				ring = ring or (if who ~= nil or id == candidate then Kit.colors.neutral else nil),
				fade = if who == "theirs" then TAKEN_FADE else 0,
			})
			p.top.Size = UDim2.new(1, 0, 0, topH)
			p.who.Position = UDim2.fromOffset(px + Kit.space.sm, 0)
			p.who.Size = UDim2.new(1, -(px + Kit.space.sm), 1, 0)
			-- The check sits on the portrait's lower right, in your color.
			local corner = math.floor(px * 0.85)
			p.check.Position = UDim2.fromOffset(corner, faceY + corner)
			CheckBadge.set(p.check, id == candidate and who ~= "theirs", mine)
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

	local function renderPicker(mineName: string?)
		local shown = canPick()
		picker.Visible = shown
		if not shown then
			return
		end
		local selected = colorPending or mineName
		for color, swatch in swatches do
			local taken = colorHolder(color) == "theirs"
			swatch.slot.BackgroundTransparency = if taken then TAKEN_FADE else 0
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

	-- One card for a player who may use the Name Pass (it is set up and they are
	-- a verified 16+ account: payload.naming), D-091: a pencil, "Name: Captain
	-- Zed" and the Name Pass as a gold pill, then a link: Rename (an owner: opens
	-- the name sheet) or Get the Name Pass (Roblox's purchase prompt; the server
	-- hears the outcome and the next State turns it into Rename), and for the
	-- offer, Roblox's rules. Hidden for everyone else.
	local nameRow = Kit.card({
		Name = "NameRow",
		LayoutOrder = 11,
		Visible = false,
		Parent = content,
	})
	local nameTop = Kit.box({
		Name = "NameTop",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, NAME_ROW_H),
		Parent = nameRow,
	})
	-- A pencil, drawn: a slanted body and its dark tip (decoration; the words say it).
	local pencil = Kit.box({
		Name = "Pencil",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(PENCIL, PENCIL),
		Parent = nameTop,
	})
	pencil:SetAttribute("Decor", true)
	Kit.new("Frame", {
		Name = "Body",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.55, 0.45),
		Size = UDim2.fromOffset(6, PENCIL),
		Rotation = 45,
		BackgroundColor3 = Kit.color(Colors.player.Amber),
		BorderSizePixel = 0,
		Parent = pencil,
	})
	Kit.new("Frame", {
		Name = "Tip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.12, 0.88),
		Size = UDim2.fromOffset(5, 5),
		Rotation = 45,
		BackgroundColor3 = Kit.colors.text,
		BorderSizePixel = 0,
		Parent = pencil,
	})
	Kit.pill("Name Pass", "text", {
		Name = "NamePassPill",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		fill = Kit.color(Colors.player.Amber),
		Parent = nameTop,
	})
	local nameLine = Kit.text("", {
		Name = "NameLine",
		Position = UDim2.fromOffset(PENCIL + Kit.space.sm, 0),
		Size = UDim2.new(1, -(PENCIL + Kit.space.sm + PASS_W), 1, 0),
		Font = Kit.font.bold,
		TextScaled = true,
		TextWrapped = false,
		Parent = nameTop,
	})
	local nameSheet = Sheet.new(parent, { title = Words.NAME_TITLE, name = "NameSheet", height = 0.5 })
	local openNameSheet: (current: string?) -> ()
	local nameButton = LinkButton.new("", function()
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
		Name = "NameButton",
		LayoutOrder = 2,
		Parent = nameRow,
	})
	-- Under the offer (eligible, without the pass): names follow Roblox's rules.
	local nameRules = Kit.caption(Words.NAME_RULES, {
		Name = "NameRules",
		LayoutOrder = 3,
		Visible = false,
		Parent = nameRow,
	})

	-- The sheet (D-091): an outlined box with a live "11/16" count, one short
	-- line of rules, "Save name" as the sheet's big button and "Use the
	-- candidate's name" as a quiet link under it.
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
	Kit.stroke(Kit.colors.muted, 2).Parent = nameBox
	Kit.pad(Kit.space.md).Parent = nameBox
	local nameMeta = Kit.box({
		Name = "NameMeta",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, Kit.size.caption + 4),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = nameSheet.body,
	})
	Kit.caption(Words.NAME_SHEET_RULES, {
		Name = "NameSheetRules",
		Size = UDim2.new(1, -(COUNT_W + Kit.space.sm), 0, Kit.size.caption + 4),
		Parent = nameMeta,
	})
	local nameCount = Kit.caption("", {
		Name = "NameCount",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(COUNT_W, Kit.size.caption + 4),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = nameMeta,
	})
	local function renderCount()
		local max = ctx.config.NAME_MAX_LENGTH
		local length = utf8.len(nameBox.Text) or #nameBox.Text
		nameCount.Text = `{math.min(length, max)}/{max}`
		nameCount.TextColor3 = if length >= max then Kit.colors.text else Kit.colors.muted
	end
	-- Typing stops at the limit (the server checks it again after trimming).
	nameBox:GetPropertyChangedSignal("Text"):Connect(function()
		local text = nameBox.Text
		local length = utf8.len(text)
		local max = ctx.config.NAME_MAX_LENGTH
		if length and length > max then
			nameBox.Text = string.sub(text, 1, (utf8.offset(text, max + 1) or (#text + 1)) - 1)
		end
		renderCount()
	end)
	local nameStatus = Kit.caption("", { Name = "NameStatus", LayoutOrder = 3, Parent = nameSheet.body })
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
	Kit.button(Words.NAME_SAVE, function()
		sendName(nameBox.Text)
	end, {
		variant = "secondary",
		Name = "NameSave",
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, Kit.PRIMARY_H),
		Font = Kit.font.display,
		TextSize = Kit.size.heading,
		Parent = nameSheet.body,
	})
	Kit.button(Words.NAME_RESET, function()
		sendName(nil)
	end, {
		variant = "ghost",
		Name = "NameReset",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = nameSheet.body,
	})

	openNameSheet = function(current: string?)
		nameBox.Text = current or ""
		renderCount()
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
	local function placeBlocks(class: Kit.SizeClass, current: number)
		local portrait = class == "portrait"
		local compact = class == "compact"
		local columns = if class == "wide" then 4 else 2
		Layout.setGrid(
			candidateLayout,
			columns,
			if portrait then CARD_H_PORTRAIT elseif compact then CARD_H_COMPACT else CARD_H
		)
		Layout.setGrid(
			issueLayout,
			columns,
			if portrait then ISSUE_H_PORTRAIT elseif compact then ISSUE_H_COMPACT else ISSUE_H
		)
		local inset = if compact then Kit.space.xs elseif portrait then Kit.space.sm else Kit.space.md
		for id, card in cards do
			local pad = card:FindFirstChildOfClass("UIPadding")
			if pad then
				pad.PaddingTop = UDim.new(0, inset)
				pad.PaddingBottom = UDim.new(0, inset)
			end
			-- A compact card: name, strength and weakness (or Taken) beside the
			-- face; the kind is in "About". Elsewhere they sit under the top row.
			local p = parts[id]
			local holderOf = if compact then p.who else card
			p.archetype.Visible = not compact
			p.name.Size = UDim2.new(1, 0, 0, if compact then NAME_H else Kit.size.body + 6)
			p.perk.Parent = holderOf
			p.drawback.Parent = holderOf
			p.taken.Parent = holderOf
		end
		local icon = if class == "wide" then ISSUE_ICON else ISSUE_ICON_SMALL
		for issue, chip in chips do
			local pad = chip:FindFirstChildOfClass("UIPadding")
			if pad then
				pad.PaddingTop = UDim.new(0, inset)
				pad.PaddingBottom = UDim.new(0, inset)
			end
			chipHeads[issue].Size = UDim2.new(1, 0, 0, icon)
			if chipNames[issue]:GetAttribute("LeadSize") ~= icon then
				chipNames[issue]:SetAttribute("LeadSize", icon)
				Kit.issueLead(chipNames[issue], issue, icon)
			end
			-- A portrait phone's half-width tile stacks the votes over the pill.
			chipRowLists[issue].FillDirection = if portrait
				then Enum.FillDirection.Vertical
				else Enum.FillDirection.Horizontal
			chipRows[issue].Size =
				UDim2.new(1, 0, 0, if portrait then 2 * Kit.PILL_H + Kit.space.xs else Kit.PILL_H)
		end
		-- The blocks beside the cards: in the right column on a landscape phone.
		local side = page.sideways()
		sideExtras.Visible = side
		if side then
			local share = Layout.SIDE_SHARE
			local half = Layout.GAP // 2
			local top = Kit.HEADER_H + Kit.NOW_H + SIDE_GAP
			sideExtras.Position = UDim2.new(1 - share, half, 0, top)
			sideExtras.Size = UDim2.new(share, -half, 1, -(top + Kit.BAR_H + SIDE_GAP))
		end
		local home = if side then sideExtras else content
		for _, block in { colorRow, picker, nameRow } do
			block.Parent = home
		end
		for _, tip in { candidateTip, issuesTip } do
			if tip then
				tip.root.Parent = home
			end
		end
		-- The link stands beside the color line, or under it in the narrow column.
		if side then
			details.Parent = sideExtras
			details.AnchorPoint = Vector2.new(0, 0)
			details.Position = UDim2.fromOffset(0, 0)
			details.Size = UDim2.new(1, 0, 0, LinkButton.HEIGHT)
			colorLine.Size = UDim2.new(1, -(DOT + Kit.space.md), 1, 0)
			colorRow.Size = UDim2.new(1, 0, 0, SIDE_COLOR_H)
		else
			colorRow.Size = UDim2.new(1, 0, 0, LinkButton.HEIGHT)
			details.Parent = colorRow
			details.AnchorPoint = Vector2.new(1, 0)
			details.Position = UDim2.fromScale(1, 0)
			details.Size = UDim2.new(0, DETAILS_W, 1, 0)
			colorLine.Size = UDim2.new(1, -(DOT + Kit.space.md + DETAILS_W), 1, 0)
		end
		local first = current == 1
		candidateGrid.Visible = first
		issueGrid.Visible = not first
		if not first and issuesTip == nil and not isLocked() then
			issuesTip = showTip(home, "select.issues", 4)
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
			-- The step dots in the header say where you are (D-091).
			bar:setStatus(if claiming ~= nil then "Saving your pick…" else "", "muted")
		elseif isReady() and prePickLoaded then
			bar:setStatus("Your last pick is loaded", "muted")
		elseif payload ~= nil and payload.daily ~= nil and claimed() ~= nil then
			-- The Daily Race (D-082): the candidate is today's, for everyone.
			local name = Words.firstName(Candidates.profile(ctx.config, claimed() :: string).name)
			bar:setStatus(`Daily Race: everyone is {name} today`, "muted")
		else
			bar:setStatus("", "muted")
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
	local function sizeClass(): Kit.SizeClass
		if ctx.portrait() then
			return "portrait"
		end
		return if Kit.compact(parent.AbsoluteSize) then "compact" else "wide"
	end

	local function relayout(): boolean
		local class = sizeClass()
		local current = step()
		if class == lastClass and current == lastStep then
			return false
		end
		if current ~= lastStep then
			arrive(current)
		end
		lastClass, lastStep = class, current
		page.setPortrait(class == "portrait")
		placeBlocks(class, current)
		renderSteps(current)
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
		-- A picked tile: the outline, a check and a fill tinted in your color (D-091).
		local current = payload
		local myColor = if current then Kit.playerColor(current.view, current.you) else Kit.colors.accent
		local tinted = Kit.color(Colors.tint(Colors.raised, Kit.rgb(myColor), ISSUE_TINT))
		for issue, chip in chips do
			local picked = table.find(platform, issue) ~= nil
			chipNames[issue].Text = Data.issueName(issue)
			local votes = coverage[issue]
			chipLines[issue].Text = if votes then Words.votes(votes) else ""
			local mult = mults[issue]
			chipBoosts[issue].Text = if mult then `{Words.boost(mult)} boost` else ""
			chipBoosts[issue].Visible = mult ~= nil
			Kit.setSelected(chip, picked)
			Kit.setEnabled(chip, not locked)
			if picked then
				chip.BackgroundColor3 = tinted
			end
			chip:SetAttribute("DataColor", if picked then true else nil)
			CheckBadge.set(chipChecks[issue], picked, myColor)
			-- Full: the others look quieter but stay tappable (for the swap hint).
			local quiet = locked or (full and not picked)
			chipNames[issue].TextColor3 = if quiet then Kit.colors.muted else Kit.colors.text
			chipLines[issue].TextColor3 = if quiet then Kit.colors.muted else Kit.colors.text
		end

		if first then
			local id = candidate
			details.Visible = id ~= nil
			details.Text = if id
				then `About {Words.firstName(Candidates.profile(ctx.config, id).name)}`
				else ""
		else
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
			pickClock:paint(nil, false)
			return
		end
		-- The bar runs over the stage's own length (a bot match scales it, D-075).
		header:setTimer(deadline - now, nil, deadline - current.stageStart)
		-- The last seconds: Lock in (or Next) drains while something can be pressed.
		pickClock:paint(deadline - now, not isLocked() and bar.primary.Active)
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
