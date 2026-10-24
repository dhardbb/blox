--!strict
-- Short copy for the debate stage (docs/DESIGN.md D-072): the moderator's
-- questions, the result cells, the clash's stamp and the verdict. Plain words,
-- fictional and generic: no real politicians, parties, slogans or positions.
-- Pure: reads only Config, the player's own View and Shared/UI/Swing.
--
--   Words.question(topic) -> string           the moderator's question for a topic
--   Words.cell(margin) -> string              "+3", "−2", "=" (a result cell)
--   Words.cells(row) -> string                "D +4 · A +3 · P =" (against their Defend, Attack, Pivot)
--   Words.facts(board) -> { string }          "Your issue", "You lead its states"...
--   Words.stamp(view, round, name) -> (string, tone)   "YOU WIN BY 3", "REX WINS BY 3", "SPLIT"
--                                             ("THEY WIN BY 3" for a name too long for a stamp)
--   Words.crowdStamp(lead, name) -> (string, tone)    "YOU WON THE CROWD", "REX WON THE CROWD",
--                                             "THEY WON THE CROWD" (a long name), "AN EVEN CROWD"
--   Words.counterLine(round, view) -> string? "Pivot beats Defend: +3"
--   Words.crowdLine(view, crowd, name) -> string  "You +4", "Rex +2", "Even" (who leads the crowd;
--                                             "Them +2" for a long name)
--   Words.zinger(board) -> string             the Zinger toggle's label

local Issues = require("../../Sim/Issues")
local SimState = require("../../Sim/State")
local Swing = require("../Swing")
local ViewModule = require("../../Sim/View")

type View = ViewModule.View

local Words = {}

-- One neutral question per issue. Fictional places, no policy positions.
local QUESTIONS: { [string]: string } = {
	Jobs = "The mill in Harlow Falls just closed. What do you tell those workers?",
	Health = "Clinics out west have month-long waits. What would you do?",
	Schools = "Classrooms in Pine Ridge are packed. What's your answer?",
	Environment = "The Marrow River flooded again this spring. What's your plan?",
	Safety = "Neighbors in Eastgate say they don't feel safe. What do you say?",
	Transit = "The Route 9 bridge has been closed for a year. Why?",
	Technology = "Half of Dunmore has no fast internet. What will you do?",
	Farms = "Grain prices fell and the co-ops are worried. Your move?",
}

function Words.question(topic: string): string
	return QUESTIONS[topic] or `{(Issues.displayName :: any)[topic] or topic}: what's your plan?`
end

local MINUS = "−" -- U+2212

-- A result cell: your score minus theirs, sign always shown ("=" for a split).
function Words.cell(margin: number): string
	if margin > 0 then
		return `+{margin}`
	elseif margin < 0 then
		return `{MINUS}{-margin}`
	end
	return "="
end

local INITIAL: { [string]: string } = { Defend = "D", Attack = "A", Pivot = "P" }

-- A move's result cells against their Defend, Attack and Pivot: "D +4 · A +3 · P =".
function Words.cells(row: Swing.MoveRow): string
	local parts: { string } = {}
	for k, move in { "Defend", "Attack", "Pivot" } do
		table.insert(parts, `{INITIAL[move]} {Words.cell(row.cells[k])}`)
	end
	return table.concat(parts, " · ")
end

-- The facts that set this round's strengths, as short pills.
function Words.facts(board: Swing.DebateBoard): { string }
	local out: { string } = {}
	if board.ownsTopic then
		table.insert(out, "Your issue")
	end
	if board.theirTopic then
		table.insert(out, "Their issue")
	end
	if board.ground > 0 then
		table.insert(out, "You lead its states")
	elseif board.ground < 0 then
		table.insert(out, "You trail its states")
	end
	table.insert(out, `Counter +{board.counter}`)
	return out
end

export type Tone = "good" | "loss" | "text"

-- Characters of the opponent's name a stamp spells out: a longer one (a custom
-- name runs to 16) makes the stamp too wide for a phone, so it says "THEY".
Words.STAMP_NAME_MAX = 10

-- The opponent on a stamp: "REX", or "THEY" for a long name.
local function stampName(theirName: string): (string, boolean)
	if (utf8.len(theirName) or #theirName) > Words.STAMP_NAME_MAX then
		return "THEY", true
	end
	return string.upper(theirName), false
end

-- The clash's stamp and its tone: who won the round and by how much.
function Words.stamp(view: View, round: SimState.DebateRound, theirName: string): (string, Tone)
	if round.winner == 0 then
		return "SPLIT", "text"
	elseif round.winner == view.you then
		return `YOU WIN BY {round.margin}`, "good"
	end
	local who, they = stampName(theirName)
	return `{who} {if they then "WIN" else "WINS"} BY {round.margin}`, "loss"
end

-- The verdict's stamp and its tone: who won the crowd (`lead` = your crowd
-- less theirs).
function Words.crowdStamp(lead: number, theirName: string): (string, Tone)
	if lead > 0 then
		return "YOU WON THE CROWD", "good"
	elseif lead < 0 then
		return `{(stampName(theirName))} WON THE CROWD`, "loss"
	end
	return "AN EVEN CROWD", "text"
end

-- "Pivot beats Defend: +3" when a counter landed, else nil.
function Words.counterLine(round: SimState.DebateRound, view: View): string?
	for p, pick in round.picks do
		for q, other in round.picks do
			if p ~= q and round.countered[q] and not round.canned[p] then
				local beats = (
					{ Defend = "Attack", Attack = "Pivot", Pivot = "Defend" } :: { [string]: string }
				)[pick]
				if beats == other then
					local score = round.scores[p] - round.strengths[p]
					local who = if p == view.you then "Your" else "Their"
					return `{who} {pick} beats {other}: +{score}`
				end
			end
		end
	end
	return nil
end

-- Who leads the crowd, short enough for the meter: "You +4", "Rex +2", "Even".
function Words.crowdLine(view: View, crowd: { number }, theirName: string): string
	local me = view.you
	local best, lead = 0, 0
	for p, c in crowd do
		if p ~= me then
			best = math.max(best, c)
		end
	end
	lead = (crowd[me] or 0) - best
	if lead > 0 then
		return `You +{lead}`
	elseif lead < 0 then
		-- A long name would not fit the meter's caption on a phone.
		local long = (utf8.len(theirName) or #theirName) > Words.STAMP_NAME_MAX
		return `{if long then "Them" else theirName} +{-lead}`
	end
	return "Even"
end

-- The Zinger toggle's label (at most 8 words).
function Words.zinger(board: Swing.DebateBoard, staked: boolean): string
	if board.zingers <= 0 then
		return "Zinger spent"
	elseif staked then
		return `Zinger staked: a win counts ×{board.zingerMult}`
	end
	return `Stake Zinger: a win counts ×{board.zingerMult}`
end

-- A move's button title: "Defend  6" (a Pivot's landing issue goes on the line under it).
function Words.moveTitle(row: Swing.MoveRow): string
	return `{row.move}  {row.strength}`
end

-- A move's parts for the "Why?" sheet: "Defend 6 = base 2 + your issue +3 + ...".
function Words.parts(row: Swing.MoveRow): string
	local terms: { string } = {}
	for _, part in row.parts do
		local sign = if part.points < 0 then MINUS else "+"
		table.insert(terms, `{Swing.partName(part.kind)} {sign}{math.abs(part.points)}`)
	end
	return `{row.move} {row.strength} = {table.concat(terms, ", ")}. Beats {row.beats}.`
end

return table.freeze(Words)
