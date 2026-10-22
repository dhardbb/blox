--!strict
-- The plan a player is building on the campaign screen, before they lock in.
-- Pure: works from the player's own View only, and shows cost and problems
-- before anything is sent. The server still validates the submission
-- (Plan.validate); this only previews, using the same cost function.

local Candidates = require("../Sim/Candidates")
local ConfigModule = require("../Sim/Config")
local Events = require("../Sim/Events")
local Issues = require("../Sim/Issues")
local Numbers = require("./Numbers")
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
	choice: Types.Choice?, -- answer to this week's Choice event (nil in any other week)
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
	return { actions = {}, prep = nil, choice = nil }
end

-- Is this week's event one that asks for a Choice answer?
function PlanDraft.isChoiceWeek(view: View): boolean
	return view.event ~= nil and view.event.kind == "Choice"
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

-- One money line of a plan: "1 flight" costing $2.
export type CostItem = { label: string, count: number, amount: number }

local function plural(n: number, word: string): string
	return `{n} {word}{if n == 1 then "" else "s"}`
end

-- What the plan spends money on, grouped, in a fixed order; the amounts add up to
-- PlanDraft.cost(...).cash. Polls covered by the free weekly polls are left out.
function PlanDraft.costItems(config: Config, view: View, draft: Draft): { CostItem }
	local profile = PlanDraft.profile(config, view)
	local cost = PlanDraft.cost(config, view, draft)
	local ads, attacks, polls, regionPolls, units = 0, 0, 0, 0, 0
	for _, action in draft.actions do
		local kind = action.kind
		if kind == "Media" then
			ads += 1
		elseif kind == "Attack" then
			attacks += 1
		elseif kind == "Poll" then
			polls += 1
		elseif kind == "RegionPoll" then
			regionPolls += 1
		elseif kind == "Gotv" then
			units += action.units or 0
		end
	end
	local paidPolls = math.max(0, polls - profile.freePolls)
	local items: { CostItem } = {}
	local function item(count: number, word: string, each: number)
		if count > 0 and each > 0 then
			table.insert(items, { label = plural(count, word), count = count, amount = count * each })
		end
	end
	item(cost.flights, "flight", config.FLIGHT_COST)
	item(ads, "ad", profile.mediaCost)
	item(attacks, "attack ad", profile.mediaCost)
	item(paidPolls, "poll", config.INTERNAL_POLL_COST)
	item(regionPolls, "region poll", config.REGION_POLL_COST)
	if units > 0 and profile.gotvCost > 0 then
		table.insert(
			items,
			{ label = `{units} ground game`, count = units, amount = units * profile.gotvCost }
		)
	end
	return items
end

-- "Plan costs $5.0, you have $4.9 (1 flight $2.0, 1 ad $3.0)." Cash is floored
-- like every money display, so the two numbers always explain the rejection.
function PlanDraft.moneyText(config: Config, view: View, draft: Draft): string
	local cost = PlanDraft.cost(config, view, draft)
	local cash = view.players[view.you].cash or 0
	local parts = {}
	for _, entry in PlanDraft.costItems(config, view, draft) do
		table.insert(parts, `{entry.label} {Numbers.cost(entry.amount)}`)
	end
	local text = `Plan costs {Numbers.cost(cost.cash)}, you have {Numbers.money(cash)}`
	if #parts > 0 then
		text ..= ` ({table.concat(parts, ", ")})`
	end
	return text .. "."
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
	if draft.choice ~= nil and not PlanDraft.isChoiceWeek(view) then
		return Plan.Reason.UnexpectedChoice
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

-- One message chip on the state card: an issue and its rally multiplier here.
export type MessageChoice = { issue: Types.Issue, mult: number }

PlanDraft.MESSAGE_CHOICES = 5 -- most message chips the state card shows before "More"

-- The message chips for state `id`: the best issue first, then the state's two
-- top issues and your platform, deduplicated, by multiplier (ties keep that
-- order), at most MESSAGE_CHOICES of them.
function PlanDraft.messageChoices(config: Config, view: View, id: string): { MessageChoice }
	local platform: { Types.Issue } = view.players[view.you].platform or {}
	local issues = stateIssues(id)
	local pool: { Types.Issue } = {}
	local function offer(issue: Types.Issue)
		if not table.find(pool, issue) then
			table.insert(pool, issue)
		end
	end
	offer((PlanDraft.bestIssue(config, view, id)))
	for k = 1, #issues do
		offer(issues[k])
	end
	for k = 1, #platform do
		offer(platform[k])
	end
	local ranked: { { issue: Types.Issue, mult: number, at: number } } = {}
	for k = 1, #pool do
		local issue: Types.Issue = pool[k]
		table.insert(
			ranked,
			{ issue = issue, mult = Resolve.issueMult(config, platform, issues, issue), at = k }
		)
	end
	table.sort(ranked, function(a, b)
		if math.abs(a.mult - b.mult) > 1e-9 then
			return a.mult > b.mult
		end
		return a.at < b.at
	end)
	local out: { MessageChoice } = {}
	for k = 1, math.min(#ranked, PlanDraft.MESSAGE_CHOICES) do
		table.insert(out, { issue = ranked[k].issue, mult = ranked[k].mult })
	end
	return out
end

-- The region a state belongs to (what a Region poll there covers), or nil.
function PlanDraft.regionOf(id: string): Types.Region?
	local record = StateData.byId[id]
	return if record then record.region else nil
end

-- A plan problem in a few words, for the disabled Lock in button.
local SHORT_PROBLEM: { [string]: string } = {
	[Plan.Reason.TooManyActions] = "Too many actions",
	[Plan.Reason.NotEnoughAP] = "Not enough AP",
	[Plan.Reason.NotEnoughMoney] = "Not enough money",
	[Plan.Reason.GotvCap] = "Ground game over the limit",
	[Plan.Reason.DuplicatePoll] = "One poll per state",
	[Plan.Reason.PivotUsed] = "Pivot already used",
}

function PlanDraft.shortProblem(reason: string?): string
	return SHORT_PROBLEM[reason or ""] or "Fix your plan"
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
	return {
		actions = actions,
		prep = if draft.prep then table.clone(draft.prep) else nil,
		choice = draft.choice,
	}
end

-- ------------------------------------------------------------ weekly events (D-027)

-- A multiplier as plain text: 1.3 -> "×1.3", 2 -> "×2".
local function times(mult: number): string
	local text = string.format("%.2f", mult)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return "×" .. text
end

-- National points with a sign, never "-0.0".
local points = Numbers.signed

-- What this week's event does, in plain words, with the numbers from Config.
function PlanDraft.eventEffect(config: Config, event: ViewModule.EventView): string
	if event.kind == "Spotlight" then
		local issue = Issues.displayName[event.issue :: Types.Issue] or "?"
		return `Rallies and ads about {issue} are worth {times(config.EVENT_SPOTLIGHT_MULT)} this week`
	elseif event.kind == "Regional" then
		local region = Issues.regionName[event.region :: Types.Region] or "?"
		return `Rallies in the {region} states are worth {times(config.EVENT_REGIONAL_MULT)} this week`
	elseif event.kind == "Windfall" then
		return `Fundraisers in states where you trail in the public poll raise {times(
			config.EVENT_WINDFALL_MULT
		)} this week`
	end
	return "Take a stance: A / B / C"
end

-- The states a Spotlight or Regional event singles out, as a set of state ids
-- (Spotlight: the issue is one of the state's two top issues).
function PlanDraft.eventStates(event: ViewModule.EventView): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, record in StateData.list do
		local hit = false
		if event.kind == "Spotlight" then
			hit = event.issue ~= nil and table.find(record.issues, event.issue) ~= nil
		elseif event.kind == "Regional" then
			hit = record.region == event.region
		end
		if hit then
			out[record.id] = true
		end
	end
	return out
end

-- Why the map marks some states for this event (nil for Windfall and Choice).
function PlanDraft.eventMapNote(event: ViewModule.EventView): string?
	if event.kind == "Spotlight" then
		return `States marked * have {Issues.displayName[event.issue :: Types.Issue] or "?"} as a top issue.`
	elseif event.kind == "Regional" then
		return `States marked * are in the {Issues.regionName[event.region :: Types.Region] or "?"}.`
	end
	return nil
end

-- One sentence on how a stance lands, from Config (D-039).
function PlanDraft.choiceNote(config: Config): string
	return `Only states with this issue as a top issue react, by their other top issue: {points(
		config.STANCE_POINTS
	)} where a stance is liked, {points(-config.STANCE_POINTS)} where it is not, {points(config.STANCE_HEDGE)} otherwise. C is the hedge: {points(
		config.STANCE_HEDGE
	)} in every state with the issue, nothing elsewhere. Other states move {points(config.STANCE_SPILL)} per top issue a side likes and {points(
		-config.STANCE_SPILL
	)} per one it dislikes. A candidate who runs on the issue is heard ×{config.STANCE_PLATFORM_MULT} there. Stances stay secret until the week resolves.`
end

PlanDraft.points = points

-- "took stance A" for a Choice stance.
function PlanDraft.choiceVerb(choice: string): string
	return `took stance {choice}`
end

-- Last week's resolved event for the week card, or nil. A Choice event names
-- both stances and the support each side's stance asked for, summed over states.
function PlanDraft.lastEventLine(view: View): string?
	local entry = nil
	for _, result in view.eventLog do
		if result.week == view.week - 1 then
			entry = result
		end
	end
	if entry == nil then
		return nil
	end
	local event = Events.byId[entry.id]
	local name = if event then event.name else "an event"
	local choices, moves = entry.choices, entry.moves
	if choices == nil or moves == nil then
		return `Last week's event: {name}.`
	end
	local you = view.you
	local them = if you == 1 then 2 else 1
	local mine, theirs = choices[you], choices[them]
	if mine == nil or theirs == nil then
		return `Last week's event: {name}.`
	end
	local net = { 0, 0 }
	for _, move in moves do
		net[1] += move.points[you] or 0
		net[2] += move.points[them] or 0
	end
	return `Last week's event: {name}. You {PlanDraft.choiceVerb(mine)}, they {PlanDraft.choiceVerb(theirs)}: {#moves} states moved, {points(
		net[1]
	)} / {points(net[2])} points in all.`
end

return table.freeze(PlanDraft)
