--!strict
-- Remote names and message shapes. The server creates one folder of two
-- RemoteEvents in ReplicatedStorage: ToServer (client requests) and ToClient
-- (server messages). Every request is one table with an `op`; every server
-- message is one table with a `kind`. Net/Schemas validates requests at runtime.

local Lobby = require("./Lobby")
local Profile = require("./Profile")
local Session = require("./Session")

local Remotes = {}

Remotes.FOLDER = "Remotes"
Remotes.TO_SERVER = "ToServer"
Remotes.TO_CLIENT = "ToClient"

-- Client -> server operations.
export type Op =
	"Queue" -- join the public queue
	| "Host" -- open a private match and get a code: { events? } (false = no event deck)
	| "Join" -- join a private match: { code }
	| "Practice" -- play the bot now: { difficulty? } (D-057)
	| "Leave" -- leave the queue or a hosted code (not a match in progress)
	| "PrePick" -- remember a candidate and platform for Select: { pick }
	| "SetColor" -- save a chosen color (Color Pass owners, D-055): { color? } (absent = auto)
	| "Claim" -- Select step 1: claim a candidate (D-048): { matchId, step, input = candidate id }
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
	events: boolean?, -- Host: false turns the event deck off for this private match
	color: string?, -- SetColor: one of Candidates.colors; absent = auto (red or blue)
	difficulty: string?, -- Practice: "Easy" | "Medium" | "Hard" | "Extreme"; absent or anything else = "Medium" (D-057)
}

-- The Color Pass as the lobby shows it (D-055). Absent from LobbyStatus while
-- Net/Products.COLOR_PASS_ID is 0: no color option anywhere.
export type ColorPass = {
	id: number, -- the pass id, for MarketplaceService:PromptGamePassPurchase
	owned: boolean, -- the server's check (false while unknown or if the check failed)
}

-- Lobby status for one player.
export type LobbyStatus = {
	state: Lobby.PlayerState,
	code: string?, -- while hosting
	queued: number, -- players waiting in the public queue
	full: boolean, -- the server has no room for another match
	profile: Profile.Summary?, -- the player's saved rating and record; absent until it has loaded
	color: string?, -- the saved color pick; absent = auto (red or blue)
	colorPass: ColorPass?, -- absent while the pass is not set up
}

-- Rating change after a rated match (message kind "Rating").
export type RatingChange = {
	matchId: string,
	before: number,
	after: number,
}

-- Server -> client messages.
export type Message = {
	kind: "Lobby" | "State" | "Notice" | "Rating" | "Rejected",
	lobby: LobbyStatus?,
	state: Session.StatePayload?,
	notice: string?, -- e.g. "OpponentDisconnected"
	rating: RatingChange?, -- Rating: sent once when a rated match ends
	op: string?, -- Rejected: the request's op
	reason: string?, -- Rejected: reason code
}

return table.freeze(Remotes)
