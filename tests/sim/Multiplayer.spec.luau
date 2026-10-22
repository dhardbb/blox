--!strict
-- Three and four players: the code claims n-player support, so it must not break.

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local Election = require("@sim/Election")
local Match = require("@sim/Match")
local StateData = require("@sim/StateData")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

describe("Multiplayer", function()
	it("creates matches for three and four players on every seed", function()
		for seed = 1, 60 do
			for _, ids in { { "a", "b", "c" }, { "a", "b", "c", "d" } } do
				local ok = pcall(Match.new, C, seed, ids)
				expect(ok):toBe(true)
			end
		end
	end)

	it("election tiebreaks only consider the players tied at the top", function()
		-- A and B each hold exactly 200 EV in few big states; C holds the rest (138 EV)
		-- in many small states. C has the most states but must not win the A-B tie.
		local function subset(target: number, available: { StateData.StateRecord }): { [string]: boolean }
			local reach: { [number]: { string }? } = { [0] = {} }
			for _, record in available do
				for total = target, record.ev, -1 do
					local base = reach[total - record.ev]
					if reach[total] == nil and base ~= nil then
						local list = table.clone(base)
						table.insert(list, record.id)
						reach[total] = list
					end
				end
			end
			local set = {}
			for _, id in reach[target] :: { string } do
				set[id] = true
			end
			return set
		end
		local big = {}
		for _, record in StateData.list do
			if record.ev >= 6 then
				table.insert(big, record)
			end
		end
		local a = subset(200, big)
		local rest = {}
		for _, record in big do
			if not a[record.id] then
				table.insert(rest, record)
			end
		end
		local b = subset(200, rest)
		local match = Match.new(C, 3, { "a", "b", "c" })
		for _, s in match.states do
			local o = if a[s.id] then 1 elseif b[s.id] then 2 else 3
			s.support = { if o == 1 then 70 else 10, if o == 2 then 70 else 10, if o == 3 then 70 else 10 }
			s.undecided = 10
		end
		local result = Election.count(C, match, { noise = false, gotv = false })
		expect(result.ev[1]):toBe(200)
		expect(result.ev[2]):toBe(200)
		expect(result.statesWon[3] > math.max(result.statesWon[1], result.statesWon[2])):toBe(true)
		expect(result.winner == 1 or result.winner == 2):toBe(true)
		expect(result.decidedBy ~= "EV"):toBe(true)
	end)
end)
