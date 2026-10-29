--!strict
-- The Daily Race card on the Lobby (docs/DESIGN.md D-082): today's candidate
-- (portrait and name, "Everyone plays as Goldie Pennywhistle today"), the time until
-- the next race, your streak and today's run, and two buttons: "Play today's
-- race" (op DailyRace; "Practice today's race" once today's run counts) and
-- "Today's board", a sheet with the day's top 50 by margin and "You: #N".
--
-- Reads only what the server sent (state.daily, Net/Daily.Info); asks for it
-- with ctx.net.send("Daily") when created, when the sheet opens and when the
-- day rolls over (the server reads the store at most once a minute).
--
--   local daily = DailyRace.new(screenRoot, ctx, { LayoutOrder = 5, Parent = column })
--   daily.card    Frame "DailyCard": DailyHead (Portrait, DailyTitle, DailyWho,
--                 DailyInfo), DailyButtons (DailyPlay, DailyBoard)
--   daily.sheet   the Sheet "DailySheet": DailyHow, DailyYou, DailyStatus,
--                 DailyRows (DailyRow_<rank>)
--   daily.update(info?)  from the screen's update (state.daily)
--   daily.tick(now)      the countdown (server time)
--
-- The look (D-090): a gold edge (DailyEdge) so it reads as an event, not a
-- list row; Play is featured in gold (UI/Featured); the streak line leads with
-- a flame (DailyFlame, gold while the streak runs); "Today's board" is a chip
-- (attribute Chip).
--
--   daily.setCompact(on) a phone's Lobby (0.15.0): one row, the buttons beside
--                        the head ("Play" / "Practice", "Top 50"), the title
--                        without its date, "As Goldie Pennywhistle", "5h 11m · 3-day
--                        streak"; the same names, so taps and specs still work

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local DailyNet = require(ReplicatedStorage.Shared.Net.Daily)
local Words = require(ReplicatedStorage.Shared.UI.Words.Daily)

local Featured = require(script.Parent.Featured)
local Kit = require(script.Parent.Kit)
local Leaderboard = require(script.Parent.Leaderboard)
local Sheet = require(script.Parent.Sheet)
local Types = require(script.Parent.Parent.Screens.Types)

local DailyRace = {}

local FACE = 48 -- px, today's candidate's portrait
local LINE_H = Kit.size.caption + 4 -- px, one caption line beside it
local HEAD_H = Kit.size.body + 4 + 2 * LINE_H -- px, the title and two lines beside the portrait
local SHEET_HEIGHT = 0.8 -- share of the screen height
local PLAY_SHARE = 0.6 -- the Play button's share of the button row
local COMPACT_FACE = 40 -- px, the portrait on a phone's one-row card
local COMPACT_PLAY_W = 84 -- px, "Play" / "Practice" beside the head
local COMPACT_BOARD_W = 68 -- px, "Top 50" beside it
local FLAME = LINE_H -- px, the streak's flame at the start of the info line
local EDGE = 2 -- px, the card's gold edge
local CARD_PAD = 14 -- px, Kit.card's padding (for height())

export type Daily = {
	card: Frame,
	sheet: Sheet.Sheet,
	update: (info: any?) -> (),
	tick: (now: number) -> (),
	open: () -> (),
	setCompact: (on: boolean) -> (),
	height: () -> number, -- px the card takes (its layout's own numbers; the Lobby centers its column with it, D-090)
}

-- The line for a board with no rows to show, or nil when it has some.
local function statusText(info: any?): string?
	local board = if info then info.board else nil
	if board == nil or board.status == "Loading" then
		return Words.LOADING
	end
	local entries = board.entries or {}
	if board.status == "Unavailable" and #entries == 0 then
		return Words.UNAVAILABLE
	end
	if #entries == 0 then
		return Words.EMPTY
	end
	return nil
end

function DailyRace.new(screen: Instance, ctx: Types.Ctx, props: { [string]: any }?): Daily
	local sheet = Sheet.new(screen, { title = Words.SHEET, name = "DailySheet", height = SHEET_HEIGHT })

	local cardProps: { [string]: any } = { Name = "DailyCard" }
	local given: { [string]: any } = props or {}
	for key, value in given do
		cardProps[key] = value
	end
	local card = Kit.card(cardProps)
	-- The gold edge (D-090) replaces the card's hairline.
	local hairline = card:FindFirstChild("Edge")
	if hairline then
		hairline:Destroy()
	end
	Kit.new("UIStroke", {
		Name = "DailyEdge",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Featured.INK,
		Thickness = EDGE,
		Parent = card,
	})

	-- Head: the portrait beside the title, who everyone plays, and a line with
	-- the time left, the streak and today's run.
	local head = Kit.box({
		Name = "DailyHead",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, HEAD_H),
		Parent = card,
	})
	local faceSlot = Kit.box({
		Name = "FaceSlot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(FACE, FACE),
		Parent = head,
	})
	local textX = FACE + Kit.space.sm
	local title = Kit.text(Words.TITLE, {
		Name = "DailyTitle",
		Position = UDim2.fromOffset(textX, 0),
		Size = UDim2.new(1, -textX, 0, Kit.size.body + 4),
		Font = Kit.font.display,
		TextWrapped = false,
		Parent = head,
	})
	local who = Kit.text(Words.WAITING, {
		Name = "DailyWho",
		Position = UDim2.fromOffset(textX, Kit.size.body + 4),
		Size = UDim2.new(1, -textX, 0, LINE_H),
		TextSize = Kit.size.caption,
		TextColor3 = Kit.colors.muted,
		TextWrapped = false,
		TextScaled = true,
		Parent = head,
	})
	local flame = Kit.icon("flame", FLAME, Featured.INK)
	flame.Name = "DailyFlame"
	flame.Position = UDim2.fromOffset(textX, Kit.size.body + 4 + LINE_H)
	flame.Visible = false
	flame.Parent = head
	local infoLine = Kit.text("", {
		Name = "DailyInfo",
		Position = UDim2.fromOffset(textX + FLAME + Kit.space.xs, Kit.size.body + 4 + LINE_H),
		Size = UDim2.new(1, -(textX + FLAME + Kit.space.xs), 0, LINE_H),
		TextSize = Kit.size.caption,
		TextWrapped = false,
		TextScaled = true,
		Parent = head,
	})
	local buttons = Kit.box({
		Name = "DailyButtons",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = card,
	})
	Kit.list("Horizontal", Kit.space.sm).Parent = buttons
	local play = Kit.button(Words.PLAY, function()
		ctx.net.send("DailyRace")
	end, {
		variant = "secondary",
		Name = "DailyPlay",
		LayoutOrder = 1,
		Size = UDim2.new(PLAY_SHARE, -Kit.space.sm / 2, 1, 0),
		Parent = buttons,
	})
	local function open()
		ctx.net.send("Daily")
		sheet:open()
	end
	Featured.set(play, Featured.GOLD)
	local boardButton = Kit.button(Words.BOARD, open, {
		variant = "chip",
		Name = "DailyBoard",
		LayoutOrder = 2,
		Size = UDim2.new(1 - PLAY_SHARE, -Kit.space.sm / 2, 1, 0),
		Parent = buttons,
	})
	boardButton:SetAttribute("Chip", true)
	local boardCorner = boardButton:FindFirstChildOfClass("UICorner")
	if boardCorner then
		boardCorner.CornerRadius = UDim.new(0, Kit.radius.pill)
	end

	-- The sheet: how it ranks, where you stand, then the day's top 50.
	Kit.caption(Words.HOW, { Name = "DailyHow", LayoutOrder = 1, Parent = sheet.body })
	local sheetYou = Kit.text("", {
		Name = "DailyYou",
		LayoutOrder = 2,
		Font = Kit.font.bold,
		Visible = false,
		Parent = sheet.body,
	})
	local sheetStatus = Kit.text("", {
		Name = "DailyStatus",
		LayoutOrder = 3,
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Kit.colors.muted,
		Visible = false,
		Parent = sheet.body,
	})
	local rows = Kit.stack({ Name = "DailyRows", LayoutOrder = 4, Parent = sheet.body }, "Vertical", 0)

	local shown: any? = nil
	local face: string? = nil -- the candidate whose portrait is drawn
	local compact = false -- a phone's one-row card (setCompact)
	local asked = -1 -- the day the client last asked about after it ended

	local function infoText(now: number): string
		local info = shown
		if info == nil then
			return ""
		end
		if compact then
			return `{Words.timeShort(info.endsAt - now)} · {Words.streakShort(info.streak)}`
		end
		return `{Words.timeLeft(info.endsAt - now)} · {Words.streak(info.streak)} · {Words.today(
			info.played,
			info.margin
		)}`
	end

	local function render(info: any?)
		shown = info
		if info == nil then
			who.Text = Words.WAITING
			infoLine.Text = ""
			flame.Visible = false
			play.Text = Words.PLAY
		else
			local name = if Candidates.exists(info.candidate)
				then Candidates.profile(ctx.config, info.candidate).name
				else info.candidate
			title.Text = if compact then Words.TITLE else `{Words.TITLE} · {Words.dateLabel(info.day)}`
			who.Text = if compact then Words.as(name) else Words.everyone(name)
			if compact then
				play.Text = if info.played then Words.PRACTICE_SHORT else Words.PLAY_SHORT
			else
				play.Text = if info.played then Words.PRACTICE else Words.PLAY
			end
			local facePx = if compact then COMPACT_FACE else FACE
			local faceKey = `{info.candidate}/{facePx}`
			if face ~= faceKey then
				face = faceKey
				for _, child in faceSlot:GetChildren() do
					child:Destroy()
				end
				Kit.portrait(info.candidate, name, facePx).Parent = faceSlot
			end
			infoLine.Text = infoText(ctx.now())
			local burning = (info.streak or 0) >= 1
			flame.Visible = true
			if flame:IsA("ImageLabel") then
				flame.ImageColor3 = if burning then Featured.INK else Kit.colors.muted
			elseif flame:IsA("TextLabel") then
				flame.TextColor3 = if burning then Featured.INK else Kit.colors.muted
			end
		end
		-- The sheet.
		for _, child in rows:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local problem = statusText(info)
		local board = if info then info.board else nil
		local mine = if board and board.you then board.you.rank else nil
		if board and problem == nil then
			for _, entry in board.entries or {} do
				Leaderboard.row(rows, `DailyRow_{entry.rank}`, {
					rank = entry.rank,
					name = entry.name,
					rating = DailyNet.marginText(entry.margin),
				}, entry.rank == mine)
			end
		end
		rows.Visible = problem == nil
		sheetStatus.Text = problem or ""
		sheetStatus.Visible = problem ~= nil
		sheetYou.Text = if info then Words.youLine(board and board.you, info.played, DailyNet.TOP) else ""
		sheetYou.Visible = info ~= nil and board ~= nil and board.status ~= "Loading"
	end

	local function update(info: any?)
		if info ~= shown then
			render(info)
		end
	end

	local function tick(now: number)
		local info = shown
		if info == nil then
			return
		end
		infoLine.Text = infoText(now)
		-- A new race began: ask for it once.
		if now >= info.endsAt and asked ~= info.day then
			asked = info.day
			ctx.net.send("Daily")
		end
	end

	-- A phone's Lobby: one row (the buttons move into the head, beside the text).
	local function setCompact(on: boolean)
		if on == compact then
			return
		end
		compact = on
		local facePx = if on then COMPACT_FACE else FACE
		faceSlot.Size = UDim2.fromOffset(facePx, facePx)
		local x = facePx + Kit.space.sm
		local right = if on then COMPACT_PLAY_W + COMPACT_BOARD_W + 2 * Kit.space.sm else 0
		for _, label in { title, who, infoLine } do
			local lead = if label == infoLine then FLAME + Kit.space.xs else 0
			label.Position = UDim2.fromOffset(x + lead, label.Position.Y.Offset)
			label.Size = UDim2.new(1, -(x + lead + right), 0, label.Size.Y.Offset)
		end
		flame.Position = UDim2.fromOffset(x, flame.Position.Y.Offset)
		if on then
			buttons.Parent = head
			buttons.AnchorPoint = Vector2.new(1, 0.5)
			buttons.Position = UDim2.fromScale(1, 0.5)
			buttons.Size = UDim2.fromOffset(COMPACT_PLAY_W + Kit.space.sm + COMPACT_BOARD_W, Kit.MIN_TOUCH)
			Kit.outer(play).Size = UDim2.new(0, COMPACT_PLAY_W, 1, 0)
			boardButton.Size = UDim2.new(0, COMPACT_BOARD_W, 1, 0)
			boardButton.Text = Words.BOARD_SHORT
		else
			buttons.Parent = card
			buttons.AnchorPoint = Vector2.new(0, 0)
			buttons.Position = UDim2.new()
			buttons.Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH)
			Kit.outer(play).Size = UDim2.new(PLAY_SHARE, -Kit.space.sm / 2, 1, 0)
			boardButton.Size = UDim2.new(1 - PLAY_SHARE, -Kit.space.sm / 2, 1, 0)
			boardButton.Text = Words.BOARD
		end
		render(shown)
	end

	render(nil)
	ctx.net.send("Daily")

	return {
		card = card,
		sheet = sheet,
		update = update,
		tick = tick,
		open = open,
		setCompact = setCompact,
		height = function(): number
			local inner = if compact
				then math.max(HEAD_H, Kit.MIN_TOUCH)
				else HEAD_H + Kit.space.sm + Kit.MIN_TOUCH + Kit.LIP_SECONDARY
			return inner + 2 * CARD_PAD
		end,
	}
end

return DailyRace
