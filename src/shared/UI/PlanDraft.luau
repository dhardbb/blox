--!strict
-- The plan a player is building on the campaign screen, before they lock in.
-- Pure: works from the player's own View only, and shows cost and problems
-- before anything is sent. The server still validates the submission
-- (Plan.validate); this only previews, using the same cost function.

local Candidates = require("../Sim/Candidates")
local ConfigModule = require("../Sim/Config")
local Plan = require("../Sim/Plan")
local Resolve = require("../Sim/Resolve")
local StateData = require("../Sim/StateData")
local Types = require("../Types")
local ViewModule = require("../Sim/View")

type Config = ConfigModule.Config
type View = ViewModule.View

export type Draft = {
	actions: { Plan.Action },
	prep: { number }?,
}

-- One stop on the route (rallies and fundraisers), for drawing the path.
export type Stop = {
	index: number, -- position in draft.actions
	state: string,
	kind: Plan.Kind,
	flight: boolean, -- this hop is a flight ($)
}

local PlanDraft = {}

local ISSUES: { Types.Issue } = {
	"Jobs",
	"Health",
	"Schools",
	"Environment",
	"Safety",
	"Transit",
	"Technology",
	"Farms",
}

function PlanDraft.new(): Draft
	return { actions = {}, prep = nil }
end

function PlanDraft.profile(config: Config, view: View): Candidates.Profile
	local me = view.players[view.you]
	return Candidates.profile(config, me.candidate or Candidates.ids[1])
end

-- Plan.cost reads only the player's profile and location, so a minimal stand-in
-- for the match keeps the preview identical to what the server will charge.
local function standIn(config: Config, view: View): any
	local players = {}
	for p, player in view.players do
		players[p] = {
			profile = if p == view.you then PlanDraft.profile(config, view) else nil,
			location = player.location,
		}
	end
	return { players = players }
end

function PlanDraft.cost(config: Config, view: View, draft: Draft): Plan.Cost
	return Plan.cost(config, standIn(config, view), view.you, { actions = draft.actions, prep = draft.prep })
end

-- AP and money left after the draft.
function PlanDraft.remaining(config: Config, view: View, draft: Draft): (number, number)
	local cost = PlanDraft.cost(config, view, draft)
	local profile = PlanDraft.profile(config, view)
	return profile.apPerWeek - cost.ap, (view.players[view.you].cash or 0) - cost.cash
end

-- The first problem the server would reject the draft for, or nil. Mirrors the
-- rules in Plan.validate that the View can check, in the same order.
function PlanDraft.problem(config: Config, view: View, draft: Draft): string?
	if #draft.actions > config.PLAN_MAX_ACTIONS then
		return Plan.Reason.TooManyActions
	end
	local profile = PlanDraft.profile(config, view)
	local gotv: { [string]: number } = {}
	local polled: { [string]: boolean } = {}
	local pivots = 0
	for _, action in draft.actions do
		if action.kind == "Gotv" then
			local id = action.state :: string
			gotv[id] = (gotv[id] or 0) + (action.units :: number)
			local placed = 0
			for i, record in StateData.list do
				if record.id == id then
					placed = view.states[i].gotv
				end
			end
			if placed + gotv[id] > profile.gotvMaxUnits then
				return Plan.Reason.GotvCap
			end
		elseif action.kind == "Poll" then
			local id = action.state :: string
			if polled[id] then
				return Plan.Reason.DuplicatePoll
			end
			polled[id] = true
		elseif action.kind == "Pivot" then
			pivots += 1
			if pivots > 1 or view.players[view.you].pivotUsed then
				return Plan.Reason.PivotUsed
			end
		end
	end
	local ap, cash = PlanDraft.remaining(config, view, draft)
	if ap < 0 then
		return Plan.Reason.NotEnoughAP
	end
	if cash < -1e-9 then
		return Plan.Reason.NotEnoughMoney
	end
	return nil
end

-- The route: rallies and fundraisers in order, marking flights.
function PlanDraft.route(view: View, draft: Draft): { Stop }
	local stops: { Stop } = {}
	local location = view.players[view.you].location
	for k, action in draft.actions do
		if action.kind == "Rally" or action.kind == "Fundraise" then
			local id = action.state :: string
			table.insert(stops, {
				index = k,
				state = id,
				kind = action.kind,
				flight = not Plan.isAdjacent(location, id),
			})
			location = id
		end
	end
	return stops
end

-- Where the candidate would be after the draft's route.
function PlanDraft.location(view: View, draft: Draft): string?
	local stops = PlanDraft.route(view, draft)
	return if #stops > 0 then stops[#stops].state else view.players[view.you].location
end

local function stateIssues(id: string): { Types.Issue }
	local record = StateData.byId[id]
	return if record then record.issues else {}
end

-- The issue that gives a rally or positive ad its biggest multiplier here.
function PlanDraft.bestIssue(config: Config, view: View, id: string): (Types.Issue, number)
	local platform: { Types.Issue } = view.players[view.you].platform or {}
	local best: Types.Issue, bestMult = ISSUES[1], -math.huge
	for k = 1, #ISSUES do
		local issue: Types.Issue = ISSUES[k]
		local mult = Resolve.issueMult(config, platform, stateIssues(id), issue)
		if mult > bestMult then
			best, bestMult = issue, mult
		end
	end
	return best, bestMult
end

-- The issue that makes an attack on the opponent hit hardest here.
function PlanDraft.bestAttackIssue(config: Config, view: View, id: string): (Types.Issue, number)
	local them = if view.you == 1 then 2 else 1
	local platform: { Types.Issue } = view.players[them].platform or {}
	local issues = stateIssues(id)
	local best: Types.Issue, bestMult = issues[1] or ISSUES[1], -math.huge
	for k = 1, #issues do
		local issue: Types.Issue = issues[k]
		local mult = Resolve.attackMult(config, platform, issues, issue)
		if mult > bestMult then
			best, bestMult = issue, mult
		end
	end
	return best, bestMult
end

function PlanDraft.add(draft: Draft, action: Plan.Action)
	table.insert(draft.actions, action)
end

function PlanDraft.remove(draft: Draft, index: number)
	table.remove(draft.actions, index)
end

-- The payload for a Submit request.
function PlanDraft.payload(draft: Draft): any
	local actions = {}
	for k, action in draft.actions do
		actions[k] = table.clone(action)
	end
	return { actions = actions, prep = if draft.prep then table.clone(draft.prep) else nil }
end

return table.freeze(PlanDraft)
