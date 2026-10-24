--!strict
-- Lobby: play the bot, find a public match, or play a friend (host a private
-- match or join one by its 5-character code). While queued or hosting it shows
-- what is happening and a Cancel button. Everything is built once; update() only
-- flips Visible and text, so a half-typed code survives server messages.
--
-- Layout (docs/UI-STYLE.md §4.1): one centered column, at most 480 px wide, that
-- does not scroll: the "LANDSLIDE" wordmark with its "RACE TO 270" ribbon
-- (Kit.wordmark, D-064), the record, then Play vs
-- Bot (the one primary) with the bot level chips under it (UI/BotLevel, D-059),
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
-- (SoundToggle, MotionToggle, SettingsTip; TimersToggle for admins, D-080), ColorButton, ColorSheet, ReviewButton, ReviewSheet (admins, D-069), BotLevel (Level_<level>), HowToSheet,
-- LeaderboardCard, LeaderboardSheet, DailyCard, DailySheet.
--
-- The Daily Race (UI/DailyRace, D-080) is one card in the column under How to
-- play: today's candidate, the countdown, the streak, Play and Today's board.
-- It takes the room the phone's leaderboard rows had, so a phone shows the
-- top 3 only when it is at least PHONE_BOARD_H + DailyRace's card tall.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Words = require(ReplicatedStorage.Shared.UI.Words.Setup)

local BotLevel = require(script.Parent.Parent.UI.BotLevel)
local DailyRace = require(script.Parent.Parent.UI.DailyRace)
local ColorPick = require(script.Parent.Parent.UI.ColorPick)
local HowTo = require(script.Parent.Parent.UI.HowTo)
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
local PHONE_BOARD_H = 740 -- px of height for the top 3 in a phone's column (else only "You" and See all)
local DAILY_CARD_H = 130 -- px the Daily Race card takes in the column (D-080): added to PHONE_BOARD_H
local STAGE_GLOW = 1.1 -- the stage glow's size, a share of the screen (an ellipse)
local STAGE_FADE = 0.75 -- its transparency: a lit table, not a spotlight
local CODE_PLATE_H = Kit.size.hero + 2 * Kit.space.lg -- px, the private match code's plate
local CODE_GLOW_FADE = 0.9 -- a faint white light inside the code plate

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
	-- Always there (empty until the profile arrives), so nothing jumps.
	local record = Kit.caption("", {
		Name = "Record",
		LayoutOrder = nextOrder(),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = content,
	})
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
	-- Breathing room between the hero block and the buttons.
	Kit.box({
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
	local friend = Sheet.new(parent, { title = "Play a friend", name = "FriendSheet", height = 0.42 })

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
	local botLevel = BotLevel.new({ LayoutOrder = 2, Parent = idle })

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
	local howToPlay = Kit.button("How to play", function()
		howTo.open()
	end, {
		variant = "ghost",
		Name = "HowToPlay",
		LayoutOrder = 4,
		Parent = idle,
	})
	local colorPick = ColorPick.new(parent, ctx, { LayoutOrder = 6, Parent = idle })
	-- Admins only (D-069): the reported names to review.
	local review = NameReview.new(parent, ctx, { LayoutOrder = 7, Parent = idle })
	-- Sound and Reduce motion: the top-right corner (D-075), on every Lobby state;
	-- for admins also "Timers off" (D-080), saved by the server.
	local settings = Settings.corner({
		Parent = parent,
		onTimers = function(off: boolean)
			ctx.net.send("SetTimersOff", { on = off })
		end,
	})
	local board = Leaderboard.new(parent, ctx)
	-- The Daily Race (D-080): one card in the column.
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
	local codeLabel = Kit.text("", {
		Name = "CodeLabel",
		Size = UDim2.fromScale(1, 1),
		Font = Kit.font.display,
		TextSize = Kit.size.hero,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
		Parent = codeWell,
	})
	local waitingNow = Kit.text("", {
		Name = "WaitingNow",
		LayoutOrder = 4,
		-- Room above and below, so the line does not touch the code or Cancel.
		Size = UDim2.new(1, 0, 0, Kit.size.body + 2 * Kit.space.md),
		Font = Kit.font.medium,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = waiting,
	})
	Kit.button("Cancel", function()
		ctx.net.send("Leave")
	end, { variant = "danger", Name = "Cancel", LayoutOrder = 5, Parent = waiting })

	Kit.heading("Match found. Starting…", {
		Name = "StartingText",
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = starting,
	})

	-- The eyebrow under the corner settings (a phone with a tall column, e.g.
	-- an admin's three toggles, D-080): it steps aside, and stays aside at
	-- this screen size so the column does not jump back and forth.
	local eyebrowClear = true
	local eyebrowSize: Vector2? = nil
	local function underCorner(): boolean
		local toggles = settings:FindFirstChild("Toggles") :: GuiObject?
		-- Not laid out yet (everything still at 0): no verdict.
		if
			toggles == nil
			or not eyebrow.Visible
			or toggles.AbsolutePosition.X <= 0
			or eyebrow.AbsoluteSize.X <= 0
		then
			return false
		end
		local text = tostring(eyebrow.Text)
		local bounds = (eyebrow :: any).TextBounds
		local textW = if bounds ~= nil and bounds.X > 0
			then bounds.X
			else (utf8.len(text) or #text) * eyebrow.TextSize * 0.62
		local at, box = eyebrow.AbsolutePosition, eyebrow.AbsoluteSize
		local right = at.X + box.X / 2 + textW / 2
		local top, bottom = toggles.AbsolutePosition.Y, toggles.AbsolutePosition.Y + toggles.AbsoluteSize.Y
		return right > toggles.AbsolutePosition.X and at.Y < bottom and at.Y + box.Y > top
	end

	local cardShadow: ImageLabel? = nil -- the card's shadow while it stands beside the column
	local function relayout()
		local size = parent.AbsoluteSize
		if size ~= eyebrowSize then
			eyebrowSize = size
			eyebrowClear = true
		end
		if eyebrowClear and underCorner() then
			eyebrowClear = false
		end
		eyebrow.Visible = size.Y >= SHORT_SCREEN and eyebrowClear
		-- The leaderboard: beside the column when there is room, else at its end.
		local card = board.card
		if size.X >= SIDE_MIN_W then
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
			board.setRows(if size.Y >= PHONE_BOARD_H + DAILY_CARD_H then Leaderboard.COMPACT else 0)
		end
	end

	local function update(state: Types.State)
		relayout()
		local lobby = state.lobby
		local status = if lobby then lobby.state else "Idle"
		local isFull = lobby ~= nil and lobby.full == true
		local profile = if lobby then lobby.profile else nil
		record.Text = if profile
			then `Rating {profile.rating} · {profile.wins} won, {profile.losses} lost`
			else ""

		fullBanner.Visible = isFull and status == "Idle"

		idle.Visible = status == "Idle"
		waiting.Visible = status == "Queued" or status == "Hosting"
		starting.Visible = status == "InMatch"
		colorPick.update(lobby)
		review.update(lobby, state.review)
		Settings.setTimers(settings, if lobby and lobby.admin then lobby.admin.timersOff == true else nil)
		board.update(state.leaderboard)
		daily.update(state.daily)
		if status ~= "Idle" then
			friend:close()
			colorPick.sheet:close()
			review.sheet:close()
			howTo.sheet:close()
			daily.sheet:close()
		end
		-- Only the idle Lobby has something to press first (UI audit rule "primary").
		parent:SetAttribute("PrimaryOptional", status ~= "Idle")
		if status == "Queued" then
			local count = if lobby then lobby.queued else 0
			waitingTitle.Text = "Looking for an opponent…"
			waitingTitle.TextSize = Kit.size.heading
			waitingTitle.Font = Kit.font.bold
			waitingTitle.TextColor3 = Kit.colors.text
			waitingHint.Text = if count > 1
				then `{count} players waiting`
				else "You'll start as soon as someone joins."
			waitingNow.Visible = false
			codeWell.Visible = false
		elseif status == "Hosting" then
			-- An eyebrow over the code: the code's hero size is this screen's fourth.
			waitingTitle.Text = string.upper(Words.HOSTING_TITLE)
			waitingTitle.TextSize = Kit.size.caption
			waitingTitle.Font = Kit.font.medium
			waitingTitle.TextColor3 = Kit.colors.muted
			waitingHint.Text = Words.HOSTING_HINT
			codeLabel.Text = if lobby and lobby.code then lobby.code else "-----"
			codeWell.Visible = true
			waitingNow.Text = Words.HOSTING_WAIT
			waitingNow.Visible = true
		end
	end

	-- Arrive top to bottom: the hero pops, then each line fades in.
	Motion.pop(title, Motion.POP_FROM)
	local arriving: { Instance } = { eyebrow, title, record, practice, findMatch, playFriend, howToPlay }
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
		end,
		destroy = function() end,
	}
end

return Screen
