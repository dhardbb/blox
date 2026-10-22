--!strict
-- Rng: reference vectors (from an independent Python implementation), determinism,
-- distribution sanity, and stream independence.

local Test = require("@testlib/Test")
local Rng = require("@sim/Rng")

local describe, it, expect = Test.describe, Test.it, Test.expect

local function take(rng: Rng.Rng, n: number): { number }
	local out = {}
	for i = 1, n do
		out[i] = Rng.nextU32(rng)
	end
	return out
end

describe("Rng", function()
	describe("reference vectors", function()
		it("xoshiro128** from state {1,2,3,4}", function()
			local rng = Rng.fromState(1, 2, 3, 4)
			expect(take(rng, 6)):toEqual({ 11520, 0, 5927040, 70819200, 2031721883, 1637235492 })
		end)

		it("seeds state words with splitmix32", function()
			local rng = Rng.new(42)
			expect({ rng.s0, rng.s1, rng.s2, rng.s3 }):toEqual({
				939911724,
				3948730756,
				321366731,
				3317318717,
			})
		end)

		it("hashes strings with FNV-1a", function()
			expect(Rng.hash("")):toBe(2166136261)
			expect(Rng.hash("polls")):toBe(1505267217)
			expect(Rng.hash("270")):toBe(2984279874)
		end)
	end)

	describe("determinism", function()
		it("same seed gives the same sequence", function()
			expect(take(Rng.new(270), 1000)):toEqual(take(Rng.new(270), 1000))
		end)

		it("different seeds give different sequences", function()
			local a, b = take(Rng.new(1), 8), take(Rng.new(2), 8)
			local same = 0
			for i = 1, 8 do
				if a[i] == b[i] then
					same += 1
				end
			end
			expect(same):toBeLessThan(2)
		end)

		it("accepts zero, negative, and large seeds", function()
			for _, seed in { 0, -1, -123456789, 2 ^ 40 + 7 } do
				local value = Rng.nextU32(Rng.new(seed))
				expect(value >= 0 and value < 2 ^ 32 and value == math.floor(value)):toBe(true)
			end
		end)

		it("rejects non-integer seeds", function()
			expect(function()
				Rng.new(1.5)
			end):toThrow("integer")
		end)

		it("clone continues identically and independently", function()
			local rng = Rng.new(9)
			Rng.gaussian(rng, 0, 1) -- leaves a cached spare to copy
			local copy = Rng.clone(rng)
			expect(Rng.gaussian(copy, 0, 1)):toBe(Rng.gaussian(rng, 0, 1))
			expect(take(copy, 20)):toEqual(take(rng, 20))
		end)
	end)

	describe("distributions", function()
		it("nextU32 stays within 32 bits", function()
			local rng = Rng.new(5)
			for _ = 1, 10000 do
				local v = Rng.nextU32(rng)
				if v < 0 or v >= 2 ^ 32 or v ~= math.floor(v) then
					error(`out of range: {v}`)
				end
			end
		end)

		it("nextFloat is in [0, 1) with mean near 0.5", function()
			local rng = Rng.new(6)
			local sum = 0
			for _ = 1, 20000 do
				local f = Rng.nextFloat(rng)
				if f < 0 or f >= 1 then
					error(`out of range: {f}`)
				end
				sum += f
			end
			expect(sum / 20000):toBeCloseTo(0.5, 0.01)
		end)

		it("nextInt covers [lo, hi] inclusively and evenly", function()
			local rng = Rng.new(7)
			local counts = {}
			for _ = 1, 60000 do
				local v = Rng.nextInt(rng, -2, 3)
				counts[v] = (counts[v] or 0) + 1
			end
			for v = -2, 3 do
				-- expected 10000 each; ±5% is > 10 standard deviations
				expect(counts[v]):toBeGreaterThan(9500)
				expect(counts[v]):toBeLessThan(10500)
			end
			expect(counts[-3]):toBe(nil)
			expect(counts[4]):toBe(nil)
		end)

		it("nextInt handles a single-value range", function()
			expect(Rng.nextInt(Rng.new(1), 4, 4)):toBe(4)
		end)

		it("nextInt rejects bad bounds", function()
			expect(function()
				Rng.nextInt(Rng.new(1), 3, 2)
			end):toThrow("hi must be")
			expect(function()
				Rng.nextInt(Rng.new(1), 0, 1.5)
			end):toThrow("integers")
		end)

		it("gaussian has the requested mean and spread", function()
			local rng = Rng.new(8)
			local n, sum, sumSq = 40000, 0, 0
			for _ = 1, n do
				local g = Rng.gaussian(rng, 3, 2)
				sum += g
				sumSq += g * g
			end
			local mean = sum / n
			local sd = math.sqrt(sumSq / n - mean * mean)
			expect(mean):toBeCloseTo(3, 0.05)
			expect(sd):toBeCloseTo(2, 0.05)
		end)

		it("shuffle returns a permutation", function()
			local list = {}
			for i = 1, 51 do
				list[i] = i
			end
			Rng.shuffle(Rng.new(10), list)
			local seen = {}
			for _, v in list do
				seen[v] = true
			end
			for i = 1, 51 do
				expect(seen[i]):toBe(true)
			end
			expect(#list):toBe(51)
		end)
	end)

	describe("fork", function()
		it("does not advance the parent", function()
			local a, b = Rng.new(11), Rng.new(11)
			Rng.fork(a, "polls")
			expect(take(a, 10)):toEqual(take(b, 10))
		end)

		it("is reproducible per label", function()
			expect(take(Rng.fork(Rng.new(12), "debate"), 10)):toEqual(
				take(Rng.fork(Rng.new(12), "debate"), 10)
			)
		end)

		it("gives different streams for different labels and from the parent", function()
			local parent = Rng.new(13)
			local polls = take(Rng.fork(parent, "polls"), 4)
			local leans = take(Rng.fork(parent, "leans"), 4)
			expect(polls[1] ~= leans[1]):toBe(true)
			expect(polls[1] ~= take(Rng.clone(parent), 1)[1]):toBe(true)
		end)

		it("is independent of fork order", function()
			local p1, p2 = Rng.new(14), Rng.new(14)
			local polls1 = Rng.fork(p1, "polls")
			local _ = Rng.fork(p1, "leans")
			local _ = Rng.fork(p2, "leans")
			local polls2 = Rng.fork(p2, "polls")
			expect(take(polls1, 10)):toEqual(take(polls2, 10))
		end)
	end)
end)
