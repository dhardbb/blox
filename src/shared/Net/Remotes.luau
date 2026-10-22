--!strict
-- Remote names and message shapes. The server creates one folder of two
-- RemoteEvents in ReplicatedStorage: ToServer (client requests) and ToClient
-- (server messages). Every request is one table with an `op`; every server
-- message is one table with a `kind`. Net/Schemas validates requests at runtime.

local Session = require("./Session")

local Remotes = {}

Remotes.FOLDER = "Remotes"
Remotes.TO_SERVER = "ToServer"
Remotes.TO_CLIENT = "ToClient"

-- Client -> server operations.
export type Op =
	"Queue" -- join the public queue
	| "Host" -- open a private match and get a code
	| "Join" -- join a private match: { code }
	| "Practice" -- play the bot now
	| "Leave" -- leave the queue or a hosted code (not a match in progress)
	| "PrePick" -- remember a candidate/color/platform for Select: { pick }
	| "Submit" -- lock in this stage's input: { matchId, step, input }
	| "Bank" -- take 15 s of time bank: { matchId, step }
	| "Skip" -- skip the resolve animation or election night: { matchId, step }
	| "Resync" -- ask for the current state again

export type Request = {
	op: Op,
	code: string?,
	pick: any?,
	matchId: string?,
	step: number?,
	input: any?,
}

-- Lobby status for one player.
export type LobbyStatus = {
	state: "Idle" | "Queued" | "Hosting" | "InMatch",
	code: string?, -- while hosting
	queued: number, -- players waiting in the public queue
	full: boolean, -- the server has no room for another match
}

-- Server -> client messages.
export type Message = {
	kind: "Lobby" | "State" | "Notice" | "Rejected",
	lobby: LobbyStatus?,
	state: Session.StatePayload?,
	notice: string?, -- e.g. "OpponentDisconnected"
	op: string?, -- Rejected: the request's op
	reason: string?, -- Rejected: reason code
}

return table.freeze(Remotes)
