--!strict
-- Short copy for the Campaign and Decision screens and the map (docs/UI-STYLE.md
-- §4.4-4.6, work package B): the "what to do now" line, the action buttons'
-- one-line effects, the plan in one line, the stance and topic summaries, and
-- the map key. Plain words, a unit or a sign on every number, no multipliers;
-- the long explanations stay in Shared/UI/Explain and Swing, behind a tap.
-- Pure: reads only Config, the player's own View and the plan being drafted.
--
--   Words.planNow(input) -> string            the plan screen's now line
--   Words.budget(actionsLeft, cash) -> string "2 actions left · $4.0"
--   Words.effect(config, view, draft, id, name, issue?, opponent) -> string
--   Words.cost(extra, flight, poll?) -> string?   "$3.0", "fly $2.0", "free"
--   Words.reason(code) -> string              a greyed-out button's reason
--   Words.planLine(actions) -> string         "Rally OH · Ad PA · Poll TX"
--   Words.stanceEffect(preview) -> string     "+4 states · −2 states"
--   Words.focusHead(config, view, info) -> string   "Schools · 14 states"
--   Words.focusOdds(info) -> string           "You win 81%"
--   Words.key(id) -> { string }               the map key's lines for a lens

local ConfigModule = require("../../Sim/Config")
local Explain = require("../Explain")
local Issues = require("../../Sim/Issues")
local Numbers = require("../Numbers")
local Plan = require("../../Sim/Plan")
local PlanDraft = require("../PlanDraft")
local StateData = require("../../Sim/StateData")
local Types = require("../../Types")
local ViewModule = require("../../Sim/View")

type Config = ConfigModule.Config
type View = ViewModule.View

local Words = {}

-- The action buttons on the state card, in order, and what each one's Plan kind is.
Words.ACTIONS = table.freeze({
	{ name = "Rally", label = "Rally", kind = "Rally" },
	{ name = "Fundraise", label = "Fundraise", kind = "Fundraise" },
	{ name = "Ad", label = "Ad", kind = "Media" },
	{ name = "Attack", label = "Attack ad", kind = "Attack" },
	{ name = "Poll", label = "Poll", kind = "Poll" },
	{ name = "Gotv", label = "Ground game", kind = "Gotv" },
	{ name = "RegionPoll", label = "Region poll", kind = "RegionPoll" },
	{ name = "PivotButton", label = "Pivot", kind = "Pivot" },
} :: { { name: string, label: string, kind: string } })

-- Why a button is greyed out, in at most three words (Plan.Reason codes).
local REASONS: { [string]: string } = {
	NotEnoughAP = "No actions left",
	NotEnoughMoney = "Not enough money",
	GotvCap = "Full here",
	DuplicatePoll = "Already polled",
	PivotUsed = "Already used",
	TooManyActions = "Plan is full",
	BadPivot = "Not now",
}

function Words.reason(code: string?): string
	return REASONS[code or ""] or "Not now"
end

-- ---------------------------------------------------------------- the now line

export type NowInput = {
	locked: boolean, -- this player locked in
	opponent: string, -- the opponent's first name
	problem: boolean, -- the plan cannot lock in as it stands
	actionsLeft: number,
	planned: number, -- actions in the plan
	selected: string?, -- the selected state's name
}

-- What to do next on the plan screen, at most eight words.
function Words.planNow(input: NowInput): string
	if input.locked then
		return `Waiting for {input.opponent}…`
	elseif input.problem then
		return "Change the plan, then Lock in"
	elseif input.actionsLeft <= 0 then
		return "All set? Press Lock in"
	elseif input.selected then
		return `Pick an action in {input.selected}`
	elseif input.planned > 0 then
		return "Tap another state, or Lock in"
	end
	return "Tap a state on the map"
end

-- "2 actions left · $4.0" (money floored, never rounded up).
function Words.budget(actionsLeft: number, cash: number): string
	local n = math.max(0, actionsLeft)
	return `{n} {if n == 1 then "action" else "actions"} left · {Numbers.money(cash)}`
end

-- ---------------------------------------------------------------- action effects

local function kindOf(name: string): string
	for _, entry in Words.ACTIONS do
		if entry.name == name then
			return entry.kind
		end
	end
	return name
end

local function regionSize(id: string): number
	local region = PlanDraft.regionOf(id)
	local n = 0
	for _, record in StateData.list do
		if record.region == region then
			n += 1
		end
	end
	return n
end

-- What one action button does in state `id`, in a few words: "+3.9 support",
-- "+$2.4", "Rex -2.4", "+1.5 on election day". From Explain's numbers, so it
-- matches the Details lines exactly.
function Words.effect(
	config: Config,
	view: View,
	draft: PlanDraft.Draft,
	id: string,
	name: string,
	issue: Types.Issue?,
	opponent: string
): string
	local kind = kindOf(name)
	if kind == "Poll" then
		return "See true support"
	elseif kind == "RegionPoll" then
		return `Poll {regionSize(id)} states`
	elseif kind == "Gotv" then
		return `+{Numbers.points(config.GOTV_PER_UNIT)} on election day`
	elseif kind == "Pivot" then
		return "Swap an issue"
	end
	local preview = Explain.action(config, view, draft, id, kind, issue)
	if kind == "Fundraise" then
		local money = preview.money or 0
		return if money < 0.05 then "Pool is empty" else `+{Numbers.money(money)}`
	elseif kind == "Attack" then
		return `{opponent} {Numbers.signed(preview.them or 0)}`
	end
	return `{Numbers.signed(preview.you or 0)} support`
end

-- What an action adds to the bill: "$3.0", "fly $2.0" (a flight to get there),
-- or "free" for a free poll; nil when it costs nothing extra.
function Words.cost(extra: number, flight: boolean, poll: boolean?): string?
	if flight then
		return `fly {Numbers.cost(extra)}`
	elseif extra > 1e-9 then
		return Numbers.cost(extra)
	elseif poll then
		return "free"
	end
	return nil
end

-- ---------------------------------------------------------------- the plan

local SHORT: { [string]: string } = {
	Rally = "Rally",
	Fundraise = "Fundraise",
	Media = "Ad",
	Attack = "Attack ad",
	Poll = "Poll",
	Gotv = "Ground game",
}

-- One action in two or three words: "Rally OH", "Poll Midwest", "Ground game OH ×2".
function Words.actionShort(action: Plan.Action): string
	local kind = action.kind
	if kind == "RegionPoll" then
		local region = action.region
		return `Poll {if region then (Issues.regionName :: any)[region] or region else "?"}`
	elseif kind == "Pivot" then
		return "Pivot"
	end
	local text = `{SHORT[kind] or kind} {action.state or "?"}`
	if kind == "Gotv" and (action.units or 1) > 1 then
		text ..= ` ×{action.units}`
	end
	return text
end

-- The whole plan on one line: "Rally OH · Ad PA · Poll TX".
function Words.planLine(actions: { Plan.Action }): string
	local parts: { string } = {}
	for _, action in actions do
		table.insert(parts, Words.actionShort(action))
	end
	return table.concat(parts, " · ")
end

-- ---------------------------------------------------------------- decisions

-- A stance in a few words: how many states it helps and hurts you in.
function Words.stanceEffect(preview: { gains: { string }, losses: { string } }): string
	local parts: { string } = {}
	if #preview.gains > 0 then
		table.insert(parts, `+{#preview.gains} {if #preview.gains == 1 then "state" else "states"}`)
	end
	if #preview.losses > 0 then
		table.insert(parts, `−{#preview.losses} {if #preview.losses == 1 then "state" else "states"}`)
	end
	return if #parts == 0 then "No change" else table.concat(parts, " · ")
end

-- A debate topic's card title: "Schools · 14 states".
function Words.focusHead(
	_config: Config,
	_view: View,
	info: { topic: Types.Issue, states: { string } }
): string
	local name = Issues.displayName[info.topic] or info.topic
	return `{name} · {#info.states} {if #info.states == 1 then "state" else "states"}`
end

-- Your chance to win a topic if you focus on it: "You win 81%".
function Words.focusOdds(info: { win: number }): string
	return `You win {math.floor(info.win * 100 + 0.5)}%`
end

-- ---------------------------------------------------------------- the map key

-- How to read the map in lens `id` ("EV", "Issues", "Polls", "Money").
function Words.key(id: string): { string }
	local lines = {
		"Color: who leads the public poll there. Grey is a toss-up.",
		"A ring: a home state or a stronghold, in its owner's color.",
	}
	if id == "Issues" then
		table.insert(lines, "The code is the state's top issue. Filled: it is one of yours.")
	elseif id == "Polls" then
		table.insert(lines, "The number is the poll leader's lead, in points.")
		table.insert(lines, "~ means no poll yet: the state's lean.")
	elseif id == "Money" then
		table.insert(lines, "What one more fundraiser there would raise this week.")
		table.insert(lines, "Faded: your plan already empties that state's money.")
	else
		table.insert(lines, "The number is how many votes the state is worth.")
		table.insert(lines, "Orange number: a battleground, where every action counts more.")
	end
	table.insert(lines, "Tap a state to see it and act there.")
	return lines
end

return table.freeze(Words)
