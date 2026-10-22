--!strict
-- Builds what ONE player may see. This is the only exit for simulation state: the
-- server replicates View.build output and nothing else.
--
-- Never included: true support or undecided, poll error terms, pool levels, the
-- seed or RNG state, opponents' exact cash, GOTV units, backlash, internal polls,
-- fundraiser yields, or debate prep before the debate resolves, and anyone's
-- candidate or platform before the Select phase ends. tests/sim/View.spec enforces it.

local ConfigModule = require("./Config")
local Debate = require("./Debate")
local Draft = require("./Draft")
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
	color: string?,
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

export type View = {
	you: number,
	phase: State.Phase,
	week: number,
	draftRound: number,
	draftKind: Draft.Kind?, -- during the draft
	draftPriority: number?, -- player with clash priority this draft round
	priorityA: number, -- public from the map reveal: who holds priority in "A" rounds
	players: { PlayerView },
	states: { StateView },
	projectedEV: { number },
	draftLog: { State.DraftPick },
	nextDebate: { week: number, topics: { Types.Issue } }?,
	debates: { State.DebateResult },
	internalPolls: { State.InternalPoll }, -- yours, from last week's plan
	raised: number, -- what your fundraisers raised last week
	debatePrep: { number }?, -- your prep for the next debate
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
			color = if selected then player.color else nil,
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
	local drafting = match.phase == "Draft"
	return {
		you = you,
		phase = match.phase,
		week = match.week,
		draftRound = match.draftRound,
		draftKind = if drafting then Draft.kind(config, match.draftRound) else nil,
		draftPriority = if drafting then Draft.priorityPlayer(config, match, match.draftRound) else nil,
		priorityA = match.priorityA,
		players = players,
		states = states,
		projectedEV = Polls.projectedEV(match),
		draftLog = copy(match.draftLog),
		nextDebate = nextDebate,
		debates = copy(match.debates),
		internalPolls = copy(me.internalPolls),
		raised = me.raised,
		debatePrep = copy(me.debatePrep),
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
