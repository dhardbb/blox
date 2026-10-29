--!strict
-- Pure helpers for the Draft screen: which states a round allows, the top-2
-- choice slots, and the wording for headers, tags and the reveal. No UI here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)
local Draft = require(ReplicatedStorage.Shared.Sim.Draft)
local State = require(ReplicatedStorage.Shared.Sim.State)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local View = require(ReplicatedStorage.Shared.Sim.View)

type Config = ConfigModule.Config

-- The player's ranked top 2. `second` only ever exists together with `first`.
export type Choices = { first: string?, second: string? }

export type Pick = { player: number, state: string, kind: Draft.Kind }

local Logic = {}

-- Legality as the View shows it (mirrors Draft.isLegal, which needs the full match):
-- a home needs a state nobody owns (strongholds are assigned before the draft,
-- D-045), nominations any state that is not a home or already a battleground.
-- Neither may take a battleground.
function Logic.legal(kind: Draft.Kind, sv: View.StateView): boolean
	if kind == "Nominate" then
		return not sv.isHome and not sv.battleground
	end
	return sv.owner == nil and not sv.battleground
end

local function nameOf(id: string): string
	local record = StateData.byId[id]
	return if record then record.name else id
end
Logic.nameOf = nameOf

-- Why a tapped state can't be picked this round: short enough for the action
-- bar's status line ("TX: already drafted").
function Logic.reason(kind: Draft.Kind, sv: View.StateView): string
	if sv.battleground then
		return `{sv.id}: already a battleground`
	elseif kind == "Nominate" and sv.isHome then
		return `{sv.id}: a home state, can't nominate`
	elseif not sv.isHome and sv.owner ~= nil then
		return `{sv.id}: a stronghold, can't be a home`
	end
	return `{sv.id}: already drafted`
end

-- Why a tapped state can't be picked, in a full sentence with the rule behind
-- it, for the notice under the slots (D-091: playtesters were refused a rival's
-- home with only a short status line). `you` and `opponent` (a first name) say
-- whose home or stronghold it is.
function Logic.why(kind: Draft.Kind, sv: View.StateView, you: number, opponent: string): string
	local owner = sv.owner
	local whose = if owner == you then "your" else `{opponent}'s`
	if sv.battleground then
		return `{sv.id} is already a battleground. Pick another state.`
	elseif kind == "Nominate" and sv.isHome then
		return `{sv.id} is {whose} home state. Home states can't be nominated, so its home bonus is safe.`
	elseif not sv.isHome and owner ~= nil then
		return `{sv.id} is {whose} stronghold. A home must be a state nobody holds yet.`
	end
	return `{sv.id} is already drafted. Pick another state.`
end

-- A choice slot's label: the state ("WY · Wyoming"), or what goes there.
function Logic.slotText(slot: number, id: string?): string
	if id then
		return `{id} · {nameOf(id)}`
	end
	return if slot == 1 then "Tap a state" else "Backup"
end

-- The round's kind for the header: "Home state", "Nominate".
function Logic.title(kind: Draft.Kind): string
	if kind == "Home" then
		return "Home state"
	end
	return "Nominate"
end

-- How the draft works, for the map reveal (three short lines, D-045).
function Logic.howItWorks(config: Config): string
	return `Strongholds come from the map: you each get your {config.STRONGHOLD_COUNT} strongest-leaning states (ringed).\nThen {Draft.rounds(
		config
	)} blind rounds: your home state, then {config.NOMINATION_ROUNDS} battlegrounds.\nEach round, a 1st choice and an optional backup. If you both want the same state, priority decides.`
end

-- "Your strongholds: MI NC VA NJ KY · theirs: GA OH WI MN IA", or nil before
-- they are assigned.
function Logic.strongholdsLine(view: View.View, you: number): string?
	local mine = view.players[you].strongholds
	local them = view.players[Logic.opponent(view)]
	local theirs = if them then them.strongholds else {}
	if #mine == 0 and #theirs == 0 then
		return nil
	end
	local function list(ids: { string }): string
		return if #ids > 0 then table.concat(ids, " ") else "none"
	end
	return `Your strongholds: {list(mine)} · theirs: {list(theirs)}`
end

-- "home state", "battleground": what a pick of this kind makes the state.
function Logic.noun(kind: Draft.Kind): string
	if kind == "Home" then
		return "home state"
	end
	return "battleground"
end

-- One line on what the pick does, from the Config numbers.
function Logic.help(config: Config, kind: Draft.Kind): string
	local big = config.BIG_STATE_EV
	if kind == "Home" then
		return `Home state: +{config.HOME_BONUS} support there (+{config.HOME_BONUS_BIG} in states with {big}+ EV), and your fundraisers there raise ×{config.HOME_FUNDRAISE_MULT} all game.`
	end
	return `Battleground: the state loses all draft bonuses, and every campaign effect there is ×{config.BATTLEGROUND_MULT}. A home state can't be nominated.`
end

-- The player who wins a clash in `round` (0-based), same rule as Draft.priorityPlayer.
-- The server leaves priorityA out until the map reveal; the Draft screen is never
-- shown before that, so the fallback only keeps the types honest.
function Logic.priorityPlayer(config: Config, view: View.View, round: number): number
	local slot = config.DRAFT_PRIORITY[round + 1]
	local a = view.priorityA or 1
	if slot == 1 then
		return a
	end
	return a % #view.players + 1
end

-- "You have priority: ties go to you" / "They have priority: ties go to them".
function Logic.priorityText(player: number, you: number): string
	if player == you then
		return "You have priority: ties go to you"
	end
	return "They have priority: ties go to them"
end

-- Priority worded for the map reveal ("in round 1") and for a finished round.
function Logic.priorityIn(player: number, you: number, round: number): string
	return `{if player == you then "You have" else "They have"} priority in round {round + 1}.`
end

function Logic.priorityWas(player: number, you: number): string
	return `{if player == you then "You" else "They"} had priority this round.`
end

-- The other seat in a 1v1.
function Logic.opponent(view: View.View): number
	for p in view.players do
		if p ~= view.you then
			return p
		end
	end
	return view.you
end

-- ---------------------------------------------------------------- choice slots

-- Applies a tap on a state. Tapping a chosen state un-picks it; otherwise it goes
-- in `target` (a slot the player aimed at), else the first empty slot, else it
-- replaces the backup.
function Logic.tap(choices: Choices, id: string, target: number?): Choices
	local first, second = choices.first, choices.second
	if first == id then
		return { first = second, second = nil }
	elseif second == id then
		return { first = first, second = nil }
	end
	if target == 1 then
		return { first = id, second = second }
	end
	if first == nil then
		return { first = id, second = nil }
	end
	return { first = first, second = id }
end

-- Empties one slot; a cleared first choice promotes the backup.
function Logic.clear(choices: Choices, slot: number): Choices
	if slot == 1 then
		return { first = choices.second, second = nil }
	end
	return { first = choices.first, second = nil }
end

-- The choices as the array the server wants: { first, second? }.
function Logic.list(choices: Choices): { string }
	local out = {}
	if choices.first then
		table.insert(out, choices.first)
		if choices.second then
			table.insert(out, choices.second)
		end
	end
	return out
end

-- ---------------------------------------------------------------- wording

-- "+3 you", "+4 them" or "even", and which player the lean favors (nil if none).
function Logic.leanText(sv: View.StateView, you: number): (string, number?)
	local to = sv.leanTo
	if to == nil or sv.lean <= 0 then
		return "even", nil
	end
	return `+{sv.lean} {if to == you then "you" else "them"}`, to
end

-- A short status for a drafted state ("your home", "their stronghold"), or nil.
function Logic.statusTag(sv: View.StateView, you: number): string?
	if sv.battleground then
		return "battleground"
	end
	local owner = sv.owner
	if owner == nil then
		return nil
	end
	local who = if owner == you then "your" else "their"
	return if sv.isHome then `{who} home` else `{who} stronghold`
end

-- Pick events of the reveal, from the server's event list.
function Logic.picks(events: { State.Event }): { Pick }
	local out: { Pick } = {}
	for _, event in events do
		local player, id, issue = event.player, event.state, event.issue
		if event.kind == "Pick" and player ~= nil and id ~= nil and issue ~= nil then
			local kind: Draft.Kind = if issue == "Home" then "Home" else "Nominate"
			table.insert(out, { player = player, state = id, kind = kind })
		end
	end
	return out
end

-- The round (0-based) the draft log ends on: the one a reveal is showing.
function Logic.lastRound(view: View.View): number?
	local best: number? = nil
	for _, pick in view.draftLog do
		if best == nil or pick.round > best then
			best = pick.round
		end
	end
	return best
end

-- When your first choice isn't what you got: say who took it.
function Logic.clashNote(
	mine: string,
	theirs: string,
	submitted: { string }?,
	theirPriority: boolean
): string?
	local first = if submitted then submitted[1] else nil
	if first == nil or mine == first or theirs ~= first then
		return nil
	end
	local reason = if theirPriority then "they had priority" else "it went to them"
	return `You both wanted {first}: {reason}, so you got {mine} instead.`
end

return Logic
