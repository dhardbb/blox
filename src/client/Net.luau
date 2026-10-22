--!strict
-- Talks to the server: sends requests on ToServer and feeds ToClient messages
-- into the Store. Match requests are stamped with the current match and step.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Store = require(script.Parent.Store)

local Net = {}

-- Readable text for rejection and notice codes.
local REASONS: { [string]: string } = {
	NotEnoughAP = "Not enough action points for that plan.",
	NotEnoughMoney = "Not enough money for that plan.",
	GotvCap = "That's over the ground-game limit for a state.",
	DuplicatePoll = "You already poll that state this week.",
	PivotUsed = "You can only pivot once per match.",
	BadPivot = "That pivot isn't allowed.",
	BadPrep = "Debate prep must use all your points, at most 4 per topic.",
	StaleStep = "Too late: that step is over.",
	AlreadyLocked = "You already locked in.",
	NoBank = "No time bank left.",
	NotSkippable = "This part can't be skipped.",
	ServerFull = "This server is full. Try again in a minute.",
	NoSuchCode = "No match with that code.",
	OwnCode = "That's your own code. Give it to a friend.",
	InMatch = "You're already in a match.",
	RateLimited = "Slow down a little.",
	IllegalChoice = "That state can't be picked this round.",
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
			Store.say(Net.reasonText(message.reason))
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
