--!strict
-- Money and points as text (playtest 1, bugs 1, 3 and 4). Money never rounds up:
-- a player with $4.96 sees "$4.9", because a $5 plan is rejected. Points round to
-- one decimal and signed numbers never read "+-0.2" or "-0.0".

local Config = require("@sim/Config")
local Fixtures = require("@ui/Fixtures")
local Format = require("@shared/DebugUI/Format")
local Numbers = require("@ui/Numbers")
local Plan = require("@sim/Plan")
local PlanDraft = require("@ui/PlanDraft")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

describe("Numbers.money", function()
	it("floors to the shown precision, never rounding up", function()
		expect(Numbers.money(4.96)):toBe("$4.9")
		expect(Numbers.money(4.99999)):toBe("$4.9")
		expect(Numbers.money(5)):toBe("$5.0")
		expect(Numbers.money(13.550725999999997)):toBe("$13.5")
		expect(Numbers.money(0)):toBe("$0.0")
		expect(Numbers.money(-0.04)):toBe("-$0.1")
	end)

	it("treats float noise just under a value like the validator does", function()
		-- Plan.validate accepts a plan within 1e-9 of the cash; so does the display.
		expect(Numbers.money(5 - 1e-12)):toBe("$5.0")
		expect(Numbers.money(0.1 + 0.2)):toBe("$0.3")
	end)

	it("never shows more money than a plan may spend", function()
		local payload = Fixtures.payload(C, "Plan")
		local view = payload.view
		local me = view.players[view.you]
		for _, cash in { 4.96, 4.949, 5.04, 2.999, 7.95 } do
			me.cash = cash
			local shown = tonumber(string.match(Numbers.money(cash), "%$([%d%.]+)")) :: number
			expect(shown <= cash + 1e-9):toBe(true)
			-- A plan that costs exactly the shown amount passes the preview check.
			local polls = math.floor(shown / C.REGION_POLL_COST)
			local draft = PlanDraft.new()
			for _ = 1, polls do
				PlanDraft.add(draft, { kind = "RegionPoll", region = "Pacific" })
			end
			local cost = PlanDraft.cost(C, view, draft)
			if cost.cash <= shown then
				expect(PlanDraft.problem(C, view, draft) ~= Plan.Reason.NotEnoughMoney):toBe(true)
			end
		end
	end)
end)

describe("Numbers.points and Numbers.signed", function()
	it("rounds points to one decimal", function()
		expect(Numbers.points(11.585209076704801)):toBe("11.6")
		expect(Numbers.points(-0.04)):toBe("0.0")
		expect(Numbers.points(3)):toBe("3.0")
	end)

	it("signs numbers once, and never says -0.0", function()
		expect(Numbers.signed(-0.2)):toBe("-0.2")
		expect(Numbers.signed(0.4)):toBe("+0.4")
		expect(Numbers.signed(0)):toBe("+0.0")
		expect(Numbers.signed(-0.01)):toBe("+0.0")
	end)
end)

describe("debug UI money", function()
	it("shows fractional cash floored in the status line and on the board", function()
		local payload = Fixtures.payload(C, "Plan")
		payload.view.players[payload.you].cash = 4.96
		local status = Format.status(payload, nil, 0)
		expect(has(status, "$4.9")):toBe(true)
		expect(has(status, "$5.0")):toBe(false)
		local board = Format.board(payload, 0)
		expect(has(board, "$4.9")):toBe(true)
		expect(has(board, "$5.0")):toBe(false)
	end)

	it("floors last week's fundraising total too", function()
		local payload = Fixtures.payload(C, "Plan")
		payload.view.raised = 13.550725999999997
		local board = Format.board(payload, 0)
		expect(has(board, "You raised $13.5 last week")):toBe(true)
	end)
end)
