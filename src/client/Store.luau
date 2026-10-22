--!strict
-- The client's copy of what the server sent (the latest State payload and lobby
-- status) plus a short message log. Screens read it; Net writes it. Listeners
-- run after every change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Session = require(ReplicatedStorage.Shared.Net.Session)

export type State = {
	payload: Session.StatePayload?,
	lobby: Remotes.LobbyStatus?,
	messages: { string }, -- newest last, for toasts and the debug panel
	resultSeen: boolean, -- the player dismissed the last match's result screen
	prePick: any?, -- the selection remembered for the next Select
}

local Store = {}

local MAX_MESSAGES = 20

local state: State = {
	payload = nil,
	lobby = nil,
	messages = {},
	resultSeen = false,
	prePick = nil,
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
	state.payload = payload
	changed()
end

function Store.setLobby(lobby: Remotes.LobbyStatus)
	state.lobby = lobby
	changed()
end

function Store.say(message: string)
	table.insert(state.messages, message)
	while #state.messages > MAX_MESSAGES do
		table.remove(state.messages, 1)
	end
	changed()
end

function Store.dismissResult()
	state.resultSeen = true
	changed()
end

function Store.setPrePick(pick: any)
	state.prePick = pick
	changed()
end

return Store
