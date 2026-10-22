--!strict
-- What the Campaign screen and its parts (TopBar, StateCard, PlanList, Prep,
-- EventCard, Reveal) share: the screen's model (the payload, the plan being
-- built, what is selected) and the text helpers every part writes with.
--
-- Campaign.luau owns the model; parts read it and change it through its fields,
-- then call model.render(). Nothing here touches instances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedFolder = ReplicatedStorage.Shared
local Candidates = require(SharedFolder.Sim.Candidates)
local ConfigModule = require(SharedFolder.Sim.Config)
local Issues = require(SharedFolder.Sim.Issues)
local Plan = require(SharedFolder.Sim.Plan)
local Numbers = require(SharedFolder.UI.Numbers)
local PlanDraft = require(SharedFolder.UI.PlanDraft)
local Session = require(SharedFolder.Net.Session)
local StateData = require(SharedFolder.Sim.StateData)
local StateOrder = require(SharedFolder.UI.StateOrder)
local Swing = require(SharedFolder.UI.Swing)
local SharedTypes = require(SharedFolder.Types)
local ViewModule = require(SharedFolder.Sim.View)

local Types = require(script.Parent.Parent.Types)

type Config = ConfigModule.Config
type View = ViewModule.View
type Issue = SharedTypes.Issue

export type Payload = Session.StatePayload
export type PivotStage = "drop" | "add"
-- What a reveal asks the map to show: net points toward you per state, and flips.
export type RevealSwing = { net: { [string]: number }, flips: { Swing.Flip } }

export type Model = {
	config: Config,
	ctx: Types.Ctx,
	payload: Payload?,
	draft: PlanDraft.Draft,
	draftStep: number?, -- the plan step the draft belongs to
	selected: string?, -- the state on the card
	chosenIssue: Issue?, -- the rally/ad message picked by hand, for `selected`
	moreIssues: boolean, -- the "More" message chips are open
	pivotStage: PivotStage?, -- the pivot chooser replaces the action grid
	pivotDrop: Issue?,
	lockStep: number?, -- step we pressed Lock in for (before the server confirms)
	skipStep: number?, -- step we pressed Skip for
	sortMode: StateOrder.Mode,
	portrait: boolean,
	peekChoice: SharedTypes.Choice?, -- a stance chip being held: previewed, not selected
	stanceMap: boolean, -- the event card is open in a Choice week, so the map previews a stance
	revealSwing: RevealSwing?, -- what a reveal shows moved on the map, else nil
	messages: { Types.Message },
	render: () -> (),
	selectState: (id: string) -> (),
}

local Part = {}

-- ---------------------------------------------------------------- stages

-- Locked in (the server says so, or we just pressed Lock in this step).
function Part.isLocked(model: Model, p: Payload): boolean
	local seat = p.seats[p.you]
	return (seat ~= nil and seat.locked) or model.lockStep == p.step
end

function Part.planning(p: Payload): boolean
	return p.stage == "Input" and p.view.phase == "Plan" and p.reveal == nil
end

function Part.editable(model: Model, p: Payload): boolean
	return Part.planning(p) and not Part.isLocked(model, p)
end

-- Is debate prep due in this plan (the week before a debate)?
function Part.prepWanted(view: View): boolean
	local debate = view.nextDebate
	return view.phase == "Plan" and debate ~= nil and debate.week == view.week + 1
end

-- The problem the draft would have with `action` added.
function Part.trial(model: Model, view: View, action: Plan.Action): string?
	local draft = model.draft
	local test: PlanDraft.Draft =
		{ actions = table.clone(draft.actions), prep = draft.prep, choice = draft.choice }
	table.insert(test.actions, action)
	return PlanDraft.problem(model.config, view, test)
end

-- What `action` adds to the draft's cash cost.
function Part.extraCash(model: Model, view: View, action: Plan.Action): number
	local draft = model.draft
	local base = PlanDraft.cost(model.config, view, draft).cash
	local test: PlanDraft.Draft =
		{ actions = table.clone(draft.actions), prep = draft.prep, choice = draft.choice }
	table.insert(test.actions, action)
	return PlanDraft.cost(model.config, view, test).cash - base
end

-- The message for rallies and ads in state `id`: picked by hand, else the best.
function Part.messageIssue(model: Model, view: View, id: string): Issue
	local chosen: Issue? = model.chosenIssue
	if chosen then
		local picked: Issue = chosen
		return picked
	end
	local best: Issue = PlanDraft.bestIssue(model.config, view, id)
	return best
end

-- Ground-game units planned for state `id`.
function Part.plannedUnits(model: Model, id: string): number
	local units = 0
	for _, action in model.draft.actions do
		if action.kind == "Gotv" and action.state == id then
			units += action.units or 0
		end
	end
	return units
end

-- ---------------------------------------------------------------- text

function Part.opponentOf(view: View): number
	return if view.you == 1 then 2 else 1
end

function Part.candidateName(config: Config, view: View, p: number): string
	local player = view.players[p]
	if player == nil or player.candidate == nil or not Candidates.exists(player.candidate) then
		return `Player {p}`
	end
	return Candidates.profile(config, player.candidate).name
end

-- The first word of a candidate's name ("Dana"), for the phone score line.
function Part.firstName(config: Config, view: View, p: number): string
	local name = Part.candidateName(config, view, p)
	return string.match(name, "^(%S+)") or name
end

function Part.stateName(id: string?): string
	if id == nil then
		return "?"
	end
	local record = StateData.byId[id]
	return if record then record.name else id
end

function Part.issueName(issue: string?): string
	if issue == nil then
		return "?"
	end
	return Issues.displayName[issue :: Issue] or issue
end

function Part.regionName(region: string?): string
	if region == nil then
		return "?"
	end
	return Issues.regionName[region :: SharedTypes.Region] or region
end

-- Money is floored, never rounded up (Numbers.money).
function Part.money(amount: number): string
	return Numbers.money(amount)
end

function Part.plural(n: number, word: string): string
	return `{n} {word}{if n == 1 then "" else "s"}`
end

-- A multiplier as "×1.5".
function Part.mult(value: number): string
	return string.format("×%.1f", value)
end

-- One plan action as a plan-list line, with the player-facing action names
-- (D-030): Rally, Fundraise, Ad, Attack ad, Poll, Region poll, Ground game, Pivot.
function Part.actionText(config: Config, action: Plan.Action, flight: boolean): string
	local kind = action.kind
	local where = Part.stateName(action.state)
	local text = kind :: string
	if kind == "Rally" then
		text = `Rally · {where} · {Part.issueName(action.issue)}`
	elseif kind == "Fundraise" then
		text = `Fundraise · {where}`
	elseif kind == "Media" then
		text = `Ad · {where} · {Part.issueName(action.issue)}`
	elseif kind == "Attack" then
		text = `Attack ad · {where} · {Part.issueName(action.issue)}`
	elseif kind == "Poll" then
		text = `Poll · {where}`
	elseif kind == "RegionPoll" then
		text = `Region poll · {Part.regionName(action.region)}`
	elseif kind == "Gotv" then
		text = `Ground game +{action.units or 1} · {where}`
	elseif kind == "Pivot" then
		text = `Pivot: drop {Part.issueName(action.drop)}, add {Part.issueName(action.add)}`
	end
	if flight then
		text ..= ` ✈ {Part.money(config.FLIGHT_COST)}`
	end
	return text
end

-- The stance the map previews in a Choice week: the one held, else the one
-- selected, else the hedge. Nil when there is nothing to preview.
function Part.previewStance(model: Model, p: Payload): SharedTypes.Choice?
	if not Part.planning(p) or not PlanDraft.isChoiceWeek(p.view) or not model.stanceMap then
		return nil
	end
	local held: SharedTypes.Choice? = model.peekChoice
	if held then
		return held
	end
	local chosen: SharedTypes.Choice? = model.draft.choice
	if chosen then
		return chosen
	end
	return "C"
end

-- This week's event, or nil while any reveal plays: the Resolve reveal carries
-- next week's view, and the Debate reveal comes before the week's plan (B1).
function Part.shownEvent(p: Payload): ViewModule.EventView?
	if p.reveal ~= nil then
		return nil
	end
	return p.view.event
end

return Part
