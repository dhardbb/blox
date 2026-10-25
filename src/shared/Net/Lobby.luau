--!strict
-- In-server lobby: the public queue, private match codes, and practice games.
-- Pure bookkeeping; MatchService does the Roblox side and makes the codes.
-- Up to MATCHES_PER_SERVER matches run at once (practice games count).
--
-- Matchmaking (D-083) adds:
--   * a bot game while you wait: after QUEUE_BOT_OFFER_SECONDS in the queue a
--     player may play the bot (Lobby.waitBot) and keeps their place in line;
--   * offers: when the queue pairs a player who is in such a bot game, the
--     match waits for them to answer "Opponent found! Leave this bot game?"
--     (Lobby.answer) within QUEUE_ACCEPT_SECONDS. Accept: the match starts.
--     Decline or no answer: they keep playing and leave the queue; the other
--     player goes back to the front of the line;
--   * holds: a player being paired with someone on another server (or being
--     teleported) is out of the local queue but keeps their place in line
--     (Lobby.hold, Lobby.unhold);
--   * Lobby.direct: a match between given players (a rematch, a match server).

local Bot = require("../Sim/Bot")
local ConfigModule = require("../Sim/Config")

type Config = ConfigModule.Config

-- A pairing that waits for players in a bot game to answer (D-083).
export type Offer = {
	players: { string }, -- the pair, first in line first
	busy: { [string]: boolean }, -- players in a bot game: they must accept
	accepted: { [string]: boolean },
	untilAt: number, -- server time the answer is due
	remote: boolean?, -- the opponent is on another server (Lobby.offerRemote): `players` is this one player
}

export type Lobby = {
	capacity: number,
	active: number, -- matches running now
	queue: { string }, -- player ids, first come first served
	codes: { [string]: string }, -- code -> host id
	hosting: { [string]: string }, -- host id -> code
	options: { [string]: Options }, -- code -> the host's match options
	playing: { [string]: boolean }, -- ids in a match
	since: { [string]: number }, -- queued (or held) id -> server time they joined the line (D-083)
	botWait: { [string]: boolean }, -- queued ids playing the bot while they wait (D-083)
	offers: { [string]: Offer }, -- id -> the offer they are in (D-083)
	held: { [string]: boolean }, -- ids pairing across servers or leaving for a match server (D-083)
	botAfter: number, -- Config.QUEUE_BOT_OFFER_SECONDS
	acceptWindow: number, -- Config.QUEUE_ACCEPT_SECONDS
}

-- "Found": an opponent was found and the match is on its way (an offer waiting
-- on the other player's answer, or a pairing across servers, D-083).
export type PlayerState = "Idle" | "Queued" | "Hosting" | "InMatch" | "Found"

-- What a private host may choose (same shape as Net/Session.Options).
export type Options = {
	events: boolean?, -- false turns the event deck off (D-027)
}

-- What a lobby request produced.
export type Outcome = {
	kind: "Waiting" | "Match" | "Practice" | "Offer" | "Declined" | "Remote",
	players: { string }, -- Match: both ids, first in line first. Offer: the pair. Declined: back in line. Remote: the one who accepted
	code: string?, -- Waiting while hosting
	events: boolean?, -- Match from a private code: false if the host turned events off
	difficulty: Bot.Difficulty?, -- Practice: the bot's difficulty (D-057)
	tutorial: boolean?, -- Practice: the tutorial, no choice timers (D-075)
	daily: number?, -- Practice: a Daily Race run on this day (D-082); never the tutorial
	waiting: boolean?, -- Practice: a bot game while the player waits in the queue (D-083)
}

-- Why a practice match is the tutorial (D-075): "First", the player has not
-- finished it yet (the server reads their profile); "Replay", they asked for it
-- from How to play.
export type Tutorial = "First" | "Replay"

-- Reason codes added by D-083.
local Reason = table.freeze({
	Matching = "Matching", -- already joining a match (an offer or a pairing across servers)
	NotQueued = "NotQueued", -- a bot game while waiting needs a place in the queue
	TooSoon = "BotTooSoon", -- before QUEUE_BOT_OFFER_SECONDS in the queue
	NoOffer = "NoOffer", -- nothing to answer
})

local Lobby = {}
Lobby.Reason = Reason

function Lobby.new(config: Config): Lobby
	return {
		capacity = config.MATCHES_PER_SERVER,
		active = 0,
		queue = {},
		codes = {},
		hosting = {},
		options = {},
		playing = {},
		since = {},
		botWait = {},
		offers = {},
		held = {},
		botAfter = config.QUEUE_BOT_OFFER_SECONDS,
		acceptWindow = config.QUEUE_ACCEPT_SECONDS,
	}
end

-- Puts `id` back in the queue by the time they joined the line, so a player
-- whose pairing fell through is ahead of everyone who came later.
local function requeue(lobby: Lobby, id: string)
	if table.find(lobby.queue, id) then
		return
	end
	local at = lobby.since[id] or -math.huge
	local index = #lobby.queue + 1
	for k, other in lobby.queue do
		if (lobby.since[other] or -math.huge) > at then
			index = k
			break
		end
	end
	table.insert(lobby.queue, index, id)
end

-- Closes the offer `id` is in: everyone else goes back to the front of the line.
local function dropOffer(lobby: Lobby, id: string)
	local offer = lobby.offers[id]
	if offer == nil then
		return
	end
	for _, other in offer.players do
		lobby.offers[other] = nil
	end
	for _, other in offer.players do
		if other ~= id then
			requeue(lobby, other)
		end
	end
end

-- Removes a player from the queue and closes any code they host. A player in a
-- bot game while they wait keeps playing it, out of the line.
function Lobby.leave(lobby: Lobby, id: string)
	local at = table.find(lobby.queue, id)
	if at then
		table.remove(lobby.queue, at)
	end
	dropOffer(lobby, id)
	lobby.since[id] = nil
	lobby.botWait[id] = nil
	lobby.held[id] = nil
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
		lobby.offers[id] = nil
	end
	for _, id in ids do
		Lobby.leave(lobby, id)
		lobby.playing[id] = true
	end
end

local function check(lobby: Lobby, id: string): string?
	if lobby.playing[id] then
		return "InMatch"
	end
	if lobby.held[id] or lobby.offers[id] then
		return Reason.Matching
	end
	if lobby.active >= lobby.capacity then
		return "ServerFull"
	end
	return nil
end

-- Pairs the two players at the front of the line. Two players free to play
-- start a match; if one of them is in a bot game, an offer waits for their
-- answer (D-083). Nil if fewer than two are waiting.
function Lobby.pair(lobby: Lobby, now: number?): Outcome?
	if #lobby.queue < 2 then
		return nil
	end
	local pair = { lobby.queue[1], lobby.queue[2] }
	local busy: { [string]: boolean } = {}
	local anyBusy = false
	for _, id in pair do
		if lobby.botWait[id] then
			busy[id] = true
			anyBusy = true
		end
	end
	if not anyBusy then
		if lobby.active >= lobby.capacity then
			return nil -- no room yet: they wait in line until a match ends
		end
		start(lobby, pair)
		return { kind = "Match", players = pair }
	end
	local offer: Offer = {
		players = pair,
		busy = busy,
		accepted = {},
		untilAt = (now or 0) + lobby.acceptWindow,
	}
	for _, id in pair do
		local at = table.find(lobby.queue, id)
		if at then
			table.remove(lobby.queue, at)
		end
		lobby.offers[id] = offer
	end
	return { kind = "Offer", players = table.clone(pair) }
end

-- Joins the public queue; pairs the two longest-waiting players. `now` (server
-- time) starts the clock for a bot game while waiting (D-083).
function Lobby.queue(lobby: Lobby, id: string, now: number?): (Outcome?, string?)
	local reason = check(lobby, id)
	if reason then
		return nil, reason
	end
	Lobby.leave(lobby, id)
	table.insert(lobby.queue, id)
	lobby.since[id] = now or 0
	local paired = Lobby.pair(lobby, now)
	if paired then
		return paired, nil
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
	if lobby.held[host] then
		return nil, "CodeBusy" -- a player on another server is joining it (D-083)
	end
	local pair = { host, id }
	local options = lobby.options[code]
	start(lobby, pair)
	return { kind = "Match", players = pair, events = options and options.events }, nil
end

-- Starts a practice match against the bot at `difficulty` (absent or unknown:
-- Easy, D-057, D-087). With `tutorial` it is the tutorial (D-075): the first one
-- and a replay both play the Easy bot (D-080: the short tutorial is tuned
-- against it; D-075 kept the level picked for the first one).
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
	local level: Bot.Difficulty = if tutorial ~= nil then "Easy" else Bot.difficulty(difficulty)
	return {
		kind = "Practice",
		players = { id },
		difficulty = level,
		tutorial = if tutorial ~= nil then true else nil,
	},
		nil
end

-- Starts a run of day `day`'s Daily Race against the bot at `level` (D-082:
-- Config.DAILY_BOT_LEVEL). A Daily Race is never the tutorial.
function Lobby.daily(lobby: Lobby, id: string, day: number, level: string?): (Outcome?, string?)
	local reason = check(lobby, id)
	if reason then
		return nil, reason
	end
	start(lobby, { id })
	return { kind = "Practice", players = { id }, difficulty = Bot.difficulty(level), daily = day }, nil
end

-- Server time from which a queued player may play the bot while waiting, or
-- nil if they are not waiting in the queue (D-083).
function Lobby.botAt(lobby: Lobby, id: string): number?
	if lobby.playing[id] or table.find(lobby.queue, id) == nil then
		return nil
	end
	return (lobby.since[id] or 0) + lobby.botAfter
end

-- A bot game while waiting (D-083): a practice match against `difficulty`,
-- unrated and never the tutorial, while the player keeps their place in line.
function Lobby.waitBot(lobby: Lobby, id: string, now: number, difficulty: string?): (Outcome?, string?)
	if lobby.playing[id] then
		return nil, "InMatch"
	end
	if lobby.offers[id] or lobby.held[id] then
		return nil, Reason.Matching
	end
	local at = Lobby.botAt(lobby, id)
	if at == nil then
		return nil, Reason.NotQueued
	end
	if now < at then
		return nil, Reason.TooSoon
	end
	if lobby.active >= lobby.capacity then
		return nil, "ServerFull"
	end
	lobby.active += 1
	lobby.playing[id] = true
	lobby.botWait[id] = true
	return { kind = "Practice", players = { id }, difficulty = Bot.difficulty(difficulty), waiting = true },
		nil
end

-- The offer `id` must answer (they are in a bot game and have not accepted), or nil.
function Lobby.pending(lobby: Lobby, id: string): Offer?
	local offer = lobby.offers[id]
	if offer and offer.busy[id] and not offer.accepted[id] then
		return offer
	end
	return nil
end

-- Player `id` answers their offer (D-083). The caller ends their bot game
-- before an accept (Lobby.ended), so the slot it held is free again.
-- Accept: once every player in a bot game has accepted, the match starts
-- (kind "Match"); until then nil. Decline: they keep playing their bot game
-- out of the line, and the others go back to the front ("Declined", with
-- those players). Nil and a reason if there is nothing to answer.
function Lobby.answer(lobby: Lobby, id: string, accept: boolean): (Outcome?, string?)
	local offer = Lobby.pending(lobby, id)
	if offer == nil then
		return nil, Reason.NoOffer
	end
	if not accept then
		local others = {}
		for _, other in offer.players do
			if other ~= id then
				table.insert(others, other)
			end
		end
		dropOffer(lobby, id)
		local at = table.find(lobby.queue, id)
		if at then
			table.remove(lobby.queue, at)
		end
		lobby.since[id] = nil
		lobby.botWait[id] = nil
		return { kind = "Declined", players = others }, nil
	end
	offer.accepted[id] = true
	for other in offer.busy do
		if not offer.accepted[other] or lobby.playing[other] then
			return nil, nil
		end
	end
	if offer.remote then
		-- The match is on another server's side: hold them while it is set up.
		lobby.offers[id] = nil
		lobby.held[id] = true
		return { kind = "Remote", players = { id } }, nil
	end
	if lobby.active >= lobby.capacity then
		-- The bot games just ended, so this is rare: back in line, first.
		for _, other in offer.players do
			lobby.offers[other] = nil
			requeue(lobby, other)
		end
		return nil, "ServerFull"
	end
	local pair = table.clone(offer.players)
	start(lobby, pair)
	return { kind = "Match", players = pair }, nil
end

-- Offers whose answer is overdue at `now`: every player in a bot game who has
-- not accepted declines (they keep playing, out of the line). Returns the
-- outcomes, one per decline (`remote`: the offer came from another server).
function Lobby.expire(lobby: Lobby, now: number): { { id: string, outcome: Outcome, remote: boolean } }
	local due: { Offer } = {}
	for _, offer in lobby.offers do
		if now > offer.untilAt and table.find(due, offer) == nil then
			table.insert(due, offer)
		end
	end
	local out = {}
	for _, offer in due do
		for _, id in offer.players do
			if Lobby.pending(lobby, id) == offer then
				local outcome = Lobby.answer(lobby, id, false)
				if outcome then
					table.insert(out, { id = id, outcome = outcome, remote = offer.remote == true })
				end
			end
		end
	end
	return out
end

-- A player on another server was paired with `id`, who is in a bot game
-- while waiting (D-083): they answer like a local offer (Lobby.answer, which
-- returns kind "Remote" once they accept), by `untilAt`. False if `id` is not
-- in a bot game while waiting in line here.
function Lobby.offerRemote(lobby: Lobby, id: string, untilAt: number): boolean
	if not lobby.botWait[id] or lobby.offers[id] or lobby.held[id] then
		return false
	end
	local at = table.find(lobby.queue, id)
	if at == nil then
		return false
	end
	table.remove(lobby.queue, at)
	lobby.offers[id] = {
		players = { id },
		busy = { [id] = true },
		accepted = {},
		untilAt = untilAt,
		remote = true,
	}
	return true
end

-- The other server gave up on a remote offer before `id` answered: no
-- question any more, and their place in line back (D-083).
function Lobby.withdraw(lobby: Lobby, id: string): boolean
	local offer = lobby.offers[id]
	if offer == nil or not offer.remote then
		return false
	end
	lobby.offers[id] = nil
	requeue(lobby, id)
	return true
end

-- Takes `id` out of the local line while they pair with a player on another
-- server, or travel to a match server (D-083). They keep their place.
function Lobby.hold(lobby: Lobby, id: string)
	local at = table.find(lobby.queue, id)
	if at then
		table.remove(lobby.queue, at)
	end
	lobby.held[id] = true
end

-- The pairing fell through: a held player who was in line goes back to their
-- place; a held host is simply free again.
function Lobby.unhold(lobby: Lobby, id: string)
	if not lobby.held[id] then
		return
	end
	lobby.held[id] = nil
	if lobby.since[id] ~= nil and not lobby.playing[id] then
		requeue(lobby, id)
	end
end

-- A match between `ids` decided elsewhere: a rematch, or the match a match
-- server was made for (D-083). Nil and a reason if any of them is busy or the
-- server is full.
function Lobby.direct(lobby: Lobby, ids: { string }, options: Options?): (Outcome?, string?)
	for _, id in ids do
		if lobby.playing[id] then
			return nil, "InMatch"
		end
	end
	if lobby.active >= lobby.capacity then
		return nil, "ServerFull"
	end
	start(lobby, ids)
	return {
		kind = "Match",
		players = table.clone(ids),
		events = if options and options.events == false then false else nil,
	},
		nil
end

-- A match is over (or abandoned): its players are free again. A player whose
-- bot game while waiting ends is still in line (D-083).
function Lobby.ended(lobby: Lobby, ids: { string })
	lobby.active = math.max(0, lobby.active - 1)
	for _, id in ids do
		lobby.playing[id] = nil
		lobby.botWait[id] = nil
	end
end

function Lobby.state(lobby: Lobby, id: string): (PlayerState, string?)
	if lobby.playing[id] then
		return "InMatch", nil
	elseif lobby.held[id] or lobby.offers[id] then
		return "Found", nil
	elseif lobby.hosting[id] then
		return "Hosting", lobby.hosting[id]
	elseif table.find(lobby.queue, id) then
		return "Queued", nil
	end
	return "Idle", nil
end

return table.freeze(Lobby)
