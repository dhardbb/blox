--!strict
-- Support model: saturation, the undecided/opponent split, renormalization, and
-- national shifts.

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local State = require("@sim/State")
local Support = require("@sim/Support")
local StateData = require("@sim/StateData")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function stateSim(a: number, b: number, u: number): State.StateSim
	return {
		id = "OH",
		ev = 17,
		support = { a, b },
		undecided = u,
		lean = 0,
		leanTo = nil,
		capacity = 9,
		pool = 9,
		battleground = false,
		owner = nil,
		isHome = false,
		momentum = { 0, 0 },
		backlash = { 0, 0 },
		gotv = { 0, 0 },
		debateShift = { 0, 0 },
		pollError = { 0, 0 },
		pollErrorUndecided = 0,
		poll = nil,
	}
end

describe("Support.saturation", function()
	it("is 1 up to the base, the floor near the cap", function()
		expect(Support.saturation(C, 20)):toBe(1)
		expect(Support.saturation(C, 35)):toBe(1)
		expect(Support.saturation(C, 53.5)):toBeCloseTo(0.5)
		expect(Support.saturation(C, 71)):toBe(C.SATURATION_FLOOR)
		expect(Support.saturation(C, 90)):toBe(C.SATURATION_FLOOR)
	end)
end)

describe("Support gains", function()
	it("take 70% from undecided and 30% from the opponent", function()
		local s = stateSim(35, 35, 30)
		Support.gain(C, s, 1, 10)
		expect(s.support[1]):toBeCloseTo(45)
		expect(s.support[2]):toBeCloseTo(32)
		expect(s.undecided):toBeCloseTo(23)
	end)

	it("come entirely from the opponent below the undecided floor", function()
		local s = stateSim(50, 45, 5)
		Support.gain(C, s, 2, 4)
		expect(s.support[1]):toBeCloseTo(46)
		expect(s.support[2]):toBeCloseTo(49)
		expect(s.undecided):toBeCloseTo(5)
	end)

	it("simultaneous equal gains leave a symmetric state symmetric (D-001)", function()
		local s = stateSim(35, 35, 30)
		local delta = Support.zero(s)
		local du = Support.addGain(C, s, 1, 3, delta) + Support.addGain(C, s, 2, 3, delta)
		Support.apply(s, delta, du)
		expect(s.support[1]):toBeCloseTo(s.support[2], 1e-12)
		expect(s.support[1] + s.support[2] + s.undecided):toBeCloseTo(100)
	end)

	it("renormalizes to 100 and clamps at zero", function()
		local s = stateSim(2, 68, 30)
		local delta = Support.zero(s)
		local du = Support.addAttack(C, 2, 1, 10, delta)
		Support.apply(s, delta, du)
		expect(s.support[1]):toBe(0)
		expect(s.support[1] + s.support[2] + s.undecided):toBeCloseTo(100)
	end)

	it("attacks send 60% of the loss to undecided and 40% to the attacker", function()
		local s = stateSim(40, 40, 20)
		local delta = Support.zero(s)
		local du = Support.addAttack(C, 1, 2, 2, delta)
		Support.apply(s, delta, du)
		expect(s.support[2]):toBeCloseTo(38)
		expect(s.support[1]):toBeCloseTo(40.8)
		expect(s.undecided):toBeCloseTo(21.2)
	end)

	it("margin is the lead over the best opponent", function()
		local s = stateSim(48, 42, 10)
		expect(Support.margin(s, 1)):toBeCloseTo(6)
		expect(Support.margin(s, 2)):toBeCloseTo(-6)
	end)
end)

describe("Support.national", function()
	local function allStates(): { State.StateSim }
		local list = {}
		for i, record in StateData.list do
			local u = 20 + (i % 5) * 5 -- undecided varies by state
			local s = stateSim((100 - u) / 2, (100 - u) / 2, u)
			s.id = record.id
			list[i] = s
		end
		return list
	end

	it("moves the population-weighted average by exactly X (D-010)", function()
		local states = allStates()
		local before, weights = 0, 0
		for i, s in states do
			before += StateData.list[i].pop * s.support[1]
			weights += StateData.list[i].pop
		end
		Support.national(C, states, { 0.8, 0 })
		local after = 0
		for i, s in states do
			after += StateData.list[i].pop * s.support[1]
		end
		expect((after - before) / weights):toBeCloseTo(0.8, 1e-9)
	end)

	it("moves states with more undecided further", function()
		local states = allStates()
		local low, high = states[5], states[4] -- 20 vs 40 undecided
		expect(low.undecided < high.undecided):toBe(true)
		local lowBefore, highBefore = low.support[2], high.support[2]
		Support.national(C, states, { 0, -1 })
		expect(highBefore - high.support[2] > lowBefore - low.support[2]):toBe(true)
	end)
end)
