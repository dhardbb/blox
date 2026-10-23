--!strict
-- The weekly event deck (D-027, D-039): the seeded draw, each kind's effect, the
-- EVENT_CAP, Choice stances and their validation, the lobby toggle, and
-- whole-match determinism with events on.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Play = require("@testlib/Play")
local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local IssueMap = require("@sim/IssueMap")
local Election = require("@sim/Election")
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
local FLAVOR = IssueMap.flavor -- Fixtures put matches on this fixed map (D-044)
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
	it("holds about two dozen generic events of all four kinds", function()
		expect(#Events.deck >= 18 and #Events.deck <= 26):toBe(true)
		local count: { [string]: number } = {}
		local choiceIssues: { [string]: boolean } = {}
		for _, event in Events.deck do
			count[event.kind] = (count[event.kind] or 0) + 1
			expect(#event.name > 0 and #event.text > 0):toBe(true)
			expect(Events.byId[event.id]):toBe(event)
			if event.kind == "Spotlight" then
				expect(Issues.isIssue(event.issue :: string)):toBe(true)
				expect(event.stances):toBe(nil)
			elseif event.kind == "Regional" then
				expect(table.find(Issues.regions, event.region :: Types.Region) ~= nil):toBe(true)
			elseif event.kind == "Choice" then
				-- A dispute over one issue with the three stance slots, A and B opposed
				-- (each likes what the other dislikes) and C the hedge (D-039).
				expect(Issues.isIssue(event.issue :: string)):toBe(true)
				expect(choiceIssues[event.issue :: string]):toBe(nil)
				choiceIssues[event.issue :: string] = true
				local stances = event.stances :: { Events.Stance }
				expect(#stances):toBe(#Events.CHOICES)
				for k, stance in stances do
					expect(stance.id):toBe(Events.CHOICES[k])
					expect(#stance.name > 0 and #stance.text > 0):toBe(true)
					for _, issue in stance.likes do
						expect(Issues.isIssue(issue)):toBe(true)
						expect(issue ~= event.issue):toBe(true)
						expect(table.find(stance.dislikes, issue)):toBe(nil)
					end
					for _, issue in stance.dislikes do
						expect(Issues.isIssue(issue)):toBe(true)
						expect(issue ~= event.issue):toBe(true)
					end
				end
				expect(stances[1].hedge or stances[2].hedge):toBe(false)
				expect(stances[3].hedge):toBe(true)
				expect(#stances[3].likes + #stances[3].dislikes):toBe(0)
				expect(stances[2].likes):toEqual(stances[1].dislikes)
				expect(stances[2].dislikes):toEqual(stances[1].likes)
				expect(#stances[1].likes > 0 and #stances[1].dislikes > 0):toBe(true)
			end
		end
		for _, kind in { "Spotlight", "Regional", "Windfall", "Choice" } do
			expect((count[kind] or 0) >= 3):toBe(true)
		end
		-- Every issue gets its own spotlight and its own Choice, so no platform is
		-- favored by the deck.
		expect(count.Spotlight):toBe(#Issues.list)
		expect(count.Choice):toBe(#Issues.list)
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
		local expected = 10 / #Events.deck
		for _, event in Events.deck do
			local share = (count[event.id] or 0) / N
			expect(math.abs(share - expected) < 0.06):toBe(true)
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

-- Every Choice event in the deck.
local function choiceEvents(): { Events.Definition }
	local out = {}
	for _, event in Events.deck do
		if event.kind == "Choice" then
			table.insert(out, event)
		end
	end
	return out
end

-- EV of the states whose other top issue is in `issues`, among those with `issue`.
local function campEV(issue: string, issues: { Types.Issue }): number
	local ev = 0
	for _, record in StateData.list do
		if table.find(record.flavor, issue :: Types.Issue) then
			for _, other in record.flavor do
				if other ~= issue and table.find(issues, other) then
					ev += record.ev
				end
			end
		end
	end
	return ev
end

-- The rule written out independently of Events.stanceEffect (D-039, D-041, D-043).
local function expectedStance(
	event: Events.Definition,
	stance: Events.Stance,
	record: Types.StateRecord,
	platform: { Types.Issue },
	base: { string }
): number
	local issue = event.issue :: Types.Issue
	local inBase = table.find(base, record.id) ~= nil
	local points = 0
	if not table.find(record.flavor, issue) then
		-- Spillover: STANCE_SPILL per liked top issue, minus the same per disliked
		-- one; nothing for the hedge; no platform multiplier.
		if not stance.hedge then
			for _, topIssue in record.flavor do
				if table.find(stance.likes, topIssue) then
					points += C.STANCE_SPILL
				elseif table.find(stance.dislikes, topIssue) then
					points -= C.STANCE_SPILL
				end
			end
			if inBase then
				points *= C.STANCE_BASE_MULT
			end
		end
		return math.clamp(points, -C.STANCE_CAP, C.STANCE_CAP)
	end
	if stance.hedge then
		points = if inBase then -C.STANCE_HEDGE_COST else 0
	else
		local other: Types.Issue = if record.flavor[1] == issue then record.flavor[2] else record.flavor[1]
		points = C.STANCE_HEDGE
		if table.find(stance.likes, other) then
			points = C.STANCE_POINTS
		elseif table.find(stance.dislikes, other) then
			points = -C.STANCE_POINTS
		end
		if inBase then
			points *= C.STANCE_BASE_MULT
		end
	end
	if table.find(platform, issue) then
		points *= C.STANCE_PLATFORM_MULT
	end
	return math.clamp(points, -C.STANCE_CAP, C.STANCE_CAP)
end

-- The id of the first state with `issue` as a top issue whose other top issue
-- the stance likes (`liked` true) or dislikes (false).
local function stateWhere(event: Events.Definition, stance: Events.Stance, liked: boolean): Types.StateRecord
	local issue = event.issue :: Types.Issue
	for _, record in StateData.list do
		if table.find(record.flavor, issue) then
			for _, other in record.flavor do
				if other ~= issue and table.find(if liked then stance.likes else stance.dislikes, other) then
					return record
				end
			end
		end
	end
	error("no such state")
end

describe("Events: Choice stances (D-039)", function()
	it(
		"a state with the issue reacts by its other top issue, the rest spill a little; a platform and a base are heard harder",
		function()
			local NONE: { Types.Issue } = {}
			-- Three bases: none, every third state, every state.
			local third: { string } = {}
			local everyone: { string } = {}
			for i, record in StateData.list do
				table.insert(everyone, record.id)
				if i % 3 == 0 then
					table.insert(third, record.id)
				end
			end
			for _, base in { {}, third, everyone } do
				for _, event in choiceEvents() do
					local issue = event.issue :: Types.Issue
					local ON: { Types.Issue } = { issue }
					for _, stance in event.stances :: { Events.Stance } do
						local listed = Events.stanceEffects(C, FLAVOR, event, stance.id, NONE, base)
						local nonzero = 0
						for i, record in StateData.list do
							local points = Events.stanceEffect(C, FLAVOR, event, stance.id, i, NONE, base)
							local heard = Events.stanceEffect(C, FLAVOR, event, stance.id, i, ON, base)
							expect(points):toBeCloseTo(expectedStance(event, stance, record, NONE, base), EPS)
							expect(heard):toBeCloseTo(expectedStance(event, stance, record, ON, base), EPS)
							expect(math.abs(points) <= C.STANCE_CAP and math.abs(heard) <= C.STANCE_CAP):toBe(
								true
							)
							if not table.find(record.flavor, issue) then
								-- The platform never reaches a state without the issue.
								expect(heard):toBe(points)
							end
							if points ~= 0 then
								nonzero += 1
								expect(listed[record.id]):toBe(points)
							else
								expect(listed[record.id]):toBe(nil)
							end
						end
						local count = 0
						for _ in listed do
							count += 1
						end
						expect(count):toBe(nonzero)
						if not stance.hedge then
							expect(nonzero >= 8):toBe(true) -- every issue tops at least eight states
						end
					end
					-- Unknown stances and events without stances move nothing.
					expect(Events.stanceEffect(C, FLAVOR, event, "Z" :: any, 1, NONE, base)):toBe(0)
					expect(Events.stanceEffect(C, FLAVOR, Events.byId.expo, "A", 1, NONE, base)):toBe(0)
				end
			end
		end
	)

	it(
		"a side counts double in the taker's own base, in issue states and spill states alike (D-043)",
		function()
			local event = Events.byId.plant -- Jobs: A likes Transit and Farms, dislikes Health and Safety
			local stance = Events.stance(event, "A")
			local liked, disliked = stateWhere(event, stance, true), stateWhere(event, stance, false)
			local NONE: { Types.Issue } = {}
			local function at(record: Types.StateRecord, base: { string }): number
				return Events.stanceEffect(C, FLAVOR, event, "A", State.indexOf[record.id], NONE, base)
			end
			expect(at(liked, {})):toBe(C.STANCE_POINTS)
			expect(at(liked, { liked.id })):toBe(C.STANCE_POINTS * C.STANCE_BASE_MULT)
			expect(at(disliked, {})):toBe(-C.STANCE_POINTS)
			expect(at(disliked, { disliked.id })):toBe(-C.STANCE_POINTS * C.STANCE_BASE_MULT)
			-- Someone else's base changes nothing here.
			expect(at(liked, { disliked.id })):toBe(C.STANCE_POINTS)
			-- A spill state doubles too (no Jobs, at least one issue the stance likes).
			local spill: Types.StateRecord? = nil
			for _, record in StateData.list do
				if not table.find(record.flavor, "Jobs") then
					local value =
						Events.stanceEffect(C, FLAVOR, event, "A", State.indexOf[record.id], NONE, nil)
					if value == C.STANCE_SPILL then
						spill = record
						break
					end
				end
			end
			expect(spill ~= nil):toBe(true)
			expect(at(spill :: Types.StateRecord, { (spill :: Types.StateRecord).id })):toBe(
				C.STANCE_SPILL * C.STANCE_BASE_MULT
			)
			-- Events.baseOf is the home plus the strongholds, each once.
			expect(Events.baseOf({ home = "OH", strongholds = { "PA", "OH" } })):toEqual({ "PA", "OH" })
			expect(Events.baseOf({ home = "OH", strongholds = { "PA" } })):toEqual({ "PA", "OH" })
			expect(Events.baseOf({ home = nil, strongholds = {} })):toEqual({})
		end
	)

	it(
		"the hedge moves nothing, except a cost in the taker's base states that have the issue (D-043)",
		function()
			for _, event in choiceEvents() do
				local issue = event.issue :: Types.Issue
				local ON: { Types.Issue } = { issue }
				-- No base: the hedge moves no state at all.
				expect(next(Events.stanceEffects(C, FLAVOR, event, "C", {}, {}))):toBe(nil)
				expect(next(Events.stanceEffects(C, FLAVOR, event, "C", ON, nil))):toBe(nil)
				-- Everyone's base: exactly the issue's states move, all by the cost.
				local everyone: { string } = {}
				for _, record in StateData.list do
					table.insert(everyone, record.id)
				end
				local plain = Events.stanceEffects(C, FLAVOR, event, "C", {}, everyone)
				local platform = Events.stanceEffects(C, FLAVOR, event, "C", ON, everyone)
				for _, record in StateData.list do
					if table.find(record.flavor, issue) then
						expect(plain[record.id]):toBe(-C.STANCE_HEDGE_COST)
						expect(platform[record.id]):toBe(-C.STANCE_HEDGE_COST * C.STANCE_PLATFORM_MULT)
					else
						expect(plain[record.id]):toBe(nil) -- the hedge never spills
						expect(platform[record.id]):toBe(nil)
					end
				end
				-- A base state without the issue is free, too.
				for _, record in StateData.list do
					if not table.find(record.flavor, issue) then
						expect(Events.stanceEffects(C, FLAVOR, event, "C", ON, { record.id })[record.id]):toBe(
							nil
						)
						break
					end
				end
			end
		end
	)

	it("each side's camp holds a fair share of the issue's EV; the hedge belongs to neither", function()
		for _, event in choiceEvents() do
			local issue = event.issue :: Types.Issue
			local stances = event.stances :: { Events.Stance }
			local total = campEV(issue, Issues.list :: { Types.Issue })
			for _, stance in stances do
				local liked, disliked = campEV(issue, stance.likes), campEV(issue, stance.dislikes)
				if stance.hedge then
					expect(liked + disliked):toBe(0)
				else
					-- Both camps are real: at least a quarter of the issue's EV each way.
					expect(liked >= 0.25 * total):toBe(true)
					expect(disliked >= 0.25 * total):toBe(true)
				end
			end
		end
	end)

	it("a stance moves a state by at most STANCE_CAP, either way (D-043)", function()
		local event = Events.byId.plant
		local stance = Events.stance(event, "A")
		local liked, disliked = stateWhere(event, stance, true), stateWhere(event, stance, false)
		local ON: { Types.Issue } = { "Jobs" }
		-- 1.5 x 2 (base) x 1.5 (platform) = 4.5 asks for more than the cap.
		expect(C.STANCE_POINTS * C.STANCE_BASE_MULT * C.STANCE_PLATFORM_MULT > C.STANCE_CAP):toBe(true)
		expect(Events.stanceEffect(C, FLAVOR, event, "A", State.indexOf[liked.id], ON, { liked.id })):toBe(
			C.STANCE_CAP
		)
		expect(Events.stanceEffect(C, FLAVOR, event, "A", State.indexOf[disliked.id], ON, { disliked.id })):toBe(
			-C.STANCE_CAP
		)
		-- Short of the cap the product stands: base alone, platform alone.
		expect(Events.stanceEffect(C, FLAVOR, event, "A", State.indexOf[liked.id], {}, { liked.id })):toBe(
			C.STANCE_POINTS * C.STANCE_BASE_MULT
		)
		expect(Events.stanceEffect(C, FLAVOR, event, "A", State.indexOf[liked.id], ON, {})):toBe(
			C.STANCE_POINTS * C.STANCE_PLATFORM_MULT
		)
		-- The cap is STANCE_CAP, not EVENT_CAP: a lower one bites.
		local tight = Config.with(C, { STANCE_CAP = 2.5 })
		expect(Events.stanceEffect(tight, FLAVOR, event, "A", State.indexOf[liked.id], ON, { liked.id })):toBe(
			2.5
		)
	end)

	it("resolves both stances together from one snapshot, records the moves and reveals them", function()
		local match = clean("plant") -- Jobs: on both platforms here, so every reaction is heard x1.5
		local event = Events.byId.plant
		local after = resolve(match, { { actions = {}, choice = "A" }, { actions = {}, choice = "B" } })
		local bases = { Events.baseOf(match.players[1]), Events.baseOf(match.players[2]) }
		local effects = {
			Events.stanceEffects(C, FLAVOR, event, "A", match.players[1].platform, bases[1]),
			Events.stanceEffects(C, FLAVOR, event, "B", match.players[2].platform, bases[2]),
		}
		-- Georgia (Jobs + Transit): A likes Transit, heard x1.5, and x2 more in a base.
		local gaMult = if table.find(bases[1], "GA") then C.STANCE_BASE_MULT else 1
		expect(effects[1].GA):toBe(math.min(C.STANCE_CAP, C.STANCE_POINTS * gaMult * C.STANCE_PLATFORM_MULT))
		local expected = State.clone(match)
		local moves: { State.StateMove } = {}
		for i, s in expected.states do
			local delta = Support.zero(s)
			local du = 0
			local points = { effects[1][s.id] or 0, effects[2][s.id] or 0 }
			for p = 1, 2 do
				if points[p] > 0 then
					du += Support.addGain(C, s, p, points[p], delta)
				elseif points[p] < 0 then
					du += Support.addLoss(p, -points[p], delta)
				end
			end
			if points[1] ~= 0 or points[2] ~= 0 then
				table.insert(moves, { state = s.id, points = points })
			end
			Support.apply(s, delta, du)
			expect(after.states[i].support[1]):toBeCloseTo(s.support[1], EPS)
			expect(after.states[i].support[2]):toBeCloseTo(s.support[2], EPS)
			expect(after.states[i].undecided):toBeCloseTo(s.undecided, EPS)
			-- No stance asks for more than the cap; a state without Jobs moves only by
			-- the spillover (doubled in a base).
			expect(math.abs(points[1]) <= C.STANCE_CAP and math.abs(points[2]) <= C.STANCE_CAP):toBe(true)
			if not table.find(StateData.list[i].flavor, "Jobs") then
				local most = 2 * C.STANCE_SPILL * C.STANCE_BASE_MULT + EPS
				expect(math.abs(points[1]) <= most and math.abs(points[2]) <= most):toBe(true)
			end
			-- The recount counterfactual sees exactly this move.
			for p = 1, 2 do
				expect(after.states[i].stanceShift[p]):toBeCloseTo(
					after.states[i].support[p] - match.states[i].support[p],
					EPS
				)
			end
		end
		expect(#moves > 0):toBe(true)
		local result = after.eventLog[#after.eventLog]
		expect(result.week):toBe(2)
		expect(result.id):toBe("plant")
		expect(result.choices):toEqual({ "A", "B" })
		expect(result.moves):toEqual(moves)
		-- Flips are projected on the start-of-week polls (35/35 here: whoever gains
		-- more takes the lead; equal points leave the tie).
		local flips = {}
		for _, move in moves do
			local to = if move.points[1] > move.points[2]
				then 1
				elseif move.points[2] > move.points[1] then 2
				else 0
			if to ~= 0 then
				table.insert(flips, { state = move.state, from = 0, to = to })
			end
		end
		expect(result.flips):toEqual(flips)
		expect((after.players[1].card :: State.WeekCard).choice):toBe("A")
		expect((after.players[2].card :: State.WeekCard).choice):toBe("B")
		local view = View.build(C, after, 2)
		expect(view.eventLog[#view.eventLog].choices):toEqual({ "A", "B" })
		expect(view.eventLog[#view.eventLog].moves):toEqual(moves)
		-- The election can be recounted without the stances' shifts.
		local with = Election.count(C, after, { noise = false })
		local recount = Election.count(C, after, { noise = false, stances = false })
		expect(with.ev[1] + with.ev[2] > 0):toBe(true)
		expect(recount.ev[1] + recount.ev[2]):toBe(0) -- every state was 35/35 before
	end)

	it("the same event moves the same states the same way in every match (given the platform)", function()
		local a = Fixtures.advanceTo(Fixtures.campaign({ seed = 4 }), "Plan", 5)
		local b =
			Fixtures.advanceTo(Fixtures.campaign({ seed = 9, candidates = { "reyes", "hale" } }), "Plan", 7)
		for p = 1, 2 do
			b.players[p].platform = table.clone(a.players[p].platform)
		end
		a.eventDeck[5], b.eventDeck[7] = "water", "water"
		local ra = resolve(a, { { actions = {}, choice = "A" }, { actions = {}, choice = "C" } })
		local rb = resolve(b, { { actions = {}, choice = "A" }, { actions = {}, choice = "C" } })
		local ma = ra.eventLog[#ra.eventLog].moves :: { State.StateMove }
		local mb = rb.eventLog[#rb.eventLog].moves :: { State.StateMove }
		expect(ma):toEqual(mb)
		expect(ma):toEqual(
			resolve(a, { { actions = {}, choice = "A" }, { actions = {}, choice = "C" } }).eventLog[#ra.eventLog].moves
		)
	end)

	it("swapping seats mirrors the outcome exactly", function()
		local match = clean("river") -- a symmetric board
		-- Same platform and same base for both seats (stances now depend on the draft).
		match.players[2].home = match.players[1].home
		match.players[2].strongholds = table.clone(match.players[1].strongholds)
		for _, pair in { { "A", "B" }, { "A", "C" }, { "B", "C" } } do
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
			for k, move in ra.moves :: { State.StateMove } do
				local other = (rb.moves :: { State.StateMove })[k]
				expect(move.state):toBe(other.state)
				expect(move.points):toEqual({ other.points[2], other.points[1] })
			end
		end
	end)

	it(
		"a missing stance defaults to the hedge, which costs each seat only in its own base (D-043)",
		function()
			local match = clean("walkout") -- Health
			expect(Events.defaultChoice()):toBe("C")
			-- Seat 1's home has Health; seat 2 has no base state with Health.
			local healthy: string? = nil
			for _, record in StateData.list do
				if table.find(record.flavor, "Health") then
					healthy = record.id
					break
				end
			end
			expect(healthy ~= nil):toBe(true)
			match.players[1].home = healthy
			match.players[1].strongholds = {}
			match.players[2].home = nil
			match.players[2].strongholds = {}
			local ok, _, plan = Plan.validate(C, match, 1, { actions = {} })
			expect(ok):toBe(true)
			expect((plan :: Plan.Plan).choice):toBe("C")
			expect(Plan.empty(C, match, 2).choice):toBe("C")
			local after = Match.advance(C, match, {})
			expect(after.eventLog[#after.eventLog].choices):toEqual({ "C", "C" })
			local moves = after.eventLog[#after.eventLog].moves :: { State.StateMove }
			-- Health is on both platforms here, so the cost is heard x1.5.
			expect(moves):toEqual({
				{ state = healthy :: string, points = { -C.STANCE_HEDGE_COST * C.STANCE_PLATFORM_MULT, 0 } },
			})
		end
	)

	it("rejects an invalid stance with a reason code, whole", function()
		local match = clean("calendar")
		for _, bad in { "Attack", "Ignore", "a", "", 3, true, { "A" } } do
			local ok, reason, plan =
				Plan.validate(C, match, 1, { actions = rallies("OH", "Jobs", 1), choice = bad })
			expect(ok):toBe(false)
			expect(reason):toBe(Plan.Reason.BadChoice)
			expect(plan):toBe(nil)
		end
		for _, id in Events.CHOICES do
			local ok, _, plan = Plan.validate(C, match, 1, { actions = {}, choice = id })
			expect(ok):toBe(true)
			expect((plan :: Plan.Plan).choice):toBe(id)
		end
	end)

	it("a stance is only allowed in a Choice week", function()
		for _, id in { "expo", "lakes", "donors" } do
			local match = clean(id)
			local ok, reason = Plan.validate(C, match, 1, { actions = {}, choice = "A" })
			expect(ok):toBe(false)
			expect(reason):toBe(Plan.Reason.UnexpectedChoice)
			expect(Plan.empty(C, match, 1).choice):toBe(nil)
		end
		local ok, reason = Plan.validate(C, clean(nil), 1, { actions = {}, choice = "C" })
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
		local ok, reason = Plan.validate(OFF, match, 1, { actions = {}, choice = "A" })
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
		expect(a.match.debates):toEqual(b.match.debates)
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
