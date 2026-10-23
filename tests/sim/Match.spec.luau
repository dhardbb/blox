--!strict
-- Match state machine: phase order, determinism, purity of advance, defaults.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Match = require("@sim/Match")
local State = require("@sim/State")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function playOut(seed: number): { string }
	local match = Match.new(C, seed, { "a", "b" })
	local trail = {}
	while match.phase ~= "Done" do
		table.insert(trail, `{match.phase}:{match.week}:{match.draftRound}`)
		match = Match.advance(C, match, {})
		Fixtures.checkSupport(match)
	end
	return trail
end

describe("Match", function()
	it("walks Select, MapReveal, 8 draft rounds, 12 weeks with debates, election", function()
		local trail = playOut(11)
		expect(trail[1]):toBe("Select:0:0")
		expect(trail[2]):toBe("MapReveal:0:0")
		for round = 0, 7 do
			expect(trail[3 + round]):toBe(`Draft:0:{round}`)
		end
		local weeks, debates = 0, {}
		for _, step in trail do
			if string.sub(step, 1, 5) == "Plan:" then
				weeks += 1
			elseif string.sub(step, 1, 7) == "Debate:" then
				table.insert(debates, step)
			end
		end
		expect(weeks):toBe(C.WEEKS)
		expect(debates):toEqual({ "Debate:4:7", "Debate:9:7" })
		expect(trail[#trail]):toBe("Election:13:7")
		expect(#trail):toBe(2 + 8 + 12 + 2 + 1)
	end)

	it("is deterministic: same seed and inputs give the same match", function()
		local function run(seed: number): State.MatchState
			local match = Match.new(C, seed, { "a", "b" })
			while match.phase ~= "Done" do
				match = Match.advance(C, match, {})
			end
			return match
		end
		expect(run(5)):toEqual(run(5))
	end)

	it("advance never mutates its argument", function()
		local match = Fixtures.campaign({ seed = 2 })
		local before = State.clone(match)
		local plan = { actions = { { kind = "Rally", state = match.players[1].location, issue = "Jobs" } } }
		Match.advance(C, match, { plan })
		expect(match):toEqual(before)
	end)

	it("an invalid input is replaced by the default, never partially applied", function()
		local match = Fixtures.campaign({ seed = 2 })
		local cash = match.players[1].cash
		local bad = {
			actions = {
				{ kind = "Media", state = "OH", issue = "Jobs" },
				{ kind = "Media", state = "OH", issue = "Jobs" },
				{ kind = "Media", state = "OH", issue = "Jobs" },
				{ kind = "Media", state = "OH", issue = "Jobs" }, -- $12 > $8
			},
		}
		expect((Match.validate(C, match, 1, bad))):toBe(false)
		local nextMatch = Match.advance(C, match, { bad })
		expect(nextMatch.players[1].cash):toBe(cash + match.players[1].profile.passiveIncome)
	end)

	it(
		"select reveals candidates and starting cash; two picks of one candidate never both stand (D-045)",
		function()
			local match = Match.new(C, 4, { "a", "b" })
			local same = { candidate = "hale", platform = { "Jobs", "Farms", "Safety" } }
			match = Match.advance(C, match, { same, same })
			local kept = if match.players[1].candidate == "hale" then 1 else 2
			expect(match.players[kept].candidate):toBe("hale")
			expect(match.players[kept].cash):toBe(0) -- Hale starts with nothing (D-023)
			expect(match.players[3 - kept].candidate ~= "hale"):toBe(true)
			expect(match.players[1].color ~= match.players[2].color):toBe(true)
		end
	)

	it("rejects malformed selections and ignores an old client's color", function()
		local match = Match.new(C, 4, { "a", "b" })
		local bad: { any } = {
			{ candidate = "nobody", platform = { "Jobs", "Farms", "Safety" } },
			{ candidate = "hale", platform = { "Jobs", "Farms" } },
			{ candidate = "hale", platform = { "Jobs", "Jobs", "Safety" } },
			{ candidate = "hale", platform = { "Jobs", "Farms", "Crime" } },
			"hale",
		}
		for _, input in bad do
			expect((Match.validate(C, match, 1, input))):toBe(false)
		end
		expect((Match.validate(C, match, 3, bad[1]))):toBe(false)
		local ok, _, normalized = Match.validate(
			C,
			match,
			1,
			{ candidate = "hale", color = "Red", platform = { "Jobs", "Farms", "Safety" } }
		)
		expect(ok):toBe(true)
		expect(normalized.color):toBe(nil)
	end)

	it("cannot advance a finished match", function()
		local match = Fixtures.advanceTo(Match.new(C, 1, { "a", "b" }), "Done")
		expect(match.election ~= nil):toBe(true)
		expect(function()
			Match.advance(C, match, {})
		end):toThrow("cannot advance")
	end)
end)

describe("drawn colors (D-044)", function()
	local View = require("@sim/View")

	it("gives every player a different color from the seed, shown from Select on", function()
		for seed = 1, 50 do
			local match = Match.new(C, seed, { "a", "b" })
			local one, two = match.players[1].color, match.players[2].color
			expect(table.find(Candidates.colors, one) ~= nil and table.find(Candidates.colors, two) ~= nil):toBe(
				true
			)
			expect(one ~= two):toBe(true)
			expect(View.build(C, match, 2).players[1].color):toBe(one)
			expect(Match.new(C, seed, { "x", "y" }).players[1].color):toBe(one)
		end
	end)

	it("favors no seat: each seat gets each color about equally (D-001)", function()
		local first: { [string]: number } = {}
		for seed = 1, 600 do
			local color = Match.new(C, seed, { "a", "b" }).players[1].color
			first[color] = (first[color] or 0) + 1
		end
		for _, color in Candidates.colors do
			-- 600 draws over six colors: about 100 each.
			local n = first[color] or 0
			expect(n > 60 and n < 140):toBe(true)
		end
	end)
end)

describe("unique candidates (D-045)", function()
	local View = require("@sim/View")
	local function pick(candidate: string): any
		return { candidate = candidate, platform = { "Jobs", "Farms", "Safety" } }
	end

	it("a claim holds the candidate: the other seat is turned down, never applied", function()
		local match = Match.new(C, 4, { "a", "b" })
		local claimed, outcomes = Match.claim(C, match, { [2] = "venkat" })
		expect(outcomes[2]):toBe(nil)
		expect(claimed.claims.venkat):toBe(2)
		expect(match.claims.venkat):toBe(nil) -- pure: the argument is untouched
		expect(Match.claimOf(claimed, 2)):toBe("venkat")
		-- Seat 1 sees it taken, cannot claim or lock it in.
		expect(View.build(C, claimed, 1).claims.venkat):toBe(2)
		local ok, reason = Match.canClaim(claimed, 1, "venkat")
		expect(ok):toBe(false)
		expect(reason):toBe("CandidateTaken")
		local valid, why = Match.validate(C, claimed, 1, pick("venkat"))
		expect(valid):toBe(false)
		expect(why):toBe("CandidateTaken")
		local again, lost = Match.claim(C, claimed, { [1] = "venkat" })
		expect(lost[1]):toBe("CandidateTaken")
		expect(again.claims.venkat):toBe(2)
		-- Seat 2 may lock in only its claim; one claim per seat.
		expect((Match.validate(C, claimed, 2, pick("hale")))):toBe(false)
		expect(select(2, Match.canClaim(claimed, 2, "hale"))):toBe("AlreadyClaimed")
		expect((Match.validate(C, claimed, 2, pick("venkat")))):toBe(true)
		-- Even a bad input for seat 1 at the deadline cannot take it.
		local done = Match.advance(C, claimed, { pick("venkat"), pick("venkat") })
		expect(done.players[2].candidate):toBe("venkat")
		expect(done.players[1].candidate ~= "venkat"):toBe(true)
	end)

	it("settles a same-step clash by a seeded coin flip, not by seat (D-001)", function()
		local wins = { 0, 0 }
		for seed = 1, 400 do
			local match, outcomes = Match.claim(C, Match.new(C, seed, { "a", "b" }), { "hale", "hale" })
			local winner = match.claims.hale
			wins[winner] += 1
			expect(outcomes[winner]):toBe(nil)
			expect(outcomes[3 - winner]):toBe("CandidateTaken")
			-- Deterministic: the same state and batch settle the same way.
			local again = Match.claim(C, Match.new(C, seed, { "a", "b" }), { "hale", "hale" })
			expect(again.claims.hale):toBe(winner)
		end
		-- 400 fair coin flips land within 160..240 with overwhelming probability.
		expect(wins[1] > 160 and wins[2] > 160):toBe(true)
	end)

	it("a timeout default takes your claim, or a free candidate from the seed", function()
		local match = Match.new(C, 9, { "a", "b" })
		match = Match.claim(C, match, { [1] = "okafor" })
		expect(Match.default(C, match, 1).candidate):toBe("okafor")
		local seen: { [string]: boolean } = {}
		for seed = 1, 60 do
			local m = Match.claim(C, Match.new(C, seed, { "a", "b" }), { [1] = "okafor" })
			local fallback = Match.default(C, m, 2).candidate
			expect(fallback ~= "okafor"):toBe(true)
			expect(Match.default(C, m, 2).candidate):toBe(fallback)
			seen[fallback] = true
			local done = Match.advance(C, m, {})
			expect(done.players[1].candidate):toBe("okafor")
			expect(done.players[2].candidate ~= "okafor"):toBe(true)
		end
		local kinds = 0
		for _ in seen do
			kinds += 1
		end
		expect(kinds >= 4):toBe(true)
	end)

	it("never lets two players end Select with one candidate", function()
		for seed = 1, 200 do
			local match = Match.new(C, seed, { "a", "b" })
			local inputs = { pick("strand"), pick("strand") }
			if seed % 3 == 0 then
				match = Match.claim(C, match, { [2] = "strand" })
			end
			local done = Match.advance(C, match, if seed % 2 == 0 then inputs else {})
			expect(done.players[1].candidate ~= done.players[2].candidate):toBe(true)
		end
	end)
end)
