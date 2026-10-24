--!strict
-- Copy for matchmaking (docs/DESIGN.md D-083): the online count, a bot game
-- while waiting, "Opponent found!", the match on its way, invites and the
-- rematch. Labels of at most 8 words, text blocks of at most 30 (the UI
-- audit). Pure.

local Matchmaking = {}

-- ---------------------------------------------------------------- lobby

Matchmaking.WAIT_BOT = "Play a bot while you wait"
Matchmaking.WAIT_BOT_HINT = "You keep your place in line. We'll ask before you leave the bot game."

-- "Looking for an opponent…" hint while queued: the online count when known.
function Matchmaking.queueHint(online: string?, waiting: number): string
	if waiting > 1 then
		return if online then `{online} · {waiting} waiting here` else `{waiting} players waiting`
	end
	return if online
		then `{online} · you'll start as soon as someone joins.`
		else "You'll start as soon as someone joins."
end

-- The match on its way (Lobby state "Found").
Matchmaking.FOUND_TITLE = "Opponent found!"
Matchmaking.FOUND_WAITING = "They're finishing a bot game. Waiting for them to join…"
Matchmaking.FOUND_JOINING = "Joining the match…"
Matchmaking.FOUND_ARRIVING = "Waiting for your opponent to arrive…"
Matchmaking.LEAVING_TITLE = "Back to the lobby"
Matchmaking.FOUND_LEAVING = "Taking you back to the lobby…"

-- "Opponent found! Leave this bot game?" during a bot game while waiting.
Matchmaking.PROMPT_TITLE = "Opponent found!"
Matchmaking.PROMPT_TEXT = "Leave this bot game and join the match?"
Matchmaking.PROMPT_NOTE = "Keep playing takes you out of the queue."
Matchmaking.PROMPT_JOIN = "Join match"
Matchmaking.PROMPT_KEEP = "Keep playing"

function Matchmaking.secondsLeft(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return if s == 1 then "1 second left" else `{s} seconds left`
end

-- ---------------------------------------------------------------- invites

Matchmaking.INVITE = "Invite a friend"
Matchmaking.INVITE_PROMPT = "Invite a friend to a match of Landslide!" -- the Roblox prompt's message
Matchmaking.INVITE_HINT = "Your friend joins your private match straight away."
Matchmaking.INVITE_UNAVAILABLE = "Invites aren't available here. Share your code instead."

-- ---------------------------------------------------------------- rematch

Matchmaking.REMATCH = "Rematch"
Matchmaking.REMATCH_ASKED = "Rematch asked"
Matchmaking.REMATCH_GONE = "Opponent left"
Matchmaking.REMATCH_EXPIRED = "Rematch expired"

-- The action bar's status line on Results.
function Matchmaking.rematchStatus(state: string, seconds: number?, them: string): string?
	local left = if seconds then ` · {math.max(0, math.ceil(seconds))} s` else ""
	if state == "Open" and seconds then
		return `Rematch? You both have to tap{left}`
	elseif state == "Waiting" then
		return `Waiting for {them}…{left}`
	elseif state == "Asked" then
		return `{them} wants a rematch!{left}`
	elseif state == "Started" then
		return "Rematch on! Starting…"
	end
	return nil
end

return table.freeze(Matchmaking)
