--!strict
-- Runs every match on this server: the lobby (queue, private codes, practice),
-- one Net/Session per match, a clock that advances them, connection changes,
-- and cleanup. The game logic lives in Net/Session and Sim; this module only
-- feeds them requests and the server time and sends what they produce.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Config = require(ReplicatedStorage.Shared.Sim.Config)
local Lobby = require(ReplicatedStorage.Shared.Net.Lobby)
local Profile = require(ReplicatedStorage.Shared.Net.Profile)
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local DataService = require(script.Parent.DataService)
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
local ratingsAtStart: { [string]: { [string]: number } } = {} -- match id -> player id -> rating; rated matches only
local random = Random.new()
local matchCount = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function idOf(player: Player): string
	return tostring(player.UserId)
end

local function sendLobby(id: string)
	local state: Lobby.PlayerState, code = Lobby.state(lobby, id)
	local status: Remotes.LobbyStatus = {
		state = state,
		code = code,
		queued = #lobby.queue,
		full = lobby.active >= lobby.capacity,
		profile = DataService.summary(id),
	}
	Replication.send(id, { kind = "Lobby", lobby = status })
end

-- Applies a finished match to each human's saved profile and tells them how
-- their rating moved. Only a human-vs-human match decided by an election or a
-- forfeit is rated (and only if both ratings were known at the start); against
-- the bot it only adds to the practice record; an abandoned match changes nothing.
local function settle(session: Session.Session)
	local starts = ratingsAtStart[session.id]
	ratingsAtStart[session.id] = nil
	local result = session.result :: Session.Result
	if result.reason == "Abandoned" or result.winner == 0 then
		return
	end
	local election = session.match.election
	local at = os.time()
	for me, seat in session.seats do
		if seat.kind ~= "Human" then
			continue
		end
		local them = if me == 1 then 2 else 1
		local input: Profile.Result = {
			at = at,
			reason = result.reason,
			rated = starts ~= nil,
			won = result.winner == me,
			candidate = session.match.players[me].candidate,
			opponentCandidate = session.match.players[them].candidate,
			opponentRating = if starts then starts[session.seats[them].id] else nil,
			evFor = if election then election.ev[me] else nil,
			evAgainst = if election then election.ev[them] else nil,
		}
		local change: Profile.Change? = nil
		local how = DataService.update(seat.id, function(profile: Profile.Profile): Profile.Profile
			local updated, applied = Profile.applyResult(profile, input, config)
			change = applied
			return updated
		end)
		if how == "Skipped" and starts then
			warn(`[270] match {session.id}: could not record the result for player {seat.id}`)
		end
		local applied = change
		if how == "Live" and applied and applied.rated then
			Replication.send(seat.id, {
				kind = "Rating",
				rating = { matchId = session.id, before = applied.before, after = applied.after },
			})
			print(`[270] player {seat.id} rating {applied.before} -> {applied.after} (match {session.id})`)
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
		for _, id in ids do
			sendLobby(id)
		end
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
		table.insert(specs, { id = id, kind = "Human", prePick = prePicks[id] })
	end
	if outcome.kind == "Practice" then
		local candidate = Candidates.ids[random:NextInteger(1, #Candidates.ids)]
		table.insert(specs, { id = "bot", kind = "Bot", candidate = candidate, style = "Balanced" })
	end
	local created: Session.Session? = nil
	local built, err = pcall(function(): string?
		created = Session.new(config, matchId, seed, specs, now(), { events = outcome.events })
		return nil
	end)
	local session = created
	if not built or session == nil then
		-- The lobby already counted this match; hand the players back.
		warn(`[270] match {matchId} could not start: {err}`)
		Lobby.ended(lobby, outcome.players)
		for _, id in outcome.players do
			sendLobby(id)
		end
		return
	end
	sessions[matchId] = session
	if outcome.kind == "Match" then
		-- Rated only if every player's saved rating is loaded and writable now.
		local ratings: { [string]: number } = {}
		for _, id in outcome.players do
			local rating = DataService.rating(id)
			if rating then
				ratings[id] = rating
			end
		end
		if #outcome.players == 2 and ratings[outcome.players[1]] and ratings[outcome.players[2]] then
			ratingsAtStart[matchId] = ratings
		else
			print(`[270] match {matchId} is unrated: a player's saved data is not available`)
		end
	end
	for _, id in outcome.players do
		matchOf[id] = matchId
		sendLobby(id)
	end
	print(`[270] match {matchId} started ({outcome.kind}), seed {seed}`)
	flush(session)
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
		outcome, reason = Lobby.practice(lobby, id)
	elseif request.op == "Leave" then
		Lobby.leave(lobby, id)
	elseif request.op == "PrePick" then
		prePicks[id] = request.pick
	end
	if reason then
		Replication.reject(player, request.op, reason)
	end
	if outcome and (outcome.kind == "Match" or outcome.kind == "Practice") then
		startMatch(outcome)
	else
		sendLobby(id)
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

-- Handles one schema-checked request.
function MatchService.handle(player: Player, request: Remotes.Request)
	local op = request.op
	if op == "Submit" or op == "Bank" or op == "Skip" then
		matchRequest(player, request)
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
	DataService.onLoaded(function(id: string)
		if matchOf[id] == nil then
			sendLobby(id)
		end
	end)
	for _, player in Players:GetPlayers() do
		sendLobby(idOf(player))
	end
	Players.PlayerAdded:Connect(function(player)
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
		Lobby.leave(lobby, id)
		prePicks[id] = nil
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
