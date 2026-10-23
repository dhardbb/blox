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
-- Stages: "Input" (players submit for a Select, Draft, Decision or Plan phase;
-- a Decision has its own TIMER_DECISION and no reveal after it, D-044), "Show"
-- (map reveal, election night), "Reveal" (draft reveal, resolve animation,
-- debate sequence), "Over". Every stage change bumps `step`; clients stamp each
-- request with the step they saw, and stale requests are rejected.

local Bot = require("../Sim/Bot")
local ConfigModule = require("../Sim/Config")
local Match = require("../Sim/Match")
local Rng = require("../Sim/Rng")
local State = require("../Sim/State")
local View = require("../Sim/View")

type Config = ConfigModule.Config

export type SeatKind = "Human" | "Bot"
export type Stage = "Input" | "Show" | "Reveal" | "Over"
export type RevealKind = "Draft" | "Resolve" | "Debate"
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
	prePick: any?, -- lobby pre-pick, used if Select times out
	botCandidate: string?,
	botStyle: Bot.Style?,
	botRng: Rng.Rng?,
}

export type Result = {
	winner: number, -- seat index, 0 if nobody (abandoned)
	reason: Reason,
}

export type SeatInfo = {
	id: string,
	kind: SeatKind,
	connected: boolean,
	locked: boolean,
	skip: boolean,
	bank: number,
	graceUntil: number?,
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
}

-- Match options a private lobby may set (public queue and practice use none).
export type Options = {
	events: boolean?, -- false: no event deck this match (D-027)
}

export type SeatSpec = {
	id: string,
	kind: SeatKind,
	prePick: any?, -- Human: optional lobby pre-pick
	candidate: string?, -- Bot: candidate to play
	style: Bot.Style?, -- Bot: play style
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
})

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
		}
	end
	local deadline = if session.stage == "Input"
		then seatDeadline(session, session.seats[p])
		else session.skippedTo or session.deadline
	local view = View.build(session.config, session.match, p)
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

local enterPhase: (session: Session, now: number) -> ()

-- Advances the simulation one phase with the given inputs and keeps its events.
local function advance(session: Session, inputs: { [number]: any })
	local nextMatch, events = Match.advance(session.config, session.match, inputs)
	session.match = nextMatch
	session.events = events
end

-- Bots submit as soon as an Input stage opens, from their own View.
local function botInputs(session: Session)
	for p, seat in session.seats do
		if isBot(seat) then
			local view = View.build(session.config, session.match, p)
			local rng = seat.botRng :: Rng.Rng
			local input = Bot.act(session.config, view, rng, seat.botCandidate or "okafor", seat.botStyle)
			local ok, _, normalized = Match.validate(session.config, session.match, p, input)
			seat.input = if ok then normalized else nil
			seat.locked = true
		end
	end
end

enterPhase = function(session: Session, now: number)
	local config = session.config
	local phase = session.match.phase
	if phase == "Select" or phase == "Draft" or phase == "Decision" or phase == "Plan" then
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
	elseif phase == "Debate" then
		advance(session, {})
		setStage(session, "Reveal", now, config.TIMER_DEBATE)
		session.reveal = "Debate"
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
			inputs[p] = seat.prePick
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
		for p, seat in session.seats do
			if seat.missed >= config.FORFEIT_MISSED_WEEKS then
				local winner = if p == 1 then 2 else 1
				finish(session, now, { winner = winner, reason = "Forfeit" })
				broadcast(session)
				return
			end
		end
	end

	local reveal = if phase == "Draft"
		then config.DRAFT_REVEAL
		elseif phase == "Plan" then config.TIMER_RESOLVE
		else 0
	if reveal > 0 then
		setStage(session, "Reveal", now, reveal)
		session.reveal = if phase == "Draft" then "Draft" else "Resolve"
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
	local seats: { Seat } = {}
	for p, spec in specs do
		ids[p] = spec.id
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
			prePick = spec.prePick,
			botCandidate = spec.candidate,
			botStyle = spec.style,
			botRng = if spec.kind == "Bot" then Rng.new(seed * 31 + p) else nil,
		}
	end
	local session: Session = {
		id = id,
		config = config,
		match = Match.new(config, seed, ids),
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
	}
	enterPhase(session, now)
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
	-- Draft reveals and debates are short and not skippable.
	local resolving = session.stage == "Reveal" and session.reveal == "Resolve"
	local election = session.stage == "Show" and session.match.phase == "Election"
	if not resolving and not election then
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
		session.skippedTo = if election
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
	if seat.graceLeft > 0 then
		seat.graceLeft -= 1
		seat.graceUntil = now + session.config.DISCONNECT_GRACE
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
