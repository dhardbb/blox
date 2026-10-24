--!strict
-- End to end: the tutorial (D-075) on the real server and client. A new
-- player's first bot match is the tutorial (no choice deadline, told so); it is
-- marked done in their saved profile when it ends in an election or a forfeit;
-- an abandoned one comes back; How to play's replay always gets the tutorial
-- against the Easy bot; and ordinary bot matches get their level's longer timers.

local process = require("@lune/process")

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Support = require("./Support")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local PLAYER_DATA = "PlayerData_v1"

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function noErrors(rig: Support.Rig)
	check(#rig.world.errors == 0, "script errors: " .. table.concat(rig.world.errors, " | "))
	check(#rig.world.wireWarnings == 0, "wire warnings: " .. table.concat(rig.world.wireWarnings, " | "))
end

local function state(rig: Support.Rig, peer: FakeRoblox.Peer): any
	local module = peer.modules[`{rig.world.root}/src/client/Store.luau`]
	check(module ~= nil, "the client Store is not loaded")
	return module.get()
end

local function saved(rig: Support.Rig, userId: number): any
	local keys = rig.world.data.stores[PLAYER_DATA]
	local record = if keys then keys[`Player_{userId}`] else nil
	return if record then record.data else nil
end

local function serverSaid(rig: Support.Rig, text: string): number
	return #Support.outputLines(rig.world.server, text)
end

local function told(rig: Support.Rig, peer: FakeRoblox.Peer, text: string): boolean
	for _, message in state(rig, peer).messages do
		if string.find(message.text, text, 1, true) then
			return true
		end
	end
	return false
end

describe("e2e: the tutorial (D-075)", function()
	it("a new player's first bot match has no deadline; leaving it marks it done", function()
		local rig = Support.new(process.cwd, 61)
		local p1 = Support.join(rig, "Player1")
		Support.fire(rig, p1, { op = "Practice", difficulty = "Hard" })
		Support.run(rig, 1)
		expect(serverSaid(rig, "match m1 started (Practice)")):toBe(1)
		expect(serverSaid(rig, "bot Hard, tutorial")):toBe(1) -- the first one keeps the level picked
		local payload = state(rig, p1).payload
		expect(payload.stage):toBe("Input")
		expect(payload.deadline):toBe(nil)
		expect(payload.tutorial):toBe(true)
		check(told(rig, p1, "no timer"), "the player was not told there is no timer")
		-- Ten idle minutes later Select is still waiting.
		Support.run(rig, 600)
		payload = state(rig, p1).payload
		expect(payload.view.phase):toBe("Select")
		expect(payload.stage):toBe("Input")

		Support.fire(rig, p1, { op = "Forfeit", matchId = "m1" })
		Support.run(rig, 3)
		expect(serverSaid(rig, "match m1 over: Forfeit")):toBe(1)
		local data = saved(rig, 1)
		expect(data and data.tutorialDone):toBe(true)

		-- The next bot match is an ordinary one: timed, the Medium bot's x1.5.
		Support.fire(rig, p1, { op = "Practice", difficulty = "Medium" })
		Support.run(rig, 1)
		expect(serverSaid(rig, "match m2 started (Practice)")):toBe(1)
		expect(serverSaid(rig, "tutorial")):toBe(1) -- only m1's line
		payload = state(rig, p1).payload
		expect(payload.matchId):toBe("m2")
		expect(payload.tutorial):toBe(nil)
		check(payload.deadline ~= nil, "an ordinary bot match has no deadline")
		check(
			math.abs(payload.deadline - payload.stageStart - C.TIMER_SELECT * C.BOT_TIME_MULT_MEDIUM) < 1e-6,
			"Select is not 1.5 times as long against the Medium bot"
		)
		noErrors(rig)
	end)

	it("How to play's replay is the tutorial again, always against the Easy bot", function()
		local rig = Support.new(process.cwd, 62)
		local p1 = Support.join(rig, "Player1")
		Support.fire(rig, p1, { op = "Practice" })
		Support.run(rig, 1)
		Support.fire(rig, p1, { op = "Forfeit", matchId = "m1" })
		Support.run(rig, 3)
		expect(saved(rig, 1).tutorialDone):toBe(true)

		Support.fire(rig, p1, { op = "Practice", difficulty = "Extreme", tutorial = true })
		Support.run(rig, 1)
		expect(serverSaid(rig, "match m2 started (Practice)")):toBe(1)
		expect(serverSaid(rig, "bot Easy, tutorial")):toBe(1)
		local payload = state(rig, p1).payload
		expect(payload.deadline):toBe(nil)
		expect(payload.tutorial):toBe(true)
		noErrors(rig)
	end)

	it("an abandoned tutorial (the player quit the game) comes back next visit", function()
		local rig = Support.new(process.cwd, 63)
		local p1 = Support.join(rig, "Player1")
		Support.fire(rig, p1, { op = "Practice" })
		Support.run(rig, 1)
		expect(serverSaid(rig, "tutorial")):toBe(1)
		Support.leave(rig, p1)
		Support.run(rig, C.DISCONNECT_GRACE + 5)
		expect(serverSaid(rig, "match m1 over: Abandoned")):toBe(1)
		local data = saved(rig, 1)
		expect(if data then data.tutorialDone else nil):toBe(nil)

		local back = Support.join(rig, "Player1", 1)
		Support.run(rig, 2)
		Support.fire(rig, back, { op = "Practice" })
		Support.run(rig, 1)
		expect(serverSaid(rig, "match m2 started (Practice)")):toBe(1)
		expect(serverSaid(rig, "tutorial")):toBe(2)
		expect(state(rig, back).payload.deadline):toBe(nil)
		noErrors(rig)
	end)

	it("a player who has played before never gets it uninvited", function()
		local rig = Support.new(process.cwd, 64)
		local keys = rig.world.data.stores[PLAYER_DATA] or {}
		rig.world.data.stores[PLAYER_DATA] = keys
		keys.Player_1 = {
			data = { version = 1, rating = 1000, practice = { games = 4, wins = 2, losses = 2 } },
		} :: any
		local p1 = Support.join(rig, "Player1")
		Support.run(rig, 2)
		Support.fire(rig, p1, { op = "Practice", difficulty = "Easy" })
		Support.run(rig, 1)
		expect(serverSaid(rig, "match m1 started (Practice)")):toBe(1)
		expect(serverSaid(rig, "tutorial")):toBe(0)
		local payload = state(rig, p1).payload
		check(payload.deadline ~= nil, "a returning player's bot match has no deadline")
		check(
			math.abs(payload.deadline - payload.stageStart - C.TIMER_SELECT * C.BOT_TIME_MULT_EASY) < 1e-6,
			"Select is not twice as long against the Easy bot"
		)
		noErrors(rig)
	end)
end)
