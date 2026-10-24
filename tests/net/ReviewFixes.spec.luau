--!strict
-- Regressions from the 0.13 server review: a debate's grace use, the debate
-- move a rejoining player sees, forfeits with more than two players, and a
-- forfeit before week 1 leaving the match unrated (D-075).

local Test = require("@testlib/Test")
local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local Rng = require("@sim/Rng")
local Session = require("@net/Session")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function humans(count: number?): Session.Session
	local specs: { Session.SeatSpec } = {}
	for k = 1, count or 2 do
		table.insert(specs, { id = tostring(100 * k), kind = "Human" })
	end
	return Session.new(C, "m1", 7, specs, 0)
end

local function auto(session: Session.Session, p: number): any
	return Bot.act(C, View.build(C, session.match, p), Rng.new(p), "okafor")
end

-- Locks every connected human with a bot-made input until `done()`; returns the time.
local function playUntil(session: Session.Session, done: () -> boolean, start: number?): number
	local t = start or 0
	for _ = 1, 4000 do
		if done() then
			return t
		end
		if session.stage == "Input" then
			for p, seat in session.seats do
				if
					seat.kind == "Human"
					and seat.connected
					and not seat.locked
					and session.stage == "Input"
				then
					local ok, reason = Session.submit(session, p, session.step, auto(session, p), t)
					assert(ok, `auto submit rejected: {reason}`)
				end
			end
		else
			t = Session.nextWake(session)
			Session.update(session, t)
		end
	end
	error("the condition never held")
end

describe("review: a debate's grace use (D-072)", function()
	it("a drop during the reveal before a debate keeps that debate's grace", function()
		local session = humans()
		local t = playUntil(session, function()
			return session.stage == "Reveal"
				and session.reveal == "Resolve"
				and session.match.phase == "Debate"
		end)
		t = session.stageStart + 1
		local before = session.seats[2].graceLeft
		Session.disconnect(session, 2, t)
		expect(session.seats[2].graceLeft):toBe(before - 1)
		expect(session.seats[2].debateGraceWeek):toBe(nil)
		Session.reconnect(session, 2, t + 1)
		-- Round 1 of the debate: a drop here still gets the debate's grace.
		t = playUntil(session, function()
			return session.stage == "Input" and session.match.phase == "Debate"
		end, t + 1)
		Session.disconnect(session, 2, t + 1)
		expect(session.seats[2].graceLeft):toBe(before - 2)
		expect((session.seats[2].graceUntil :: number) - (t + 1)):toBe(C.DISCONNECT_GRACE)
	end)

	it("a drop during the debate's intro counts as that debate's", function()
		local session = humans()
		local t = playUntil(session, function()
			return session.stage == "Show" and session.reveal == "DebateIntro"
		end)
		Session.disconnect(session, 2, t)
		expect(session.seats[2].debateGraceWeek):toBe(session.match.week)
		Session.reconnect(session, 2, t + 1)
		Session.disconnect(session, 2, t + 2)
		expect(session.seats[2].graceUntil):toBe(t + 2)
	end)
end)

describe("review: your own debate move in the View (D-072)", function()
	it("a locked-in move and Zinger reach only their own seat, also on a resync", function()
		local session = humans()
		playUntil(session, function()
			return session.stage == "Input" and session.match.phase == "Debate"
		end)
		local t = session.stageStart + 1
		Session.drain(session)
		expect((Session.submit(session, 1, session.step, { move = "Attack", zinger = true }, t))):toBe(true)
		local mine = (Session.payload(session, 1).view.debate :: any).yourMove
		expect(mine ~= nil and mine.move):toBe("Attack")
		expect(mine ~= nil and mine.zinger):toBe(true)
		expect((Session.payload(session, 2).view.debate :: any).yourMove):toBe(nil)
		for _, message in Session.drain(session) do
			local state = message.state
			if state and state.view.debate then
				local move = (state.view.debate :: any).yourMove
				if message.seat == 1 then
					expect(move ~= nil and move.move):toBe("Attack")
				else
					expect(move):toBe(nil)
				end
			end
		end
	end)
end)

describe("review: forfeits with any number of players", function()
	it("two players: the other seat wins, as before", function()
		local session = humans()
		expect((Session.forfeit(session, 2, 1))):toBe(true)
		expect(session.result and session.result.winner):toBe(1)
		expect(session.result and session.result.winners):toBe(nil)
	end)

	it("three players: everyone who stayed shares the win", function()
		local session = humans(3)
		expect((Session.forfeit(session, 1, 1))):toBe(true)
		local result = session.result :: Session.Result
		expect(result.reason):toBe("Forfeit")
		expect(result.winner):toBe(0)
		expect(result.winners):toEqual({ 2, 3 })
	end)

	it("three players: missed weeks forfeit only the seat that missed them", function()
		local session = humans(3)
		local t = playUntil(session, function()
			return session.stage == "Input" and session.match.phase == "Plan"
		end)
		session.seats[3].graceLeft = 0
		Session.disconnect(session, 3, t)
		playUntil(session, function()
			return session.stage == "Over"
		end, t)
		local result = session.result :: Session.Result
		expect(result.reason):toBe("Forfeit")
		expect(result.winners):toEqual({ 1, 2 })
	end)
end)

describe("review: leaving before week 1 is unrated (D-075)", function()
	it("a forfeit during Select or the draft makes the match unrated for both", function()
		local select = humans()
		Session.forfeit(select, 2, 1)
		expect(select.result and select.result.unrated):toBe(true)

		local draft = humans()
		playUntil(draft, function()
			return draft.match.phase == "Draft"
		end)
		Session.forfeit(draft, 1, 50)
		expect(draft.result and draft.result.unrated):toBe(true)
	end)

	it("a drop before week 1 that ends in a forfeit is unrated too", function()
		local session = humans()
		session.seats[2].graceLeft = 0
		Session.disconnect(session, 2, 1)
		playUntil(session, function()
			return session.stage == "Over"
		end, 1)
		local result = session.result :: Session.Result
		expect(result.reason):toBe("Forfeit")
		expect(result.winner):toBe(1)
		expect(result.unrated):toBe(true)
	end)

	it("a forfeit from week 1 on stays rated", function()
		local session = humans()
		local t = playUntil(session, function()
			return session.stage == "Input" and session.match.phase == "Plan"
		end)
		Session.forfeit(session, 2, t)
		expect(session.result):toEqual({ winner = 1, reason = "Forfeit" })
	end)

	it("a player who drops early but comes back and plays on is rated", function()
		local session = humans()
		Session.disconnect(session, 2, 1)
		Session.reconnect(session, 2, 2)
		local t = playUntil(session, function()
			return session.stage == "Input" and session.match.phase == "Plan"
		end, 2)
		Session.forfeit(session, 2, t)
		expect(session.result and session.result.unrated):toBe(nil)
	end)
end)
