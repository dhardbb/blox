--!strict
-- Matchmaking end to end on the fake engine (docs/DESIGN.md D-080): several
-- worlds stand for several servers of one game, sharing memory stores and
-- data stores. Players queue or host on different servers, get paired, are
-- teleported (logged by the fake TeleportService), and the test joins them to
-- the match server's world, which starts the match from its spec. Also: the
-- in-server fallback in Studio, invites, a bot game while waiting, the
-- rematch, the online count, and the failure paths.

local process = require("@lune/process")

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Matchmaking = require("@net/Matchmaking")
local Test = require("@testlib/Test")
local Rig = require("../ui/Rig")

local describe, it, expect = Test.describe, Test.it, Test.expect

type World = FakeRoblox.World
type Peer = FakeRoblox.Peer

local PLACE = 4242
local C = Config.defaults

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

-- A live server of the published game (not Studio). `extra` adds world options.
local function server(job: string, extra: { [string]: any }?): World
	local options: { [string]: any } =
		{ root = process.cwd, seed = 7, jobId = job, placeId = PLACE, studio = false }
	for key, value in extra or {} do
		options[key] = value
	end
	return FakeRoblox.world(options :: any)
end

-- Another server of the same game as `first`, on the same clock.
local function another(first: World, job: string, extra: { [string]: any }?): World
	local options: { [string]: any } = { memory = first.memory, stores = first.data.stores }
	for key, value in extra or {} do
		options[key] = value
	end
	local world = server(job, options)
	world.clock = first.clock
	return world
end

local function runAll(worlds: { World }, seconds: number)
	for _ = 1, math.ceil(seconds / 0.1) do
		for _, world in worlds do
			FakeRoblox.step(world, 0.1)
		end
	end
end

local function runUntil(worlds: { World }, predicate: () -> boolean, limit: number): boolean
	local waited = 0
	while waited < limit do
		if predicate() then
			return true
		end
		runAll(worlds, 0.5)
		waited += 0.5
	end
	return predicate()
end

local function join(world: World, name: string, userId: number, joinData: any?): Peer
	if joinData then
		world.joinData[userId] = joinData
	end
	local peer = FakeRoblox.join(world, name, userId)
	return peer
end

-- Calls a client's Net function as that client (FireServer needs it).
local function asClient(world: World, peer: Peer, fn: () -> ())
	world.current = peer
	fn()
	world.current = nil
end

local function store(world: World, peer: Peer): any
	return Rig.storeOf(world, peer)
end

local function lobbyOf(world: World, peer: Peer): any
	return store(world, peer).get().lobby
end

local function payloadOf(world: World, peer: Peer): any
	return store(world, peer).get().payload
end

local function said(world: World, peer: Peer, text: string): boolean
	for _, message in store(world, peer).get().messages do
		if string.find(message.text, text, 1, true) then
			return true
		end
	end
	return false
end

local function sentTo(world: World, userId: number): any?
	for _, entry in world.teleport.sent do
		if entry.userId == userId then
			return entry
		end
	end
	return nil
end

local function noErrors(worlds: { World })
	for _, world in worlds do
		check(#world.errors == 0, "script errors: " .. table.concat(world.errors, " | "))
	end
end

local function serverLogged(world: World, text: string): boolean
	for _, line in world.server.log do
		if string.find(line, text, 1, true) then
			return true
		end
	end
	return false
end

-- Two lobby servers with A (UserId 1) on the first and B (2) on the second.
local function twoServers(): (World, World, Peer, Peer)
	local w1 = server("job-1")
	local w2 = another(w1, "job-2")
	local a = join(w1, "A", 1)
	local b = join(w2, "B", 2)
	runAll({ w1, w2 }, 2)
	return w1, w2, a, b
end

-- Joins the players of match server `privateId` to a new world for it.
local function matchServer(
	first: World,
	privateId: string,
	players: { { name: string, id: number } }
): (World, { Peer })
	local w3 = another(first, "job-match", { privateServerId = privateId })
	local peers = {}
	for _, p in players do
		table.insert(peers, join(w3, p.name, p.id, { TeleportData = { landslide = 1 } }))
	end
	return w3, peers
end

describe("e2e matchmaking: across servers (D-080)", function()
	it("pairs two queued players on different servers and starts their match on a match server", function()
		local w1, w2, a, b = twoServers()
		FakeRoblox.fire(w1, a, { op = "Queue" })
		runAll({ w1, w2 }, 1)
		FakeRoblox.fire(w2, b, { op = "Queue" })
		local moved = runUntil({ w1, w2 }, function()
			return sentTo(w1, 1) ~= nil and sentTo(w2, 2) ~= nil
		end, 30)
		check(moved, "the two players were never teleported")
		local toA, toB = sentTo(w1, 1) :: any, sentTo(w2, 2) :: any
		expect(toA.access):toBe(toB.access)
		expect(toA.placeId):toBe(PLACE)
		expect(toA.data.landslide):toBe(1)
		-- B's server (the newer player's) reserved the server and wrote the spec.
		expect(#w2.teleport.servers):toBe(1)
		local privateId = w2.teleport.servers[1].privateId
		local spec = w1.memory.hash[Matchmaking.SPEC_MAP][privateId].value
		expect(Matchmaking.isSpec(spec)):toBe(true)
		expect(spec.players[1]):toBe("1") -- the waiting player takes seat 1
		expect(spec.players[2]):toBe("2")
		expect(spec.mode):toBe("Queue")
		-- Both showed "Joining" before they left, and the queue is empty again.
		runAll({ w1, w2 }, 1)
		expect(#w1.clients):toBe(0)
		expect(#w2.clients):toBe(0)
		local queue = w1.memory.sorted[Matchmaking.QUEUE_MAP] or {}
		expect(next(queue)):toBe(nil)

		-- The match server: both arrive and the match starts from the spec.
		local w3, peers = matchServer(w1, privateId, { { name = "A", id = 1 }, { name = "B", id = 2 } })
		local started = runUntil({ w1, w2, w3 }, function()
			local pa, pb = payloadOf(w3, peers[1]), payloadOf(w3, peers[2])
			return pa ~= nil and pb ~= nil and pa.matchId == pb.matchId
		end, 30)
		check(started, "the match server never started the match")
		check(serverLogged(w3, `seed {spec.seed}`), "the match did not use the spec's seed")
		local pa = payloadOf(w3, peers[1])
		expect(pa.you):toBe(1)
		expect(pa.seats[2].id):toBe("2")
		expect(pa.seats[2].kind):toBe("Human")
		-- Both saved profiles loaded there: the match is rated.
		check(not serverLogged(w3, "is unrated"), "the match server's match is unrated")
		expect(lobbyOf(w3, peers[1]).matchServer):toBe(true)
		noErrors({ w1, w2, w3 })
	end)

	it("keeps two players on one server in-server: no teleport", function()
		local w1 = server("job-1")
		local a, b = join(w1, "A", 1), join(w1, "B", 2)
		runAll({ w1 }, 1)
		FakeRoblox.fire(w1, a, { op = "Queue" })
		runAll({ w1 }, 5) -- A's ticket goes out
		FakeRoblox.fire(w1, b, { op = "Queue" })
		runAll({ w1 }, 5)
		local pa, pb = payloadOf(w1, a), payloadOf(w1, b)
		check(pa ~= nil and pb ~= nil and pa.matchId == pb.matchId, "no local match")
		expect(#w1.teleport.sent):toBe(0)
		expect(next(w1.memory.sorted[Matchmaking.QUEUE_MAP] or {})):toBe(nil)
		noErrors({ w1 })
	end)

	it("finds a private code hosted on another server", function()
		local w1, w2, a, b = twoServers()
		FakeRoblox.fire(w1, a, { op = "Host", events = false })
		runAll({ w1, w2 }, 2)
		local code = lobbyOf(w1, a).code
		check(type(code) == "string", "no code")
		FakeRoblox.fire(w2, b, { op = "Join", code = code })
		runAll({ w1, w2 }, 1)
		expect(lobbyOf(w2, b).state):toBe("Found")
		local moved = runUntil({ w1, w2 }, function()
			return sentTo(w1, 1) ~= nil and sentTo(w2, 2) ~= nil
		end, 30)
		check(moved, "host and joiner were never teleported")
		local privateId = w2.teleport.servers[1].privateId
		local spec = w1.memory.hash[Matchmaking.SPEC_MAP][privateId].value
		expect(spec.players[1]):toBe("1") -- the host takes seat 1
		expect(spec.mode):toBe("Code")
		expect(spec.events):toBe(false)
		noErrors({ w1, w2 })
	end)

	it("says so when a code does not exist anywhere, and joins a real one", function()
		local w1, w2, a, b = twoServers()
		FakeRoblox.fire(w2, b, { op = "Join", code = "ZZZZZ" })
		runAll({ w1, w2 }, 2)
		check(said(w2, b, "No match with that code"), "no NoSuchCode for a missing code")
		FakeRoblox.fire(w1, a, { op = "Host" })
		runAll({ w1, w2 }, 2)
		local code = lobbyOf(w1, a).code
		FakeRoblox.fire(w2, b, { op = "Join", code = code })
		runAll({ w1, w2 }, 1)
		expect(lobbyOf(w2, b).state):toBe("Found")
		noErrors({ w1, w2 })
	end)

	it("tells the joiner when the host cancels while the match is set up", function()
		local w1, w2, a, b = twoServers()
		FakeRoblox.fire(w1, a, { op = "Host" })
		runAll({ w1, w2 }, 2)
		local code = lobbyOf(w1, a).code
		FakeRoblox.fire(w2, b, { op = "Join", code = code })
		runAll({ w1, w2 }, 1)
		expect(lobbyOf(w2, b).state):toBe("Found")
		FakeRoblox.fire(w1, a, { op = "Leave" })
		local told = runUntil({ w1, w2 }, function()
			return said(w2, b, "isn't hosting that match anymore")
		end, 30)
		check(told, "the joiner was not told")
		expect(lobbyOf(w2, b).state):toBe("Idle")
		expect(#w2.teleport.sent):toBe(0)
		noErrors({ w1, w2 })
	end)

	it("asks a player in a bot game on another server before taking them out of it", function()
		local w1, w2, a, b = twoServers()
		FakeRoblox.fire(w1, a, { op = "Queue" })
		runAll({ w1, w2 }, C.QUEUE_BOT_OFFER_SECONDS + 1)
		FakeRoblox.fire(w1, a, { op = "WaitBot", difficulty = "Easy" })
		runAll({ w1, w2 }, 4)
		check(payloadOf(w1, a) ~= nil, "no bot game")
		FakeRoblox.fire(w2, b, { op = "Queue" })
		local asked = runUntil({ w1, w2 }, function()
			local lobby = lobbyOf(w1, a)
			return lobby ~= nil and lobby.found ~= nil and lobby.found.phase == "Answer"
		end, 20)
		check(asked, "A was never asked")
		expect(lobbyOf(w2, b).found.phase):toBe("Waiting")
		asClient(w1, a, function()
			Rig.netOf(w1, a).answer(true)
		end)
		local moved = runUntil({ w1, w2 }, function()
			return sentTo(w1, 1) ~= nil and sentTo(w2, 2) ~= nil
		end, 30)
		check(moved, "the players were never teleported after A accepted")
		noErrors({ w1, w2 })
	end)

	it("puts a player back in line when the teleport fails", function()
		local w1, w2, a, b = twoServers()
		w2.teleport.failures = Matchmaking.TELEPORT_ATTEMPTS
		FakeRoblox.fire(w1, a, { op = "Queue" })
		runAll({ w1, w2 }, 1)
		FakeRoblox.fire(w2, b, { op = "Queue" })
		local back = runUntil({ w1, w2 }, function()
			return said(w2, b, "Couldn't move you to the match")
		end, 40)
		check(back, "no TeleportFailed notice")
		runAll({ w1, w2 }, 1)
		expect(lobbyOf(w2, b).state):toBe("Queued")
		noErrors({ w1, w2 })
	end)

	it("lets a failed reservation go and tries again", function()
		local w1, w2, a, b = twoServers()
		w2.teleport.reserveFailures = Matchmaking.TELEPORT_ATTEMPTS
		FakeRoblox.fire(w1, a, { op = "Queue" })
		runAll({ w1, w2 }, 1)
		FakeRoblox.fire(w2, b, { op = "Queue" })
		local moved = runUntil({ w1, w2 }, function()
			return sentTo(w1, 1) ~= nil and sentTo(w2, 2) ~= nil
		end, 60)
		check(moved, "never paired after the failed reservation")
		check(said(w2, b, "Couldn't move you"), "the failed attempt was not explained")
		noErrors({ w1, w2 })
	end)

	it("sends a match server's lone player back to the lobby and the queue", function()
		local w1 = server("job-1")
		local specs = w1.memory.hash
		specs[Matchmaking.SPEC_MAP] = {
			["ps-9"] = {
				value = Matchmaking.spec("x#1", 99, { "1", "2" }, "Queue", nil, w1.clock),
				expires = w1.clock + 600,
			},
		}
		local w3, peers = matchServer(w1, "ps-9", { { name = "A", id = 1 } })
		runAll({ w3 }, 3)
		expect(lobbyOf(w3, peers[1]).state):toBe("Found")
		expect(lobbyOf(w3, peers[1]).found.phase):toBe("Arriving")
		local sent = runUntil({ w3 }, function()
			return sentTo(w3, 1) ~= nil
		end, Matchmaking.ARRIVAL_TIMEOUT + 10)
		check(sent, "the lone player was never sent back")
		local trip = sentTo(w3, 1) :: any
		expect(trip.access):toBe(nil)
		expect(trip.data.notice):toBe("OpponentNoShow")
		expect(trip.data.requeue):toBe(true)

		-- Back on a lobby server: the notice, and straight back in the queue.
		local w4 = another(w1, "job-4")
		local back = join(w4, "A", 1, { TeleportData = trip.data })
		runAll({ w4 }, 2)
		check(said(w4, back, "couldn't reach the match"), "no notice on return")
		expect(lobbyOf(w4, back).state):toBe("Queued")
		noErrors({ w3, w4 })
	end)

	it("takes players from a match server back to a lobby server after the match", function()
		local w1 = server("job-1")
		w1.memory.hash[Matchmaking.SPEC_MAP] = {
			["ps-7"] = {
				value = Matchmaking.spec("x#2", 1234, { "1", "2" }, "Queue", nil, w1.clock),
				expires = w1.clock + 600,
			},
		}
		local w3, peers = matchServer(w1, "ps-7", { { name = "A", id = 1 }, { name = "B", id = 2 } })
		check(
			runUntil({ w3 }, function()
				return payloadOf(w3, peers[1]) ~= nil
			end, 20),
			"no match"
		)
		asClient(w3, peers[2], function()
			Rig.netOf(w3, peers[2]).forfeit()
		end)
		runAll({ w3 }, 2)
		expect(payloadOf(w3, peers[1]).stage):toBe("Over")
		FakeRoblox.fire(w3, peers[1], { op = "Return" })
		check(
			runUntil({ w3 }, function()
				return sentTo(w3, 1) ~= nil
			end, 10),
			"Return did not teleport"
		)
		expect((sentTo(w3, 1) :: any).access):toBe(nil)
		-- On a lobby server Return is turned down.
		local w4 = another(w1, "job-4")
		local p = join(w4, "C", 3)
		runAll({ w4 }, 1)
		FakeRoblox.fire(w4, p, { op = "Return" })
		runAll({ w4 }, 1)
		check(said(w4, p, "already in the lobby"), "Return on a lobby server was not turned down")
		noErrors({ w3, w4 })
	end)
end)

describe("e2e matchmaking: Studio and failures fall back to in-server (D-080)", function()
	it("matches in-server in Studio with no memory store or teleport, and counts this server", function()
		local world = FakeRoblox.world({ root = process.cwd, seed = 3 })
		local a, b = join(world, "A", 1), join(world, "B", 2)
		runAll({ world }, 1)
		expect(lobbyOf(world, a).online):toBe(2)
		FakeRoblox.fire(world, a, { op = "Queue" })
		runAll({ world }, 4)
		FakeRoblox.fire(world, b, { op = "Queue" })
		runAll({ world }, 2)
		local pa, pb = payloadOf(world, a), payloadOf(world, b)
		check(pa ~= nil and pb ~= nil and pa.matchId == pb.matchId, "no match in Studio")
		expect(world.memory.requests):toBe(0)
		expect(#world.teleport.sent):toBe(0)
		noErrors({ world })
	end)

	it("keeps working in-server when memory stores fail, and hides the online count", function()
		local w1 = server("job-1")
		w1.memory.failures = 100000
		local a, b = join(w1, "A", 1), join(w1, "B", 2)
		runAll({ w1 }, 70)
		expect(lobbyOf(w1, a).online):toBe(nil)
		FakeRoblox.fire(w1, a, { op = "Queue" })
		runAll({ w1 }, 8)
		FakeRoblox.fire(w1, b, { op = "Queue" })
		runAll({ w1 }, 2)
		local pa, pb = payloadOf(w1, a), payloadOf(w1, b)
		check(pa ~= nil and pb ~= nil and pa.matchId == pb.matchId, "no local match while memory stores fail")
		noErrors({ w1 })
	end)
end)

describe("e2e matchmaking: online count (D-080)", function()
	it("adds up the players on every server", function()
		local w1, w2, a, _b = twoServers()
		local c = join(w2, "C", 3)
		local counted = runUntil({ w1, w2 }, function()
			local lobby = lobbyOf(w1, a)
			return lobby ~= nil and lobby.online == 3
		end, Matchmaking.ONLINE_PERIOD * 2 + 5)
		check(counted, `server 1 never showed 3 online (shows {tostring((lobbyOf(w1, a) or {}).online)})`)
		check(
			runUntil({ w1, w2 }, function()
				return lobbyOf(w2, c).online == 3
			end, Matchmaking.ONLINE_PERIOD + 5),
			"server 2 never showed 3 online"
		)
		noErrors({ w1, w2 })
	end)
end)

describe("e2e matchmaking: invites (D-080)", function()
	it("takes an invited friend straight into the host's private match", function()
		local world = FakeRoblox.world({ root = process.cwd, seed = 3 })
		local host = join(world, "Host", 1)
		runAll({ world }, 1)
		FakeRoblox.fire(world, host, { op = "Host" })
		runAll({ world }, 1)
		local code = lobbyOf(world, host).code
		local friend = join(world, "Friend", 2, { LaunchData = Matchmaking.launchData(code) })
		local started = runUntil({ world }, function()
			local ph, pf = payloadOf(world, host), payloadOf(world, friend)
			return ph ~= nil and pf ~= nil and ph.matchId == pf.matchId
		end, 15)
		check(started, "the invited friend was not taken into the match")
		noErrors({ world })
	end)

	it("tells a friend who arrives after the host left that the invite expired", function()
		local world = FakeRoblox.world({ root = process.cwd, seed = 3 })
		local host = join(world, "Host", 1)
		runAll({ world }, 1)
		FakeRoblox.fire(world, host, { op = "Host" })
		runAll({ world }, 1)
		local code = lobbyOf(world, host).code
		FakeRoblox.leave(world, host)
		local friend = join(world, "Friend", 2, { LaunchData = Matchmaking.launchData(code) })
		local told = runUntil({ world }, function()
			return said(world, friend, "invite has expired")
		end, 15)
		check(told, "no InviteExpired notice")
		expect(lobbyOf(world, friend).state):toBe("Idle")
		noErrors({ world })
	end)

	it("finds the host on another server", function()
		local w1, w2, a, _b = twoServers()
		FakeRoblox.fire(w1, a, { op = "Host" })
		runAll({ w1, w2 }, 2)
		local code = lobbyOf(w1, a).code
		join(w2, "Friend", 5, { LaunchData = Matchmaking.launchData(code) })
		local moved = runUntil({ w1, w2 }, function()
			return sentTo(w1, 1) ~= nil and sentTo(w2, 5) ~= nil
		end, 40)
		check(moved, "the invited friend and the host never met")
		noErrors({ w1, w2 })
	end)

	it("opens Roblox's invite prompt with the code, or says invites are unavailable", function()
		local world = FakeRoblox.world({ root = process.cwd, seed = 3 })
		local host = join(world, "Host", 1)
		runAll({ world }, 1)
		FakeRoblox.fire(world, host, { op = "Host" })
		runAll({ world }, 1)
		local code = lobbyOf(world, host).code
		Rig.tap(world, host, "Lobby", "InviteHost", 1)
		expect(#world.social.prompts):toBe(1)
		expect(world.social.prompts[1].launchData):toBe(Matchmaking.launchData(code))
		world.social.canInvite = false
		Rig.tap(world, host, "Lobby", "InviteHost", 1)
		expect(#world.social.prompts):toBe(1)
		check(said(world, host, "Invites aren't available"), "no message when invites are unavailable")
		world.social.canInvite = true
		world.social.failures = 1
		Rig.tap(world, host, "Lobby", "InviteHost", 1)
		expect(#world.social.prompts):toBe(1)
		noErrors({ world })
	end)
end)

describe("e2e matchmaking: a bot game while waiting (D-080)", function()
	local function queuedWithBot(): (World, Peer)
		local world = FakeRoblox.world({ root = process.cwd, seed = 3 })
		local a = join(world, "A", 1)
		runAll({ world }, 1)
		FakeRoblox.fire(world, a, { op = "Queue" })
		runAll({ world }, 1)
		FakeRoblox.fire(world, a, { op = "WaitBot", difficulty = "Hard" })
		runAll({ world }, 1)
		check(said(world, a, "bot game opens after"), "WaitBot was not turned down before 30 s")
		expect(payloadOf(world, a)):toBe(nil)
		runAll({ world }, C.QUEUE_BOT_OFFER_SECONDS)
		check(type(lobbyOf(world, a).botAt) == "number", "no botAt while queued")
		FakeRoblox.fire(world, a, { op = "WaitBot", difficulty = "Hard" })
		runAll({ world }, 2)
		local payload = payloadOf(world, a)
		check(payload ~= nil, "no bot game")
		expect(payload.seats[2].kind):toBe("Bot")
		expect(payload.seats[2].difficulty):toBe("Hard")
		expect(payload.tutorial):toBe(nil)
		check(said(world, a, "still in the queue"), "no WaitBot notice")
		return world, a
	end

	it("joins the match found when the player accepts, ending the bot game unrated", function()
		local world, a = queuedWithBot()
		local botMatch = payloadOf(world, a).matchId
		local b = join(world, "B", 2)
		runAll({ world }, 1)
		FakeRoblox.fire(world, b, { op = "Queue" })
		runAll({ world }, 1)
		expect(lobbyOf(world, b).state):toBe("Found")
		expect(lobbyOf(world, b).found.phase):toBe("Waiting")
		expect(lobbyOf(world, a).found.phase):toBe("Answer")
		check(Rig.findIn(a, "FoundOverlay", "FoundJoin") ~= nil, "no prompt over the bot game")
		check(FakeRoblox.find(a, "FoundOverlay").Visible == true, "the prompt is hidden")
		Rig.tap(world, a, "FoundOverlay", "FoundJoin", 2)
		local pa, pb = payloadOf(world, a), payloadOf(world, b)
		check(pa ~= nil and pb ~= nil and pa.matchId == pb.matchId, "no match after accepting")
		check(pa.matchId ~= botMatch, "still the bot match")
		expect(pa.seats[1].kind):toBe("Human")
		expect(pa.seats[2].kind):toBe("Human")
		expect(FakeRoblox.find(a, "Results")):toBe(nil) -- the bot game's end is skipped
		-- The cut-short bot game is not in the saved practice record.
		local saved = world.data.stores.PlayerData_v1.Player_1
		local practice = if saved and saved.data then saved.data.practice else nil
		expect(practice == nil or practice.games == 0):toBe(true)
		noErrors({ world })
	end)

	it("keeps the bot game and puts the other player first in line on Keep playing", function()
		local world, a = queuedWithBot()
		local b = join(world, "B", 2)
		runAll({ world }, 1)
		FakeRoblox.fire(world, b, { op = "Queue" })
		runAll({ world }, 1)
		Rig.tap(world, a, "FoundOverlay", "FoundKeep", 1)
		expect(payloadOf(world, a).seats[2].kind):toBe("Bot")
		expect(lobbyOf(world, a).found):toBe(nil)
		expect(lobbyOf(world, b).state):toBe("Queued")
		check(said(world, a, "You left the queue"), "no notice for the decliner")
		check(said(world, b, "You're first in line"), "no notice for the other player")
		noErrors({ world })
	end)

	it("counts no answer as Keep playing", function()
		local world, a = queuedWithBot()
		local b = join(world, "B", 2)
		runAll({ world }, 1)
		FakeRoblox.fire(world, b, { op = "Queue" })
		runAll({ world }, C.QUEUE_ACCEPT_SECONDS + 2)
		check(said(world, a, "No answer in time"), "no expiry notice")
		expect(lobbyOf(world, b).state):toBe("Queued")
		expect(FakeRoblox.find(a, "FoundOverlay").Visible):toBe(false)
		noErrors({ world })
	end)
end)

describe("e2e matchmaking: rematch (D-080)", function()
	-- A and B queue on one server and autoplay a whole match to Results.
	local function playedMatch(seed: number): (World, Peer, Peer)
		local world = FakeRoblox.world({ root = process.cwd, seed = seed })
		local a, b = join(world, "A", 1), join(world, "B", 2)
		runAll({ world }, 1)
		FakeRoblox.fire(world, a, { op = "Queue" })
		FakeRoblox.fire(world, b, { op = "Queue" })
		runAll({ world }, 1)
		FakeRoblox.press(world, a, "Autoplay")
		FakeRoblox.press(world, b, "Autoplay")
		local over = runUntil({ world }, function()
			local pa, pb = payloadOf(world, a), payloadOf(world, b)
			return pa ~= nil and pb ~= nil and pa.stage == "Over" and pb.stage == "Over"
		end, 1200)
		check(over, "the match never ended")
		FakeRoblox.press(world, a, "Autoplay")
		FakeRoblox.press(world, b, "Autoplay")
		runAll({ world }, 1)
		return world, a, b
	end

	it("against a person: both tap within the window, a new match with the same seats", function()
		local world, a, b = playedMatch(4)
		local first = payloadOf(world, a)
		local seatA = first.you
		local status = store(world, a).get().rematch
		check(status ~= nil and status.matchId == first.matchId, "no rematch status")
		expect(status.state):toBe("Open")
		Rig.tap(world, a, "Results", "Rematch", 1)
		expect(store(world, a).get().rematch.state):toBe("Waiting")
		expect(store(world, b).get().rematch.state):toBe("Asked")
		check(not Rig.enabled(a, "Results", "Rematch"), "Rematch stays enabled after asking")
		Rig.tap(world, b, "Results", "Rematch", 2)
		local again = payloadOf(world, a)
		check(again.matchId ~= first.matchId, "no new match")
		expect(again.you):toBe(seatA) -- the same seats
		expect(payloadOf(world, b).matchId):toBe(again.matchId)
		-- The new match ends in a forfeit: the one who left cannot be rematched.
		asClient(world, b, function()
			Rig.netOf(world, b).forfeit()
		end)
		runAll({ world }, 1)
		expect(store(world, a).get().rematch.state):toBe("Gone")
		expect(Rig.textOf(a, "Results", "Rematch")):toBe("Opponent left")
		FakeRoblox.fire(world, a, { op = "Rematch", matchId = payloadOf(world, a).matchId })
		runAll({ world }, 1)
		check(said(world, a, "Your opponent has left"), "no OpponentLeft rejection")
		noErrors({ world })
	end)

	it(
		"closes the window after REMATCH_WINDOW_SECONDS, and when the opponent starts something else",
		function()
			local world, a, b = playedMatch(6)
			Rig.tap(world, a, "Results", "Rematch", 1)
			runAll({ world }, C.REMATCH_WINDOW_SECONDS + 1)
			expect(store(world, a).get().rematch.state):toBe("Expired")
			expect(store(world, b).get().rematch.state):toBe("Expired")
			expect(Rig.textOf(b, "Results", "Rematch")):toBe("Rematch expired")
			noErrors({ world })
		end
	)

	it("against the bot: one tap starts a new match at the same level", function()
		local world = FakeRoblox.world({ root = process.cwd, seed = 4 })
		local keys = {}
		world.data.stores.PlayerData_v1 = keys
		keys.Player_1 = { data = { version = 1, tutorialDone = true } }
		local a = join(world, "A", 1)
		runAll({ world }, 1)
		FakeRoblox.fire(world, a, { op = "Practice", difficulty = "Easy" })
		runAll({ world }, 1)
		FakeRoblox.press(world, a, "Autoplay")
		local over = runUntil({ world }, function()
			local p = payloadOf(world, a)
			return p ~= nil and p.stage == "Over"
		end, 1500)
		check(over, "the bot match never ended")
		FakeRoblox.press(world, a, "Autoplay")
		local first = payloadOf(world, a).matchId
		runAll({ world }, 1)
		expect(Rig.textOf(a, "Results", "Rematch")):toBe("Rematch")
		Rig.tap(world, a, "Results", "Rematch", 2)
		local again = payloadOf(world, a)
		check(again.matchId ~= first, "no new bot match")
		expect(again.seats[2].kind):toBe("Bot")
		expect(again.seats[2].difficulty):toBe("Easy")
		noErrors({ world })
	end)
end)
