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
local Events = require("@sim/Events")
local Rng = require("@sim/Rng")
local State = require("@sim/State")
local StateData = require("@sim/StateData")
local Types = require("@shared/Types")
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

	-- Week 5 with a Choice event, every state 35/35 in the polls, no draft or lean.
	local function stanceWeek(id: string): State.MatchState
		local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 4 }), "Plan", 5)
		match.eventDeck[5] = id
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
		"takes the stance that pays in the states it needs, and the hedge when it needs both camps (D-039)",
		function()
			local event = Events.byId.plant -- Jobs: A likes Transit and Farms, B likes Health and Safety
			local likedByA: { [string]: boolean }, likedByB: { [string]: boolean } = {}, {}
			for id, points in Events.stanceEffects(C, event, "A", {}) do
				if points > 0.5 then
					likedByA[id] = true
				elseif points < 0 then
					likedByB[id] = true
				end
			end
			local match = stanceWeek("plant")
			needOnly(match, likedByA)
			expect(Bot.plan(C, View.build(C, match, 1), Rng.new(1)).choice):toBe("A")
			expect(Bot.plan(C, View.build(C, match, 2), Rng.new(1)).choice):toBe("A")
			needOnly(match, likedByB)
			expect(Bot.plan(C, View.build(C, match, 1), Rng.new(1)).choice):toBe("B")
			-- Close everywhere: a side nets about nothing, the hedge is a sure gain.
			match = stanceWeek("plant")
			expect(Bot.plan(C, View.build(C, match, 1), Rng.new(1)).choice):toBe("C")
			-- The value the bot computes is the public per-state preview, EV-weighted.
			local view = View.build(C, match, 1)
			local estimates = Bot.estimates(C, view)
			local platform = view.players[1].platform :: { Types.Issue }
			local valueA = Bot.stanceValue(C, estimates, view.event :: any, "A", platform)
			local valueC = Bot.stanceValue(C, estimates, view.event :: any, "C", platform)
			expect(valueC > valueA):toBe(true)
		end
	)

	it("the RandomStance style takes every slot about equally; every style carries a valid stance", function()
		local match = stanceWeek("river")
		local seen: { [string]: number } = { A = 0, B = 0, C = 0 }
		local N = 600
		for k = 1, N do
			local plan = Bot.plan(C, View.build(C, match, 1), Rng.new(k), "RandomStance")
			seen[plan.choice] += 1
		end
		for _, id in Events.CHOICES do
			expect(math.abs(seen[id] / N - 1 / 3) < 0.07):toBe(true)
		end
		for _, style in { "Balanced", "Random", "AttackOnly", "RandomStance" } do
			local plan = Bot.plan(C, View.build(C, match, 1), Rng.new(2), style :: Bot.Style)
			expect(Events.isChoice(plan.choice)):toBe(true)
		end
		match.eventDeck[5] = nil
		expect(Bot.plan(C, View.build(C, match, 1), Rng.new(2)).choice):toBe(nil)
	end)

	it("preps the topic whose states it needs, within the per-topic cap (D-040)", function()
		local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 4 }), "Plan", 3)
		expect(match.debateTopics[4] ~= nil):toBe(true)
		local topics = match.debateTopics[4]
		for t = 1, #topics do
			local camp: { [string]: boolean } = {}
			for _, id in StateData.list do
				camp[id.id] = table.find(id.issues, topics[t]) ~= nil
			end
			-- Only this topic's states are close; the rest are decided.
			for _, s in match.states do
				s.poll = if camp[s.id]
					then { support = { 35, 35 }, undecided = 30 }
					else { support = { 60, 20 }, undecided = 20 }
			end
			local prep = Bot.plan(C, View.build(C, match, 1), Rng.new(1)).prep :: { number }
			local total = 0
			for _, points in prep do
				expect(points <= C.DEBATE_MAX_PER_TOPIC):toBe(true)
				total += points
			end
			expect(total):toBe(match.players[1].profile.debatePrep)
			for u = 1, #topics do
				if u ~= t then
					expect(prep[t] > prep[u]):toBe(true)
				end
			end
		end
	end)
end)
