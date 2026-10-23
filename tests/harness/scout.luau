--!strict
-- Scouting check for D-049 (polls reveal ground game): the standard bot against
-- the same bot that never buys internal polls, seats alternating, two different
-- candidates per match. Prints the NeverPoll win rate with its 95% band, what
-- each side spent on polls and ground game, and how often a poll caught some.
--
--   lune run tests/harness/scout.luau                         -- 2,000 matches
--   lune run tests/harness/scout.luau 1000 GOTV_PER_UNIT=1.2  -- a Config variant
--   lune run tests/harness/scout.luau 1000 bot.scoutPolls=3   -- a Bot.tuning variant

local process = require("@lune/process")

local Bot = require("@sim/Bot")
local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Play = require("@testlib/Play")
local Rng = require("@sim/Rng")

local N = 2000
local changes: { [string]: any } = {}
local variant = {}
for _, arg in process.args do
	local key, value = string.match(arg, "^([%u_]+)=(.+)$")
	local tuning, tuned = string.match(arg, "^bot%.(%w+)=(.+)$")
	if key and value then
		changes[key] = tonumber(value) or value
		table.insert(variant, arg)
	elseif tuning and tuned then
		local knobs = Bot.tuning :: any
		assert(knobs[tuning] ~= nil, `unknown Bot.tuning key {tuning}`)
		knobs[tuning] = tonumber(tuned)
		table.insert(variant, arg)
	elseif tonumber(arg) then
		N = tonumber(arg) :: number
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
local spend = { poll = { 0, 0 }, gotv = { 0, 0 }, caught = { 0, 0 } } -- [1] NeverPoll, [2] Balanced
local started = os.clock()
for k = 1, N do
	local seed = 300000 + k
	local styles = if k % 2 == 0 then { "NeverPoll", "Balanced" } else { "Balanced", "NeverPoll" }
	local slot = if k % 2 == 0 then 1 else 2
	local r = Play.match(config, seed, pairFor(seed), styles :: any)
	if r.winner == slot then
		wins += 1
	end
	for side, p in { slot, 3 - slot } do
		spend.poll[side] += r.pollSpend[p] / N
		spend.gotv[side] += r.gotvSpend[p] / N
		spend.caught[side] += r.scoutedGotv[p] / N
	end
end
print(if #variant > 0 then "Variant: " .. table.concat(variant, " ") else "Config and bot: defaults")
print(
	string.format(
		"NeverPoll win rate over %d matches: %.1f%% (+/- %.1f at 95%%), target < 50%%, %.0fs",
		N,
		100 * wins / N,
		100 * 1.96 * math.sqrt(0.25 / N),
		os.clock() - started
	)
)
print(
	string.format(
		"Per player per match: polls $%.1f vs $%.1f, ground game $%.1f vs $%.1f (NeverPoll vs Balanced); the Balanced bot's polls saw their ground game in %.1f states",
		spend.poll[1],
		spend.poll[2],
		spend.gotv[1],
		spend.gotv[2],
		spend.caught[2]
	)
)
