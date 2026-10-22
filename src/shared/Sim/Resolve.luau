--!strict
-- Weekly resolution in a fixed order: costs and flights, rallies, fundraisers,
-- media and attacks, pivots, the Choice event, momentum, drift, then upkeep and
-- polls. This week's event (Sim/Events) boosts rallies, media and fundraisers
-- within EVENT_CAP per player, state and week (D-027).
--
-- Every step reads one start-of-step snapshot and applies all players' effects
-- together (D-001), so the order of players in the match never matters.

local ConfigModule = require("./Config")
local Events = require("./Events")
local Plan = require("./Plan")
local Polls = require("./Polls")
local Rng = require("./Rng")
local State = require("./State")
local StateData = require("./StateData")
local Support = require("./Support")
local Types = require("../Types")

type Config = ConfigModule.Config
type MatchState = State.MatchState
type StateSim = State.StateSim
type Event = State.Event

local Resolve = {}

-- Issue multiplier for a rally or positive media buy.
function Resolve.issueMult(
	config: Config,
	platform: { Types.Issue },
	stateIssues: { Types.Issue },
	issue: Types.Issue
): number
	local inPlatform = table.find(platform, issue) ~= nil
	local inState = table.find(stateIssues, issue) ~= nil
	if inPlatform and inState then
		return config.ISSUE_MULT_BOTH
	elseif inState then
		return config.ISSUE_MULT_STATE
	elseif inPlatform then
		return config.ISSUE_MULT_PLATFORM
	end
	return config.ISSUE_MULT_NEITHER
end

-- Issue multiplier for an attack: strong on a state top issue the target's platform
-- lacks, weak otherwise (D-016).
function Resolve.attackMult(
	config: Config,
	targetPlatform: { Types.Issue },
	stateIssues: { Types.Issue },
	issue: Types.Issue
): number
	if table.find(stateIssues, issue) and not table.find(targetPlatform, issue) then
		return config.ISSUE_MULT_ATTACK
	end
	return config.ISSUE_MULT_NEITHER
end

function Resolve.closingMult(config: Config, week: number): number
	return if week >= config.CLOSING_FROM_WEEK then config.CLOSING_MULT else 1
end

-- Per-state accumulator for one step: deltas are built against the snapshot and
-- applied together by `flush`.
type Batch = { [number]: { delta: { number }, du: number } }

local function slot(batch: Batch, i: number, s: StateSim)
	local entry = batch[i]
	if entry == nil then
		entry = { delta = Support.zero(s), du = 0 }
		batch[i] = entry
	end
	return entry
end

local function flush(match: MatchState, batch: Batch)
	for i, entry in batch do
		Support.apply(match.states[i], entry.delta, entry.du)
	end
end

-- Resolves the current week from every player's normalized plan. Mutates `match`
-- and returns the events, in resolution order.
function Resolve.week(config: Config, match: MatchState, plans: { Plan.Plan }): { Event }
	local n = #match.players
	local events: { Event } = {}
	local week = match.week
	local closing = Resolve.closingMult(config, week)
	local gained: { [number]: { number } } = {} -- momentum gained this week [state][player]
	local event = Events.at(match)
	local supportLedger: Events.Ledger = {} -- event support granted [state][player]
	local moneyLedger: Events.Ledger = {} -- event money granted [state][player]

	local function addMomentum(i: number, p: number, amount: number)
		local list = gained[i]
		if list == nil then
			list = table.create(n, 0)
			gained[i] = list
		end
		list[p] += amount
	end

	-- 1. Costs, flights, ground game, and the week card.
	local cards: { State.WeekCard } = {}
	for p, player in match.players do
		local plan = plans[p]
		local cost = Plan.cost(config, match, p, plan)
		player.cash -= cost.cash
		cards[p] =
			{ rallies = {}, fundraisers = {}, media = {}, pivot = nil, flights = cost.flights, choice = nil }
		for _, action in plan.actions do
			if action.kind == "Rally" or action.kind == "Fundraise" then
				player.location = action.state
			elseif action.kind == "Gotv" then
				local s = State.get(match, action.state :: string)
				s.gotv[p] += action.units :: number
			end
		end
		if cost.flights > 0 then
			table.insert(events, { kind = "Flights", player = p, amount = cost.flights })
		end
	end

	-- 2. Rallies.
	local batch: Batch = {}
	for p, player in match.players do
		local profile = player.profile
		local underdogRally = Polls.underdogMults(config, match, p)
		local frontrunner = if player.frontrunner then profile.frontrunnerRallyMult else 1
		for _, action in plans[p].actions do
			if action.kind == "Rally" then
				local id = action.state :: string
				local i = State.indexOf[id]
				local s = match.states[i]
				local issue: Types.Issue = action.issue :: Types.Issue
				local mult = Resolve.issueMult(config, player.platform, StateData.list[i].issues, issue)
					* profile.rallyMult
					* (if s.battleground then config.BATTLEGROUND_MULT else 1)
					* underdogRally
					* frontrunner
					* closing
				local gain = profile.rallySupport * mult * Support.saturation(config, s.support[p])
				local eventMult = Events.supportMult(config, event, "Rally", issue, i)
				gain += Events.grant(config, supportLedger, i, p, gain * (eventMult - 1))
				local entry = slot(batch, i, s)
				entry.du += Support.addGain(config, s, p, gain, entry.delta)
				addMomentum(i, p, config.RALLY_MOMENTUM)
				table.insert(cards[p].rallies, { state = id, issue = issue })
				table.insert(events, { kind = "Rally", player = p, state = id, issue = issue :: string })
			end
		end
	end
	flush(match, batch)

	-- 3. Fundraisers. Requests in one state share its pool in proportion to their
	-- raw yields; multipliers apply after the cap and do not drain the pool.
	local requests: { [number]: { { p: number, raw: number } } } = {}
	for p in match.players do
		for _, action in plans[p].actions do
			if action.kind == "Fundraise" then
				local id = action.state :: string
				local i = State.indexOf[id]
				local s = match.states[i]
				local raw = config.FUNDRAISER_BASE + config.FUNDRAISER_PER_SHARE * s.support[p] / 100
				local list = requests[i]
				if list == nil then
					list = {}
					requests[i] = list
				end
				table.insert(list, { p = p, raw = raw })
				table.insert(cards[p].fundraisers, id)
				table.insert(events, { kind = "Fundraise", player = p, state = id })
			end
		end
	end
	for _, player in match.players do
		player.raised = 0
	end
	for i, list in requests do
		local s = match.states[i]
		local total = 0
		for _, request in list do
			total += request.raw
		end
		local scale = if total > s.pool then s.pool / total else 1
		for _, request in list do
			local player = match.players[request.p]
			local profile = player.profile
			local _, underdogFund = Polls.underdogMults(config, match, request.p)
			local take = request.raw * scale
			local home = if s.isHome and s.owner == request.p then config.HOME_FUNDRAISE_MULT else 1
			local frontrunner = if player.frontrunner then profile.frontrunnerFundMult else 1
			local money = take * profile.fundraiseMult * home * underdogFund * frontrunner
			-- Windfall reads the start-of-week public poll, the one both players saw.
			local eventMult = Events.fundMult(config, event, s.poll, request.p)
			money += Events.grant(config, moneyLedger, i, request.p, money * (eventMult - 1))
			player.cash += money
			player.raised += money
		end
		s.pool = math.max(0, s.pool - total * scale)
	end
	for p, player in match.players do
		if player.raised > 0 then
			table.insert(events, { kind = "Raised", player = p, amount = player.raised, private = true })
		end
	end

	-- 4. Media buys and attacks. Repeat buys by one player in one state this week are
	-- worth mediaSaturation^(k-1). Backlash is per attacker, so it is tracked in order.
	batch = {}
	for p, player in match.players do
		local profile = player.profile
		local bought: { [number]: number } = {}
		for _, action in plans[p].actions do
			if action.kind == "Media" or action.kind == "Attack" then
				local id = action.state :: string
				local i = State.indexOf[id]
				local s = match.states[i]
				local issue: Types.Issue = action.issue :: Types.Issue
				local k = (bought[i] or 0) + 1
				bought[i] = k
				local factor = profile.mediaSaturation ^ (k - 1)
				local common = profile.mediaMult
					* (if s.battleground then config.BATTLEGROUND_MULT else 1)
					* closing
					* factor
				local entry = slot(batch, i, s)
				local attack = action.kind == "Attack"
				if attack then
					local target = action.target :: number
					local mult = Resolve.attackMult(
						config,
						match.players[target].platform,
						StateData.list[i].issues,
						issue
					)
					entry.du += Support.addAttack(
						config,
						p,
						target,
						config.ATTACK_LOSS * mult * common,
						entry.delta
					)
					addMomentum(i, p, config.ATTACK_MOMENTUM * factor)
					if s.backlash[p] >= config.BACKLASH_THRESHOLD then
						entry.du += Support.addLoss(p, config.BACKLASH_PENALTY, entry.delta)
						s.backlash[p] = 0
						table.insert(events, { kind = "Backlash", player = p, state = id })
					else
						s.backlash[p] += 1
					end
				else
					local mult = Resolve.issueMult(config, player.platform, StateData.list[i].issues, issue)
					local gain = config.MEDIA_SUPPORT
						* mult
						* common
						* Support.saturation(config, s.support[p])
					local eventMult = Events.supportMult(config, event, "Media", issue, i)
					gain += Events.grant(config, supportLedger, i, p, gain * (eventMult - 1))
					entry.du += Support.addGain(config, s, p, gain, entry.delta)
					addMomentum(i, p, config.MEDIA_MOMENTUM * factor)
				end
				table.insert(cards[p].media, { state = id, issue = issue, attack = attack })
				table.insert(events, {
					kind = if attack then "Attack" else "Media",
					player = p,
					state = id,
					issue = issue :: string,
				})
			end
		end
	end
	flush(match, batch)

	-- 5. Platform pivots: swap the issue, then lose PIVOT_PENALTY national support.
	local national = table.create(n, 0)
	local anyPivot = false
	for p, player in match.players do
		for _, action in plans[p].actions do
			if action.kind == "Pivot" then
				local drop: Types.Issue, add: Types.Issue =
					action.drop :: Types.Issue, action.add :: Types.Issue
				local at = table.find(player.platform, drop) :: number
				player.platform[at] = add
				player.pivotUsed = true
				national[p] -= config.PIVOT_PENALTY
				anyPivot = true
				cards[p].pivot = { drop = drop, add = add }
				table.insert(events, { kind = "Pivot", player = p, issue = add :: string })
			end
		end
	end
	if anyPivot then
		Support.national(config, match.states, national)
	end

	-- 5b. The Choice event: every player's secret answer resolves together through
	-- the payoff matrix, as one national shift. Every event is logged publicly.
	if event ~= nil then
		local result: State.EventResult = { week = week, id = event.id, choices = nil, national = nil }
		if event.kind == "Choice" then
			local choices: { Types.Choice } = {}
			for p in match.players do
				choices[p] = plans[p].choice or "Ignore"
			end
			local payoffs = Events.choicePayoffs(config, choices)
			local any = false
			for p in match.players do
				cards[p].choice = choices[p]
				any = any or payoffs[p] ~= 0
				table.insert(
					events,
					{ kind = "Choice", player = p, issue = choices[p] :: string, amount = payoffs[p] }
				)
			end
			if any then
				Support.national(config, match.states, payoffs)
			end
			result.choices = choices
			result.national = payoffs
		end
		table.insert(match.eventLog, result)
	end

	-- 6. Momentum: decay, add this week's gains (scaled per candidate), clamp.
	for i, s in match.states do
		local list = gained[i]
		for p, player in match.players do
			local add = if list then list[p] * player.profile.momentumGainMult else 0
			s.momentum[p] =
				math.clamp(s.momentum[p] * player.profile.momentumDecay + add, 0, config.MOMENTUM_CAP)
		end
	end

	-- 7. Drift: in each state, only the momentum leader drifts, by DRIFT_RATE x the
	-- gap to the runner-up, capped (D-010).
	for _, s in match.states do
		local leader, best, second = 0, -math.huge, -math.huge
		for p = 1, n do
			local m = s.momentum[p]
			if m > best then
				leader, second, best = p, best, m
			elseif m > second then
				second = m
			end
		end
		local drift = math.min(config.DRIFT_RATE * (best - second), config.DRIFT_CAP)
		if leader > 0 and drift > 0 then
			Support.gain(config, s, leader, drift)
		end
	end

	-- 8. Upkeep: backlash decay, pool refill, income, debate prep, week card.
	for _, s in match.states do
		for p = 1, n do
			s.backlash[p] = math.max(0, s.backlash[p] - config.BACKLASH_DECAY)
		end
		s.pool = math.min(s.capacity, s.pool + s.capacity * config.POOL_REFILL)
	end
	local wantsPrep = Plan.wantsPrep(config, match)
	for p, player in match.players do
		player.cash += player.profile.passiveIncome
		player.card = cards[p]
		if wantsPrep then
			player.debatePrep = plans[p].prep or Plan.defaultPrep(config, player.profile.debatePrep)
		end
	end

	-- 9. Public polls, the rubber band, and internal polls (end-of-week truth).
	Polls.update(config, match, false)
	Polls.updateUnderdog(config, match)
	for p, player in match.players do
		local rng = Rng.fork(match.rng, `internal:{week}:{p}`)
		local seen: { [string]: boolean } = {}
		local results: { State.InternalPoll } = {}
		local function poll(id: string)
			if not seen[id] then
				seen[id] = true
				table.insert(results, Polls.internal(config, rng, State.get(match, id)))
			end
		end
		for _, action in plans[p].actions do
			if action.kind == "Poll" then
				poll(action.state :: string)
			elseif action.kind == "RegionPoll" then
				for _, record in StateData.list do
					if record.region == action.region then
						poll(record.id)
					end
				end
			end
		end
		player.internalPolls = results
		if #results > 0 then
			table.insert(events, { kind = "InternalPolls", player = p, amount = #results, private = true })
		end
	end
	table.insert(events, { kind = "Polls" })
	return events
end

return table.freeze(Resolve)
