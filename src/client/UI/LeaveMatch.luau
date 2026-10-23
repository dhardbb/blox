--!strict
-- "Leave match" (docs/DESIGN.md D-059): the confirmation before a player leaves
-- the match in progress. Every in-match header's "?" opens the Help sheet, and
-- its last button, "Leave match" (HelpLeave), opens this. Against a person it
-- asks "Leave and forfeit?" (it counts as a loss); against the bot "Leave this
-- practice match?". Confirming sends Forfeit (ctx.net.forfeit): the server ends
-- the match, the opponent wins by forfeit, and this player lands in the Lobby
-- (Store.leave skips the Results screen). Not offered on the Results screen,
-- whose own buttons go back to the Lobby.
--
-- Mounted once by App.client above the screens and the Help sheet, below the
-- toast (ZIndex 45). Never a primary action: Leave is the danger button, and
-- "Keep playing" closes. It closes by itself if the match ends meanwhile.
--
--   local leave = LeaveMatch.mount(parent, ctx)
--   leave.open()      only while a match is running (a no-op otherwise)
--   leave.close() · leave.isOpen() -> boolean
--   leave.root   Frame "LeaveOverlay" (Visible only while open; PrimaryOptional)
--   Elements: LeaveSheet (UI/Sheet), LeaveText, LeaveConfirm, LeaveStay;
--   attribute VsBot on the root while it asks about a practice match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Words = require(ReplicatedStorage.Shared.UI.Words.Lobby)

local Kit = require(script.Parent.Kit)
local Sheet = require(script.Parent.Sheet)
local Types = require(script.Parent.Parent.Screens.Types)

local LeaveMatch = {}

local Z = 45 -- above the Help sheet (40), below the toast (50)
local HEIGHT = 0.36 -- share of a phone's screen
local TICK = 0.25 -- s between checks that the match is still running

export type LeaveMatch = {
	root: Frame,
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
}

-- True if the match in this payload is against the bot.
function LeaveMatch.vsBot(payload: any): boolean
	if payload == nil or type(payload.seats) ~= "table" then
		return false
	end
	for p, seat in payload.seats do
		if p ~= payload.you and seat.kind == "Bot" then
			return true
		end
	end
	return false
end

function LeaveMatch.mount(parent: Instance, ctx: Types.Ctx): LeaveMatch
	local root = Kit.new("Frame", {
		Name = "LeaveOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true, -- swallows taps meant for the screen underneath
		ZIndex = Z,
		Visible = false,
	}) :: Frame
	root:SetAttribute("PrimaryOptional", true)

	local isOpen = false
	local watch: RBXScriptConnection? = nil
	local function hide()
		isOpen = false
		root.Visible = false
		if watch then
			watch:Disconnect()
			watch = nil
		end
	end

	local sheet = Sheet.new(root, {
		title = Words.LEAVE_HUMAN_TITLE,
		name = "LeaveSheet",
		height = HEIGHT,
		onClose = hide,
	})
	local text = Kit.text(Words.LEAVE_HUMAN_TEXT, {
		Name = "LeaveText",
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = sheet.body,
	})
	local confirm = Kit.button(Words.LEAVE_HUMAN_CONFIRM, function()
		local payload = ctx.store.get().payload
		sheet:close()
		if payload == nil or payload.stage == "Over" then
			return -- the match ended while the sheet was open
		end
		local forfeit = ctx.net.forfeit
		if forfeit then
			forfeit()
		else
			local leave = ctx.store.leave
			if leave then
				leave(payload.matchId)
			end
			ctx.net.send("Forfeit", { matchId = payload.matchId })
		end
	end, { variant = "danger", Name = "LeaveConfirm", LayoutOrder = 2, Parent = sheet.body })
	Kit.button(Words.LEAVE_STAY, function()
		sheet:close()
	end, { variant = "ghost", Name = "LeaveStay", LayoutOrder = 3, Parent = sheet.body })

	local function open()
		local payload = ctx.store.get().payload
		if payload == nil or payload.stage == "Over" then
			return
		end
		local bot = LeaveMatch.vsBot(payload)
		root:SetAttribute("VsBot", bot)
		sheet:setTitle(if bot then Words.LEAVE_BOT_TITLE else Words.LEAVE_HUMAN_TITLE)
		text.Text = if bot then Words.LEAVE_BOT_TEXT else Words.LEAVE_HUMAN_TEXT
		confirm.Text = if bot then Words.LEAVE_BOT_CONFIRM else Words.LEAVE_HUMAN_CONFIRM
		isOpen = true
		root.Visible = true
		sheet:open()
		if watch == nil then
			local elapsed = 0
			watch = RunService.RenderStepped:Connect(function(dt: number)
				elapsed += dt
				if elapsed < TICK then
					return
				end
				elapsed = 0
				local now = ctx.store.get().payload
				if now == nil or now.stage == "Over" or now.matchId ~= payload.matchId then
					sheet:close()
					hide()
				end
			end)
		end
	end

	root.Parent = parent
	return {
		root = root,
		open = open,
		close = function()
			sheet:close()
			hide()
		end,
		isOpen = function(): boolean
			return isOpen
		end,
	}
end

return LeaveMatch
