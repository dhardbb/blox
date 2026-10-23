--!strict
-- The Color Pass (docs/DESIGN.md D-055) end to end on the fake engine: the real
-- server (MatchService, PassService, DataService) and the real client Lobby.
-- Ownership comes from the fake MarketplaceService (world.market), never the
-- client; a saved color counts only for an owner; a failed check falls back to
-- red or blue; a pass id of 0 hides the option everywhere. Also the sheet's
-- locked and owned states offline, with a clean UI audit at every size.

local Test = require("@testlib/Test")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Rig = require("./Rig")

local describe, it, expect = Test.describe, Test.it, Test.expect

local PASS = 9876543 -- a made-up pass id for these worlds
local STORE = "PlayerData_v1"
local SIZES = {
	{ x = 390, y = 844 },
	{ x = 1024, y = 768 },
	{ x = 1280, y = 720 },
}

local check = Rig.check

-- A live world with the pass set up (or not), the player's ownership and any
-- saved profile in place before they join.
local function live(
	seed: number,
	options: { passId: number?, owns: boolean?, saved: any?, failures: number? }
): (FakeRoblox.World, FakeRoblox.Peer)
	local world = Rig.newWorld(seed)
	FakeRoblox.setColorPass(world, options.passId or 0)
	local userId = world.nextUserId
	if options.owns then
		FakeRoblox.setOwnsPass(world, userId, PASS, true)
	end
	if options.saved then
		world.data.stores[STORE] = { [`Player_{userId}`] = { data = options.saved } }
	end
	world.market.failures = options.failures or 0
	local peer = FakeRoblox.join(world, "A")
	FakeRoblox.run(world, 12) -- loads, checks and any retries (2 s + 4 s)
	return world, peer
end

local function lobbyOf(world: FakeRoblox.World, peer: FakeRoblox.Peer): any
	return Rig.storeOf(world, peer).get().lobby
end

local function savedColor(world: FakeRoblox.World, userId: number): string?
	FakeRoblox.run(world, 2) -- let the save land
	local record = world.data.stores[STORE][`Player_{userId}`]
	return if record then record.data.color else nil
end

-- Presses Practice and returns this player's color in the match.
local function practiceColor(world: FakeRoblox.World, peer: FakeRoblox.Peer): string
	Rig.tap(world, peer, "Lobby", "Practice", 1)
	local payload = Rig.payloadOf(world, peer)
	check(payload ~= nil, "the practice match did not start")
	return payload.view.players[payload.you].color
end

-- The Lobby's Color button label ("Color: …").
local function buttonText(peer: FakeRoblox.Peer): string
	local label = Rig.need(peer, "Lobby", "ColorButton"):FindFirstChild("Label", true)
	check(label ~= nil, "the Color button has no label")
	return tostring(label.Text)
end

-- Strict UI audit of the Lobby (every layout and style rule), as the snaps run it.
local function strictAudit(world: FakeRoblox.World, peer: FakeRoblox.Peer): number
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	return Audit.run(Rig.need(peer, "Screens", "Lobby"), "Lobby", { strict = true })
end

local function rejected(world: FakeRoblox.World, peer: FakeRoblox.Peer, reason: string): boolean
	for _, message in Rig.storeOf(world, peer).get().messages do
		if message.rejected and message.reason == reason then
			return true
		end
	end
	return false
end

describe("Color Pass: server (D-055)", function()
	it("is hidden everywhere while the pass id is 0, and matches deal red or blue", function()
		local world, peer = live(1, { passId = 0, owns = true, saved = { color = "Emerald" } })
		local lobby = lobbyOf(world, peer)
		check(lobby ~= nil, "no lobby status")
		expect(lobby.colorPass):toBe(nil)
		expect(Rig.shown(Rig.need(peer, "Lobby", "ColorButton"), "Lobby")):toBe(false)
		expect(world.market.checks):toBe(0)
		FakeRoblox.fire(world, peer, { op = "SetColor", color = "Teal" })
		FakeRoblox.run(world, 0.5)
		expect(rejected(world, peer, "NoColorPass")):toBe(true)
		local color = practiceColor(world, peer)
		expect(color == "Crimson" or color == "Cobalt"):toBe(true)
		Rig.noErrors(world)
	end)

	it("gives an owner their saved color in the match, and the bot red or blue", function()
		local world, peer = live(2, { passId = PASS, owns = true })
		local lobby = lobbyOf(world, peer)
		check(lobby.colorPass ~= nil, "no colorPass in the lobby status")
		expect(lobby.colorPass.id):toBe(PASS)
		expect(lobby.colorPass.owned):toBe(true)
		Rig.tap(world, peer, "Lobby", "ColorButton")
		Rig.tap(world, peer, "Lobby", "Swatch_Emerald", 1)
		expect(lobbyOf(world, peer).color):toBe("Emerald")
		expect(savedColor(world, 1)):toBe("Emerald")
		check(
			Rig.findIn(peer, "Lobby", "Swatch_Emerald"):GetAttribute("Selected") == true,
			"no outline on the pick"
		)
		expect(practiceColor(world, peer)):toBe("Emerald")
		local payload = Rig.payloadOf(world, peer)
		local bot = payload.view.players[if payload.you == 1 then 2 else 1].color
		expect(bot == "Crimson" or bot == "Cobalt"):toBe(true)
		Rig.noErrors(world)
	end)

	it("lets an owner claim another color in Select, and turns a non-owner down (D-061)", function()
		local world, peer = live(8, { passId = PASS, owns = true, saved = { color = "Teal" } })
		expect(practiceColor(world, peer)):toBe("Teal")
		local payload = Rig.payloadOf(world, peer)
		expect(payload.view.canPickColor):toBe(true)
		expect(payload.view.colorClaims.Teal):toBe(payload.you)
		FakeRoblox.fire(
			world,
			peer,
			{ op = "ClaimColor", matchId = payload.matchId, step = payload.step, color = "Violet" }
		)
		FakeRoblox.run(world, 0.5)
		payload = Rig.payloadOf(world, peer)
		expect(payload.view.players[payload.you].color):toBe("Violet")
		expect(payload.view.colorClaims):toEqual({ Violet = payload.you })
		Rig.noErrors(world)

		local other, stranger = live(9, { passId = PASS, owns = false })
		practiceColor(other, stranger)
		local theirs = Rig.payloadOf(other, stranger)
		expect(theirs.view.canPickColor):toBe(false)
		FakeRoblox.fire(
			other,
			stranger,
			{ op = "ClaimColor", matchId = theirs.matchId, step = theirs.step, color = "Violet" }
		)
		FakeRoblox.run(other, 0.5)
		expect(rejected(other, stranger, "NoColorPass")):toBe(true)
		local color = Rig.payloadOf(other, stranger).view.players[theirs.you].color
		expect(color == "Crimson" or color == "Cobalt"):toBe(true)
		Rig.noErrors(other)
	end)

	it("Auto clears the pick", function()
		local world, peer = live(3, { passId = PASS, owns = true, saved = { color = "Violet" } })
		expect(lobbyOf(world, peer).color):toBe("Violet")
		Rig.tap(world, peer, "Lobby", "ColorButton")
		Rig.tap(world, peer, "Lobby", "Swatch_Auto", 1)
		expect(lobbyOf(world, peer).color):toBe(nil)
		expect(savedColor(world, 1)):toBe(nil)
		Rig.noErrors(world)
	end)

	it("ignores a saved color when the player does not own the pass", function()
		local world, peer = live(4, { passId = PASS, owns = false, saved = { color = "Amber" } })
		local lobby = lobbyOf(world, peer)
		expect(lobby.colorPass.owned):toBe(false)
		expect(buttonText(peer)):toBe("Color: red or blue")
		-- The client cannot talk its way in: the server asks Roblox again and refuses.
		FakeRoblox.fire(world, peer, { op = "SetColor", color = "Teal" })
		FakeRoblox.run(world, 1)
		expect(rejected(world, peer, "NoColorPass")):toBe(true)
		expect(savedColor(world, 1)):toBe("Amber")
		local color = practiceColor(world, peer)
		expect(color == "Crimson" or color == "Cobalt"):toBe(true)
		Rig.noErrors(world)
	end)

	it("falls back to red or blue when the ownership check fails, without an error", function()
		local world, peer = live(5, { passId = PASS, owns = true, saved = { color = "Teal" }, failures = 3 })
		expect(world.market.checks):toBe(3)
		expect(lobbyOf(world, peer).colorPass.owned):toBe(false)
		local color = practiceColor(world, peer)
		expect(color == "Crimson" or color == "Cobalt"):toBe(true)
		Rig.noErrors(world)
	end)

	it("retries a failed check: one failure, then the owner is known", function()
		local world, peer = live(6, { passId = PASS, owns = true, saved = { color = "Teal" }, failures = 1 })
		expect(world.market.checks):toBe(2)
		expect(lobbyOf(world, peer).colorPass.owned):toBe(true)
		expect(practiceColor(world, peer)):toBe("Teal")
		Rig.noErrors(world)
	end)

	it("rejects a color that is not one of the six and keeps the saved one", function()
		local world, peer = live(7, { passId = PASS, owns = true, saved = { color = "Cobalt" } })
		for _, bad in { "Gold", "crimson", "" } do
			FakeRoblox.fire(world, peer, { op = "SetColor", color = bad })
			FakeRoblox.run(world, 0.3)
		end
		FakeRoblox.fire(world, peer, { op = "SetColor", color = 5 })
		FakeRoblox.run(world, 0.3)
		expect(rejected(world, peer, "UnknownColor")):toBe(true)
		expect(rejected(world, peer, "BadShape")):toBe(true)
		expect(savedColor(world, 1)):toBe("Cobalt")
		Rig.noErrors(world)
	end)

	it("buys the pass from the sheet: the prompt opens, a purchase unlocks the swatches", function()
		local world, peer = live(8, { passId = PASS, owns = false })
		Rig.tap(world, peer, "Lobby", "ColorButton")
		check(Rig.findIn(peer, "Lobby", "Swatch_Teal"):GetAttribute("Locked") == true, "swatches not locked")
		-- Tapping a locked swatch sends nothing.
		Rig.tap(world, peer, "Lobby", "Swatch_Teal")
		expect(lobbyOf(world, peer).color):toBe(nil)
		Rig.tap(world, peer, "Lobby", "BuyColorPass")
		expect(#world.market.prompts):toBe(1)
		expect(world.market.prompts[1].passId):toBe(PASS)
		-- Cancelled: still locked.
		FakeRoblox.finishPassPurchase(world, peer, PASS, false)
		FakeRoblox.run(world, 0.5)
		expect(lobbyOf(world, peer).colorPass.owned):toBe(false)
		FakeRoblox.finishPassPurchase(world, peer, PASS, true)
		FakeRoblox.run(world, 0.5)
		expect(lobbyOf(world, peer).colorPass.owned):toBe(true)
		check(
			Rig.findIn(peer, "Lobby", "Swatch_Teal"):GetAttribute("Locked") == false,
			"still locked after buying"
		)
		Rig.tap(world, peer, "Lobby", "Swatch_Teal", 1)
		expect(lobbyOf(world, peer).color):toBe("Teal")
		expect(practiceColor(world, peer)):toBe("Teal")
		Rig.noErrors(world)
	end)

	it("loads an old profile without a color as auto, and keeps its record", function()
		local old =
			{ version = 1, rating = 1040, games = 3, wins = 2, losses = 1, perCandidate = {}, recent = {} }
		local world, peer = live(9, { passId = PASS, owns = true, saved = old })
		local lobby = lobbyOf(world, peer)
		expect(lobby.color):toBe(nil)
		expect(lobby.profile.rating):toBe(1040)
		local color = practiceColor(world, peer)
		expect(color == "Crimson" or color == "Cobalt"):toBe(true)
		Rig.noErrors(world)
	end)
end)

describe("Color Pass: the sheet (D-055)", function()
	local function offline(size: { x: number, y: number }, pass: ("locked" | "owned")?, color: string?): any
		local world, peer = Rig.fixture("Lobby", size)
		world.current = peer
		Rig.storeOf(world, peer).setLobby(Fixtures.lobby("Idle", { colorPass = pass, color = color }))
		world.current = nil
		FakeRoblox.run(world, 0.5)
		return world, peer
	end

	it("shows the button only when the lobby status carries the pass", function()
		local world, peer = Rig.fixture("Lobby", Rig.PHONE)
		expect(Rig.shown(Rig.need(peer, "Lobby", "ColorButton"), "Lobby")):toBe(false)
		world, peer = offline(Rig.PHONE, "locked")
		expect(Rig.shown(Rig.need(peer, "Lobby", "ColorButton"), "Lobby")):toBe(true)
		Rig.noErrors(world)
	end)

	it("locked: greyed swatches on Auto, one line and a buy button; audit clean at every size", function()
		for _, size in SIZES do
			local world, peer = offline(size, "locked", "Violet")
			Rig.tap(world, peer, "Lobby", "ColorButton")
			expect(Rig.textOf(peer, "Lobby", "ColorHint")):toBe("Pick your color with the Color Pass.")
			expect(Rig.shown(Rig.need(peer, "Lobby", "BuyColorPass"), "Lobby")):toBe(true)
			expect(Rig.shown(Rig.need(peer, "Lobby", "ColorTie"), "Lobby")):toBe(false)
			check(Rig.need(peer, "Lobby", "Swatch_Auto"):GetAttribute("Selected") == true, "Auto not marked")
			check(
				Rig.need(peer, "Lobby", "Swatch_Violet"):GetAttribute("Selected") ~= true,
				"a locked pick shows"
			)
			check(not Rig.enabled(peer, "Lobby", "Swatch_Crimson"), "a locked swatch is enabled")
			local problems = Rig.audit(peer, "Lobby")
			check(#problems == 0, `{size.x}x{size.y}: ` .. table.concat(problems, " | "))
			expect(strictAudit(world, peer)):toBe(0)
			Rig.noErrors(world)
		end
	end)

	it("owned: the pick outlined, no buy button, a tap saves; audit clean at every size", function()
		for _, size in SIZES do
			local world, peer = offline(size, "owned", "Emerald")
			expect(buttonText(peer)):toBe("Color: Emerald")
			Rig.tap(world, peer, "Lobby", "ColorButton")
			expect(Rig.shown(Rig.need(peer, "Lobby", "BuyColorPass"), "Lobby")):toBe(false)
			check(
				Rig.need(peer, "Lobby", "Swatch_Emerald"):GetAttribute("Selected") == true,
				"pick not marked"
			)
			Rig.tap(world, peer, "Lobby", "Swatch_Cobalt")
			expect(Rig.storeOf(world, peer).get().lobby.color):toBe("Cobalt")
			check(
				Rig.need(peer, "Lobby", "Swatch_Cobalt"):GetAttribute("Selected") == true,
				"new pick not marked"
			)
			local problems = Rig.audit(peer, "Lobby")
			check(#problems == 0, `{size.x}x{size.y}: ` .. table.concat(problems, " | "))
			expect(strictAudit(world, peer)):toBe(0)
			Rig.noErrors(world)
		end
	end)
end)
