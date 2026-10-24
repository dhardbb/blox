--!strict
-- The real-shape map's geometry (docs/DESIGN.md D-070), pure: the generated
-- MapShapeData (scripts/mapgen/make.py) plus lookups and tap hit tests, so the
-- client map (Map/ShapeMap), the headless snapshots and the specs all agree.
--
-- Coordinates are fractions of the map box: x of its width, y of its height.
--
-- Two layouts (D-079), both drawn from the same atlases:
--   wide  the box at ASPECT (1.6): the land on the left, the nine small
--         Northeast states as callout chips in one column at the right edge
--         (iPad, desktop, and any map that is short for its width)
--   tall  the box at TALL_ASPECT (1.1), for a phone in portrait: the land
--         fills the width (12 % bigger than in wide) and the chips stand in
--         two rows under it (wide enough for a "VT +16" plate, D-079), so a
--         390 px phone gets a 390 x 354 map instead of 390 x 244
-- In both, Alaska and Hawaii sit in hairline inset boxes in the Pacific under
-- California: Alaska at INSET_AK of its generated size over Hawaii at
-- INSET_HI (its islands are specks otherwise). MapShape.fit picks the layout for a box of a given size.
--
-- Taps (Layout.resolve): a point in the callout band picks the nearest chip; a
-- point inside a state's outline picks that state (so a neighbor's bigger tap
-- square never steals it); anything else (a border line, the coast, the sea
-- next to a small state) goes to the tap square that was pressed.
--
-- The module-level functions (list, get, contains, at, chipAt, resolve,
-- labelAt, roomPx) are the wide layout's, as before.

local Data = require("./MapShapeData")
local MapLayout = require("./MapLayout")

export type Shape = Data.Shape
export type Rect = Data.Rect
export type Kind = "wide" | "tall"

type Box = { x0: number, y0: number, x1: number, y1: number }

export type Layout = {
	kind: Kind,
	aspect: number, -- box width / height
	land: Rect, -- the border overlay's rect (every state but the callout chips)
	legend: Rect, -- the strip for the legend row, clear of land and chips
	chips: Rect, -- the callout band (a column in wide, a row in tall)
	row: boolean, -- the chips stand in a row (tall)
	insets: { [string]: Rect }, -- the hairline boxes around AK and HI
	-- The callout bracket: polylines (x1, y1, x2, y2, ...) tying the chips to
	-- the Northeast coast, drawn instead of nine leader lines (D-079).
	bracket: { { number } },
	shapes: { Shape },
	list: () -> { Shape },
	get: (id: string) -> Shape?,
	contains: (id: string, x: number, y: number) -> boolean,
	at: (x: number, y: number) -> string?,
	chipAt: (x: number, y: number) -> string?,
	resolve: (x: number, y: number, pressed: string?) -> string?,
	labelAt: (id: string) -> (number, number),
	roomPx: (id: string, widthPx: number) -> number,
	-- A callout state's leader (shown while its chip is selected or hovered):
	-- a polyline from its chip to its real place; nil for other states.
	leader: (id: string) -> { number }?,
}

local MapShape = {}

MapShape.data = Data
MapShape.ASPECT = Data.ASPECT
MapShape.TALL_ASPECT = 1.1 -- the tall layout's box width / height (two chip rows under the land)
MapShape.TALL_BELOW = 480 -- px: a map box narrower than this may stand up (a phone in portrait)
MapShape.LADDER = MapLayout.LADDER

-- Display constants (presentation only).
local INSET_AK = 0.45 -- Alaska's size in its inset, share of the generated one (it is huge and worth 3)
local INSET_HI = 1.4 -- Hawaii's size in its inset, x the generated one (its islands are specks otherwise)
local INSET_GAP = 0.008 -- box widths between the two insets' boxes
local INSET_PAD = 0.006 -- box widths between an inset's land and its hairline box
local TALL_SIDE = 0.012 -- box widths of margin left and right of the land in tall
local TALL_TOP = 0.004 -- box heights of margin over the land in tall
local TALL_CHIP_PX = 38 -- px at MapLayout.PHONE_WIDTH: one chip row's height in tall (a 36 px target and a gap)
local TALL_CHIP_ROWS = 2 -- chip rows in tall: wide enough cells for a "VT +16" plate (D-079)
local TALL_GAP = 0.005 -- box heights between the land and the chip row, and the row and the legend
local BRACKET_TICK = 0.012 -- box widths, the bracket's ends turning toward the coast
local HI_LABEL_X, HI_LABEL_Y = 0.74, 0.3 -- Hawaii's label in its box, shares of the box (the free sea)

-- ---------------------------------------------------------------- hit tests

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

-- ---------------------------------------------------------------- transforms

type Xform = (x: number, y: number) -> (number, number)

local function mapRing(ring: { number }, f: Xform): { number }
	local out = table.create(#ring)
	for i = 1, #ring, 2 do
		out[i], out[i + 1] = f(ring[i], ring[i + 1])
	end
	return out
end

local function mapRect(r: Rect, f: Xform): Rect
	local x0, y0 = f(r.x, r.y)
	local x1, y1 = f(r.x + r.w, r.y + r.h)
	return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

-- A shape moved by `f` (a uniform scale and a shift in px), its room scaled by
-- `s`; `anchor` (in the layout's coordinates) replaces its label anchor.
local function moved(shape: Shape, f: Xform, s: number, chip: Rect?, anchor: { number }?): Shape
	local rings, edges = {}, {}
	for k, ring in shape.rings do
		rings[k] = mapRing(ring, f)
	end
	for k, ring in shape.edges do
		edges[k] = mapRing(ring, f)
	end
	local r = mapRect({ x = shape.x, y = shape.y, w = shape.w, h = shape.h }, f)
	local lx, ly = f(shape.lx, shape.ly)
	if anchor then
		lx, ly = anchor[1], anchor[2] -- already in the layout's coordinates
	end
	local copy = table.clone(shape)
	copy.x, copy.y, copy.w, copy.h = r.x, r.y, r.w, r.h
	copy.lx, copy.ly = lx, ly
	copy.room = shape.room * s
	copy.rings, copy.edges = rings, edges
	copy.chip = chip
	return table.freeze(copy) :: Shape
end

-- A shape's land bounds (its rings), in the generated coordinates.
local function bounds(shape: Shape): Box
	local b = { x0 = math.huge, y0 = math.huge, x1 = -math.huge, y1 = -math.huge }
	for _, ring in shape.rings do
		for i = 1, #ring, 2 do
			b.x0 = math.min(b.x0, ring[i])
			b.x1 = math.max(b.x1, ring[i])
			b.y0 = math.min(b.y0, ring[i + 1])
			b.y1 = math.max(b.y1, ring[i + 1])
		end
	end
	return b
end

-- Scale `s` about (px, py), then shift by (dx, dy): box fractions of the
-- generated (wide) box, where a uniform px scale is the same factor on x and y.
local function similarity(s: number, px: number, py: number, dx: number, dy: number): Xform
	return function(x: number, y: number): (number, number)
		return px + s * (x - px) + dx, py + s * (y - py) + dy
	end
end

local raw: { Shape } = Data.shapes
local rawById: { [string]: Shape } = {}
for _, shape in raw do
	rawById[shape.id] = shape
end

-- Alaska and Hawaii in their insets (generated coordinates), stacked in the
-- Pacific under California and west of Arizona and Texas: Hawaii grown at the
-- bottom left, Alaska shrunk above it. Each gets a transform, a room factor
-- and a hairline box.
local insetXform: { [string]: Xform } = {}
local insetScale: { [string]: number } = {}
local insetBox: { [string]: Rect } = {}
local insetAnchor: { [string]: { number } } = {} -- generated coordinates, after the inset's move
do
	local ak = bounds(rawById.AK)
	local hi = bounds(rawById.HI)
	local padY = INSET_PAD * Data.ASPECT -- the same px as INSET_PAD across
	local gapY = INSET_GAP * Data.ASPECT
	local left = ak.x0 + INSET_PAD -- the insets' land starts here
	local bottom = ak.y1 -- ... and Hawaii's ends here (the land's bottom)
	local hiW, hiH = INSET_HI * (hi.x1 - hi.x0), INSET_HI * (hi.y1 - hi.y0)
	insetXform.HI = similarity(INSET_HI, hi.x0, hi.y1, left - hi.x0, bottom - hi.y1)
	-- Hawaii's room is the inset's free sea (make.py), which does not grow with it.
	insetScale.HI = 1
	local hiTop = bottom - hiH
	local akW, akH = INSET_AK * (ak.x1 - ak.x0), INSET_AK * (ak.y1 - ak.y0)
	local akBottom = hiTop - 2 * padY - gapY
	insetXform.AK = similarity(INSET_AK, ak.x0, ak.y1, left - ak.x0, akBottom - ak.y1)
	insetScale.AK = INSET_AK
	insetBox.HI = { x = left - INSET_PAD, y = hiTop - padY, w = hiW + 2 * INSET_PAD, h = hiH + 2 * padY }
	-- Hawaii's label stands in the free sea at its box's top right (the islands
	-- run from the top left to the bottom right), like an inset's title, so it
	-- never covers the Big Island.
	local box = insetBox.HI
	insetAnchor.HI = { box.x + box.w * HI_LABEL_X, box.y + box.h * HI_LABEL_Y }
	insetBox.AK =
		{ x = left - INSET_PAD, y = akBottom - akH - padY, w = akW + 2 * INSET_PAD, h = akH + 2 * padY }
end

-- ---------------------------------------------------------------- layouts

local function build(kind: Kind): Layout
	local aspect = if kind == "tall" then MapShape.TALL_ASPECT else Data.ASPECT
	local borders = Data.borders
	-- The land transform: identity in wide; in tall the land is scaled by k
	-- (the same px factor across and down) to fill the width.
	local land: Xform
	local k = 1
	if kind == "tall" then
		k = (1 - 2 * TALL_SIDE) / borders.w
		local ratio = aspect / Data.ASPECT -- a generated box height in tall box heights, per box width
		local x0, y0 = borders.x, borders.y
		land = function(x: number, y: number): (number, number)
			return TALL_SIDE + k * (x - x0), TALL_TOP + k * ratio * (y - y0)
		end
	else
		land = function(x: number, y: number): (number, number)
			return x, y
		end
	end
	local landRect = mapRect({ x = borders.x, y = borders.y, w = borders.w, h = borders.h }, land)

	-- The callout band and each chip's rect.
	local chipRects: { [string]: Rect } = {}
	local band: Rect
	local legend: Rect
	if kind == "tall" then
		local bottom = landRect.y + landRect.h
		local chipH = TALL_CHIP_PX / MapLayout.PHONE_WIDTH * aspect -- box heights, one row
		local top = bottom + TALL_GAP
		band = { x = TALL_SIDE, y = top, w = 1 - 2 * TALL_SIDE, h = chipH * TALL_CHIP_ROWS }
		-- North to south in reading order: VT NH MA RI CT / NJ DE MD DC.
		local perRow = math.ceil(#MapLayout.LADDER / TALL_CHIP_ROWS)
		local pitch = band.w / perRow
		for i, id in MapLayout.LADDER do
			local row = (i - 1) // perRow
			local col = (i - 1) % perRow
			chipRects[id] = { x = band.x + col * pitch, y = top + row * chipH, w = pitch, h = chipH }
		end
		local legendTop = top + band.h + TALL_GAP
		legend = { x = TALL_SIDE, y = legendTop, w = 1 - 2 * TALL_SIDE, h = 1 - legendTop - TALL_GAP / 2 }
	else
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for _, id in MapLayout.LADDER do
			local chip = rawById[id].chip :: Rect
			chipRects[id] = chip
			x0, y0 = math.min(x0, chip.x), math.min(y0, chip.y)
			x1, y1 = math.max(x1, chip.x + chip.w), math.max(y1, chip.y + chip.h)
		end
		band = { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
		legend = Data.legend
	end

	local shapes: { Shape } = {}
	local byId: { [string]: Shape } = {}
	for i, shape in raw do
		local f: Xform = land
		local s = k
		local inset = insetXform[shape.id]
		if inset then
			f = function(x: number, y: number): (number, number)
				return land(inset(x, y))
			end
			s = k * insetScale[shape.id]
		end
		local anchor = insetAnchor[shape.id]
		local made =
			moved(shape, f, s, chipRects[shape.id], if anchor then { land(anchor[1], anchor[2]) } else nil)
		shapes[i] = made
		byId[shape.id] = made
	end
	local insets: { [string]: Rect } = {}
	for id, box in insetBox do
		insets[id] = mapRect(box, land)
	end

	-- The Northeast coast the chips stand for: the callout states' bounds.
	local ne = { x0 = math.huge, y0 = math.huge, x1 = -math.huge, y1 = -math.huge }
	for _, id in MapLayout.LADDER do
		local b = bounds(byId[id])
		ne.x0, ne.y0 = math.min(ne.x0, b.x0), math.min(ne.y0, b.y0)
		ne.x1, ne.y1 = math.max(ne.x1, b.x1), math.max(ne.y1, b.y1)
	end
	local bracket: { { number } }
	local tickY = BRACKET_TICK * aspect -- the same px as BRACKET_TICK across
	if kind == "tall" then
		-- Down the sea east of the coast, then along the top of the chip row.
		local x = math.min(1 - TALL_SIDE / 2, ne.x1 + BRACKET_TICK)
		local rowTop = band.y - TALL_GAP / 2
		bracket = {
			{ x - BRACKET_TICK, ne.y0, x, ne.y0, x, rowTop, band.x, rowTop },
			{ x, ne.y1, x - BRACKET_TICK, ne.y1 },
		}
	else
		-- A brace left of the column, its point at the coast's middle.
		local x = band.x - BRACKET_TICK / 2
		local mid = (ne.y0 + ne.y1) / 2
		bracket = {
			{
				x,
				band.y + tickY,
				x,
				mid - tickY,
				x - BRACKET_TICK,
				mid,
				x,
				mid + tickY,
				x,
				band.y + band.h - tickY,
			},
		}
	end

	local ringBoxes: { [string]: { Box } } = {}
	for _, shape in shapes do
		local list = {}
		for _, ring in shape.rings do
			local b = { x0 = math.huge, y0 = math.huge, x1 = -math.huge, y1 = -math.huge }
			for i = 1, #ring, 2 do
				b.x0 = math.min(b.x0, ring[i])
				b.x1 = math.max(b.x1, ring[i])
				b.y0 = math.min(b.y0, ring[i + 1])
				b.y1 = math.max(b.y1, ring[i + 1])
			end
			table.insert(list, b)
		end
		ringBoxes[shape.id] = list
	end

	local layout = {} :: Layout
	layout.kind = kind
	layout.aspect = aspect
	layout.land = landRect
	layout.legend = legend
	layout.chips = band
	layout.row = kind == "tall"
	layout.insets = insets
	layout.bracket = bracket
	layout.shapes = shapes

	function layout.list(): { Shape }
		return shapes
	end

	function layout.get(id: string): Shape?
		return byId[id]
	end

	-- Is (x, y) inside the state's outline (any of its islands)?
	function layout.contains(id: string, x: number, y: number): boolean
		local shape = byId[id]
		if shape == nil then
			return false
		end
		for n, ring in shape.rings do
			local b = ringBoxes[id][n]
			if x >= b.x0 and x <= b.x1 and y >= b.y0 and y <= b.y1 and inRing(ring, x, y) then
				return true
			end
		end
		return false
	end

	-- The state whose outline holds (x, y), or nil (the sea, a border line).
	function layout.at(x: number, y: number): string?
		for _, shape in shapes do
			if layout.contains(shape.id, x, y) then
				return shape.id
			end
		end
		return nil
	end

	-- The callout chip nearest (x, y) when the point is in the callout band, else nil.
	function layout.chipAt(x: number, y: number): string?
		local inBand = if layout.row then y >= band.y else x >= band.x
		if not inBand then
			return nil
		end
		local best, bestD = nil, math.huge
		for _, id in MapLayout.LADDER do
			local chip = chipRects[id]
			-- (Across a row of chips: the nearest by distance, y in box widths.)
			local d = if layout.row
				then (x - (chip.x + chip.w / 2)) ^ 2 + ((y - (chip.y + chip.h / 2)) / aspect) ^ 2
				else math.abs(y - (chip.y + chip.h / 2))
			if d < bestD then
				best, bestD = id, d
			end
		end
		return best
	end

	-- Which state a tap at (x, y) means; `pressed` is the tap square that got it
	-- (nil: a tap on open map, which then selects nothing).
	function layout.resolve(x: number, y: number, pressed: string?): string?
		return layout.chipAt(x, y) or layout.at(x, y) or pressed
	end

	-- Where a state's label (and its marks) sit: its anchor; a callout state's chip center.
	function layout.labelAt(id: string): (number, number)
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
	function layout.roomPx(id: string, widthPx: number): number
		local shape = byId[id]
		return if shape then shape.room * widthPx else 0
	end

	function layout.leader(id: string): { number }?
		local shape = byId[id]
		local chip = if shape then shape.chip else nil
		if shape == nil or chip == nil then
			return nil
		end
		if layout.row then
			-- Up from the chip to the bracket, along it to the coast, up to the state.
			local line = bracket[1]
			local x, rowTop = line[5], line[6]
			local cx = chip.x + chip.w / 2
			return { cx, chip.y, cx, rowTop, x, rowTop, x, shape.ly, shape.lx, shape.ly }
		end
		return { chip.x, chip.y + chip.h / 2, shape.lx, shape.ly }
	end

	return table.freeze(layout)
end

local layouts: { [Kind]: Layout } = {}

-- The layout of `kind` (built once).
function MapShape.layout(kind: Kind): Layout
	local made = layouts[kind]
	if made == nil then
		made = build(kind)
		layouts[kind] = made
	end
	return made
end

-- The layout for a map that may be up to `widthPx` x `heightPx`: tall when the
-- box is narrow (a phone in portrait) and standing up shows the land bigger,
-- else wide. Returns the kind and its aspect; screens size the map's box with
-- it, and the map picks the same kind from that box.
function MapShape.fit(widthPx: number, heightPx: number): (Kind, number)
	if widthPx <= 0 or widthPx >= MapShape.TALL_BELOW then
		return "wide", Data.ASPECT
	end
	local h = if heightPx > 0 then heightPx else math.huge
	local wide, tall = MapShape.layout("wide"), MapShape.layout("tall")
	local wideLand = wide.land.w * math.min(widthPx, h * wide.aspect)
	local tallLand = tall.land.w * math.min(widthPx, h * tall.aspect)
	if tallLand > wideLand + 0.5 then
		return "tall", tall.aspect
	end
	return "wide", Data.ASPECT
end

-- The box's height for a map `widthPx` wide that may be up to `heightPx` tall
-- (the layout MapShape.fit picks).
function MapShape.heightFor(widthPx: number, heightPx: number): number
	local _, aspect = MapShape.fit(widthPx, heightPx)
	return math.floor(math.min(widthPx / aspect, if heightPx > 0 then heightPx else math.huge))
end

-- ---------------------------------------------------------------- the wide layout, as before

local wide = MapShape.layout("wide")

-- Every state, in StateData order.
function MapShape.list(): { Shape }
	return wide.shapes
end

function MapShape.get(id: string): Shape?
	return wide.get(id)
end

function MapShape.contains(id: string, x: number, y: number): boolean
	return wide.contains(id, x, y)
end

function MapShape.at(x: number, y: number): string?
	return wide.at(x, y)
end

function MapShape.chipAt(x: number, y: number): string?
	return wide.chipAt(x, y)
end

function MapShape.resolve(x: number, y: number, pressed: string?): string?
	return wide.resolve(x, y, pressed)
end

function MapShape.labelAt(id: string): (number, number)
	return wide.labelAt(id)
end

function MapShape.roomPx(id: string, widthPx: number): number
	return wide.roomPx(id, widthPx)
end

return table.freeze(MapShape)
