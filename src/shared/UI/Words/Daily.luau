--!strict
-- Copy for the Daily Race (docs/DESIGN.md D-082): the Lobby's card, the day's
-- board sheet and the Results summary. Plain words, labels of at most 8 words,
-- any text block at most 30 words (the UI audit's wallOfText). Pure.

local SimDaily = require("../../Sim/Daily")

local Daily = {}

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

Daily.TITLE = "Daily Race"
Daily.EYEBROW = "DAILY RACE"
Daily.PLAY = "Play today's race"
Daily.PRACTICE = "Practice today's race"
Daily.BOARD = "Today's board"
-- A phone's one-row card (0.15.0): short labels beside the head.
Daily.PLAY_SHORT = "Play"
Daily.PRACTICE_SHORT = "Practice"
Daily.BOARD_SHORT = "Top 50"
Daily.SHEET = "Today's top 50"
Daily.HOW =
	"Ranked by your final vote margin over the bot. Ties: fewer weeks behind in the polls, then who finished first. Only your first run each day counts."
Daily.LOADING = "Loading today's board…"
Daily.UNAVAILABLE = "Today's board is unavailable"
Daily.EMPTY = "Nobody has finished today's race yet. Be the first!"
Daily.WAITING = "Loading today's race…"
Daily.REMATCH_PRACTICE = "Rematch plays today's race as practice." -- Results' status line after a run (D-082)
Daily.SAVING = "Saving your run…"

-- "Sat, Oct 24" (UTC).
function Daily.dateLabel(day: number): string
	local _, m, d = SimDaily.civil(day)
	return `{WEEKDAYS[SimDaily.weekday(day)]}, {MONTHS[m]} {d}`
end

-- "Everyone plays as Dana Okafor today".
function Daily.everyone(name: string): string
	return `Everyone plays as {name} today`
end

-- "As Dana Okafor": who everyone plays, on a phone's one-row card.
function Daily.as(name: string): string
	return `As {name}`
end

-- Time until the next race without "left" (a phone's card): "5h 12m", "12m", "40s".
function Daily.timeShort(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	if h > 0 then
		return `{h}h {m}m`
	elseif m > 0 then
		return `{m}m`
	end
	return `{s}s`
end

-- Time until the next race: "5h 12m left", "12m left", "40s left".
function Daily.timeLeft(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = s // 3600
	local m = (s % 3600) // 60
	if h > 0 then
		return `{h}h {m}m left`
	elseif m > 0 then
		return `{m}m left`
	end
	return `{s}s left`
end

-- "3-day streak", "1-day streak", "No streak yet".
function Daily.streak(n: number): string
	if n <= 0 then
		return "No streak yet"
	end
	return `{n}-day streak`
end

-- A margin as a sentence piece: "won by 62", "lost by 40", "a tie".
function Daily.margin(margin: number): string
	if margin > 0 then
		return `won by {margin}`
	elseif margin < 0 then
		return `lost by {-margin}`
	end
	return "a tie"
end

-- The card's word on today's own run: "Won by 62 today", "Run in progress", "Not played yet".
function Daily.today(played: boolean, margin: number?): string
	if margin ~= nil then
		local text = Daily.margin(margin)
		return `{string.upper(string.sub(text, 1, 1))}{string.sub(text, 2)} today`
	elseif played then
		return "Run in progress"
	end
	return "Not played yet"
end

-- The viewer's line under the day's list.
function Daily.youLine(you: { rank: number?, margin: number }?, played: boolean, top: number): string
	if you == nil then
		return if played then "You: your run will show here" else "You: play today's race to get on it"
	end
	local points = if you.margin > 0 then `+{you.margin}` else tostring(you.margin)
	if you.rank then
		return `You: #{you.rank} · {points}`
	end
	return `You: not in the top {top} · {points}`
end

-- Results: the line under the Daily Race eyebrow.
function Daily.resultLine(run: { counted: boolean, margin: number, forfeit: boolean }): string
	if run.forfeit then
		return if run.counted
			then "You left, so today's run counts as a full loss."
			else "Practice run: you left."
	end
	local margin = run.margin
	local text = if margin > 0
		then `You won by {margin} votes.`
		elseif margin < 0 then `You lost by {-margin} votes.`
		else "A tie on votes."
	return if run.counted
		then text
		else `Practice run: {string.lower(string.sub(text, 1, 1))}{string.sub(text, 2)}`
end

-- Results: the rank line of a counted run.
function Daily.rankLine(rank: number?, top: number): string
	if rank then
		return `Rank today: #{rank}`
	end
	return `Rank today: not in the top {top} yet`
end

-- Results: why a practice run does not count.
function Daily.practiceLine(margin: number?): string
	if margin ~= nil then
		return `Only your first run counts. Today: {Daily.margin(margin)}.`
	end
	return "Only your first run each day counts."
end

return table.freeze(Daily)
