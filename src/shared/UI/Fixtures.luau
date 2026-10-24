--!strict
-- Realistic State payloads for each screen, made by playing a real Session with
-- bots up to the wanted moment. Screens render these in DEBUG_UI mode (no server
-- needed) and the UI specs use them. Deterministic by seed.

local Bot = require("../Sim/Bot")
local ConfigModule = require("../Sim/Config")
local Election = require("../Sim/Election")
local Events = require("../Sim/Events")
local Rng = require("../Sim/Rng")
local Session = require("../Net/Session")
local StateData = require("../Sim/StateData")
local View = require("../Sim/View")

type Config = ConfigModule.Config

export type Moment =
	"Select" -- character select, nothing chosen yet
	| "SelectColor" -- the same for a Color Pass owner: you hold Violet, Rex claimed Teal (D-061)
	| "SelectName" -- Select for a Name Pass owner (D-069): you named your candidate "Captain Zed"; Rex is "Big Wave"
	| "SelectNameBuy" -- Select for an eligible player without the Name Pass (D-069)
	| "MapReveal" -- leans shown
	| "Draft" -- a nomination round in progress, homes picked and strongholds assigned
	| "Plan" -- week 3 plan, with history behind it
	| "Stance" -- the Decision screen in a Choice week: stances A / B / C (D-044)
	| "ChoiceWeek" -- the plan that follows a stance (the stance taken in one line)
	| "Resolve" -- the resolve animation after week 3
	| "ChoiceResolve" -- the resolve animation right after a Choice week (both stances revealed)
	| "DebateIntro" -- the week 4 debate's stage before round 1 (D-072)
	| "DebateRound" -- round 2 of the week 9 debate: pick a move (D-072)
	| "Clash" -- the clash after round 1 of the week 4 debate
	| "Debate" -- the verdict after the week 4 debate's last round
	| "Election" -- election night
	| "Over" -- the result: a win for seat 1 (the first seed from `seed`, default END_SEED, on where it wins)
	| "Landslide" -- the result after a landslide win: you took over 70% of the votes (D-062)
	| "LandslideLoss" -- the result after the rival's landslide

local Fixtures = {}

local END_SEED = 26 -- the default first seed of the Election and Over moments
local END_TRIES = 40 -- seeds tried from there for a seat-1 win

Fixtures.MOMENTS = table.freeze({
	"Select",
	"SelectColor",
	"SelectName",
	"SelectNameBuy",
	"MapReveal",
	"Draft",
	"Plan",
	"Stance",
	"ChoiceWeek",
	"Resolve",
	"ChoiceResolve",
	"DebateIntro",
	"DebateRound",
	"Clash",
	"Debate",
	"Election",
	"Over",
	"Landslide",
	"LandslideLoss",
} :: { Moment })

local function reached(session: Session.Session, moment: Moment): boolean
	local phase = session.match.phase
	local stage = session.stage
	if moment == "Select" then
		return phase == "Select"
	elseif moment == "MapReveal" then
		return phase == "MapReveal"
	elseif moment == "Draft" then
		return phase == "Draft" and session.match.draftRound == 1 and stage == "Input"
	elseif moment == "Plan" then
		return phase == "Plan" and session.match.week == 3 and stage == "Input"
	elseif moment == "Stance" then
		return phase == "Decision" and session.match.decision == "Stance" and stage == "Input"
	elseif moment == "ChoiceWeek" then
		return phase == "Plan" and stage == "Input" and Events.isChoiceWeek(session.match)
	elseif moment == "Resolve" then
		return session.reveal == "Resolve" and session.match.week == 4
	elseif moment == "ChoiceResolve" then
		local log = session.match.eventLog
		local last = log[#log]
		return session.reveal == "Resolve"
			and last ~= nil
			and last.choices ~= nil
			and last.week == session.match.week - 1
	elseif moment == "DebateIntro" then
		return session.reveal == "DebateIntro"
	elseif moment == "DebateRound" then
		local live = session.match.debate
		return phase == "Debate"
			and stage == "Input"
			and session.match.week == 9
			and live ~= nil
			and live.round == 2
	elseif moment == "Clash" then
		return session.reveal == "Clash" and session.match.week == 4
	elseif moment == "Debate" then
		return session.reveal == "Verdict"
	elseif moment == "Election" then
		return phase == "Election" and stage == "Show"
	end
	return stage == "Over"
end

-- Plays one match with seed `s` up to `moment`. Nil if the match ends first (a
-- seed whose deck never deals a Choice event into a plan week).
local function play(config: Config, moment: Moment, s: number, candidate: string?): Session.StatePayload?
	local session = Session.new(config, "fixture", s, {
		{ id = "you", kind = "Human" },
		{ id = "bot", kind = "Bot", candidate = "calloway" },
	}, 0)
	local rng = Rng.new(s * 13 + 1)
	local t = 0
	for _ = 1, 500 do
		if reached(session, moment) then
			return Session.payload(session, 1)
		end
		if session.stage == "Over" then
			return nil
		end
		if session.stage == "Input" and not session.seats[1].locked then
			local view = View.build(config, session.match, 1)
			local input = Bot.act(config, view, rng, candidate or "okafor")
			local ok, reason = Session.submit(session, 1, session.step, input, t)
			assert(ok, `fixture submit rejected: {reason}`)
		else
			t = Session.nextWake(session)
			Session.update(session, t)
		end
		Session.drain(session)
	end
	return nil
end

-- Select for a Color Pass owner (D-061): two owners, you with Violet saved,
-- the opponent with Teal saved, and the opponent holding Rex Calloway.
local function selectColor(config: Config, s: number): Session.StatePayload
	local session = Session.new(config, "fixture", s, {
		{ id = "you", kind = "Human", colorPass = true, color = "Violet" },
		{ id = "rex", kind = "Human", colorPass = true, color = "Teal" },
	}, 0)
	local ok, reason = Session.claim(session, 2, session.step, "calloway", 0)
	assert(ok, `fixture claim rejected: {reason}`)
	Session.update(session, 0)
	Session.drain(session)
	return Session.payload(session, 1)
end

-- The Over payload turned into a landslide for `winner` (D-062): the loser's
-- safest states, in reveal order, go to the winner until the winner holds more
-- than LANDSLIDE_EV_SHARE of the votes; the totals and the result follow.
local function landslide(config: Config, payload: Session.StatePayload, winner: number): Session.StatePayload
	local election = payload.view.election
	assert(election ~= nil, "the Over fixture has no election")
	local total = 0
	for _, r in election.results do
		total += StateData.byId[r.state].ev
	end
	local function recount()
		local ev, states = table.create(#election.ev, 0), table.create(#election.ev, 0)
		for _, r in election.results do
			if r.winner > 0 then
				ev[r.winner] += StateData.byId[r.state].ev
				states[r.winner] += 1
			end
		end
		election.ev, election.statesWon = ev, states
	end
	recount()
	for _, r in election.results do
		if election.ev[winner] > config.LANDSLIDE_EV_SHARE * total then
			break
		end
		if r.winner ~= winner then
			r.winner = winner
			recount()
		end
	end
	election.winner = winner
	election.decidedBy = "EV"
	payload.result = { winner = winner, reason = "Election" }
	assert(Election.landslide(config, election) == winner, "the landslide fixture is not a landslide")
	return payload
end

-- Made-up Name Pass id for fixtures (the real one lives in Net/Products).
Fixtures.NAME_PASS_ID = 7654321
Fixtures.YOUR_NAME = "Captain Zed" -- the custom names in the SelectName fixture
Fixtures.THEIR_NAME = "Big Wave"

-- Select for a player who may use the Name Pass (D-069), both seats eligible
-- (they see custom names): `owned` you own it and named your candidate; the
-- opponent, holding Rex Calloway, is named too. Without `owned`, nobody is named.
local function selectName(config: Config, s: number, owned: boolean): Session.StatePayload
	local session = Session.new(config, "fixture", s, {
		{
			id = "you",
			kind = "Human",
			seesNames = true,
			namePass = { id = Fixtures.NAME_PASS_ID, owned = owned },
			customName = if owned then Fixtures.YOUR_NAME else nil,
		},
		{
			id = "rex",
			kind = "Human",
			seesNames = true,
			namePass = { id = Fixtures.NAME_PASS_ID, owned = owned },
			customName = if owned then Fixtures.THEIR_NAME else nil,
		},
	}, 0)
	local ok, reason = Session.claim(session, 2, session.step, "calloway", 0)
	assert(ok, `fixture claim rejected: {reason}`)
	Session.update(session, 0)
	if owned then
		-- The server shares each name once it is filtered for the viewer.
		Session.showName(session, 1, 2, Fixtures.THEIR_NAME, Fixtures.THEIR_NAME)
	end
	Session.drain(session)
	return Session.payload(session, 1)
end

-- The payload seat 1 would receive at `moment`. Seat 1 is played by the bot too,
-- as candidate `candidate` (default Dana Okafor) against Rex Calloway. Stance,
-- ChoiceWeek and ChoiceResolve try the next seeds in turn until one deals a Choice event
-- into a plan week (weeks 2 to 11), so the result is still fixed by the seed given.
function Fixtures.payload(
	config: Config,
	moment: Moment,
	seed: number?,
	candidate: string?
): Session.StatePayload
	local first = seed or 18 -- 7 -> 18 with the 24-card deck (D-039): weeks 3 and 8 are still Windfalls
	if moment == "Landslide" or moment == "LandslideLoss" then
		local over = Fixtures.payload(config, "Over", seed, candidate)
		return landslide(config, over, if moment == "Landslide" then over.you else 3 - over.you)
	end
	if seed == nil and (moment == "Election" or moment == "Over") then
		-- Half-price polls (D-063) turned seed 18 into a loss for seat 1; END_SEED
		-- is where the search for a seat-1 win starts.
		first = END_SEED
	end
	if moment == "SelectColor" then
		return selectColor(config, first)
	elseif moment == "SelectName" or moment == "SelectNameBuy" then
		return selectName(config, first, moment == "SelectName")
	end
	if moment == "Election" or moment == "Over" then
		-- The result screen's fixture is a win for seat 1 (its specs check the
		-- victory moment), and election night is the same match.
		for k = 0, END_TRIES - 1 do
			local over = play(config, "Over", first + k, candidate)
			if over and over.result and over.result.winner == 1 then
				if moment == "Over" then
					return over
				end
				local night = play(config, "Election", first + k, candidate)
				if night then
					return night
				end
			end
		end
		error(`no seed from {first} on gives seat 1 the win`)
	end
	local tries = if moment == "Stance" or moment == "ChoiceWeek" or moment == "ChoiceResolve" then 40 else 1
	for k = 0, tries - 1 do
		local payload = play(config, moment, first + k, candidate)
		if payload then
			return payload
		end
	end
	error(`fixture never reached {moment}`)
end

-- Made-up pass id for fixtures (the real one lives in Net/Products).
Fixtures.COLOR_PASS_ID = 1234567

-- Made-up usernames for the leaderboard fixture.
local FIRST = { "Maple", "Quiet", "Pixel", "Nova", "River", "Tiny", "Copper", "Mossy", "Sunny", "Bright" }
local SECOND = { "Fox", "Comet", "Harbor", "Bean", "Sketch" }

-- A leaderboard as the server sends it (Net/Leaderboard.Board, D-059).
-- `options.count` entries (default 50); `options.you` is the viewer's rank in
-- the list (default 4), or 0 for a ranked viewer outside it, or -1 for a
-- viewer with no rated games; `options.status` overrides "Ok".
function Fixtures.leaderboard(options: { count: number?, you: number?, status: string? }?): any
	local count = if options and options.count then options.count else 50
	local you = if options and options.you then options.you else 4
	local entries = {}
	for k = 1, count do
		local first = FIRST[(k - 1) % #FIRST + 1]
		local second = SECOND[(k - 1) // #FIRST % #SECOND + 1]
		table.insert(
			entries,
			{ rank = k, id = tostring(1000 + k), name = `{first}{second}{k}`, rating = 1480 - 9 * k }
		)
	end
	local mine: { rank: number?, rating: number }? = nil
	if you > 0 and you <= count then
		mine = { rank = you, rating = entries[you].rating }
	elseif you == 0 then
		mine = { rating = 1004 }
	end
	return {
		status = if options and options.status then options.status else "Ok",
		entries = entries,
		you = mine,
	}
end

-- A lobby status for the lobby screen. `options.colorPass` shows the color
-- option (D-055) as a non-owner ("locked") or an owner ("owned"); without it the
-- pass is not set up. `options.color` is the saved pick.
function Fixtures.lobby(
	state: ("Idle" | "Queued" | "Hosting")?,
	options: { colorPass: ("locked" | "owned")?, color: string? }?
): any
	local pass = if options then options.colorPass else nil
	return {
		state = state or "Idle",
		code = if state == "Hosting" then "AB3CD" else nil,
		queued = if state == "Queued" then 1 else 0,
		full = false,
		color = if options then options.color else nil,
		colorPass = if pass then { id = Fixtures.COLOR_PASS_ID, owned = pass == "owned" } else nil,
	}
end

return table.freeze(Fixtures)
