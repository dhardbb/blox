--!strict
-- Heuristic AI for practice mode and the balance harness. Decent, not optimal.
--
-- The bot sees only its own View, exactly like a client. It values a state by
-- how much one more point of margin there is worth in expected EV:
--   value(S) = EV(S) x pdf(margin / sigma) / sigma
-- with margin read from public polls (or a fresh internal poll) and sigma covering
-- poll error, election noise and the weeks left. That weights states by
-- EV x closeness, and issue matching enters through each action's gain. Plans are
-- built greedily: each AP goes to the best rally or fundraiser on the route, then
-- money goes to the best media buy, attack, poll or ground-game unit until
-- nothing is worth its price. Estimates are updated after every pick, so returns
-- diminish the way the simulation's do.
--
-- This week's event (View.event) enters the same estimates: a Spotlight issue
-- and a Regional rally are worth their multiplier, a Windfall fundraiser in a
-- trailing state its bonus, each within EVENT_CAP per state. A Choice event's
-- stance is the one whose public per-state effects (Events.stanceEffects) are
-- worth the most expected EV on this bot's map (Bot.choose, D-039); debate prep
-- goes where a topic win moves the states this bot needs (Bot.prep, D-040). A
-- candidate who previews next week's event (View.nextEvent) ends the route in a
-- coming Regional's region.
--
-- Styles restrict the balanced policy for the harness's dominance checks.

local Candidates = require("./Candidates")
local ConfigModule = require("./Config")
local Debate = require("./Debate")
local Draft = require("./Draft")
local Events = require("./Events")
local Issues = require("./Issues")
local Plan = require("./Plan")
local Resolve = require("./Resolve")
local Rng = require("./Rng")
local StateData = require("./StateData")
local Support = require("./Support")
local Types = require("../Types")
local ViewModule = require("./View")

type Config = ConfigModule.Config
type View = ViewModule.View

export type Style =
	"Balanced" -- the standard bot
	| "Random" -- random legal actions (the floor the standard bot must beat)
	| "FundraiseOnly" -- spends every AP on fundraisers
	| "RallyOnly" -- spends every AP on rallies
	| "AttackOnly" -- spends media money only on attacks
	| "NeverPoll" -- never buys internal polls
	| "Sandbag" -- stops investing in a state once it estimates a lead over +4
	| "RandomStance" -- the standard bot, but takes a random stance on Choice events (the skill check for D-039)

local Bot = {}

local INV_SQRT_2PI = 1 / math.sqrt(2 * math.pi)
local ISSUES: { Types.Issue } = Issues.list :: any

-- Bot heuristics (not gameplay numbers, so they live here rather than in Config).
-- Left unfrozen so harness experiments can vary them.
Bot.tuning = {
	draftSigma = 8, -- how far the campaign is expected to move a state after the draft
	pollStates = 1, -- paid internal polls per week: the closest big state(s)
	pollMinCash = 0, -- only buy paid polls with at least this much cash
	pollFromWeek = 4, -- first week the bot buys paid polls
	gotvFromWeek = 7, -- start banking ground game this week (9 -> 7, D-021: six weeks of spend, placed after the first debate)
	gotvPremium = 1.3, -- GOTV is hidden and never saturates: value it a little higher (1.2 -> 1.3, D-037: the flat economy pulled late money into ads)
	moneyValue = 0.4, -- value of $1 as a share of the best media buy per dollar (banked money waits a week and buys worse ads than the best one)
	sandbagLead = 4, -- the sandbag bot never pads past this estimated margin
	minValuePerDollar = 0.002, -- below this, money is better banked
	campaignVariance = 2, -- margin variance added per week left in the campaign
}
local T = Bot.tuning

local function pdf(x: number): number
	return INV_SQRT_2PI * math.exp(-0.5 * x * x)
end

local function cdf(x: number): number
	-- Abramowitz-Stegun 7.1.26 via erf; plenty for a heuristic.
	local sign = if x < 0 then -1 else 1
	local z = math.abs(x) / math.sqrt(2)
	local t = 1 / (1 + 0.3275911 * z)
	local poly = t
		* (0.254829592 + t * (-0.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429))))
	return 0.5 * (1 + sign * (1 - poly * math.exp(-z * z)))
end

local function opponentOf(view: View): number
	return if view.you == 1 then 2 else 1
end

local function profileOf(config: Config, view: View, p: number): Candidates.Profile
	return Candidates.profile(config, view.players[p].candidate or Candidates.ids[1])
end

-- Best issue for a positive action by a player with `platform` in state i, and its
-- issue multiplier. A Spotlight issue counts at its event multiplier when ranking.
local function bestIssue(
	config: Config,
	platform: { Types.Issue },
	i: number,
	spotlight: Types.Issue?
): (Types.Issue, number)
	local best: Types.Issue, bestMult, bestScore = ISSUES[1], 0, -math.huge
	for k = 1, #ISSUES do
		local issue: Types.Issue = ISSUES[k]
		local mult = Resolve.issueMult(config, platform, StateData.list[i].issues, issue)
		local score = if issue == spotlight then mult * config.EVENT_SPOTLIGHT_MULT else mult
		if score > bestScore then
			best, bestMult, bestScore = issue, mult, score
		end
	end
	return best, bestMult
end

-- Best attack issue against a target with `platform` in state i.
local function bestAttackIssue(config: Config, platform: { Types.Issue }, i: number): (Types.Issue, number)
	local best: Types.Issue, bestMult = StateData.list[i].issues[1], -math.huge
	local stateIssues = StateData.list[i].issues
	for k = 1, #stateIssues do
		local issue: Types.Issue = stateIssues[k]
		local mult = Resolve.attackMult(config, platform, stateIssues, issue)
		if mult > bestMult then
			best, bestMult = issue, mult
		end
	end
	return best, bestMult
end

-- ---------------------------------------------------------------- select

-- Platform for a candidate: the issues covering the most EV, with a little noise.
function Bot.select(config: Config, view: View, rng: Rng.Rng, candidate: string, style: Style?): any
	local weight: { [string]: number } = {}
	for _, record in StateData.list do
		for _, issue in record.issues do
			weight[issue] = (weight[issue] or 0) + record.ev
		end
	end
	local issues: { Types.Issue } = table.clone(ISSUES)
	local score: { [string]: number } = {}
	for _, issue in issues do
		score[issue] = if style == "Random"
			then Rng.nextFloat(rng)
			else weight[issue] * (0.85 + 0.3 * Rng.nextFloat(rng))
	end
	table.sort(issues, function(a, b)
		return score[a] > score[b]
	end)
	return {
		candidate = candidate,
		color = Candidates.colors[view.you],
		platform = table.move(issues, 1, config.PLATFORM_SIZE, 1, {}),
	}
end

-- ---------------------------------------------------------------- draft

-- Expected margin for player `me` in state i from leans and the draft so far.
local function draftMargin(config: Config, view: View, i: number, me: number): number
	local s = view.states[i]
	local margin = 0
	if s.leanTo ~= nil then
		margin = if s.leanTo == me then s.lean else -s.lean
	end
	if s.owner ~= nil and not s.battleground then
		local big = StateData.list[i].ev >= config.BIG_STATE_EV
		local bonus = if s.isHome
			then (if big then config.HOME_BONUS_BIG else config.HOME_BONUS)
			else (if big then config.STRONGHOLD_BONUS_BIG else config.STRONGHOLD_BONUS)
		-- The normal split moves the margin by 1.3x the bonus.
		margin += (if s.owner == me then 1 else -1) * bonus * (1 + (1 - config.GAIN_FROM_UNDECIDED))
	end
	return margin
end

function Bot.draft(config: Config, view: View, rng: Rng.Rng, style: Style?): any
	local me = view.you
	local round = view.draftRound
	local kind = Draft.kind(config, round)
	local platform: { Types.Issue } = view.players[me].platform or {}
	local scored = {}
	for i, record in StateData.list do
		local s = view.states[i]
		local legal
		if kind == "Nominate" then
			legal = not s.isHome and not s.battleground
		else
			legal = s.owner == nil and not s.battleground
		end
		if legal then
			local value
			if style == "Random" then
				value = Rng.nextFloat(rng)
			else
				local m = draftMargin(config, view, i, me)
				local big = record.ev >= config.BIG_STATE_EV
				if kind == "Nominate" then
					-- Resetting a state to its lean: good when it strips an opponent's bonus.
					local lean = if s.leanTo == nil then 0 elseif s.leanTo == me then s.lean else -s.lean
					value = record.ev * (cdf(lean / T.draftSigma) - cdf(m / T.draftSigma))
				else
					local bonus = if kind == "Home"
						then (if big then config.HOME_BONUS_BIG else config.HOME_BONUS)
						else (if big then config.STRONGHOLD_BONUS_BIG else config.STRONGHOLD_BONUS)
					local after = m + bonus * (2 - config.GAIN_FROM_UNDECIDED)
					value = record.ev * (cdf(after / T.draftSigma) - cdf(m / T.draftSigma))
					for _, issue in record.issues do
						if table.find(platform, issue) then
							value *= 1.1
						end
					end
					if kind == "Home" then
						value += #record.adjacent * 0.15 -- a well-connected base for the route
					end
				end
				value *= 0.9 + 0.2 * Rng.nextFloat(rng)
			end
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

-- ---------------------------------------------------------------- plan

type Estimate = {
	margin: number, -- my estimated margin over the opponent (support points)
	mine: number, -- my estimated support share
	undecided: number,
	sigma: number,
	momentum: number, -- my momentum after this week's planned gains (pre-decay units)
	theirMomentum: number,
	bought: number, -- media buys planned here this week
	gotv: number, -- my units, placed plus planned
}

local function buildEstimates(config: Config, view: View): { Estimate }
	local me, them = view.you, opponentOf(view)
	local weeksLeft = math.max(0, config.WEEKS - view.week)
	local campaign = T.campaignVariance * weeksLeft
	local fresh: { [string]: any } = {}
	for _, poll in view.internalPolls do
		fresh[poll.state] = poll
	end
	local out: { Estimate } = {}
	for i, s in view.states do
		local poll = s.poll
		local mine, theirs, undecided = 35, 35, 30
		local errorVar = config.POLL_SIGMA ^ 2
		if fresh[s.id] then
			local f = fresh[s.id]
			mine, theirs, undecided = f.support[me], f.support[them], f.undecided
			errorVar = config.INTERNAL_POLL_ERROR ^ 2
		elseif poll ~= nil then
			mine, theirs, undecided = poll.support[me], poll.support[them], poll.undecided
		end
		out[i] = {
			margin = mine - theirs + config.GOTV_PER_UNIT * s.gotv,
			mine = mine,
			undecided = undecided,
			sigma = math.sqrt(errorVar + config.ELECTION_SIGMA ^ 2 + campaign),
			momentum = s.momentum[me] * 0.5,
			theirMomentum = s.momentum[them] * 0.5,
			bought = 0,
			gotv = s.gotv,
		}
	end
	return out
end

Bot.estimates = buildEstimates

-- Expected EV per point of margin in a state.
local function marginValue(e: Estimate, ev: number): number
	return ev * pdf(e.margin / e.sigma) / e.sigma
end

-- Margin a positive gain of `g` support points buys (the normal split).
local function marginFromGain(config: Config, e: Estimate, g: number): number
	local fromOpponent = if e.undecided >= config.UNDECIDED_FLOOR then 1 - config.GAIN_FROM_UNDECIDED else 1
	return g * (1 + fromOpponent)
end

-- Extra drift (as margin) from adding `m` momentum to my side this week.
local function driftGain(config: Config, e: Estimate, m: number): number
	local function drift(mine: number): number
		local gap = math.min(config.MOMENTUM_CAP, mine) - e.theirMomentum
		return math.min(config.DRIFT_RATE * math.max(0, gap), config.DRIFT_CAP)
	end
	return marginFromGain(config, e, drift(e.momentum + m) - drift(e.momentum))
end

local function apply(config: Config, e: Estimate, gain: number, momentum: number)
	local margin = marginFromGain(config, e, gain) + driftGain(config, e, momentum)
	e.margin += margin
	e.mine += gain
	e.momentum += momentum
end

function Bot.plan(config: Config, view: View, rng: Rng.Rng, style: Style?): any
	local me, them = view.you, opponentOf(view)
	local profile = profileOf(config, view, me)
	local player = view.players[me]
	local platform: { Types.Issue } = player.platform or {}
	local theirPlatform: { Types.Issue } = view.players[them].platform or {}
	local cash = player.cash or 0
	local week = view.week
	local closing = Resolve.closingMult(config, week)
	local actions: { any } = {}
	local estimates = buildEstimates(config, view)
	local prep = nil
	if table.find(config.DEBATE_WEEKS, week + 1) then
		prep = Bot.prep(config, view, estimates)
	end

	local event = view.event
	local choice: Types.Choice? = nil
	if event ~= nil and event.kind == "Choice" then
		choice = Bot.choose(config, view, estimates, rng, style)
	end
	local spotlight: Types.Issue? = if event ~= nil and event.kind == "Spotlight" then event.issue else nil

	if style == "Random" then
		return Bot.randomPlan(config, view, rng, prep, choice)
	end

	local underdogRally, underdogFund = 1, 1
	if player.underdogTier == 1 then
		underdogRally, underdogFund = config.UNDERDOG_RALLY_1, config.UNDERDOG_FUND_1
	elseif player.underdogTier == 2 then
		underdogRally, underdogFund = config.UNDERDOG_RALLY_2, config.UNDERDOG_FUND_2
	end
	underdogRally = 1 + (underdogRally - 1) * profile.underdogScale
	underdogFund = 1 + (underdogFund - 1) * profile.underdogScale
	if player.frontrunner then
		underdogRally *= profile.frontrunnerRallyMult
		underdogFund *= profile.frontrunnerFundMult
	end

	local function capped(i: number): boolean
		return style == "Sandbag" and estimates[i].margin > T.sandbagLead
	end

	local function bg(i: number): number
		return if view.states[i].battleground then config.BATTLEGROUND_MULT else 1
	end

	-- Event bonuses already planned per state this week (support, money), so the
	-- estimates respect EVENT_CAP like Resolve does.
	local eventSupport: { [number]: number } = {}
	local eventMoney: { [number]: number } = {}
	local function withEvent(i: number, kind: "Rally" | "Media", issue: Types.Issue, gain: number): number
		local mult = Events.supportMult(config, event, kind, issue, i)
		if mult <= 1 then
			return gain
		end
		local room = math.max(0, config.EVENT_CAP - (eventSupport[i] or 0))
		return gain + math.min(gain * (mult - 1), room)
	end
	local function moneyWithEvent(i: number, money: number): number
		local mult = Events.fundMult(config, event, view.states[i].poll, me)
		if mult <= 1 then
			return money
		end
		local room = math.max(0, config.EVENT_CAP - (eventMoney[i] or 0))
		return money + math.min(money * (mult - 1), room)
	end

	-- Value and parameters of the next media buy (positive or attack) in state i.
	local function mediaOption(i: number, attack: boolean): (number, Types.Issue)
		local e = estimates[i]
		local factor = profile.mediaSaturation ^ e.bought
		local value: number, issue: Types.Issue
		if attack then
			local mult
			issue, mult = bestAttackIssue(config, theirPlatform, i)
			local loss = config.ATTACK_LOSS * mult * profile.mediaMult * bg(i) * closing * factor
			local margin = loss * (2 - config.ATTACK_TO_UNDECIDED)
			if view.states[i].backlash >= config.BACKLASH_THRESHOLD - 1 then
				margin -= config.BACKLASH_PENALTY -- the next one triggers backlash
			end
			value = marginValue(e, StateData.list[i].ev) * margin
		else
			local mult
			issue, mult = bestIssue(config, platform, i, spotlight)
			local gain = config.MEDIA_SUPPORT
				* mult
				* profile.mediaMult
				* bg(i)
				* closing
				* factor
				* Support.saturation(config, e.mine)
			gain = withEvent(i, "Media", issue, gain)
			value = marginValue(e, StateData.list[i].ev)
				* (marginFromGain(config, e, gain) + driftGain(config, e, config.MEDIA_MOMENTUM * factor))
		end
		return value, issue
	end

	-- Value of a dollar this week: the best first media buy per dollar.
	local lambda = 0
	for i in estimates do
		if not capped(i) then
			local value = mediaOption(i, style == "AttackOnly")
			lambda = math.max(lambda, value / profile.mediaCost)
		end
	end
	lambda *= T.moneyValue
	if week >= config.WEEKS then
		lambda *= 0.25 -- money is nearly worthless after this week
	end

	-- 1. The route: each AP to the best rally or fundraiser.
	local location = player.location
	local fundraised: { [number]: number } = {}
	local opponentFundraised: { [string]: boolean } = {}
	local card = view.players[them].card
	if card then
		for _, id in card.fundraisers do
			opponentFundraised[id] = true
		end
	end
	local ap = profile.apPerWeek
	local reserve = 0
	-- The Pollster's preview (D-035): with a Regional event due next week, ending this
	-- week's route in its region saves the flight and starts the boosted rallies
	-- without one. Worth a flight plus a share of a rally there.
	local nextRegion: Types.Region? = nil
	local preview = view.nextEvent
	if preview ~= nil and preview.kind == "Regional" then
		nextRegion = preview.region
	end
	for k = 1, ap do
		local best: any, bestValue = nil, 0
		for i, record in StateData.list do
			local adjacent = Plan.isAdjacent(location, record.id)
			local flight = if adjacent then 0 else config.FLIGHT_COST
			if flight <= cash - reserve then
				local e = estimates[i]
				local flightValue = flight * lambda
				if k == ap and nextRegion ~= nil and record.region == nextRegion then
					local boostedRally = (config.EVENT_REGIONAL_MULT - 1) * profile.rallySupport * bg(i)
					local stayValue = marginValue(e, record.ev) * marginFromGain(config, e, boostedRally)
					flightValue -= config.FLIGHT_COST * lambda + stayValue
				end
				if style ~= "FundraiseOnly" and not capped(i) then
					local issue: Types.Issue, mult = bestIssue(config, platform, i, spotlight)
					local base = profile.rallySupport
						* mult
						* profile.rallyMult
						* bg(i)
						* underdogRally
						* closing
						* Support.saturation(config, e.mine)
					local gain = withEvent(i, "Rally", issue, base)
					local margin = marginFromGain(config, e, gain)
						+ driftGain(config, e, config.RALLY_MOMENTUM)
					local value = marginValue(e, record.ev) * margin - flightValue
					if value > bestValue then
						best, bestValue =
							{
								kind = "Rally",
								state = record.id,
								issue = issue,
								i = i,
								gain = gain,
								base = base,
							}, value
					end
				end
				if style ~= "RallyOnly" then
					local s = view.states[i]
					local share = e.mine / 100
					local raw = config.FUNDRAISER_BASE + config.FUNDRAISER_PER_SHARE * share
					local pool = s.capacity
					if opponentFundraised[record.id] then
						pool *= 0.6
					end
					pool -= fundraised[i] or 0
					local yield = math.max(0, math.min(pool, raw))
					local home = if s.isHome and s.owner == me then config.HOME_FUNDRAISE_MULT else 1
					local base = yield * profile.fundraiseMult * home * underdogFund
					local money = moneyWithEvent(i, base)
					local value = money * lambda - flightValue
					if value > bestValue then
						best, bestValue =
							{
								kind = "Fundraise",
								state = record.id,
								i = i,
								money = money,
								base = base,
								raw = yield,
							}, value
					end
				end
			end
		end
		if best == nil then
			break
		end
		if not Plan.isAdjacent(location, best.state) then
			cash -= config.FLIGHT_COST
		end
		location = best.state
		if best.kind == "Rally" then
			table.insert(actions, { kind = "Rally", state = best.state, issue = best.issue })
			apply(config, estimates[best.i], best.gain, config.RALLY_MOMENTUM)
			eventSupport[best.i] = (eventSupport[best.i] or 0) + best.gain - best.base
		else
			table.insert(actions, { kind = "Fundraise", state = best.state })
			fundraised[best.i] = (fundraised[best.i] or 0) + best.raw
			eventMoney[best.i] = (eventMoney[best.i] or 0) + best.money - best.base
		end
	end

	-- 2. Internal polls: the closest big states, unless already polled fresh.
	if style ~= "NeverPoll" and week < config.WEEKS and week >= T.pollFromWeek then
		local polled = {}
		for _, poll in view.internalPolls do
			polled[poll.state] = true
		end
		local order = {}
		for i, record in StateData.list do
			if not polled[record.id] and record.ev >= 8 then
				table.insert(order, { i = i, value = marginValue(estimates[i], record.ev) })
			end
		end
		table.sort(order, function(a, b)
			return a.value > b.value
		end)
		local free = profile.freePolls
		for k = 1, math.min(T.pollStates + free, #order) do
			local cost = if free > 0 then 0 else config.INTERNAL_POLL_COST
			if k > T.pollStates and cost > 0 then
				break
			end
			if cost <= cash and (cost == 0 or cash >= T.pollMinCash) and order[k].value > 0.05 then
				table.insert(actions, { kind = "Poll", state = StateData.list[order[k].i].id })
				cash -= cost
				free = math.max(0, free - 1)
			end
		end
	end

	-- 3. Money: media, attacks and (late) ground game, best value per dollar first.
	local guard = 0
	while guard < config.PLAN_MAX_ACTIONS - #actions do
		guard += 1
		local best: any, bestPerDollar = nil, T.minValuePerDollar
		for i, record in StateData.list do
			if not capped(i) then
				local e = estimates[i]
				if profile.mediaCost <= cash then
					if style ~= "AttackOnly" then
						local value, issue = mediaOption(i, false)
						local perDollar = value / profile.mediaCost
						if perDollar > bestPerDollar then
							best, bestPerDollar = { kind = "Media", i = i, issue = issue }, perDollar
						end
					end
					local value, issue = mediaOption(i, true)
					local perDollar = value / profile.mediaCost
					if perDollar > bestPerDollar then
						best, bestPerDollar = { kind = "Attack", i = i, issue = issue }, perDollar
					end
				end
				if week >= T.gotvFromWeek and profile.gotvCost <= cash and e.gotv < profile.gotvMaxUnits then
					-- Hidden from polls and never saturates: worth a premium late.
					local perDollar = marginValue(e, record.ev)
						* config.GOTV_PER_UNIT
						* T.gotvPremium
						/ profile.gotvCost
					if perDollar > bestPerDollar then
						best, bestPerDollar = { kind = "Gotv", i = i }, perDollar
					end
				end
			end
		end
		if best == nil then
			break
		end
		local e = estimates[best.i]
		local id = StateData.list[best.i].id
		if best.kind == "Gotv" then
			table.insert(actions, { kind = "Gotv", state = id, units = 1 })
			cash -= profile.gotvCost
			e.gotv += 1
			e.margin += config.GOTV_PER_UNIT
		else
			local attack = best.kind == "Attack"
			table.insert(actions, { kind = best.kind, state = id, issue = best.issue })
			cash -= profile.mediaCost
			local factor = profile.mediaSaturation ^ e.bought
			e.bought += 1
			if attack then
				local _, mult = bestAttackIssue(config, theirPlatform, best.i)
				e.margin += config.ATTACK_LOSS * mult * profile.mediaMult * bg(best.i) * closing * factor * 1.4
			else
				local _, mult = bestIssue(config, platform, best.i, spotlight)
				local base = config.MEDIA_SUPPORT
					* mult
					* profile.mediaMult
					* bg(best.i)
					* closing
					* factor
					* Support.saturation(config, e.mine)
				local gain = withEvent(best.i, "Media", best.issue, base)
				eventSupport[best.i] = (eventSupport[best.i] or 0) + gain - base
				apply(config, e, gain, config.MEDIA_MOMENTUM * factor)
			end
		end
	end

	return Bot.merge({ actions = actions, prep = prep, choice = choice })
end

-- Merges repeated single GOTV units in one state into one action.
function Bot.merge(plan: any): any
	local out = {}
	local gotvAt: { [string]: any } = {}
	for _, action in plan.actions do
		if action.kind == "Gotv" and gotvAt[action.state] then
			gotvAt[action.state].units += action.units
		else
			table.insert(out, action)
			if action.kind == "Gotv" then
				gotvAt[action.state] = action
			end
		end
	end
	return { actions = out, prep = plan.prep, choice = plan.choice }
end

-- Expected EV a stance is worth to a candidate with `platform`: each state's
-- public reaction (Events.stanceEffects) as margin, weighted by how much a point
-- of margin there is worth. A loss goes to undecided, so it costs exactly its
-- points of margin.
function Bot.stanceValue(
	config: Config,
	estimates: { Estimate },
	event: ViewModule.EventView,
	id: Types.Choice,
	platform: { Types.Issue },
	base: { string }?
): number
	local definition = Events.byId[event.id]
	if definition == nil then
		return 0
	end
	local value = 0
	for i, record in StateData.list do
		local points = Events.stanceEffect(config, definition, id, i, platform, base)
		if points ~= 0 then
			local e = estimates[i]
			local margin = if points > 0 then marginFromGain(config, e, points) else points
			value += marginValue(e, record.ev) * margin
		end
	end
	return value
end

-- The stance on this week's Choice event: the one worth the most expected EV on
-- this bot's map (ties go to the first slot, so no seat is favored). The Random
-- and RandomStance styles pick uniformly.
function Bot.choose(
	config: Config,
	view: View,
	estimates: { Estimate },
	rng: Rng.Rng,
	style: Style?
): Types.Choice
	if style == "Random" or style == "RandomStance" then
		return Events.CHOICES[Rng.nextInt(rng, 1, #Events.CHOICES)]
	end
	local event = view.event
	local platform: { Types.Issue } = view.players[view.you].platform or {}
	local base = Events.baseOf(view.players[view.you])
	local best: Types.Choice, bestValue = Events.CHOICES[1], -math.huge
	if event ~= nil then
		for k = 1, #Events.CHOICES do
			local id: Types.Choice = Events.CHOICES[k]
			local value = Bot.stanceValue(config, estimates, event, id, platform, base)
			if value > bestValue then
				best, bestValue = id, value
			end
		end
	end
	return best
end

-- Expected EV of winning topic t for `view.you`: the topic's states (where the
-- win lands DEBATE_TOPIC_WIN) plus the flat national part everywhere; and what a
-- gaffe there would cost.
function Bot.topicValue(config: Config, estimates: { Estimate }, topic: Types.Issue): (number, number)
	local win, gaffe = 0, 0
	for i, record in StateData.list do
		local e = estimates[i]
		local worth = marginValue(e, record.ev)
		win += worth * marginFromGain(config, e, config.DEBATE_TOPIC_NATIONAL)
		if table.find(record.issues, topic) then
			win += worth * marginFromGain(config, e, config.DEBATE_TOPIC_WIN)
			gaffe += worth * config.DEBATE_GAFFE
		end
	end
	return win, gaffe
end

-- Debate prep: the split (at most DEBATE_MAX_PER_TOPIC on a topic) with the most
-- expected EV, from the odds of winning each topic (Debate.odds) against an
-- opponent assumed to spread their prep evenly, the topic's value on this map,
-- and the gaffe a zero risks. Every split is tried: the roll makes returns
-- convex near a big deficit, so a greedy point-by-point split can miss the best one.
function Bot.prep(config: Config, view: View, estimates: { Estimate }?): { number }?
	local topics = view.nextDebate and view.nextDebate.topics
	if topics == nil then
		return nil
	end
	local me, them = view.you, opponentOf(view)
	local profile, theirProfile = profileOf(config, view, me), profileOf(config, view, them)
	local mine: { Types.Issue } = view.players[me].platform or {}
	local theirs: { Types.Issue } = view.players[them].platform or {}
	local es = estimates or buildEstimates(config, view)
	local fixed: { number } = {} -- my fixed score minus their expected one, per topic
	local values: { number } = {}
	local gaffes: { number } = {}
	local theirEven = theirProfile.debatePrep / #topics
	for t = 1, #topics do
		local topic: Types.Issue = topics[t]
		fixed[t] = (if table.find(mine, topic) then config.DEBATE_PLATFORM_BONUS else 0)
			- (if table.find(theirs, topic) then config.DEBATE_PLATFORM_BONUS else 0)
			+ profile.debateStat
			- theirProfile.debateStat
			- theirEven
		values[t], gaffes[t] = Bot.topicValue(config, es, topic)
	end
	local function expected(t: number, points: number): number
		local win, _, lose = Debate.odds(config, fixed[t] + points)
		return win * values[t] - (if points == 0 then lose * gaffes[t] else 0)
	end
	local best: { number } = Plan.defaultPrep(config, profile.debatePrep)
	local bestTotal = -math.huge
	local split = table.create(#topics, 0)
	local function search(t: number, left: number, total: number)
		if t > #topics then
			if left == 0 and total > bestTotal then
				best, bestTotal = table.clone(split), total
			end
			return
		end
		local most = math.min(left, config.DEBATE_MAX_PER_TOPIC)
		local least = if t == #topics
			then left
			else math.max(0, left - (#topics - t) * config.DEBATE_MAX_PER_TOPIC)
		for points = most, least, -1 do
			split[t] = points
			search(t + 1, left - points, total + expected(t, points))
		end
		split[t] = 0
	end
	search(1, profile.debatePrep, 0)
	return best
end

-- Random legal actions: the floor every real strategy must beat.
function Bot.randomPlan(
	config: Config,
	view: View,
	rng: Rng.Rng,
	prep: { number }?,
	choice: Types.Choice?
): any
	local me = view.you
	local profile = profileOf(config, view, me)
	local player = view.players[me]
	local platform: { Types.Issue } = player.platform or ISSUES
	local cash = player.cash or 0
	local location = player.location
	local actions: { any } = {}
	for _ = 1, profile.apPerWeek do
		local record = StateData.list[Rng.nextInt(rng, 1, #StateData.list)]
		local flight = if Plan.isAdjacent(location, record.id) then 0 else config.FLIGHT_COST
		if flight <= cash then
			cash -= flight
			location = record.id
			if Rng.nextFloat(rng) < 0.5 then
				local issue = platform[Rng.nextInt(rng, 1, #platform)]
				table.insert(actions, { kind = "Rally", state = record.id, issue = issue })
			else
				table.insert(actions, { kind = "Fundraise", state = record.id })
			end
		end
	end
	while cash >= profile.mediaCost and Rng.nextFloat(rng) < 0.7 do
		local record = StateData.list[Rng.nextInt(rng, 1, #StateData.list)]
		local issue = ISSUES[Rng.nextInt(rng, 1, #ISSUES)]
		table.insert(actions, { kind = "Media", state = record.id, issue = issue })
		cash -= profile.mediaCost
	end
	return { actions = actions, prep = prep, choice = choice }
end

-- One call for any phase that wants input (the harness and practice mode use this).
function Bot.act(config: Config, view: View, rng: Rng.Rng, candidate: string, style: Style?): any
	if view.phase == "Select" then
		return Bot.select(config, view, rng, candidate, style)
	elseif view.phase == "Draft" then
		return Bot.draft(config, view, rng, style)
	elseif view.phase == "Plan" then
		return Bot.plan(config, view, rng, style)
	end
	return nil
end

return table.freeze(Bot)
