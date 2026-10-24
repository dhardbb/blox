--!strict
-- In-server lobby: the public queue, private match codes, and practice games.
-- Pure bookkeeping; LobbyService does the Roblox side and makes the codes.
-- Up to MATCHES_PER_SERVER matches run at once (practice games count).

local Bot = require("../Sim/Bot")
local ConfigModule = require("../Sim/Config")

type Config = ConfigModule.Config

export type Lobby = {
	capacity: number,
	active: number, -- matches running now
	queue: { string }, -- player ids, first come first served
	codes: { [string]: string }, -- code -> host id
	hosting: { [string]: string }, -- host id -> code
	options: { [string]: Options }, -- code -> the host's match options
	playing: { [string]: boolean }, -- ids in a match
}

export type PlayerState = "Idle" | "Queued" | "Hosting" | "InMatch"

-- What a private host may choose (same shape as Net/Session.Options).
export type Options = {
	events: boolean?, -- false turns the event deck off (D-027)
}

-- What a lobby request produced.
export type Outcome = {
	kind: "Waiting" | "Match" | "Practice",
	players: { string }, -- Match: both ids, first in line first
	code: string?, -- Waiting while hosting
	events: boolean?, -- Match from a private code: false if the host turned events off
	difficulty: Bot.Difficulty?, -- Practice: the bot's difficulty (D-057)
	tutorial: boolean?, -- Practice: the tutorial, no choice timers (D-075)
	daily: number?, -- Practice: a Daily Race run on this day (D-080); never the tutorial
}

-- Why a practice match is the tutorial (D-075): "First", the player has not
-- finished it yet (the server reads their profile); "Replay", they asked for it
-- from How to play.
export type Tutorial = "First" | "Replay"

local Lobby = {}

function Lobby.new(config: Config): Lobby
	return {
		capacity = config.MATCHES_PER_SERVER,
		active = 0,
		queue = {},
		codes = {},
		hosting = {},
		options = {},
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
		lobby.options[code] = nil
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
-- `options` are the host's settings for the match (events on unless false).
function Lobby.host(lobby: Lobby, id: string, code: string, options: Options?): (Outcome?, string?)
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
	lobby.options[code] = { events = if options and options.events == false then false else nil }
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
	local options = lobby.options[code]
	start(lobby, pair)
	return { kind = "Match", players = pair, events = options and options.events }, nil
end

-- Starts a practice match against the bot at `difficulty` (absent or unknown:
-- Medium, D-057). With `tutorial` it is the tutorial (D-075): the first one
-- keeps the level the player picked; a replay always plays the Easy bot.
function Lobby.practice(
	lobby: Lobby,
	id: string,
	difficulty: string?,
	tutorial: Tutorial?
): (Outcome?, string?)
	local reason = check(lobby, id)
	if reason then
		return nil, reason
	end
	start(lobby, { id })
	local level: Bot.Difficulty = if tutorial == "Replay" then "Easy" else Bot.difficulty(difficulty)
	return {
		kind = "Practice",
		players = { id },
		difficulty = level,
		tutorial = if tutorial ~= nil then true else nil,
	},
		nil
end

-- Starts a run of day `day`'s Daily Race against the bot at `level` (D-080:
-- Config.DAILY_BOT_LEVEL). A Daily Race is never the tutorial.
function Lobby.daily(lobby: Lobby, id: string, day: number, level: string?): (Outcome?, string?)
	local reason = check(lobby, id)
	if reason then
		return nil, reason
	end
	start(lobby, { id })
	return { kind = "Practice", players = { id }, difficulty = Bot.difficulty(level), daily = day }, nil
end

-- A match is over (or abandoned): its players are free again.
function Lobby.ended(lobby: Lobby, ids: { string })
	lobby.active = math.max(0, lobby.active - 1)
	for _, id in ids do
		lobby.playing[id] = nil
	end
end

function Lobby.state(lobby: Lobby, id: string): (PlayerState, string?)
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
