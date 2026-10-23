--!strict
-- Node-map layout: one circle per state at its projected center, radius growing
-- with sqrt(EV), nudged apart so no two circles overlap. Nine small Northeast
-- states (MapLayout.LADDER) cannot fit where they really are, so they leave the
-- projection and stand in an inset "ladder": one column of equal circles at the
-- right edge, north to south, each with a leader line back to its true center
-- (Node.cx, Node.cy). Alaska and Hawaii sit in insets at the bottom left. Pure
-- and deterministic, so it is computed once and tested headlessly.
--
-- Coordinates are fractions of the map box: x and r in units of the box width,
-- y in units of the box height. The box is meant to be shown at ASPECT (width /
-- height) with a UIAspectRatioConstraint, so circles stay round.
--
-- Sizes are chosen for the narrowest map the game shows, PHONE_WIDTH px wide:
-- there every circle is big enough to hold its label (labelPx), and every
-- MIN_HIT px tap target stays inside the box.

local StateData = require("../Sim/StateData")
local Types = require("../Types")

export type Node = {
	id: string,
	x: number, -- center, 0..1 of the box width
	y: number, -- center, 0..1 of the box height
	r: number, -- radius, in units of the box width
	cx: number, -- true projected center (where a ladder node's leader points), box width
	cy: number, -- true projected center, box height
	ladder: boolean, -- stands in the Northeast inset ladder
}

local MapLayout = {}

MapLayout.ASPECT = 1.6 -- box width / height
MapLayout.PHONE_WIDTH = 360 -- px, the narrowest map the layout is sized for (a 390 px portrait phone less its screen padding, with room)
MapLayout.MIN_HIT = 36 -- px, tap target per node; must equal Kit.MAP_NODE_MIN (NodeMap.spec)
MapLayout.LABEL_SCALE = 0.85 -- label box width as a share of the circle's diameter
-- The Northeast inset, top to bottom (roughly north to south, so leaders rarely cross).
MapLayout.LADDER = table.freeze({ "VT", "NH", "MA", "RI", "CT", "NJ", "DE", "MD", "DC" })

local LON_WEST, LON_EAST = -125, -66.5 -- contiguous states
local LAT_NORTH, LAT_SOUTH = 49.5, 24.5
local MARGIN_X, EAST_X = 0.05, 0.86 -- projected x of LON_WEST and LON_EAST (the ladder is east of it)
local MARGIN_TOP, MARGIN_BOTTOM = 0.07, 0.13 -- projected y of LAT_NORTH and LAT_SOUTH, in box heights
local R_BASE, R_PER_SQRT_EV = 0.0293, 0.0040 -- radius = base + per * sqrt(EV), in box widths
local GAP = 0.004 -- minimum space between two circles, in box widths (room for an owner ring on a phone)
local LADDER_X = 0.95 -- ladder column center, box width (keeps a MIN_HIT target inside at PHONE_WIDTH)
local LADDER_R = 0.0305 -- ladder circle radius, box width
local LADDER_TOP, LADDER_BOTTOM = 0.08, 0.92 -- first and last ladder centers, box height
local ITERATIONS = 400
local SETTLE = 200 -- extra pushes without the pull home, so no overlap is left
local PULL = 0.02 -- share of the way back toward the true position per iteration
local INSETS: { [string]: { x: number, y: number } } = {
	AK = { x = 0.07, y = 0.88 },
	HI = { x = 0.19, y = 0.93 },
}
MapLayout.GAP = GAP

local ladderIndex: { [string]: number } = {}
for k, id in MapLayout.LADDER do
	ladderIndex[id] = k
end

function MapLayout.radius(ev: number): number
	return R_BASE + R_PER_SQRT_EV * math.sqrt(ev)
end

-- Width in px of a node's label box when the map is `widthPx` wide.
function MapLayout.labelPx(node: Node, widthPx: number): number
	return MapLayout.LABEL_SCALE * 2 * node.r * widthPx
end

-- Half the side of a node's tap target, in box widths: the circle's radius, but
-- never less than MIN_HIT / 2 px at PHONE_WIDTH. Scales with the map, so bigger
-- maps get proportionally bigger targets; NodeMap also clamps it to MIN_HIT px.
function MapLayout.hitRadius(node: Node): number
	return math.max(node.r, MapLayout.MIN_HIT / 2 / MapLayout.PHONE_WIDTH)
end

-- True projected position, y in box-width units.
local function project(record: Types.StateRecord): (number, number)
	local inset = INSETS[record.id]
	if inset then
		return inset.x, inset.y / MapLayout.ASPECT
	end
	local u = (record.lon - LON_WEST) / (LON_EAST - LON_WEST)
	local v = (LAT_NORTH - record.lat) / (LAT_NORTH - LAT_SOUTH)
	local x = MARGIN_X + u * (EAST_X - MARGIN_X)
	local y = MARGIN_TOP + v * (1 - MARGIN_TOP - MARGIN_BOTTOM)
	return x, y / MapLayout.ASPECT
end

local cached: { Node }? = nil

-- Every state's node, in StateData.list order. Computed once.
function MapLayout.nodes(): { Node }
	if cached then
		return cached
	end
	local n = #StateData.list
	local height = 1 / MapLayout.ASPECT
	-- Half a tap target, in box widths: centers stay this far from the edges.
	local hit = MapLayout.MIN_HIT / 2 / MapLayout.PHONE_WIDTH
	local xs, ys, rs, homeX, homeY, fixed = {}, {}, {}, {}, {}, {}
	for i, record in StateData.list do
		homeX[i], homeY[i] = project(record)
		local k = ladderIndex[record.id]
		if k then
			local t = (k - 1) / (#MapLayout.LADDER - 1)
			xs[i] = LADDER_X
			ys[i] = (LADDER_TOP + t * (LADDER_BOTTOM - LADDER_TOP)) * height
			rs[i] = LADDER_R
			fixed[i] = true
		else
			xs[i], ys[i] = homeX[i], homeY[i]
			rs[i] = MapLayout.radius(record.ev)
			fixed[i] = false
		end
	end

	local function push()
		for i = 1, n do
			for j = i + 1, n do
				if fixed[i] and fixed[j] then
					continue
				end
				local dx, dy = xs[j] - xs[i], ys[j] - ys[i]
				local d = math.sqrt(dx * dx + dy * dy)
				local need = rs[i] + rs[j] + GAP * 1.05 -- a hair over GAP so rounding cannot fail it
				if d < need then
					if d < 1e-9 then
						dx, dy, d = 1, 0, 1 -- coincident: push along x
					end
					local ux, uy = dx / d, dy / d
					local over = need - d
					-- Bigger circles move less; ladder nodes never move.
					local wi = if fixed[i] then 0 elseif fixed[j] then 1 else rs[j] / (rs[i] + rs[j])
					local wj = 1 - wi
					xs[i] -= ux * over * wi
					ys[i] -= uy * over * wi
					xs[j] += ux * over * wj
					ys[j] += uy * over * wj
				end
			end
		end
	end

	local function clamp(pull: number)
		for i = 1, n do
			if not fixed[i] then
				xs[i] += (homeX[i] - xs[i]) * pull
				ys[i] += (homeY[i] - ys[i]) * pull
				local m = math.max(rs[i], hit)
				xs[i] = math.clamp(xs[i], m, 1 - m)
				ys[i] = math.clamp(ys[i], m, height - m)
			end
		end
	end

	for _ = 1, ITERATIONS do
		push()
		clamp(PULL)
	end
	for _ = 1, SETTLE do
		push()
		clamp(0)
	end

	local nodes: { Node } = {}
	for i, record in StateData.list do
		nodes[i] = table.freeze({
			id = record.id,
			x = xs[i],
			y = ys[i] * MapLayout.ASPECT,
			r = rs[i],
			cx = homeX[i],
			cy = homeY[i] * MapLayout.ASPECT,
			ladder = fixed[i],
		})
	end
	cached = table.freeze(nodes)
	return nodes
end

-- Adjacency edges as pairs of node indices, each listed once (ladder nodes
-- included; NodeMap draws a leader for them instead of their borders).
function MapLayout.edges(): { { number } }
	local index: { [string]: number } = {}
	for i, record in StateData.list do
		index[record.id] = i
	end
	local edges = {}
	for i, record in StateData.list do
		for _, other in record.adjacent do
			local j = index[other]
			if j and j > i then
				table.insert(edges, { i, j })
			end
		end
	end
	return edges
end

return table.freeze(MapLayout)
