--!strict
-- Shared/UI/PollMiss (D-073): the end screen's map, final polls against the
-- real result, and the states the polls called wrong.

local Config = require("@sim/Config")
local Fixtures = require("@ui/Fixtures")
local PollMiss = require("@ui/PollMiss")
local Polls = require("@sim/Polls")
local StateData = require("@sim/StateData")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local cached: any = nil
local function overView(): any
	if cached == nil then
		local payload = Fixtures.payload(C, "Over") :: any
		cached = payload.view
	end
	return cached
end

-- A small View by hand: three states with these polls and results.
local function tiny(polls: { { number }? }, results: { { winner: number, margin: number } }): any
	local ids = { "OH", "PA", "NV" }
	local states = {}
	local rows = {}
	for k, id in ids do
		local shares = polls[k]
		states[k] = {
			id = id,
			lean = 2,
			leanTo = 1,
			poll = if shares then { support = shares, undecided = 100 - shares[1] - shares[2] } else nil,
		}
		rows[k] = { state = id, winner = results[k].winner, margin = results[k].margin }
	end
	return {
		you = 1,
		players = { {}, {} },
		states = states,
		election = { ev = { 0, 0 }, results = rows },
	}
end

describe("PollMiss.rows", function()
	it("reads each state's final poll and its result", function()
		local view = tiny(
			{ { 46, 42 }, { 40, 44 }, { 45, 45 } },
			{ { winner = 1, margin = 3.5 }, { winner = 1, margin = 0.4 }, { winner = 2, margin = 1 } }
		)
		local rows = PollMiss.rows(view)
		expect(#rows):toBe(3)
		expect(rows[1].pollLeader):toBe(1)
		expect(rows[1].pollLead):toBeCloseTo(4)
		expect(rows[1].miss):toBe(false)
		expect(rows[2].pollLeader):toBe(2)
		expect(rows[2].winner):toBe(1)
		expect(rows[2].miss):toBe(true)
		-- A tied poll called nobody: it cannot miss.
		expect(rows[3].pollLeader):toBe(0)
		expect(rows[3].miss):toBe(false)
		expect(rows[2].ev):toBe(StateData.byId.PA.ev)
	end)

	it("never counts a state without a poll or with a tied count as a miss", function()
		local view = tiny(
			{ nil, { 40, 44 }, { 50, 40 } },
			{ { winner = 2, margin = 2 }, { winner = 0, margin = 0 }, { winner = 1, margin = 9 } }
		)
		for _, row in PollMiss.rows(view) do
			check(not row.miss, `{row.id} counted as a miss`)
		end
	end)

	it("agrees with the sim's own leaders on a real match", function()
		local view = overView()
		local rows = PollMiss.rows(view)
		expect(#rows):toBe(#view.states)
		local results = {}
		for _, r in view.election.results do
			results[r.state] = r
		end
		for k, row in rows do
			local s = view.states[k]
			expect(row.id):toBe(s.id)
			expect(row.pollLeader):toBe(Polls.leader(s.poll))
			expect(row.winner):toBe(results[s.id].winner)
			expect(row.miss):toBe(row.pollLeader ~= 0 and row.winner ~= 0 and row.pollLeader ~= row.winner)
		end
	end)
end)

describe("PollMiss.votes", function()
	it("is the header's projection on the final polls and the real count on election night", function()
		local view = overView()
		local rows = PollMiss.rows(view)
		expect(PollMiss.votes(rows, "Polls", 2)):toEqual(view.projectedEV)
		local won = PollMiss.votes(rows, "Result", 2)
		expect(won):toEqual(view.election.ev)
	end)
end)

describe("PollMiss.summary", function()
	local function row(id: string, ev: number): any
		return { id = id, ev = ev, pollLeader = 1, pollLead = 1, winner = 2, margin = 1, miss = true }
	end

	it("names the misses, most votes first", function()
		local rows =
			{ row("NV", 6), row("WI", 10), row("AZ", 11), { id = "OH", ev = 17, miss = false } :: any }
		local misses = PollMiss.misses(rows)
		expect(#misses):toBe(3)
		expect(PollMiss.summary(misses)):toBe("Polls missed 3 states: AZ, WI, NV")
	end)

	it("says one state and no state plainly", function()
		expect(PollMiss.summary({ row("NV", 6) })):toBe("Polls missed 1 state: NV")
		expect(PollMiss.summary({})):toBe("The final polls called every state right.")
	end)

	it("keeps a long list to one short line", function()
		local rows = {}
		for k, id in { "TX", "FL", "PA", "OH", "GA", "NC", "MI", "AZ" } do
			table.insert(rows, row(id, 40 - k))
		end
		local text = PollMiss.summary(PollMiss.misses(rows))
		expect(text):toBe("Polls missed 8 states: TX, FL, PA, OH, GA, NC +2 more")
	end)

	it("breaks a tie on votes by state id", function()
		local misses = PollMiss.misses({ row("WI", 10), row("MN", 10) })
		expect(misses[1].id):toBe("MN")
	end)
end)

describe("PollMiss.mapStates", function()
	it("leaves the polls as they were in the polls mode", function()
		local view = overView()
		local states = PollMiss.mapStates(view, PollMiss.rows(view), "Polls")
		for k, s in states do
			expect(s.poll):toEqual(view.states[k].poll)
		end
	end)

	it("paints each result in its winner's favor, by its margin, never as a toss-up", function()
		local view = tiny(
			{ { 46, 42 }, { 40, 44 }, { 45, 45 } },
			{ { winner = 1, margin = 12 }, { winner = 2, margin = 0.4 }, { winner = 0, margin = 0 } }
		)
		local before = view.states[1].poll
		local states = PollMiss.mapStates(view, PollMiss.rows(view), "Result")
		expect(states[1].poll.support[1] - states[1].poll.support[2]):toBeCloseTo(12)
		expect(states[2].poll.support[2] - states[2].poll.support[1]):toBeCloseTo(PollMiss.RESULT_MIN_LEAD)
		expect(states[3].poll.support[1]):toBe(states[3].poll.support[2])
		expect(states[1].leanTo):toBe(nil)
		-- The View itself is unchanged.
		expect(view.states[1].poll):toBe(before)
		expect(view.states[1].leanTo):toBe(1)
	end)

	it("shows the leader and lead each mode names", function()
		local r =
			{ id = "OH", ev = 17, pollLeader = 2, pollLead = 1.5, winner = 1, margin = 4, miss = true } :: any
		local leader, lead = PollMiss.lead(r, "Polls")
		expect(leader):toBe(2)
		expect(lead):toBe(1.5)
		leader, lead = PollMiss.lead(r, "Result")
		expect(leader):toBe(1)
		expect(lead):toBe(4)
	end)
end)

describe("PollMiss words", function()
	it("writes a lead as whole points, or one decimal under a point", function()
		expect(PollMiss.leadText(3.4)):toBe("+3")
		expect(PollMiss.leadText(12.6)):toBe("+13")
		expect(PollMiss.leadText(0.4)):toBe("+0.4")
		expect(PollMiss.leadText(0)):toBe("+0.0")
	end)

	it("puts you first in the votes line", function()
		expect(PollMiss.votesLine("Polls", { 248, 290 }, 2, { "Rex", "Dana" })):toBe(
			"Final polls: you 290, Rex 248"
		)
		expect(PollMiss.votesLine("Result", { 302, 236 }, 1, { "Dana", "Rex" })):toBe(
			"Election night: you 302, Rex 236"
		)
	end)

	it("describes a tapped state, and says when the polls missed it", function()
		local row = {
			id = "NV",
			ev = 6,
			pollLeader = 2,
			pollLead = 1.2,
			winner = 1,
			margin = 2.44,
			miss = true,
		} :: any
		expect(PollMiss.stateLine(row, 1, { "Dana", "Rex" })):toBe(
			"Nevada · 6 votes. Final poll: Rex +1. Result: you by 2.4 points. The polls missed it."
		)
		local called =
			{ id = "OH", ev = 17, pollLeader = 0, pollLead = 0, winner = 2, margin = 5, miss = false } :: any
		expect(PollMiss.stateLine(called, 1, { "Dana", "Rex" })):toBe(
			"Ohio · 17 votes. Final poll: tied. Result: Rex by 5.0 points."
		)
	end)
end)
