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

local KINDS: { MapShape.Kind } = { "wide", "tall" }

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

	it("puts every label anchor inside its own state (Hawaii's: its inset's free sea)", function()
		for _, kind in KINDS do
			local geo = MapShape.layout(kind)
			for _, s in geo.list() do
				check(s.room > 0, `{kind} {s.id} has no room`)
				if s.id == "HI" then
					local box = geo.insets.HI
					check(
						s.lx > box.x and s.lx < box.x + box.w and s.ly > box.y and s.ly < box.y + box.h,
						`{kind} HI's label is outside its inset`
					)
					expect(geo.at(s.lx, s.ly)):toBe(nil)
				else
					check(
						geo.contains(s.id, s.lx, s.ly),
						`{kind} {s.id} anchor ({s.lx}, {s.ly}) is outside its outline`
					)
					expect(geo.at(s.lx, s.ly)):toBe(s.id)
				end
			end
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
		expect(MapShape.layout("tall").resolve(0.5, 0.01, nil)):toBe(nil)
	end)
end)

describe("MapShape layouts (D-079)", function()
	it("keeps the wide layout as before, and stands the tall one up at 1.25", function()
		local wide, tall = MapShape.layout("wide"), MapShape.layout("tall")
		expect(wide.aspect):toBe(MapLayout.ASPECT)
		expect(tall.aspect):toBe(MapShape.TALL_ASPECT)
		for i, s in wide.list() do
			expect(tall.list()[i].id):toBe(s.id)
			if s.id ~= "AK" and s.id ~= "HI" then
				expect(s.lx):toBe(MapShape.data.shapes[i].lx)
				expect(s.room):toBe(MapShape.data.shapes[i].room)
			end
		end
		-- On a 390 px phone the tall map's land is bigger than the wide map's.
		check(tall.land.w > wide.land.w * 1.1, "the tall layout's land is not bigger")
	end)

	it("keeps every sprite, inset, chip and the legend inside the box in both layouts", function()
		for _, kind in KINDS do
			local geo = MapShape.layout(kind)
			local function inside(r: MapShape.Rect, what: string)
				check(
					r.x >= -1e-3 and r.y >= -1e-3 and r.x + r.w <= 1.001 and r.y + r.h <= 1.001,
					`{kind}: {what} leaves the box`
				)
			end
			for _, s in geo.list() do
				inside({ x = s.x, y = s.y, w = s.w, h = s.h }, `{s.id}'s sprite`)
				if s.chip then
					inside(s.chip, `{s.id}'s chip`)
				end
			end
			inside(geo.legend, "the legend")
			for id, box in geo.insets do
				inside(box, `{id}'s inset`)
			end
		end
	end)

	it("keeps every other state's land out of the Alaska and Hawaii insets", function()
		for _, kind in KINDS do
			local geo = MapShape.layout(kind)
			for id, box in geo.insets do
				for _, s in geo.list() do
					if s.id ~= "AK" and s.id ~= "HI" then
						for _, ring in s.rings do
							for i = 1, #ring, 2 do
								local x, y = ring[i], ring[i + 1]
								check(
									not (x > box.x and x < box.x + box.w and y > box.y and y < box.y + box.h),
									`{kind}: {s.id} reaches into {id}'s inset`
								)
							end
						end
					end
				end
				local own = geo.get(id) :: MapShape.Shape
				for _, ring in own.rings do
					for i = 1, #ring, 2 do
						check(
							ring[i] >= box.x
								and ring[i] <= box.x + box.w
								and ring[i + 1] >= box.y
								and ring[i + 1] <= box.y + box.h,
							`{kind}: {id} pokes out of its inset`
						)
					end
				end
			end
			local a, h = geo.insets.AK, geo.insets.HI
			check(
				not (a.y + a.h > h.y and h.y + h.h > a.y and a.x + a.w > h.x and h.x + h.w > a.x),
				"insets overlap"
			)
		end
	end)

	it("stands the tall layout's chips in one row under all land, north to south, 36 px wide", function()
		local geo = MapShape.layout("tall")
		local south = 0
		for _, s in geo.list() do
			for _, ring in s.rings do
				for i = 2, #ring, 2 do
					south = math.max(south, ring[i])
				end
			end
		end
		local previous = -1
		for _, id in MapLayout.LADDER do
			local chip = (geo.get(id) :: MapShape.Shape).chip :: MapShape.Rect
			check(chip.y > south, `{id}'s chip overlaps land`)
			check(chip.x >= previous - 1e-6, `{id}'s chip is out of order`)
			previous = chip.x + chip.w
			check(
				chip.w * MapLayout.PHONE_WIDTH >= MapLayout.MIN_HIT - 1e-6,
				`{id}'s chip is under 36 px wide`
			)
			check(
				chip.h * MapLayout.PHONE_WIDTH / geo.aspect >= MapLayout.MIN_HIT - 1e-6,
				`{id}'s chip is under 36 px tall`
			)
			local cx, cy = geo.labelAt(id)
			expect(geo.chipAt(cx, cy)):toBe(id)
			expect(geo.resolve(chip.x + chip.w * 0.05, cy, nil)):toBe(id)
			expect(geo.resolve(chip.x + chip.w * 0.95, chip.y + chip.h, "TX")):toBe(id)
			-- Its leader runs from the chip to its state.
			local path = geo.leader(id) :: { number }
			check(#path >= 4, `{id} has no leader`)
			local shape = geo.get(id) :: MapShape.Shape
			expect(path[#path - 1]):toBe(shape.lx)
			expect(path[#path]):toBe(shape.ly)
		end
		expect(geo.legend.y > geo.chips.y + geo.chips.h - 1e-6):toBe(true)
	end)

	it("resolves taps by outline in the tall layout too", function()
		local geo = MapShape.layout("tall")
		local stolen = 0
		local half = MapLayout.MIN_HIT / 2 / MapLayout.PHONE_WIDTH
		for _, s in geo.list() do
			if s.chip == nil then
				for gx = -4, 4 do
					for gy = -4, 4 do
						local x = s.lx + gx / 4 * half
						local y = s.ly + gy / 4 * half * geo.aspect
						local inside = geo.at(x, y)
						local got = geo.resolve(x, y, s.id)
						if inside then
							expect(got):toBe(inside)
							if inside ~= s.id then
								stolen += 1
							end
						else
							expect(got):toBe(geo.chipAt(x, y) or s.id)
						end
					end
				end
			end
		end
		check(stolen > 0, "no square overlapped a neighbor: the sample proves nothing")
	end)

	it("fits the layout to the room: tall on a phone in portrait, wide on an iPad or a short box", function()
		expect((MapShape.fit(358, 400))):toBe("tall")
		expect((MapShape.fit(390, 312))):toBe("tall")
		expect((MapShape.fit(358, 200))):toBe("wide") -- short: the wide map is bigger
		expect((MapShape.fit(620, 600))):toBe("wide") -- an iPad's map column
		expect((MapShape.fit(1000, 0))):toBe("wide")
		expect(MapShape.heightFor(390, 400)):toBe(math.floor(390 / MapShape.TALL_ASPECT))
		expect(MapShape.heightFor(620, 600)):toBe(math.floor(620 / MapLayout.ASPECT))
		-- The box a screen makes from heightFor asks for the same layout again.
		for _, w in { 300, 340, 358, 372, 390, 470 } do
			for _, hmax in { 150, 200, 250, 300, 350, 500 } do
				local kind = MapShape.fit(w, hmax)
				local h = MapShape.heightFor(w, hmax)
				expect((MapShape.fit(w, h))):toBe(kind)
			end
		end
	end)

	it("draws a bracket from the chips to the Northeast coast in both layouts", function()
		for _, kind in KINDS do
			local geo = MapShape.layout(kind)
			check(#geo.bracket >= 1, `{kind}: no bracket`)
			for _, line in geo.bracket do
				check(#line >= 4 and #line % 2 == 0, `{kind}: a bracket line has {#line} numbers`)
				for i = 1, #line do
					check(line[i] >= -1e-3 and line[i] <= 1.001, `{kind}: the bracket leaves the box`)
				end
			end
		end
	end)
end)
