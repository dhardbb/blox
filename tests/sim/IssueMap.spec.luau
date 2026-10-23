--!strict
-- The per-match issue map (D-044): drawn from the seed, balanced, public from
-- Select, and niche issues hit harder.

local Config = require("@sim/Config")
local IssueMap = require("@sim/IssueMap")
local Issues = require("@sim/Issues")
local Match = require("@sim/Match")
local Rng = require("@sim/Rng")
local StateData = require("@sim/StateData")
local Test = require("@testlib/Test")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local MEAN = 538 * 2 / #Issues.list

local function draw(seed: number): IssueMap.IssueMap
	return IssueMap.draw(C, Rng.fork(Rng.new(seed), "issues"))
end

describe("IssueMap", function()
	it("gives every state two different valid issues", function()
		for seed = 1, 50 do
			local map = draw(seed)
			expect(#map):toBe(#StateData.list)
			for i, issues in map do
				expect(#issues):toBe(2)
				expect(Issues.isIssue(issues[1]) and Issues.isIssue(issues[2])):toBe(true)
				if issues[1] == issues[2] then
					error(`seed {seed}: {StateData.list[i].id} repeats an issue`)
				end
			end
		end
	end)

	it("is the same for the same seed and differs between seeds", function()
		expect(draw(7)):toEqual(draw(7))
		local differs = 0
		for seed = 1, 20 do
			if not Test.deepEqual(draw(seed), draw(seed + 1)) then
				differs += 1
			end
		end
		expect(differs):toBe(20)
		local match = Match.new(C, 7, { "a", "b" })
		expect(match.issueMap):toEqual(draw(7))
	end)

	it("keeps every issue inside the EV band and the state-count limits, every time", function()
		local lo, hi = MEAN * (1 - C.ISSUE_EV_BAND), MEAN * (1 + C.ISSUE_EV_BAND)
		for seed = 1, 300 do
			local map = draw(seed)
			local ev = IssueMap.evByIssue(map)
			local count = IssueMap.statesByIssue(map)
			for _, issue in Issues.list do
				if ev[issue] < lo or ev[issue] > hi then
					error(`seed {seed}: {issue} covers {ev[issue]} EV`)
				end
				if count[issue] < C.ISSUE_MIN_STATES or count[issue] > C.ISSUE_MAX_STATES then
					error(`seed {seed}: {issue} tops {count[issue]} states`)
				end
			end
		end
	end)

	it("changes which issues carry the most EV from match to match", function()
		local leaders: { [string]: number } = {}
		for seed = 1, 200 do
			local top = IssueMap.ranked(draw(seed))[1]
			leaders[top] = (leaders[top] or 0) + 1
		end
		for _, issue in Issues.list do
			-- Every issue leads sometimes; none leads most matches.
			local n = leaders[issue] or 0
			if n < 5 or n > 60 then
				error(`{issue} leads {n} of 200 maps`)
			end
		end
	end)

	it("keeps some regional flavor without letting it decide", function()
		local kept, slots = 0, 0
		for seed = 1, 100 do
			for i, issues in draw(seed) do
				for _, issue in issues do
					slots += 1
					if table.find(StateData.list[i].flavor, issue) then
						kept += 1
					end
				end
			end
		end
		-- Uniform would keep 2 of 8 = 25%.
		local share = kept / slots
		expect(share > 0.3 and share < 0.6):toBe(true)
	end)

	it("makes niche issues hit harder: the bonus grows as the issue's EV shrinks", function()
		local bonus = C.ISSUE_MULT_BOTH - C.ISSUE_MULT_STATE
		for seed = 1, 50 do
			local map = draw(seed)
			local ev = IssueMap.evByIssue(map)
			local mults = IssueMap.platformMults(C, map)
			for _, issue in Issues.list do
				local want = C.ISSUE_MULT_STATE + bonus * (MEAN / ev[issue]) ^ C.ISSUE_NICHE_POWER
				expect(mults[issue]):toBeCloseTo(math.min(C.ISSUE_NICHE_MAX, want), 0.005)
				expect(mults[issue] > C.ISSUE_MULT_STATE):toBe(true)
			end
			for _, a in Issues.list do
				for _, b in Issues.list do
					if ev[a] < ev[b] then
						expect(mults[a] >= mults[b]):toBe(true)
					end
				end
			end
		end
		-- An issue at the mean EV gets the plain ISSUE_MULT_BOTH.
		expect(C.ISSUE_MULT_STATE + bonus * (MEAN / MEAN) ^ C.ISSUE_NICHE_POWER):toBe(C.ISSUE_MULT_BOTH)
	end)

	it("is public from Select on, with the multipliers", function()
		local match = Match.new(C, 3, { "a", "b" })
		local view = View.build(C, match, 2)
		expect(view.phase):toBe("Select")
		expect(view.issueMap):toEqual(match.issueMap)
		expect(view.platformMults):toEqual(match.platformMults)
	end)
end)
