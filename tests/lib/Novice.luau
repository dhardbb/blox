--!strict
-- Scripted first-time players for the Easy-bot study (tests/harness/novice.luau).
-- Not a bot level and not shipped: a stand-in for a person who has read the
-- screens once and plans by feel, modeled on what the six new players in the
-- 0.15 text playtests actually sent (duel h1-h3: commands and notes).
--
-- What they did, and what every variant here does to some degree:
-- - Rallies go to states they like (their home, the big states with a platform
--   issue) about as often as to the states the polls call close, and they stay
--   with a state for weeks. Nobody reasons about the tipping point.
-- - A week is "rally X, fund X, rally (or ad) Y": one fundraiser, one or two ads.
--   Cash piles up ($30-80 from week 6 on); ground game starts late, sporadically,
--   or only as a final-week dump. No attack ads, no polls, no pivots.
-- - Stances: the hedge (the default) a lot, otherwise the side whose headline
--   reads bigger. Debate moves near random, a "cannot lose" move when one is
--   pointed out, the Zinger on any round.
-- - Now and then a rally in the opponent's stronghold ("show the flag").
--
-- Every input is legal and decided from the player's own View only.

local Bot = require("@sim/Bot")
local Candidates = require("@sim/Candidates")
local ConfigModule = require("@sim/Config")
local Debate = require("@sim/Debate")
local Draft = require("@sim/Draft")
local Events = require("@sim/Events")
local Issues = require("@sim/Issues")
local Plan = require("@sim/Plan")
local Resolve = require("@sim/Resolve")
local Rng = require("@sim/Rng")
local StateData = require("@sim/StateData")
local Types = require("@shared/Types")
local ViewModule = require("@sim/View")

type Config = ConfigModule.Config
type View = ViewModule.View

export type Params = {
	name: string,
	-- Where the effort goes.
	likedCount: number, -- "my states": home plus the biggest states with a platform issue
	pollWeight: number, -- 0 = goes only by liked states, 1 = only by the polls' "in play" list
	inPlay: number, -- a public-poll margin within this many points looks close
	evPower: number, -- how strongly bigger states pull (EV ^ evPower)
	noise: number, -- log-normal spread on each state's appeal, redrawn every week
	sticky: number, -- chance the week starts where last week ended
	repeatRally: number, -- chance the second rally goes back to the first state
	strongholdRally: number, -- chance the second rally goes to an opponent stronghold or home
	bestIssue: number, -- chance a rally or ad uses the best issue shown (else a platform issue at random)
	fundraisers: number, -- fundraisers a week (after the first rally)
	secondFund: number, -- chance of one more fundraiser instead of a rally
	-- Money.
	maxAds: number, -- ads a week at most
	reserve: number, -- cash kept back (not spent) before the last week
	gotvFrom: number, -- first week ground game is considered (99 = never)
	gotvChance: number, -- chance per week from then on
	gotvUnits: number, -- units per state at a time
	gotvStates: number, -- states per week
	dumpLast: number, -- chance the last week spends everything (ground game first)
	-- Decisions.
	hedge: number, -- chance of the hedge (C, the preselected default)
	stanceRead: number, -- otherwise: chance of picking by the summary, else A or B at random
	stanceByNeed: boolean, -- the summary read is EV in close states (true) or the raw total (false)
	safeRead: number, -- chance of taking a "cannot lose" move when the board has one
	debateRead: number, -- otherwise: chance of the move whose cells add up best, else random
	zingerOnSafe: boolean, -- stake the Zinger on a safe winning chance or the last round (else any round)
	-- Study instrument: phases handed to the standard bot instead ("Plan", "Draft",
	-- "Decision", "Debate"), to measure what each part of a novice's play costs.
	delegate: { [string]: boolean }?,
}

local Novice = {}

-- The three variants (the study's weak, typical and attentive new player).
local WEAK: Params = {
	name = "Weak",
	likedCount = 6,
	pollWeight = 0.3,
	inPlay = 5,
	evPower = 0.8,
	noise = 0.5,
	sticky = 0.6,
	repeatRally = 0.5,
	strongholdRally = 0.25,
	bestIssue = 0.5,
	fundraisers = 1,
	secondFund = 0.3,
	maxAds = 1,
	reserve = 45,
	gotvFrom = 99,
	gotvChance = 0,
	gotvUnits = 2,
	gotvStates = 1,
	dumpLast = 0.25,
	hedge = 0.6,
	stanceRead = 0.3,
	stanceByNeed = false,
	safeRead = 0.25,
	debateRead = 0.2,
	zingerOnSafe = false,
}

local TYPICAL: Params = {
	name = "Typical",
	likedCount = 8,
	pollWeight = 0.6,
	inPlay = 5,
	evPower = 1,
	noise = 0.4,
	sticky = 0.5,
	repeatRally = 0.4,
	strongholdRally = 0.15,
	bestIssue = 0.75,
	fundraisers = 1,
	secondFund = 0.15,
	maxAds = 2,
	reserve = 20,
	gotvFrom = 7,
	gotvChance = 0.4,
	gotvUnits = 2,
	gotvStates = 1,
	dumpLast = 0.5,
	hedge = 0.4,
	stanceRead = 0.6,
	stanceByNeed = false,
	safeRead = 0.5,
	debateRead = 0.4,
	zingerOnSafe = false,
}

local ATTENTIVE: Params = {
	name = "Attentive",
	likedCount = 10,
	pollWeight = 0.9,
	inPlay = 5,
	evPower = 1,
	noise = 0.25,
	sticky = 0.2,
	repeatRally = 0.2,
	strongholdRally = 0.05,
	bestIssue = 0.95,
	fundraisers = 1,
	secondFund = 0,
	maxAds = 6,
	reserve = 6,
	gotvFrom = 6,
	gotvChance = 0.8,
	gotvUnits = 2,
	gotvStates = 2,
	dumpLast = 1,
	hedge = 0.2,
	stanceRead = 0.9,
	stanceByNeed = true,
	safeRead = 0.9,
	debateRead = 0.6,
	zingerOnSafe = true,
}

Novice.VARIANTS =
	table.freeze({ Weak = WEAK, Typical = TYPICAL, Attentive = ATTENTIVE } :: { [string]: Params })
Novice.NAMES = table.freeze({ "Weak", "Typical", "Attentive" })

local ISSUES: { Types.Issue } = Issues.list :: any

-- The rival: the other player (1v1).
local function rival(view: View): number
	return if view.you == 1 then 2 else 1
end

-- Public-poll margin for me in state i (0 with no poll).
local function margin(view: View, i: number): number
	local poll = view.states[i].poll
	if poll == nil then
		return 0
	end
	return (poll.support[view.you] or 0) - (poll.support[rival(view)] or 0)
end

local function platformOf(view: View): { Types.Issue }
	return view.players[view.you].platform or {}
end

local function platformHits(view: View, i: number): number
	local platform = platformOf(view)
	local hits = 0
	for _, issue in view.issueMap[i] do
		if table.find(platform, issue) then
			hits += 1
		end
	end
	return hits
end

-- "My states": home, then the biggest states with a platform issue.
local function likedSet(view: View, params: Params): { [number]: boolean }
	local me = view.players[view.you]
	local order = {}
	for i, record in StateData.list do
		local score = record.ev * (1 + 0.5 * platformHits(view, i))
		if record.id == me.home then
			score = math.huge
		end
		table.insert(order, { i = i, score = score })
	end
	table.sort(order, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.i < b.i
	end)
	local out = {}
	for k = 1, math.min(params.likedCount, #order) do
		out[order[k].i] = true
	end
	return out
end

-- The issue a rally or ad uses: the best one shown, or a platform issue at random.
local function issueFor(config: Config, view: View, rng: Rng.Rng, params: Params, i: number): Types.Issue
	local platform = platformOf(view)
	if Rng.nextFloat(rng) >= params.bestIssue and #platform > 0 then
		return platform[Rng.nextInt(rng, 1, #platform)]
	end
	local best: Types.Issue, bestMult = ISSUES[1], -math.huge
	for k = 1, #ISSUES do
		local issue: Types.Issue = ISSUES[k]
		local stateIssues: { Types.Issue } = view.issueMap[i] :: any
		local mult = Resolve.issueMult(config, platform, stateIssues, issue, view.platformMults)
		if mult > bestMult then
			best, bestMult = issue, mult
		end
	end
	return best
end

-- How much a state appeals this week, by feel.
local function appeal(view: View, rng: Rng.Rng, params: Params, liked: { [number]: boolean }): { number }
	local out = table.create(#StateData.list, 0)
	for i, record in StateData.list do
		local m = math.abs(margin(view, i))
		local close = if m <= params.inPlay then 1 elseif m <= 2 * params.inPlay then 0.4 else 0.1
		local like = if liked[i] then 1 else 0.15
		local mix = (1 - params.pollWeight) * like + params.pollWeight * close
		out[i] = record.ev ^ params.evPower * mix * math.exp(Rng.gaussian(rng, 0, params.noise))
	end
	return out
end

local function ranked(scores: { number }): { number }
	local order = table.create(#scores, 0)
	for i in scores do
		order[i] = i
	end
	table.sort(order, function(a, b)
		if scores[a] ~= scores[b] then
			return scores[a] > scores[b]
		end
		return a < b
	end)
	return order
end

local function indexOf(id: string?): number?
	if id == nil then
		return nil
	end
	for i, record in StateData.list do
		if record.id == id then
			return i
		end
	end
	return nil
end

-- ---------------------------------------------------------------- phases

local function select(config: Config, view: View, rng: Rng.Rng, candidate: string): any
	-- "Pick issues by highest EV x multiplier" (h1p1): the big issues, with a little noise.
	return Bot.select(config, view, rng, candidate, "TopIssues")
end

local function draft(config: Config, view: View, rng: Rng.Rng, params: Params): any
	local me = view.you
	local kind = Draft.kind(config, view.draftRound)
	local mine = view.players[me]
	local theirs = view.players[rival(view)]
	local scored = {}
	for i, record in StateData.list do
		local s = view.states[i]
		local legal = if kind == "Nominate"
			then not s.isHome and not s.battleground
			else s.owner == nil and not s.battleground
		if legal then
			-- The draft list is sorted biggest first: big states, a platform issue helps.
			local value = record.ev * (1 + 0.15 * platformHits(view, i))
			if kind == "Nominate" then
				if table.find(mine.strongholds, record.id) then
					value *= 1 - params.pollWeight -- the attentive see they would strip their own bonus
				elseif table.find(theirs.strongholds, record.id) then
					value *= 1 + params.pollWeight
				end
			end
			value *= math.exp(Rng.gaussian(rng, 0, 0.3))
			table.insert(scored, { id = record.id, value = value })
		end
	end
	table.sort(scored, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.id < b.id
	end)
	local choices = {}
	for k = 1, math.min(Draft.CHOICES, #scored) do
		choices[k] = scored[k].id
	end
	return { choices = choices }
end

local function decide(config: Config, view: View, rng: Rng.Rng, params: Params): any
	local event = view.event
	if event == nil or Rng.nextFloat(rng) < params.hedge then
		return { choice = "C" }
	end
	if Rng.nextFloat(rng) >= params.stanceRead then
		return { choice = if Rng.nextFloat(rng) < 0.5 then "A" else "B" }
	end
	local definition = Events.byId[event.id]
	local platform = platformOf(view)
	local base = Events.baseOf(view.players[view.you])
	local best, bestValue = "C", 0
	for _, id in { "A", "B" } do
		local value = 0
		for i, record in StateData.list do
			local points =
				Events.stanceEffect(config, view.issueMap, definition, id :: any, i, platform, base)
			if params.stanceByNeed then
				if math.abs(margin(view, i)) <= params.inPlay then
					value += points * record.ev
				end
			else
				value += points
			end
		end
		if value > bestValue then
			best, bestValue = id, value
		end
	end
	return { choice = best }
end

local function debate(config: Config, view: View, rng: Rng.Rng, params: Params): any
	local live = view.debate
	if live == nil then
		return nil
	end
	local me, them = view.you, rival(view)
	local board = live.board
	local worst, sum = {}, {}
	local safe: { number } = {}
	for a = 1, #Debate.MOVES do
		local mine: Types.DebateMove = Debate.MOVES[a]
		worst[a], sum[a] = math.huge, 0
		for b = 1, #Debate.MOVES do
			local theirs: Types.DebateMove = Debate.MOVES[b]
			local cell = Debate.versus(config, board, me, mine, them, theirs)
			worst[a] = math.min(worst[a], cell)
			sum[a] += cell
		end
		if worst[a] >= 0 then
			table.insert(safe, a)
		end
	end
	local pick: number
	if #safe > 0 and Rng.nextFloat(rng) < params.safeRead then
		pick = safe[1]
		for _, a in safe do
			if sum[a] > sum[pick] then
				pick = a
			end
		end
	elseif Rng.nextFloat(rng) < params.debateRead then
		pick = 1
		for a = 2, #Debate.MOVES do
			if sum[a] > sum[pick] then
				pick = a
			end
		end
	else
		pick = Rng.nextInt(rng, 1, #Debate.MOVES)
	end
	local zinger = false
	if (live.zingers[me] or 0) > 0 then
		local roundsLeft = #live.topics - live.round + 1
		if params.zingerOnSafe then
			zinger = roundsLeft == 1 or (worst[pick] >= 0 and sum[pick] > 0)
		else
			zinger = Rng.nextFloat(rng) < 1 / roundsLeft
		end
	end
	return { move = Debate.MOVES[pick], zinger = zinger }
end

local function plan(config: Config, view: View, rng: Rng.Rng, params: Params): any
	local me = view.you
	local player = view.players[me]
	local profile = Candidates.profile(config, player.candidate or Candidates.ids[1])
	local cash = player.cash or 0
	local location = player.location
	local liked = likedSet(view, params)
	local scores = appeal(view, rng, params, liked)
	local order = ranked(scores)
	local actions: { any } = {}

	-- The route: rally X, fund X, then rally (or fund) Y.
	local function hop(i: number): boolean
		local id = StateData.list[i].id
		if Plan.isAdjacent(location, id) then
			location = id
			return true
		end
		if cash >= config.FLIGHT_COST then
			cash -= config.FLIGHT_COST
			location = id
			return true
		end
		return false
	end
	local function stop(i: number, kind: "Rally" | "Fundraise")
		if not hop(i) then
			i = indexOf(location) or i -- no money to fly: stay put
		end
		local id = StateData.list[i].id
		if kind == "Rally" then
			table.insert(
				actions,
				{ kind = "Rally", state = id, issue = issueFor(config, view, rng, params, i) }
			)
		else
			table.insert(actions, { kind = "Fundraise", state = id })
		end
	end

	local first = order[1]
	local here = indexOf(location)
	if here ~= nil and Rng.nextFloat(rng) < params.sticky then
		first = here
	end
	local second = order[2]
	if Rng.nextFloat(rng) < params.repeatRally then
		second = first
	end
	if Rng.nextFloat(rng) < params.strongholdRally then
		local theirs = view.players[rival(view)]
		local pool = table.clone(theirs.strongholds)
		if theirs.home then
			table.insert(pool, theirs.home)
		end
		if #pool > 0 then
			second = indexOf(pool[Rng.nextInt(rng, 1, #pool)]) or second
		end
	end
	local ap = profile.apPerWeek
	local funds = params.fundraisers + (if Rng.nextFloat(rng) < params.secondFund then 1 else 0)
	funds = math.min(funds, ap - 1)
	stop(first, "Rally")
	for k = 2, ap do
		if k - 1 <= funds then
			stop(if k == 2 then first else second, "Fundraise")
		else
			stop(second, "Rally")
		end
	end

	-- Money: a few ads in the states that appeal most, ground game late.
	local last = view.week >= config.WEEKS
	local dump = last and Rng.nextFloat(rng) < params.dumpLast
	local reserve = if dump then 0 else params.reserve
	local gotvPlaced: { [number]: number } = {}
	local function gotv(i: number, units: number)
		local have = view.states[i].gotv + (gotvPlaced[i] or 0)
		local n =
			math.min(units, profile.gotvMaxUnits - have, math.floor((cash - reserve) / profile.gotvCost))
		if n > 0 then
			table.insert(actions, { kind = "Gotv", state = StateData.list[i].id, units = n })
			cash -= n * profile.gotvCost
			gotvPlaced[i] = (gotvPlaced[i] or 0) + n
		end
	end
	if dump then
		-- The last week: everything into ground game in the closest-looking big states, then ads.
		for _, i in order do
			gotv(i, profile.gotvMaxUnits)
		end
	elseif view.week >= params.gotvFrom and Rng.nextFloat(rng) < params.gotvChance then
		local placed = 0
		for _, i in order do
			if placed >= params.gotvStates then
				break
			end
			gotv(i, params.gotvUnits)
			if gotvPlaced[i] then
				placed += 1
			end
		end
	end
	local ads = 0
	local k = 1
	while (dump or ads < params.maxAds) and cash - profile.mediaCost >= reserve and k <= #order do
		local i = order[((k - 1) % 4) + 1] -- the top few states, in turn
		table.insert(
			actions,
			{ kind = "Media", state = StateData.list[i].id, issue = issueFor(config, view, rng, params, i) }
		)
		cash -= profile.mediaCost
		ads += 1
		k += 1
		if #actions >= config.PLAN_MAX_ACTIONS then
			break
		end
	end
	return Bot.merge({ actions = actions })
end

-- One call for any phase that wants input, like Bot.act.
function Novice.act(config: Config, view: View, rng: Rng.Rng, candidate: string, params: Params): any
	if params.delegate and params.delegate[view.phase] then
		return Bot.act(config, view, rng, candidate, "Balanced")
	end
	if view.phase == "Select" then
		return select(config, view, rng, candidate)
	elseif view.phase == "Draft" then
		return draft(config, view, rng, params)
	elseif view.phase == "Decision" then
		return decide(config, view, rng, params)
	elseif view.phase == "Debate" then
		return debate(config, view, rng, params)
	elseif view.phase == "Plan" then
		return plan(config, view, rng, params)
	end
	return nil
end

return table.freeze(Novice)
