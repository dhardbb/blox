--!strict
-- The weekly event deck (D-027): the seeded draw, each kind's effect, the
-- EVENT_CAP, the Choice payoff matrix and its validation, the lobby toggle, and
-- whole-match determinism with events on.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Play = require("@testlib/Play")
local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local Events = require("@sim/Events")
local Issues = require("@sim/Issues")
local Match = require("@sim/Match")
local Plan = require("@sim/Plan")
local Resolve = require("@sim/Resolve")
local Rng = require("@sim/Rng")
local State = require("@sim/State")
local StateData = require("@sim/StateData")
local Support = require("@sim/Support")
local Types = require("@shared/Types")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local OFF = Config.with(C, { EVENTS_ENABLED = false })
-- No drift, so a week's support changes are exactly its direct effects.
local NODRIFT = Config.with(C, { DRIFT_RATE = 0 })
local SAME = { { "Jobs", "Health", "Schools" }, { "Jobs", "Health", "Schools" } }
local EPS = 1e-9

-- Week 2 with both players identical, in Ohio, every state reset to 35/35/30 with
-- no lean, momentum, ownership or rubber band, and the given event (nil = none).
local function clean(id: string?): State.MatchState
	local match = Fixtures.advanceTo(
		Fixtures.campaign({ seed = 21, candidates = { "hale", "hale" }, platforms = SAME }),
		"Plan",
		2
	)
	for _, s in match.states do
		s.support = { 35, 35 }
		s.undecided = 30
		s.lean, s.leanTo = 0, nil
		s.battleground, s.owner, s.isHome = false, nil, false
		s.momentum = { 0, 0 }
		s.pool = s.capacity
		s.poll = { support = { 35, 35 }, undecided = 30 }
	end
	for _, player in match.players do
		player.location = "OH"
		player.cash = 50
		player.underdogTier = 0
		player.frontrunner = false
	end
	match.eventDeck[2] = id
	return match
end

-- The same match with this week's event removed.
local function without(match: State.MatchState): State.MatchState
	local copy = State.clone(match)
	copy.eventDeck[copy.week] = nil
	return copy
end

local function normalize(config: Config.Config, match: State.MatchState, inputs: { any }): { Plan.Plan }
	local plans = {}
	for p = 1, 2 do
		local ok, reason, plan = Plan.validate(config, match, p, inputs[p] or { actions = {} })
		assert(ok and plan, `plan {p} rejected: {reason}`)
		plans[p] = plan
	end
	return plans
end

-- Resolves the week on a copy with no drift and returns the copy.
local function resolve(match: State.MatchState, inputs: { any }, config: Config.Config?): State.MatchState
	local cfg = config or NODRIFT
	local copy = State.clone(match)
	Resolve.week(cfg, copy, normalize(cfg, copy, inputs))
	return copy
end

-- Support player p gained in state `id` this week.
local function gained(before: State.MatchState, after: State.MatchState, id: string, p: number): number
	return State.get(after, id).support[p] - State.get(before, id).support[p]
end

local function rallies(id: string, issue: string, count: number): { any }
	local actions = {}
	for k = 1, count do
		actions[k] = { kind = "Rally", state = id, issue = issue }
	end
	return actions
end

-- A seed whose dealt deck holds an event of `kind`, and the week it falls in.
local function seedWith(kind: Types.EventKind): (number, number)
	for seed = 1, 500 do
		local deck = Events.draw(C, Rng.new(seed))
		for week, id in deck do
			if Events.byId[id].kind == kind then
				return seed, week
			end
		end
	end
	error(`no seed deals a {kind} event`)
end

describe("Events: the deck", function()
	it("holds about twenty generic events of all four kinds", function()
		expect(#Events.deck >= 18 and #Events.deck <= 24):toBe(true)
		local count: { [string]: number } = {}
		for _, event in Events.deck do
			count[event.kind] = (count[event.kind] or 0) + 1
			expect(#event.name > 0 and #event.text > 0):toBe(true)
			expect(Events.byId[event.id]):toBe(event)
			if event.kind == "Spotlight" then
				expect(Issues.isIssue(event.issue :: string)):toBe(true)
			elseif event.kind == "Regional" then
				expect(table.find(Issues.regions, event.region :: Types.Region) ~= nil):toBe(true)
			end
		end
		for _, kind in { "Spotlight", "Regional", "Windfall", "Choice" } do
			expect((count[kind] or 0) >= 3):toBe(true)
		end
		-- Every issue gets its own spotlight, so no platform is favored by the deck.
		expect(count.Spotlight):toBe(#Issues.list)
	end)

	it("the draw is deterministic by seed and comes from its own fork", function()
		expect(Events.draw(C, Rng.new(5))):toEqual(Events.draw(C, Rng.new(5)))
		expect(Match.new(C, 5, { "a", "b" }).eventDeck):toEqual(Match.new(C, 5, { "a", "b" }).eventDeck)
		local differs = false
		for seed = 2, 6 do
			local a, b = Events.draw(C, Rng.new(seed)), Events.draw(C, Rng.new(1))
			for week = 1, C.WEEKS do
				if a[week] ~= b[week] then
					differs = true
				end
			end
		end
		expect(differs):toBe(true)
		-- Turning events off changes nothing else that the seed decides.
		local on, off = Match.new(C, 7, { "a", "b" }), Match.new(OFF, 7, { "a", "b" })
		expect(off.priorityA):toBe(on.priorityA)
		expect(off.debateTopics):toEqual(on.debateTopics)
		expect(off.states):toEqual(on.states)
	end)

	it("deals one event to each of weeks 2-11, none to weeks 1 and 12, no repeats", function()
		for seed = 1, 200 do
			local deck = Match.new(C, seed, { "a", "b" }).eventDeck
			expect(deck[1]):toBe(nil)
			expect(deck[C.WEEKS]):toBe(nil)
			local seen: { [string]: boolean } = {}
			local weeks = 0
			for week, id in deck do
				weeks += 1
				expect(week >= 2 and week <= C.WEEKS - 1):toBe(true)
				expect(Events.byId[id] ~= nil):toBe(true)
				expect(seen[id]):toBe(nil)
				seen[id] = true
			end
			expect(weeks):toBe(10)
		end
	end)

	it("every event is dealt about equally often", function()
		local count: { [string]: number } = {}
		local N = 2000
		for seed = 1, N do
			for _, id in Events.draw(C, Rng.new(seed)) do
				count[id] = (count[id] or 0) + 1
			end
		end
		for _, event in Events.deck do
			local share = (count[event.id] or 0) / N -- expected 10/20 = 0.5
			expect(share > 0.44 and share < 0.56):toBe(true)
		end
	end)

	it("only the current week's event is public, during its Debate and Plan", function()
		local match = Match.new(C, 3, { "a", "b" })
		while match.phase ~= "Done" do
			local view = View.build(C, match, 1)
			local id = match.eventDeck[match.week]
			if (match.phase == "Plan" or match.phase == "Debate") and id then
				expect(view.event and view.event.id):toBe(id)
				expect(view.event and view.event.week):toBe(match.week)
			else
				expect(view.event):toBe(nil)
			end
			match = Match.advance(C, match, {})
		end
		expect(#match.eventLog):toBe(10)
	end)
end)

describe("Events: effects", function()
	it(
		"Spotlight: rallies and positive media on the issue x1.3, attacks and other issues untouched",
		function()
			local match = clean("expo") -- Technology
			local plain = without(match)
			-- Technology in Ohio for this platform is x0.8: 2.4 base, 0.72 extra, under the cap.
			local rally = { { actions = rallies("OH", "Technology", 1) } }
			local g, g0 =
				gained(match, resolve(match, rally), "OH", 1), gained(plain, resolve(plain, rally), "OH", 1)
			expect(g):toBeCloseTo(g0 * C.EVENT_SPOTLIGHT_MULT, EPS)
			local media = { { actions = { { kind = "Media", state = "OH", issue = "Technology" } } } }
			g, g0 =
				gained(match, resolve(match, media), "OH", 1), gained(plain, resolve(plain, media), "OH", 1)
			expect(g):toBeCloseTo(g0 * C.EVENT_SPOTLIGHT_MULT, EPS)
			local other = { { actions = rallies("OH", "Jobs", 1) } }
			expect(gained(match, resolve(match, other), "OH", 1)):toBeCloseTo(
				gained(plain, resolve(plain, other), "OH", 1),
				EPS
			)
			local attack = { { actions = { { kind = "Attack", state = "OH", issue = "Technology" } } } }
			expect(gained(match, resolve(match, attack), "OH", 2)):toBeCloseTo(
				gained(plain, resolve(plain, attack), "OH", 2),
				EPS
			)
		end
	)

	it("Regional: rallies in the region x1.5; media and other regions untouched", function()
		local match = clean("lakes") -- Great Lakes; Ohio is in it, Pennsylvania is not
		expect(StateData.byId.OH.region):toBe("GreatLakes")
		expect(StateData.byId.PA.region ~= "GreatLakes"):toBe(true)
		local plain = without(match)
		local rally = { { actions = rallies("OH", "Technology", 1) } }
		local g, g0 =
			gained(match, resolve(match, rally), "OH", 1), gained(plain, resolve(plain, rally), "OH", 1)
		expect(g):toBeCloseTo(g0 * C.EVENT_REGIONAL_MULT, EPS)
		local outside = { { actions = rallies("PA", "Technology", 1) } }
		expect(gained(match, resolve(match, outside), "PA", 1)):toBeCloseTo(
			gained(plain, resolve(plain, outside), "PA", 1),
			EPS
		)
		local media = { { actions = { { kind = "Media", state = "OH", issue = "Technology" } } } }
		expect(gained(match, resolve(match, media), "OH", 1)):toBeCloseTo(
			gained(plain, resolve(plain, media), "OH", 1),
			EPS
		)
	end)

	it("Windfall: fundraisers x1.5 only where the fundraiser trails in the public poll", function()
		local match = clean("donors")
		State.get(match, "OH").poll = { support = { 30, 40 }, undecided = 30 } -- player 1 trails here
		State.get(match, "PA").poll = { support = { 40, 30 }, undecided = 30 } -- and leads here
		local plain = without(match)
		local function raised(m: State.MatchState, inputs: { any }, p: number): number
			return resolve(m, inputs).players[p].raised
		end
		local home = { { actions = { { kind = "Fundraise", state = "OH" } } } }
		local r, r0 = raised(match, home, 1), raised(plain, home, 1)
		expect(r):toBeCloseTo(r0 + math.min(r0 * (C.EVENT_WINDFALL_MULT - 1), C.EVENT_CAP), EPS)
		-- The bonus does not drain the pool.
		expect(State.get(resolve(match, home), "OH").pool):toBeCloseTo(
			State.get(resolve(plain, home), "OH").pool,
			EPS
		)
		-- Player 2 leads in Ohio: nothing extra.
		local theirs = { nil :: any, { actions = { { kind = "Fundraise", state = "OH" } } } }
		expect(raised(match, theirs, 2)):toBeCloseTo(raised(plain, theirs, 2), EPS)
		-- Leading or tied is not trailing.
		local lead = { { actions = { { kind = "Fundraise", state = "PA" } } } }
		expect(raised(match, lead, 1)):toBeCloseTo(raised(plain, lead, 1), EPS)
		expect(Events.trails({ support = { 35, 35 }, undecided = 30 }, 1)):toBe(false)
		expect(Events.trails(nil, 1)):toBe(false)
	end)

	it("an event adds at most EVENT_CAP to one player in one state per week", function()
		-- Three spotlight rallies on Jobs in Ohio (x1.5 issue): 4.5 base each, 1.35 extra
		-- each uncapped (4.05), so the cap binds: exactly 2 extra in total.
		local match = clean("factory") -- Jobs
		local plain = without(match)
		local inputs = { { actions = rallies("OH", "Jobs", 3) } }
		local extra = gained(match, resolve(match, inputs), "OH", 1)
			- gained(plain, resolve(plain, inputs), "OH", 1)
		expect(extra):toBeCloseTo(C.EVENT_CAP, EPS)
		-- Rallies and media share the one allowance, per player and state.
		local ledger: Events.Ledger = {}
		expect(Events.grant(C, ledger, 1, 1, 1.35)):toBeCloseTo(1.35, EPS)
		expect(Events.grant(C, ledger, 1, 1, 0.72)):toBeCloseTo(0.65, EPS)
		expect(Events.grant(C, ledger, 1, 1, 0.5)):toBe(0)
		expect(Events.grant(C, ledger, 1, 2, 0.5)):toBe(0.5) -- the other player's own allowance
		expect(Events.grant(C, ledger, 2, 1, 0.5)):toBe(0.5) -- and another state's
		local media = { kind = "Media", state = "OH", issue = "Jobs" }
		inputs = { { actions = { rallies("OH", "Jobs", 1)[1], media, media, media } } }
		extra = gained(match, resolve(match, inputs), "OH", 1)
			- gained(plain, resolve(plain, inputs), "OH", 1)
		expect(extra > 1.5 and extra <= C.EVENT_CAP + EPS):toBe(true)
		-- A Windfall is capped in money the same way. At the default x1.2 one state's
		-- pool cannot reach the cap, so a stronger variant shows it binding.
		local strong = Config.with(NODRIFT, { EVENT_WINDFALL_MULT = 1.5 })
		match = clean("matching")
		State.get(match, "OH").poll = { support = { 30, 40 }, undecided = 30 }
		plain = without(match)
		inputs =
			{ { actions = { { kind = "Fundraise", state = "OH" }, { kind = "Fundraise", state = "OH" } } } }
		local r = resolve(match, inputs, strong).players[1].raised
		local r0 = resolve(plain, inputs, strong).players[1].raised
		expect(r0 * (strong.EVENT_WINDFALL_MULT - 1) > C.EVENT_CAP):toBe(true)
		expect(r - r0):toBeCloseTo(C.EVENT_CAP, EPS)
	end)

	it("the cap holds for bot plans in every boosting event, every state and player", function()
		for _, id in { "factory", "expo", "lakes", "coast", "regatta", "donors", "smalldollar" } do
			for seed = 1, 6 do
				local match = Fixtures.advanceTo(Fixtures.campaign({ seed = seed }), "Plan", 2 + seed)
				match.eventDeck[match.week] = id
				local plain = without(match)
				local inputs = {}
				for p = 1, 2 do
					inputs[p] = Bot.plan(C, View.build(C, match, p), Rng.new(seed * 10 + p))
				end
				local a, b = resolve(match, inputs), resolve(plain, inputs)
				for i, s in a.states do
					for p = 1, 2 do
						local diff = s.support[p] - b.states[i].support[p]
						expect(math.abs(diff) <= C.EVENT_CAP + EPS):toBe(true)
					end
				end
				for p = 1, 2 do
					local states: { [string]: boolean } = {}
					local count = 0
					for _, action in normalize(NODRIFT, match, inputs)[p].actions do
						if action.kind == "Fundraise" and not states[action.state :: string] then
							states[action.state :: string] = true
							count += 1
						end
					end
					expect(a.players[p].raised - b.players[p].raised <= count * C.EVENT_CAP + EPS):toBe(true)
				end
			end
		end
	end)
end)

describe("Events: Choice", function()
	it("the payoff matrix is the Config table, small, and symmetric between seats", function()
		local CH = Events.CHOICES
		for _, x in CH do
			for _, y in CH do
				local v = Events.payoff(C, x, y)
				expect(math.abs(v) <= C.EVENT_CAP):toBe(true)
				local pair = Events.choicePayoffs(C, { x, y })
				expect(pair[1]):toBe(v)
				expect(pair[2]):toBe(Events.payoff(C, y, x))
				local swapped = Events.choicePayoffs(C, { y, x })
				expect(swapped):toEqual({ pair[2], pair[1] })
			end
		end
		expect(Events.payoff(C, "Attack", "Ignore")):toBe(C.CHOICE_ATTACK_IGNORE)
		expect(Events.payoff(C, "Attack", "Defend")):toBe(C.CHOICE_ATTACK_DEFEND)
		expect(Events.payoff(C, "Defend", "Ignore")):toBe(C.CHOICE_DEFEND_IGNORE)
		expect(Events.payoff(C, "Attack", "Attack")):toBe(C.CHOICE_ATTACK_ATTACK)
		expect(Events.payoff(C, "Ignore", "Ignore")):toBe(0)
		-- Payoffs are clamped to the cap even if a variant's matrix is not.
		local wild = Config.with(C, { CHOICE_ATTACK_IGNORE = 5 })
		expect(Events.choicePayoffs(wild, { "Attack", "Ignore" })[1]):toBe(C.EVENT_CAP)
	end)

	it("resolves both answers together as one national shift and reveals them", function()
		local match = clean("clip")
		local after =
			resolve(match, { { actions = {}, choice = "Attack" }, { actions = {}, choice = "Ignore" } })
		local expected = State.clone(match)
		local national = { C.CHOICE_ATTACK_IGNORE, C.CHOICE_IGNORE_ATTACK }
		Support.national(C, expected.states, national)
		for i, s in after.states do
			expect(s.support[1]):toBeCloseTo(expected.states[i].support[1], EPS)
			expect(s.support[2]):toBeCloseTo(expected.states[i].support[2], EPS)
			-- No state moves by more than the cap.
			expect(math.abs(s.support[1] - match.states[i].support[1]) <= C.EVENT_CAP):toBe(true)
		end
		local result = after.eventLog[#after.eventLog]
		expect(result.week):toBe(2)
		expect(result.id):toBe("clip")
		expect(result.choices):toEqual({ "Attack", "Ignore" })
		expect(result.national):toEqual(national)
		expect((after.players[1].card :: State.WeekCard).choice):toBe("Attack")
		expect((after.players[2].card :: State.WeekCard).choice):toBe("Ignore")
		local view = View.build(C, after, 2)
		expect(view.eventLog[#view.eventLog].choices):toEqual({ "Attack", "Ignore" })
	end)

	it("swapping seats mirrors the outcome exactly", function()
		local match = clean("rumor") -- a symmetric board
		for _, pair in { { "Attack", "Ignore" }, { "Attack", "Defend" }, { "Defend", "Ignore" } } do
			local a =
				resolve(match, { { actions = {}, choice = pair[1] }, { actions = {}, choice = pair[2] } })
			local b =
				resolve(match, { { actions = {}, choice = pair[2] }, { actions = {}, choice = pair[1] } })
			for i, s in a.states do
				expect(s.support[1]):toBeCloseTo(b.states[i].support[2], EPS)
				expect(s.support[2]):toBeCloseTo(b.states[i].support[1], EPS)
				expect(s.undecided):toBeCloseTo(b.states[i].undecided, EPS)
			end
			local ra, rb = a.eventLog[#a.eventLog], b.eventLog[#b.eventLog]
			local na, nb = ra.national :: { number }, rb.national :: { number }
			expect(na[1]):toBe(nb[2])
			expect(na[2]):toBe(nb[1])
		end
	end)

	it("a missing answer defaults to Ignore", function()
		local match = clean("memo")
		local ok, _, plan = Plan.validate(C, match, 1, { actions = {} })
		expect(ok):toBe(true)
		expect((plan :: Plan.Plan).choice):toBe("Ignore")
		expect(Plan.empty(C, match, 2).choice):toBe("Ignore")
		local after = Match.advance(C, match, {})
		expect(after.eventLog[#after.eventLog].choices):toEqual({ "Ignore", "Ignore" })
		expect(after.eventLog[#after.eventLog].national):toEqual({ 0, 0 })
	end)

	it("rejects an invalid answer with a reason code, whole", function()
		local match = clean("endorse")
		for _, bad in { "Surrender", "attack", "", 3, true, { "Attack" } } do
			local ok, reason, plan =
				Plan.validate(C, match, 1, { actions = rallies("OH", "Jobs", 1), choice = bad })
			expect(ok):toBe(false)
			expect(reason):toBe(Plan.Reason.BadChoice)
			expect(plan):toBe(nil)
		end
		local ok, _, plan = Plan.validate(C, match, 1, { actions = {}, choice = "Defend" })
		expect(ok):toBe(true)
		expect((plan :: Plan.Plan).choice):toBe("Defend")
	end)

	it("an answer is only allowed in a Choice week", function()
		for _, id in { "expo", "lakes", "donors" } do
			local match = clean(id)
			local ok, reason = Plan.validate(C, match, 1, { actions = {}, choice = "Attack" })
			expect(ok):toBe(false)
			expect(reason):toBe(Plan.Reason.UnexpectedChoice)
			expect(Plan.empty(C, match, 1).choice):toBe(nil)
		end
		local ok, reason = Plan.validate(C, clean(nil), 1, { actions = {}, choice = "Ignore" })
		expect(ok):toBe(false)
		expect(reason):toBe(Plan.Reason.UnexpectedChoice)
	end)
end)

describe("Events: off and on", function()
	it("events disabled: no deck, no event, no effects, no answers", function()
		local match = Match.new(OFF, 11, { "a", "b" })
		expect(next(match.eventDeck)):toBe(nil)
		local record = Play.match(OFF, 11, { "okafor", "calloway" })
		expect(#record.match.eventLog):toBe(0)
		expect(record.invalid):toBe(0)
		match = Fixtures.advanceTo(Fixtures.campaign({ seed = 11 }), "Plan", 3)
		match.eventDeck = {}
		expect(View.build(OFF, match, 1).event):toBe(nil)
		local ok, reason = Plan.validate(OFF, match, 1, { actions = {}, choice = "Attack" })
		expect(ok):toBe(false)
		expect(reason):toBe(Plan.Reason.UnexpectedChoice)
	end)

	it("a whole match with events is deterministic, Choice weeks included", function()
		local seed = seedWith("Choice")
		local a = Play.match(C, seed, { "reyes", "strand" })
		local b = Play.match(C, seed, { "reyes", "strand" })
		expect(a.invalid):toBe(0)
		expect(#a.match.eventLog):toBe(10)
		expect(a.match.eventLog):toEqual(b.match.eventLog)
		expect(a.match.states):toEqual(b.match.states)
		expect(a.match.election):toEqual(b.match.election)
		local answered = false
		for _, result in a.match.eventLog do
			if result.choices then
				answered = true
				expect(#result.choices):toBe(2)
			end
		end
		expect(answered):toBe(true)
		Fixtures.checkSupport(a.match)
	end)
end)
