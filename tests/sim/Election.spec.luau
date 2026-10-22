--!strict
-- Election night (GOTV, noise, tiebreaks, reveal order) and debates.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Config = require("@sim/Config")
local Debate = require("@sim/Debate")
local Election = require("@sim/Election")
local Match = require("@sim/Match")
local State = require("@sim/State")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

-- A finished campaign with every state's truth overwritten.
local function board(fill: (s: State.StateSim, i: number) -> ()): State.MatchState
	local match = Fixtures.campaign({ seed = 31 })
	for i, s in match.states do
		s.gotv = { 0, 0 }
		fill(s, i)
	end
	return match
end

-- A subset of states holding exactly `target` EV (subset-sum by DP).
local function subsetWithEV(match: State.MatchState, target: number): { [number]: boolean }
	local reach: { [number]: { number }? } = { [0] = {} }
	for i, s in match.states do
		for total = target, s.ev, -1 do
			local base = reach[total - s.ev]
			if reach[total] == nil and base ~= nil then
				local list = table.clone(base)
				table.insert(list, i)
				reach[total] = list
			end
		end
	end
	local chosen = reach[target]
	assert(chosen, "no subset")
	local set = {}
	for _, i in chosen do
		set[i] = true
	end
	return set
end

describe("Election", function()
	it("GOTV units add to the election-day margin", function()
		local match = board(function(s)
			s.support, s.undecided = { 45, 46 }, 9
		end)
		local before = Election.count(C, match, { noise = false })
		expect(before.ev[2]):toBe(538)
		State.get(match, "OH").gotv = { 2, 0 }
		local after = Election.count(C, match, { noise = false })
		expect(after.ev[1]):toBe(17)
		expect(Election.count(C, match, { noise = false, gotv = false }).ev[1]):toBe(0)
	end)

	it("margin noise has sd about 2", function()
		local diffs = {}
		for seed = 1, 60 do
			local match = Fixtures.campaign({ seed = seed })
			for _, noise in Election.noise(C, match) do
				table.insert(diffs, noise[1] - noise[2])
			end
		end
		local sum, sq = 0, 0
		for _, d in diffs do
			sum += d
			sq += d * d
		end
		local sd = math.sqrt(sq / #diffs - (sum / #diffs) ^ 2)
		expect(math.abs(sd - C.ELECTION_SIGMA) < 0.1):toBe(true)
	end)

	it("reveals the safest states first and the closest last", function()
		local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 8 }), "Election")
		local result = match.election :: State.ElectionResult
		expect(#result.results):toBe(51)
		for k = 2, #result.results do
			expect(result.results[k - 1].margin >= result.results[k].margin):toBe(true)
		end
		expect(result.ev[1] + result.ev[2]):toBe(538)
		expect(result.ev[result.winner] >= 269):toBe(true)
	end)

	it("a 269-269 tie goes to whoever won more states", function()
		local base = Fixtures.campaign({ seed = 31 })
		local half = subsetWithEV(base, 269)
		local count = 0
		for _ in half do
			count += 1
		end
		local match = board(function(s, i)
			s.support, s.undecided = if half[i] then { 50, 40 } else { 40, 50 }, 10
		end)
		local result = Election.count(C, match, { noise = false })
		expect(result.ev):toEqual({ 269, 269 })
		expect(result.decidedBy):toBe("States")
		expect(result.winner):toBe(if count > 51 - count then 1 else 2)
	end)

	it("true EV ignores noise and GOTV", function()
		local match = board(function(s, i)
			s.support, s.undecided = if i % 2 == 0 then { 50, 40 } else { 40, 50 }, 10
			s.gotv = { 0, 4 }
		end)
		local ev = Election.trueEV(C, match)
		local expected = 0
		for i, s in match.states do
			if i % 2 == 0 then
				expected += s.ev
			end
		end
		expect(ev[1]):toBe(expected)
	end)
end)

describe("Debates", function()
	it("draws three distinct seeded topics per debate", function()
		local match = Match.new(C, 77, { "a", "b" })
		for _, week in C.DEBATE_WEEKS do
			local topics = match.debateTopics[week]
			expect(#topics):toBe(C.DEBATE_TOPICS)
			expect(topics[1] ~= topics[2] and topics[2] ~= topics[3] and topics[1] ~= topics[3]):toBe(true)
		end
		expect(Match.new(C, 77, { "a", "b" }).debateTopics):toEqual(match.debateTopics)
	end)

	it("scores, winners, sweeps and gaffes follow the formula", function()
		for seed = 1, 30 do
			local match = Fixtures.advanceTo(Fixtures.campaign({ seed = seed }), "Debate", 4)
			match.players[1].debatePrep = { 4, 2, 0 }
			match.players[2].debatePrep = { 0, 2, 4 }
			local result = Debate.resolve(C, match)
			local topics = result.topics
			local expected = { 0, 0 }
			local wins = { 0, 0 }
			for t, topic in topics do
				for p = 1, 2 do
					local player = match.players[p]
					local floor = result.prep[p][t]
						+ (if table.find(player.platform, topic) then C.DEBATE_PLATFORM_BONUS else 0)
						+ player.profile.debateStat
					local roll = result.scores[p][t] - floor
					expect(roll >= 0 and roll <= C.DEBATE_ROLL_MAX and roll == math.floor(roll)):toBe(true)
				end
				local a, b = result.scores[1][t], result.scores[2][t]
				local winner = if a > b then 1 elseif b > a then 2 else 0
				expect(result.winners[t]):toBe(winner)
				if winner > 0 then
					wins[winner] += 1
					expected[winner] += C.DEBATE_TOPIC_WIN
					local loser = 3 - winner
					if result.prep[loser][t] == 0 then
						expected[loser] -= C.DEBATE_GAFFE
					end
				end
			end
			for p = 1, 2 do
				if wins[p] == #topics then
					expected[p] += C.DEBATE_SWEEP
				end
				expect(result.national[p]):toBeCloseTo(expected[p], 1e-9)
			end
			expect(match.players[1].debatePrep):toBe(nil)
			Fixtures.checkSupport(match)
		end
	end)

	it("missing prep defaults to an even spread", function()
		local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 3 }), "Debate", 4)
		expect(match.players[1].debatePrep):toEqual({ 2, 2, 2 })
		local result = Debate.resolve(C, match)
		expect(result.prep[2]):toEqual({ 2, 2, 2 })
	end)

	it("records the support each debate moved, per state and player", function()
		for seed = 1, 10 do
			local match = Fixtures.advanceTo(Fixtures.campaign({ seed = seed }), "Debate", 4)
			match.players[1].debatePrep = { 4, 2, 0 }
			match.players[2].debatePrep = { 0, 2, 4 }
			local before = {}
			for i, s in match.states do
				before[i] = table.clone(s.support)
				expect(s.debateShift):toEqual({ 0, 0 })
			end
			local result = Debate.resolve(C, match)
			local moved = false
			for i, s in match.states do
				for p = 1, 2 do
					expect(s.debateShift[p]):toBeCloseTo(s.support[p] - before[i][p], 1e-9)
					if math.abs(s.debateShift[p]) > 1e-9 then
						moved = true
					end
				end
			end
			expect(moved):toBe(result.national[1] ~= 0 or result.national[2] ~= 0)
		end
	end)

	it("the election can be recounted without the debates' shifts", function()
		local match = board(function(s)
			s.support, s.undecided = { 45, 45 }, 10
			s.debateShift = { 0, 0 }
		end)
		local oh = State.get(match, "OH")
		oh.support = { 46, 44 }
		oh.debateShift = { 1.5, -0.5 } -- the debate turned a 44.5-44.5 tie into 46-44
		local with = Election.count(C, match, { noise = false })
		local without = Election.count(C, match, { noise = false, debates = false })
		expect(with.ev[1]):toBe(17)
		expect(without.ev[1]):toBe(0)
		expect(without.ev[2]):toBe(0) -- 44.5 each: an exact tie awards nobody
		-- The same seeded noise is used in both counts.
		local noisy = Election.count(C, match, { debates = false })
		expect(noisy.ev[1] + noisy.ev[2] <= 538):toBe(true)
	end)
end)
