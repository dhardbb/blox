--!strict
-- A debate round's three moves (docs/DESIGN.md D-072). Each is one big button:
-- the move and its strength over three result cells against the opponent's
-- moves, a "Safe" tag on a move that cannot lose (only in the player's first
-- debate of the session, with a coach tip), then the Zinger toggle and "Why?"
-- (each move's strength in parts, what a win lands on, what losing to their
-- counter costs, and whether their Zinger is still live).
--
--   [ Defend  6 <Safe>        D +4 · A +3 · P = ]
--   [ Pivot  4                D +1 · A −1 · P +1 ]
--   [ Lands on Safety states                     ]
--   (the cells: your result against their Defend, Attack, Pivot)
--   ( Stake Zinger: win ×2 · used either way )
--   ( Why? + )
--
-- Every number comes from Shared/UI/Swing.debateBoard, from the player's own
-- View. Tapping picks a move; holding it previews its landing states on the map.
--
-- A landscape phone (D-098, moves:setCompact(true)): the three moves stand
-- side by side as tiles in one row, so all three show above the action bar
-- without scrolling (stacked they ran half a scroll down):
--
--   [ Defend 6 ] [ Attack 2 ] [ Pivot 4 ]
--   [ D+4 A+4 P=] [ D−3 A−3 P+2] [ ... ]
--   [  <Safe>  ]
--   ( Stake Zinger: win ×2 · used either way )
--
-- A tile drops the Pivot's "Lands on" line (Why? still says where it lands).
--
--   local moves = Moves.new(parent, model, pick, order)   -- pick: the screen's Pick
--   moves:render(p)
--   moves:setCompact(on)   -- tiles in a row on a landscape phone (optional for callers)
--   moves.root  Frame "DebateMoves"
--   Elements: MoveGrid (the three moves), MoveDefend / MoveAttack / MovePivot (MoveTitle*, MoveCells*,
--   MoveSafe*), Zinger, DebateWhy (WhyToggle), WhyDefend / WhyAttack / WhyPivot,
--   WhyWin*, WhyLoss*, WhyRule, WhyRivalZinger.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedTypes = require(ReplicatedStorage.Shared.Types)
local Swing = require(ReplicatedStorage.Shared.UI.Swing)
local Words = require(ReplicatedStorage.Shared.UI.Words.Debate)

local Collapsible = require(script.Parent.Parent.Parent.UI.Collapsible)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Model = require(script.Parent.Parent.CampaignParts.Model)

type Move = SharedTypes.DebateMove

local Moves = {}

local MOVES: { Move } = { "Defend", "Attack", "Pivot" }
local LINE_H = 28 -- px, a move's one line: its name and strength, then its result cells
local CELLS_W = 196 -- px, the result cells at the right of the line
local TILE_TITLE_H = 22 -- px, a tile's name and strength (D-098)
local TILE_CELLS_H = 18 -- px, a tile's result cells under it
local TILE_PAD = 6 -- px, a tile's side padding

-- What the screen and this part share about the round being answered.
export type Pick = {
	move: Move?, -- picked (nil until one is tapped; the server's default is a canned Defend)
	held: Move?, -- being held: previewed, not picked
	zinger: boolean,
	showSafe: boolean, -- tag the safe moves (the player's first debate this session)
}

type Row = {
	button: TextButton,
	line: Frame,
	left: Frame,
	title: TextLabel,
	cells: TextLabel,
	safe: TextLabel,
	lands: TextLabel, -- a Pivot's landing issue, under its line
	why: TextLabel,
	win: TextLabel,
	loss: TextLabel,
}

export type Moves = {
	root: Frame,
	render: (self: Moves, p: Model.Payload) -> (),
	-- Tiles in one row (a landscape phone, D-098). Optional for callers.
	setCompact: ((self: Moves, on: boolean) -> ())?,
}

function Moves.new(parent: Instance, model: Model.Model, pick: Pick, order: number): Moves
	local config = model.config
	local root = Kit.box({
		Name = "DebateMoves",
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Kit.list("Vertical", Kit.space.sm).Parent = root

	local function held(input: InputObject): boolean
		local kind = input.UserInputType.Name
		return kind == "MouseButton1" or kind == "Touch"
	end

	local rows: { [string]: Row } = {}
	-- The three moves: stacked, or tiles in a row on a landscape phone.
	local grid = Kit.box({
		Name = "MoveGrid",
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	local gridList = Kit.list("Vertical", Kit.space.sm)
	gridList.Parent = grid
	local compact = false
	local why = Collapsible.new(root, { title = "Why?", name = "DebateWhy", order = 10 })
	why.toggle.Name = "WhyToggle"
	for k = 1, #MOVES do
		local move: Move = MOVES[k]
		local button: TextButton
		button = Kit.cardButton(function()
			local p = model.payload
			if button.Active == false or p == nil or not Model.editable(model, p) then
				return
			end
			pick.move = move
			pick.held = nil
			model.render()
		end, { Name = `Move{move}`, LayoutOrder = k, Parent = grid })
		-- Tighter than a card's usual padding: three moves must fit above the bar on a phone.
		local pad = button:FindFirstChildOfClass("UIPadding")
		if pad then
			pad.PaddingTop = UDim.new(0, Kit.space.sm)
			pad.PaddingBottom = UDim.new(0, Kit.space.sm)
		end
		-- One line: the move and its strength (and the Safe tag) on the left, the
		-- three result cells on the right.
		local line = Kit.box({
			Name = `MoveLine{move}`,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, LINE_H),
			Parent = button,
		})
		local left = Kit.box({ Name = `MoveLeft{move}`, Size = UDim2.new(1, -CELLS_W, 1, 0), Parent = line })
		local leftList = Kit.list("Horizontal", Kit.space.xs)
		leftList.VerticalAlignment = Enum.VerticalAlignment.Center
		leftList.Parent = left
		local title = Kit.text("", {
			Name = `MoveTitle{move}`,
			LayoutOrder = 1,
			Size = UDim2.fromOffset(0, LINE_H),
			AutomaticSize = Enum.AutomaticSize.X,
			Font = Kit.font.bold,
			TextSize = Kit.size.heading,
			TextWrapped = false,
			Parent = left,
		})
		local safe = Kit.pill(
			"Safe",
			"good",
			{ Name = `MoveSafe{move}`, LayoutOrder = 2, Visible = false, Parent = left }
		)
		local lands = Kit.caption("", {
			Name = `MoveLands{move}`,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 18),
			TextWrapped = false,
			Visible = false,
			Parent = button,
		})
		local cells = Kit.caption("", {
			Name = `MoveCells{move}`,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.new(0, CELLS_W, 1, 0),
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Kit.colors.text,
			Parent = line,
		})
		-- A tile's cells shrink a little rather than clip (D-098; never below 12 px).
		Kit.new("UITextSizeConstraint", {
			MaxTextSize = Kit.size.caption,
			MinTextSize = Kit.MIN_TEXT,
			Parent = cells,
		})
		-- Holding previews; the preview ends however the hold does: released on
		-- the button (InputEnded), the mouse moved off it (MouseLeave), or the
		-- press ended or was cancelled anywhere (the same InputObject is updated
		-- until its input ends: InputObject, Changed).
		local function release()
			if pick.held == move then
				pick.held = nil
				model.render()
			end
		end
		button.InputBegan:Connect(function(input: InputObject)
			if held(input) and pick.held ~= move then
				pick.held = move
				model.render()
				local changed = (input :: any).Changed
				if changed == nil then
					return
				end
				local connection: RBXScriptConnection
				connection = changed:Connect(function(property: string)
					local state = if property == "UserInputState" then input.UserInputState.Name else nil
					if state == "End" or state == "Cancel" then
						connection:Disconnect()
						release()
					end
				end)
			end
		end)
		button.InputEnded:Connect(function(input: InputObject)
			if held(input) then
				release()
			end
		end)
		button.MouseLeave:Connect(release)
		local whyLine = Kit.caption("", {
			Name = `Why{move}`,
			LayoutOrder = 3 * k,
			TextColor3 = Kit.colors.text,
			Parent = why.body,
		})
		local winLine = Kit.caption("", { Name = `WhyWin{move}`, LayoutOrder = 3 * k + 1, Parent = why.body })
		local lossLine =
			Kit.caption("", { Name = `WhyLoss{move}`, LayoutOrder = 3 * k + 2, Parent = why.body })
		rows[move] = {
			button = button,
			line = line,
			left = left,
			title = title,
			cells = cells,
			safe = safe,
			lands = lands,
			why = whyLine,
			win = winLine,
			loss = lossLine,
		}
	end
	local rule = Kit.caption("", { Name = "WhyRule", LayoutOrder = 100, Parent = why.body })
	local rivalZinger = Kit.caption("", {
		Name = "WhyRivalZinger",
		LayoutOrder = 101,
		TextColor3 = Kit.colors.text,
		Visible = false,
		Parent = why.body,
	})

	local zinger: TextButton
	zinger = Kit.chip("", function()
		local p = model.payload
		if zinger.Active == false or p == nil or not Model.editable(model, p) then
			return
		end
		pick.zinger = not pick.zinger
		model.render()
	end, { Name = "Zinger", LayoutOrder = 5, Parent = root })

	-- Stacked rows, or tiles in a row (D-098).
	local function setCompact(_self: Moves, on: boolean)
		if on == compact then
			return
		end
		compact = on
		gridList.FillDirection = if on then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		gridList.Padding = UDim.new(0, if on then Kit.space.xs else Kit.space.sm)
		local gap = Kit.space.xs * (#MOVES - 1) / #MOVES
		for _, row in rows do
			local button = row.button
			button.Size = if on then UDim2.new(1 / #MOVES, -gap, 0, 0) else UDim2.fromScale(1, 0)
			local pad = button:FindFirstChildOfClass("UIPadding")
			if pad then
				local side = UDim.new(0, if on then TILE_PAD else Kit.space.md)
				pad.PaddingLeft, pad.PaddingRight = side, side
			end
			row.line.Size = UDim2.new(1, 0, 0, if on then TILE_TITLE_H + TILE_CELLS_H else LINE_H)
			row.left.Size = if on then UDim2.new(1, 0, 0, TILE_TITLE_H) else UDim2.new(1, -CELLS_W, 1, 0)
			row.title.Size = UDim2.fromOffset(0, if on then TILE_TITLE_H else LINE_H)
			row.title.TextSize = if on then Kit.size.body else Kit.size.heading
			-- The Safe tag on a row of its own under a tile's cells.
			row.safe.Parent = if on then button else row.left
			row.safe.LayoutOrder = if on then 3 else 2
			row.cells.AnchorPoint = if on then Vector2.new(0, 1) else Vector2.new(1, 0.5)
			row.cells.Position = if on then UDim2.fromScale(0, 1) else UDim2.fromScale(1, 0.5)
			row.cells.Size = if on then UDim2.new(1, 0, 0, TILE_CELLS_H) else UDim2.new(0, CELLS_W, 1, 0)
			row.cells.TextXAlignment = if on then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
			row.cells.TextScaled = on
		end
		model.render()
	end

	local part: Moves = {
		root = root,
		setCompact = setCompact,
		render = function(_self: Moves, p: Model.Payload)
			local board = Swing.debateBoard(config, p.view)
			root.Visible = board ~= nil and Model.debating(p)
			if board == nil or not root.Visible then
				return
			end
			local canEdit = Model.editable(model, p)
			for k = 1, #MOVES do
				local move: Move = MOVES[k]
				local row = rows[move]
				local info = board.rows[k]
				row.title.Text = Words.moveTitle(info)
				row.lands.Visible = info.landing ~= board.topic and not compact
				row.lands.Text = `Lands on {Model.issueName(info.landing)} states`
				row.cells.Text = if compact then Words.cellsShort(info) else Words.cells(info)
				row.safe.Visible = pick.showSafe and info.safe
				row.why.Text = Words.parts(info)
				row.win.Text = info.winLine
				row.loss.Text = info.lossLine
				Kit.setSelected(row.button, pick.move == move)
				Kit.setEnabled(row.button, canEdit)
			end
			-- Tiles share one height, the Safe tag's row included when any shows.
			local anySafe = false
			for k = 1, #MOVES do
				anySafe = anySafe or rows[MOVES[k]].safe.Visible
			end
			local tileH = 2 * Kit.space.sm
				+ TILE_TITLE_H
				+ TILE_CELLS_H
				+ (if anySafe then Kit.space.xs + Kit.PILL_H else 0)
			for _, row in rows do
				row.button.AutomaticSize = if compact then Enum.AutomaticSize.None else Enum.AutomaticSize.Y
				local width = row.button.Size.X
				row.button.Size = UDim2.new(width.Scale, width.Offset, 0, if compact then tileH else 0)
			end
			if board.zingers <= 0 then
				pick.zinger = false
			end
			zinger.Text = Words.zinger(board, pick.zinger)
			Kit.setSelected(zinger, pick.zinger)
			Kit.setEnabled(zinger, canEdit and board.zingers > 0)
			rule.Text =
				`Defend beats Attack, Attack beats Pivot, Pivot beats Defend (+{board.counter} this round). Higher score wins the round; equal is a split. Same move as last round: -{config.DEBATE_REPEAT}.`
			local theirLine = Words.rivalZinger(board, Model.firstName(config, p.view, board.rival))
			rivalZinger.Visible = theirLine ~= nil
			rivalZinger.Text = theirLine or ""
		end,
	}
	return part
end

return Moves
