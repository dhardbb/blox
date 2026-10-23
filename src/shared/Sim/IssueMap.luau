--!strict
-- Each match's top issues (D-047): two per state, drawn from the match seed, so
-- the electoral votes behind each issue change every match and no platform is
-- always the right one. Public from the first View on: players pick a platform
-- against it at Select.
--
-- The draw: every state takes two different issues, its regional flavor
-- (StateData's `flavor`) ISSUE_FLAVOR_WEIGHT times as likely as the rest. Then a
-- seeded local search replaces one state's issue or trades issues between two
-- states (accepting any move that does not make things worse) until every issue's total EV sits within ISSUE_EV_BAND of the
-- mean and every issue tops ISSUE_MIN_STATES..ISSUE_MAX_STATES states, or
-- ISSUE_DRAW_STEPS proposals run out (the specs check the band is always met).
-- Pure and deterministic: the same seed draws the same map.

local ConfigModule = require("./Config")
local Issues = require("./Issues")
local Rng = require("./Rng")
local StateData = require("./StateData")
local Types = require("../Types")

type Config = ConfigModule.Config

-- Top issues by state, in StateData.list order (index i = StateData.list[i]).
export type IssueMap = { { Types.Issue } }

local IssueMap = {}

local ISSUES: { Types.Issue } = Issues.list :: any
local NAMES: { string } = Issues.list :: any -- the same list, untyped for the draw's tables
local COUNT = #ISSUES
local COUNT_WEIGHT = 10 -- cost of one state too many or too few, in EV (a search weight, not a rule)

local indexOf: { [string]: number } = {}
for i, record in StateData.list do
	indexOf[record.id] = i
end

-- The regional-flavor map from StateData: no longer what a match plays on, but
-- a fixed, valid map for specs that need known issues.
local flavor: IssueMap = {}
for i, record in StateData.list do
	flavor[i] = table.freeze(table.clone(record.flavor))
end
IssueMap.flavor = table.freeze(flavor)

-- Total EV of the states where each issue is a top issue.
function IssueMap.evByIssue(map: IssueMap): { [string]: number }
	local out: { [string]: number } = {}
	for _, issue in ISSUES do
		out[issue] = 0
	end
	for i, record in StateData.list do
		for _, issue in map[i] do
			out[issue] += record.ev
		end
	end
	return out
end

-- Number of states where each issue is a top issue.
function IssueMap.statesByIssue(map: IssueMap): { [string]: number }
	local out: { [string]: number } = {}
	for _, issue in ISSUES do
		out[issue] = 0
	end
	for i in StateData.list do
		for _, issue in map[i] do
			out[issue] += 1
		end
	end
	return out
end

-- The top issues of a state id ({} for an unknown id).
function IssueMap.of(map: IssueMap, id: string): { Types.Issue }
	local i = indexOf[id]
	return if i and map[i] then map[i] else {}
end

-- Is `issue` a top issue of the state at index i?
function IssueMap.has(map: IssueMap, i: number, issue: Types.Issue): boolean
	local issues = map[i]
	return issues ~= nil and table.find(issues, issue) ~= nil
end

-- The issues in descending EV order (ties in Issues.list order).
function IssueMap.ranked(map: IssueMap): { Types.Issue }
	local ev = IssueMap.evByIssue(map)
	local order: { Types.Issue } = table.clone(ISSUES)
	local position: { [string]: number } = {}
	for k, issue in ISSUES do
		position[issue] = k
	end
	table.sort(order, function(a, b)
		if ev[a] ~= ev[b] then
			return ev[a] > ev[b]
		end
		return position[a] < position[b]
	end)
	return order
end

-- A weighted pick from ISSUES, skipping `exclude`: flavor issues count `weight`.
local function weightedPick(
	rng: Rng.Rng,
	flavorIssues: { string },
	weight: number,
	exclude: { string }
): string
	local total = 0
	for _, issue in NAMES do
		if not table.find(exclude, issue) then
			total += if table.find(flavorIssues, issue) then weight else 1
		end
	end
	local roll = Rng.nextFloat(rng) * total
	local last = NAMES[1]
	for _, issue in NAMES do
		if not table.find(exclude, issue) then
			last = issue
			roll -= if table.find(flavorIssues, issue) then weight else 1
			if roll < 0 then
				return issue
			end
		end
	end
	return last
end

-- The multiplier a rally or positive ad gets on a platform issue in a state where
-- it is a top issue, by issue, this match (D-047, "niche issues hit harder"): the
-- bonus over ISSUE_MULT_STATE is ISSUE_MULT_BOTH's, scaled by
-- (mean EV / the issue's EV)^ISSUE_NICHE_POWER and capped at ISSUE_NICHE_MAX. An
-- issue that covers few electoral votes moves its few states more, so every
-- platform pick is worth about the same and the right one depends on where you
-- plan to fight. Rounded to hundredths so the screens can print it exactly.
function IssueMap.platformMults(config: Config, map: IssueMap): { [string]: number }
	local ev = IssueMap.evByIssue(map)
	local total = 0
	for _, record in StateData.list do
		total += record.ev
	end
	local mean = total * 2 / COUNT
	local bonus = config.ISSUE_MULT_BOTH - config.ISSUE_MULT_STATE
	local out: { [string]: number } = {}
	for _, issue in NAMES do
		local scale = (mean / math.max(1, ev[issue])) ^ config.ISSUE_NICHE_POWER
		local mult = math.min(config.ISSUE_NICHE_MAX, config.ISSUE_MULT_STATE + bonus * scale)
		out[issue] = math.floor(mult * 100 + 0.5) / 100
	end
	return table.freeze(out)
end

-- Draws a match's issue map from `rng` (fork a labeled child for it).
function IssueMap.draw(config: Config, rng: Rng.Rng): IssueMap
	local states = StateData.list
	local n = #states
	local totalEV = 0
	for _, record in states do
		totalEV += record.ev
	end
	local mean = totalEV * 2 / COUNT
	local lo, hi = mean * (1 - config.ISSUE_EV_BAND), mean * (1 + config.ISSUE_EV_BAND)
	local minStates, maxStates = config.ISSUE_MIN_STATES, config.ISSUE_MAX_STATES
	local weight = config.ISSUE_FLAVOR_WEIGHT

	local map: { { string } } = {}
	local ev: { [string]: number } = {}
	local count: { [string]: number } = {}
	for _, issue in NAMES do
		ev[issue], count[issue] = 0, 0
	end
	for i, record in states do
		local first = weightedPick(rng, record.flavor :: any, weight, {})
		local second = weightedPick(rng, record.flavor :: any, weight, { first })
		map[i] = { first, second }
		for _, issue in map[i] do
			ev[issue] += record.ev
			count[issue] += 1
		end
	end

	-- How far one issue is outside the band, in EV.
	local function issueCost(e: number, c: number): number
		local cost = math.max(0, e - hi) + math.max(0, lo - e)
		return cost + COUNT_WEIGHT * (math.max(0, c - maxStates) + math.max(0, minStates - c))
	end
	local cost = 0
	for _, issue in NAMES do
		cost += issueCost(ev[issue], count[issue])
	end

	-- Moves one state's issue from `old` to `new` in the running totals.
	local function shift(record: Types.StateRecord, old: string, new: string)
		ev[old] -= record.ev
		count[old] -= 1
		ev[new] += record.ev
		count[new] += 1
	end

	for _ = 1, config.ISSUE_DRAW_STEPS do
		if cost <= 0 then
			break
		end
		local i = Rng.nextInt(rng, 1, n)
		local slot = Rng.nextInt(rng, 1, 2)
		local record = states[i]
		local old = map[i][slot]
		if Rng.nextFloat(rng) < 0.5 then
			-- Replace one issue of one state (moves EV and a state count).
			local new = weightedPick(rng, record.flavor :: any, weight, map[i])
			local before = issueCost(ev[old], count[old]) + issueCost(ev[new], count[new])
			local after = issueCost(ev[old] - record.ev, count[old] - 1)
				+ issueCost(ev[new] + record.ev, count[new] + 1)
			if after <= before then
				map[i][slot] = new
				shift(record, old, new)
				cost += after - before
			end
		else
			-- Trade issues between two states (moves EV, keeps the state counts).
			local j = Rng.nextInt(rng, 1, n)
			local otherSlot = Rng.nextInt(rng, 1, 2)
			local other = states[j]
			local theirs = map[j][otherSlot]
			if old ~= theirs and table.find(map[i], theirs) == nil and table.find(map[j], old) == nil then
				local delta = other.ev - record.ev
				local before = issueCost(ev[old], count[old]) + issueCost(ev[theirs], count[theirs])
				local after = issueCost(ev[old] + delta, count[old])
					+ issueCost(ev[theirs] - delta, count[theirs])
				if after <= before then
					map[i][slot], map[j][otherSlot] = theirs, old
					ev[old] += delta
					ev[theirs] -= delta
					cost += after - before
				end
			end
		end
	end

	-- Each state's two issues in Issues.list order, so the map reads the same way
	-- however it was drawn. Frozen: a match shares it across clones and views.
	local position: { [string]: number } = {}
	for k, issue in ISSUES do
		position[issue] = k
	end
	for i in states do
		table.sort(map[i], function(a, b)
			return position[a] < position[b]
		end)
		table.freeze(map[i])
	end
	return table.freeze(map) :: any
end

return table.freeze(IssueMap)
