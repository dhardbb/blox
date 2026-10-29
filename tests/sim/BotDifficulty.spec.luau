--!strict
-- Practice bot difficulty (D-057, D-087, D-095): the names and the Easy default, the
-- profile each level plays (Extreme is the Expert), valid and
-- deterministic play at every level and profile, the once-a-match misjudgment,
-- and fair play: every level decides from its own View, so hidden state never
-- changes a decision.

local Test = require("@testlib/Test")
local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local Match = require("@sim/Match")
local Play = require("@testlib/Play")
local Rng = require("@sim/Rng")
local State = require("@sim/State")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

-- Every profile a practice bot can play: the four levels' and the Daily Race's.
local PROFILES: { Bot.Style } =
	{ "Rookie", "Casual", "Sharp", "Expert", "Hazy", "Balanced", "Foresight", "Strategist" }

-- Plays `seed` bot against bot up to week `week`'s Plan phase.
local function toPlan(seed: number, week: number): State.MatchState
	local match = Match.new(C, seed, { "p1", "p2" })
	local rngs = { Rng.new(seed), Rng.new(seed + 1) }
	while match.phase ~= "Plan" or match.week < week do
		local inputs = {}
		if Match.wantsInput(match) then
			for p = 1, 2 do
				inputs[p] = Bot.act(C, View.build(C, match, p), rngs[p], if p == 1 then "hale" else "reyes")
			end
		end
		match = Match.advance(C, match, inputs)
	end
	return match
end

describe("Bot difficulty (D-057, D-087)", function()
	it("reads a difficulty from untrusted input, Easy by default", function()
		for _, level in Bot.DIFFICULTIES do
			expect(Bot.difficulty(level)):toBe(level)
		end
		for _, bad in { nil, "", "hard", "EXTREME", "Impossible", 3, true, {} } :: { any } do
			expect(Bot.difficulty(bad)):toBe("Easy")
		end
		expect(Bot.DEFAULT_DIFFICULTY):toBe("Easy")
	end)

	it("maps the ladder: Easy Rookie, Medium Casual, Hard Sharp, Extreme Expert (D-095)", function()
		expect(Bot.styleFor("Easy")):toBe("Rookie")
		expect(Bot.styleFor("Medium")):toBe("Casual")
		expect(Bot.styleFor("Hard")):toBe("Sharp")
		expect(Bot.styleFor("Extreme")):toBe("Expert")
		expect(Bot.styleFor(nil)):toBe("Rookie")
	end)

	it("levels differ only in how they misjudge: Config's noise, once-a-match flag and slips", function()
		expect(Bot.misjudgment(C, "Rookie")):toEqual({
			noise = C.BOT_ROOKIE_NOISE,
			once = C.BOT_ROOKIE_ONCE,
			slip = C.BOT_ROOKIE_SLIP,
		})
		expect(Bot.misjudgment(C, "Casual")):toEqual({
			noise = C.BOT_CASUAL_NOISE,
			once = C.BOT_CASUAL_ONCE,
			slip = C.BOT_CASUAL_SLIP,
		})
		expect(Bot.misjudgment(C, "Hazy")):toEqual({
			noise = C.BOT_HAZY_NOISE,
			once = C.BOT_HAZY_ONCE,
			slip = C.BOT_HAZY_SLIP,
		})
		expect(Bot.misjudgment(C, "Sharp")):toEqual({
			noise = C.BOT_SHARP_NOISE,
			once = C.BOT_SHARP_ONCE,
			slip = C.BOT_SHARP_SLIP,
		})
		for _, style in { "Expert", "Balanced", "Foresight", "Strategist", nil } :: { any } do
			expect(Bot.misjudgment(C, style)):toBe(nil)
		end
		-- Each step up misjudges less, or slips less.
		expect(C.BOT_ROOKIE_NOISE > C.BOT_CASUAL_NOISE):toBe(true)
		expect(C.BOT_CASUAL_NOISE > C.BOT_SHARP_NOISE):toBe(true)
		expect(C.BOT_CASUAL_SLIP > C.BOT_SHARP_SLIP):toBe(true)
		expect(C.BOT_SHARP_ONCE):toBe(false)
	end)

	it("Extreme is the standard bot's judgment with a longer view of the campaign (D-095)", function()
		expect(C.BOT_EXPERT_CAMPAIGN_VARIANCE > Bot.tuning.campaignVariance):toBe(true)
		local match = toPlan(971, 4)
		local view = View.build(C, match, 1)
		-- The same View, the same stream: the Expert plans differently from the
		-- standard bot only because it reads every state as further in play.
		local expert = Bot.plan(C, view, Rng.new(7), "Expert")
		local standard = Bot.plan(C, view, Rng.new(7), "Balanced")
		expect(expert ~= nil and standard ~= nil):toBe(true)
		local saved = Bot.tuning.campaignVariance
		Bot.tuning.campaignVariance = C.BOT_EXPERT_CAMPAIGN_VARIANCE
		local widened = Bot.plan(C, view, Rng.new(7), "Balanced")
		Bot.tuning.campaignVariance = saved
		expect(expert):toEqual(widened)
		-- And the standard bot is untouched by it.
		expect(Bot.plan(C, view, Rng.new(7), "Balanced")):toEqual(standard)
	end)

	it("every level and profile finishes matches with only valid inputs, from either seat", function()
		for k, style in PROFILES do
			local a = Play.match(C, 900 + k, { "okafor", "strand" }, { style, "Balanced" })
			local b = Play.match(C, 910 + k, { "venkat", "hale" }, { "Balanced", style })
			expect(a.invalid):toBe(0)
			expect(b.invalid):toBe(0)
			expect(a.match.phase):toBe("Done")
			expect(b.match.phase):toBe("Done")
		end
	end)

	it("every level and profile is deterministic: same seed and inputs, same moves", function()
		for k, style in PROFILES do
			local styles = { style, style }
			local a = Play.match(C, 920 + k, { "reyes", "begay" }, styles)
			local b = Play.match(C, 920 + k, { "reyes", "begay" }, styles)
			expect(a.match):toEqual(b.match)
		end
	end)

	it("the misjudging levels still raise money and spend it", function()
		for _, style in { "Rookie", "Casual", "Sharp", "Hazy" } :: { Bot.Style } do
			local raised, unspent = 0, 0
			for k = 1, 6 do
				local record = Play.match(C, 930 + k, { "okafor", "hale" }, { style, "Balanced" })
				raised += record.raised[1] / 6
				unspent += record.unspent[1] / 6
			end
			expect(raised > 10):toBe(true)
			expect(unspent < 20):toBe(true)
		end
	end)

	it("Easy and Medium misjudge the same way all match; Hard redraws every plan (D-087, D-095)", function()
		local early = toPlan(961, 2)
		local late = toPlan(961, 10)
		local other = toPlan(962, 2)
		for _, style in { "Rookie", "Casual" } :: { Bot.Style } do
			local a = Bot.misjudgedWeights(C, View.build(C, early, 1), Rng.new(1), style)
			local b = Bot.misjudgedWeights(C, View.build(C, late, 1), Rng.new(2), style)
			expect(a ~= nil):toBe(true)
			expect(b):toEqual(a) -- another week, another plan stream: the same misjudgment
			-- Another match, or the other seat, misjudges differently.
			expect(Bot.misjudgedWeights(C, View.build(C, other, 1), Rng.new(1), style) ~= a):toBe(true)
			local mine = a :: { number }
			local theirs = Bot.misjudgedWeights(C, View.build(C, early, 2), Rng.new(1), style) :: { number }
			local differs = false
			for i, w in mine do
				differs = differs or math.abs(w - theirs[i]) > 1e-9
			end
			expect(differs):toBe(true)
			-- And it does not depend on the plan's stream at all: the same plan.
			local view = View.build(C, late, 1)
			expect(Bot.plan(C, view, Rng.new(5), style)):toEqual(Bot.plan(C, view, Rng.new(6), style))
		end
		for _, style in { "Sharp", "Hazy" } :: { Bot.Style } do
			local a = Bot.misjudgedWeights(C, View.build(C, early, 1), Rng.new(1), style) :: { number }
			local b = Bot.misjudgedWeights(C, View.build(C, early, 1), Rng.new(2), style) :: { number }
			local differs = false
			for i, w in a do
				differs = differs or math.abs(w - b[i]) > 1e-9
			end
			expect(differs):toBe(true)
		end
		expect(Bot.misjudgedWeights(C, View.build(C, early, 1), Rng.new(1), "Balanced")):toBe(nil)
	end)

	-- The same match with every hidden number moved: true support, true undecided,
	-- the opponent's ground game, the fundraising pools, the poll error terms and
	-- the opponent's private polls. None of it is in a View.
	local function disturb(match: State.MatchState, me: number): State.MatchState
		local them = if me == 1 then 2 else 1
		local copy = State.deepCopy(match)
		for _, s in copy.states do
			local shift = math.min(4, s.support[them])
			s.support[me] += shift
			s.support[them] -= shift
			s.gotv[them] = math.min(C.GOTV_MAX_UNITS, s.gotv[them] + 2)
			s.pool *= 0.5
			s.pollError[me] += 1.5
			s.pollError[them] -= 1.5
			s.pollErrorUndecided += 1
		end
		copy.players[them].internalPolls = {
			{ state = "OH", support = { 50, 40 }, undecided = 10, momentum = { 0, 3 }, gotv = { 4, 4 } },
		}
		return copy
	end

	it("every level and profile decides the same when hidden state changes (fair play)", function()
		for k, style in PROFILES do
			local match = Match.new(C, 940 + k, { "p1", "p2" })
			local rngs = { Rng.new(1), Rng.new(2) }
			local candidates = { "calloway", "alvarado" }
			local checked = 0
			while match.phase ~= "Done" do
				local inputs = {}
				if Match.wantsInput(match) then
					local hidden = disturb(match, 1)
					local view = View.build(C, match, 1)
					expect(View.build(C, hidden, 1)):toEqual(view)
					local twin = Rng.clone(rngs[1])
					inputs[1] = Bot.act(C, view, rngs[1], candidates[1], style)
					local again = Bot.act(C, View.build(C, hidden, 1), twin, candidates[1], style)
					expect(again):toEqual(inputs[1])
					checked += 1
					inputs[2] = Bot.act(C, View.build(C, match, 2), rngs[2], candidates[2], "Balanced")
				end
				match = Match.advance(C, match, inputs)
			end
			expect(checked > C.WEEKS):toBe(true)
		end
	end)

	it("a foresight profile only reads its own View: it ignores the opponent's real cash", function()
		-- The opponent's exact cash is hidden; only its bracket shows. Two matches
		-- that differ only in that cash, inside one bracket, get the same plan.
		local match = Match.new(C, 951, { "p1", "p2" })
		local rngs = { Rng.new(3), Rng.new(4) }
		while match.phase ~= "Plan" or match.week < 6 do
			local inputs = {}
			if Match.wantsInput(match) then
				for p = 1, 2 do
					inputs[p] =
						Bot.act(C, View.build(C, match, p), rngs[p], if p == 1 then "hale" else "reyes")
				end
			end
			match = Match.advance(C, match, inputs)
		end
		local richer = State.deepCopy(match)
		local cash = richer.players[2].cash
		local bracket = View.moneyBracket(C, cash)
		local nudged = if bracket == "Low"
			then cash * 0.5
			elseif bracket == "High" then cash + 5
			else C.OPPONENT_MONEY_LOW
		richer.players[2].cash = nudged
		expect(View.moneyBracket(C, nudged)):toBe(bracket)
		for _, style in PROFILES do
			local a = Bot.act(C, View.build(C, match, 1), Rng.new(9), "hale", style)
			local b = Bot.act(C, View.build(C, richer, 1), Rng.new(9), "hale", style)
			expect(b):toEqual(a)
		end
	end)
end)
