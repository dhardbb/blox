--!strict
-- Match records for balance analysis (D-094): what a finished session's record
-- holds, its key, its size, and that it carries no names; the per-player stats
-- and the public landslide count in Profile, and their migration.

local serde = require("@lune/serde")

local Test = require("@testlib/Test")
local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local Election = require("@sim/Election")
local MatchRecord = require("@net/MatchRecord")
local Profile = require("@net/Profile")
local Rng = require("@sim/Rng")
local Session = require("@net/Session")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function measure(value: any): number
	return #serde.encode("json", value)
end

-- Plays a human (seat 1, a bot-made input each time, except the plan weeks in
-- `idle`) against a practice bot to the end. Returns the session.
local function play(seed: number, idle: { [number]: boolean }?, options: Session.Options?): Session.Session
	local session = Session.new(C, "m7", seed, {
		{ id = "123456", kind = "Human", customName = "Zed Quill" },
		{ id = "bot", kind = "Bot", candidate = "hale", difficulty = "Medium" },
	}, 1000, options)
	local rng = Rng.new(seed)
	local t = 1000
	for _ = 1, 2000 do
		if session.stage == "Over" then
			break
		end
		local seat = session.seats[1]
		local planWeek = session.match.phase == "Plan" and (idle or {})[session.match.week]
		if session.stage == "Input" and not seat.locked and not planWeek then
			local input = Bot.act(session.config, View.build(session.config, session.match, 1), rng, "okafor")
			local ok, why = Session.submit(session, 1, session.step, input, t)
			assert(ok, `auto submit rejected: {why}`)
			continue -- a lock-in can open the next stage at once: answer it before time moves
		end
		t = math.max(t + 0.1, Session.nextWake(session))
		Session.update(session, t)
	end
	assert(session.stage == "Over", "the session never finished")
	return session
end

local function info(mode: MatchRecord.Mode?, at: number?): MatchRecord.Info
	return {
		mode = mode or "Practice",
		rated = false,
		version = "0.17.0",
		at = at or 1793232000, -- 2026-10-29 00:00 UTC
		ended = 1000 + 600,
		server = "0f3a9c2e-1111-2222-3333-444455556666",
	}
end

describe("MatchRecord: a finished match (D-094)", function()
	local session = play(41, { [3] = true })
	local record = MatchRecord.build(session, info())

	it("names the version, mode, seed, seats, candidates and the bot's level", function()
		expect(record.v):toBe(MatchRecord.SCHEMA)
		expect(record.version):toBe("0.17.0")
		expect(record.mode):toBe("Practice")
		expect(record.seed):toBe(41)
		expect(record.level):toBe("Medium")
		expect(record.seats[1].id):toBe("123456")
		expect(record.seats[1].kind):toBe("Human")
		expect(record.seats[2].id):toBe("bot")
		expect(record.seats[2].candidate):toBe("hale")
		expect(record.seats[1].candidate):toBe(session.match.players[1].candidate)
		expect(#record.seats[1].platform):toBe(#session.match.players[1].platform)
		expect(record.seats[1].home):toBe(session.match.players[1].home)
		expect(record.duration):toBe(600)
	end)

	it("keeps every week's plans, stances, debate moves, events and projected EV", function()
		local plans = record.plans :: { { { string } } }
		expect(#plans):toBe(C.WEEKS)
		-- Week 3 the human let the timer run out: an empty plan and a timeout.
		expect(#plans[3][1]):toBe(0)
		expect(record.timeouts):toEqual({ "Plan:3:1" })
		for week = 1, C.WEEKS do
			expect(#plans[week][2] > 0):toBe(true) -- the bot plans every week
			if week ~= 3 then
				expect(#plans[week][1] > 0):toBe(true)
			end
		end
		expect(#plans[2][1] > 0):toBe(true)
		expect(#plans[2][2] > 0):toBe(true)
		for _, action in plans[2][1] do
			expect(string.match(action, "^%a+:") ~= nil):toBe(true)
		end
		local choices = 0
		for _, e in session.match.eventLog do
			if e.choices then
				choices += 1
				expect(record.stances[choices].choices):toEqual(e.choices)
			end
		end
		expect(#record.stances):toBe(choices)
		expect(#record.events):toBe(#session.match.eventLog)
		expect(#record.debates):toBe(#session.match.debates)
		expect(#record.debates[1].rounds):toBe(3)
		expect(#record.debates[1].rounds[1].picks):toBe(2)
		expect(#record.projected):toBe(#session.match.pollHistory)
		expect(#record.projected[1]):toBe(3)
	end)

	it("has the final EV, winner and landslide flag from the election", function()
		local election = session.match.election :: any
		expect(record.reason):toBe("Election")
		expect(record.ev):toEqual(election.ev)
		expect(record.winner):toBe(election.winner)
		expect(record.landslide):toBe(Election.landslide(C, election) ~= nil)
		expect(record.weeks):toBe(C.WEEKS)
		expect(#record.forfeits):toBe(0)
	end)

	it("holds user ids only: no custom names", function()
		expect(string.find(serde.encode("json", record), "Zed", 1, true)):toBe(nil)
	end)

	it("is a few kilobytes of JSON, well under the limit", function()
		local size = measure(record)
		expect(size < 12000):toBe(true)
		expect(size > 500):toBe(true)
		local fitted, fittedSize = MatchRecord.fit(record, measure)
		expect(fitted):toBe(record)
		expect(fittedSize):toBe(size)
	end)

	it("keys by UTC date first, within 50 characters", function()
		local key = MatchRecord.key(record)
		expect(key):toBe("20261029_0f3a9c2e_m7_41")
		expect(#key <= 50):toBe(true)
		expect(MatchRecord.day(0)):toBe("19700101")
		expect(MatchRecord.day(951782400)):toBe("20000229")
		expect(MatchRecord.day(1793231999)):toBe("20261028")
		local long = table.clone(record)
		long.id = string.rep("a", 60) .. "/" .. string.rep("m", 30) .. "/9"
		long.seed = 2147483647
		expect(#MatchRecord.key(long) <= 50):toBe(true)
	end)

	it("drops plans, then debate rounds, when a record is too big", function()
		local calls = 0
		local fitted = MatchRecord.fit(record, function(value: any): number
			calls += 1
			return if value.plans ~= nil then MatchRecord.MAX_CHARS + 1 else 10
		end)
		expect(fitted ~= nil):toBe(true)
		local cut = fitted :: MatchRecord.Record
		expect(cut.plans):toBe(nil)
		expect(cut.trimmed):toBe(true)
		expect(#cut.debates[1].rounds):toBe(3)
		local smaller = MatchRecord.fit(record, function(value: any): number
			local rounds = if value.debates[1] then #value.debates[1].rounds else 0
			return if rounds > 0 then MatchRecord.MAX_CHARS + 1 else 10
		end) :: MatchRecord.Record
		expect(#smaller.debates[1].rounds):toBe(0)
		local none, size = MatchRecord.fit(record, function(): number
			return MatchRecord.MAX_CHARS + 5
		end)
		expect(none):toBe(nil)
		expect(size):toBe(MatchRecord.MAX_CHARS + 5)
		expect(record.plans ~= nil):toBe(true) -- the original is untouched
		expect(calls > 0):toBe(true)
	end)

	it("records a forfeit's leaver and the tutorial flag", function()
		local quit = Session.new(C, "m8", 5, {
			{ id = "1", kind = "Human" },
			{ id = "bot", kind = "Bot", candidate = "hale", difficulty = "Easy" },
		}, 0, { tutorial = true })
		Session.forfeit(quit, 1, 5)
		local r = MatchRecord.build(quit, info("Tutorial"))
		expect(r.reason):toBe("Forfeit")
		expect(r.forfeits):toEqual({ 1 })
		expect(r.tutorial):toBe(true)
		expect(r.ev):toBe(nil)
		expect(r.landslide):toBe(false)
	end)
end)

describe("Profile: stats and the public landslide count (D-094)", function()
	local function result(fields: { [string]: any }): Profile.Result
		local base: { [string]: any } = {
			at = 100,
			reason = "Election",
			rated = true,
			won = true,
			candidate = "okafor",
			opponentCandidate = "hale",
			opponentRating = 1000,
			evFor = 400,
			evAgainst = 138,
		}
		for k, v in fields do
			base[k] = v
		end
		return base :: any
	end

	it("counts a landslide publicly only in a rated public-queue match", function()
		local p = Profile.new()
		p = Profile.applyResult(p, result({ landslide = true, public = true }))
		expect(Profile.landslides(p)):toBe(1)
		p = Profile.applyResult(p, result({ landslide = true })) -- private code
		expect(Profile.landslides(p)):toBe(1)
		p = Profile.applyResult(p, result({ landslide = true, rated = false, opponentRating = nil })) -- practice
		expect(Profile.landslides(p)):toBe(1)
		p = Profile.applyResult(p, result({ landslide = false, public = true })) -- a close win
		p = Profile.applyResult(p, result({ won = false, landslide = true, public = true })) -- lost to one
		expect(Profile.landslides(p)):toBe(1)
		local stats = p.stats :: Profile.Stats
		expect(stats.landslidesAll):toBe(3)
		expect(stats.publicGames):toBe(3)
		expect(stats.privateGames):toBe(1)
		expect(stats.elections):toBe(5)
		expect(stats.evFor):toBe(2000)
		expect(stats.bestEV):toBe(400)
		expect(Profile.summary(p).landslides):toBe(1)
		expect(Profile.summary(Profile.new()).landslides):toBe(nil)
	end)

	it("counts forfeits; an abandoned match changes nothing", function()
		local p = Profile.new()
		p = Profile.applyResult(p, result({ reason = "Forfeit", won = false, evFor = nil, evAgainst = nil }))
		p = Profile.applyResult(p, result({ reason = "Forfeit", won = true, public = true }))
		local stats = p.stats :: Profile.Stats
		expect(stats.forfeitLosses):toBe(1)
		expect(stats.forfeitWins):toBe(1)
		expect(stats.elections):toBe(0)
		expect(Profile.applyResult(p, result({ reason = "Abandoned" }))):toBe(p)
	end)

	it("migrates: no stats stays none, garbage is cleaned, counts default to 0", function()
		local old = { version = 1, rating = 1100, wins = 3, losses = 1, games = 4 }
		local p = Profile.migrate(old)
		expect(p.stats):toBe(nil)
		expect(Profile.landslides(p)):toBe(0)
		local messy =
			Profile.migrate({ stats = { v = 1, landslides = -3, evFor = "x", bestEV = 0 / 0, since = 5 } })
		local stats = messy.stats :: Profile.Stats
		expect(stats.landslides):toBe(0)
		expect(stats.evFor):toBe(0)
		expect(stats.bestEV):toBe(0)
		expect(stats.since):toBe(5)
		expect(Profile.migrate({ stats = "nope" }).stats):toBe(nil)
		-- A block from before `v` existed reads as version 0, same fields.
		local early =
			Profile.migrate({ stats = { landslides = 2, landslidesAll = 1 } }).stats :: Profile.Stats
		expect(early.v):toBe(Profile.STATS_VERSION)
		expect(early.landslides):toBe(2)
		expect(early.landslidesAll):toBe(2)
		-- Round trip through the store's JSON.
		local played = Profile.applyResult(Profile.new(), result({ landslide = true, public = true }))
		local back = Profile.migrate(serde.decode("json", serde.encode("json", played)))
		expect(back.stats):toEqual(played.stats)
	end)

	it("keeps a newer stats block as it was and does not count into it", function()
		local future = { v = Profile.STATS_VERSION + 1, landslides = 7, newThing = "kept", since = 1 }
		local p = Profile.migrate({ stats = future })
		local stats = p.stats :: any
		expect(stats.v):toBe(Profile.STATS_VERSION + 1)
		expect(stats.newThing):toBe("kept")
		expect(Profile.landslides(p)):toBe(7)
		local after = Profile.applyResult(p, result({ landslide = true, public = true }))
		expect(Profile.landslides(after)):toBe(7)
		expect(Profile.withOnboard(p, 3, 0)):toBe(p)
	end)

	it("a pending result keeps its landslide and public flags", function()
		local list = Profile.cleanPending({
			{ id = "x", result = result({ landslide = true, public = true }) },
			{ id = "y", result = result({ landslide = "yes" }) },
		})
		expect(list[1].result.landslide):toBe(true)
		expect(list[1].result.public):toBe(true)
		expect(list[2].result.landslide):toBe(nil)
	end)

	it("moves the onboarding step forward only", function()
		local p = Profile.withOnboard(Profile.new(), 1, 50)
		expect((p.stats :: Profile.Stats).onboard):toBe(1)
		expect((p.stats :: Profile.Stats).since):toBe(50)
		p = Profile.withOnboard(p, 4, 60)
		p = Profile.withOnboard(p, 2, 70)
		expect((p.stats :: Profile.Stats).onboard):toBe(4)
		expect((Profile.migrate({ stats = { onboard = 500 } }).stats :: Profile.Stats).onboard):toBe(100)
	end)
end)
