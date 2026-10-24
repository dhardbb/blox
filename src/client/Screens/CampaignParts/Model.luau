--!strict
-- What the Campaign and Decision screens and their parts (TopBar, StateCard,
-- PlanList, Focus, EventCard, Reveal) share: the screen's model (the payload,
-- the plan or decision being built, what is selected) and the text helpers every
-- part writes with.
--
-- The screen owns the model; parts read it and change it through its fields,
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
-- `step`: one move of the week's reveal (every touched state badged, D-063).
export type RevealSwing = { net: { [string]: number }, flips: { Swing.Flip }, step: boolean? }

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
	choice: SharedTypes.Choice?, -- Decision screen: the stance selected (nil until one is tapped; the server's default is C)
	focus: Issue?, -- Decision screen: the debate topic selected (nil until one is tapped; the default is no focus)
	peekChoice: SharedTypes.Choice?, -- a stance chip being held: previewed, not selected
	peekFocus: Issue?, -- a focus topic being held: previewed, not selected
	stanceMap: boolean, -- the stance chips are showing, so the map previews a stance
	revealSwing: RevealSwing?, -- what a reveal shows moved on the map, else nil
	revealEV: { number }?, -- the projected votes the header shows during a reveal (the running tally, D-063), else nil
	caption: string?, -- the reveal's latest line, shown as the header's now line
	captionPolls: boolean?, -- the caption is the reveal's "New polls are in" step (its own header look, D-063)
	moreActions: boolean, -- the state card shows every action, not just the main ones
	details: boolean, -- the state card's Details are open
	messages: { Types.Message },
	render: () -> (),
	selectState: (id: string) -> (),
	-- While an action button is held: what it would do, shown on the map ("+4.1"),
	-- nil to hide. Campaign sets it; nil on screens without a plan.
	ghost: ((id: string, text: string?) -> ())?,
}

local Part = {}

Part.OPPONENT_LOCKED = "locked in ✓" -- the opponent's state once they lock in
Part.DOTS_PER_SECOND = 2 -- the opponent's "thinking…" dots step this often

-- The action bar's opponent line: "Rex: thinking.." (the dots step with `now`,
-- padded to a fixed width so the name stays put; all three when `still`),
-- "Rex: locked in ✓", "Rex: disconnected".
function Part.opponentLine(name: string, state: string, now: number, still: boolean): string
	if state == "thinking" then
		local n = if still then 3 else math.floor(now * Part.DOTS_PER_SECOND) % 3 + 1
		return `{name}: thinking{string.rep(".", n)}{string.rep(" ", 3 - n)}`
	end
	return `{name}: {state}`
end

-- ---------------------------------------------------------------- stages

-- Locked in (the server says so, or we just pressed Lock in this step).
function Part.isLocked(model: Model, p: Payload): boolean
	local seat = p.seats[p.you]
	return (seat ~= nil and seat.locked) or model.lockStep == p.step
end

function Part.planning(p: Payload): boolean
	return p.stage == "Input" and p.view.phase == "Plan" and p.reveal == nil
end

-- The Decision step before the plan (D-044): "Focus" or "Stance", else nil.
function Part.deciding(p: Payload): ("Focus" | "Stance")?
	if p.stage == "Input" and p.view.phase == "Decision" and p.reveal == nil then
		return p.view.decision
	end
	return nil
end

function Part.editable(model: Model, p: Payload): boolean
	return (Part.planning(p) or Part.deciding(p) ~= nil) and not Part.isLocked(model, p)
end

-- The problem the draft would have with `action` added.
function Part.trial(model: Model, view: View, action: Plan.Action): string?
	local draft = model.draft
	local test: PlanDraft.Draft = { actions = table.clone(draft.actions) }
	table.insert(test.actions, action)
	return PlanDraft.problem(model.config, view, test)
end

-- What `action` adds to the draft's cash cost.
function Part.extraCash(model: Model, view: View, action: Plan.Action): number
	local draft = model.draft
	local base = PlanDraft.cost(model.config, view, draft).cash
	local test: PlanDraft.Draft = { actions = table.clone(draft.actions) }
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

-- The stance the map previews on the stance screen: the one held, else the one
-- selected, else the hedge. Nil when there is nothing to preview.
function Part.previewStance(model: Model, p: Payload): SharedTypes.Choice?
	if Part.deciding(p) ~= "Stance" or not PlanDraft.isChoiceWeek(p.view) or not model.stanceMap then
		return nil
	end
	local held: SharedTypes.Choice? = model.peekChoice
	if held then
		return held
	end
	local chosen: SharedTypes.Choice? = model.choice
	if chosen then
		return chosen
	end
	return "C"
end

-- The topic the map previews on the focus screen: the one held, else the one
-- selected. Nil when there is nothing to preview.
function Part.previewFocus(model: Model, p: Payload): Issue?
	if Part.deciding(p) ~= "Focus" then
		return nil
	end
	return model.peekFocus or model.focus
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
