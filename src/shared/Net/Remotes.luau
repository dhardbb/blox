--!strict
-- Remote names and message shapes. The server creates one folder of two
-- RemoteEvents in ReplicatedStorage: ToServer (client requests) and ToClient
-- (server messages). Every request is one table with an `op`; every server
-- message is one table with a `kind`. Net/Schemas validates requests at runtime.

local Leaderboard = require("./Leaderboard")
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
	| "Practice" -- play the bot now: { difficulty?, tutorial? } (D-057, D-075)
	| "Leave" -- leave the queue or a hosted code (not a match in progress)
	| "PrePick" -- remember a candidate and platform for Select: { pick }
	| "SetColor" -- save a chosen color (Color Pass owners, D-055): { color? } (absent = auto)
	| "SetName" -- name your candidate (Name Pass owners, eligible players, D-069): { name? } (absent = its own name)
	| "ReportName" -- report a custom name you were shown (D-069): { userId } (the setter's, as a string)
	| "ReviewList" -- admins: ask for the reported names (D-069); answered with a "Review" message
	| "ReviewKeep" -- admins: keep a reported name, dismissing its reports: { userId, name }
	| "ReviewRemove" -- admins: remove a reported name and block it as whole words (D-078): { userId, name }
	| "Claim" -- Select step 1: claim a candidate (D-048): { matchId, step, input = candidate id }
	| "ClaimColor" -- Select, Color Pass owners: claim a color, first come first served (D-061): { matchId, step, color }
	| "Submit" -- lock in this stage's input: { matchId, step, input }
	| "Bank" -- take 15 s of time bank: { matchId, step }
	| "Skip" -- skip the resolve animation or election night: { matchId, step }
	| "Resync" -- ask for the current state again
	| "Leaderboard" -- ask for the global leaderboard (D-059); answered with a "Leaderboard" message
	| "Forfeit" -- leave the match in progress and lose it (D-059): { matchId }
	| "SetTimersOff" -- admins: the "Timers off" toggle, saved and applied to their match (D-080): { on }

export type Request = {
	op: Op,
	code: string?,
	pick: any?,
	matchId: string?,
	step: number?,
	input: any?,
	events: boolean?, -- Host: false turns the event deck off for this private match
	color: string?, -- SetColor: one of Candidates.colors; absent = auto (red or blue). ClaimColor: the color (required)
	difficulty: string?, -- Practice: "Easy" | "Medium" | "Hard" | "Extreme"; absent or anything else = "Medium" (D-057)
	tutorial: boolean?, -- Practice: true replays the tutorial (How to play, D-075): Easy bot, no choice timers
	name: string?, -- SetName: the custom name as typed (absent = the candidate's own); ReviewKeep/ReviewRemove: the name the admin saw
	userId: string?, -- ReportName, ReviewKeep, ReviewRemove: the setter's user id (digits)
	on: boolean?, -- SetTimersOff: true turns the admin's choice timers off (D-080)
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
	review: { count: number }?, -- admins only (D-069): reported names waiting for review
	admin: { timersOff: boolean }?, -- admins only (D-080): their saved "Timers off" toggle
}

-- One reported name in the admins' review panel (D-069).
export type ReviewEntry = {
	userId: string, -- the setter
	name: string, -- the reported name
	owner: string, -- the setter's username ("Player <id>" if unknown)
	count: number, -- distinct reporters
	first: number, -- unix time of the first report
	last: number, -- unix time of the latest report
}

-- The review panel's list (message kind "Review"); ok false if it could not be read.
export type ReviewBoard = {
	ok: boolean,
	entries: { ReviewEntry },
}

-- Rating change after a rated match (message kind "Rating").
export type RatingChange = {
	matchId: string,
	before: number,
	after: number,
}

-- Server -> client messages.
export type Message = {
	kind: "Lobby" | "State" | "Notice" | "Rating" | "Rejected" | "Leaderboard" | "Review",
	lobby: LobbyStatus?,
	state: Session.StatePayload?,
	notice: string?, -- e.g. "OpponentDisconnected"
	rating: RatingChange?, -- Rating: sent once when a rated match ends
	leaderboard: Leaderboard.Board?, -- Leaderboard: the top list and where this player stands
	review: ReviewBoard?, -- Review: the reported names (admins only, D-069)
	op: string?, -- Rejected: the request's op
	reason: string?, -- Rejected: reason code
}

return table.freeze(Remotes)
