--!strict
-- Admin "Timers off" (D-081): the choice timers turn off only while every human
-- in the match is an admin and one of them has the toggle on; a match with any
-- other human keeps its timers. Mid-match changes act at once on an open
-- choice; a match between people with the timers off is unrated; the bot
-- still answers at once; the request schema and the saved toggle.

local Test = require("@testlib/Test")
local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local Profile = require("@net/Profile")
local Rng = require("@sim/Rng")
local Schemas = require("@net/Schemas")
local Session = require("@net/Session")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local NO = Session.NO_DEADLINE

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function near(got: number, want: number)
	check(math.abs(got - want) < 1e-6, `expected {want}, got {got}`)
end

local function human(id: string, admin: boolean?, off: boolean?): Session.SeatSpec
	return { id = id, kind = "Human", admin = admin, timersOff = off }
end

local function bot(difficulty: Bot.Difficulty?): Session.SeatSpec
	return { id = "bot", kind = "Bot", candidate = "hale", difficulty = difficulty }
end

local function new(specs: { Session.SeatSpec }, options: Session.Options?): Session.Session
	return Session.new(C, "a1", 7, specs, 0, options)
end

local function notices(session: Session.Session, seat: number): { string }
	local out = {}
	for _, message in Session.drain(session) do
		if message.kind == "Notice" and message.seat == seat then
			table.insert(out, message.notice :: string)
		end
	end
	return out
end

local function auto(session: Session.Session, p: number): any
	local view = View.build(C, session.match, p)
	return Bot.act(C, view, Rng.new(p), "okafor")
end

-- Plays on until the match is over: every human seat locks in `think` seconds
-- into each Input stage; Show and Reveal stages run out. `during(session)` runs
-- once at the start of every stage (it may toggle things).
local function playOut(session: Session.Session, think: number, during: ((Session.Session) -> ())?)
	local t = session.stageStart
	local lastStep = -1
	for _ = 1, 600 do
		if session.stage == "Over" then
			return
		end
		if session.step ~= lastStep then
			lastStep = session.step
			if during then
				during(session)
			end
		end
		if session.stage == "Input" then
			local open: number? = nil
			for p, seat in session.seats do
				if seat.kind == "Human" and not seat.locked then
					open = p
					break
				end
			end
			if open then
				t = math.max(t, session.stageStart + think)
				local ok, reason = Session.submit(session, open, session.step, auto(session, open), t)
				assert(ok, `submit rejected: {reason}`)
				continue
			end
		end
		t = math.max(t, Session.nextWake(session))
		Session.update(session, t)
	end
	error("the match did not end")
end

describe("Session: who gets the admin rule (D-081)", function()
	it("an admin against the bot with Timers off: no choice deadline, told once", function()
		local session = new({ human("1", true, true), bot("Hard") })
		local allowed, on = Session.adminRule(session)
		expect(allowed):toBe(true)
		expect(on):toBe(true)
		expect(session.stage):toBe("Input")
		expect(session.deadline):toBe(NO)
		local payload = Session.payload(session, 1)
		expect(payload.deadline):toBe(nil)
		expect(payload.adminNoTimer):toBe(true)
		expect(payload.tutorial):toBe(nil)
		check(payload.adminTimers ~= nil, "the admin's seat has no toggle state")
		expect((payload.adminTimers :: any).on):toBe(true)
		expect((payload.adminTimers :: any).allowed):toBe(true)
		local said = notices(session, 1)
		expect(said[1]):toBe(Session.ADMIN_TIMERS_OFF) -- one human: nothing about ratings
		-- The bot still answers at once.
		expect(session.seats[2].locked):toBe(true)
		-- A day later Select is still waiting.
		Session.update(session, 86400)
		expect(session.match.phase):toBe("Select")
		expect(session.stage):toBe("Input")
	end)

	it("a Daily Race keeps its timers for an admin with Timers off (D-082)", function()
		local session = new(
			{ human("1", true, true), bot("Hard") },
			{ daily = { day = 20000, counted = true } }
		)
		local allowed, on = Session.adminRule(session)
		expect(allowed):toBe(false)
		expect(on):toBe(false)
		near(session.deadline, C.TIMER_SELECT)
		local payload = Session.payload(session, 1)
		expect(payload.adminNoTimer):toBe(nil)
		expect((payload.adminTimers :: any).allowed):toBe(false)
		expect(#notices(session, 1)):toBe(0)
		local ok = Session.setTimersOff(session, 1, true, 1)
		expect(ok):toBe(true) -- saved, but the rule does not change
		near(session.deadline, C.TIMER_SELECT)
	end)

	it("an admin with the toggle off plays with timers", function()
		local session = new({ human("1", true, false), bot("Hard") })
		near(session.deadline, C.TIMER_SELECT)
		local payload = Session.payload(session, 1)
		expect(payload.adminNoTimer):toBe(nil)
		expect((payload.adminTimers :: any).on):toBe(false)
		expect(#notices(session, 1)):toBe(0)
	end)

	it("two admins: one toggle on is enough, for both of them", function()
		local session = new({ human("1", true, false), human("2", true, true) })
		expect(session.deadline):toBe(NO)
		for p = 1, 2 do
			local payload = Session.payload(session, p)
			expect(payload.deadline):toBe(nil)
			expect(payload.adminNoTimer):toBe(true)
			expect((payload.adminTimers :: any).allowed):toBe(true)
		end
		expect(notices(session, 1)[1]):toBe(Session.ADMIN_TIMERS_OFF_UNRATED)
	end)

	it("never stalls anyone else: an admin with Timers off against a non-admin keeps the timers", function()
		local session = new({ human("1", true, true), human("2", false) })
		local allowed, on = Session.adminRule(session)
		expect(allowed):toBe(false)
		expect(on):toBe(false)
		near(session.deadline, C.TIMER_SELECT)
		local mine = Session.payload(session, 1)
		expect(mine.adminNoTimer):toBe(nil)
		expect((mine.adminTimers :: any).on):toBe(true)
		expect((mine.adminTimers :: any).allowed):toBe(false)
		-- The other player learns nothing about admins.
		local theirs = Session.payload(session, 2)
		expect(theirs.adminTimers):toBe(nil)
		expect(theirs.adminNoTimer):toBe(nil)
		-- The toggle mid-match is kept but changes nothing.
		Session.drain(session)
		local ok = Session.setTimersOff(session, 1, true, 5)
		expect(ok):toBe(true)
		near(session.deadline, C.TIMER_SELECT)
		expect(#notices(session, 2)):toBe(0)
		-- The Select timer still runs out on time.
		Session.update(session, C.TIMER_SELECT + 0.01)
		check(session.match.phase ~= "Select" or session.stage ~= "Input", "Select did not close on time")
	end)

	it("a non-admin's own timersOff (from anywhere) is ignored", function()
		local session = new({ human("1", false, true), bot() })
		expect(session.seats[1].timersOff):toBe(false)
		check(session.deadline < NO, "a non-admin got no deadline")
		expect(Session.payload(session, 1).adminTimers):toBe(nil)
	end)
end)

describe("Session.setTimersOff (D-081)", function()
	it("turns off mid-step, waits, then back on with a fresh full timer", function()
		local session = new({ human("1", true, false), bot("Easy") })
		Session.drain(session)
		local full = C.TIMER_SELECT * C.BOT_TIME_MULT_EASY
		near(session.deadline, full)
		local step = session.step
		local ok, reason = Session.setTimersOff(session, 1, true, 10)
		expect(ok):toBe(true)
		expect(reason):toBe(nil)
		expect(session.step):toBe(step) -- the same step: an in-flight lock-in still counts
		expect(session.deadline):toBe(NO)
		expect(Session.payload(session, 1).deadline):toBe(nil)
		expect(notices(session, 1)[1]):toBe(Session.ADMIN_TIMERS_OFF)
		Session.update(session, 5000)
		expect(session.stage):toBe("Input")
		expect(session.match.phase):toBe("Select")
		-- Back on at 5000: the whole (Easy x2) Select timer from now.
		ok = Session.setTimersOff(session, 1, false, 5000)
		expect(ok):toBe(true)
		expect(session.stageStart):toBe(5000)
		near(session.deadline, 5000 + full)
		near(Session.payload(session, 1).deadline :: number, 5000 + full)
		expect(Session.payload(session, 1).adminNoTimer):toBe(nil)
		expect(notices(session, 1)[1]):toBe(Session.ADMIN_TIMERS_ON)
		Session.update(session, 5000 + full - 1)
		expect(session.match.phase):toBe("Select")
		Session.update(session, 5000 + full + 0.01)
		check(session.match.phase ~= "Select", "Select did not close when its fresh timer ran out")
	end)

	it("off during a reveal: the reveal runs on, the next choice has no deadline", function()
		local session = new({ human("1", true, false), bot("Hard") })
		-- Lock in Select; the map reveal (a Show stage) follows.
		local ok = Session.submit(session, 1, session.step, auto(session, 1), 1)
		expect(ok):toBe(true)
		expect(session.stage):toBe("Show")
		local showEnd = session.deadline
		check(showEnd < NO, "the map reveal has no end")
		Session.setTimersOff(session, 1, true, 2)
		expect(session.deadline):toBe(showEnd) -- reveals keep their time
		expect(Session.payload(session, 1).deadline):toBe(showEnd)
		Session.update(session, showEnd + 0.01)
		expect(session.match.phase):toBe("Draft")
		expect(session.stage):toBe("Input")
		expect(session.deadline):toBe(NO)
		expect(Session.payload(session, 1).deadline):toBe(nil)
	end)

	it("no time bank and no reconnect window while the timers are off", function()
		local session = new({ human("1", true, true), human("2", true) })
		-- Play to the first plan.
		local t = 0
		for _ = 1, 200 do
			if session.match.phase == "Plan" and session.stage == "Input" then
				break
			end
			if session.stage == "Input" then
				for p = 1, 2 do
					if not session.seats[p].locked then
						t += 1
						Session.submit(session, p, session.step, auto(session, p), t)
					end
				end
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
		expect(session.match.phase):toBe("Plan")
		local okBank, why = Session.bank(session, 1, session.step, t)
		expect(okBank):toBe(false)
		expect(why):toBe(Session.Reason.NoTimer)
		Session.disconnect(session, 2, t)
		Session.reconnect(session, 2, t + 1)
		expect(session.seats[2].bankUsed):toBe(0)
		expect(session.deadline):toBe(NO)
	end)

	it("turns down a non-admin, a bot seat and a finished match, never throwing", function()
		local session = new({ human("1", true), human("2", false) })
		local ok, reason = Session.setTimersOff(session, 2, true, 1)
		expect(ok):toBe(false)
		expect(reason):toBe(Session.Reason.AdminOnly)
		expect(session.seats[2].timersOff):toBe(false)
		local vsBot = new({ human("1", true), bot() })
		ok, reason = Session.setTimersOff(vsBot, 2, true, 1)
		expect(ok):toBe(false)
		expect(reason):toBe(Session.Reason.AdminOnly)
		ok, reason = Session.setTimersOff(vsBot, 9, true, 1)
		expect(ok):toBe(false)
		expect(reason):toBe(Session.Reason.AdminOnly)
		Session.forfeit(vsBot, 1, 2)
		ok, reason = Session.setTimersOff(vsBot, 1, true, 3)
		expect(ok):toBe(false)
		expect(reason):toBe(Session.Reason.Over)
	end)

	it("the tutorial stays untimed whatever the toggle says", function()
		local session = new({ human("1", true, true), bot("Easy") }, { tutorial = true })
		expect(session.deadline):toBe(NO)
		local said = notices(session, 1)
		expect(said[1]):toBe(Session.TUTORIAL)
		Session.setTimersOff(session, 1, false, 4)
		expect(session.deadline):toBe(NO)
		expect(Session.payload(session, 1).tutorial):toBe(true)
	end)
end)

describe("Session: ratings with the timers off (D-081)", function()
	it("two admins who had the timers off at any point: unrated, flagged timersOff", function()
		local session = new({ human("1", true), human("2", true) })
		local turnedOn = false
		playOut(session, 1, function(s)
			if s.match.phase == "Plan" and s.match.week == 2 and not turnedOn then
				turnedOn = true
				Session.setTimersOff(s, 2, true, s.stageStart)
			elseif s.match.phase == "Plan" and s.match.week == 3 and s.seats[2].timersOff then
				Session.setTimersOff(s, 2, false, s.stageStart) -- back on: still unrated
			end
		end)
		local result = session.result :: Session.Result
		expect(result.reason):toBe("Election")
		expect(result.unrated):toBe(true)
		expect(result.timersOff):toBe(true)
	end)

	it("two admins who never turned them off: rated as usual", function()
		local session = new({ human("1", true), human("2", true) })
		playOut(session, 1)
		local result = session.result :: Session.Result
		expect(result.reason):toBe("Election")
		expect(result.unrated):toBe(nil)
		expect(result.timersOff):toBe(nil)
	end)

	it("an admin against the bot: a whole match with no deadline, no rating flags", function()
		local session = new({ human("1", true, true), bot("Medium") })
		local stages = 0
		playOut(session, 30, function(s)
			if s.stage == "Input" then
				stages += 1
				expect(s.deadline):toBe(NO)
				expect(Session.payload(s, 1).deadline):toBe(nil)
			else
				check(s.deadline < NO, "a reveal lost its time")
			end
		end)
		check(stages > 10, "too few choice steps seen")
		local result = session.result :: Session.Result
		expect(result.reason):toBe("Election")
		expect(result.unrated):toBe(nil)
		expect(result.timersOff):toBe(nil)
	end)

	it("an early forfeit keeps D-077's reason, not the timers'", function()
		local session = new({ human("1", true, true), human("2", true) })
		Session.forfeit(session, 1, 1)
		local result = session.result :: Session.Result
		expect(result.unrated):toBe(true)
		expect(result.timersOff):toBe(nil)
	end)
end)

describe("SetTimersOff request and saved toggle (D-081)", function()
	it("needs a boolean `on`, keeps nothing else", function()
		local ok, reason, request = Schemas.request({ op = "SetTimersOff", on = true, admin = true })
		expect(ok):toBe(true)
		expect(reason):toBe(nil)
		expect((request :: any).on):toBe(true)
		expect((request :: any).admin):toBe(nil)
		ok, reason = Schemas.request({ op = "SetTimersOff", on = false })
		expect(ok):toBe(true)
		for _, bad in { {}, { on = "yes" }, { on = 1 } } do
			local raw: any = table.clone(bad)
			raw.op = "SetTimersOff"
			ok, reason = Schemas.request(raw)
			expect(ok):toBe(false)
			expect(reason):toBe("BadShape")
		end
	end)

	it("is saved as adminTimersOff, off as no field, and survives migrate", function()
		local profile = Profile.new(C)
		expect(profile.adminTimersOff):toBe(nil)
		local on = Profile.withTimersOff(profile, true)
		expect(on.adminTimersOff):toBe(true)
		expect(profile.adminTimersOff):toBe(nil) -- a copy
		expect(Profile.migrate(on, C).adminTimersOff):toBe(true)
		expect(Profile.withTimersOff(on, false).adminTimersOff):toBe(nil)
		expect(Profile.migrate({ adminTimersOff = "yes" }, C).adminTimersOff):toBe(nil)
	end)
end)
