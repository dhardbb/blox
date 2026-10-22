--!strict
-- Public polls (AR(1) error, D-002), projected EV, and the underdog rubber band (D-006).

local Test = require("@testlib/Test")
local Fixtures = require("@testlib/Fixtures")
local Config = require("@sim/Config")
local Polls = require("@sim/Polls")
local State = require("@sim/State")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

describe("Public polls", function()
	it("shares are whole numbers that sum to 100", function()
		local match = Fixtures.campaign({ seed = 4 })
		for _, s in match.states do
			local poll = s.poll :: State.Poll
			local total = poll.undecided
			for _, share in poll.support do
				expect(share == math.floor(share) and share >= 0):toBe(true)
				total += share
			end
			expect(total):toBe(100)
			expect(poll.undecided >= 0):toBe(true)
		end
	end)

	it("margin error has sd about 3 and carries about 70% week to week", function()
		local current: { number } = {}
		local previous: { number } = {}
		for seed = 1, 40 do
			local match = Fixtures.campaign({ seed = seed })
			local last: { number } = {}
			for week = 1, 12 do
				match.week = week
				Polls.update(C, match, false)
				for i, s in match.states do
					local e = s.pollError[1] - s.pollError[2]
					if week > 1 then
						table.insert(previous, last[i])
						table.insert(current, e)
					end
					last[i] = e
				end
			end
		end
		local n = #current
		local sx, sy, sxx, syy, sxy = 0, 0, 0, 0, 0
		for k = 1, n do
			local x, y = previous[k], current[k]
			sx += x
			sy += y
			sxx += x * x
			syy += y * y
			sxy += x * y
		end
		local sd = math.sqrt(syy / n - (sy / n) ^ 2)
		local r = (sxy / n - sx * sy / n / n) / math.sqrt((sxx / n - (sx / n) ^ 2) * (syy / n - (sy / n) ^ 2))
		expect(math.abs(sd - C.POLL_SIGMA) < 0.15):toBe(true)
		expect(math.abs(r - C.POLL_RHO) < 0.04):toBe(true)
	end)

	it("errors are zero-sum across players", function()
		local match = Fixtures.campaign({ seed = 6 })
		for _, s in match.states do
			expect(s.pollError[1] + s.pollError[2]):toBeCloseTo(0, 1e-9)
		end
	end)

	it("projected EV counts poll leaders and skips ties", function()
		local match = Fixtures.campaign({ seed = 6 })
		for _, s in match.states do
			s.poll = { support = { 40, 40 }, undecided = 20 }
		end
		expect(Polls.projectedEV(match)):toEqual({ 0, 0 })
		State.get(match, "CA").poll = { support = { 45, 40 }, undecided = 15 }
		State.get(match, "TX").poll = { support = { 40, 45 }, undecided = 15 }
		expect(Polls.projectedEV(match)):toEqual({ 54, 40 })
	end)
end)

describe("Underdog rubber band", function()
	-- Sets every poll so player 2 leads everywhere (gap 538), or a dead heat (gap 0).
	local function setPolls(match: State.MatchState, sweep: boolean)
		for _, s in match.states do
			s.poll =
				{ support = if sweep then { 40, 45 } else { 40, 40 }, undecided = if sweep then 15 else 20 }
		end
	end

	it("switches on at the threshold and off only 30 EV below it", function()
		expect(C.UNDERDOG_SMOOTHING):toBe(0.4)
		expect(C.UNDERDOG_HYSTERESIS):toBe(30)
		local match = Fixtures.campaign({ seed = 6 })
		local trailer = match.players[1]
		trailer.lead, trailer.underdogTier = nil, 0
		setPolls(match, true)
		Polls.updateUnderdog(C, match)
		expect(trailer.lead):toBe(-538)
		expect(trailer.underdogTier):toBe(2)
		expect(match.players[2].underdogTier):toBe(0)

		-- Dead-heat polls keep 60% of the smoothed gap each week (D-020):
		-- 322.8, 193.7, 116.2, 69.7, 41.8, 25.1, 15.1, 9.0. Tier 2 holds down to 70,
		-- tier 1 down to 10.
		setPolls(match, false)
		local tiers = {}
		for _ = 1, 8 do
			Polls.updateUnderdog(C, match)
			table.insert(tiers, trailer.underdogTier)
		end
		expect(tiers):toEqual({ 2, 2, 2, 1, 1, 1, 1, 0 })
	end)

	it("hysteresis holds a tier just under its threshold", function()
		local match = Fixtures.campaign({ seed = 6 })
		local player = match.players[1]
		setPolls(match, false)
		player.lead, player.underdogTier = -90, 2 -- smooths to a 54 gap: under 70, so tier 1
		Polls.updateUnderdog(C, match)
		expect(player.underdogTier):toBe(1)
		player.lead, player.underdogTier = -130, 2 -- smooths to 78: still >= 70, stays tier 2
		Polls.updateUnderdog(C, match)
		expect(player.underdogTier):toBe(2)
		player.lead, player.underdogTier = -60, 0 -- smooths to 36: below 40, tier 0 stays off
		Polls.updateUnderdog(C, match)
		expect(player.underdogTier):toBe(0)
		player.lead, player.underdogTier = -60, 1 -- 36 is under 40 but over 10: tier 1 holds
		Polls.updateUnderdog(C, match)
		expect(player.underdogTier):toBe(1)
	end)

	it("multipliers by tier, doubled bonus for Tomas", function()
		local match = Fixtures.campaign({ seed = 6, candidates = { "reyes", "okafor" } })
		match.players[1].underdogTier = 1
		match.players[2].underdogTier = 2
		local rally1, fund1 = Polls.underdogMults(C, match, 1)
		expect(rally1):toBeCloseTo(1 + (C.UNDERDOG_RALLY_1 - 1) * 2)
		expect(fund1):toBeCloseTo(1 + (C.UNDERDOG_FUND_1 - 1) * 2)
		local rally2, fund2 = Polls.underdogMults(C, match, 2)
		expect(rally2):toBe(C.UNDERDOG_RALLY_2)
		expect(fund2):toBe(C.UNDERDOG_FUND_2)
	end)

	it("Tomas's frontrunner drawback turns on when leading by 40+", function()
		local match = Fixtures.campaign({ seed = 6, candidates = { "reyes", "okafor" } })
		setPolls(match, true)
		Polls.updateUnderdog(C, match)
		expect(match.players[1].frontrunner):toBe(false)
		for _, s in match.states do
			s.poll = { support = { 45, 40 }, undecided = 15 }
		end
		for _ = 1, 3 do
			Polls.updateUnderdog(C, match)
		end
		expect(match.players[1].frontrunner):toBe(true)
		expect(match.players[2].frontrunner):toBe(false) -- Dana has no such drawback
	end)
end)
