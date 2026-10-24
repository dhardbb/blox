--!strict
-- Results' Graph tab (docs/DESIGN.md D-073): both players' projected votes week
-- by week, from the public polls (the header's numbers), then election night's
-- real count. Roblox has no chart widget, so the chart is plain Frames placed
-- where Shared/UI/EVChart says: each line piece a thin Frame turned about its
-- center (GuiObject.Rotation), each point a round Frame.
--
--   GraphTab.new(parent, order) -> Tab
--   tab:set(payload, names)      the match to show
--   tab:layout(width, height)    redraws the chart for the column's width and the room left
--
-- One card ("GraphCard"):
--   GraphTitle   "Votes in the polls, by week"
--   Legend       a dot in each player's color and their name (you first), and
--                the 270 line
--   Chart        (a data-colored box) the marker row (44 px: a "D" or "S" chip
--                over each debate or stance week, Marker_<week>_<kind>, each a
--                44 px tap target), the plot (gridlines with their numbers, the
--                white 270 line, Line_<p>_<k> pieces and Dot_<p>_<k> points;
--                the result's points bigger and ringed in white, set a little
--                apart), then the x labels (Start, weeks, Result) that fit
--   ChartNote    the tapped marker's week ("Week 4 · Debate: you won 2 of 3
--                topics"), else how to read the markers
--   ChartSummary "You: 238 at the start, 290 in the final polls, 302 on election night."
-- Sized so the whole card fits the screen without scrolling.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVChart = require(ReplicatedStorage.Shared.UI.EVChart)
local Session = require(ReplicatedStorage.Shared.Net.Session)

local Kit = require(script.Parent.Parent.Parent.UI.Kit)

local GraphTab = {}

local WIN_EV = 270
local AXIS_W = 34 -- px, the y numbers' column
local RIGHT_PAD = 6 -- px right of the plot
local MARKER_ROW = Kit.MIN_TOUCH -- px, the debate and stance chips over the plot
local MARKER = 22 -- px, one marker chip
local LABEL_ROW = Kit.size.caption + 8 -- px, the x labels under the plot
local LINE_PX = 3 -- px, a series line's thickness
local DOT = 8 -- px, a week's point
local RESULT_DOT = 14 -- px, the result's point
local CHAR_PX = 8 -- px, a caption character's width, for fitting the x labels
local PLOT_MIN, PLOT_MAX = 150, 250 -- px, the plot's height
local GUIDE = 0.6 -- the transparency of a marker's guide line down the plot
local GRID = 0.6 -- the transparency of a gridline
local NOTE_H = 2 * (Kit.size.caption + 4) -- px, the note keeps room for two lines, so a tap never moves the card
local SUMMARY_H = 2 * (Kit.size.body + 6) -- px, the summary's room (two lines on a phone)
-- px of the card around the chart: its padding, title, legend, note, summary and
-- the gaps between them, and the column's bottom padding.
local CARD_EXTRA = 2 * 14
	+ (Kit.size.heading + 6)
	+ (Kit.size.caption + 6)
	+ NOTE_H
	+ SUMMARY_H
	+ 5 * Kit.space.sm
	+ Kit.space.md
local HINT = "Tap D (debate) or S (stance vote) to see that week."

export type Tab = {
	root: Frame,
	set: (self: Tab, payload: Session.StatePayload, names: { string }) -> (),
	show: (self: Tab, visible: boolean) -> (),
	layout: (self: Tab, width: number, height: number) -> (),
}

local function round(inst: GuiObject)
	Kit.round().Parent = inst
end

function GraphTab.new(parent: Instance, order: number): Tab
	local root = Kit.stack(
		{ Name = "GraphTab", LayoutOrder = order, Visible = false, Parent = parent },
		"Vertical",
		Kit.space.sm
	)
	local card =
		Kit.card({ Name = "GraphCard", LayoutOrder = 1, Size = UDim2.fromScale(1, 0), Parent = root })
	Kit.text("Votes in the polls, by week", {
		Name = "GraphTitle",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, Kit.size.heading + 6),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.bold,
		TextSize = Kit.size.heading,
		Parent = card,
	})
	local legend = Kit.box({
		Name = "Legend",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, Kit.size.caption + 6),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})
	local legendList = Kit.list("Horizontal", Kit.space.md)
	legendList.Wraps = true
	legendList.VerticalAlignment = Enum.VerticalAlignment.Center
	legendList.Parent = legend
	local chart = Kit.dataColor(Kit.box({
		Name = "Chart",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, MARKER_ROW + PLOT_MIN + LABEL_ROW),
		Parent = card,
	}))
	local note = Kit.caption(HINT, {
		Name = "ChartNote",
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, NOTE_H),
		Parent = card,
	})
	local summary = Kit.text("", {
		Name = "ChartSummary",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, Kit.size.body + 6),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.medium,
		Parent = card,
	})

	local current: Session.StatePayload? = nil
	local names: { string } = {}
	local points: { EVChart.Point } = {}
	local markers: { EVChart.Marker } = {}
	local picked: string? = nil -- the tapped marker's button name
	local drawnFor = "" -- the width x height the chart was last drawn for
	local width, height = 0, 0
	local markerButtons: { [string]: TextButton } = {}
	local markerLines: { [string]: string } = {}

	local function seats(view: any, you: number): { number }
		local out = { you }
		for p = 1, #view.players do
			if p ~= you then
				table.insert(out, p)
			end
		end
		return out
	end

	local function fillLegend()
		for _, child in legend:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local payload = current
		if payload == nil then
			return
		end
		local view = payload.view
		local function item(name: string, k: number, swatch: GuiObject, text: string)
			local row = Kit.box({
				Name = name,
				LayoutOrder = k,
				Size = UDim2.fromOffset(0, Kit.size.caption + 6),
				AutomaticSize = Enum.AutomaticSize.X,
				Parent = legend,
			})
			local list = Kit.list("Horizontal", Kit.space.xs)
			list.VerticalAlignment = Enum.VerticalAlignment.Center
			list.Parent = row
			swatch.LayoutOrder = 1
			swatch.Parent = row
			Kit.text(text, {
				Name = "Text",
				LayoutOrder = 2,
				Size = UDim2.fromOffset(0, Kit.size.caption + 6),
				AutomaticSize = Enum.AutomaticSize.X,
				TextWrapped = false,
				TextSize = Kit.size.caption,
				Parent = row,
			})
		end
		for k, p in seats(view, payload.you) do
			local dot = Kit.box({
				Name = "Swatch",
				Size = UDim2.fromOffset(12, 12),
				BackgroundTransparency = 0,
				BackgroundColor3 = Kit.playerColor(view, p),
			})
			round(dot)
			local who = if p == payload.you then `You · {names[p] or "you"}` else (names[p] or `Player {p}`)
			item(`Legend_{p}`, k, Kit.dataColor(dot), who)
		end
		local tick = Kit.box({
			Name = "Swatch",
			Size = UDim2.fromOffset(16, 2),
			BackgroundTransparency = 0,
			BackgroundColor3 = Kit.colors.text,
		})
		item("Legend_270", #view.players + 1, tick, `{WIN_EV} to win`)
	end

	local function showNote()
		local line = if picked then markerLines[picked] else nil
		note.Text = line or HINT
		note.TextColor3 = if line then Kit.colors.text else Kit.colors.muted
		for name, button in markerButtons do
			local chip = button:FindFirstChild("Chip") :: Frame?
			local stroke = if chip then chip:FindFirstChildOfClass("UIStroke") else nil
			if stroke then
				stroke.Color = if name == picked then Kit.colors.accent else Kit.colors.line
				stroke.Thickness = if name == picked then 2 else 1
			end
		end
	end

	local function draw()
		for _, child in chart:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		markerButtons = {}
		markerLines = {}
		local payload = current
		if payload == nil or #points == 0 or width <= AXIS_W + RIGHT_PAD then
			return
		end
		local view = payload.view
		local plotW = width - AXIS_W - RIGHT_PAD
		local plotH = math.clamp(height - CARD_EXTRA - MARKER_ROW - LABEL_ROW, PLOT_MIN, PLOT_MAX)
		chart.Size = UDim2.new(1, 0, 0, MARKER_ROW + plotH + LABEL_ROW)
		local plot = Kit.box({
			Name = "Plot",
			Position = UDim2.fromOffset(AXIS_W, MARKER_ROW),
			Size = UDim2.fromOffset(plotW, plotH),
			BackgroundTransparency = 0,
			BackgroundColor3 = Kit.colors.field,
			Parent = chart,
		})
		Kit.corner(Kit.radius.control).Parent = plot
		local lo, hi, step = EVChart.range(points, WIN_EV)
		local xs = EVChart.xs(points, plotW)
		local function yOf(value: number): number
			return EVChart.y(value, lo, hi, plotH)
		end

		-- Gridlines and their numbers (a number too close to the 270 line gives way to it).
		local markY = yOf(WIN_EV)
		local v = lo
		while v <= hi do
			local y = yOf(v)
			Kit.box({
				Name = `Grid_{v}`,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(0, y),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundTransparency = GRID,
				BackgroundColor3 = Kit.colors.line,
				Parent = plot,
			})
			if math.abs(y - markY) >= Kit.size.caption then
				Kit.text(tostring(v), {
					Name = `YLabel_{v}`,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.fromOffset(
						0,
						MARKER_ROW + math.clamp(y, Kit.size.caption / 2, plotH - Kit.size.caption / 2)
					),
					Size = UDim2.fromOffset(AXIS_W - Kit.space.xs, Kit.size.caption + 2),
					TextSize = Kit.size.caption,
					TextWrapped = false,
					TextColor3 = Kit.colors.muted,
					TextXAlignment = Enum.TextXAlignment.Right,
					Parent = chart,
				})
			end
			v += step
		end
		-- The 270 line: a plain white tick across the plot, its number in white.
		Kit.box({
			Name = "Line270",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(0, markY),
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundTransparency = 0,
			BackgroundColor3 = Kit.colors.text,
			ZIndex = 2,
			Parent = plot,
		})
		Kit.text(tostring(WIN_EV), {
			Name = "YLabel_270",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(0, MARKER_ROW + markY),
			Size = UDim2.fromOffset(AXIS_W - Kit.space.xs, Kit.size.caption + 2),
			Font = Kit.font.bold,
			TextSize = Kit.size.caption,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = chart,
		})

		-- Markers: a chip over each debate or stance week and a faint guide down the plot.
		local xOfWeek: { [number]: number } = {}
		for i, point in points do
			if point.week ~= nil then
				xOfWeek[point.week] = xs[i]
			end
		end
		for _, marker in markers do
			local x = xOfWeek[marker.week]
			if x ~= nil then
				local name = `Marker_{marker.week}_{marker.kind}`
				Kit.box({
					Name = `Guide_{marker.week}_{marker.kind}`,
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromOffset(x, 0),
					Size = UDim2.new(0, 1, 1, 0),
					BackgroundTransparency = GUIDE,
					BackgroundColor3 = Kit.colors.muted,
					Parent = plot,
				})
				local cx = math.clamp(AXIS_W + x, Kit.MIN_TOUCH / 2, width - Kit.MIN_TOUCH / 2)
				local button = Kit.new("TextButton", {
					Name = name,
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromOffset(cx, 0),
					Size = UDim2.fromOffset(Kit.MIN_TOUCH, MARKER_ROW),
					BackgroundTransparency = 1,
					Text = "",
					AutoButtonColor = false,
					ZIndex = 3,
					Parent = chart,
				}) :: TextButton
				local chip = Kit.box({
					Name = "Chip",
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0.5, AXIS_W + x - cx, 0.5, 0),
					Size = UDim2.fromOffset(MARKER, MARKER),
					BackgroundTransparency = 0,
					BackgroundColor3 = Kit.colors.raised,
					ZIndex = 3,
					Parent = button,
				})
				round(chip)
				Kit.stroke(Kit.colors.line, 1).Parent = chip
				Kit.text(marker.letter, {
					Name = "Letter",
					Size = UDim2.fromScale(1, 1),
					Font = Kit.font.bold,
					TextSize = Kit.size.caption,
					TextWrapped = false,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 3,
					Parent = chip,
				})
				button.Activated:Connect(function()
					picked = if picked == name then nil else name
					showNote()
				end)
				markerButtons[name] = button
				markerLines[name] = marker.line
			end
		end

		-- The lines, then the points on top: the opponent's first, so yours is above.
		local players = seats(view, payload.you)
		for index = #players, 1, -1 do
			local p = players[index]
			local color = Kit.playerColor(view, p)
			for k = 1, #points - 1 do
				local seg = EVChart.segment(
					xs[k],
					yOf(points[k].ev[p] or 0),
					xs[k + 1],
					yOf(points[k + 1].ev[p] or 0)
				)
				local piece = Kit.box({
					Name = `Line_{p}_{k}`,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(seg.x, seg.y),
					Size = UDim2.fromOffset(seg.length + 1, LINE_PX),
					Rotation = seg.rotation,
					BackgroundTransparency = if points[k + 1].result then 0.35 else 0,
					BackgroundColor3 = color,
					ZIndex = 3,
					Parent = plot,
				})
				round(piece)
			end
			for k, point in points do
				local px = if point.result then RESULT_DOT else DOT
				local dot = Kit.box({
					Name = `Dot_{p}_{k}`,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(xs[k], yOf(point.ev[p] or 0)),
					Size = UDim2.fromOffset(px, px),
					BackgroundTransparency = 0,
					BackgroundColor3 = color,
					ZIndex = 4,
					Parent = plot,
				})
				dot:SetAttribute("Overhang", true) -- a point on the plot's edge pokes out by its radius
				round(dot)
				if point.result then
					Kit.stroke(Kit.colors.text, 2).Parent = dot
				end
			end
		end

		-- The x labels that fit.
		local shown = EVChart.labels(points, xs, plotW, CHAR_PX)
		for k, point in points do
			if shown[k] then
				local w = math.max(#point.label * CHAR_PX, 16)
				local x0 = math.clamp(xs[k] - w / 2, 0, plotW - w)
				Kit.text(point.label, {
					Name = `XLabel_{k}`,
					Position = UDim2.fromOffset(AXIS_W + x0, MARKER_ROW + plotH + 4),
					Size = UDim2.fromOffset(w, LABEL_ROW - 4),
					Font = if point.result then Kit.font.bold else Kit.font.body,
					TextSize = Kit.size.caption,
					TextWrapped = false,
					TextColor3 = if point.result then Kit.colors.text else Kit.colors.muted,
					TextXAlignment = Enum.TextXAlignment.Center,
					Parent = chart,
				})
			end
		end
		showNote()
	end

	local tab: Tab
	tab = {
		root = root,
		set = function(_self: Tab, payload: Session.StatePayload, shortNames: { string })
			if current == nil or current.matchId ~= payload.matchId then
				picked = nil
			end
			current = payload
			names = shortNames
			points = EVChart.points(payload.view)
			markers = EVChart.markers(payload.view, shortNames)
			summary.Text = EVChart.summary(points, payload.you) or ""
			summary.Visible = summary.Text ~= ""
			fillLegend()
			drawnFor = ""
			if root.Visible then
				draw()
			end
		end,
		show = function(_self: Tab, visible: boolean)
			root.Visible = visible
			if visible and drawnFor == "" then
				drawnFor = `{width}x{height}`
				draw()
			end
		end,
		layout = function(_self: Tab, w: number, h: number)
			-- The chart's width: the column less the card's padding.
			width, height = math.floor(w - 2 * 14), math.floor(h)
			local key = `{width}x{height}`
			if root.Visible and key ~= drawnFor then
				drawnFor = key
				draw()
			end
		end,
	}
	return tab
end

return GraphTab
