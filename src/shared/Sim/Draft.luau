--!strict
-- The state draft (D-007, D-009, D-044). Strongholds are not drafted: when the
-- map is revealed each player is given their STRONGHOLD_COUNT strongest-leaning
-- states (Draft.assignStrongholds), so both see them before any pick. Then the
-- blind rounds: round 0 picks home states, the next NOMINATION_ROUNDS nominate
-- battlegrounds. Every round each player submits a ranked top 2; on a clash the
-- round's priority player gets their choice and the other falls back.
-- Bonuses are applied once, after the last round (Draft.applyBonuses).

local ConfigModule = require("./Config")
local State = require("./State")
local StateData = require("./StateData")
local Support = require("./Support")

type Config = ConfigModule.Config
type MatchState = State.MatchState

export type Kind = "Home" | "Nominate"

local Draft = {}

Draft.CHOICES = 2 -- ranked choices per round

function Draft.rounds(config: Config): number
	return 1 + config.NOMINATION_ROUNDS
end

function Draft.kind(_config: Config, round: number): Kind
	if round == 0 then
		return "Home"
	end
	return "Nominate"
end

-- Player p's strongholds-to-be: the states leaning toward p, strongest lean
-- first, then the bigger state, then by id; at most STRONGHOLD_COUNT. Each
-- player's list comes only from their own leans, so the order players are served
-- in cannot matter (D-001), and leans come in mirrored pairs (D-008), so in a 1v1
-- both lists hold the same lean magnitudes.
function Draft.strongholdsFor(config: Config, match: MatchState, p: number): { string }
	local list: { number } = {}
	for i, s in match.states do
		if s.leanTo == p and s.lean > 0 and s.owner == nil and not s.battleground then
			table.insert(list, i)
		end
	end
	table.sort(list, function(a, b)
		local sa, sb = match.states[a], match.states[b]
		if sa.lean ~= sb.lean then
			return sa.lean > sb.lean
		end
		if sa.ev ~= sb.ev then
			return sa.ev > sb.ev
		end
		return sa.id < sb.id
	end)
	local ids = {}
	for k = 1, math.min(config.STRONGHOLD_COUNT, #list) do
		ids[k] = match.states[list[k]].id
	end
	return ids
end

-- Gives every player their strongholds (D-044). Called once, when Select ends,
-- so the map reveal and every draft round show them.
function Draft.assignStrongholds(config: Config, match: MatchState)
	local chosen = {}
	for p in match.players do
		chosen[p] = Draft.strongholdsFor(config, match, p)
	end
	for p, ids in chosen do
		local player = match.players[p]
		for _, id in ids do
			State.get(match, id).owner = p
			table.insert(player.strongholds, id)
		end
	end
end

-- Can player p take this state in this round? A home needs a state nobody owns
-- (not a stronghold); nominations need a state that is not a home and not already
-- a battleground (any player's stronghold is fair game, D-007).
function Draft.isLegal(config: Config, match: MatchState, _p: number, round: number, id: string): boolean
	local i = State.indexOf[id]
	if i == nil then
		return false
	end
	local s = match.states[i]
	if Draft.kind(config, round) == "Nominate" then
		return not s.isHome and not s.battleground
	end
	return s.owner == nil and not s.battleground
end

-- Player who has clash priority this round.
function Draft.priorityPlayer(config: Config, match: MatchState, round: number): number
	local slot = config.DRAFT_PRIORITY[round + 1]
	if slot == 1 then
		return match.priorityA
	end
	-- "B" in a two-player match is the other player; with more players, the next one.
	return match.priorityA % #match.players + 1
end

-- Validates one player's submission: { choices = { id, id? } }. Returns the choice
-- list on success, or a reason code.
function Draft.validate(
	config: Config,
	match: MatchState,
	p: number,
	input: any
): (boolean, string?, { string }?)
	if match.phase ~= "Draft" then
		return false, "WrongPhase", nil
	end
	if type(input) ~= "table" or type(input.choices) ~= "table" then
		return false, "BadShape", nil
	end
	local raw = input.choices
	local count = 0
	for key in raw do
		if type(key) ~= "number" then
			return false, "BadShape", nil
		end
		count += 1
	end
	if count < 1 or count > Draft.CHOICES or #raw ~= count then
		return false, "BadChoiceCount", nil
	end
	local choices = {}
	for _, id in raw do
		if type(id) ~= "string" or State.indexOf[id] == nil then
			return false, "UnknownState", nil
		end
		if table.find(choices, id) then
			return false, "DuplicateChoice", nil
		end
		if not Draft.isLegal(config, match, p, match.draftRound, id) then
			return false, "IllegalChoice", nil
		end
		table.insert(choices, id)
	end
	return true, nil, choices
end

-- States sorted for auto-fill: platform matches first, then by EV, then id.
-- Nominations never auto-fill the player's own strongholds.
local function fillOrder(config: Config, match: MatchState, p: number, round: number): { string }
	local platform = match.players[p].platform
	local nominating = Draft.kind(config, round) == "Nominate"
	local list = {}
	for i, record in StateData.list do
		local s = match.states[i]
		local own = nominating and s.owner == p
		if not own and Draft.isLegal(config, match, p, round, record.id) then
			table.insert(list, record)
		end
	end
	local function matches(record): boolean
		for _, issue in record.issues do
			if table.find(platform, issue) then
				return true
			end
		end
		return false
	end
	table.sort(list, function(a, b)
		local ma, mb = matches(a), matches(b)
		if ma ~= mb then
			return ma
		end
		if a.ev ~= b.ev then
			return a.ev > b.ev
		end
		return a.id < b.id
	end)
	local ids = {}
	for k, record in list do
		ids[k] = record.id
	end
	return ids
end

-- Pads a choice list to Draft.CHOICES with the auto-fill order.
function Draft.autofill(config: Config, match: MatchState, p: number, choices: { string }): { string }
	local filled = table.clone(choices)
	for _, id in fillOrder(config, match, p, match.draftRound) do
		if #filled >= Draft.CHOICES then
			break
		end
		if not table.find(filled, id) then
			table.insert(filled, id)
		end
	end
	return filled
end

-- Resolves the current round from every player's choices (already validated and
-- auto-filled). Players are served in priority order; each takes their best choice
-- not already taken this round. Returns the picks made, in priority order.
function Draft.resolveRound(
	config: Config,
	match: MatchState,
	choices: { [number]: { string } }
): { State.DraftPick }
	local round = match.draftRound
	local kind: Kind = Draft.kind(config, round)
	local first = Draft.priorityPlayer(config, match, round)
	local n = #match.players
	local taken: { [string]: boolean } = {}
	local picks: { State.DraftPick } = {}
	for k = 0, n - 1 do
		local p = (first - 1 + k) % n + 1
		local pick: string? = nil
		for _, id in choices[p] do
			if not taken[id] then
				pick = id
				break
			end
		end
		if pick == nil then
			for _, id in fillOrder(config, match, p, round) do
				if not taken[id] then
					pick = id
					break
				end
			end
		end
		assert(pick, "no legal draft state left")
		taken[pick] = true
		table.insert(picks, { round = round, player = p, state = pick, kind = kind })
	end

	for _, pick in picks do
		local s = State.get(match, pick.state)
		local player = match.players[pick.player]
		if kind == "Home" then
			s.owner = pick.player
			s.isHome = true
			player.home = pick.state
			player.location = pick.state
		else
			s.battleground = true
			table.insert(player.nominations, pick.state)
		end
		table.insert(match.draftLog, pick)
	end
	return picks
end

-- Applies home and stronghold bonuses (battlegrounds keep only their lean). Uses
-- the normal gain split, without saturation or multipliers.
function Draft.applyBonuses(config: Config, match: MatchState)
	for _, s in match.states do
		local owner = s.owner
		if owner ~= nil and not s.battleground then
			local big = s.ev >= config.BIG_STATE_EV
			local bonus
			if s.isHome then
				bonus = if big then config.HOME_BONUS_BIG else config.HOME_BONUS
			else
				bonus = if big then config.STRONGHOLD_BONUS_BIG else config.STRONGHOLD_BONUS
			end
			Support.gain(config, s, owner, bonus)
		end
	end
end

return table.freeze(Draft)
