--!strict
-- The real-shape map's geometry (docs/DESIGN.md D-070), pure: the generated
-- MapShapeData (scripts/mapgen/make.py) plus lookups and tap hit tests, so the
-- client map (Map/ShapeMap), the headless snapshots and the specs all agree.
--
-- Coordinates are fractions of the map box: x of its width, y of its height.
-- The box is shown at ASPECT (= MapLayout.ASPECT).
--
-- Taps (MapShape.resolve): a point in the callout column picks the nearest
-- chip; a point inside a state's outline picks that state (so a neighbor's
-- bigger tap square never steals it); anything else (a border line, the coast,
-- the sea next to a small state) goes to the tap square that was pressed.

local Data = require("./MapShapeData")
local MapLayout = require("./MapLayout")

export type Shape = Data.Shape
export type Rect = Data.Rect

type Box = { x0: number, y0: number, x1: number, y1: number }

local MapShape = {}

MapShape.data = Data
MapShape.ASPECT = Data.ASPECT
MapShape.LADDER = MapLayout.LADDER

local list: { Shape } = Data.shapes
local byId: { [string]: Shape } = {}
local boxes: { [string]: { Box } } = {} -- per state, each ring's bounds
for _, shape in list do
	byId[shape.id] = shape
	local bounds = {}
	for _, ring in shape.rings do
		local b = { x0 = math.huge, y0 = math.huge, x1 = -math.huge, y1 = -math.huge }
		for i = 1, #ring, 2 do
			b.x0 = math.min(b.x0, ring[i])
			b.x1 = math.max(b.x1, ring[i])
			b.y0 = math.min(b.y0, ring[i + 1])
			b.y1 = math.max(b.y1, ring[i + 1])
		end
		table.insert(bounds, b)
	end
	boxes[shape.id] = bounds
end

-- Every state, in StateData order.
function MapShape.list(): { Shape }
	return list
end

function MapShape.get(id: string): Shape?
	return byId[id]
end

-- Even-odd test of (x, y) against one flat ring.
local function inRing(ring: { number }, x: number, y: number): boolean
	local inside = false
	local n = #ring
	local jx, jy = ring[n - 1], ring[n]
	for i = 1, n, 2 do
		local ix, iy = ring[i], ring[i + 1]
		if (iy > y) ~= (jy > y) and x < (jx - ix) * (y - iy) / (jy - iy) + ix then
			inside = not inside
		end
		jx, jy = ix, iy
	end
	return inside
end

-- Is (x, y) inside the state's outline (any of its islands)?
function MapShape.contains(id: string, x: number, y: number): boolean
	local shape = byId[id]
	if shape == nil then
		return false
	end
	for k, ring in shape.rings do
		local b = boxes[id][k]
		if x >= b.x0 and x <= b.x1 and y >= b.y0 and y <= b.y1 and inRing(ring, x, y) then
			return true
		end
	end
	return false
end

-- The state whose outline holds (x, y), or nil (the sea, a border line).
function MapShape.at(x: number, y: number): string?
	for _, shape in list do
		if MapShape.contains(shape.id, x, y) then
			return shape.id
		end
	end
	return nil
end

-- The callout chip nearest (x, y) when the point is in the chip column, else nil.
function MapShape.chipAt(x: number, y: number): string?
	local best, bestD = nil, math.huge
	for _, id in MapLayout.LADDER do
		local chip = byId[id] and byId[id].chip
		if chip and x >= chip.x then
			local d = math.abs(y - (chip.y + chip.h / 2))
			if d < bestD then
				best, bestD = id, d
			end
		end
	end
	return best
end

-- Which state a tap at (x, y) means; `pressed` is the tap square that got it
-- (nil: a tap on open map, which then selects nothing).
function MapShape.resolve(x: number, y: number, pressed: string?): string?
	return MapShape.chipAt(x, y) or MapShape.at(x, y) or pressed
end

-- Where a state's label (and its marks) sit: its anchor; a callout state's chip center.
function MapShape.labelAt(id: string): (number, number)
	local shape = byId[id]
	if shape == nil then
		return 0.5, 0.5
	end
	local chip = shape.chip
	if chip then
		return chip.x + chip.w / 2, chip.y + chip.h / 2
	end
	return shape.lx, shape.ly
end

-- The diameter in px of the biggest circle inside the state on a map `widthPx` wide.
function MapShape.roomPx(id: string, widthPx: number): number
	local shape = byId[id]
	return if shape then shape.room * widthPx else 0
end

return table.freeze(MapShape)
