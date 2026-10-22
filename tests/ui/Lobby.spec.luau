--!strict
-- The Lobby, Select and Results screens on the fake Roblox engine: fixtures
-- render offline with a clean UI audit, the controls do what they say, and a
-- live practice match runs from the Lobby to the Results screen and back.

local process = require("@lune/process")

local Test = require("@testlib/Test")
local FakeRoblox = require("@testlib/FakeRoblox")

local describe, it, expect = Test.describe, Test.it, Test.expect

local PHONE = { x = 390, y = 844 }
local MATCH_LIMIT = 600 -- simulated seconds for a whole autoplayed match

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function newWorld(screen: { x: number, y: number }?): FakeRoblox.World
	return FakeRoblox.world({ root = process.cwd, seed = 5, screen = screen })
end

local function noErrors(world: FakeRoblox.World)
	check(#world.errors == 0, "script errors: " .. table.concat(world.errors, " | "))
	check(#world.wireWarnings == 0, "wire warnings: " .. table.concat(world.wireWarnings, " | "))
end

local function logged(peer: FakeRoblox.Peer, text: string): boolean
	for _, line in peer.log do
		if string.find(line, text, 1, true) then
			return true
		end
	end
	return false
end

local function count(peer: FakeRoblox.Peer, text: string): number
	local n = 0
	for _, line in peer.log do
		if string.find(line, text, 1, true) then
			n += 1
		end
	end
	return n
end

-- Finds `name` inside the screen frame called `screen` (the debug panel has
-- buttons named Practice and Host too, so a bare find could pick those).
local function findIn(peer: FakeRoblox.Peer, screen: string, name: string): any
	local root = FakeRoblox.find(peer, screen)
	if root == nil then
		return nil
	end
	for _, inst in root:GetDescendants() do
		if inst.Name == name then
			return inst
		end
	end
	return nil
end

local function need(peer: FakeRoblox.Peer, screen: string, name: string): any
	local inst = findIn(peer, screen, name)
	check(inst ~= nil, `{screen} has no element {name}`)
	return inst
end

local function tap(world: FakeRoblox.World, peer: FakeRoblox.Peer, screen: string, name: string)
	local inst = need(peer, screen, name)
	world.current = peer
	inst.Activated.fire()
	world.current = nil
	FakeRoblox.run(world, 0.3)
end

local function textOf(peer: FakeRoblox.Peer, screen: string, name: string): string
	return tostring(need(peer, screen, name).Text)
end

local function visible(peer: FakeRoblox.Peer, screen: string, name: string): boolean
	local inst = need(peer, screen, name)
	return inst.Visible ~= false
end

local function mountFixture(
	fixture: string,
	screen: { x: number, y: number }?
): (FakeRoblox.World, FakeRoblox.Peer)
	local world = newWorld(screen)
	local peer = FakeRoblox.join(world, "P", { DebugScreen = fixture })
	FakeRoblox.run(world, 2)
	return world, peer
end

-- The client's Store module, to push crafted payloads into a fixture.
local function storeOf(peer: FakeRoblox.Peer): any
	for path, module in peer.modules do
		if string.match(path, "/client/Store%.luau$") then
			return module
		end
	end
	error("no Store module loaded")
end

local FIXTURES: { { fixture: string, screen: string } } = {
	{ fixture = "Lobby", screen = "Lobby" },
	{ fixture = "Select", screen = "Select" },
	{ fixture = "Over", screen = "Results" },
}

describe("Lobby, Select and Results mount", function()
	for _, case in FIXTURES do
		it(`{case.screen} renders {case.fixture} at 1280x720 with a clean audit`, function()
			local world, peer = mountFixture(case.fixture, nil)
			check(FakeRoblox.find(peer, case.screen) ~= nil, `{case.screen} did not mount`)
			expect(logged(peer, `UI audit {case.screen}: 0 problem(s)`)):toBe(true)
			noErrors(world)
		end)

		it(`{case.screen} mounts on a phone in portrait`, function()
			local world, peer = mountFixture(case.fixture, PHONE)
			check(FakeRoblox.find(peer, case.screen) ~= nil, `{case.screen} did not mount`)
			expect(logged(peer, `UI audit {case.screen}: 0 problem(s)`)):toBe(true)
			noErrors(world)
		end)
	end
end)

describe("Lobby", function()
	it("sends Practice, Queue and Host from its buttons", function()
		local world, peer = mountFixture("Lobby", nil)
		tap(world, peer, "Lobby", "Practice")
		expect(logged(peer, "DEBUG_UI send Practice")):toBe(true)
		tap(world, peer, "Lobby", "FindMatch")
		expect(logged(peer, "DEBUG_UI send Queue")):toBe(true)
		tap(world, peer, "Lobby", "Host")
		expect(logged(peer, "DEBUG_UI send Host")):toBe(true)
		noErrors(world)
	end)

	it("joins only with a well-formed code, uppercased", function()
		local world, peer = mountFixture("Lobby", nil)
		local box = need(peer, "Lobby", "CodeBox")
		for _, bad in { "", "AB3", "AB3CDE", "AB10C", "AB-CD" } do
			box.Text = bad
			tap(world, peer, "Lobby", "Join")
		end
		expect(count(peer, "DEBUG_UI send Join")):toBe(0)
		expect(visible(peer, "Lobby", "Toast")):toBe(true)

		box.Text = " ab3cd "
		tap(world, peer, "Lobby", "Join")
		expect(count(peer, "DEBUG_UI send Join")):toBe(1)
		expect(tostring(box.Text)):toBe("AB3CD")
		noErrors(world)
	end)
end)

-- Pick everything but the last issue on the Select fixture.
local function pickMost(world: FakeRoblox.World, peer: FakeRoblox.Peer)
	tap(world, peer, "Select", "Candidate_okafor")
	tap(world, peer, "Select", "Color_Teal")
	tap(world, peer, "Select", "Issue_Jobs")
	tap(world, peer, "Select", "Issue_Health")
end

describe("Select", function()
	it("locks in only with a candidate, a color and three issues", function()
		local world, peer = mountFixture("Select", nil)
		tap(world, peer, "Select", "LockIn")
		expect(logged(peer, "DEBUG_UI submit")):toBe(false)

		pickMost(world, peer)
		tap(world, peer, "Select", "LockIn")
		expect(logged(peer, "DEBUG_UI submit")):toBe(false)
		expect(textOf(peer, "Select", "PlatformHeading")):toBe("3. Platform (2/3)")

		tap(world, peer, "Select", "Issue_Schools")
		tap(world, peer, "Select", "LockIn")
		expect(count(peer, "DEBUG_UI submit")):toBe(1)
		expect(string.find(textOf(peer, "Select", "Status"), "Locked", 1, true) ~= nil):toBe(true)
		expect(textOf(peer, "Select", "LockIn")):toBe("Locked")

		-- Locked is final: a second press submits nothing more.
		tap(world, peer, "Select", "LockIn")
		expect(count(peer, "DEBUG_UI submit")):toBe(1)
		noErrors(world)
	end)

	it("refuses a fourth issue and lets one be taken back", function()
		local world, peer = mountFixture("Select", nil)
		pickMost(world, peer)
		tap(world, peer, "Select", "Issue_Schools")
		tap(world, peer, "Select", "Issue_Safety")
		expect(textOf(peer, "Select", "PlatformHeading")):toBe("3. Platform (3/3)")
		local picked = tostring(need(peer, "Select", "Issue_Jobs").BackgroundColor3)
		expect(tostring(need(peer, "Select", "Issue_Safety").BackgroundColor3) ~= picked):toBe(true)

		tap(world, peer, "Select", "Issue_Jobs")
		expect(textOf(peer, "Select", "PlatformHeading")):toBe("3. Platform (2/3)")
		tap(world, peer, "Select", "Issue_Safety")
		expect(textOf(peer, "Select", "PlatformHeading")):toBe("3. Platform (3/3)")
		noErrors(world)
	end)

	it("counts down to the deadline", function()
		local world, peer = mountFixture("Select", nil)
		local before = textOf(peer, "Select", "Timer")
		FakeRoblox.run(world, 5)
		local after = textOf(peer, "Select", "Timer")
		expect(after ~= before):toBe(true)
		noErrors(world)
	end)

	it("shows every candidate with its perk and drawback", function()
		local world, peer = mountFixture("Select", nil)
		local Candidates = require("@sim/Candidates")
		for _, id in Candidates.ids do
			need(peer, "Select", `Candidate_{id}`)
		end
		for _, name in Candidates.colors do
			need(peer, "Select", `Color_{name}`)
		end
		expect(string.sub(textOf(peer, "Select", "Perk"), 1, 1)):toBe("+")
		expect(string.sub(textOf(peer, "Select", "Drawback"), 1, 1)):toBe("-")
		noErrors(world)
	end)
end)

describe("Results", function()
	it("shows the outcome, both sides and the closest states", function()
		local world, peer = mountFixture("Over", nil)
		local banner = textOf(peer, "Results", "Banner")
		expect(banner == "YOU WON" or banner == "You lost" or banner == "No result"):toBe(true)
		need(peer, "Results", "Player_You")
		need(peer, "Results", "Player_Opponent")
		check(string.find(textOf(peer, "Results", "EV"), " EV", 1, true) ~= nil, "no EV total")
		check(findIn(peer, "Results", "ClosestHeading") ~= nil, "no closest states")
		noErrors(world)
	end)

	it("says Forfeit and Abandoned in words", function()
		local world, peer = mountFixture("Over", nil)
		local store = storeOf(peer)
		local function with(winner: number, reason: string): string
			local payload = table.clone(store.get().payload)
			payload.result = { winner = winner, reason = reason }
			payload.view = table.clone(payload.view)
			payload.view.election = nil
			world.current = peer
			store.setPayload(payload)
			world.current = nil
			FakeRoblox.run(world, 0.3)
			return textOf(peer, "Results", "Banner") .. " | " .. textOf(peer, "Results", "Reason")
		end
		local you = store.get().payload.you
		expect(with(you, "Forfeit")):toBe("YOU WON | Your opponent forfeited the match.")
		local lost = with(3 - you, "Forfeit")
		expect(string.find(lost, "You lost | You forfeited", 1, true) ~= nil):toBe(true)
		local none = with(0, "Abandoned")
		expect(string.find(none, "No result | The match was abandoned", 1, true) ~= nil):toBe(true)
		noErrors(world)
	end)

	it("goes back to the lobby, or straight into another practice match", function()
		local world, peer = mountFixture("Over", nil)
		tap(world, peer, "Results", "BackToLobby")
		check(FakeRoblox.find(peer, "Lobby") ~= nil, "no Lobby after Back to lobby")
		expect(FakeRoblox.find(peer, "Results")):toBe(nil)

		local world2, peer2 = mountFixture("Over", nil)
		expect(textOf(peer2, "Results", "PlayAgain")):toBe("Practice again")
		tap(world2, peer2, "Results", "PlayAgain")
		expect(logged(peer2, "DEBUG_UI send Practice")):toBe(true)
		check(FakeRoblox.find(peer2, "Lobby") ~= nil, "no Lobby after Play again")
		noErrors(world)
		noErrors(world2)
	end)
end)

describe("live: Lobby to Results and back", function()
	it("plays a practice match with autoplay, then returns to the lobby", function()
		local world = newWorld()
		local peer = FakeRoblox.join(world, "P")
		FakeRoblox.run(world, 1)
		check(FakeRoblox.find(peer, "Lobby") ~= nil, "no Lobby at start")

		tap(world, peer, "Lobby", "Practice")
		FakeRoblox.press(world, peer, "Autoplay")
		local over = FakeRoblox.runUntil(world, function()
			return FakeRoblox.find(peer, "Results") ~= nil
		end, MATCH_LIMIT)
		check(over, "the Results screen never appeared")
		FakeRoblox.run(world, 1)
		expect(logged(peer, "UI audit Results: 0 problem(s)")):toBe(true)
		local banner = textOf(peer, "Results", "Banner")
		expect(banner == "YOU WON" or banner == "You lost"):toBe(true)

		tap(world, peer, "Results", "BackToLobby")
		check(FakeRoblox.find(peer, "Lobby") ~= nil, "no Lobby after Back to lobby")
		expect(visible(peer, "Lobby", "Idle")):toBe(true)
		noErrors(world)
	end)

	it("takes a hand-made selection through Select into the match", function()
		local world = newWorld()
		local peer = FakeRoblox.join(world, "P")
		FakeRoblox.run(world, 1)
		tap(world, peer, "Lobby", "Practice")
		check(FakeRoblox.find(peer, "Select") ~= nil, "no Select screen after Practice")
		tap(world, peer, "Select", "Candidate_hale")
		tap(world, peer, "Select", "Color_Cobalt")
		tap(world, peer, "Select", "Issue_Jobs")
		tap(world, peer, "Select", "Issue_Health")
		tap(world, peer, "Select", "Issue_Schools")
		tap(world, peer, "Select", "LockIn")
		-- The bot has locked too, so the server moves on to the map reveal.
		FakeRoblox.run(world, 3)
		expect(FakeRoblox.find(peer, "Select")):toBe(nil)
		expect(logged(peer, "rejected")):toBe(false)
		noErrors(world)
	end)

	it("shows queue and hosting states from the server", function()
		local world = newWorld()
		local peer = FakeRoblox.join(world, "P")
		FakeRoblox.run(world, 1)

		tap(world, peer, "Lobby", "FindMatch")
		check(visible(peer, "Lobby", "Waiting"), "no waiting box while queued")
		expect(visible(peer, "Lobby", "Idle")):toBe(false)
		expect(string.find(textOf(peer, "Lobby", "WaitingText"), "Looking for an opponent", 1, true) ~= nil):toBe(
			true
		)
		tap(world, peer, "Lobby", "Cancel")
		expect(visible(peer, "Lobby", "Idle")):toBe(true)

		tap(world, peer, "Lobby", "Host")
		check(visible(peer, "Lobby", "Waiting"), "no waiting box while hosting")
		expect(visible(peer, "Lobby", "CodeLabel")):toBe(true)
		expect(#textOf(peer, "Lobby", "CodeLabel")):toBe(5)
		tap(world, peer, "Lobby", "Cancel")
		expect(visible(peer, "Lobby", "Idle")):toBe(true)

		-- An unknown code comes back as a toast.
		need(peer, "Lobby", "CodeBox").Text = "ZZZZ9"
		tap(world, peer, "Lobby", "Join")
		expect(string.find(textOf(peer, "Lobby", "Toast"), "No match with that code", 1, true) ~= nil):toBe(
			true
		)
		noErrors(world)
	end)
end)
