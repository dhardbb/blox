--!strict
-- The client's copy of what the server sent (the latest State payload and lobby
-- status) plus a short message log. Screens read it; Net writes it. Listeners
-- run after every change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Daily = require(ReplicatedStorage.Shared.Net.Daily)
local Leaderboard = require(ReplicatedStorage.Shared.Net.Leaderboard)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Session = require(ReplicatedStorage.Shared.Net.Session)

-- One line of the message log. Ids only ever grow, so a screen tells "new" apart
-- from "already seen" by id even after old lines have been dropped.
export type Message = {
	id: number,
	text: string,
	rejected: boolean, -- the server turned a request down (Net's "Rejected")
	reason: string?, -- the rejection's reason code, for screens that explain it
}

export type State = {
	payload: Session.StatePayload?,
	lobby: Remotes.LobbyStatus?,
	messages: { Message }, -- newest last, for toasts and the week card
	resultSeen: boolean, -- the player dismissed the last match's result screen
	prePick: any?, -- the selection remembered for the next Select
	rating: Remotes.RatingChange?, -- the rating change after the last rated match
	leaderboard: Leaderboard.Board?, -- the global leaderboard as the server last sent it (D-059)
	leaving: string?, -- the match this player chose to leave: its end skips Results (D-059)
	review: Remotes.ReviewBoard?, -- admins: the reported names, as last sent (D-069)
	daily: Daily.Info?, -- today's Daily Race, the streak and the day's board, as last sent (D-080)
	dailyRun: Daily.Run?, -- the Daily Race run that ended last (its Results summary, D-080)
}

local Store = {}

local MAX_MESSAGES = 20
local lastMessageId = 0 -- id of the newest message ever said

local state: State = {
	payload = nil,
	lobby = nil,
	messages = {},
	resultSeen = false,
	prePick = nil,
	rating = nil,
	leaderboard = nil,
	leaving = nil,
	review = nil,
	daily = nil,
	dailyRun = nil,
}
local listeners: { (State) -> () } = {}

function Store.get(): State
	return state
end

local function changed()
	for _, listener in table.clone(listeners) do
		task.spawn(listener, state)
	end
end

function Store.subscribe(listener: (State) -> ()): () -> ()
	table.insert(listeners, listener)
	return function()
		local at = table.find(listeners, listener)
		if at then
			table.remove(listeners, at)
		end
	end
end

function Store.setPayload(payload: Session.StatePayload)
	local previous = state.payload
	if previous == nil or previous.matchId ~= payload.matchId then
		state.resultSeen = false
	end
	-- The player left this match: its end goes straight back to the lobby.
	if state.leaving ~= nil and state.leaving == payload.matchId and payload.stage == "Over" then
		state.resultSeen = true
	end
	state.payload = payload
	changed()
end

-- The server took this player's report on seat `seat`'s custom name (D-069):
-- hide it here at once. Once a match is over the server sends no new State,
-- so Results would otherwise keep showing it. A copy of the payload, so every
-- screen sees a new one and redraws with the candidate's own name.
function Store.hideName(seat: number)
	local payload = state.payload
	local entry = if payload then payload.view.players[seat] else nil
	if payload == nil or entry == nil or entry.customName == nil then
		return
	end
	local players = table.clone(payload.view.players)
	local hidden = table.clone(entry)
	hidden.customName = nil
	players[seat] = hidden
	local view = table.clone(payload.view)
	view.players = players
	local copy = table.clone(payload)
	copy.view = view
	state.payload = copy
	changed()
end

function Store.setLobby(lobby: Remotes.LobbyStatus)
	state.lobby = lobby
	changed()
end

function Store.say(text: string, rejected: boolean?, reason: string?)
	lastMessageId += 1
	table.insert(
		state.messages,
		{ id = lastMessageId, text = text, rejected = rejected == true, reason = reason }
	)
	while #state.messages > MAX_MESSAGES do
		table.remove(state.messages, 1)
	end
	changed()
end

function Store.dismissResult()
	state.resultSeen = true
	changed()
end

function Store.setReview(board: Remotes.ReviewBoard)
	state.review = board
	changed()
end

-- Today's Daily Race as the server sent it (D-080). A message that carries a
-- finished run also keeps that run for the Results screen.
function Store.setDaily(info: Daily.Info)
	state.daily = info
	if info.run then
		state.dailyRun = info.run
	end
	changed()
end

function Store.setLeaderboard(board: Leaderboard.Board)
	state.leaderboard = board
	changed()
end

-- The player confirmed leaving match `matchId` (D-059): when the server ends it,
-- the Lobby shows instead of the Results screen.
function Store.leave(matchId: string)
	state.leaving = matchId
end

function Store.setRating(change: Remotes.RatingChange)
	state.rating = change
	changed()
end

function Store.setPrePick(pick: any)
	state.prePick = pick
	changed()
end

return Store
