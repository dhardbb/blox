--!strict
-- The real map's geometry (src/shared/UI/MapShape.luau and the generated
-- MapShapeData, D-070), pure: every state has a shape, a label anchor inside it
-- and a sprite inside the box and its atlas; the atlases on disk are at most
-- 1024 px; the callout chips stand east of all land; taps resolve by outline.

local fs = require("@lune/fs")

local MapLayout = require("@ui/MapLayout")
local MapShape = require("@ui/MapShape")
local StateData = require("@sim/StateData")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

-- A PNG's size from its IHDR chunk.
local function pngSize(path: string): (number, number)
	local bytes = fs.readFile(path)
	check(string.sub(bytes, 2, 4) == "PNG", `{path} is not a PNG`)
	return string.unpack(">I4I4", bytes, 17)
end

local function landEast(): number
	local east = 0
	for _, shape in MapShape.list() do
		for _, ring in shape.rings do
			for i = 1, #ring, 2 do
				east = math.max(east, ring[i])
			end
		end
	end
	return east
end

describe("MapShape (D-070)", function()
	it("has one shape per state, in StateData order, at the circle map's aspect", function()
		expect(#MapShape.list()):toBe(#StateData.list)
		for i, record in StateData.list do
			expect(MapShape.list()[i].id):toBe(record.id)
		end
		expect(MapShape.ASPECT):toBe(MapLayout.ASPECT)
	end)

	it("keeps every sprite inside the box and inside its atlas", function()
		local atlases = MapShape.data.atlases
		for _, s in MapShape.list() do
			check(s.x >= -1e-3 and s.y >= -1e-3, `{s.id} sprite starts outside the box`)
			check(s.x + s.w <= 1.001 and s.y + s.h <= 1.001, `{s.id} sprite ends outside the box`)
			local atlas = atlases[s.atlas]
			check(atlas ~= nil, `{s.id} has no atlas {s.atlas}`)
			check(s.ox >= 0 and s.oy >= 0, `{s.id} rect offset`)
			check(s.ox + s.ow <= atlas.w and s.oy + s.oh <= atlas.h, `{s.id} rect leaves its atlas`)
		end
	end)

	it("ships atlases and borders on disk at their listed sizes, none over 1024 px", function()
		for _, atlas in MapShape.data.atlases do
			local w, h = pngSize(atlas.file)
			expect(w):toBe(atlas.w)
			expect(h):toBe(atlas.h)
			check(w <= 1024 and h <= 1024, `{atlas.file} is {w}x{h}`)
		end
		local b = MapShape.data.borders
		local w, h = pngSize(b.file)
		expect(w):toBe(b.pw)
		expect(h):toBe(b.ph)
		check(w <= 1024 and h <= 1024, `{b.file} is {w}x{h}`)
	end)

	it("puts every label anchor inside its own state", function()
		for _, s in MapShape.list() do
			check(
				MapShape.contains(s.id, s.lx, s.ly),
				`{s.id} anchor ({s.lx}, {s.ly}) is outside its outline`
			)
			expect(MapShape.at(s.lx, s.ly)):toBe(s.id)
			check(s.room > 0, `{s.id} has no room`)
		end
	end)

	it("gives the nine small Northeast states chips east of all land, north to south", function()
		local east = landEast()
		local previous = -1
		for _, id in MapLayout.LADDER do
			local chip = (MapShape.get(id) :: MapShape.Shape).chip
			check(chip ~= nil, `{id} has no chip`)
			local c = chip :: MapShape.Rect
			check(c.x > east, `{id} chip overlaps land`)
			check(c.x + c.w <= 1.001 and c.y + c.h <= 1.001, `{id} chip leaves the box`)
			check(c.y >= previous - 1e-6, `{id} chip is out of order`)
			previous = c.y + c.h
			-- 36 px wide on the narrowest map; overlapping heights are settled by the nearest chip.
			check(c.w * MapLayout.PHONE_WIDTH >= MapLayout.MIN_HIT - 1e-6, `{id} chip is under 36 px wide`)
			local cx, cy = MapShape.labelAt(id)
			expect(MapShape.chipAt(cx, cy)):toBe(id)
			expect(MapShape.resolve(cx, c.y + c.h * 0.05, nil)):toBe(id)
			expect(MapShape.resolve(cx, c.y + c.h * 0.95, "VT")):toBe(id)
		end
		for _, s in MapShape.list() do
			if table.find(MapLayout.LADDER, s.id) == nil then
				check(s.chip == nil, `{s.id} should have no chip`)
			end
		end
	end)

	it("resolves a tap by outline, so a neighbor's tap square never steals it", function()
		-- Sample each state's 36 px square on a phone map: a point inside another
		-- state's outline goes to that state, whichever square was pressed.
		local stolen = 0
		local half = MapLayout.MIN_HIT / 2 / MapLayout.PHONE_WIDTH
		for _, s in MapShape.list() do
			if s.chip == nil then
				for gx = -4, 4 do
					for gy = -4, 4 do
						local x = s.lx + gx / 4 * half
						local y = s.ly + gy / 4 * half * MapShape.ASPECT
						local inside = MapShape.at(x, y)
						local got = MapShape.resolve(x, y, s.id)
						if inside then
							expect(got):toBe(inside)
							if inside ~= s.id then
								stolen += 1
							end
						else
							-- A border or the coast: the pressed square (the chip column: its chip).
							expect(got):toBe(MapShape.chipAt(x, y) or s.id)
						end
					end
				end
			end
		end
		check(stolen > 0, "no square overlapped a neighbor: the sample proves nothing")
	end)

	it("picks nothing on open sea when no square was pressed", function()
		expect(MapShape.resolve(0.5, 0.995, nil)):toBe(nil)
		expect(MapShape.resolve(0.01, 0.01, nil)):toBe(nil)
	end)
end)
