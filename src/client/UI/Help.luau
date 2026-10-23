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
--   HelpSettingsLabel and the row Settings with SoundChip and MotionChip).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)
local Explain = require(ReplicatedStorage.Shared.UI.Explain)
local Words = require(ReplicatedStorage.Shared.UI.Words.Reveal)

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
local ICON = 20 -- px, an action's icon in the Actions and Polls pictures

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

-- How to win: a race bar with the 270 tick.
local function winArt(art: Frame, config: ConfigModule.Config)
	local you = Kit.color(Colors.player.Cobalt)
	local them = Kit.color(Colors.player.Crimson)
	Kit.dataColor(art)
	local labels = row(art, "Labels", 1)
	Kit.text("You 280", {
		Name = "You",
		Size = UDim2.fromScale(0.4, 1),
		Font = Kit.font.bold,
		TextColor3 = you,
		Parent = labels,
	})
	Kit.text(`{config.EV_TO_WIN} to win`, {
		Name = "Goal",
		Position = UDim2.fromScale(0.3, 0),
		Size = UDim2.fromScale(0.4, 1),
		TextSize = Kit.size.caption,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = labels,
	})
	Kit.text("258 Rival", {
		Name = "Them",
		Position = UDim2.fromScale(0.6, 0),
		Size = UDim2.fromScale(0.4, 1),
		Font = Kit.font.bold,
		TextColor3 = them,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = labels,
	})
	local track = Kit.box({
		Name = "Bar",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, BAR_H),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.colors.raised,
		ClipsDescendants = true,
		Parent = art,
	})
	Kit.corner(BAR_H // 2).Parent = track
	Kit.box({
		Name = "FillYou",
		Size = UDim2.fromScale(280 / 538, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = you,
		Parent = track,
	})
	Kit.box({
		Name = "FillThem",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(258 / 538, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = them,
		Parent = track,
	})
	Kit.box({
		Name = "Tick",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(config.EV_TO_WIN / 538, 0),
		Size = UDim2.new(0, 2, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.colors.text,
		ZIndex = 2,
		Parent = track,
	})
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
			Font = Kit.font.bold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = line,
		})
		Kit.round().Parent = circle
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
		local glyph = Kit.icon(icon, ICON, Kit.tone(tone))
		glyph.AnchorPoint = Vector2.new(0, 0.5)
		glyph.Position = UDim2.fromScale(0, 0.5)
		glyph.Parent = line
		left = ICON + Kit.space.xs
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
		Kit.text(entry.topic, {
			Name = "Topic",
			Size = UDim2.fromScale(0.4, 1),
			Font = Kit.font.bold,
			Parent = line,
		})
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

-- ---------------------------------------------------------------- mount

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
	local tabBar = Kit.box({
		Name = "HelpTabs",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = sheet.body,
	})
	local grid = Kit.new("UIGridLayout", {
		CellPadding = UDim2.fromOffset(Kit.space.sm, Kit.space.sm),
		CellSize = UDim2.new(1 / #tabs, -Kit.space.sm, 0, Kit.MIN_TOUCH),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabBar,
	}) :: UIGridLayout

	local chips: { [string]: TextButton } = {}
	local pages: { [string]: Frame } = {}
	local showTab: (tab: string) -> ()

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

	-- The numbers behind each tab, from Explain (refilled at every open).
	local function fillNumbers()
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
			Kit.setSelected(chips[id], id == tab)
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
		-- Five tabs in a row on a wide screen, three per row on a phone.
		local size = root.AbsoluteSize
		local columns = if size.Y > size.X then 3 else #tabs
		grid.CellSize = UDim2.new(1 / columns, -Kit.space.sm, 0, Kit.MIN_TOUCH)
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
