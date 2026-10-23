--!strict
-- Practice bot difficulty (D-057): the names, Medium being the standard bot,
-- valid and deterministic play at every level, and fair play: every level
-- decides from its own View, so hidden state never changes a decision.

local Test = require("@testlib/Test")
local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local Match = require("@sim/Match")
local Play = require("@testlib/Play")
local Rng = require("@sim/Rng")
local State = require("@sim/State")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

describe("Bot difficulty (D-057)", function()
	it("reads a difficulty from untrusted input, Medium by default", function()
		for _, level in Bot.DIFFICULTIES do
			expect(Bot.difficulty(level)):toBe(level)
		end
		for _, bad in { nil, "", "hard", "EXTREME", "Impossible", 3, true, {} } :: { any } do
			expect(Bot.difficulty(bad)):toBe("Medium")
		end
		expect(Bot.DEFAULT_DIFFICULTY):toBe("Medium")
	end)

	it("Medium is the standard Balanced bot; the others are their own styles", function()
		expect(Bot.styleFor("Medium")):toBe("Balanced")
		expect(Bot.styleFor(nil)):toBe("Balanced")
		expect(Bot.styleFor("Easy")):toBe("Easy")
		expect(Bot.styleFor("Hard")):toBe("Hard")
		expect(Bot.styleFor("Extreme")):toBe("Extreme")
	end)

	it("every level finishes matches with only valid inputs, from either seat", function()
		for k, level in Bot.DIFFICULTIES do
			local style = Bot.styleFor(level)
			local a = Play.match(C, 900 + k, { "okafor", "strand" }, { style, "Balanced" })
			local b = Play.match(C, 910 + k, { "venkat", "hale" }, { "Balanced", style })
			expect(a.invalid):toBe(0)
			expect(b.invalid):toBe(0)
			expect(a.match.phase):toBe("Done")
			expect(b.match.phase):toBe("Done")
		end
	end)

	it("every level is deterministic: same seed and inputs, same moves", function()
		for k, level in Bot.DIFFICULTIES do
			local styles = { Bot.styleFor(level), Bot.styleFor(level) }
			local a = Play.match(C, 920 + k, { "reyes", "begay" }, styles)
			local b = Play.match(C, 920 + k, { "reyes", "begay" }, styles)
			expect(a.match):toEqual(b.match)
		end
	end)

	it("Easy still spends: it raises money and leaves little of it in the bank", function()
		local record = Play.match(C, 931, { "okafor", "hale" }, { "Easy", "Balanced" })
		expect(record.raised[1] > 10):toBe(true)
		expect(record.unspent[1] < 20):toBe(true)
	end)

	-- The same match with every hidden number moved: true support, true undecided,
	-- the opponent's ground game, the fundraising pools, the poll error terms and
	-- the opponent's private polls. None of it is in a View.
	local function disturb(match: State.MatchState, me: number): State.MatchState
		local them = if me == 1 then 2 else 1
		local copy = State.deepCopy(match)
		for _, s in copy.states do
			local shift = math.min(4, s.support[them])
			s.support[me] += shift
			s.support[them] -= shift
			s.gotv[them] = math.min(C.GOTV_MAX_UNITS, s.gotv[them] + 2)
			s.pool *= 0.5
			s.pollError[me] += 1.5
			s.pollError[them] -= 1.5
			s.pollErrorUndecided += 1
		end
		copy.players[them].internalPolls = {
			{ state = "OH", support = { 50, 40 }, undecided = 10, momentum = { 0, 3 }, gotv = { 4, 4 } },
		}
		return copy
	end

	it("Hard and Extreme decide the same when hidden state changes (fair play)", function()
		for k, level in { "Hard", "Extreme", "Easy" } :: { Bot.Difficulty } do
			local style = Bot.styleFor(level)
			local match = Match.new(C, 940 + k, { "p1", "p2" })
			local rngs = { Rng.new(1), Rng.new(2) }
			local candidates = { "calloway", "alvarado" }
			local checked = 0
			while match.phase ~= "Done" do
				local inputs = {}
				if Match.wantsInput(match) then
					local hidden = disturb(match, 1)
					local view = View.build(C, match, 1)
					expect(View.build(C, hidden, 1)):toEqual(view)
					local twin = Rng.clone(rngs[1])
					inputs[1] = Bot.act(C, view, rngs[1], candidates[1], style)
					local again = Bot.act(C, View.build(C, hidden, 1), twin, candidates[1], style)
					expect(again):toEqual(inputs[1])
					checked += 1
					inputs[2] = Bot.act(C, View.build(C, match, 2), rngs[2], candidates[2], "Balanced")
				end
				match = Match.advance(C, match, inputs)
			end
			expect(checked > C.WEEKS):toBe(true)
		end
	end)

	it("a stronger level only reads its own View: its foresight ignores the opponent's real cash", function()
		-- The opponent's exact cash is hidden; only its bracket shows. Two matches
		-- that differ only in that cash, inside one bracket, get the same plan.
		local match = Match.new(C, 951, { "p1", "p2" })
		local rngs = { Rng.new(3), Rng.new(4) }
		while match.phase ~= "Plan" or match.week < 6 do
			local inputs = {}
			if Match.wantsInput(match) then
				for p = 1, 2 do
					inputs[p] =
						Bot.act(C, View.build(C, match, p), rngs[p], if p == 1 then "hale" else "reyes")
				end
			end
			match = Match.advance(C, match, inputs)
		end
		local richer = State.deepCopy(match)
		local cash = richer.players[2].cash
		local bracket = View.moneyBracket(C, cash)
		local nudged = if bracket == "Low"
			then cash * 0.5
			elseif bracket == "High" then cash + 5
			else C.OPPONENT_MONEY_LOW
		richer.players[2].cash = nudged
		expect(View.moneyBracket(C, nudged)):toBe(bracket)
		for _, level in { "Hard", "Extreme" } :: { Bot.Difficulty } do
			local a = Bot.act(C, View.build(C, match, 1), Rng.new(9), "hale", Bot.styleFor(level))
			local b = Bot.act(C, View.build(C, richer, 1), Rng.new(9), "hale", Bot.styleFor(level))
			expect(b):toEqual(a)
		end
	end)
end)
