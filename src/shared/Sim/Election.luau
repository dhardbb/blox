--!strict
-- Election night. In each state, a player's final score is true support plus
-- GOTV_PER_UNIT per ground-game unit plus seeded noise; the highest score takes the
-- state's EV. Noise is a zero-sum component per player with sd ELECTION_SIGMA / sqrt(2),
-- so in 1v1 the margin noise has sd ELECTION_SIGMA, as in docs/PLAN.md.
--
-- Most EV wins. An EV tie goes to whoever won more states, then the popular vote
-- (support x population), then a seeded coin.

local ConfigModule = require("./Config")
local Rng = require("./Rng")
local State = require("./State")
local StateData = require("./StateData")

type Config = ConfigModule.Config
type MatchState = State.MatchState

local Election = {}

local SQRT_HALF = math.sqrt(0.5)

-- Final scores in one state; `noise` may be nil for a noiseless count. With
-- `debates` false, the support the debates moved is subtracted first.
local function scores(
	config: Config,
	s: State.StateSim,
	noise: { number }?,
	gotv: boolean,
	debates: boolean
): { number }
	local n = #s.support
	local out = table.create(n, 0)
	for p = 1, n do
		out[p] = s.support[p]
			- (if debates then 0 else s.debateShift[p])
			+ (if gotv then config.GOTV_PER_UNIT * s.gotv[p] else 0)
			+ (if noise then noise[p] else 0)
	end
	return out
end

-- Winner (0 on an exact tie) and margin over the runner-up.
local function decide(values: { number }): (number, number)
	local best, second, winner = -math.huge, -math.huge, 0
	for p, v in values do
		if v > best then
			second, best, winner = best, v, p
		elseif v == best then
			second, winner = v, 0
		elseif v > second then
			second = v
		end
	end
	return winner, best - second
end

-- Zero-sum election noise for every state, drawn in state order from the seed.
function Election.noise(config: Config, match: MatchState): { { number } }
	local rng = Rng.fork(match.rng, "election")
	local n = #match.players
	local all = {}
	for i = 1, #match.states do
		local draws = table.create(n, 0)
		local mean = 0
		for p = 1, n do
			draws[p] = Rng.gaussian(rng, 0, config.ELECTION_SIGMA * SQRT_HALF)
			mean += draws[p] / n
		end
		for p = 1, n do
			draws[p] -= mean
		end
		all[i] = draws
	end
	return all
end

-- Counts the election. Options: `noise` (default: the match's seeded noise; pass
-- false for none), `gotv` (default true) and `debates` (default true; false
-- recounts with the support the debates moved subtracted, same noise). The
-- harness uses the options for counterfactuals; the game always uses the defaults.
function Election.count(
	config: Config,
	match: MatchState,
	options: { noise: boolean?, gotv: boolean?, debates: boolean? }?
): State.ElectionResult
	local useNoise = not (options and options.noise == false)
	local useGotv = not (options and options.gotv == false)
	local useDebates = not (options and options.debates == false)
	local noise = if useNoise then Election.noise(config, match) else nil
	local n = #match.players
	local ev = table.create(n, 0)
	local statesWon = table.create(n, 0)
	local popular = table.create(n, 0)
	local results: { State.StateResult } = {}
	for i, s in match.states do
		local winner, margin = decide(scores(config, s, if noise then noise[i] else nil, useGotv, useDebates))
		if winner > 0 then
			ev[winner] += s.ev
			statesWon[winner] += 1
		end
		for p = 1, n do
			popular[p] += s.support[p] * StateData.list[i].pop
		end
		table.insert(results, { state = s.id, winner = winner, margin = margin })
	end
	table.sort(results, function(a, b)
		if a.margin ~= b.margin then
			return a.margin > b.margin
		end
		return a.state < b.state
	end)

	local winner, decidedBy = 0, "EV"
	for _, key in { "EV", "States", "Popular" } do
		local values = if key == "EV" then ev elseif key == "States" then statesWon else popular
		local w = decide(values)
		if w > 0 then
			winner, decidedBy = w, key
			break
		end
	end
	if winner == 0 then
		-- Only reachable on an exact popular-vote tie among the leaders.
		winner = Rng.nextInt(Rng.fork(match.rng, "election-coin"), 1, n)
		decidedBy = "Coin"
	end
	return {
		ev = ev,
		statesWon = statesWon,
		popular = popular,
		winner = winner,
		decidedBy = decidedBy :: any,
		results = results,
	}
end

-- EV each player holds right now on true support alone (no noise, no GOTV).
function Election.trueEV(config: Config, match: MatchState): { number }
	return Election.count(config, match, { noise = false, gotv = false }).ev
end

return table.freeze(Election)
