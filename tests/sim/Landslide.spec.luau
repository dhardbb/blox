--!strict
-- Election.landslide (D-062): a win with strictly more than LANDSLIDE_EV_SHARE
-- of the EV in play. 538 in play at 0.70: 377 is a landslide, 376 is not.

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local Election = require("@sim/Election")
local State = require("@sim/State")
local StateData = require("@sim/StateData")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

-- An election result over every state with these totals (the per-state rows
-- only carry the state ids; the helper reads EV in play from them).
local function result(ev: { number }, winner: number, states: { string }?): State.ElectionResult
	local rows: { State.StateResult } = {}
	for _, s in StateData.list do
		if states == nil or table.find(states, s.id) then
			table.insert(rows, { state = s.id, winner = winner, margin = 1 })
		end
	end
	return {
		ev = ev,
		statesWon = { 0, 0 },
		popular = { 0, 0 },
		winner = winner,
		decidedBy = "EV",
		results = rows,
	}
end

describe("Election.landslide", function()
	it("puts the default line at 377 of 538", function()
		local total = 0
		for _, s in StateData.list do
			total += s.ev
		end
		expect(total):toBe(538)
		expect(C.LANDSLIDE_EV_SHARE):toBe(0.70)
		expect(Election.landslide(C, result({ 377, 161 }, 1))):toBe(1)
		expect(Election.landslide(C, result({ 376, 162 }, 1))):toBe(nil)
	end)

	it("works for either seat", function()
		expect(Election.landslide(C, result({ 100, 438 }, 2))):toBe(2)
		expect(Election.landslide(C, result({ 162, 376 }, 2))):toBe(nil)
	end)

	it("needs strictly more than the share", function()
		-- 0.5 of 538 is exactly 269: 269 is not "more than half", 270 is.
		local half = Config.with(C, { LANDSLIDE_EV_SHARE = 0.5 })
		expect(Election.landslide(half, result({ 269, 269 }, 1))):toBe(nil)
		expect(Election.landslide(half, result({ 270, 268 }, 1))):toBe(1)
	end)

	it("counts the EV in play, not the EV awarded", function()
		-- Tied states award nobody: 380 of 538 is still a landslide with 20 untaken.
		expect(Election.landslide(C, result({ 380, 138 }, 1))):toBe(1)
		-- A smaller board: CA (54) + TX (40) = 94 in play; 66 of 94 is 70.2%.
		expect(Election.landslide(C, result({ 66, 28 }, 1, { "CA", "TX" }))):toBe(1)
		expect(Election.landslide(C, result({ 65, 29 }, 1, { "CA", "TX" }))):toBe(nil)
	end)

	it("is never a landslide without an election or on an EV tie", function()
		expect(Election.landslide(C, nil)):toBe(nil)
		expect(Election.landslide(C, result({ 269, 269 }, 1))):toBe(nil)
		expect(Election.landslide(C, result({ 0, 0 }, 1, {}))):toBe(nil)
	end)

	it("agrees with a full counted match", function()
		local Fixtures = require("@testlib/Fixtures")
		for seed = 1, 20 do
			local match = Fixtures.campaign({ seed = seed })
			local election = Election.count(C, match)
			local winner = Election.landslide(C, election)
			local share = election.ev[election.winner] / 538
			expect(winner ~= nil):toBe(share > C.LANDSLIDE_EV_SHARE)
			if winner then
				expect(winner):toBe(election.winner)
			end
		end
	end)
end)
