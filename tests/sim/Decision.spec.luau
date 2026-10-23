--!strict
-- The Decision phase (D-044): the debate focus and Choice stances on their own step
-- before the plan. Ordering inside a week, validation and reason codes, timeout
-- defaults, never-partial application, determinism, and no leaks.

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Config = require("@sim/Config")
local Decision = require("@sim/Decision")
local Events = require("@sim/Events")
local Match = require("@sim/Match")
local Plan = require("@sim/Plan")
local Rng = require("@sim/Rng")
local State = require("@sim/State")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local R = Plan.Reason

-- Stable text form of any plain value (sorted keys), for byte-for-byte comparison.
local function serialize(value: any): string
	if type(value) == "table" then
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
	elseif type(value) == "number" then
		return string.format("%.17g", value)
	end
	return tostring(value)
end

-- Plays a match with default inputs and returns the phase trail of one week:
-- "Decision:Focus", "Debate", "Decision:Stance", "Plan".
local function weekTrail(match: State.MatchState, week: number): { string }
	local trail = {}
	local guard = 0
	while match.week <= week and match.phase ~= "Election" do
		if match.week == week then
			table.insert(trail, if match.decision then `{match.phase}:{match.decision}` else match.phase)
		end
		match = Match.advance(C, match, {})
		guard += 1
		assert(guard < 200, "never left the week")
	end
	return trail
end

-- Week 3's plan with week 4's (debate) event and week 5's event set by hand.
local function before4(event4: string?, event5: string?): State.MatchState
	local match = Fixtures.advanceTo(Fixtures.campaign({ seed = 8 }), "Plan", 3)
	match.eventDeck[4] = event4
	match.eventDeck[5] = event5
	return match
end

-- A match in week 4's Focus decision.
local function focusDecision(): State.MatchState
	local match = Match.advance(C, before4(nil, nil), {})
	assert(match.phase == "Decision" and match.decision == "Focus", "week 4 opens with the focus")
	return match
end

-- A match in week 5's Stance decision.
local function stanceDecision(): State.MatchState
	local match = before4(nil, "plant")
	while not (match.phase == "Decision" and match.week == 5) do
		match = Match.advance(C, match, {})
	end
	assert(match.decision == "Stance", "week 5 opens with a stance")
	return match
end

describe("Decision: order inside a week", function()
	it("a debate week picks the focus, then debates, then plans", function()
		expect(weekTrail(before4("expo", nil), 4)):toEqual({ "Decision:Focus", "Debate", "Plan" })
	end)

	it("a Choice week decides the stance, then plans", function()
		expect(weekTrail(before4(nil, "plant"), 5)):toEqual({ "Decision:Stance", "Plan" })
	end)

	it("a debate week with a Choice event: focus, debate, then the stance, then the plan", function()
		expect(weekTrail(before4("plant", nil), 4)):toEqual({
			"Decision:Focus",
			"Debate",
			"Decision:Stance",
			"Plan",
		})
	end)

	it("any other week goes straight to the plan", function()
		expect(weekTrail(before4(nil, "expo"), 5)):toEqual({ "Plan" })
		expect(weekTrail(before4(nil, nil), 5)):toEqual({ "Plan" })
		expect(Decision.opening(C, before4(nil, nil), 5)):toBe(nil)
	end)

	it("with the event deck off, only the debate focus is decided", function()
		local OFF = Config.with(C, { EVENTS_ENABLED = false })
		local match = Match.new(OFF, 4, { "a", "b" })
		local decisions = {}
		while match.phase ~= "Done" do
			if match.phase == "Decision" then
				table.insert(decisions, `{match.week}:{match.decision}`)
			end
			match = Match.advance(OFF, match, {})
		end
		expect(decisions):toEqual({ "4:Focus", "9:Focus" })
	end)
end)

describe("Decision.validate", function()
	it("takes one of this debate's topics as the focus, and nothing else", function()
		local match = focusDecision()
		local topics = match.debateTopics[4]
		for _, topic in topics do
			local ok, reason, input = Decision.validate(C, match, 1, { focus = topic })
			expect(reason):toBe(nil)
			expect(ok):toBe(true)
			expect((input :: Decision.Input).focus):toBe(topic)
		end
		local other = "Jobs"
		for _, issue in { "Jobs", "Health", "Schools", "Farms" } do
			if not table.find(topics, issue :: any) then
				other = issue
			end
		end
		for _, bad in { other, "Nothing", "", 1, true, { topics[1] }, { 2, 2, 2 } } do
			expect(select(2, Decision.validate(C, match, 1, { focus = bad }))):toBe(R.BadFocus)
		end
		expect(select(2, Decision.validate(C, match, 1, {}))):toBe(R.BadFocus)
		expect(select(2, Decision.validate(C, match, 1, { prep = { 2, 2, 2 } }))):toBe(R.BadFocus)
		expect(select(2, Decision.validate(C, match, 1, { focus = topics[1], choice = "A" }))):toBe(
			R.UnexpectedChoice
		)
	end)

	it("takes one of the three stances, and nothing else", function()
		local match = stanceDecision()
		for _, id in Events.CHOICES do
			local ok, _, input = Decision.validate(C, match, 2, { choice = id })
			expect(ok):toBe(true)
			expect((input :: Decision.Input).choice):toBe(id)
		end
		for _, bad in { "D", "a", "", 3, true, { "A" } } do
			expect(select(2, Decision.validate(C, match, 2, { choice = bad }))):toBe(R.BadChoice)
		end
		expect(select(2, Decision.validate(C, match, 2, {}))):toBe(R.BadChoice)
		expect(select(2, Decision.validate(C, match, 2, { choice = "A", focus = "Jobs" }))):toBe(
			R.UnexpectedFocus
		)
		-- A weekly plan is not a decision.
		expect(select(2, Decision.validate(C, match, 2, { actions = {} }))):toBe(R.BadChoice)
	end)

	it("drops unknown fields and rejects every other shape with a code, never throwing", function()
		local match = stanceDecision()
		local _, _, input = Decision.validate(C, match, 1, { choice = "B", cheat = true, actions = { 1 } })
		expect(input):toEqual({ choice = "B" })
		local rng = Rng.new(5)
		local junk: { any } = { 1, "x", true, {}, { choice = {} }, { focus = { {} } }, { 1, 2, 3 } }
		for _ = 1, 50 do
			table.insert(junk, { choice = Rng.nextInt(rng, -5, 5), focus = Rng.nextFloat(rng) })
		end
		for _, kind in { "Focus", "Stance" } do
			match.decision = kind :: State.DecisionKind
			for _, raw in junk do
				local ok, reason = Match.validate(C, match, 1, raw)
				expect(ok):toBe(false)
				expect(type(reason)):toBe("string")
				expect(reason ~= "Internal"):toBe(true)
			end
		end
	end)

	it("only in a Decision phase; the plan phase rejects decision payloads", function()
		local match = before4(nil, nil)
		expect(select(2, Decision.validate(C, match, 1, { choice = "A" }))):toBe(R.WrongPhase)
		expect(select(2, Match.validate(C, match, 1, { focus = "Jobs" }))):toBe(R.BadShape)
		expect(select(2, Match.validate(C, match, 1, { actions = {}, focus = "Jobs" }))):toBe(
			R.UnexpectedFocus
		)
		expect(select(2, Match.validate(C, match, 1, { actions = {}, choice = "A" }))):toBe(
			R.UnexpectedChoice
		)
	end)
end)

describe("Decision: defaults, application and secrecy", function()
	it("nothing sent (the timer ran out): no focus, and the hedge", function()
		local match = focusDecision()
		expect(Decision.default(C, match, 1)):toEqual({})
		match = Match.advance(C, match, {})
		expect(match.phase):toBe("Debate")
		expect(match.players[1].debateFocus):toBe(nil)
		match = Match.advance(C, match, {})
		expect(match.debates[1].focus):toEqual({ 0, 0 })
		expect(match.debates[1].prep):toEqual({ { 0, 0, 0 }, { 0, 0, 0 } })

		match = stanceDecision()
		expect(Decision.default(C, match, 2)):toEqual({ choice = "C" })
		match = Match.advance(C, match, {})
		expect(match.phase):toBe("Plan")
		expect(match.players[1].stance):toBe("C")
		match = Match.advance(C, match, {})
		expect(match.eventLog[#match.eventLog].choices):toEqual({ "C", "C" })
		expect(match.players[1].stance):toBe(nil) -- spent with the week
	end)

	it("an invalid decision is replaced by the default whole, never partially", function()
		local start = focusDecision()
		local topic = start.debateTopics[4][2]
		local match = Match.advance(C, start, { { focus = topic, choice = "A" }, { focus = topic } })
		expect(match.players[1].debateFocus):toBe(nil)
		expect(match.players[2].debateFocus):toBe(topic)
		match = Match.advance(C, stanceDecision(), { { choice = "Z" }, { choice = "B" } })
		expect(match.players[1].stance):toBe("C")
		expect(match.players[2].stance):toBe("B")
	end)

	it("the stance taken is the one the week resolves with, for both seats at once", function()
		local match = Match.advance(C, stanceDecision(), { { choice = "A" }, { choice = "B" } })
		local view = View.build(C, match, 1)
		expect(view.stance):toBe("A")
		expect(View.build(C, match, 2).stance):toBe("B")
		match = Match.advance(C, match, {})
		expect(match.eventLog[#match.eventLog].choices):toEqual({ "A", "B" })
		expect((match.players[1].card :: State.WeekCard).choice):toBe("A")
		expect(View.build(C, match, 1).stance):toBe(nil)
	end)

	it("swapping seats mirrors the decisions exactly (no seat is favored, D-001)", function()
		local a = Match.advance(C, stanceDecision(), { { choice = "A" }, { choice = "B" } })
		local b = Match.advance(C, stanceDecision(), { { choice = "B" }, { choice = "A" } })
		expect(a.players[1].stance):toBe(b.players[2].stance)
		expect(a.players[2].stance):toBe(b.players[1].stance)
	end)

	it("the opponent's decision never reaches your view before it resolves", function()
		local topics = focusDecision().debateTopics[4]
		local function viewAfter(theirs: any, phase: "Focus" | "Stance"): string
			local match = if phase == "Focus" then focusDecision() else stanceDecision()
			local mine = if phase == "Focus" then { focus = topics[1] } else { choice = "C" }
			match = Match.advance(C, match, { mine, theirs })
			return serialize(View.build(C, match, 1))
		end
		local focusBase = viewAfter({ focus = topics[1] }, "Focus")
		expect(viewAfter({ focus = topics[3] }, "Focus")):toBe(focusBase)
		expect(viewAfter({}, "Focus")):toBe(focusBase)
		local stanceBase = viewAfter({ choice = "C" }, "Stance")
		expect(viewAfter({ choice = "A" }, "Stance")):toBe(stanceBase)
		-- Deep check: nothing about the opponent's stance anywhere in the view.
		local match = Match.advance(C, stanceDecision(), { { choice = "C" }, { choice = "A" } })
		local function scan(value: any)
			if type(value) == "table" then
				for key, child in value do
					expect(key ~= "stance" or child == "C"):toBe(true)
					scan(child)
				end
			end
		end
		scan(View.build(C, match, 1))
	end)

	it("the decision's view says what is asked, and shows the event and topics", function()
		local focus = View.build(C, focusDecision(), 1)
		expect(focus.phase):toBe("Decision")
		expect(focus.decision):toBe("Focus")
		expect(focus.nextDebate and focus.nextDebate.week):toBe(4)
		local stance = View.build(C, stanceDecision(), 1)
		expect(stance.decision):toBe("Stance")
		expect(stance.event and stance.event.kind):toBe("Choice")
		expect(View.build(C, before4(nil, nil), 1).decision):toBe(nil)
	end)

	it("is deterministic: same seed and decisions give the same match", function()
		local function run(): State.MatchState
			local match = Match.new(C, 17, { "a", "b" })
			while match.phase ~= "Done" do
				local inputs = {}
				if match.phase == "Decision" then
					local topics = match.debateTopics[match.week]
					inputs = if match.decision == "Focus"
						then { { focus = topics[1] }, { focus = topics[3] } }
						else { { choice = "A" }, { choice = "B" } }
				end
				match = Match.advance(C, match, inputs)
			end
			return match
		end
		local a, b = run(), run()
		expect(a):toEqual(b)
		expect(a.debates[1].focus):toEqual({ 1, 3 })
	end)
end)
