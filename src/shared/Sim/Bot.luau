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
-- trailing state its bonus, each within EVENT_CAP per state. In a Decision phase
-- (D-044) a Choice event's stance is the one whose public per-state effects
-- (Events.stanceEffects) are worth the most expected EV on this bot's map
-- (Bot.choose, D-039). In a debate round (D-062) it plays the move whose worst
-- outcome is best on its map, and stakes its Zinger where a likely win lands
-- on the states worth the most (Bot.debate). A
-- candidate who previews next week's event (View.nextEvent) ends the route in a
-- coming Regional's region.
--
-- Paid internal polls scout the opponent's hidden ground game (D-049): from
-- scoutFromWeek the bot polls the close states it has not just polled (a region
-- when enough of them share one), pays for none while the opponent's cash shows
-- Low, and counts every unit a poll saw against its own margin there, so the
-- money step answers with ads or ground game where the race is really close.
--
-- Styles restrict the balanced policy for the harness's dominance checks.
--
-- Difficulty (practice mode, D-057): Medium is the Balanced style, unchanged.
-- Easy misjudges: every plan it weighs each state's worth by a random factor
-- (BOT_EASY_NOISE), drafts on a noisier read, and slips into a random debate
-- move or stance half the time (BOT_EASY_SLIP). Hard and Extreme see exactly
-- what Medium sees, the View, and use it better: they predict the opponent's
-- plan by running the standard bot from the opponent's side of the public board
-- (their cash guessed from its money bracket) and count it against this week's
-- margins (BOT_HARD_FORESIGHT); they value a state by how much it moves the
-- chance of reaching 270, not expected EV alone (BOT_HARD_WIN_CHANCE); and in a
-- debate round they best-reply to the move the standard bot would play from the
-- opponent's side (BOT_DEBATE_READ). Extreme is Hard with the win-chance weight
-- pushed three times as far: it defends the close states it leads harder when
-- ahead and reaches further for the ones it trails when behind; in debates it
-- also reads the opponent's own past moves (BOT_EXTREME_HISTORY).

local Candidates = require("./Candidates")
local ConfigModule = require("./Config")
local Debate = require("./Debate")
local Draft = require("./Draft")
local Events = require("./Events")
local IssueMap = require("./IssueMap")
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
	| "RandomMove" -- the standard bot, but random debate moves and a random Zinger round (the skill check for D-062)
	| "NoAnswer" -- the standard bot, but never answers a debate round (the canned answer: what a timeout costs, D-062)
	| "AlwaysDefend" -- the standard bot, but always Defends in a debate (no move may dominate, D-062)
	| "AlwaysAttack" -- the standard bot, but always Attacks in a debate
	| "AlwaysPivot" -- the standard bot, but always Pivots in a debate
	| "TopIssues" -- the standard bot, but runs on the three highest-EV issues (the niche check for D-047)
	| "NicheIssues" -- the standard bot, but runs on the three lowest-EV issues (the niche check for D-047)
	| "Easy" -- practice difficulty Easy (D-057)
	| "Hard" -- practice difficulty Hard (D-057)
	| "Extreme" -- practice difficulty Extreme (D-057)

-- Practice difficulty (D-057). Medium plays the Balanced style.
export type Difficulty = "Easy" | "Medium" | "Hard" | "Extreme"

local Bot = {}

local DIFFICULTIES: { Difficulty } = { "Easy", "Medium", "Hard", "Extreme" }
local DEFAULT_DIFFICULTY: Difficulty = "Medium"
Bot.DIFFICULTIES = table.freeze(DIFFICULTIES)
Bot.DEFAULT_DIFFICULTY = DEFAULT_DIFFICULTY

-- A difficulty from untrusted input: one of the four names, else Medium.
function Bot.difficulty(value: any): Difficulty
	for k = 1, #DIFFICULTIES do
		local level: Difficulty = DIFFICULTIES[k]
		if value == level then
			return level
		end
	end
	return DEFAULT_DIFFICULTY
end

-- The style a difficulty plays (Medium is the standard Balanced bot).
function Bot.styleFor(difficulty: Difficulty?): Style
	local level = Bot.difficulty(difficulty)
	if level == "Easy" then
		return "Easy"
	elseif level == "Hard" then
		return "Hard"
	elseif level == "Extreme" then
		return "Extreme"
	end
	return "Balanced"
end

local INV_SQRT_2PI = 1 / math.sqrt(2 * math.pi)
local ISSUES: { Types.Issue } = Issues.list :: any

-- Bot heuristics (not gameplay numbers, so they live here rather than in Config).
-- Left unfrozen so harness experiments can vary them.
Bot.tuning = {
	draftSigma = 8, -- how far the campaign is expected to move a state after the draft
	pollStates = 1, -- internal polls per week before scouting starts (free ones count): the closest big state(s)
	pollMinCash = 0, -- only buy paid polls with at least this much cash
	pollFromWeek = 4, -- first week the bot buys paid polls
	scoutFromWeek = 7, -- from this week, polls scout the opponent's ground game (D-049; the bot's own ground game starts then too)
	scoutPolls = 1, -- internal polls per week while scouting (free ones count)
	scoutMinValue = 0.05, -- skip states whose margin is worth less than this (EV per point)
	scoutResponse = 1, -- share of the opponent's scouted units the bot counts against its margin
	regionPollShare = 1.5, -- buy a region poll when its states are worth this many times the singles its price would buy
	gotvFromWeek = 6, -- start banking ground game this week (9 -> 7, D-021: six weeks of spend, placed after the first debate; 7 -> 6, D-049: a dearer unit needs a longer runway)
	gotvPremium = 1.5, -- GOTV is hidden and never saturates: value it a little higher (1.2 -> 1.3, D-037: the flat economy pulled late money into ads; 1.3 -> 1.5, D-049: the $2.5 unit)
	moneyValue = 0.4, -- value of $1 as a share of the best media buy per dollar (banked money waits a week and buys worse ads than the best one)
	sandbagLead = 4, -- the sandbag bot never pads past this estimated margin
	minValuePerDollar = 0.002, -- below this, money is better banked
	campaignVariance = 2, -- margin variance added per week left in the campaign
	freshPollVar = 1, -- a fresh internal poll keeps this share of the public poll's error variance (0 -> 1, D-049: trusting a poll's exact read made the bot pile into one razor-close state)
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

-- Best issue for a positive action by a player with `platform` in a state whose
-- top issues are `stateIssues`, and its issue multiplier. A Spotlight issue counts
-- at its event multiplier when ranking.
local function bestIssue(
	config: Config,
	platform: { Types.Issue },
	stateIssues: { Types.Issue },
	platformMults: { [string]: number },
	spotlight: Types.Issue?
): (Types.Issue, number)
	local best: Types.Issue, bestMult, bestScore = ISSUES[1], 0, -math.huge
	for k = 1, #ISSUES do
		local issue: Types.Issue = ISSUES[k]
		local mult = Resolve.issueMult(config, platform, stateIssues, issue, platformMults)
		local score = if issue == spotlight then mult * config.EVENT_SPOTLIGHT_MULT else mult
		if score > bestScore then
			best, bestMult, bestScore = issue, mult, score
		end
	end
	return best, bestMult
end

-- Best attack issue against a target with `platform` in a state whose top issues
-- are `stateIssues`.
local function bestAttackIssue(
	config: Config,
	platform: { Types.Issue },
	stateIssues: { Types.Issue }
): (Types.Issue, number)
	local best: Types.Issue, bestMult = stateIssues[1], -math.huge
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

-- Platform for a candidate: three issues at random. Niche issues hit harder
-- (D-047), tuned until running on the match's three biggest or three smallest
-- issues wins about as often as a mixed platform, so no issue is the right pick
-- before the draft says where the campaign will be fought. The TopIssues and
-- NicheIssues styles are the harness's check of that.
function Bot.select(config: Config, view: View, rng: Rng.Rng, candidate: string, style: Style?): any
	-- Candidates are unique (D-048): keep a claim already made; a candidate the
	-- opponent holds gives way to a free one drawn from the bot's stream.
	local claims: { [string]: number } = view.claims or {}
	for id, owner in claims do
		if owner == view.you then
			candidate = id
		end
	end
	local owner = claims[candidate]
	if owner ~= nil and owner ~= view.you then
		local free: { string } = {}
		for _, id in Candidates.ids do
			if claims[id] == nil then
				table.insert(free, id)
			end
		end
		candidate = free[Rng.nextInt(rng, 1, #free)]
	end
	local ev = IssueMap.evByIssue(view.issueMap)
	local issues: { Types.Issue } = table.clone(ISSUES)
	local score: { [string]: number } = {}
	for _, issue in issues do
		local noise = Rng.nextFloat(rng)
		if style == "TopIssues" then
			score[issue] = ev[issue] + noise
		elseif style == "NicheIssues" then
			score[issue] = -ev[issue] + noise
		else
			score[issue] = noise
		end
	end
	table.sort(issues, function(a, b)
		return score[a] > score[b]
	end)
	return {
		candidate = candidate,
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
					for _, issue in view.issueMap[i] do
						if table.find(platform, issue) then
							value *= 1.1
						end
					end
					if kind == "Home" then
						value += #record.adjacent * 0.15 -- a well-connected base for the route
					end
				end
				if style == "Easy" then
					value *= math.exp(Rng.gaussian(rng, 0, config.BOT_EASY_NOISE)) -- a hazier read (D-057)
				else
					value *= 0.9 + 0.2 * Rng.nextFloat(rng)
				end
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
	theirGotv: number, -- the opponent's units, as my latest internal poll there saw them (0 if never polled; D-049)
	weight: number, -- scales what a point of margin here is worth (1 for Medium; D-057)
}

local function buildEstimates(config: Config, view: View): { Estimate }
	local me, them = view.you, opponentOf(view)
	local weeksLeft = math.max(0, config.WEEKS - view.week)
	local campaign = T.campaignVariance * weeksLeft
	local fresh: { [string]: any } = {}
	for _, poll in view.internalPolls do
		fresh[poll.state] = poll
	end
	local scouted: { [string]: any } = {}
	for _, scout in view.scouted do
		scouted[scout.state] = scout
	end
	local out: { Estimate } = {}
	for i, s in view.states do
		local poll = s.poll
		local mine, theirs, undecided = 35, 35, 30
		local errorVar = config.POLL_SIGMA ^ 2
		if fresh[s.id] then
			local f = fresh[s.id]
			mine, theirs, undecided = f.support[me], f.support[them], f.undecided
			errorVar = math.max(config.INTERNAL_POLL_ERROR ^ 2, T.freshPollVar * config.POLL_SIGMA ^ 2)
		elseif poll ~= nil then
			mine, theirs, undecided = poll.support[me], poll.support[them], poll.undecided
		end
		local theirGotv = if scouted[s.id] then (scouted[s.id].gotv[them] or 0) * T.scoutResponse else 0
		out[i] = {
			margin = mine - theirs + config.GOTV_PER_UNIT * (s.gotv - theirGotv),
			mine = mine,
			undecided = undecided,
			sigma = math.sqrt(errorVar + config.ELECTION_SIGMA ^ 2 + campaign),
			momentum = s.momentum[me] * 0.5,
			theirMomentum = s.momentum[them] * 0.5,
			bought = 0,
			gotv = s.gotv,
			theirGotv = theirGotv,
			weight = 1,
		}
	end
	return out
end

Bot.estimates = buildEstimates

-- Expected EV per point of margin in a state.
local function marginValue(e: Estimate, ev: number): number
	return e.weight * ev * pdf(e.margin / e.sigma) / e.sigma
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

-- The greedy plan on `estimates` (updated in place as actions are picked).
local function planOn(config: Config, view: View, style: Style?, estimates: { Estimate }): any
	local me, them = view.you, opponentOf(view)
	local profile = profileOf(config, view, me)
	local player = view.players[me]
	local platform: { Types.Issue } = player.platform or {}
	local theirPlatform: { Types.Issue } = view.players[them].platform or {}
	local cash = player.cash or 0
	local week = view.week
	local closing = Resolve.closingMult(config, week)
	local actions: { any } = {}

	local event = view.event
	local spotlight: Types.Issue? = if event ~= nil and event.kind == "Spotlight" then event.issue else nil

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
			issue, mult = bestAttackIssue(config, theirPlatform, view.issueMap[i])
			local loss = config.ATTACK_LOSS * mult * profile.mediaMult * bg(i) * closing * factor
			local margin = loss * (2 - config.ATTACK_TO_UNDECIDED)
			if view.states[i].backlash >= config.BACKLASH_THRESHOLD - 1 then
				margin -= config.BACKLASH_PENALTY -- the next one triggers backlash
			end
			value = marginValue(e, StateData.list[i].ev) * margin
		else
			local mult
			issue, mult = bestIssue(config, platform, view.issueMap[i], view.platformMults, spotlight)
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
					local issue: Types.Issue, mult =
						bestIssue(config, platform, view.issueMap[i], view.platformMults, spotlight)
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

	-- 2. Internal polls. Early: the closest big state, for a sharper read. From
	-- scoutFromWeek (D-049): the close states not polled last week, to see the
	-- opponent's ground game there before election night.
	if style ~= "NeverPoll" and week < config.WEEKS and week >= T.pollFromWeek then
		local polled = {}
		for _, poll in view.internalPolls do
			polled[poll.state] = true
		end
		local scouting = week >= T.scoutFromWeek
		local order = {}
		for i, record in StateData.list do
			if not polled[record.id] and (scouting or record.ev >= 8) then
				table.insert(order, { i = i, value = marginValue(estimates[i], record.ev) })
			end
		end
		table.sort(order, function(a, b)
			if a.value ~= b.value then
				return a.value > b.value
			end
			return a.i < b.i
		end)
		local free = profile.freePolls
		local wanted = if scouting then T.scoutPolls else T.pollStates
		if scouting and view.players[them].money == "Low" then
			wanted = 0 -- they can barely afford ground game: only the free polls
		end
		local covered: { [number]: boolean } = {}
		local minValue = if scouting then T.scoutMinValue else 0.05

		-- A region poll when its worthwhile states are worth more than the singles
		-- its price would buy (the free polls are spent first, on the best states).
		if scouting and wanted > 0 and config.REGION_POLL_COST <= cash then
			local singles = math.floor(config.REGION_POLL_COST / config.INTERNAL_POLL_COST)
			local benchmark = 0
			for k = free + 1, math.min(free + singles, #order) do
				benchmark += order[k].value
			end
			local byRegion: { [string]: number } = {}
			for k = free + 1, #order do
				local entry = order[k]
				if entry.value > minValue then
					local region = StateData.list[entry.i].region
					byRegion[region] = (byRegion[region] or 0) + entry.value
				end
			end
			local bestRegion, bestTotal = nil, benchmark * T.regionPollShare
			for _, region in Issues.regions do
				local total = byRegion[region] or 0
				if total > bestTotal then
					bestRegion, bestTotal = region, total
				end
			end
			if bestRegion ~= nil then
				table.insert(actions, { kind = "RegionPoll", region = bestRegion })
				cash -= config.REGION_POLL_COST
				wanted = 0
				for k, entry in order do
					if StateData.list[entry.i].region == bestRegion and k > free then
						covered[entry.i] = true
					end
				end
			end
		end

		local taken = 0
		for _, entry in order do
			if not covered[entry.i] and entry.value > minValue then
				local cost = if free > 0 then 0 else config.INTERNAL_POLL_COST
				-- Free polls first; paid ones only up to `wanted` polls in all.
				if free == 0 and (taken >= wanted or cost > cash or cash < T.pollMinCash) then
					break
				end
				table.insert(actions, { kind = "Poll", state = StateData.list[entry.i].id })
				cash -= cost
				taken += 1
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
				local _, mult = bestAttackIssue(config, theirPlatform, view.issueMap[best.i])
				e.margin += config.ATTACK_LOSS * mult * profile.mediaMult * bg(best.i) * closing * factor * 1.4
			else
				local _, mult =
					bestIssue(config, platform, view.issueMap[best.i], view.platformMults, spotlight)
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

	return Bot.merge({ actions = actions })
end

-- ---------------------------------------------------------------- difficulty

-- The public board as the opponent sees it, built only from this View (D-057):
-- their cash is guessed from their money bracket, their ground game from what
-- this bot's own polls saw, and they hold no internal polls this bot knows of.
local function opponentView(config: Config, view: View): View
	local them = opponentOf(view)
	local scouted: { [string]: number } = {}
	for _, scout in view.scouted do
		scouted[scout.state] = scout.gotv[them] or 0
	end
	local players = table.clone(view.players)
	local bracket = view.players[them].money
	local guess = config.BOT_FORESIGHT_CASH
	local theirs = table.clone(players[them])
	theirs.cash = if bracket == "Low" then guess[1] elseif bracket == "Medium" then guess[2] else guess[3]
	players[them] = theirs
	local states = table.create(#view.states)
	for i, s in view.states do
		local copy = table.clone(s)
		copy.gotv = scouted[s.id] or 0
		copy.backlash = 0
		states[i] = copy
	end
	local out = table.clone(view)
	out.you = them
	out.players = players
	out.states = states
	out.internalPolls = {}
	out.scouted = {}
	out.nextEvent = nil
	return out
end

-- Hard and up: the standard bot's plan from the opponent's side, counted against
-- this bot's margins (each state's predicted swing, times `share`).
local function foresee(config: Config, view: View, estimates: { Estimate }, share: number)
	local theirView = opponentView(config, view)
	local theirs = buildEstimates(config, theirView)
	local before = table.create(#theirs, 0)
	for i, e in theirs do
		before[i] = e.margin
	end
	planOn(config, theirView, "Balanced", theirs)
	for i, e in theirs do
		estimates[i].margin -= share * (e.margin - before[i])
	end
end

-- Hard and up: weight each state by how much a point of margin there moves the
-- chance of reaching EV_TO_WIN (a normal approximation of the EV total), relative
-- to the expected-EV worth Medium uses. Ahead, close states this bot leads count
-- more (lower variance); behind, it reaches for the states it trails.
local function weighByWinChance(config: Config, estimates: { Estimate }, strength: number)
	local mean, var = 0, 0
	local chance = table.create(#estimates, 0)
	for i, e in estimates do
		local ev = StateData.list[i].ev
		local p = cdf(e.margin / e.sigma)
		chance[i] = p
		mean += ev * p
		var += ev * ev * p * (1 - p)
	end
	local sd = math.sqrt(math.max(var, 1))
	local z = (mean - (config.EV_TO_WIN - 0.5)) / sd
	for i, e in estimates do
		local ev = StateData.list[i].ev
		local w = 1 - z * ev * (1 - 2 * chance[i]) / (2 * sd)
		e.weight *= math.max(0.1, 1 + strength * (w - 1))
	end
end

function Bot.plan(config: Config, view: View, rng: Rng.Rng, style: Style?): any
	if style == "Random" then
		return Bot.randomPlan(config, view, rng)
	end
	local estimates = buildEstimates(config, view)
	if style == "Easy" then
		for _, e in estimates do
			e.weight = math.exp(Rng.gaussian(rng, 0, config.BOT_EASY_NOISE))
		end
	elseif style == "Hard" or style == "Extreme" then
		local extreme = style == "Extreme"
		local share = if extreme then config.BOT_EXTREME_FORESIGHT else config.BOT_HARD_FORESIGHT
		local strength = if extreme then config.BOT_EXTREME_WIN_CHANCE else config.BOT_HARD_WIN_CHANCE
		if share > 0 then
			foresee(config, view, estimates, share)
		end
		if strength > 0 then
			weighByWinChance(config, estimates, strength)
		end
	end
	return planOn(config, view, style, estimates)
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
	return { actions = out }
end

-- Expected EV a stance is worth to a candidate with `platform`: each state's
-- public reaction (Events.stanceEffects) as margin, weighted by how much a point
-- of margin there is worth. A loss goes to undecided, so it costs exactly its
-- points of margin.
function Bot.stanceValue(
	config: Config,
	issueMap: IssueMap.IssueMap,
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
		local points = Events.stanceEffect(config, issueMap, definition, id, i, platform, base)
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
	if
		style == "Random"
		or style == "RandomStance"
		or (style == "Easy" and Rng.nextFloat(rng) < config.BOT_EASY_SLIP)
	then
		return Events.CHOICES[Rng.nextInt(rng, 1, #Events.CHOICES)]
	end
	local event = view.event
	local platform: { Types.Issue } = view.players[view.you].platform or {}
	local base = Events.baseOf(view.players[view.you])
	local best: Types.Choice, bestValue = Events.CHOICES[1], -math.huge
	if event ~= nil then
		for k = 1, #Events.CHOICES do
			local id: Types.Choice = Events.CHOICES[k]
			local value = Bot.stanceValue(config, view.issueMap, estimates, event, id, platform, base)
			if value > bestValue then
				best, bestValue = id, value
			end
		end
	end
	return best
end

-- ---------------------------------------------------------------- debates

-- Debate rounds (D-062). Each cell of the round's 3x3 table (my move, their
-- move) is valued first by the result (+1 a win, 0 a split, -1 a loss: reading
-- the board is the skill) and then, at most DEBATE_WORTH_SHARE of a result, by
-- what its map effects are worth on this bot's estimates: a point of support
-- in a state is worth EV x closeness (marginValue), a gain buys margin through
-- the normal split, gains of theirs and backfires of mine count against it.
-- Pure on the View.
local DEBATE_WORTH_SHARE = 0.5 -- the map's share of a cell's value, next to the result's 1 (a bot heuristic, not a rule)

-- Expected EV one support point (as a gain) is worth in `issue`'s states, and
-- as a loss.
local function issueWorth(
	config: Config,
	issueMap: IssueMap.IssueMap,
	estimates: { Estimate },
	issue: Types.Issue
): (number, number)
	local gain, loss = 0, 0
	for i, record in StateData.list do
		if table.find(issueMap[i], issue) then
			local e = estimates[i]
			local worth = marginValue(e, record.ev)
			gain += worth * marginFromGain(config, e, 1)
			loss += worth
		end
	end
	return gain, loss
end

type Cells = { { number } } -- [my move][their move], MOVES order

-- The value of every cell for player `me` against `them` on `board`, with my
-- win counted `mult` times (a staked Zinger).
local function debateCells(
	config: Config,
	issueMap: IssueMap.IssueMap,
	estimates: { Estimate },
	board: Debate.Board,
	me: number,
	them: number,
	mult: number
): Cells
	local cells: Cells = {}
	local worth: { [string]: { number } } = {}
	local function w(issue: Types.Issue): { number }
		local cached = worth[issue]
		if cached == nil then
			local gain, loss = issueWorth(config, issueMap, estimates, issue)
			cached = { gain, loss }
			worth[issue] = cached
		end
		return cached
	end
	local worths: { { number } } = {}
	local results: { { number } } = {}
	local biggest = 0
	for a = 1, #Debate.MOVES do
		local mine: Types.DebateMove = Debate.MOVES[a]
		worths[a], results[a] = {}, {}
		local myLanding = w(Debate.landing(board, me, mine))
		for b = 1, #Debate.MOVES do
			local theirs: Types.DebateMove = Debate.MOVES[b]
			local theirLanding = w(Debate.landing(board, them, theirs))
			local m = Debate.versus(config, board, me, mine, them, theirs)
			local value
			if m > 0 then
				value = config.DEBATE_ROUND_WIN * mult * myLanding[1]
				if Debate.BEATS[mine] == theirs then
					value += config.DEBATE_BACKFIRE * theirLanding[2]
				end
			elseif m < 0 then
				value = -config.DEBATE_ROUND_WIN * theirLanding[1]
				if Debate.BEATS[theirs] == mine then
					value -= config.DEBATE_BACKFIRE * myLanding[2]
				end
			else
				value = config.DEBATE_ROUND_SPLIT * (myLanding[1] - theirLanding[1])
			end
			worths[a][b] = value
			results[a][b] = if m > 0 then 1 elseif m < 0 then -1 else 0
			biggest = math.max(biggest, math.abs(value))
		end
	end
	for a = 1, #Debate.MOVES do
		cells[a] = {}
		for b = 1, #Debate.MOVES do
			local share = if biggest > 0 then worths[a][b] / biggest else 0
			cells[a][b] = results[a][b] + DEBATE_WORTH_SHARE * share
		end
	end
	return cells
end

-- The move with the best worst cell, then the best average (ties in MOVES order).
local function maximin(cells: Cells): number
	local best, bestWorst, bestSum = 1, -math.huge, -math.huge
	for a = 1, #cells do
		local worst, sum = math.huge, 0
		for _, v in cells[a] do
			worst = math.min(worst, v)
			sum += v
		end
		if worst > bestWorst + 1e-9 or (math.abs(worst - bestWorst) <= 1e-9 and sum > bestSum + 1e-9) then
			best, bestWorst, bestSum = a, worst, sum
		end
	end
	return best
end

-- The move with the best expected cell against `weights` over their moves.
local function bestReply(cells: Cells, weights: { number }): number
	local best, bestValue = 1, -math.huge
	for a = 1, #cells do
		local value = 0
		for b, v in cells[a] do
			value += weights[b] * v
		end
		if value > bestValue + 1e-9 then
			best, bestValue = a, value
		end
	end
	return best
end

-- The board of a later round of this debate, as far as public facts tell today
-- (no history, today's polls and crowd). Used to judge where a Zinger pays most.
local function laterBoard(config: Config, view: View, round: number): Debate.Board?
	local live = view.debate
	if live == nil or live.topics[round] == nil then
		return nil
	end
	local platforms: { { Types.Issue } } = {}
	local mults: { number } = {}
	for p, player in view.players do
		platforms[p] = player.platform or {}
		mults[p] = profileOf(config, view, p).zingerMult
	end
	local polls = {}
	for i, s in view.states do
		polls[i] = s.poll
	end
	return Debate.boardFrom(config, {
		week = live.week,
		round = round,
		topic = live.topics[round],
		issueMap = view.issueMap,
		platforms = platforms,
		polls = polls,
		crowd = live.crowd,
		zingers = live.zingers,
		zingerMults = mults,
		last = {},
	})
end

-- What staking the Zinger on `move` this round is worth: the chance it wins
-- (against `weights` over their moves) times the extra map effect a win gets.
local STAKE_FLOOR = 0.5 -- a stake's value counts at least this share of where it lands, whatever the chance (a bot heuristic)

local function stakeValue(
	config: Config,
	view: View,
	estimates: { Estimate },
	board: Debate.Board,
	move: number,
	weights: { number }
): number
	local me, them = view.you, opponentOf(view)
	local chance = 0
	local mine: Types.DebateMove = Debate.MOVES[move]
	for b = 1, #Debate.MOVES do
		local theirs: Types.DebateMove = Debate.MOVES[b]
		if Debate.versus(config, board, me, mine, them, theirs) > 0 then
			chance += weights[b]
		end
	end
	local gain = issueWorth(config, view.issueMap, estimates, Debate.landing(board, me, mine))
	-- Where it lands counts most (the states this bot needs); the chance of a win tilts it.
	return (STAKE_FLOOR + (1 - STAKE_FLOOR) * chance) * gain * (board.players[me].zingerMult - 1)
end

local EVEN = { 1 / 3, 1 / 3, 1 / 3 }

-- Stake the Zinger now? Yes in the last round; otherwise when this round's
-- stake is worth the most of this and every later round (later ones judged on
-- today's facts against an even opponent). Rounds that tie (a Pivot often lands
-- on the same issue every round) share the stake evenly, by this bot's own rng.
local function stakeNow(
	config: Config,
	view: View,
	estimates: { Estimate },
	board: Debate.Board,
	move: number,
	weights: { number },
	rng: Rng.Rng
): boolean
	local live = view.debate :: ViewModule.DebateView
	local me = view.you
	if (live.zingers[me] or 0) <= 0 then
		return false
	end
	if live.round >= #live.topics then
		return true
	end
	local now = stakeValue(config, view, estimates, board, move, weights)
	local ties = 1
	for r = live.round + 1, #live.topics do
		local later = laterBoard(config, view, r)
		if later then
			local cells = debateCells(config, view.issueMap, estimates, later, me, opponentOf(view), 1)
			local value = stakeValue(config, view, estimates, later, maximin(cells), EVEN)
			if value > now + 1e-9 then
				return false
			elseif value >= now - 1e-9 then
				ties += 1
			end
		end
	end
	return ties == 1 or Rng.nextFloat(rng) < 1 / ties
end

-- The standard bot's move from the opponent's side of the public board (Hard
-- and up predict it, D-057).
local function predictedMove(config: Config, view: View, board: Debate.Board): number
	local theirView = opponentView(config, view)
	local theirs = buildEstimates(config, theirView)
	local cells = debateCells(config, view.issueMap, theirs, board, theirView.you, view.you, 1)
	return maximin(cells)
end

-- Extreme: how often the opponent played each move in this match's finished
-- debate rounds (public), or nil before it has played two.
local function pastMoves(view: View): { number }?
	local them = opponentOf(view)
	local counts = { 0, 0, 0 }
	local total = 0
	local function add(rounds: { any })
		for _, round in rounds do
			local pick = round.picks[them]
			local k = table.find(Debate.MOVES, pick)
			if k and not round.canned[them] then
				counts[k] += 1
				total += 1
			end
		end
	end
	for _, result in view.debates do
		if result.rounds then
			add(result.rounds)
		end
	end
	if view.debate then
		add(view.debate.rounds)
	end
	if total < 2 then
		return nil
	end
	return { counts[1] / total, counts[2] / total, counts[3] / total }
end

-- A debate round's move (D-062): { move, zinger }, or nil for the canned answer.
function Bot.debate(config: Config, view: View, rng: Rng.Rng, style: Style?): any
	local live = view.debate
	if live == nil then
		return nil
	end
	if style == "NoAnswer" then
		return nil
	end
	local me, them = view.you, opponentOf(view)
	local board = live.board
	local hasZinger = (live.zingers[me] or 0) > 0
	local roundsLeft = #live.topics - live.round + 1
	local function randomZinger(): boolean
		return hasZinger and Rng.nextFloat(rng) < 1 / roundsLeft
	end
	if
		style == "Random"
		or style == "RandomMove"
		or (style == "Easy" and Rng.nextFloat(rng) < config.BOT_EASY_SLIP)
	then
		return { move = Debate.MOVES[Rng.nextInt(rng, 1, #Debate.MOVES)], zinger = randomZinger() }
	end
	local estimates = buildEstimates(config, view)
	local cells = debateCells(config, view.issueMap, estimates, board, me, them, 1)
	local move: number
	local weights = EVEN
	if style == "AlwaysDefend" then
		move = 1
	elseif style == "AlwaysAttack" then
		move = 2
	elseif style == "AlwaysPivot" then
		move = 3
	elseif style == "Hard" or style == "Extreme" then
		local predicted = predictedMove(config, view, board)
		local read = config.BOT_DEBATE_READ
		weights = {}
		for b = 1, #Debate.MOVES do
			weights[b] = (1 - read) / #Debate.MOVES + (if b == predicted then read else 0)
		end
		local past = if style == "Extreme" then pastMoves(view) else nil
		if past then
			local h = config.BOT_EXTREME_HISTORY
			for b = 1, #Debate.MOVES do
				weights[b] = (1 - h) * weights[b] + h * past[b]
			end
		end
		move = bestReply(cells, weights)
	else
		move = maximin(cells)
	end
	local zinger = if style == "Easy"
		then randomZinger()
		else stakeNow(config, view, estimates, board, move, weights, rng)
	return { move = Debate.MOVES[move], zinger = zinger }
end

-- A Decision phase (D-044): this week's stance. Every style decides the same
-- way except Random and RandomStance (Bot.choose).
function Bot.decide(config: Config, view: View, rng: Rng.Rng, style: Style?): any
	local estimates = buildEstimates(config, view)
	return { choice = Bot.choose(config, view, estimates, rng, style) }
end

-- Random legal actions: the floor every real strategy must beat.
function Bot.randomPlan(config: Config, view: View, rng: Rng.Rng): any
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
	return { actions = actions }
end

-- One call for any phase that wants input (the harness and practice mode use this).
function Bot.act(config: Config, view: View, rng: Rng.Rng, candidate: string, style: Style?): any
	if view.phase == "Select" then
		return Bot.select(config, view, rng, candidate, style)
	elseif view.phase == "Draft" then
		return Bot.draft(config, view, rng, style)
	elseif view.phase == "Decision" then
		return Bot.decide(config, view, rng, style)
	elseif view.phase == "Debate" then
		return Bot.debate(config, view, rng, style)
	elseif view.phase == "Plan" then
		return Bot.plan(config, view, rng, style)
	end
	return nil
end

return table.freeze(Bot)
