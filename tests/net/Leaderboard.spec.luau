--!strict
-- The global leaderboard's pure rules (Net/Leaderboard, D-059), leaving a match
-- (Session.forfeit, D-059) and the requests behind both (Net/Schemas).

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local Leaderboard = require("@net/Leaderboard")
local Schemas = require("@net/Schemas")
local Session = require("@net/Session")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function name(id: string): string
	return `user{id}`
end

local function ids(entries: { Leaderboard.Entry }): string
	local out = {}
	for _, entry in entries do
		table.insert(out, `{entry.rank}:{entry.id}`)
	end
	return table.concat(out, " ")
end

describe("Leaderboard: reading a page", function()
	it("ranks by rating, best first, and names each player", function()
		local entries = Leaderboard.fromPage({
			{ key = "Player_7", value = 1010 },
			{ key = "Player_3", value = 1200 },
			{ key = "Player_9", value = 990 },
		}, name)
		expect(ids(entries)):toBe("1:3 2:7 3:9")
		expect(entries[1].name):toBe("user3")
		expect(entries[1].rating):toBe(1200)
	end)

	it("puts equal ratings in a fixed order (smaller id first)", function()
		local a = Leaderboard.fromPage({
			{ key = "Player_20", value = 1000 },
			{ key = "Player_100", value = 1000 },
			{ key = "Player_3", value = 1000 },
		}, name)
		local b = Leaderboard.fromPage({
			{ key = "Player_3", value = 1000 },
			{ key = "Player_100", value = 1000 },
			{ key = "Player_20", value = 1000 },
		}, name)
		expect(ids(a)):toBe("1:3 2:20 3:100")
		expect(ids(b)):toBe(ids(a))
	end)

	it("skips rows this game would not write and keeps one row per player", function()
		local entries = Leaderboard.fromPage({
			{ key = "Player_1", value = 1100 },
			{ key = "Player_1", value = 900 },
			{ key = "Other_2", value = 1500 },
			{ key = "Player_x", value = 1500 },
			{ key = "Player_4", value = "lots" },
			{ key = "Player_5", value = 0 / 0 },
			"junk",
			{ key = "Player_6", value = 1050.7 },
		}, name)
		expect(ids(entries)):toBe("1:1 2:6")
		expect(entries[2].rating):toBe(1050)
	end)

	it("keeps at most the top 50", function()
		local rows = {}
		for k = 1, 80 do
			table.insert(rows, { key = `Player_{k}`, value = 1000 + k })
		end
		local entries = Leaderboard.fromPage(rows, name)
		expect(#entries):toBe(Leaderboard.TOP)
		expect(entries[1].id):toBe("80")
		expect(entries[50].id):toBe("31")
		expect(entries[50].rank):toBe(50)
	end)

	it("reads an empty page as an empty list", function()
		expect(#Leaderboard.fromPage({}, name)):toBe(0)
	end)

	it("keys a player as Player_<UserId> and reads only such keys back", function()
		expect(Leaderboard.keyOf("123")):toBe("Player_123")
		expect(Leaderboard.idOf("Player_123")):toBe("123")
		expect(Leaderboard.idOf("Player_")):toBe(nil)
		expect(Leaderboard.idOf(42)):toBe(nil)
	end)

	it("cleans names: a fallback for a missing one, cut to 32 characters", function()
		expect(Leaderboard.cleanName(nil, "5")):toBe("Player 5")
		expect(Leaderboard.cleanName("", "5")):toBe("Player 5")
		expect(#Leaderboard.cleanName(string.rep("a", 60), "5")):toBe(Leaderboard.MAX_NAME)
	end)
end)

describe("Leaderboard: moving one player", function()
	local base = Leaderboard.fromPage({
		{ key = "Player_1", value = 1200 },
		{ key = "Player_2", value = 1100 },
		{ key = "Player_3", value = 1000 },
	}, name)

	it("moves a listed player to their new place", function()
		local after = Leaderboard.patch(base, "3", "user3", 1150)
		expect(ids(after)):toBe("1:1 2:3 3:2")
		expect(after[2].rating):toBe(1150)
		expect(ids(base)):toBe("1:1 2:2 3:3") -- the old list is untouched
	end)

	it("adds a newcomer, and drops whoever falls out of a full top 50", function()
		local rows = {}
		for k = 1, 50 do
			table.insert(rows, { key = `Player_{k}`, value = 1000 + k })
		end
		local full = Leaderboard.fromPage(rows, name)
		local after = Leaderboard.patch(full, "999", "newcomer", 1025)
		expect(#after):toBe(50)
		expect(Leaderboard.rankOf(after, "999") ~= nil):toBe(true)
		expect(Leaderboard.rankOf(after, "1")):toBe(nil) -- 1001, the lowest, fell out
		local low = Leaderboard.patch(full, "998", "low", 500)
		expect(Leaderboard.rankOf(low, "998")):toBe(nil)
	end)
end)

describe("Leaderboard: what a viewer is sent", function()
	local entries = Leaderboard.fromPage({
		{ key = "Player_1", value = 1200 },
		{ key = "Player_2", value = 1100 },
	}, name)

	it("gives a listed viewer their rank", function()
		local board = Leaderboard.board("Ok", entries, "2", 1100)
		expect(board.status):toBe("Ok")
		expect(#board.entries):toBe(2)
		expect(board.you and board.you.rank):toBe(2)
		expect(board.you and board.you.rating):toBe(1100)
	end)

	it("gives a ranked viewer outside the list only their rating", function()
		local board = Leaderboard.board("Ok", entries, "77", 1004)
		expect(board.you and board.you.rank):toBe(nil)
		expect(board.you and board.you.rating):toBe(1004)
	end)

	it("says nothing about a viewer with no rated games", function()
		local board = Leaderboard.board("Ok", entries, "77", nil)
		expect(board.you):toBe(nil)
	end)

	it("hands out copies, never the cached rows", function()
		local board = Leaderboard.board("Ok", entries, "1", 1200)
		board.entries[1].rating = 0
		expect(entries[1].rating):toBe(1200)
	end)
end)

describe("Requests: Leaderboard and Forfeit", function()
	it("accepts Leaderboard with no fields", function()
		local ok, _, request = Schemas.request({ op = "Leaderboard" })
		expect(ok):toBe(true)
		expect(request and request.op):toBe("Leaderboard")
	end)

	it("accepts Forfeit only with the match id", function()
		local ok, _, request = Schemas.request({ op = "Forfeit", matchId = "m4" })
		expect(ok):toBe(true)
		expect(request and request.matchId):toBe("m4")
		local bad, reason = Schemas.request({ op = "Forfeit" })
		expect(bad):toBe(false)
		expect(reason):toBe("BadShape")
		expect((Schemas.request({ op = "Forfeit", matchId = 4 }))):toBe(false)
	end)
end)

describe("Session: leaving a match (D-059)", function()
	local function humans(): Session.Session
		return Session.new(C, "m1", 7, {
			{ id = "100", kind = "Human" },
			{ id = "200", kind = "Human" },
		}, 0)
	end

	it("ends the match at once as a forfeit won by the other seat, and says why", function()
		local session = humans()
		Session.drain(session)
		local ok, reason = Session.forfeit(session, 1, 5)
		expect(ok):toBe(true)
		expect(reason):toBe(nil)
		expect(session.stage):toBe("Over")
		local result = session.result :: Session.Result
		expect(result.winner):toBe(2)
		expect(result.reason):toBe("Forfeit")
		local notices, states = 0, 0
		for _, message in Session.drain(session) do
			if message.kind == "Notice" then
				expect(message.seat):toBe(2)
				expect(message.notice):toBe(Session.OPPONENT_FORFEITED)
				notices += 1
			elseif message.kind == "State" then
				expect(message.state and message.state.stage):toBe("Over")
				states += 1
			end
		end
		expect(notices):toBe(1)
		expect(states):toBe(2) -- both seats see the end
	end)

	it("works from any stage, the second seat too", function()
		local session = humans()
		Session.update(session, C.TIMER_SELECT) -- on to the map reveal
		check(session.stage ~= "Input", "still in Select")
		expect((Session.forfeit(session, 2, C.TIMER_SELECT + 1))):toBe(true)
		expect((session.result :: Session.Result).winner):toBe(1)
	end)

	it("a second request changes nothing", function()
		local session = humans()
		Session.forfeit(session, 1, 5)
		Session.drain(session)
		local step = session.step
		local ok, reason = Session.forfeit(session, 1, 6)
		expect(ok):toBe(false)
		expect(reason):toBe("Over")
		expect(session.step):toBe(step)
		expect((session.result :: Session.Result).winner):toBe(2)
		expect(#Session.drain(session)):toBe(0)
	end)

	it("in practice the bot wins; nobody is told (the bot has no screen)", function()
		local session = Session.new(C, "m2", 7, {
			{ id = "100", kind = "Human" },
			{ id = "bot", kind = "Bot", candidate = "hale" },
		}, 0)
		Session.drain(session)
		expect((Session.forfeit(session, 1, 3))):toBe(true)
		expect((session.result :: Session.Result).winner):toBe(2)
		for _, message in Session.drain(session) do
			expect(message.kind):toBe("State")
		end
	end)
end)
