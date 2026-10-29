--!strict
-- "How to play" (docs/UI-STYLE.md §4.10): a sheet (bottom sheet on a phone,
-- centered panel on wide screens) with five tabs: How to win, Your turn,
-- Actions, Events & debates, Polls & ground game. Each tab is a small picture
-- built from frames (a race bar, the three steps of a turn, the six actions,
-- a debate scoreboard, the three kinds of polls) and at most 60 words
-- (Shared/UI/Words/Reveal.help); the Actions and Polls pictures carry each
-- action's icon (UI/Icons) beside its name. Under each, "All the numbers"
-- opens today's exact rules for that tab, every number from Config and your
-- candidate (Shared/UI/Explain.help), so a balance change needs no edit here.
--
-- Mounted once by App.client above the screens (below the toast); every
-- header's "?" opens it (ctx.help). It opens on the tab for the moment (a
-- debate or a stance: Events; the plan: Your turn; else How to win), keeps the
-- step's countdown in its title row (the clock keeps running), and closes with
-- its × or a tap outside. It never holds a primary action. How to win starts
-- with the Settings row (UI/Settings: Sound and Reduce motion, session only).
--
--   local help = Help.mount(parent, ctx)
--   help.open() · help.close() · help.isOpen() -> boolean · help.destroy()
--   help.select(tabId)            shows one tab ("win", "turn", "actions", "events", "polls")
--   help.root   Frame "HelpOverlay" (Visible only while open; PrimaryOptional)
--   Elements: HelpSheet (UI/Sheet), HelpClose (the ×), HelpTimer, HelpTabs,
--   HelpTab_<tab>, HelpPage_<tab>, HelpArt_<tab>, HelpIntro_<tab>,
--   HelpMoreButton_<tab>, HelpMore_<tab>, HelpSection_<id>, HelpTitle_<id>,
--   HelpText_<id> (one per Explain.help section), HelpSettings (the label
--   HelpSettingsLabel and the row Settings with SoundChip and MotionChip),
--   HelpLeave (D-059: "Leave match" at the end, only in a live match and only
--   when App gave ctx.leave; it closes Help and opens the confirmation).
--   HelpBug (D-090: "Report a bug", a small ghost button at the very end when
--   App gave ctx.bug; it closes Help and opens UI/BugSheet for this screen).
--   HelpAdmin (D-081, admins only: the payload's adminTimers): above the tabs,
--   the chip HelpAdminTimers ("Timers off (admin)", outlined while on; a tap
--   sends SetTimersOff) and the line HelpAdminNote (what it does here, or
--   "Only in games where every player is an admin.").
--   Help.art.<tab>(frame, config) draws a tab's picture (the Lobby's How to
--   play reuses them).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)
local Explain = require(ReplicatedStorage.Shared.UI.Explain)
local Issues = require(ReplicatedStorage.Shared.Sim.Issues)
local LobbyWords = require(ReplicatedStorage.Shared.UI.Words.Lobby)
local Words = require(ReplicatedStorage.Shared.UI.Words.Reveal)
local SetupWords = require(ReplicatedStorage.Shared.UI.Words.Setup)

local Audit = require(script.Parent.Audit)
local Kit = require(script.Parent.Kit)
local Settings = require(script.Parent.Settings)
local Sheet = require(script.Parent.Sheet)
local Types = require(script.Parent.Parent.Screens.Types)

local Help = {}

Help.MAX_WIDTH = Kit.SHEET_MAX_W -- px, the sheet's width on wide screens
local TICK = 0.25 -- s between countdown refreshes
local HEIGHT = 0.9 -- share of the screen the sheet takes
local TIMER_W = 64 -- px, the countdown in the title row
local NUMBER = 28 -- px, a step number's circle
local ART_ROW = 28 -- px, one row of a picture
local NAME_W = 112 -- px, the name column of the Actions picture
local BAR_H = 12 -- px, the race bar in the How to win picture
local ICON = 24 -- px, an action's icon plate (Kit.iconPlate) in the Actions and Polls pictures
local TAB_INSET = 3 -- px between the tab track's edge and its tabs
local ISSUE_ROW = 24 -- px, one issue in the Actions picture's key (D-076)
local ISSUE_ICON = 18 -- px, an issue's symbol in the pictures

-- The plan action kind (Sim/Plan) behind each name in Words.ACTIONS, for its icon.
local ACTION_KINDS: { [string]: string } = {
	Rally = "Rally",
	Fundraise = "Fundraise",
	Ad = "Media",
	["Attack ad"] = "Attack",
	Poll = "Poll",
	["Ground game"] = "Gotv",
}

export type Help = {
	root: Frame,
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	select: (tab: string) -> (),
	destroy: () -> (),
}

-- ---------------------------------------------------------------- pictures

local function row(parent: Instance, name: string, order: number): Frame
	return Kit.box({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ART_ROW),
		Parent = parent,
	})
end

-- How to win: the race bar (Kit.raceBar, as in the match) with the 270 tick,
-- the two totals in Fredoka and the names in their readable player colors.
local SAMPLE_YOU = 280 -- votes in the picture
local SAMPLE_THEM = 258
local SAMPLE_ALL = 538 -- every vote on the map

local function winArt(art: Frame, config: ConfigModule.Config)
	local you = Kit.color(Colors.player.Cobalt)
	local them = Kit.color(Colors.player.Crimson)
	local labels = row(art, "Labels", 1)
	local function side(name: string, text: string, color: Color3, right: boolean)
		Kit.text(text, {
			Name = name,
			Position = UDim2.fromScale(if right then 0.6 else 0, 0),
			Size = UDim2.fromScale(0.4, 1),
			Font = Kit.font.display,
			TextColor3 = Kit.textColor(color),
			TextXAlignment = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
			Parent = labels,
		})
	end
	side("You", `You {SAMPLE_YOU}`, you, false)
	Kit.text(`{config.EV_TO_WIN} to win`, {
		Name = "Goal",
		Position = UDim2.fromScale(0.3, 0),
		Size = UDim2.fromScale(0.4, 1),
		TextSize = Kit.size.caption,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = labels,
	})
	side("Them", `{SAMPLE_THEM} Rival`, them, true)
	local bar = Kit.raceBar(art, { h = BAR_H, mark = config.EV_TO_WIN / SAMPLE_ALL, name = "Bar", order = 2 })
	bar.left.Name = "FillYou"
	bar.right.Name = "FillThem"
	bar:setColors(you, them)
	bar:set(SAMPLE_YOU / SAMPLE_ALL, SAMPLE_THEM / SAMPLE_ALL)
end

-- Your turn: the three steps, numbered.
local function turnArt(art: Frame, config: ConfigModule.Config)
	local steps = {
		"Tap a state on the map",
		`Pick an action (you have {config.AP_PER_WEEK})`,
		"Press Lock in",
	}
	for k, text in steps do
		local line = row(art, `Step{k}`, k)
		local circle = Kit.text(tostring(k), {
			Name = "Number",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(NUMBER, NUMBER),
			BackgroundTransparency = 0,
			BackgroundColor3 = Kit.colors.raised,
			Font = Kit.font.display,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = line,
		})
		Kit.round().Parent = circle
		Kit.bevel(circle)
		Kit.text(text, {
			Name = "Text",
			Position = UDim2.fromOffset(NUMBER + Kit.space.sm, 0),
			Size = UDim2.new(1, -(NUMBER + Kit.space.sm), 1, 0),
			TextScaled = true,
			Parent = line,
		})
	end
end

-- A pill in a fixed-width name column and a short line beside it, with the
-- action's icon (UI/Icons) in front when there is one.
local function namedRow(
	art: Frame,
	name: string,
	order: number,
	pill: string,
	tone: Kit.Tone,
	text: string,
	icon: string?
)
	local line = row(art, name, order)
	local left = 0
	if icon then
		local plate = Kit.iconPlate(icon, ICON, Kit.tone(tone))
		plate.AnchorPoint = Vector2.new(0, 0.5)
		plate.Position = UDim2.fromScale(0, 0.5)
		plate.Parent = line
		left = ICON + Kit.space.sm
	end
	local box = Kit.box({
		Name = "NameBox",
		Position = UDim2.fromOffset(left, 0),
		Size = UDim2.new(0, NAME_W, 1, 0),
		Parent = line,
	})
	Kit.pill(pill, tone, {
		Name = "Name",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Parent = box,
	})
	Kit.text(text, {
		Name = "Text",
		Position = UDim2.fromOffset(left + NAME_W + Kit.space.sm, 0),
		Size = UDim2.new(1, -(left + NAME_W + Kit.space.sm), 1, 0),
		TextSize = Kit.size.caption,
		TextScaled = true,
		Parent = line,
	})
end

-- The eight issues (D-076): each one's symbol and name in two columns, so the
-- symbols on the map and the chips have a key here too. `order`: its place
-- in `art` (default after everything).
local function issuesArt(art: Frame, order: number?)
	local grid = Kit.box({
		Name = "IssuesKey",
		LayoutOrder = order or 100,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = art,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -Kit.space.xs, 0, ISSUE_ROW),
		CellPadding = UDim2.fromOffset(Kit.space.sm, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for k, issue in Issues.list do
		Kit.issueTag(issue, { LayoutOrder = k, iconSize = ISSUE_ICON, Parent = grid })
	end
end

local function actionsArt(art: Frame)
	for k, action in Words.ACTIONS do
		local kind = ACTION_KINDS[action.name]
		local icon = if kind then Kit.actionIcon(kind) else nil
		namedRow(art, `Action{k}`, k, action.name, "text", action.text, icon or "vote")
	end
end

-- Events & debates: a debate scoreboard, the way the debate shows it.
local function eventsArt(art: Frame)
	local rows: { { topic: string, score: string, verdict: string, tone: Kit.Tone } } = {
		{ topic = "Jobs", score = "5 – 3", verdict = "You win", tone = "good" },
		{ topic = "Health", score = "2 – 4", verdict = "Rival wins", tone = "bad" },
	}
	for k, entry in rows do
		local line = row(art, `Topic{k}`, k)
		local topic = Kit.text(Kit.issueName(entry.topic), {
			Name = "Topic",
			Size = UDim2.fromScale(0.4, 1),
			Font = Kit.font.bold,
			Parent = line,
		})
		Kit.issueLead(topic, entry.topic, ISSUE_ICON) -- its symbol, as in the debate (D-076)
		Kit.text(entry.score, {
			Name = "Score",
			Position = UDim2.fromScale(0.4, 0),
			Size = UDim2.fromScale(0.25, 1),
			Font = Kit.font.bold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = line,
		})
		local box = Kit.box({
			Name = "VerdictBox",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.35, 1),
			Parent = line,
		})
		Kit.pill(entry.verdict, entry.tone, {
			filled = true,
			Name = "Verdict",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Parent = box,
		})
	end
end

local function pollsArt(art: Frame)
	namedRow(art, "Public", 1, "Public poll", "text", "Everyone sees it; can be off", "search")
	namedRow(art, "Private", 2, "Your poll", "good", "Only you: the real numbers", "search")
	namedRow(art, "Ground", 3, "Ground game", "muted", "Hidden until election night", "footprints")
end

-- The pictures, for other sheets that explain the same thing (UI/HowTo).
Help.art = table.freeze({
	win = winArt,
	turn = turnArt,
	actions = actionsArt,
	issues = issuesArt,
	events = eventsArt,
	polls = pollsArt,
})

-- ---------------------------------------------------------------- mount

Help.ADMIN_TIMERS = "Timers off (admin)" -- the admin chip's label (D-081)

-- The line under the admin chip (D-081): what "Timers off" does in this match,
-- or why it does nothing here.
function Help.adminNote(on: boolean, allowed: boolean, payload: any): string
	if not allowed then
		if payload and payload.daily then
			return "Not in the Daily Race: every run has the same clock."
		end
		return "Only in games where every player is an admin."
	end
	local humans = 0
	for _, seat in (if payload then payload.seats else nil) or {} do
		if seat.kind == "Human" then
			humans += 1
		end
	end
	if on then
		local rated = if humans >= 2 then " This match is unrated." else ""
		return `On: no choice timers in this match, for every player.{rated}`
	end
	local rated = if humans >= 2 then " That makes this match unrated." else ""
	return `Off: tap to drop the choice timers for every player.{rated}`
end

function Help.mount(parent: Instance, ctx: Types.Ctx): Help
	local root = Kit.new("Frame", {
		Name = "HelpOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true, -- swallows taps meant for the screen underneath
		ZIndex = 40,
		Visible = false,
	}) :: Frame
	root:SetAttribute("PrimaryOptional", true)

	local isOpen = false
	local connection: RBXScriptConnection? = nil
	local elapsed = 0
	local current = "win"

	local function close()
		if not isOpen then
			return
		end
		isOpen = false
		root.Visible = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	local sheet = Sheet.new(root, {
		title = "How to play",
		name = "HelpSheet",
		height = HEIGHT,
		onClose = close,
	})
	sheet.closeButton.Name = "HelpClose"
	sheet.title.Size = UDim2.new(1, -(Kit.MIN_TOUCH + TIMER_W + 2 * Kit.space.sm), 1, 0)
	local timer = Kit.text("", {
		Name = "HelpTimer",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(Kit.MIN_TOUCH + Kit.space.sm), 0, 0),
		Size = UDim2.new(0, TIMER_W, 1, 0),
		Font = Kit.font.bold,
		TextSize = Kit.size.heading,
		TextScaled = true,
		TextColor3 = Kit.colors.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		Parent = sheet.title.Parent,
	})

	local tabs = Words.help(ctx.config)
	-- The tabs as one segmented control (like the Lobby's bot level): a field
	-- track, the open tab raised with the white outline, the others flat with
	-- muted labels. (Per-corner "folder" tabs need UICorner's per-corner radii,
	-- still a Studio beta feature, so not here.)
	local tabBar = Kit.new("Frame", {
		Name = "HelpTabs",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Kit.colors.field,
		BorderSizePixel = 0,
		Parent = sheet.body,
	}) :: Frame
	Kit.corner(Kit.radius.button).Parent = tabBar
	Kit.bevel(tabBar)
	Kit.pad(TAB_INSET).Parent = tabBar
	local grid = Kit.new("UIGridLayout", {
		CellPadding = UDim2.fromOffset(TAB_INSET, TAB_INSET),
		CellSize = UDim2.new(1 / #tabs, -TAB_INSET, 0, Kit.MIN_TOUCH),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = tabBar,
	}) :: UIGridLayout

	local chips: { [string]: TextButton } = {}
	local pages: { [string]: Frame } = {}
	local showTab: (tab: string) -> ()

	-- Admins only (D-081): "Timers off" for this match, above the tabs.
	local adminBox = Kit.stack({
		Name = "HelpAdmin",
		LayoutOrder = 0,
		Visible = false,
		Parent = sheet.body,
	}, "Vertical", Kit.space.xs)
	-- Room for the chip's outline (drawn outside it) under the body's clip edge.
	Kit.new("UIPadding", { PaddingTop = UDim.new(0, TAB_INSET), Parent = adminBox })
	local adminOn = false
	local adminSeen: any = nil -- the payload the row last painted from
	local paintAdmin: (on: boolean) -> ()
	local adminChip = Kit.chip(Help.ADMIN_TIMERS, function()
		local on = not adminOn
		paintAdmin(on)
		ctx.net.send("SetTimersOff", { on = on })
	end, {
		Name = "HelpAdminTimers",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = adminBox,
	})
	local adminNote = Kit.caption("", { Name = "HelpAdminNote", LayoutOrder = 2, Parent = adminBox })
	paintAdmin = function(on: boolean)
		adminOn = on
		adminChip:SetAttribute("On", on)
		Kit.setSelected(adminChip, on)
		local payload = ctx.store.get().payload
		local admin = if payload then payload.adminTimers else nil
		adminNote.Text = Help.adminNote(on, admin ~= nil and admin.allowed == true, payload)
	end
	-- Follows the payload (only when a new one arrived, so a tap's repaint stays).
	local function refreshAdmin()
		local payload = ctx.store.get().payload
		local admin = if payload and payload.stage ~= "Over" then payload.adminTimers else nil
		adminBox.Visible = admin ~= nil
		if admin ~= nil and payload ~= adminSeen then
			adminSeen = payload
			paintAdmin(admin.on == true)
		end
	end

	for k, tab in tabs do
		chips[tab.id] = Kit.chip(tab.label, function()
			showTab(tab.id)
		end, { Name = `HelpTab_{tab.id}`, LayoutOrder = k, Parent = tabBar })

		local page = Kit.stack({
			Name = `HelpPage_{tab.id}`,
			LayoutOrder = 2,
			Visible = false,
			Parent = sheet.body,
		}, "Vertical", Kit.space.md)
		pages[tab.id] = page
		if tab.id == "win" then
			-- The session settings, first thing in the default tab.
			local settings = Kit.stack({
				Name = "HelpSettings",
				LayoutOrder = 0,
				Parent = page,
			}, "Vertical", Kit.space.xs)
			Kit.caption("Settings", { Name = "HelpSettingsLabel", LayoutOrder = 1, Parent = settings })
			Settings.row({ LayoutOrder = 2, Parent = settings })
		end
		Kit.text(tab.title, {
			Name = `HelpPageTitle_{tab.id}`,
			LayoutOrder = 1,
			Font = Kit.font.bold,
			Parent = page,
		})
		local art = Kit.card({
			Name = `HelpArt_{tab.id}`,
			LayoutOrder = 2,
			BackgroundColor3 = Kit.colors.field,
		})
		art.Parent = page
		if tab.id == "win" then
			winArt(art, ctx.config)
		elseif tab.id == "turn" then
			turnArt(art, ctx.config)
		elseif tab.id == "actions" then
			actionsArt(art)
			-- Under the actions, the issues that rallies and ads are about.
			Kit.caption(Words.ISSUES_KEY, {
				Name = "IssuesCaption",
				LayoutOrder = #Words.ACTIONS + 1,
				Parent = art,
			})
			issuesArt(art, #Words.ACTIONS + 2)
		elseif tab.id == "events" then
			eventsArt(art)
		else
			pollsArt(art)
		end
		Kit.text(tab.text, {
			Name = `HelpIntro_{tab.id}`,
			LayoutOrder = 3,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = page,
		})
		local more = Kit.stack(
			{ Name = `HelpMore_{tab.id}`, LayoutOrder = 5, Visible = false, Parent = page },
			"Vertical",
			Kit.space.md
		)
		local moreButton: TextButton
		moreButton = Kit.button("All the numbers +", function()
			more.Visible = not more.Visible
			moreButton.Text = if more.Visible
				then `All the numbers {Kit.glyph.minus}`
				else "All the numbers +"
		end, {
			variant = "ghost",
			Name = `HelpMoreButton_{tab.id}`,
			LayoutOrder = 4,
			Size = UDim2.fromOffset(200, Kit.MIN_TOUCH),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = page,
		})
	end

	-- Leaving the match (D-059): the last thing in the sheet, in a live match
	-- only, under a rule: a destructive secondary (orange outline, never a primary).
	local leaveRule = Kit.divider({
		Name = "HelpLeaveRule",
		LayoutOrder = 9,
		BackgroundTransparency = 0.5,
		Visible = false,
		Parent = sheet.body,
	})
	-- Reporting the opponent's custom name (D-069), when one is showing.
	local reportSeat: number? = nil
	local report = Kit.button(
		"",
		function()
			local openReport = ctx.report
			local seat = reportSeat
			sheet:close()
			if openReport and seat then
				openReport(seat)
			end
		end,
		{ variant = "secondary", Name = "HelpReport", LayoutOrder = 10, Visible = false, Parent = sheet.body }
	)
	local leave = Kit.button(LobbyWords.LEAVE, function()
		local openLeave = ctx.leave
		sheet:close()
		if openLeave then
			openLeave()
		end
	end, { variant = "danger", Name = "HelpLeave", LayoutOrder = 11, Visible = false, Parent = sheet.body })
	-- Reporting a bug (D-090): small and last, out of the way.
	local bug = Kit.button(LobbyWords.BUG_LABEL, function()
		local openBug = ctx.bug
		sheet:close()
		if openBug then
			openBug(nil)
		end
	end, {
		variant = "ghost",
		Name = "HelpBug",
		LayoutOrder = 12,
		Size = UDim2.fromOffset(160, Kit.MIN_TOUCH),
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = sheet.body,
	})

	-- The numbers behind each tab, from Explain (refilled at every open).
	local function fillNumbers()
		-- Each tab's intro follows the match's config too: the tutorial's
		-- election comes after its week 4, not week 12 (D-080).
		for _, tab in Words.help(ctx.config) do
			local intro = pages[tab.id] and pages[tab.id]:FindFirstChild(`HelpIntro_{tab.id}`)
			if intro and intro:IsA("TextLabel") then
				intro.Text = tab.text
			end
		end
		local payload = ctx.store.get().payload
		local view = if payload then payload.view else nil
		local byId: { [string]: Explain.Section } = {}
		for _, section in Explain.help(ctx.config, view) do
			byId[section.id] = section
		end
		for _, tab in tabs do
			local more = pages[tab.id]:FindFirstChild(`HelpMore_{tab.id}`) :: Frame
			for _, child in more:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			for k, id in tab.sections do
				local section = byId[id]
				if section == nil then
					continue
				end
				local box = Kit.stack(
					{ Name = `HelpSection_{id}`, LayoutOrder = k, Parent = more },
					"Vertical",
					Kit.space.xs
				)
				Kit.text(section.title, {
					Name = `HelpTitle_{id}`,
					LayoutOrder = 1,
					Font = Kit.font.bold,
					Parent = box,
				})
				Kit.caption(Words.plain(table.concat(section.lines, "\n")), {
					Name = `HelpText_{id}`,
					LayoutOrder = 2,
					TextColor3 = Kit.colors.text,
					Parent = box,
				})
			end
		end
	end

	showTab = function(tab: string)
		if not pages[tab] then
			return
		end
		current = tab
		for id, page in pages do
			page.Visible = id == tab
			local chip = chips[id]
			Kit.setSelected(chip, id == tab)
			chip.BackgroundTransparency = if id == tab then 0 else 1
			chip.TextColor3 = if id == tab then Kit.colors.text else Kit.colors.muted
		end
	end

	-- The tab for the moment the player asked from.
	local function tabForNow(): string
		local payload = ctx.store.get().payload
		if payload == nil then
			return "win"
		end
		local view = payload.view
		if payload.reveal == "Debate" or view.phase == "Decision" then
			return "events"
		elseif view.phase == "Plan" then
			return "turn"
		end
		return "win"
	end

	local function countdown()
		refreshAdmin()
		local payload = ctx.store.get().payload
		if payload == nil or payload.deadline == nil then
			timer.Visible = false
			return
		end
		local left = payload.deadline - ctx.now()
		timer.Text = Kit.clock(left)
		local warn = if payload.stage == "Input" then Kit.TIMER_WARN else 0
		timer.TextColor3 = if math.ceil(left) < warn then Kit.colors.danger else Kit.colors.accent
		timer.Visible = true
	end

	local function auditing(): boolean
		return RunService:IsStudio()
			or workspace:GetAttribute("DebugScreen") ~= nil
			or workspace:GetAttribute("DebugText") == true
	end

	local function open()
		fillNumbers()
		local live = ctx.store.get().payload
		leave.Visible = ctx.leave ~= nil and live ~= nil and live.stage ~= "Over"
		reportSeat = nil
		if ctx.report and live then
			for seat, player in live.view.players do
				if seat ~= live.you and player.customName then
					reportSeat = seat
					report.Text = SetupWords.reportButton(player.customName)
				end
			end
		end
		report.Visible = reportSeat ~= nil
		bug.Visible = ctx.bug ~= nil
		leaveRule.Visible = leave.Visible or report.Visible or bug.Visible
		-- Five tabs in a row on a wide screen, three per row on a phone.
		local size = root.AbsoluteSize
		local columns = if size.Y > size.X then 3 else #tabs
		grid.CellSize = UDim2.new(1 / columns, -TAB_INSET, 0, Kit.MIN_TOUCH)
		showTab(tabForNow())
		isOpen = true
		root.Visible = true
		sheet:open()
		countdown()
		if connection == nil then
			elapsed = 0
			connection = RunService.RenderStepped:Connect(function(dt: number)
				elapsed += dt
				if elapsed >= TICK then
					elapsed = 0
					countdown()
				end
			end)
		end
		if auditing() then
			task.delay(0.5, function()
				if isOpen then
					Audit.run(root, "Help")
				end
			end)
		end
	end

	showTab(current)
	root.Parent = parent
	return {
		root = root,
		open = open,
		close = function()
			sheet:close()
			close()
		end,
		isOpen = function(): boolean
			return isOpen
		end,
		select = function(tab: string)
			showTab(tab)
		end,
		destroy = function()
			close()
			root:Destroy()
		end,
	}
end

return Help
