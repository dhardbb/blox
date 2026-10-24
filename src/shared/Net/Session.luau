--!strict
-- One live match: the simulation plus everything the server adds around it
-- (phase timers, lock-ins, the time bank, resolve skips, disconnect grace,
-- forfeits, bots) and the per-seat State messages it replicates.
--
-- Pure like the simulation: the caller passes the current server time (`now`,
-- an absolute workspace:GetServerTimeNow() value) into every call and sends
-- whatever Session.drain returns. Nothing here touches Roblox, so it is tested
-- headlessly (tests/net/Session.spec.luau).
--
-- Stages: "Input" (players submit for a Select, Draft, Decision, Debate round or
-- Plan phase; a Decision has its own TIMER_DECISION and no reveal after it,
-- D-044), "Show" (map reveal, the debate's intro, election night), "Reveal"
-- (draft reveal, resolve animation, a debate round's clash and the debate's
-- verdict, D-072), "Over". A debate week runs: intro (Show) -> three times
-- [round (Input, TIMER_DEBATE_ROUND) -> clash (Reveal)] -> verdict (Reveal). Every stage change bumps `step`; clients stamp each
-- request with the step they saw, and stale requests are rejected.

local Bot = require("../Sim/Bot")
local Candidates = require("../Sim/Candidates")
local ConfigModule = require("../Sim/Config")
local Match = require("../Sim/Match")
local Resolve = require("../Sim/Resolve")
local Rng = require("../Sim/Rng")
local State = require("../Sim/State")
local View = require("../Sim/View")
local CustomName = require("./CustomName")

type Config = ConfigModule.Config

export type SeatKind = "Human" | "Bot"
export type Stage = "Input" | "Show" | "Reveal" | "Over"
export type RevealKind = "Draft" | "Resolve" | "Debate" | "DebateIntro" | "Clash" | "Verdict" -- "Debate" is no longer sent (D-072)
export type Reason = "Election" | "Forfeit" | "Abandoned"

export type Seat = {
	id: string, -- player id (a UserId as a string) or a bot label
	kind: SeatKind,
	connected: boolean,
	graceUntil: number?, -- while disconnected: auto-submit once this passes
	graceLeft: number, -- grace periods left this match
	bank: number, -- time-bank seconds left this match
	bankUsed: number, -- seconds added to this seat's deadline in the current Input stage (time bank, reconnect)
	locked: boolean,
	input: any?, -- normalized submission for the current Input stage
	skip: boolean, -- wants to skip the current Reveal/Show
	missed: number, -- consecutive Plan stages missed while disconnected
	debateGraceWeek: number?, -- the debate week this seat already spent a grace use in (one per debate, D-072)
	leftEarly: boolean, -- disconnected before week 1 began and not back since (D-075)
	prePick: any?, -- lobby pre-pick, used if Select times out
	botCandidate: string?,
	botStyle: Bot.Style?,
	botDifficulty: Bot.Difficulty?, -- practice difficulty (D-057); nil for a harness bot with an explicit style
	botRng: Rng.Rng?,
	-- Custom names (the Name Pass, D-069). The server fills these from its own
	-- checks; a bot seat never has any.
	customName: string?, -- this player's candidate name for the match, already filtered
	seesNames: boolean, -- this player may see custom names (eligible: Roblox lets them chat)
	namePass: NamePass?, -- this player may use the Name Pass (it is set up and they are eligible)
	shownNames: { [number]: string? }, -- other seats' names as filtered for THIS viewer (Session.showName)
	hiddenNames: { [number]: string }, -- names this viewer reported: never shown to them again
}

-- The Name Pass as one seat sees it (D-069): present only for a player who is
-- eligible while the pass is set up.
export type NamePass = {
	id: number, -- the pass id, for MarketplaceService:PromptGamePassPurchase
	owned: boolean, -- the server's check
}

-- What the Select screen needs to offer a custom name (StatePayload.naming).
export type Naming = {
	id: number, -- the pass id
	owned: boolean,
	name: string?, -- the custom name in use this match; nil = the candidate's own
}

export type Result = {
	winner: number, -- seat index, 0 if nobody (abandoned) or if several seats share the win
	reason: Reason,
	-- A forfeit with more than two players: every seat that stayed, in seat order.
	-- Absent when one seat won (always, with two players).
	winners: { number }?,
	-- The match counts for no one's rating (D-075): a player forfeited or left
	-- before week 1 began. Absent otherwise.
	unrated: boolean?,
}

export type SeatInfo = {
	id: string,
	kind: SeatKind,
	connected: boolean,
	locked: boolean,
	skip: boolean,
	bank: number,
	graceUntil: number?,
	difficulty: Bot.Difficulty?, -- a bot seat's practice difficulty (D-057)
}

export type StatePayload = {
	matchId: string,
	step: number,
	stage: Stage,
	reveal: RevealKind?,
	stageStart: number,
	deadline: number, -- this seat's deadline (its own time bank included)
	you: number,
	view: View.View,
	events: { State.Event },
	seats: { SeatInfo },
	result: Result?,
	naming: Naming?, -- the Name Pass for this seat (D-069); absent unless they may use it
}

export type Message = {
	seat: number,
	kind: "State" | "Notice",
	state: StatePayload?,
	notice: string?, -- notice code, e.g. "OpponentDisconnected"
}

export type Session = {
	id: string,
	config: Config,
	match: State.MatchState,
	seats: { Seat },
	step: number,
	stage: Stage,
	stageStart: number,
	deadline: number, -- base deadline of the stage
	skippedTo: number?, -- earlier end once every seat has skipped
	reveal: RevealKind?, -- what a Reveal stage is showing
	events: { State.Event }, -- events of the last advance, shown during Reveal
	result: Result?,
	outbox: { Message },
	pendingClaims: { [number]: string }, -- Select: candidate claims waiting for the next update (one batch, D-048)
	pendingColorClaims: { [number]: string }, -- Select: color claims waiting for the next update (one batch, D-061)
	introWeek: number?, -- the debate week whose intro has been shown (D-072)
	verdictNext: boolean, -- the last round's clash is on: the debate's verdict follows it
}

-- Match options a private lobby may set (public queue and practice use none).
export type Options = {
	events: boolean?, -- false: no event deck this match (D-027)
}

export type SeatSpec = {
	id: string,
	kind: SeatKind,
	prePick: any?, -- Human: optional lobby pre-pick
	colorPass: boolean?, -- Human: owns the Color Pass (the server's check, D-055): may claim colors in Select (D-061)
	color: string?, -- Human: a Color Pass owner's saved favorite, claimed as Select opens (D-061); ignored without colorPass
	customName: string?, -- Human: a Name Pass owner's saved name, filtered for this match (D-069)
	seesNames: boolean?, -- Human: may see custom names (D-069); default false
	namePass: NamePass?, -- Human: may use the Name Pass (D-069)
	candidate: string?, -- Bot: candidate to play
	style: Bot.Style?, -- Bot: play style (wins over difficulty; the harness uses it)
	difficulty: Bot.Difficulty?, -- Bot: practice difficulty (D-057); plays Bot.styleFor(difficulty)
}

local Session = {}

-- Request outcome codes (the client maps them to messages).
Session.Reason = table.freeze({
	StaleStep = "StaleStep",
	NotInput = "NotInput",
	AlreadyLocked = "AlreadyLocked",
	NoBank = "NoBank",
	NotSkippable = "NotSkippable",
	Over = "Over",
	NotSelect = "NotSelect",
})

-- Notice sent to a player whose claim lost a same-step coin flip (D-048).
Session.CANDIDATE_TAKEN = "CandidateTaken"
-- Notice sent to a Color Pass owner whose color claim (or saved favorite, as
-- Select opened) lost a same-step coin flip: pick another color (D-061).
Session.COLOR_TAKEN = "ColorTaken"
-- Notice sent to the others when a player leaves the match (D-059).
Session.OPPONENT_FORFEITED = "OpponentForfeited"

local function isBot(seat: Seat): boolean
	return seat.kind == "Bot"
end

-- A seat that has disconnected and run out of grace no longer holds anything up.
local function absent(seat: Seat, now: number): boolean
	return not seat.connected and (seat.graceUntil == nil or now >= seat.graceUntil)
end

local function seatDeadline(session: Session, seat: Seat): number
	return session.deadline + seat.bankUsed
end

local function inputDuration(config: Config, phase: State.Phase): number
	if phase == "Select" then
		return config.TIMER_SELECT
	elseif phase == "Draft" then
		return config.TIMER_DRAFT_ROUND
	elseif phase == "Decision" then
		return config.TIMER_DECISION
	elseif phase == "Debate" then
		return config.TIMER_DEBATE_ROUND
	end
	return config.TIMER_PLAN
end

-- ---------------------------------------------------------------- messages

function Session.payload(session: Session, p: number): StatePayload
	local seats: { SeatInfo } = {}
	for q, seat in session.seats do
		seats[q] = {
			id = seat.id,
			kind = seat.kind,
			connected = seat.connected,
			locked = seat.locked,
			skip = seat.skip,
			bank = seat.bank,
			graceUntil = if seat.connected then nil else seat.graceUntil,
			difficulty = seat.botDifficulty,
		}
	end
	local deadline = if session.stage == "Input"
		then seatDeadline(session, session.seats[p])
		else session.skippedTo or session.deadline
	-- Custom names reach only a viewer who may see them (D-069): their own,
	-- and each other seat's as the server filtered it for this viewer.
	local seat = session.seats[p]
	local names: { [number]: string }? = nil
	if seat.seesNames then
		local found: { [number]: string } = {}
		for q, other in session.seats do
			local shown = if q == p then other.customName else seat.shownNames[q]
			if shown ~= nil and other.customName ~= nil then
				found[q] = shown
			end
		end
		names = found
	end
	-- Your own debate move, once locked in this round (the match keeps it only as
	-- the session's input until the round resolves), so a rejoin shows it.
	local yourMove = if session.stage == "Input"
			and session.match.phase == "Debate"
			and seat.locked
		then seat.input
		else nil
	local view = View.build(session.config, session.match, p, names, yourMove)
	-- Week 12's resolve reveal already runs in phase Election, and a forfeit after
	-- it leaves a computed result nobody saw: the result is sent only from election
	-- night on (the Show stage, then the end of a match decided by it).
	local result = session.result
	local night = (session.stage == "Show" and session.match.phase == "Election")
		or (session.stage == "Over" and result ~= nil and result.reason == "Election")
	if not night then
		view.election = nil
	end
	return {
		matchId = session.id,
		step = session.step,
		stage = session.stage,
		reveal = session.reveal,
		stageStart = session.stageStart,
		deadline = deadline,
		you = p,
		view = view,
		events = View.events(session.events, p),
		seats = seats,
		result = if session.result then table.clone(session.result) else nil,
		naming = if seat.namePass
			then { id = seat.namePass.id, owned = seat.namePass.owned, name = seat.customName }
			else nil,
	}
end

-- Queues a fresh State message for every connected human seat.
local function broadcast(session: Session)
	for p, seat in session.seats do
		if seat.kind == "Human" and seat.connected then
			table.insert(session.outbox, { seat = p, kind = "State", state = Session.payload(session, p) })
		end
	end
end

local function notify(session: Session, except: number, notice: string)
	for p, seat in session.seats do
		if p ~= except and seat.kind == "Human" and seat.connected then
			table.insert(session.outbox, { seat = p, kind = "Notice", notice = notice })
		end
	end
end

-- Returns and clears the queued messages.
function Session.drain(session: Session): { Message }
	local out = session.outbox
	session.outbox = {}
	return out
end

-- ---------------------------------------------------------------- stages

local function setStage(session: Session, stage: Stage, now: number, duration: number)
	session.step += 1
	session.stage = stage
	session.stageStart = now
	session.deadline = now + duration
	session.skippedTo = nil
	session.reveal = nil
	for _, seat in session.seats do
		seat.skip = isBot(seat)
	end
end

local function finish(session: Session, now: number, result: Result)
	session.result = result
	setStage(session, "Over", now, 0)
end

-- Before week 1 begins: Select, the map reveal and the draft (D-075).
local function beforeWeekOne(session: Session): boolean
	local phase = session.match.phase
	return phase == "Select" or phase == "MapReveal" or phase == "Draft"
end

-- Ends the match as a forfeit by `losers` (seat indices). Every other seat wins:
-- with two players that is the one other seat, as `winner`; with more, all who
-- stayed share it (`winners`, and `winner` 0). Nobody left: abandoned. A loser who
-- forfeited or left before week 1 began makes it unrated for everyone (D-075).
local function forfeitBy(session: Session, now: number, losers: { [number]: boolean }, early: boolean)
	local stayed: { number } = {}
	for p in session.seats do
		if not losers[p] then
			table.insert(stayed, p)
		end
	end
	if #stayed == 0 then
		finish(session, now, { winner = 0, reason = "Abandoned" })
		return
	end
	local unrated = early
	for p in losers do
		if session.seats[p].leftEarly then
			unrated = true
		end
	end
	local result: Result = { winner = if #stayed == 1 then stayed[1] else 0, reason = "Forfeit" }
	if #stayed > 1 then
		result.winners = stayed
	end
	if unrated then
		result.unrated = true
	end
	finish(session, now, result)
end

local enterPhase: (session: Session, now: number) -> ()

-- Advances the simulation one phase with the given inputs and keeps its events.
local function advance(session: Session, inputs: { [number]: any })
	local nextMatch, events = Match.advance(session.config, session.match, inputs)
	session.match = nextMatch
	session.events = events
end

local function tell(session: Session, p: number, notice: string)
	local seat = session.seats[p]
	if seat.kind == "Human" and seat.connected then
		table.insert(session.outbox, { seat = p, kind = "Notice", notice = notice })
	end
end

-- Settles the claims that arrived since the last update as one batch each
-- (candidates, then colors): a seeded coin flip orders them (Match.claim,
-- Match.claimColor), and a loser is told (D-048, D-061).
local function settleClaims(session: Session)
	if next(session.pendingClaims) == nil and next(session.pendingColorClaims) == nil then
		return
	end
	if next(session.pendingClaims) ~= nil then
		local requests = session.pendingClaims
		session.pendingClaims = {}
		local nextMatch, outcomes = Match.claim(session.config, session.match, requests)
		session.match = nextMatch
		for p in outcomes do
			tell(session, p, Session.CANDIDATE_TAKEN)
		end
	end
	if next(session.pendingColorClaims) ~= nil then
		local requests = session.pendingColorClaims
		session.pendingColorClaims = {}
		local nextMatch, outcomes = Match.claimColor(session.config, session.match, requests)
		session.match = nextMatch
		for p, reason in outcomes do
			if reason == "ColorTaken" then
				tell(session, p, Session.COLOR_TAKEN)
			end
		end
	end
	broadcast(session)
end

-- Bots submit as soon as an Input stage opens, from their own View. At Select a
-- bot claims its candidate first (one batch for every bot), or a free one.
local function botInputs(session: Session)
	local candidates: { [number]: string } = {}
	if session.match.phase == "Select" then
		local requests: { [number]: string } = {}
		for p, seat in session.seats do
			if isBot(seat) then
				requests[p] = seat.botCandidate or "okafor"
			end
		end
		local nextMatch = Match.claim(session.config, session.match, requests)
		session.match = nextMatch
		for p in requests do
			local claimed = Match.claimOf(session.match, p)
			if claimed == nil then
				claimed = Match.default(session.config, session.match, p).candidate
				session.match = (Match.claim(session.config, session.match, { [p] = claimed }))
			end
			candidates[p] = claimed :: string
		end
	end
	for p, seat in session.seats do
		if isBot(seat) then
			local view = View.build(session.config, session.match, p)
			local rng = seat.botRng :: Rng.Rng
			local candidate = candidates[p] or seat.botCandidate or "okafor"
			local input = Bot.act(session.config, view, rng, candidate, seat.botStyle)
			local ok, _, normalized = Match.validate(session.config, session.match, p, input)
			seat.input = if ok then normalized else nil
			seat.locked = true
		end
	end
end

enterPhase = function(session: Session, now: number)
	local config = session.config
	local phase = session.match.phase
	if session.verdictNext then
		-- The last round's clash is over: the debate's verdict (D-072).
		session.verdictNext = false
		setStage(session, "Reveal", now, config.TIMER_DEBATE_VERDICT)
		session.reveal = "Verdict"
		broadcast(session)
		return
	end
	if phase == "Debate" and session.introWeek ~= session.match.week then
		-- The debate stage before round 1 (D-072).
		session.introWeek = session.match.week
		session.events = {}
		setStage(session, "Show", now, config.TIMER_DEBATE_INTRO)
		session.reveal = "DebateIntro"
		broadcast(session)
		return
	end
	if
		phase == "Select"
		or phase == "Draft"
		or phase == "Decision"
		or phase == "Debate"
		or phase == "Plan"
	then
		for _, seat in session.seats do
			seat.locked = false
			seat.input = nil
			seat.bankUsed = 0
		end
		setStage(session, "Input", now, inputDuration(config, phase))
		session.events = {}
		botInputs(session)
	elseif phase == "MapReveal" then
		session.events = {}
		setStage(session, "Show", now, config.TIMER_MAP_REVEAL)
	elseif phase == "Election" then
		session.events = {}
		setStage(session, "Show", now, config.TIMER_ELECTION)
	else
		local election = session.match.election :: State.ElectionResult
		finish(session, now, { winner = election.winner, reason = "Election" })
	end
	broadcast(session)
end

-- Ends the current Input stage: fills in defaults, advances, then reveals.
local function closeInput(session: Session, now: number)
	local config = session.config
	local phase = session.match.phase
	local inputs = {}
	for p, seat in session.seats do
		if seat.locked and seat.input ~= nil then
			inputs[p] = seat.input
		elseif phase == "Select" and seat.prePick ~= nil then
			-- The lobby pre-pick, on the candidate this player claimed if they did.
			local pick = table.clone(seat.prePick)
			pick.candidate = Match.claimOf(session.match, p) or pick.candidate
			inputs[p] = pick
		end
		if phase == "Plan" and seat.kind == "Human" then
			-- Consecutive: any week the player was here (locked in or just idle) or
			-- played before dropping starts the count again.
			if seat.locked or seat.connected then
				seat.missed = 0
			else
				seat.missed += 1
			end
		end
	end
	advance(session, inputs)

	if phase == "Plan" then
		-- Every seat that has now missed too many weeks forfeits, all at once.
		local losers: { [number]: boolean } = {}
		local any = false
		for p, seat in session.seats do
			if seat.missed >= config.FORFEIT_MISSED_WEEKS then
				losers[p] = true
				any = true
			end
		end
		if any then
			forfeitBy(session, now, losers, false)
			broadcast(session)
			return
		end
	end

	local reveal = if phase == "Draft"
		then config.DRAFT_REVEAL
		elseif phase == "Plan" then Resolve.revealTime(config, session.events)
		elseif phase == "Debate" then config.TIMER_DEBATE_CLASH
		else 0
	if reveal > 0 then
		setStage(session, "Reveal", now, reveal)
		session.reveal = if phase == "Draft" then "Draft" elseif phase == "Debate" then "Clash" else "Resolve"
		-- After the last round the match has left the Debate phase: the verdict follows.
		session.verdictNext = phase == "Debate" and session.match.phase ~= "Debate"
		broadcast(session)
	else
		enterPhase(session, now)
	end
end

-- Is the current Input stage ready to close?
local function inputDone(session: Session, now: number): boolean
	for _, seat in session.seats do
		if not seat.locked then
			if seat.connected then
				if now < seatDeadline(session, seat) then
					return false
				end
			elseif not absent(seat, now) then
				-- Disconnected but still in grace: wait for them past the deadline.
				return false
			end
		end
	end
	return true
end

-- End time of a Show or Reveal stage, honoring skips.
local function showEnd(session: Session): number
	return session.skippedTo or session.deadline
end

-- Moves the session forward as far as the clock allows.
function Session.update(session: Session, now: number)
	settleClaims(session)
	for _ = 1, 64 do
		if session.stage == "Over" then
			return
		end
		local humansHere = false
		for _, seat in session.seats do
			if seat.kind == "Human" and not absent(seat, now) then
				humansHere = true
			end
		end
		if not humansHere then
			finish(session, now, { winner = 0, reason = "Abandoned" })
			broadcast(session)
			return
		end
		if session.stage == "Input" then
			if not inputDone(session, now) then
				return
			end
			closeInput(session, now)
		elseif now >= showEnd(session) then
			-- Only a Show stage ends its phase. The resolve reveal that closes week 12
			-- already runs in phase Election, and must lead into election night.
			if
				session.stage == "Show"
				and (session.match.phase == "MapReveal" or session.match.phase == "Election")
			then
				advance(session, {})
			end
			enterPhase(session, now)
		else
			return
		end
	end
	error("session did not settle")
end

-- Earliest time at which Session.update could change something (for scheduling).
function Session.nextWake(session: Session): number
	if session.stage == "Over" then
		return math.huge
	end
	if next(session.pendingClaims) ~= nil or next(session.pendingColorClaims) ~= nil then
		return -math.huge -- claims settle on the next tick
	end
	local wake = if session.stage == "Input" then math.huge else showEnd(session)
	for _, seat in session.seats do
		if session.stage == "Input" and not seat.locked then
			wake = math.min(wake, seatDeadline(session, seat))
		end
		local grace = seat.graceUntil
		-- A grace period that ran out before this stage began has already been handled.
		if not seat.connected and grace ~= nil and grace > session.stageStart then
			wake = math.min(wake, grace)
		end
	end
	return wake
end

-- ---------------------------------------------------------------- construction

function Session.new(
	config: Config,
	id: string,
	seed: number,
	specs: { SeatSpec },
	now: number,
	options: Options?
): Session
	assert(#specs >= 2, "a session needs two seats")
	if options and options.events == false then
		config = ConfigModule.with(config, { EVENTS_ENABLED = false })
	end
	local ids = {}
	local colorPass: { [string]: Match.ColorPass } = {}
	local seats: { Seat } = {}
	for p, spec in specs do
		ids[p] = spec.id
		if spec.kind == "Human" and spec.colorPass == true then
			colorPass[spec.id] = { favorite = spec.color }
		end
		-- A practice bot's level (D-057); an explicit style (the harness) wins.
		local difficulty: Bot.Difficulty? = if spec.kind == "Bot"
				and spec.style == nil
				and spec.difficulty ~= nil
			then Bot.difficulty(spec.difficulty)
			else nil
		seats[p] = {
			id = spec.id,
			kind = spec.kind,
			connected = true,
			graceUntil = nil,
			graceLeft = config.GRACE_USES,
			bank = config.TIME_BANK,
			bankUsed = 0,
			locked = false,
			input = nil,
			skip = spec.kind == "Bot",
			missed = 0,
			debateGraceWeek = nil,
			leftEarly = false,
			prePick = spec.prePick,
			botCandidate = spec.candidate,
			botStyle = spec.style or (if difficulty then Bot.styleFor(difficulty) else nil),
			botDifficulty = difficulty,
			botRng = if spec.kind == "Bot" then Rng.new(seed * 31 + p) else nil,
			customName = if spec.kind == "Human" then spec.customName else nil,
			seesNames = spec.kind == "Human" and spec.seesNames == true,
			namePass = if spec.kind == "Human" and spec.namePass then table.clone(spec.namePass) else nil,
			shownNames = {},
			hiddenNames = {},
		}
	end
	local session: Session = {
		id = id,
		config = config,
		match = Match.new(config, seed, ids, colorPass),
		seats = seats,
		step = 0,
		stage = "Input",
		stageStart = now,
		deadline = now,
		skippedTo = nil,
		reveal = nil,
		events = {},
		result = nil,
		outbox = {},
		pendingClaims = {},
		pendingColorClaims = {},
		introWeek = nil,
		verdictNext = false,
	}
	enterPhase(session, now)
	-- An owner whose saved favorite lost the coin flip as Select opened (both
	-- owners saved the same color) is told to pick another (D-061).
	for p, spec in specs do
		local favorite = if colorPass[spec.id] ~= nil then spec.color else nil
		if favorite ~= nil and table.find(Candidates.colors, favorite) ~= nil then
			if Match.colorClaimOf(session.match, p) ~= favorite then
				tell(session, p, Session.COLOR_TAKEN)
			end
		end
	end
	return session
end

-- ---------------------------------------------------------------- requests

local function checkStep(session: Session, step: any): string?
	if session.stage == "Over" then
		return Session.Reason.Over
	end
	if step ~= session.step then
		return Session.Reason.StaleStep
	end
	return nil
end

-- A player locks in their input for the current Input stage. Returns (ok, reason).
function Session.submit(session: Session, p: number, step: any, input: any, now: number): (boolean, string?)
	local stale = checkStep(session, step)
	if stale then
		return false, stale
	end
	local seat = session.seats[p]
	if session.stage ~= "Input" then
		return false, Session.Reason.NotInput
	end
	if seat.locked then
		return false, Session.Reason.AlreadyLocked
	end
	if now > seatDeadline(session, seat) + 1 then
		return false, Session.Reason.StaleStep
	end
	if session.match.phase == "Select" then
		-- Locking in a selection claims its candidate, first come first served (D-048).
		settleClaims(session)
		local candidate = if type(input) == "table" then input.candidate else nil
		local free, why = Match.canClaim(session.match, p, candidate)
		if not free then
			return false, why
		end
		local ok, reason = Match.validate(session.config, session.match, p, input)
		if not ok then
			return false, reason
		end
		session.match = (Match.claim(session.config, session.match, { [p] = candidate }))
	end
	local ok, reason, normalized = Match.validate(session.config, session.match, p, input)
	if not ok then
		return false, reason
	end
	seat.input = normalized
	seat.locked = true
	broadcast(session)
	Session.update(session, now)
	return true, nil
end

-- A player claims a candidate during Select (step 1 of the Select screen, D-048).
-- A candidate someone already holds is turned down at once ("CandidateTaken");
-- otherwise the claim waits for the next update, where every claim that arrived
-- in the same server step is settled together by a seeded coin flip.
function Session.claim(
	session: Session,
	p: number,
	step: any,
	candidate: any,
	now: number
): (boolean, string?)
	local stale = checkStep(session, step)
	if stale then
		return false, stale
	end
	local seat = session.seats[p]
	if session.stage ~= "Input" then
		return false, Session.Reason.NotInput
	end
	if session.match.phase ~= "Select" then
		return false, Session.Reason.NotSelect
	end
	if seat.locked then
		return false, Session.Reason.AlreadyLocked
	end
	if now > seatDeadline(session, seat) + 1 then
		return false, Session.Reason.StaleStep
	end
	local ok, reason = Match.canClaim(session.match, p, candidate)
	if not ok then
		return false, reason
	end
	if Match.claimOf(session.match, p) == candidate then
		return true, nil
	end
	session.pendingClaims[p] = candidate
	return true, nil
end

-- A Color Pass owner claims a color during Select (D-061), first come, first
-- served like a candidate: a color someone else holds is turned down at once
-- ("ColorTaken"), a player without the pass is turned down ("NoColorPass");
-- otherwise the claim waits for the next update, where every color claim that
-- arrived in the same server step is settled together by a seeded coin flip.
-- A new claim releases the player's old color. Allowed until Select ends, also
-- after locking in (the color is not part of the selection).
function Session.claimColor(
	session: Session,
	p: number,
	step: any,
	color: any,
	now: number
): (boolean, string?)
	local stale = checkStep(session, step)
	if stale then
		return false, stale
	end
	local seat = session.seats[p]
	if session.stage ~= "Input" then
		return false, Session.Reason.NotInput
	end
	if session.match.phase ~= "Select" then
		return false, Session.Reason.NotSelect
	end
	if now > seatDeadline(session, seat) + 1 then
		return false, Session.Reason.StaleStep
	end
	local ok, reason = Match.canClaimColor(session.match, p, color)
	if not ok then
		return false, reason
	end
	if Match.colorClaimOf(session.match, p) == color then
		session.pendingColorClaims[p] = nil -- back to the color they hold
		return true, nil
	end
	session.pendingColorClaims[p] = color
	return true, nil
end

-- A Name Pass owner names their candidate for this match (D-069); nil goes back
-- to the candidate's own name. The server has already checked the pass and
-- filtered the name (server/NameService): this only stores it. Allowed only
-- during Select (the name is part of who you are this match), also after
-- locking in; never for a bot seat. Everyone who may see custom names gets a
-- fresh State at once.
function Session.setName(session: Session, p: number, name: string?): (boolean, string?)
	local seat = session.seats[p]
	if seat == nil or seat.kind ~= "Human" then
		return false, Session.Reason.NotInput
	end
	if session.stage == "Over" then
		return false, Session.Reason.Over
	end
	if session.match.phase ~= "Select" then
		return false, Session.Reason.NotSelect
	end
	if seat.namePass == nil or not seat.namePass.owned then
		return false, CustomName.Reason.NoNamePass
	end
	seat.customName = name
	-- Nobody else sees the new name until the server has filtered it for them.
	for _, other in session.seats do
		other.shownNames[p] = nil
	end
	broadcast(session)
	return true, nil
end

-- Shows seat `setter`'s name `name` to seat `viewer` as `text`: the name as the
-- server filtered it for that viewer, or nil to show them the candidate's own
-- name (D-069). Ignored when the setter's name has changed since (`name` is
-- what the server filtered). Sends the viewer a fresh State when it changes.
function Session.showName(session: Session, viewer: number, setter: number, name: string, text: string?)
	local seat = session.seats[viewer]
	local from = session.seats[setter]
	if seat == nil or from == nil or viewer == setter or session.stage == "Over" then
		return
	end
	if from.customName ~= name or seat.shownNames[setter] == text then
		return
	end
	if text ~= nil and seat.hiddenNames[setter] == name then
		return -- this viewer reported it
	end
	seat.shownNames[setter] = text
	if seat.kind == "Human" and seat.connected then
		table.insert(
			session.outbox,
			{ seat = viewer, kind = "State", state = Session.payload(session, viewer) }
		)
	end
end

-- The server learned that a seat owns the Name Pass (bought during the match)
-- or that it may use it at all (eligible: then it may also see names; nil =
-- not eligible); sends that seat a fresh State.
function Session.setNamePass(session: Session, p: number, pass: NamePass?)
	local seat = session.seats[p]
	if seat == nil or seat.kind ~= "Human" or session.stage == "Over" then
		return
	end
	seat.namePass = if pass then table.clone(pass) else nil
	seat.seesNames = pass ~= nil
	if seat.connected then
		table.insert(session.outbox, { seat = p, kind = "State", state = Session.payload(session, p) })
	end
end

-- Seat `viewer` reported seat `setter`'s name `name` (D-069): they see the
-- candidate's own name from now on, whatever the server shares later. Sends
-- them a fresh State.
function Session.hideName(session: Session, viewer: number, setter: number, name: string)
	local seat = session.seats[viewer]
	if seat == nil or session.seats[setter] == nil or viewer == setter then
		return
	end
	seat.hiddenNames[setter] = name
	seat.shownNames[setter] = nil
	if seat.kind == "Human" and seat.connected and session.stage ~= "Over" then
		table.insert(
			session.outbox,
			{ seat = viewer, kind = "State", state = Session.payload(session, viewer) }
		)
	end
end

-- A reviewer removed seat `p`'s name (D-069): their candidate goes back to its
-- own name for everyone, in any phase. Everyone gets a fresh State.
function Session.clearName(session: Session, p: number)
	local seat = session.seats[p]
	if seat == nil or seat.customName == nil then
		return
	end
	seat.customName = nil
	for _, other in session.seats do
		other.shownNames[p] = nil
	end
	if session.stage ~= "Over" then
		broadcast(session)
	end
end

-- A player takes one chunk of their time bank during a Plan stage.
function Session.bank(session: Session, p: number, step: any, now: number): (boolean, string?)
	local stale = checkStep(session, step)
	if stale then
		return false, stale
	end
	local seat = session.seats[p]
	local config = session.config
	if session.stage ~= "Input" or session.match.phase ~= "Plan" or seat.locked then
		return false, Session.Reason.NotInput
	end
	if seat.bank < config.TIME_BANK_CHUNK or now > seatDeadline(session, seat) then
		return false, Session.Reason.NoBank
	end
	seat.bank -= config.TIME_BANK_CHUNK
	seat.bankUsed += config.TIME_BANK_CHUNK
	broadcast(session)
	return true, nil
end

-- A player asks to skip the resolve animation or election night. The stage ends
-- early only once every connected seat has asked.
function Session.skip(session: Session, p: number, step: any, now: number): (boolean, string?)
	local stale = checkStep(session, step)
	if stale then
		return false, stale
	end
	local config = session.config
	-- Draft reveals, the debate's intro and its clashes are short and not
	-- skippable; its verdict is (D-072).
	local resolving = session.stage == "Reveal" and session.reveal == "Resolve"
	local verdict = session.stage == "Reveal" and session.reveal == "Verdict"
	local election = session.stage == "Show" and session.match.phase == "Election"
	if not resolving and not verdict and not election then
		return false, Session.Reason.NotSkippable
	end
	session.seats[p].skip = true
	local all = true
	for _, seat in session.seats do
		if seat.connected and not seat.skip then
			all = false
		end
	end
	if all then
		session.skippedTo = if election or verdict
			then now
			else math.min(session.deadline, session.stageStart + config.TIMER_RESOLVE_SKIPPED)
	end
	broadcast(session)
	Session.update(session, now)
	return true, nil
end

-- ---------------------------------------------------------------- connection

-- A player left. They get a grace period (if any are left) before their inputs
-- are auto-submitted; the others are told at once.
function Session.disconnect(session: Session, p: number, now: number)
	local seat = session.seats[p]
	if not seat.connected or session.stage == "Over" then
		return
	end
	seat.connected = false
	if beforeWeekOne(session) then
		seat.leftEarly = true
	end
	-- A debate spends at most one grace use (D-072): a second drop in the same
	-- debate gets canned answers straight away. The debate starts with its intro:
	-- a drop during the week's reveal before it (already phase Debate) is not one.
	local week = session.match.week
	local debating = session.match.phase == "Debate"
		and session.introWeek == week
		and session.reveal ~= "Resolve"
	local spentThisDebate = debating and seat.debateGraceWeek == week
	if seat.graceLeft > 0 and not spentThisDebate then
		seat.graceLeft -= 1
		seat.graceUntil = now + session.config.DISCONNECT_GRACE
		if debating then
			seat.debateGraceWeek = week
		end
	else
		seat.graceUntil = now
	end
	notify(session, p, "OpponentDisconnected")
	broadcast(session)
	Session.update(session, now)
end

-- A player came back: they get the current state straight away.
function Session.reconnect(session: Session, p: number, now: number)
	local seat = session.seats[p]
	seat.connected = true
	seat.graceUntil = nil
	seat.leftEarly = false
	if session.stage == "Input" and not seat.locked then
		-- Grace can hold a stage open past this seat's deadline. Give the returning
		-- player a fair window to act instead of closing it with their default.
		local needed = now + session.config.RECONNECT_WINDOW - session.deadline
		seat.bankUsed = math.max(seat.bankUsed, needed)
	end
	notify(session, p, "OpponentReconnected")
	broadcast(session)
	Session.update(session, now)
end

-- A player chose to leave (D-059): the match ends at once as a forfeit, won by
-- the other seat (with more than two, by everyone else), the same result as
-- missing FORFEIT_MISSED_WEEKS weeks. Before week 1 begins it is unrated
-- (D-075). The others are told why. Returns (false, "Over") once the match has
-- ended, so a repeated request changes nothing.
function Session.forfeit(session: Session, p: number, now: number): (boolean, string?)
	if session.stage == "Over" then
		return false, Session.Reason.Over
	end
	forfeitBy(session, now, { [p] = true }, beforeWeekOne(session))
	notify(session, p, Session.OPPONENT_FORFEITED)
	broadcast(session)
	return true, nil
end

-- Ends the match as abandoned, whatever state it is in. The server calls this
-- when a Session call throws, so a broken match can't hold its players forever.
function Session.abort(session: Session, now: number)
	if session.stage == "Over" then
		return
	end
	finish(session, now, { winner = 0, reason = "Abandoned" })
	broadcast(session)
end

-- Seat index for a player id, or nil.
function Session.seatOf(session: Session, id: string): number?
	for p, seat in session.seats do
		if seat.id == id then
			return p
		end
	end
	return nil
end

return table.freeze(Session)
