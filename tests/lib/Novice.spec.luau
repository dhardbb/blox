--!strict
-- The scripted first-time players of the Easy-bot study (tests/lib/Novice.luau,
-- tests/harness/novice.luau): every input legal from either seat, the same
-- match from the same seed, and the habits they are meant to have.

local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local Match = require("@sim/Match")
local Novice = require("./Novice")
local Rng = require("@sim/Rng")
local Test = require("./Test")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local config = Config.defaults

type Run = { invalid: number, winner: number, ev: { number }, cash: number, kinds: { [string]: number } }

-- One match: the novice in `seat`, the study's Easy bot (the Hazy profile, D-087) in the other.
local function run(params: Novice.Params, seed: number, seat: number): Run
	local match = Match.new(config, seed, { "p1", "p2" })
	local rngs = { Rng.new(seed * 2 + 101), Rng.new(seed * 2 + 102) }
	local candidates = { "okafor", "calloway" }
	local invalid = 0
	local kinds: { [string]: number } = {}
	while match.phase ~= "Done" do
		local inputs = {}
		if Match.wantsInput(match) then
			for p = 1, 2 do
				local view = View.build(config, match, p)
				local input
				if p == seat then
					input = Novice.act(config, view, rngs[p], candidates[p], params)
					if input ~= nil and match.phase == "Plan" then
						for _, action in input.actions do
							kinds[action.kind] = (kinds[action.kind] or 0) + 1
						end
					end
				else
					input = Bot.act(config, view, rngs[p], candidates[p], "Hazy")
				end
				if input ~= nil and not Match.validate(config, match, p, input) then
					invalid += 1
					input = nil
				end
				inputs[p] = input
			end
		end
		match = Match.advance(config, match, inputs)
	end
	local result = match.election :: any
	return {
		invalid = invalid,
		winner = result.winner,
		ev = result.ev,
		cash = match.players[seat].cash,
		kinds = kinds,
	}
end

describe("Novice players (Easy-bot study)", function()
	it("every variant plays a whole match from either seat with only legal inputs", function()
		for _, name in Novice.NAMES do
			for seat = 1, 2 do
				local r = run(Novice.VARIANTS[name], 900 + seat, seat)
				expect(r.invalid):toBe(0)
				expect(r.ev[1] + r.ev[2] > 0):toBe(true)
			end
		end
	end)

	it("the same seed plays the same match", function()
		local a = run(Novice.VARIANTS.Typical, 913, 1)
		local b = run(Novice.VARIANTS.Typical, 913, 1)
		expect(a.ev[1]):toBe(b.ev[1])
		expect(a.ev[2]):toBe(b.ev[2])
		expect(a.cash):toBe(b.cash)
	end)

	it("plays like the playtests: rallies and fundraisers, ads, no polls, attacks or pivots", function()
		for _, name in Novice.NAMES do
			local r = run(Novice.VARIANTS[name], 921, 2)
			expect((r.kinds.Rally or 0) > 0):toBe(true)
			expect((r.kinds.Fundraise or 0) > 0):toBe(true)
			expect((r.kinds.Media or 0) > 0):toBe(true)
			expect(r.kinds.Poll):toBe(nil)
			expect(r.kinds.RegionPoll):toBe(nil)
			expect(r.kinds.Attack):toBe(nil)
			expect(r.kinds.Pivot):toBe(nil)
		end
	end)

	it("the weak novice sits on more money than the attentive one", function()
		local weak, attentive = 0, 0
		for k = 1, 3 do
			weak += run(Novice.VARIANTS.Weak, 930 + k, 1).cash
			attentive += run(Novice.VARIANTS.Attentive, 930 + k, 1).cash
		end
		expect(weak > attentive + 30):toBe(true)
	end)

	it("hands a delegated phase to the standard bot", function()
		local params = table.clone(Novice.VARIANTS.Weak)
		params.delegate = { Plan = true }
		local r = run(params, 941, 1)
		expect(r.invalid):toBe(0)
		expect((r.kinds.Poll or 0) > 0):toBe(true) -- the standard bot polls; a novice never does
	end)
end)
