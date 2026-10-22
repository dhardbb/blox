--!strict
-- Elo ratings for rated 1v1 matches. Pure arithmetic: no state, no I/O.
-- Ratings are whole numbers. The change for one player is rounded half away
-- from zero, so the two players of a match always move by equal and opposite
-- amounts and each server can compute its own side from the same two inputs.
-- Only the rating floor (Config.ELO_FLOOR) can break that symmetry (D-028).

local ConfigModule = require("../Sim/Config")

type Config = ConfigModule.Config

local Rating = {}

-- Chance that a player rated `rating` beats one rated `opponent`, 0 to 1.
function Rating.expected(rating: number, opponent: number): number
	return 1 / (1 + 10 ^ ((opponent - rating) / 400))
end

local function roundAway(x: number): number
	if x < 0 then
		return -math.floor(-x + 0.5)
	end
	return math.floor(x + 0.5)
end

-- Whole-point change for the first player. `score` is 1 for a win, 0 for a
-- loss, 0.5 for a draw. The opponent's change is the negative of this.
function Rating.delta(config: Config, rating: number, opponent: number, score: number): number
	return roundAway(config.ELO_K * (score - Rating.expected(rating, opponent)))
end

-- The first player's rating after a decided match, floored at Config.ELO_FLOOR.
function Rating.next(config: Config, rating: number, opponent: number, won: boolean): number
	local after = rating + Rating.delta(config, rating, opponent, if won then 1 else 0)
	return math.max(config.ELO_FLOOR, after)
end

return table.freeze(Rating)
