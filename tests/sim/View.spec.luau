--!strict
-- View is the only exit for simulation state. These specs check that it carries
-- nothing hidden: forbidden fields never appear, and changing any hidden value
-- leaves the view byte-for-byte the same.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Config = require("@sim/Config")
local Events = require("@sim/Events")
local Match = require("@sim/Match")
local Session = require("@net/Session")
local State = require("@sim/State")
local StateData = require("@sim/StateData")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local OFF = Config.with(C, { EVENTS_ENABLED = false })

-- Keys that name hidden simulation data. None may appear anywhere in a view.
local FORBIDDEN = {
	"pollError",
	"pollErrorUndecided",
	"pool",
	"debateShift",
	"stanceShift",
	"rng",
	"seed",
	"s0",
	"spare",
	"profile",
	"lead",
	"eventDeck",
}

-- Stable text form of any plain value (sorted keys), for byte-for-byte comparison.
local function serialize(value: any): string
	local kind = type(value)
	if kind == "table" then
		local keys = {}
		for key in value do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		for _, key in keys do
			table.insert(parts, `{tostring(key)}={serialize(value[key])}`)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif kind == "number" then
		return string.format("%.17g", value)
	end
	assert(kind == "string" or kind == "boolean" or kind == "nil", `view holds a {kind}`)
	return tostring(value)
end

local function walk(value: any, path: string, visit: (key: string, path: string) -> ())
	if type(value) ~= "table" then
		return
	end
	for key, child in value do
		local name = tostring(key)
		visit(name, path .. "." .. name)
		walk(child, path .. "." .. name, visit)
	end
end

local function checkView(view: View.View)
	walk(view, "view", function(key, path)
		if table.find(FORBIDDEN, key) then
			error(`hidden field leaked at {path}`)
		end
	end)
	for _, s in view.states do
		local entry = s :: any
		if entry.support ~= nil or entry.undecided ~= nil then
			error(`true support leaked for {s.id}`)
		end
	end
	for p, player in view.players do
		if p ~= view.you and player.cash ~= nil then
			error("opponent cash leaked")
		end
	end
	serialize(view) -- plain data only: no functions, threads or userdata
end

-- A match mid-campaign where both players have hidden data of every kind.
local function busyMatch(): State.MatchState
	local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 12 }), "Plan", 3)
	local plan = {
		actions = {
			{ kind = "Poll", state = "OH" },
			{ kind = "Gotv", state = "OH", units = 1 },
			{ kind = "Attack", state = "PA", issue = "Farms" },
			{ kind = "Fundraise", state = match.players[1].location },
		},
		prep = { 4, 2, 0 },
	}
	local plan2 = table.clone(plan)
	plan2.actions = table.clone(plan.actions)
	plan2.actions[4] = { kind = "Fundraise", state = match.players[2].location }
	for p, input in { plan, plan2 } do
		local ok, reason = Match.validate(C, match, p, input)
		assert(ok, `busy plan {p} rejected: {reason}`)
	end
	return (Match.advance(C, match, { plan, plan2 }))
end

describe("View: no leaks", function()
	it("no view in a whole match carries hidden fields", function()
		local match = Match.new(C, 99, { "a", "b" })
		while true do
			for p = 1, 2 do
				checkView(View.build(C, match, p))
			end
			if match.phase == "Done" then
				break
			end
			match = Match.advance(C, match, {})
		end
	end)

	it("changing any hidden value leaves the view identical", function()
		local match = busyMatch()
		expect(match.phase):toBe("Debate")
		local before = serialize(View.build(C, match, 1))

		local secret = State.clone(match)
		for _, s in secret.states do
			s.support[1] += 0.37
			s.support[2] -= 0.21
			s.undecided -= 0.16
			s.pool = s.pool / 2
			s.pollError[1] += 1
			s.pollError[2] -= 1
			s.pollErrorUndecided += 2
			s.gotv[2] += 3
			s.debateShift[1] += 0.5
			s.debateShift[2] -= 0.5
			s.stanceShift[1] += 0.25
			s.stanceShift[2] -= 0.25
			s.backlash[2] += 2
		end
		local opponent = secret.players[2]
		opponent.cash = if opponent.cash > 10 then opponent.cash + 5 elseif opponent.cash < 4 then 0 else 7
		opponent.internalPolls = { { state = "CA", support = { 1, 2 }, undecided = 3, momentum = { 0, 0 } } }
		opponent.raised = 1234
		opponent.debatePrep = { 0, 3, 3 }
		opponent.lead = (opponent.lead or 0) + 0.001 -- same tier, different smoothed value
		secret.seed = 31337
		secret.rng.s0 = 1
		-- The rest of the deck: every week but the current one is hidden.
		for week = 1, C.WEEKS do
			if week ~= secret.week then
				secret.eventDeck[week] = if secret.eventDeck[week] == "memo" then "clip" else "memo"
			end
		end

		expect(serialize(View.build(C, secret, 1))):toBe(before)
	end)

	it("the opponent's pending Choice stance never reaches the other seat (D-027, D-039)", function()
		-- Stances live only in the submitted plan (the server's seat input) until the
		-- week resolves; nothing the opponent locks in may change what seat 1 is sent.
		local function payloadFor(choice: string?): string
			local session = Session.new(C, "m", 3, {
				{ id = "100", kind = "Human" },
				{ id = "200", kind = "Human" },
			}, 0)
			local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 3 }), "Plan", 2)
			match.eventDeck[2] = "plant"
			session.match = match
			if choice then
				local ok, reason =
					Session.submit(session, 2, session.step, { actions = {}, choice = choice }, 0)
				assert(ok, reason)
			end
			local payload = Session.payload(session, 1)
			return serialize(payload.view) .. serialize(payload.events)
		end
		local before = payloadFor(nil)
		for _, choice in Events.CHOICES do
			expect(payloadFor(choice)):toBe(before)
		end
		expect(string.find(before, "choice=", 1, true)):toBe(nil) -- no stance anywhere yet
		-- The event's stances and issue are public before anyone answers; the
		-- per-state preview is a pure function of them.
		local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 3 }), "Plan", 2)
		match.eventDeck[2] = "plant"
		local pending = View.build(C, match, 1)
		local event = pending.event :: View.EventView
		expect(event.kind):toBe("Choice")
		expect(event.issue):toBe("Jobs")
		local stances = event.stances :: { View.StanceView }
		expect(#stances):toBe(3)
		for k, stance in stances do
			expect(stance.id):toBe(Events.CHOICES[k])
			expect(#stance.name > 0 and #stance.text > 0):toBe(true)
			-- The hedge moves a state only in the taker's base (D-043): public too.
			local base = Events.baseOf(pending.players[1])
			if stance.id == "C" then
				base = {}
				for _, record in StateData.list do
					table.insert(base, record.id)
				end
				expect(next(Events.stanceEffects(C, Events.byId[event.id], stance.id, {}, {}))):toBe(nil)
			end
			expect(next(Events.stanceEffects(C, Events.byId[event.id], stance.id, {}, base)) ~= nil):toBe(
				true
			)
		end
		local other = State.clone(match)
		other.eventDeck[2] = "expo"
		expect((View.build(C, other, 1).event :: View.EventView).stances):toBe(nil)
		-- After the week resolves, both stances and their moves are public.
		match = Match.advance(C, match, { nil :: any, { actions = {}, choice = "A" } })
		local view = View.build(C, match, 1)
		checkView(view)
		local logged = view.eventLog[#view.eventLog]
		expect(logged.choices):toEqual({ "C", "A" })
		expect(#(logged.moves :: { State.StateMove }) > 0):toBe(true)
		expect(logged.flips ~= nil):toBe(true)
		expect((view.players[2].card :: State.WeekCard).choice):toBe("A")
	end)

	it("the player does see their own hidden data", function()
		local match = busyMatch()
		local view = View.build(C, match, 1)
		expect(#view.internalPolls):toBe(1)
		expect(view.internalPolls[1].state):toBe("OH")
		expect(view.players[1].cash):toBe(match.players[1].cash)
		expect(view.debatePrep):toEqual({ 4, 2, 0 })
		local oh = view.states[State.indexOf.OH]
		expect(oh.gotv):toBe(1)
		expect(View.build(C, match, 2).states[State.indexOf.OH].gotv):toBe(1) -- their own unit, not mine
	end)

	it("opponent money is only a bracket", function()
		local match = busyMatch()
		local cases = { { 3.9, "Low" }, { 4, "Medium" }, { 10, "Medium" }, { 10.1, "High" } }
		for _, case in cases do
			match.players[2].cash = case[1]
			local view = View.build(C, match, 1)
			expect(view.players[2].money):toBe(case[2])
			expect(view.players[2].cash):toBe(nil)
		end
	end)

	it("hides candidates, platforms and leans until Select ends", function()
		local match = Match.new(C, 5, { "a", "b" })
		local view = View.build(C, match, 1)
		for _, player in view.players do
			expect(player.candidate):toBe(nil)
			expect(player.platform):toBe(nil)
		end
		for _, s in view.states do
			expect(s.lean):toBe(0)
		end
		match = Match.advance(C, match, {})
		view = View.build(C, match, 1)
		expect(view.players[2].candidate ~= nil):toBe(true)
		local leaned = 0
		for _, s in view.states do
			if s.lean > 0 then
				leaned += 1
			end
		end
		expect(leaned):toBe(C.LEAN_STATE_COUNT)
	end)

	it("clash priority is hidden until Select ends", function()
		local match = Match.new(C, 5, { "a", "b" })
		expect(View.build(C, match, 1).priorityA):toBe(nil)
		match = Match.advance(C, match, {})
		expect(View.build(C, match, 1).priorityA):toBe(match.priorityA)
		expect(View.build(C, match, 2).priorityA):toBe(match.priorityA)
	end)

	it("debate prep is revealed only after the debate; the debate's moves and flips come with it", function()
		local match = busyMatch()
		expect(#View.build(C, match, 1).debates):toBe(0)
		match = Match.advance(C, match, {})
		local view = View.build(C, match, 1)
		checkView(view)
		expect(view.debates[1].prep[2]):toEqual({ 4, 2, 0 })
		expect(view.debatePrep):toBe(nil)
		expect(view.debates[1].moves):toEqual(match.debates[1].moves)
		expect(view.debates[1].flips):toEqual(match.debates[1].flips)
		expect(view.debates[1].gaffes):toEqual(match.debates[1].gaffes)
	end)

	it("announces the next debate's topics", function()
		local match = Fixtures.campaign({ seed = 5 })
		local view = View.build(C, match, 1)
		expect(view.nextDebate and view.nextDebate.week):toBe(4)
		expect(view.nextDebate and view.nextDebate.topics):toEqual(match.debateTopics[4])
		match = Fixtures.advanceTo(match, "Plan", 5)
		view = View.build(C, match, 1)
		expect(view.nextDebate and view.nextDebate.week):toBe(9)
	end)

	it("Helen Strand sees next week's event; nobody else does (D-035)", function()
		local match = Fixtures.advanceTo(
			Fixtures.campaign({ seed = 5, candidates = { "strand", "okafor" } }),
			"Plan",
			3
		)
		local view = View.build(C, match, 1)
		checkView(view)
		expect(view.nextEvent and view.nextEvent.week):toBe(4)
		expect(view.nextEvent and view.nextEvent.id):toBe(match.eventDeck[4])
		expect(view.nextEvent and view.nextEvent.kind):toBe(Events.byId[match.eventDeck[4]].kind)
		expect(View.build(C, match, 2).nextEvent):toBe(nil)
		-- Only the next week: the rest of the deck stays hidden from her too.
		local before = serialize(view)
		local secret = State.clone(match)
		for week = 1, C.WEEKS do
			if week ~= secret.week and week ~= secret.week + 1 then
				secret.eventDeck[week] = if secret.eventDeck[week] == "memo" then "clip" else "memo"
			end
		end
		expect(serialize(View.build(C, secret, 1))):toBe(before)
		-- Week 12 has no event, so in week 11 there is nothing to preview; the preview
		-- is gone once the campaign is over.
		match = Fixtures.advanceTo(match, "Plan", 11)
		expect(View.build(C, match, 1).event ~= nil):toBe(true)
		expect(View.build(C, match, 1).nextEvent):toBe(nil)
		match = Fixtures.advanceTo(match, "Election")
		expect(View.build(C, match, 1).nextEvent):toBe(nil)
		-- With events off there is nothing to see.
		local off = Fixtures.advanceTo(
			Match.advance(OFF, Match.new(OFF, 5, { "a", "b" }), {
				{ candidate = "strand", color = "Crimson", platform = { "Jobs", "Health", "Schools" } },
				{ candidate = "okafor", color = "Cobalt", platform = { "Jobs", "Health", "Schools" } },
			}),
			"Plan",
			3
		)
		expect(View.build(OFF, off, 1).nextEvent):toBe(nil)
	end)

	it("the election result appears only on election night", function()
		local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 5 }), "Plan", 12)
		expect(View.build(C, match, 1).election):toBe(nil)
		match = Match.advance(C, match, {})
		expect(match.phase):toBe("Election")
		expect(View.build(C, match, 1).election ~= nil):toBe(true)
	end)

	it("filters private events to their owner", function()
		local events: { State.Event } = {
			{ kind = "Rally", player = 1, state = "OH" },
			{ kind = "Raised", player = 2, amount = 5, private = true },
			{ kind = "Raised", player = 1, amount = 4, private = true },
		}
		local mine = View.events(events, 1)
		expect(#mine):toBe(2)
		for _, event in mine do
			expect(event.amount ~= 5):toBe(true)
		end
	end)
end)
