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
		for i, record in StateData.list do
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
				local mult =
					Resolve.issueMult(C, platform :: any, view.issueMap[i], choice.issue, view.platformMults)
				expect(choice.mult):toBe(mult)
			end
		end
	end)

	it("covers the state's top issues and the platform", function()
		for i, record in StateData.list do
			local choices = PlanDraft.messageChoices(C, view, record.id)
			local offered: { [string]: boolean } = {}
			for _, choice in choices do
				offered[choice.issue] = true
			end
			local wanted = 0
			local pool: { [string]: boolean } = {}
			for _, issue in view.issueMap[i] do
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

-- A state that is neither the candidate's location nor adjacent to it (a flight).
local function farFrom(location: string?): string
	for _, record in StateData.list do
		if record.id ~= location and not Plan.isAdjacent(location, record.id) then
			return record.id
		end
	end
	error("no far state")
end

describe("PlanDraft.moneyText (playtest 1, bug 2)", function()
	it("says what the plan costs, what you have, and which items cost money", function()
		local view = Fixtures.payload(C, "Plan").view
		local me = view.players[view.you]
		local profile = PlanDraft.profile(C, view)
		me.cash = 4.96
		local far = farFrom(me.location)
		local draft = PlanDraft.new()
		PlanDraft.add(draft, { kind = "Rally", state = far, issue = "Jobs" })
		PlanDraft.add(draft, { kind = "Media", state = far, issue = "Jobs" })
		PlanDraft.add(draft, { kind = "RegionPoll", region = "Pacific" })
		expect(PlanDraft.problem(C, view, draft)):toBe(Plan.Reason.NotEnoughMoney)
		local total = C.FLIGHT_COST + profile.mediaCost + C.REGION_POLL_COST
		expect(PlanDraft.moneyText(C, view, draft)):toBe(
			string.format(
				"Plan costs $%.1f, you have $4.9 (1 flight $%.1f, 1 ad $%.1f, 1 region poll $%.1f).",
				total,
				C.FLIGHT_COST,
				profile.mediaCost,
				C.REGION_POLL_COST
			)
		)
	end)

	it("lists items that add up to the plan's cost, free polls left out", function()
		local view = Fixtures.payload(C, "Plan").view
		local me = view.players[view.you]
		local profile = PlanDraft.profile(C, view)
		local far = farFrom(me.location)
		local draft = PlanDraft.new()
		PlanDraft.add(draft, { kind = "Fundraise", state = far })
		PlanDraft.add(draft, { kind = "Rally", state = farFrom(far), issue = "Jobs" })
		PlanDraft.add(draft, { kind = "Attack", state = far, issue = "Jobs" })
		PlanDraft.add(draft, { kind = "Gotv", state = far, units = 2 })
		for k = 1, profile.freePolls + 2 do
			PlanDraft.add(draft, { kind = "Poll", state = StateData.list[k].id })
		end
		local sum = 0
		for _, item in PlanDraft.costItems(C, view, draft) do
			sum += item.amount
		end
		expect(math.abs(sum - PlanDraft.cost(C, view, draft).cash) < 1e-9):toBe(true)
		local text = PlanDraft.moneyText(C, view, draft)
		check(string.find(text, "2 polls", 1, true) ~= nil, text)
		check(string.find(text, "1 attack ad", 1, true) ~= nil, text)
		check(string.find(text, "2 ground game", 1, true) ~= nil, text)
	end)
end)
