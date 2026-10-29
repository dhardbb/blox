--!strict
-- "Opponent found! Leave this bot game?" (docs/DESIGN.md D-083). A player who
-- plays the bot while waiting in the queue keeps their place in line; when an
-- opponent is found the server asks them (LobbyStatus.found.phase "Answer",
-- due at found.untilAt, Config.QUEUE_ACCEPT_SECONDS after it was asked).
-- "Join match" ends the bot game (unrated, nothing saved) and starts the
-- match; "Keep playing" keeps the bot game and leaves the queue, and the other
-- player goes back to the front of the line. No answer in time counts as
-- Keep playing.
--
-- The look (D-090): the opponent's Roblox headshot and display name on top
-- (when the server knows them: found.opponent), "Join match" as the main
-- button (UI/Featured), a bar that shrinks as the answer comes due, and no ×:
-- the two buttons are the only ways out (the scrim does not close it either).
--
-- Mounted once by App.client above the screens (ZIndex 45, like LeaveMatch),
-- so it shows over whichever match screen the bot game is on.
--
--   local prompt = FoundPrompt.mount(parent, ctx)
--   prompt.root   Frame "FoundOverlay" (Visible only while open; PrimaryOptional)
--   Elements: FoundSheet (UI/Sheet), FoundWho (FoundFace, FoundName),
--   FoundText, FoundBar (FoundBarFill), FoundTime, FoundNote, FoundJoin, FoundKeep.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Words = require(ReplicatedStorage.Shared.UI.Words.Matchmaking)

local Config = require(ReplicatedStorage.Shared.Sim.Config)

local Featured = require(script.Parent.Featured)
local Kit = require(script.Parent.Kit)
local Sheet = require(script.Parent.Sheet)
local Types = require(script.Parent.Parent.Screens.Types)

local FoundPrompt = {}

local Z = 45 -- above the Help sheet (40), below the toast (50)
local HEIGHT = 0.42 -- share of a phone's screen
local TICK = 0.25 -- s between countdown updates
local FACE = 48 -- px, the opponent's headshot
local BAR_H = 6 -- px, the countdown bar
local HEADSHOT = "rbxthumb://type=AvatarHeadShot&id=%s&w=150&h=150" -- the documented thumbnail URL (Content: rbxthumb)

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
	local open = false

	local sheet = Sheet.new(root, {
		title = Words.PROMPT_TITLE,
		name = "FoundSheet",
		height = HEIGHT,
		closable = false,
		onClose = function()
			open = false
			root.Visible = false
		end,
	})
	-- Who was found: their headshot and display name.
	local who = Kit.box({
		Name = "FoundWho",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, FACE),
		Visible = false,
		Parent = sheet.body,
	})
	local face = Kit.new("ImageLabel", {
		Name = "FoundFace",
		Size = UDim2.fromOffset(FACE, FACE),
		BackgroundColor3 = Kit.colors.raised,
		BorderSizePixel = 0,
		Image = "",
		ScaleType = Enum.ScaleType.Fit,
		Parent = who,
	}) :: ImageLabel
	Kit.round().Parent = face
	local name = Kit.heading("", {
		Name = "FoundName",
		Position = UDim2.fromOffset(FACE + Kit.space.md, 0),
		Size = UDim2.new(1, -(FACE + Kit.space.md), 1, 0),
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = who,
	})
	Kit.text(Words.PROMPT_TEXT, {
		Name = "FoundText",
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = sheet.body,
	})
	-- The time left as a bar that shrinks to nothing, over the seconds.
	local bar = Kit.new("Frame", {
		Name = "FoundBar",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, BAR_H),
		BackgroundColor3 = Kit.colors.field,
		BorderSizePixel = 0,
		Parent = sheet.body,
	}) :: Frame
	Kit.corner(Kit.radius.pill).Parent = bar
	local fill = Kit.new("Frame", {
		Name = "FoundBarFill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.colors.accent,
		BorderSizePixel = 0,
		Parent = bar,
	}) :: Frame
	Kit.corner(Kit.radius.pill).Parent = fill
	local time = Kit.text("", {
		Name = "FoundTime",
		LayoutOrder = 3,
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
	local join = Kit.button(Words.PROMPT_JOIN, function()
		answer(true)
	end, { variant = "secondary", Name = "FoundJoin", LayoutOrder = 4, Parent = sheet.body })
	Featured.set(join, Kit.colors.accent)
	Kit.button(Words.PROMPT_KEEP, function()
		answer(false)
	end, { variant = "ghost", Name = "FoundKeep", LayoutOrder = 5, Parent = sheet.body })
	Kit.caption(Words.PROMPT_NOTE, {
		Name = "FoundNote",
		LayoutOrder = 6,
		AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true,
		Parent = sheet.body,
	})

	-- The countdown: the line and the bar.
	local function paintTime(due: number)
		local left = due - ctx.now()
		time.Text = Words.secondsLeft(left)
		local share = math.clamp(left / Config.defaults.QUEUE_ACCEPT_SECONDS, 0, 1)
		fill.Size = UDim2.fromScale(share, 1)
		fill.Visible = share > 0
	end

	local function paintWho(state: Types.State)
		local lobby = state.lobby
		local found = if lobby then lobby.found else nil
		local opponent = if found then found.opponent else nil
		local known = type(opponent) == "table"
			and type(opponent.userId) == "string"
			and string.match(opponent.userId, "^%d+$") ~= nil
			and type(opponent.name) == "string"
		who.Visible = known
		if known then
			face.Image = string.format(HEADSHOT, opponent.userId)
			name.Text = opponent.name
		end
	end

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
		paintWho(state)
		paintTime(due)
		if due ~= shownFor then
			shownFor = due
			if not open then
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
		local due = shownFor
		if open and due then
			paintTime(due)
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
