--!strict
-- The node-map layout (src/shared/UI/MapLayout.luau), pure: no overlaps, every
-- circle and tap target inside the box, the Northeast inset ladder, and labels
-- big enough to read on a 390 px phone map (docs/UI-OVERHAUL.md B12, WP1).

local MapLayout = require("@ui/MapLayout")
local StateData = require("@sim/StateData")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local EPS = 1e-9
local HEIGHT = 1 / MapLayout.ASPECT -- box height in box widths

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function byId(): { [string]: MapLayout.Node }
	local at = {}
	for _, n in MapLayout.nodes() do
		at[n.id] = n
	end
	return at
end

describe("MapLayout (B12)", function()
	it("keeps every pair of circles at least GAP apart", function()
		local nodes = MapLayout.nodes()
		for i = 1, #nodes do
			for j = i + 1, #nodes do
				local a, b = nodes[i], nodes[j]
				local dx, dy = a.x - b.x, (a.y - b.y) * HEIGHT
				local d = math.sqrt(dx * dx + dy * dy)
				check(
					d >= a.r + b.r + MapLayout.GAP - EPS,
					`{a.id} and {b.id} are {d} apart, want {a.r + b.r + MapLayout.GAP}`
				)
			end
		end
	end)

	it("keeps every circle and every phone-size tap target inside the box", function()
		for _, n in MapLayout.nodes() do
			local y = n.y * HEIGHT -- in box widths
			check(n.x >= n.r - EPS and n.x <= 1 - n.r + EPS, `{n.id} circle pokes out sideways`)
			check(y >= n.r - EPS and y <= HEIGHT - n.r + EPS, `{n.id} circle pokes out vertically`)
			local h = MapLayout.hitRadius(n)
			check(h * MapLayout.PHONE_WIDTH >= MapLayout.MIN_HIT / 2 - EPS, `{n.id} tap target is too small`)
			check(n.x >= h - EPS and n.x <= 1 - h + EPS, `{n.id} tap target pokes out sideways`)
			check(y >= h - EPS and y <= HEIGHT - h + EPS, `{n.id} tap target pokes out vertically`)
		end
	end)

	it("stands the nine Northeast states in one ladder, in order, at the right edge", function()
		expect(table.concat(MapLayout.LADDER, " ")):toBe("VT NH MA RI CT NJ DE MD DC")
		local at = byId()
		local first = at[MapLayout.LADDER[1]]
		local previousY = -1
		for _, id in MapLayout.LADDER do
			local n = at[id]
			check(n.ladder, `{id} is not flagged as a ladder node`)
			check(math.abs(n.x - first.x) < EPS, `{id} is not in the ladder column`)
			check(n.y > previousY, `{id} is out of order in the ladder`)
			check(math.abs(n.r - first.r) < EPS, `{id} has a different radius from the rest of the ladder`)
			previousY = n.y
		end
		check(first.x > 0.9, "the ladder is not at the right edge")
		local ladder = 0
		for _, n in MapLayout.nodes() do
			if n.ladder then
				ladder += 1
			else
				check(n.x < first.x - first.r, `{n.id} sits in the ladder column`)
			end
		end
		expect(ladder):toBe(9)
		expect(#MapLayout.nodes() - ladder):toBe(42)
		check(not at.ME.ladder and not at.NY.ladder and not at.PA.ladder, "ME, NY and PA stay on the map")
	end)

	it("points each ladder leader at the state's true center, west of the ladder", function()
		local at = byId()
		for _, id in MapLayout.LADDER do
			local n = at[id]
			check(n.cx < n.x - n.r, `{id}'s leader does not head west`)
			check(n.cx > 0.7 and n.cy > 0.1 and n.cy < 0.6, `{id}'s true center is not in the Northeast`)
		end
		-- DC is south of VT on the real map too.
		check(at.DC.cy > at.VT.cy, "true centers are not north-up")
	end)

	it("makes every label readable on a 390 px map", function()
		for _, n in MapLayout.nodes() do
			local px = MapLayout.labelPx(n, 390)
			if n.ladder then
				check(px >= 20, `ladder label {n.id} is {px} px wide at 390 (want 20)`)
			else
				check(px >= 24, `label {n.id} is {px} px wide at 390 (want 24)`)
			end
		end
	end)

	it("moves no projected state far from where it really is", function()
		for _, n in MapLayout.nodes() do
			if not n.ladder then
				local dx, dy = n.x - n.cx, (n.y - n.cy) * HEIGHT
				local d = math.sqrt(dx * dx + dy * dy)
				check(d <= 0.1, `{n.id} moved {d} box widths`)
			end
		end
	end)

	it("still lists one node per state, in StateData order", function()
		local nodes = MapLayout.nodes()
		expect(#nodes):toBe(#StateData.list)
		for i, record in StateData.list do
			expect(nodes[i].id):toBe(record.id)
		end
		expect(MapLayout.MIN_HIT):toBe(36)
	end)
end)
