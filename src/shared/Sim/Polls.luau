--!strict
-- Public polls, projected EV, the underdog rubber band, and internal polls.
--
-- Public poll error is AR(1) per state (D-002): e_t = rho e_{t-1} + sqrt(1 - rho^2) z_t.
-- Each player's share carries a zero-sum error component with sd POLL_SIGMA / sqrt(2),
-- so in 1v1 the margin error has sd POLL_SIGMA; undecided has its own error term.

local ConfigModule = require("./Config")
local Rng = require("./Rng")
local State = require("./State")

type Config = ConfigModule.Config
type MatchState = State.MatchState
type StateSim = State.StateSim

local Polls = {}

local SQRT_HALF = math.sqrt(0.5)

-- Advances one state's persistent error. `first` draws from the stationary
-- distribution instead of carrying anything over.
local function stepError(config: Config, rng: Rng.Rng, s: StateSim, first: boolean)
	local n = #s.support
	local carry = if first then 0 else config.POLL_RHO
	local fresh = if first then 1 else math.sqrt(1 - config.POLL_RHO * config.POLL_RHO)
	local draws = table.create(n, 0)
	local mean = 0
	for p = 1, n do
		draws[p] = Rng.gaussian(rng, 0, config.POLL_SIGMA * SQRT_HALF)
		mean += draws[p] / n
	end
	for p = 1, n do
		s.pollError[p] = carry * s.pollError[p] + fresh * (draws[p] - mean)
	end
	s.pollErrorUndecided = carry * s.pollErrorUndecided + fresh * Rng.gaussian(rng, 0, config.POLL_SIGMA)
end

-- Whole-number shares that sum to 100 from noisy raw values.
local function roundShares(raw: { number }, rawUndecided: number): State.Poll
	local n = #raw
	local total = rawUndecided
	for p = 1, n do
		raw[p] = math.max(0, raw[p])
		total += raw[p]
	end
	rawUndecided = math.max(0, rawUndecided)
	total = math.max(total, 1e-9)
	local support = table.create(n, 0)
	local sum = 0
	for p = 1, n do
		support[p] = math.floor(raw[p] * 100 / total + 0.5)
		sum += support[p]
	end
	local undecided = 100 - sum
	while undecided < 0 do
		-- Rounding overshot: take the excess from the largest share.
		local largest = 1
		for p = 2, n do
			if support[p] > support[largest] then
				largest = p
			end
		end
		support[largest] -= 1
		undecided += 1
	end
	return { support = support, undecided = undecided }
end

-- The public poll a state would show given its current error terms.
function Polls.shown(s: StateSim): State.Poll
	local n = #s.support
	local raw = table.create(n, 0)
	for p = 1, n do
		raw[p] = s.support[p] + s.pollError[p] - s.pollErrorUndecided / n
	end
	return roundShares(raw, s.undecided + s.pollErrorUndecided)
end

-- Publishes this week's public polls for every state. Call once per week, after
-- resolution (and once after the draft, with first = true).
function Polls.update(config: Config, match: MatchState, first: boolean)
	local rng = Rng.fork(match.rng, `poll:{match.week}`)
	for _, s in match.states do
		stepError(config, rng, s, first)
		s.poll = Polls.shown(s)
	end
end

-- The player who leads a poll outright, or nil on a tie.
local function pollLeader(poll: State.Poll): number?
	local best, leader, tied = -1, nil, false
	for p, share in poll.support do
		if share > best then
			best, leader, tied = share, p, false
		elseif share == best then
			tied = true
		end
	end
	if tied then
		return nil
	end
	return leader
end

-- The outright leader of a poll, or 0 on a tie (or with no poll yet).
function Polls.leader(poll: State.Poll?): number
	if poll == nil then
		return 0
	end
	return pollLeader(poll) or 0
end

-- Republishes every state's public poll from the current truth with the SAME
-- error terms (no new draw): the debate moved support at the start of the week
-- and the map should show it right away (D-040). Returns the states whose poll
-- leader changed, in StateData order.
function Polls.refresh(match: MatchState): { State.PollFlip }
	local flips: { State.PollFlip } = {}
	for _, s in match.states do
		local from = Polls.leader(s.poll)
		s.poll = Polls.shown(s)
		local to = Polls.leader(s.poll)
		if to ~= from then
			table.insert(flips, { state = s.id, from = from, to = to })
		end
	end
	return flips
end

-- Leader changes that `moves` (points per player, added straight to the shown
-- shares) would cause on the current public polls. Pure arithmetic on public
-- numbers, so the client can preview it and the server reports it (D-039).
function Polls.projectFlips(match: MatchState, moves: { State.StateMove }): { State.PollFlip }
	local flips: { State.PollFlip } = {}
	for _, move in moves do
		local s = State.get(match, move.state)
		local poll = s.poll
		if poll ~= nil then
			local shares = table.clone(poll.support)
			for p, points in move.points do
				shares[p] += points
			end
			local from = Polls.leader(poll)
			local to = Polls.leader({ support = shares, undecided = poll.undecided })
			if to ~= from then
				table.insert(flips, { state = s.id, from = from, to = to })
			end
		end
	end
	return flips
end

-- Electoral votes each player would win if the latest public polls were the result.
-- Tied states count for nobody.
function Polls.projectedEV(match: MatchState): { number }
	local ev = table.create(#match.players, 0)
	for _, s in match.states do
		local poll = s.poll
		if poll ~= nil then
			local leader = pollLeader(poll)
			if leader ~= nil then
				ev[leader] += s.ev
			end
		end
	end
	return ev
end

-- Updates every player's smoothed projected lead, underdog tier (with hysteresis)
-- and frontrunner flag from the latest public polls (D-006).
function Polls.updateUnderdog(config: Config, match: MatchState)
	local ev = Polls.projectedEV(match)
	for p, player in match.players do
		local best = -math.huge
		for q, value in ev do
			if q ~= p and value > best then
				best = value
			end
		end
		local lead = ev[p] - best
		local previous = player.lead
		local smoothed = if previous == nil
			then lead
			else config.UNDERDOG_SMOOTHING * lead + (1 - config.UNDERDOG_SMOOTHING) * previous
		player.lead = smoothed

		local gap = -smoothed
		local tier = player.underdogTier
		local h = config.UNDERDOG_HYSTERESIS
		if gap >= config.UNDERDOG_EV_2 or (tier == 2 and gap >= config.UNDERDOG_EV_2 - h) then
			tier = 2
		elseif gap >= config.UNDERDOG_EV_1 or (tier >= 1 and gap >= config.UNDERDOG_EV_1 - h) then
			tier = 1
		else
			tier = 0
		end
		player.underdogTier = tier

		local band = player.profile.frontrunnerEV
		player.frontrunner = band ~= nil and smoothed >= band
	end
end

-- Underdog multipliers for player p this week: (rally, fundraiser). The bonus part
-- is scaled by the candidate's underdogScale.
function Polls.underdogMults(config: Config, match: MatchState, p: number): (number, number)
	local player = match.players[p]
	local rally, fund = 1, 1
	if player.underdogTier == 1 then
		rally, fund = config.UNDERDOG_RALLY_1, config.UNDERDOG_FUND_1
	elseif player.underdogTier == 2 then
		rally, fund = config.UNDERDOG_RALLY_2, config.UNDERDOG_FUND_2
	end
	local scale = player.profile.underdogScale
	return 1 + (rally - 1) * scale, 1 + (fund - 1) * scale
end

-- A private internal poll of one state for player p: true support within
-- INTERNAL_POLL_ERROR (zero-sum offsets, one decimal), exact undecided and momentum,
-- and every player's ground-game units there, exact (D-044).
function Polls.internal(config: Config, rng: Rng.Rng, s: StateSim): State.InternalPoll
	local n = #s.support
	local offsets = table.create(n, 0)
	local mean = 0
	for p = 1, n do
		offsets[p] = (Rng.nextFloat(rng) * 2 - 1) * config.INTERNAL_POLL_ERROR
		mean += offsets[p] / n
	end
	local support = table.create(n, 0)
	for p = 1, n do
		local offset = math.clamp(offsets[p] - mean, -config.INTERNAL_POLL_ERROR, config.INTERNAL_POLL_ERROR)
		support[p] = math.floor((s.support[p] + offset) * 10 + 0.5) / 10
	end
	return {
		state = s.id,
		support = support,
		undecided = math.floor(s.undecided * 10 + 0.5) / 10,
		momentum = table.clone(s.momentum),
		gotv = table.clone(s.gotv),
	}
end

return table.freeze(Polls)
