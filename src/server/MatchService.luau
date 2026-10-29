--!strict
-- Runs every match on this server: the lobby (queue, private codes, practice),
-- one Net/Session per match, a clock that advances them, connection changes,
-- and cleanup. The game logic lives in Net/Session and Sim; this module only
-- feeds them requests and the server time and sends what they produce.
--
-- Matchmaking (D-083): players still waiting after the local lobby had its go
-- are matched across servers (server/CrossServer); a match server (a reserved
-- server) starts the match it was made for and sends its players back to a
-- lobby server afterwards; a queued player may play the bot while they wait;
-- Results offers a rematch; the Lobby shows how many players are online
-- (server/OnlineCount); a friend invited with a private code is taken
-- straight into it (their join's LaunchData).
--
-- Data (D-094): every finished match is written as a record for balance
-- analysis (server/MatchLog), each human's result carries its landslide flag
-- and whether it was a public match (the public landslide count, Profile),
-- and server/Analytics logs funnels and custom events. None of it can stop or
-- break a match: each step is pcall'd and never yields here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bot = require(ReplicatedStorage.Shared.Sim.Bot)
local BugReport = require(ReplicatedStorage.Shared.Net.BugReport)
local BugReports = require(script.Parent.BugReports)
local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Config = require(ReplicatedStorage.Shared.Sim.Config)
local Election = require(ReplicatedStorage.Shared.Sim.Election)
local CustomName = require(ReplicatedStorage.Shared.Net.CustomName)
local Lobby = require(ReplicatedStorage.Shared.Net.Lobby)
local MatchRecord = require(ReplicatedStorage.Shared.Net.MatchRecord)
local Matchmaking = require(ReplicatedStorage.Shared.Net.Matchmaking)
local Profile = require(ReplicatedStorage.Shared.Net.Profile)
local Rematch = require(ReplicatedStorage.Shared.Net.Rematch)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local Version = require(ReplicatedStorage.Shared.Version)
local Analytics = require(script.Parent.Analytics)
local DataService = require(script.Parent.DataService)
local DailyService = require(script.Parent.DailyService)
local Admins = require(script.Parent.Admins)
local CrossServer = require(script.Parent.CrossServer)
local LeaderboardService = require(script.Parent.LeaderboardService)
local MatchLog = require(script.Parent.MatchLog)
local NameEligibility = require(script.Parent.NameEligibility)
local NameReview = require(script.Parent.NameReview)
local NameService = require(script.Parent.NameService)
local OnlineCount = require(script.Parent.OnlineCount)
local PassService = require(script.Parent.PassService)
local Replication = require(script.Parent.Replication)

local MatchService = {}

local CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" -- no 0/O or 1/I
local CODE_LENGTH = 5
local TICK = 0.1 -- seconds between session clock checks

local config = Config.defaults
local lobby = Lobby.new(config)
local sessions: { [string]: Session.Session } = {}
local matchOf: { [string]: string } = {} -- player id -> match id
local prePicks: { [string]: any } = {}
local approvedNames: { [string]: string } = {} -- player id -> their saved custom name, filtered this visit (D-069)
local shownTo: { [string]: { [string]: string } } = {} -- viewer id -> setter id -> the custom name they were shown
local reports: { [string]: { last: number, count: number } } = {} -- reporter id -> rate-limit state, this visit (the daily count is in their profile)
local ownerNames: { [number]: string } = {} -- user id -> username, for the review panel

-- Reasons a report or a review request is turned down (D-069).
local ReportReason = table.freeze({
	Self = "ReportSelf", -- your own name
	NoName = "ReportNoName", -- you were not shown a custom name from that player
	TooSoon = "ReportTooSoon", -- NAME_REPORT_WAIT has not passed since your last report
	Limit = "ReportLimit", -- NAME_REPORTS_PER_DAY reached (saved in the profile, D-078)
	NotAdmin = "NotAdmin", -- review requests are for admins only
	ReviewFailed = "ReviewFailed", -- the review queue could not be read or written
	ReviewChanged = "ReviewChanged", -- the queued name is no longer the one the admin saw (D-078)
})
local ratingsAtStart: { [string]: { [string]: number } } = {} -- match id -> player id -> rating; rated matches only
local resultIds: { [string]: string } = {} -- match id -> an id for its result unique across servers (Profile.settle)
local lastRequest: { [string]: { [string]: number } } = {} -- player id -> op -> server time of the last accepted one (cooldowns)
local random = Random.new()
local matchCount = 0

-- Matchmaking (D-083).
local REQUEST_COOLDOWN = 1 -- s between one player's WaitBot, Answer, Rematch or Return requests
local JOIN_COOLDOWN = 2 -- s between one player's lookups of a code on another server (a MemoryStore read)
local PROFILE_WAIT = 10 -- s a match server waits for both saved profiles before starting unrated
local LAUNCH_TRIES = 10 -- launch data can take a few seconds to appear after an invited join
local LAUNCH_WAIT = 1 -- s between reads
type MatchInfo = {
	kind: "Match" | "Practice",
	players: { string }, -- the humans, seat order
	difficulty: Bot.Difficulty?, -- Practice: the bot's level
	events: boolean?, -- Match: false if the host turned events off
	waiting: boolean?, -- Practice: a bot game while waiting in the queue
	daily: boolean?, -- Practice: a Daily Race run (D-082): its rematch is today's race again
	private: boolean?, -- Match: from a private code (or a rematch of one): not public (D-094)
}
local matchInfo: { [string]: MatchInfo } = {} -- running or just finished match id -> how it was made
type RematchEntry = {
	offer: Rematch.Offer,
	info: MatchInfo,
	told: boolean, -- its players were told it expired
}
local rematches: { [string]: RematchEntry } = {} -- finished match id -> its rematch offer
local rematchOf: { [string]: string } = {} -- player id -> the finished match whose rematch they may take
local foundAs: { [string]: Remotes.Found } = {} -- held player id -> what their Lobby says (Found)
local queuedAt: { [string]: number } = {} -- queued player id -> unix time they joined the line (tickets)
local matchServer = CrossServer.isMatchServer()
local spec: Matchmaking.Spec? = nil -- a match server's match, once read
local specStarted = false
local arrivedAt: number? = nil -- server time both of a match server's players were here
local onlineShown: number? = nil

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Per-player cooldown for ops that write saved data or call the text filter:
-- true (and the time is noted) if `op` may run now, false while it cools down.
local function cooled(id: string, op: string, seconds: number): boolean
	local times = lastRequest[id] or {}
	lastRequest[id] = times
	local t = now()
	local last = times[op]
	if last ~= nil and t - last < seconds then
		return false
	end
	times[op] = t
	return true
end

local function idOf(player: Player): string
	return tostring(player.UserId)
end

-- What a player whose match is on its way sees (D-083), or nil.
local function foundOf(id: string): Remotes.Found?
	local pending = Lobby.pending(lobby, id)
	if pending then
		return { phase = "Answer", untilAt = pending.untilAt }
	end
	local offer = lobby.offers[id]
	if offer then
		return { phase = "Waiting", untilAt = offer.untilAt }
	end
	if lobby.held[id] then
		return foundAs[id] or { phase = "Joining" }
	end
	return nil
end

local function sendLobby(id: string)
	local state: Lobby.PlayerState, code = Lobby.state(lobby, id)
	local profile = DataService.profile(id)
	local passId = PassService.colorPassId()
	local status: Remotes.LobbyStatus = {
		state = state,
		code = code,
		queued = #lobby.queue,
		full = lobby.active >= lobby.capacity,
		profile = DataService.summary(id),
		color = if profile then profile.color else nil,
		-- Absent while the pass is not set up: the client then shows no color option.
		-- Admins have it free even while the id is 0 (D-069).
		colorPass = if PassService.offered("Color", id)
			then { id = passId or 0, owned = PassService.ownsColorPass(id) }
			else nil,
		-- Admins only: the review button's count (D-069).
		review = if Admins.isAdminId(tonumber(id) or 0) then { count = NameReview.pendingCount() } else nil,
		-- Admins only: the corner's "Timers off" toggle as saved (D-081).
		admin = if Admins.isAdminId(tonumber(id) or 0)
			then { timersOff = profile ~= nil and profile.adminTimersOff == true }
			else nil,
		online = OnlineCount.get(),
		botAt = Lobby.botAt(lobby, id),
		found = foundOf(id),
		matchServer = if matchServer then true else nil,
	}
	Replication.send(id, { kind = "Lobby", lobby = status })
end

local function playerOf(id: string): Player?
	local userId = tonumber(id)
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

-- Whether this player may buy, set and see custom names (D-069): Roblox lets
-- them chat (server/NameEligibility, the stand-in for 16+; cached, checked on join).
local function eligible(id: string): boolean
	local player = playerOf(id)
	return player ~= nil and NameEligibility.isEligible(player)
end

-- The Name Pass as this player may use it, or nil (not set up, or not eligible).
local function namePassOf(id: string): Session.NamePass?
	if not PassService.offered("Name", id) or not eligible(id) then
		return nil
	end
	return { id = PassService.namePassId() or 0, owned = PassService.ownsNamePass(id) }
end

-- Filters a player's saved custom name once per visit (when their profile
-- loads), so a match can start without waiting on the filter. A name the filter
-- now turns down, or a filter that cannot be reached, leaves no name. Yields.
local function approveSavedName(id: string)
	approvedNames[id] = nil
	local player = playerOf(id)
	local profile = DataService.profile(id)
	if player == nil or profile == nil or profile.customName == nil then
		return
	end
	-- The profile can load before the join's eligibility check finishes: ask now.
	if not eligible(id) then
		NameEligibility.refresh(player)
	end
	if namePassOf(id) == nil then
		return
	end
	NameReview.ensureLoaded()
	local name, reason = NameService.check(player, profile.customName)
	if playerOf(id) ~= player then
		return
	end
	if name then
		approvedNames[id] = name
	elseif reason == CustomName.Reason.Filtered and NameService.isReviewedExact(profile.customName) then
		-- A reviewer removed this very name since: clear it from their save, and say so.
		DataService.update(id, function(saved: Profile.Profile): Profile.Profile
			return Profile.withCustomName(saved, nil)
		end)
		Replication.send(id, { kind = "Notice", notice = "NameRemoved" })
	elseif reason == CustomName.Reason.Filtered and NameService.isBlocked(profile.customName) then
		-- It only contains a blocked name (D-078): not used, but left in their save.
		Replication.send(id, { kind = "Notice", notice = "NameNotAllowed" })
	end
end

-- A human seat for a match. Color Pass ownership is the server's own check as
-- it knows it now (no waiting, D-055): an owner may claim colors during Select
-- and their saved color is claimed for them as Select opens (D-061). Anyone
-- else, or an owner whose check failed, is dealt red or blue. The Name Pass
-- (D-069): an eligible player gets the pass's state; an owner's saved name,
-- already filtered, names their candidate; only eligible players see names,
-- and another player's only once it is filtered for them (shareNames).
local function humanSpec(id: string): Session.SeatSpec
	local owns = PassService.ownsColorPass(id)
	local profile = if owns then DataService.profile(id) else nil
	local namePass = namePassOf(id)
	-- Admins (D-081), checked here on the server: their saved "Timers off".
	local admin = Admins.isAdminId(tonumber(id) or 0)
	local saved = if admin then DataService.profile(id) else nil
	return {
		admin = admin,
		timersOff = saved ~= nil and saved.adminTimersOff == true,
		id = id,
		kind = "Human",
		prePick = prePicks[id],
		colorPass = owns,
		color = if profile then profile.color else nil,
		seesNames = eligible(id),
		namePass = namePass,
		customName = if namePass and namePass.owned then approvedNames[id] else nil,
		landslides = Profile.landslides(DataService.profile(id)), -- shown with their name (D-094)
	}
end

-- SetColor: saves a chosen color (or auto, when `color` is nil) in the profile.
-- Returns a reason code when it is turned down. May yield (a fresh pass check).
local function setColor(player: Player, color: string?): string?
	local id = idOf(player)
	if not cooled(id, "SetColor", config.SET_COLOR_COOLDOWN) then
		return "RateLimited"
	end
	if color ~= nil then
		if not Profile.isColor(color) then
			return "UnknownColor"
		end
		if not PassService.offered("Color", id) then
			return "NoColorPass"
		end
		-- Not known to own it: ask Roblox again (a failed check at join, or a
		-- purchase made outside the game), never the client.
		if not PassService.ownsColorPass(id) and not PassService.refresh(player) then
			return "NoColorPass"
		end
	end
	local how = DataService.update(id, function(profile: Profile.Profile): Profile.Profile
		return (Profile.withColor(profile, color))
	end)
	if how == "Skipped" then
		return "NotSaved"
	end
	print(`[270] player {id} color: {color or "auto"} ({how})`)
	return nil
end

-- Sends the current lobby status to everyone who is not in a match. Whenever the
-- queue or the number of running matches changes, every idle, queued and hosting
-- player's screen (queue count, "server full") has to follow.
local function broadcastLobby()
	for _, player in Players:GetPlayers() do
		local id = idOf(player)
		if matchOf[id] == nil then
			sendLobby(id)
		end
	end
end

-- Applies a finished match to each human's saved profile and tells them how
-- their rating moved. Only a human-vs-human match decided by an election or a
-- forfeit is rated (and only if both ratings were known at the start); against
-- the bot it only adds to the practice record; an unrated human match and an
-- abandoned match change nothing. A player whose profile is still loading gets
-- the result when the load finishes.
local function settle(session: Session.Session)
	if session.daily then
		-- The Daily Race (D-082): its own score and streak; never the rating,
		-- the practice record or the tutorial.
		ratingsAtStart[session.id] = nil
		resultIds[session.id] = nil
		DailyService.settle(session)
		return
	end
	local starts: { [string]: number }? = ratingsAtStart[session.id]
	ratingsAtStart[session.id] = nil
	local resultId = resultIds[session.id] or session.id
	resultIds[session.id] = nil
	local result = session.result :: Session.Result
	local winners = result.winners or (if result.winner ~= 0 then { result.winner } else {})
	if result.reason == "Abandoned" or #winners == 0 then
		return
	end
	local vsBot = false
	for _, seat in session.seats do
		if seat.kind == "Bot" then
			vsBot = true
		end
	end
	if result.unrated and starts then
		-- A forfeit or a drop before week 1 counts for no one (D-077); nor does a
		-- match where an admin had the timers off (D-081).
		starts = nil
		local why = if result.timersOff then "an admin turned the timers off" else "it ended before week 1"
		print(`[270] match {session.id} is unrated: {why}`)
		for _, seat in session.seats do
			if seat.kind == "Human" then
				Replication.send(seat.id, {
					kind = "Notice",
					notice = if result.timersOff then "AdminUnrated" else "ForfeitUnrated",
				})
			end
		end
	end
	if starts == nil and not vsBot then
		return
	end
	-- A forfeit can follow the last plan, after the election was computed but
	-- before anyone saw it: only a shown election has electoral votes to record.
	local election = if result.reason == "Election" then session.match.election else nil
	local slide = if election then Election.landslide(session.config, election) else nil
	-- Public (D-094): rated, from the public queue (or its rematch), not a private code.
	local info = matchInfo[session.id]
	local public = starts ~= nil and info ~= nil and info.kind == "Match" and info.private ~= true
	local at = os.time()
	for me, seat in session.seats do
		if seat.kind ~= "Human" then
			continue
		end
		-- Rated and practice matches have two seats: the opponent is the other one.
		local them = if me == 1 then 2 else 1
		local input: Profile.Result = {
			at = at,
			reason = result.reason,
			rated = starts ~= nil,
			won = table.find(winners, me) ~= nil,
			candidate = session.match.players[me].candidate,
			opponentCandidate = session.match.players[them].candidate,
			opponentRating = if starts then starts[session.seats[them].id] else nil,
			evFor = if election then election.ev[me] else nil,
			evAgainst = if election then election.ev[them] else nil,
			opponent = if starts then session.seats[them].id else nil,
			-- The tutorial (D-075) is done once it ends in an election or a forfeit
			-- (Leave match included); an abandoned one comes back next time.
			tutorial = if session.tutorial then true else nil,
			landslide = if slide == me then true else nil,
			public = if public then true else nil,
		}
		local function announce(applied: Profile.Change)
			if applied.rated then
				Replication.send(seat.id, {
					kind = "Rating",
					rating = { matchId = session.id, before = applied.before, after = applied.after },
				})
				LeaderboardService.record(seat.id, applied.after)
				if public and slide == me then
					-- The public landslide count's board column (D-094).
					LeaderboardService.recordLandslides(
						seat.id,
						Profile.landslides(DataService.profile(seat.id))
					)
				end
				print(
					`[270] player {seat.id} rating {applied.before} -> {applied.after} (match {session.id})`
				)
			end
		end
		-- Saved at once; a player who left (even for another server) still gets it.
		local how = DataService.applyResult(seat.id, resultId, input, announce)
		if how == "Offline" and starts then
			print(`[270] match {session.id}: result for player {seat.id} recorded in their saved data`)
		end
	end
end

-- ---------------------------------------------------------------- rematch (D-083)

-- Tells each player still here where a rematch stands.
local function sendRematch(entry: RematchEntry)
	local t = now()
	for _, id in entry.offer.players do
		if playerOf(id) ~= nil and rematchOf[id] == entry.offer.matchId then
			Replication.send(id, { kind = "Rematch", rematch = Rematch.status(entry.offer, id, t) })
		end
	end
end

local function closeRematch(matchId: string)
	local entry = rematches[matchId]
	rematches[matchId] = nil
	if entry then
		for _, id in entry.offer.players do
			if rematchOf[id] == matchId then
				rematchOf[id] = nil
			end
		end
	end
end

-- Player `id` left the server or started something else: a rematch they
-- could take is gone, and the other player is told.
local function leaveRematch(id: string)
	local matchId = rematchOf[id]
	if matchId == nil then
		return
	end
	rematchOf[id] = nil
	local entry = rematches[matchId]
	if entry and Rematch.leave(entry.offer, id) then
		sendRematch(entry)
	end
end

-- A match just ended: its players may play it again (not after an abandoned
-- match). The player who forfeited is not offered one.
local function openRematch(session: Session.Session)
	local info = matchInfo[session.id]
	matchInfo[session.id] = nil
	local result = session.result
	if info == nil or result == nil or result.reason == "Abandoned" then
		return
	end
	local offer =
		Rematch.new(session.id, info.players, info.kind == "Practice", now(), config.REMATCH_WINDOW_SECONDS)
	local entry: RematchEntry = { offer = offer, info = info, told = false }
	for _, id in info.players do
		local previous = rematchOf[id]
		if previous then
			closeRematch(previous)
		end
	end
	rematches[session.id] = entry
	for p, seat in session.seats do
		if seat.kind ~= "Human" then
			continue
		end
		rematchOf[seat.id] = session.id
		local forfeited = result.reason == "Forfeit" and result.winner ~= p and result.winner ~= 0
		if playerOf(seat.id) == nil or forfeited then
			Rematch.leave(offer, seat.id)
		end
	end
	sendRematch(entry)
end

-- ---------------------------------------------------------------- data (D-094)

-- How a match was made, for its record and analytics.
local function modeOf(session: Session.Session, info: MatchInfo?): MatchRecord.Mode
	if session.daily then
		return "Daily"
	elseif session.tutorial then
		return "Tutorial"
	elseif info and info.kind == "Practice" then
		return if info.waiting then "WaitBot" else "Practice"
	end
	return if info and info.private then "Private" else "Queue"
end

local function humansOf(session: Session.Session): { string }
	local ids: { string } = {}
	for _, seat in session.seats do
		if seat.kind == "Human" then
			table.insert(ids, seat.id)
		end
	end
	return ids
end

local function factsOf(session: Session.Session, info: MatchInfo?): Analytics.MatchFacts
	local level: string? = nil
	local candidates: { [string]: string } = {}
	for p, seat in session.seats do
		if seat.kind == "Bot" and seat.botDifficulty then
			level = seat.botDifficulty
		end
		local player = session.match.players[p]
		if seat.kind == "Human" and player and player.candidate ~= "" then
			candidates[seat.id] = player.candidate
		end
	end
	return {
		id = session.id,
		mode = modeOf(session, info),
		level = level,
		humans = humansOf(session),
		candidates = candidates,
		tutorial = session.tutorial,
	}
end

local function serverId(): string
	return if game.JobId == "" then "studio" else game.JobId
end

-- A match ended: its record is queued (MatchLog) and analytics told. Never
-- yields; the caller pcalls it.
local function recordEnd(session: Session.Session, info: MatchInfo?, rated: boolean)
	local result = session.result :: Session.Result
	MatchLog.record(session, {
		mode = modeOf(session, info),
		rated = rated,
		version = Version.VERSION,
		at = os.time(),
		ended = now(),
		server = serverId(),
	})
	local winners = result.winners or (if result.winner ~= 0 then { result.winner } else {})
	local outcomes: { [string]: string } = {}
	for p, seat in session.seats do
		if seat.kind == "Human" then
			outcomes[seat.id] = if result.reason == "Abandoned"
				then "None"
				elseif table.find(winners, p) then "Won"
				else "Lost"
		end
	end
	local election = if result.reason == "Election" then session.match.election else nil
	local slide = if election then Election.landslide(session.config, election) else nil
	local slideSeat = if slide then session.seats[slide] else nil
	Analytics.matchEnded(
		factsOf(session, info),
		result.reason,
		now() - session.startedAt,
		outcomes,
		rated,
		if slideSeat and slideSeat.kind == "Human" then slideSeat.id else nil
	)
end

-- Sends a session's queued messages; ends the match in the lobby once it is over.
local function flush(session: Session.Session)
	for _, message in Session.drain(session) do
		local seat = session.seats[message.seat]
		local out: Remotes.Message = { kind = message.kind, state = message.state, notice = message.notice }
		Replication.send(seat.id, out)
	end
	DailyService.watch(session) -- a counted Daily Race run reaching week 1 (D-082)
	if session.tutorial and session.match.week >= 1 then
		-- The onboarding funnel's tutorial weeks (D-094).
		pcall(Analytics.tutorialWeek, session.id, humansOf(session), session.match.week)
	end
	if session.stage == "Over" and sessions[session.id] then
		sessions[session.id] = nil
		local ids = {}
		for _, seat in session.seats do
			if seat.kind == "Human" then
				table.insert(ids, seat.id)
				matchOf[seat.id] = nil
			end
		end
		Lobby.ended(lobby, ids)
		local info = matchInfo[session.id]
		local ended = session.result
		local rated = ratingsAtStart[session.id] ~= nil and ended ~= nil and ended.unrated ~= true
		local settled, err = pcall(function(): string?
			settle(session)
			return nil
		end)
		if not settled then
			warn(`[270] match {session.id}: could not apply the result to saved data: {err}`)
		end
		local logged, logErr = pcall(function(): string?
			recordEnd(session, info, rated)
			return nil
		end)
		if not logged then
			warn(`[270] match {session.id}: could not record it: {logErr}`)
		end
		openRematch(session)
		-- A bot game while waiting is over: they are still in line (D-083).
		for _, id in ids do
			local at = queuedAt[id]
			if at and table.find(lobby.queue, id) then
				CrossServer.queued(id, at, false)
			end
		end
		broadcastLobby()
		local result = session.result :: Session.Result
		print(`[270] match {session.id} over: {result.reason}, winner seat {result.winner}`)
	end
end

-- Runs one Session call. If it throws, the match is abandoned so a bug can't
-- leave its players stuck in it; the caller then flushes to free the lobby.
local function guard(session: Session.Session, call: () -> ()): boolean
	local ok, err = pcall(function(): string?
		call()
		return nil
	end)
	if ok then
		return true
	end
	warn(`[270] match {session.id} failed, abandoning it: {err}`)
	local aborted, abortErr = pcall(function(): string?
		Session.abort(session, now())
		return nil
	end)
	if not aborted then
		warn(`[270] match {session.id} could not be aborted cleanly: {abortErr}`)
	end
	return false
end

-- Shows each custom name in a match to every other player allowed to see it
-- (D-069): an eligible viewer whom Roblox lets receive the setter's messages
-- (NameEligibility.canSee), as the filter shows it to that viewer
-- (NameService.forViewer). Everyone else keeps the candidate's own name.
-- Yields (the checks); a match that ended meanwhile is left alone.
local function shareNames(session: Session.Session)
	for q, setter in session.seats do
		local name = setter.customName
		local from = playerOf(setter.id)
		if setter.kind ~= "Human" or name == nil or from == nil then
			continue
		end
		for p, viewer in session.seats do
			if p == q or viewer.kind ~= "Human" or not viewer.seesNames then
				continue
			end
			local to = playerOf(viewer.id)
			-- Filtered for this viewer, like chat (NameService.forViewer).
			local text = if to ~= nil and NameEligibility.canSee(from, to)
				then NameService.forViewer(from, to, name)
				else nil
			-- A name this viewer reported stays hidden from them, in every match.
			if text ~= nil and Profile.hides(DataService.profile(viewer.id), setter.id, name) then
				Session.hideName(session, p, q, name)
				text = nil
			end
			if text ~= nil then
				local seen = shownTo[viewer.id] or {}
				seen[setter.id] = name
				shownTo[viewer.id] = seen
			end
			if sessions[session.id] ~= session then
				return
			end
			guard(session, function()
				Session.showName(session, p, q, name, text)
			end)
		end
	end
	if sessions[session.id] == session then
		flush(session)
	end
end

-- SetName (D-069): names the player's candidate (nil = its own name). Needs the
-- Name Pass and an eligible account (Roblox lets them chat); the name is checked and
-- filtered (server/NameService), saved in the profile, and, during Select,
-- used in the player's match at once. Returns a reason code when it is turned
-- down (CustomName.Reason); the old name stays. May yield (the filter, a
-- fresh pass check).
local function setName(player: Player, text: string?): string?
	local id = idOf(player)
	-- Before anything that calls Roblox (the chat check, the pass, the filter).
	if not cooled(id, "SetName", config.SET_NAME_COOLDOWN) then
		return "RateLimited"
	end
	if not PassService.offered("Name", id) then
		return CustomName.Reason.NoNamePass
	end
	if not eligible(id) and not NameEligibility.refresh(player) then
		return CustomName.Reason.NotEligible
	end
	-- Not known to own it: ask Roblox again, never the client.
	if not PassService.ownsNamePass(id) and not PassService.refreshName(player) then
		return CustomName.Reason.NoNamePass
	end
	local name: string? = nil
	if text ~= nil then
		local normalized = CustomName.normalize(text, config)
		if normalized ~= nil and normalized == approvedNames[id] then
			name = normalized -- already filtered this visit: no second filter call
		else
			NameReview.ensureLoaded()
			local checked, reason = NameService.check(player, text)
			if checked == nil then
				return reason
			end
			name = checked
		end
	end
	if playerOf(id) ~= player then
		return nil -- they left while the filter ran
	end
	if name then
		approvedNames[id] = name
	else
		approvedNames[id] = nil
	end
	local how = DataService.update(id, function(profile: Profile.Profile): Profile.Profile
		return Profile.withCustomName(profile, name)
	end)
	local session = sessions[matchOf[id] or ""]
	if session then
		local seat = Session.seatOf(session, id) :: number
		guard(session, function()
			-- Eligible: checked just above, so seeing names follows too.
			Session.setSeesNames(session, seat, eligible(id))
			Session.setNamePass(session, seat, namePassOf(id))
			Session.setName(session, seat, name)
		end)
		flush(session)
		task.spawn(shareNames, session)
	elseif how == "Skipped" then
		return CustomName.Reason.NotSaved
	end
	print(`[270] player {id} name: {name or "(the candidate's own)"} ({how})`)
	return nil
end

-- Clears player `id`'s custom name after a review (D-069): their profile, this
-- visit's copy, their match (any phase), and a friendly notice. Yields.
local function clearRemovedName(id: string)
	approvedNames[id] = nil
	DataService.update(id, function(saved: Profile.Profile): Profile.Profile
		return Profile.withCustomName(saved, nil)
	end)
	local session = sessions[matchOf[id] or ""]
	if session then
		local seat = Session.seatOf(session, id) :: number
		guard(session, function()
			Session.clearName(session, seat)
		end)
		flush(session)
	else
		sendLobby(id)
	end
	Replication.send(id, { kind = "Notice", notice = "NameRemoved" })
	print(`[270] player {id}: custom name removed after review`)
end

-- Stops using player `id`'s custom name this visit without touching their
-- saved data (D-078: it only contains a name a reviewer removed). Yields.
local function hideBlockedName(id: string)
	approvedNames[id] = nil
	local session = sessions[matchOf[id] or ""]
	if session then
		local seat = Session.seatOf(session, id) :: number
		guard(session, function()
			Session.clearName(session, seat)
		end)
		flush(session)
	else
		sendLobby(id)
	end
	Replication.send(id, { kind = "Notice", notice = "NameNotAllowed" })
	print(`[270] player {id}: custom name not used after a review (kept in their save)`)
end

-- The reviewed blocklist grew (here or on another server): stop every name in
-- this server that now matches it. Only the exact removed name is also taken
-- out of its owner's saved data (D-078).
local function onBlocklist(added: { string })
	for id, name in approvedNames do
		if CustomName.reviewedExact(name, added) then
			task.spawn(clearRemovedName, id)
		elseif NameService.isBlocked(name) then
			task.spawn(hideBlockedName, id)
		end
	end
end

-- ReportName (D-069): `player` reports the custom name they were shown for
-- `setterId`. They stop seeing it at once (this match and, through their
-- profile, every later one); the report waits in the review queue for an
-- admin. Rate-limited per reporter. Returns a reason code when turned down.
local function reportName(player: Player, setterId: string): string?
	local id = idOf(player)
	if setterId == id then
		return ReportReason.Self
	end
	local seen = shownTo[id]
	local name = if seen then seen[setterId] else nil
	if name == nil then
		return ReportReason.NoName
	end
	local state = reports[id] or { last = -math.huge, count = 0 }
	-- The daily count lives in the profile, so leaving and rejoining does not
	-- reset it; without a loaded profile this visit's count stands in.
	local unix = os.time()
	local profile = DataService.profile(id)
	if not Profile.canReport(profile, unix, config) or state.count >= config.NAME_REPORTS_PER_DAY then
		return ReportReason.Limit
	end
	local t = now()
	if t - state.last < config.NAME_REPORT_WAIT then
		return ReportReason.TooSoon
	end
	reports[id] = { last = t, count = state.count + 1 }
	seen = seen :: { [string]: string }
	seen[setterId] = nil
	local session = sessions[matchOf[id] or ""]
	if session then
		local viewer = Session.seatOf(session, id) :: number
		local setter = Session.seatOf(session, setterId)
		if setter then
			guard(session, function()
				Session.hideName(session, viewer, setter, name)
			end)
			flush(session)
		end
	end
	DataService.update(id, function(saved: Profile.Profile): Profile.Profile
		return Profile.withReport(Profile.withHiddenName(saved, setterId, name, config), unix, config)
	end)
	Replication.send(id, { kind = "Notice", notice = "NameReported" })
	task.spawn(function()
		if not NameReview.report(tonumber(setterId) :: number, player.UserId, name, os.time()) then
			warn(`[270] could not queue the report on {setterId}'s name for review`)
		end
	end)
	print(`[270] player {id} reported {setterId}'s name`)
	return nil
end

-- A username for the review panel (cached; "Player <id>" if the lookup fails).
local function ownerName(userId: number): string
	local known = ownerNames[userId]
	if known then
		return known
	end
	local ok, name = pcall(function(): string
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if ok and type(name) == "string" then
		ownerNames[userId] = name
		return name
	end
	return `Player {userId}`
end

-- Sends an admin the review queue. Yields.
local function sendReview(id: string)
	local list = NameReview.list()
	local entries: { Remotes.ReviewEntry } = {}
	local found: { NameReview.Entry } = list or {}
	for _, entry in found do
		table.insert(entries, {
			userId = tostring(entry.userId),
			name = entry.name,
			owner = ownerName(entry.userId),
			count = entry.count,
			first = entry.first,
			last = entry.last,
		})
	end
	Replication.send(id, { kind = "Review", review = { ok = list ~= nil, entries = entries } })
end

-- BugReport (D-090): filtered, rate-limited and stored by server/BugReports,
-- with the player's match id from the server's own records. The player hears
-- "Thanks" (a Notice) or why not (a rejection). Yields.
local function bugReport(player: Player, request: Remotes.Request)
	local id = idOf(player)
	local reason = BugReports.submit(player, request.text, {
		screen = request.screen,
		matchId = matchOf[id],
	}, os.time())
	if reason then
		Replication.reject(player, "BugReport", reason)
	else
		Replication.send(id, { kind = "Notice", notice = "BugReported" })
	end
end

-- BugList (D-090): admins only, checked here on every request. Sends the
-- newest reports, each with its sender's username. Yields.
local function bugList(player: Player)
	local id = idOf(player)
	if not Admins.isAdmin(player) then
		Replication.reject(player, "BugList", ReportReason.NotAdmin)
		return
	end
	if not cooled(id, "BugList", config.BUG_LIST_COOLDOWN) then
		Replication.reject(player, "BugList", "RateLimited")
		return
	end
	local list = BugReports.list(os.time())
	local entries: { Remotes.BugEntry } = {}
	local records: { BugReport.Record } = list or {}
	for _, record in records do
		table.insert(entries, {
			at = record.at,
			userId = tostring(record.userId),
			owner = ownerName(record.userId),
			version = record.version,
			screen = record.screen,
			matchId = record.matchId,
			text = record.text,
		})
	end
	Replication.send(id, { kind = "Bugs", bugs = { ok = list ~= nil, entries = entries } })
end

-- ReviewList, ReviewKeep, ReviewRemove (D-069): admins only, checked here on
-- every request. Returns a reason code when turned down. Yields.
local function review(player: Player, request: Remotes.Request): string?
	local id = idOf(player)
	if not Admins.isAdmin(player) then
		return ReportReason.NotAdmin
	end
	local target = tonumber(request.userId or "")
	local name = request.name
	local failure: NameReview.Failure? = nil
	if request.op == "ReviewKeep" and target and name then
		failure = NameReview.keep(target, name)
		if failure == nil then
			print(`[270] admin {id} kept the name of {target}`)
		end
	elseif request.op == "ReviewRemove" and target and name then
		local _entry: string?, why: NameReview.Failure? = NameReview.remove(target, name)
		failure = why
		if failure == nil then
			print(`[270] admin {id} removed the name of {target}`)
		end
	end
	-- The list again either way, so a changed entry shows as it is now.
	sendReview(id)
	if matchOf[id] == nil then
		sendLobby(id)
	end
	if failure == "Changed" then
		return ReportReason.ReviewChanged
	elseif failure == "Failed" then
		return ReportReason.ReviewFailed
	end
	return nil
end

local function newCode(): string
	for _ = 1, 100 do
		local chars = table.create(CODE_LENGTH, "")
		for k = 1, CODE_LENGTH do
			local at = random:NextInteger(1, #CODE_ALPHABET)
			chars[k] = string.sub(CODE_ALPHABET, at, at)
		end
		local code = table.concat(chars)
		if lobby.codes[code] == nil then
			return code
		end
	end
	error("could not make a free match code")
end

-- Starts the match a lobby outcome describes. `fixedSeed`: a match server's
-- match uses the seed in its spec (D-083).
local function startMatch(outcome: Lobby.Outcome, fixedSeed: number?)
	matchCount += 1
	local matchId = `m{matchCount}`
	local seed = fixedSeed or random:NextInteger(1, 2 ^ 31 - 1)
	-- The Daily Race (D-082): the day's seed, candidates and bot level for everyone.
	local race = if outcome.daily ~= nil then DailyService.race() else nil
	if race and race.day ~= outcome.daily then
		race = nil -- midnight passed between the request and here: play it as asked
	end
	local daily: Session.DailyRun? = nil
	if race then
		seed = race.seed
		daily = { day = race.day, counted = DailyService.canCount(outcome.players[1], race.day) }
	end
	-- Whatever they were waiting for elsewhere is over (D-083). A bot game while
	-- waiting keeps their place in line, here and across servers.
	for _, id in outcome.players do
		leaveRematch(id)
		foundAs[id] = nil
		if outcome.waiting then
			local at = queuedAt[id]
			if at then
				CrossServer.queued(id, at, true)
			end
		else
			local at = queuedAt[id]
			if at then
				pcall(Analytics.unqueued, id, os.time() - at, "Matched")
			end
			queuedAt[id] = nil
			CrossServer.forget(id)
		end
	end
	local specs: { Session.SeatSpec } = {}
	for _, id in outcome.players do
		local seatSpec = humanSpec(id)
		if race then
			seatSpec.candidate = race.candidate
		end
		table.insert(specs, seatSpec)
	end
	if outcome.kind == "Practice" then
		local candidate = if race
			then race.botCandidate
			else Candidates.ids[random:NextInteger(1, #Candidates.ids)]
		table.insert(specs, {
			id = "bot",
			kind = "Bot",
			candidate = candidate,
			difficulty = Bot.difficulty(outcome.difficulty), -- D-057, D-087: absent = Easy
			profile = if race then race.style else nil, -- the Daily Race's bot plays as it always has (D-087)
		})
	end
	local created: Session.Session? = nil
	local built, err = pcall(function(): string?
		created = Session.new(config, matchId, seed, specs, now(), {
			events = outcome.events,
			tutorial = outcome.kind == "Practice"
				and outcome.tutorial == true
				and daily == nil
				and not outcome.waiting,
			daily = daily,
		})
		return nil
	end)
	local session = created
	if not built or session == nil then
		-- The lobby already counted this match; hand the players back.
		warn(`[270] match {matchId} could not start: {err}`)
		Lobby.ended(lobby, outcome.players)
		broadcastLobby()
		return
	end
	sessions[matchId] = session
	matchInfo[matchId] = {
		kind = if outcome.kind == "Practice" then "Practice" else "Match",
		players = table.clone(outcome.players),
		difficulty = if outcome.kind == "Practice" then Bot.difficulty(outcome.difficulty) else nil,
		events = outcome.events,
		waiting = outcome.waiting,
		daily = if daily then true else nil,
		private = if outcome.private then true else nil,
	}
	-- An id for the result unique across servers, so it is applied once (Profile.settle).
	local job = if game.JobId == "" then "studio" else game.JobId
	resultIds[matchId] = `{job}/{matchId}/{seed}`
	local pairCapped = false
	if outcome.kind == "Match" then
		-- Rated only if every player's saved rating is loaded and writable now.
		local ratings: { [string]: number } = {}
		for _, id in outcome.players do
			local rating = DataService.rating(id)
			if rating then
				ratings[id] = rating
			end
		end
		local a, b = outcome.players[1], outcome.players[2]
		if #outcome.players == 2 and ratings[a] and ratings[b] then
			-- At most RATED_PAIR_DAILY_MAX rated games a day for one pair (D-077).
			local t = os.time()
			local played = math.max(
				Profile.ratedGamesWith(DataService.profile(a), b, t, config),
				Profile.ratedGamesWith(DataService.profile(b), a, t, config)
			)
			if played >= config.RATED_PAIR_DAILY_MAX then
				print(`[270] match {matchId} is unrated: this pair played {played} rated games in a day`)
				pairCapped = true
			else
				ratingsAtStart[matchId] = ratings
			end
		else
			print(`[270] match {matchId} is unrated: a player's saved data is not available`)
		end
	end
	for _, id in outcome.players do
		matchOf[id] = matchId
		sendLobby(id)
	end
	broadcastLobby() -- the queue shrank and a match slot filled up
	local against = if outcome.kind == "Practice" then `, bot {Bot.difficulty(outcome.difficulty)}` else ""
	if outcome.kind == "Practice" and race then
		against ..= ` playing {race.style}` -- the Daily Race's own profile (D-087)
	end
	if outcome.tutorial then
		against ..= ", tutorial"
	end
	if daily then
		against ..= ", daily race"
		DailyService.started(session)
	end
	if outcome.waiting then
		against ..= ", while waiting"
	end
	print(`[270] match {matchId} started ({outcome.kind}), seed {seed}{against}`)
	pcall(Analytics.matchStarted, factsOf(session, matchInfo[matchId]))
	flush(session)
	if pairCapped then
		for _, id in outcome.players do
			Replication.send(id, { kind = "Notice", notice = "MatchUnrated" })
		end
	end
	if outcome.waiting then
		for _, id in outcome.players do
			Replication.send(id, { kind = "Notice", notice = "WaitBot" })
		end
	end
	task.spawn(shareNames, session)
end

-- ---------------------------------------------------------------- matchmaking (D-083)

local function notify(id: string, code: string)
	Replication.send(id, { kind = "Notice", notice = code })
end

-- Every player waiting in this server's line has a ticket in the game-wide
-- queue (CrossServer.queued keeps an existing one as it is).
local function relist()
	for _, id in lobby.queue do
		local at = queuedAt[id]
		if at == nil then
			at = os.time()
			queuedAt[id] = at
		end
		CrossServer.queued(id, at, lobby.botWait[id] == true)
	end
end

-- Acts on what a lobby step produced: a match starts; an offer asks its
-- players (the ones in a bot game answer, the others wait, D-083).
local function apply(outcome: Lobby.Outcome?)
	if outcome == nil then
		return
	end
	if outcome.kind == "Match" or outcome.kind == "Practice" then
		startMatch(outcome)
	elseif outcome.kind == "Offer" then
		for _, id in outcome.players do
			-- Out of the game-wide queue while they answer; back in if it falls through.
			CrossServer.forget(id)
			sendLobby(id)
		end
		print(`[270] opponent found for {table.concat(outcome.players, " and ")}: waiting for an answer`)
	end
end

-- Pairs the front of the line again (someone came back to it).
local function repair()
	apply(Lobby.pair(lobby, now()))
	relist()
end

-- A player in a bot game said no to an offer, or did not answer in time:
-- they keep playing it, out of the line; the others are first in line again.
local function declined(id: string, outcome: Lobby.Outcome, why: string, remote: boolean)
	queuedAt[id] = nil
	if remote then
		CrossServer.answer(id, false)
	else
		CrossServer.forget(id)
	end
	notify(id, why)
	sendLobby(id)
	for _, other in outcome.players do
		notify(other, "OpponentDeclined")
	end
	repair()
	broadcastLobby()
end

-- Answer (D-083): "Opponent found! Leave this bot game?" Accept ends the bot
-- game (abandoned: unrated, nothing saved, the tutorial flag untouched) and
-- starts the match once every player in a bot game has accepted. Returns a
-- reason code when there is nothing to answer.
local function answerOffer(id: string, accept: boolean): string?
	local offer = Lobby.pending(lobby, id)
	if offer == nil then
		return Lobby.Reason.NoOffer
	end
	local remote = offer.remote == true
	if not accept then
		local outcome = Lobby.answer(lobby, id, false)
		if outcome then
			declined(id, outcome, "OfferDeclined", remote)
		end
		return nil
	end
	local session = sessions[matchOf[id] or ""]
	if session then
		guard(session, function()
			Session.abort(session, now())
		end)
		flush(session)
	end
	local outcome, reason = Lobby.answer(lobby, id, true)
	if outcome and outcome.kind == "Remote" then
		foundAs[id] = { phase = "Joining" }
		CrossServer.answer(id, true)
		sendLobby(id)
	elseif outcome then
		apply(outcome)
	else
		sendLobby(id) -- waiting for the other player's answer, or back in line
		relist()
	end
	return reason
end

-- Rematch (D-083): against the bot a new match at the same level at once;
-- against a person once both have tapped within the window.
local function rematchRequest(player: Player, matchId: string): string?
	local id = idOf(player)
	local entry = rematches[matchId]
	if entry == nil or rematchOf[id] ~= matchId then
		return Rematch.Reason.NotYours
	end
	if matchOf[id] ~= nil then
		return "InMatch"
	end
	local verdict, reason = Rematch.ask(entry.offer, id, now())
	if verdict == nil then
		sendRematch(entry)
		return reason
	end
	pcall(Analytics.rematch, id, if entry.info.kind == "Practice" then "Practice" else "Match")
	if verdict == "Waiting" then
		print(`[270] player {id} asks for a rematch of {matchId}`)
		sendRematch(entry)
		return nil
	end
	local info = entry.info
	local outcome: Lobby.Outcome? = nil
	local why: string? = nil
	if info.kind == "Practice" then
		if info.daily then
			-- After a Daily Race (D-082): today's race again, a practice run once
			-- today's run counted (DailyService decides as it starts).
			local race = DailyService.race()
			outcome, why = Lobby.daily(lobby, id, race.day, race.level)
		elseif info.waiting and Lobby.botAt(lobby, id) ~= nil then
			-- Still in line: another bot game while they wait.
			outcome, why = Lobby.waitBot(lobby, id, now(), info.difficulty)
		else
			outcome, why = Lobby.practice(lobby, id, info.difficulty, nil)
		end
	else
		outcome, why = Lobby.direct(lobby, entry.offer.players, { events = info.events })
		if outcome then
			outcome.private = info.private -- a private match's rematch stays private (D-094)
		end
	end
	sendRematch(entry)
	closeRematch(matchId)
	if outcome == nil then
		for _, other in entry.offer.players do
			if other ~= id then
				local them = playerOf(other)
				if them then
					Replication.reject(them, "Rematch", why or "Rejected")
				end
			end
		end
		return why
	end
	print(`[270] rematch of {matchId}`)
	startMatch(outcome)
	return nil
end

-- Return (D-083): from a match server back to a lobby server.
local function returnToLobby(player: Player): string?
	local id = idOf(player)
	if not matchServer then
		return "NotMatchServer"
	end
	if matchOf[id] ~= nil then
		return "InMatch"
	end
	leaveRematch(id)
	Lobby.leave(lobby, id)
	CrossServer.forget(id)
	Lobby.hold(lobby, id)
	foundAs[id] = { phase = "Leaving" }
	sendLobby(id)
	task.spawn(CrossServer.toLobby, player, nil, false, function(_: Player)
		Lobby.unhold(lobby, id)
		foundAs[id] = nil
		notify(id, "TeleportFailed")
		sendLobby(id)
	end)
	return nil
end

-- A private code that is not on this server: look it up across servers.
-- The player is held (Found) while the match server is set up. Yields.
local function joinRemote(player: Player, code: string)
	local id = idOf(player)
	local why = CrossServer.join(id, code)
	if why then
		Replication.reject(player, "Join", why)
		sendLobby(id)
	end
end

local function lobbyRequest(player: Player, request: Remotes.Request)
	local id = idOf(player)
	local outcome, reason = nil, nil
	local op = request.op
	if
		op == "Queue"
		or op == "Host"
		or op == "Join"
		or op == "Practice"
		or op == "WaitBot"
		or op == "DailyRace"
	then
		-- Starting anything else gives up a rematch (D-083).
		leaveRematch(id)
	end
	if op == "Queue" then
		outcome, reason = Lobby.queue(lobby, id, now())
		if outcome then
			CrossServer.forget(id)
			queuedAt[id] = os.time()
		end
	elseif op == "Host" then
		local code = newCode()
		outcome, reason = Lobby.host(lobby, id, code, { events = request.events })
		if outcome then
			queuedAt[id] = nil
			CrossServer.forget(id)
			CrossServer.hosted(id, code, request.events)
		end
	elseif op == "Join" then
		outcome, reason = Lobby.join(lobby, id, request.code :: string)
		if reason == "NoSuchCode" and CrossServer.enabled() then
			if cooled(id, "JoinRemote", JOIN_COOLDOWN) then
				reason = nil
				task.spawn(joinRemote, player, request.code :: string)
			else
				reason = "RateLimited"
			end
		end
	elseif op == "Practice" then
		-- The tutorial (D-075): asked for from How to play, or this player's
		-- first bot match (their saved profile says they have not finished it).
		local tutorial: Lobby.Tutorial? = if request.tutorial == true
			then "Replay"
			elseif Profile.needsTutorial(DataService.profile(id)) then "First"
			else nil
		outcome, reason = Lobby.practice(lobby, id, request.difficulty, tutorial)
	elseif op == "DailyRace" then
		-- Today's Daily Race (D-082): never the tutorial; the first run past week 1 counts.
		local race = DailyService.race()
		outcome, reason = Lobby.daily(lobby, id, race.day, race.level)
	elseif op == "WaitBot" then
		if cooled(id, op, REQUEST_COOLDOWN) then
			outcome, reason = Lobby.waitBot(lobby, id, now(), request.difficulty)
		else
			reason = "RateLimited"
		end
	elseif op == "Answer" then
		reason = if cooled(id, op, REQUEST_COOLDOWN / 2)
			then answerOffer(id, request.accept == true)
			else "RateLimited"
	elseif op == "Rematch" then
		reason = if cooled(id, op, REQUEST_COOLDOWN)
			then rematchRequest(player, request.matchId :: string)
			else "RateLimited"
	elseif op == "Return" then
		reason = if cooled(id, op, REQUEST_COOLDOWN) then returnToLobby(player) else "RateLimited"
	elseif op == "Leave" then
		Lobby.leave(lobby, id)
		local at = queuedAt[id]
		if at then
			pcall(Analytics.unqueued, id, os.time() - at, "Left")
		end
		queuedAt[id] = nil
		foundAs[id] = nil
		CrossServer.forget(id)
		repair()
	elseif op == "PrePick" then
		prePicks[id] = request.pick
	elseif op == "SetColor" then
		reason = setColor(player, request.color)
	end
	if reason then
		Replication.reject(player, op, reason)
	end
	if reason == nil then
		-- Analytics (D-094): looking for a game, the queue.
		if op == "Queue" then
			pcall(Analytics.queued, id)
		elseif op == "Host" or op == "Join" or op == "Practice" or op == "WaitBot" or op == "DailyRace" then
			pcall(Analytics.looking, id)
		end
	end
	if outcome and outcome.kind ~= "Waiting" then
		apply(outcome)
		relist()
		broadcastLobby()
	elseif op == "PrePick" or op == "SetColor" or op == "Answer" or op == "Rematch" or reason then
		sendLobby(id) -- only this player's own screen changes
	else
		relist()
		broadcastLobby() -- the queue or the open codes changed
	end
end

local function matchRequest(player: Player, request: Remotes.Request)
	local id = idOf(player)
	local session = sessions[matchOf[id] or ""]
	if session == nil or request.matchId ~= session.id then
		Replication.reject(player, request.op, "NotInMatch")
		return
	end
	local seat = Session.seatOf(session, id) :: number
	local accepted = false
	local reason: string? = nil
	local ran = guard(session, function()
		if request.op == "Submit" then
			accepted, reason = Session.submit(session, seat, request.step, request.input, now())
		elseif request.op == "Claim" then
			accepted, reason = Session.claim(session, seat, request.step, request.input, now())
		elseif request.op == "ClaimColor" then
			accepted, reason = Session.claimColor(session, seat, request.step, request.color, now())
		elseif request.op == "Bank" then
			accepted, reason = Session.bank(session, seat, request.step, now())
		else
			accepted, reason = Session.skip(session, seat, request.step, now())
		end
	end)
	if not ran then
		Replication.reject(player, request.op, "Internal")
	elseif not accepted then
		Replication.reject(player, request.op, reason or "Rejected")
	end
	flush(session)
end

-- Forfeit (D-059): the player leaves the match they are in and loses it, as a
-- disconnect forfeit does (rated against a human, a practice loss against the
-- bot); the match ends for everyone and the leaver is back in the lobby. A
-- player with no match (already out: a repeated request) just gets the lobby
-- again. A request for another match than theirs is turned down.
local function forfeit(player: Player, request: Remotes.Request)
	local id = idOf(player)
	local session = sessions[matchOf[id] or ""]
	if session == nil then
		sendLobby(id)
		return
	end
	if request.matchId ~= session.id then
		Replication.reject(player, request.op, "NotInMatch")
		return
	end
	local seat = Session.seatOf(session, id) :: number
	local accepted, reason = false, nil
	local ran = guard(session, function()
		accepted, reason = Session.forfeit(session, seat, now())
	end)
	if not ran then
		Replication.reject(player, request.op, "Internal")
	elseif not accepted and reason ~= Session.Reason.Over then
		Replication.reject(player, request.op, reason or "Rejected")
	end
	if accepted then
		print(`[270] player {id} left match {session.id} (forfeit)`)
	end
	flush(session)
end

-- SetTimersOff (D-081): an admin's "Timers off" toggle. Admins only, checked
-- here on every request (never the client's word); cooled down like the other
-- saved settings. Saved in their profile and applied to their match at once
-- (Session.setTimersOff: only where every human is an admin). Returns a reason
-- code when it is turned down.
local function setTimersOff(player: Player, on: boolean): string?
	local id = idOf(player)
	if not Admins.isAdmin(player) then
		return Session.Reason.AdminOnly
	end
	if not cooled(id, "SetTimersOff", config.SET_TIMERS_OFF_COOLDOWN) then
		return "RateLimited"
	end
	local how = DataService.update(id, function(profile: Profile.Profile): Profile.Profile
		return Profile.withTimersOff(profile, on)
	end)
	local session = sessions[matchOf[id] or ""]
	local reason: string? = nil
	if session then
		local seat = Session.seatOf(session, id) :: number
		local accepted, why = false, nil
		local ran = guard(session, function()
			accepted, why = Session.setTimersOff(session, seat, on, now())
		end)
		if not ran then
			reason = "Internal"
		elseif not accepted then
			reason = why or "Rejected"
		end
		flush(session)
	else
		if how == "Skipped" then
			reason = "TimersNotSaved"
		end
		sendLobby(id)
	end
	print(`[270] admin {id} timers {if on then "off" else "on"} ({how})`)
	return reason
end

-- Sends a player their current screen again (their match's State, or the
-- lobby), so a toggle painted ahead of the server's answer goes back (D-081).
local function resend(id: string)
	local session = sessions[matchOf[id] or ""]
	if session then
		local seat = Session.seatOf(session, id) :: number
		Replication.send(id, { kind = "State", state = Session.payload(session, seat) })
	else
		sendLobby(id)
	end
end

-- Handles one schema-checked request.
function MatchService.handle(player: Player, request: Remotes.Request)
	local op = request.op
	if op == "Submit" or op == "Claim" or op == "ClaimColor" or op == "Bank" or op == "Skip" then
		matchRequest(player, request)
	elseif op == "Forfeit" then
		forfeit(player, request)
	elseif op == "SetName" then
		local reason = setName(player, request.name)
		if reason then
			Replication.reject(player, op, reason)
		end
		if matchOf[idOf(player)] == nil then
			sendLobby(idOf(player))
		end
	elseif op == "ReportName" then
		local reason = reportName(player, request.userId :: string)
		if reason then
			Replication.reject(player, op, reason)
		end
	elseif op == "ReviewList" or op == "ReviewKeep" or op == "ReviewRemove" then
		local reason = review(player, request)
		if reason then
			Replication.reject(player, op, reason)
		end
	elseif op == "BugReport" then
		bugReport(player, request)
	elseif op == "BugList" then
		bugList(player)
	elseif op == "SetTimersOff" then
		local reason = setTimersOff(player, request.on == true)
		if reason then
			Replication.reject(player, op, reason)
			resend(idOf(player))
		end
	elseif op == "Leaderboard" then
		LeaderboardService.request(idOf(player))
	elseif op == "Daily" then
		DailyService.request(idOf(player))
	elseif op == "Resync" then
		local id = idOf(player)
		local session = sessions[matchOf[id] or ""]
		if session then
			local seat = Session.seatOf(session, id) :: number
			Replication.send(id, { kind = "State", state = Session.payload(session, seat) })
		else
			sendLobby(id)
		end
	else
		lobbyRequest(player, request)
	end
end

-- ---------------------------------------------------------------- arrivals (D-083)

-- A match server starts its match once both players are here and their saved
-- profiles have loaded, or PROFILE_WAIT after both arrived (then unrated, as
-- any match whose ratings are not known). The seats and the seed come from
-- the spec in memory store, never from the teleport data.
local function tryStartSpec()
	local s = spec
	if s == nil or specStarted then
		return
	end
	for _, id in s.players do
		if playerOf(id) == nil then
			return
		end
	end
	local t = now()
	local since = arrivedAt or t
	arrivedAt = since
	for _, id in s.players do
		if DataService.rating(id) == nil and t - since < PROFILE_WAIT then
			return
		end
	end
	specStarted = true
	for _, id in s.players do
		foundAs[id] = nil
	end
	local outcome, why = Lobby.direct(lobby, s.players, { events = s.events })
	if outcome == nil then
		warn(`[270] match server could not start {s.match}: {why}`)
		return
	end
	outcome.private = if s.mode == "Code" then true else nil -- a private code's match (D-094)
	print(`[270] match server: both players are here, starting {s.match}`)
	startMatch(outcome, s.seed)
end

-- Sends a match server's waiting players back to a lobby server: the
-- opponent never came, or the match could not be read.
local function sendBack(noticeCode: string, requeue: boolean)
	for _, player in Players:GetPlayers() do
		local id = idOf(player)
		if matchOf[id] == nil and lobby.held[id] then
			foundAs[id] = { phase = "Leaving" }
			sendLobby(id)
			task.spawn(CrossServer.toLobby, player, noticeCode, requeue, function(_: Player)
				Lobby.unhold(lobby, id)
				foundAs[id] = nil
				notify(id, noticeCode)
				sendLobby(id)
			end)
		end
	end
end

-- A match server reads its spec and waits for its players (D-083).
local function runMatchServer()
	local loaded = CrossServer.loadSpec()
	spec = loaded
	if loaded == nil then
		warn("[270] match server: no match spec; sending players back")
		sendBack("MatchServerFailed", true)
		return
	end
	print(`[270] match server for {loaded.match}: {table.concat(loaded.players, " vs ")}`)
	-- Anyone here who is not one of its players is just a lobby player.
	for _, player in Players:GetPlayers() do
		local id = idOf(player)
		if table.find(loaded.players, id) == nil and foundAs[id] and foundAs[id].phase == "Arriving" then
			Lobby.unhold(lobby, id)
			foundAs[id] = nil
			sendLobby(id)
		end
	end
	tryStartSpec()
	task.delay(Matchmaking.ARRIVAL_TIMEOUT, function()
		if not specStarted then
			print(`[270] match server: the opponent did not arrive for {loaded.match}`)
			sendBack("OpponentNoShow", loaded.mode == "Queue")
		end
	end)
end

-- An invited friend joined with the host's code in their launch data
-- (D-083): straight into the host's private match, on this server or another.
local function inviteJoin(player: Player, code: string)
	local id = idOf(player)
	if playerOf(id) ~= player or matchOf[id] ~= nil or Lobby.state(lobby, id) ~= "Idle" then
		return
	end
	print(`[270] player {id} joined from an invite to code {code}`)
	local outcome, reason = Lobby.join(lobby, id, code)
	if outcome then
		apply(outcome)
		relist()
		broadcastLobby()
		return
	end
	if reason == "NoSuchCode" and CrossServer.enabled() then
		reason = CrossServer.join(id, code)
	end
	if reason == "NoSuchCode" or reason == "Unavailable" then
		notify(id, "InviteExpired")
	elseif reason == "CodeBusy" then
		notify(id, "InviteBusy")
	end
	sendLobby(id)
end

-- How a player arrived (D-083): back from a match server (a notice, and
-- maybe straight back into the queue), or from a friend's invite (its launch
-- data carries the host's code). GetJoinData is server-side; launch data can
-- take a few seconds to appear, so it is read again a few times. Yields.
local function readArrival(player: Player)
	local function joinData(): any
		local ok, data = pcall(function(): any
			return (player :: any):GetJoinData()
		end)
		return if ok and type(data) == "table" then data else nil
	end
	local data = joinData()
	if data == nil then
		return
	end
	local id = idOf(player)
	local noticeCode, requeue = Matchmaking.readTravel(data.TeleportData)
	if noticeCode then
		notify(id, noticeCode)
	end
	if requeue and not matchServer and matchOf[id] == nil and Lobby.state(lobby, id) == "Idle" then
		lobbyRequest(player, { op = "Queue" })
	end
	if matchServer then
		return -- a match server's players came for its match, not for an invite
	end
	local launch = data.LaunchData
	for _ = 1, LAUNCH_TRIES do
		if type(launch) == "string" and launch ~= "" then
			break
		end
		task.wait(LAUNCH_WAIT)
		if playerOf(id) ~= player then
			return
		end
		local again = joinData()
		launch = if again then again.LaunchData else nil
	end
	local code = Matchmaking.codeFromLaunch(launch)
	if code then
		inviteJoin(player, code)
	end
end

-- Offers nobody answered, rematch windows that closed, and a match server
-- whose players are all here (D-083).
local function matchmakingTick(t: number)
	for _, item in Lobby.expire(lobby, t) do
		declined(item.id, item.outcome, "OfferExpired", item.remote)
	end
	for matchId, entry in rematches do
		local offer = entry.offer
		if not offer.vsBot and not offer.started and not entry.told and t > offer.untilAt then
			entry.told = true
			sendRematch(entry)
		end
		if Rematch.closed(offer, t) and (entry.told or offer.vsBot or offer.started) then
			closeRematch(matchId)
		end
	end
	if spec ~= nil and not specStarted then
		tryStartSpec()
	end
end

function MatchService.start()
	DataService.start()
	MatchLog.start()
	Analytics.start()
	LeaderboardService.start({
		send = function(id: string, board)
			Replication.send(id, { kind = "Leaderboard", leaderboard = board })
		end,
		-- Only a player with rated games has a place on the board.
		ratingOf = function(id: string): number?
			local profile = DataService.profile(id)
			return if profile and profile.games > 0 then profile.rating else nil
		end,
	})
	-- Results another server left for a player here were merged into their profile.
	DataService.onResult(function(id: string, change: Profile.Change)
		if change.rated then
			LeaderboardService.record(id, change.after)
		end
		if matchOf[id] == nil then
			sendLobby(id)
		end
	end)
	DataService.onLoaded(function(id: string)
		if matchOf[id] == nil then
			sendLobby(id)
			DailyService.tell(id) -- the streak and today's run are known now (D-082)
		end
		tryStartSpec()
		pcall(Analytics.joined, id) -- the visit funnel, and the onboarding funnel for a new player (D-094)
		task.spawn(approveSavedName, id)
		-- Ratings saved before the board existed join it on the player's next visit.
		local profile = DataService.profile(id)
		if profile and profile.games > 0 and DataService.rating(id) ~= nil then
			LeaderboardService.record(id, profile.rating)
			LeaderboardService.recordLandslides(id, Profile.landslides(profile)) -- D-094; none: no write
		end
	end)
	-- Matching across servers and the online count (D-083). Both are off in
	-- Studio and in an unpublished place: matches are made in-server there.
	CrossServer.start({
		isWaiting = function(id: string): boolean
			return playerOf(id) ~= nil and table.find(lobby.queue, id) ~= nil
		end,
		isHosting = function(id: string, code: string): boolean
			return playerOf(id) ~= nil and lobby.hosting[id] == code and not lobby.held[id]
		end,
		ask = function(id: string, untilAt: number): boolean
			if Lobby.offerRemote(lobby, id, untilAt) then
				print(`[270] opponent found on another server for {id}: asking them`)
				sendLobby(id)
				return true
			end
			return false
		end,
		hold = function(id: string, phase: string, untilAt: number?)
			if matchOf[id] ~= nil then
				return -- already playing a match here
			end
			Lobby.hold(lobby, id)
			foundAs[id] = { phase = phase :: Remotes.FoundPhase, untilAt = untilAt }
			sendLobby(id)
			broadcastLobby()
		end,
		unhold = function(id: string, noticeCode: string?)
			Lobby.withdraw(lobby, id) -- a question about a pairing that is gone
			Lobby.unhold(lobby, id)
			foundAs[id] = nil
			if noticeCode then
				notify(id, noticeCode)
			end
			sendLobby(id)
			repair()
			broadcastLobby()
		end,
		recode = function(id: string)
			local old = lobby.hosting[id]
			if old == nil then
				return
			end
			local events = lobby.options[old] and lobby.options[old].events
			Lobby.leave(lobby, id)
			local code = newCode()
			if Lobby.host(lobby, id, code, { events = events }) then
				CrossServer.hosted(id, code, events)
			end
			sendLobby(id)
		end,
	})
	OnlineCount.onChanged(function(count: number?)
		if count ~= onlineShown then
			onlineShown = count
			broadcastLobby()
		end
	end)
	OnlineCount.start()
	if matchServer then
		task.spawn(runMatchServer)
	end
	PassService.start()
	NameReview.start()
	NameReview.onBlocklist(onBlocklist)
	PassService.onChanged(function(id: string)
		if matchOf[id] == nil then
			sendLobby(id)
			return
		end
		-- Bought the Name Pass during a match: Select offers the name at once.
		local session = sessions[matchOf[id] or ""]
		if session then
			local seat = Session.seatOf(session, id) :: number
			guard(session, function()
				Session.setNamePass(session, seat, namePassOf(id))
			end)
			flush(session)
		end
		if approvedNames[id] == nil then
			task.spawn(approveSavedName, id)
		end
	end)
	-- Name eligibility (D-069) is asked once per visit, then the saved name is
	-- filtered for it.
	local function checkNames(player: Player)
		Admins.refresh(player)
		if Admins.isAdmin(player) then
			NameReview.refreshCount() -- the Review names button's count
		end
		NameEligibility.refresh(player)
		local id = idOf(player)
		approveSavedName(id)
		if playerOf(id) ~= player then
			return -- they left meanwhile
		end
		local session = sessions[matchOf[id] or ""]
		if session == nil then
			sendLobby(id)
			return
		end
		-- Matched (or back in a match) before the check returned: their seat
		-- follows it now, and the names in the match are shared with them.
		local seat = Session.seatOf(session, id) :: number
		guard(session, function()
			Session.setSeesNames(session, seat, eligible(id))
			Session.setNamePass(session, seat, namePassOf(id))
		end)
		flush(session)
		task.spawn(shareNames, session)
	end
	for _, player in Players:GetPlayers() do
		sendLobby(idOf(player))
		task.spawn(checkNames, player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(checkNames, player)
		local id = idOf(player)
		local session = sessions[matchOf[id] or ""]
		if session then
			guard(session, function()
				Session.reconnect(session, Session.seatOf(session, id) :: number, now())
			end)
			flush(session)
		else
			-- A match server's player waits for their opponent (D-083).
			if matchServer and not specStarted and (spec == nil or table.find(spec.players, id) ~= nil) then
				Lobby.hold(lobby, id)
				foundAs[id] = { phase = "Arriving" }
			end
			sendLobby(id)
			tryStartSpec()
		end
		task.spawn(readArrival, player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local id = idOf(player)
		local before = Lobby.state(lobby, id)
		Lobby.leave(lobby, id)
		prePicks[id] = nil
		approvedNames[id] = nil
		shownTo[id] = nil
		reports[id] = nil
		lastRequest[id] = nil
		NameEligibility.forget(player)
		Admins.forget(player)
		NameService.forget(player)
		Analytics.left(id)
		-- Matchmaking (D-083): their tickets and a rematch with them are gone;
		-- anyone they were paired with here is first in line again.
		leaveRematch(id)
		CrossServer.forget(id)
		queuedAt[id] = nil
		foundAs[id] = nil
		if before == "Queued" or before == "Hosting" or before == "Found" then
			repair()
			broadcastLobby()
		end
		local session = sessions[matchOf[id] or ""]
		if session then
			guard(session, function()
				Session.disconnect(session, Session.seatOf(session, id) :: number, now())
			end)
			flush(session)
		end
	end)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < TICK then
			return
		end
		elapsed = 0
		local t = now()
		matchmakingTick(t)
		for _, session in sessions do
			if t >= Session.nextWake(session) then
				guard(session, function()
					Session.update(session, t)
				end)
				flush(session)
			end
		end
	end)
end

return MatchService
