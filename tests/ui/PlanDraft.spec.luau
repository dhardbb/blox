--!strict
-- The plan-draft helpers the redesigned campaign screen adds (UI overhaul WP3):
-- the message chips, a state's region for the Region poll, and the short plan
-- problem on a disabled Lock in. Pure: no fake engine.

local Config = require("@sim/Config")
local Fixtures = require("@ui/Fixtures")
local Issues = require("@sim/Issues")
local Plan = require("@sim/Plan")
local PlanDraft = require("@ui/PlanDraft")
local Resolve = require("@sim/Resolve")
local StateData = require("@sim/StateData")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

describe("PlanDraft.messageChoices", function()
	local view = Fixtures.payload(C, "Plan").view
	local platform = view.players[view.you].platform :: { string }

	it("offers at most five chips, best first, with no repeats", function()
		for _, record in StateData.list do
			local choices = PlanDraft.messageChoices(C, view, record.id)
			check(#choices >= 1 and #choices <= PlanDraft.MESSAGE_CHOICES, `{record.id}: {#choices} chips`)
			local best, bestMult = PlanDraft.bestIssue(C, view, record.id)
			expect(choices[1].issue):toBe(best)
			expect(choices[1].mult):toBe(bestMult)
			local seen: { [string]: boolean } = {}
			for k, choice in choices do
				check(not seen[choice.issue], `{record.id}: {choice.issue} twice`)
				seen[choice.issue] = true
				if k > 1 then
					check(choice.mult <= choices[k - 1].mult + 1e-9, `{record.id}: not sorted by multiplier`)
				end
				local mult = Resolve.issueMult(C, platform :: any, record.issues, choice.issue)
				expect(choice.mult):toBe(mult)
			end
		end
	end)

	it("covers the state's top issues and the platform", function()
		for _, record in StateData.list do
			local choices = PlanDraft.messageChoices(C, view, record.id)
			local offered: { [string]: boolean } = {}
			for _, choice in choices do
				offered[choice.issue] = true
			end
			local wanted = 0
			local pool: { [string]: boolean } = {}
			for _, issue in record.issues do
				pool[issue] = true
			end
			for _, issue in platform do
				pool[issue] = true
			end
			for _ in pool do
				wanted += 1
			end
			if wanted <= PlanDraft.MESSAGE_CHOICES - 1 then
				for issue in pool do
					check(offered[issue] == true, `{record.id}: {issue} is not offered`)
				end
			end
			for _, choice in choices do
				local best = PlanDraft.bestIssue(C, view, record.id)
				check(
					pool[choice.issue] == true or choice.issue == best,
					`{record.id}: {choice.issue} is neither a top issue nor on the platform`
				)
			end
		end
	end)
end)

describe("PlanDraft.regionOf", function()
	it("names every state's region and nothing for an unknown id", function()
		for _, record in StateData.list do
			expect(PlanDraft.regionOf(record.id)):toBe(record.region)
			check(Issues.regionName[record.region] ~= nil, `{record.id} has no region name`)
		end
		expect(PlanDraft.regionOf("ZZ")):toBe(nil)
	end)
end)

describe("PlanDraft.shortProblem", function()
	it("says what is wrong in a few words, with a fallback", function()
		expect(PlanDraft.shortProblem(Plan.Reason.NotEnoughMoney)):toBe("Not enough money")
		expect(PlanDraft.shortProblem(Plan.Reason.NotEnoughAP)):toBe("Not enough AP")
		expect(PlanDraft.shortProblem(nil)):toBe("Fix your plan")
		expect(PlanDraft.shortProblem("Brand new")):toBe("Fix your plan")
		for _, reason in Plan.Reason do
			check(#PlanDraft.shortProblem(reason) <= 26, `{reason}: too long for the button`)
		end
	end)
end)
