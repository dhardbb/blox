--!strict
-- Election night (GOTV, noise, tiebreaks, reveal order) and debates.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Config = require("@sim/Config")
local IssueMap = require("@sim/IssueMap")
local Debate = require("@sim/Debate")
local Election = require("@sim/Election")
local Issues = require("@sim/Issues")
local Match = require("@sim/Match")
local Polls = require("@sim/Polls")
local State = require("@sim/State")
local StateData = require("@sim/StateData")
local Support = require("@sim/Support")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local FLAVOR = IssueMap.flavor -- Fixtures put matches on this fixed map (D-047)

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

	it("a round's points land in its landing states and apply from one snapshot (D-001, D-062)", function()
		local pairs =
			{ { "Defend", "Attack" }, { "Pivot", "Defend" }, { "Attack", "Pivot" }, { "Pivot", "Pivot" } }
		for seed = 1, 30 do
			local match = Fixtures.advanceTo(Fixtures.campaign({ seed = seed }), "Debate", 4)
			local pair = pairs[seed % #pairs + 1]
			local inputs: { State.DebateInput } = {
				{ move = pair[1] :: any, zinger = seed % 3 == 0, canned = false },
				{ move = pair[2] :: any, zinger = false, canned = false },
			}
			local snapshot = State.clone(match)
			local roundBoard = Debate.board(C, match)
			local clash = Debate.clash(C, roundBoard, inputs)
			local round = Debate.round(C, match, inputs)
			expect(round.winner):toBe(clash.winner)
			expect(round.scores):toEqual(clash.scores)
			-- Every state with a landing issue gets exactly the round's points.
			local wants = { 0, 0 }
			for p = 1, 2 do
				if p == round.winner then
					wants[p] = C.DEBATE_ROUND_WIN * round.mult
				elseif round.split[p] then
					wants[p] = C.DEBATE_ROUND_SPLIT
				elseif round.backfire[p] then
					wants[p] = -C.DEBATE_BACKFIRE
				end
			end
			local moves: { State.StateMove } = {}
			for _, record in StateData.list do
				local points = { 0, 0 }
				for p = 1, 2 do
					if wants[p] ~= 0 and table.find(record.flavor, round.landing[p]) then
						points[p] = wants[p]
					end
				end
				if points[1] ~= 0 or points[2] ~= 0 then
					table.insert(moves, { state = record.id, points = points })
				end
			end
			expect(round.moves):toEqual(moves)
			local byState = {}
			for _, move in moves do
				byState[move.state] = move
			end
			for i, s in snapshot.states do
				local delta = Support.zero(s)
				local du = 0
				local move = byState[s.id]
				for p = 1, 2 do
					local x = if move then move.points[p] else 0
					if x > 0 then
						du += Support.addGain(C, s, p, x, delta)
					elseif x < 0 then
						du += Support.addLoss(p, -x, delta)
					end
				end
				Support.apply(s, delta, du)
				for p = 1, 2 do
					expect(match.states[i].support[p]):toBeCloseTo(s.support[p], 1e-9)
				end
			end
			expect(match.players[1].debateMove):toBe(nil)
			Fixtures.checkSupport(match)
		end
	end)

	it(
		"republishes the public polls with the same error terms after every round and lists the leader changes",
		function()
			for seed = 1, 20 do
				local match = Fixtures.advanceTo(Fixtures.campaign({ seed = seed }), "Debate", 4)
				local before = {}
				for i, s in match.states do
					before[i] =
						{ poll = s.poll, error = table.clone(s.pollError), undecided = s.pollErrorUndecided }
				end
				local round = Debate.round(C, match, {
					{ move = "Defend", zinger = true, canned = false },
					{ move = "Pivot", zinger = false, canned = false },
				})
				local flips = {}
				for i, s in match.states do
					expect(s.pollError):toEqual(before[i].error)
					expect(s.pollErrorUndecided):toBe(before[i].undecided)
					expect(s.poll):toEqual(Polls.shown(s))
					local from, to = Polls.leader(before[i].poll), Polls.leader(s.poll)
					if from ~= to then
						table.insert(flips, { state = s.id, from = from, to = to })
					end
				end
				expect(round.flips):toEqual(flips)
				-- The view carries the moved polls and the finished round, nothing hidden.
				local view = View.build(C, match, 2)
				local debate = view.debate :: View.DebateView
				expect(debate.rounds[1].moves):toEqual(round.moves)
				expect(debate.rounds[1].flips):toEqual(flips)
				for i, s in view.states do
					expect(s.poll):toEqual(match.states[i].poll)
				end
			end
		end
	)

	it("topic states are fixed data on the fixed map", function()
		for _, topic in Issues.list do
			local states = Debate.topicStates(FLAVOR, topic)
			expect(#states >= 8):toBe(true)
			for _, id in states do
				expect(table.find(StateData.byId[id].flavor, topic) ~= nil):toBe(true)
			end
		end
	end)

	it("records the support each debate moved, per state and player", function()
		for seed = 1, 10 do
			local match = Fixtures.advanceTo(Fixtures.campaign({ seed = seed }), "Debate", 4)
			local before = {}
			for i, s in match.states do
				before[i] = table.clone(s.support)
				expect(s.debateShift):toEqual({ 0, 0 })
			end
			local moves = 0
			for _ = 1, C.DEBATE_TOPICS do
				local round = Debate.round(C, match, {
					{ move = "Attack", zinger = false, canned = false },
					{ move = "Defend", zinger = false, canned = false },
				})
				moves += #round.moves
			end
			local moved = false
			for i, s in match.states do
				for p = 1, 2 do
					expect(s.debateShift[p]):toBeCloseTo(s.support[p] - before[i][p], 1e-9)
					if math.abs(s.debateShift[p]) > 1e-9 then
						moved = true
					end
				end
			end
			expect(moved):toBe(moves > 0)
		end
	end)

	it("the election can be recounted without the debates' shifts", function()
		local match = board(function(s)
			s.support, s.undecided = { 45, 45 }, 10
			s.debateShift = { 0, 0 }
			s.stanceShift = { 0, 0 }
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
