--!strict
-- "Opponent found! Leave this bot game?" (docs/DESIGN.md D-083). A player who
-- plays the bot while waiting in the queue keeps their place in line; when an
-- opponent is found the server asks them (LobbyStatus.found.phase "Answer",
-- due at found.untilAt, Config.QUEUE_ACCEPT_SECONDS after it was asked).
-- "Join match" ends the bot game (unrated, nothing saved) and starts the
-- match; "Keep playing" keeps the bot game and leaves the queue, and the other
-- player goes back to the front of the line. No answer in time counts as
-- Keep playing. The × or the scrim only hides the sheet.
--
-- Mounted once by App.client above the screens (ZIndex 45, like LeaveMatch),
-- so it shows over whichever match screen the bot game is on.
--
--   local prompt = FoundPrompt.mount(parent, ctx)
--   prompt.root   Frame "FoundOverlay" (Visible only while open; PrimaryOptional)
--   Elements: FoundSheet (UI/Sheet), FoundText, FoundTime, FoundNote,
--   FoundJoin, FoundKeep.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Words = require(ReplicatedStorage.Shared.UI.Words.Matchmaking)

local Kit = require(script.Parent.Kit)
local Sheet = require(script.Parent.Sheet)
local Types = require(script.Parent.Parent.Screens.Types)

local FoundPrompt = {}

local Z = 45 -- above the Help sheet (40), below the toast (50)
local HEIGHT = 0.42 -- share of a phone's screen
local TICK = 0.25 -- s between countdown updates

export type FoundPrompt = {
	root: Frame,
	isOpen: () -> boolean,
}

-- The answer this player owes, from their lobby status, or nil.
local function asked(state: Types.State): number?
	local lobby = state.lobby
	local found = if lobby then lobby.found else nil
	if found and found.phase == "Answer" and type(found.untilAt) == "number" then
		return found.untilAt
	end
	return nil
end

function FoundPrompt.mount(parent: Instance, ctx: Types.Ctx): FoundPrompt
	local root = Kit.new("Frame", {
		Name = "FoundOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = Z,
		Visible = false,
	}) :: Frame
	root:SetAttribute("PrimaryOptional", true)

	local shownFor: number? = nil -- the untilAt of the offer on screen
	local dismissed: number? = nil -- an offer the player hid with ×
	local open = false

	local sheet = Sheet.new(root, {
		title = Words.PROMPT_TITLE,
		name = "FoundSheet",
		height = HEIGHT,
		onClose = function()
			open = false
			root.Visible = false
			dismissed = shownFor
		end,
	})
	Kit.text(Words.PROMPT_TEXT, {
		Name = "FoundText",
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = sheet.body,
	})
	local time = Kit.text("", {
		Name = "FoundTime",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.medium,
		TextColor3 = Kit.colors.warn,
		Parent = sheet.body,
	})
	local function answer(accept: boolean)
		sheet:close()
		local send = ctx.net.answer
		if send then
			send(accept)
		else
			ctx.net.send("Answer", { accept = accept })
		end
	end
	Kit.button(Words.PROMPT_JOIN, function()
		answer(true)
	end, { variant = "secondary", Name = "FoundJoin", LayoutOrder = 3, Parent = sheet.body })
	Kit.button(Words.PROMPT_KEEP, function()
		answer(false)
	end, { variant = "ghost", Name = "FoundKeep", LayoutOrder = 4, Parent = sheet.body })
	Kit.caption(Words.PROMPT_NOTE, {
		Name = "FoundNote",
		LayoutOrder = 5,
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		Parent = sheet.body,
	})

	local function follow(state: Types.State)
		local due = asked(state)
		if due == nil then
			shownFor = nil
			if open then
				open = false
				sheet:close()
				root.Visible = false
			end
			return
		end
		time.Text = Words.secondsLeft(due - ctx.now())
		if due ~= shownFor then
			shownFor = due
			if dismissed ~= due and not open then
				open = true
				root.Visible = true
				sheet:open()
			end
		end
	end

	ctx.store.get() -- the first state arrives through the subscription below
	local subscribe = (ctx.store :: any).subscribe
	if type(subscribe) == "function" then
		subscribe(follow)
	end
	local elapsed = 0
	RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		if open and shownFor then
			time.Text = Words.secondsLeft(shownFor - ctx.now())
		end
	end)
	follow(ctx.store.get())

	root.Parent = parent
	return {
		root = root,
		isOpen = function(): boolean
			return open
		end,
	}
end

return FoundPrompt
