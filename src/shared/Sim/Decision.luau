--!strict
-- The Decision phase (D-044): one focused input with its own timer before the
-- week's plan, in any week that asks for a Choice stance.
--
-- Order inside a week:
--   debate week:  Debate (three live rounds, Sim/Debate, D-072) -> [Decision "Stance"] -> Plan
--   Choice week:  Decision "Stance" -> Plan
--   other weeks:  Plan
-- A stance is chosen after any debate of the same week, so the republished
-- polls are on the table. (A debate used to open with a "Focus" decision; live
-- rounds replaced it, D-072.)
--
-- Payload: { choice = "A"|"B"|"C" }. Like plans, a payload is rejected whole
-- with a reason code (Plan.Reason) and never throws; a valid one comes back
-- normalized. Whoever sends nothing gets the default: the hedge (C).
--
-- Hidden: the stance lives in PlayerState.stance until the week resolves. View
-- shows each player only their own.

local ConfigModule = require("./Config")
local Events = require("./Events")
local Plan = require("./Plan")
local State = require("./State")
local Types = require("../Types")

type Config = ConfigModule.Config
type MatchState = State.MatchState

export type Kind = State.DecisionKind

export type Input = {
	choice: Types.Choice?, -- Stance decisions
}

local Decision = {}

local R = Plan.Reason

-- The decision that opens `week`, before anything else happens in it.
function Decision.opening(_config: Config, match: MatchState, week: number): Kind?
	local event = Events.at(match, week)
	if event ~= nil and event.kind == "Choice" then
		return "Stance"
	end
	return nil
end

-- The decision that follows this week's debate (nil: straight to the plan).
function Decision.afterDebate(match: MatchState): Kind?
	return if Events.isChoiceWeek(match) then "Stance" else nil
end

-- Validates player p's decision. Returns (true, nil, input) with a normalized
-- input, or (false, reason, nil).
function Decision.validate(
	_config: Config,
	match: MatchState,
	_p: number,
	input: any
): (boolean, string?, Input?)
	if match.phase ~= "Decision" or match.decision == nil then
		return false, R.WrongPhase, nil
	end
	if type(input) ~= "table" then
		return false, R.BadShape, nil
	end
	if input.focus ~= nil then
		return false, R.UnexpectedFocus, nil
	end
	if input.move ~= nil then
		return false, R.UnexpectedMove, nil
	end
	if not Events.isChoice(input.choice) then
		return false, R.BadChoice, nil
	end
	return true, nil, { choice = input.choice :: Types.Choice }
end

-- What player p gets if they send nothing: the hedge.
function Decision.default(_config: Config, _match: MatchState, _p: number): Input
	return { choice = Events.defaultChoice() }
end

-- Stores every player's (normalized) decision on the hidden player state.
-- Mutates `match`.
function Decision.apply(_config: Config, match: MatchState, inputs: { Input })
	for p, player in match.players do
		player.stance = inputs[p].choice or Events.defaultChoice()
	end
end

return table.freeze(Decision)
