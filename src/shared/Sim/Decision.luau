--!strict
-- The Decision phase (D-044): one focused input with its own timer before the
-- week's plan, in any week that asks for a debate focus or a Choice stance.
--
-- Order inside a week:
--   debate week:  Decision "Focus" -> Debate -> [Decision "Stance"] -> Plan
--   Choice week:  Decision "Stance" -> Plan
--   other weeks:  Plan
-- The focus is chosen right before the debate it feeds; a stance is chosen after
-- any debate of the same week, so the republished polls are on the table.
--
-- Payloads: { focus = <one of this debate's topics> } in a Focus decision,
-- { choice = "A"|"B"|"C" } in a Stance decision. Like plans, a payload is
-- rejected whole with a reason code (Plan.Reason) and never throws; a valid one
-- comes back normalized. Whoever sends nothing gets the default: no focus (every
-- topic lost is then a gaffe, Sim/Debate), the hedge (C).
--
-- Hidden: the focus lives in PlayerState.debateFocus until the debate resolves,
-- the stance in PlayerState.stance until the week resolves. View shows each
-- player only their own.

local ConfigModule = require("./Config")
local Events = require("./Events")
local Plan = require("./Plan")
local State = require("./State")
local Types = require("../Types")

type Config = ConfigModule.Config
type MatchState = State.MatchState

export type Kind = State.DecisionKind

export type Input = {
	focus: Types.Issue?, -- Focus decisions (nil = no focus, only ever the default)
	choice: Types.Choice?, -- Stance decisions
}

local Decision = {}

local R = Plan.Reason

-- The decision that opens `week`, before anything else happens in it.
function Decision.opening(config: Config, match: MatchState, week: number): Kind?
	if table.find(config.DEBATE_WEEKS, week) then
		return "Focus"
	end
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
	if match.decision == "Focus" then
		if input.choice ~= nil then
			return false, R.UnexpectedChoice, nil
		end
		local topics = match.debateTopics[match.week]
		local focus = input.focus
		if type(focus) ~= "string" or topics == nil or table.find(topics, focus :: Types.Issue) == nil then
			return false, R.BadFocus, nil
		end
		return true, nil, { focus = focus :: Types.Issue, choice = nil }
	end
	if input.focus ~= nil then
		return false, R.UnexpectedFocus, nil
	end
	if not Events.isChoice(input.choice) then
		return false, R.BadChoice, nil
	end
	return true, nil, { focus = nil, choice = input.choice :: Types.Choice }
end

-- What player p gets if they send nothing: no focus, or the hedge.
function Decision.default(_config: Config, match: MatchState, _p: number): Input
	if match.decision == "Focus" then
		return { focus = nil, choice = nil }
	end
	return { focus = nil, choice = Events.defaultChoice() }
end

-- Stores every player's (normalized) decision on the hidden player state.
-- Mutates `match`.
function Decision.apply(_config: Config, match: MatchState, inputs: { Input })
	for p, player in match.players do
		local input = inputs[p]
		if match.decision == "Focus" then
			player.debateFocus = input.focus
		else
			player.stance = input.choice or Events.defaultChoice()
		end
	end
end

return table.freeze(Decision)
