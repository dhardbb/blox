--!strict
-- Matching across servers (docs/DESIGN.md D-080; the ticket rules are in
-- Net/Matchmaking). The local lobby (Net/Lobby) always pairs players on this
-- server first and at once; this module puts every player still waiting into
-- the game-wide queue, every hosted private code into the game-wide code
-- list, pairs this server's waiting players with older players on other
-- servers, and sends both to a fresh reserved server (a match server) that
-- starts their match from the spec written for it.
--
-- One loop runs every Matchmaking.POLL seconds while anything is waiting:
--   * each ticket this server owns is refreshed with one UpdateAsync that also
--     reads it back (Claimed by another server: accept, or ask the player if
--     they are in a bot game; Ready: teleport the player; a lapsed claim: back
--     to Open);
--   * each pairing this server started is checked with one GetAsync (Accepted:
--     reserve a server, write the spec, mark the ticket Ready, teleport our
--     player; Declined or lapsed: our player goes back to their place in line);
--   * one scan of the oldest Matchmaking.SCAN queue tickets, if a player here
--     waits with nobody yet, to claim the oldest open ticket of an older player.
--
-- MatchService owns the players: it tells this module who is waiting
-- (queued, hosted, forget) and gets told what to do through the hooks.
-- Everything here is off where Memory.available() is false (Studio, an
-- unpublished place): those servers match in-server only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Sim.Config)
local Matchmaking = require(ReplicatedStorage.Shared.Net.Matchmaking)
local Memory = require(script.Parent.Memory)
local Teleport = require(script.Parent.Teleport)

local CrossServer = {}

local TRAVEL_TIMEOUT = 30 -- s after a teleport began before a player still here counts as not moved
local SPEC_TRIES = 5 -- tries to read a match server's spec
local SPEC_WAIT = 2 -- s between them

export type Hooks = {
	-- True while `id` waits in this server's queue, free to be paired (not in an offer or held).
	isWaiting: (id: string) -> boolean,
	-- True while `id` hosts `code` here.
	isHosting: (id: string, code: string) -> boolean,
	-- `id` was claimed while in a bot game: ask them (Lobby.offerRemote). False if they cannot be asked.
	ask: (id: string, untilAt: number) -> boolean,
	-- `id` is being paired or is about to travel: out of the local line ("Found").
	hold: (id: string, phase: string, untilAt: number?) -> (),
	-- The pairing fell through: `id` goes back where they were, with an optional notice.
	unhold: (id: string, notice: string?) -> (),
	-- A host's code collided with another server's: give them a new code.
	recode: (id: string) -> (),
}

type Owned = {
	kind: Matchmaking.Kind,
	id: string,
	key: string, -- the ticket's key: the UserId (Queue) or the code (Code)
	at: number, -- unix time they started waiting
	busy: boolean,
	events: boolean?,
	published: boolean,
	match: string?, -- the remote claim this ticket is answering
	answered: boolean?, -- we answered `match` (Accepted)
	traveling: boolean?,
}

type Claim = {
	match: string,
	kind: Matchmaking.Kind,
	me: string, -- our player
	key: string, -- the other player's ticket key
	other: string, -- the other player (UserId)
	events: boolean?, -- Code: the host's choice
	untilAt: number, -- unix
	busy: boolean, -- the other player is in a bot game
}

local hooks: Hooks? = nil
local owned: { [string]: Owned } = {} -- "Queue:<id>" / "Code:<code>" -> ticket
local claims: { [string]: Claim } = {} -- match key -> a pairing this server started
local traveling: { [string]: boolean } = {} -- ids on their way out
local claimCount = 0
local running = false
local random = Random.new()

local function job(): string
	return if game.JobId == "" then "studio" else game.JobId
end

local function ownedKey(kind: Matchmaking.Kind, key: string): string
	return `{kind}:{key}`
end

local function structure(kind: Matchmaking.Kind): any?
	if kind == "Queue" then
		return Memory.sorted(Matchmaking.QUEUE_MAP)
	end
	return Memory.hash(Matchmaking.CODE_MAP)
end

local function claimWindow(): number
	return Config.defaults.QUEUE_ACCEPT_SECONDS + Matchmaking.CLAIM_EXTRA
end

-- One UpdateAsync on a ticket with a Matchmaking transform. Returns (ok, the
-- ticket now if the transform changed it, else nil, the ticket it last saw).
local function update(kind: Matchmaking.Kind, key: string, transform: (any) -> any): (boolean, any, any)
	local map = structure(kind)
	if map == nil then
		return false, nil, nil
	end
	local seen: any = nil
	local ok, result = Memory.call(`{kind} update`, function(): any
		if kind == "Queue" then
			return map:UpdateAsync(key, function(old: any, sortKey: any): (any, any)
				seen = old
				local new = transform(old)
				if new == nil then
					return nil, nil
				end
				return new, sortKey or (new :: any).at
			end, Matchmaking.TICKET_TTL)
		end
		return map:UpdateAsync(key, function(old: any): any
			seen = old
			return transform(old)
		end, Matchmaking.TICKET_TTL)
	end)
	return ok, if ok then result else nil, seen
end

local function read(kind: Matchmaking.Kind, key: string): (boolean, any)
	local map = structure(kind)
	if map == nil then
		return false, nil
	end
	return Memory.call(`{kind} read`, function(): any
		return (map:GetAsync(key))
	end)
end

local function remove(kind: Matchmaking.Kind, key: string)
	local map = structure(kind)
	if map then
		Memory.call(`{kind} remove`, function(): any
			map:RemoveAsync(key)
			return true
		end)
	end
end

local function call(name: string, ...: any): any
	local h = hooks
	if h == nil then
		return nil
	end
	local fn = (h :: any)[name]
	local ok, result = pcall(fn, ...)
	if not ok then
		warn(`[270] cross-server hook {name}: {result}`)
		return nil
	end
	return result
end

-- ---------------------------------------------------------------- travel

-- Sends our player `id` to the match server `access`. A teleport that never
-- happens puts them back (MatchService's unhold, with a notice).
local function travel(id: string, access: string, match: string)
	local userId = tonumber(id)
	local player = if userId then Players:GetPlayerByUserId(userId) else nil
	if player == nil then
		return
	end
	traveling[id] = true
	call("hold", id, "Joining", nil)
	local function failed(_: Player)
		if traveling[id] then
			traveling[id] = nil
			call("unhold", id, "TeleportFailed")
		end
	end
	task.delay(TRAVEL_TIMEOUT, function()
		if traveling[id] and player.Parent ~= nil then
			warn(`[270] player {id} is still here {TRAVEL_TIMEOUT} s after their teleport`)
			failed(player)
		end
	end)
	print(`[270] player {id} -> match server ({match})`)
	Teleport.send(player, access, { landslide = 1, match = match }, failed)
end

-- ---------------------------------------------------------------- tickets we own

local function publish(entry: Owned): boolean
	local now = os.time()
	local ticket = Matchmaking.open(entry.kind, entry.id, job(), entry.at, now, {
		busy = entry.busy,
		events = entry.events,
	})
	if entry.kind == "Queue" then
		local map = structure("Queue")
		if map == nil then
			return false
		end
		local ok = Memory.call("Queue publish", function(): any
			return map:SetAsync(entry.key, ticket, Matchmaking.TICKET_TTL, entry.at)
		end)
		return ok
	end
	-- A code: only if nobody else's live ticket holds it.
	local collided = false
	local ok = update("Code", entry.key, function(old: any): any
		collided = false
		if Matchmaking.isTicket(old) and old.job ~= job() and not Matchmaking.stale(old, now) then
			collided = true
			return nil
		end
		return ticket
	end)
	if ok and collided then
		owned[ownedKey("Code", entry.key)] = nil
		call("recode", entry.id)
		return false
	end
	return ok
end

local function stillHere(entry: Owned): boolean
	if entry.kind == "Queue" then
		return call("isWaiting", entry.id) == true
	end
	return call("isHosting", entry.id, entry.key) == true
end

-- Reads one owned ticket back (refreshing it) and acts on its state.
local function observe(entry: Owned, slot: string)
	local now = os.time()
	local ok, _, seen = update(entry.kind, entry.key, function(old: any): any
		return Matchmaking.refresh(old, entry.id, job(), now, entry.busy)
	end)
	if not ok then
		return
	end
	if not Matchmaking.isTicket(seen) or seen.id ~= entry.id or seen.job ~= job() then
		-- Expired or overwritten: write it again (a Ready one we already acted on is gone for good).
		if not entry.traveling then
			entry.published = publish(entry)
		end
		return
	end
	local ticket: Matchmaking.Ticket = seen
	local match = ticket.match
	if ticket.state == "Open" then
		if entry.match ~= nil and not entry.traveling then
			-- A claim we were answering lapsed and was reopened: back in line.
			entry.match = nil
			entry.answered = nil
			call("unhold", entry.id, nil)
		end
		return
	end
	if match ~= nil and claims[match] ~= nil then
		return -- our own lock while we pair this player with someone else
	end
	if (ticket.state == "Claimed" or ticket.state == "Accepted") and now > (ticket.untilAt or 0) then
		update(entry.kind, entry.key, function(old: any): any
			return Matchmaking.lapse(old, now)
		end)
		if entry.match ~= nil then
			entry.match = nil
			entry.answered = nil
			call("unhold", entry.id, nil)
		end
		return
	end
	if ticket.state == "Claimed" and match ~= nil and entry.match ~= match then
		if entry.match ~= nil then
			-- The pairing we answered fell through and a new one came before we
			-- saw the ticket open again: back in line first, then answer this one.
			entry.match = nil
			entry.answered = nil
			call("unhold", entry.id, nil)
		end
		entry.match = match
		entry.answered = nil
		if not stillHere(entry) then
			update(entry.kind, entry.key, function(old: any): any
				return Matchmaking.answer(old, match, false)
			end)
			owned[slot] = nil
			remove(entry.kind, entry.key)
			return
		end
		if entry.kind == "Queue" and entry.busy then
			-- In a bot game: they answer "Opponent found! Leave this bot game?".
			local untilAt = ticket.untilAt or (now + Config.defaults.QUEUE_ACCEPT_SECONDS)
			local serverUntil = workspace:GetServerTimeNow()
				+ math.max(1, math.min(Config.defaults.QUEUE_ACCEPT_SECONDS, untilAt - now - 2))
			if call("ask", entry.id, serverUntil) ~= true then
				update(entry.kind, entry.key, function(old: any): any
					return Matchmaking.answer(old, match, false)
				end)
			end
			return
		end
		local answered = update(entry.kind, entry.key, function(old: any): any
			return Matchmaking.answer(old, match, true)
		end)
		if answered then
			entry.answered = true
			print(`[270] player {entry.id} accepts {ticket.by} from another server ({match})`)
			call("hold", entry.id, "Joining", nil)
		end
		return
	end
	if ticket.state == "Ready" and match ~= nil and entry.match == match and entry.answered then
		entry.traveling = true
		owned[slot] = nil
		remove(entry.kind, entry.key)
		travel(entry.id, ticket.access :: string, match)
	end
end

-- ---------------------------------------------------------------- pairings we start

local function dropClaim(claim: Claim, notice: string?)
	print(
		`[270] pairing {claim.match} of {claim.me} with {claim.other} fell through ({notice or "no answer"})`
	)
	claims[claim.match] = nil
	if claim.kind == "Queue" then
		local slot = owned[ownedKey("Queue", claim.me)]
		update("Queue", claim.me, function(old: any): any
			return Matchmaking.reopen(old, claim.match)
		end)
		if slot then
			slot.match = nil
		end
	end
	call("unhold", claim.me, notice)
end

local function finish(claim: Claim)
	local access, privateId = Teleport.reserve()
	if access == nil or privateId == nil then
		update(claim.kind, claim.key, function(old: any): any
			return Matchmaking.reopen(old, claim.match)
		end)
		dropClaim(claim, "TeleportFailed")
		return
	end
	-- The waiting player (or the host) takes seat 1.
	local players = { claim.other, claim.me }
	local spec = Matchmaking.spec(
		claim.match,
		random:NextInteger(1, 2 ^ 31 - 1),
		players,
		claim.kind,
		claim.events,
		os.time()
	)
	local specs = Memory.hash(Matchmaking.SPEC_MAP)
	local written = specs ~= nil
		and Memory.call("spec write", function(): any
			return (specs :: any):SetAsync(privateId, spec, Matchmaking.SPEC_TTL)
		end)
	if not written then
		update(claim.kind, claim.key, function(old: any): any
			return Matchmaking.reopen(old, claim.match)
		end)
		dropClaim(claim, "TeleportFailed")
		return
	end
	if claims[claim.match] ~= claim then
		-- Our player cancelled while the server was reserved: let the other one go.
		update(claim.kind, claim.key, function(old: any): any
			return Matchmaking.reopen(old, claim.match)
		end)
		return
	end
	local ok, ready = update(claim.kind, claim.key, function(old: any): any
		return Matchmaking.ready(old, claim.match, access)
	end)
	if not ok or ready == nil then
		dropClaim(claim, nil)
		return
	end
	claims[claim.match] = nil
	if claim.kind == "Queue" then
		owned[ownedKey("Queue", claim.me)] = nil
		remove("Queue", claim.me)
	end
	print(`[270] paired {claim.other} with {claim.me} across servers ({claim.match})`)
	travel(claim.me, access, claim.match)
end

local function check(claim: Claim)
	local ok, ticket = read(claim.kind, claim.key)
	if not ok then
		return
	end
	local now = os.time()
	-- Why it fell through, for our player: an opponent who stayed in their bot
	-- game, or a host who stopped hosting.
	local gone = if claim.kind == "Queue" then "OpponentDeclined" else "CodeGone"
	if not Matchmaking.isTicket(ticket) or ticket.match ~= claim.match then
		dropClaim(claim, if claim.kind == "Code" then gone else nil)
		return
	end
	if ticket.state == "Accepted" then
		finish(claim)
	elseif ticket.state == "Declined" then
		update(claim.kind, claim.key, function(old: any): any
			return Matchmaking.reopen(old, claim.match)
		end)
		dropClaim(claim, gone)
	elseif now > claim.untilAt then
		update(claim.kind, claim.key, function(old: any): any
			return Matchmaking.lapse(old, now)
		end)
		dropClaim(claim, gone)
	end
end

-- Claims the oldest open ticket of an older player for each of our free waiting players.
local function scan()
	local candidates: { Owned } = {}
	for _, entry in owned do
		if
			entry.kind == "Queue"
			and entry.published
			and not entry.busy
			and entry.match == nil
			and not entry.traveling
			and call("isWaiting", entry.id) == true
		then
			table.insert(candidates, entry)
		end
	end
	if #candidates == 0 then
		return
	end
	table.sort(candidates, function(a, b)
		return a.at < b.at
	end)
	local map = structure("Queue")
	if map == nil then
		return
	end
	local ok, rows = Memory.call("Queue scan", function(): any
		return map:GetRangeAsync(Enum.SortDirection.Ascending, Matchmaking.SCAN)
	end)
	if not ok or type(rows) ~= "table" then
		return
	end
	local taken: { [string]: boolean } = {}
	for _, me in candidates do
		local now = os.time()
		local free = {}
		for _, row in rows do
			if type(row) == "table" and not taken[tostring(row.key)] then
				table.insert(free, row)
			end
		end
		local target = Matchmaking.pick(free, me.id, me.at, job(), now)
		if target == nil or call("isWaiting", me.id) ~= true then
			continue
		end
		local targetTicket: any = nil
		for _, row in rows do
			if type(row) == "table" and row.key == target then
				targetTicket = row.value
			end
		end
		taken[target] = true
		claimCount += 1
		local match = Matchmaking.matchKey(job(), claimCount)
		local untilAt = now + claimWindow()
		-- Lock our own player first, then claim theirs.
		local locked, mine = update("Queue", me.id, function(old: any): any
			return Matchmaking.claim(old, target, targetTicket.job, match, now, untilAt)
		end)
		if not locked or mine == nil then
			continue
		end
		local claimed, theirs = update("Queue", target, function(old: any): any
			return Matchmaking.claim(old, me.id, job(), match, now, untilAt)
		end)
		if not claimed or theirs == nil then
			update("Queue", me.id, function(old: any): any
				return Matchmaking.reopen(old, match)
			end)
			continue
		end
		me.match = match
		claims[match] = {
			match = match,
			kind = "Queue",
			me = me.id,
			key = target,
			other = target,
			untilAt = untilAt,
			busy = (theirs :: any).busy == true,
		}
		local serverUntil = workspace:GetServerTimeNow() + Config.defaults.QUEUE_ACCEPT_SECONDS
		print(`[270] player {me.id} claims {target} on another server ({match})`)
		call("hold", me.id, if (theirs :: any).busy then "Waiting" else "Joining", serverUntil)
	end
end

-- ---------------------------------------------------------------- the loop

local function busyWork(): boolean
	return next(owned) ~= nil or next(claims) ~= nil
end

-- One pass of the loop. Yields.
function CrossServer.step()
	for slot, entry in table.clone(owned) do
		if owned[slot] ~= entry then
			continue
		end
		if not entry.published then
			entry.published = publish(entry)
		else
			observe(entry, slot)
		end
	end
	for match, claim in table.clone(claims) do
		if claims[match] == claim then
			check(claim)
		end
	end
	scan()
end

local function loop()
	while running do
		if busyWork() then
			local ok, err = pcall(function(): string?
				CrossServer.step()
				return nil
			end)
			if not ok then
				warn(`[270] cross-server step: {err}`)
			end
		end
		task.wait(Matchmaking.POLL)
	end
end

-- ---------------------------------------------------------------- MatchService's side

function CrossServer.enabled(): boolean
	return Memory.available()
end

function CrossServer.start(h: Hooks)
	hooks = h
	if running or not CrossServer.enabled() then
		return
	end
	running = true
	task.spawn(loop)
	pcall(function()
		game:BindToClose(function()
			for _, entry in table.clone(owned) do
				remove(entry.kind, entry.key)
			end
		end)
	end)
end

-- `id` waits in this server's queue since unix time `at` (busy: in a bot
-- game). Called again when they start or end a bot game.
function CrossServer.queued(id: string, at: number, busy: boolean)
	if not running then
		return
	end
	local slot = ownedKey("Queue", id)
	local entry = owned[slot]
	if entry then
		entry.busy = busy
		return
	end
	owned[slot] = {
		kind = "Queue",
		id = id,
		key = id,
		at = at,
		busy = busy,
		published = false,
	}
end

-- `id` hosts private code `code` (events: the host's choice).
function CrossServer.hosted(id: string, code: string, events: boolean?)
	if not running then
		return
	end
	owned[ownedKey("Code", code)] = {
		kind = "Code",
		id = id,
		key = code,
		at = os.time(),
		busy = false,
		events = if events == false then false else nil,
		published = false,
	}
	task.spawn(function()
		local entry = owned[ownedKey("Code", code)]
		if entry and not entry.published then
			entry.published = publish(entry)
		end
	end)
end

-- `id` stopped waiting (left the line, stopped hosting, left the server, or
-- started a match here). Their tickets go, and a pairing they were in is undone.
function CrossServer.forget(id: string)
	if not running then
		return
	end
	traveling[id] = nil
	local gone: { Owned } = {}
	for slot, entry in owned do
		if entry.id == id and not entry.traveling then
			owned[slot] = nil
			table.insert(gone, entry)
		end
	end
	local undone: { Claim } = {}
	for match, claim in claims do
		if claim.me == id then
			claims[match] = nil
			table.insert(undone, claim)
		end
	end
	if #gone == 0 and #undone == 0 then
		return
	end
	task.spawn(function()
		for _, entry in gone do
			remove(entry.kind, entry.key)
		end
		for _, claim in undone do
			update(claim.kind, claim.key, function(old: any): any
				return Matchmaking.reopen(old, claim.match)
			end)
		end
	end)
end

-- A player in a bot game answered a claim from another server (D-080).
function CrossServer.answer(id: string, accept: boolean)
	if not running then
		return
	end
	local slot = ownedKey("Queue", id)
	local entry = owned[slot]
	local match = if entry then entry.match else nil
	if entry == nil or match == nil then
		return
	end
	task.spawn(function()
		local ok, answered = update("Queue", id, function(old: any): any
			return Matchmaking.answer(old, match, accept)
		end)
		if not accept then
			owned[slot] = nil
			remove("Queue", id)
			return
		end
		if ok and answered ~= nil then
			entry.answered = true
			entry.busy = false
			call("hold", id, "Joining", nil)
		else
			entry.match = nil
			call("unhold", id, nil)
		end
	end)
end

-- Joins a private code hosted on another server. Returns a reason code when
-- it cannot (NoSuchCode, OwnCode, CodeBusy), else nil: the player is held
-- while the match server is set up. Yields.
function CrossServer.join(id: string, code: string): string?
	if not running then
		return "NoSuchCode"
	end
	local ok, ticket = read("Code", code)
	if not ok then
		return "Unavailable"
	end
	local now = os.time()
	if not Matchmaking.isTicket(ticket) or ticket.kind ~= "Code" or Matchmaking.stale(ticket, now) then
		return "NoSuchCode"
	end
	if ticket.id == id then
		return "OwnCode"
	end
	if ticket.state ~= "Open" or ticket.job == job() then
		return if ticket.state ~= "Open" then "CodeBusy" else "NoSuchCode"
	end
	claimCount += 1
	local match = Matchmaking.matchKey(job(), claimCount)
	local untilAt = now + claimWindow()
	local claimed, value = update("Code", code, function(old: any): any
		return Matchmaking.claim(old, id, job(), match, now, untilAt)
	end)
	if not claimed then
		return "Unavailable"
	end
	if value == nil then
		return "CodeBusy"
	end
	claims[match] = {
		match = match,
		kind = "Code",
		me = id,
		key = code,
		other = ticket.id,
		events = if ticket.events == false then false else nil,
		untilAt = untilAt,
		busy = false,
	}
	call("hold", id, "Joining", nil)
	print(`[270] player {id} joins code {code} on another server ({match})`)
	return nil
end

-- True while `id` is on their way to a match server.
function CrossServer.traveling(id: string): boolean
	return traveling[id] == true
end

-- ---------------------------------------------------------------- match servers

-- True if this server is a reserved server: a match server (D-080).
function CrossServer.isMatchServer(): boolean
	local ok, result = pcall(function(): boolean
		return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
	end)
	return ok and result == true
end

-- The spec this match server was made for, or nil. Yields (a few tries: it
-- was written just before the teleport).
function CrossServer.loadSpec(): Matchmaking.Spec?
	if not CrossServer.enabled() or not CrossServer.isMatchServer() then
		return nil
	end
	local specs = Memory.hash(Matchmaking.SPEC_MAP)
	if specs == nil then
		return nil
	end
	local key = game.PrivateServerId
	for try = 1, SPEC_TRIES do
		local ok, value = Memory.call("spec read", function(): any
			return specs:GetAsync(key)
		end)
		if ok and Matchmaking.isSpec(value) then
			return value
		end
		if try < SPEC_TRIES then
			task.wait(SPEC_WAIT)
		end
	end
	return nil
end

-- Sends `player` back to a lobby server (a public server of this place), with
-- an optional notice and whether to queue them again there. `failed` runs if
-- the teleport does not happen. Yields.
function CrossServer.toLobby(player: Player, notice: string?, requeue: boolean, failed: (Player) -> ())
	local id = tostring(player.UserId)
	traveling[id] = true
	task.delay(TRAVEL_TIMEOUT, function()
		if traveling[id] and player.Parent ~= nil then
			traveling[id] = nil
			pcall(failed, player)
		end
	end)
	Teleport.send(
		player,
		nil,
		{ landslide = 1, notice = notice, requeue = requeue or nil },
		function(p: Player)
			if traveling[id] then
				traveling[id] = nil
				failed(p)
			end
		end
	)
end

return CrossServer
