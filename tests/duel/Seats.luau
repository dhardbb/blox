--!strict
-- The duel harness's seat rules, pure so tests/duel/Seats.spec.luau can pin them:
-- `--bot SEAT:LEVEL` puts the server's practice bot in one seat, so a single
-- agent plays the bot through the same files a two-agent duel uses.
--
-- The match is a real Practice match (the Lobby's Play vs Bot, D-057): the server
-- seats the person first and its bot second, so only seat 2 can hold the bot.
-- The person is a returning player (tutorial done, D-075), so it is a full
-- 12-week match, not the tutorial.

local Bot = require("@shared/Sim/Bot")

export type BotSeat = {
	seat: number, -- always 2: Practice seats the person first
	level: Bot.Difficulty,
}

local Seats = {}

-- Parses the value of `--bot` ("2:Easy", "2:hard"; the level is not case
-- sensitive). Returns the seat, or nil and a message for the usage line.
function Seats.parse(value: string?): (BotSeat?, string?)
	if value == nil then
		return nil, "--bot needs SEAT:LEVEL, e.g. --bot 2:Easy"
	end
	local seatText, levelText = string.match(value, "^%s*(%d+)%s*:%s*(%a+)%s*$")
	if seatText == nil or levelText == nil then
		return nil, `--bot needs SEAT:LEVEL, e.g. --bot 2:Easy (got "{value}")`
	end
	local seat = tonumber(seatText) :: number
	if seat ~= 2 then
		return nil,
			`--bot seat must be 2: a practice match seats the person first and the bot second (got {seat})`
	end
	local wanted = string.lower(levelText :: string)
	for k = 1, #Bot.DIFFICULTIES do
		local level: Bot.Difficulty = Bot.DIFFICULTIES[k]
		if string.lower(level) == wanted then
			return { seat = seat, level = level }, nil
		end
	end
	return nil, `--bot level must be one of {table.concat(Bot.DIFFICULTIES, ", ")} (got "{levelText}")`
end

-- How many people join the match: 1 with a bot seat, else 2.
function Seats.people(bot: BotSeat?): number
	return if bot then 1 else 2
end

-- The name the result uses for a seat no agent plays.
function Seats.botName(bot: BotSeat): string
	return `bot ({bot.level})`
end

-- The request that starts the match once everyone has joined: a Practice
-- request with the bot's level, or nil for the two-person queue.
function Seats.request(bot: BotSeat?): { op: string, difficulty: string }?
	if bot == nil then
		return nil
	end
	local level: string = bot.level
	return { op = "Practice", difficulty = level }
end

return table.freeze(Seats)
