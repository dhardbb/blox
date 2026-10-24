--!strict
-- The seeded weekly event deck (docs/PLAN.md "Events", DESIGN.md D-027, D-039).
--
-- Twenty-four events as data. Match.new shuffles them with the "events" fork of
-- the match seed and deals one to each week from EVENT_FIRST_WEEK to
-- EVENT_LAST_WEEK, so no event repeats and weeks 1 and 12 have none (the
-- tutorial deals one Choice event into its week, EVENT_CHOICE_ONLY, D-080). Only the
-- current week's event is public (View shows it during that week's Debate and
-- Plan); the rest of the deck stays on the server.
--
-- Four kinds, applied during that week's Resolve:
--   Spotlight  rallies and positive media on one issue x EVENT_SPOTLIGHT_MULT
--   Regional   rallies in one region x EVENT_REGIONAL_MULT
--   Windfall   fundraisers x EVENT_WINDFALL_MULT where the fundraiser trails in
--              the public poll
--   Choice     a dispute over one issue; each player secretly takes one of three
--              stances (plan.choice = "A" | "B" | "C") and every state that has
--              the issue as a top issue reacts to it (Events.stanceEffects)
--
-- Stances (D-039): "A" and "B" are opposed positions, "C" the hedge. A state
-- with the event's issue as a top issue reacts by its OTHER top issue: if the
-- stance likes it, +STANCE_POINTS; if it dislikes it, -STANCE_POINTS; otherwise
-- +STANCE_HEDGE. A state without the issue still hears a side through its own
-- top issues: +STANCE_SPILL per issue the stance likes, -STANCE_SPILL per issue
-- it dislikes. The taker's own home and strongholds (their base) listen hardest:
-- a side counts x STANCE_BASE_MULT there, and the hedge, which moves no other
-- state, costs STANCE_HEDGE_COST in each base state with the issue (D-043), so
-- each player's right answer depends on their own draft. A candidate whose
-- platform carries the issue is listened to harder: every reaction in the
-- issue's states x STANCE_PLATFORM_MULT. Reactions depend only on fixed state
-- data, the public platform and the public draft, so a player can learn them. Both players' stances resolve from one snapshot.
--
-- The cap: an event adds at most EVENT_CAP to one player in one state in one week
-- beyond what the actions would have given without it (support points, or $ for a
-- Windfall). Stance points are clamped to +/- STANCE_CAP per state instead.

local ConfigModule = require("./Config")
local Rng = require("./Rng")
local State = require("./State")
local IssueMap = require("./IssueMap")
local StateData = require("./StateData")
local Types = require("../Types")

type Config = ConfigModule.Config

-- One stance a Choice event offers. `likes` and `dislikes` are the other top
-- issues that decide a state's reaction; the hedge has neither.
export type Stance = {
	id: Types.Choice,
	name: string, -- short label for the button
	text: string, -- one line of flavor, generic and fictional
	likes: { Types.Issue },
	dislikes: { Types.Issue },
	hedge: boolean,
}

export type Definition = {
	id: string,
	kind: Types.EventKind,
	name: string, -- short headline
	text: string, -- one line of flavor, generic and fictional
	issue: Types.Issue?, -- Spotlight and Choice
	region: Types.Region?, -- Regional
	stances: { Stance }?, -- Choice: exactly the three slots in Events.CHOICES order
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

-- The three stance slots every Choice event offers, in display order.
Events.CHOICES = table.freeze({ "A", "B", "C" } :: { Types.Choice })

-- The stance a player who submits nothing takes: the hedge, the last slot.
function Events.defaultChoice(): Types.Choice
	return Events.CHOICES[#Events.CHOICES]
end

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

type Side = { name: string, text: string, likes: { Types.Issue }, dislikes: { Types.Issue } }

-- A Choice event: side A, side B (which likes what A dislikes and vice versa) and
-- the hedge C.
local function choice(
	id: string,
	issue: Types.Issue,
	name: string,
	text: string,
	a: Side,
	b: { name: string, text: string },
	c: { name: string, text: string }
): Definition
	local stances: { Stance } = {
		table.freeze({
			id = "A" :: Types.Choice,
			name = a.name,
			text = a.text,
			likes = table.freeze(table.clone(a.likes)),
			dislikes = table.freeze(table.clone(a.dislikes)),
			hedge = false,
		}),
		table.freeze({
			id = "B" :: Types.Choice,
			name = b.name,
			text = b.text,
			likes = table.freeze(table.clone(a.dislikes)),
			dislikes = table.freeze(table.clone(a.likes)),
			hedge = false,
		}),
		table.freeze({
			id = "C" :: Types.Choice,
			name = c.name,
			text = c.text,
			likes = table.freeze({}),
			dislikes = table.freeze({}),
			hedge = true,
		}),
	}
	return table.freeze({
		id = id,
		kind = "Choice" :: Types.EventKind,
		name = name,
		text = text,
		issue = issue,
		stances = table.freeze(stances),
	})
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
	-- Choice events: one per issue, so the deck favors no platform. The likes and
	-- dislikes split each issue's states into two camps of roughly equal EV.
	choice(
		"plant",
		"Jobs",
		"Plant at a crossroads",
		"A big employer is deciding whether to stay. Everyone asks where you stand.",
		{
			name = "Stand with the plant",
			text = "Cheered where jobs ride on the freight lines and the farm belt.",
			likes = { "Transit", "Farms" },
			dislikes = { "Health", "Safety" },
		},
		{
			name = "Stand with the neighbors",
			text = "Cheered where the plant's neighbors worry about clinics and streets.",
		},
		{ name = "Call for a study", text = "Nobody is thrilled, nobody is angry." }
	),
	choice(
		"walkout",
		"Health",
		"Clinic walkout",
		"Hospital staff and managers are at odds, and both want you on their side.",
		{
			name = "Side with the staff",
			text = "Cheered in working towns, farm country and the river valleys.",
			likes = { "Jobs", "Environment", "Farms" },
			dislikes = { "Transit", "Safety" },
		},
		{ name = "Side with the board", text = "Cheered in the commuter belts and the big-city precincts." },
		{ name = "Offer to mediate", text = "A quiet week for everyone." }
	),
	choice(
		"calendar",
		"Schools",
		"Calendar fight",
		"A school-year shake-up splits teachers and parents down the middle.",
		{
			name = "Side with the teachers",
			text = "Cheered in the college towns, the clinic districts and the rail suburbs.",
			likes = { "Technology", "Health", "Transit" },
			dislikes = { "Farms", "Jobs" },
		},
		{ name = "Side with the parents", text = "Cheered in farm country and the factory towns." },
		{ name = "Leave it to the districts", text = "Nobody loves it, nobody minds." }
	),
	choice(
		"river",
		"Environment",
		"River cleanup",
		"A polluted river makes headlines. Who should pick up the bill?",
		{
			name = "Side with the river towns",
			text = "Cheered in the clinic districts, farm country, mill towns and school districts.",
			likes = { "Health", "Farms", "Jobs", "Schools" },
			dislikes = { "Technology" },
		},
		{
			name = "Side with the tech corridor",
			text = "Cheered along the tech corridor, booed by the river towns.",
		},
		{ name = "Promise a study", text = "A mild shrug everywhere it matters." }
	),
	choice(
		"patrol",
		"Safety",
		"Night patrol plan",
		"Volunteers want to patrol at night; the downtown council says leave it to the city.",
		{
			name = "Side with the volunteers",
			text = "Cheered in ranch country and the tech suburbs, booed downtown.",
			likes = { "Farms", "Technology" },
			dislikes = { "Jobs", "Health", "Transit" },
		},
		{
			name = "Side with the council",
			text = "Cheered in the factory towns, clinic districts and commuter belts.",
		},
		{ name = "Let the city decide", text = "A quiet answer that offends nobody." }
	),
	choice(
		"toll",
		"Transit",
		"Bridge toll",
		"A toll on the old bridge pits commuters against the crews who would rebuild it.",
		{
			name = "Side with the commuters",
			text = "Cheered in the factory towns, farm country and the river valleys.",
			likes = { "Jobs", "Farms", "Environment" },
			dislikes = { "Health", "Safety", "Technology" },
		},
		{
			name = "Side with the builders",
			text = "Cheered in the clinic districts, downtown and the tech suburbs.",
		},
		{ name = "Ask for a review", text = "The bridge waits; nobody is upset." }
	),
	choice(
		"datacenter",
		"Technology",
		"Data center boom",
		"Start-ups want a giant data center; the townships around it are not so sure.",
		{
			name = "Side with the start-ups",
			text = "Cheered along the coast and in the mountain tech towns.",
			likes = { "Environment" },
			dislikes = { "Schools", "Safety", "Transit" },
		},
		{
			name = "Side with the townships",
			text = "Cheered in the school districts, downtown and the rail suburbs.",
		},
		{ name = "Form a task force", text = "A polite answer that moves little." }
	),
	choice(
		"water",
		"Farms",
		"Water rights",
		"A dry summer sets ranchers against growers over who gets the water.",
		{
			name = "Side with the ranchers",
			text = "Cheered in ranch country and along the rail lines.",
			likes = { "Safety", "Transit" },
			dislikes = { "Schools", "Jobs", "Health", "Environment" },
		},
		{
			name = "Side with the growers",
			text = "Cheered in the school districts, mill towns, clinic districts and river valleys.",
		},
		{ name = "Call a summit", text = "Everyone nods, nobody cheers." }
	),
} :: { Definition })

local byId: { [string]: Definition } = {}
for _, event in Events.deck do
	assert(byId[event.id] == nil, `duplicate event id {event.id}`)
	byId[event.id] = event
end
Events.byId = table.freeze(byId)

-- True if `value` names one of the three stance slots.
function Events.isChoice(value: any): boolean
	return type(value) == "string" and table.find(Events.CHOICES, value :: Types.Choice) ~= nil
end

-- The stance with this id in a Choice event, or nil.
function Events.stance(event: Definition, id: Types.Choice): Stance?
	if event.stances == nil then
		return nil
	end
	for _, stance in event.stances :: { Stance } do
		if stance.id == id then
			return stance
		end
	end
	return nil
end

-- Deals the deck for a new match: week -> event id. Empty when events are off.
function Events.draw(config: Config, rng: Rng.Rng): { [number]: string }
	local dealt: { [number]: string } = {}
	if not config.EVENTS_ENABLED then
		return dealt
	end
	local ids: { string } = {}
	for _, event in Events.deck do
		-- The tutorial deals Choice events only (EVENT_CHOICE_ONLY, D-080).
		if not config.EVENT_CHOICE_ONLY or event.kind == "Choice" then
			table.insert(ids, event.id)
		end
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

-- A candidate's base for stances: their home and strongholds (state ids, public
-- once the draft is revealed).
function Events.baseOf(player: { home: string?, strongholds: { string }? }): { string }
	local base = if player.strongholds then table.clone(player.strongholds) else {}
	if player.home and not table.find(base, player.home) then
		table.insert(base, player.home)
	end
	return base
end

-- Support points stance `id` of a Choice event moves for a candidate with
-- `platform` and `base` (Events.baseOf) who takes it, in the state at index i (0
-- where the state does not react). Public arithmetic on the match's issue map
-- (D-047), the platform and the draft, clamped to +/- STANCE_CAP: the client
-- previews it, the server applies it.
function Events.stanceEffect(
	config: Config,
	issueMap: IssueMap.IssueMap,
	event: Definition,
	id: Types.Choice,
	i: number,
	platform: { Types.Issue },
	base: { string }?
): number
	local stance = Events.stance(event, id)
	local issue = event.issue
	if stance == nil or issue == nil then
		return 0
	end
	local issues = issueMap[i]
	local inBase = base ~= nil and table.find(base, StateData.list[i].id) ~= nil
	local points = 0
	if table.find(issues, issue) == nil then
		-- Spillover: a state that does not care about the issue still hears the
		-- stance through the issues it does care about, a little.
		if not stance.hedge then
			for _, topIssue in issues do
				if table.find(stance.likes, topIssue) then
					points += config.STANCE_SPILL
				elseif table.find(stance.dislikes, topIssue) then
					points -= config.STANCE_SPILL
				end
			end
		end
	elseif stance.hedge then
		-- The hedge moves nobody, and your own base hears it as ducking the issue.
		points = if inBase then -config.STANCE_HEDGE_COST else 0
	else
		points = config.STANCE_HEDGE
		for _, topIssue in issues do
			if topIssue ~= issue then
				if table.find(stance.likes, topIssue) then
					points = config.STANCE_POINTS
				elseif table.find(stance.dislikes, topIssue) then
					points = -config.STANCE_POINTS
				end
			end
		end
	end
	if inBase and not stance.hedge then
		points *= config.STANCE_BASE_MULT
	end
	-- A candidate who runs on the issue is heard harder where it is a top issue.
	if table.find(issues, issue) and table.find(platform, issue) then
		points *= config.STANCE_PLATFORM_MULT
	end
	return math.clamp(points, -config.STANCE_CAP, config.STANCE_CAP)
end

-- Every state a stance moves for a candidate with `platform` and `base`: state id
-- -> support points (nonzero entries only).
function Events.stanceEffects(
	config: Config,
	issueMap: IssueMap.IssueMap,
	event: Definition,
	id: Types.Choice,
	platform: { Types.Issue },
	base: { string }?
): { [string]: number }
	local out: { [string]: number } = {}
	for i, record in StateData.list do
		local points = Events.stanceEffect(config, issueMap, event, id, i, platform, base)
		if points ~= 0 then
			out[record.id] = points
		end
	end
	return out
end

return table.freeze(Events)
