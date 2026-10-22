--!strict
-- Leans (D-008) and the blind draft (D-007, D-009).

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Config = require("@sim/Config")
local Draft = require("@sim/Draft")
local Leans = require("@sim/Leans")
local Match = require("@sim/Match")
local Rng = require("@sim/Rng")
local State = require("@sim/State")
local StateData = require("@sim/StateData")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

describe("Leans", function()
	it("lean 30 states within bounds, mirrored in EV pairs, balanced", function()
		for seed = 1, 50 do
			local leans = Leans.generate(C, Rng.new(seed), 2)
			local count, weighted = 0, { 0, 0 }
			local byMagnitude: { [number]: { number } } = {}
			for i, lean in leans do
				if lean.lean > 0 then
					count += 1
					local ev = StateData.list[i].ev
					local cap = if ev >= C.BIG_STATE_EV then C.LEAN_BIG_STATE_CAP else C.LEAN_MAX
					expect(lean.lean >= C.LEAN_MIN and lean.lean <= cap):toBe(true)
					expect(lean.lean == math.floor(lean.lean)):toBe(true)
					local to = lean.leanTo :: number
					weighted[to] += ev * lean.lean
					local sides = byMagnitude[lean.lean] or { 0, 0 }
					sides[to] += 1
					byMagnitude[lean.lean] = sides
				end
			end
			expect(count):toBe(C.LEAN_STATE_COUNT)
			expect(math.abs(weighted[1] - weighted[2]) <= C.LEAN_MAX_EV_IMBALANCE):toBe(true)
			for _, sides in byMagnitude do
				expect(sides[1]):toBe(sides[2]) -- every magnitude is mirrored
			end
		end
	end)

	it("are deterministic by seed and differ across seeds", function()
		expect(Leans.generate(C, Rng.new(7), 2)):toEqual(Leans.generate(C, Rng.new(7), 2))
		local a, b = Leans.generate(C, Rng.new(7), 2), Leans.generate(C, Rng.new(8), 2)
		local same = true
		for i in a do
			if a[i].lean ~= b[i].lean or a[i].leanTo ~= b[i].leanTo then
				same = false
			end
		end
		expect(same):toBe(false)
	end)

	it("apply +L/2 and -L/2 around the base", function()
		local support = Leans.startingSupport(C, { lean = 4, leanTo = 2 }, 2)
		expect(support[1]):toBe(33)
		expect(support[2]):toBe(37)
		local none = Leans.startingSupport(C, { lean = 0, leanTo = nil }, 2)
		expect(none[1]):toBe(C.BASE_SUPPORT)
	end)
end)

-- A match in the draft with leans cleared, so bonuses can be checked exactly.
local function drafting(): State.MatchState
	local match = Fixtures.selected({ seed = 3 })
	match = Match.advance(C, match, {})
	expect(match.phase):toBe("Draft")
	for _, s in match.states do
		s.lean, s.leanTo = 0, nil
		s.support = { C.BASE_SUPPORT, C.BASE_SUPPORT }
		s.undecided = C.BASE_UNDECIDED
	end
	return match
end

local function pick(match: State.MatchState, a: { string }, b: { string }): State.MatchState
	return (Match.advance(C, match, { { choices = a }, { choices = b } }))
end

describe("Draft", function()
	it("priority follows A B B A B A A B from the seeded A", function()
		local match = drafting()
		local a = match.priorityA
		local b = 3 - a
		local expected = { a, b, b, a, b, a, a, b }
		for round = 0, 7 do
			expect(Draft.priorityPlayer(C, match, round)):toBe(expected[round + 1])
		end
	end)

	it("priority A is seeded and both players get it", function()
		local seen = { false, false }
		for seed = 1, 40 do
			seen[Match.new(C, seed, { "a", "b" }).priorityA] = true
		end
		expect(seen[1] and seen[2]):toBe(true)
	end)

	it("a first-choice clash goes to the priority player; the other gets their second", function()
		local match = drafting()
		local a = match.priorityA
		local choices = { { "OH", "PA" }, { "OH", "MI" } }
		local nextMatch = pick(match, choices[1], choices[2])
		local b = 3 - a
		expect(nextMatch.players[a].home):toBe("OH")
		expect(nextMatch.players[b].home):toBe(if b == 1 then "PA" else "MI")
	end)

	it("auto-fills a missing backup with the best platform-matching state", function()
		local match = drafting()
		local filled = Draft.autofill(C, match, 1, { "OH" })
		expect(#filled):toBe(2)
		expect(filled[1]):toBe("OH")
		-- Player 1's platform is Jobs/Health/Schools: the backup must share an issue.
		local record = StateData.byId[filled[2]]
		local matches = false
		for _, issue in record.issues do
			if table.find(match.players[1].platform, issue) then
				matches = true
			end
		end
		expect(matches):toBe(true)
	end)

	it("rejects bad submissions with reason codes and never throws", function()
		local match = drafting()
		local bad: { any } = {
			nil,
			5,
			{},
			{ choices = {} },
			{ choices = { "OH", "PA", "MI" } },
			{ choices = { "ZZ" } },
			{ choices = { "OH", "OH" } },
			{ choices = { 5 } },
			{ choices = { x = "OH" } },
		}
		for _, input in bad do
			local ok, reason = Match.validate(C, match, 1, input)
			expect(ok):toBe(false)
			expect(type(reason)):toBe("string")
		end
		expect((Match.validate(C, match, 1, { choices = { "OH" } }))):toBe(true)
	end)

	it("home states cannot be nominated; drafted states cannot be re-drafted", function()
		local match = pick(drafting(), { "OH" }, { "PA" })
		expect(Draft.isLegal(C, match, 1, 1, "OH")):toBe(false)
		expect(Draft.isLegal(C, match, 1, 1, "MI")):toBe(true)
		expect(Draft.isLegal(C, match, 1, 6, "OH")):toBe(false)
		expect(Draft.isLegal(C, match, 1, 6, "MI")):toBe(true)
	end)

	it("applies home, stronghold and big-state bonuses; battlegrounds reset to the lean", function()
		local match = drafting()
		match = pick(match, { "OH" }, { "CA" }) -- homes: OH (17 EV), CA (54 EV)
		match = pick(match, { "WI" }, { "TX" }) -- strongholds
		match = pick(match, { "MN" }, { "AZ" })
		match = pick(match, { "IA" }, { "NV" })
		match = pick(match, { "KS" }, { "NM" })
		match = pick(match, { "NE" }, { "UT" })
		match.states[State.indexOf.AZ].lean = 4
		match.states[State.indexOf.AZ].leanTo = 2
		match.states[State.indexOf.AZ].support = { 33, 37 }
		match = pick(match, { "AZ" }, { "WI" }) -- nominations
		match = pick(match, { "NH" }, { "MN" })
		expect(match.phase):toBe("Plan")
		expect(match.week):toBe(1)

		local function support(id: string): { number }
			return State.get(match, id).support
		end
		-- Home +12: 47 / 31.4 (70% from undecided, 30% from the opponent).
		expect(support("OH")[1]):toBeCloseTo(47)
		expect(support("OH")[2]):toBeCloseTo(31.4)
		-- Big home +6.
		expect(support("CA")[2]):toBeCloseTo(41)
		-- Stronghold +8, big stronghold +4.
		expect(support("IA")[1]):toBeCloseTo(43)
		expect(support("TX")[2]):toBeCloseTo(39)
		-- Nominated strongholds lose their bonus but keep the lean.
		expect(support("WI")[1]):toBeCloseTo(35)
		expect(support("AZ")[1]):toBeCloseTo(33)
		expect(support("AZ")[2]):toBeCloseTo(37)
		expect(State.get(match, "AZ").battleground):toBe(true)
		expect(State.get(match, "NH").battleground):toBe(true)
		-- The candidate starts at home with polls published.
		expect(match.players[1].location):toBe("OH")
		expect(State.get(match, "OH").poll ~= nil):toBe(true)
		Fixtures.checkSupport(match)
	end)

	it("a nomination clash falls back to the second choice", function()
		local match = drafting()
		for _ = 1, 6 do
			match = Match.advance(C, match, {})
		end
		expect(Draft.kind(C, match.draftRound)):toBe("Nominate")
		local p = Draft.priorityPlayer(C, match, match.draftRound)
		local q = 3 - p
		local legal = {}
		for _, record in StateData.list do
			if Draft.isLegal(C, match, p, match.draftRound, record.id) then
				table.insert(legal, record.id)
			end
		end
		local inputs = {}
		inputs[p] = { choices = { legal[1], legal[2] } }
		inputs[q] = { choices = { legal[1], legal[3] } }
		match = Match.advance(C, match, inputs)
		expect(table.find(match.players[p].nominations, legal[1]) ~= nil):toBe(true)
		expect(table.find(match.players[q].nominations, legal[3]) ~= nil):toBe(true)
	end)
end)
