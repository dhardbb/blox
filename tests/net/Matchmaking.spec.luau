--!strict
-- Matchmaking's pure rules (docs/DESIGN.md D-083): tickets for matching across
-- servers, the online count, the rematch state machine, the lobby's bot game
-- while waiting and its offers, and the new requests.

local Config = require("@sim/Config")
local Lobby = require("@net/Lobby")
local Matchmaking = require("@net/Matchmaking")
local Online = require("@net/Online")
local Rematch = require("@net/Rematch")
local Schemas = require("@net/Schemas")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local NOW = 1000

local function ticket(id: string, job: string, at: number, options: any?): Matchmaking.Ticket
	return Matchmaking.open("Queue", id, job, at, NOW, options)
end

describe("Matchmaking tickets", function()
	it("walks a claim from Open to Ready, and only the right claim moves it", function()
		local t = ticket("11", "job-a", 900)
		expect(Matchmaking.isTicket(t)):toBe(true)
		local claimed = Matchmaking.claim(t, "22", "job-b", "job-b#1", NOW, NOW + 25) :: any
		expect(claimed.state):toBe("Claimed")
		expect(claimed.by):toBe("22")
		expect(Matchmaking.isTicket(claimed)):toBe(true)
		-- A second claim loses: the ticket is no longer open.
		expect(Matchmaking.claim(claimed, "33", "job-c", "job-c#1", NOW, NOW + 25)):toBe(nil)
		-- Only the claim's own match key answers or readies it.
		expect(Matchmaking.answer(claimed, "other", true)):toBe(nil)
		expect(Matchmaking.ready(claimed, "job-b#1", "access")):toBe(nil) -- not accepted yet
		local accepted = Matchmaking.answer(claimed, "job-b#1", true) :: any
		expect(accepted.state):toBe("Accepted")
		local ready = Matchmaking.ready(accepted, "job-b#1", "access-1") :: any
		expect(ready.state):toBe("Ready")
		expect(ready.access):toBe("access-1")
		expect(Matchmaking.isTicket(ready)):toBe(true)
		-- A Ready ticket is never reopened or lapsed: the players are on their way.
		expect(Matchmaking.reopen(ready, "job-b#1")):toBe(nil)
		expect(Matchmaking.lapse(ready, NOW + 1000)):toBe(nil)
		-- The place in line never changes.
		expect(ready.at):toBe(900)
	end)

	it("declines, reopens and lapses claims back to Open with the same place in line", function()
		local claimed =
			Matchmaking.claim(ticket("11", "job-a", 900), "22", "job-b", "m", NOW, NOW + 25) :: any
		local declined = Matchmaking.answer(claimed, "m", false) :: any
		expect(declined.state):toBe("Declined")
		local reopened = Matchmaking.reopen(declined, "m") :: any
		expect(reopened.state):toBe("Open")
		expect(reopened.by):toBe(nil)
		expect(reopened.match):toBe(nil)
		expect(reopened.at):toBe(900)
		expect(Matchmaking.reopen(declined, "another")):toBe(nil)
		-- Lapse waits for the claim's deadline.
		expect(Matchmaking.lapse(claimed, NOW + 25)):toBe(nil)
		local lapsed = Matchmaking.lapse(claimed, NOW + 26) :: any
		expect(lapsed.state):toBe("Open")
	end)

	it("never claims a stale ticket, a foreign value, or the same player's old ticket", function()
		local old = ticket("11", "job-a", 900)
		expect(Matchmaking.claim(old, "22", "job-b", "m", NOW + Matchmaking.STALE + 1, NOW + 99)):toBe(nil)
		expect(Matchmaking.claim({ v = 2 }, "22", "job-b", "m", NOW, NOW + 25)):toBe(nil)
		expect(Matchmaking.claim("junk", "22", "job-b", "m", NOW, NOW + 25)):toBe(nil)
		expect(Matchmaking.claim(old, "11", "job-b", "m", NOW, NOW + 25)):toBe(nil)
	end)

	it("refreshes only its own ticket and keeps its state", function()
		local t = ticket("11", "job-a", 900)
		local fresh = Matchmaking.refresh(t, "11", "job-a", NOW + 30, true) :: any
		expect(fresh.touched):toBe(NOW + 30)
		expect(fresh.busy):toBe(true)
		expect(Matchmaking.refresh(t, "11", "job-z", NOW + 30, false)):toBe(nil)
		expect(Matchmaking.refresh(nil, "11", "job-a", NOW, false)):toBe(nil)
		local claimed = Matchmaking.claim(t, "22", "job-b", "m", NOW, NOW + 25) :: any
		expect((Matchmaking.refresh(claimed, "11", "job-a", NOW + 3, false) :: any).state):toBe("Claimed")
	end)

	it("rejects malformed tickets", function()
		local good = ticket("11", "job-a", 900) :: any
		local function bad(change: { [string]: any }): boolean
			local copy = table.clone(good)
			for key, value in change do
				copy[key] = value
			end
			return not Matchmaking.isTicket(copy)
		end
		expect(bad({ id = "abc" })):toBe(true)
		expect(bad({ kind = "Party" })):toBe(true)
		expect(bad({ state = "Gone" })):toBe(true)
		expect(bad({ at = math.huge })):toBe(true)
		expect(bad({ job = "" })):toBe(true)
		expect(bad({ state = "Claimed" })):toBe(true) -- a claim needs by, byJob, match, untilAt
		expect(bad({ state = "Ready", by = "2", byJob = "j", match = "m" })):toBe(true) -- no access
		expect(Matchmaking.isTicket(good)):toBe(true)
	end)

	it("picks the oldest open ticket of an older player on another server", function()
		local rows = {
			{ key = "1", value = ticket("1", "job-a", 800) }, -- this server: never
			{
				key = "2",
				value = Matchmaking.claim(ticket("2", "job-b", 810), "9", "job-c", "m", NOW, NOW + 9),
			},
			{ key = "3", value = ticket("3", "job-c", 820) },
			{ key = "4", value = ticket("4", "job-d", 820) },
			{ key = "5", value = ticket("5", "job-e", 990) }, -- newer than me
			{ key = "x", value = "garbage" },
		}
		-- Player 7 on job-a, queued at 950: 3 and 4 are older, open and elsewhere;
		-- at the same time the smaller UserId counts as older.
		expect(Matchmaking.pick(rows, "7", 950, "job-a", NOW)):toBe("3")
		-- For 3 (job-c), 1 on job-a is older and open.
		expect(Matchmaking.pick(rows, "3", 820, "job-c", NOW)):toBe("1")
		-- The oldest player never claims: nobody older is open.
		expect(Matchmaking.pick(rows, "1", 800, "job-a", NOW)):toBe(nil)
		-- Same second: 3 is older than 4 by UserId, so 4 claims 3 and not the reverse.
		local tie = { rows[3], rows[4] }
		expect(Matchmaking.pick(tie, "4", 820, "job-d", NOW)):toBe("3")
		expect(Matchmaking.pick(tie, "3", 820, "job-c", NOW)):toBe(nil)
		-- Stale tickets are skipped.
		expect(Matchmaking.pick(rows, "7", 950, "job-a", NOW + Matchmaking.STALE + 1)):toBe(nil)
	end)

	it("checks match specs and keeps the events choice", function()
		local spec = Matchmaking.spec("m", 1234, { "11", "22" }, "Code", false, NOW)
		expect(Matchmaking.isSpec(spec)):toBe(true)
		expect(spec.events):toBe(false)
		expect(Matchmaking.spec("m", 1, { "11", "22" }, "Queue", nil, NOW).events):toBe(nil)
		expect(Matchmaking.isSpec(Matchmaking.spec("m", 1, { "11", "11" }, "Queue", nil, NOW))):toBe(false)
		expect(Matchmaking.isSpec(Matchmaking.spec("m", 1, { "11" }, "Queue", nil, NOW))):toBe(false)
		expect(Matchmaking.isSpec(Matchmaking.spec("m", 1.5, { "11", "22" }, "Queue", nil, NOW))):toBe(false)
		expect(Matchmaking.isSpec({
			v = 1,
			match = "m",
			seed = 1,
			players = { "a", "b" },
			mode = "Queue",
			at = 1,
		})):toBe(false)
	end)

	it("puts the code in an invite's launch data and reads only a well-formed one back", function()
		local data = Matchmaking.launchData("AB3CD")
		expect(#data <= Matchmaking.LAUNCH_MAX):toBe(true)
		expect(Matchmaking.codeFromLaunch(data)):toBe("AB3CD")
		expect(Matchmaking.codeFromLaunch("")):toBe(nil)
		expect(Matchmaking.codeFromLaunch("AB3CD")):toBe(nil)
		expect(Matchmaking.codeFromLaunch(Matchmaking.LAUNCH_PREFIX .. "AB0CD")):toBe(nil) -- no 0 in codes
		expect(Matchmaking.codeFromLaunch(Matchmaking.LAUNCH_PREFIX .. "AB3CDE")):toBe(nil)
		expect(Matchmaking.codeFromLaunch(5)):toBe(nil)
		expect(Matchmaking.codeFromLaunch(string.rep("x", 300))):toBe(nil)
	end)

	it("takes only known notices from a returning player's teleport data", function()
		local notice, requeue =
			Matchmaking.readTravel({ landslide = 1, notice = "OpponentNoShow", requeue = true })
		expect(notice):toBe("OpponentNoShow")
		expect(requeue):toBe(true)
		notice, requeue = Matchmaking.readTravel({ landslide = 1, notice = "YouWin1000Robux" })
		expect(notice):toBe(nil)
		expect(requeue):toBe(false)
		notice = Matchmaking.readTravel(nil)
		expect(notice):toBe(nil)
		notice = Matchmaking.readTravel({ notice = "OpponentNoShow" })
		expect(notice):toBe(nil)
	end)
end)

describe("Online", function()
	it("sums fresh reports and skips stale or foreign ones", function()
		local rows = {
			{ key = "a", value = Online.report(12, 990) },
			{ key = "b", value = Online.report(30, 950) },
			{ key = "c", value = Online.report(7, 800) }, -- stale
			{ key = "d", value = { n = "lots", at = 999 } },
			{ key = "e", value = { n = 100000, at = 999 } }, -- not a Roblox server
			{ key = "f", value = { n = -3, at = 999 } },
		}
		expect(Online.sum(rows, NOW, 90)):toBe(42)
		expect(Online.sum({}, NOW, 90)):toBe(0)
	end)

	it("knows when the shared total is due and never shows fewer than this server holds", function()
		expect(Online.due(nil, NOW, 30)):toBe(true)
		expect(Online.due(Online.report(10, NOW - 31), NOW, 30)):toBe(true)
		expect(Online.due(Online.report(10, NOW - 5), NOW, 30)):toBe(false)
		expect(Online.shown(nil, 4)):toBe(nil)
		expect(Online.shown(3, 4)):toBe(4)
		expect(Online.shown(1234, 4)):toBe(1234)
	end)

	it("writes the count with thousands separators", function()
		expect(Online.text(1)):toBe("1 online")
		expect(Online.text(999)):toBe("999 online")
		expect(Online.text(1234)):toBe("1,234 online")
		expect(Online.text(1234567)):toBe("1,234,567 online")
	end)
end)

describe("Rematch", function()
	it("against a person: both tap within the window, in any order", function()
		local offer = Rematch.new("m1", { "a", "b" }, false, NOW, 20)
		expect(Rematch.status(offer, "a", NOW).state):toBe("Open")
		expect(Rematch.status(offer, "a", NOW).untilAt):toBe(NOW + 20)
		expect((Rematch.ask(offer, "b", NOW + 3))):toBe("Waiting")
		expect(Rematch.status(offer, "b", NOW + 3).state):toBe("Waiting")
		expect(Rematch.status(offer, "a", NOW + 3).state):toBe("Asked")
		expect((Rematch.ask(offer, "a", NOW + 19))):toBe("Start")
		expect(Rematch.status(offer, "a", NOW + 19).state):toBe("Started")
		expect(Rematch.closed(offer, NOW + 19)):toBe(true)
		-- A second tap does nothing more.
		local again, reason = Rematch.ask(offer, "a", NOW + 19)
		expect(again):toBe(nil)
		expect(reason):toBe(Rematch.Reason.NotYours)
	end)

	it("expires, and says so to both", function()
		local offer = Rematch.new("m1", { "a", "b" }, false, NOW, 20)
		Rematch.ask(offer, "a", NOW + 1)
		local verdict, reason = Rematch.ask(offer, "b", NOW + 21)
		expect(verdict):toBe(nil)
		expect(reason):toBe(Rematch.Reason.Expired)
		expect(Rematch.status(offer, "a", NOW + 21).state):toBe("Expired")
		expect(Rematch.status(offer, "a", NOW + 21).untilAt):toBe(nil)
		expect(Rematch.closed(offer, NOW + 21)):toBe(true)
	end)

	it("is gone when the opponent leaves or starts something else", function()
		local offer = Rematch.new("m1", { "a", "b" }, false, NOW, 20)
		expect(Rematch.leave(offer, "b")):toBe(true)
		expect(Rematch.leave(offer, "b")):toBe(false)
		expect(Rematch.leave(offer, "z")):toBe(false)
		expect(Rematch.status(offer, "a", NOW).state):toBe("Gone")
		local verdict, reason = Rematch.ask(offer, "a", NOW + 1)
		expect(verdict):toBe(nil)
		expect(reason):toBe(Rematch.Reason.Gone)
		expect(Rematch.closed(offer, NOW + 1)):toBe(false) -- "a" may still read it
		Rematch.leave(offer, "a")
		expect(Rematch.closed(offer, NOW + 1)):toBe(true)
	end)

	it("against the bot: one tap starts at once, whenever", function()
		local offer = Rematch.new("m2", { "a" }, true, NOW, 20)
		expect(Rematch.status(offer, "a", NOW + 500).state):toBe("Open")
		expect(Rematch.status(offer, "a", NOW).untilAt):toBe(nil)
		expect((Rematch.ask(offer, "a", NOW + 500))):toBe("Start")
		expect((Rematch.ask(offer, "x", NOW))):toBe(nil)
	end)
end)

describe("Lobby: a bot game while waiting (D-083)", function()
	it("is offered only after QUEUE_BOT_OFFER_SECONDS in the queue, and keeps the place in line", function()
		local lobby = Lobby.new(C)
		local wait = C.QUEUE_BOT_OFFER_SECONDS
		expect(select(2, Lobby.waitBot(lobby, "a", NOW, "Hard"))):toBe("NotQueued")
		Lobby.queue(lobby, "a", NOW)
		expect(Lobby.botAt(lobby, "a")):toBe(NOW + wait)
		expect(select(2, Lobby.waitBot(lobby, "a", NOW + wait - 1, "Hard"))):toBe("BotTooSoon")
		local outcome = Lobby.waitBot(lobby, "a", NOW + wait, "Hard") :: any
		expect(outcome.kind):toBe("Practice")
		expect(outcome.difficulty):toBe("Hard")
		expect(outcome.waiting):toBe(true)
		expect(outcome.tutorial):toBe(nil)
		expect(Lobby.state(lobby, "a")):toBe("InMatch")
		expect(table.find(lobby.queue, "a")):toBe(1)
		expect(lobby.active):toBe(1)
		expect(select(2, Lobby.waitBot(lobby, "a", NOW + wait, "Hard"))):toBe("InMatch")
		-- The bot game ends: still in line, and another one may start at once.
		Lobby.ended(lobby, { "a" })
		expect(Lobby.state(lobby, "a")):toBe("Queued")
		expect(Lobby.botAt(lobby, "a")):toBe(NOW + wait)
	end)

	it("pairs a newcomer with a player in a bot game through an offer they accept", function()
		local lobby = Lobby.new(C)
		Lobby.queue(lobby, "a", NOW)
		Lobby.waitBot(lobby, "a", NOW + 40, nil)
		local offer = Lobby.queue(lobby, "b", NOW + 50) :: any
		expect(offer.kind):toBe("Offer")
		expect(offer.players[1]):toBe("a")
		expect(offer.players[2]):toBe("b")
		expect(Lobby.state(lobby, "b")):toBe("Found")
		expect(Lobby.state(lobby, "a")):toBe("InMatch")
		local pending = Lobby.pending(lobby, "a") :: any
		expect(pending.untilAt):toBe(NOW + 50 + C.QUEUE_ACCEPT_SECONDS)
		expect(Lobby.pending(lobby, "b")):toBe(nil) -- b has nothing to answer
		expect(select(2, Lobby.answer(lobby, "b", true))):toBe("NoOffer")
		expect(select(2, Lobby.practice(lobby, "b"))):toBe("Matching")
		-- MatchService ends a's bot game first, then the answer starts the match.
		Lobby.ended(lobby, { "a" })
		local match = Lobby.answer(lobby, "a", true) :: any
		expect(match.kind):toBe("Match")
		expect(match.players[1]):toBe("a")
		expect(Lobby.state(lobby, "a")):toBe("InMatch")
		expect(Lobby.state(lobby, "b")):toBe("InMatch")
		expect(lobby.active):toBe(1)
		expect(#lobby.queue):toBe(0)
	end)

	it("a decline keeps the bot game, leaves the line, and puts the other player first", function()
		local lobby = Lobby.new(C)
		Lobby.queue(lobby, "a", NOW)
		Lobby.waitBot(lobby, "a", NOW + 40, nil)
		Lobby.queue(lobby, "b", NOW + 50)
		local declined = Lobby.answer(lobby, "a", false) :: any
		expect(declined.kind):toBe("Declined")
		expect(declined.players[1]):toBe("b")
		expect(Lobby.state(lobby, "a")):toBe("InMatch") -- still playing the bot
		expect(table.find(lobby.queue, "a")):toBe(nil)
		expect(Lobby.state(lobby, "b")):toBe("Queued")
		expect(lobby.queue[1]):toBe("b")
		-- Ending the bot game later does not put a back in line.
		Lobby.ended(lobby, { "a" })
		expect(Lobby.state(lobby, "a")):toBe("Idle")
	end)

	it("an unanswered offer expires as a decline", function()
		local lobby = Lobby.new(C)
		Lobby.queue(lobby, "a", NOW)
		Lobby.waitBot(lobby, "a", NOW + 40, nil)
		Lobby.queue(lobby, "b", NOW + 50)
		expect(#Lobby.expire(lobby, NOW + 50 + C.QUEUE_ACCEPT_SECONDS)):toBe(0)
		local expired = Lobby.expire(lobby, NOW + 51 + C.QUEUE_ACCEPT_SECONDS)
		expect(#expired):toBe(1)
		expect(expired[1].id):toBe("a")
		expect(expired[1].remote):toBe(false)
		expect(Lobby.state(lobby, "b")):toBe("Queued")
	end)

	it("the waiting player cancelling sends the bot player back to the front of the line", function()
		local lobby = Lobby.new(C)
		Lobby.queue(lobby, "a", NOW)
		Lobby.waitBot(lobby, "a", NOW + 40, nil)
		Lobby.queue(lobby, "b", NOW + 50)
		Lobby.leave(lobby, "b")
		expect(Lobby.pending(lobby, "a")):toBe(nil)
		expect(lobby.queue[1]):toBe("a")
		expect(Lobby.state(lobby, "a")):toBe("InMatch")
	end)

	it("asks a player in a bot game about an opponent on another server", function()
		local lobby = Lobby.new(C)
		Lobby.queue(lobby, "a", NOW)
		expect(Lobby.offerRemote(lobby, "a", NOW + 15)):toBe(false) -- not in a bot game: no question
		Lobby.waitBot(lobby, "a", NOW + 40, nil)
		expect(Lobby.offerRemote(lobby, "a", NOW + 55)):toBe(true)
		expect(Lobby.offerRemote(lobby, "a", NOW + 55)):toBe(false)
		Lobby.ended(lobby, { "a" })
		local accepted = Lobby.answer(lobby, "a", true) :: any
		expect(accepted.kind):toBe("Remote")
		expect(Lobby.state(lobby, "a")):toBe("Found") -- held while the match server is set up
		-- It fell through: back in line at their old place.
		Lobby.queue(lobby, "c", NOW + 60)
		Lobby.unhold(lobby, "a")
		expect(lobby.queue[1]):toBe("a")
	end)

	it("withdraws a remote question when the other server gives up first", function()
		local lobby = Lobby.new(C)
		Lobby.queue(lobby, "a", NOW)
		Lobby.waitBot(lobby, "a", NOW + 40, nil)
		Lobby.offerRemote(lobby, "a", NOW + 55)
		expect(Lobby.withdraw(lobby, "a")):toBe(true)
		expect(Lobby.pending(lobby, "a")):toBe(nil)
		expect(lobby.queue[1]):toBe("a")
		expect(Lobby.withdraw(lobby, "a")):toBe(false)
	end)
end)

describe("Lobby: holds, direct matches and capacity (D-083)", function()
	it("holds a player out of the line and gives them their place back", function()
		local lobby = Lobby.new(C)
		Lobby.queue(lobby, "a", NOW)
		Lobby.hold(lobby, "a")
		expect(Lobby.state(lobby, "a")):toBe("Found")
		-- Someone joins meanwhile: no local pairing with a held player.
		local b = Lobby.queue(lobby, "b", NOW + 5) :: any
		expect(b.kind):toBe("Waiting")
		expect(select(2, Lobby.queue(lobby, "a", NOW + 6))):toBe("Matching")
		Lobby.unhold(lobby, "a")
		expect(lobby.queue[1]):toBe("a")
		expect(lobby.queue[2]):toBe("b")
		-- The next pairing takes them both.
		local paired = Lobby.pair(lobby, NOW + 7) :: any
		expect(paired.kind):toBe("Match")
	end)

	it("a held host's code cannot be joined here while someone elsewhere joins it", function()
		local lobby = Lobby.new(C)
		Lobby.host(lobby, "h", "AB3CD")
		Lobby.hold(lobby, "h")
		expect(select(2, Lobby.join(lobby, "j", "AB3CD"))):toBe("CodeBusy")
		Lobby.unhold(lobby, "h")
		expect(Lobby.state(lobby, "h")):toBe("Hosting")
		expect((Lobby.join(lobby, "j", "AB3CD") :: any).kind):toBe("Match")
	end)

	it(
		"starts a direct match (a rematch, a match server) unless someone is busy or the server is full",
		function()
			local lobby = Lobby.new(C)
			local match = Lobby.direct(lobby, { "a", "b" }, { events = false }) :: any
			expect(match.kind):toBe("Match")
			expect(match.events):toBe(false)
			expect(select(2, Lobby.direct(lobby, { "a", "c" }))):toBe("InMatch")
			for k = 2, C.MATCHES_PER_SERVER do
				Lobby.practice(lobby, `p{k}`)
			end
			expect(select(2, Lobby.direct(lobby, { "x", "y" }))):toBe("ServerFull")
		end
	)

	it("holds a 50-player server's worth of matches", function()
		expect(C.MATCHES_PER_SERVER >= 25):toBe(true)
		expect(C.QUEUE_BOT_OFFER_SECONDS):toBe(30)
		expect(C.REMATCH_WINDOW_SECONDS > 0):toBe(true)
		expect(C.QUEUE_ACCEPT_SECONDS > 0):toBe(true)
	end)
end)

describe("Schemas: the matchmaking requests (D-083)", function()
	it("accepts WaitBot, Answer, Rematch and Return, and checks their fields", function()
		local function check(raw: any): (boolean, string?, any)
			return Schemas.request(raw)
		end
		local ok, _, request = check({ op = "WaitBot", difficulty = "Hard" })
		expect(ok):toBe(true)
		expect(request.difficulty):toBe("Hard")
		ok, _, request = check({ op = "WaitBot", difficulty = "Nightmare" })
		expect(request.difficulty):toBe("Medium")
		ok, _, request = check({ op = "Answer", accept = false })
		expect(ok):toBe(true)
		expect(request.accept):toBe(false)
		expect(select(2, check({ op = "Answer" }))):toBe("BadShape")
		expect(select(2, check({ op = "Answer", accept = "yes" }))):toBe("BadShape")
		ok, _, request = check({ op = "Rematch", matchId = "m3" })
		expect(ok):toBe(true)
		expect(request.matchId):toBe("m3")
		expect(select(2, check({ op = "Rematch" }))):toBe("BadShape")
		ok = check({ op = "Return", junk = true })
		expect(ok):toBe(true)
	end)
end)
