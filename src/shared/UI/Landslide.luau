--!strict
-- The Landslide moment on Results (docs/DESIGN.md D-062): whether to show it
-- and its words, from the player's own View and the match result. Pure.
--
--   Landslide.moment(config, view, result, names) -> Moment?
--
-- Nil unless the match was decided on election night and its winner took
-- strictly more than LANDSLIDE_EV_SHARE of the votes in play
-- (Sim/Election.landslide). Both players get it: the winner's is theirs
-- ("YOU WON BY A" / LANDSLIDE), the loser's names the rival ("REX WON BY A").

local ConfigModule = require("../Sim/Config")
local Election = require("../Sim/Election")
local Session = require("../Net/Session")
local StateData = require("../Sim/StateData")
local ViewModule = require("../Sim/View")

type Config = ConfigModule.Config
type View = ViewModule.View

local Landslide = {}

Landslide.STAMP = "LANDSLIDE" -- the stamp's text, for both players

export type Moment = {
	winner: number, -- the landslide winner's player id (their color colors the stamp)
	mine: boolean, -- the viewer won it
	eyebrow: string, -- over the stamp: "You won by a" / "Rex won by a"
	stamp: string, -- Landslide.STAMP
	line: string, -- under it: "You took 412 of 538 votes, over 70%."
}

function Landslide.moment(config: Config, view: View, result: Session.Result?, names: { string }): Moment?
	local election = view.election
	if result == nil or result.reason ~= "Election" or election == nil then
		return nil
	end
	local winner = Election.landslide(config, election)
	if winner == nil or winner ~= result.winner then
		return nil
	end
	local total = 0
	for _, r in election.results do
		local record = StateData.byId[r.state]
		if record then
			total += record.ev
		end
	end
	local mine = winner == view.you
	local who = if mine then "You" else names[winner] or "Your opponent"
	local share = math.floor(100 * config.LANDSLIDE_EV_SHARE + 0.5)
	return {
		winner = winner,
		mine = mine,
		eyebrow = `{who} won by a`,
		stamp = Landslide.STAMP,
		line = `{who} took {election.ev[winner]} of {total} votes, over {share}%.`,
	}
end

return table.freeze(Landslide)
