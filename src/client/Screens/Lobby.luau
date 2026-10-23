--!strict
-- Lobby: play the bot, find a public match, or play a friend (host a private
-- match or join one by its 5-character code). While queued or hosting it shows
-- what is happening and a Cancel button. Everything is built once; update() only
-- flips Visible and text, so a half-typed code survives server messages.
--
-- Layout (docs/UI-STYLE.md §4.1): one centered column, at most 480 px wide, that
-- does not scroll: the "270" hero, a one-line tagline, the record, then Play vs
-- Bot (the one primary), "Find match" and "Play a friend" side by side, and a
-- ghost "How to play" (the Help sheet). "Play a friend" opens a sheet with
-- "Make a code" (Host) and the code field + Join. Messages (rejections,
-- notices, a bad code) go to the global toast.
--
-- Stable names: Practice, FindMatch, PlayFriend, HowToPlay, FriendSheet, Host,
-- CodeBox, Join, Idle, Waiting, Starting, WaitingText, CodeWell, CodeLabel,
-- WaitingHint, Cancel, Record, ServerFull, Title, Pitch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Words = require(ReplicatedStorage.Shared.UI.Words.Setup)

local Kit = require(script.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Common.Layout)
local Sheet = require(script.Parent.Parent.UI.Sheet)
local Types = require(script.Parent.Types)

local Screen = {}

local MAX_WIDTH = 480 -- px
local CODE_LENGTH = 5
local SHORT_SCREEN = 420 -- px; below this the tagline is dropped to make room

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

	Kit.text("270", {
		Name = "Title",
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, Kit.size.hero + 8),
		Font = Kit.font.bold,
		TextSize = Kit.size.hero,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = content,
	})
	local pitch = Kit.text(Words.TAGLINE, {
		Name = "Pitch",
		LayoutOrder = nextOrder(),
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = content,
	})
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
		ctx.net.send("Practice")
	end, { variant = "primary", Name = "Practice", LayoutOrder = 1, Parent = idle })
	practice:SetAttribute("PrimaryAction", true)

	local pair = Kit.box({
		Name = "Pair",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = idle,
	})
	Kit.list("Horizontal", Kit.space.sm).Parent = pair
	Kit.button("Find match", function()
		ctx.net.send("Queue")
	end, {
		variant = "secondary",
		Name = "FindMatch",
		LayoutOrder = 1,
		Size = UDim2.new(0.5, -Kit.space.sm / 2, 1, 0),
		Parent = pair,
	})
	Kit.button("Play a friend", function()
		friend:open()
	end, {
		variant = "secondary",
		Name = "PlayFriend",
		LayoutOrder = 2,
		Size = UDim2.new(0.5, -Kit.space.sm / 2, 1, 0),
		Parent = pair,
	})
	local openHelp = ctx.help
	if openHelp then
		Kit.button("How to play", function()
			openHelp()
		end, {
			variant = "ghost",
			Name = "HowToPlay",
			LayoutOrder = 3,
			Parent = idle,
		})
	end

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
	local codeWell = Kit.new("Frame", {
		Name = "CodeWell",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, Kit.size.hero + 2 * Kit.space.lg),
		BackgroundColor3 = Kit.colors.field,
		BorderSizePixel = 0,
		Visible = false,
		Parent = waiting,
	}) :: Frame
	Kit.corner(Kit.radius.panel).Parent = codeWell
	local codeLabel = Kit.text("", {
		Name = "CodeLabel",
		Size = UDim2.fromScale(1, 1),
		Font = Kit.font.mono,
		TextSize = Kit.size.hero,
		TextXAlignment = Enum.TextXAlignment.Center,
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

	local function relayout()
		pitch.Visible = parent.AbsoluteSize.Y >= SHORT_SCREEN
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
		if status ~= "Idle" then
			friend:close()
		end
		-- Only the idle Lobby has something to press first (UI audit rule "primary").
		parent:SetAttribute("PrimaryOptional", status ~= "Idle")
		if status == "Queued" then
			local count = if lobby then lobby.queued else 0
			waitingTitle.Text = "Looking for an opponent…"
			waitingHint.Text = if count > 1
				then `{count} players waiting`
				else "You'll start as soon as someone joins."
			waitingNow.Visible = false
			codeWell.Visible = false
		elseif status == "Hosting" then
			waitingTitle.Text = "Your private match"
			waitingHint.Text = Words.HOSTING_HINT
			codeLabel.Text = if lobby and lobby.code then lobby.code else "-----"
			codeWell.Visible = true
			waitingNow.Text = Words.HOSTING_WAIT
			waitingNow.Visible = true
		end
	end

	return {
		update = update,
		tick = function(_now: number)
			relayout()
		end,
		destroy = function() end,
	}
end

return Screen
