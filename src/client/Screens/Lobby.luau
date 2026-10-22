--!strict
-- Lobby: play the bot, find a public match, host a private match or join one by
-- its 5-character code. While queued or hosting it shows what is happening and a
-- Cancel button. Everything is built once; update() only flips Visible and text,
-- so a half-typed code survives server messages.

local Kit = require(script.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Common.Layout)
local Types = require(script.Parent.Types)

local Screen = {}

local MAX_WIDTH = 480 -- px
local BUTTON_HEIGHT = 52 -- px
local TOAST_SECONDS = 4
local CODE_LENGTH = 5

local PITCH = "Race a rival to 270 electoral votes: draft the map, run the campaign, win election night."

-- Codes use letters A-Z and digits 2-9 (no 0 or 1).
local function validCode(code: string): boolean
	return #code == CODE_LENGTH and string.match(code, "^[A-Z2-9]+$") ~= nil
end

function Screen.mount(parent: Frame, ctx: Types.Ctx): Types.Screen
	local page = Layout.page(parent, { maxWidth = MAX_WIDTH })
	local content = page.content

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	Kit.box({ Name = "Spacer", LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 24), Parent = content })

	Kit.text("270", {
		Name = "Title",
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, 84),
		Font = Kit.font.bold,
		TextSize = 72,
		TextScaled = true,
		TextColor3 = Kit.colors.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = content,
	})
	Kit.text(PITCH, {
		Name = "Pitch",
		LayoutOrder = nextOrder(),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = content,
	})

	local record = Kit.text("", {
		Name = "Record",
		LayoutOrder = nextOrder(),
		Size = UDim2.new(1, 0, 0, 24),
		TextScaled = true,
		TextSize = Kit.size.large,
		Font = Kit.font.medium,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = content,
	})

	local toast = Kit.text("", {
		Name = "Toast",
		LayoutOrder = nextOrder(),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextSize = Kit.size.body,
		TextColor3 = Kit.colors.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = content,
	})
	local fullBanner = Kit.text("Server full. Try again in a minute.", {
		Name = "ServerFull",
		LayoutOrder = nextOrder(),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
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
		Kit.list("Vertical", 10).Parent = box
		return box
	end

	local idle = section("Idle")
	local waiting = section("Waiting")
	local starting = section("Starting")

	-- Current lobby facts, read by the button handlers.
	local isFull = false
	local toastUntil = 0
	local lastMessageKey = ""

	local function showToast(text: string)
		toast.Text = text
		toast.Visible = true
		toastUntil = ctx.now() + TOAST_SECONDS
	end

	local buttons: { TextButton } = {}
	local function mainButton(text: string, name: string, op: string, primary: boolean): TextButton
		local button = Kit.button(text, function()
			if isFull then
				return
			end
			ctx.net.send(op)
		end, {
			Name = name,
			LayoutOrder = #buttons + 1,
			Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
			TextSize = Kit.size.large,
			BackgroundColor3 = if primary then Kit.colors.accent else Kit.colors.raised,
			TextColor3 = if primary then Kit.colors.background else Kit.colors.text,
			Parent = idle,
		})
		table.insert(buttons, button)
		return button
	end
	mainButton("Play vs Bot", "Practice", "Practice", true)
	mainButton("Find Match", "FindMatch", "Queue", false)
	mainButton("Host Private Match", "Host", "Host", false)

	Kit.text("Have a code from a friend?", {
		Name = "JoinHint",
		LayoutOrder = 10,
		Size = UDim2.new(1, 0, 0, 22),
		TextColor3 = Kit.colors.muted,
		Parent = idle,
	})
	local joinRow =
		Kit.box({ Name = "JoinRow", LayoutOrder = 11, Size = UDim2.new(1, 0, 0, 48), Parent = idle })
	Kit.list("Horizontal", 8).Parent = joinRow
	local codeBox = Kit.new("TextBox", {
		Name = "CodeBox",
		LayoutOrder = 1,
		Size = UDim2.new(0.6, -4, 1, 0),
		BackgroundColor3 = Kit.colors.surface,
		BorderSizePixel = 0,
		Font = Kit.font.mono,
		TextSize = Kit.size.large,
		TextColor3 = Kit.colors.text,
		PlaceholderText = "CODE",
		PlaceholderColor3 = Kit.colors.muted,
		ClearTextOnFocus = false,
		Text = "",
		Parent = joinRow,
	}) :: TextBox
	Kit.corner(8).Parent = codeBox
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
	local joinButton = Kit.button("Join", function()
		if isFull then
			return
		end
		local code = normalizeCode()
		if not validCode(code) then
			showToast("Enter the 5-character code: letters A-Z and numbers 2-9.")
			return
		end
		ctx.net.send("Join", { code = code })
	end, {
		Name = "Join",
		LayoutOrder = 2,
		Size = UDim2.new(0.4, -4, 1, 0),
		Parent = joinRow,
	})
	table.insert(buttons, joinButton)

	-- Queued or hosting: one box, one Cancel.
	local waitingTitle = Kit.text("", {
		Name = "WaitingText",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.medium,
		TextSize = Kit.size.large,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = waiting,
	})
	local codeLabel = Kit.text("", {
		Name = "CodeLabel",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 84),
		Font = Kit.font.mono,
		TextSize = 64,
		TextScaled = true,
		TextColor3 = Kit.colors.accent,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = waiting,
	})
	local waitingHint = Kit.text("", {
		Name = "WaitingHint",
		LayoutOrder = 3,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = waiting,
	})
	Kit.button("Cancel", function()
		ctx.net.send("Leave")
	end, {
		Name = "Cancel",
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
		TextSize = Kit.size.large,
		Parent = waiting,
	})

	Kit.text("Match found. Starting...", {
		Name = "StartingText",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.medium,
		TextSize = Kit.size.large,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = starting,
	})

	local function relayout()
		page.setPortrait(ctx.portrait())
	end

	local function update(state: Types.State)
		relayout()
		local lobby = state.lobby
		local status = if lobby then lobby.state else "Idle"
		isFull = lobby ~= nil and lobby.full == true
		local profile = if lobby then lobby.profile else nil
		record.Visible = profile ~= nil
		if profile then
			record.Text = `Rating {profile.rating} · {profile.wins} won, {profile.losses} lost`
		end

		fullBanner.Visible = isFull and status == "Idle"
		for _, button in buttons do
			Kit.setEnabled(button, not isFull)
		end

		idle.Visible = status == "Idle"
		waiting.Visible = status == "Queued" or status == "Hosting"
		starting.Visible = status == "InMatch"
		if status == "Queued" then
			local count = if lobby then lobby.queued else 0
			waitingTitle.Text = `Looking for an opponent… ({count} waiting)`
			waitingHint.Text = "You will be matched as soon as someone else joins."
			codeLabel.Visible = false
		elseif status == "Hosting" then
			waitingTitle.Text = "Your private match"
			waitingHint.Text = "Tell your friend to enter this code"
			codeLabel.Text = if lobby and lobby.code then lobby.code else "-----"
			codeLabel.Visible = true
		end

		-- A new message (rejection, notice) shows as a toast for a few seconds.
		local messages = state.messages
		local key = `{#messages}|{messages[#messages] or ""}`
		if key ~= lastMessageKey then
			lastMessageKey = key
			if #messages > 0 then
				showToast(messages[#messages])
			end
		end
	end

	-- Messages already in the store belong to an earlier screen; do not toast them.
	do
		local messages = ctx.store.get().messages
		lastMessageKey = `{#messages}|{messages[#messages] or ""}`
	end

	return {
		update = update,
		tick = function(now: number)
			if toast.Visible and now >= toastUntil then
				toast.Visible = false
			end
			relayout()
		end,
		destroy = function() end,
	}
end

return Screen
