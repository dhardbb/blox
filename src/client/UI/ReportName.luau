--!strict
-- "Report name" (docs/DESIGN.md D-069): the confirmation before a player
-- reports another player's custom candidate name. Opened from the in-match
-- Help sheet ("Report "Big Wave"") and from the Results screen's opponent
-- card, only while that player's custom name is showing. Confirming sends
-- ReportName (ctx.net.reportName): at once this player sees the candidate's
-- own name instead (this match and later ones), and the report waits for the
-- game's owners to review. Roblox offers games no call that opens its own
-- report flow, so the sheet also points to Roblox's Report in the Roblox menu.
--
-- Mounted once by App.client like LeaveMatch (ZIndex 45). Never a primary:
-- Report is the danger button, Cancel closes.
--
--   local report = ReportName.mount(parent, ctx)
--   report.open(seat)   the seat whose custom name to report (a no-op without one)
--   report.close() · report.isOpen() -> boolean
--   report.root   Frame "ReportOverlay" (Visible only while open; PrimaryOptional)
--   Elements: ReportSheet (UI/Sheet), ReportText, ReportRoblox, ReportConfirm, ReportCancel

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Words = require(ReplicatedStorage.Shared.UI.Words.Setup)

local Kit = require(script.Parent.Kit)
local Sheet = require(script.Parent.Sheet)
local Types = require(script.Parent.Parent.Screens.Types)

local ReportName = {}

local Z = 45 -- above the Help sheet (40), below the toast (50)
local HEIGHT = 0.42 -- share of a phone's screen

export type ReportName = {
	root: Frame,
	open: (seat: number) -> (),
	close: () -> (),
	isOpen: () -> boolean,
}

-- The custom name seat `seat` shows to this viewer, its setter's id and the
-- candidate's own name, or nil when there is nothing to report.
function ReportName.target(config: any, payload: any, seat: number): (string?, string?, string?)
	if payload == nil or seat == payload.you then
		return nil, nil, nil
	end
	local player = payload.view.players[seat]
	local info = payload.seats[seat]
	if player == nil or player.customName == nil or info == nil or info.kind ~= "Human" then
		return nil, nil, nil
	end
	local id = player.candidate
	local own = if id and Candidates.exists(id)
		then Candidates.profile(config, id).name
		else "the candidate's own name"
	return player.customName, info.id, own
end

function ReportName.mount(parent: Instance, ctx: Types.Ctx): ReportName
	local root = Kit.new("Frame", {
		Name = "ReportOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = Z,
		Visible = false,
	}) :: Frame
	root:SetAttribute("PrimaryOptional", true)

	local isOpen = false
	local target: string? = nil
	local function hide()
		isOpen = false
		root.Visible = false
	end
	local sheet =
		Sheet.new(root, { title = Words.REPORT_TITLE, name = "ReportSheet", height = HEIGHT, onClose = hide })
	local text = Kit.text("", {
		Name = "ReportText",
		LayoutOrder = 1,
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = sheet.body,
	})
	Kit.caption(Words.REPORT_ROBLOX, { Name = "ReportRoblox", LayoutOrder = 2, Parent = sheet.body })
	Kit.button(Words.REPORT_CONFIRM, function()
		local id = target
		sheet:close()
		hide()
		if id == nil then
			return
		end
		local send = ctx.net.reportName
		if send then
			send(id)
		else
			ctx.net.send("ReportName", { userId = id })
		end
	end, { variant = "danger", Name = "ReportConfirm", LayoutOrder = 3, Parent = sheet.body })
	Kit.button(Words.REPORT_CANCEL, function()
		sheet:close()
		hide()
	end, { variant = "ghost", Name = "ReportCancel", LayoutOrder = 4, Parent = sheet.body })

	local function open(seat: number)
		local name, id, own = ReportName.target(ctx.config, ctx.store.get().payload, seat)
		if name == nil or id == nil then
			return
		end
		target = id
		text.Text = Words.reportText(name, own :: string)
		isOpen = true
		root.Visible = true
		sheet:open()
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

return ReportName
