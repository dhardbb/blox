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
local Remotes = require(ReplicatedStorage.Shared.Net.Remotes)
local Session = require(ReplicatedStorage.Shared.Net.Session)
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
	}
	Replication.send(id, { kind = "Lobby", lobby = status })
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
		for _, id in ids do
			sendLobby(id)
		end
		local result = session.result :: Session.Result
		print(`[270] match {session.id} over: {result.reason}, winner seat {result.winner}`)
	end
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
	local session = Session.new(config, matchId, seed, specs, now())
	sessions[matchId] = session
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
		outcome, reason = Lobby.host(lobby, id, newCode())
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
	local ok, reason
	if request.op == "Submit" then
		ok, reason = Session.submit(session, seat, request.step, request.input, now())
	elseif request.op == "Bank" then
		ok, reason = Session.bank(session, seat, request.step, now())
	else
		ok, reason = Session.skip(session, seat, request.step, now())
	end
	if not ok then
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
	for _, player in Players:GetPlayers() do
		sendLobby(idOf(player))
	end
	Players.PlayerAdded:Connect(function(player)
		local id = idOf(player)
		local session = sessions[matchOf[id] or ""]
		if session then
			Session.reconnect(session, Session.seatOf(session, id) :: number, now())
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
			Session.disconnect(session, Session.seatOf(session, id) :: number, now())
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
				local ok, err = pcall(function(): string?
					Session.update(session, t)
					return nil
				end)
				if not ok then
					warn(`[270] match {session.id} failed: {err}`)
				end
				flush(session)
			end
		end
	end)
end

return MatchService
