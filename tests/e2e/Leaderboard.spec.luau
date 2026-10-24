--!strict
-- End to end: the global leaderboard (D-059) and leaving a match (D-059). The
-- real server and client on the fake engine, whose OrderedDataStore is
-- world.data.ordered (its own failure switch: world.data.orderedFailures) and
-- whose Players:GetNameFromUserIdAsync answers from world.userNames.

local process = require("@lune/process")

local Test = require("@testlib/Test")
local FakeRoblox = require("@testlib/FakeRoblox")
local Profile = require("@net/Profile")
local Support = require("./Support")

local describe, it, expect = Test.describe, Test.it, Test.expect

local BOARD = "Leaderboard_v1"
local PLAYER_DATA = "PlayerData_v1"
local REFRESH = 60

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function newRig(seed: number): Support.Rig
	return Support.new(process.cwd, seed)
end

local function noErrors(rig: Support.Rig)
	check(#rig.world.errors == 0, "script errors: " .. table.concat(rig.world.errors, " | "))
	check(#rig.world.wireWarnings == 0, "wire warnings: " .. table.concat(rig.world.wireWarnings, " | "))
end

local function store(rig: Support.Rig, peer: FakeRoblox.Peer): any
	local module = peer.modules[`{rig.world.root}/src/client/Store.luau`]
	check(module ~= nil, "the client Store is not loaded")
	return module
end

-- The board this client was sent last.
local function board(rig: Support.Rig, peer: FakeRoblox.Peer): any
	local value = store(rig, peer).get().leaderboard
	check(value ~= nil, `{peer.name} has no leaderboard`)
	return value
end

local function names(value: any): string
	local out = {}
	for _, entry in value.entries do
		table.insert(out, `{entry.rank}.{entry.name}={entry.rating}`)
	end
	return table.concat(out, " ")
end

local function seed(rig: Support.Rig, rows: { [string]: number })
	local keys = rig.world.data.ordered[BOARD] or {}
	rig.world.data.ordered[BOARD] = keys
	for key, value in rows do
		keys[key] = value
	end
end

local function ask(rig: Support.Rig, peer: FakeRoblox.Peer)
	Support.fire(rig, peer, { op = "Leaderboard" })
	Support.run(rig, 2)
end

local function saved(rig: Support.Rig, userId: number): any
	local keys = rig.world.data.stores[PLAYER_DATA]
	local record = if keys then keys[`Player_{userId}`] else nil
	check(record ~= nil, `nothing saved for {userId}`)
	return record.data
end

local function serverSaid(rig: Support.Rig, text: string): number
	return #Support.outputLines(rig.world.server, text)
end

describe("e2e: the global leaderboard", function()
	it("lists nobody on a fresh server, and the viewer is unranked", function()
		local rig = newRig(31)
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 2)
		local value = board(rig, p1)
		expect(value.status):toBe("Ok")
		expect(#value.entries):toBe(0)
		expect(value.you):toBe(nil)
		noErrors(rig)
	end)

	it("ranks the store's ratings best first, with usernames and the viewer's place", function()
		local rig = newRig(32)
		rig.world.userNames[500] = "RiverKite"
		rig.world.userNames[501] = "AmberOwl"
		seed(rig, { Player_500 = 1300, Player_501 = 1100, Player_1 = 1200 })
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 2)
		local value = board(rig, p1)
		expect(names(value)):toBe("1.RiverKite=1300 2.Player1=1200 3.AmberOwl=1100")
		expect(value.you and value.you.rank):toBe(2)
		noErrors(rig)
	end)

	it("reads the store at most once a minute, however often it is asked", function()
		local rig = newRig(33)
		local p1 = Support.join(rig, "Player1")
		local p2 = Support.join(rig, "Player2")
		Support.run(rig, 2)
		expect(rig.world.data.sortedReads):toBe(1) -- both Lobbies asked; one read
		for _ = 1, 3 do
			ask(rig, p1)
		end
		expect(rig.world.data.sortedReads):toBe(1)
		seed(rig, { Player_900 = 1500 })
		ask(rig, p2)
		expect(#board(rig, p2).entries):toBe(0) -- still the cached list
		Support.run(rig, REFRESH)
		ask(rig, p2)
		expect(rig.world.data.sortedReads):toBe(2)
		expect(#board(rig, p2).entries):toBe(1)
		noErrors(rig)
	end)

	it("says Unavailable when it never read the store, and keeps the last good list after", function()
		local rig = newRig(34)
		rig.world.data.orderedFailures = 1
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 2)
		expect(board(rig, p1).status):toBe("Unavailable")
		expect(#board(rig, p1).entries):toBe(0)

		rig.world.userNames[500] = "RiverKite"
		seed(rig, { Player_500 = 1300 })
		Support.run(rig, REFRESH)
		ask(rig, p1)
		expect(board(rig, p1).status):toBe("Ok")
		expect(names(board(rig, p1))):toBe("1.RiverKite=1300")

		rig.world.data.orderedFailures = 1
		Support.run(rig, REFRESH)
		ask(rig, p1)
		expect(board(rig, p1).status):toBe("Ok")
		expect(names(board(rig, p1))):toBe("1.RiverKite=1300")
		check(serverSaid(rig, "could not read the leaderboard") >= 2, "the failed reads were not logged")
		noErrors(rig)
	end)

	it("shows a placeholder for a name it could not look up, and tries again next read", function()
		local rig = newRig(35)
		rig.world.userNames[500] = "RiverKite"
		rig.world.nameFailures = 1
		seed(rig, { Player_500 = 1300 })
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 2)
		expect(names(board(rig, p1))):toBe("1.Player 500=1300")
		Support.run(rig, REFRESH)
		ask(rig, p1)
		expect(names(board(rig, p1))):toBe("1.RiverKite=1300")
		local lookups = rig.world.nameLookups
		Support.run(rig, REFRESH)
		ask(rig, p1)
		expect(rig.world.nameLookups):toBe(lookups) -- cached now
		noErrors(rig)
	end)

	it("adds a returning player who already has rated games", function()
		local rig = newRig(36)
		local profile = Profile.new()
		profile.games = 3
		profile.wins = 2
		profile.losses = 1
		profile.rating = 1111
		rig.world.data.stores[PLAYER_DATA] = { Player_1 = { data = profile } }
		Support.join(rig, "Player1")
		Support.run(rig, 2)
		expect(rig.world.data.ordered[BOARD].Player_1):toBe(1111)
		noErrors(rig)
	end)
end)

describe("e2e: leaving a match", function()
	it("against a person: a forfeit, rated, the opponent wins and the leaver is in the lobby", function()
		local rig = newRig(41)
		local p1, p2 = Support.join(rig, "Player1"), Support.join(rig, "Player2")
		Support.queueMatch(rig, p1, p2)
		check(serverSaid(rig, "match m1 started") == 1, "no match started")
		-- From week 1 on (before it, a forfeit is unrated: D-077).
		Support.press(rig, p1, "Autoplay")
		Support.press(rig, p2, "Autoplay")
		check(Support.untilStatus(rig, p1, "Week 1 Plan · Input", 400), "never reached Week 1")
		Support.fire(rig, p1, { op = "Forfeit", matchId = "m1" })
		Support.run(rig, 3)
		expect(serverSaid(rig, "match m1 over: Forfeit, winner seat 2")):toBe(1)

		local loser, winner = saved(rig, 1), saved(rig, 2)
		check(loser.rating < 1000 and winner.rating > 1000, "the ratings did not move")
		expect(loser.rating + winner.rating):toBe(2000)
		expect(loser.losses):toBe(1)
		expect(winner.wins):toBe(1)
		expect(loser.recent[1].reason):toBe("Forfeit")
		-- Both ratings are on the board now.
		expect(rig.world.data.ordered[BOARD].Player_1):toBe(loser.rating)
		expect(rig.world.data.ordered[BOARD].Player_2):toBe(winner.rating)

		-- The winner sees the match end by forfeit; the leaver is back in the lobby.
		local theirs = store(rig, p2).get()
		expect(theirs.payload.stage):toBe("Over")
		expect(theirs.payload.result.reason):toBe("Forfeit")
		expect(theirs.payload.result.winner):toBe(theirs.payload.you)
		local told = false
		for _, message in theirs.messages do
			if string.find(message.text, "You win by forfeit", 1, true) then
				told = true
			end
		end
		check(told, "the winner was not told their opponent left")
		local mine = store(rig, p1).get()
		expect(mine.lobby.state):toBe("Idle")
		noErrors(rig)
	end)

	it("against the bot: a practice loss, the rating and the board untouched", function()
		local rig = newRig(42)
		local p1 = Support.join(rig, "Player1")
		Support.press(rig, p1, "Practice")
		Support.run(rig, 1)
		Support.fire(rig, p1, { op = "Forfeit", matchId = "m1" })
		Support.run(rig, 3)
		expect(serverSaid(rig, "match m1 over: Forfeit, winner seat 2")):toBe(1)
		local data = saved(rig, 1)
		expect(data.rating):toBe(1000)
		expect(data.games):toBe(0)
		expect(data.practice.losses):toBe(1)
		local keys = rig.world.data.ordered[BOARD]
		expect(if keys then keys.Player_1 else nil):toBe(nil)
		expect(store(rig, p1).get().lobby.state):toBe("Idle")
		noErrors(rig)
	end)

	it("a second request changes nothing and is not an error", function()
		local rig = newRig(43)
		local p1 = Support.join(rig, "Player1")
		Support.press(rig, p1, "Practice")
		Support.run(rig, 1)
		Support.fire(rig, p1, { op = "Forfeit", matchId = "m1" })
		Support.fire(rig, p1, { op = "Forfeit", matchId = "m1" })
		Support.run(rig, 3)
		expect(serverSaid(rig, "match m1 over")):toBe(1)
		expect(serverSaid(rig, "rejected Forfeit")):toBe(0)
		expect(saved(rig, 1).practice.losses):toBe(1)
		noErrors(rig)
	end)

	it("outside a match it only sends the lobby again; another match's id is turned down", function()
		local rig = newRig(44)
		local p1 = Support.join(rig, "Player1")
		Support.fire(rig, p1, { op = "Forfeit", matchId = "m7" })
		Support.run(rig, 1)
		expect(serverSaid(rig, "rejected Forfeit")):toBe(0)
		expect(store(rig, p1).get().lobby.state):toBe("Idle")

		Support.press(rig, p1, "Practice")
		Support.run(rig, 1)
		Support.fire(rig, p1, { op = "Forfeit", matchId = "m9" })
		Support.run(rig, 1)
		expect(serverSaid(rig, "NotInMatch")):toBe(1)
		expect(serverSaid(rig, "match m1 over")):toBe(0)
		expect(store(rig, p1).get().lobby.state):toBe("InMatch")
		Support.fire(rig, p1, { op = "Forfeit" }) -- no match id: refused by the schema
		Support.run(rig, 1)
		expect(serverSaid(rig, "match m1 over")):toBe(0)
		noErrors(rig)
	end)
end)
