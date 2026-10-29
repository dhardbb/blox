--!strict
-- The short tutorial (D-080): Config.tutorial's schedule (4 weeks, one Choice
-- stance in week 2, one live debate in week 3, EV_TO_WIN unchanged), that the
-- normal 12-week match is untouched, determinism from the seed, and whole
-- bot-vs-bot tutorials against the Easy bot that end after week 4.

local Test = require("@testlib/Test")
local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local Events = require("@sim/Events")
local Match = require("@sim/Match")
local Rng = require("@sim/Rng")
local Session = require("@net/Session")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local T = Config.tutorial(C)

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

type Run = {
	match: any,
	phases: { string }, -- "week:phase" each time the phase changed
}

-- Plays one bot-vs-bot match on `config`: the standard bot (a new player's
-- stand-in) against the Easy bot.
local function play(config: Config.Config, seed: number): Run
	local match = Match.new(config, seed, { "you", "bot" })
	local rngs = { Rng.new(seed * 2 + 1), Rng.new(seed * 2 + 2) }
	local styles: { Bot.Style } = { "Balanced", Bot.styleFor("Easy") }
	local candidates = { "okafor", "calloway" }
	local phases: { string } = {}
	local last = ""
	for _ = 1, 200 do
		local tag = `{match.week}:{match.phase}`
		if tag ~= last then
			table.insert(phases, tag)
			last = tag
		end
		if match.phase == "Done" then
			return { match = match, phases = phases }
		end
		local inputs = {}
		if Match.wantsInput(match) then
			for p = 1, 2 do
				local input = Bot.act(config, View.build(config, match, p), rngs[p], candidates[p], styles[p])
				check(Match.validate(config, match, p, input), `a bot input was rejected in {tag}`)
				inputs[p] = input
			end
		end
		match = Match.advance(config, match, inputs)
	end
	error("the match did not end")
end

describe("Tutorial schedule (D-080)", function()
	it("is 4 weeks with one stance week and one debate week, still a race to 270", function()
		expect(T.WEEKS):toBe(C.TUTORIAL_WEEKS)
		expect(T.WEEKS):toBe(4)
		expect(T.DEBATE_WEEKS):toEqual({ 3 })
		expect(T.EVENT_FIRST_WEEK):toBe(C.TUTORIAL_CHOICE_WEEK)
		expect(T.EVENT_LAST_WEEK):toBe(C.TUTORIAL_CHOICE_WEEK)
		expect(T.TUTORIAL_CHOICE_WEEK):toBe(2)
		expect(T.EVENT_CHOICE_ONLY):toBe(true)
		expect(T.CLOSING_FROM_WEEK):toBe(C.TUTORIAL_CLOSING_FROM_WEEK)
		expect(T.START_CASH):toBe(C.TUTORIAL_START_CASH)
		expect(T.EV_TO_WIN):toBe(270)
		-- The stance, the debate and the closing push all fall inside the campaign,
		-- the stance before the debate, and each in a week of its own.
		check(
			T.TUTORIAL_CHOICE_WEEK >= 2 and T.TUTORIAL_CHOICE_WEEK < T.DEBATE_WEEKS[1],
			"stance before debate"
		)
		check(T.DEBATE_WEEKS[1] < T.WEEKS, "the debate leaves a week to act on it")
		check(T.CLOSING_FROM_WEEK <= T.WEEKS, "the closing push is inside the campaign")
		expect(#T.DEBATE_WEEKS):toBe(1)
		expect(T.DEBATE_TOPICS):toBe(3) -- one live debate of three rounds
	end)

	it("changes only the schedule keys; every other number is the base config's", function()
		local changed = {
			WEEKS = true,
			DEBATE_WEEKS = true,
			EVENT_FIRST_WEEK = true,
			EVENT_LAST_WEEK = true,
			EVENT_CHOICE_ONLY = true,
			CLOSING_FROM_WEEK = true,
			START_CASH = true,
		}
		for key, value in C :: any do
			if not changed[key] then
				check((T :: any)[key] == value, `Config.tutorial changed {key}`)
			end
		end
		-- And it sits on whatever base it is given (a lobby's events-off config, a harness variant).
		local variant = Config.tutorial(Config.with(C, { TUTORIAL_WEEKS = 5, RALLY_SUPPORT = 4 }))
		expect(variant.WEEKS):toBe(5)
		expect(variant.RALLY_SUPPORT):toBe(4)
	end)

	it("deals exactly one event, a Choice, into the stance week, on every seed", function()
		for seed = 1, 60 do
			local match = Match.new(T, seed, { "a", "b" })
			local weeks = 0
			for week, id in match.eventDeck do
				weeks += 1
				expect(week):toBe(T.TUTORIAL_CHOICE_WEEK)
				expect(Events.byId[id].kind):toBe("Choice")
			end
			expect(weeks):toBe(1)
			-- Debate topics for its one debate week only.
			local debateWeeks = 0
			for week, topics in match.debateTopics do
				debateWeeks += 1
				expect(week):toBe(3)
				expect(#topics):toBe(T.DEBATE_TOPICS)
			end
			expect(debateWeeks):toBe(1)
		end
	end)

	it("draws its Choice event from the seed", function()
		local seen: { [string]: boolean } = {}
		local count = 0
		for seed = 1, 40 do
			local id = Match.new(T, seed, { "a", "b" }).eventDeck[2]
			if not seen[id] then
				seen[id] = true
				count += 1
			end
			expect(Match.new(T, seed, { "a", "b" }).eventDeck[2]):toBe(id)
		end
		check(count >= 3, `only {count} different Choice events over 40 seeds`)
	end)
end)

describe("Normal schedule unchanged (D-080)", function()
	it("keeps 12 weeks, debates in weeks 4 and 9, events weeks 2 to 11 of every kind", function()
		expect(C.WEEKS):toBe(12)
		expect(C.DEBATE_WEEKS):toEqual({ 4, 9 })
		expect(C.EVENT_FIRST_WEEK):toBe(2)
		expect(C.EVENT_LAST_WEEK):toBe(11)
		expect(C.EVENT_CHOICE_ONLY):toBe(false)
		expect(C.CLOSING_FROM_WEEK):toBe(10)
		expect(C.START_CASH):toBe(8)
		local kinds: { [string]: boolean } = {}
		for seed = 1, 20 do
			local match = Match.new(C, seed, { "a", "b" })
			for week = 2, 11 do
				local id = match.eventDeck[week]
				check(id ~= nil, `seed {seed} has no event in week {week}`)
				kinds[Events.byId[id].kind] = true
			end
			expect(match.eventDeck[1]):toBe(nil)
			expect(match.eventDeck[12]):toBe(nil)
		end
		for _, kind in { "Spotlight", "Regional", "Windfall", "Choice" } do
			check(kinds[kind] == true, `no {kind} event dealt in a normal match`)
		end
	end)

	it("plays a seeded normal match exactly as before the tutorial existed", function()
		-- Pinned on the commit before D-080 (Balanced Pennywhistle vs Easy Quibble, seed
		-- 4242): the deck, every week's projected votes and the result. D-057's
		-- Easy bot plays on as the Hazy profile (D-087). Weeks 10-12 re-pinned
		-- for D-096 (the underdog tier now ends on the latest polls), which moved
		-- the trailer's boost from week 9 on. Weeks 3 on re-pinned for D-099 (a
		-- stance resolves before the plan, so both bots plan on the polls it made).
		local seed = 4242
		local match = Match.new(C, seed, { "a", "b" })
		local rngs = { Rng.new(seed + 1), Rng.new(seed + 2) }
		local candidates = { "okafor", "hale" }
		local styles: { Bot.Style } = { "Balanced", "Hazy" }
		while match.phase ~= "Done" do
			local inputs = {}
			if Match.wantsInput(match) then
				for p = 1, 2 do
					inputs[p] = Bot.act(C, View.build(C, match, p), rngs[p], candidates[p], styles[p])
				end
			end
			match = Match.advance(C, match, inputs)
		end
		local deck = {}
		for week = 1, 12 do
			table.insert(deck, match.eventDeck[week] or "-")
		end
		expect(table.concat(deck, ",")):toBe(
			"-,plant,safety,matching,expo,datacenter,river,lakes,smalldollar,coast,rodeo,-"
		)
		local history = {}
		for _, entry in match.pollHistory do
			table.insert(history, `{entry.ev[1]}/{entry.ev[2]}`)
		end
		expect(table.concat(history, " ")):toBe(
			"280/185 317/189 323/209 271/243 254/278 275/250 311/217 310/222 342/196 337/193 349/186 345/189 323/201"
		)
		local election = match.election :: any
		expect(election.ev[1]):toBe(333)
		expect(election.ev[2]):toBe(205)
	end)
end)

describe("Tutorial match (D-080)", function()
	it("a bot-vs-bot tutorial runs draft, 4 weeks, the stance, the debate and election night", function()
		for seed = 1, 12 do
			local run = play(T, seed)
			local phases = table.concat(run.phases, " ")
			expect(phases):toBe(
				"0:Select 0:MapReveal 0:Draft 1:Plan 2:Decision 2:Plan 3:Debate 3:Plan 4:Plan 5:Election 5:Done"
			)
			local election = run.match.election :: any
			check(election ~= nil and election.ev[1] + election.ev[2] <= 538, "no election")
			-- One debate result, three rounds; one stance week in the log.
			expect(#run.match.debates):toBe(1)
			local stances = 0
			for _, entry in run.match.eventLog do
				if entry.choices ~= nil then
					stances += 1
					expect(entry.week):toBe(2)
				end
			end
			expect(stances):toBe(1)
			-- The weekly projection: after the draft and after each of the 4 weeks.
			expect(#run.match.pollHistory):toBe(T.WEEKS + 1)
		end
	end)

	it("is deterministic: same seed and inputs, same match; another seed, another match", function()
		local a = play(T, 21).match
		local b = play(T, 21).match
		local c = play(T, 22).match
		local function digest(match: any): string
			local parts = { tostring(match.eventDeck[2]) }
			for _, entry in match.pollHistory do
				table.insert(parts, `{entry.ev[1]}/{entry.ev[2]}`)
			end
			for _, s in match.states do
				table.insert(parts, string.format("%s %.6f %.6f", s.id, s.support[1], s.support[2]))
			end
			table.insert(parts, `{match.election.ev[1]}-{match.election.ev[2]}`)
			return table.concat(parts, "|")
		end
		expect(digest(a)):toBe(digest(b))
		check(digest(a) ~= digest(c), "two seeds played the same tutorial")
	end)

	it(
		"the server plays a tutorial session on the tutorial's config, a practice match on the normal one",
		function()
			local function session(tutorial: boolean?): Session.Session
				return Session.new(C, "t", 5, {
					{ id = "100", kind = "Human" },
					{ id = "bot", kind = "Bot", candidate = "hale", difficulty = "Easy" },
				}, 0, { tutorial = tutorial })
			end
			expect(session(true).config.WEEKS):toBe(4)
			expect(session(true).match.eventDeck[2] ~= nil):toBe(true)
			expect(session().config.WEEKS):toBe(12)
			expect(session().config):toBe(C)
		end
	)
end)
