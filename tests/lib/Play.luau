--!strict
-- Plays one bot-vs-bot match end to end and records what the balance harness and
-- the bot specs measure. Bots act on their own View only, like real clients.

local Bot = require("@sim/Bot")
local ConfigModule = require("@sim/Config")
local Election = require("@sim/Election")
local Match = require("@sim/Match")
local Polls = require("@sim/Polls")
local Rng = require("@sim/Rng")
local State = require("@sim/State")
local StateData = require("@sim/StateData")
local View = require("@sim/View")

type Config = ConfigModule.Config

local Play = {}

export type Record = {
	seed: number,
	candidates: { string },
	styles: { Bot.Style },
	winner: number,
	ev: { number },
	priorityA: number,
	invalid: number, -- bot inputs the validator rejected (should be 0)
	trueLeaderWeek8: number, -- 0 if tied
	unspent: { number },
	tierChanges: number,
	underdogWeeks: number, -- player-weeks with an underdog tier on
	underdogWrong: number, -- ... where that player was truly ahead by 20+ EV
	gotvSpend: { number },
	gotvDecided: boolean, -- the winner changes if GOTV is removed
	projectionWrong: boolean, -- the week-12 projected leader lost
	leanEV: { number }, -- EV of states leaning toward each player
	leanedStates: number,
	leanedFlipped: number, -- leaned states won by the side the lean opposed
	tossupEVDraft: number, -- EV within +/-1.35 true margin right after the draft
	tossupEVElection: number, -- EV with win probability 25-75% on election day
	noiseSpread: number, -- sd of player 1's EV from election noise alone
	debateTopicsWon: { number },
	debateTopicsPlayed: number,
	match: State.MatchState,
}

local function phi(x: number): number
	local sign = if x < 0 then -1 else 1
	local z = math.abs(x) / math.sqrt(2)
	local t = 1 / (1 + 0.3275911 * z)
	local poly = t
		* (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))))
	return 0.5 * (1 + sign * (1 - poly * math.exp(-z * z)))
end

local function tossupEV(config: Config, match: State.MatchState, withGotv: boolean): (number, number)
	local tossup, variance = 0, 0
	for _, s in match.states do
		local margin = s.support[1] - s.support[2]
		if withGotv then
			margin += config.GOTV_PER_UNIT * (s.gotv[1] - s.gotv[2])
		end
		local p = phi(margin / config.ELECTION_SIGMA)
		if p > 0.25 and p < 0.75 then
			tossup += s.ev
		end
		variance += s.ev * s.ev * p * (1 - p)
	end
	return tossup, math.sqrt(variance)
end

local function leader(values: { number }): number
	if values[1] > values[2] then
		return 1
	elseif values[2] > values[1] then
		return 2
	end
	return 0
end

-- Plays a full match. `styles` default to Balanced for both.
function Play.match(config: Config, seed: number, candidates: { string }, styles: { Bot.Style }?): Record
	local styleOf: { Bot.Style } = styles or { "Balanced", "Balanced" }
	local match = Match.new(config, seed, { "p1", "p2" })
	local rngs = { Rng.new(seed * 2 + 101), Rng.new(seed * 2 + 102) }
	local invalid = 0
	local trueLeaderWeek8 = 0
	local tierChanges, underdogWeeks, underdogWrong = 0, 0, 0
	local lastTier = { 0, 0 }
	local tossupDraft = 0
	local projectionWrong = false
	local projectedLeader = 0
	local gotvSpend = { 0, 0 }

	while match.phase ~= "Done" do
		local inputs = {}
		if Match.wantsInput(match) then
			for p = 1, 2 do
				local view = View.build(config, match, p)
				local input = Bot.act(config, view, rngs[p], candidates[p], styleOf[p])
				local ok = Match.validate(config, match, p, input)
				if not ok then
					invalid += 1
				end
				if ok and match.phase == "Plan" then
					for _, action in input.actions do
						if action.kind == "Gotv" then
							gotvSpend[p] += action.units * match.players[p].profile.gotvCost
						end
					end
				end
				inputs[p] = input
			end
		end
		local before = match.phase
		match = Match.advance(config, match, inputs)

		if before == "Draft" and match.phase ~= "Draft" then
			tossupDraft = tossupEV(config, match, false)
		end
		if before == "Plan" then
			local week = match.week - 1
			local trueEV = Election.trueEV(config, match)
			if week == 8 then
				trueLeaderWeek8 = leader(trueEV)
			end
			if week == config.WEEKS then
				projectedLeader = leader(Polls.projectedEV(match))
			end
			for p, player in match.players do
				if player.underdogTier ~= lastTier[p] then
					tierChanges += 1
					lastTier[p] = player.underdogTier
				end
				if player.underdogTier > 0 and week < config.WEEKS then
					underdogWeeks += 1
					if trueEV[p] - trueEV[3 - p] >= 20 then
						underdogWrong += 1
					end
				end
			end
		end
	end

	local result = match.election :: State.ElectionResult
	projectionWrong = projectedLeader ~= 0 and projectedLeader ~= result.winner
	local noGotv = Election.count(config, match, { gotv = false })
	local tossupElection, spread = tossupEV(config, match, true)

	local leanEV = { 0, 0 }
	local leanedStates, leanedFlipped = 0, 0
	local winners: { [string]: number } = {}
	for _, r in result.results do
		winners[r.state] = r.winner
	end
	for i, s in match.states do
		local to = s.leanTo
		if to ~= nil and s.lean > 0 then
			leanEV[to] += StateData.list[i].ev
			leanedStates += 1
			if winners[s.id] ~= to and winners[s.id] ~= 0 then
				leanedFlipped += 1
			end
		end
	end

	local topicsWon, topicsPlayed = { 0, 0 }, 0
	for _, debate in match.debates do
		for _, w in debate.winners do
			topicsPlayed += 1
			if w > 0 then
				topicsWon[w] += 1
			end
		end
	end

	return {
		seed = seed,
		candidates = candidates,
		styles = styleOf,
		winner = result.winner,
		ev = result.ev,
		priorityA = match.priorityA,
		invalid = invalid,
		trueLeaderWeek8 = trueLeaderWeek8,
		unspent = { match.players[1].cash, match.players[2].cash },
		tierChanges = tierChanges,
		underdogWeeks = underdogWeeks,
		underdogWrong = underdogWrong,
		gotvSpend = gotvSpend,
		gotvDecided = noGotv.winner ~= result.winner,
		projectionWrong = projectionWrong,
		leanEV = leanEV,
		leanedStates = leanedStates,
		leanedFlipped = leanedFlipped,
		tossupEVDraft = tossupDraft,
		tossupEVElection = tossupElection,
		noiseSpread = spread,
		debateTopicsWon = topicsWon,
		debateTopicsPlayed = topicsPlayed,
		match = match,
	}
end

return Play
