--!strict
-- The Name Pass (docs/DESIGN.md D-063) end to end on the fake engine: the real
-- server (MatchService, PassService, NameService, NameEligibility, DataService)
-- and the real client Select screen. Ownership comes from the fake
-- MarketplaceService, eligibility from server/NameEligibility (faked with
-- FakeRoblox.setVerifiedAge: no engine API reports a verified age, so by
-- default nobody is eligible), the filter from the fake TextService (it hides
-- "zork"). A custom name reaches only viewers who are eligible themselves.

local Test = require("@testlib/Test")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Rig = require("./Rig")

local describe, it, expect = Test.describe, Test.it, Test.expect

local PASS = 5551234 -- a made-up pass id for these worlds
local STORE = "PlayerData_v1"
local SIZES = {
	{ x = 390, y = 844 },
	{ x = 1024, y = 768 },
	{ x = 1280, y = 720 },
}

local check = Rig.check

type Options = {
	passId: number?, -- default PASS; 0 turns the pass off
	owns: boolean?,
	age: number?, -- the verified age NameEligibility reports; nil = unknown (not eligible)
	saved: any?,
}

-- Sets up one player's pass, age and saved profile before they join, then joins them.
local function joinWith(world: FakeRoblox.World, name: string, options: Options): FakeRoblox.Peer
	local userId = world.nextUserId
	if options.owns then
		FakeRoblox.setOwnsPass(world, userId, PASS, true)
	end
	if options.saved then
		world.data.stores[STORE] = world.data.stores[STORE] or {}
		world.data.stores[STORE][`Player_{userId}`] = { data = options.saved }
	end
	return FakeRoblox.join(world, name)
end

local function live(seed: number, options: Options): (FakeRoblox.World, FakeRoblox.Peer)
	local world = Rig.newWorld(seed)
	FakeRoblox.setNamePass(world, options.passId or PASS)
	FakeRoblox.setVerifiedAge(world, if options.age then { [world.nextUserId] = options.age } else {})
	local peer = joinWith(world, "A", options)
	FakeRoblox.run(world, 12) -- loads, checks, the saved name's filter
	return world, peer
end

local function practice(world: FakeRoblox.World, peer: FakeRoblox.Peer): any
	Rig.tap(world, peer, "Lobby", "Practice", 1)
	local payload = Rig.payloadOf(world, peer)
	check(payload ~= nil, "the practice match did not start")
	return payload
end

local function rejected(world: FakeRoblox.World, peer: FakeRoblox.Peer, reason: string): boolean
	for _, message in Rig.storeOf(world, peer).get().messages do
		if message.rejected and message.reason == reason then
			return true
		end
	end
	return false
end

local function setName(world: FakeRoblox.World, peer: FakeRoblox.Peer, name: string?)
	FakeRoblox.fire(world, peer, { op = "SetName", name = name })
	FakeRoblox.run(world, 1)
end

local function mine(world: FakeRoblox.World, peer: FakeRoblox.Peer): string?
	local payload = Rig.payloadOf(world, peer)
	return payload.view.players[payload.you].customName
end

local function savedName(world: FakeRoblox.World, userId: number): string?
	FakeRoblox.run(world, 2) -- let the save land
	local record = world.data.stores[STORE][`Player_{userId}`]
	return if record then record.data.customName else nil
end

describe("Name Pass: who may use it (D-063)", function()
	it("is hidden everywhere while the pass id is 0", function()
		local world, peer =
			live(1, { passId = 0, owns = true, age = 30, saved = { customName = "Captain Zed" } })
		local payload = practice(world, peer)
		expect(payload.naming):toBe(nil)
		expect(mine(world, peer)):toBe(nil)
		expect(Rig.shown(Rig.need(peer, "Select", "NameRow"), "Select")):toBe(false)
		setName(world, peer, "Big Wave")
		expect(rejected(world, peer, "NoNamePass")):toBe(true)
		expect(world.text.calls):toBe(0)
		Rig.noErrors(world)
	end)

	it("fails closed: with no verified age, an owner cannot buy, set or see a name", function()
		local world, peer = live(2, { owns = true, saved = { customName = "Captain Zed" } })
		local payload = practice(world, peer)
		expect(payload.naming):toBe(nil)
		expect(mine(world, peer)):toBe(nil)
		expect(Rig.shown(Rig.need(peer, "Select", "NameRow"), "Select")):toBe(false)
		setName(world, peer, "Big Wave")
		expect(rejected(world, peer, "NameNotEligible")):toBe(true)
		expect(world.text.calls):toBe(0)
		Rig.noErrors(world)
	end)

	it("turns down a verified 15-year-old", function()
		local world, peer = live(3, { owns = true, age = 15 })
		expect(practice(world, peer).naming):toBe(nil)
		setName(world, peer, "Big Wave")
		expect(rejected(world, peer, "NameNotEligible")):toBe(true)
		Rig.noErrors(world)
	end)
end)

describe("Name Pass: setting a name (D-063)", function()
	it("names an eligible owner's candidate, saves it, and never names the bot", function()
		local world, peer = live(4, { owns = true, age = 16 })
		local payload = practice(world, peer)
		check(payload.naming ~= nil, "no naming for an eligible owner")
		expect(payload.naming.id):toBe(PASS)
		expect(payload.naming.owned):toBe(true)
		setName(world, peer, "  Captain   Zed ")
		expect(mine(world, peer)):toBe("Captain Zed")
		payload = Rig.payloadOf(world, peer)
		expect(payload.naming.name):toBe("Captain Zed")
		expect(payload.view.players[if payload.you == 1 then 2 else 1].customName):toBe(nil)
		expect(world.text.contexts[#world.text.contexts]):toBe("PublicChat")
		expect(savedName(world, 1)):toBe("Captain Zed")
		-- Back to the candidate's own name.
		setName(world, peer, nil)
		expect(mine(world, peer)):toBe(nil)
		expect(savedName(world, 1)):toBe(nil)
		Rig.noErrors(world)
	end)

	it("turns down filtered, empty, too long and bad names, and keeps the old one", function()
		local world, peer = live(5, { owns = true, age = 20 })
		practice(world, peer)
		setName(world, peer, "Captain Zed")
		local before = world.text.calls
		for _, case in
			{
				{ "The Zork", "NameFiltered" },
				{ "   ", "NameEmpty" },
				{ string.rep("x", 17), "NameTooLong" },
				{ "Zed #1", "NameBadText" },
			}
		do
			setName(world, peer, case[1])
			check(rejected(world, peer, case[2]), `{case[1]} was not turned down with {case[2]}`)
			expect(mine(world, peer)):toBe("Captain Zed")
		end
		-- Only the first reached the filter: the rest never left the server's own checks.
		expect(world.text.calls):toBe(before + 1)
		expect(savedName(world, 1)):toBe("Captain Zed")
		Rig.noErrors(world)
	end)

	it("fails closed when the filter cannot be reached", function()
		local world, peer = live(6, { owns = true, age = 20 })
		practice(world, peer)
		world.text.failures = 1
		setName(world, peer, "Captain Zed")
		expect(rejected(world, peer, "NameFilterFailed")):toBe(true)
		expect(mine(world, peer)):toBe(nil)
		Rig.noErrors(world)
	end)

	it("turns down a name on the server's blocklist before the filter", function()
		local world, peer = live(7, { owns = true, age = 20 })
		FakeRoblox.setModuleField(world, "src/server/NameService.luau", "BLOCKLIST", { "Grumble" })
		practice(world, peer)
		local before = world.text.calls
		setName(world, peer, "Mr GRUMBLE")
		expect(rejected(world, peer, "NameFiltered")):toBe(true)
		expect(world.text.calls):toBe(before)
		expect(mine(world, peer)):toBe(nil)
		Rig.noErrors(world)
	end)

	it("filters a saved name again when the player joins", function()
		local world, peer = live(8, { owns = true, age = 20, saved = { customName = "Zork" } })
		expect(practice(world, peer).naming.name):toBe(nil)
		expect(mine(world, peer)):toBe(nil)
		local other, again = live(9, { owns = true, age = 20, saved = { customName = "Captain Zed" } })
		expect(practice(other, again).naming.name):toBe("Captain Zed")
		expect(mine(other, again)):toBe("Captain Zed")
		Rig.noErrors(world)
		Rig.noErrors(other)
	end)

	it("only changes the match during Select; later it is saved for the next match", function()
		local world, peer = live(10, { owns = true, age = 20 })
		practice(world, peer)
		Rig.tap(world, peer, "Select", "Candidate_hale")
		Rig.tap(world, peer, "Select", "LockIn", 1)
		for _, issue in { "Jobs", "Health", "Schools" } do
			Rig.tap(world, peer, "Select", `Issue_{issue}`)
		end
		Rig.tap(world, peer, "Select", "LockIn", 1)
		FakeRoblox.run(world, 45)
		check(Rig.payloadOf(world, peer).view.phase ~= "Select", "Select did not end")
		setName(world, peer, "Captain Zed")
		expect(mine(world, peer)):toBe(nil)
		expect(savedName(world, 1)):toBe("Captain Zed")
		Rig.noErrors(world)
	end)
end)

describe("Name Pass: who sees a name (D-063)", function()
	-- Two players queue into one match: A eligible and named, B as given.
	local function pair(seed: number, bAge: number?): (FakeRoblox.World, FakeRoblox.Peer, FakeRoblox.Peer)
		local world = Rig.newWorld(seed)
		FakeRoblox.setNamePass(world, PASS)
		local first = world.nextUserId
		FakeRoblox.setVerifiedAge(world, { [first] = 30, [first + 1] = bAge :: any })
		local a = joinWith(world, "A", { owns = true, saved = { customName = "Captain Zed" } })
		local b = joinWith(world, "B", {})
		FakeRoblox.run(world, 12)
		FakeRoblox.fire(world, a, { op = "Queue" })
		FakeRoblox.fire(world, b, { op = "Queue" })
		FakeRoblox.run(world, 2)
		check(Rig.payloadOf(world, a) ~= nil and Rig.payloadOf(world, b) ~= nil, "the match did not start")
		return world, a, b
	end

	local function nameOfA(world: FakeRoblox.World, viewer: FakeRoblox.Peer, a: FakeRoblox.Peer): string?
		local seatA = Rig.payloadOf(world, a).you
		return Rig.payloadOf(world, viewer).view.players[seatA].customName
	end

	it("shows A's name to A and to an eligible opponent", function()
		local world, a, b = pair(11, 18)
		expect(nameOfA(world, a, a)):toBe("Captain Zed")
		expect(nameOfA(world, b, a)):toBe("Captain Zed")
		-- B may use the pass too (eligible), but does not own it.
		expect(Rig.payloadOf(world, b).naming.owned):toBe(false)
		Rig.noErrors(world)
	end)

	it("never sends A's name to an opponent who is not verified 16+", function()
		local world, a, b = pair(12, nil)
		expect(nameOfA(world, a, a)):toBe("Captain Zed")
		expect(nameOfA(world, b, a)):toBe(nil)
		expect(Rig.payloadOf(world, b).naming):toBe(nil)
		-- A new name during Select reaches A only.
		setName(world, a, "Big Wave")
		expect(nameOfA(world, a, a)):toBe("Big Wave")
		expect(nameOfA(world, b, a)):toBe(nil)
		Rig.noErrors(world)
	end)
end)

describe("Name Pass: Select (D-063)", function()
	it("offers the pass to an eligible player without it, and Rename after the purchase", function()
		local world, peer = live(13, { owns = false, age = 25 })
		practice(world, peer)
		Rig.tap(world, peer, "Select", "Candidate_okafor")
		check(Rig.shown(Rig.need(peer, "Select", "NameRow"), "Select"), "no name line for an eligible player")
		local button = Rig.need(peer, "Select", "NameButton")
		expect(tostring(button.Text)):toBe("Get the Name Pass")
		Rig.tap(world, peer, "Select", "NameButton", 0.5)
		expect(#world.market.prompts):toBe(1)
		expect(world.market.prompts[1].passId):toBe(PASS)
		FakeRoblox.finishPassPurchase(world, peer, PASS, true)
		FakeRoblox.run(world, 1)
		expect(Rig.payloadOf(world, peer).naming.owned):toBe(true)
		expect(tostring(button.Text)):toBe("Rename")
		-- Rename, type, save: the real server filters it and the line follows.
		Rig.tap(world, peer, "Select", "NameButton", 0.5)
		check(Rig.need(peer, "Select", "NameSheet").Visible == true, "the name sheet did not open")
		Rig.need(peer, "Select", "NameBox").Text = "Captain Zed"
		Rig.tap(world, peer, "Select", "NameSave", 1)
		expect(mine(world, peer)):toBe("Captain Zed")
		expect(tostring(Rig.need(peer, "Select", "NameLine").Text)):toBe("Name: Captain Zed")
		expect(Rig.need(peer, "Select", "NameSheet").Visible):toBe(false)
		-- A filtered name: the sheet stays open and says why.
		Rig.tap(world, peer, "Select", "NameButton", 0.5)
		Rig.need(peer, "Select", "NameBox").Text = "Zork"
		Rig.tap(world, peer, "Select", "NameSave", 1)
		check(Rig.need(peer, "Select", "NameSheet").Visible == true, "the sheet closed on a refusal")
		expect(tostring(Rig.need(peer, "Select", "NameStatus").Text)):toBe(
			"That name isn't allowed. Try another name."
		)
		expect(mine(world, peer)):toBe("Captain Zed")
		Rig.noErrors(world)
	end)

	it("stops typing at the limit", function()
		local world, peer = Rig.fixture("SelectName", nil)
		local box = Rig.need(peer, "Select", "NameBox")
		box.Text = string.rep("a", 20)
		FakeRoblox.run(world, 0.1)
		expect(#tostring(box.Text)):toBe(16)
	end)

	it("shows the opponent's custom name, and the name line, at every size with a clean audit", function()
		for _, screen in SIZES do
			local world, peer = Rig.fixture("SelectName", screen)
			Rig.tap(world, peer, "Select", "Candidate_okafor")
			expect(tostring(Rig.need(peer, "Select", "NameLine").Text)):toBe(`Name: {Fixtures.YOUR_NAME}`)
			local opponent = Rig.need(peer, "Select", "BarOpponent")
			check(
				string.find(tostring(opponent.Text), Fixtures.THEIR_NAME, 1, true) ~= nil,
				`the opponent line says {opponent.Text}`
			)
			local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
			expect(Audit.run(Rig.need(peer, "Screens", "Select"), "Select", { strict = true })):toBe(0)
			Rig.noErrors(world)
		end
	end)
end)
