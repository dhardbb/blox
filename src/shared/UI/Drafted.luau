--!strict
-- What a player's draft amounts to, from one View. Pure.
--
-- A nominated state loses every draft bonus and becomes a battleground (PLAN.md
-- "Battlegrounds", D-007), but it stays in its drafter's `strongholds` list. So a
-- stronghold someone nominated is listed apart: it no longer counts as one
-- (playtest 1).

local ViewModule = require("../Sim/View")

type View = ViewModule.View

local Drafted = {}

export type Nominated = { state: string, by: number } -- `by`: the player who nominated it

local function stateView(view: View, id: string): ViewModule.StateView?
	for _, s in view.states do
		if s.id == id then
			return s
		end
	end
	return nil
end

-- Who nominated state `id` (the first nominator if several), or nil.
function Drafted.nominatedBy(view: View, id: string): number?
	for q, player in view.players do
		if table.find(player.nominations, id) then
			return q
		end
	end
	return nil
end

-- Player p's strongholds that still count, and the ones that were nominated
-- (each with who nominated it), both in draft order.
function Drafted.strongholds(view: View, p: number): ({ string }, { Nominated })
	local active, nominated = {}, {}
	for _, id in view.players[p].strongholds do
		local s = stateView(view, id)
		if s ~= nil and s.battleground then
			table.insert(nominated, { state = id, by = Drafted.nominatedBy(view, id) or 0 })
		else
			table.insert(active, id)
		end
	end
	return active, nominated
end

local function list(ids: { string }): string
	return if #ids > 0 then table.concat(ids, " ") else "none"
end

-- "strongholds MI GA NJ; nominated by the opponent: IL NC (now battlegrounds, no
-- bonus); battlegrounds nominated by you: FL NY" from player p's point of view
-- of `view.you`.
function Drafted.summary(view: View, p: number): string
	local active, nominated = Drafted.strongholds(view, p)
	local byOpponent, byYou = {}, {}
	for _, entry in nominated do
		table.insert(if entry.by == p then byYou else byOpponent, entry.state)
	end
	local whose = if p == view.you then "you" else "them"
	local other = if p == view.you then "the opponent" else "you"
	local text = `strongholds {list(active)}`
	if #byOpponent > 0 then
		text ..= `; nominated by {other}: {list(byOpponent)} (now battlegrounds, no bonus)`
	end
	if #byYou > 0 then
		text ..= `; own strongholds nominated by {whose}: {list(byYou)} (no bonus)`
	end
	return text .. `; battlegrounds nominated by {whose}: {list(view.players[p].nominations)}`
end

return table.freeze(Drafted)
