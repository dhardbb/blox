--!strict
-- The owners' name review (docs/DESIGN.md D-069). Admins only: the Lobby
-- shows "Review names (N)" when the lobby status carries `review` (the server
-- decides who is an admin, and checks again on every request). The sheet asks
-- the server for the queue (ReviewList) and lists each reported name: the
-- name, then "by <username> · N reports · first – last", with Keep (dismiss
-- the reports; the name stays) and Remove (clear that player's name and block
-- it and names like it). The server answers every action with a fresh list.
--
--   local review = NameReview.new(screen, ctx, props)   props place the button
--   review.button   TextButton "ReviewButton" (hidden for everyone but admins)
--   review.update(lobby, board)   the lobby status and Store's `review`
--   review.sheet    Sheet "ReviewSheet"
--   Elements: ReviewEmpty, ReviewRow_<userId> (ReviewName, ReviewLine,
--   ReviewKeep, ReviewRemove)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Words = require(ReplicatedStorage.Shared.UI.Words.Setup)

local Kit = require(script.Parent.Kit)
local Sheet = require(script.Parent.Sheet)

local NameReview = {}

local ROW_H = 96 -- px, one reported name: the name, the line, the two buttons
local ACTION_W = 0.5 -- share of the row each action takes
local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

export type NameReview = {
	button: TextButton,
	sheet: Sheet.Sheet,
	update: (lobby: any?, board: any?) -> (),
}

-- "Oct 23" for a unix time (UTC).
local function day(at: number): string
	local ok, date = pcall(function(): any
		return os.date("!*t", math.floor(at))
	end)
	if not ok or type(date) ~= "table" then
		return "?"
	end
	return `{MONTHS[date.month] or "?"} {date.day}`
end

function NameReview.new(screen: Instance, ctx: any, props: { [string]: any }?): NameReview
	local sheet = Sheet.new(screen, { title = Words.REVIEW_TITLE, name = "ReviewSheet", height = 0.7 })
	local base: { [string]: any } = {
		variant = "secondary",
		Name = "ReviewButton",
		Visible = false,
	}
	local given: { [string]: any } = props or {}
	for key, value in given do
		base[key] = value
	end
	local button = Kit.button("", function()
		ctx.net.send("ReviewList")
		sheet:open()
	end, base)
	local empty = Kit.caption("", { Name = "ReviewEmpty", LayoutOrder = 0, Parent = sheet.body })
	local rows: { Frame } = {}

	local function fill(board: any?)
		for _, row in rows do
			row:Destroy()
		end
		rows = {}
		if board == nil then
			empty.Text = ""
			return
		end
		empty.Text = if not board.ok
			then Words.REVIEW_FAILED
			elseif #board.entries == 0 then Words.REVIEW_EMPTY
			else ""
		empty.Visible = empty.Text ~= ""
		for k, entry in board.entries do
			local row = Kit.box({
				Name = `ReviewRow_{entry.userId}`,
				LayoutOrder = k,
				Size = UDim2.new(1, 0, 0, ROW_H),
				Parent = sheet.body,
			})
			Kit.text(entry.name, {
				Name = "ReviewName",
				Size = UDim2.new(1, 0, 0, Kit.size.body + 8),
				Font = Kit.font.bold,
				Parent = row,
			})
			Kit.caption(Words.reviewLine(entry.owner, entry.count, day(entry.first), day(entry.last)), {
				Name = "ReviewLine",
				AutomaticSize = Enum.AutomaticSize.None,
				Position = UDim2.fromOffset(0, Kit.size.body + 8),
				Size = UDim2.new(1, 0, 0, Kit.size.caption + 6),
				TextScaled = true,
				TextWrapped = false,
				Parent = row,
			})
			Kit.button(Words.REVIEW_KEEP, function()
				ctx.net.send("ReviewKeep", { userId = entry.userId, name = entry.name })
			end, {
				variant = "secondary",
				Name = "ReviewKeep",
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 1, -Kit.LIP_SECONDARY),
				Size = UDim2.new(ACTION_W, -Kit.space.sm / 2, 0, Kit.MIN_TOUCH),
				Parent = row,
			})
			Kit.button(Words.REVIEW_REMOVE, function()
				ctx.net.send("ReviewRemove", { userId = entry.userId, name = entry.name })
			end, {
				variant = "danger",
				Name = "ReviewRemove",
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.fromScale(1, 1),
				Size = UDim2.new(ACTION_W, -Kit.space.sm / 2, 0, Kit.MIN_TOUCH),
				Parent = row,
			})
			table.insert(rows, row)
		end
	end

	local shown: any = nil
	return {
		button = button,
		sheet = sheet,
		update = function(lobby: any?, board: any?)
			local review = if lobby then lobby.review else nil
			button.Visible = review ~= nil
			if review then
				button.Text = Words.reviewButton(review.count)
			elseif sheet:isOpen() then
				sheet:close()
			end
			if board ~= shown then
				shown = board
				fill(board)
			end
		end,
	}
end

return NameReview
