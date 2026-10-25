--!strict
-- The Daily Race's rules off the engine (D-082): scoring and its tie-breaks,
-- weeks behind, the streak's lifecycle and its place in the profile, the day's
-- board, the lobby's Daily outcome, the request schema, and a Session with the
-- day's fixed candidate (claimed at Select, nobody may change it).

local Test = require("@testlib/Test")
local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local Daily = require("@net/Daily")
local Lobby = require("@net/Lobby")
local Profile = require("@net/Profile")
local Rng = require("@sim/Rng")
local Schemas = require("@net/Schemas")
local Session = require("@net/Session")
local SimDaily = require("@sim/Daily")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local DAY = 20750 -- 2026-10-24
local START = DAY * 86400

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

describe("Daily: scoring", function()
	it("ranks by margin first, then fewer weeks behind, then the earlier finish", function()
		local base = Daily.score(62, 3, START + 3600, DAY)
		check(Daily.score(64, 12, START + 80000, DAY) > base, "a bigger margin must win whatever else")
		check(Daily.score(62, 2, START + 80000, DAY) > base, "fewer weeks behind must break a margin tie")
		check(Daily.score(62, 3, START + 60, DAY) > base, "the earlier finish must break the last tie")
		check(Daily.score(62, 3, START + 7200, DAY) < base, "a later finish ranks lower")
		check(
			Daily.score(-2, 0, START, DAY) < Daily.score(0, 12, START + 86399, DAY),
			"a loss is below a tie"
		)
	end)

	it("is a whole number that decodes back", function()
		for _, case in { { 62, 3, 3600 }, { -538, 99, 0 }, { 538, 0, 86399 }, { 0, 12, 43210 } } do
			local score = Daily.score(case[1], case[2], START + case[3], DAY)
			expect(score):toBe(math.floor(score))
			check(score >= 0 and score < 2 ^ 53, "out of range")
			local margin, behind, at = Daily.decode(score)
			expect({ margin, behind, at }):toEqual(case)
		end
	end)

	it("clamps what it cannot hold", function()
		local margin, behind, at = Daily.decode(Daily.score(900, 400, START - 50, DAY))
		expect({ margin, behind, at }):toEqual({ 538, 99, 0 })
		-- A run that ended after midnight counts as the day's last second.
		local _, _, late = Daily.decode(Daily.score(10, 1, START + 90000, DAY))
		expect(late):toBe(86399)
	end)

	it("scores a forfeit (Config) below every finished run", function()
		expect(C.DAILY_FORFEIT_MARGIN):toBe(-538)
		local forfeit = Daily.score(C.DAILY_FORFEIT_MARGIN, Daily.BEHIND_MAX, START, DAY)
		check(forfeit < Daily.score(-536, 12, START + 86399, DAY), "a forfeit must rank last")
	end)

	it("counts the poll weeks where someone else led", function()
		local history = {
			{ week = 1, ev = { 270, 268 } },
			{ week = 2, ev = { 260, 278 } },
			{ week = 3, ev = { 269, 269 } }, -- a tie is not behind
			{ week = 4, ev = { 200, 338 } },
		}
		expect(Daily.weeksBehind(history, 1)):toBe(2)
		expect(Daily.weeksBehind(history, 2)):toBe(1)
		expect(Daily.weeksBehind(nil, 1)):toBe(0)
	end)

	it("writes margins for the board", function()
		expect(Daily.marginText(62)):toBe("+62")
		expect(Daily.marginText(-40)):toBe("-40")
		expect(Daily.marginText(0)):toBe("0")
	end)
end)

describe("Daily: the streak", function()
	it("starts at 1, grows a day at a time, and a counted day counts once", function()
		local r = Daily.begin(nil, DAY)
		expect(r.streak):toBe(1)
		expect(Daily.counted(r, DAY)):toBe(true)
		expect(Daily.counted(r, DAY + 1)):toBe(false)
		expect(Daily.begin(r, DAY)):toBe(r) -- the same day again: unchanged
		local r2 = Daily.begin(r, DAY + 1)
		local r3 = Daily.begin(r2, DAY + 2)
		expect(r3.streak):toBe(3)
		expect(r3.best):toBe(3)
	end)

	it("shows the streak today and tomorrow, 0 after a missed day, with nothing else lost", function()
		local r = Daily.begin(Daily.begin(nil, DAY - 1), DAY)
		expect(Daily.streak(r, DAY)):toBe(2)
		expect(Daily.streak(r, DAY + 1)):toBe(2) -- not played yet today: still alive
		expect(Daily.streak(r, DAY + 2)):toBe(0) -- a day missed
		expect(Daily.streak(nil, DAY)):toBe(0)
		local again = Daily.begin(r, DAY + 2)
		expect(again.streak):toBe(1)
		expect(again.best):toBe(2) -- the best streak is kept
	end)

	it("saves a run's result once, and only for its own day", function()
		local r = Daily.begin(nil, DAY)
		local done = Daily.finish(r, DAY, 62, 3, 12345) :: Daily.Record
		expect(done.margin):toBe(62)
		expect(done.score):toBe(12345)
		expect(Daily.finish(done, DAY, -10, 9, 1)):toBe(done) -- a second end changes nothing
		expect(Daily.finish(r, DAY + 1, 5, 0, 1)):toBe(r) -- another day's run changes nothing
		expect(Daily.finish(nil, DAY, 5, 0, 1)):toBe(nil)
		expect(done.streak):toBe(1)
	end)

	it("cleans a stored record and drops garbage", function()
		expect(Daily.clean(nil)):toBe(nil)
		expect(Daily.clean("x")):toBe(nil)
		expect(Daily.clean({ last = "today", streak = 2 })):toBe(nil)
		expect(Daily.clean({ last = DAY, streak = 0 })):toBe(nil)
		local r =
			Daily.clean({ last = DAY, streak = 4.7, best = 2, margin = 900, behind = 1, score = 5 }) :: Daily.Record
		expect(r.streak):toBe(4)
		expect(r.best):toBe(4) -- never below the streak
		expect(r.margin):toBe(538)
		local partial = Daily.clean({ last = DAY, streak = 1, margin = 3 }) :: Daily.Record
		expect(partial.margin):toBe(nil) -- a result needs all three fields
	end)

	it("lives in the profile: saved, migrated, copied, never the rating or the practice record", function()
		local p = Profile.new(C)
		local begun = Profile.withDailyBegun(p, DAY)
		expect(p.daily):toBe(nil) -- the old profile is untouched
		local done = Profile.withDailyResult(begun, DAY, 62, 3, 999)
		local d = done.daily :: Daily.Record
		expect(d.margin):toBe(62)
		expect(done.rating):toBe(p.rating)
		expect(done.practice):toEqual(p.practice)
		expect(Profile.needsTutorial(done)):toBe(true) -- a Daily Race is not the tutorial
		local back = Profile.migrate(done, C)
		expect(back.daily):toEqual(done.daily)
		expect(Profile.migrate({ version = 1, daily = { last = "x" } }, C).daily):toBe(nil)
		expect(Profile.migrate({ version = 1 }, C).daily):toBe(nil)
	end)
end)

describe("Daily: the day's board", function()
	local function name(id: string): string
		return `user{id}`
	end

	it("ranks a page by score and skips rows this game would not write", function()
		local entries = Daily.fromPage({
			{ key = "Player_1", value = Daily.score(10, 3, START + 100, DAY) },
			{ key = "Player_2", value = Daily.score(40, 3, START + 100, DAY) },
			{ key = "Player_3", value = Daily.score(10, 1, START + 100, DAY) },
			{ key = "Player_2", value = 5 },
			{ key = "Other_4", value = 1 },
			{ key = "Player_5", value = -3 },
			"junk",
		}, name)
		expect(#entries):toBe(3)
		expect(entries[1].id):toBe("2")
		expect(entries[1].margin):toBe(40)
		expect(entries[2].id):toBe("3") -- fewer weeks behind
		expect(entries[3].id):toBe("1")
		expect(entries[3].rank):toBe(3)
	end)

	it("keeps at most the top 50 and moves a player in at once", function()
		local rows = {}
		for k = 1, 70 do
			table.insert(rows, { key = `Player_{k}`, value = Daily.score(k, 0, START, DAY) })
		end
		local entries = Daily.fromPage(rows, name)
		expect(#entries):toBe(Daily.TOP)
		local after = Daily.patch(entries, "999", "me", Daily.score(65, 0, START + 10, DAY))
		expect(Daily.rankOf(after, "999")):toBe(7) -- 70 .. 66 and the earlier 65 first
		expect(Daily.rankOf(entries, "999")):toBe(nil)
	end)

	it("tells the viewer their place, or their margin outside the top list", function()
		local entries = Daily.fromPage({ { key = "Player_1", value = Daily.score(10, 0, START, DAY) } }, name)
		local listed = Daily.board("Ok", entries, "1", nil, DAY)
		expect(listed.you):toEqual({ rank = 1, margin = 10 })
		local record = Daily.finish(Daily.begin(nil, DAY), DAY, -4, 2, 1)
		local outside = Daily.board("Ok", entries, "2", record, DAY)
		expect(outside.you):toEqual({ margin = -4 })
		expect(Daily.board("Ok", entries, "2", record, DAY + 1).you):toBe(nil) -- yesterday's run
		expect(Daily.board("Ok", entries, "3", nil, DAY).you):toBe(nil)
	end)
end)

describe("Daily: lobby and requests", function()
	it("starts a Daily Race as a practice match against the day's level, never the tutorial", function()
		local lobby = Lobby.new(C)
		local outcome = Lobby.daily(lobby, "100", DAY, C.DAILY_BOT_LEVEL) :: Lobby.Outcome
		expect(outcome.kind):toBe("Practice")
		expect(outcome.daily):toBe(DAY)
		expect(outcome.difficulty):toBe("Extreme")
		expect(outcome.tutorial):toBe(nil)
		local _, reason = Lobby.daily(lobby, "100", DAY, "Extreme")
		expect(reason):toBe("InMatch")
	end)

	it("accepts the two new ops with no fields", function()
		for _, op in { "DailyRace", "Daily" } do
			local ok, _, request = Schemas.request({ op = op, extra = "ignored" })
			expect(ok):toBe(true)
			expect((request :: any).op):toBe(op)
		end
	end)
end)

describe("Daily: a session with the day's candidate", function()
	local race = SimDaily.race(C, DAY)

	local function daily(tutorial: boolean?): Session.Session
		return Session.new(C, "d1", race.seed, {
			{ id = "100", kind = "Human", candidate = race.candidate },
			{ id = "bot", kind = "Bot", candidate = race.botCandidate, difficulty = race.level },
		}, 0, { tutorial = tutorial, daily = { day = DAY, counted = true } })
	end

	it("claims the day's candidate for the player as Select opens (straight to the issues)", function()
		local session = daily()
		local payload = Session.payload(session, 1)
		expect(payload.view.phase):toBe("Select")
		expect(payload.view.claims[race.candidate]):toBe(1)
		expect(payload.view.claims[race.botCandidate]):toBe(2)
		expect(payload.daily):toEqual({ day = DAY, counted = true })
		expect(payload.seats[2].difficulty):toBe("Extreme")
	end)

	it("uses the x1 timer (Extreme) and is never the tutorial", function()
		local session = daily(true)
		expect(session.tutorial):toBe(false)
		expect(session.timeScale):toBe(1)
		local payload = Session.payload(session, 1)
		expect(payload.tutorial):toBe(nil)
		check(math.abs((payload.deadline :: number) - C.TIMER_SELECT) < 1e-6, "Select is not the plain timer")
	end)

	it("turns down another candidate, by claim or by lock-in", function()
		local session = daily()
		local other = if race.candidate == "okafor" then "venkat" else "okafor"
		if other == race.botCandidate then
			other = "strand"
		end
		local ok, reason = Session.claim(session, 1, session.step, other, 1)
		expect(ok):toBe(false)
		expect(reason):toBe("AlreadyClaimed")
		ok, reason = Session.submit(
			session,
			1,
			session.step,
			{ candidate = other, platform = { "Jobs", "Health", "Schools" } },
			1
		)
		expect(ok):toBe(false)
		expect(reason):toBe("AlreadyClaimed")
		ok = Session.submit(
			session,
			1,
			session.step,
			{ candidate = race.candidate, platform = { "Jobs", "Health", "Schools" } },
			1
		)
		expect(ok):toBe(true)
	end)

	it("keeps the day's candidate when Select runs out, and the player picks their own issues", function()
		local session = daily()
		Session.update(session, C.TIMER_SELECT + 1)
		expect(session.match.players[1].candidate):toBe(race.candidate)
		expect(session.match.players[2].candidate):toBe(race.botCandidate)
		expect(#session.match.players[1].platform):toBe(C.PLATFORM_SIZE)
	end)

	it("plays the same bot moves for everyone who plays the same moves that day", function()
		local function botPlatform(id: string): { string }
			local session = Session.new(C, "d", race.seed, {
				{ id = id, kind = "Human", candidate = race.candidate },
				{ id = "bot", kind = "Bot", candidate = race.botCandidate, difficulty = race.level },
			}, 0, { daily = { day = DAY, counted = true } })
			local view = View.build(C, session.match, 1)
			local mine = Bot.act(C, view, Rng.new(1), race.candidate)
			Session.submit(session, 1, session.step, mine, 1)
			Session.update(session, 2)
			return session.match.players[2].platform
		end
		expect(botPlatform("100")):toEqual(botPlatform("200"))
	end)
end)
