--!strict
-- Matching across servers (docs/DESIGN.md D-080). Pure: server/CrossServer does
-- the MemoryStore, TeleportService and timing, and uses these helpers for every
-- value it reads or writes, so the rules are tested without an engine.
--
-- A waiting player is a **ticket**: one per queued player in the sorted map
-- QUEUE_MAP (key = their UserId, sort key = when they joined the queue) and
-- one per hosted private code in the hash map CODE_MAP (key = the code). The
-- server the player is on owns the ticket: it writes it, refreshes it every
-- REFRESH seconds (it expires after TICKET_TTL, so a crashed server's tickets
-- vanish) and removes it when they stop waiting.
--
-- Another server pairs with a ticket in four steps, each one UpdateAsync on the
-- ticket (a transform that returns nil changes nothing, so two servers can never
-- both win a step):
--   1. Claim     Open -> Claimed (by, byJob, match, until). The claimer first
--                claims its own player's ticket the same way, so no third
--                server can take them meanwhile. Only the newer player's server
--                claims (the oldest waiting player never claims), so two
--                servers never claim each other's players at once.
--   2. Answer    the owner: Claimed -> Accepted, or Declined (the player left,
--                or turned the match down from a bot game, D-080).
--   3. Ready     the claimer: Accepted -> Ready (access = the reserved server's
--                access code), after writing the match spec under the reserved
--                server's PrivateServerId in SPEC_MAP. Then it teleports its player.
--   4. The owner sees Ready, teleports its player and removes the ticket.
-- A claim that is not answered by `until` lapses: either side reopens it
-- (Reopen: back to Open, the player keeps their place in line).
--
-- The match server reads its spec from SPEC_MAP, never from the teleport data:
-- Player:GetJoinData() says teleport data passes through the client.

local Matchmaking = {}

-- MemoryStore structures (names are global within the game).
Matchmaking.QUEUE_MAP = "Queue_v1" -- sorted map: UserId -> ticket, sort key = queued at (unix)
Matchmaking.CODE_MAP = "Codes_v1" -- hash map: code -> ticket
Matchmaking.SPEC_MAP = "MatchServers_v1" -- hash map: PrivateServerId -> match spec
Matchmaking.ONLINE_MAP = "Online_v1" -- sorted map: JobId -> { n, at }
Matchmaking.ONLINE_TOTAL = "OnlineTotal_v1" -- hash map: "Total" -> { n, at }

-- Request budget and timing (server plumbing, not gameplay: like Net/Leaderboard).
Matchmaking.POLL = 3 -- s between a server's scans while one of its players waits
Matchmaking.SCAN = 10 -- oldest tickets one scan reads (GetRangeAsync costs one unit per item)
Matchmaking.TICKET_TTL = 90 -- s a ticket lives unless its owner refreshes it
Matchmaking.REFRESH = 30 -- s between an owner's refreshes of a waiting ticket
Matchmaking.STALE = 45 -- s without a refresh after which nobody claims a ticket
Matchmaking.CLAIM_EXTRA = 10 -- s a claim lives beyond the accept window (Config.QUEUE_ACCEPT_SECONDS)
Matchmaking.SPEC_TTL = 600 -- s a match spec lives (the match server reads it once)
Matchmaking.ARRIVAL_TIMEOUT = 60 -- s a match server waits for both players before sending them back
Matchmaking.ONLINE_PERIOD = 30 -- s between a server's player-count reports
Matchmaking.ONLINE_TTL = 90 -- s a server's count lives (a crashed server drops out)
Matchmaking.ONLINE_PAGE = 200 -- GetRangeAsync's largest page
Matchmaking.ATTEMPTS = 3 -- tries per MemoryStore request, waiting BACKOFF * 2^n between them
Matchmaking.BACKOFF = 0.5 -- s
Matchmaking.TELEPORT_ATTEMPTS = 3 -- tries per teleport (TeleportAsync errors, TeleportInitFailed)
Matchmaking.LAUNCH_MAX = 200 -- ExperienceInviteOptions.LaunchData's documented limit, characters
Matchmaking.LAUNCH_PREFIX = "landslide:code=" -- an invite's launch data: prefix .. the host's code

export type Kind = "Queue" | "Code"
export type TicketState = "Open" | "Claimed" | "Accepted" | "Declined" | "Ready"

export type Ticket = {
	v: number, -- format version (1)
	kind: Kind,
	id: string, -- the waiting player (Queue) or the host (Code)
	job: string, -- the JobId of the server they are on
	at: number, -- unix time they started waiting (the queue's order)
	touched: number, -- unix time of the owner's last refresh
	busy: boolean?, -- Queue: playing a bot game while they wait (D-080)
	events: boolean?, -- Code: false = the host turned events off (D-027)
	state: TicketState,
	by: string?, -- Claimed and after: the other player
	byJob: string?, -- their server
	match: string?, -- a key for this pairing, unique across servers
	untilAt: number?, -- unix time a Claimed or Accepted ticket lapses
	access: string?, -- Ready: the reserved server's access code
}

-- What a match server starts from (SPEC_MAP, key = its PrivateServerId).
export type Spec = {
	v: number,
	match: string, -- the pairing's key
	seed: number,
	players: { string }, -- UserIds, seat order (the waiting player or host first)
	mode: Kind, -- Queue or Code (the rated rules are the same, D-077)
	events: boolean?, -- false: no event deck (a host's choice)
	at: number, -- unix time it was written
}

local CODE_PATTERN = "^[A-Z2-9][A-Z2-9][A-Z2-9][A-Z2-9][A-Z2-9]$"
local MAX_TEXT = 128 -- longest string field a ticket or spec may carry (MemoryStore keys are at most 128)
local STATES: { [string]: boolean } =
	{ Open = true, Claimed = true, Accepted = true, Declined = true, Ready = true }

local function isText(value: any): boolean
	return type(value) == "string" and #value > 0 and #value <= MAX_TEXT
end

local function isTime(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isUserId(value: any): boolean
	return type(value) == "string" and #value <= 20 and string.match(value, "^%d+$") ~= nil
end

function Matchmaking.isCode(value: any): boolean
	return type(value) == "string" and string.match(value, CODE_PATTERN) ~= nil
end

-- True if `value` (read back from a MemoryStore) is a ticket this game wrote.
function Matchmaking.isTicket(value: any): boolean
	if type(value) ~= "table" or value.v ~= 1 then
		return false
	end
	if (value.kind ~= "Queue" and value.kind ~= "Code") or not STATES[value.state] then
		return false
	end
	if
		not isUserId(value.id)
		or not isText(value.job)
		or not isTime(value.at)
		or not isTime(value.touched)
	then
		return false
	end
	if value.state ~= "Open" then
		if not isUserId(value.by) or not isText(value.byJob) or not isText(value.match) then
			return false
		end
		if value.state ~= "Ready" and not isTime(value.untilAt) then
			return false
		end
	end
	if value.state == "Ready" and not isText(value.access) then
		return false
	end
	return true
end

local function copy(ticket: Ticket): Ticket
	return table.clone(ticket)
end

local function opened(ticket: Ticket): Ticket
	local out = copy(ticket)
	out.state = "Open"
	out.by = nil
	out.byJob = nil
	out.match = nil
	out.untilAt = nil
	out.access = nil
	return out
end

-- A new open ticket.
function Matchmaking.open(
	kind: Kind,
	id: string,
	job: string,
	at: number,
	now: number,
	options: { busy: boolean?, events: boolean? }?
): Ticket
	return {
		v = 1,
		kind = kind,
		id = id,
		job = job,
		at = at,
		touched = now,
		busy = if options and options.busy then true else nil,
		events = if options and options.events == false then false else nil,
		state = "Open",
	}
end

-- The owner's refresh (UpdateAsync transform): keeps the ticket's state and
-- place in line, notes the time and whether they are in a bot game. Nil (no
-- change) for a ticket another server now owns or that is not this game's.
function Matchmaking.refresh(old: any, id: string, job: string, now: number, busy: boolean?): Ticket?
	if not Matchmaking.isTicket(old) or old.id ~= id or old.job ~= job then
		return nil
	end
	local out = copy(old)
	out.touched = now
	out.busy = if busy then true else nil
	return out
end

-- True if nobody should pair with this ticket: not refreshed for STALE seconds.
function Matchmaking.stale(ticket: Ticket, now: number): boolean
	return now - ticket.touched > Matchmaking.STALE
end

-- Step 1 (UpdateAsync transform): claim an open, fresh ticket for player `by`
-- on server `byJob`. `untilAt` is when the claim lapses. Nil if it is not open,
-- stale, or `by`'s own.
function Matchmaking.claim(
	old: any,
	by: string,
	byJob: string,
	match: string,
	now: number,
	untilAt: number
): Ticket?
	if not Matchmaking.isTicket(old) or old.state ~= "Open" or Matchmaking.stale(old, now) then
		return nil
	end
	if old.id == by and old.job ~= byJob then
		return nil -- the same player on another server: an old ticket
	end
	local out = copy(old)
	out.state = "Claimed"
	out.by = by
	out.byJob = byJob
	out.match = match
	out.untilAt = untilAt
	return out
end

-- Step 2 (the owner's UpdateAsync transform): accept or decline claim `match`.
function Matchmaking.answer(old: any, match: string, accept: boolean): Ticket?
	if not Matchmaking.isTicket(old) or old.state ~= "Claimed" or old.match ~= match then
		return nil
	end
	local out = copy(old)
	out.state = if accept then "Accepted" else "Declined"
	return out
end

-- Step 3 (the claimer's UpdateAsync transform): the reserved server is ready.
function Matchmaking.ready(old: any, match: string, access: string): Ticket?
	if
		not Matchmaking.isTicket(old)
		or old.state ~= "Accepted"
		or old.match ~= match
		or not isText(access)
	then
		return nil
	end
	local out = copy(old)
	out.state = "Ready"
	out.access = access
	out.untilAt = nil
	return out
end

-- Undo claim `match` (UpdateAsync transform): back to Open with the same place
-- in line. Nil if the ticket moved on to another claim or is Ready.
function Matchmaking.reopen(old: any, match: string): Ticket?
	if not Matchmaking.isTicket(old) or old.state == "Open" or old.state == "Ready" or old.match ~= match then
		return nil
	end
	return opened(old)
end

-- A claim nobody finished in time (UpdateAsync transform, either side): back
-- to Open. Nil while the claim is still live.
function Matchmaking.lapse(old: any, now: number): Ticket?
	if not Matchmaking.isTicket(old) or (old.state ~= "Claimed" and old.state ~= "Accepted") then
		return nil
	end
	if now <= (old.untilAt :: number) then
		return nil
	end
	return opened(old)
end

-- Who a claimer should pair its player `me` (queued at `at`, on `job`) with:
-- the key of the oldest open, fresh ticket of another player that joined the
-- queue no later than they did (ties: the smaller UserId is older). `rows` are
-- GetRangeAsync items ({ key, value }), oldest first. Nil if there is none.
function Matchmaking.pick(rows: { any }, me: string, at: number, job: string, now: number): string?
	local best: string? = nil
	local bestAt = math.huge
	local bestId = math.huge
	for _, row in rows do
		local ticket = if type(row) == "table" then row.value else nil
		if not Matchmaking.isTicket(ticket) or ticket.kind ~= "Queue" then
			continue
		end
		if ticket.id == me or ticket.state ~= "Open" or Matchmaking.stale(ticket, now) then
			continue
		end
		if ticket.job == job then
			continue -- a player on this server: the local queue pairs them
		end
		local id = tonumber(ticket.id) :: number
		local older = ticket.at < at or (ticket.at == at and id < (tonumber(me) or math.huge))
		if not older then
			continue
		end
		if ticket.at < bestAt or (ticket.at == bestAt and id < bestId) then
			best, bestAt, bestId = ticket.id, ticket.at, id
		end
	end
	return best
end

-- A match key unique across servers.
function Matchmaking.matchKey(job: string, count: number): string
	return `{string.sub(job, 1, 40)}#{count}`
end

function Matchmaking.spec(
	match: string,
	seed: number,
	players: { string },
	mode: Kind,
	events: boolean?,
	at: number
): Spec
	return {
		v = 1,
		match = match,
		seed = seed,
		players = table.clone(players),
		mode = mode,
		events = if events == false then false else nil,
		at = at,
	}
end

function Matchmaking.isSpec(value: any): boolean
	if type(value) ~= "table" or value.v ~= 1 or not isText(value.match) then
		return false
	end
	if type(value.seed) ~= "number" or value.seed ~= math.floor(value.seed) or not isTime(value.at) then
		return false
	end
	if value.mode ~= "Queue" and value.mode ~= "Code" then
		return false
	end
	if value.events ~= nil and value.events ~= false then
		return false
	end
	local players = value.players
	if type(players) ~= "table" or #players ~= 2 then
		return false
	end
	for _, id in players do
		if not isUserId(id) then
			return false
		end
	end
	return players[1] ~= players[2]
end

-- An invite's launch data: the host's private code (D-080). At most LAUNCH_MAX
-- characters (ExperienceInviteOptions.LaunchData).
function Matchmaking.launchData(code: string): string
	return Matchmaking.LAUNCH_PREFIX .. code
end

-- The code in a joining player's Player:GetJoinData().LaunchData, or nil.
function Matchmaking.codeFromLaunch(data: any): string?
	if type(data) ~= "string" or #data > Matchmaking.LAUNCH_MAX then
		return nil
	end
	local prefix = Matchmaking.LAUNCH_PREFIX
	if string.sub(data, 1, #prefix) ~= prefix then
		return nil
	end
	local code = string.sub(data, #prefix + 1)
	return if Matchmaking.isCode(code) then code else nil
end

-- Teleport data (D-080). Only presentation rides on it (it passes through the
-- client): to a match server the pairing's key (for the logs), back to the
-- lobby a notice and whether to queue again.
export type Travel = {
	landslide: number, -- 1
	match: string?,
	notice: string?, -- one of RETURN_NOTICES
	requeue: boolean?,
}

Matchmaking.RETURN_NOTICES = table.freeze({
	OpponentNoShow = true, -- the opponent never reached the match server
	MatchServerFailed = true, -- the match server could not read its match
})

-- What a lobby server may take from a returning player's teleport data.
function Matchmaking.readTravel(data: any): (string?, boolean)
	if type(data) ~= "table" or data.landslide ~= 1 then
		return nil, false
	end
	local notice = if type(data.notice) == "string" and Matchmaking.RETURN_NOTICES[data.notice]
		then data.notice
		else nil
	return notice, data.requeue == true
end

return table.freeze(Matchmaking)
