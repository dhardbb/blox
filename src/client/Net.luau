--!strict
-- Talks to the server: sends requests on ToServer and feeds ToClient messages
-- into the Store. Match requests are stamped with the current match and step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Store = require(script.Parent.Store)

local Net = {}

-- Readable text for rejection codes: every code the server can send back (Plan,
-- Session, Draft, Match, Schemas, Lobby and the server's own checks). The greyed
-- action buttons read "Greyed out: {text}", so the plan reasons are phrased to fit.
local REASONS: { [string]: string } = {
	-- Plan (Plan.Reason)
	WrongPhase = "You can't do that right now.",
	BadShape = "The server couldn't read that request.",
	TooManyActions = "That's more actions than one week allows.",
	UnknownKind = "That isn't an action you can take.",
	UnknownState = "That isn't a state on this map.",
	UnknownIssue = "That isn't an issue in this game.",
	UnknownRegion = "That isn't a region on this map.",
	BadTarget = "That action can't target that player.",
	BadUnits = "That's not a valid number of ground-game units.",
	NotEnoughAP = "Not enough action points for that plan.",
	NotEnoughMoney = "Not enough money for that plan.",
	GotvCap = "That's over the ground-game limit for a state.",
	DuplicatePoll = "You already poll that state this week.",
	PivotUsed = "You can only pivot once per match.",
	BadPivot = "That pivot isn't allowed.",
	BadFocus = "Pick one of this debate's topics to focus on.",
	UnexpectedFocus = "The debate focus is picked on its own screen, not in the plan.",
	BadChoice = "That isn't a valid answer to this week's event.",
	UnexpectedChoice = "The stance is picked on its own screen, not in the plan.",
	-- Session (Session.Reason)
	StaleStep = "Too late: that step is over.",
	NotInput = "This part of the match isn't taking input right now.",
	AlreadyLocked = "You already locked in.",
	NoBank = "No time bank left.",
	NotSkippable = "This part can't be skipped.",
	Over = "The match is over.",
	-- Select and Draft
	UnknownCandidate = "Pick one of the eight candidates.",
	UnknownColor = "Pick one of the six colors.",
	BadPlatform = "Pick exactly three different issues.",
	UnknownPlayer = "The server doesn't know that player.",
	BadChoiceCount = "Pick one state, or two with a backup.",
	DuplicateChoice = "Your two choices must be different states.",
	IllegalChoice = "That state can't be picked this round.",
	-- Lobby
	ServerFull = "This server is full. Try again in a minute.",
	NoSuchCode = "No match with that code.",
	OwnCode = "That's your own code. Give it to a friend.",
	CodeTaken = "That code is already in use. Try hosting again.",
	InMatch = "You're already in a match.",
	BadCode = "Codes are 5 characters: letters A-Z and numbers 2-9.",
	-- The server's own checks
	NotInMatch = "That match isn't running for you anymore.",
	UnknownOp = "The server doesn't know that request.",
	RateLimited = "Slow down a little.",
	Internal = "Something went wrong on the server. Try again.",
	Rejected = "The server turned that down.",
}

local NOTICES: { [string]: string } = {
	OpponentDisconnected = "Your opponent disconnected. Their moves auto-submit after the grace period.",
	OpponentReconnected = "Your opponent is back.",
}

function Net.reasonText(reason: string?): string
	return REASONS[reason or ""] or `Rejected: {reason or "unknown"}`
end

local toServer: RemoteEvent? = nil

function Net.start()
	local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER)
	toServer = folder:WaitForChild(Remotes.TO_SERVER) :: RemoteEvent
	local toClient = folder:WaitForChild(Remotes.TO_CLIENT) :: RemoteEvent
	toClient.OnClientEvent:Connect(function(message: Remotes.Message)
		if message.kind == "State" and message.state then
			Store.setPayload(message.state)
		elseif message.kind == "Lobby" and message.lobby then
			Store.setLobby(message.lobby)
		elseif message.kind == "Rating" and message.rating then
			Store.setRating(message.rating)
		elseif message.kind == "Notice" then
			Store.say(NOTICES[message.notice or ""] or (message.notice or "Notice"))
		elseif message.kind == "Rejected" then
			Store.say(Net.reasonText(message.reason), true, message.reason)
		end
	end)
	Net.send("Resync")
end

function Net.send(op: string, fields: { [string]: any }?)
	local remote = toServer
	if remote == nil then
		return
	end
	local message: { [string]: any } = { op = op }
	if fields then
		for key, value in fields do
			message[key] = value
		end
	end
	remote:FireServer(message)
end

local function matchRequest(op: string, input: any?)
	local payload = Store.get().payload
	if payload == nil or payload.stage == "Over" then
		return
	end
	Net.send(op, { matchId = payload.matchId, step = payload.step, input = input })
end

function Net.submit(input: any)
	matchRequest("Submit", input)
end

function Net.bank()
	matchRequest("Bank")
end

function Net.skip()
	matchRequest("Skip")
end

return Net
