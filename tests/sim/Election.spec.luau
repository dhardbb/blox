--!strict
-- Election night (GOTV, noise, tiebreaks, reveal order) and debates.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Config = require("@sim/Config")
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

	it(
		"scores, winners, sweeps and gaffes follow the formula; wins move the topic's states (D-040, D-044)",
		function()
			for seed = 1, 30 do
				local match = Fixtures.advanceTo(Fixtures.campaign({ seed = seed }), "Debate", 4)
				local topicList = match.debateTopics[4]
				match.players[1].debateFocus = topicList[1]
				-- Every other seed, seat 2 took no focus: every topic it loses is a gaffe.
				match.players[2].debateFocus = if seed % 2 == 0 then topicList[3] else nil
				local snapshot = State.clone(match)
				local result = Debate.resolve(C, match)
				local topics = result.topics
				local national = { 0, 0 }
				local wins = { 0, 0 }
				local gaffes = { { false, false, false }, { false, false, false } }
				expect(result.focus):toEqual({ 1, if seed % 2 == 0 then 3 else 0 })
				for t, topic in topics do
					for p = 1, 2 do
						local player = match.players[p]
						local edge = if result.focus[p] == t then player.profile.focusEdge else 0
						expect(result.prep[p][t]):toBe(edge)
						local floor = result.prep[p][t]
							+ (if table.find(player.platform, topic) then C.DEBATE_PLATFORM_BONUS else 0)
							+ player.profile.debateStat
						local roll = result.scores[p][t] - floor
						expect(roll >= 0 and roll <= C.DEBATE_ROLL_MAX and roll == math.floor(roll)):toBe(
							true
						)
					end
					local a, b = result.scores[1][t], result.scores[2][t]
					local winner = if a > b then 1 elseif b > a then 2 else 0
					expect(result.winners[t]):toBe(winner)
					if winner > 0 then
						wins[winner] += 1
						national[winner] += C.DEBATE_TOPIC_NATIONAL
						local loser = 3 - winner
						if result.focus[loser] == 0 then
							gaffes[loser][t] = true
						end
					end
				end
				for p = 1, 2 do
					if wins[p] == #topics then
						national[p] += C.DEBATE_SWEEP
					end
					expect(result.national[p]):toBeCloseTo(national[p], 1e-9)
				end
				expect(result.gaffes):toEqual(gaffes)
				-- The targeted moves: DEBATE_TOPIC_WIN to the winner and -DEBATE_GAFFE to a
				-- gaffer in every state where the topic is a top issue, nothing elsewhere.
				local moves: { State.StateMove } = {}
				for _, record in StateData.list do
					local points = { 0, 0 }
					for t, topic in topics do
						if table.find(record.issues, topic) then
							if result.winners[t] > 0 then
								points[result.winners[t]] += C.DEBATE_TOPIC_WIN
							end
							for p = 1, 2 do
								if gaffes[p][t] then
									points[p] -= C.DEBATE_GAFFE
								end
							end
						end
					end
					if points[1] ~= 0 or points[2] ~= 0 then
						table.insert(moves, { state = record.id, points = points })
					end
				end
				expect(result.moves):toEqual(moves)
				expect(Debate.moves(C, 2, topics, result.winners, gaffes)):toEqual(moves)
				-- Support moved by the flat part plus the targeted part, from one snapshot.
				local byState = {}
				for _, move in moves do
					byState[move.state] = move
				end
				for i, s in snapshot.states do
					local delta = Support.zero(s)
					local du = 0
					for p = 1, 2 do
						local x = national[p] + (if byState[s.id] then byState[s.id].points[p] else 0)
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
					expect(match.states[i].undecided):toBeCloseTo(s.undecided, 1e-9)
				end
				expect(match.players[1].debateFocus):toBe(nil)
				Fixtures.checkSupport(match)
			end
		end
	)

	it(
		"republishes the public polls with the same error terms and lists the states that changed leader",
		function()
			for seed = 1, 20 do
				local match = Fixtures.advanceTo(Fixtures.campaign({ seed = seed }), "Debate", 4)
				match.players[1].debateFocus = match.debateTopics[4][1]
				match.players[2].debateFocus = match.debateTopics[4][3]
				local before = {}
				for i, s in match.states do
					before[i] =
						{ poll = s.poll, error = table.clone(s.pollError), undecided = s.pollErrorUndecided }
				end
				local result = Debate.resolve(C, match)
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
				expect(result.flips):toEqual(flips)
				-- The view carries the moved polls, the moves and the flips, nothing hidden.
				local view = View.build(C, match, 2)
				expect(view.debates[1].moves):toEqual(result.moves)
				expect(view.debates[1].flips):toEqual(flips)
				for i, s in view.states do
					expect(s.poll):toEqual(match.states[i].poll)
				end
			end
		end
	)

	it("topic states are fixed data and the odds follow the roll", function()
		for _, topic in Issues.list do
			local states = Debate.topicStates(topic)
			expect(#states >= 8):toBe(true)
			for _, id in states do
				expect(table.find(StateData.byId[id].issues, topic) ~= nil):toBe(true)
			end
		end
		local win, tie, lose = Debate.odds(C, 0)
		expect(win):toBeCloseTo(lose, 1e-9)
		expect(win + tie + lose):toBeCloseTo(1, 1e-9)
		local win2, _, lose2 = Debate.odds(C, 2)
		expect(win2 >= 0.75 and lose2 <= 0.12):toBe(true)
		expect((Debate.odds(C, 4))):toBe(1)
	end)

	it("a focus usually wins its topic, but not always (D-044)", function()
		-- Same platforms and stats, so only the focus and the roll differ. Seat 1
		-- focuses on topic 1, seat 2 on topic 3; topic 2 is level.
		local same = { { "Jobs", "Health", "Schools" }, { "Jobs", "Health", "Schools" } }
		local won, lost, theirs = 0, 0, 0
		local n = 150
		for seed = 1, n do
			local match =
				Fixtures.advanceTo(Fixtures.campaign({ seed = seed, platforms = same }), "Debate", 4)
			match.players[1].debateFocus = match.debateTopics[4][1]
			match.players[2].debateFocus = match.debateTopics[4][3]
			local result = Debate.resolve(C, match)
			if result.winners[1] == 1 then
				won += 1
			elseif result.winners[1] == 2 then
				lost += 1
			end
			if result.winners[3] == 2 then
				theirs += 1
			end
		end
		expect(won / n >= 0.6):toBe(true)
		expect(won / n < 0.95):toBe(true)
		expect(lost / n <= 0.2):toBe(true)
		expect(theirs / n >= 0.6):toBe(true)
	end)

	it("no focus by default: nothing added, and every topic lost is a gaffe", function()
		local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 3 }), "Debate", 4)
		expect(match.players[1].debateFocus):toBe(nil)
		local result = Debate.resolve(C, match)
		expect(result.focus):toEqual({ 0, 0 })
		expect(result.prep[2]):toEqual({ 0, 0, 0 })
		for t, winner in result.winners do
			for p = 1, 2 do
				expect(result.gaffes[p][t]):toBe(winner ~= 0 and winner ~= p)
			end
		end
	end)

	it("records the support each debate moved, per state and player", function()
		for seed = 1, 10 do
			local match = Fixtures.advanceTo(Fixtures.campaign({ seed = seed }), "Debate", 4)
			match.players[1].debateFocus = match.debateTopics[4][1]
			match.players[2].debateFocus = match.debateTopics[4][3]
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
			expect(moved):toBe(result.national[1] ~= 0 or result.national[2] ~= 0 or #result.moves > 0)
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
