--!strict
-- Seeded PRNG for the simulation: xoshiro128** seeded via splitmix32.
-- All match randomness comes from here so the same seed + inputs replays exactly.
--
-- State is a plain table of numbers so it can be cloned, serialized, and compared.
-- Use Rng.fork(rng, "label") to give each system (polls, debates, leans, ...) its own
-- stream, so adding draws to one system never shifts another system's numbers.

export type Rng = {
	s0: number,
	s1: number,
	s2: number,
	s3: number,
	spare: number?, -- second Box-Muller value, consumed by the next gaussian() call
}

local Rng = {}

local TWO_32 = 4294967296

-- 32-bit multiply without losing precision in doubles (operands split into 16-bit halves).
local function mul32(a: number, b: number): number
	local aLo, aHi = bit32.band(a, 0xFFFF), bit32.rshift(a, 16)
	local bLo, bHi = bit32.band(b, 0xFFFF), bit32.rshift(b, 16)
	local cross = bit32.band(aHi * bLo + aLo * bHi, 0xFFFF)
	return bit32.band(aLo * bLo + bit32.lshift(cross, 16), 0xFFFFFFFF)
end

-- splitmix32 step: returns (nextState, output).
local function splitmix32(x: number): (number, number)
	x = bit32.band(x + 0x9E3779B9, 0xFFFFFFFF)
	local z = x
	z = mul32(bit32.bxor(z, bit32.rshift(z, 16)), 0x85EBCA6B)
	z = mul32(bit32.bxor(z, bit32.rshift(z, 13)), 0xC2B2AE35)
	return x, bit32.bxor(z, bit32.rshift(z, 16))
end

-- FNV-1a hash of a string to 32 bits.
function Rng.hash(text: string): number
	local h = 0x811C9DC5
	for i = 1, #text do
		h = mul32(bit32.bxor(h, string.byte(text, i)), 0x01000193)
	end
	return h
end

-- Builds a generator directly from four state words (used by tests against reference vectors).
function Rng.fromState(s0: number, s1: number, s2: number, s3: number): Rng
	assert(s0 ~= 0 or s1 ~= 0 or s2 ~= 0 or s3 ~= 0, "xoshiro state must not be all zero")
	return { s0 = s0, s1 = s1, s2 = s2, s3 = s3, spare = nil }
end

-- New generator from any integer seed (taken modulo 2^32).
function Rng.new(seed: number): Rng
	assert(seed == math.floor(seed), "seed must be an integer")
	local x = seed % TWO_32
	local s0, s1, s2, s3
	x, s0 = splitmix32(x)
	x, s1 = splitmix32(x)
	x, s2 = splitmix32(x)
	x, s3 = splitmix32(x)
	if s0 == 0 and s1 == 0 and s2 == 0 and s3 == 0 then
		s0 = 1
	end
	return Rng.fromState(s0, s1, s2, s3)
end

-- Next raw 32-bit unsigned integer.
function Rng.nextU32(rng: Rng): number
	local s0, s1, s2, s3 = rng.s0, rng.s1, rng.s2, rng.s3
	local result = bit32.band(bit32.lrotate(bit32.band(s1 * 5, 0xFFFFFFFF), 7) * 9, 0xFFFFFFFF)
	local t = bit32.lshift(s1, 9)
	s2 = bit32.bxor(s2, s0)
	s3 = bit32.bxor(s3, s1)
	s1 = bit32.bxor(s1, s2)
	s0 = bit32.bxor(s0, s3)
	s2 = bit32.bxor(s2, t)
	s3 = bit32.lrotate(s3, 11)
	rng.s0, rng.s1, rng.s2, rng.s3 = s0, s1, s2, s3
	return result
end

-- Uniform float in [0, 1).
function Rng.nextFloat(rng: Rng): number
	return Rng.nextU32(rng) / TWO_32
end

-- Uniform integer in [lo, hi], inclusive, without modulo bias.
function Rng.nextInt(rng: Rng, lo: number, hi: number): number
	assert(lo == math.floor(lo) and hi == math.floor(hi), "bounds must be integers")
	assert(hi >= lo, "hi must be >= lo")
	local span = hi - lo + 1
	assert(span <= TWO_32, "range too large")
	local limit = TWO_32 - (TWO_32 % span)
	local value = Rng.nextU32(rng)
	while value >= limit do
		value = Rng.nextU32(rng)
	end
	return lo + (value % span)
end

-- Normal distribution sample (Box-Muller; caches the paired value).
function Rng.gaussian(rng: Rng, mean: number, sd: number): number
	local spare = rng.spare
	if spare ~= nil then
		rng.spare = nil
		return mean + sd * spare
	end
	local u1 = 1 - Rng.nextFloat(rng) -- (0, 1], so log never sees 0
	local u2 = Rng.nextFloat(rng)
	local radius = math.sqrt(-2 * math.log(u1))
	local angle = 2 * math.pi * u2
	rng.spare = radius * math.sin(angle)
	return mean + sd * radius * math.cos(angle)
end

-- Fisher-Yates shuffle in place; returns the same list.
function Rng.shuffle<T>(rng: Rng, list: { T }): { T }
	for i = #list, 2, -1 do
		local j = Rng.nextInt(rng, 1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

-- Independent child stream for one named purpose. Does not advance the parent,
-- so the order in which systems fork never matters.
function Rng.fork(rng: Rng, label: string): Rng
	local mixed = bit32.bxor(rng.s0, rng.s2, Rng.hash(label))
	local x = bit32.bxor(rng.s1, rng.s3)
	local s0, s1, s2, s3
	x, s0 = splitmix32(bit32.bxor(x, mixed))
	x, s1 = splitmix32(x)
	x, s2 = splitmix32(x)
	x, s3 = splitmix32(x)
	if s0 == 0 and s1 == 0 and s2 == 0 and s3 == 0 then
		s0 = 1
	end
	return Rng.fromState(s0, s1, s2, s3)
end

-- Copy of the generator's current state (for snapshots and replays).
function Rng.clone(rng: Rng): Rng
	return { s0 = rng.s0, s1 = rng.s1, s2 = rng.s2, s3 = rng.s3, spare = rng.spare }
end

return Rng
