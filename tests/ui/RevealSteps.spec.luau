--!strict
-- Shared/UI/RevealSteps (D-063): the end-of-week reveal as a running tally.
-- Each move's step must be the sim's own arithmetic (with true support in
-- place of the polls and no drift it adds up to exactly what Resolve did), the
-- last step must land on the real new polls and projected votes, the numbers
-- must not depend on whose screen it is or on the reveal order (D-001), and
-- only the player's own View and public events go in.

local Bot = require("@sim/Bot")
local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Fixtures = require("@ui/Fixtures")
local Match = require("@sim/Match")
local Resolve = require("@sim/Resolve")
local RevealSteps = require("@ui/RevealSteps")
local Rng = require("@sim/Rng")
local State = require("@sim/State")
local Test = require("@testlib/Test")
local View = require("@sim/View")
local Words = require("@ui/Words/Reveal")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local NO_DRIFT = Config.with(C, { DRIFT_RATE = 0 })

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

-- The View with every public poll replaced by the true shares (no noise).
local function truthView(config: any, match: State.MatchState, p: number): any
	local view = View.build(config, match, p) :: any
	for i, s in match.states do
		view.states[i].poll = { support = table.clone(s.support), undecided = s.undecided }
	end
	return view
end

type Week = {
	before: any,
	after: any,
	events: { State.Event },
	match: State.MatchState,
	next: State.MatchState,
}

-- Plays a bot match with `config` and hands each Plan week (both seats'
-- inputs, the match before and after) to `visit`.
local function playWeeks(config: any, seed: number, candidates: { string }, visit: (week: Week) -> ())
	local match = Match.new(config, seed, { "p1", "p2" })
	local rngs = { Rng.new(seed * 3 + 1), Rng.new(seed * 3 + 2) }
	local guard = 0
	while match.phase ~= "Done" and match.phase ~= "Election" do
		guard += 1
		assert(guard < 200, "the match never ended")
		local inputs = {}
		if Match.wantsInput(match) then
			for p = 1, 2 do
				inputs[p] = Bot.act(config, View.build(config, match, p), rngs[p], candidates[p])
			end
		end
		local planning = match.phase == "Plan"
		local nextMatch, events = Match.advance(config, match, inputs)
		if planning then
			visit({ before = nil, after = nil, events = events, match = match, next = nextMatch })
		end
		match = nextMatch
	end
end

local PAIRS = {
	{ Candidates.ids[1], Candidates.ids[2] },
	{ Candidates.ids[3] or Candidates.ids[1], Candidates.ids[4] or Candidates.ids[2] },
	{ Candidates.ids[#Candidates.ids], Candidates.ids[1] },
}

describe("RevealSteps: the moves are the sim's arithmetic", function()
	it("with true support for polls and no drift, the moves add up to what Resolve did", function()
		local weeks = 0
		local moves = 0
		for k, pair in PAIRS do
			playWeeks(NO_DRIFT, 300 + k, pair, function(week)
				for p = 1, 2 do
					local before = truthView(NO_DRIFT, week.match, p)
					local after = truthView(NO_DRIFT, week.next, p)
					local tally = RevealSteps.build(NO_DRIFT, before, after, View.events(week.events, p))
					local steps = tally.steps
					check(steps[#steps].kind == "Settle", "the last step is not the settle")
					local moved = RevealSteps.viewAt(tally, #steps - 1)
					for i, s in week.next.states do
						local poll = moved.states[i].poll
						for q = 1, 2 do
							local diff = math.abs(poll.support[q] - s.support[q])
							check(
								diff < 1e-6,
								`week {week.match.week} seat {p} {s.id} player {q}: moves say {poll.support[q]}, Resolve {s.support[q]}`
							)
						end
						check(math.abs(poll.undecided - s.undecided) < 1e-6, `{s.id} undecided off`)
					end
					for _, step in steps do
						if step.kind == "Move" and step.moving then
							moves += 1
						end
					end
				end
				weeks += 1
			end)
		end
		check(weeks >= 30, `only {weeks} weeks checked`)
		check(moves >= 100, `only {moves} moves checked`)
	end)

	it("the numbers are the same whichever seat watches (D-001)", function()
		playWeeks(C, 411, PAIRS[1], function(week)
			local shares: { { any } } = {}
			for p = 1, 2 do
				local before = View.build(C, week.match, p)
				local after = View.build(C, week.next, p)
				local tally = RevealSteps.build(C, before, after, View.events(week.events, p))
				local moved = RevealSteps.viewAt(tally, #tally.steps - 1)
				shares[p] = {}
				for i, s in moved.states do
					shares[p][i] = s.poll
				end
			end
			for i, poll in shares[1] do
				local other = shares[2][i]
				for q = 1, 2 do
					check(
						math.abs(poll.support[q] - other.support[q]) < 1e-9,
						`week {week.match.week} state {i}: seat 1 sees {poll.support[q]}, seat 2 {other.support[q]}`
					)
				end
			end
		end)
	end)
end)

describe("RevealSteps: the steps", function()
	it("ends exactly on the new polls and projected votes", function()
		playWeeks(C, 512, PAIRS[2], function(week)
			local before = View.build(C, week.match, 1)
			local after = View.build(C, week.next, 1)
			local tally = RevealSteps.build(C, before, after, View.events(week.events, 1))
			local last = tally.steps[#tally.steps]
			expect(last.kind):toBe("Settle")
			expect(last.ev):toEqual(after.projectedEV)
			check(RevealSteps.viewAt(tally, #tally.steps) == after, "the last view is not the real one")
			check(RevealSteps.viewAt(tally, 99) == after, "past the end is not the real one")
			check(RevealSteps.viewAt(tally, 0) == before, "step 0 is not the week's start")
			-- The settle's change plus every move's is the week's real change.
			local total: { [string]: number } = {}
			for _, step in tally.steps do
				for id, d in step.net do
					total[id] = (total[id] or 0) + d
				end
			end
			for _, s in after.states do
				local real = (RevealSteps.margin(after, s.id) or 0) - (RevealSteps.margin(before, s.id) or 0)
				check(
					math.abs((total[s.id] or 0) - real) < RevealSteps.MIN_MOVE * #tally.steps,
					`{s.id}: steps add to {total[s.id] or 0}, polls moved {real}`
				)
			end
		end)
	end)

	it("puts one move in each step, the first player's first, and keeps every shown event", function()
		playWeeks(C, 613, PAIRS[3], function(week)
			local before = View.build(C, week.match, 2)
			local after = View.build(C, week.next, 2)
			local events = View.events(week.events, 2)
			local tally = RevealSteps.build(C, before, after, events)
			local shown = 0
			for _, event in events do
				if Words.shows(event) then
					shown += 1
				end
			end
			expect(#RevealSteps.eventsUpTo(tally, #tally.steps)):toBe(shown)
			check(#tally.steps <= shown + 1, "more steps than events")
			-- The server's reveal time counts at least as many steps as any screen shows (D-063).
			check(
				#tally.steps <= Resolve.revealSteps(week.events),
				`{#tally.steps} steps on screen, the server timed {Resolve.revealSteps(week.events)}`
			)
			local first = tally.steps[1]
			if first.kind == "Move" and first.player ~= nil then
				expect(first.player):toBe(Words.revealFirst(before))
			end
			local seenOther = false
			for k, step in tally.steps do
				if step.kind == "Settle" then
					expect(k):toBe(#tally.steps)
				else
					check(#step.events > 0, "an empty step")
					if step.player ~= nil and step.player ~= tally.first then
						seenOther = true
					elseif seenOther then
						error("the first player's moves came after the other's", 0)
					end
					local lead = RevealSteps.lead(step)
					check(lead ~= nil, "a step about nothing")
				end
			end
		end)
	end)

	it("estimates nothing without the week's start: every step shows the new View", function()
		local payload = Fixtures.payload(C, "Resolve")
		local tally = RevealSteps.build(C, nil, payload.view, payload.events)
		for k, step in tally.steps do
			check(RevealSteps.viewAt(tally, k) == payload.view, `step {k} is not the new view`)
			check(next(step.net) == nil, `step {k} badges a move`)
			expect(step.ev):toEqual(payload.view.projectedEV)
		end
	end)

	it("moves the projected votes and the map during the UI fixture's week", function()
		local plan = Fixtures.payload(C, "Plan")
		local payload = Fixtures.payload(C, "Resolve")
		local tally = RevealSteps.build(C, plan.view, payload.view, payload.events)
		check(#tally.steps >= 3, `only {#tally.steps} steps`)
		local moved = 0
		for _, step in tally.steps do
			if next(step.net) ~= nil then
				moved += 1
			end
		end
		check(moved >= 2, `only {moved} steps move the map`)
		expect(tally.steps[1].ev):toEqual(RevealSteps.viewAt(tally, 1).projectedEV)
	end)
end)
