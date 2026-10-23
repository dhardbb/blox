--!strict
-- Bot difficulty check (D-057): one difficulty against another, seats alternating,
-- two different candidates per match, every bot deciding from its own View.
-- Prints each pairing's win rate with its 95% band, and how long one bot
-- decision takes (mean, 99th percentile and worst, per difficulty and phase).
--
--   lune run tests/harness/difficulty.luau                  -- the D-057 table, 400 matches a pairing (~1 min)
--   lune run tests/harness/difficulty.luau 1000             -- the table, 1,000 a pairing
--   lune run tests/harness/difficulty.luau Hard Medium 800  -- one pairing (first named = the reported side)
--   lune run tests/harness/difficulty.luau Easy Medium BOT_EASY_NOISE=1   -- a Config variant
--
-- Targets against Medium: Easy 15-25%, Hard 60-70%, Extreme 75-85%. Seats
-- alternate and seeds are fixed (300001 on), so a run repeats exactly.

local process = require("@lune/process")

local Bot = require("@sim/Bot")
local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Match = require("@sim/Match")
local Rng = require("@sim/Rng")
local View = require("@sim/View")

local N = 400
local named: { Bot.Difficulty } = {}
local changes: { [string]: any } = {}
local variant: { string } = {}
for _, arg in process.args do
	local key, value = string.match(arg, "^([%u_]+)=(.+)$")
	if key and value then
		if value == "true" or value == "false" then
			changes[key] = value == "true"
		else
			local list = {}
			for part in string.gmatch(value, "[^,]+") do
				table.insert(list, tonumber(part))
			end
			changes[key] = if #list > 1 then table.freeze(list) else tonumber(value) or value
		end
		table.insert(variant, arg)
	elseif tonumber(arg) then
		N = tonumber(arg) :: number
	elseif table.find(Bot.DIFFICULTIES, arg) then
		table.insert(named, arg :: Bot.Difficulty)
	elseif arg ~= "--" then
		error(`unknown argument {arg}: use a number, a difficulty or KEY=value`)
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

-- Decision times in milliseconds, by difficulty and phase.
local times: { [string]: { [string]: { number } } } = {}
local function record(level: string, phase: string, ms: number)
	times[level] = times[level] or {}
	local list = times[level][phase] or {}
	times[level][phase] = list
	table.insert(list, ms)
end

-- Plays one match; returns the winning seat and the number of rejected inputs.
local function play(seed: number, levels: { Bot.Difficulty }): (number, number)
	local candidates = pairFor(seed)
	local match = Match.new(config, seed, { "p1", "p2" })
	local rngs = { Rng.new(seed * 2 + 101), Rng.new(seed * 2 + 102) }
	local styles = { Bot.styleFor(levels[1]), Bot.styleFor(levels[2]) }
	local invalid = 0
	while match.phase ~= "Done" do
		local inputs = {}
		if Match.wantsInput(match) then
			for p = 1, 2 do
				local view = View.build(config, match, p)
				local started = os.clock()
				local input = Bot.act(config, view, rngs[p], candidates[p], styles[p])
				record(levels[p], view.phase, (os.clock() - started) * 1000)
				if input ~= nil and not Match.validate(config, match, p, input) then
					invalid += 1
					input = nil
				end
				inputs[p] = input
			end
		end
		match = Match.advance(config, match, inputs)
	end
	return (match.election :: any).winner, invalid
end

local function pairing(a: Bot.Difficulty, b: Bot.Difficulty)
	local wins, invalid = 0, 0
	local started = os.clock()
	for k = 1, N do
		local seed = 300000 + k
		-- Seats alternate, so neither side keeps slot 1's draft priority.
		local levels = if k % 2 == 0 then { a, b } else { b, a }
		local slot = if k % 2 == 0 then 1 else 2
		local winner, bad = play(seed, levels)
		invalid += bad
		if winner == slot then
			wins += 1
		end
	end
	print(
		string.format(
			"%-8s vs %-8s %5.1f%% (+/- %.1f at 95%%) over %d matches, %d invalid inputs, %.0fs",
			a,
			b,
			100 * wins / N,
			100 * 1.96 * math.sqrt(0.25 / N),
			N,
			invalid,
			os.clock() - started
		)
	)
end

print(if #variant > 0 then "Config variant: " .. table.concat(variant, " ") else "Config: defaults")
if #named >= 2 then
	pairing(named[1], named[2])
else
	for _, level in { "Easy", "Hard", "Extreme" } do
		pairing(level :: Bot.Difficulty, "Medium")
	end
	for _, level in { "Medium", "Hard", "Extreme" } do
		pairing(level :: Bot.Difficulty, "Easy")
	end
	pairing("Extreme", "Hard")
end

print("")
print("Decision time (ms): mean / p99 / worst")
for _, level in Bot.DIFFICULTIES do
	local byPhase = times[level]
	if byPhase then
		local parts = {}
		for _, phase in { "Select", "Draft", "Decision", "Plan" } do
			local list = byPhase[phase]
			if list then
				table.sort(list)
				local sum = 0
				for _, ms in list do
					sum += ms
				end
				local p99 = list[math.max(1, math.ceil(#list * 0.99))]
				table.insert(
					parts,
					string.format("%s %.2f / %.2f / %.2f", phase, sum / #list, p99, list[#list])
				)
			end
		end
		print(string.format("  %-8s %s", level, table.concat(parts, "   ")))
	end
end
