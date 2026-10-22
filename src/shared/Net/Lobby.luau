--!strict
-- In-server lobby: the public queue, private match codes, and practice games.
-- Pure bookkeeping; LobbyService does the Roblox side and makes the codes.
-- Up to MATCHES_PER_SERVER matches run at once (practice games count).

local ConfigModule = require("../Sim/Config")

type Config = ConfigModule.Config

export type Lobby = {
	capacity: number,
	active: number, -- matches running now
	queue: { string }, -- player ids, first come first served
	codes: { [string]: string }, -- code -> host id
	hosting: { [string]: string }, -- host id -> code
	playing: { [string]: boolean }, -- ids in a match
}

-- What a lobby request produced.
export type Outcome = {
	kind: "Waiting" | "Match" | "Practice",
	players: { string }, -- Match: both ids, first in line first
	code: string?, -- Waiting while hosting
}

local Lobby = {}

function Lobby.new(config: Config): Lobby
	return {
		capacity = config.MATCHES_PER_SERVER,
		active = 0,
		queue = {},
		codes = {},
		hosting = {},
		playing = {},
	}
end

-- Removes a player from the queue and closes any code they host.
function Lobby.leave(lobby: Lobby, id: string)
	local at = table.find(lobby.queue, id)
	if at then
		table.remove(lobby.queue, at)
	end
	local code = lobby.hosting[id]
	if code then
		lobby.codes[code] = nil
		lobby.hosting[id] = nil
	end
end

local function start(lobby: Lobby, ids: { string })
	lobby.active += 1
	for _, id in ids do
		Lobby.leave(lobby, id)
		lobby.playing[id] = true
	end
end

local function check(lobby: Lobby, id: string): string?
	if lobby.playing[id] then
		return "InMatch"
	end
	if lobby.active >= lobby.capacity then
		return "ServerFull"
	end
	return nil
end

-- Joins the public queue; pairs the two longest-waiting players.
function Lobby.queue(lobby: Lobby, id: string): (Outcome?, string?)
	local reason = check(lobby, id)
	if reason then
		return nil, reason
	end
	Lobby.leave(lobby, id)
	table.insert(lobby.queue, id)
	if #lobby.queue >= 2 then
		local pair = { lobby.queue[1], lobby.queue[2] }
		start(lobby, pair)
		return { kind = "Match", players = pair }, nil
	end
	return { kind = "Waiting", players = { id } }, nil
end

-- Opens a private match under `code` (made by the caller, unique on this server).
function Lobby.host(lobby: Lobby, id: string, code: string): (Outcome?, string?)
	local reason = check(lobby, id)
	if reason then
		return nil, reason
	end
	if lobby.codes[code] then
		return nil, "CodeTaken"
	end
	Lobby.leave(lobby, id)
	lobby.codes[code] = id
	lobby.hosting[id] = code
	return { kind = "Waiting", players = { id }, code = code }, nil
end

-- Joins a private match by code.
function Lobby.join(lobby: Lobby, id: string, code: string): (Outcome?, string?)
	local reason = check(lobby, id)
	if reason then
		return nil, reason
	end
	local host = lobby.codes[code]
	if host == nil then
		return nil, "NoSuchCode"
	end
	if host == id then
		return nil, "OwnCode"
	end
	local pair = { host, id }
	start(lobby, pair)
	return { kind = "Match", players = pair }, nil
end

-- Starts a practice match against the bot.
function Lobby.practice(lobby: Lobby, id: string): (Outcome?, string?)
	local reason = check(lobby, id)
	if reason then
		return nil, reason
	end
	start(lobby, { id })
	return { kind = "Practice", players = { id } }, nil
end

-- A match is over (or abandoned): its players are free again.
function Lobby.ended(lobby: Lobby, ids: { string })
	lobby.active = math.max(0, lobby.active - 1)
	for _, id in ids do
		lobby.playing[id] = nil
	end
end

function Lobby.state(lobby: Lobby, id: string): ("Idle" | "Queued" | "Hosting" | "InMatch", string?)
	if lobby.playing[id] then
		return "InMatch", nil
	elseif lobby.hosting[id] then
		return "Hosting", lobby.hosting[id]
	elseif table.find(lobby.queue, id) then
		return "Queued", nil
	end
	return "Idle", nil
end

return table.freeze(Lobby)
