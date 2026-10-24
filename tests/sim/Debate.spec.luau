--!strict
-- Debates as live rounds (D-062): the phase order, the board's arithmetic, the
-- clash (counters, splits, backfires, canned answers), the stakes Zinger, the
-- crowd and the ovation, validation, seat symmetry, determinism and N players.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Config = require("@sim/Config")
local Debate = require("@sim/Debate")
local IssueMap = require("@sim/IssueMap")
local Match = require("@sim/Match")
local Plan = require("@sim/Plan")
local State = require("@sim/State")
local StateData = require("@sim/StateData")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local R = Plan.Reason

local function serialize(value: any): string
	if type(value) == "table" then
		local keys = {}
		for key in value do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for _, key in keys do
			table.insert(parts, `{tostring(key)}={serialize(value[key])}`)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif type(value) == "number" then
		return string.format("%.17g", value)
	end
	return tostring(value)
end

-- A match at week 4's first debate round.
local function round1(seed: number?): State.MatchState
	local match = Fixtures.advanceTo(Fixtures.campaign({ seed = seed or 8 }), "Debate", 4)
	assert(match.debate ~= nil and match.debate.round == 1, "week 4 opens on round 1")
	return match
end

-- Public polls where player `leader` leads every state by `by` points.
local function polls(leader: number, by: number): { State.Poll? }
	local out: { State.Poll? } = {}
	for i in StateData.list do
		local support = { 40, 40 }
		support[leader] += by
		out[i] = { support = support, undecided = 100 - support[1] - support[2] }
	end
	return out
end

local function input(move: string, zinger: boolean?, canned: boolean?): State.DebateInput
	return { move = move :: any, zinger = zinger == true, canned = canned == true }
end

-- A board on the flavor map: topic Jobs, p1's platform has it, p2's does not.
local function jobsBoard(overrides: { [string]: any }?): Debate.Board
	local base: Debate.BoardInput = {
		week = 4,
		round = 1,
		topic = "Jobs",
		issueMap = IssueMap.flavor,
		platforms = { { "Jobs", "Safety", "Transit" }, { "Health", "Schools", "Farms" } },
		polls = polls(1, 4),
		crowd = { 0, 0 },
		zingers = { 1, 1 },
		zingerMults = { 2, 2 },
		last = {},
	}
	for key, value in overrides or {} do
		(base :: any)[key] = value
	end
	return Debate.boardFrom(C, base)
end

describe("Debate phase order (D-062)", function()
	it("a debate week opens on three rounds, then the plan; no focus decision", function()
		local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 8 }), "Plan", 3)
		match.eventDeck[4] = nil
		local trail = {}
		match = Match.advance(C, match, {})
		while match.week == 4 do
			table.insert(
				trail,
				if match.phase == "Debate" then `Debate:{(match.debate :: any).round}` else match.phase
			)
			if match.phase == "Plan" then
				break
			end
			match = Match.advance(C, match, {})
		end
		expect(table.concat(trail, " ")):toBe("Debate:1 Debate:2 Debate:3 Plan")
		expect(#match.debates):toBe(1)
		expect(match.debate):toBe(nil)
	end)

	it("a Choice event in a debate week asks for its stance after the debate", function()
		local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 8 }), "Plan", 3)
		match.eventDeck[4] = "plant"
		match = Match.advance(C, match, {})
		for _ = 1, 3 do
			expect(match.phase):toBe("Debate")
			match = Match.advance(C, match, {})
		end
		expect(match.phase):toBe("Decision")
		expect(match.decision):toBe("Stance")
	end)

	it("the debate's topics are the ones announced weeks ahead", function()
		local match = Fixtures.campaign({ seed = 8 })
		local announced = View.build(C, match, 1).nextDebate
		match = Fixtures.advanceTo(match, "Debate", 4)
		expect((announced :: any).topics):toEqual((match.debate :: any).topics)
	end)
end)

describe("Debate.board", function()
	it("adds up each move's strength from public facts", function()
		local board = jobsBoard()
		local me, them = board.players[1], board.players[2]
		expect(me.defend.strength):toBe(C.DEBATE_DEFEND_BASE + C.DEBATE_OWN_ISSUE + C.DEBATE_GROUND)
		expect(me.attack.strength):toBe(C.DEBATE_ATTACK_BASE)
		expect(me.pivot.strength):toBe(C.DEBATE_PIVOT_BASE)
		expect(them.defend.strength):toBe(C.DEBATE_DEFEND_BASE)
		expect(them.attack.strength):toBe(C.DEBATE_ATTACK_BASE + C.DEBATE_THEIR_ISSUE + C.DEBATE_GROUND)
		expect(them.pivot.strength):toBe(C.DEBATE_PIVOT_BASE + C.DEBATE_OFF_ISSUE)
		expect(me.ground):toBe(1)
		expect(them.ground):toBe(-1)
		-- The parts add up to the strength and name every bonus.
		for _, side in board.players do
			for _, info in { side.defend, side.attack, side.pivot } do
				local sum = 0
				for _, p in info.parts do
					sum += p.points
				end
				expect(sum):toBe(info.strength)
			end
		end
	end)

	it("takes the repeat penalty and the crowd into account", function()
		local board = jobsBoard({ crowd = { 3, 0 }, last = { "Defend", "Attack" } })
		expect(board.players[1].defend.strength):toBe(
			C.DEBATE_DEFEND_BASE + C.DEBATE_OWN_ISSUE + C.DEBATE_GROUND - C.DEBATE_REPEAT
		)
		expect(board.players[2].attack.strength):toBe(
			C.DEBATE_ATTACK_BASE
				+ C.DEBATE_THEIR_ISSUE
				+ C.DEBATE_GROUND
				+ C.DEBATE_CROWD_TRAIL
				- C.DEBATE_REPEAT
		)
		expect(board.players[2].trailsCrowd):toBe(true)
		expect(board.players[1].trailsCrowd):toBe(false)
	end)

	it("the counter grows by round", function()
		expect(Debate.counter(C, 1)):toBe(C.DEBATE_COUNTER[1])
		expect(Debate.counter(C, 2)):toBe(C.DEBATE_COUNTER[2])
		expect(Debate.counter(C, 3)):toBe(C.DEBATE_COUNTER[3])
		expect(jobsBoard({ round = 3 }).counter):toBe(C.DEBATE_COUNTER[3])
	end)

	it("a pivot lands on the platform issue with the most EV in play", function()
		-- Every poll within the close band: the issue with the most EV wins.
		local board = jobsBoard({ polls = polls(1, 2) })
		local function inPlayEV(issue: string): number
			local ev = 0
			for i, record in StateData.list do
				if table.find(IssueMap.flavor[i], issue :: any) then
					ev += record.ev
				end
			end
			return ev
		end
		local best, bestEV = nil, -1
		for _, issue in { "Safety", "Transit" } do
			if inPlayEV(issue) > bestEV then
				best, bestEV = issue, inPlayEV(issue)
			end
		end
		expect(board.players[1].pivotIssue):toBe(best)
		-- Nothing in play: platform order decides.
		local far = jobsBoard({ polls = polls(1, 20) })
		expect(far.players[1].pivotIssue):toBe("Safety")
		expect(far.players[2].pivotIssue):toBe("Health")
	end)
end)

describe("Debate.clash", function()
	it("the counter decides close rounds and the countered loser backfires", function()
		local board = jobsBoard()
		-- p1 Defend 6 vs p2 Attack 5: Defend counters (+2) and wins; the Attack backfires.
		local defend = board.players[1].defend.strength
		local attack = board.players[2].attack.strength
		local clash = Debate.clash(C, board, { input("Defend"), input("Attack") })
		expect(clash.winner):toBe(1)
		expect(clash.margin):toBe(defend + C.DEBATE_COUNTER[1] - attack)
		expect(clash.backfire):toEqual({ false, true })
		-- p1 Defend vs p2 Pivot: Pivot counters; whoever scores higher wins, equal splits.
		local pivot = board.players[2].pivot.strength + C.DEBATE_COUNTER[1]
		local other = Debate.clash(C, board, { input("Defend"), input("Pivot") })
		if pivot > defend then
			expect(other.winner):toBe(2)
			expect(other.backfire):toEqual({ true, false })
		elseif pivot == defend then
			expect(other.winner):toBe(0)
			expect(other.split):toEqual({ true, true })
			expect(other.backfire):toEqual({ false, false })
		else
			expect(other.winner):toBe(1)
			expect(other.backfire):toEqual({ false, false })
		end
	end)

	it("a canned answer is never countered, never counters and never backfires", function()
		local board = jobsBoard()
		local clash = Debate.clash(C, board, { input("Defend", false, true), input("Pivot") })
		expect(clash.strengths[1]):toBe(C.DEBATE_CANNED)
		expect(clash.scores):toEqual({ C.DEBATE_CANNED, board.players[2].pivot.strength })
		expect(clash.backfire):toEqual({ false, false })
		expect(clash.countered):toEqual({ false, false })
	end)

	it("Debate.versus matches the clash for two players", function()
		local board = jobsBoard({ round = 2 })
		for _, a in Debate.MOVES do
			for _, b in Debate.MOVES do
				local clash = Debate.clash(C, board, { input(a), input(b) })
				expect(Debate.versus(C, board, 1, a, 2, b)):toBe(clash.scores[1] - clash.scores[2])
			end
		end
	end)
end)

describe("Debate.round", function()
	it("moves the winner's landing states, x2 with a staked Zinger, and spends it", function()
		local plain = round1()
		local staked = round1()
		local _ = Debate.round(C, plain, { input("Defend"), input("Attack") })
		local board = Debate.board(C, staked)
		local clash = Debate.clash(C, board, { input("Defend"), input("Attack") })
		if clash.winner == 0 then
			return -- this seed splits; covered by the board specs
		end
		local w = clash.winner
		local inputs = { input("Defend"), input("Attack") }
		inputs[w] = input(inputs[w].move, true)
		local round = Debate.round(C, staked, inputs)
		expect(round.winner):toBe(w)
		expect(round.mult):toBe(staked.players[w].profile.zingerMult)
		expect((staked.debate :: any).zingers[w]):toBe(0)
		for _, move in round.moves do
			if move.points[w] > 0 then
				expect(move.points[w]):toBe(C.DEBATE_ROUND_WIN * round.mult)
			end
		end
		expect(round.crowd[w]):toBe(math.min(round.margin, C.DEBATE_CROWD_ROUND_MAX) * round.mult)
	end)

	it("a Zinger is spent even on a lost round, and a second one is ZingerSpent", function()
		local match = round1()
		local _ = Debate.round(C, match, { input("Pivot", true), input("Defend", true) })
		expect((match.debate :: any).zingers):toEqual({ 0, 0 })
		local ok, reason = Match.validate(C, match, 1, { move = "Attack", zinger = true })
		expect(ok):toBe(false)
		expect(reason):toBe(R.ZingerSpent)
	end)

	it("a round won against a canned answer gains at most DEBATE_CANNED_CROWD crowd", function()
		local match = round1()
		local round = Debate.round(C, match, { input("Attack", true), Debate.default() })
		if round.winner == 1 then
			expect(round.crowd[1] <= C.DEBATE_CANNED_CROWD):toBe(true)
		end
		expect(round.backfire[2]):toBe(false)
	end)

	it("republishes the polls after each round and records the debate", function()
		local match = round1()
		local before = {}
		for i, s in match.states do
			before[i] = s.poll and s.poll.support[1]
		end
		local first = Debate.round(C, match, { input("Defend"), input("Attack") })
		for _, flip in first.flips do
			expect(StateData.byId[flip.state] ~= nil):toBe(true)
		end
		local _ = Debate.round(C, match, { input("Attack"), input("Pivot") })
		local _, result = Debate.round(C, match, { input("Pivot"), input("Defend") })
		expect(result ~= nil):toBe(true)
		local done = result :: State.DebateResult
		expect(#done.rounds):toBe(3)
		expect(#done.winners):toBe(3)
		expect(done.national):toEqual({ 0, 0 })
		expect(match.debate):toBe(nil)
		expect(match.debates[#match.debates]):toBe(done)
	end)

	it("a crowd lead of DEBATE_OVATION is a standing ovation in every battleground", function()
		local match = round1()
		local live = match.debate :: State.LiveDebate
		live.round = 3
		live.crowd = { C.DEBATE_OVATION + 5, 0 }
		local before = {}
		for i, s in match.states do
			before[i] = s.momentum[1]
		end
		local _, result = Debate.round(C, match, { Debate.default(), Debate.default() })
		expect((result :: any).ovation):toBe(1)
		for i, s in match.states do
			if s.battleground then
				expect(s.momentum[1]):toBe(math.min(C.MOMENTUM_CAP, before[i] + C.DEBATE_OVATION_MOMENTUM))
			end
		end
	end)
end)

describe("Debate validation", function()
	it("rejects bad moves whole, with a reason, and normalizes good ones", function()
		local match = round1()
		local cases: { { any } } = {
			{ "nope", R.BadShape },
			{ {}, R.BadMove },
			{ { move = "Shout" }, R.BadMove },
			{ { focus = "Jobs" }, R.BadMove },
			{ { move = "Defend", zinger = "yes" }, R.BadShape },
		}
		for _, case in cases do
			local ok, reason, normalized = Match.validate(C, match, 1, case[1])
			expect(ok):toBe(false)
			expect(reason):toBe(case[2])
			expect(normalized):toBe(nil)
		end
		local ok, _, normalized = Match.validate(C, match, 2, { move = "Pivot", extra = 1 })
		expect(ok):toBe(true)
		expect(normalized):toEqual({ move = "Pivot", zinger = false, canned = false })
		-- A client cannot claim the canned answer.
		local _, _, sneaky = Match.validate(C, match, 2, { move = "Defend", canned = true })
		expect((sneaky :: any).canned):toBe(false)
	end)

	it("a plan carrying a move is rejected; a move outside a debate is WrongPhase", function()
		local match = Fixtures.campaign({ seed = 8 })
		local ok, reason = Match.validate(C, match, 1, { actions = {}, move = "Defend" })
		expect(ok):toBe(false)
		expect(reason):toBe(R.UnexpectedMove)
		local ok2, reason2 = Debate.validate(C, match, 1, { move = "Defend" })
		expect(ok2):toBe(false)
		expect(reason2):toBe(R.WrongPhase)
	end)

	it("a missing input is the canned answer", function()
		expect(Match.default(C, round1(), 1)):toEqual(Debate.default())
	end)
end)

describe("Debate fairness", function()
	it("swapping seats mirrors every result (D-001)", function()
		local a =
			jobsBoard({ platforms = { { "Jobs", "Safety", "Transit" }, { "Jobs", "Farms", "Health" } } })
		local b = jobsBoard({
			platforms = { { "Jobs", "Farms", "Health" }, { "Jobs", "Safety", "Transit" } },
			polls = polls(2, 4),
		})
		for _, x in Debate.MOVES do
			for _, y in Debate.MOVES do
				local one = Debate.clash(C, a, { input(x), input(y) })
				local two = Debate.clash(C, b, { input(y), input(x) })
				expect(one.scores[1]):toBe(two.scores[2])
				expect(one.scores[2]):toBe(two.scores[1])
				local mirrored = if one.winner == 0 then 0 else 3 - one.winner
				expect(two.winner):toBe(mirrored)
			end
		end
	end)

	it("equal scores always split, whatever the seat", function()
		local board = jobsBoard({
			platforms = { { "Health", "Schools", "Farms" }, { "Health", "Schools", "Farms" } },
			polls = polls(1, 0),
		})
		local clash = Debate.clash(C, board, { input("Pivot"), input("Pivot") })
		expect(clash.winner):toBe(0)
	end)

	it("same seed and inputs replay the same debate", function()
		local function run(): string
			local match = round1(12)
			local trail = {}
			for _, pair in { { "Defend", "Attack" }, { "Pivot", "Pivot" }, { "Attack", "Defend" } } do
				local round = Debate.round(C, match, { input(pair[1], true), input(pair[2]) })
				table.insert(trail, round)
			end
			return serialize({ trail, match.states })
		end
		expect(run()):toBe(run())
	end)

	it("plays three-player debates", function()
		local match = Match.new(C, 5, { "a", "b", "c" })
		local guard = 0
		while match.phase ~= "Plan" or match.week < 5 do
			match = Match.advance(C, match, {})
			guard += 1
			assert(guard < 400, "stuck")
		end
		expect(#match.debates):toBe(1)
		expect(#match.debates[1].rounds[1].picks):toBe(3)
		Fixtures.checkSupport(match)
	end)

	it("never shows another player's pending move", function()
		local match = round1()
		match.players[2].debateMove = input("Attack", true)
		local view = View.build(C, match, 1)
		expect((view.debate :: any).yourMove):toBe(nil)
		match.players[1].debateMove = input("Pivot")
		expect((View.build(C, match, 1).debate :: any).yourMove.move):toBe("Pivot")
		expect((View.build(C, match, 2).debate :: any).yourMove.move):toBe("Attack")
	end)
end)
