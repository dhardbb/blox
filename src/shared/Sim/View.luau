--!strict
-- Builds what ONE player may see. This is the only exit for simulation state: the
-- server replicates View.build output and nothing else.
--
-- Never included: true support or undecided, poll error terms, pool levels, the
-- seed or RNG state, opponents' exact cash, GOTV units (an opponent's only as your
-- own internal polls measured them, D-049), backlash, internal polls,
-- fundraiser yields, anyone's
-- candidate or platform before the Select phase ends, the event deck beyond the
-- current week (next week's event only for a candidate whose perk previews it,
-- D-035), or anyone's debate focus or Choice stance but your own before the debate
-- or the week resolves (they are taken in the Decision phase, D-044, and live in
-- the hidden player state until then). tests/sim/View.spec enforces it.

local ConfigModule = require("./Config")
local Debate = require("./Debate")
local Draft = require("./Draft")
local Events = require("./Events")
local IssueMap = require("./IssueMap")
local Polls = require("./Polls")
local State = require("./State")
local Types = require("../Types")

type Config = ConfigModule.Config
type MatchState = State.MatchState

export type MoneyBracket = "Low" | "Medium" | "High"

export type StateView = {
	id: string,
	lean: number,
	leanTo: number?,
	capacity: number,
	battleground: boolean,
	owner: number?,
	isHome: boolean,
	momentum: { number },
	poll: State.Poll?,
	gotv: number, -- your own units
	backlash: number, -- your own attack backlash meter
}

export type PlayerView = {
	id: string,
	candidate: string?, -- nil until Select ends
	color: string, -- claimed or dealt (D-055, D-061), shown from Select on; may change during Select
	platform: { Types.Issue }?,
	home: string?,
	strongholds: { string },
	nominations: { string },
	location: string?,
	cash: number?, -- yours only
	money: MoneyBracket,
	underdogTier: number,
	frontrunner: boolean,
	pivotUsed: boolean,
	card: State.WeekCard?,
}

-- One stance of a Choice event, as shown on its button (D-039). The per-state
-- effect is Events.stanceEffects(config, view.issueMap, Events.byId[event.id], stance.id, ...).
export type StanceView = {
	id: Types.Choice,
	name: string,
	text: string,
}

-- This week's event, as everyone sees it (D-027, D-039).
export type EventView = {
	week: number,
	id: string,
	kind: Types.EventKind,
	name: string,
	text: string,
	issue: Types.Issue?, -- Spotlight and Choice
	region: Types.Region?, -- Regional
	stances: { StanceView }?, -- Choice: the three stances in Events.CHOICES order
}

export type View = {
	you: number,
	phase: State.Phase,
	decision: State.DecisionKind?, -- during a Decision phase: "Focus" or "Stance" (D-044)
	week: number,
	draftRound: number,
	draftKind: Draft.Kind?, -- during the draft
	draftPriority: number?, -- player with clash priority this draft round
	priorityA: number?, -- who holds priority in "A" rounds; public from the map reveal, absent during Select
	players: { PlayerView },
	states: { StateView },
	claims: { [string]: number }, -- Select: candidate id -> the player who claimed it (D-048)
	colorClaims: { [string]: number }, -- Select: color -> the player who claimed it (D-061); a color not in here was dealt
	canPickColor: boolean, -- you own the Color Pass and it is Select: you may claim any color not claimed by someone else (D-061)
	issueMap: IssueMap.IssueMap, -- each state's two top issues this match (D-047), public from Select on
	platformMults: { [string]: number }, -- by issue: rally/ad multiplier on a platform issue where it is a top issue (D-047)
	projectedEV: { number },
	draftLog: { State.DraftPick },
	nextDebate: { week: number, topics: { Types.Issue } }?,
	debates: { State.DebateResult },
	event: EventView?, -- this week's event, during its Decision, Debate and Plan phases
	nextEvent: EventView?, -- next week's event, only for a candidate with eventPreview (D-035)
	eventLog: { State.EventResult }, -- resolved events, Choice answers revealed
	internalPolls: { State.InternalPoll }, -- yours, from last week's plan
	scouted: { State.Scout }, -- yours: the latest ground game each of your internal polls saw, per state (D-049)
	raised: number, -- what your fundraisers raised last week
	debateFocus: Types.Issue?, -- your focus topic for this week's debate, from its Decision until the debate resolves
	stance: Types.Choice?, -- your stance on this week's Choice event, from its Decision until the week resolves
	election: State.ElectionResult?, -- from election night on
}

local View = {}

function View.moneyBracket(config: Config, cash: number): MoneyBracket
	if cash < config.OPPONENT_MONEY_LOW then
		return "Low"
	elseif cash > config.OPPONENT_MONEY_HIGH then
		return "High"
	end
	return "Medium"
end

local copy = State.deepCopy

-- The view for player `you`.
function View.build(config: Config, match: MatchState, you: number): View
	assert(match.players[you], `unknown player {you}`)
	local selected = match.phase ~= "Select"
	local mapShown = selected -- leans are revealed with the map, after Select

	local players: { PlayerView } = {}
	for p, player in match.players do
		local mine = p == you
		players[p] = {
			id = player.id,
			candidate = if selected then player.candidate else nil,
			color = player.color,
			platform = if selected then table.clone(player.platform) else nil,
			home = player.home,
			strongholds = table.clone(player.strongholds),
			nominations = table.clone(player.nominations),
			location = player.location,
			cash = if mine and selected then player.cash else nil,
			money = View.moneyBracket(config, player.cash),
			underdogTier = player.underdogTier,
			frontrunner = player.frontrunner,
			pivotUsed = player.pivotUsed,
			card = copy(player.card),
		}
	end

	local states: { StateView } = {}
	for i, s in match.states do
		states[i] = {
			id = s.id,
			lean = if mapShown then s.lean else 0,
			leanTo = if mapShown then s.leanTo else nil,
			capacity = s.capacity,
			battleground = s.battleground,
			owner = s.owner,
			isHome = s.isHome,
			momentum = table.clone(s.momentum),
			poll = copy(s.poll),
			gotv = s.gotv[you],
			backlash = s.backlash[you],
		}
	end

	local nextDebate = nil
	local debateWeek = Debate.nextWeek(config, math.max(match.week, 1))
	if debateWeek ~= nil and match.phase ~= "Done" and match.phase ~= "Election" then
		local resolved = false
		for _, result in match.debates do
			if result.week == debateWeek then
				resolved = true
			end
		end
		if resolved then
			debateWeek = Debate.nextWeek(config, debateWeek + 1)
		end
		if debateWeek ~= nil then
			nextDebate = { week = debateWeek, topics = table.clone(match.debateTopics[debateWeek]) }
		end
	end

	local me = match.players[you]
	local function eventView(week: number): EventView?
		local definition = Events.at(match, week)
		if definition == nil then
			return nil
		end
		local stances: { StanceView }? = nil
		local list = definition.stances
		if list ~= nil then
			local copied: { StanceView } = {}
			for k, stance in list do
				copied[k] = { id = stance.id, name = stance.name, text = stance.text }
			end
			stances = copied
		end
		return {
			week = week,
			id = definition.id,
			kind = definition.kind,
			name = definition.name,
			text = definition.text,
			issue = definition.issue,
			region = definition.region,
			stances = stances,
		}
	end
	local event: EventView? = nil
	local nextEvent: EventView? = nil
	if match.phase == "Decision" or match.phase == "Plan" or match.phase == "Debate" then
		event = eventView(match.week)
		-- The Pollster's briefing (D-035): a candidate with eventPreview sees that many
		-- weeks ahead. Nothing else about the deck leaves the server.
		if me.profile.eventPreview >= 1 and match.week + 1 <= config.WEEKS then
			nextEvent = eventView(match.week + 1)
		end
	end

	local drafting = match.phase == "Draft"
	return {
		you = you,
		phase = match.phase,
		decision = if match.phase == "Decision" then match.decision else nil,
		week = match.week,
		draftRound = match.draftRound,
		draftKind = if drafting then Draft.kind(config, match.draftRound) else nil,
		draftPriority = if drafting then Draft.priorityPlayer(config, match, match.draftRound) else nil,
		priorityA = if match.phase == "Select" then nil else match.priorityA,
		players = players,
		states = states,
		claims = table.clone(match.claims),
		colorClaims = table.clone(match.colorClaims),
		canPickColor = match.phase == "Select" and me.colorPass,
		issueMap = copy(match.issueMap),
		platformMults = copy(match.platformMults),
		projectedEV = Polls.projectedEV(match),
		draftLog = copy(match.draftLog),
		nextDebate = nextDebate,
		debates = copy(match.debates),
		event = event,
		nextEvent = nextEvent,
		eventLog = copy(match.eventLog),
		internalPolls = copy(me.internalPolls),
		scouted = copy(me.scouted),
		raised = me.raised,
		debateFocus = me.debateFocus,
		stance = me.stance,
		election = if match.phase == "Election" or match.phase == "Done" then copy(match.election) else nil,
	}
end

-- The events player `you` may see: public ones, plus their own private ones.
function View.events(events: { State.Event }, you: number): { State.Event }
	local out = {}
	for _, event in events do
		if not event.private or event.player == you then
			table.insert(out, table.clone(event))
		end
	end
	return out
end

return table.freeze(View)
