--!strict
-- The Daily Race (docs/DESIGN.md D-082): one race a UTC day, the same for every
-- player. Everything about it comes from the day number alone (whole days since
-- 1970-01-01 UTC; the server passes os.time() // 86400), through Sim/Rng:
--
--   seed          the match seed: map leans, issue map, debate topics, events
--   candidate     who every player runs that day (forced: no candidate pick)
--   botCandidate  who the bot runs (never the player's candidate)
--   level         the level the bot counts as (Config.DAILY_BOT_LEVEL, Extreme:
--                 its timers)
--   style         how the bot plays (Config.DAILY_BOT_STYLE, Foresight: D-082's
--                 Hard, kept by D-087 so every day's board means the same)
--
-- Candidates rotate in seeded cycles: the days are cut into cycles of one day
-- per candidate, each cycle is a seeded shuffle of the whole roster (so every
-- cycle uses every candidate once), and when a cycle would open with the
-- candidate the previous one closed on, its first two days swap. So no
-- candidate ever runs two days in a row. The platform is not part of the race:
-- every player picks their own three issues from the same issue map (D-082).
--
-- Pure: no clock, no Roblox. The same day always gives the same race.

local Bot = require("./Bot")
local Candidates = require("./Candidates")
local ConfigModule = require("./Config")
local Rng = require("./Rng")

type Config = ConfigModule.Config

export type Race = {
	day: number, -- whole days since 1970-01-01 UTC
	date: string, -- "2026-10-24" (UTC)
	seed: number, -- the match seed, 1 .. 2^31 - 1
	candidate: string, -- every player's candidate today
	botCandidate: string, -- the bot's candidate today
	level: Bot.Difficulty, -- the level the bot counts as (its timers)
	style: Bot.Style, -- how the bot plays
	endsAt: number, -- Unix seconds the race ends (the next 00:00 UTC)
}

local Daily = {}

Daily.DAY = 86400 -- seconds in a UTC day
local MAX_SEED = 2 ^ 31 - 1

-- The day a Unix time falls on (UTC).
function Daily.dayOf(unix: number): number
	return math.floor(unix / Daily.DAY)
end

-- Unix seconds day `day` ends (00:00 UTC of the next day).
function Daily.endsAt(day: number): number
	return (day + 1) * Daily.DAY
end

-- The civil date of a day (proleptic Gregorian, UTC): year, month 1-12, day
-- of month 1-31. Howard Hinnant's days-to-civil algorithm.
function Daily.civil(day: number): (number, number, number)
	local z = day + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe =
		math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	local y = yoe + era * 400 + (if m <= 2 then 1 else 0)
	return y, m, d
end

-- The day as "YYYY-MM-DD" (UTC): the daily leaderboard's key.
function Daily.dateKey(day: number): string
	local y, m, d = Daily.civil(day)
	return string.format("%04d-%02d-%02d", y, m, d)
end

-- Day of the week, 1 = Sunday … 7 = Saturday (1970-01-01 was a Thursday).
function Daily.weekday(day: number): number
	return (day + 4) % 7 + 1
end

-- One cycle's shuffle of the roster, before the no-repeat fix.
local function rawCycle(cycle: number): { string }
	local order = table.clone(Candidates.ids) :: { string }
	Rng.shuffle(Rng.new(Rng.hash(`daily-cycle:{cycle}`)), order)
	return order
end

-- The candidates of cycle `cycle`, one a day: a seeded shuffle of the whole
-- roster whose first two swap if it would open with the candidate the
-- previous cycle closed on. The swap never touches the last place, so the
-- previous cycle's last candidate is its raw shuffle's.
function Daily.cycle(cycle: number): { string }
	local order = rawCycle(cycle)
	local previous = rawCycle(cycle - 1)
	if #order >= 2 and order[1] == previous[#previous] then
		order[1], order[2] = order[2], order[1]
	end
	return order
end

-- Every player's candidate on day `day`.
function Daily.candidate(day: number): string
	local n = #Candidates.ids
	local cycle = math.floor(day / n)
	return Daily.cycle(cycle)[day - cycle * n + 1]
end

-- The match seed of day `day`.
function Daily.seed(day: number): number
	return Rng.nextInt(Rng.new(Rng.hash(`daily-seed:{day}`)), 1, MAX_SEED)
end

-- The bot's candidate on day `day`: any other candidate, seeded by the day.
function Daily.botCandidate(day: number): string
	local mine = Daily.candidate(day)
	local others: { string } = {}
	for _, id in Candidates.ids do
		if id ~= mine then
			table.insert(others, id)
		end
	end
	return others[Rng.nextInt(Rng.new(Rng.hash(`daily-bot:{day}`)), 1, #others)]
end

-- Everything about day `day`'s race.
function Daily.race(config: Config, day: number): Race
	assert(day == math.floor(day), "day must be a whole number")
	return table.freeze({
		day = day,
		date = Daily.dateKey(day),
		seed = Daily.seed(day),
		candidate = Daily.candidate(day),
		botCandidate = Daily.botCandidate(day),
		level = Bot.difficulty(config.DAILY_BOT_LEVEL),
		style = config.DAILY_BOT_STYLE :: Bot.Style,
		endsAt = Daily.endsAt(day),
	})
end

return table.freeze(Daily)
