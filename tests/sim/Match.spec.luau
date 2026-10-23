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
		local tag = if match.decision then `:{match.decision}` else ""
		table.insert(trail, `{match.phase}:{match.week}:{match.draftRound}{tag}`)
		match = Match.advance(C, match, {})
		Fixtures.checkSupport(match)
	end
	return trail
end

describe("Match", function()
	it("walks Select, MapReveal, 3 draft rounds, 12 weeks with decisions and debates, election", function()
		local trail = playOut(11)
		expect(trail[1]):toBe("Select:0:0")
		expect(trail[2]):toBe("MapReveal:0:0")
		for round = 0, 2 do
			expect(trail[3 + round]):toBe(`Draft:0:{round}`)
		end
		local weeks, debates, stances = 0, {}, 0
		for k, step in trail do
			if string.sub(step, 1, 5) == "Plan:" then
				weeks += 1
			elseif string.sub(step, 1, 7) == "Debate:" then
				table.insert(debates, step)
				-- Prep is decided right before the debate it feeds (D-044).
				expect(trail[k - 1]):toBe(`Decision:{string.match(step, "^Debate:(%d+)")}:2:Focus`)
			elseif string.match(step, ":Stance$") then
				stances += 1
				local week = string.match(step, "^Decision:(%d+)")
				expect(trail[k + 1]):toBe(`Plan:{week}:2`)
			end
		end
		expect(weeks):toBe(C.WEEKS)
		expect(debates):toEqual({ "Debate:4:2", "Debate:9:2" })
		expect(stances > 0):toBe(true)
		expect(trail[#trail]):toBe("Election:13:2")
		expect(#trail):toBe(2 + 3 + 12 + 2 * 2 + stances + 1)
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
		"select reveals candidates and starting cash; two picks of one candidate never both stand (D-048)",
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

describe("colors: red and blue by default, Color Pass owners claim theirs (D-055, D-061)", function()
	local View = require("@sim/View")

	type Pass = { [string]: Match.ColorPass }

	local function colorsOf(match: State.MatchState): { string }
		local out = {}
		for p, player in match.players do
			out[p] = player.color
		end
		return out
	end

	local function newMatch(seed: number, ids: { string }?, pass: Pass?): State.MatchState
		return Match.new(C, seed, ids or { "a", "b" }, pass)
	end

	local function distinct(match: State.MatchState)
		local seen: { [string]: boolean } = {}
		for _, player in match.players do
			expect(table.find(Candidates.colors, player.color) ~= nil):toBe(true)
			expect(seen[player.color]):toBe(nil)
			seen[player.color] = true
		end
	end

	it("deals one Crimson and one Cobalt to two players without the pass, every match", function()
		for seed = 1, 200 do
			local one, two = table.unpack(colorsOf(newMatch(seed)))
			local pair = { [one] = true, [two] = true }
			expect(pair.Crimson == true and pair.Cobalt == true):toBe(true)
		end
	end)

	it("shows colors from Select on, and the same seed and passes give the same colors", function()
		for seed = 1, 50 do
			local match = newMatch(seed)
			local one = match.players[1].color
			expect(View.build(C, match, 2).players[1].color):toBe(one)
			expect(newMatch(seed, { "x", "y" }).players[1].color):toBe(one)
			local pass: Pass = { a = { favorite = "Emerald" }, b = { favorite = "Emerald" } }
			expect(newMatch(seed, nil, pass)):toEqual(newMatch(seed, nil, table.clone(pass)))
		end
	end)

	it("favors no seat: each seat gets Crimson about half the time (D-001)", function()
		local first = 0
		for seed = 1, 1000 do
			if newMatch(seed).players[1].color == "Crimson" then
				first += 1
			end
		end
		-- 1,000 coin flips: 500 ± 16 is one standard deviation.
		expect(first > 440 and first < 560):toBe(true)
	end)

	it("claims an owner's favorite as Select opens; the other player gets red or blue", function()
		for seed = 1, 100 do
			local match = newMatch(seed, nil, { b = { favorite = "Crimson" } })
			expect(colorsOf(match)):toEqual({ "Cobalt", "Crimson" })
			expect(match.colorClaims):toEqual({ Crimson = 2 })
			match = newMatch(seed, nil, { a = { favorite = "Cobalt" } })
			expect(colorsOf(match)):toEqual({ "Cobalt", "Crimson" })
			match = newMatch(seed, nil, { a = { favorite = "Emerald" } })
			expect(match.players[1].color):toBe("Emerald")
			local other = match.players[2].color
			expect(other == "Crimson" or other == "Cobalt"):toBe(true)
			-- An owner without a favorite starts with a dealt color and no claim.
			match = newMatch(seed, nil, { a = {} })
			expect(match.colorClaims):toEqual({})
			expect(colorsOf(match)):toEqual(colorsOf(newMatch(seed)))
		end
	end)

	it("ignores an unknown favorite and a pass for someone who is not playing", function()
		for seed = 1, 50 do
			local match = newMatch(
				seed,
				nil,
				{ a = { favorite = "Gold" }, b = { favorite = "red" }, z = {
					favorite = "Teal",
				} }
			)
			expect(colorsOf(match)):toEqual(colorsOf(newMatch(seed)))
			expect(match.colorClaims):toEqual({})
		end
	end)

	it(
		"settles two owners with the same favorite by a fair coin flip; the loser keeps the pass and picks another",
		function()
			local wins = 0
			for seed = 1, 1000 do
				local match =
					newMatch(seed, nil, { a = { favorite = "Violet" }, b = { favorite = "Violet" } })
				distinct(match)
				local winner = match.colorClaims.Violet
				expect(winner == 1 or winner == 2):toBe(true)
				local loser = 3 - winner
				expect(match.players[winner].color):toBe("Violet")
				-- Not a claim: a provisional red or blue until they pick (D-061).
				expect(Match.colorClaimOf(match, loser)):toBe(nil)
				local dealt = match.players[loser].color
				expect(dealt == "Crimson" or dealt == "Cobalt"):toBe(true)
				expect(View.build(C, match, loser).canPickColor):toBe(true)
				if seed <= 50 then
					local after, outcomes = Match.claimColor(C, match, { [loser] = "Teal" })
					expect(outcomes[loser]):toBe(nil)
					expect(after.players[loser].color):toBe("Teal")
					expect(after.players[winner].color):toBe("Violet")
				end
				if winner == 1 then
					wins += 1
				end
			end
			expect(wins > 440 and wins < 560):toBe(true)
		end
	)

	it("is first come, first served: a claimed color is taken, any free one can be claimed", function()
		local match = newMatch(4, nil, { a = {}, b = {} })
		local claimed, outcomes = Match.claimColor(C, match, { [1] = "Teal" })
		expect(outcomes[1]):toBe(nil)
		expect(claimed.players[1].color):toBe("Teal")
		expect(claimed.colorClaims.Teal):toBe(1)
		expect(match.colorClaims.Teal):toBe(nil) -- pure: the argument is untouched
		-- Everyone sees it claimed at once.
		expect(View.build(C, claimed, 2).colorClaims.Teal):toBe(1)
		local ok, reason = Match.canClaimColor(claimed, 2, "Teal")
		expect(ok):toBe(false)
		expect(reason):toBe("ColorTaken")
		local again, lost = Match.claimColor(C, claimed, { [2] = "Teal" })
		expect(lost[2]):toBe("ColorTaken")
		expect(again.colorClaims.Teal):toBe(1)
		expect(again.players[2].color == "Crimson" or again.players[2].color == "Cobalt"):toBe(true)
		-- Seat 2 takes another free color; re-claiming your own is fine.
		local both, fine = Match.claimColor(C, again, { [1] = "Teal", [2] = "Amber" })
		expect(fine):toEqual({})
		expect(colorsOf(both)):toEqual({ "Teal", "Amber" })
	end)

	it("settles claims of the same color in one step by a fair, seeded coin flip", function()
		local wins = { 0, 0 }
		for seed = 1, 1000 do
			local match = newMatch(seed, nil, { a = {}, b = {} })
			local after, outcomes = Match.claimColor(C, match, { "Amber", "Amber" })
			local winner = after.colorClaims.Amber
			wins[winner] += 1
			local loser = 3 - winner
			expect(outcomes[loser]):toBe("ColorTaken")
			expect(outcomes[winner]):toBe(nil)
			distinct(after)
			-- The same seed and claims settle the same way.
			expect((Match.claimColor(C, match, { "Amber", "Amber" }))):toEqual(after)
			-- The loser can claim another color straight away.
			local next = Match.claimColor(C, after, { [loser] = "Crimson" })
			expect(next.players[loser].color):toBe("Crimson")
		end
		expect(wins[1] > 440 and wins[1] < 560):toBe(true)
	end)

	it("turns down a player without the pass, a bad color, and claims after Select", function()
		local match = newMatch(6, nil, { a = {} })
		expect(View.build(C, match, 1).canPickColor):toBe(true)
		expect(View.build(C, match, 2).canPickColor):toBe(false)
		local after, outcomes = Match.claimColor(C, match, { [2] = "Teal" })
		expect(outcomes[2]):toBe("NoColorPass")
		expect(after.colorClaims):toEqual({})
		expect(colorsOf(after)):toEqual(colorsOf(match))
		expect(select(2, Match.canClaimColor(match, 1, "Gold"))):toBe("UnknownColor")
		expect(select(2, Match.canClaimColor(match, 1, 5))):toBe("UnknownColor")
		expect(select(2, Match.canClaimColor(match, 3, "Teal"))):toBe("UnknownPlayer")
		local selected = Match.advance(C, match, {})
		expect(select(2, Match.canClaimColor(selected, 1, "Teal"))):toBe("WrongPhase")
		expect(View.build(C, selected, 1).canPickColor):toBe(false)
	end)

	it("a new claim releases the old color", function()
		local match = newMatch(8, nil, { a = {}, b = {} })
		local first = Match.claimColor(C, match, { [1] = "Teal" })
		local changed = Match.claimColor(C, first, { [1] = "Violet" })
		expect(changed.colorClaims):toEqual({ Violet = 1 })
		expect(changed.players[1].color):toBe("Violet")
		local taken = Match.claimColor(C, changed, { [2] = "Teal" })
		expect(taken.players[2].color):toBe("Teal")
		expect(taken.colorClaims):toEqual({ Violet = 1, Teal = 2 })
	end)

	it("claiming the color dealt to someone without a claim deals them the next default", function()
		for seed = 1, 100 do
			local match = newMatch(seed, nil, { a = {} })
			local dealt = match.players[2].color
			local after = Match.claimColor(C, match, { [1] = dealt })
			expect(after.players[1].color):toBe(dealt)
			local other = after.players[2].color
			expect(other ~= dealt and (other == "Crimson" or other == "Cobalt")):toBe(true)
		end
	end)

	it("keeps claimed colors at the end of Select and deals the rest, skipping taken colors", function()
		for seed = 1, 100 do
			local match = newMatch(seed, nil, { a = {} })
			match = Match.claimColor(C, match, { [1] = "Cobalt" })
			local done = Match.advance(C, match, {})
			expect(done.phase):toBe("MapReveal")
			expect(colorsOf(done)):toEqual({ "Cobalt", "Crimson" })
			match = Match.claimColor(C, newMatch(seed, nil, { a = {} }), { [1] = "Teal" })
			done = Match.advance(C, match, {})
			expect(done.players[1].color):toBe("Teal")
			expect(done.players[2].color == "Crimson" or done.players[2].color == "Cobalt"):toBe(true)
		end
	end)

	it("keeps colors distinct for more than two players", function()
		local ids = { "a", "b", "c", "d", "e", "f" }
		for seed = 1, 100 do
			local all: Pass = {}
			for _, id in ids do
				all[id] = {}
			end
			for _, pass in
				{
					{} :: Pass,
					{ a = { favorite = "Crimson" }, c = { favorite = "Crimson" }, f = { favorite = "Teal" } } :: Pass,
					{ b = { favorite = "Amber" }, d = { favorite = "Amber" } } :: Pass,
				}
			do
				local match = newMatch(seed, ids, pass)
				distinct(match)
				match = Match.claimColor(C, newMatch(seed, ids, all), { "Teal", "Teal", "Crimson", "Cobalt" })
				distinct(match)
			end
			-- Three without a claim: red and blue go to two of them.
			local defaults = 0
			for _, color in colorsOf(newMatch(seed, { "a", "b", "c" })) do
				if color == "Crimson" or color == "Cobalt" then
					defaults += 1
				end
			end
			expect(defaults):toBe(2)
		end
		local seatThreeRed = 0
		for seed = 1, 600 do
			local color = newMatch(seed, { "a", "b", "c" }).players[3].color
			if color == "Crimson" or color == "Cobalt" then
				seatThreeRed += 1
			end
		end
		-- Two of three seats get red or blue: about 400 of 600.
		expect(seatThreeRed > 340 and seatThreeRed < 460):toBe(true)
	end)

	it(
		"changes no other seeded stream: the issue map and leans are the same with or without claims",
		function()
			for seed = 1, 20 do
				local plain = newMatch(seed)
				local picked = newMatch(seed, nil, { a = { favorite = "Teal" }, b = { favorite = "Amber" } })
				expect(colorsOf(picked)):toEqual({ "Teal", "Amber" })
				for i, state in plain.states do
					expect(picked.states[i].lean):toBe(state.lean)
					expect(picked.states[i].leanTo):toBe(state.leanTo)
				end
				expect(picked.issueMap):toEqual(plain.issueMap)
				expect(picked.priorityA):toBe(plain.priorityA)
			end
		end
	)
end)

describe("unique candidates (D-048)", function()
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
