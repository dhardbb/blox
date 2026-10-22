--!strict
-- The bot: always submits valid input, finishes full matches with every
-- candidate, is deterministic, and beats random play.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Play = require("@testlib/Play")
local Bot = require("@sim/Bot")
local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Election = require("@sim/Election")
local Rng = require("@sim/Rng")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

describe("Bot", function()
	it("plays a full bot-vs-bot match with only valid inputs", function()
		local record = Play.match(C, 1, { "okafor", "calloway" })
		expect(record.match.phase):toBe("Done")
		expect(record.invalid):toBe(0)
		expect(record.ev[1] + record.ev[2]):toBe(538)
		expect(record.winner == 1 or record.winner == 2):toBe(true)
		Fixtures.checkSupport(record.match)
	end)

	it("every candidate finishes a match without invalid inputs", function()
		for k, id in Candidates.ids do
			local other = Candidates.ids[k % #Candidates.ids + 1]
			local record = Play.match(C, 100 + k, { id, other })
			expect(record.invalid):toBe(0)
			expect(record.match.players[1].candidate):toBe(id)
		end
	end)

	it("every style submits only valid inputs", function()
		for k, style in { "Random", "FundraiseOnly", "RallyOnly", "AttackOnly", "NeverPoll", "Sandbag" } do
			local record = Play.match(C, 200 + k, { "strand", "begay" }, { style :: any, "Balanced" })
			expect(record.invalid):toBe(0)
		end
	end)

	it("is deterministic for a seed", function()
		local a = Play.match(C, 42, { "reyes", "venkat" })
		local b = Play.match(C, 42, { "reyes", "venkat" })
		expect(a.match):toEqual(b.match)
		expect(Election.trueEV(C, a.match)):toEqual(Election.trueEV(C, b.match))
	end)

	it("beats a random bot at least 95% of the time", function()
		local wins, n = 0, 40
		for k = 1, n do
			local styles = if k % 2 == 0 then { "Random", "Balanced" } else { "Balanced", "Random" }
			local record = Play.match(C, 300 + k, { "hale", "hale" }, styles :: any)
			if record.styles[record.winner] == "Balanced" then
				wins += 1
			end
		end
		expect(wins / n >= 0.95):toBe(true)
	end)

	it("spends its money: little is left at the end", function()
		local record = Play.match(C, 7, { "alvarado", "okafor" })
		for p = 1, 2 do
			expect(record.unspent[p] < 15):toBe(true)
		end
	end)

	it("banks ground game from week 7, not only in the last weeks (D-021)", function()
		-- Both players' GOTV spend is recorded as plans are submitted, so a unit placed
		-- in week 7 or 8 shows up as spend before week 9 in at least one of these games.
		local early = 0
		for seed = 11, 14 do
			local match = Fixtures.advanceTo(Fixtures.campaign({ seed = seed }), "Plan", 7)
			local rng = Rng.new(seed)
			for week = 7, 8 do
				for p = 1, 2 do
					local view = View.build(C, match, p)
					local plan = Bot.act(C, view, rng, match.players[p].candidate, "Balanced")
					for _, action in plan.actions do
						if action.kind == "Gotv" then
							early += action.units
						end
					end
				end
				match = Fixtures.advanceTo(match, "Plan", week + 1)
			end
		end
		expect(early > 0):toBe(true)
	end)
end)
