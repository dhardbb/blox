--!strict
-- Seeded public state leans (D-008): terrain for the draft, never real partisanship.
--
-- LEAN_STATE_COUNT states are chosen, sorted by EV and walked in pairs; each pair
-- shares one magnitude (LEAN_MIN..LEAN_MAX, capped for big states) with the two
-- sides assigned at random. The whole draw is rerolled while any player's
-- EV-weighted lean total differs from another's by more than LEAN_MAX_EV_IMBALANCE.

local ConfigModule = require("./Config")
local Rng = require("./Rng")
local StateData = require("./StateData")

type Config = ConfigModule.Config

export type Lean = { lean: number, leanTo: number? }

local Leans = {}

local MAX_ATTEMPTS = 1000

-- One draw. Returns leans by state index and the EV-weighted total per player.
local function draw(config: Config, rng: Rng.Rng, players: number): ({ Lean }, { number })
	local leans: { Lean } = {}
	for i = 1, #StateData.list do
		leans[i] = { lean = 0, leanTo = nil }
	end
	local order = {}
	for i = 1, #StateData.list do
		order[i] = i
	end
	Rng.shuffle(rng, order)
	local chosen = table.move(order, 1, config.LEAN_STATE_COUNT, 1, {})
	table.sort(chosen, function(a, b)
		local ra, rb = StateData.list[a], StateData.list[b]
		if ra.ev ~= rb.ev then
			return ra.ev < rb.ev
		end
		return ra.id < rb.id
	end)

	local weighted = table.create(players, 0)
	for k = 1, #chosen - 1, 2 do
		local a, b = chosen[k], chosen[k + 1]
		local big = StateData.list[a].ev >= config.BIG_STATE_EV or StateData.list[b].ev >= config.BIG_STATE_EV
		local cap = if big then config.LEAN_BIG_STATE_CAP else config.LEAN_MAX
		local magnitude = Rng.nextInt(rng, config.LEAN_MIN, math.max(config.LEAN_MIN, cap))
		local first = Rng.nextInt(rng, 1, players)
		local second = Rng.nextInt(rng, 1, players - 1)
		if second >= first then
			second += 1
		end
		leans[a] = { lean = magnitude, leanTo = first }
		leans[b] = { lean = magnitude, leanTo = second }
		weighted[first] += magnitude * StateData.list[a].ev
		weighted[second] += magnitude * StateData.list[b].ev
	end
	return leans, weighted
end

-- Leans by state index (StateData.list order) for a match with `players` players.
function Leans.generate(config: Config, rng: Rng.Rng, players: number): { Lean }
	assert(players >= 2, "leans need at least two players")
	for _ = 1, MAX_ATTEMPTS do
		local leans, weighted = draw(config, rng, players)
		local lo, hi = math.huge, -math.huge
		for _, w in weighted do
			lo, hi = math.min(lo, w), math.max(hi, w)
		end
		if hi - lo <= config.LEAN_MAX_EV_IMBALANCE then
			return leans
		end
	end
	error("could not draw balanced leans")
end

-- Starting support for a state with lean L toward one player: that player gets
-- +L/2, the others share -L/2, undecided stays BASE_UNDECIDED. With two players
-- the base is BASE_SUPPORT each.
function Leans.startingSupport(config: Config, lean: Lean, players: number): { number }
	local support = table.create(players, (100 - config.BASE_UNDECIDED) / players)
	local leanTo = lean.leanTo
	if leanTo ~= nil and lean.lean > 0 then
		for p = 1, players do
			if p == leanTo then
				support[p] += lean.lean / 2
			else
				support[p] -= lean.lean / 2 / (players - 1)
			end
		end
	end
	return support
end

return table.freeze(Leans)
