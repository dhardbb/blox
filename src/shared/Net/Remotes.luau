--!strict
-- Remote names and message shapes. The server creates one folder of two
-- RemoteEvents in ReplicatedStorage: ToServer (client requests) and ToClient
-- (server messages). Every request is one table with an `op`; every server
-- message is one table with a `kind`. Net/Schemas validates requests at runtime.

local Daily = require("./Daily")
local Leaderboard = require("./Leaderboard")
local Lobby = require("./Lobby")
local Profile = require("./Profile")
local Rematch = require("./Rematch")
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
	| "DailyRace" -- play today's Daily Race (D-080): today's candidate, the Hard bot; the first run past week 1 counts
	| "Daily" -- ask for today's Daily Race and its board (D-080); answered with a "Daily" message
	| "WaitBot" -- play the bot while waiting in the queue (D-080): { difficulty? }
	| "Answer" -- answer "Opponent found! Leave this bot game?" (D-080): { accept }
	| "Rematch" -- on Results: play the same opponent again (D-080): { matchId } (the finished match)
	| "Return" -- in a match server: go back to a lobby server (D-080)

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
	accept: boolean?, -- Answer: true joins the match found, false keeps playing the bot (D-080)
}

-- An opponent was found and the match is on its way (LobbyStatus.found, D-080).
export type FoundPhase =
	"Answer" -- you are in a bot game: join the match or keep playing (by untilAt)
	| "Waiting" -- the opponent is in a bot game and has until untilAt to answer
	| "Joining" -- a match server is being set up for you two, or you are on your way
	| "Arriving" -- you are in the match server; your opponent is on their way
	| "Leaving" -- on your way back to a lobby server

export type Found = {
	phase: FoundPhase,
	untilAt: number?, -- server time: Answer and Waiting
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
	online: number?, -- players online in every server of the game (D-080); absent while unknown
	botAt: number?, -- Queued: server time from which a bot game while waiting is offered (D-080)
	found: Found?, -- Found, or InMatch in a bot game while waiting: the match on its way (D-080)
	matchServer: boolean?, -- this is a match server: Back to lobby goes to a lobby server (D-080)
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
	kind: "Lobby"
		| "State"
		| "Notice"
		| "Rating"
		| "Rejected"
		| "Leaderboard"
		| "Review"
		| "Daily"
		| "Rematch",
	lobby: LobbyStatus?,
	state: Session.StatePayload?,
	notice: string?, -- e.g. "OpponentDisconnected"
	rating: RatingChange?, -- Rating: sent once when a rated match ends
	leaderboard: Leaderboard.Board?, -- Leaderboard: the top list and where this player stands
	review: ReviewBoard?, -- Review: the reported names (admins only, D-069)
	daily: Daily.Info?, -- Daily: today's race, your streak and the day's board (D-080)
	rematch: Rematch.Status?, -- Rematch: where a rematch of the last match stands (D-080)
	op: string?, -- Rejected: the request's op
	reason: string?, -- Rejected: reason code
}

return table.freeze(Remotes)
