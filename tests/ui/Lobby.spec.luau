--!strict
-- The Lobby, Select and Results screens on the fake Roblox engine: fixtures
-- render offline with a clean UI audit, the controls do what they say, and a
-- live practice match runs from the Lobby to the Results screen and back. Also
-- the v0.3.1 bug-hunt cases for the Lobby: message ids, the toast, the page
-- padding, and a full server that never locks the buttons; and the UI overhaul
-- (WP2, docs/UI-OVERHAUL.md §3.1): one accent button, the global toast only.

local process = require("@lune/process")

local Test = require("@testlib/Test")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Rig = require("./Rig")

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

-- The global toast's text while it shows, or nil (the Lobby has no toast of its own).
local function toastText(peer: FakeRoblox.Peer): string?
	local layer = FakeRoblox.find(peer, "ToastLayer")
	local frame = if layer then layer:FindFirstChild("Toast") else nil
	if frame == nil or frame.Visible == false then
		return nil
	end
	return tostring(frame:FindFirstChild("ToastText").Text)
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
		expect(toastText(peer)):toBe("Enter the 5-character code: letters A-Z and numbers 2-9.")

		box.Text = " ab3cd "
		tap(world, peer, "Lobby", "Join")
		expect(count(peer, "DEBUG_UI send Join")):toBe(1)
		expect(tostring(box.Text)):toBe("AB3CD")
		noErrors(world)
	end)
end)

-- Pick everything but the last issue on the Select fixture: claim a candidate
-- (step 1, D-045), then two issues.
local function pickMost(world: FakeRoblox.World, peer: FakeRoblox.Peer)
	tap(world, peer, "Select", "Candidate_okafor")
	tap(world, peer, "Select", "LockIn")
	tap(world, peer, "Select", "Issue_Jobs")
	tap(world, peer, "Select", "Issue_Health")
end

describe("Select", function()
	it("locks in only with a candidate and three issues", function()
		local world, peer = mountFixture("Select", nil)
		tap(world, peer, "Select", "LockIn")
		expect(logged(peer, "DEBUG_UI submit")):toBe(false)

		pickMost(world, peer)
		tap(world, peer, "Select", "LockIn")
		expect(logged(peer, "DEBUG_UI submit")):toBe(false)
		expect(textOf(peer, "Select", "PlatformHeading")):toBe("2. Issues for Dana Okafor (2/3)")

		tap(world, peer, "Select", "Issue_Schools")
		tap(world, peer, "Select", "LockIn")
		expect(count(peer, "DEBUG_UI submit")):toBe(1)
		expect(textOf(peer, "Select", "BarStatus")):toBe("Locked in · waiting for opponent")
		expect(textOf(peer, "Select", "LockIn")):toBe("Locked in")

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
		expect(textOf(peer, "Select", "PlatformHeading")):toBe("2. Issues for Dana Okafor (3/3)")
		local picked = tostring(need(peer, "Select", "Issue_Jobs").BackgroundColor3)
		expect(tostring(need(peer, "Select", "Issue_Safety").BackgroundColor3) ~= picked):toBe(true)

		tap(world, peer, "Select", "Issue_Jobs")
		expect(textOf(peer, "Select", "PlatformHeading")):toBe("2. Issues for Dana Okafor (2/3)")
		tap(world, peer, "Select", "Issue_Safety")
		expect(textOf(peer, "Select", "PlatformHeading")):toBe("2. Issues for Dana Okafor (3/3)")
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
		need(peer, "Select", "ColorLine")
		expect(string.sub(textOf(peer, "Select", "Perk"), 1, 1)):toBe("+")
		expect(string.sub(textOf(peer, "Select", "Drawback"), 1, 3)):toBe("−")
		noErrors(world)
	end)
end)

describe("Results", function()
	it("shows the outcome, both sides and the closest states", function()
		local world, peer = mountFixture("Over", nil)
		local banner = textOf(peer, "Results", "Banner")
		expect(banner == "You won" or banner == "You lost" or banner == "No result"):toBe(true)
		need(peer, "Results", "Player_You")
		need(peer, "Results", "Player_Opponent")
		check(string.find(textOf(peer, "Results", "EV"), " EV", 1, true) ~= nil, "no EV total")
		check(findIn(peer, "Results", "Closest") ~= nil, "no closest states")
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
		expect(with(you, "Forfeit")):toBe("You won | Your opponent forfeited the match.")
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
		expect(textOf(peer2, "Results", "PlayAgain")):toBe("Play vs Bot again")
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
		expect(banner == "You won" or banner == "You lost"):toBe(true)

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
		Rig.claim(world, peer)
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
		expect(string.find(toastText(peer) or "", "No match with that code", 1, true) ~= nil):toBe(true)
		noErrors(world)
	end)
end)

-- ------------------------------------------------------------------ v0.3.1 bug hunt
-- (moved here from ClientFixes.spec when it was split per screen)

describe("Lobby messages are told apart by id", function()
	it("keeps counting past the size of the log", function()
		local world, peer = Rig.practice(3)
		local store = Rig.storeOf(world, peer)
		local last = 0
		for k = 1, 30 do
			store.say(`message {k}`)
			local messages = store.get().messages
			local newest = messages[#messages]
			check(type(newest) == "table" and newest.text == `message {k}`, "newest message is wrong")
			check(newest.id > last, "ids do not grow")
			last = newest.id
		end
		Rig.noErrors(world)
	end)

	it("toasts every Lobby rejection, not only the first 20", function()
		local world, peer = Rig.practice(3)
		local box = Rig.need(peer, "Lobby", "CodeBox")
		for k = 1, 24 do
			box.Text = "ZZZZ9"
			Rig.tap(world, peer, "Lobby", "Join", 0.3)
			check(toastText(peer) ~= nil, `no toast for attempt {k}`)
			FakeRoblox.run(world, 5)
			check(toastText(peer) == nil, "the toast never went away")
		end
		Rig.noErrors(world)
	end)
end)

describe("Lobby keeps no space for a Debug button", function()
	it("does not pad the bottom of the Lobby page", function()
		local _, peer = Rig.fixture("Lobby", Rig.PHONE)
		local content = Rig.need(peer, "Lobby", "Content")
		expect(content:FindFirstChildOfClass("UIPadding").PaddingBottom.Offset <= 16):toBe(true)
	end)
end)

describe("A full server never locks the Lobby", function()
	it("keeps the banner as information and the buttons working", function()
		local world, peer = Rig.fixture("Lobby", nil)
		local full = Fixtures.lobby("Idle")
		full.full = true
		world.current = peer
		Rig.storeOf(world, peer).setLobby(full)
		world.current = nil
		FakeRoblox.run(world, 0.3)
		check(Rig.shown(Rig.need(peer, "Lobby", "ServerFull"), "Lobby"), "no server full banner")
		for _, name in { "Practice", "FindMatch", "Host", "Join" } do
			check(Rig.enabled(peer, "Lobby", name), `{name} is disabled while the status says full`)
		end
		Rig.tap(world, peer, "Lobby", "Practice")
		expect(Rig.count(peer, "DEBUG_UI send Practice")):toBe(1)
		Rig.tap(world, peer, "Lobby", "FindMatch")
		expect(Rig.count(peer, "DEBUG_UI send Queue")):toBe(1)
		Rig.tap(world, peer, "Lobby", "Host")
		expect(Rig.count(peer, "DEBUG_UI send Host")):toBe(1)
		Rig.need(peer, "Lobby", "CodeBox").Text = "AB3CD"
		Rig.tap(world, peer, "Lobby", "Join")
		expect(Rig.count(peer, "DEBUG_UI send Join")):toBe(1)
		Rig.noErrors(world)
	end)

	it("hides the banner again when the status says there is room", function()
		local world, peer = Rig.fixture("Lobby", nil)
		local full = Fixtures.lobby("Idle")
		full.full = true
		world.current = peer
		Rig.storeOf(world, peer).setLobby(full)
		Rig.storeOf(world, peer).setLobby(Fixtures.lobby("Idle"))
		world.current = nil
		FakeRoblox.run(world, 0.3)
		check(not Rig.shown(Rig.need(peer, "Lobby", "ServerFull"), "Lobby"), "the banner stays")
	end)
end)

-- ------------------------------------------------------------------ UI overhaul (WP2)

local function same(a: any, b: any): boolean
	return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
end

local function strictAudit(world: FakeRoblox.World, peer: FakeRoblox.Peer): number
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	return Audit.run(need(peer, "Screens", "Lobby"), "Lobby", { strict = true })
end

describe("Lobby design system", function()
	it("fills only Play vs Bot with the accent and makes it the primary action", function()
		local world, peer = mountFixture("Lobby", nil)
		local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
		local holder = need(peer, "Screens", "Lobby")
		local accents = {}
		for _, inst in holder:GetDescendants() do
			if inst:IsA("GuiButton") and same(inst.BackgroundColor3, Kit.colors.accent) then
				table.insert(accents, inst.Name)
			end
		end
		expect(table.concat(accents, ",")):toBe("Practice")
		expect(textOf(peer, "Lobby", "Practice")):toBe("Play vs Bot")
		expect(need(peer, "Lobby", "Practice"):GetAttribute("PrimaryAction")):toBe(true)
		expect(need(peer, "Lobby", "FindMatch"):GetAttribute("Variant")):toBe("secondary")
		expect(need(peer, "Lobby", "Host"):GetAttribute("Variant")):toBe("secondary")
		expect(need(peer, "Lobby", "Join"):GetAttribute("Variant")):toBe("secondary")
		expect(need(peer, "Lobby", "Cancel"):GetAttribute("Variant")):toBe("danger")
		expect(need(peer, "Lobby", "Title").TextSize):toBe(Kit.size.hero)
		noErrors(world)
	end)

	it("has no toast of its own", function()
		local world, peer = mountFixture("Lobby", nil)
		expect(findIn(peer, "Lobby", "Toast")):toBe(nil)
		noErrors(world)
	end)

	it("reserves the record line before the profile arrives", function()
		local world, peer = mountFixture("Lobby", nil)
		local record = need(peer, "Lobby", "Record")
		check(Rig.shown(record, "Lobby"), "the record line takes no space before the profile")
		local lobby = Fixtures.lobby("Idle")
		lobby.profile = { rating = 1000, wins = 3, losses = 2 }
		world.current = peer
		storeOf(peer).setLobby(lobby)
		world.current = nil
		FakeRoblox.run(world, 0.3)
		expect(textOf(peer, "Lobby", "Record")):toBe("Rating 1000 · 3 won, 2 lost")
		noErrors(world)
	end)

	it("audits clean, strictly, idle and hosting at both sizes", function()
		for _, screen in { PHONE, { x = 1280, y = 720 } } do
			local world, peer = mountFixture("Lobby", screen)
			expect(strictAudit(world, peer)):toBe(0)
			world.current = peer
			storeOf(peer).setLobby(Fixtures.lobby("Hosting"))
			world.current = nil
			FakeRoblox.run(world, 0.3)
			expect(textOf(peer, "Lobby", "CodeLabel")):toBe("AB3CD")
			expect(strictAudit(world, peer)):toBe(0)
			noErrors(world)
		end
	end)
end)
