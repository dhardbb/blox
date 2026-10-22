--!strict
-- Realistic State payloads for each screen, made by playing a real Session with
-- bots up to the wanted moment. Screens render these in DEBUG_UI mode (no server
-- needed) and the UI specs use them. Deterministic by seed.

local Bot = require("../Sim/Bot")
local ConfigModule = require("../Sim/Config")
local Rng = require("../Sim/Rng")
local Session = require("../Net/Session")
local View = require("../Sim/View")

type Config = ConfigModule.Config

export type Moment =
	"Select" -- character select, nothing chosen yet
	| "MapReveal" -- leans shown
	| "Draft" -- a draft round in progress, some picks made
	| "Plan" -- week 3 plan, with history behind it
	| "Resolve" -- the resolve animation after week 3
	| "DebatePrep" -- the week before a debate (prep due)
	| "Debate" -- the debate sequence
	| "Election" -- election night
	| "Over" -- the result

local Fixtures = {}

Fixtures.MOMENTS = table.freeze({
	"Select",
	"MapReveal",
	"Draft",
	"Plan",
	"Resolve",
	"DebatePrep",
	"Debate",
	"Election",
	"Over",
} :: { Moment })

local function reached(session: Session.Session, moment: Moment): boolean
	local phase = session.match.phase
	local stage = session.stage
	if moment == "Select" then
		return phase == "Select"
	elseif moment == "MapReveal" then
		return phase == "MapReveal"
	elseif moment == "Draft" then
		return phase == "Draft" and session.match.draftRound == 3 and stage == "Input"
	elseif moment == "Plan" then
		return phase == "Plan" and session.match.week == 3 and stage == "Input"
	elseif moment == "Resolve" then
		return session.reveal == "Resolve" and session.match.week == 4
	elseif moment == "DebatePrep" then
		return phase == "Plan" and session.match.week == 8 and stage == "Input"
	elseif moment == "Debate" then
		return session.reveal == "Debate"
	elseif moment == "Election" then
		return phase == "Election" and stage == "Show"
	end
	return stage == "Over"
end

-- The payload seat 1 would receive at `moment`. Seat 1 is played by the bot too,
-- as candidate `candidate` (default Dana Okafor) against Rex Calloway.
function Fixtures.payload(
	config: Config,
	moment: Moment,
	seed: number?,
	candidate: string?
): Session.StatePayload
	local s = seed or 7
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
	error(`fixture never reached {moment}`)
end

-- A lobby status for the lobby screen.
function Fixtures.lobby(state: ("Idle" | "Queued" | "Hosting")?): any
	return {
		state = state or "Idle",
		code = if state == "Hosting" then "AB3CD" else nil,
		queued = if state == "Queued" then 1 else 0,
		full = false,
	}
end

return table.freeze(Fixtures)
