--!strict
-- The Lobby's matchmaking parts (docs/DESIGN.md D-083), kept out of
-- Screens/Lobby so that screen only places them:
--   Online       "1,234 online" under the record (hidden while unknown; while
--                queued the waiting hint carries it)
--   WaitBot      "Play a bot while you wait" (the queue's main button, D-090:
--                the primary while it shows), once the player has waited
--                Config.QUEUE_BOT_OFFER_SECONDS in the queue (the server's
--                LobbyStatus.botAt), with WaitBotHint under it; it plays the
--                level picked under Play vs Bot (UI/BotLevel)
--   InviteHost   "Invite a friend" on the private-code screen
--   Invite       "Invite a friend" at the top of the Play a friend sheet (its
--                main button, D-090: UI/Featured), with
--                InviteHint: it makes a code (Host) and then opens Roblox's
--                invite prompt carrying it (Net.invite)
--   FoundHint, FoundCancel   the match on its way (state "Found"): what is
--                happening, and Cancel (Back to lobby in a match server)
--
--   local parts = LobbyMatch.new(ctx, slots)
--   parts.update(state) · parts.tick(now)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Online = require(ReplicatedStorage.Shared.Net.Online)
local Words = require(ReplicatedStorage.Shared.UI.Words.Matchmaking)

local BotLevel = require(script.Parent.BotLevel)
local Featured = require(script.Parent.Featured)
local Kit = require(script.Parent.Kit)
local Types = require(script.Parent.Parent.Screens.Types)

local LobbyMatch = {}

local INVITE_WAIT = 15 -- s a tapped "Invite a friend" waits for its code before giving up

export type Slots = {
	content: Frame, -- the Lobby's column
	onlineOrder: number, -- LayoutOrder of the Online line in the column
	waiting: Frame, -- the Queued / Hosting section
	waitingOrder: number, -- LayoutOrder for WaitBot / InviteHost in it
	startingText: TextLabel, -- the InMatch / Found section's heading
	sheetBody: Frame, -- the Play a friend sheet's body
	closeSheet: () -> (),
}

export type Parts = {
	online: TextLabel,
	update: (state: Types.State) -> (),
	tick: (now: number) -> (),
}

function LobbyMatch.new(ctx: Types.Ctx, slots: Slots): Parts
	local online = Kit.caption("", {
		Name = "Online",
		LayoutOrder = slots.onlineOrder,
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Kit.colors.good,
		Visible = false,
		Parent = slots.content,
	})

	-- ------------------------------------------------------------ a bot game while waiting

	local waitBot = Kit.button(Words.WAIT_BOT, function()
		ctx.net.send("WaitBot", { difficulty = BotLevel.get() })
	end, {
		variant = "primary",
		Name = "WaitBot",
		LayoutOrder = slots.waitingOrder,
		Visible = false,
		Parent = slots.waiting,
	})
	waitBot:SetAttribute("PrimaryAction", true)
	local waitBotHint = Kit.caption(Words.WAIT_BOT_HINT, {
		Name = "WaitBotHint",
		LayoutOrder = slots.waitingOrder,
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = slots.waiting,
	})

	-- ------------------------------------------------------------ invites

	local inviteWanted: number? = nil -- os.clock() when "Invite a friend" asked for a code
	local function invite(code: string)
		local send = ctx.net.invite
		if send then
			task.spawn(send, code)
		end
	end
	local inviteHost = Kit.button(Words.INVITE, function()
		local lobby = ctx.store.get().lobby
		if lobby and lobby.code then
			invite(lobby.code)
		end
	end, {
		variant = "secondary",
		Name = "InviteHost",
		LayoutOrder = slots.waitingOrder,
		Visible = false,
		Parent = slots.waiting,
	})
	local inviteButton = Kit.button(Words.INVITE, function()
		slots.closeSheet()
		inviteWanted = os.clock()
		ctx.net.send("Host")
	end, { variant = "secondary", Name = "Invite", LayoutOrder = -2, Parent = slots.sheetBody })
	Featured.set(inviteButton, Kit.colors.accent)
	Kit.text(Words.INVITE_HINT, {
		Name = "InviteHint",
		LayoutOrder = -1,
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Kit.colors.muted,
		Parent = slots.sheetBody,
	})
	Kit.divider({ LayoutOrder = 0, Parent = slots.sheetBody })

	-- ------------------------------------------------------------ the match on its way

	local starting = slots.startingText.Parent :: Instance
	local foundHint = Kit.text("", {
		Name = "FoundHint",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = starting,
	})
	local foundCancel = Kit.button("Cancel", function()
		local lobby = ctx.store.get().lobby
		if lobby and lobby.found and lobby.found.phase == "Arriving" then
			ctx.net.send("Return")
		else
			ctx.net.send("Leave")
		end
	end, { variant = "danger", Name = "FoundCancel", LayoutOrder = 3, Visible = false, Parent = starting })

	local lastState: Types.State? = nil

	local function refresh(now: number)
		local state = lastState
		local lobby = if state then state.lobby else nil
		local status = if lobby then lobby.state else "Idle"
		-- The online count, wherever the column shows.
		local count = if lobby then lobby.online else nil
		online.Text = if type(count) == "number" then `● {Online.text(count)}` else ""
		online.Visible = type(count) == "number" and status == "Idle" -- queued: in the waiting hint
		-- A bot game while waiting: offered once the server says so.
		local botAt = if lobby and status == "Queued" then lobby.botAt else nil
		local offered = type(botAt) == "number" and now >= botAt
		waitBot.Visible = offered
		waitBotHint.Visible = offered
		inviteHost.Visible = status == "Hosting" and lobby ~= nil and lobby.code ~= nil
		-- The match on its way.
		local found = if lobby then lobby.found else nil
		local phase = if status == "Found" and found then found.phase else nil
		if status == "Found" then
			local title, hint = Words.FOUND_TITLE, Words.FOUND_JOINING
			if phase == "Waiting" then
				hint = Words.FOUND_WAITING
				if found and type(found.untilAt) == "number" then
					hint ..= ` {Words.secondsLeft(found.untilAt - now)}.`
				end
			elseif phase == "Arriving" then
				hint = Words.FOUND_ARRIVING
			elseif phase == "Leaving" then
				title, hint = Words.LEAVING_TITLE, Words.FOUND_LEAVING
			end
			slots.startingText.Text = title
			foundHint.Text = hint
		else
			slots.startingText.Text = "Match found. Starting…"
		end
		foundHint.Visible = status == "Found"
		foundCancel.Visible = phase == "Waiting" or phase == "Joining" or phase == "Arriving"
		foundCancel.Text = if phase == "Arriving" then "Back to lobby" else "Cancel"
	end

	local function update(state: Types.State)
		lastState = state
		local lobby = state.lobby
		local status = if lobby then lobby.state else "Idle"
		-- "Invite a friend" from the sheet: the prompt opens once the code arrives.
		local wanted = inviteWanted
		if wanted ~= nil then
			if status == "Hosting" and lobby and lobby.code then
				inviteWanted = nil
				invite(lobby.code)
			elseif status ~= "Idle" or os.clock() - wanted > INVITE_WAIT then
				inviteWanted = nil
			end
		end
		refresh(ctx.now())
	end

	return {
		online = online,
		update = update,
		tick = refresh,
	}
end

return LobbyMatch
