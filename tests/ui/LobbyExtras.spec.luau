--!strict
-- The start screen's extras (D-059) on the fake engine: the bot level picker
-- and the Practice request it shapes, How to play, the leaderboard card and
-- sheet, and "Leave match" from an in-match "?" against the bot and a person.

local Test = require("@testlib/Test")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Config = require("@sim/Config")
local Words = require("@ui/Words/Lobby")
local Rig = require("./Rig")

local describe, it, expect = Test.describe, Test.it, Test.expect

local check, need, tap, textOf = Rig.check, Rig.need, Rig.tap, Rig.textOf
local PHONE = Rig.PHONE
local DESKTOP = { x = 1280, y = 720 }
-- A phone tall enough for the top 3 under the Daily Race card (D-080: 870 px and up).
local TALL_PHONE = { x = 430, y = 932 }

local function strictAudit(world: FakeRoblox.World, peer: FakeRoblox.Peer, screen: string): number
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	return Audit.run(FakeRoblox.find(peer, screen), screen, { strict = true })
end

local function setBoard(world: FakeRoblox.World, peer: FakeRoblox.Peer, board: any)
	world.current = peer
	Rig.storeOf(world, peer).setLeaderboard(board)
	world.current = nil
	FakeRoblox.run(world, 0.3)
end

-- Records every Net.send the live client makes (the real one still runs).
local function spySends(world: FakeRoblox.World, peer: FakeRoblox.Peer): { { op: string, fields: any } }
	local sent = {}
	local net = Rig.netOf(world, peer)
	local real = net.send
	net.send = function(op: string, fields: any?)
		table.insert(sent, { op = op, fields = fields })
		real(op, fields)
	end
	return sent
end

local function serverSaid(world: FakeRoblox.World, text: string): boolean
	return Rig.count(world.server, text) > 0
end

local function shownIn(peer: FakeRoblox.Peer, screen: string, name: string): boolean
	local inst = Rig.findIn(peer, screen, name)
	return inst ~= nil and Rig.shown(inst, screen)
end

describe("Lobby: the bot level (D-059)", function()
	it("starts on Medium and outlines the level tapped", function()
		local world, peer = Rig.fixture("Lobby", PHONE)
		local BotLevel = FakeRoblox.require(world, peer, "src/client/UI/BotLevel.luau")
		BotLevel.set("Medium") -- the module outlives a world: start clean
		FakeRoblox.run(world, 0.2)
		expect(need(peer, "Lobby", "Level_Medium"):GetAttribute("Selected")):toBe(true)
		tap(world, peer, "Lobby", "Level_Hard")
		expect(need(peer, "Lobby", "Level_Hard"):GetAttribute("Selected")):toBe(true)
		expect(need(peer, "Lobby", "Level_Medium"):GetAttribute("Selected")):toBe(false)
		expect(need(peer, "Lobby", "BotLevel"):GetAttribute("Level")):toBe("Hard")
		check(need(peer, "Lobby", "Level_Extreme").AbsoluteSize.X >= 44, "a level chip is too narrow")
		expect(strictAudit(world, peer, "Lobby")):toBe(0)
		Rig.noErrors(world)
	end)

	it("sends the picked level with Practice, and remembers it for the session", function()
		local world, peer = Rig.practice(51)
		local sent = spySends(world, peer)
		tap(world, peer, "Lobby", "Level_Extreme")
		tap(world, peer, "Lobby", "Practice")
		local practice = nil
		for _, entry in sent do
			if entry.op == "Practice" then
				practice = entry
			end
		end
		check(practice ~= nil, "no Practice request")
		expect(practice and practice.fields and practice.fields.difficulty):toBe("Extreme")
		check(FakeRoblox.find(peer, "Select") ~= nil, "the practice match did not start")

		-- Leave it; the Lobby that comes back still has Extreme picked.
		local net = Rig.netOf(world, peer)
		world.current = peer
		net.forfeit()
		world.current = nil
		FakeRoblox.run(world, 2)
		check(FakeRoblox.find(peer, "Lobby") ~= nil, "not back in the lobby")
		expect(need(peer, "Lobby", "BotLevel"):GetAttribute("Level")):toBe("Extreme")
		Rig.noErrors(world)
	end)

	-- End to end (D-057, D-059): the chip the player taps reaches the server's
	-- bot seat; a level the server does not know plays Medium.
	it("the level tapped is the level the bot seat plays; an unknown one is Medium", function()
		local world, peer = Rig.practice(52)
		local BotLevel = FakeRoblox.require(world, peer, "src/client/UI/BotLevel.luau")
		BotLevel.set("Medium") -- the module outlives a world: start clean
		FakeRoblox.run(world, 0.2)
		local function botSeat(): any
			local payload = Rig.payloadOf(world, peer)
			for _, seat in (payload and payload.seats) or {} do
				if seat.difficulty ~= nil then
					return seat
				end
			end
			return nil
		end

		tap(world, peer, "Lobby", "Level_Hard")
		tap(world, peer, "Lobby", "Practice")
		check(FakeRoblox.find(peer, "Select") ~= nil, "the Hard practice match did not start")
		expect(Rig.count(world.server, "match m1 started (Practice)")):toBe(1)
		expect(serverSaid(world, "bot Hard")):toBe(true)
		local seat = botSeat()
		expect(seat and seat.difficulty):toBe("Hard")

		-- Leave it, then ask for a level that does not exist.
		local net = Rig.netOf(world, peer)
		world.current = peer
		net.forfeit()
		world.current = nil
		FakeRoblox.run(world, 2)
		check(FakeRoblox.find(peer, "Lobby") ~= nil, "not back in the lobby")
		world.current = peer
		net.send("Practice", { difficulty = "Nightmare" })
		world.current = nil
		FakeRoblox.run(world, 1)
		check(FakeRoblox.find(peer, "Select") ~= nil, "the second practice match did not start")
		expect(Rig.count(world.server, "match m2 started (Practice)")):toBe(1)
		expect(serverSaid(world, "bot Medium")):toBe(true)
		seat = botSeat()
		expect(seat and seat.difficulty):toBe("Medium")
		expect(serverSaid(world, "rejected")):toBe(false)
		BotLevel.set("Medium")
		Rig.noErrors(world)
	end)
end)

describe("Lobby: How to play (D-059)", function()
	it("opens six short pages and steps through them to Got it", function()
		local world, peer = Rig.fixture("Lobby", PHONE)
		tap(world, peer, "Lobby", "HowToPlay")
		check(need(peer, "Lobby", "HowToSheet").Visible == true, "the sheet did not open")
		check(shownIn(peer, "Lobby", "HowToPage_goal"), "page 1 is not the goal")
		check(not shownIn(peer, "Lobby", "HowToBack"), "Back shows on page 1")
		expect(textOf(peer, "Lobby", "HowToCount")):toBe("1 of 6")
		expect(strictAudit(world, peer, "Lobby")):toBe(0)
		for page, id in { "week", "actions", "issues", "events", "night" } do
			tap(world, peer, "Lobby", "HowToNext")
			check(shownIn(peer, "Lobby", `HowToPage_{id}`), `page {page + 1} is not {id}`)
			expect(strictAudit(world, peer, "Lobby")):toBe(0)
		end
		expect(textOf(peer, "Lobby", "HowToNext")):toBe("Got it")
		tap(world, peer, "Lobby", "HowToBack")
		check(shownIn(peer, "Lobby", "HowToPage_events"), "Back did not go back")
		tap(world, peer, "Lobby", "HowToNext")
		tap(world, peer, "Lobby", "HowToNext")
		check(need(peer, "Lobby", "HowToSheet").Visible == false, "Got it did not close the sheet")
		-- Opening it again starts over.
		tap(world, peer, "Lobby", "HowToPlay")
		check(shownIn(peer, "Lobby", "HowToPage_goal"), "it did not start over")
		Rig.noErrors(world)
	end)

	it("reuses the in-match Help pictures and never holds a primary", function()
		local world, peer = Rig.fixture("Lobby", DESKTOP)
		tap(world, peer, "Lobby", "HowToPlay")
		check(Rig.findIn(peer, "Lobby", "FillYou") ~= nil, "no race bar on the goal page")
		check(Rig.findIn(peer, "Lobby", "Action1") ~= nil, "no action rows")
		for _, inst in need(peer, "Lobby", "HowToSheet"):GetDescendants() do
			check(inst:GetAttribute("PrimaryAction") ~= true, `{inst.Name} is a primary in the sheet`)
		end
		Rig.noErrors(world)
	end)
end)

describe("Lobby: the leaderboard (D-059)", function()
	it("shows the top 3 inside the column on a tall phone", function()
		local world, peer = Rig.fixture("Lobby", TALL_PHONE)
		local card = need(peer, "Lobby", "LeaderboardCard")
		check(card:FindFirstAncestor("Idle") ~= nil, "the card is not in the column")
		check(Rig.findIn(peer, "Lobby", "Row_3") ~= nil, "no third row")
		expect(Rig.findIn(peer, "Lobby", "Row_4")):toBe(nil)
		expect(textOf(peer, "Lobby", "LeaderboardYou")):toBe("You: #4 · 1444")
		expect(strictAudit(world, peer, "Lobby")):toBe(0)
		Rig.noErrors(world)
	end)

	it("shows the top 3 on a 390x844 phone beside a one-row Daily Race card (0.15.0)", function()
		local world, peer = Rig.fixture("Lobby", PHONE)
		local card = need(peer, "Lobby", "LeaderboardCard")
		check(card:FindFirstAncestor("Idle") ~= nil, "the card is not in the column")
		check(Rig.findIn(peer, "Lobby", "Row_3") ~= nil, "no third row")
		expect(Rig.findIn(peer, "Lobby", "Row_4")):toBe(nil)
		check(shownIn(peer, "Lobby", "LeaderboardYou"), "no viewer line")
		-- The Daily Race card is one row: its buttons sit in its head.
		local play = need(peer, "Lobby", "DailyPlay")
		check(play:FindFirstAncestor("DailyHead") ~= nil, "the Daily card is not one row on a phone")
		expect(textOf(peer, "Lobby", "DailyBoard")):toBe("Top 50")
		expect(strictAudit(world, peer, "Lobby")):toBe(0)
		Rig.noErrors(world)
	end)

	it("keeps the full Daily Race card on an iPad", function()
		local world, peer = Rig.fixture("Lobby", { x = 1024, y = 768 })
		local play = need(peer, "Lobby", "DailyPlay")
		expect(play:FindFirstAncestor("DailyHead")):toBe(nil)
		expect(textOf(peer, "Lobby", "DailyBoard")):toBe("Today's board")
		expect(strictAudit(world, peer, "Lobby")):toBe(0)
		Rig.noErrors(world)
	end)

	it("keeps only the viewer's line and See all on a short phone", function()
		local world, peer = Rig.fixture("Lobby", { x = 375, y = 667 })
		expect(Rig.findIn(peer, "Lobby", "Row_1")):toBe(nil)
		check(shownIn(peer, "Lobby", "LeaderboardYou"), "no viewer line")
		check(shownIn(peer, "Lobby", "LeaderboardSeeAll"), "no See all")
		expect(strictAudit(world, peer, "Lobby")):toBe(0)
		Rig.noErrors(world)
	end)

	it("shows the top 10 beside the column on a wide screen, the viewer's row raised", function()
		local world, peer = Rig.fixture("Lobby", DESKTOP)
		local card = need(peer, "Lobby", "LeaderboardCard")
		expect(card:FindFirstAncestor("Idle")):toBe(nil)
		check(Rig.findIn(peer, "Lobby", "Row_10") ~= nil, "no tenth row")
		expect(Rig.findIn(peer, "Lobby", "Row_11")):toBe(nil)
		local mine = need(peer, "Lobby", "Row_4")
		expect(mine:GetAttribute("You")):toBe(true)
		expect(mine.BackgroundTransparency):toBe(0)
		expect(need(peer, "Lobby", "Row_3"):GetAttribute("You")):toBe(false)
		-- The column and the card do not overlap.
		local column = need(peer, "Lobby", "Content")
		check(
			column.AbsolutePosition.X + column.AbsoluteSize.X <= card.AbsolutePosition.X,
			"the card overlaps the column"
		)
		expect(strictAudit(world, peer, "Lobby")):toBe(0)
		Rig.noErrors(world)
	end)

	it("See all opens the top 50 in a sheet", function()
		local world, peer = Rig.fixture("Lobby", PHONE)
		tap(world, peer, "Lobby", "LeaderboardSeeAll")
		check(need(peer, "Lobby", "LeaderboardSheet").Visible == true, "the sheet did not open")
		check(Rig.findIn(peer, "Lobby", "SheetRow_50") ~= nil, "no 50th row")
		expect(textOf(peer, "Lobby", "SheetYou")):toBe("You: #4 · 1444")
		expect(strictAudit(world, peer, "Lobby")):toBe(0)
		Rig.noErrors(world)
	end)

	it("says where an unlisted viewer stands, and when nobody is ranked or it can't load", function()
		local world, peer = Rig.fixture("Lobby", TALL_PHONE)
		setBoard(world, peer, Fixtures.leaderboard({ you = 0 }))
		expect(textOf(peer, "Lobby", "LeaderboardYou")):toBe("You: not in the top 50 · 1004")

		setBoard(world, peer, Fixtures.leaderboard({ count = 0, you = -1 }))
		check(shownIn(peer, "Lobby", "LeaderboardStatus"), "no empty-board line")
		check(
			string.find(textOf(peer, "Lobby", "LeaderboardStatus"), "No ranked players yet", 1, true) ~= nil,
			"the empty board says something else"
		)
		check(not shownIn(peer, "Lobby", "LeaderboardYou"), "the you line repeats the empty line")

		setBoard(world, peer, Fixtures.leaderboard({ count = 0, you = -1, status = "Unavailable" }))
		expect(textOf(peer, "Lobby", "LeaderboardStatus")):toBe("Leaderboard unavailable")

		-- A failed read with an earlier list keeps showing that list.
		setBoard(world, peer, Fixtures.leaderboard({ count = 5, status = "Unavailable" }))
		check(not shownIn(peer, "Lobby", "LeaderboardStatus"), "the last good list is hidden")
		check(Rig.findIn(peer, "Lobby", "Row_1") ~= nil, "no rows")
		expect(strictAudit(world, peer, "Lobby")):toBe(0)
		Rig.noErrors(world)
	end)

	it("asks the server for the board when the Lobby opens", function()
		local world, peer = Rig.practice(52)
		local board = Rig.storeOf(world, peer).get().leaderboard
		check(board ~= nil, "no board arrived")
		expect(board.status):toBe("Ok")
		Rig.noErrors(world)
	end)
end)

describe("Leave match (D-059)", function()
	it("against the bot: ? > Leave match asks about practice, Keep playing stays, Leave ends it", function()
		local world, peer = Rig.practice(53)
		tap(world, peer, "Lobby", "Practice")
		check(FakeRoblox.find(peer, "Select") ~= nil, "no Select screen")
		tap(world, peer, "Select", "HelpButton")
		check(shownIn(peer, "HelpOverlay", "HelpLeave"), "no Leave match in the Help sheet")
		tap(world, peer, "HelpOverlay", "HelpLeave")
		local overlay = FakeRoblox.find(peer, "LeaveOverlay")
		check(overlay.Visible == true, "the confirmation did not open")
		check(FakeRoblox.find(peer, "HelpOverlay").Visible == false, "Help stayed open under it")
		expect(overlay:GetAttribute("VsBot")):toBe(true)
		expect(textOf(peer, "LeaveOverlay", "Title")):toBe("Leave this practice match?")
		expect(strictAudit(world, peer, "LeaveOverlay")):toBe(0)

		tap(world, peer, "LeaveOverlay", "LeaveStay")
		check(overlay.Visible == false, "Keep playing did not close it")
		check(FakeRoblox.find(peer, "Select") ~= nil, "Keep playing left the match")
		expect(serverSaid(world, "match m1 over")):toBe(false)

		tap(world, peer, "Select", "HelpButton")
		tap(world, peer, "HelpOverlay", "HelpLeave")
		tap(world, peer, "LeaveOverlay", "LeaveConfirm", 2)
		expect(serverSaid(world, "match m1 over: Forfeit, winner seat 2")):toBe(true)
		check(FakeRoblox.find(peer, "Lobby") ~= nil, "the leaver is not in the lobby")
		expect(FakeRoblox.find(peer, "Results")):toBe(nil)
		check(overlay.Visible == false, "the confirmation stayed up")
		Rig.noErrors(world)
	end)

	it("against a person: Leave and forfeit; the opponent sees they won by forfeit", function()
		local world = Rig.newWorld(54, PHONE)
		local a = FakeRoblox.join(world, "A")
		local b = FakeRoblox.join(world, "B")
		FakeRoblox.run(world, 1)
		tap(world, a, "Lobby", "FindMatch")
		tap(world, b, "Lobby", "FindMatch", 1)
		check(FakeRoblox.find(a, "Select") ~= nil and FakeRoblox.find(b, "Select") ~= nil, "no match")
		tap(world, a, "Select", "HelpButton")
		tap(world, a, "HelpOverlay", "HelpLeave")
		expect(FakeRoblox.find(a, "LeaveOverlay"):GetAttribute("VsBot")):toBe(false)
		expect(textOf(a, "LeaveOverlay", "Title")):toBe("Leave and forfeit?")
		expect(textOf(a, "LeaveOverlay", "LeaveText")):toBe("This counts as a loss, and your opponent wins.")
		expect(textOf(a, "LeaveOverlay", "LeaveConfirm")):toBe("Leave and forfeit")
		expect(strictAudit(world, a, "LeaveOverlay")):toBe(0)
		tap(world, a, "LeaveOverlay", "LeaveConfirm", 2)

		check(FakeRoblox.find(a, "Lobby") ~= nil, "the leaver is not in the lobby")
		check(FakeRoblox.find(b, "Results") ~= nil, "the opponent has no Results screen")
		local reason = need(b, "Results", "Reason")
		expect(reason.Text):toBe("Your opponent forfeited the match.")
		Rig.noErrors(world)
	end)

	it("closes by itself when the match ends while it is open", function()
		local world, peer = Rig.fixture("Plan", PHONE)
		tap(world, peer, "Campaign", "HelpButton")
		tap(world, peer, "HelpOverlay", "HelpLeave")
		local overlay = FakeRoblox.find(peer, "LeaveOverlay")
		check(overlay.Visible == true, "the confirmation did not open")
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		payload.step += 1
		payload.stage = "Over"
		payload.result = { winner = payload.you, reason = "Election" }
		Rig.push(world, peer, payload)
		FakeRoblox.run(world, 0.5)
		check(overlay.Visible == false, "the confirmation outlived the match")
		check(FakeRoblox.find(peer, "Results") ~= nil, "no Results screen")
		Rig.noErrors(world)
	end)
end)

describe("Lobby words (D-059)", function()
	it("keeps every How to play page to a title and at most 30 words", function()
		local pages = Words.howTo(Config.defaults)
		check(#pages >= 3 and #pages <= 6, `{#pages} pages`) -- six since D-076 (the issues)
		for _, page in pages do
			local words = 0
			for _ in string.gmatch(page.text, "%S+") do
				words += 1
			end
			check(words <= 30, `{page.id} has {words} words`)
			check(page.title ~= "", `{page.id} has no title`)
		end
		expect(Words.youLine({ rating = 1004 }, 50)):toBe("You: not in the top 50 · 1004")
		expect(Words.youLine({ rank = 4, rating = 1444 }, 50)):toBe("You: #4 · 1444")
		check(
			string.find(pages[1].text, tostring(Config.defaults.EV_TO_WIN), 1, true) ~= nil,
			"the goal page has no 270"
		)
	end)

	it("offers four bot levels, Medium by default", function()
		expect(table.concat(Words.LEVELS, ",")):toBe("Easy,Medium,Hard,Extreme")
		expect(Words.DEFAULT_LEVEL):toBe("Medium")
	end)
end)
