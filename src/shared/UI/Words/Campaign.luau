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
--   Words.SCORE_CAPTION · Words.mapTip(mine, theirs) -> string   what the header's score is (M4)
--   Words.effect(config, view, draft, id, name, issue?, opponent) -> string
--   Words.cost(extra, flight, poll?, noAction?) -> string?   "$3.0", "Flight $2.0", "free", "$3.0 · no action"
--   Words.NO_ACTION[name] -> true         the buttons that cost money but no action (D-086)
--   Words.reason(code) -> string              a greyed-out button's reason
--   Words.swapTitle(config) -> string         the issue-swap chooser's title (the plan's Pivot)
--   Words.planLine(actions) -> string         "Rally OH · Ad PA · Poll TX"
--   Words.stanceEffect(preview) -> string     "+4 states · −2 states"
--   Words.stanceParts(preview) -> (string?, string?)   "+4 states", "−2 states"
--   Words.key(id) -> { string }               the map key's lines for a lens
--   Words.KEY_STATES · Words.keyChip(id, ev) -> "PA 19" · Words.keyLine(keys) -> "Key states: PA 19 · OH 17" (D-088)
--   Words.bands() -> { { name, text } }       the map key's four color steps
--   Words.gain(effect) -> string?             "+4.1" from "+4.1 support" (the map's ghost tag)
--   Words.percent(text) -> string             "×1.2" said as "20% more" (an event's effect)
--   Words.eventTitle(event, next?) -> string  "Windfall · Small-dollar surge" ("Next week: <name>")
--   Words.eventLine(config, event, stance?) -> string   the event strip's one line (D-065)
--   Words.closing(config, week) -> Closing?       the closing weeks on the event strip (S3)

local Colors = require("../Colors")
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

local MINUS = "−" -- the minus sign (Kit.glyph.minus), for a cost written as a loss

-- A Config number as written in a sentence: "1", "1.5".
local function whole(value: number): string
	return if value == math.floor(value) then string.format("%d", value) else Numbers.points(value)
end

-- The action buttons on the state card, in order, and what each one's Plan kind is.
Words.ACTIONS = table.freeze({
	{ name = "Rally", label = "Rally", kind = "Rally" },
	{ name = "Fundraise", label = "Fundraise", kind = "Fundraise" },
	{ name = "Ad", label = "Ad", kind = "Media" },
	{ name = "Attack", label = "Attack ad", kind = "Attack" },
	{ name = "Poll", label = "Poll", kind = "Poll" },
	{ name = "Gotv", label = "Ground game", kind = "Gotv" },
	{ name = "RegionPoll", label = "Region poll", kind = "RegionPoll" },
	-- The plan's Pivot is "Swap issue" on screen (the debate has its own Pivot move).
	{ name = "PivotButton", label = "Swap issue", kind = "Pivot" },
} :: { { name: string, label: string, kind: string } })

-- The buttons whose cost line adds "no action" (D-086): they cost money and no
-- action point (Plan.cost; tests/ui/CampaignWords.spec checks it).
Words.NO_ACTION = table.freeze({ Ad = true, Attack = true, Gotv = true } :: { [string]: boolean })

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

-- What the header's score is (M4): each side's projected votes on today's
-- public polls. The caption under the race bar (wide screens only) and the
-- first plan's coach tip, "310 vs 189: votes if today's polls held. Tap any
-- state." (11 words: a tip's limit is 12, so the tutorial's "Week 1 of 4."
-- prefix does not fit and is left out).
Words.SCORE_CAPTION = "if the polls were right"
function Words.mapTip(mine: number, theirs: number): string
	return `{math.floor(mine + 0.5)} vs {math.floor(theirs + 0.5)}: votes if today's polls held. Tap any state.`
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
-- "+$2.4", "Buster -2.4", "+1.5 on election day". From Explain's numbers, so it
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
		return `{MINUS}{whole(config.PIVOT_PENALTY)} support everywhere`
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

-- The issue-swap chooser's title (the plan's Pivot, said "Swap issue" on screen),
-- from Config: "Swap an issue (once per match, −1 support everywhere)" and, on a
-- second line, what it takes and the first step.
function Words.swapTitle(config: Config): string
	local ap = config.PIVOT_AP
	return `Swap an issue (once per match, {MINUS}{whole(config.PIVOT_PENALTY)} support everywhere)\nUses {ap} {if ap
			== 1
		then "action"
		else "actions"}. Drop which issue?`
end

-- What an action adds to the bill: "$3.0", "Flight $2.0" (a flight to get there),
-- or "free" for a free poll; nil when it costs nothing extra. `noAction` (an ad
-- or ground game, Words.NO_ACTION) adds that it takes no action: "$3.0 · no action".
function Words.cost(extra: number, flight: boolean, poll: boolean?, noAction: boolean?): string?
	local text: string? = nil
	if flight then
		text = `Flight {Numbers.cost(extra)}`
	elseif extra > 1e-9 then
		text = Numbers.cost(extra)
	elseif poll then
		text = "free"
	end
	if noAction then
		return if text then `{text} · no action` else "no action"
	end
	return text
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
		return "Swap issue"
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

-- The same in two parts, for a line that colors them apart: the gain ("+4
-- states", or "No change" when there is neither) and the loss ("−2 states") or nil.
function Words.stanceParts(preview: { gains: { string }, losses: { string } }): (string?, string?)
	local function count(n: number): string
		return `{n} {if n == 1 then "state" else "states"}`
	end
	local gain = if #preview.gains > 0 then `+{count(#preview.gains)}` else nil
	local loss = if #preview.losses > 0 then `−{count(#preview.losses)}` else nil
	if gain == nil and loss == nil then
		return "No change", nil
	end
	return gain, loss
end

-- An event's effect without the multiplier sign: "raise ×1.2 this week" ->
-- "raise 20% more this week"; "×0.8" -> "20% less".
function Words.percent(text: string): string
	return (
		string.gsub(text, "×(%d+%.?%d*)", function(m: string): string
			local value = tonumber(m) or 1
			local pct = math.floor(math.abs(value - 1) * 100 + 0.5)
			return if value >= 1 then `{pct}% more` else `{pct}% less`
		end)
	)
end

-- ---------------------------------------------------------------- the event strip (D-065)

-- A multiplier as a signed percent: 1.3 -> "+30%", 0.8 -> "−20%".
local function plusPercent(mult: number): string
	local pct = math.floor(math.abs(mult - 1) * 100 + 0.5)
	return if mult >= 1 then `+{pct}%` else `−{pct}%`
end

-- The event strip's title: "Windfall · Small-dollar surge"; with `upcoming`,
-- next week's event for a candidate who previews the deck ("Next week:
-- Infrastructure week": the line under it says what it does).
function Words.eventTitle(event: ViewModule.EventView, upcoming: boolean?): string
	return if upcoming then `Next week: {event.name}` else `{event.kind} · {event.name}`
end

-- The event strip's one line: what the event does, short enough for one line
-- on a phone ("Fundraisers where you trail +20%"). A Choice week says the
-- stance taken on the Decision screen ("Stance A: Side with the staff"), or
-- the question before one is taken. The full sentence is behind a tap.
function Words.eventLine(config: Config, event: ViewModule.EventView, stance: Types.Choice?): string
	if event.kind == "Spotlight" then
		local issue = Issues.displayName[event.issue :: Types.Issue] or "?"
		return `{issue} rallies and ads {plusPercent(config.EVENT_SPOTLIGHT_MULT)}`
	elseif event.kind == "Regional" then
		local region = Issues.regionName[event.region :: Types.Region] or "?"
		return `Rallies in the {region} {plusPercent(config.EVENT_REGIONAL_MULT)}`
	elseif event.kind == "Windfall" then
		return `Fundraisers where you trail {plusPercent(config.EVENT_WINDFALL_MULT)}`
	end
	if stance ~= nil then
		local name = ""
		local stances: { ViewModule.StanceView } = event.stances or {}
		for _, entry in stances do
			if entry.id == stance then
				name = `: {entry.name}`
			end
		end
		return `Stance {stance}{name}`
	end
	local issue = Issues.displayName[event.issue :: Types.Issue] or "?"
	return `Take a stance on {issue}`
end

-- The closing weeks (Resolve.closingMult: rallies, ads and attack ads), for the
-- event strip (S3). Nil outside CLOSING_FROM_WEEK - 1 .. the end, or with no bonus.
-- `line`: the strip's third line under a week's event, short enough for a
-- phone ("Closing weeks: rallies and ads +15%"; the week before, "From next
-- week: rallies, ads +15%"). `title` and `alone`: the strip's two lines in a
-- week with no event ("Closing weeks" / "Rallies and ads +15%"). `detail`: the
-- same in a sentence, for the strip's details sheet.
export type Closing = { line: string, title: string, alone: string, detail: string }

function Words.closing(config: Config, week: number): Closing?
	local first = config.CLOSING_FROM_WEEK
	if config.CLOSING_MULT == 1 or week < first - 1 then
		return nil
	end
	local plus = plusPercent(config.CLOSING_MULT)
	local more = math.floor((config.CLOSING_MULT - 1) * 100 + 0.5)
	local what = `every rally and ad (attack ads too) counts {more}% more, for both of you`
	if week >= first then
		return {
			line = `Closing weeks: rallies and ads {plus}`,
			title = "Closing weeks",
			alone = `Rallies and ads {plus}`,
			detail = `Closing weeks: until election night, {what}.`,
		}
	end
	return {
		line = `From next week: rallies, ads {plus}`,
		title = "Closing weeks next week",
		alone = `Rallies and ads {plus} from week {first}`,
		detail = `Closing weeks start next week: from week {first}, {what}.`,
	}
end

-- ---------------------------------------------------------------- the map key

-- How to read the map in lens `id` ("EV", "Issues", "Polls", "Money").
function Words.key(id: string): { string }
	local lines = {
		"Color: who leads the public poll there, and by how much:",
		"A ring: a home state or a stronghold, in its owner's color.",
	}
	if id == "Issues" then
		table.insert(lines, "The mark is the state's top issue, below. Filled: it is one of yours.")
	elseif id == "Polls" then
		table.insert(lines, "The number is the leader's lead in points; ~ means no poll yet.")
		table.insert(
			lines,
			"▲ momentum (▲▲ strong) in its color; ● your ground game, ○ theirs polled."
		)
	elseif id == "Money" then
		table.insert(lines, "The number is what one fundraiser raises there; gold: the 8 richest.")
		table.insert(lines, "Faded: your plan already empties that state's money.")
	else
		table.insert(lines, "The number is how many votes the state is worth.")
		table.insert(lines, "★ and a white outline: a battleground, where every action counts more.")
	end
	table.insert(lines, Words.KEY_MAP)
	table.insert(lines, "Faint numbers: what your plan moves there, if nothing else changes.")
	table.insert(lines, "Faces: where each candidate is (yours is bigger); tap the state for the name.")
	table.insert(lines, "Close races: shows only the states within 8 points; the rest fade.")
	table.insert(lines, "Tap a state to see it and act there.")
	return lines
end

-- ---------------------------------------------------------------- key states (D-088)

Words.KEY_STATES = "Key states" -- the side column's line and the map legend's word
Words.KEY_LEGEND = "key state" -- the map's legend row
Words.KEY_MAP = "Glow and dashed outline: a key state, where 270 is decided this week." -- the map key

-- One key state's chip: its code and its votes, as on the map's plates.
function Words.keyChip(id: string, ev: number): string
	return `{id} {ev}`
end

-- "Key states: PA 19 · OH 17 · WI 10" (nil with none).
function Words.keyLine(keys: { { id: string, ev: number } }): string?
	if #keys == 0 then
		return nil
	end
	local parts: { string } = {}
	for _, key in keys do
		table.insert(parts, Words.keyChip(key.id, key.ev))
	end
	return `{Words.KEY_STATES}: {table.concat(parts, " · ")}`
end

-- The number an action button's effect line leads with, signed ("+4.1",
-- "+$5.2", "-2.4"), for the map's ghost tag; nil when it has none ("See true support").
function Words.gain(effect: string): string?
	local line = string.match(effect, "^[^\n]*") or ""
	return string.match(line, "[%+%-]%$?%d+%.?%d*")
end

local BAND_NAMES: { [string]: string } = {
	tossup = "Toss-up",
	lean = "Leans",
	likely = "Likely",
	safe = "Safe",
}

-- The map's four color steps (Colors.BANDS, display only), weakest first:
-- "Toss-up: closer than 3 points", ..., "Safe: ahead by 15 points or more".
function Words.bands(): { { name: string, text: string } }
	local out = {}
	local from = 0
	for _, band in Colors.BANDS do
		local label = BAND_NAMES[band.name] or band.name
		local text
		if from == 0 then
			text = `{label}: closer than {band.below} points`
		elseif band.below == math.huge then
			text = `{label}: ahead by {from} points or more`
		else
			text = `{label}: ahead by {from} to {band.below} points`
		end
		table.insert(out, { name = band.name, text = text })
		from = band.below
	end
	return out
end

return table.freeze(Words)
