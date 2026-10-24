--!strict
-- Copy for the start screen's extras (docs/DESIGN.md D-059): the bot level
-- picker, the global leaderboard, "How to play" for brand-new players, and the
-- "Leave match" confirmation. Plain words, labels of at most 8 words, any text
-- block at most 30 words (the UI audit's wallOfText). Numbers come from Config,
-- so a balance change needs no edit here. Pure.

local ConfigModule = require("../../Sim/Config")
local StateData = require("../../Sim/StateData")

type Config = ConfigModule.Config

local Lobby = {}

-- ---------------------------------------------------------------- bot level

-- The levels the Lobby offers for Play vs Bot, easiest first. The Practice
-- request carries the chosen one as `difficulty`; the server decides what each
-- level means.
Lobby.LEVELS = table.freeze({ "Easy", "Medium", "Hard", "Extreme" })
Lobby.DEFAULT_LEVEL = "Medium"

-- ---------------------------------------------------------------- leaderboard

Lobby.BOARD_TITLE = "Leaderboard"
Lobby.BOARD_SEE_ALL = "See all"
Lobby.BOARD_OPEN = "Leaderboard"
Lobby.BOARD_SHEET = "Top 50 players"
Lobby.BOARD_LOADING = "Loading the leaderboard…"
Lobby.BOARD_UNAVAILABLE = "Leaderboard unavailable"
Lobby.BOARD_EMPTY = "No ranked players yet. Play someone (not the bot) to get on the board."
Lobby.BOARD_HOW = "Ranked by rating. Only matches against players count."

-- The viewer's line under the list.
function Lobby.youLine(you: { rank: number?, rating: number }?, top: number): string
	if you == nil then
		return "You: play someone (not the bot) to get ranked"
	end
	if you.rank then
		return `You: #{you.rank} · {you.rating}`
	end
	return `You: not in the top {top} · {you.rating}`
end

-- ---------------------------------------------------------------- how to play

Lobby.HOWTO_TITLE = "How to play"
Lobby.HOWTO_NEXT = "Next"
Lobby.HOWTO_BACK = "Back"
Lobby.HOWTO_DONE = "Got it"

export type Page = {
	id: string, -- "goal" | "week" | "actions" | "events" | "night": which picture
	title: string,
	text: string, -- at most 30 words
}

-- The three beats of a week, for the "Each week" picture.
Lobby.WEEK_STEPS = table.freeze({ "Plan your actions", "Both plans are revealed", "The map moves" })

-- Election night's picture: three calls (state name, its votes, won by you).
function Lobby.nightCalls(): { { state: string, votes: number, you: boolean } }
	local out = {}
	for _, call in { { id = "OH", you = true }, { id = "GA", you = false }, { id = "AZ", you = true } } do
		local record = StateData.byId[call.id]
		if record then
			table.insert(out, { state = record.name, votes = record.ev, you = call.you })
		end
	end
	return out
end

-- The pages, in order.
function Lobby.howTo(config: Config): { Page }
	return {
		{
			id = "goal",
			title = "The goal",
			text = `Every state is worth votes. Win a state and you get all of them. After week {config.WEEKS}, the first to {config.EV_TO_WIN} votes wins.`,
		},
		{
			id = "week",
			title = "Each week",
			text = "You and your opponent plan at the same time, in secret. Then both plans are revealed together and the polls move.",
		},
		{
			id = "actions",
			title = "Your actions",
			text = `You get {config.AP_PER_WEEK} actions a week. Tap a state, pick an action, then Lock in. Rallies and ads count extra on your 3 issues.`,
		},
		{
			id = "issues",
			title = "Your issues",
			text = "Pick 3 of these 8 issues at the start. Rallies and ads on them count extra where states care. On the map, a symbol shows each state's top issue.",
		},
		{
			id = "events",
			title = "Debates and events",
			text = "Some weeks bring an event: pick a side, A, B or C. Debates are three quick rounds: Defend, Attack or Pivot. Win a round and its states swing your way.",
		},
		{
			id = "night",
			title = "Election night",
			text = `After the last week, every state is called, one by one. Ground game adds its hidden votes now. First to {config.EV_TO_WIN} wins.`,
		},
	}
end

-- "2 of 5"
function Lobby.pageCount(page: number, pages: number): string
	return `{page} of {pages}`
end

-- ---------------------------------------------------------------- leave match

Lobby.LEAVE = "Leave match"
Lobby.LEAVE_STAY = "Keep playing"
Lobby.LEAVE_HUMAN_TITLE = "Leave and forfeit?"
Lobby.LEAVE_HUMAN_TEXT = "This counts as a loss, and your opponent wins."
Lobby.LEAVE_HUMAN_CONFIRM = "Leave and forfeit"
Lobby.LEAVE_BOT_TITLE = "Leave this practice match?"
Lobby.LEAVE_BOT_TEXT = "Practice never changes your rating."
Lobby.LEAVE_BOT_CONFIRM = "Leave match"

return table.freeze(Lobby)
