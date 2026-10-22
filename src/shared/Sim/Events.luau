--!strict
-- The seeded weekly event deck (docs/PLAN.md "Events", DESIGN.md D-027).
--
-- Twenty events as data. Match.new shuffles them with the "events" fork of the
-- match seed and deals one to each week from EVENT_FIRST_WEEK to EVENT_LAST_WEEK,
-- so no event repeats and weeks 1 and 12 have none. Only the current week's event
-- is public (View shows it during that week's Debate and Plan); the rest of the
-- deck stays on the server.
--
-- Four kinds, applied during that week's Resolve:
--   Spotlight  rallies and positive media on one issue x EVENT_SPOTLIGHT_MULT
--   Regional   rallies in one region x EVENT_REGIONAL_MULT
--   Windfall   fundraisers x EVENT_WINDFALL_MULT where the fundraiser trails in
--              the public poll
--   Choice     each player secretly answers Attack / Defend / Ignore (plan.choice)
--              and a symmetric payoff matrix in national points resolves it
--
-- The cap: an event adds at most EVENT_CAP to one player in one state in one week
-- beyond what the actions would have given without it (support points, or $ for a
-- Windfall). Choice payoffs are national points clamped to +/- EVENT_CAP.

local ConfigModule = require("./Config")
local Rng = require("./Rng")
local State = require("./State")
local StateData = require("./StateData")
local Types = require("../Types")

type Config = ConfigModule.Config

export type Definition = {
	id: string,
	kind: Types.EventKind,
	name: string, -- short headline
	text: string, -- one line of flavor, generic and fictional
	issue: Types.Issue?, -- Spotlight
	region: Types.Region?, -- Regional
}

-- The parts of an event the effect rules read (a Definition or a View.EventView).
export type Effect = {
	kind: Types.EventKind,
	issue: Types.Issue?,
	region: Types.Region?,
}

-- Extra granted so far this week, [state index][player index].
export type Ledger = { [number]: { [number]: number } }

local Events = {}

Events.CHOICES = table.freeze({ "Attack", "Defend", "Ignore" } :: { Types.Choice })

local function spotlight(id: string, issue: Types.Issue, name: string, text: string): Definition
	return table.freeze({
		id = id,
		kind = "Spotlight" :: Types.EventKind,
		name = name,
		text = text,
		issue = issue,
	})
end

local function regional(id: string, region: Types.Region, name: string, text: string): Definition
	return table.freeze({
		id = id,
		kind = "Regional" :: Types.EventKind,
		name = name,
		text = text,
		region = region,
	})
end

local function other(id: string, kind: Types.EventKind, name: string, text: string): Definition
	return table.freeze({ id = id, kind = kind, name = name, text = text })
end

-- The deck. Ids are stable (saved in replays); order here does not matter.
Events.deck = table.freeze({
	spotlight(
		"factory",
		"Jobs",
		"Factory reopening",
		"A shuttered plant reopens and every channel covers hiring."
	),
	spotlight("clinic", "Health", "Flu season", "Clinics are crowded and health care leads the news."),
	spotlight("schools", "Schools", "Back to school", "Classrooms reopen and parents want answers."),
	spotlight(
		"storm",
		"Environment",
		"Storm season",
		"A string of storms puts the weather on every front page."
	),
	spotlight("safety", "Safety", "Safety summit", "City leaders gather to talk about safer streets."),
	spotlight(
		"bridges",
		"Transit",
		"Infrastructure week",
		"Bridges, buses and potholes are all anyone talks about."
	),
	spotlight("expo", "Technology", "Tech expo", "The big gadget fair draws cameras from coast to coast."),
	spotlight("harvest", "Farms", "Harvest festival", "Fairs and farm stands fill the evening news."),
	regional("lakes", "GreatLakes", "Lakeshore fair", "Crowds pack the lakefront fairs of the Great Lakes."),
	regional("coast", "Pacific", "Coastal festival", "Music festivals line the Pacific coast all week."),
	regional(
		"regatta",
		"SouthAtlantic",
		"Riverfront regatta",
		"Boat races draw big crowds across the South Atlantic."
	),
	regional(
		"rodeo",
		"SouthCentral",
		"Rodeo season",
		"Rodeo grandstands are full across the South Central states."
	),
	regional("trails", "Mountain", "Trail days", "Mountain towns host their summer trail festivals."),
	other(
		"donors",
		"Windfall",
		"Donor retreat",
		"Big donors want to back the underdog where the race is close."
	),
	other("smalldollar", "Windfall", "Small-dollar surge", "Online giving spikes for whoever is behind."),
	other(
		"matching",
		"Windfall",
		"Matching-gift week",
		"A civic fund matches gifts in states where you trail."
	),
	other("memo", "Choice", "Leaked memo", "An old campaign memo surfaces. Attack, defend, or ignore it?"),
	other("clip", "Choice", "Viral clip", "A blooper clip is everywhere. Attack, defend, or ignore it?"),
	other("rumor", "Choice", "Rumor mill", "A rumor is spreading online. Attack, defend, or ignore it?"),
	other(
		"endorse",
		"Choice",
		"Endorsement fight",
		"A popular mayor is still undecided. Attack, defend, or ignore?"
	),
} :: { Definition })

local byId: { [string]: Definition } = {}
for _, event in Events.deck do
	assert(byId[event.id] == nil, `duplicate event id {event.id}`)
	byId[event.id] = event
end
Events.byId = table.freeze(byId)

function Events.isChoice(value: any): boolean
	return type(value) == "string" and table.find(Events.CHOICES, value :: Types.Choice) ~= nil
end

-- Deals the deck for a new match: week -> event id. Empty when events are off.
function Events.draw(config: Config, rng: Rng.Rng): { [number]: string }
	local dealt: { [number]: string } = {}
	if not config.EVENTS_ENABLED then
		return dealt
	end
	local ids: { string } = {}
	for k, event in Events.deck do
		ids[k] = event.id
	end
	Rng.shuffle(Rng.fork(rng, "events"), ids)
	local k = 0
	for week = math.max(1, config.EVENT_FIRST_WEEK), math.min(config.WEEKS, config.EVENT_LAST_WEEK) do
		k += 1
		if ids[k] == nil then
			break
		end
		dealt[week] = ids[k]
	end
	return dealt
end

-- The event of a given week (default: the match's current week), or nil.
function Events.at(match: State.MatchState, week: number?): Definition?
	local id = match.eventDeck[week or match.week]
	if id == nil then
		return nil
	end
	return byId[id]
end

-- True if the current week's event asks every player for a Choice.
function Events.isChoiceWeek(match: State.MatchState): boolean
	local event = Events.at(match)
	return event ~= nil and event.kind == "Choice"
end

-- Multiplier the event puts on a rally or positive media buy on `issue` in the
-- state at index i (1 if it does not apply). Attacks are never boosted.
function Events.supportMult(
	config: Config,
	event: Effect?,
	kind: "Rally" | "Media",
	issue: Types.Issue,
	i: number
): number
	if event == nil then
		return 1
	end
	if event.kind == "Spotlight" and event.issue == issue then
		return config.EVENT_SPOTLIGHT_MULT
	elseif event.kind == "Regional" and kind == "Rally" and StateData.list[i].region == event.region then
		return config.EVENT_REGIONAL_MULT
	end
	return 1
end

-- Does player p trail someone in this public poll? (A tie is not trailing.)
function Events.trails(poll: State.Poll?, p: number): boolean
	if poll == nil then
		return false
	end
	local mine = poll.support[p]
	for q, share in poll.support do
		if q ~= p and share > mine then
			return true
		end
	end
	return false
end

-- Multiplier the event puts on player p's fundraiser in a state with this public poll.
function Events.fundMult(config: Config, event: Effect?, poll: State.Poll?, p: number): number
	if event ~= nil and event.kind == "Windfall" and Events.trails(poll, p) then
		return config.EVENT_WINDFALL_MULT
	end
	return 1
end

-- Grants up to `extra` of event bonus to player p in state i, within what is left
-- of EVENT_CAP this week, and records it. Returns the amount granted.
function Events.grant(config: Config, ledger: Ledger, i: number, p: number, extra: number): number
	if extra <= 0 then
		return 0
	end
	local row = ledger[i]
	if row == nil then
		row = {}
		ledger[i] = row
	end
	local used = row[p] or 0
	local granted = math.min(extra, math.max(0, config.EVENT_CAP - used))
	row[p] = used + granted
	return granted
end

-- National points for answering `mine` against an opponent who answered `theirs`.
function Events.payoff(config: Config, mine: Types.Choice, theirs: Types.Choice): number
	if mine == "Attack" then
		return if theirs == "Attack"
			then config.CHOICE_ATTACK_ATTACK
			elseif theirs == "Defend" then config.CHOICE_ATTACK_DEFEND
			else config.CHOICE_ATTACK_IGNORE
	elseif mine == "Defend" then
		return if theirs == "Attack"
			then config.CHOICE_DEFEND_ATTACK
			elseif theirs == "Defend" then config.CHOICE_DEFEND_DEFEND
			else config.CHOICE_DEFEND_IGNORE
	end
	return if theirs == "Attack"
		then config.CHOICE_IGNORE_ATTACK
		elseif theirs == "Defend" then config.CHOICE_IGNORE_DEFEND
		else config.CHOICE_IGNORE_IGNORE
end

-- Every player's national points from everyone's choices: the sum of the matrix
-- against each opponent (exactly the matrix in 1v1), clamped to +/- EVENT_CAP.
-- Depends only on the choices, never on seat order.
function Events.choicePayoffs(config: Config, choices: { Types.Choice }): { number }
	local out = table.create(#choices, 0)
	for p = 1, #choices do
		local mine: Types.Choice = choices[p]
		local total = 0
		for q = 1, #choices do
			local theirs: Types.Choice = choices[q]
			if q ~= p then
				total += Events.payoff(config, mine, theirs)
			end
		end
		out[p] = math.clamp(total, -config.EVENT_CAP, config.EVENT_CAP)
	end
	return out
end

return table.freeze(Events)
