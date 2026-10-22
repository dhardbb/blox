--!strict
-- Node-map layout: one circle per state at its projected center, radius growing
-- with sqrt(EV), nudged apart so no two circles overlap (the Northeast is dense).
-- Alaska and Hawaii sit in insets at the bottom left. Pure and deterministic, so it
-- is computed once and tested headlessly.
--
-- Coordinates are fractions of the map box: x and r in units of the box width,
-- y in units of the box height. The box is meant to be shown at ASPECT (width /
-- height) with a UIAspectRatioConstraint, so circles stay round.

local StateData = require("../Sim/StateData")
local Types = require("../Types")

export type Node = {
	id: string,
	x: number, -- center, 0..1 of the box width
	y: number, -- center, 0..1 of the box height
	r: number, -- radius, in units of the box width
}

local MapLayout = {}

MapLayout.ASPECT = 1.6 -- box width / height
local LON_WEST, LON_EAST = -125, -66.5 -- contiguous states
local LAT_NORTH, LAT_SOUTH = 49.5, 24.5
local MARGIN_X, MARGIN_TOP, MARGIN_BOTTOM = 0.05, 0.07, 0.08
local R_BASE, R_PER_SQRT_EV = 0.004, 0.0062 -- radius = base + per * sqrt(EV), in box widths
local GAP = 0.003 -- minimum space between two circles, in box widths
local ITERATIONS = 400
local PULL = 0.02 -- share of the way back toward the true position per iteration
local INSETS: { [string]: { x: number, y: number } } = {
	AK = { x = 0.07, y = 0.88 },
	HI = { x = 0.19, y = 0.93 },
}

function MapLayout.radius(ev: number): number
	return R_BASE + R_PER_SQRT_EV * math.sqrt(ev)
end

-- True projected position (before overlap relaxation), y in box-width units.
local function project(record: Types.StateRecord): (number, number)
	local inset = INSETS[record.id]
	if inset then
		return inset.x, inset.y / MapLayout.ASPECT
	end
	local u = (record.lon - LON_WEST) / (LON_EAST - LON_WEST)
	local v = (LAT_NORTH - record.lat) / (LAT_NORTH - LAT_SOUTH)
	local x = MARGIN_X + u * (1 - 2 * MARGIN_X)
	local y = MARGIN_TOP + v * (1 - MARGIN_TOP - MARGIN_BOTTOM - 0.05)
	return x, y / MapLayout.ASPECT
end

local cached: { Node }? = nil

-- Every state's node, in StateData.list order. Computed once.
function MapLayout.nodes(): { Node }
	if cached then
		return cached
	end
	local n = #StateData.list
	local xs, ys, rs, homeX, homeY = {}, {}, {}, {}, {}
	for i, record in StateData.list do
		xs[i], ys[i] = project(record)
		homeX[i], homeY[i] = xs[i], ys[i]
		rs[i] = MapLayout.radius(record.ev)
	end
	local height = 1 / MapLayout.ASPECT
	for _ = 1, ITERATIONS do
		for i = 1, n do
			for j = i + 1, n do
				local dx, dy = xs[j] - xs[i], ys[j] - ys[i]
				local d = math.sqrt(dx * dx + dy * dy)
				local need = rs[i] + rs[j] + GAP
				if d < need then
					if d < 1e-9 then
						dx, dy, d = 1, 0, 1 -- coincident: push along x
					end
					local push = (need - d) / 2
					local ux, uy = dx / d, dy / d
					-- Bigger circles move less.
					local wi = rs[j] / (rs[i] + rs[j])
					local wj = rs[i] / (rs[i] + rs[j])
					xs[i] -= ux * push * 2 * wi
					ys[i] -= uy * push * 2 * wi
					xs[j] += ux * push * 2 * wj
					ys[j] += uy * push * 2 * wj
				end
			end
		end
		for i = 1, n do
			xs[i] += (homeX[i] - xs[i]) * PULL
			ys[i] += (homeY[i] - ys[i]) * PULL
			xs[i] = math.clamp(xs[i], rs[i], 1 - rs[i])
			ys[i] = math.clamp(ys[i], rs[i], height - rs[i])
		end
	end
	local nodes: { Node } = {}
	for i, record in StateData.list do
		nodes[i] = table.freeze({ id = record.id, x = xs[i], y = ys[i] * MapLayout.ASPECT, r = rs[i] })
	end
	cached = table.freeze(nodes)
	return nodes
end

-- Adjacency edges as pairs of node indices, each listed once.
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
