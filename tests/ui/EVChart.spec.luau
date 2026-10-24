--!strict
-- Shared/UI/EVChart (D-073): the end screen's week-by-week chart of projected
-- votes: the series, the y scale, the x positions, the line pieces as rotated
-- Frames, the x labels that fit and the debate and stance markers.

local Config = require("@sim/Config")
local EVChart = require("@ui/EVChart")
local Events = require("@sim/Events")
local Fixtures = require("@ui/Fixtures")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local cached: any = nil
local function overView(): any
	if cached == nil then
		local payload = Fixtures.payload(C, "Over") :: any
		cached = payload.view
	end
	return cached
end

local function point(label: string, week: number?, a: number, b: number): EVChart.Point
	return { label = label, week = week, ev = { a, b }, result = week == nil }
end

describe("EVChart.points", function()
	it("runs from the draft's polls through every week to the real result", function()
		local view = overView()
		local points = EVChart.points(view)
		expect(#points):toBe(C.WEEKS + 2)
		expect(points[1].label):toBe("Start")
		expect(points[2].label):toBe("1")
		expect(points[C.WEEKS + 1].label):toBe(tostring(C.WEEKS))
		-- The last week is the final polls: the header's last projection.
		expect(points[C.WEEKS + 1].ev):toEqual(view.projectedEV)
		local last = points[#points]
		expect(last.result):toBe(true)
		expect(last.label):toBe("Result")
		expect(last.ev):toEqual(view.election.ev)
	end)

	it("sorts the history by week and copes with none", function()
		local view = {
			pollHistory = { { week = 2, ev = { 1, 2 } }, { week = 0, ev = { 3, 4 } } },
			election = nil,
		} :: any
		local points = EVChart.points(view)
		expect(points[1].week):toBe(0)
		expect(points[2].week):toBe(2)
		expect(#EVChart.points({ pollHistory = nil, election = nil } :: any)):toBe(0)
	end)
end)

describe("EVChart.range", function()
	it("always shows 270 and every value, on whole steps", function()
		local lo, hi, step = EVChart.range({ point("1", 1, 300, 238), point("R", nil, 320, 218) }, 270)
		check(lo <= 218 - EVChart.PAD, `lo {lo}`)
		check(hi >= 320 + EVChart.PAD, `hi {hi}`)
		expect(lo % step):toBe(0)
		expect(hi % step):toBe(0)
		check((hi - lo) / step <= EVChart.MAX_LINES, "too many gridlines")
	end)

	it("includes 270 even when nobody comes near it", function()
		local lo, hi = EVChart.range({ point("1", 1, 100, 120) }, 270)
		check(lo <= 100 and hi >= 270, `{lo}..{hi}`)
	end)

	it("never leaves 0 … 538", function()
		local lo, hi, step = EVChart.range({ point("1", 1, 538, 0) }, 270)
		expect(lo):toBe(0)
		expect(hi):toBe(538)
		expect(step):toBe(100)
	end)
end)

describe("EVChart.xs and y", function()
	it("spaces the weeks evenly and sets the result a little apart", function()
		local points =
			{ point("Start", 0, 1, 1), point("1", 1, 1, 1), point("2", 2, 1, 1), point("R", nil, 1, 1) }
		local xs = EVChart.xs(points, 400)
		local stepPx = xs[2] - xs[1]
		expect(xs[3] - xs[2]):toBeCloseTo(stepPx)
		expect(xs[4] - xs[3]):toBeCloseTo(stepPx * EVChart.RESULT_GAP)
		expect(xs[1]):toBeCloseTo(stepPx / 2)
		expect(400 - xs[4]):toBeCloseTo(stepPx / 2)
	end)

	it("puts the top of the range at 0 and the bottom at the height", function()
		expect(EVChart.y(400, 200, 400, 100)):toBe(0)
		expect(EVChart.y(200, 200, 400, 100)):toBe(100)
		expect(EVChart.y(300, 200, 400, 100)):toBe(50)
		expect(EVChart.y(999, 200, 400, 100)):toBe(0)
	end)
end)

describe("EVChart.segment", function()
	it("is a flat line between two points at the same height", function()
		local s = EVChart.segment(10, 20, 30, 20)
		expect(s.x):toBe(20)
		expect(s.y):toBe(20)
		expect(s.length):toBe(20)
		expect(s.rotation):toBe(0)
	end)

	it("turns clockwise for a line going down the screen (y grows down)", function()
		local s = EVChart.segment(0, 0, 10, 10)
		expect(s.rotation):toBeCloseTo(45)
		expect(s.length):toBeCloseTo(math.sqrt(200))
		expect(EVChart.segment(0, 10, 10, 0).rotation):toBeCloseTo(-45)
	end)

	it("its ends land on both points once rotated about its center", function()
		local s = EVChart.segment(12, 80, 40, 30)
		local r = math.rad(s.rotation)
		local ex, ey = s.x + math.cos(r) * s.length / 2, s.y + math.sin(r) * s.length / 2
		expect(ex):toBeCloseTo(40)
		expect(ey):toBeCloseTo(30)
	end)
end)

describe("EVChart.labels", function()
	local function full(): { EVChart.Point }
		local points = { point("Start", 0, 1, 1) }
		for w = 1, 12 do
			table.insert(points, point(tostring(w), w, 1, 1))
		end
		table.insert(points, point("Result", nil, 1, 1))
		return points
	end

	local function noOverlap(
		points: { EVChart.Point },
		xs: { number },
		shown: { boolean },
		width: number,
		charPx: number
	)
		local last = -math.huge
		for i, on in shown do
			if on then
				local w = #points[i].label * charPx
				local x0 = math.clamp(xs[i] - w / 2, 0, width - w)
				check(x0 >= last, `label {points[i].label} overlaps the one before`)
				check(x0 + w <= width + 0.001, `label {points[i].label} leaves the chart`)
				last = x0 + w
			end
		end
	end

	it("shows every week on a wide chart", function()
		local points = full()
		local xs = EVChart.xs(points, 900)
		local shown = EVChart.labels(points, xs, 900, 8)
		for i in points do
			check(shown[i], `label {points[i].label} hidden on a wide chart`)
		end
	end)

	it("drops week labels on a phone so none overlap, keeping Start and Result", function()
		local points = full()
		local width = 320
		local xs = EVChart.xs(points, width)
		local shown = EVChart.labels(points, xs, width, 8)
		check(shown[1] and shown[#points], "Start or Result is hidden")
		local count = 0
		for _, on in shown do
			if on then
				count += 1
			end
		end
		check(count >= 5, `only {count} labels on a phone`)
		check(count < #points, "every label kept on a phone")
		noOverlap(points, xs, shown, width, 8)
	end)
end)

describe("EVChart.markers", function()
	it("marks every debate and every Choice event of the match, oldest first", function()
		local view = overView()
		local markers = EVChart.markers(view, { "Dana", "Rex" })
		local debates, choices = 0, 0
		for k, marker in markers do
			if k > 1 then
				check(marker.week >= markers[k - 1].week, "markers out of order")
			end
			if marker.kind == "Debate" then
				debates += 1
				expect(marker.letter):toBe("D")
				check(string.find(marker.line, `Week {marker.week} · Debate: `, 1, true) == 1, marker.line)
			else
				choices += 1
				expect(marker.letter):toBe("S")
			end
		end
		expect(debates):toBe(#view.debates)
		local expected = 0
		for _, entry in view.eventLog do
			if Events.byId[entry.id].kind == "Choice" then
				expected += 1
			end
		end
		expect(choices):toBe(expected)
	end)

	it("says who won a debate and what each player chose", function()
		local choice: any = nil
		for _, definition in Events.deck do
			if definition.kind == "Choice" then
				choice = definition
				break
			end
		end
		assert(choice, "the deck has a Choice event")
		local view = {
			you = 1,
			players = { {}, {} },
			debates = {
				{ week = 4, topics = { "Jobs", "Health", "Schools" }, winners = { 2, 2, 1 } },
				{ week = 8, topics = { "Jobs", "Health" }, winners = { 1, 2 } },
			},
			eventLog = { { week = 6, id = choice.id, choices = { "A", "C" } } },
		} :: any
		local markers = EVChart.markers(view, { "Dana", "Rex" })
		expect(#markers):toBe(3)
		expect(markers[1].line):toBe("Week 4 · Debate: Rex won 2 of 3 topics")
		expect(markers[2].line):toBe(
			`Week 6 · {choice.name}: you chose {choice.stances[1].name}; Rex chose {choice.stances[3].name}`
		)
		expect(markers[3].line):toBe("Week 8 · Debate: even, 1 topic each")
	end)
end)

describe("EVChart.summary", function()
	it("walks your line from the start to the final polls and the result", function()
		local points = {
			point("Start", 0, 238, 300),
			point("1", 1, 250, 288),
			point("12", 12, 290, 248),
			point("Result", nil, 302, 236),
		}
		expect(EVChart.summary(points, 1)):toBe(
			"You: 238 at the start, 290 in the final polls, 302 on election night."
		)
		expect(EVChart.summary(points, 2)):toBe(
			"You: 300 at the start, 248 in the final polls, 236 on election night."
		)
		expect(EVChart.summary({}, 1)):toBe(nil)
	end)
end)
