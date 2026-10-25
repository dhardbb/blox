--!strict
-- The short tutorial (D-080): bot-vs-bot runs on Config.tutorial's schedule
-- against the Easy bot, and how long the tutorial takes on the server's clock.
--
--   lune run tests/harness/tutorial.luau                   -- 400 matches a pairing (~20 s)
--   lune run tests/harness/tutorial.luau 1000              -- 1,000 a pairing
--   lune run tests/harness/tutorial.luau TUTORIAL_START_CASH=12   -- a Config variant
--   lune run tests/harness/tutorial.luau --normal          -- the same table on the 12-week schedule, for reference
--
-- The "player" is a bot standing in for a new player: the standard bot (a sharp
-- one), the Hazy profile (a careless one: D-057's Easy) and Random (one tapping
-- anything legal: the floor), always against the Easy bot (since D-087 the
-- Rookie profile), seats alternating, two different candidates per match.
-- D-080's targets (sharp 55-80 %, careless 40-60 %) were set against D-057's
-- Easy; D-087 made Easy deliberately weaker, so both now win far more often (the
-- tutorial should end in a win). Most matches should still be decided on
-- election night:
-- before the votes are counted, the state that carries the eventual winner to
-- 270 (its tipping state) is within SAFE points of true margin, ground game
-- counted, so election night's swing could still decide it. "Toss-up": within
-- ELECTION_SIGMA.
--
-- Then the length: the tutorial played through Net/Session with a new player's
-- think times (THINK) against the Easy bot, every reveal and election night run
-- to its end (and once with the skippable ones skipped early). Seeds are fixed (500001 on), so a run repeats exactly.

local process = require("@lune/process")

local Bot = require("@sim/Bot")
local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Match = require("@sim/Match")
local Polls = require("@sim/Polls")
local Rng = require("@sim/Rng")
local Session = require("@net/Session")
local View = require("@sim/View")

local SAFE = 5 -- points of true margin (2.5 x ELECTION_SIGMA) that election-night noise almost never undoes

-- A new player's think time in seconds, by step (the tutorial has no timer).
-- Brisk: reads a tip and acts. Careful: reads every card first.
-- `watch`: seconds of a skippable stage (the week's reveal, the debate's
-- verdict, election night) watched before tapping Skip; nil = watched to the end.
type Think = {
	Select: number,
	Draft: number,
	Decision: number,
	Debate: number,
	Plan: number,
	plan1: number,
	watch: { [string]: number }?,
}
local THINK: { [string]: Think } = {
	brisk = { Select = 30, Draft = 12, Decision = 15, Debate = 8, Plan = 35, plan1 = 50 },
	["brisk+skip"] = {
		Select = 30,
		Draft = 12,
		Decision = 15,
		Debate = 8,
		Plan = 35,
		plan1 = 50,
		watch = { Resolve = 6, Verdict = 3, Election = 20 },
	},
	careful = { Select = 60, Draft = 20, Decision = 30, Debate = 15, Plan = 60, plan1 = 90 },
}

local N = 400
local normal = false
local changes: { [string]: any } = {}
local variant: { string } = {}
for _, arg in process.args do
	local key, value = string.match(arg, "^([%u_%d]+)=(.+)$")
	if key and value then
		if value == "true" or value == "false" then
			changes[key] = value == "true"
		else
			local list = {}
			for part in string.gmatch(value, "[^,]+") do
				table.insert(list, tonumber(part))
			end
			changes[key] = if #list > 1 or key == "TUTORIAL_DEBATE_WEEKS"
				then table.freeze(list)
				else tonumber(value) or value
		end
		table.insert(variant, arg)
	elseif arg == "--normal" then
		normal = true
	elseif tonumber(arg) then
		N = tonumber(arg) :: number
	elseif arg ~= "--" then
		error(`unknown argument {arg}: use a number, --normal or KEY=value`)
	end
end
local base = Config.with(Config.defaults, changes)
local config = if normal then base else Config.tutorial(base)

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

type Outcome = {
	winner: number,
	tip: number, -- the winner's tipping-state margin before election night (true points)
	upset: boolean, -- the last public poll's projected leader lost
	margin: number, -- winner's EV minus the loser's
	weeks: number,
	debates: { number },
	choices: { number },
	invalid: number,
}

-- The tipping state's true margin for player p before the votes are counted
-- (ground game counted, no election-night noise): sort p's states by margin and
-- take the one whose votes carry p to EV_TO_WIN. Negative: p trailed there.
local function tipping(match: any, p: number): number
	local margins: { { ev: number, margin: number } } = {}
	for _, s in match.states do
		local mine = s.support[p] + config.GOTV_PER_UNIT * s.gotv[p]
		local best = -math.huge
		for q = 1, #s.support do
			if q ~= p then
				best = math.max(best, s.support[q] + config.GOTV_PER_UNIT * s.gotv[q])
			end
		end
		table.insert(margins, { ev = s.ev, margin = mine - best })
	end
	table.sort(margins, function(a, b)
		return a.margin > b.margin
	end)
	local total = 0
	for _, entry in margins do
		total += entry.ev
		if total >= config.EV_TO_WIN then
			return entry.margin
		end
	end
	return -math.huge
end

local function play(seed: number, styles: { Bot.Style }): Outcome
	local candidates = pairFor(seed)
	local match = Match.new(config, seed, { "p1", "p2" })
	local rngs = { Rng.new(seed * 2 + 101), Rng.new(seed * 2 + 102) }
	local invalid = 0
	local debates: { number } = {}
	local choices: { number } = {}
	local tips = { 0, 0 }
	local projected = { 0, 0 }
	while match.phase ~= "Done" do
		if match.phase == "Debate" and table.find(debates, match.week) == nil then
			table.insert(debates, match.week)
		end
		if match.phase == "Decision" and table.find(choices, match.week) == nil then
			table.insert(choices, match.week)
		end
		local inputs = {}
		if Match.wantsInput(match) then
			for p = 1, 2 do
				local view = View.build(config, match, p)
				local input = Bot.act(config, view, rngs[p], candidates[p], styles[p])
				if input ~= nil and not Match.validate(config, match, p, input) then
					invalid += 1
					input = nil
				end
				inputs[p] = input
			end
		end
		local before = match.phase
		match = Match.advance(config, match, inputs)
		if before == "Plan" and match.phase == "Election" then
			tips = { tipping(match, 1), tipping(match, 2) }
			projected = Polls.projectedEV(match)
		end
	end
	local election = match.election :: any
	local winner = election.winner
	local leader = if projected[1] > projected[2] then 1 elseif projected[2] > projected[1] then 2 else 0
	return {
		winner = winner,
		tip = if winner == 0 then 0 else tips[winner],
		upset = leader ~= 0 and leader ~= winner,
		margin = if winner == 0 then 0 else election.ev[winner] - election.ev[3 - winner],
		weeks = match.week - 1,
		debates = debates,
		choices = choices,
		invalid = invalid,
	}
end

local scheduleErrors = 0
local function pairing(player: Bot.Style, label: string)
	local wins, open, tossups, upsets, invalid, margin = 0, 0, 0, 0, 0, 0
	local tipList: { number } = {}
	local started = os.clock()
	for k = 1, N do
		local seed = 500000 + k
		-- Seats alternate, so neither side keeps slot 1's draft priority.
		local slot = if k % 2 == 0 then 1 else 2
		local easy = Bot.styleFor("Easy") -- the tutorial's bot (D-080), whatever profile Easy plays (D-087)
		local styles: { Bot.Style } = if slot == 1 then { player, easy } else { easy, player }
		local o = play(seed, styles)
		invalid += o.invalid
		if o.winner == slot then
			wins += 1
		end
		if o.tip <= SAFE then
			open += 1
		end
		if o.tip <= config.ELECTION_SIGMA then
			tossups += 1
		end
		table.insert(tipList, o.tip)
		if o.upset then
			upsets += 1
		end
		margin += o.margin
		-- The schedule: every match plays its weeks, its debates and its Choice weeks.
		local wantChoices = if config.EVENT_CHOICE_ONLY then { config.EVENT_FIRST_WEEK } else nil
		local ok = o.weeks == config.WEEKS and #o.debates == #config.DEBATE_WEEKS
		for i, week in config.DEBATE_WEEKS do
			ok = ok and o.debates[i] == week
		end
		if wantChoices then
			ok = ok and #o.choices == 1 and o.choices[1] == wantChoices[1]
		end
		if not ok then
			scheduleErrors += 1
		end
	end
	table.sort(tipList)
	print(
		string.format(
			"%-22s %5.1f%% (+/- %.1f)   decided on election night %5.1f%% (toss-up %4.1f%%, median tipping margin %+.1f)   poll leader lost %4.1f%%   mean margin %5.1f EV   %d invalid   %.0fs",
			label,
			100 * wins / N,
			100 * 1.96 * math.sqrt(0.25 / N),
			100 * open / N,
			100 * tossups / N,
			tipList[math.ceil(N / 2)],
			100 * upsets / N,
			margin / N,
			invalid,
			os.clock() - started
		)
	)
end

print(if normal then "Schedule: normal (12 weeks)" else "Schedule: tutorial (Config.tutorial)")
print(if #variant > 0 then "Config variant: " .. table.concat(variant, " ") else "Config: defaults")
print(
	`Weeks {config.WEEKS}, debates in week(s) {table.concat(config.DEBATE_WEEKS, ", ")}, events weeks {config.EVENT_FIRST_WEEK}-{config.EVENT_LAST_WEEK}{if config.EVENT_CHOICE_ONLY
		then " (Choice only)"
		else ""}, start cash ${config.START_CASH}`
)
print("")
print(`Player vs the Easy bot, {N} matches each (the player's win rate):`)
pairing("Balanced", "Sharp player")
pairing("Hazy", "Careless player")
pairing("Random", "Random (taps anything)")
print(
	if scheduleErrors == 0
		then "Schedule: every match ran as configured"
		else `!! {scheduleErrors} match(es) off the schedule`
)

-- ------------------------------------------------------------------- length

-- Plays the tutorial through Net/Session: seat 1 is the player (the Medium bot's
-- choices after `think` seconds), seat 2 the Easy bot. Returns the minutes from
-- Select to the end of election night.
local function length(seed: number, think: Think): number
	local session = Session.new(base, "len", seed, {
		{ id = "you", kind = "Human" },
		{ id = "bot", kind = "Bot", candidate = "calloway", difficulty = "Easy" },
	}, 0, { tutorial = not normal })
	local rng = Rng.new(seed * 7 + 3)
	local t = 0
	for _ = 1, 2000 do
		Session.drain(session)
		if session.stage == "Over" then
			return t / 60
		end
		local watching = if session.stage == "Show" and session.match.phase == "Election"
			then "Election"
			else session.reveal
		local watch = if think.watch and watching then think.watch[watching] else nil
		if watch and not session.seats[1].skip and session.stageStart + watch < Session.nextWake(session) then
			t = session.stageStart + watch
			assert(Session.skip(session, 1, session.step, t), "skip rejected")
		elseif session.stage == "Input" and not session.seats[1].locked then
			local phase = session.match.phase
			local wait = if phase == "Plan" and session.match.week == 1
				then think.plan1
				else (think :: any)[phase] :: number
			if not normal then
				t = session.stageStart + wait
			else
				t = math.min(session.stageStart + wait, session.deadline)
			end
			local view = View.build(session.config, session.match, 1)
			local input = Bot.act(session.config, view, rng, "okafor")
			assert(Session.submit(session, 1, session.step, input, t), "submit rejected")
		else
			t = Session.nextWake(session)
			Session.update(session, t)
		end
	end
	error("the tutorial did not end")
end

print("")
print("Length (Select to the end of election night; reveals run out unless the profile skips):")
for _, name in { "brisk", "brisk+skip", "careful" } do
	local list: { number } = {}
	local sum = 0
	local runs = math.min(N, 100)
	for k = 1, runs do
		local minutes = length(500000 + k, THINK[name])
		table.insert(list, minutes)
		sum += minutes
	end
	table.sort(list)
	local function clock(m: number): string
		return string.format("%d:%02d", math.floor(m), math.floor((m % 1) * 60 + 0.5))
	end
	local think = THINK[name]
	print(
		string.format(
			"  %-10s mean %s  median %s  p90 %s  max %s   (think: Select %ds, draft round %ds, plan %ds (week 1: %ds), stance %ds, debate round %ds; %d runs)",
			name,
			clock(sum / runs),
			clock(list[math.ceil(runs / 2)]),
			clock(list[math.ceil(runs * 0.9)]),
			clock(list[runs]),
			think.Select,
			think.Draft,
			think.Plan,
			think.plan1,
			think.Decision,
			think.Debate,
			runs
		)
	)
end
