--!strict
-- The bot: always submits valid input, finishes full matches with every
-- candidate, is deterministic, and beats random play.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Play = require("@testlib/Play")
local Bot = require("@sim/Bot")
local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Debate = require("@sim/Debate")
local IssueMap = require("@sim/IssueMap")
local Election = require("@sim/Election")
local Events = require("@sim/Events")
local Match = require("@sim/Match")
local Rng = require("@sim/Rng")
local State = require("@sim/State")
local StateData = require("@sim/StateData")
local Types = require("@shared/Types")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local FLAVOR = IssueMap.flavor -- Fixtures put matches on this fixed map (D-047)

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
		for k, style in
			{ "Random", "FundraiseOnly", "RallyOnly", "AttackOnly", "NeverPoll", "Sandbag", "RandomStance" }
		do
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

	it("banks ground game by weeks 7-8, not only in the last weeks (D-021, D-049)", function()
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
	it("scouts close states for their ground game and counts what it sees (D-049)", function()
		-- Week 8, Okafor (no free polls) against Hale, three close states, the rest decided.
		local function board(theirCash: number): State.MatchState
			local match = Fixtures.advanceTo(
				Fixtures.campaign({ seed = 9, candidates = { "okafor", "hale" } }),
				"Plan",
				8
			)
			for _, s in match.states do
				local close = s.id == "OH" or s.id == "PA" or s.id == "WI"
				s.poll = if close
					then { support = { 40, 40 }, undecided = 20 }
					else { support = { 60, 25 }, undecided = 15 }
			end
			match.players[1].cash = 30
			match.players[2].cash = theirCash
			return match
		end
		local function polls(match: State.MatchState): { string }
			local out = {}
			for _, action in Bot.plan(C, View.build(C, match, 1), Rng.new(1), "Balanced").actions do
				if action.kind == "Poll" then
					table.insert(out, action.state)
				elseif action.kind == "RegionPoll" then
					table.insert(out, action.region)
				end
			end
			return out
		end
		local scouted = polls(board(20))
		expect(#scouted):toBe(1)
		expect(scouted[1] == "OH" or scouted[1] == "PA" or scouted[1] == "WI"):toBe(true)
		expect(#polls(board(1))):toBe(0) -- their cash shows Low: no paid scouting

		-- What a poll saw counts against the bot's margin there, and only there.
		local match = board(20)
		local before = Bot.estimates(C, View.build(C, match, 1))
		match.players[1].scouted = { { state = "OH", week = 7, gotv = { 0, 3 } } }
		local after = Bot.estimates(C, View.build(C, match, 1))
		local oh, pa = State.indexOf.OH, State.indexOf.PA
		expect(after[oh].margin):toBeCloseTo(before[oh].margin - 3 * C.GOTV_PER_UNIT, 1e-9)
		expect(after[oh].theirGotv):toBe(3)
		expect(after[pa].margin):toBe(before[pa].margin)
	end)

	-- Counts what the bot plans over several boards, with week `week`'s event set to
	-- `id` (nil = none), using `count(action, view)` on each action.
	local function tally(id: string?, count: (action: any, view: View.View) -> number): number
		local total = 0
		for seed = 31, 38 do
			local match = Fixtures.advanceTo(Fixtures.campaign({ seed = seed }), "Plan", 5)
			match.eventDeck[5] = id
			for p = 1, 2 do
				local view = View.build(C, match, p)
				for _, action in Bot.plan(C, view, Rng.new(seed), "Balanced").actions do
					total += count(action, view)
				end
			end
		end
		return total
	end

	it("uses events: the spotlight issue, the regional rally, the windfall fundraiser (D-027)", function()
		local function onTech(action: any): number
			return if action.issue == "Technology" and action.kind ~= "Attack" then 1 else 0
		end
		expect(tally("expo", onTech) > tally(nil, onTech)):toBe(true)
		local function pacificRally(action: any): number
			return if action.kind == "Rally" and StateData.byId[action.state].region == "Pacific"
				then 1
				else 0
		end
		expect(tally("coast", pacificRally) > tally(nil, pacificRally)):toBe(true)
		local function trailingFund(action: any, view: View.View): number
			if action.kind ~= "Fundraise" then
				return 0
			end
			for _, s in view.states do
				if s.id == action.state then
					return if Events.trails(s.poll, view.you) then 1 else 0
				end
			end
			return 0
		end
		expect(tally("donors", trailingFund) >= tally(nil, trailingFund)):toBe(true)
	end)

	it("Helen Strand's bot ends the week where next week's Regional event is (D-035)", function()
		-- With the preview of a Pacific event next week, her last stop lands in the
		-- Pacific more often, so next week's boosted rallies start without a flight.
		local function lastStopInPacific(nextId: string?): number
			local total = 0
			for seed = 31, 46 do
				local match = Fixtures.advanceTo(
					Fixtures.campaign({ seed = seed, candidates = { "strand", "okafor" } }),
					"Plan",
					5
				)
				match.eventDeck[5] = nil
				match.eventDeck[6] = nextId
				local view = View.build(C, match, 1)
				local last = nil
				for _, action in Bot.plan(C, view, Rng.new(seed), "Balanced").actions do
					if action.kind == "Rally" or action.kind == "Fundraise" then
						last = action.state
					end
				end
				if last and StateData.byId[last].region == "Pacific" then
					total += 1
				end
			end
			return total
		end
		expect(lastStopInPacific("coast") > lastStopInPacific(nil)):toBe(true)
	end)

	-- Week 5's Stance decision (D-044) on a Choice event, every state 35/35 in the
	-- polls, no draft or lean.
	local function stanceWeek(id: string): State.MatchState
		local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 4 }), "Plan", 5)
		match.eventDeck[5] = id
		match.phase, match.decision = "Decision", "Stance"
		for _, s in match.states do
			s.support, s.undecided = { 35, 35 }, 30
			s.poll = { support = { 35, 35 }, undecided = 30 }
			s.lean, s.leanTo = 0, nil
			s.battleground, s.owner, s.isHome = false, nil, false
			s.momentum, s.gotv = { 0, 0 }, { 0, 0 }
		end
		return match
	end

	-- Polls every state in `camp` as close and every other state as decided.
	local function needOnly(match: State.MatchState, camp: { [string]: boolean })
		for _, s in match.states do
			s.poll = if camp[s.id]
				then { support = { 35, 35 }, undecided = 30 }
				else { support = { 60, 20 }, undecided = 20 }
		end
	end

	it(
		"takes the stance that pays in the states it needs; the hedge never beats a side (D-039, D-043)",
		function()
			local event = Events.byId.plant -- Jobs: A likes Transit and Farms, B likes Health and Safety
			local likedByA: { [string]: boolean }, likedByB: { [string]: boolean } = {}, {}
			for id, points in Events.stanceEffects(C, FLAVOR, event, "A", {}) do
				if points > 0.5 then
					likedByA[id] = true
				elseif points < 0 then
					likedByB[id] = true
				end
			end
			local match = stanceWeek("plant")
			needOnly(match, likedByA)
			expect(Bot.act(C, View.build(C, match, 1), Rng.new(1), "okafor").choice):toBe("A")
			expect(Bot.act(C, View.build(C, match, 2), Rng.new(1), "okafor").choice):toBe("A")
			needOnly(match, likedByB)
			expect(Bot.act(C, View.build(C, match, 1), Rng.new(1), "okafor").choice):toBe("B")
			-- Close everywhere: a side gains where it is liked and loses where it is not,
			-- and a gain buys more margin than the same loss costs, so a side nets
			-- something. The hedge moves nothing (and costs in your own base), so it is
			-- never the better answer: it is the safe default, not a winning play.
			match = stanceWeek("plant")
			local view = View.build(C, match, 1)
			local estimates = Bot.estimates(C, view)
			local platform = view.players[1].platform :: { Types.Issue }
			local base = Events.baseOf(view.players[1])
			local function value(id: Types.Choice): number
				return Bot.stanceValue(C, FLAVOR, estimates, view.event :: any, id, platform, base)
			end
			expect(value("A") > 0 and value("B") > 0):toBe(true)
			expect(value("C") <= 0):toBe(true)
			expect(Bot.act(C, view, Rng.new(1), "okafor").choice ~= "C"):toBe(true)
			-- With no base the hedge is worth nothing; with every state your base it costs.
			expect(Bot.stanceValue(C, FLAVOR, estimates, view.event :: any, "C", platform, {})):toBe(0)
			local everyone: { string } = {}
			for _, record in StateData.list do
				table.insert(everyone, record.id)
			end
			expect(Bot.stanceValue(C, FLAVOR, estimates, view.event :: any, "C", platform, everyone) < 0):toBe(
				true
			)
		end
	)

	it("two seats with different bases take different stances on the same board (D-043)", function()
		local event = Events.byId.plant
		local stance = Events.stance(event, "A") :: Events.Stance
		-- One state A is cheered in and one it is jeered in, same EV, both with Jobs.
		local cheered: Types.StateRecord? = nil
		local jeered: Types.StateRecord? = nil
		for _, one in StateData.list do
			for _, two in StateData.list do
				if one.ev == two.ev and table.find(one.flavor, "Jobs") and table.find(two.flavor, "Jobs") then
					local a = Events.stanceEffect(C, FLAVOR, event, "A", State.indexOf[one.id], {})
					local b = Events.stanceEffect(C, FLAVOR, event, "A", State.indexOf[two.id], {})
					if a == C.STANCE_POINTS and b == -C.STANCE_POINTS then
						cheered, jeered = one, two
					end
				end
			end
			if cheered then
				break
			end
		end
		expect(stance.id):toBe("A")
		expect(cheered ~= nil and jeered ~= nil):toBe(true)
		local c, j = cheered :: Types.StateRecord, jeered :: Types.StateRecord
		local match = stanceWeek("plant")
		needOnly(match, { [c.id] = true, [j.id] = true })
		for _, player in match.players do
			player.platform = {}
		end
		-- Seat 1 holds the state A is cheered in; seat 2 holds the one it is jeered in.
		match.players[1].home, match.players[1].strongholds = c.id, {}
		match.players[2].home, match.players[2].strongholds = j.id, {}
		-- Same polls for both seats: the board is identical, only the bases differ.
		local one = Bot.act(C, View.build(C, match, 1), Rng.new(1), "okafor").choice
		local two = Bot.act(C, View.build(C, match, 2), Rng.new(1), "okafor").choice
		expect(one):toBe("A")
		expect(two):toBe("B")
		-- And through stanceValue: each seat's own base tips its own answer.
		local view = View.build(C, match, 1)
		local estimates = Bot.estimates(C, view)
		local function value(id: Types.Choice, base: { string }): number
			return Bot.stanceValue(C, FLAVOR, estimates, view.event :: any, id, {}, base)
		end
		expect(value("A", { c.id }) > value("B", { c.id })):toBe(true)
		expect(value("B", { j.id }) > value("A", { j.id })):toBe(true)
		expect(value("A", {})):toBeCloseTo(value("B", {}), 1e-9)
	end)

	it("the RandomStance style takes every slot about equally; every style carries a valid stance", function()
		local match = stanceWeek("river")
		local seen: { [string]: number } = { A = 0, B = 0, C = 0 }
		local N = 600
		for k = 1, N do
			local decided = Bot.decide(C, View.build(C, match, 1), Rng.new(k), "RandomStance")
			seen[decided.choice] += 1
		end
		for _, id in Events.CHOICES do
			expect(math.abs(seen[id] / N - 1 / 3) < 0.07):toBe(true)
		end
		for _, style in { "Balanced", "Random", "AttackOnly", "RandomStance" } do
			local decided = Bot.decide(C, View.build(C, match, 1), Rng.new(2), style :: Bot.Style)
			expect(Events.isChoice(decided.choice)):toBe(true)
		end
		-- The plan that follows carries neither a stance nor prep (D-044).
		match.phase, match.decision = "Plan", nil
		local plan = Bot.plan(C, View.build(C, match, 1), Rng.new(2))
		expect(plan.choice):toBe(nil)
		expect(plan.focus):toBe(nil)
		expect((Match.validate(C, match, 1, plan))):toBe(true)
	end)

	-- A debate round 2 where both own the topic, seat 1 leads its states, and seat 2
	-- pivoted last round: Defend wins against every reply.
	local function sureDefend(): State.MatchState
		local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 4 }), "Debate", 4)
		local live = match.debate :: State.LiveDebate
		live.round = 2
		local topic = live.topics[2]
		match.players[1].platform = { topic }
		match.players[2].platform = { topic }
		for _, other in
			{ "Jobs", "Health", "Schools", "Environment", "Safety", "Transit", "Technology", "Farms" }
		do
			if other ~= topic and #match.players[1].platform < 3 then
				table.insert(match.players[1].platform, other :: Types.Issue)
			end
		end
		for _, other in
			{ "Farms", "Technology", "Transit", "Safety", "Environment", "Schools", "Health", "Jobs" }
		do
			if
				other ~= topic
				and not table.find(match.players[1].platform, other :: Types.Issue)
				and #match.players[2].platform < 3
			then
				table.insert(match.players[2].platform, other :: Types.Issue)
			end
		end
		live.last = { [2] = "Pivot" }
		for i, s in match.states do
			s.poll = if table.find(match.issueMap[i], topic)
				then { support = { 40, 34 }, undecided = 26 }
				else { support = { 35, 35 }, undecided = 30 }
		end
		return match
	end

	it("plays the debate move that wins against every reply (D-072)", function()
		local match = sureDefend()
		local view = View.build(C, match, 1)
		local board = (view.debate :: View.DebateView).board
		for _, theirs in { "Defend", "Attack", "Pivot" } do
			expect(Debate.versus(C, board, 1, "Defend", 2, theirs :: Types.DebateMove) > 0):toBe(true)
		end
		for _, style in { "Balanced", "Hard", "Extreme" } do
			local move = Bot.act(C, view, Rng.new(1), "okafor", style :: Bot.Style)
			expect(move.move):toBe("Defend")
			expect((Match.validate(C, match, 1, move))):toBe(true)
		end
	end)

	it("stakes its Zinger by the last round at the latest, and never twice", function()
		local match = sureDefend()
		local live = match.debate :: State.LiveDebate
		live.round = C.DEBATE_TOPICS
		local move = Bot.act(C, View.build(C, match, 1), Rng.new(1), "okafor")
		expect(move.zinger):toBe(true)
		live.zingers[1] = 0
		local again = Bot.act(C, View.build(C, match, 1), Rng.new(1), "okafor")
		expect(again.zinger):toBe(false)
		expect((Match.validate(C, match, 1, again))):toBe(true)
	end)

	it("the harness styles play what they say (D-072)", function()
		local match = sureDefend()
		local view = View.build(C, match, 1)
		expect(Bot.act(C, view, Rng.new(1), "okafor", "AlwaysAttack").move):toBe("Attack")
		expect(Bot.act(C, view, Rng.new(1), "okafor", "AlwaysPivot").move):toBe("Pivot")
		expect(Bot.act(C, view, Rng.new(1), "okafor", "AlwaysDefend").move):toBe("Defend")
		expect(Bot.act(C, view, Rng.new(1), "okafor", "NoAnswer")):toBe(nil)
		local seen: { [string]: boolean } = {}
		for k = 1, 60 do
			seen[Bot.act(C, view, Rng.new(k), "okafor", "RandomMove").move] = true
		end
		expect(seen.Defend and seen.Attack and seen.Pivot):toBe(true)
	end)
end)

describe("Bot: its opponent with more than two players", function()
	it("is the rival with the most projected votes; with two players, the other one", function()
		local two = View.build(C, Match.new(C, 3, { "a", "b" }), 2)
		expect(Bot.opponentOf(two)):toBe(1)
		local view = View.build(C, Match.new(C, 3, { "a", "b", "c" }), 1)
		view.projectedEV = { 100, 50, 300 }
		expect(Bot.opponentOf(view)):toBe(3)
		view.you = 3
		expect(Bot.opponentOf(view)):toBe(1)
		-- A tie goes to the lower seat, so the choice never depends on table order.
		view.you = 2
		view.projectedEV = { 120, 50, 120 }
		expect(Bot.opponentOf(view)):toBe(1)
	end)
end)
