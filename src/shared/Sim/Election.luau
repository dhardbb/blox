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
-- `debates` (or `stances`) false, the support the debates (or the Choice
-- stances) moved is subtracted first.
local function scores(
	config: Config,
	s: State.StateSim,
	noise: { number }?,
	gotv: boolean,
	debates: boolean,
	stances: boolean
): { number }
	local n = #s.support
	local out = table.create(n, 0)
	for p = 1, n do
		out[p] = s.support[p]
			- (if debates then 0 else s.debateShift[p])
			- (if stances then 0 else s.stanceShift[p])
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
-- false for none), `gotv` (default true), `debates` and `stances` (default true;
-- false recounts with the support the debates or the Choice stances moved
-- subtracted, same noise). The harness uses the options for counterfactuals; the
-- game always uses the defaults.
function Election.count(
	config: Config,
	match: MatchState,
	options: { noise: boolean?, gotv: boolean?, debates: boolean?, stances: boolean? }?
): State.ElectionResult
	local useNoise = not (options and options.noise == false)
	local useGotv = not (options and options.gotv == false)
	local useDebates = not (options and options.debates == false)
	local useStances = not (options and options.stances == false)
	local noise = if useNoise then Election.noise(config, match) else nil
	local n = #match.players
	local ev = table.create(n, 0)
	local statesWon = table.create(n, 0)
	local popular = table.create(n, 0)
	local results: { State.StateResult } = {}
	for i, s in match.states do
		local winner, margin =
			decide(scores(config, s, if noise then noise[i] else nil, useGotv, useDebates, useStances))
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

	-- Each tiebreak only compares the players still tied at the top.
	local contenders = {}
	for p = 1, n do
		contenders[p] = p
	end
	local winner, decidedBy = 0, "EV"
	for _, key in { "EV", "States", "Popular" } do
		local values = if key == "EV" then ev elseif key == "States" then statesWon else popular
		local best = -math.huge
		for _, p in contenders do
			best = math.max(best, values[p])
		end
		local tied = {}
		for _, p in contenders do
			if values[p] == best then
				table.insert(tied, p)
			end
		end
		if #tied == 1 then
			winner, decidedBy = tied[1], key
			break
		end
		contenders = tied
	end
	if winner == 0 then
		-- Only reachable on an exact popular-vote tie among the leaders.
		winner = contenders[Rng.nextInt(Rng.fork(match.rng, "election-coin"), 1, #contenders)]
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

-- The landslide winner, or nil: the winner of `election` took strictly more than
-- LANDSLIDE_EV_SHARE of the EV in play (every counted state's EV; 377 of 538 at
-- 0.70). A tie on EV is never a landslide. Pure; the Results screen shows the
-- LANDSLIDE graphic to both players from this (D-062).
function Election.landslide(config: Config, election: State.ElectionResult?): number?
	if election == nil then
		return nil
	end
	local winner = election.winner
	local won = election.ev[winner]
	if won == nil then
		return nil
	end
	local total = 0
	for _, r in election.results do
		local record = StateData.byId[r.state]
		if record then
			total += record.ev
		end
	end
	if total <= 0 then
		return nil
	end
	for p, ev in election.ev do
		if p ~= winner and ev >= won then
			return nil
		end
	end
	if won > config.LANDSLIDE_EV_SHARE * total then
		return winner
	end
	return nil
end

-- EV each player holds right now on true support alone (no noise, no GOTV).
function Election.trueEV(config: Config, match: MatchState): { number }
	return Election.count(config, match, { noise = false, gotv = false }).ev
end

return table.freeze(Election)
