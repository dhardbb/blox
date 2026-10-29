--!strict
-- Talks to the server: sends requests on ToServer and feeds ToClient messages
-- into the Store. Match requests are stamped with the current match and step.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Config = require(ReplicatedStorage.Shared.Sim.Config)
local Matchmaking = require(ReplicatedStorage.Shared.Net.Matchmaking)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local MatchWords = require(ReplicatedStorage.Shared.UI.Words.Matchmaking)
local Words = require(ReplicatedStorage.Shared.UI.Words.Setup)
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
	PivotUsed = "You can only swap an issue once per match.",
	BadPivot = "That issue swap isn't allowed.",
	BadFocus = "Debates have no focus any more: pick a move each round.",
	UnexpectedFocus = "Debates have no focus any more: pick a move each round.",
	BadMove = "Pick Defend, Attack or Pivot.",
	ZingerSpent = "Your Zinger is already spent this debate.",
	UnexpectedMove = "Debate moves are picked in the debate, not in the plan.",
	BadChoice = "That isn't a valid answer to this week's event.",
	UnexpectedChoice = "The stance is picked on its own screen, not in the plan.",
	-- Session (Session.Reason)
	StaleStep = "Too late: that step is over.",
	NotInput = "This part of the match isn't taking input right now.",
	AlreadyLocked = "You already locked in.",
	NoBank = "No time bank left.",
	NoTimer = "No timer here: take your time.",
	NotSkippable = "This part can't be skipped.",
	Over = "The match is over.",
	-- Select and Draft
	UnknownCandidate = "Pick one of the eight candidates.",
	CandidateTaken = "Your opponent already has that candidate. Pick another.",
	AlreadyClaimed = "You already have a candidate this match.",
	NotSelect = "Candidates are picked only at the start of a match.",
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
	-- Matchmaking (D-083)
	Matching = "You're already joining a match.",
	NotQueued = "Join the queue first.",
	BotTooSoon = `A bot game opens after {Config.defaults.QUEUE_BOT_OFFER_SECONDS} seconds in the queue.`,
	NoOffer = "There's no match waiting for your answer.",
	NoRematch = "That rematch isn't available anymore.",
	RematchExpired = "The rematch window has closed.",
	OpponentLeft = "Your opponent has left.",
	NotMatchServer = "You're already in the lobby.",
	CodeBusy = "Someone else is joining that match right now.",
	Unavailable = "Matching across servers isn't working right now. Try again soon.",
	-- Color (D-055)
	UnknownColor = "Pick one of the six colors.",
	NoColorPass = "Picking a color needs the Color Pass.",
	NotSaved = "Your saved data didn't load, so your color can't be saved.",
	ColorTaken = "Your opponent has that color. Pick another.",
	-- Custom names (D-069)
	NoNamePass = "Naming your candidate needs the Name Pass.",
	NameNotEligible = "Custom names are for age-checked players 16 and over.",
	NameBadText = "Use letters, spaces, - ' and . only. Try another.",
	NameEmpty = "Type a name first.",
	NameTooShort = "Use at least 2 letters.",
	NameRepeats = "No letter three times in a row. Try another.",
	NameTooLong = `Names can be at most {Config.defaults.NAME_MAX_LENGTH} characters.`,
	NameFiltered = "That name isn't allowed. Try another.",
	NameFilterFailed = "Names can't be checked right now. Try again in a minute.",
	NameNotSaved = "Your saved data didn't load, so your name can't be saved.",
	ReportSelf = "That's your own name.",
	ReportNoName = "There's no custom name to report there.",
	ReportTooSoon = "Wait a few seconds before reporting again.",
	ReportLimit = "You've sent a lot of reports. Thanks! Try again later.",
	NotAdmin = "Only the game's owners can review names.",
	ReviewFailed = "The review list couldn't be saved. Try again in a minute.",
	ReviewChanged = "That name changed since the list loaded. Check it again.",
	-- Bug reports (D-090)
	BugTooShort = `Tell us a little more: at least {Config.defaults.BUG_REPORT_MIN_CHARS} characters.`,
	BugTooLong = `Bug reports can be at most {Config.defaults.BUG_REPORT_MAX_CHARS} characters.`,
	BugTooSoon = "Thanks! Wait a minute before sending another report.",
	BugLimit = "You've sent a lot of bug reports today. Thanks! Try again tomorrow.",
	BugFailed = "Your report couldn't be sent right now. Try again in a minute.",
	-- Admin "Timers off" (D-081)
	AdminOnly = "Only the game's admins can turn timers off.",
	TimersNotSaved = "Your saved data didn't load, so the timer setting can't be saved.",
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
	CandidateTaken = "Your opponent claimed that candidate at the same moment and won the coin flip. Pick another.",
	OpponentForfeited = "Your opponent left the match. You win by forfeit.",
	NameReported = "Thanks for the report. You'll see the candidate's own name instead.",
	BugReported = "Thanks! Your bug report was sent to the game's makers.",
	NameRemoved = "Your custom name was removed after a review. You can pick a new one.",
	Tutorial = `Tutorial: {Config.defaults.TUTORIAL_WEEKS} short weeks and no timer on any choice, so take your time.`,
	NameNotAllowed = "Your custom name isn't allowed anymore, so your candidate uses their own. You can pick a new one.",
	MatchUnrated = `This match is unrated: you two already played {Config.defaults.RATED_PAIR_DAILY_MAX} rated matches today.`,
	ForfeitUnrated = "The match ended before week 1, so it doesn't count for anyone's rating.",
	AdminTimersOff = "Timers off (admin): every choice waits until it's locked in.",
	AdminTimersOffUnrated = "Timers off (admin): every choice waits until it's locked in. This match is unrated.",
	AdminTimersOn = "Timers back on (admin): choices are timed again, starting full.",
	AdminUnrated = "Timers were off (admin), so this match doesn't count for anyone's rating.",
	DailyCounted = "Daily Race: this run counts once week 1 starts. Good luck!",
	DailyPractice = "Practice run: today's Daily Race already counts. This one won't.",
	-- Matchmaking (D-083)
	WaitBot = "You're still in the queue. We'll ask before you leave this bot game.",
	OfferDeclined = "You left the queue and kept playing. Find a match again any time.",
	OfferExpired = "No answer in time, so you left the queue. Enjoy the bot game!",
	OpponentDeclined = "Your opponent kept playing their bot game. You're first in line.",
	OpponentNoShow = "Your opponent couldn't reach the match, so you're back in the lobby.",
	MatchServerFailed = "The match couldn't start, so you're back in the lobby.",
	TeleportFailed = "Couldn't move you to the match. Try again.",
	InviteExpired = "That invite has expired: your friend isn't hosting anymore.",
	InviteBusy = "Someone else is joining your friend's match right now.",
	CodeGone = "Your friend isn't hosting that match anymore.",
}

-- The color this player last asked for (Net.claimColor) and in which match,
-- for the ColorTaken notice.
local lastColorClaim: string? = nil
local lastColorMatch: string? = nil

-- "Buster took Crimson first. Pick another color." (D-061): the opponent by their
-- candidate's first name once they hold one; the color last asked for, else the
-- saved favorite (a tie as Select opened).
local function colorTakenText(): string
	local state = Store.get()
	local payload = state.payload
	local who: string? = nil
	if payload and payload.view.claims then
		for id, owner in payload.view.claims do
			if owner ~= payload.you and Candidates.exists(id) then
				-- Their custom name when this view carries one (D-069).
				local them = payload.view.players[owner]
				who = if them and them.customName
					then them.customName
					else Words.firstName(Candidates.profile(Config.defaults, id).name)
			end
		end
	end
	local lobby = state.lobby
	local asked = if payload and payload.matchId == lastColorMatch then lastColorClaim else nil
	return Words.colorTaken(who, asked or (if lobby then lobby.color else nil))
end

-- The player whose custom name this player last reported (Net.reportName).
local reportedId: string? = nil

-- The server took the report (its NameReported notice): hide that name in the
-- payload this client holds. A match that is over gets no new State, so
-- Results would keep showing the name otherwise (D-069).
local function hideReported()
	local id = reportedId
	reportedId = nil
	local payload = Store.get().payload
	if id == nil or payload == nil then
		return
	end
	for seat, info in payload.seats do
		if info.id == id then
			Store.hideName(seat)
		end
	end
end

local function noticeText(code: string?): string
	if code == "ColorTaken" then
		return colorTakenText()
	end
	return NOTICES[code or ""] or (code or "Notice")
end

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
		elseif message.kind == "Review" and message.review then
			Store.setReview(message.review)
		elseif message.kind == "Bugs" and message.bugs then
			Store.setBugs(message.bugs)
		elseif message.kind == "Leaderboard" and message.leaderboard then
			Store.setLeaderboard(message.leaderboard)
		elseif message.kind == "Daily" and message.daily then
			Store.setDaily(message.daily)
		elseif message.kind == "Rematch" and message.rematch then
			Store.setRematch(message.rematch)
		elseif message.kind == "Notice" then
			if message.notice == "NameReported" then
				hideReported()
			end
			Store.say(noticeText(message.notice))
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

-- Select step 1: claim a candidate (D-048).
function Net.claim(candidate: string)
	matchRequest("Claim", candidate)
end

-- Select: a Color Pass owner claims a color, first come, first served (D-061).
function Net.claimColor(color: string)
	local payload = Store.get().payload
	if payload == nil or payload.stage == "Over" then
		return
	end
	lastColorClaim = color
	lastColorMatch = payload.matchId
	Net.send("ClaimColor", { matchId = payload.matchId, step = payload.step, color = color })
end

-- Saves a chosen color (Color Pass owners, D-055); nil goes back to auto. The
-- server checks the pass itself.
function Net.setColor(color: string?)
	Net.send("SetColor", { color = color })
end

-- Names your candidate (Name Pass owners, D-069); nil goes back to the
-- candidate's own name. The server checks the pass, the age rule and the
-- text filter itself.
function Net.setName(name: string?)
	Net.send("SetName", { name = name })
end

-- Reports the custom name this player was shown for `userId` (D-069). When the
-- server's NameReported notice arrives, that name is hidden here too.
function Net.reportName(userId: string)
	reportedId = userId
	Net.send("ReportName", { userId = userId })
end

-- Sends a bug report (D-090): the server filters, rate-limits and stores it,
-- then says "Thanks" (a Notice) or why not (a rejection).
function Net.bugReport(text: string, screen: string)
	Net.send("BugReport", { text = text, screen = screen })
end

-- Opens Roblox's purchase prompt for a pass (a LocalScript may, per the
-- MarketplaceService docs). The server hears the outcome
-- (PromptGamePassPurchaseFinished) and sends a new lobby status.
function Net.buyPass(passId: number)
	pcall(function()
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, passId)
	end)
end

-- Leaves the match in progress and loses it (D-059). The server ends the match
-- and sends this player back to the lobby; Store.leave skips its Results.
function Net.forfeit()
	local payload = Store.get().payload
	if payload == nil or payload.stage == "Over" then
		return
	end
	Store.leave(payload.matchId)
	Net.send("Forfeit", { matchId = payload.matchId })
end

function Net.bank()
	matchRequest("Bank")
end

-- Answers "Opponent found! Leave this bot game?" (D-083). Joining ends the
-- bot game: its end skips Results (Store.leave), straight to the new match.
function Net.answer(accept: boolean)
	local payload = Store.get().payload
	if accept and payload and payload.stage ~= "Over" then
		Store.leave(payload.matchId)
	end
	Net.send("Answer", { accept = accept })
end

-- Rematch on Results (D-083): the match this player just finished.
function Net.rematch()
	local payload = Store.get().payload
	if payload == nil or payload.stage ~= "Over" then
		return
	end
	Net.send("Rematch", { matchId = payload.matchId })
end

-- Opens Roblox's invite prompt with the private code in the invite's launch
-- data (D-083), once SocialService says this player may invite. Says so in
-- the toast when they can't (a platform without invites, an error). Yields.
function Net.invite(code: string)
	local ok, can = pcall(function(): boolean
		return SocialService:CanSendGameInviteAsync(Players.LocalPlayer)
	end)
	if not ok or can ~= true then
		Store.say(MatchWords.INVITE_UNAVAILABLE, true, "InviteUnavailable")
		return
	end
	local prompted = pcall(function()
		local options = Instance.new("ExperienceInviteOptions")
		options.LaunchData = Matchmaking.launchData(code)
		options.PromptMessage = MatchWords.INVITE_PROMPT
		SocialService:PromptGameInvite(Players.LocalPlayer, options)
	end)
	if not prompted then
		Store.say(MatchWords.INVITE_UNAVAILABLE, true, "InviteUnavailable")
	end
end

function Net.skip()
	matchRequest("Skip")
end

return Net
