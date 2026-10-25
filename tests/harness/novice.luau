--!strict
-- Easy-bot study: scripted first-time players (tests/lib/Novice: Weak, Typical,
-- Attentive) against the practice bots, seats alternating, two different
-- candidates per match, fixed seeds. Every player decides from its own View.
-- The bots in Sim/Bot are unchanged; the prototype variants below are harness
-- flags on the bot's seat only (its own Config, Bot.tuning while it decides,
-- what it is shown of its cash, its seat's underdog boost), so nothing here
-- changes a default.
--
--   lune run tests/harness/novice.luau                     -- benchmark: 3 novices vs Easy and Medium, 1,000 each (~1 min)
--   lune run tests/harness/novice.luau Typical Easy 2000   -- one pairing (the first named is the reported side)
--   lune run tests/harness/novice.luau Easy Medium         -- two bots
--   lune run tests/harness/novice.luau ablate [N]          -- Easy with one edge removed at a time, vs Typical
--   lune run tests/harness/novice.luau options [N]         -- the tuning options vs each novice, and vs Medium
--   lune run tests/harness/novice.luau leaks [N]           -- the novice with one part of its play handed to the standard bot
--   lune run tests/harness/novice.luau habits [N]          -- the typical novice with one habit group fixed at a time
--   (ablate, leaks and habits take --novice=Weak|Typical|Attentive; Typical by default)
--   lune run tests/harness/novice.luau Typical Easy --variant=NoGotv
--
-- Flags on the bot under test (the first bot named in the pairing):
--   bot.KEY=value     its own Config only, e.g. bot.BOT_EASY_SLIP=1 (the match keeps the defaults)
--   tune.key=value    Bot.tuning while it decides, e.g. tune.gotvFromWeek=99
--   --reserve=N       it plans as if it had $N less, so about $N sits idle
--   --fixed-noise     Easy's misjudgment of each state is drawn once a match, not every week
--   --no-rubber       the underdog boost (D-020) never applies to its seat (needs approval: a rule change)
--   --income=X        its cash moves by $X after every week (a handicap prototype; needs approval)
--   --variant=Name    a named set of the flags above (VARIANTS below)
-- KEY=value (no prefix) changes the match Config for both seats; nov.key=value
-- changes a novice parameter (tests/lib/Novice Params) for every novice seat, and
-- --delegate=Plan,Debate hands those phases of every novice seat to the standard bot.
--
-- Each line: the reported side's win rate (95% band), the median winning
-- margin in EV, the median margin of the reported side's wins and its share of
-- wins by 40+ EV, both sides' unspent cash and ground-game units, and the weeks
-- each side spent in an underdog tier.

local process = require("@lune/process")

local Bot = require("@sim/Bot")
local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Match = require("@sim/Match")
local Novice = require("@testlib/Novice")
local Rng = require("@sim/Rng")
local View = require("@sim/View")

type Config = Config.Config

export type Flags = {
	config: { [string]: any }?,
	tuning: { [string]: any }?,
	reserve: number?,
	fixedNoise: boolean?,
	noRubber: boolean?,
	income: number?,
}

type Seat = {
	label: string,
	novice: Novice.Params?,
	style: Bot.Style?,
	flags: Flags,
	config: Config?, -- the bot's own Config (bot.KEY=value), else the match's
}

-- Named flag sets: the ablations (one edge of Easy removed) and the options.
local VARIANTS: { [string]: { text: string, flags: Flags } } = {
	NoGotv = { text = "no ground game", flags = { tuning = { gotvFromWeek = 99 } } },
	LateGotv = { text = "ground game from week 10", flags = { tuning = { gotvFromWeek = 10 } } },
	Idle30 = { text = "keeps $30 idle", flags = { reserve = 30 } },
	NoPolls = { text = "no internal polls", flags = { tuning = { pollFromWeek = 99, scoutFromWeek = 99 } } },
	Slip0 = { text = "never slips (stances, debates)", flags = { config = { BOT_EASY_SLIP = 0 } } },
	Slip1 = {
		text = "always slips (random stance, move, Zinger)",
		flags = { config = { BOT_EASY_SLIP = 1 } },
	},
	Noise0 = { text = "no misjudgment (Medium's plans)", flags = { config = { BOT_EASY_NOISE = 0 } } },
	Noise1 = { text = "noise 1.0", flags = { config = { BOT_EASY_NOISE = 1 } } },
	Noise2 = { text = "noise 2.0", flags = { config = { BOT_EASY_NOISE = 2 } } },
	Fixed = { text = "noise 0.45 drawn once a match", flags = { fixedNoise = true } },
	Fixed1 = {
		text = "noise 1.0 drawn once a match",
		flags = { fixedNoise = true, config = { BOT_EASY_NOISE = 1 } },
	},
	BigStates = { text = "values big states, not close ones", flags = { tuning = { campaignVariance = 40 } } },
	NoRubber = { text = "no underdog boost for the bot", flags = { noRubber = true } },
	Income1 = { text = "$1 less a week", flags = { income = -1 } },
	-- The options (easy-study): A and B only play worse (D-057's intent), C changes the rules for the bot.
	OptA = {
		text = "A: misjudges hard and stubbornly (noise 4 drawn once a match), random stances and debate moves",
		flags = { fixedNoise = true, config = { BOT_EASY_NOISE = 4, BOT_EASY_SLIP = 1 } },
	},
	OptB = {
		text = "B: novice habits (noise 2.5 once a match, random decisions, $40 idle, ground game from week 11)",
		flags = {
			fixedNoise = true,
			reserve = 40,
			config = { BOT_EASY_NOISE = 2.5, BOT_EASY_SLIP = 1 },
			tuning = { gotvFromWeek = 11 },
		},
	},
	OptC = {
		text = "C: noise 3 once a match, random decisions, no underdog boost, $1 less a week (needs approval)",
		flags = {
			fixedNoise = true,
			noRubber = true,
			income = -1,
			config = { BOT_EASY_NOISE = 3, BOT_EASY_SLIP = 1 },
		},
	},
}

-- The ablation list (each vs the typical novice), in print order.
local ABLATIONS = {
	"",
	"Slip0",
	"Slip1",
	"Noise0",
	"Noise1",
	"Noise2",
	"Fixed",
	"Fixed1",
	"NoGotv",
	"LateGotv",
	"Idle30",
	"NoPolls",
	"BigStates",
	"NoRubber",
	"Income1",
}

-- The typical novice's habits, one group at a time set to the attentive novice's
-- values: which habit costs a new player the most against Easy.
local HABITS: { { name: string, params: { [string]: any } } } = {
	{
		name = "targets like Attentive (polls over liked states, less sticky, less noise)",
		params = {
			pollWeight = 0.9,
			sticky = 0.2,
			repeatRally = 0.2,
			noise = 0.25,
			strongholdRally = 0.05,
			bestIssue = 0.95,
		},
	},
	{ name = "spends like Attentive ($6 kept, up to 6 ads)", params = { reserve = 6, maxAds = 6 } },
	{
		name = "ground game like Attentive (from week 6, 2 states, last-week dump)",
		params = { gotvFrom = 6, gotvChance = 0.8, gotvStates = 2, dumpLast = 1 },
	},
	{
		name = "stances like Attentive (hedge 20%, reads close states)",
		params = { hedge = 0.2, stanceRead = 0.9, stanceByNeed = true },
	},
	{
		name = "debates like Attentive (safe moves, Zinger on a sure win)",
		params = { safeRead = 0.9, debateRead = 0.6, zingerOnSafe = true },
	},
}

-- The tuning options of the study, each measured vs every novice and vs Medium.
local OPTIONS: { string } = { "OptA", "OptB", "OptC" }

-- ---------------------------------------------------------------- arguments

local N = 1000
local named: { string } = {}
local changes: { [string]: any } = {}
local botChanges: { [string]: any } = {}
local tuning: { [string]: any } = {}
local noviceChanges: { [string]: any } = {}
local flags: Flags = {}
local variantName: string? = nil
local mode = "pair"
local noviceName = "Typical"
local notes: { string } = {}

local function parseValue(value: string): any
	if value == "true" or value == "false" then
		return value == "true"
	end
	local list = {}
	for part in string.gmatch(value, "[^,]+") do
		table.insert(list, tonumber(part))
	end
	if #list > 1 then
		return table.freeze(list)
	end
	return tonumber(value) or value
end

for _, arg in process.args do
	local prefix, key, value = string.match(arg, "^(%a+)%.([%w_]+)=(.+)$")
	local plainKey, plainValue = string.match(arg, "^([%u_][%u%d_]*)=(.+)$")
	local flag, rawValue = string.match(arg, "^%-%-([%w%-]+)=?(.*)$")
	local flagValue: string = rawValue or ""
	if prefix == "bot" and key and value then
		botChanges[key] = parseValue(value)
		table.insert(notes, arg)
	elseif prefix == "nov" and key and value then
		noviceChanges[key] = parseValue(value)
		table.insert(notes, arg)
	elseif prefix == "tune" and key and value then
		tuning[key] = parseValue(value)
		table.insert(notes, arg)
	elseif plainKey and plainValue then
		changes[plainKey] = parseValue(plainValue)
		table.insert(notes, arg)
	elseif flag == "reserve" then
		flags.reserve = tonumber(flagValue)
		table.insert(notes, arg)
	elseif flag == "income" then
		flags.income = tonumber(flagValue)
		table.insert(notes, arg)
	elseif flag == "fixed-noise" then
		flags.fixedNoise = true
		table.insert(notes, arg)
	elseif flag == "no-rubber" then
		flags.noRubber = true
		table.insert(notes, arg)
	elseif flag == "delegate" then
		local phases = {}
		for phase in string.gmatch(flagValue, "[^,]+") do
			phases[phase] = true
		end
		noviceChanges.delegate = phases
		table.insert(notes, arg)
	elseif flag == "novice" then
		assert(Novice.VARIANTS[flagValue], `unknown novice {flagValue}`)
		noviceName = flagValue
	elseif flag == "variant" then
		assert(VARIANTS[flagValue], `unknown variant {flagValue}`)
		variantName = flagValue
		table.insert(notes, arg)
	elseif tonumber(arg) then
		N = tonumber(arg) :: number
	elseif arg == "ablate" or arg == "options" or arg == "bench" or arg == "leaks" or arg == "habits" then
		mode = arg
	elseif Novice.VARIANTS[arg] or table.find(Bot.DIFFICULTIES, arg) then
		table.insert(named, arg)
	elseif arg ~= "--" then
		error(`unknown argument {arg}`)
	end
end
if #named < 2 and mode == "pair" then
	mode = "bench"
end
if next(botChanges) then
	flags.config = botChanges
end
if next(tuning) then
	flags.tuning = tuning
end
local config = Config.with(Config.defaults, changes)

-- Merges two flag sets (the second wins).
local function merge(a: Flags, b: Flags): Flags
	local out: Flags = table.clone(a)
	for key, value in b :: any do
		if type(value) == "table" then
			local inner = table.clone((out :: any)[key] or {})
			for k, v in value do
				inner[k] = v
			end
			(out :: any)[key] = inner
		else
			(out :: any)[key] = value
		end
	end
	return out
end

local function seatFor(name: string, extra: Flags?): Seat
	local novice = Novice.VARIANTS[name]
	if novice then
		if next(noviceChanges) then
			local params = table.clone(novice) :: any
			for key, value in noviceChanges do
				assert(params[key] ~= nil or key == "delegate", `unknown novice parameter {key}`)
				params[key] = value
			end
			novice = params
		end
		return { label = name, novice = novice, flags = {} }
	end
	local level: Bot.Difficulty = Bot.difficulty(name)
	local f: Flags = extra or {}
	local own = if f.config then Config.with(config, f.config) else nil
	return { label = level, style = Bot.styleFor(level), flags = f, config = own }
end

-- ---------------------------------------------------------------- one match

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

local function botAct(seat: Seat, view: any, rng: Rng.Rng, candidate: string, seed: number, p: number): any
	local f = seat.flags
	local saved: { [string]: any } = {}
	if f.tuning then
		for key, value in f.tuning do
			saved[key] = (Bot.tuning :: any)[key];
			(Bot.tuning :: any)[key] = value
		end
	end
	local shown = view
	local r = rng
	if view.phase == "Plan" then
		if f.reserve and f.reserve > 0 then
			shown = table.clone(view)
			local players = table.clone(view.players)
			local me = table.clone(players[view.you])
			me.cash = math.max(0, (me.cash or 0) - f.reserve)
			players[view.you] = me
			shown.players = players
		end
		if f.fixedNoise then
			r = Rng.new(seed * 7 + p) -- the same weights every week of this match
		end
	end
	local input = Bot.act(seat.config or config, shown, r, candidate, seat.style)
	for key, value in saved do
		(Bot.tuning :: any)[key] = value
	end
	return input
end

type Record = {
	winner: number,
	ev: { number },
	cash: { number },
	gotv: { number },
	underdogWeeks: { number },
	invalid: number,
}

local function play(seed: number, seats: { Seat }): Record
	local candidates = pairFor(seed)
	local match = Match.new(config, seed, { "p1", "p2" })
	local rngs = { Rng.new(seed * 2 + 101), Rng.new(seed * 2 + 102) }
	local invalid = 0
	local gotv = { 0, 0 }
	local underdog = { 0, 0 }
	while match.phase ~= "Done" do
		local inputs = {}
		local phase = match.phase
		if Match.wantsInput(match) then
			for p = 1, 2 do
				local view = View.build(config, match, p)
				local seat = seats[p]
				local input
				if seat.novice then
					input = Novice.act(config, view, rngs[p], candidates[p], seat.novice)
				else
					input = botAct(seat, view, rngs[p], candidates[p], seed, p)
				end
				if input ~= nil and not Match.validate(config, match, p, input) then
					invalid += 1
					input = nil
				end
				if input ~= nil and phase == "Plan" then
					for _, action in input.actions do
						if action.kind == "Gotv" then
							gotv[p] += action.units
						end
					end
				end
				inputs[p] = input
			end
		end
		match = Match.advance(config, match, inputs)
		if phase == "Select" then
			for p = 1, 2 do
				if seats[p].flags.noRubber then
					local profile = table.clone(match.players[p].profile) :: any
					profile.underdogScale = 0
					match.players[p].profile = profile
				end
			end
		elseif phase == "Plan" then
			for p = 1, 2 do
				local income = seats[p].flags.income
				if income then
					match.players[p].cash = math.max(0, match.players[p].cash + income)
				end
				if match.players[p].underdogTier > 0 then
					underdog[p] += 1
				end
			end
		end
	end
	local result = match.election :: any
	return {
		winner = result.winner,
		ev = result.ev,
		cash = { match.players[1].cash, match.players[2].cash },
		gotv = gotv,
		underdogWeeks = underdog,
		invalid = invalid,
	}
end

-- ---------------------------------------------------------------- a pairing

local function median(list: { number }): number
	if #list == 0 then
		return 0 / 0
	end
	local sorted = table.clone(list)
	table.sort(sorted)
	local mid = (#sorted + 1) / 2
	return (sorted[math.floor(mid)] + sorted[math.ceil(mid)]) / 2
end

export type Summary = {
	rate: number,
	band: number,
	median: number,
	medianWin: number,
	big: number,
	medianLoss: number,
}

-- A vs B over N matches; the reported side is A. Seeds 500001 on, seats alternate.
local function pairing(a: Seat, b: Seat, n: number, label: string?): Summary
	local wins, ties, invalid = 0, 0, 0
	local margins, winMargins, lossMargins = {}, {}, {}
	local big = 0
	local cash, units, under = { 0, 0 }, { 0, 0 }, { 0, 0 }
	local started = os.clock()
	for k = 1, n do
		local seed = 500000 + k
		local slot = if k % 2 == 0 then 1 else 2
		local seats = if slot == 1 then { a, b } else { b, a }
		local r = play(seed, seats)
		invalid += r.invalid
		local other = 3 - slot
		local gap = r.ev[slot] - r.ev[other]
		table.insert(margins, math.abs(gap))
		if r.winner == slot then
			wins += 1
			table.insert(winMargins, gap)
			if gap >= 40 then
				big += 1
			end
		elseif r.winner == 0 then
			ties += 1
		else
			table.insert(lossMargins, -gap)
		end
		cash[1] += r.cash[slot]
		cash[2] += r.cash[other]
		units[1] += r.gotv[slot]
		units[2] += r.gotv[other]
		under[1] += r.underdogWeeks[slot]
		under[2] += r.underdogWeeks[other]
	end
	local p = wins / n
	local band = 1.96 * math.sqrt(math.max(p * (1 - p), 0.01) / n)
	local summary = {
		rate = 100 * p,
		band = 100 * band,
		median = median(margins),
		medianWin = median(winMargins),
		big = if wins > 0 then 100 * big / wins else 0,
		medianLoss = median(lossMargins),
	}
	print(
		string.format(
			"%-34s %5.1f%% +/- %.1f | margin %3.0f | A wins by %3.0f (%2.0f%% 40+), loses by %3.0f | $ %4.1f / %4.1f | gotv %4.1f / %4.1f | underdog wks %3.1f / %3.1f | %d ties %d invalid %.0fs",
			label or `{a.label} vs {b.label}`,
			summary.rate,
			summary.band,
			summary.median,
			summary.medianWin,
			summary.big,
			summary.medianLoss,
			cash[1] / n,
			cash[2] / n,
			units[1] / n,
			units[2] / n,
			under[1] / n,
			under[2] / n,
			ties,
			invalid,
			os.clock() - started
		)
	)
	return summary
end

-- ---------------------------------------------------------------- modes

print(if #notes > 0 then "Flags: " .. table.concat(notes, " ") else "Flags: none (defaults)")
print(
	"columns: A win% (95%) | median winning margin | A's median win (share 40+), median loss | unspent $ A/B | gotv units A/B | underdog weeks A/B"
)

local function withVariant(name: string?, base: Flags): Flags
	if name == nil or name == "" then
		return base
	end
	return merge(VARIANTS[name].flags, base)
end

if mode == "bench" then
	for _, novice in Novice.NAMES do
		for _, level in { "Easy", "Medium" } do
			pairing(seatFor(novice), seatFor(level, withVariant(variantName, flags)), N)
		end
	end
	pairing(seatFor("Easy", withVariant(variantName, flags)), seatFor("Medium"), N)
elseif mode == "ablate" then
	pairing(seatFor(noviceName), seatFor("Medium"), N, `{noviceName} vs Medium (reference)`)
	for _, name in ABLATIONS do
		local text = if name == "" then "Easy (as shipped)" else `Easy, {VARIANTS[name].text}`
		pairing(seatFor(noviceName), seatFor("Easy", withVariant(name, flags)), N, `{noviceName} vs {text}`)
	end
elseif mode == "habits" then
	pairing(seatFor(noviceName), seatFor("Easy", flags), N, `{noviceName} vs Easy`)
	for _, habit in HABITS do
		local base = seatFor(noviceName)
		local params = table.clone(base.novice :: Novice.Params) :: any
		for key, value in habit.params do
			params[key] = value
		end
		base.novice = params
		pairing(base, seatFor("Easy", flags), N, `{noviceName}, {habit.name}`)
	end
elseif mode == "leaks" then
	-- The novice's own play, one part at a time handed to the standard bot.
	pairing(seatFor(noviceName), seatFor("Easy", flags), N, `{noviceName} vs Easy`)
	for _, phases in { { "Draft" }, { "Plan" }, { "Decision" }, { "Debate" }, { "Decision", "Debate" } } do
		local base = seatFor(noviceName)
		local params = table.clone(base.novice :: Novice.Params)
		local set = {}
		for _, phase in phases do
			set[phase] = true
		end
		params.delegate = set
		base.novice = params
		pairing(base, seatFor("Easy", flags), N, `{noviceName}, bot's {table.concat(phases, "+")} vs Easy`)
	end
elseif mode == "options" then
	for _, name in OPTIONS do
		print(`-- {name}: {VARIANTS[name].text}`)
		local f = withVariant(name, flags)
		for _, novice in Novice.NAMES do
			pairing(seatFor(novice), seatFor("Easy", f), N, `{novice} vs Easy[{name}]`)
		end
		pairing(seatFor("Easy", f), seatFor("Medium"), N, `Easy[{name}] vs Medium`)
	end
else
	local first, second = named[1], named[2]
	-- The flags go to the first bot named.
	if Novice.VARIANTS[first] then
		pairing(seatFor(first), seatFor(second, withVariant(variantName, flags)), N)
	else
		pairing(seatFor(first, withVariant(variantName, flags)), seatFor(second), N)
	end
end
