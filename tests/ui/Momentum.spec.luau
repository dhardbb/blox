--!strict
-- Momentum drift, explained the way the sim runs it (playtest 2, bug 4: the
-- text said "the leader gains 0.6 support per point of lead" and testers
-- measured about half, because momentum decays before it is counted). Every
-- number here is measured by running a real week of the sim, never typed in.

local Config = require("@sim/Config")
local Explain = require("@ui/Explain")
local Format = require("@shared/DebugUI/Format")
local Fixtures = require("@testlib/Fixtures")
local Match = require("@sim/Match")
local Numbers = require("@ui/Numbers")
local State = require("@sim/State")
local Test = require("@testlib/Test")
local UIFixtures = require("@ui/Fixtures")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local SAME = { { "Jobs", "Health", "Schools" }, { "Jobs", "Health", "Schools" } }
local LEAD = 4 -- momentum lead of player 1 in Ohio before the week

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function has(text: string, part: string)
	check(string.find(text, part, 1, true) ~= nil, `"{text}" lacks "{part}"`)
end

-- A clean week-1 match (as in Resolve.spec): every state 35/35/30, no lean,
-- momentum, ownership or rubber band; then Ohio gets a momentum lead.
local function clean(candidates: { string }): State.MatchState
	local match = Fixtures.campaign({ seed = 21, candidates = candidates, platforms = SAME })
	for _, s in match.states do
		s.support = { 35, 35 }
		s.undecided = 30
		s.lean, s.leanTo = 0, nil
		s.battleground, s.owner, s.isHome = false, nil, false
		s.momentum = { 0, 0 }
		s.pool = s.capacity
	end
	for _, player in match.players do
		player.location = "OH"
		player.cash = 50
		player.underdogTier = 0
		player.frontrunner = false
	end
	State.get(match, "OH").momentum = { LEAD, 0 }
	return match
end

-- The support player 1 gains in Ohio from one week with no campaigning: drift only.
local function measuredDrift(match: State.MatchState): number
	local before = State.get(match, "OH").support[1]
	local after = Match.advance(C, match, { { actions = {} }, { actions = {} } })
	return State.get(after, "OH").support[1] - before
end

-- "0.3", "0.15": the per-point rate as the text prints it.
local function rateText(value: number): string
	local text = string.format("%.2f", value)
	text = string.gsub(text, "0$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

describe("Momentum drift text matches the sim (playtest 2, bug 4)", function()
	for _, candidate in { "hale", "reyes" } do
		it(`{candidate}: the state note predicts the drift a real week gives`, function()
			local match = clean({ candidate, "hale" })
			local view = View.build(C, match, 1)
			local s = view.states[State.indexOf.OH]
			local drift = measuredDrift(match)
			check(drift > 0, "no drift measured")
			check(drift < C.DRIFT_RATE * LEAD - 1e-6, "drift is not smaller than rate x shown lead")
			local note = Explain.momentumNote(C, view, s)
			has(note, `about {Numbers.signed(drift)} support drifts to you next week`)
			has(note, `about {rateText(drift / LEAD)} support next week per point of momentum lead shown now`)
			expect(Explain.driftPerPoint(C, view)):toBeCloseTo(drift / LEAD)
		end)
	end

	it("help, the board and the state note all state the measured rate", function()
		local match = clean({ "hale", "hale" })
		local drift = measuredDrift(match)
		local per = `about {rateText(drift / LEAD)} support next week per point of momentum lead shown now`
		local view = View.build(C, match, 1)
		local rule = Explain.driftRule(C, view)
		has(rule, per)
		local helpText = {}
		for _, section in Explain.help(C, view) do
			table.insert(helpText, table.concat(section.lines, "\n"))
		end
		has(table.concat(helpText, "\n"), rule)
		has(table.concat(Explain.help(C, nil)[3].lines, "\n"), Explain.driftRule(C, nil))
		local payload = UIFixtures.payload(C, "Plan")
		local board = Format.board(payload, 0)
		has(board, Explain.driftRule(C, payload.view))
		-- The old wording, which read as the whole drift, is gone everywhere.
		local old = `gains {Explain.num(C.DRIFT_RATE)} support per point of lead`
		for _, text in { rule, table.concat(helpText, "\n"), board } do
			check(string.find(text, old, 1, true) == nil, `still says "{old}"`)
		end
	end)
end)
