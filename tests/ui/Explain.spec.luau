--!strict
-- Shared/UI/Explain: the plain-words numbers behind every action, label and
-- help section. Every expected value here is worked out by hand from Config and
-- Candidates (written as the formula, so a balance pass that changes a number
-- still passes), on a hand-set Ohio: you 40 – 35 them, 25 undecided. Pure.

local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Explain = require("@ui/Explain")
local Fixtures = require("@ui/Fixtures")
local IssueMap = require("@sim/IssueMap")
local Issues = require("@sim/Issues")
local Numbers = require("@ui/Numbers")
local PlanDraft = require("@ui/PlanDraft")
local State = require("@sim/State")
local StateData = require("@sim/StateData")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local OH = State.indexOf.OH

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function near(got: number?, want: number, what: string)
	check(got ~= nil, `{what}: no value`)
	check(math.abs((got :: number) - want) < 1e-6, `{what}: got {got}, want {want}`)
end

local function has(text: string, part: string)
	check(string.find(text, part, 1, true) ~= nil, `"{text}" lacks "{part}"`)
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

-- The week-3 fixture view with Ohio and both players set by hand: you are Dana
-- Okafor on Jobs/Health/Farms in Ohio, they are Rex Calloway on Schools/Safety/Transit.
local function ohio(): any
	local view = deepCopy(Fixtures.payload(C, "Plan").view)
	local me, them = view.you, if view.you == 1 then 2 else 1
	view.week = 3
	view.event = nil
	view.internalPolls = {}
	local mine, theirs = view.players[me], view.players[them]
	mine.candidate, mine.platform, mine.location = "okafor", { "Jobs", "Health", "Farms" }, "OH"
	mine.cash, mine.underdogTier, mine.frontrunner, mine.pivotUsed = 20, 0, false, false
	theirs.candidate, theirs.platform = "calloway", { "Schools", "Safety", "Transit" }
	theirs.underdogTier, theirs.frontrunner = 0, false
	local s = view.states[OH]
	s.poll = { support = table.create(#view.players, 0), undecided = 25 }
	s.poll.support[me], s.poll.support[them] = 40, 35
	s.battleground, s.owner, s.isHome = false, nil, false
	s.momentum = table.create(#view.players, 0)
	s.backlash, s.gotv = 0, 0
	s.lean, s.leanTo = 4, me
	-- The fixed flavor map (Ohio: Jobs and Schools) with the plain platform
	-- multiplier on every issue; real matches draw both (D-044).
	view.issueMap = IssueMap.flavor
	local mults = {}
	for _, issue in Issues.list do
		mults[issue] = C.ISSUE_MULT_BOTH
	end
	view.platformMults = mults
	return view
end

local function sat(support: number): number
	return math.clamp((C.SUPPORT_CAP - support) / (C.SUPPORT_CAP - C.BASE_SUPPORT), C.SATURATION_FLOOR, 1)
end

local CAPACITY = Config.poolCapacity(C, StateData.byId.OH.pop)

describe("Explain.estimate", function()
	it("uses the public poll, or your internal poll when you have one", function()
		local view = ohio()
		local est = Explain.estimate(C, view, "OH")
		expect(est.source):toBe("public")
		expect(est.mine):toBe(40)
		expect(est.theirs):toBe(35)
		expect(est.undecided):toBe(25)
		view.internalPolls = {
			{ state = "OH", support = { 41.5, 33.2 }, undecided = 25.3, momentum = { 0, 0 } },
		}
		view.internalPolls[1].support[view.you] = 41.5
		local internal = Explain.estimate(C, view, "OH")
		expect(internal.source):toBe("internal")
		expect(internal.mine):toBe(41.5)
	end)
end)

describe("Explain.action: rallies and ads", function()
	it("previews a rally on a platform issue that is a state top issue", function()
		local view = ohio()
		local p = Explain.action(C, view, PlanDraft.new(), "OH", "Rally", "Jobs")
		local gain = C.RALLY_SUPPORT * C.ISSUE_MULT_BOTH * sat(40)
		near(p.you, gain, "rally gain")
		near(p.them, -gain * (1 - C.GAIN_FROM_UNDECIDED), "rally opponent loss")
		near(p.momentum, C.RALLY_MOMENTUM, "rally momentum")
		has(p.text, `Rally: about {Numbers.signed(gain)} you`)
		has(p.text, "Jobs ×1.5")
		has(p.text, "1 AP")
	end)

	it("names the battleground, underdog and closing multipliers", function()
		local view = ohio()
		view.states[OH].battleground = true
		view.players[view.you].underdogTier = 2
		view.week = C.CLOSING_FROM_WEEK
		local p = Explain.action(C, view, PlanDraft.new(), "OH", "Rally", "Schools")
		local gain = C.RALLY_SUPPORT
			* C.ISSUE_MULT_STATE
			* C.BATTLEGROUND_MULT
			* C.UNDERDOG_RALLY_2
			* C.CLOSING_MULT
			* sat(40)
		near(p.you, gain, "rally gain")
		has(p.text, "battleground")
		has(p.text, "underdog")
		has(p.text, "closing weeks")
	end)

	it("uses the candidate's own rally and doubles Reyes's underdog bonus", function()
		local view = ohio()
		view.players[view.you].candidate = "reyes"
		view.players[view.you].underdogTier = 1
		local reyes = Candidates.profile(C, "reyes")
		local p = Explain.action(C, view, PlanDraft.new(), "OH", "Rally", "Health")
		local under = 1 + (C.UNDERDOG_RALLY_1 - 1) * reyes.underdogScale
		near(p.you, reyes.rallySupport * C.ISSUE_MULT_PLATFORM * under * sat(40), "Reyes rally")
		near(p.momentum, C.RALLY_MOMENTUM * reyes.momentumGainMult, "Reyes momentum")
	end)

	it("adds the event bonus up to the cap", function()
		local view = ohio()
		view.event = { week = 3, id = "factory", kind = "Spotlight", name = "x", text = "x", issue = "Jobs" }
		local p = Explain.action(C, view, PlanDraft.new(), "OH", "Rally", "Jobs")
		local base = C.RALLY_SUPPORT * C.ISSUE_MULT_BOTH * sat(40)
		near(p.you, base + math.min(base * (C.EVENT_SPOTLIGHT_MULT - 1), C.EVENT_CAP), "spotlight rally")
		has(p.text, "event")
	end)

	it("charges a flight when the rally is not next door", function()
		local view = ohio()
		local p = Explain.action(C, view, PlanDraft.new(), "CA", "Rally", "Jobs")
		has(p.text, `flight {Numbers.cost(C.FLIGHT_COST)}`)
		local next = Explain.action(C, view, PlanDraft.new(), "PA", "Rally", "Jobs")
		check(string.find(next.text, "flight", 1, true) == nil, next.text)
	end)

	it("discounts repeat ads in the same state", function()
		local view = ohio()
		local draft = PlanDraft.new()
		local first = Explain.action(C, view, draft, "OH", "Media", "Jobs")
		local gain = C.MEDIA_SUPPORT * C.ISSUE_MULT_BOTH * sat(40)
		near(first.you, gain, "first ad")
		near(first.momentum, C.MEDIA_MOMENTUM, "ad momentum")
		has(first.text, `Ad: about {Numbers.signed(gain)} you`)
		has(first.text, Numbers.cost(C.MEDIA_COST))
		PlanDraft.add(draft, { kind = "Media", state = "OH", issue = "Jobs" })
		local second = Explain.action(C, view, draft, "OH", "Media", "Jobs")
		near(second.you, gain * C.MEDIA_SATURATION, "second ad")
		has(second.text, "repeat")
	end)

	it("previews an attack ad and its backlash", function()
		local view = ohio()
		local p = Explain.action(C, view, PlanDraft.new(), "OH", "Attack", "Jobs")
		local loss = C.ATTACK_LOSS * C.ISSUE_MULT_ATTACK
		near(p.them, -loss, "attack loss")
		near(p.you, loss * (1 - C.ATTACK_TO_UNDECIDED), "attack gain")
		has(p.text, `Attack ad: about {Numbers.signed(-loss)} them`)
		has(p.text, `backlash 1 of {C.BACKLASH_THRESHOLD}`)
		view.states[OH].backlash = C.BACKLASH_THRESHOLD
		local hurt = Explain.action(C, view, PlanDraft.new(), "OH", "Attack", "Jobs")
		near(hurt.you, loss * (1 - C.ATTACK_TO_UNDECIDED) - C.BACKLASH_PENALTY, "attack with backlash")
		has(hurt.text, `backlash costs you {Numbers.points(C.BACKLASH_PENALTY)}`)
	end)

	it("counts attacks already in the plan toward the backlash meter", function()
		local view = ohio()
		view.states[OH].backlash = C.BACKLASH_THRESHOLD - 1
		local draft = PlanDraft.new()
		PlanDraft.add(draft, { kind = "Attack", state = "OH", issue = "Jobs" })
		local p = Explain.action(C, view, draft, "OH", "Attack", "Jobs")
		-- The second ad in the state is worth MEDIA_SATURATION of the first.
		local loss = C.ATTACK_LOSS * C.ISSUE_MULT_ATTACK * C.MEDIA_SATURATION
		near(p.them, -loss, "second attack")
		near(p.you, loss * (1 - C.ATTACK_TO_UNDECIDED) - C.BACKLASH_PENALTY, "second attack's backlash")
	end)
end)

describe("Explain.action: money, polls, ground game, pivot", function()
	it("previews a fundraiser, capped by the pool", function()
		local view = ohio()
		local okafor = Candidates.profile(C, "okafor")
		local raw = C.FUNDRAISER_BASE + C.FUNDRAISER_PER_SHARE * 40 / 100
		local draft = PlanDraft.new()
		local first = Explain.action(C, view, draft, "OH", "Fundraise", nil)
		near(first.money, raw * okafor.fundraiseMult, "first fundraiser")
		has(first.text, `Fundraise: up to about {Numbers.money(raw * okafor.fundraiseMult)}`)
		has(first.text, `pool {Numbers.money(CAPACITY)}`)
		-- Fill the pool with earlier fundraisers: the next one gets only what is left.
		local k = 1
		while k * raw < CAPACITY do
			PlanDraft.add(draft, { kind = "Fundraise", state = "OH" })
			k += 1
		end
		local last = Explain.action(C, view, draft, "OH", "Fundraise", nil)
		near(last.money, (CAPACITY - (k - 1) * raw) * okafor.fundraiseMult, "last fundraiser")
		PlanDraft.add(draft, { kind = "Fundraise", state = "OH" })
		local dry = Explain.action(C, view, draft, "OH", "Fundraise", nil)
		near(dry.money, 0, "dry pool")
	end)

	it("adds the home multiplier at home", function()
		local view = ohio()
		local s = view.states[OH]
		s.owner, s.isHome = view.you, true
		local raw = C.FUNDRAISER_BASE + C.FUNDRAISER_PER_SHARE * 40 / 100
		local p = Explain.action(C, view, PlanDraft.new(), "OH", "Fundraise", nil)
		near(p.money, raw * Candidates.profile(C, "okafor").fundraiseMult * C.HOME_FUNDRAISE_MULT, "home")
		has(p.text, "home")
	end)

	it("prices polls, free polls first", function()
		local view = ohio()
		local p = Explain.action(C, view, PlanDraft.new(), "OH", "Poll", nil)
		has(p.text, `±{C.INTERNAL_POLL_ERROR}`)
		has(p.text, Numbers.cost(C.INTERNAL_POLL_COST))
		view.players[view.you].candidate = "strand"
		local free = Explain.action(C, view, PlanDraft.new(), "OH", "Poll", nil)
		has(free.text, "free")
		local region = Explain.action(C, view, PlanDraft.new(), "OH", "RegionPoll", nil)
		local n = 0
		for _, record in StateData.list do
			if record.region == "GreatLakes" then
				n += 1
			end
		end
		has(region.text, `{n} Great Lakes states`)
		has(region.text, Numbers.cost(C.REGION_POLL_COST))
	end)

	it("previews ground game and pivot", function()
		local view = ohio()
		local gotv = Explain.action(C, view, PlanDraft.new(), "OH", "Gotv", nil)
		has(gotv.text, `{Numbers.signed(C.GOTV_PER_UNIT)} margin`)
		has(gotv.text, `0 of {C.GOTV_MAX_UNITS}`)
		has(gotv.text, "election night")
		local pivot = Explain.action(C, view, PlanDraft.new(), "OH", "Pivot", nil)
		has(pivot.text, `{C.PIVOT_AP} AP`)
		has(pivot.text, Numbers.points(C.PIVOT_PENALTY))
	end)

	it("lists one preview per action grid button", function()
		local view = ohio()
		local list = Explain.previews(C, view, PlanDraft.new(), "OH", "Jobs")
		local names = {}
		for _, entry in list do
			table.insert(names, entry.name)
		end
		expect(table.concat(names, ",")):toBe("Rally,Fundraise,Ad,Attack,Poll,Gotv,RegionPoll,PivotButton")
	end)
end)

describe("Explain labels", function()
	it("says who a lean favors", function()
		local view = ohio()
		local s = view.states[OH]
		expect(Explain.leanText(view, s)):toBe("leans you +4")
		s.leanTo = if view.you == 1 then 2 else 1
		expect(Explain.leanText(view, s)):toBe("leans them +4")
		s.leanTo, s.lean = nil, 0
		expect(Explain.leanText(view, s)):toBe("no lean")
	end)

	it("explains momentum and its drift", function()
		local view = ohio()
		local s = view.states[OH]
		s.momentum[view.you] = 2
		local note = Explain.momentumNote(C, view, s)
		local drift = math.min(C.DRIFT_RATE * 2 * C.MOMENTUM_DECAY, C.DRIFT_CAP)
		has(note, `about {Numbers.signed(drift)} support drifts to you`)
		has(note, `{math.floor(C.MOMENTUM_DECAY * 100 + 0.5)}%`)
	end)

	it("explains backlash and the underdog tier", function()
		local view = ohio()
		local s = view.states[OH]
		expect(Explain.backlashNote(C, view, s)):toBe(nil)
		s.backlash = 1
		has(Explain.backlashNote(C, view, s) :: string, `1 of {C.BACKLASH_THRESHOLD}`)
		expect(Explain.underdogText(C, view, view.you)):toBe(nil)
		view.players[view.you].underdogTier = 1
		local text = Explain.underdogText(C, view, view.you) :: string
		has(text, "You are underdog tier 1")
		has(text, `{C.UNDERDOG_EV_1}+`)
	end)
end)

describe("Explain: debates, Choice events, election night", function()
	it("gives exact debate odds for an edge", function()
		local win, tie, lose = Explain.debateOdds(C, 0)
		local faces = C.DEBATE_ROLL_MAX + 1
		near(tie, faces / (faces * faces), "even tie")
		near(win, lose, "even is fair")
		near(win + tie + lose, 1, "odds add up")
		local win2 = Explain.debateOdds(C, 2)
		check(win2 > win, "an edge helps")
	end)

	it("splits a debate score into prep, platform, stat and roll", function()
		local view = ohio()
		local me, them = view.you, if view.you == 1 then 2 else 1
		local prep = { {}, {} } :: { { number } }
		local scores = { {}, {} } :: { { number } }
		prep[me], prep[them] = { 2, 2, 2 }, { 4, 1, 1 }
		-- Jobs is on your platform: 2 prep + 2 platform + 1 stat + roll 3.
		scores[me] = { 2 + C.DEBATE_PLATFORM_BONUS + C.DEBATE_STAT + 3, 0, 0 }
		scores[them] = { 4 + C.DEBATE_STAT + 5, 0, 0 }
		local result = {
			week = 4,
			topics = { "Jobs", "Safety", "Farms" },
			prep = prep,
			scores = scores,
			winners = {},
			national = {},
		}
		local mine = Explain.debateParts(C, view, result :: any, me, 1)
		expect(mine.roll):toBe(3)
		expect(mine.platform):toBe(C.DEBATE_PLATFORM_BONUS)
		local theirs = Explain.debateParts(C, view, result :: any, them, 1)
		expect(theirs.roll):toBe(5)
		expect(theirs.platform):toBe(0)
		local line = Explain.debateLine(C, view, result :: any, 1)
		has(line, "you 2 prep")
		has(line, "roll 3")
		has(line, "them 4 prep")
	end)

	it("states a prep topic's known score", function()
		local view = ohio()
		local line = Explain.prepLine(C, view, "Jobs", 3)
		has(
			line,
			`You: 3 prep + {C.DEBATE_PLATFORM_BONUS} platform + {C.DEBATE_STAT} stat = {3 + C.DEBATE_PLATFORM_BONUS + C.DEBATE_STAT}`
		)
		has(line, `roll 0 to {C.DEBATE_ROLL_MAX}`)
		has(line, `their hidden prep ({Candidates.profile(C, "calloway").debatePrep} points in all)`)
		local theirs = Explain.prepLine(C, view, "Safety", 0)
		has(theirs, `them: {C.DEBATE_PLATFORM_BONUS} platform`)
	end)

	it("shows every stance of a Choice event and the states it moves (D-039, D-043)", function()
		local FLAVOR = IssueMap.flavor
		local lines = Explain.choiceLines(C, FLAVOR, { id = "plant" })
		expect(#lines):toBe(3)
		has(lines[1], "A · Stand with the plant: ")
		has(lines[1], `{Numbers.signed(C.STANCE_POINTS)} in `)
		has(lines[1], `{Numbers.signed(-C.STANCE_POINTS)} in `)
		-- With no base the hedge moves nothing; in a base with the issue it costs.
		has(lines[3], "C · Call for a study: no state reacts")
		local base = { "GA", "WV" } -- GA has Jobs; West Virginia does not
		local withBase = Explain.choiceLines(C, FLAVOR, { id = "plant" }, {}, base)
		has(withBase[3], `C · Call for a study: {Numbers.signed(-C.STANCE_HEDGE_COST)} in GA`)
		expect(string.find(withBase[3], "WV", 1, true)):toBe(nil)
		-- A base doubles a side there, and the preview is the sim's own arithmetic.
		local plain = Explain.stanceEffects(C, FLAVOR, "plant", "A", {}, nil)
		local doubled = Explain.stanceEffects(C, FLAVOR, "plant", "A", {}, { "GA" })
		expect(doubled.GA):toBe(plain.GA * C.STANCE_BASE_MULT)
		has(withBase[1], Numbers.signed(plain.GA * C.STANCE_BASE_MULT))
		-- Without an event: the general rule.
		local general = Explain.choiceLines(C, nil, nil)
		expect(#general):toBe(3)
		has(general[1], Numbers.signed(C.STANCE_POINTS))
		has(general[1], `×{C.STANCE_BASE_MULT} in your home and strongholds`)
		has(general[1], `at most ±{C.STANCE_CAP} a state`)
		has(general[3], Numbers.signed(-C.STANCE_HEDGE_COST))
	end)

	it("turns a poll lead into a chance to win the state", function()
		near(Explain.leadWinChance(C, 0), 0.5, "no lead")
		local sd = math.sqrt(C.POLL_SIGMA ^ 2 + C.ELECTION_SIGMA ^ 2)
		-- One standard deviation ahead wins about 84% of the time.
		check(math.abs(Explain.leadWinChance(C, sd) - 0.8413) < 1e-3, "one sd")
		check(math.abs(Explain.leadWinChance(C, -sd) - 0.1587) < 1e-3, "one sd behind")
	end)
end)

describe("Explain.help", function()
	local REQUIRED = { "actions", "flights", "map", "ground", "polls", "debates", "events", "election" }

	it("has a short section for every concept, numbers from Config", function()
		local sections = Explain.help(C, nil)
		local byId: { [string]: any } = {}
		for _, section in sections do
			byId[section.id] = section
			check(#section.lines >= 1, `{section.id} is empty`)
		end
		for _, id in REQUIRED do
			check(byId[id] ~= nil, `no help section {id}`)
		end
		local all = {}
		for _, section in sections do
			table.insert(all, table.concat(section.lines, "\n"))
		end
		local text = table.concat(all, "\n")
		has(text, Numbers.cost(C.FLIGHT_COST))
		has(text, `0 to {C.DEBATE_ROLL_MAX}`)
		has(text, Numbers.signed(C.DEBATE_TOPIC_WIN))
		has(text, Numbers.signed(C.STANCE_POINTS))
		has(text, `{Numbers.signed(C.GOTV_PER_UNIT)}`)
	end)

	it("follows a changed Config", function()
		local changed = Config.with(C, { FLIGHT_COST = 7, DEBATE_ROLL_MAX = 9, STANCE_POINTS = 0.7 })
		local text = {}
		for _, section in Explain.help(changed, nil) do
			table.insert(text, table.concat(section.lines, "\n"))
		end
		local all = table.concat(text, "\n")
		has(all, "$7.0")
		has(all, "0 to 9")
		has(all, "+0.7")
	end)

	it("uses your candidate's numbers when there is a view", function()
		local view = ohio()
		view.players[view.you].candidate = "calloway"
		local calloway = Candidates.profile(C, "calloway")
		local text = {}
		for _, section in Explain.help(C, view) do
			table.insert(text, table.concat(section.lines, "\n"))
		end
		local all = table.concat(text, "\n")
		has(all, calloway.name)
		has(all, `{calloway.apPerWeek} AP`)
		has(all, Numbers.cost(calloway.mediaCost))
	end)
end)
