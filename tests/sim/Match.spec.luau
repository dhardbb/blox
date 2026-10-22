--!strict
-- Match state machine: phase order, determinism, purity of advance, defaults.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
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

	it("select reveals candidates, starting cash and unique colors", function()
		local match = Match.new(C, 4, { "a", "b" })
		local same = { candidate = "hale", color = "Teal", platform = { "Jobs", "Farms", "Safety" } }
		match = Match.advance(C, match, { same, same })
		expect(match.players[1].candidate):toBe("hale")
		expect(match.players[1].cash):toBe(0) -- Hale starts with nothing (D-023)
		expect(match.players[1].color ~= match.players[2].color):toBe(true)
		expect(match.players[1].color == "Teal" or match.players[2].color == "Teal"):toBe(true)
	end)

	it("rejects malformed selections", function()
		local match = Match.new(C, 4, { "a", "b" })
		local bad: { any } = {
			{ candidate = "nobody", color = "Teal", platform = { "Jobs", "Farms", "Safety" } },
			{ candidate = "hale", color = "Red", platform = { "Jobs", "Farms", "Safety" } },
			{ candidate = "hale", color = "Teal", platform = { "Jobs", "Farms" } },
			{ candidate = "hale", color = "Teal", platform = { "Jobs", "Jobs", "Safety" } },
			{ candidate = "hale", color = "Teal", platform = { "Jobs", "Farms", "Crime" } },
			"hale",
		}
		for _, input in bad do
			expect((Match.validate(C, match, 1, input))):toBe(false)
		end
		expect((Match.validate(C, match, 3, bad[1]))):toBe(false)
	end)

	it("cannot advance a finished match", function()
		local match = Fixtures.advanceTo(Match.new(C, 1, { "a", "b" }), "Done")
		expect(match.election ~= nil):toBe(true)
		expect(function()
			Match.advance(C, match, {})
		end):toThrow("cannot advance")
	end)
end)

describe("color clashes (playtest 1, bug 6)", function()
	local View = require("@sim/View")
	local function pick(color: string): any
		return { candidate = "okafor", color = color, platform = { "Jobs", "Farms", "Safety" } }
	end

	it("records the color each player asked for and shows it only to them", function()
		local match = Match.advance(C, Match.new(C, 4, { "a", "b" }), { pick("Cobalt"), pick("Cobalt") })
		local kept = if match.players[1].color == "Cobalt" then 1 else 2
		local moved = 3 - kept
		expect(match.players[kept].color):toBe("Cobalt")
		expect(match.players[moved].color):toBe("Crimson") -- the first free color
		for p = 1, 2 do
			expect(match.players[p].pickedColor):toBe("Cobalt")
			local view = View.build(C, match, p)
			expect(view.players[p].pickedColor):toBe("Cobalt")
			expect(view.players[3 - p].pickedColor):toBe(nil)
		end
	end)

	it("hides picks during Select and leaves a clash-free pick alone", function()
		local fresh = Match.new(C, 4, { "a", "b" })
		expect(View.build(C, fresh, 1).players[1].pickedColor):toBe(nil)
		local match = Match.advance(C, fresh, { pick("Teal"), pick("Amber") })
		expect(match.players[1].color):toBe("Teal")
		expect(match.players[2].color):toBe("Amber")
		expect(match.players[1].pickedColor):toBe("Teal")
	end)

	it("settles a clash by the seed, not by seat (D-001)", function()
		local wins = { 0, 0 }
		for seed = 1, 400 do
			local match = Match.advance(C, Match.new(C, seed, { "a", "b" }), { pick("Teal"), pick("Teal") })
			local p = if match.players[1].color == "Teal" then 1 else 2
			wins[p] += 1
		end
		-- 400 fair coin flips land within 160..240 with overwhelming probability.
		expect(wins[1] > 160 and wins[2] > 160):toBe(true)
	end)
end)
