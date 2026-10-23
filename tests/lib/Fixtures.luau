--!strict
-- Shared builders for simulation specs: matches advanced to a given phase with
-- chosen candidates and platforms, and invariant checks.

local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local IssueMap = require("@sim/IssueMap")
local Issues = require("@sim/Issues")
local Match = require("@sim/Match")
local State = require("@sim/State")

local Fixtures = {}

export type Options = {
	seed: number?,
	candidates: { string }?,
	platforms: { { string } }?,
	drawnIssues: boolean?, -- keep the seed's drawn issue map instead of the fixed one
}

-- Puts a match on the fixed flavor issue map (StateData's flavor: OH has Jobs,
-- IA Farms...) with the plain ISSUE_MULT_BOTH on every issue, for specs that need
-- known top issues and round numbers. Real matches draw both (D-044).
function Fixtures.fixedIssues(match: State.MatchState): State.MatchState
	match.issueMap = IssueMap.flavor
	local mults: { [string]: number } = {}
	for _, issue in Issues.list do
		mults[issue] = Config.defaults.ISSUE_MULT_BOTH
	end
	match.platformMults = table.freeze(mults)
	return match
end

local DEFAULT_PLATFORMS = {
	{ "Jobs", "Health", "Schools" },
	{ "Environment", "Safety", "Technology" },
}

-- A two-player match that has finished Select (so it is in MapReveal).
function Fixtures.selected(options: Options?): State.MatchState
	local o: Options = options or {}
	local config = Config.defaults
	local match = Match.new(config, o.seed or 1, { "p1", "p2" })
	if not o.drawnIssues then
		Fixtures.fixedIssues(match)
	end
	local candidates = o.candidates or { "okafor", "okafor" }
	local platforms = o.platforms or DEFAULT_PLATFORMS
	local inputs = {}
	for p = 1, 2 do
		inputs[p] = { candidate = candidates[p], platform = platforms[p] }
	end
	local selected = Match.advance(config, match, inputs)
	-- Real matches never share a candidate (D-045), but the rule specs check the
	-- simultaneous-resolution symmetry (D-001) with mirrored candidates: put the
	-- asked-for candidate back on any seat the uniqueness rule moved.
	for p = 1, 2 do
		local player = selected.players[p]
		if player.candidate ~= candidates[p] then
			player.candidate = candidates[p]
			player.profile = Candidates.profile(config, candidates[p])
			player.cash = player.profile.startCash
		end
	end
	return selected
end

-- A two-player match at week 1 Plan, drafted with default (auto-filled) picks.
function Fixtures.campaign(options: Options?): State.MatchState
	local config = Config.defaults
	local match = Fixtures.selected(options)
	while match.phase ~= "Plan" do
		match = Match.advance(config, match, {})
	end
	return match
end

-- Advances until `phase` (and, if given, `week`) is reached, with default inputs.
function Fixtures.advanceTo(match: State.MatchState, phase: State.Phase, week: number?): State.MatchState
	local config = Config.defaults
	local guard = 0
	while not (match.phase == phase and (week == nil or match.week == week)) do
		match = Match.advance(config, match, {})
		guard += 1
		assert(guard < 100, `never reached {phase}`)
	end
	return match
end

-- Errors unless every state's shares are in [0, 100] and sum to 100.
function Fixtures.checkSupport(match: State.MatchState)
	for _, s in match.states do
		local total = s.undecided
		assert(s.undecided >= -1e-9 and s.undecided <= 100 + 1e-9, `{s.id} undecided out of range`)
		for _, value in s.support do
			assert(value >= -1e-9 and value <= 100 + 1e-9, `{s.id} support out of range`)
			total += value
		end
		assert(math.abs(total - 100) < 1e-6, `{s.id} shares sum to {total}`)
	end
end

return Fixtures
