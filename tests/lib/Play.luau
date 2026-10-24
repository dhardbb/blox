--!strict
-- Plays one bot-vs-bot match end to end and records what the balance harness and
-- the bot specs measure. Bots act on their own View only, like real clients.

local Bot = require("@sim/Bot")
local ConfigModule = require("@sim/Config")
local IssueMap = require("@sim/IssueMap")
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
	candidates: { string }, -- as played (Select keeps candidates unique, D-048)
	styles: { Bot.Style },
	platforms: { { string } }, -- each player's platform as picked
	issueEV: { [string]: number }, -- EV each issue covered on this match's map (D-047)
	platformTop3: { boolean }, -- each player's platform was the three highest-EV issues
	winner: number,
	ev: { number },
	landslide: boolean, -- the winner took more than LANDSLIDE_EV_SHARE of the EV (D-062)
	priorityA: number,
	invalid: number, -- bot inputs the validator rejected (should be 0)
	trueLeaderWeek8: number, -- 0 if tied
	unspent: { number },
	raised: { number }, -- money each player's fundraisers raised over the match
	raisedByWeek: { number }, -- both players' fundraiser money by campaign week (front-loading check)
	tierChanges: number,
	underdogWeeks: number, -- player-weeks with an underdog tier on
	underdogWrong: number, -- ... where that player was truly ahead by 20+ EV
	gotvSpend: { number },
	pollSpend: { number }, -- money each player paid for internal polls (free ones excluded)
	statePolls: { number }, -- single-state internal polls each player ran (free ones included)
	regionPolls: { number }, -- region polls each player ran
	scoutedGotv: { number }, -- states where the player's own polls last saw opponent ground game (D-049)
	gotvDecided: boolean, -- the winner changes if GOTV is removed
	debateDecided: boolean, -- the winner changes if the debates' support shifts are removed
	debateShiftEV: number, -- |EV swing| the debates' shifts account for in the final count
	stanceDecided: boolean, -- the winner changes if the Choice stances' support shifts are removed
	stanceShiftEV: number, -- |EV swing| the stances' shifts account for in the final count
	stances: { [string]: number }, -- how often each stance slot was taken, both players
	choiceWeeks: number, -- Choice events dealt into this match
	sameStance: number, -- Choice events where both players took the same stance (their moves then mostly cancel)
	projectionWrong: boolean, -- the week-12 projected leader lost
	leanEV: { number }, -- EV of states leaning toward each player
	leanedStates: number,
	leanedFlipped: number, -- leaned states won by the side the lean opposed
	tossupEVDraft: number, -- EV within +/-1.35 true margin right after the draft
	tossupEVElection: number, -- EV with win probability 25-75% on election day
	noiseSpread: number, -- sd of player 1's EV from election noise alone
	debateTopicsWon: { number },
	debateTopicsPlayed: number,
	debateRounds: number, -- debate rounds played (D-062)
	debateMoves: { [string]: number }, -- moves played, both players, by move ("Canned" for a timeout)
	debateSplits: number, -- rounds that were a split
	sameMove: number, -- rounds where both played the same move
	safeRounds: number, -- (player, round) pairs where the player had a move that could not lose
	safeTaken: number, -- ... and won or split the round
	zingerRounds: { number }, -- Zingers staked in rounds 1, 2, 3
	zingerWins: number, -- staked rounds the staker won
	ovations: number,
	draftRounds: number, -- blind draft rounds played
	draftClashes: number, -- rounds where both players' first choices were the same state
	homeClash: boolean, -- both players' first choice for home was the same state
	homes: { string }, -- each player's home
	strongholds: { { string } }, -- each player's strongholds (drafted or assigned), before nominations strip any
	strongholdEV: { number }, -- EV of each player's strongholds
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
	local pollSpend = { 0, 0 }
	local statePolls, regionPolls = { 0, 0 }, { 0, 0 }
	local raised = { 0, 0 }
	local raisedByWeek = table.create(config.WEEKS, 0)
	local draftRounds, draftClashes, homeClash = 0, 0, false
	local platforms: { { string } } = { {}, {} }

	while match.phase ~= "Done" do
		local inputs = {}
		if Match.wantsInput(match) then
			for p = 1, 2 do
				local view = View.build(config, match, p)
				local input = Bot.act(config, view, rngs[p], candidates[p], styleOf[p])
				-- nil: the bot sends nothing (NoAnswer), so the default applies.
				local ok = input == nil or Match.validate(config, match, p, input)
				if not ok then
					invalid += 1
				end
				if ok and match.phase == "Plan" then
					local free = match.players[p].profile.freePolls
					for _, action in input.actions do
						if action.kind == "Gotv" then
							gotvSpend[p] += action.units * match.players[p].profile.gotvCost
						elseif action.kind == "Poll" then
							statePolls[p] += 1
							if free > 0 then
								free -= 1
							else
								pollSpend[p] += config.INTERNAL_POLL_COST
							end
						elseif action.kind == "RegionPoll" then
							regionPolls[p] += 1
							pollSpend[p] += config.REGION_POLL_COST
						end
					end
				end
				inputs[p] = input
			end
		end
		local before = match.phase
		if before == "Draft" then
			draftRounds += 1
			local a, b = inputs[1].choices[1], inputs[2].choices[1]
			if a ~= nil and a == b then
				draftClashes += 1
				if match.draftRound == 0 then
					homeClash = true
				end
			end
		end
		match = Match.advance(config, match, inputs)
		if before == "Select" then
			for p = 1, 2 do
				platforms[p] = table.clone(match.players[p].platform)
			end
		end

		if before == "Draft" and match.phase ~= "Draft" then
			tossupDraft = tossupEV(config, match, false)
		end
		if before == "Plan" then
			local week = match.week - 1
			for p, player in match.players do
				raised[p] += player.raised
				raisedByWeek[week] += player.raised
			end
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
	local noDebates = Election.count(config, match, { debates = false })
	local noStances = Election.count(config, match, { stances = false })
	local stances: { [string]: number } = {}
	local choiceWeeks, sameStance = 0, 0
	for _, logged in match.eventLog do
		local choices = logged.choices
		if choices then
			choiceWeeks += 1
			for _, id in choices do
				stances[id] = (stances[id] or 0) + 1
			end
			if choices[1] == choices[2] then
				sameStance += 1
			end
		end
	end
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

	local scoutedGotv = { 0, 0 }
	for p, player in match.players do
		for _, scout in player.scouted do
			if (scout.gotv[3 - p] or 0) > 0 then
				scoutedGotv[p] += 1
			end
		end
	end

	local topicsWon, topicsPlayed = { 0, 0 }, 0
	local debateRounds, debateSplits, sameMove, safeRounds, safeTaken, zingerWins, ovations =
		0, 0, 0, 0, 0, 0, 0
	local debateMoves: { [string]: number } = { Defend = 0, Attack = 0, Pivot = 0, Canned = 0 }
	local zingerRounds = { 0, 0, 0 }
	for _, debate in match.debates do
		for _, w in debate.winners do
			topicsPlayed += 1
			if w > 0 then
				topicsWon[w] += 1
			end
		end
		if debate.ovation > 0 then
			ovations += 1
		end
		for _, round in debate.rounds do
			debateRounds += 1
			if round.winner == 0 then
				debateSplits += 1
			end
			if round.picks[1] == round.picks[2] and not round.canned[1] and not round.canned[2] then
				sameMove += 1
			end
			for p = 1, 2 do
				local key = if round.canned[p] then "Canned" else round.picks[p]
				debateMoves[key] += 1
				if round.safe[p] then
					safeRounds += 1
					if round.winner == p or round.split[p] then
						safeTaken += 1
					end
				end
				if round.zingers[p] then
					zingerRounds[round.round] += 1
					if round.winner == p then
						zingerWins += 1
					end
				end
			end
		end
	end

	local homes, strongholds, strongholdEV = {}, {}, {}
	for p, player in match.players do
		homes[p] = player.home or ""
		strongholds[p] = table.clone(player.strongholds)
		strongholdEV[p] = 0
		for _, id in player.strongholds do
			strongholdEV[p] += StateData.byId[id].ev
		end
	end

	local issueEV = IssueMap.evByIssue(match.issueMap)
	local sorted: { number } = {}
	for _, ev in issueEV do
		table.insert(sorted, ev)
	end
	table.sort(sorted, function(a, b)
		return a > b
	end)
	local platformTop3 = {}
	for p = 1, 2 do
		local lowest = math.huge
		for _, issue in platforms[p] do
			lowest = math.min(lowest, issueEV[issue])
		end
		platformTop3[p] = lowest >= sorted[config.PLATFORM_SIZE]
	end

	return {
		seed = seed,
		candidates = { match.players[1].candidate, match.players[2].candidate },
		styles = styleOf,
		platforms = platforms,
		issueEV = issueEV,
		platformTop3 = platformTop3,
		winner = result.winner,
		ev = result.ev,
		landslide = Election.landslide(config, result) ~= nil,
		priorityA = match.priorityA,
		invalid = invalid,
		trueLeaderWeek8 = trueLeaderWeek8,
		unspent = { match.players[1].cash, match.players[2].cash },
		raised = raised,
		raisedByWeek = raisedByWeek,
		tierChanges = tierChanges,
		underdogWeeks = underdogWeeks,
		underdogWrong = underdogWrong,
		gotvSpend = gotvSpend,
		pollSpend = pollSpend,
		statePolls = statePolls,
		regionPolls = regionPolls,
		scoutedGotv = scoutedGotv,
		gotvDecided = noGotv.winner ~= result.winner,
		debateDecided = noDebates.winner ~= result.winner,
		debateShiftEV = math.abs((result.ev[1] - result.ev[2]) - (noDebates.ev[1] - noDebates.ev[2])) / 2,
		stanceDecided = noStances.winner ~= result.winner,
		stanceShiftEV = math.abs((result.ev[1] - result.ev[2]) - (noStances.ev[1] - noStances.ev[2])) / 2,
		stances = stances,
		choiceWeeks = choiceWeeks,
		sameStance = sameStance,
		projectionWrong = projectionWrong,
		leanEV = leanEV,
		leanedStates = leanedStates,
		leanedFlipped = leanedFlipped,
		tossupEVDraft = tossupDraft,
		tossupEVElection = tossupElection,
		noiseSpread = spread,
		debateTopicsWon = topicsWon,
		debateTopicsPlayed = topicsPlayed,
		debateRounds = debateRounds,
		debateMoves = debateMoves,
		debateSplits = debateSplits,
		sameMove = sameMove,
		safeRounds = safeRounds,
		safeTaken = safeTaken,
		zingerRounds = zingerRounds,
		zingerWins = zingerWins,
		ovations = ovations,
		draftRounds = draftRounds,
		draftClashes = draftClashes,
		homeClash = homeClash,
		homes = homes,
		strongholds = strongholds,
		strongholdEV = strongholdEV,
		match = match,
	}
end

return Play
