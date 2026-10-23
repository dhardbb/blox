--!strict
-- The global leaderboard on the Lobby (docs/DESIGN.md D-059): a card with the
-- best players by rating (rank, name, rating; the viewer's own row raised and
-- bold) and "See all", which opens a sheet with the top 50. Under the list,
-- where the viewer stands: "You: #4 · 1444", "You: not in the top 50 · 1004",
-- or how to get ranked. Before the first answer it says it is loading; if the
-- server can't read the board and has no earlier list, "Leaderboard
-- unavailable"; with nobody ranked yet, how to get on it.
--
-- The screen decides how many rows the card shows (setRows): the top 10 beside
-- the Lobby's column on a wide screen, the top 3 inside it on a phone. Reads
-- only the board the server sent (state.leaderboard); asks for it with
-- ctx.net.send("Leaderboard") when created and when the sheet opens (the server
-- answers from its cache and reads the store at most once a minute).
--
--   local board = Leaderboard.new(screenRoot, ctx)
--   board.card    Frame "LeaderboardCard": LeaderboardTitle, LeaderboardSeeAll,
--                 LeaderboardRows (Row_<rank>, attribute You on the viewer's),
--                 LeaderboardStatus, LeaderboardYou
--   board.sheet   the Sheet "LeaderboardSheet": SheetHow, SheetYou, SheetStatus,
--                 SheetRows (SheetRow_<rank>)
--   board.update(board?)   from the screen's update (state.leaderboard)
--   board.setRows(n)       rows on the card
--   board.open()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeaderboardNet = require(ReplicatedStorage.Shared.Net.Leaderboard)
local Words = require(ReplicatedStorage.Shared.UI.Words.Lobby)

local Kit = require(script.Parent.Kit)
local Sheet = require(script.Parent.Sheet)
local Types = require(script.Parent.Parent.Screens.Types)

local Leaderboard = {}

Leaderboard.SHORT = LeaderboardNet.SHORT -- rows beside the Lobby's column on a tall screen
Leaderboard.COMPACT = LeaderboardNet.COMPACT -- rows on a phone or a short screen

local ROW_H = 32 -- px, one entry
local RANK_W = 44 -- px, "#50"
local RATING_W = 56 -- px, "1480"
local SEE_ALL_W = 96 -- px
local SHEET_HEIGHT = 0.8 -- share of the screen height

export type Board = {
	card: Frame,
	sheet: Sheet.Sheet,
	update: (board: any?) -> (),
	setRows: (n: number) -> (),
	open: () -> (),
}

-- One entry: "#3", the name (shrinks to fit), the rating. Raised and bold when
-- it is the viewer's.
local function entryRow(parent: Instance, name: string, entry: any, mine: boolean): Frame
	local line = Kit.box({
		Name = name,
		LayoutOrder = entry.rank,
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundTransparency = if mine then 0 else 1,
		BackgroundColor3 = Kit.colors.raised,
		Parent = parent,
	})
	line:SetAttribute("You", mine)
	if mine then
		Kit.corner(Kit.radius.control).Parent = line
	end
	local font = if mine then Kit.font.bold else Kit.font.body
	Kit.text(`#{entry.rank}`, {
		Name = "Rank",
		Position = UDim2.fromOffset(Kit.space.xs, 0),
		Size = UDim2.new(0, RANK_W, 1, 0),
		Font = if mine then Kit.font.bold else Kit.font.medium,
		TextColor3 = if mine then Kit.colors.text else Kit.colors.muted,
		TextWrapped = false,
		Parent = line,
	})
	Kit.text(tostring(entry.name), {
		Name = "Name",
		Position = UDim2.fromOffset(Kit.space.xs + RANK_W, 0),
		Size = UDim2.new(1, -(2 * Kit.space.xs + RANK_W + RATING_W), 1, 0),
		Font = font,
		TextScaled = true,
		TextWrapped = false,
		Parent = line,
	})
	Kit.text(tostring(entry.rating), {
		Name = "Rating",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Kit.space.xs, 0, 0),
		Size = UDim2.new(0, RATING_W, 1, 0),
		Font = Kit.font.bold,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = line,
	})
	return line
end

-- The line for a board with no rows to show, or nil when it has some.
local function statusText(board: any?): string?
	if board == nil or board.status == "Loading" then
		return Words.BOARD_LOADING
	end
	local entries = board.entries or {}
	if board.status == "Unavailable" and #entries == 0 then
		return Words.BOARD_UNAVAILABLE
	end
	if #entries == 0 then
		return Words.BOARD_EMPTY
	end
	return nil
end

function Leaderboard.new(screen: Instance, ctx: Types.Ctx): Board
	local sheet =
		Sheet.new(screen, { title = Words.BOARD_SHEET, name = "LeaderboardSheet", height = SHEET_HEIGHT })

	local card = Kit.card({ Name = "LeaderboardCard" })
	local head = Kit.box({
		Name = "LeaderboardHead",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = card,
	})
	Kit.text(Words.BOARD_TITLE, {
		Name = "LeaderboardTitle",
		Size = UDim2.new(1, -(SEE_ALL_W + Kit.space.sm), 1, 0),
		Font = Kit.font.bold,
		TextWrapped = false,
		Parent = head,
	})
	local function open()
		ctx.net.send("Leaderboard")
		sheet:open()
	end
	Kit.button(Words.BOARD_SEE_ALL, open, {
		variant = "ghost",
		Name = "LeaderboardSeeAll",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, SEE_ALL_W, 1, 0),
		Parent = head,
	})
	local rowsBox = Kit.stack({ Name = "LeaderboardRows", LayoutOrder = 2, Parent = card }, "Vertical", 0)
	local status = Kit.caption("", {
		Name = "LeaderboardStatus",
		LayoutOrder = 3,
		Visible = false,
		Parent = card,
	})
	local you = Kit.caption("", {
		Name = "LeaderboardYou",
		LayoutOrder = 4,
		TextColor3 = Kit.colors.text,
		Visible = false,
		Parent = card,
	})

	-- The sheet: how it ranks, where you stand, then the top 50.
	Kit.caption(Words.BOARD_HOW, { Name = "SheetHow", LayoutOrder = 1, Parent = sheet.body })
	local sheetYou = Kit.text("", {
		Name = "SheetYou",
		LayoutOrder = 2,
		Font = Kit.font.bold,
		Visible = false,
		Parent = sheet.body,
	})
	local sheetStatus = Kit.text("", {
		Name = "SheetStatus",
		LayoutOrder = 3,
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Kit.colors.muted,
		Visible = false,
		Parent = sheet.body,
	})
	local sheetRows = Kit.stack({ Name = "SheetRows", LayoutOrder = 4, Parent = sheet.body }, "Vertical", 0)

	local shown: any? = nil -- the board drawn last
	local rows = LeaderboardNet.COMPACT
	local drawnRows = -1

	local function fill(box: Frame, prefix: string, board: any?, limit: number)
		for _, child in box:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		if board == nil then
			return
		end
		local mine = if board.you then board.you.rank else nil
		for k, entry in board.entries or {} do
			if k > limit then
				break
			end
			entryRow(box, `{prefix}{entry.rank}`, entry, entry.rank == mine)
		end
	end

	local function render(board: any?)
		shown = board
		drawnRows = rows
		local problem = statusText(board)
		fill(rowsBox, "Row_", board, rows)
		fill(sheetRows, "SheetRow_", board, LeaderboardNet.TOP)
		rowsBox.Visible = problem == nil
		status.Text = problem or ""
		status.Visible = problem ~= nil
		sheetStatus.Text = problem or ""
		sheetStatus.Visible = problem ~= nil
		-- Nobody listed and the viewer unranked: the status line already says it all.
		local ready = board ~= nil
			and board.status ~= "Loading"
			and not (board.you == nil and #(board.entries or {}) == 0)
		local line = if board then Words.youLine(board.you, LeaderboardNet.TOP) else ""
		you.Text = line
		you.Visible = ready
		sheetYou.Text = line
		sheetYou.Visible = ready
	end

	local function update(board: any?)
		if board ~= shown or rows ~= drawnRows then
			render(board)
		end
	end
	render(nil)
	ctx.net.send("Leaderboard")

	return {
		card = card,
		sheet = sheet,
		update = update,
		setRows = function(n: number)
			rows = n
			update(shown)
		end,
		open = open,
	}
end

return Leaderboard
