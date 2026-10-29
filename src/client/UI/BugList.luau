--!strict
-- The admins' bug reports (docs/DESIGN.md D-090), beside "Review names" in the
-- Lobby (the same admin pattern as UI/NameReview, D-069): "Bug reports" shows
-- when the lobby status carries `review` (the server decides who is an admin
-- and checks again on BugList). The sheet asks the server for the newest
-- reports (BugList, answered with a "Bugs" message: Store.bugs) and lists each:
-- the text as Roblox's filter let it through, then who, when (UTC), the screen,
-- the version and the match. Read only.
--
--   local bugs = BugList.new(screen, ctx, props)   props place the button
--   bugs.button   TextButton "BugsButton" (hidden for everyone but admins)
--   bugs.update(lobby, board)   the lobby status and Store's `bugs`
--   bugs.sheet    Sheet "BugsSheet"
--   Elements: BugsStatus, BugRow_<k> (BugRowText, BugRowLine)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Words = require(ReplicatedStorage.Shared.UI.Words.Lobby)

local Kit = require(script.Parent.Kit)
local Sheet = require(script.Parent.Sheet)

local BugList = {}

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

export type BugList = {
	button: TextButton,
	sheet: Sheet.Sheet,
	update: (lobby: any?, board: any?) -> (),
}

-- "Oct 28 14:05" for a unix time (UTC).
local function stamp(at: number): string
	local ok, date = pcall(function(): any
		return os.date("!*t", math.floor(at))
	end)
	if not ok or type(date) ~= "table" then
		return "?"
	end
	return string.format("%s %d %02d:%02d", MONTHS[date.month] or "?", date.day, date.hour, date.min)
end

function BugList.new(screen: Instance, ctx: any, props: { [string]: any }?): BugList
	local sheet = Sheet.new(screen, { title = Words.BUGS_TITLE, name = "BugsSheet", height = 0.8 })
	local base: { [string]: any } = {
		variant = "secondary",
		Name = "BugsButton",
		Visible = false,
	}
	local given: { [string]: any } = props or {}
	for key, value in given do
		base[key] = value
	end
	local button = Kit.button(Words.BUGS_BUTTON, function()
		ctx.net.send("BugList")
		sheet:open()
	end, base)
	local status =
		Kit.caption(Words.BUGS_LOADING, { Name = "BugsStatus", LayoutOrder = 0, Parent = sheet.body })
	local rows: { Frame } = {}

	local function fill(board: any?)
		for _, row in rows do
			row:Destroy()
		end
		rows = {}
		status.Text = if board == nil
			then Words.BUGS_LOADING
			elseif not board.ok then Words.BUGS_FAILED
			elseif #board.entries == 0 then Words.BUGS_EMPTY
			else ""
		status.Visible = status.Text ~= ""
		if board == nil then
			return
		end
		for k, entry in board.entries do
			local row = Kit.card({
				Name = `BugRow_{k}`,
				LayoutOrder = k,
				BackgroundColor3 = Kit.colors.field,
				Parent = sheet.body,
			})
			Kit.text(entry.text, {
				Name = "BugRowText",
				LayoutOrder = 1,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = row,
			})
			Kit.caption(
				Words.bugLine(entry.owner, stamp(entry.at), entry.screen, entry.version, entry.matchId),
				{
					Name = "BugRowLine",
					LayoutOrder = 2,
					Parent = row,
				}
			)
			table.insert(rows, row)
		end
	end

	local shown: any = nil
	fill(nil)
	return {
		button = button,
		sheet = sheet,
		update = function(lobby: any?, board: any?)
			local admin = lobby ~= nil and lobby.review ~= nil
			button.Visible = admin
			if not admin and sheet:isOpen() then
				sheet:close()
			end
			if board ~= shown then
				shown = board
				fill(board)
			end
		end,
	}
end

return BugList
