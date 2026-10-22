--!strict
-- Lobby: play the bot, find a public match, host a private match or join one by
-- its 5-character code. While queued or hosting it shows what is happening and a
-- Cancel button. Everything is built once; update() only flips Visible and text,
-- so a half-typed code survives server messages.
--
-- Layout (docs/UI-OVERHAUL.md §3.1): one centered column, at most 560 px wide,
-- that does not scroll (so "Play vs Bot", the one primary, is never in a scroll
-- area). Messages (rejections, notices, a bad code) go to the global toast.

local Kit = require(script.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Common.Layout)
local Types = require(script.Parent.Types)

local Screen = {}

local MAX_WIDTH = 560 -- px
local CODE_LENGTH = 5
local SHORT_SCREEN = 480 -- px; below this the pitch line is dropped to make room

local PITCH = "Race a rival to 270 electoral votes: draft the map, run the campaign, win election night."

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
		TextColor3 = Kit.colors.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = content,
	})
	local pitch = Kit.caption(PITCH, {
		Name = "Pitch",
		LayoutOrder = nextOrder(),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = content,
	})
	-- Always there (empty until the profile arrives), so nothing jumps.
	local record = Kit.text("", {
		Name = "Record",
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, Kit.size.caption + 6),
		TextSize = Kit.size.caption,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = content,
	})
	local fullBanner = Kit.caption("Server full. Try again in a minute.", {
		Name = "ServerFull",
		LayoutOrder = nextOrder(),
		TextSize = Kit.size.body,
		TextColor3 = Kit.colors.danger,
		Font = Kit.font.medium,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = content,
	})

	local function section(name: string): Frame
		local box = Kit.box({
			Name = name,
			LayoutOrder = nextOrder(),
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Visible = false,
			Parent = content,
		})
		Kit.list("Vertical", Kit.space.sm).Parent = box
		return box
	end

	local idle = section("Idle")
	local waiting = section("Waiting")
	local starting = section("Starting")

	-- A local problem (a malformed code) shows in the global toast like a rejection.
	local function complain(text: string)
		ctx.store.say(text, true)
	end

	-- Never disabled by "server full": that status can be stale, and the server
	-- answers ServerFull with a toast if there is still no room.
	local practice = Kit.button("Play vs Bot", function()
		ctx.net.send("Practice")
	end, { variant = "primary", Name = "Practice", LayoutOrder = 1, Parent = idle })
	practice:SetAttribute("PrimaryAction", true)
	Kit.button("Find Match", function()
		ctx.net.send("Queue")
	end, { variant = "secondary", Name = "FindMatch", LayoutOrder = 2, Parent = idle })
	Kit.button("Host Private Match", function()
		ctx.net.send("Host")
	end, { variant = "secondary", Name = "Host", LayoutOrder = 3, Parent = idle })

	Kit.caption("Have a code?", { Name = "JoinHint", LayoutOrder = 10, Parent = idle })
	local joinRow = Kit.box({
		Name = "JoinRow",
		LayoutOrder = 11,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = idle,
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
		PlaceholderText = "CODE",
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

	-- Queued or hosting: one box, one Cancel.
	local waitingTitle = Kit.text("", {
		Name = "WaitingText",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.bold,
		TextSize = Kit.size.heading,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = waiting,
	})
	local codeWell = Kit.new("Frame", {
		Name = "CodeWell",
		LayoutOrder = 2,
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
		TextColor3 = Kit.colors.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = codeWell,
	})
	local waitingHint = Kit.caption("", {
		Name = "WaitingHint",
		LayoutOrder = 3,
		TextSize = Kit.size.body,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = waiting,
	})
	Kit.button("Cancel", function()
		ctx.net.send("Leave")
	end, { variant = "danger", Name = "Cancel", LayoutOrder = 4, Parent = waiting })

	Kit.text("Match found. Starting…", {
		Name = "StartingText",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.bold,
		TextSize = Kit.size.heading,
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
		-- Only the idle Lobby has something to press first (UI audit rule "primary").
		parent:SetAttribute("PrimaryOptional", status ~= "Idle")
		if status == "Queued" then
			local count = if lobby then lobby.queued else 0
			waitingTitle.Text = `Looking for an opponent… ({count} waiting)`
			waitingHint.Text = "You will be matched as soon as someone else joins."
			codeWell.Visible = false
		elseif status == "Hosting" then
			waitingTitle.Text = "Your private match"
			waitingHint.Text = "Tell your friend to enter this code"
			codeLabel.Text = if lobby and lobby.code then lobby.code else "-----"
			codeWell.Visible = true
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
