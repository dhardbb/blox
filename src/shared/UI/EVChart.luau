--!strict
-- The end screen's graph (docs/DESIGN.md D-066): both players' projected votes
-- week by week, from the public polls (the header's numbers), then election
-- night's real count as the last point. Pure: the series, the scale and every
-- pixel position, so Results only draws Frames where this says.
--
--   EVChart.points(view) -> { Point }              Start, week 1 … last week, Result
--   EVChart.range(points, mark) -> (lo, hi, step)  the y axis, always showing `mark` (270)
--   EVChart.xs(points, width) -> { number }        each point's x in px (the result a little apart)
--   EVChart.y(value, lo, hi, height) -> number     a value's y in px, 0 at the top
--   EVChart.segment(x1, y1, x2, y2) -> Segment     one line piece as a rotated Frame
--   EVChart.labels(points, xs, width, charPx) -> { boolean }   x labels that fit
--   EVChart.markers(view, names) -> { Marker }     debate and stance weeks, with their line
--   EVChart.summary(points, you) -> string?        "You: 238 at the start, 290 in the final polls, 302 on election night."
--
-- History comes from `view.pollHistory` (the projected votes each time the
-- weekly polls came out: week 0 after the draft, week w at the end of week w),
-- public from election night on; the result from `view.election.ev`.

local Events = require("../Sim/Events")
local ViewModule = require("../Sim/View")

type View = ViewModule.View

export type Point = {
	label: string, -- the x axis: "Start", "1" … "12", "Result"
	week: number?, -- nil for the result
	ev: { number }, -- by player
	result: boolean,
}

export type Segment = {
	x: number, -- the center, px
	y: number,
	length: number, -- px
	rotation: number, -- degrees, clockwise (GuiObject.Rotation)
}

export type Marker = {
	week: number,
	kind: "Debate" | "Choice",
	letter: string, -- the marker's glyph: "D" a debate, "S" a stance vote
	line: string, -- shown when tapped: "Week 4 · Debate: you won 2 of 3 topics"
}

local EVChart = {}

EVChart.RESULT_GAP = 1.5 -- the result sits this many week-steps after the last week
EVChart.STEPS = { 50, 100 } -- y gridline steps: the first whose lines number at most MAX_LINES
EVChart.MAX_LINES = 6
EVChart.PAD = 20 -- votes of room above the highest value and below the lowest
EVChart.LABEL_GAP = 6 -- px between two x labels
EVChart.TOTAL = 538 -- the y axis never goes past every vote on the map

function EVChart.points(view: View): { Point }
	local points: { Point } = {}
	local history = view.pollHistory
	if history then
		local sorted = table.clone(history)
		table.sort(sorted, function(a, b)
			return a.week < b.week
		end)
		for _, entry in sorted do
			table.insert(points, {
				label = if entry.week == 0 then "Start" else tostring(entry.week),
				week = entry.week,
				ev = table.clone(entry.ev),
				result = false,
			})
		end
	end
	local election = view.election
	if election then
		table.insert(points, { label = "Result", week = nil, ev = table.clone(election.ev), result = true })
	end
	return points
end

-- The y axis: from `lo` to `hi` votes with gridlines every `step`, covering every
-- value and `mark` with PAD to spare, on whole steps, within 0 … TOTAL (a range
-- that reaches every vote on the map tops out at TOTAL itself).
function EVChart.range(points: { Point }, mark: number): (number, number, number)
	local low, high = mark, mark
	for _, point in points do
		for _, value in point.ev do
			low = math.min(low, value)
			high = math.max(high, value)
		end
	end
	low = math.max(0, low - EVChart.PAD)
	high = math.min(EVChart.TOTAL, high + EVChart.PAD)
	local lo, hi, step = 0, EVChart.TOTAL, EVChart.STEPS[#EVChart.STEPS]
	for _, s in EVChart.STEPS do
		local a = math.floor(low / s) * s
		local b = math.min(math.ceil(high / s) * s, EVChart.TOTAL)
		lo, hi, step = a, b, s
		if (b - a) / s <= EVChart.MAX_LINES then
			break
		end
	end
	if hi <= lo then
		hi = lo + step
	end
	return lo, hi, step
end

-- x of every point across `width` px: the weeks evenly, half a step of room at
-- either end, the result RESULT_GAP steps after the last week.
function EVChart.xs(points: { Point }, width: number): { number }
	local weeks, hasResult = 0, false
	for _, point in points do
		if point.result then
			hasResult = true
		else
			weeks += 1
		end
	end
	local span = math.max(weeks - 1, 0) + (if hasResult and weeks > 0 then EVChart.RESULT_GAP else 0)
	local stepPx = width / (span + 1) -- half a step of room at either end
	local xs: { number } = {}
	local k = 0
	for i, point in points do
		if point.result and weeks > 0 then
			xs[i] = stepPx / 2 + (weeks - 1 + EVChart.RESULT_GAP) * stepPx
		else
			xs[i] = stepPx / 2 + k * stepPx
			k += 1
		end
	end
	return xs
end

function EVChart.y(value: number, lo: number, hi: number, height: number): number
	local t = (math.clamp(value, lo, hi) - lo) / math.max(hi - lo, 1)
	return height * (1 - t)
end

-- A line from (x1, y1) to (x2, y2) as one Frame: centered on the midpoint, as
-- long as the line, turned by its angle (Roblox turns a GuiObject about its
-- center, clockwise, with y growing down).
function EVChart.segment(x1: number, y1: number, x2: number, y2: number): Segment
	local dx, dy = x2 - x1, y2 - y1
	return {
		x = (x1 + x2) / 2,
		y = (y1 + y2) / 2,
		length = math.sqrt(dx * dx + dy * dy),
		rotation = math.deg(math.atan2(dy, dx)),
	}
end

-- Which x labels to show so none overlaps another or leaves the `width`: the
-- first and the last always (the last is the result), and the weeks every k-th
-- week for the smallest k that fits (`charPx`: an estimated character width).
function EVChart.labels(points: { Point }, xs: { number }, width: number, charPx: number): { boolean }
	local n = #points
	local function span(i: number): (number, number)
		local w = #points[i].label * charPx
		local x0 = math.clamp(xs[i] - w / 2, 0, math.max(width - w, 0))
		return x0, x0 + w
	end
	local function fits(chosen: { number }): boolean
		for a = 1, #chosen - 1 do
			local _, right = span(chosen[a])
			local left = span(chosen[a + 1])
			if right + EVChart.LABEL_GAP > left then
				return false
			end
		end
		return true
	end
	local shown = table.create(n, false)
	if n == 0 then
		return shown
	end
	for stride = 1, math.max(n, 1) do
		local chosen: { number } = { 1 }
		for i = 2, n - 1 do
			local week = points[i].week
			if week ~= nil and week % stride == 0 then
				table.insert(chosen, i)
			end
		end
		if n > 1 then
			table.insert(chosen, n)
		end
		-- A week label too close to the result gives way to it.
		while #chosen > 2 and not fits({ chosen[#chosen - 1], chosen[#chosen] }) do
			table.remove(chosen, (#chosen - 1)) -- the week before the result
		end
		if fits(chosen) or stride == n then
			for _, i in chosen do
				shown[i] = true
			end
			return shown
		end
	end
	return shown
end

local function plural(n: number, word: string): string
	return `{n} {word}{if n == 1 then "" else "s"}`
end

-- The debates and the Choice events of the match, oldest first, each with the
-- line shown when its marker is tapped. `names` are first names by player.
function EVChart.markers(view: View, names: { string }): { Marker }
	local you = view.you
	local function who(p: number): string
		return if p == you then "you" else (names[p] or `Player {p}`)
	end
	local markers: { Marker } = {}
	for _, debate in view.debates do
		local won = table.create(#view.players, 0)
		for _, winner in debate.winners do
			if winner ~= 0 and won[winner] ~= nil then
				won[winner] += 1
			end
		end
		local best, leader, tied = -1, 0, false
		for p, count in won do
			if count > best then
				best, leader, tied = count, p, false
			elseif count == best then
				tied = true
			end
		end
		local total = #debate.topics
		local verdict = if tied
			then `even, {plural(best, "topic")} each`
			else `{who(leader)} won {best} of {plural(total, "topic")}`
		table.insert(markers, {
			week = debate.week,
			kind = "Debate",
			letter = "D",
			line = `Week {debate.week} · Debate: {verdict}`,
		})
	end
	for _, entry in view.eventLog do
		local definition = Events.byId[entry.id]
		if definition and definition.kind == "Choice" then
			local parts: { string } = {}
			local choices = entry.choices
			if choices then
				local order = { you }
				for p = 1, #view.players do
					if p ~= you then
						table.insert(order, p)
					end
				end
				for _, p in order do
					local choice = choices[p]
					local stanceName: string? = nil
					local stances: { Events.Stance } = definition.stances or {}
					for _, stance in stances do
						if stance.id == choice then
							stanceName = stance.name
						end
					end
					if stanceName then
						table.insert(parts, `{who(p)} chose {stanceName}`)
					end
				end
			end
			local tail = if #parts > 0 then `: {table.concat(parts, "; ")}` else ""
			table.insert(markers, {
				week = entry.week,
				kind = "Choice",
				letter = "S",
				line = `Week {entry.week} · {definition.name}{tail}`,
			})
		end
	end
	table.sort(markers, function(a, b)
		if a.week ~= b.week then
			return a.week < b.week
		end
		return a.kind < b.kind
	end)
	return markers
end

-- Your own line in words, under the chart.
function EVChart.summary(points: { Point }, you: number): string?
	local first, lastWeek, result = nil, nil, nil
	for _, point in points do
		if point.result then
			result = point
		elseif first == nil then
			first = point
			lastWeek = point
		else
			lastWeek = point
		end
	end
	local parts: { string } = {}
	if first and lastWeek then
		table.insert(
			parts,
			`{first.ev[you]} {if first.week == 0 then "at the start" else `in week {first.week}`}`
		)
		if lastWeek ~= first then
			table.insert(parts, `{lastWeek.ev[you]} in the final polls`)
		end
	end
	if result then
		table.insert(parts, `{result.ev[you]} on election night`)
	end
	if #parts == 0 then
		return nil
	end
	return `You: {table.concat(parts, ", ")}.`
end

return table.freeze(EVChart)
