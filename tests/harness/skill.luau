--!strict
-- Skill check for Choice stances (D-039, D-041) and debate moves (D-072):
-- the standard bot against the same bot deciding at random, seats alternating,
-- two different candidates per match. Prints the random style's win rate with
-- its 95% band.
--
--   lune run tests/harness/skill.luau            -- 2,000 matches, RandomStance
--   lune run tests/harness/skill.luau 4000 STANCE_POINTS=2   -- more matches, a Config variant
--   lune run tests/harness/skill.luau RandomMove DEBATE_ROUND_WIN=1.2   -- the debate check
--   (also NoAnswer, AlwaysDefend, AlwaysAttack, AlwaysPivot)

local process = require("@lune/process")

local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Play = require("@testlib/Play")
local Rng = require("@sim/Rng")

local N = 2000
local style = "RandomStance"
local changes: { [string]: any } = {}
for _, arg in process.args do
	local key, value = string.match(arg, "^([%u_]+)=(.+)$")
	if key and value then
		changes[key] = tonumber(value) or value
	elseif tonumber(arg) then
		N = tonumber(arg) :: number
	elseif
		arg == "RandomStance"
		or arg == "RandomMove"
		or arg == "NoAnswer"
		or arg == "AlwaysDefend"
		or arg == "AlwaysAttack"
		or arg == "AlwaysPivot"
	then
		style = arg
	end
end
local config = Config.with(Config.defaults, changes)

local ids = Candidates.ids
local function pairFor(seed: number): { string }
	local rng = Rng.new(seed * 977 + 13)
	local a = Rng.nextInt(rng, 1, #ids)
	local b = Rng.nextInt(rng, 1, #ids - 1)
	if b >= a then
		b += 1
	end
	return { ids[a], ids[b] }
end

local wins = 0
local started = os.clock()
for k = 1, N do
	local seed = 200000 + k
	local styles = if k % 2 == 0 then { style, "Balanced" } else { "Balanced", style }
	local slot = if k % 2 == 0 then 1 else 2
	local r = Play.match(config, seed, pairFor(seed), styles :: any)
	if r.winner == slot then
		wins += 1
	end
end
local variant = {}
for key, value in changes do
	table.insert(variant, `{key}={value}`)
end
print(if #variant > 0 then "Config variant: " .. table.concat(variant, " ") else "Config: defaults")
print(
	string.format(
		"%s win rate over %d matches: %.1f%% (+/- %.1f at 95%%), %.0fs",
		style,
		N,
		100 * wins / N,
		100 * 1.96 * math.sqrt(0.25 / N),
		os.clock() - started
	)
)
