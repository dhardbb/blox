--!strict
-- Matchmaking on screen (docs/DESIGN.md D-083), on fixtures: the online count,
-- a bot game while waiting, the match on its way, invites, "Opponent found!
-- Leave this bot game?" over a match screen, and Rematch on Results. Each
-- state is audited (strict UI audit 0) at phone, iPad and desktop.

local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Test = require("@testlib/Test")
local Rig = require("./Rig")

local describe, it, expect = Test.describe, Test.it, Test.expect

local check, tap, textOf = Rig.check, Rig.tap, Rig.textOf
local SIZES = {
	{ x = 844, y = 390 },
	{ x = 1024, y = 768 },
	{ x = 1280, y = 720 },
}

local function strictAudit(world: FakeRoblox.World, peer: FakeRoblox.Peer, screen: string): number
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	return Audit.run(FakeRoblox.find(peer, screen), screen, { strict = true })
end

local function setLobby(world: FakeRoblox.World, peer: FakeRoblox.Peer, lobby: any)
	world.current = peer
	Rig.storeOf(world, peer).setLobby(lobby)
	world.current = nil
	FakeRoblox.run(world, 0.4)
end

local function logged(peer: FakeRoblox.Peer, text: string): boolean
	return Rig.count(peer, text) > 0
end

local function shownIn(peer: FakeRoblox.Peer, screen: string, name: string): boolean
	local inst = Rig.findIn(peer, screen, name)
	return inst ~= nil and Rig.shown(inst, screen)
end

local function lobby(state: string, extra: { [string]: any }): any
	local status = Fixtures.lobby(if state == "Hosting" or state == "Queued" then state :: any else "Idle")
	status.state = state
	for key, value in extra do
		status[key] = value
	end
	return status
end

describe("Lobby: the online count (D-083)", function()
	it("shows 1,234 online when the server knows it, and nothing when it doesn't", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Lobby", size)
			setLobby(world, peer, lobby("Idle", { online = 1234 }))
			check(shownIn(peer, "Lobby", "Online"), "no online count")
			expect(textOf(peer, "Lobby", "Online")):toBe("● 1,234 online")
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
			setLobby(world, peer, lobby("Idle", {}))
			check(not shownIn(peer, "Lobby", "Online"), "an unknown count still shows")
			Rig.noErrors(world)
		end
	end)

	it("puts the count in the queue's hint while waiting", function()
		local world, peer = Rig.fixture("Lobby", Rig.PHONE)
		setLobby(world, peer, lobby("Queued", { online = 87 }))
		expect(textOf(peer, "Lobby", "WaitingHint")):toBe(
			"87 online · you'll start as soon as someone joins."
		)
		check(not shownIn(peer, "Lobby", "Online"), "the count shows twice")
		Rig.noErrors(world)
	end)
end)

describe("Lobby: a bot game while waiting (D-083)", function()
	it("offers it once the server's botAt has passed, and sends WaitBot", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Lobby", size)
			setLobby(world, peer, lobby("Queued", { online = 12, botAt = world.clock + 5 }))
			check(not shownIn(peer, "Lobby", "WaitBot"), "offered too soon")
			FakeRoblox.run(world, 6)
			check(shownIn(peer, "Lobby", "WaitBot"), "never offered")
			check(shownIn(peer, "Lobby", "WaitBotHint"), "no hint under the offer")
			expect(textOf(peer, "Lobby", "WaitBot")):toBe("Play a bot while you wait")
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
			tap(world, peer, "Lobby", "WaitBot")
			check(logged(peer, "DEBUG_UI send WaitBot"), "no WaitBot request")
			Rig.noErrors(world)
		end
	end)
end)

describe("Lobby: the match on its way (D-083)", function()
	it("says what is happening in each phase, with Cancel where it makes sense", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Lobby", size)
			setLobby(
				world,
				peer,
				lobby("Found", { found = { phase = "Waiting", untilAt = world.clock + 12 } })
			)
			expect(textOf(peer, "Lobby", "StartingText")):toBe("Opponent found!")
			check(
				string.find(textOf(peer, "Lobby", "FoundHint"), "12 seconds left", 1, true) ~= nil,
				"no countdown"
			)
			check(shownIn(peer, "Lobby", "FoundCancel"), "no Cancel while waiting")
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
			tap(world, peer, "Lobby", "FoundCancel")
			check(logged(peer, "DEBUG_UI send Leave"), "Cancel did not leave")

			setLobby(world, peer, lobby("Found", { found = { phase = "Joining" } }))
			expect(textOf(peer, "Lobby", "FoundHint")):toBe("Joining the match…")

			setLobby(world, peer, lobby("Found", { found = { phase = "Arriving" }, matchServer = true }))
			expect(textOf(peer, "Lobby", "FoundCancel")):toBe("Back to lobby")
			tap(world, peer, "Lobby", "FoundCancel")
			check(logged(peer, "DEBUG_UI send Return"), "Back to lobby did not Return")

			setLobby(world, peer, lobby("Found", { found = { phase = "Leaving" } }))
			expect(textOf(peer, "Lobby", "StartingText")):toBe("Back to the lobby")
			check(not shownIn(peer, "Lobby", "FoundCancel"), "Cancel while leaving")
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
			Rig.noErrors(world)
		end
	end)
end)

describe("Lobby: invites (D-083)", function()
	it("Invite a friend in the sheet makes a code, then opens the invite with it", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Lobby", size)
			tap(world, peer, "Lobby", "PlayFriend", 0.5)
			check(shownIn(peer, "Lobby", "Invite"), "no Invite in the friend sheet")
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
			tap(world, peer, "Lobby", "Invite")
			check(logged(peer, "DEBUG_UI send Host"), "Invite did not make a code")
			setLobby(world, peer, lobby("Hosting", { code = "QW3RT" }))
			check(logged(peer, "DEBUG_UI invite QW3RT"), "no invite prompt with the code")
			Rig.noErrors(world)
		end
	end)

	it("shows Invite a friend on the code screen", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Lobby", size)
			setLobby(world, peer, lobby("Hosting", { code = "AB3CD" }))
			check(shownIn(peer, "Lobby", "InviteHost"), "no Invite on the code screen")
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
			tap(world, peer, "Lobby", "InviteHost")
			check(logged(peer, "DEBUG_UI invite AB3CD"), "InviteHost did not invite")
			Rig.noErrors(world)
		end
	end)
end)

describe("Opponent found! during a bot game (D-083)", function()
	it("asks over the match screen with a countdown, and answers", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Plan", size)
			setLobby(
				world,
				peer,
				lobby("InMatch", { found = { phase = "Answer", untilAt = world.clock + 15 } })
			)
			local overlay = FakeRoblox.find(peer, "FoundOverlay")
			check(overlay ~= nil and overlay.Visible == true, "no prompt")
			check(
				string.find(textOf(peer, "FoundOverlay", "FoundTime"), "seconds left", 1, true) ~= nil,
				"no countdown"
			)
			expect(textOf(peer, "FoundOverlay", "FoundJoin")):toBe("Join match")
			expect(textOf(peer, "FoundOverlay", "FoundKeep")):toBe("Keep playing")
			local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
			expect(Audit.run(overlay, "FoundOverlay", { strict = true })):toBe(0)
			tap(world, peer, "FoundOverlay", "FoundJoin")
			check(logged(peer, "DEBUG_UI answer true"), "Join did not answer")
			check(overlay.Visible == false, "the prompt stayed open")
			-- A new offer asks again; the server clearing it closes the prompt.
			setLobby(
				world,
				peer,
				lobby("InMatch", { found = { phase = "Answer", untilAt = world.clock + 14 } })
			)
			check(overlay.Visible == true, "a new offer did not ask")
			tap(world, peer, "FoundOverlay", "FoundKeep")
			check(logged(peer, "DEBUG_UI answer false"), "Keep playing did not answer")
			setLobby(
				world,
				peer,
				lobby("InMatch", { found = { phase = "Answer", untilAt = world.clock + 13 } })
			)
			setLobby(world, peer, lobby("InMatch", {}))
			check(overlay.Visible == false, "the prompt outlived the offer")
			Rig.noErrors(world)
		end
	end)
end)

describe("Results: Rematch (D-083)", function()
	-- The Over fixture against a person.
	local function versusPerson(size: { x: number, y: number }): (FakeRoblox.World, FakeRoblox.Peer, any)
		local world, peer = Rig.fixture("Over", size)
		local store = Rig.storeOf(world, peer)
		local payload = Rig.deepCopy(store.get().payload)
		for p, seat in payload.seats do
			if p ~= payload.you then
				seat.kind = "Human"
				seat.difficulty = nil
			end
		end
		world.current = peer
		store.setPayload(payload)
		world.current = nil
		FakeRoblox.run(world, 0.5)
		return world, peer, payload
	end

	local function setRematch(world: FakeRoblox.World, peer: FakeRoblox.Peer, status: any)
		world.current = peer
		Rig.storeOf(world, peer).setRematch(status)
		world.current = nil
		FakeRoblox.run(world, 0.4)
	end

	it("follows the server: asked, waiting, opponent left, expired", function()
		for _, size in SIZES do
			local world, peer, payload = versusPerson(size)
			expect(textOf(peer, "Results", "Rematch")):toBe("Rematch")
			check(Rig.enabled(peer, "Results", "Rematch"), "Rematch disabled at first")
			setRematch(
				world,
				peer,
				{ matchId = payload.matchId, state = "Asked", untilAt = world.clock + 12 }
			)
			check(Rig.enabled(peer, "Results", "Rematch"), "Rematch disabled when asked")
			check(
				string.find(textOf(peer, "Results", "RematchText"), "wants a rematch", 1, true) ~= nil,
				"no ask line" -- a banner over the bar since D-090
			)
			expect(strictAudit(world, peer, "Results")):toBe(0)
			setRematch(
				world,
				peer,
				{ matchId = payload.matchId, state = "Waiting", untilAt = world.clock + 9 }
			)
			expect(textOf(peer, "Results", "Rematch")):toBe("Rematch asked")
			check(not Rig.enabled(peer, "Results", "Rematch"), "Rematch enabled while waiting")
			check(
				string.find(textOf(peer, "Results", "BarStatus"), "Waiting for", 1, true) ~= nil,
				"no waiting line"
			)
			setRematch(world, peer, { matchId = payload.matchId, state = "Gone" })
			expect(textOf(peer, "Results", "Rematch")):toBe("Opponent left")
			check(not Rig.enabled(peer, "Results", "Rematch"), "Rematch enabled after they left")
			expect(strictAudit(world, peer, "Results")):toBe(0)
			setRematch(world, peer, { matchId = payload.matchId, state = "Expired" })
			expect(textOf(peer, "Results", "Rematch")):toBe("Rematch expired")
			-- A status for another match changes nothing here.
			setRematch(world, peer, { matchId = "other", state = "Gone" })
			expect(textOf(peer, "Results", "Rematch")):toBe("Rematch")
			Rig.noErrors(world)
		end
	end)

	it("runs out on screen when the window passes", function()
		local world, peer, payload = versusPerson(Rig.PHONE)
		setRematch(world, peer, { matchId = payload.matchId, state = "Open", untilAt = world.clock + 3 })
		check(Rig.enabled(peer, "Results", "Rematch"), "Rematch disabled while open")
		FakeRoblox.run(world, 4)
		expect(textOf(peer, "Results", "Rematch")):toBe("Rematch expired")
		Rig.noErrors(world)
	end)

	it("sends Rematch, and in a match server Back to lobby goes back to a lobby server", function()
		local world, peer = Rig.fixture("Over", Rig.PHONE)
		tap(world, peer, "Results", "Rematch")
		check(logged(peer, "DEBUG_UI rematch"), "no Rematch request")
		setLobby(world, peer, lobby("Idle", { matchServer = true }))
		tap(world, peer, "Results", "BackToLobby")
		check(logged(peer, "DEBUG_UI send Return"), "no Return from a match server")
		Rig.noErrors(world)
	end)
end)
