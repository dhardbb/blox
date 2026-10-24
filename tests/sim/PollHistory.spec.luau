--!strict
-- MatchState.pollHistory (D-073): the projected votes each time the weekly
-- public polls came out (week 0 after the draft, week w at the end of week w),
-- kept for the end screen's week-by-week chart and shown in the View only from
-- election night on.

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local Match = require("@sim/Match")
local Polls = require("@sim/Polls")
local State = require("@sim/State")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

-- Plays a whole match on default inputs; `visit` sees every state after a step.
local function play(
	seed: number,
	visit: ((before: State.MatchState, after: State.MatchState) -> ())?
): State.MatchState
	local match = Match.new(C, seed, { "a", "b" })
	while match.phase ~= "Done" do
		local after = Match.advance(C, match, {})
		if visit then
			visit(match, after)
		end
		match = after
	end
	return match
end

describe("Poll history", function()
	it("starts empty", function()
		expect(#Match.new(C, 1, { "a", "b" }).pollHistory):toBe(0)
	end)

	it("keeps one point per published week: the draft's polls, then every week's end", function()
		local match = play(7)
		expect(#match.pollHistory):toBe(C.WEEKS + 1)
		for k, point in match.pollHistory do
			expect(point.week):toBe(k - 1)
			expect(#point.ev):toBe(2)
		end
	end)

	it("records the projection on the polls just published, and only then", function()
		play(11, function(before, after)
			local added = #after.pollHistory - #before.pollHistory
			local published = (before.phase == "Draft" and after.phase ~= "Draft") or before.phase == "Plan"
			expect(added):toBe(if published then 1 else 0)
			if published then
				local point = after.pollHistory[#after.pollHistory]
				expect(point.week):toBe(before.week)
				expect(point.ev):toEqual(Polls.projectedEV(after))
			end
		end)
	end)

	it("ends on the final polls the View shows on election night", function()
		local match = play(19)
		local last = match.pollHistory[#match.pollHistory]
		expect(last.week):toBe(C.WEEKS)
		expect(last.ev):toEqual(View.build(C, match, 1).projectedEV)
	end)

	it("is the same for the same seed and inputs", function()
		expect(play(23).pollHistory):toEqual(play(23).pollHistory)
	end)

	it("is in the View from election night on, the same for every player", function()
		local match = Match.new(C, 31, { "a", "b" })
		while match.phase ~= "Done" do
			local over = match.phase == "Election"
			for p = 1, 2 do
				local view = View.build(C, match, p)
				if over then
					expect(view.pollHistory):toEqual(match.pollHistory)
				else
					expect(view.pollHistory):toBe(nil)
				end
			end
			match = Match.advance(C, match, {})
		end
		expect(View.build(C, match, 1).pollHistory):toEqual(View.build(C, match, 2).pollHistory)
		expect(#(View.build(C, match, 2).pollHistory :: { State.PollPoint })):toBe(C.WEEKS + 1)
	end)

	it("handles more than two players", function()
		local match = Match.new(C, 5, { "a", "b", "c" })
		while match.phase ~= "Done" do
			match = Match.advance(C, match, {})
		end
		for _, point in match.pollHistory do
			expect(#point.ev):toBe(3)
		end
	end)
end)
