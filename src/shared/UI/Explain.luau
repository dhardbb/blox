--!strict
-- What the numbers mean, in plain words (playtest 2: every tester found them
-- opaque). Pure: works from Config, Candidates and the player's own View only,
-- and reuses the simulation's own formulas (Resolve, Support, Polls, Events,
-- Plan) read-only, so a balance pass that changes Config or a candidate flows
-- through without edits here. Nothing hidden is used or guessed at: where the
-- sim reads true support, the preview uses your internal poll of the state if
-- you have one, else the public poll, and says "about".
--
--   Explain.estimate(config, view, id)                 -> Estimate (your support basis)
--   Explain.action(config, view, draft, id, kind, issue?) -> Preview (one action here)
--   Explain.previews(config, view, draft, id, message) -> { { name, text } } (the action grid)
--   Explain.leanText(view, s) · momentumNote · backlashNote · underdogText
--   Explain.driftRule(config, view?) · driftPerPoint (how momentum turns into support)
--   Explain.debateOdds(config, edge) -> (win, tie, lose)
--   Explain.debateParts / debateLine (a resolved topic, split into prep, platform, stat, roll)
--   Explain.choiceLines(config) (the Choice payoff matrix as three lines)
--   Explain.leadWinChance(config, pollLead)
--   Explain.help(config, view?) -> { Section } (the "How it works" screen)

local Candidates = require("../Sim/Candidates")
local ConfigModule = require("../Sim/Config")
local Events = require("../Sim/Events")
local Issues = require("../Sim/Issues")
local Leans = require("../Sim/Leans")
local Numbers = require("./Numbers")
local Plan = require("../Sim/Plan")
local PlanDraft = require("./PlanDraft")
local Polls = require("../Sim/Polls")
local Resolve = require("../Sim/Resolve")
local SimState = require("../Sim/State")
local StateData = require("../Sim/StateData")
local Support = require("../Sim/Support")
local Types = require("../Types")
local ViewModule = require("../Sim/View")

type Config = ConfigModule.Config
type View = ViewModule.View
type StateView = ViewModule.StateView
type Profile = Candidates.Profile

local Explain = {}

-- ---------------------------------------------------------------- text helpers

-- A multiplier: 1.5 -> "×1.5", 1.15 -> "×1.15", 2 -> "×2.0".
local function times(mult: number): string
	local text = string.format("%.2f", mult)
	text = string.gsub(text, "(%.%d)0$", "%1")
	return "×" .. text
end

-- An exact rate in money: 0.25 -> "$0.25", 6 -> "$6.0" (Numbers.money floors to tenths).
local function rate(amount: number): string
	local text = string.format("%.2f", amount)
	text = string.gsub(text, "(%.%d)0$", "%1")
	return "$" .. text
end
Explain.times = times

-- A plain number with at most one decimal: 2 -> "2", 1.5 -> "1.5".
local function num(value: number): string
	local text = string.format("%.1f", value)
	text = string.gsub(text, "%.0$", "")
	return text
end
Explain.num = num

-- A rate with up to two decimals: 0.3 -> "0.3", 0.15 -> "0.15", 1 -> "1".
local function exact(value: number): string
	local text = string.format("%.2f", value)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

local function pct(share: number): string
	return `{math.floor(share * 100 + 0.5)}%`
end

local signed = Numbers.signed
local points = Numbers.points

local function plural(n: number, word: string): string
	return `{n} {word}{if n == 1 then "" else "s"}`
end

local function issueName(issue: string?): string
	return if issue then (Issues.displayName :: any)[issue] or issue else "?"
end

local function opponentOf(view: View): number
	return if view.you == 1 then 2 else 1
end

local function profileOf(config: Config, view: View, p: number): Profile
	local player = view.players[p]
	local id = if player
			and player.candidate
			and Candidates.exists(player.candidate)
		then player.candidate
		else Candidates.ids[1]
	return Candidates.profile(config, id)
end

-- The underdog multipliers for player p: Polls.underdogMults reads only the
-- player's tier and profile, so a minimal stand-in keeps them identical.
local function underdog(config: Config, view: View, p: number): (number, number)
	local players = {}
	players[p] = { underdogTier = view.players[p].underdogTier, profile = profileOf(config, view, p) }
	return Polls.underdogMults(config, { players = players } :: any, p)
end

local function eventEffect(view: View): Events.Effect?
	local event = view.event
	if event == nil then
		return nil
	end
	return { kind = event.kind, issue = event.issue, region = event.region }
end

-- The extra an event adds, within EVENT_CAP (Events.grant, on an empty ledger).
local function eventExtra(config: Config, base: number, mult: number): number
	return math.min(math.max(0, base * (mult - 1)), config.EVENT_CAP)
end

-- ---------------------------------------------------------------- estimates

export type Estimate = {
	mine: number,
	theirs: number,
	undecided: number,
	source: "internal" | "public" | "start",
}

-- Your support in a state as far as you can know it: your internal poll there
-- (true support within INTERNAL_POLL_ERROR), else the public poll, else the
-- starting support from the lean.
function Explain.estimate(config: Config, view: View, id: string): Estimate
	local me, them = view.you, opponentOf(view)
	for _, result in view.internalPolls do
		if result.state == id then
			return {
				mine = result.support[me] or 0,
				theirs = result.support[them] or 0,
				undecided = result.undecided,
				source = "internal",
			}
		end
	end
	local s = view.states[SimState.indexOf[id]]
	local poll = s.poll
	if poll then
		return {
			mine = poll.support[me] or 0,
			theirs = poll.support[them] or 0,
			undecided = poll.undecided,
			source = "public",
		}
	end
	local start = Leans.startingSupport(config, { lean = s.lean, leanTo = s.leanTo }, #view.players)
	return { mine = start[me], theirs = start[them], undecided = config.BASE_UNDECIDED, source = "start" }
end

-- ---------------------------------------------------------------- action previews

export type Preview = {
	kind: string,
	text: string,
	you: number?, -- expected change to your support here (points)
	them: number?, -- expected change to the opponent's support here
	momentum: number?, -- momentum you gain here
	money: number?, -- expected money raised
}

-- Earlier actions of `kinds` in the draft in state `id`.
local function countIn(draft: PlanDraft.Draft, id: string, kinds: { [string]: boolean }): number
	local n = 0
	for _, action in draft.actions do
		if kinds[action.kind] and action.state == id then
			n += 1
		end
	end
	return n
end

local MEDIA_KINDS = { Media = true, Attack = true }

-- The AP and flight part of a rally or fundraiser line.
local function moveCost(config: Config, view: View, draft: PlanDraft.Draft, id: string): string
	local from = PlanDraft.location(view, draft)
	if Plan.isAdjacent(from, id) then
		return "1 AP"
	end
	return `1 AP + flight {Numbers.cost(config.FLIGHT_COST)}`
end

-- How the opponent's share of a gain is split (Support.addGain): the rest comes
-- from undecided voters while there are enough of them.
local function opponentShare(config: Config, undecided: number): number
	local fromUndecided = if undecided >= config.UNDECIDED_FLOOR then config.GAIN_FROM_UNDECIDED else 0
	return 1 - fromUndecided
end

local function withParts(parts: { string }): string
	return if #parts > 0 then ` ({table.concat(parts, ", ")})` else ""
end

-- The multipliers both rallies and ads share, as numbers and named parts.
local function commonParts(config: Config, view: View, s: StateView, parts: { string }): number
	local mult = 1
	if s.battleground then
		mult *= config.BATTLEGROUND_MULT
		table.insert(parts, `battleground {times(config.BATTLEGROUND_MULT)}`)
	end
	local closing = Resolve.closingMult(config, view.week)
	if closing ~= 1 then
		mult *= closing
		table.insert(parts, `closing weeks {times(closing)}`)
	end
	return mult
end

local function saturationPart(config: Config, est: Estimate, parts: { string }): number
	local sat = Support.saturation(config, est.mine)
	if sat < 0.995 then
		table.insert(parts, `at {num(est.mine)}% you gain less: {times(sat)}`)
	end
	return sat
end

local function rally(
	config: Config,
	view: View,
	draft: PlanDraft.Draft,
	id: string,
	issue: Types.Issue
): Preview
	local me = view.you
	local i = SimState.indexOf[id]
	local s = view.states[i]
	local profile = profileOf(config, view, me)
	local platform: { Types.Issue } = view.players[me].platform or {}
	local est = Explain.estimate(config, view, id)
	local parts: { string } = {}
	local issueMult = Resolve.issueMult(config, platform, StateData.list[i].issues, issue)
	table.insert(parts, `{issueName(issue)} {times(issueMult)}`)
	local mult = issueMult * profile.rallyMult * commonParts(config, view, s, parts)
	local underdogRally = underdog(config, view, me)
	if underdogRally ~= 1 then
		mult *= underdogRally
		table.insert(parts, `underdog {times(underdogRally)}`)
	end
	if view.players[me].frontrunner and profile.frontrunnerRallyMult ~= 1 then
		mult *= profile.frontrunnerRallyMult
		table.insert(parts, `far ahead {times(profile.frontrunnerRallyMult)}`)
	end
	local gain = profile.rallySupport * mult * saturationPart(config, est, parts)
	local eventMult = Events.supportMult(config, eventEffect(view), "Rally", issue, i)
	if eventMult ~= 1 then
		gain += eventExtra(config, gain, eventMult)
		table.insert(parts, `event {times(eventMult)}, at most +{num(config.EVENT_CAP)}`)
	end
	local them = -gain * opponentShare(config, est.undecided)
	local momentum = config.RALLY_MOMENTUM * profile.momentumGainMult
	return {
		kind = "Rally",
		you = gain,
		them = them,
		momentum = momentum,
		text = `Rally: about {signed(gain)} you, {signed(them)} them here{withParts(parts)}; +{num(momentum)} momentum; {moveCost(
			config,
			view,
			draft,
			id
		)}`,
	}
end

local function media(
	config: Config,
	view: View,
	draft: PlanDraft.Draft,
	id: string,
	issue: Types.Issue
): Preview
	local me = view.you
	local i = SimState.indexOf[id]
	local s = view.states[i]
	local profile = profileOf(config, view, me)
	local platform: { Types.Issue } = view.players[me].platform or {}
	local est = Explain.estimate(config, view, id)
	local parts: { string } = {}
	local issueMult = Resolve.issueMult(config, platform, StateData.list[i].issues, issue)
	table.insert(parts, `{issueName(issue)} {times(issueMult)}`)
	local k = countIn(draft, id, MEDIA_KINDS) + 1
	local factor = profile.mediaSaturation ^ (k - 1)
	local common = profile.mediaMult * commonParts(config, view, s, parts) * factor
	if profile.mediaMult ~= 1 then
		table.insert(parts, `your candidate {times(profile.mediaMult)}`)
	end
	if k > 1 then
		table.insert(parts, `repeat ad #{k} {times(factor)}`)
	end
	local gain = config.MEDIA_SUPPORT * issueMult * common * saturationPart(config, est, parts)
	local eventMult = Events.supportMult(config, eventEffect(view), "Media", issue, i)
	if eventMult ~= 1 then
		gain += eventExtra(config, gain, eventMult)
		table.insert(parts, `event {times(eventMult)}, at most +{num(config.EVENT_CAP)}`)
	end
	local them = -gain * opponentShare(config, est.undecided)
	local momentum = config.MEDIA_MOMENTUM * factor * profile.momentumGainMult
	return {
		kind = "Media",
		you = gain,
		them = them,
		momentum = momentum,
		text = `Ad: about {signed(gain)} you, {signed(them)} them here{withParts(parts)}; +{num(momentum)} momentum; {Numbers.cost(
			profile.mediaCost
		)}`,
	}
end

local function attack(
	config: Config,
	view: View,
	draft: PlanDraft.Draft,
	id: string,
	issue: Types.Issue
): Preview
	local me, rival = view.you, opponentOf(view)
	local i = SimState.indexOf[id]
	local s = view.states[i]
	local profile = profileOf(config, view, me)
	local theirPlatform: { Types.Issue } = view.players[rival].platform or {}
	local parts: { string } = {}
	local mult = Resolve.attackMult(config, theirPlatform, StateData.list[i].issues, issue)
	table.insert(
		parts,
		`{issueName(issue)} {times(mult)}{if mult == config.ISSUE_MULT_ATTACK
			then ": a top issue here, not on their platform"
			else ""}`
	)
	local k = countIn(draft, id, MEDIA_KINDS) + 1
	local factor = profile.mediaSaturation ^ (k - 1)
	local common = profile.mediaMult * commonParts(config, view, s, parts) * factor
	if k > 1 then
		table.insert(parts, `repeat ad #{k} {times(factor)}`)
	end
	local loss = config.ATTACK_LOSS * mult * common
	local gain = loss * (1 - config.ATTACK_TO_UNDECIDED)
	-- The backlash meter, run through the attacks already planned here (Resolve step 4).
	local meter = s.backlash
	for _, action in draft.actions do
		if action.kind == "Attack" and action.state == id then
			meter = if meter >= config.BACKLASH_THRESHOLD then 0 else meter + 1
		end
	end
	local backlash: string
	if meter >= config.BACKLASH_THRESHOLD then
		gain -= config.BACKLASH_PENALTY
		backlash = `backlash costs you {points(config.BACKLASH_PENALTY)} and resets`
	else
		backlash = `backlash {meter + 1} of {config.BACKLASH_THRESHOLD}`
	end
	return {
		kind = "Attack",
		you = gain,
		them = -loss,
		momentum = 0,
		text = `Attack ad: about {signed(-loss)} them, {signed(gain)} you here{withParts(parts)}; {backlash}; no momentum; {Numbers.cost(
			profile.mediaCost
		)}`,
	}
end

local function fundraise(config: Config, view: View, draft: PlanDraft.Draft, id: string): Preview
	local me = view.you
	local i = SimState.indexOf[id]
	local s = view.states[i]
	local profile = profileOf(config, view, me)
	local est = Explain.estimate(config, view, id)
	local parts: { string } = {}
	local raw = config.FUNDRAISER_BASE + config.FUNDRAISER_PER_SHARE * est.mine / 100
	-- Fundraisers in one state share its pool (Resolve step 3): the k-th of yours
	-- gets what the earlier ones leave of a full pool.
	local k = countIn(draft, id, { Fundraise = true }) + 1
	local take = math.min(k * raw, s.capacity) - math.min((k - 1) * raw, s.capacity)
	local mult = profile.fundraiseMult
	if profile.fundraiseMult ~= 1 then
		table.insert(parts, `your candidate {times(profile.fundraiseMult)}`)
	end
	if s.isHome and s.owner == me then
		mult *= config.HOME_FUNDRAISE_MULT
		table.insert(parts, `home {times(config.HOME_FUNDRAISE_MULT)}`)
	end
	local _, underdogFund = underdog(config, view, me)
	if underdogFund ~= 1 then
		mult *= underdogFund
		table.insert(parts, `underdog {times(underdogFund)}`)
	end
	if view.players[me].frontrunner and profile.frontrunnerFundMult ~= 1 then
		mult *= profile.frontrunnerFundMult
		table.insert(parts, `far ahead {times(profile.frontrunnerFundMult)}`)
	end
	local money = take * mult
	local eventMult = Events.fundMult(config, eventEffect(view), s.poll, me)
	if eventMult ~= 1 then
		money += eventExtra(config, money, eventMult)
		table.insert(parts, `event {times(eventMult)}`)
	end
	table.insert(parts, `pool {Numbers.money(s.capacity)} when full, shared with them`)
	return {
		kind = "Fundraise",
		money = money,
		text = `Fundraise: up to about {Numbers.money(money)} here{withParts(parts)}; {moveCost(
			config,
			view,
			draft,
			id
		)}`,
	}
end

local function poll(config: Config, view: View, draft: PlanDraft.Draft): Preview
	local profile = profileOf(config, view, view.you)
	local used = 0
	for _, action in draft.actions do
		if action.kind == "Poll" then
			used += 1
		end
	end
	local free = math.max(0, profile.freePolls - used)
	local price = if free > 0
		then `free ({free} of {profile.freePolls} free this week)`
		else Numbers.cost(config.INTERNAL_POLL_COST)
	return {
		kind = "Poll",
		text = `Poll: next week you see true support here within ±{num(config.INTERNAL_POLL_ERROR)}, exact undecided and momentum; {price}`,
	}
end

local function regionPoll(config: Config, id: string): Preview
	local region: Types.Region? = PlanDraft.regionOf(id)
	local n = 0
	for _, record in StateData.list do
		if record.region == region then
			n += 1
		end
	end
	local name = if region then (Issues.regionName :: any)[region] or region else "?"
	return {
		kind = "RegionPoll",
		text = `Region poll: an internal poll of all {n} {name} states; {Numbers.cost(
			config.REGION_POLL_COST
		)}`,
	}
end

local function gotv(config: Config, view: View, draft: PlanDraft.Draft, id: string): Preview
	local profile = profileOf(config, view, view.you)
	local s = view.states[SimState.indexOf[id]]
	local planned = 0
	for _, action in draft.actions do
		if action.kind == "Gotv" and action.state == id then
			planned += action.units or 0
		end
	end
	local placed = s.gotv + planned
	return {
		kind = "Gotv",
		text = `Ground game: {signed(config.GOTV_PER_UNIT)} margin here on election night per unit ({placed} of {profile.gotvMaxUnits} placed); polls never show it; {Numbers.cost(
			profile.gotvCost
		)} a unit`,
	}
end

local function pivot(config: Config, view: View): Preview
	local used = view.players[view.you].pivotUsed
	return {
		kind = "Pivot",
		text = if used
			then "Pivot: already used this match"
			else `Pivot: swap one platform issue for another; {config.PIVOT_AP} AP and -{points(
				config.PIVOT_PENALTY
			)} national support; once per match`,
	}
end

-- One action's expected effect in state `id`, given what is already planned.
-- `kind` is a Plan kind (Rally, Fundraise, Media, Attack, Poll, RegionPoll,
-- Gotv, Pivot); `issue` is the message for Rally, Media and Attack.
function Explain.action(
	config: Config,
	view: View,
	draft: PlanDraft.Draft,
	id: string,
	kind: string,
	issue: Types.Issue?
): Preview
	if kind == "Rally" then
		return rally(config, view, draft, id, issue or PlanDraft.bestIssue(config, view, id))
	elseif kind == "Media" then
		return media(config, view, draft, id, issue or PlanDraft.bestIssue(config, view, id))
	elseif kind == "Attack" then
		return attack(config, view, draft, id, issue or PlanDraft.bestAttackIssue(config, view, id))
	elseif kind == "Fundraise" then
		return fundraise(config, view, draft, id)
	elseif kind == "Poll" then
		return poll(config, view, draft)
	elseif kind == "RegionPoll" then
		return regionPoll(config, id)
	elseif kind == "Gotv" then
		return gotv(config, view, draft, id)
	end
	return pivot(config, view)
end

-- The state card's action grid, in its order, with the button names it uses.
local GRID: { { name: string, kind: string } } = {
	{ name = "Rally", kind = "Rally" },
	{ name = "Fundraise", kind = "Fundraise" },
	{ name = "Ad", kind = "Media" },
	{ name = "Attack", kind = "Attack" },
	{ name = "Poll", kind = "Poll" },
	{ name = "Gotv", kind = "Gotv" },
	{ name = "RegionPoll", kind = "RegionPoll" },
	{ name = "PivotButton", kind = "Pivot" },
}

export type GridPreview = { name: string, text: string }

-- Every action grid button's preview in state `id`, rallies and ads on `message`.
function Explain.previews(
	config: Config,
	view: View,
	draft: PlanDraft.Draft,
	id: string,
	message: Types.Issue
): { GridPreview }
	local out: { GridPreview } = {}
	for _, entry in GRID do
		local issue: Types.Issue? = if entry.kind == "Rally" or entry.kind == "Media" then message else nil
		table.insert(
			out,
			{ name = entry.name, text = Explain.action(config, view, draft, id, entry.kind, issue).text }
		)
	end
	return out
end

-- ---------------------------------------------------------------- labels

-- "leans you +4", "leans them +4" or "no lean": from the viewer's side.
function Explain.leanText(view: View, s: StateView): string
	if s.leanTo == nil or s.lean <= 0 then
		return "no lean"
	end
	return `leans {if s.leanTo == view.you then "you" else "them"} +{s.lean}`
end

-- What the momentum in a state does next week, if nobody campaigns there.
function Explain.momentumNote(config: Config, view: View, s: StateView): string
	local me, rival = view.you, opponentOf(view)
	local mine, theirs = profileOf(config, view, me), profileOf(config, view, rival)
	local nextMine = (s.momentum[me] or 0) * mine.momentumDecay
	local nextTheirs = (s.momentum[rival] or 0) * theirs.momentumDecay
	local lead = nextMine - nextTheirs
	local drift = math.min(config.DRIFT_RATE * math.abs(lead), config.DRIFT_CAP)
	local head: string
	if drift < 0.05 then
		head = "No momentum lead here, so no drift."
	else
		local who = if lead > 0 then "you" else "them"
		head =
			`{if lead > 0 then "You lead" else "They lead"} momentum: about {signed(drift)} support drifts to {who} next week.`
	end
	local theirsNote = ""
	if theirs.momentumDecay ~= mine.momentumDecay then
		theirsNote = ` (their candidate keeps {pct(theirs.momentumDecay)})`
	end
	return `{head} Drift: {Explain.driftRule(config, view)}{theirsNote}. Momentum is capped at {num(
		config.MOMENTUM_CAP
	)}. It does not change what a rally gives.`
end

-- Your attack backlash in a state, or nil when there is none.
function Explain.backlashNote(config: Config, _view: View, s: StateView): string?
	local meter = s.backlash
	if meter <= 0 then
		return nil
	end
	local threshold = config.BACKLASH_THRESHOLD
	local next = if meter >= threshold
		then `Your next attack ad here also costs you {points(config.BACKLASH_PENALTY)} support.`
		else `{plural(threshold - meter, "more attack")} fill it; the one after also costs you {points(
			config.BACKLASH_PENALTY
		)} support.`
	return `Your attack backlash here: {meter} of {threshold}. {next} Fades {num(config.BACKLASH_DECAY)} a week.`
end

-- Player p's underdog tier and what it gives, or nil at tier 0. Also names the
-- frontrunner drawback when it is on.
function Explain.underdogText(config: Config, view: View, p: number): string?
	local player = view.players[p]
	local profile = profileOf(config, view, p)
	local who = if p == view.you then "You are" else "They are"
	local parts: { string } = {}
	if player.underdogTier > 0 then
		local rallyMult, fundMult = underdog(config, view, p)
		local gap = if player.underdogTier >= 2 then config.UNDERDOG_EV_2 else config.UNDERDOG_EV_1
		table.insert(
			parts,
			`{who} underdog tier {player.underdogTier}: rallies {times(rallyMult)}, fundraisers {times(
				fundMult
			)} (about {gap}+ projected EV behind)`
		)
	end
	if player.frontrunner and profile.frontrunnerEV ~= nil then
		table.insert(
			parts,
			`{who} far ahead: rallies {times(profile.frontrunnerRallyMult)}, fundraisers {times(
				profile.frontrunnerFundMult
			)} ({profile.name}'s drawback)`
		)
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, ". ") .. "."
end

-- ---------------------------------------------------------------- debates

-- Exact chances for one topic when your fixed score (prep + platform + stat)
-- beats theirs by `edge`: both roll 0..DEBATE_ROLL_MAX, the higher total wins.
function Explain.debateOdds(config: Config, edge: number): (number, number, number)
	local faces = config.DEBATE_ROLL_MAX + 1
	local win, tie = 0, 0
	for a = 0, config.DEBATE_ROLL_MAX do
		for b = 0, config.DEBATE_ROLL_MAX do
			local d = edge + a - b
			if d > 0 then
				win += 1
			elseif d == 0 then
				tie += 1
			end
		end
	end
	local n = faces * faces
	return win / n, tie / n, (n - win - tie) / n
end

export type TopicParts = { prep: number, platform: number, stat: number, roll: number, score: number }

-- Player p's score on topic t of a resolved debate, split into its parts. The
-- roll is what is left after prep, platform bonus and debate stat (the debate
-- result carries prep and the total). Meant for the debate week, before any
-- later pivot changes the platform.
function Explain.debateParts(
	config: Config,
	view: View,
	result: SimState.DebateResult,
	p: number,
	t: number
): TopicParts
	local prep = (result.prep[p] or {})[t] or 0
	local score = (result.scores[p] or {})[t] or 0
	local platform: { Types.Issue } = view.players[p].platform or {}
	local bonus = if table.find(platform, result.topics[t]) then config.DEBATE_PLATFORM_BONUS else 0
	local stat = profileOf(config, view, p).debateStat
	return { prep = prep, platform = bonus, stat = stat, roll = score - prep - bonus - stat, score = score }
end

local function partsText(config: Config, parts: TopicParts): string
	local text = `{parts.prep} prep`
	if parts.platform > 0 then
		text ..= ` + {parts.platform} platform`
	end
	text ..= ` + {parts.stat} stat`
	if parts.roll >= 0 and parts.roll <= config.DEBATE_ROLL_MAX then
		text ..= ` + roll {parts.roll}`
	else
		text ..= ` + {parts.roll} other`
	end
	return `{text} = {parts.score}`
end

-- "you 2 prep + 2 platform + 1 stat + roll 3 = 8 · them 4 prep + 1 stat + roll 5 = 10"
function Explain.debateLine(config: Config, view: View, result: SimState.DebateResult, t: number): string
	local me, rival = view.you, opponentOf(view)
	return `you {partsText(config, Explain.debateParts(config, view, result, me, t))} · them {partsText(
		config,
		Explain.debateParts(config, view, result, rival, t)
	)}`
end

-- One prep row's known score: "You: 2 prep + 2 platform + 1 stat = 5, plus a
-- roll 0 to 6 · them: 1 stat + their hidden prep (6 points)". Their prep stays
-- hidden until the debate; their platform and candidate are public.
function Explain.prepLine(config: Config, view: View, topic: Types.Issue, prep: number): string
	local me, rival = view.you, opponentOf(view)
	local function bonus(p: number): number
		local platform: { Types.Issue } = view.players[p].platform or {}
		return if table.find(platform, topic) then config.DEBATE_PLATFORM_BONUS else 0
	end
	local mine, theirs = profileOf(config, view, me), profileOf(config, view, rival)
	local myFixed = prep + bonus(me) + mine.debateStat
	local text = `You: {prep} prep`
	if bonus(me) > 0 then
		text ..= ` + {bonus(me)} platform`
	end
	text ..= ` + {mine.debateStat} stat = {myFixed}, plus a roll 0 to {config.DEBATE_ROLL_MAX} · them: `
	if bonus(rival) > 0 then
		text ..= `{bonus(rival)} platform + `
	end
	return text
		.. `{theirs.debateStat} stat + their hidden prep ({theirs.debatePrep} points in all), plus a roll`
end

-- ---------------------------------------------------------------- Choice events

-- National points for answering `mine` against `theirs` (1v1, clamped like the sim).
function Explain.choicePayoff(config: Config, mine: Types.Choice, theirs: Types.Choice): number
	return Events.choicePayoffs(config, { mine, theirs })[1]
end

local VERB: { [string]: string } = { Attack = "attack", Defend = "defend", Ignore = "ignore" }

-- "Attack: -0.2 if they attack · -0.3 if they defend · +0.2 if they ignore", one per answer.
function Explain.choiceLines(config: Config): { string }
	local out: { string } = {}
	for k = 1, #Events.CHOICES do
		local mine: Types.Choice = Events.CHOICES[k]
		local parts: { string } = {}
		for j = 1, #Events.CHOICES do
			local theirs: Types.Choice = Events.CHOICES[j]
			table.insert(parts, `{signed(Explain.choicePayoff(config, mine, theirs))} if they {VERB[theirs]}`)
		end
		table.insert(out, `{mine}: {table.concat(parts, " · ")}`)
	end
	return out
end

-- ---------------------------------------------------------------- election night

-- The standard normal CDF (Abramowitz and Stegun 7.1.26, error under 1.5e-7).
local function phi(x: number): number
	local z = math.abs(x) / math.sqrt(2)
	local t = 1 / (1 + 0.3275911 * z)
	local y = 1
		- (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592)
			* t
			* math.exp(-z * z)
	return if x >= 0 then 0.5 * (1 + y) else 0.5 * (1 - y)
end

-- The chance a public-poll lead of `lead` points holds on election night, with
-- no ground game: the poll's error (POLL_SIGMA on the margin) and the night's
-- swing (ELECTION_SIGMA) together. Undecided voters never vote.
function Explain.leadWinChance(config: Config, lead: number): number
	local sd = math.sqrt(config.POLL_SIGMA ^ 2 + config.ELECTION_SIGMA ^ 2)
	if sd <= 0 then
		return if lead > 0 then 1 elseif lead < 0 then 0 else 0.5
	end
	return phi(lead / sd)
end

-- ---------------------------------------------------------------- help

export type Section = { id: string, title: string, lines: { string } }

-- The candidate numbers the help quotes: yours when the view names your
-- candidate, otherwise Config's defaults.
type Numbersheet = {
	name: string?,
	perk: string?,
	drawback: string?,
	apPerWeek: number,
	passiveIncome: number,
	rallySupport: number,
	mediaCost: number,
	mediaSaturation: number,
	mediaMult: number,
	fundraiseMult: number,
	freePolls: number,
	gotvCost: number,
	gotvMaxUnits: number,
	momentumDecay: number,
	debatePrep: number,
	debateStat: number,
}

local function sheet(config: Config, view: View?): Numbersheet
	local player = if view then view.players[view.you] else nil
	if player and player.candidate and Candidates.exists(player.candidate) then
		local p = Candidates.profile(config, player.candidate)
		return {
			name = p.name,
			perk = p.perk,
			drawback = p.drawback,
			apPerWeek = p.apPerWeek,
			passiveIncome = p.passiveIncome,
			rallySupport = p.rallySupport,
			mediaCost = p.mediaCost,
			mediaSaturation = p.mediaSaturation,
			mediaMult = p.mediaMult,
			fundraiseMult = p.fundraiseMult,
			freePolls = p.freePolls,
			gotvCost = p.gotvCost,
			gotvMaxUnits = p.gotvMaxUnits,
			momentumDecay = p.momentumDecay,
			debatePrep = p.debatePrep,
			debateStat = p.debateStat,
		}
	end
	return {
		name = nil,
		perk = nil,
		drawback = nil,
		apPerWeek = config.AP_PER_WEEK,
		passiveIncome = config.PASSIVE_INCOME,
		rallySupport = config.RALLY_SUPPORT,
		mediaCost = config.MEDIA_COST,
		mediaSaturation = config.MEDIA_SATURATION,
		mediaMult = 1,
		fundraiseMult = 1,
		freePolls = 0,
		gotvCost = config.GOTV_COST,
		gotvMaxUnits = config.GOTV_MAX_UNITS,
		momentumDecay = config.MOMENTUM_DECAY,
		debatePrep = config.DEBATE_PREP,
		debateStat = config.DEBATE_STAT,
	}
end

-- Drift exactly as Resolve runs it (steps 6 and 7): each week every player's
-- momentum in a state is first multiplied by what their candidate keeps, then
-- that week's rallies and ads add to it, then the leader gains DRIFT_RATE x the
-- gap to the runner-up, at most DRIFT_CAP. So the lead a player sees now drifts
-- DRIFT_RATE x keep per point next week if nobody campaigns there (playtest 2:
-- the old text quoted DRIFT_RATE alone, twice the real number).
function Explain.driftPerPoint(config: Config, view: View?): number
	return config.DRIFT_RATE * sheet(config, view).momentumDecay
end

-- The drift rule in one clause, with your candidate's numbers when the view
-- names one. Starts lower case so callers can put it after "Drift: ".
function Explain.driftRule(config: Config, view: View?): string
	local keep = sheet(config, view).momentumDecay
	return `with no new rallies or ads there, the leader gains about {exact(config.DRIFT_RATE * keep)} support next week per point of momentum lead shown now (momentum first keeps {pct(
		keep
	)}, then the leader gains {num(config.DRIFT_RATE)} per point of what is left, at most {num(
		config.DRIFT_CAP
	)} a week)`
end

local function oddsText(config: Config, edge: number): string
	local win, tie, lose = Explain.debateOdds(config, edge)
	return `win {pct(win)}, tie {pct(tie)}, lose {pct(lose)}`
end

-- The "How it works" sections, one per concept, every number from Config and
-- Candidates (and your candidate when the view names one).
function Explain.help(config: Config, view: View?): { Section }
	local c = config
	local me = sheet(config, view)
	local sections: { Section } = {}
	local function section(id: string, title: string, lines: { string })
		table.insert(sections, { id = id, title = title, lines = lines })
	end

	local who = if me.name
		then `Numbers below are for your candidate, {me.name} (perk: {me.perk}; drawback: {me.drawback}).`
		else "Numbers below are the standard ones; each candidate changes a few (see the candidate cards)."
	section("actions", "Actions", {
		who,
		`Each week you get {me.apPerWeek} AP (unused AP is lost) and {rate(me.passiveIncome)} income. Money carries over.`,
		`Rally (1 AP): {signed(me.rallySupport)} support in that state, times the message's issue: {times(
			c.ISSUE_MULT_BOTH
		)} if it is on your platform and a top issue there, {times(c.ISSUE_MULT_STATE)} top issue only, {times(
			c.ISSUE_MULT_PLATFORM
		)} platform only, {times(c.ISSUE_MULT_NEITHER)} neither. +{num(c.RALLY_MOMENTUM)} momentum.`,
		`Fundraise (1 AP): {rate(c.FUNDRAISER_BASE)} + {rate(c.FUNDRAISER_PER_SHARE)} × your support share there{if me.fundraiseMult
				~= 1
			then `, {times(me.fundraiseMult)} for you`
			else ""}, {times(c.HOME_FUNDRAISE_MULT)} in your home state. Each state has a pool ({rate(
			c.POOL_BASE
		)} + {rate(c.POOL_PER_MILLION)} per million people, at most {rate(c.POOL_MAX)}) shared by both players; it refills {pct(
			c.POOL_REFILL
		)} a week. The pool's level is hidden, so the preview is an upper bound.`,
		`Ad ({Numbers.cost(me.mediaCost)}): {signed(c.MEDIA_SUPPORT)} support{if me.mediaMult ~= 1
			then ` {times(me.mediaMult)}`
			else ""}, same issue multipliers, +{num(c.MEDIA_MOMENTUM)} momentum. Each extra ad in the same state and week is worth {times(
			me.mediaSaturation
		)} of the one before.`,
		`Attack ad ({Numbers.cost(me.mediaCost)}): {signed(-c.ATTACK_LOSS)} for them, {times(
			c.ISSUE_MULT_ATTACK
		)} on a state top issue missing from their platform ({times(c.ISSUE_MULT_NEITHER)} otherwise). {pct(
			c.ATTACK_TO_UNDECIDED
		)} of what they lose becomes undecided, the rest goes to you. No momentum. Watch your backlash.`,
		`Poll ({Numbers.cost(c.INTERNAL_POLL_COST)}{if me.freePolls > 0
			then `, {me.freePolls} free a week`
			else ""}) and Region poll ({Numbers.cost(c.REGION_POLL_COST)}, every state in the region): your private read of true support. See Polls.`,
		`Ground game ({Numbers.cost(me.gotvCost)} a unit, up to {me.gotvMaxUnits} per state): counts only on election night. See Ground game.`,
		`Pivot ({c.PIVOT_AP} AP, once per match): swap one platform issue; costs {points(c.PIVOT_PENALTY)} national support.`,
		`Multipliers stack: battlegrounds {times(c.BATTLEGROUND_MULT)} on every campaign effect; from week {c.CLOSING_FROM_WEEK} rallies and ads {times(
			c.CLOSING_MULT
		)}; gains shrink as your support nears {c.SUPPORT_CAP}% (never below {times(c.SATURATION_FLOOR)}).`,
		`A gain takes {pct(c.GAIN_FROM_UNDECIDED)} from undecided voters and the rest from your opponent (all from your opponent once undecided is under {c.UNDECIDED_FLOOR}).`,
		"The preview under the action buttons does this math for the selected state, using your internal poll there if you have one, else the public poll.",
	})

	section("flights", "Flights and routes", {
		"Rallies and fundraisers move your candidate, in plan order. Ads, polls, ground game and pivots happen from anywhere.",
		`Each stop must be where you are or share a land border with the previous stop. Otherwise it is a flight: {Numbers.cost(
			c.FLIGHT_COST
		)}, no extra AP. The map draws your route; ✈ marks flights.`,
	})

	section("map", "Leans, momentum, backlash, underdog", {
		`Lean: "leans you +4" means the state started 4 points of margin your way (+2 you, -2 them). {c.LEAN_STATE_COUNT} states get a random lean of {c.LEAN_MIN} to {c.LEAN_MAX} ({c.LEAN_BIG_STATE_CAP} at most in states with {c.BIG_STATE_EV}+ EV), balanced between players.`,
		`Draft bonuses: home state {signed(c.HOME_BONUS)} ({signed(c.HOME_BONUS_BIG)} if big), stronghold {signed(
			c.STRONGHOLD_BONUS
		)} ({signed(c.STRONGHOLD_BONUS_BIG)} if big). A nominated battleground loses its bonus but gets {times(
			c.BATTLEGROUND_MULT
		)} on every campaign effect.`,
		`Momentum: rallies add {num(c.RALLY_MOMENTUM)}, ads {num(c.MEDIA_MOMENTUM)}, attacks none (max {num(
			c.MOMENTUM_CAP
		)}). Drift: {Explain.driftRule(c, view)}. The ▲ on the map marks the leader.`,
		`Backlash: each attack ad fills your meter in that state by 1. Once it is at {c.BACKLASH_THRESHOLD}, the next attack there also costs you {points(
			c.BACKLASH_PENALTY
		)} support and empties it. It fades {num(c.BACKLASH_DECAY)} a week.`,
		`Underdog tier: from your projected EV deficit, smoothed over weeks. Tier 1 at {c.UNDERDOG_EV_1}+ EV behind: rallies {times(
			c.UNDERDOG_RALLY_1
		)}, fundraisers {times(c.UNDERDOG_FUND_1)}. Tier 2 at {c.UNDERDOG_EV_2}+: rallies {times(
			c.UNDERDOG_RALLY_2
		)}, fundraisers {times(c.UNDERDOG_FUND_2)}. You drop a tier only once the gap is {c.UNDERDOG_HYSTERESIS} EV under its line.`,
	})

	section("ground", "Ground game", {
		`Each unit adds {signed(c.GOTV_PER_UNIT)} to your margin in that state on election night, and nowhere else: polls and the projection never show it, and your opponent never sees your units.`,
		`Units cost {Numbers.cost(me.gotvCost)}, stack up to {me.gotvMaxUnits} per state over the match, and need no AP or travel. Best in close states you expect to lose by a little.`,
	})

	section("polls", "Polls", {
		`Public polls (everyone sees them) are true support plus an error of about {num(c.POLL_SIGMA)} points on the margin. {pct(
			c.POLL_RHO
		)} of each state's error carries into next week, so a poll can stay wrong for weeks.`,
		"Projected EV gives each state to whoever leads its public poll; a tied poll counts for nobody, so the two totals rarely add to 538.",
		`Internal polls (only you see them, next week): true support within ±{num(c.INTERNAL_POLL_ERROR)}, exact undecided and momentum. Use them in close states.`,
	})

	local debateWeeks: { string } = {}
	for _, week in c.DEBATE_WEEKS do
		table.insert(debateWeeks, tostring(week))
	end
	section("debates", "Debates", {
		`Debates open weeks {table.concat(debateWeeks, " and ")}, on {c.DEBATE_TOPICS} topics shown in advance. In the week before, spread {me.debatePrep} prep points over them (at most {c.DEBATE_MAX_PER_TOPIC} on one).`,
		`Each topic: prep + {c.DEBATE_PLATFORM_BONUS} if it is on your platform + debate stat ({me.debateStat}) + a roll of 0 to {c.DEBATE_ROLL_MAX}. Higher total wins the topic; a tie gives it to nobody.`,
		`Winning a topic: {signed(c.DEBATE_TOPIC_WIN)} national. Winning all: {signed(c.DEBATE_SWEEP)} more and +{num(
			c.DEBATE_SWEEP_MOMENTUM
		)} momentum in every battleground. Losing a topic you gave 0 prep: {signed(-c.DEBATE_GAFFE)} (a gaffe).`,
		`The roll is big. Level: {oddsText(c, 0)}. 2 points ahead: {oddsText(c, 2)}. 4 ahead: {oddsText(c, 4)}.`,
		"A national point moves every state by about one point (more where more voters are undecided).",
	})

	local choice = Explain.choiceLines(c)
	section("events", "Events", {
		`From week {c.EVENT_FIRST_WEEK} to {c.EVENT_LAST_WEEK}, each week has one public event.`,
		`Spotlight: rallies and ads on its issue {times(c.EVENT_SPOTLIGHT_MULT)}. Regional: rallies in its region {times(
			c.EVENT_REGIONAL_MULT
		)}. Windfall: fundraisers {times(c.EVENT_WINDFALL_MULT)} in states where you trail in the public poll. An event adds at most {num(
			c.EVENT_CAP
		)} per state per week.`,
		"Choice: both answer Attack, Defend or Ignore in secret. National points for you, by their answer:",
		choice[1],
		choice[2],
		choice[3],
	})

	section("election", "Election night", {
		`Each state goes to whoever has more true support, plus {signed(c.GOTV_PER_UNIT)} per ground-game unit, plus a random swing of about {num(
			c.ELECTION_SIGMA
		)} points on the margin.`,
		"Undecided voters do not vote. Polls were never the truth: they carry their own error.",
		`So a public-poll lead of 1 point holds about {pct(Explain.leadWinChance(c, 1))} of the time, 3 points {pct(
			Explain.leadWinChance(c, 3)
		)}, 5 points {pct(Explain.leadWinChance(c, 5))} (without ground game).`,
		`Most electoral votes wins ({c.EV_TO_WIN} of 538 is a sure win). Ties go to states won, then the popular vote, then a coin.`,
	})
	return sections
end

return table.freeze(Explain)
