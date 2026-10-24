--!strict
-- Weekly plan schema and validation. The server runs every client payload through
-- Plan.validate; an invalid plan is rejected whole with a reason code and never
-- throws. A valid plan comes back normalized: a fresh table holding only known
-- fields, so nothing a client adds survives into the simulation.
--
-- Rallies and fundraisers form the candidate's route: each stop must be the current
-- state or adjacent to the previous stop, otherwise it is a flight (FLIGHT_COST, no AP).
--
-- Choice stances and debate moves are not part of a plan: a stance has its own
-- Decision phase before it (Sim/Decision, D-044) and a debate its own rounds
-- (Sim/Debate, D-062). A plan that carries `focus`, `choice` or `move` is
-- rejected (UnexpectedFocus, UnexpectedChoice, UnexpectedMove).

local ConfigModule = require("./Config")
local Issues = require("./Issues")
local State = require("./State")
local StateData = require("./StateData")
local Types = require("../Types")

type Config = ConfigModule.Config
type MatchState = State.MatchState

export type Kind = "Rally" | "Fundraise" | "Media" | "Attack" | "Poll" | "RegionPoll" | "Gotv" | "Pivot"

export type Action = {
	kind: Kind,
	state: string?, -- every kind except RegionPoll and Pivot
	issue: Types.Issue?, -- Rally, Media, Attack
	target: number?, -- Attack: the player attacked (optional with one opponent)
	region: Types.Region?, -- RegionPoll
	units: number?, -- Gotv
	drop: Types.Issue?, -- Pivot
	add: Types.Issue?, -- Pivot
}

export type Plan = {
	actions: { Action },
}

export type Cost = {
	ap: number,
	cash: number,
	flights: number,
}

local Plan = {}

-- Reason codes (stable strings; the client maps them to messages).
Plan.Reason = table.freeze({
	WrongPhase = "WrongPhase",
	BadShape = "BadShape",
	TooManyActions = "TooManyActions",
	UnknownKind = "UnknownKind",
	UnknownState = "UnknownState",
	UnknownIssue = "UnknownIssue",
	UnknownRegion = "UnknownRegion",
	BadTarget = "BadTarget",
	BadUnits = "BadUnits",
	GotvCap = "GotvCap",
	DuplicatePoll = "DuplicatePoll",
	PivotUsed = "PivotUsed",
	BadPivot = "BadPivot",
	NotEnoughAP = "NotEnoughAP",
	NotEnoughMoney = "NotEnoughMoney",
	-- Decision phase codes (Sim/Decision), and a plan that carries a focus or a stance.
	BadFocus = "BadFocus", -- no longer sent: the debate focus is gone (D-062); kept so old clients' messages still map
	UnexpectedFocus = "UnexpectedFocus",
	BadChoice = "BadChoice",
	UnexpectedChoice = "UnexpectedChoice",
	-- Debate round codes (Sim/Debate, D-062), and a plan that carries a move.
	BadMove = "BadMove",
	ZingerSpent = "ZingerSpent",
	UnexpectedMove = "UnexpectedMove",
})

local R = Plan.Reason

local KINDS: { [string]: boolean } = {
	Rally = true,
	Fundraise = true,
	Media = true,
	Attack = true,
	Poll = true,
	RegionPoll = true,
	Gotv = true,
	Pivot = true,
}

local isRegion: { [string]: boolean } = {}
for _, region in Issues.regions do
	isRegion[region] = true
end

local function isInteger(value: any): boolean
	return type(value) == "number" and value == math.floor(value) and value == value
end

-- Is moving from `from` to `to` free (same state or a land border)?
function Plan.isAdjacent(from: string?, to: string): boolean
	if from == nil or from == to then
		return true
	end
	return table.find(StateData.byId[from].adjacent, to) ~= nil
end

-- AP, cash and flights a (normalized) plan costs player p.
function Plan.cost(config: Config, match: MatchState, p: number, plan: Plan): Cost
	local player = match.players[p]
	local profile = player.profile
	local ap, cash, flights = 0, 0, 0
	local location = player.location
	local freePolls = profile.freePolls
	for _, action in plan.actions do
		local kind = action.kind
		if kind == "Rally" or kind == "Fundraise" then
			ap += 1
			local stop = action.state :: string
			if not Plan.isAdjacent(location, stop) then
				flights += 1
				cash += config.FLIGHT_COST
			end
			location = stop
		elseif kind == "Media" or kind == "Attack" then
			cash += profile.mediaCost
		elseif kind == "Poll" then
			if freePolls > 0 then
				freePolls -= 1
			else
				cash += config.INTERNAL_POLL_COST
			end
		elseif kind == "RegionPoll" then
			cash += config.REGION_POLL_COST
		elseif kind == "Gotv" then
			cash += (action.units :: number) * profile.gotvCost
		elseif kind == "Pivot" then
			ap += config.PIVOT_AP
		end
	end
	return { ap = ap, cash = cash, flights = flights }
end

-- Checks one action's fields; returns a normalized copy or a reason code.
local function normalizeAction(match: MatchState, p: number, raw: any): (Action?, string?)
	if type(raw) ~= "table" then
		return nil, R.BadShape
	end
	local kind = raw.kind
	if type(kind) ~= "string" or not KINDS[kind] then
		return nil, R.UnknownKind
	end
	local action: Action = { kind = kind :: Kind }
	local player = match.players[p]

	if kind ~= "RegionPoll" and kind ~= "Pivot" then
		local id = raw.state
		if type(id) ~= "string" or State.indexOf[id] == nil then
			return nil, R.UnknownState
		end
		action.state = id
	end

	if kind == "Rally" or kind == "Media" or kind == "Attack" then
		local issue = raw.issue
		if type(issue) ~= "string" or not Issues.isIssue(issue) then
			return nil, R.UnknownIssue
		end
		action.issue = issue :: Types.Issue
	end

	if kind == "Attack" then
		local target = raw.target
		if target == nil then
			if #match.players ~= 2 then
				return nil, R.BadTarget
			end
			target = if p == 1 then 2 else 1
		end
		if not isInteger(target) or target < 1 or target > #match.players or target == p then
			return nil, R.BadTarget
		end
		action.target = target
	elseif kind == "RegionPoll" then
		local region = raw.region
		if type(region) ~= "string" or not isRegion[region] then
			return nil, R.UnknownRegion
		end
		action.region = region :: Types.Region
	elseif kind == "Gotv" then
		local units = raw.units
		if not isInteger(units) or units < 1 then
			return nil, R.BadUnits
		end
		action.units = units
	elseif kind == "Pivot" then
		local drop, add = raw.drop, raw.add
		if type(drop) ~= "string" or type(add) ~= "string" then
			return nil, R.BadPivot
		end
		if not Issues.isIssue(drop) or not Issues.isIssue(add) then
			return nil, R.UnknownIssue
		end
		if
			not table.find(player.platform, drop :: Types.Issue)
			or table.find(player.platform, add :: Types.Issue)
		then
			return nil, R.BadPivot
		end
		action.drop = drop :: Types.Issue
		action.add = add :: Types.Issue
	end
	return action, nil
end

-- Validates player p's plan for the current week. Returns (true, nil, plan) with a
-- normalized plan, or (false, reason, nil).
function Plan.validate(config: Config, match: MatchState, p: number, input: any): (boolean, string?, Plan?)
	if match.phase ~= "Plan" then
		return false, R.WrongPhase, nil
	end
	if type(input) ~= "table" or type(input.actions) ~= "table" then
		return false, R.BadShape, nil
	end
	if input.focus ~= nil then
		return false, R.UnexpectedFocus, nil
	end
	if input.choice ~= nil then
		return false, R.UnexpectedChoice, nil
	end
	if input.move ~= nil or input.zinger ~= nil then
		return false, R.UnexpectedMove, nil
	end
	local raw = input.actions
	local count = 0
	for key in raw do
		if type(key) ~= "number" then
			return false, R.BadShape, nil
		end
		count += 1
	end
	if #raw ~= count then
		return false, R.BadShape, nil
	end
	if count > config.PLAN_MAX_ACTIONS then
		return false, R.TooManyActions, nil
	end

	local player = match.players[p]
	local actions: { Action } = {}
	local polled: { [string]: boolean } = {}
	local gotv: { [string]: number } = {}
	local pivots = 0
	for k = 1, count do
		local action, reason = normalizeAction(match, p, raw[k])
		if action == nil then
			return false, reason, nil
		end
		if action.kind == "Poll" then
			local id = action.state :: string
			if polled[id] then
				return false, R.DuplicatePoll, nil
			end
			polled[id] = true
		elseif action.kind == "Gotv" then
			local id = action.state :: string
			local units = (gotv[id] or 0) + (action.units :: number)
			gotv[id] = units
			if State.get(match, id).gotv[p] + units > player.profile.gotvMaxUnits then
				return false, R.GotvCap, nil
			end
		elseif action.kind == "Pivot" then
			pivots += 1
			if player.pivotUsed or pivots > 1 then
				return false, R.PivotUsed, nil
			end
		end
		table.insert(actions, action)
	end

	local plan: Plan = { actions = actions }
	local cost = Plan.cost(config, match, p, plan)
	if cost.ap > player.profile.apPerWeek then
		return false, R.NotEnoughAP, nil
	end
	if cost.cash > player.cash + 1e-9 then
		return false, R.NotEnoughMoney, nil
	end
	return true, nil, plan
end

-- The plan submitted for a player who does not lock in: nothing (money banks, AP is
-- lost).
function Plan.empty(): Plan
	return { actions = {} }
end

return table.freeze(Plan)
