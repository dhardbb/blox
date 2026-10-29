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

	-- Player 2 leads the smallest states in the public polls until its lead is
	-- at least `target` EV; every other state is a dead heat (counts for nobody).
	-- Returns player 1's projected deficit.
	local function setGap(match: State.MatchState, target: number): number
		local order = table.clone(match.states)
		table.sort(order, function(a, b)
			return if a.ev == b.ev then a.id < b.id else a.ev < b.ev
		end)
		local gap = 0
		for _, s in order do
			if gap < target then
				s.poll = { support = { 40, 45 }, undecided = 15 }
				gap += s.ev
			else
				s.poll = { support = { 40, 40 }, undecided = 20 }
			end
		end
		return gap
	end

	it("switches on from the smoothed gap, with hysteresis between tiers", function()
		expect(C.UNDERDOG_SMOOTHING):toBe(0.35)
		expect(C.UNDERDOG_HYSTERESIS):toBe(30)
		local match = Fixtures.campaign({ seed = 6 })
		local trailer = match.players[1]
		trailer.lead, trailer.underdogLead, trailer.underdogTier = nil, nil, 0
		setPolls(match, true)
		Polls.updateUnderdog(C, match)
		expect(trailer.underdogLead):toBe(-538)
		expect(trailer.lead):toBe(-538)
		expect(trailer.underdogTier):toBe(2)
		expect(match.players[2].underdogTier):toBe(0)

		-- A trailer the latest polls still put 10+ EV behind keeps a smoothed gap:
		-- 65% of last week's plus 35% of this week's.
		local g = setGap(match, 20)
		expect(g >= 20 and g < 40):toBe(true)
		local expected = -538
		local tiers = {}
		for _ = 1, 6 do
			Polls.updateUnderdog(C, match)
			expected = 0.35 * -g + 0.65 * expected
			expect(trailer.underdogLead):toBeCloseTo(expected)
			table.insert(tiers, trailer.underdogTier)
		end
		-- 538 smooths down past 100 and 70 (tier 2 holds to 70), then sits in tier 1.
		local want = {}
		local e = -538
		local tier = 2
		for _ = 1, 6 do
			e = 0.35 * -g + 0.65 * e
			if -e >= C.UNDERDOG_EV_2 or (tier == 2 and -e >= C.UNDERDOG_EV_2 - 30) then
				tier = 2
			else
				tier = 1
			end
			table.insert(want, tier)
		end
		expect(tiers):toEqual(want)
		expect(tiers[1]):toBe(2)
		expect(tiers[6]):toBe(1)
	end)

	it("ends the week the latest polls clear it, then has to build up again (D-096)", function()
		local match = Fixtures.campaign({ seed = 6 })
		local trailer = match.players[1]
		trailer.lead, trailer.underdogLead, trailer.underdogTier = nil, nil, 0
		setPolls(match, true)
		Polls.updateUnderdog(C, match)
		expect(trailer.underdogTier):toBe(2)

		-- A dead heat: within 10 EV of level, so the tier ends at once and its
		-- smoothed lead restarts from the polls; the plain lead still smooths.
		setPolls(match, false)
		Polls.updateUnderdog(C, match)
		expect(trailer.underdogTier):toBe(0)
		expect(trailer.underdogLead):toBe(0)
		expect(trailer.lead):toBeCloseTo(0.65 * -538)

		-- One bad week 40+ behind does not switch it back on: it smooths up from 0.
		local g = setGap(match, 45)
		Polls.updateUnderdog(C, match)
		expect(trailer.underdogLead):toBeCloseTo(0.35 * -g)
		expect(trailer.underdogTier):toBe(0)

		-- Leading also clears it at once.
		trailer.underdogLead, trailer.underdogTier = -200, 2
		for _, s in match.states do
			s.poll = { support = { 45, 40 }, undecided = 15 }
		end
		Polls.updateUnderdog(C, match)
		expect(trailer.underdogTier):toBe(0)
		expect(trailer.underdogLead):toBe(538)
	end)

	it("the clear line is the tier-1 exit line: just over 10 EV behind still smooths", function()
		local match = Fixtures.campaign({ seed = 6 })
		local player = match.players[1]
		local g = setGap(match, 11)
		expect(g > C.UNDERDOG_EV_1 - C.UNDERDOG_HYSTERESIS):toBe(true)
		player.underdogLead, player.underdogTier = -90, 2
		Polls.updateUnderdog(C, match)
		local smoothed = 0.35 * -g + 0.65 * -90
		expect(player.underdogLead):toBeCloseTo(smoothed)
		expect(player.underdogTier):toBe(if -smoothed >= 70 then 2 else 1)
		expect(g <= 20):toBe(true)
		player.underdogLead, player.underdogTier = -50, 0 -- under 40 smoothed: tier 0 stays off
		Polls.updateUnderdog(C, match)
		expect(player.underdogTier):toBe(0)
		player.underdogLead, player.underdogTier = -50, 1 -- over 10 smoothed: tier 1 holds
		Polls.updateUnderdog(C, match)
		expect(player.underdogTier):toBe(1)
	end)

	it("reads public polls only: true support changes nothing", function()
		local match = Fixtures.campaign({ seed = 6 })
		setGap(match, 60)
		local copy = table.clone(match.players[1])
		for _, s in match.states do
			s.support = { 70, 10 }
		end
		Polls.updateUnderdog(C, match)
		local tierA, leadA = match.players[1].underdogTier, match.players[1].underdogLead
		match.players[1] = copy
		for _, s in match.states do
			s.support = { 10, 70 }
		end
		Polls.updateUnderdog(C, match)
		expect(match.players[1].underdogTier):toBe(tierA)
		expect(match.players[1].underdogLead):toBe(leadA)
	end)

	it("multipliers by tier, doubled bonus for Dash", function()
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

	it("Dash's frontrunner drawback turns on when leading by 40+", function()
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
		expect(match.players[2].frontrunner):toBe(false) -- Goldie has no such drawback
	end)
end)
