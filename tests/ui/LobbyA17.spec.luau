--!strict
-- 0.17 slice A (docs/DESIGN.md D-090) on fixtures: the start screen (the map
-- behind the logo, the livelier Play button, the "?" chip that pulses for new
-- players, a colored dot per bot level, the Daily Race card), the queue (the
-- logo stays still, a pulsing ring, the elapsed time, the bot game as the main
-- button), "Opponent found!" (Join first, a shrinking bar, the opponent's face
-- and name, no ×), the private code (tap to select, waiting dots), the invite
-- sheet, How to play's progress dots, the tutorial's end, Results' rematch
-- banner and Daily rank, the bug report sheet and the admins' bug list.
-- Strict audit 0 at phone, iPad and desktop.

local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Config = require("@sim/Config")
local Test = require("@testlib/Test")
local Rig = require("./Rig")

local describe, it, expect = Test.describe, Test.it, Test.expect

local check, need, tap, textOf = Rig.check, Rig.need, Rig.tap, Rig.textOf
local C = Config.defaults
local PHONE = Rig.PHONE
local IPAD = { x = 1024, y = 768 }
local DESKTOP = { x = 1280, y = 720 }
local SIZES = { PHONE, IPAD, DESKTOP }

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

local function lobby(state: string, extra: { [string]: any }?): any
	local status = Fixtures.lobby(if state == "Hosting" or state == "Queued" then state :: any else "Idle")
	status.state = state
	for key, value in extra or {} do
		status[key] = value
	end
	return status
end

local function shownIn(peer: FakeRoblox.Peer, screen: string, name: string): boolean
	local inst = Rig.findIn(peer, screen, name)
	return inst ~= nil and Rig.shown(inst, screen)
end

local NEW = { rating = 1000, games = 0, wins = 0, losses = 0 }
local VETERAN = { rating = 1210, games = 14, wins = 9, losses = 5 }

describe("Start screen (D-090)", function()
	it("shows a faint map behind the logo and a livelier Play vs Bot", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Lobby", size)
			local map = need(peer, "Lobby", "BrandMap")
			check(map:GetAttribute("Decor") == true, "the map behind the logo is not decorative")
			local practice = need(peer, "Lobby", "Practice")
			check(practice:FindFirstChild("PlayIcon", true) ~= nil, "Play vs Bot has no play mark")
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
			Rig.noErrors(world)
		end
	end)

	it("makes How to play a ? chip in the corner that pulses for a new player", function()
		local world, peer = Rig.fixture("Lobby", PHONE)
		setLobby(world, peer, lobby("Idle", { profile = NEW }))
		local how = need(peer, "Lobby", "HowToPlay")
		check(how:FindFirstAncestor("CornerSettings") ~= nil, "How to play is not in the corner")
		expect(how.Text):toBe("?")
		expect(how:GetAttribute("Label")):toBe("How to play")
		expect(how:GetAttribute("Pulse")):toBe(true)
		expect(strictAudit(world, peer, "Lobby")):toBe(0)
		tap(world, peer, "Lobby", "HowToPlay")
		check(need(peer, "Lobby", "HowToSheet").Visible == true, "the sheet did not open")
		expect(how:GetAttribute("Pulse")):toBe(false) -- seen: it stops asking
		Rig.noErrors(world)

		local world2, peer2 = Rig.fixture("Lobby", PHONE)
		setLobby(world2, peer2, lobby("Idle", { profile = VETERAN }))
		expect(need(peer2, "Lobby", "HowToPlay"):GetAttribute("Pulse")):toBe(false)
		Rig.noErrors(world2)
	end)

	it("puts a colored dot on each bot level", function()
		local world, peer = Rig.fixture("Lobby", IPAD)
		local colors: { [string]: boolean } = {}
		for _, level in { "Easy", "Medium", "Hard", "Extreme" } do
			local dot = need(peer, "Lobby", `Level_{level}`):FindFirstChild("LevelDot", true)
			check(dot ~= nil, `{level} has no dot`)
			colors[tostring(dot.BackgroundColor3)] = true
		end
		local n = 0
		for _ in colors do
			n += 1
		end
		expect(n):toBe(4)
		Rig.noErrors(world)
	end)

	it(
		"dresses the Daily Race card: a gold edge, a stand-out Play, the streak's flame, a board chip",
		function()
			for _, size in SIZES do
				local world, peer = Rig.fixture("Lobby", size)
				world.current = peer
				Rig.storeOf(world, peer).setDaily(Fixtures.daily({ now = world.clock }))
				world.current = nil
				FakeRoblox.run(world, 0.3)
				local card = need(peer, "Lobby", "DailyCard")
				check(card:FindFirstChild("DailyEdge") ~= nil, "the card has no colored edge")
				check(shownIn(peer, "Lobby", "DailyFlame"), "no flame by the streak")
				check(
					need(peer, "Lobby", "DailyPlay"):GetAttribute("Featured") == true,
					"Play does not stand out"
				)
				check(
					need(peer, "Lobby", "DailyBoard"):GetAttribute("Chip") == true,
					"the board is not a chip"
				)
				expect(strictAudit(world, peer, "Lobby")):toBe(0)
				Rig.noErrors(world)
			end
		end
	)
end)

describe("The queue (D-090)", function()
	it("keeps the logo still, pulses a ring, counts the wait and features the bot game", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Lobby", size)
			local mark = need(peer, "Lobby", "Mark")
			local before = mark.AbsolutePosition
			setLobby(world, peer, lobby("Queued", { online = 1234, botAt = world.clock - 5 }))
			local after = mark.AbsolutePosition
			check(
				math.abs(before.X - after.X) <= 0.5 and math.abs(before.Y - after.Y) <= 0.5,
				`the logo moved {before} -> {after} at {size.x}x{size.y}`
			)
			check(shownIn(peer, "Lobby", "QueueRing"), "no ring")
			-- Waited since botAt less the offer delay: 35 s and the moments since.
			local waited = textOf(peer, "Lobby", "QueueTime")
			local seconds = C.QUEUE_BOT_OFFER_SECONDS + 5
			check(waited == `0:{seconds}` or waited == `0:{seconds + 1}`, `waited {waited}`)
			local waitBot = need(peer, "Lobby", "WaitBot")
			expect(waitBot:GetAttribute("PrimaryAction")):toBe(true)
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
			Rig.noErrors(world)
		end
	end)
end)

describe("Opponent found! (D-090)", function()
	it("makes Join the main button with a shrinking bar, the opponent's face and name, and no ×", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Plan", size)
			setLobby(
				world,
				peer,
				lobby("InMatch", {
					found = {
						phase = "Answer",
						untilAt = world.clock + C.QUEUE_ACCEPT_SECONDS,
						opponent = { userId = "4242", name = "Sir Zorkalot" },
					},
				})
			)
			local overlay = FakeRoblox.find(peer, "FoundOverlay")
			expect(need(peer, "FoundOverlay", "FoundJoin"):GetAttribute("Featured")):toBe(true)
			expect(textOf(peer, "FoundOverlay", "FoundName")):toBe("Sir Zorkalot")
			local face = need(peer, "FoundOverlay", "FoundFace")
			check(string.find(face.Image, "id=4242", 1, true) ~= nil, `face image {face.Image}`)
			check(not shownIn(peer, "FoundOverlay", "Close"), "the × still shows")
			local fill = need(peer, "FoundOverlay", "FoundBarFill")
			local full = fill.Size.X.Scale
			FakeRoblox.run(world, 5)
			check(fill.Size.X.Scale < full, "the bar did not shrink")
			local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
			expect(Audit.run(overlay, "FoundOverlay", { strict = true })):toBe(0)
			Rig.noErrors(world)
		end
	end)
end)

describe("Private code and invites (D-090)", function()
	it("selects the code on a tap and animates the waiting line", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Lobby", size)
			setLobby(world, peer, lobby("Hosting"))
			expect(textOf(peer, "Lobby", "CodeHint")):toBe("Tap to copy")
			local box = need(peer, "Lobby", "CodeLabel")
			expect(box.ClassName):toBe("TextBox")
			expect(box.TextEditable):toBe(false)
			expect(box.Text):toBe("AB3CD")
			local first = textOf(peer, "Lobby", "WaitingNow")
			FakeRoblox.run(world, 1.2)
			check(textOf(peer, "Lobby", "WaitingNow") ~= first, "the waiting dots do not move")
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
			Rig.noErrors(world)
		end
	end)

	it("makes Invite a friend the main button of the friend sheet", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Lobby", size)
			tap(world, peer, "Lobby", "PlayFriend", 0.5)
			local invite = need(peer, "Lobby", "Invite")
			expect(invite:GetAttribute("Featured")):toBe(true)
			expect(need(peer, "Lobby", "Host"):GetAttribute("Featured")):toBe(nil)
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
			Rig.noErrors(world)
		end
	end)
end)

describe("How to play (D-090)", function()
	it("shows progress dots and ends on Play the tutorial as the main button", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Lobby", size)
			tap(world, peer, "Lobby", "HowToPlay")
			local dots = need(peer, "Lobby", "HowToDots")
			for page = 1, 6 do
				for k = 1, 6 do
					local dot = dots:FindFirstChild(`Dot_{k}`)
					check(dot ~= nil, `no dot {k}`)
					expect(dot:GetAttribute("On")):toBe(k == page)
				end
				local featured = need(peer, "Lobby", "PlayTutorial"):GetAttribute("Featured") == true
				expect(featured):toBe(page == 6)
				expect(strictAudit(world, peer, "Lobby")):toBe(0)
				if page < 6 then
					tap(world, peer, "Lobby", "HowToNext")
				end
			end
			Rig.noErrors(world)
		end
	end)
end)

describe("The tutorial's end (D-090)", function()
	it("headlines You're ready! and calls the match Practice done!", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("TutorialOver", size)
			expect(textOf(peer, "Results", "Banner")):toBe("You're ready!")
			expect(textOf(peer, "Results", "ReadyTitle")):toBe("Practice done!")
			expect(strictAudit(world, peer, "Results")):toBe(0)
			Rig.noErrors(world)
		end
	end)
end)

describe("Results: the rematch banner and the Daily rank (D-090)", function()
	it("shows Buster wants a rematch! as a banner with his face", function()
		for _, size in SIZES do
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
			check(not shownIn(peer, "Results", "RematchBanner"), "a banner before anyone asked")
			world.current = peer
			store.setRematch({ matchId = payload.matchId, state = "Asked", untilAt = world.clock + 14 })
			world.current = nil
			FakeRoblox.run(world, 0.5)
			check(shownIn(peer, "Results", "RematchBanner"), "no rematch banner")
			check(
				string.find(textOf(peer, "Results", "RematchText"), "wants a rematch!", 1, true) ~= nil,
				"the banner does not say it"
			)
			check(Rig.findIn(peer, "Results", "RematchFace") ~= nil, "no face on the banner")
			expect(strictAudit(world, peer, "Results")):toBe(0)
			Rig.noErrors(world)
		end
	end)

	it("shows a counted Daily rank as a big number with the flame", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Over", size)
			local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
			payload.daily = { day = Fixtures.DAILY_DAY, counted = true }
			Rig.push(world, peer, payload)
			world.current = peer
			Rig.storeOf(world, peer).setDaily(Fixtures.daily({
				now = world.clock,
				played = true,
				margin = 62,
				you = 7,
				run = { matchId = payload.matchId, counted = true, margin = 62, forfeit = false, rank = 7 },
			}))
			world.current = nil
			FakeRoblox.run(world, 0.5)
			expect(textOf(peer, "Results", "DailyRank")):toBe("#7")
			check(shownIn(peer, "Results", "DailyRankFlame"), "no flame by the rank")
			expect(strictAudit(world, peer, "Results")):toBe(0)
			Rig.noErrors(world)
		end
	end)
end)

describe("Report a bug (D-090)", function()
	it("opens from the corner, counts characters and sends the text with the screen", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Lobby", size)
			local bug = need(peer, "Lobby", "BugToggle")
			expect(bug:GetAttribute("Label")):toBe("Report a bug")
			tap(world, peer, "Lobby", "BugToggle")
			local overlay = FakeRoblox.find(peer, "BugOverlay")
			check(overlay ~= nil and overlay.Visible == true, "the bug sheet did not open")
			local box = need(peer, "BugOverlay", "BugText")
			box.Text = "The map froze in week 3"
			FakeRoblox.run(world, 0.2)
			expect(textOf(peer, "BugOverlay", "BugCount")):toBe(`23/{C.BUG_REPORT_MAX_CHARS}`)
			local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
			expect(Audit.run(overlay, "BugOverlay", { strict = true })):toBe(0)
			tap(world, peer, "BugOverlay", "BugSend")
			expect(Rig.count(peer, "DEBUG_UI bugReport Lobby: The map froze in week 3")):toBe(1)
			check(overlay.Visible == false, "the sheet stayed open")
			Rig.noErrors(world)
		end
	end)

	it("does not send a report that is too short", function()
		local world, peer = Rig.fixture("Lobby", PHONE)
		tap(world, peer, "Lobby", "BugToggle")
		need(peer, "BugOverlay", "BugText").Text = "hi"
		FakeRoblox.run(world, 0.2)
		tap(world, peer, "BugOverlay", "BugSend")
		expect(Rig.count(peer, "DEBUG_UI bugReport")):toBe(0)
		check(FakeRoblox.find(peer, "BugOverlay").Visible == true, "the sheet closed on a short report")
		Rig.noErrors(world)
	end)

	it("is in the in-match Help sheet too, tagged with the screen", function()
		local world, peer = Rig.fixture("Plan", PHONE)
		tap(world, peer, "Campaign", "HelpButton")
		tap(world, peer, "HelpOverlay", "HelpBug")
		need(peer, "BugOverlay", "BugText").Text = "A state card was empty"
		FakeRoblox.run(world, 0.2)
		tap(world, peer, "BugOverlay", "BugSend")
		expect(Rig.count(peer, "DEBUG_UI bugReport Campaign: A state card was empty")):toBe(1)
		Rig.noErrors(world)
	end)

	it("lists the newest reports for admins", function()
		for _, size in SIZES do
			local world, peer = Rig.fixture("Lobby", size)
			check(not shownIn(peer, "Lobby", "BugsButton"), "a player sees the admins' bug list")
			setLobby(world, peer, lobby("Idle", { review = { count = 2 }, admin = { timersOff = false } }))
			check(shownIn(peer, "Lobby", "BugsButton"), "an admin has no bug list")
			tap(world, peer, "Lobby", "BugsButton")
			check(Rig.count(peer, "DEBUG_UI send BugList") >= 1, "the list was not asked for")
			world.current = peer
			Rig.storeOf(world, peer).setBugs({
				ok = true,
				entries = {
					{
						at = 1761700000,
						userId = "77",
						owner = "MapleFox",
						version = "0.17.0",
						screen = "Campaign",
						matchId = "m-12",
						text = "The rematch button did nothing.",
					},
				},
			})
			world.current = nil
			FakeRoblox.run(world, 0.3)
			check(shownIn(peer, "Lobby", "BugRow_1"), "no row for the report")
			check(
				string.find(textOf(peer, "Lobby", "BugRowText"), "rematch button", 1, true) ~= nil,
				"the row does not show the text"
			)
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
			Rig.noErrors(world)
		end
	end)
end)

describe("Coach tips on a landscape phone (D-090)", function()
	it("puts a tutorial tip first in the side column, so Got it is never under the bar", function()
		for _, moment in { "TutorialPlan", "TutorialLast" } do
			local world, peer = Rig.fixture(moment, PHONE)
			local tip = need(peer, "Campaign", "CoachTip")
			for _, sibling in tip.Parent:GetChildren() do
				if sibling ~= tip and sibling:IsA("GuiObject") and sibling.Visible then
					check(
						sibling.LayoutOrder > tip.LayoutOrder,
						`{moment}: {sibling.Name} ({sibling.LayoutOrder}) sits above the tip ({tip.LayoutOrder})`
					)
				end
			end
			Rig.noErrors(world)
		end
	end)
end)
