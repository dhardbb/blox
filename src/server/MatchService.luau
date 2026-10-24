--!strict
-- Runs every match on this server: the lobby (queue, private codes, practice),
-- one Net/Session per match, a clock that advances them, connection changes,
-- and cleanup. The game logic lives in Net/Session and Sim; this module only
-- feeds them requests and the server time and sends what they produce.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Bot = require(ReplicatedStorage.Shared.Sim.Bot)
local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Config = require(ReplicatedStorage.Shared.Sim.Config)
local CustomName = require(ReplicatedStorage.Shared.Net.CustomName)
local Lobby = require(ReplicatedStorage.Shared.Net.Lobby)
local Profile = require(ReplicatedStorage.Shared.Net.Profile)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local DataService = require(script.Parent.DataService)
local Admins = require(script.Parent.Admins)
local LeaderboardService = require(script.Parent.LeaderboardService)
local NameEligibility = require(script.Parent.NameEligibility)
local NameReview = require(script.Parent.NameReview)
local NameService = require(script.Parent.NameService)
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
	return {
		id = id,
		kind = "Human",
		prePick = prePicks[id],
		colorPass = owns,
		color = if profile then profile.color else nil,
		seesNames = eligible(id),
		namePass = namePass,
		customName = if namePass and namePass.owned then approvedNames[id] else nil,
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
		-- A forfeit or a drop before week 1 counts for no one (D-077).
		starts = nil
		print(`[270] match {session.id} is unrated: it ended before week 1`)
		for _, seat in session.seats do
			if seat.kind == "Human" then
				Replication.send(seat.id, { kind = "Notice", notice = "ForfeitUnrated" })
			end
		end
	end
	if starts == nil and not vsBot then
		return
	end
	-- A forfeit can follow the last plan, after the election was computed but
	-- before anyone saw it: only a shown election has electoral votes to record.
	local election = if result.reason == "Election" then session.match.election else nil
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
		}
		local function announce(applied: Profile.Change)
			if applied.rated then
				Replication.send(seat.id, {
					kind = "Rating",
					rating = { matchId = session.id, before = applied.before, after = applied.after },
				})
				LeaderboardService.record(seat.id, applied.after)
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

-- Sends a session's queued messages; ends the match in the lobby once it is over.
local function flush(session: Session.Session)
	for _, message in Session.drain(session) do
		local seat = session.seats[message.seat]
		local out: Remotes.Message = { kind = message.kind, state = message.state, notice = message.notice }
		Replication.send(seat.id, out)
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
		local settled, err = pcall(function(): string?
			settle(session)
			return nil
		end)
		if not settled then
			warn(`[270] match {session.id}: could not apply the result to saved data: {err}`)
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

local function startMatch(outcome: Lobby.Outcome)
	matchCount += 1
	local matchId = `m{matchCount}`
	local seed = random:NextInteger(1, 2 ^ 31 - 1)
	local specs: { Session.SeatSpec } = {}
	for _, id in outcome.players do
		table.insert(specs, humanSpec(id))
	end
	if outcome.kind == "Practice" then
		local candidate = Candidates.ids[random:NextInteger(1, #Candidates.ids)]
		table.insert(specs, {
			id = "bot",
			kind = "Bot",
			candidate = candidate,
			difficulty = Bot.difficulty(outcome.difficulty), -- D-057: absent = Medium (the standard bot)
		})
	end
	local created: Session.Session? = nil
	local built, err = pcall(function(): string?
		created = Session.new(
			config,
			matchId,
			seed,
			specs,
			now(),
			{ events = outcome.events, tutorial = outcome.kind == "Practice" and outcome.tutorial == true }
		)
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
	if outcome.tutorial then
		against ..= ", tutorial"
	end
	print(`[270] match {matchId} started ({outcome.kind}), seed {seed}{against}`)
	flush(session)
	if pairCapped then
		for _, id in outcome.players do
			Replication.send(id, { kind = "Notice", notice = "MatchUnrated" })
		end
	end
	task.spawn(shareNames, session)
end

local function lobbyRequest(player: Player, request: Remotes.Request)
	local id = idOf(player)
	local outcome, reason = nil, nil
	if request.op == "Queue" then
		outcome, reason = Lobby.queue(lobby, id)
	elseif request.op == "Host" then
		outcome, reason = Lobby.host(lobby, id, newCode(), { events = request.events })
	elseif request.op == "Join" then
		outcome, reason = Lobby.join(lobby, id, request.code :: string)
	elseif request.op == "Practice" then
		-- The tutorial (D-075): asked for from How to play, or this player's
		-- first bot match (their saved profile says they have not finished it).
		local tutorial: Lobby.Tutorial? = if request.tutorial == true
			then "Replay"
			elseif Profile.needsTutorial(DataService.profile(id)) then "First"
			else nil
		outcome, reason = Lobby.practice(lobby, id, request.difficulty, tutorial)
	elseif request.op == "Leave" then
		Lobby.leave(lobby, id)
	elseif request.op == "PrePick" then
		prePicks[id] = request.pick
	elseif request.op == "SetColor" then
		reason = setColor(player, request.color)
	end
	if reason then
		Replication.reject(player, request.op, reason)
	end
	if outcome and (outcome.kind == "Match" or outcome.kind == "Practice") then
		startMatch(outcome)
	elseif request.op == "PrePick" or request.op == "SetColor" or reason then
		sendLobby(id) -- only this player's own screen changes
	else
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
	elseif op == "Leaderboard" then
		LeaderboardService.request(idOf(player))
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

function MatchService.start()
	DataService.start()
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
		end
		task.spawn(approveSavedName, id)
		-- Ratings saved before the board existed join it on the player's next visit.
		local profile = DataService.profile(id)
		if profile and profile.games > 0 and DataService.rating(id) ~= nil then
			LeaderboardService.record(id, profile.rating)
		end
	end)
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
			sendLobby(id)
		end
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
		if before == "Queued" or before == "Hosting" then
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
