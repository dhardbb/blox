--!strict
-- Lobby: play the bot, find a public match, or play a friend (host a private
-- match or join one by its 5-character code). While queued or hosting it shows
-- what is happening and a Cancel button. Everything is built once; update() only
-- flips Visible and text, so a half-typed code survives server messages.
--
-- Layout (docs/UI-STYLE.md §4.1): one centered column, at most 480 px wide, that
-- does not scroll: the "LANDSLIDE" wordmark with its "RACE TO 270" ribbon
-- (Kit.wordmark, D-064), the record, then Play vs
-- Bot (the one primary) with the bot level chips under it (UI/BotLevel, D-059)
-- and a line on the picked level (BotLevelNote, D-087; a phone under
-- PHONE_BOARD_H + NOTE_ROOM drops the eyebrow to make room),
-- "Find match" and "Play a friend" side by side, and a ghost "How to play"
-- (UI/HowTo, five short pages and "Play the tutorial", D-059, D-075), and once
-- the Color Pass is set up the "Color" button (UI/ColorPick, D-055: red or blue, or your pick with the pass). The
-- global leaderboard (UI/Leaderboard, D-059) sits beside the column on a wide
-- screen (top 10, or top 3 when short) and at the end of it on a phone (top 3,
-- or just "You" and See all on a short phone: the column never scrolls).
-- Sound and Reduce motion are two compact icon toggles in the top-right corner
-- (UI/Settings.corner, D-075), inside the safe area the Game ScreenGui keeps
-- (CoreUISafeInsets: clear of Roblox's own buttons and a notch), above the
-- leaderboard card's corner.
-- "Play a friend" opens a sheet with
-- "Make a code" (Host) and the code field + Join. Messages (rejections,
-- notices, a bad code) go to the global toast.
--
-- Motion (docs/UI-STYLE.md §2.7.1): on mount the wordmark pops and the column
-- fades in top to bottom (Motion.stagger); nothing waits on it.
--
-- Stable names: Practice, FindMatch, PlayFriend, HowToPlay, FriendSheet, Host,
-- CodeBox, Join, Idle, Waiting, Starting, WaitingText, CodeWell, CodeLabel,
-- WaitingHint, Cancel, Record, ServerFull, Title (Mark, Ribbon, Tagline), Eyebrow, CornerSettings
-- (SoundToggle, MotionToggle, SettingsTip; TimersToggle for admins, D-081), ColorButton, ColorSheet, ReviewButton, ReviewSheet (admins, D-069), LevelPick (BotLevel (Level_<level>), BotLevelNote), HowToSheet,
-- LeaderboardCard, LeaderboardSheet, DailyCard, DailySheet.
--
-- The Daily Race (UI/DailyRace, D-082) is one card in the column under How to
-- play: today's candidate, the countdown, the streak, Play and Today's board.
--
-- Matchmaking (D-083, UI/LobbyMatch): the Online count beside the record (one
-- "Stats" row), a bot game while waiting in the queue (WaitBot), "Invite a
-- friend" in the friend sheet and on the code screen (Invite, InviteHost), and
-- the match on its way (state "Found": the Starting section with FoundHint,
-- FoundCancel).
--
-- A phone (0.15.0; any screen too narrow for the card beside the column): the
-- column starts below the corner toggles (CORNER_CLEAR), so the eyebrow and the
-- wordmark never sit under them; the Daily Race card is one row
-- (DailyRace.setCompact: "Play", "Top 50"); How to play shares a row with the
-- Color button when the Color Pass is set up ("Extras"); and the leaderboard
-- shows the top 3 when the screen is at least PHONE_BOARD_H tall (a 390x844
-- phone), more for an admin's Review names button, else "You" and See all.
-- iPad and desktop keep the column, the full Daily card and the card beside.
--
-- 0.17 (D-090): a faint red and blue map with stars behind the wordmark
-- (UI/BrandMap), Play vs Bot with a play badge and a light that sweeps it,
-- How to play as a "?" chip in the corner (HowToPlay; it pulses, attribute
-- Pulse, for a player with no games until they open it) beside the bug toggle
-- (BugToggle: "Report a bug", UI/BugSheet), and for admins "Bug reports"
-- (BugsButton, UI/BugList) beside Review names. Color, Review names and Bug
-- reports share the Extras row on a phone. On a wide screen the column stands
-- at a fixed top (centered for the idle column, idleHeight), so the wordmark
-- stays still when the queue or the code screen opens. The queue shows a
-- pulsing ring with the time waited (QueueRing, QueueTime) and "Play a bot
-- while you wait" as its primary; the private code is a read-only TextBox a
-- tap selects (CodeHint "Tap to copy": Roblox games cannot write the
-- clipboard), and the waiting line's dots move unless motion is reduced.
--
-- A landscape phone (D-089, Kit.compact: height is short): two panes. The
-- column of buttons on the left (no eyebrow, the one-row Daily card), and on
-- the right, under the corner toggles, the "Brand" pane: the wordmark, the
-- record and the leaderboard card ("You" and See all, the top 3 when tall
-- enough).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyWords = require(ReplicatedStorage.Shared.UI.Words.Lobby)
local Words = require(ReplicatedStorage.Shared.UI.Words.Setup)

local BotLevel = require(script.Parent.Parent.UI.BotLevel)
local BrandMap = require(script.Parent.Parent.UI.BrandMap)
local BugList = require(script.Parent.Parent.UI.BugList)
local DailyRace = require(script.Parent.Parent.UI.DailyRace)
local ColorPick = require(script.Parent.Parent.UI.ColorPick)
local HowTo = require(script.Parent.Parent.UI.HowTo)
local LandslideBadge = require(script.Parent.Parent.UI.LandslideBadge)
local LobbyMatch = require(script.Parent.Parent.UI.LobbyMatch)
local MatchWords = require(ReplicatedStorage.Shared.UI.Words.Matchmaking)
local Online = require(ReplicatedStorage.Shared.Net.Online)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local NameReview = require(script.Parent.Parent.UI.NameReview)
local Kit = require(script.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Common.Layout)
local Leaderboard = require(script.Parent.Parent.UI.Leaderboard)
local Motion = require(script.Parent.Parent.UI.Motion)
local Settings = require(script.Parent.Parent.UI.Settings)
local Sheet = require(script.Parent.Parent.UI.Sheet)
local Types = require(script.Parent.Types)

local Screen = {}

local MAX_WIDTH = 480 -- px
local CODE_LENGTH = 5
local SHORT_SCREEN = 420 -- px; below this the eyebrow is dropped to make room
local BOARD_W = 300 -- px, the leaderboard card beside the column
local BOARD_GAP = Kit.space.lg -- px between the column and the card
local SIDE_MIN_W = MAX_WIDTH + BOARD_W + BOARD_GAP + 2 * Kit.space.xl -- px of width for the card beside the column
local TALL_BOARD_H = 560 -- px of height for the top 10 beside the column (else the top 3)
local PHONE_BOARD_H = 830 -- px of screen height for the top 3 in a phone's column (else only "You" and See all)
local CORNER_CLEAR = Kit.MIN_TOUCH + Kit.space.sm -- px a phone's column starts below the corner toggles
local REVIEW_ROOM = Kit.MIN_TOUCH + Kit.space.sm -- px an admin's Review names button takes from the board
local NOTE_ROOM = BotLevel.NOTE_HEIGHT + Kit.space.xs -- px the bot level's line takes (a phone shorter than PHONE_BOARD_H + this drops the eyebrow)
local STAGE_GLOW = 1.1 -- the stage glow's size, a share of the screen (an ellipse)
local STAGE_FADE = 0.75 -- its transparency: a lit table, not a spotlight
local COLUMN_SHARE = 0.56 -- share of a landscape phone's width the button column takes (D-089)
local COMPACT_BOARD_H = 440 -- px of screen height for the top 3 in a landscape phone's brand pane (else the dense card)
local DENSE_BOARD_H = 330 -- px of screen height for the dense card's top 3 there (else "You" and See all; fix17)
local CODE_PLATE_H = Kit.size.hero + 2 * Kit.space.lg -- px, the private match code's plate
local CODE_GLOW_FADE = 0.9 -- a faint white light inside the code plate
local MAP_W = 1.5 -- the backdrop map's box, a share of the wordmark's width (D-090)
local MAP_H = 3.2 -- and of its height (the map keeps its aspect inside this box)
local COMPACT_MAP_W = 1.05 -- a landscape phone's brand pane is narrow: the map about the wordmark's width
local COMPACT_MAP_H = 2.2
local PLAY_BADGE = 32 -- px, the play badge on Play vs Bot
local RING = 88 -- px, the queue's ring
local RING_EVERY = 1.4 -- s between two pulses of the queue's ring
local RING_BREATHE = { 0.15, 0.7, 1.2 } -- the ring's edge: transparency from, to, seconds
local DOT_EVERY = 0.4 -- s per step of the waiting line's dots
local PULSE = { 0, 0.75, 0.9 } -- the "?" chip's outline for a new player: transparency from, to, seconds
local EYEBROW_H = Kit.size.caption + 4 -- px, the eyebrow's line (idleHeight)
local CORNER_ICON = 18 -- px, the bug toggle's icon (its glyph stays at body size until the image is uploaded)

-- Codes use letters A-Z and digits 2-9 (no 0 or 1).
local function validCode(code: string): boolean
	return #code == CODE_LENGTH and string.match(code, "^[A-Z2-9]+$") ~= nil
end

function Screen.mount(parent: Frame, ctx: Types.Ctx): Types.Screen
	local content = Layout.lane(parent, MAX_WIDTH, { Name = "Content" })
	local list = Kit.list("Vertical", Kit.space.sm)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = content
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 0),
		Parent = content,
	})

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- The stage: the map's navy glow behind everything, so the first screen is
	-- not a void (docs/UI-STYLE.md §2, Kit.glow; decorative).
	Kit.glow(parent, Kit.colors.glow, { scale = STAGE_GLOW, transparency = STAGE_FADE, stretch = true })

	local eyebrow = Kit.eyebrow(Words.EYEBROW, {
		Name = "Eyebrow",
		LayoutOrder = nextOrder(),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = content,
	})
	-- The lockup (Kit.wordmark, D-064): "LANDSLIDE" in Fredoka at up to 72 with
	-- its glow and lip, the "RACE TO 270" ribbon under it.
	local title = Kit.wordmark(nil, { Name = "Title", LayoutOrder = nextOrder(), Parent = content })
	-- The backdrop (D-090): a faint red and blue map with stars, behind the
	-- wordmark wherever it stands (it moves with it to the brand pane).
	local brandMap = BrandMap.new({ Size = UDim2.fromScale(MAP_W, MAP_H), Parent = title })
	-- The record and the online count on one line (D-083). Always there (the
	-- record empty until the profile arrives), so nothing jumps.
	local stats = Kit.box({
		Name = "Stats",
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, Kit.size.caption + Kit.space.xs),
		Parent = content,
	})
	local statsList = Kit.list("Horizontal", Kit.space.md)
	statsList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	statsList.VerticalAlignment = Enum.VerticalAlignment.Center
	statsList.Parent = stats
	local record = Kit.caption("", {
		Name = "Record",
		LayoutOrder = 1,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = stats,
	})
	local onlineOrder = nextOrder() -- the Online line's slot (UI/LobbyMatch); it moves into Stats
	local fullBanner = Kit.text("Server full. Try again in a minute.", {
		Name = "ServerFull",
		LayoutOrder = nextOrder(),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Kit.colors.warn,
		Font = Kit.font.medium,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = content,
	})
	-- Breathing room between the hero block and the buttons (not on a phone).
	local spacer = Kit.box({
		Name = "Spacer",
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, Kit.space.sm),
		Parent = content,
	})

	local function section(name: string): Frame
		local box = Kit.stack({
			Name = name,
			LayoutOrder = nextOrder(),
			Visible = false,
			Parent = content,
		}, "Vertical", Kit.space.sm)
		return box
	end

	local idle = section("Idle")
	local waiting = section("Waiting")
	local starting = section("Starting")

	-- ------------------------------------------------------------ the friend sheet

	-- Mounted last (below) so it draws over the column; built first so the
	-- buttons can open it.
	local friend = Sheet.new(parent, { title = "Play a friend", name = "FriendSheet", height = 0.56 })

	-- A local problem (a malformed code) shows in the global toast like a rejection.
	local function complain(text: string)
		ctx.store.say(text, true)
	end

	-- ------------------------------------------------------------ idle

	-- Never disabled by "server full": that status can be stale, and the server
	-- answers ServerFull with a toast if there is still no room.
	local practice = Kit.button("Play vs Bot", function()
		ctx.net.send("Practice", { difficulty = BotLevel.get() })
	end, { variant = "primary", Name = "Practice", LayoutOrder = 1, Parent = idle })
	practice:SetAttribute("PrimaryAction", true)
	-- More life (D-090): a blue play badge at the left, and a light that sweeps it.
	local badge = Kit.text("►", {
		Name = "PlayIcon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Kit.space.xs, 0.5, 0),
		Size = UDim2.fromOffset(PLAY_BADGE, PLAY_BADGE),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.color(Colors.player.Cobalt),
		TextColor3 = Kit.colors.text,
		Font = Kit.font.bold,
		TextSize = Kit.size.body,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Parent = practice,
	})
	Kit.round().Parent = badge
	Kit.dataColor(badge)
	practice.Active = true
	local stopShine = Motion.shine(practice)
	-- The level chips and, under them, one line on the picked level (D-087).
	local levelBox =
		Kit.stack({ Name = "LevelPick", LayoutOrder = 2, Parent = idle }, "Vertical", Kit.space.xs)
	local botLevel = BotLevel.new({ LayoutOrder = 1, Parent = levelBox })
	local levelNote = BotLevel.note({ LayoutOrder = 2, Parent = levelBox })

	local pair = Kit.box({
		Name = "Pair",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = idle,
	})
	Kit.list("Horizontal", Kit.space.sm).Parent = pair
	local findMatch = Kit.button("Find match", function()
		ctx.net.send("Queue")
	end, {
		variant = "secondary",
		Name = "FindMatch",
		LayoutOrder = 1,
		Size = UDim2.new(0.5, -Kit.space.sm / 2, 1, 0),
		Parent = pair,
	})
	local playFriend = Kit.button("Play a friend", function()
		friend:open()
	end, {
		variant = "secondary",
		Name = "PlayFriend",
		LayoutOrder = 2,
		Size = UDim2.new(0.5, -Kit.space.sm / 2, 1, 0),
		Parent = pair,
	})
	local howTo = HowTo.new(parent, ctx)
	-- How to play is a "?" chip in the corner (D-090); it pulses for a new player.
	local seenHowTo = false
	local paintPulse: () -> ()
	local howToPlay = Settings.cornerButton("HowToPlay", LobbyWords.HELP_LABEL, function()
		seenHowTo = true
		paintPulse()
		howTo.open()
	end, LobbyWords.HELP_CHIP)
	-- Report a bug (D-090): small, in the corner, out of the way.
	local bugToggle = Settings.cornerButton("BugToggle", LobbyWords.BUG_LABEL, function()
		local open = ctx.bug
		if open then
			open("Lobby")
		end
	end)
	local bugIcon = Kit.icon("bug", CORNER_ICON, Kit.colors.muted)
	bugIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	bugIcon.Position = UDim2.fromScale(0.5, 0.5)
	bugIcon.Parent = bugToggle
	bugToggle.Visible = ctx.bug ~= nil
	local colorPick = ColorPick.new(parent, ctx, { LayoutOrder = 6, Parent = idle })
	-- A phone: the Color, Review names and Bug reports buttons side by side (relayout).
	local extras = Kit.box({
		Name = "Extras",
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Visible = false,
		Parent = idle,
	})
	Kit.list("Horizontal", Kit.space.sm).Parent = extras
	-- Admins only (D-069): the reported names to review.
	local review = NameReview.new(parent, ctx, { LayoutOrder = 7, Parent = idle })
	-- Admins only (D-090): the newest bug reports.
	local bugs = BugList.new(parent, ctx, { LayoutOrder = 8, Parent = idle })
	-- Sound and Reduce motion: the top-right corner (D-075), on every Lobby state;
	-- for admins also "Timers off" (D-081), saved by the server.
	local settings = Settings.corner({
		Parent = parent,
		onTimers = function(off: boolean)
			ctx.net.send("SetTimersOff", { on = off })
		end,
		extras = { howToPlay, bugToggle },
	})
	-- The "?" chip's pulse: an outline that breathes until a new player opens it.
	local stopPulse: (() -> ())? = nil
	local newPlayer = false
	paintPulse = function()
		local on = newPlayer and not seenHowTo
		if howToPlay:GetAttribute("Pulse") == on then
			return
		end
		howToPlay:SetAttribute("Pulse", on)
		Kit.setSelected(howToPlay, on)
		local stop = stopPulse
		if stop then
			stop()
			stopPulse = nil
		end
		local stroke = howToPlay:FindFirstChild("VariantStroke")
		if on and stroke then
			stopPulse = Motion.breathe(stroke, "Transparency", PULSE[1], PULSE[2], PULSE[3])
		end
	end
	howToPlay:SetAttribute("Pulse", true) -- so the first paint below sets it either way
	paintPulse()
	local board = Leaderboard.new(parent, ctx)
	-- A landscape phone's right pane (D-089): wordmark, record, leaderboard.
	local brand = Kit.box({ Name = "Brand", Visible = false, Parent = parent })
	local brandList = Kit.list("Vertical", Kit.space.sm)
	brandList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	brandList.VerticalAlignment = Enum.VerticalAlignment.Center
	brandList.Parent = brand
	local brandPad =
		Kit.new("UIPadding", { PaddingTop = UDim.new(0, CORNER_CLEAR), Parent = brand }) :: UIPadding
	-- The Daily Race (D-082): one card in the column.
	local daily = DailyRace.new(parent, ctx, { LayoutOrder = 5, Parent = idle })

	-- The sheet: make a code, or enter one.
	local body = friend.body
	Kit.text(Words.FRIEND_MAKE, {
		Name = "MakeHint",
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = body,
	})
	Kit.button("Make a code", function()
		friend:close()
		ctx.net.send("Host")
	end, { variant = "secondary", Name = "Host", LayoutOrder = 2, Parent = body })
	Kit.divider({ LayoutOrder = 3, Parent = body })
	Kit.text(Words.FRIEND_ENTER, {
		Name = "JoinHint",
		LayoutOrder = 4,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = body,
	})
	local joinRow = Kit.box({
		Name = "JoinRow",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = body,
	})
	Kit.list("Horizontal", Kit.space.sm).Parent = joinRow
	local codeBox = Kit.new("TextBox", {
		Name = "CodeBox",
		LayoutOrder = 1,
		Size = UDim2.new(0.6, -Kit.space.sm / 2, 1, 0),
		BackgroundColor3 = Kit.colors.field,
		BorderSizePixel = 0,
		Font = Kit.font.mono,
		TextSize = Kit.size.body,
		TextColor3 = Kit.colors.text,
		PlaceholderText = Words.CODE_PLACEHOLDER,
		PlaceholderColor3 = Kit.colors.muted,
		ClearTextOnFocus = false,
		Text = "",
		Parent = joinRow,
	}) :: TextBox
	Kit.corner(Kit.radius.control).Parent = codeBox
	Kit.stroke(Kit.colors.line, 1).Parent = codeBox

	local function normalizeCode(): string
		local stripped = string.gsub(codeBox.Text, "%s", "")
		local code = string.upper(stripped)
		codeBox.Text = code
		return code
	end
	codeBox.FocusLost:Connect(function()
		normalizeCode()
	end)
	Kit.button("Join", function()
		local code = normalizeCode()
		if not validCode(code) then
			complain("Enter the 5-character code: letters A-Z and numbers 2-9.")
			return
		end
		ctx.net.send("Join", { code = code })
	end, {
		variant = "secondary",
		Name = "Join",
		LayoutOrder = 2,
		Size = UDim2.new(0.4, -Kit.space.sm / 2, 1, 0),
		Parent = joinRow,
	})

	-- ------------------------------------------------------------ queued or hosting

	-- The queue (D-090): a ring that pulses, with the time waited inside it.
	local ringRow = Kit.box({
		Name = "QueueRingRow",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, RING),
		Visible = false,
		Parent = waiting,
	})
	local ring = Kit.new("Frame", {
		Name = "QueueRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(RING, RING),
		BackgroundColor3 = Kit.colors.field,
		BorderSizePixel = 0,
		Parent = ringRow,
	}) :: Frame
	Kit.round().Parent = ring
	local ringEdge = Kit.new("UIStroke", {
		Name = "RingEdge",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Kit.colors.accent,
		Thickness = 3,
		Transparency = RING_BREATHE[1],
		Parent = ring,
	}) :: UIStroke
	local queueTime = Kit.text("", {
		Name = "QueueTime",
		Size = UDim2.fromScale(1, 1),
		Font = Kit.font.display,
		TextSize = Kit.size.heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Parent = ring,
	})
	local waitingTitle = Kit.heading("", {
		Name = "WaitingText",
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = waiting,
	})
	local waitingHint = Kit.text("", {
		Name = "WaitingHint",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = waiting,
	})
	-- The code on a lit plate: a field well with the bevel edge, the code in
	-- Fredoka at hero size.
	local codeWell = Kit.new("Frame", {
		Name = "CodeWell",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, CODE_PLATE_H),
		BackgroundColor3 = Kit.colors.field,
		BorderSizePixel = 0,
		Visible = false,
		Parent = waiting,
	}) :: Frame
	Kit.corner(Kit.radius.sheet).Parent = codeWell
	Kit.bevel(codeWell)
	Kit.glow(codeWell, Kit.colors.accent, { scale = 1, transparency = CODE_GLOW_FADE, stretch = true })
	-- A read-only TextBox (D-090): a tap selects the code so the player can
	-- copy it (Roblox gives games no clipboard; the OS copy does the rest).
	local codeLabel = Kit.new("TextBox", {
		Name = "CodeLabel",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = Kit.font.display,
		TextSize = Kit.size.hero,
		TextColor3 = Kit.colors.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextEditable = false,
		ClearTextOnFocus = false,
		Text = "",
		ZIndex = 2,
		Parent = codeWell,
	}) :: TextBox
	pcall(function()
		codeLabel.Focused:Connect(function()
			-- Select the whole code (CursorPosition and SelectionStart, 1-based).
			codeLabel.CursorPosition = #codeLabel.Text + 1
			codeLabel.SelectionStart = 1
		end)
	end)
	local codeHint = Kit.caption(LobbyWords.CODE_COPY, {
		Name = "CodeHint",
		LayoutOrder = 4,
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, Kit.size.caption + Kit.space.xs),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = waiting,
	})
	local waitingNow = Kit.text("", {
		Name = "WaitingNow",
		LayoutOrder = 5,
		-- Room above and below, so the line does not touch the code or Cancel.
		Size = UDim2.new(1, 0, 0, Kit.size.body + 2 * Kit.space.md),
		Font = Kit.font.medium,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = waiting,
	})
	Kit.button("Cancel", function()
		ctx.net.send("Leave")
	end, { variant = "danger", Name = "Cancel", LayoutOrder = 7, Parent = waiting })

	local startingText = Kit.heading("Match found. Starting…", {
		Name = "StartingText",
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = starting,
	})
	local matchParts = LobbyMatch.new(ctx, {
		content = content,
		onlineOrder = onlineOrder,
		waiting = waiting,
		waitingOrder = 6,
		startingText = startingText,
		sheetBody = friend.body,
		closeSheet = function()
			friend:close()
		end,
	})
	matchParts.online.LayoutOrder = 2
	matchParts.online.Size = UDim2.fromScale(0, 1)
	matchParts.online.AutomaticSize = Enum.AutomaticSize.X
	matchParts.online.Parent = stats

	local cardShadow: ImageLabel? = nil -- the card's shadow while it stands beside the column
	local padding = content:FindFirstChildOfClass("UIPadding") :: UIPadding
	local colorHolder = Kit.outer(colorPick.button)
	local reviewHolder = Kit.outer(review.button)
	local bugsHolder = Kit.outer(bugs.button)

	-- The idle column's height, from its parts' own sizes (D-090): a wide
	-- screen's column starts where this would sit centered, whatever state
	-- shows, so the wordmark never moves when the queue or a code opens.
	local function idleHeight(): number
		local gap = Kit.space.sm
		local h = Kit.wordmarkHeight() + gap + stats.Size.Y.Offset + gap
		if eyebrow.Visible then
			h += EYEBROW_H + gap
		end
		if spacer.Visible then
			h += spacer.Size.Y.Offset + gap
		end
		h += Kit.PRIMARY_H + gap -- Play vs Bot
		h += BotLevel.HEIGHT + Kit.space.xs + BotLevel.NOTE_HEIGHT + gap -- the levels and their line
		h += Kit.MIN_TOUCH + gap -- Find match, Play a friend
		h += daily.height()
		for _, button in { colorPick.button, review.button, bugs.button } do
			if button.Visible then
				h += gap + Kit.MIN_TOUCH
			end
		end
		return h
	end

	local function relayout()
		local size = parent.AbsoluteSize
		local compact = Kit.compact(size)
		local phone = size.X < SIDE_MIN_W or compact
		-- A landscape phone: the wordmark and the record move to the brand pane.
		brand.Visible = compact
		-- The backdrop map stays inside the brand pane on a landscape phone (D-090).
		brand.ClipsDescendants = compact
		brandMap.root.Size = if compact
			then UDim2.fromScale(COMPACT_MAP_W, COMPACT_MAP_H)
			else UDim2.fromScale(MAP_W, MAP_H)
		local top = if compact then brand else content
		if title.Parent ~= top then
			title.Parent = top
			stats.Parent = top
		end
		-- A short phone drops the eyebrow for the level's line (D-087), so the
		-- leaderboard's top 3 still fits from PHONE_BOARD_H.
		eyebrow.Visible = not compact
			and size.Y >= SHORT_SCREEN
			and (not phone or size.Y >= PHONE_BOARD_H + NOTE_ROOM)
		-- A phone's column starts below the corner toggles (the eyebrow and the
		-- wordmark never sit under them); beside the card it is clear of them,
		-- and so is a landscape phone's (the toggles are over the brand pane).
		padding.PaddingTop = UDim.new(0, if phone and not compact then CORNER_CLEAR else 0)
		spacer.Visible = not phone
		daily.setCompact(phone)
		-- On a phone, Color, Review names and Bug reports share one row (D-090).
		local row: { GuiObject } = {}
		local faces: { TextButton } = { colorPick.button, review.button, bugs.button }
		local holders: { GuiObject } = { colorHolder, reviewHolder, bugsHolder }
		for k, face in faces do
			if face.Visible then
				table.insert(row, holders[k])
			end
		end
		local paired = phone and #row > 0
		extras.Visible = paired
		-- A landscape phone's column has no height for the Extras row as well
		-- as the level's line (it ran under the top bar and off the bottom,
		-- fix17): with the row, the chips' outline says the level alone and
		-- the rows sit closer.
		local crowded = compact and paired
		levelNote.Visible = not crowded
		local idleList = idle:FindFirstChildOfClass("UIListLayout")
		if idleList then
			idleList.Padding = UDim.new(0, if crowded then Kit.space.xs else Kit.space.sm)
		end
		local holder = if paired then extras else idle
		local cells = math.max(#row, 1)
		local cell = UDim2.new(1 / cells, -Kit.space.sm * (cells - 1) / cells, 0, Kit.MIN_TOUCH)
		for k, item in { colorHolder, reviewHolder, bugsHolder } do
			if item.Parent ~= holder then
				item.Parent = holder
			end
			item.Size = if paired then cell else UDim2.new(1, 0, 0, Kit.MIN_TOUCH)
			item.LayoutOrder = if paired then k else 5 + k
		end
		-- A wide screen: the column from a fixed top (idleHeight), so nothing jumps.
		if not phone then
			list.VerticalAlignment = Enum.VerticalAlignment.Top
			padding.PaddingTop = UDim.new(0, math.max(0, math.floor((size.Y - idleHeight()) / 2)))
		else
			list.VerticalAlignment = Enum.VerticalAlignment.Center
		end
		-- The leaderboard: beside the column when there is room, else at its end.
		local card = board.card
		if compact then
			content.AnchorPoint = Vector2.new(0, 0)
			content.Position = UDim2.new()
			content.Size = UDim2.new(COLUMN_SHARE, -BOARD_GAP // 2, 1, 0)
			brand.Position = UDim2.new(COLUMN_SHARE, BOARD_GAP // 2, 0, 0)
			brand.Size = UDim2.new(1 - COLUMN_SHARE, -BOARD_GAP // 2, 1, 0)
			card.Parent = brand
			card.LayoutOrder = 8
			card.AnchorPoint = Vector2.new(0, 0)
			card.Position = UDim2.new()
			card.Size = UDim2.fromScale(1, 0)
			-- A short landscape phone (an iPhone's 332 px under the top bar) has
			-- the top 3 on a dense card: the full card fits from COMPACT_BOARD_H.
			local needed = COMPACT_BOARD_H + (if review.button.Visible then REVIEW_ROOM else 0)
			local tall = size.Y >= needed
			board.setDense(not tall)
			board.setRows(if tall or size.Y >= DENSE_BOARD_H then Leaderboard.COMPACT else 0)
			brandList.Padding = UDim.new(0, if tall then Kit.space.sm else Kit.space.xs)
			-- The wordmark's box has a gap over its letters: on the dense layout
			-- that gap may sit beside the corner toggles.
			brandPad.PaddingTop = UDim.new(0, if tall then CORNER_CLEAR else CORNER_CLEAR - Kit.space.sm)
			return
		end
		board.setDense(false)
		content.AnchorPoint = Vector2.new(0.5, 0)
		content.Size = UDim2.fromScale(1, 1)
		if not phone then
			local shift = (BOARD_W + BOARD_GAP) / 2
			content.Position = UDim2.new(0.5, -shift, 0, 0)
			card.Parent = parent
			card.AnchorPoint = Vector2.new(0, 0.5)
			card.Position = UDim2.new(0.5, MAX_WIDTH / 2 - shift + BOARD_GAP, 0.5, 0)
			card.Size = UDim2.fromOffset(BOARD_W, 0)
			-- Standing on the stage, the card casts a shadow (in the column the
			-- list would move one, so there it keeps the bevel only).
			local shadow = cardShadow
			if shadow == nil or shadow.Parent ~= parent then
				cardShadow = Kit.shadow(card)
			end
			board.setRows(if size.Y >= TALL_BOARD_H then Leaderboard.SHORT else Leaderboard.COMPACT)
		else
			content.Position = UDim2.fromScale(0.5, 0)
			card.Parent = idle
			card.LayoutOrder = 8
			card.AnchorPoint = Vector2.new(0, 0)
			card.Position = UDim2.new()
			card.Size = UDim2.fromScale(1, 0)
			local needed = PHONE_BOARD_H + (if review.button.Visible then REVIEW_ROOM else 0)
			board.setRows(if size.Y >= needed then Leaderboard.COMPACT else 0)
		end
	end

	-- The queue's clock and ring (D-090): from when the player joined the queue
	-- (the server's botAt less the offer delay), else from when this screen saw it.
	local queuedSince: number? = nil
	local lastRing = -math.huge
	local stopBreathe: (() -> ())? = nil
	local function paintQueue(now: number, status: string)
		local queued = status == "Queued"
		ringRow.Visible = queued
		if not queued then
			queuedSince = nil
			local stop = stopBreathe
			if stop then
				stop()
				stopBreathe = nil
			end
			return
		end
		local since = queuedSince or now
		queuedSince = since
		queueTime.Text = Kit.clock(math.max(0, now - since))
		if stopBreathe == nil then
			local b = RING_BREATHE
			stopBreathe = Motion.breathe(ringEdge, "Transparency", b[1], b[2], b[3])
		end
		if now - lastRing >= RING_EVERY then
			lastRing = now
			Motion.ring(ring, Kit.colors.accent) -- nothing under reduced motion
		end
	end

	-- The private code's waiting line: its dots step unless motion is reduced.
	local function paintWaiting(now: number)
		local base = string.gsub(Words.HOSTING_WAIT, "…$", "")
		if Motion.reduced() then
			waitingNow.Text = Words.HOSTING_WAIT
		else
			local dots = math.floor(now / DOT_EVERY) % 4
			-- Padded to the same width, so the line never shifts as the dots move.
			waitingNow.Text = base .. string.rep(".", dots) .. string.rep(" ", 3 - dots)
		end
	end

	local function update(state: Types.State)
		relayout()
		local lobby = state.lobby
		local status = if lobby then lobby.state else "Idle"
		local isFull = lobby ~= nil and lobby.full == true
		local profile = if lobby then lobby.profile else nil
		-- The public landslide count (D-094) joins the record line once there is one.
		local slides = if profile and (profile.landslides or 0) >= 1
			then ` · {LandslideBadge.line(profile.landslides)}`
			else ""
		record.Text = if profile
			then `Rating {profile.rating} · {profile.wins} won, {profile.losses} lost{slides}`
			else ""
		-- A player with no games yet: the "?" chip pulses until they open it (D-090).
		newPlayer = profile ~= nil and (profile.games or 0) == 0 and profile.wins + profile.losses == 0
		paintPulse()

		fullBanner.Visible = isFull and status == "Idle"

		idle.Visible = status == "Idle"
		waiting.Visible = status == "Queued" or status == "Hosting"
		starting.Visible = status == "InMatch" or status == "Found"
		colorPick.update(lobby)
		review.update(lobby, state.review)
		bugs.update(lobby, state.bugs)
		Settings.setTimers(settings, if lobby and lobby.admin then lobby.admin.timersOff == true else nil)
		board.update(state.leaderboard)
		daily.update(state.daily)
		if status ~= "Idle" then
			friend:close()
			colorPick.sheet:close()
			review.sheet:close()
			bugs.sheet:close()
			howTo.sheet:close()
			daily.sheet:close()
		end
		relayout() -- the Color and Review buttons may have just shown or hidden
		-- Only the idle Lobby has something to press first (UI audit rule "primary").
		parent:SetAttribute("PrimaryOptional", status ~= "Idle")
		if status == "Queued" then
			local count = if lobby then lobby.queued else 0
			waitingTitle.Text = "Looking for an opponent…"
			waitingTitle.TextSize = Kit.size.heading
			waitingTitle.Font = Kit.font.bold
			waitingTitle.TextColor3 = Kit.colors.text
			local online = if lobby and type(lobby.online) == "number" then Online.text(lobby.online) else nil
			waitingHint.Text = MatchWords.queueHint(online, count)
			waitingNow.Visible = false
			codeWell.Visible = false
			codeHint.Visible = false
			-- The time waited counts from the server's botAt when it sent one.
			if lobby and type(lobby.botAt) == "number" then
				queuedSince = lobby.botAt - ctx.config.QUEUE_BOT_OFFER_SECONDS
			end
		elseif status == "Hosting" then
			-- An eyebrow over the code: the code's hero size is this screen's fourth.
			waitingTitle.Text = string.upper(Words.HOSTING_TITLE)
			waitingTitle.TextSize = Kit.size.caption
			waitingTitle.Font = Kit.font.medium
			waitingTitle.TextColor3 = Kit.colors.muted
			waitingHint.Text = Words.HOSTING_HINT
			codeLabel.Text = if lobby and lobby.code then lobby.code else "-----"
			codeWell.Visible = true
			codeHint.Visible = true
			paintWaiting(ctx.now())
			waitingNow.Visible = true
		end
		paintQueue(ctx.now(), status)
		matchParts.update(state)
	end

	-- Arrive top to bottom: the hero pops, then each line fades in.
	Motion.pop(title, Motion.POP_FROM)
	local arriving: { Instance } = { eyebrow, title, record, practice, findMatch, playFriend }
	for _, child in botLevel.root:GetChildren() do
		if child:IsA("TextButton") then
			table.insert(arriving, child)
		end
	end
	for _, child in settings:GetDescendants() do
		if child:IsA("TextButton") then
			table.insert(arriving, child)
		end
	end
	table.insert(arriving, levelNote)
	table.insert(arriving, daily.card)
	table.insert(arriving, colorPick.button)
	table.insert(arriving, board.card)
	Motion.stagger(arriving, function(item, _index, delay)
		Motion.enter(item, nil, delay)
	end)

	return {
		update = update,
		tick = function(now: number)
			relayout()
			daily.tick(now)
			matchParts.tick(now)
			local lobby = ctx.store.get().lobby
			local status = if lobby then lobby.state else "Idle"
			paintQueue(now, status)
			if status == "Hosting" then
				paintWaiting(now)
			end
		end,
		destroy = function()
			stopShine()
			brandMap.stop()
			local stop = stopPulse
			if stop then
				stop()
			end
			local breathe = stopBreathe
			if breathe then
				breathe()
			end
		end,
	}
end

return Screen
