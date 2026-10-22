--!strict
-- Regressions found by the server bug hunt: the forfeit counter, and what a
-- State message may show before election night (D-026).

local Test = require("@testlib/Test")
local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local Rng = require("@sim/Rng")
local Session = require("@net/Session")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function humans(): Session.Session
	return Session.new(C, "m1", 5, {
		{ id = "100", kind = "Human" },
		{ id = "200", kind = "Human" },
	}, 0)
end

type Clock = { now: number }

-- Steps the clock one second at a time, locking in a bot-made input for every
-- connected human seat that is not in `idle`, until `done()` or `limit` seconds.
-- `each` sees the session after every step.
local function play(
	session: Session.Session,
	clock: Clock,
	done: () -> boolean,
	idle: { [number]: boolean }?,
	each: (() -> ())?
)
	local rngs = { Rng.new(1), Rng.new(2) }
	for _ = 1, 4000 do
		if done() then
			return
		end
		clock.now += 1
		Session.update(session, clock.now)
		if done() then
			return -- before anyone locks in, so a stage that just opened is still open
		end
		if session.stage == "Input" then
			for p, seat in session.seats do
				if seat.connected and not seat.locked and not (idle and idle[p]) then
					local view = View.build(C, session.match, p)
					local ok, reason = Session.submit(
						session,
						p,
						session.step,
						Bot.act(C, view, rngs[p], "okafor"),
						clock.now
					)
					assert(ok, `submit rejected: {reason}`)
				end
			end
		end
		if each then
			each()
		end
	end
	error(
		`the clock ran out before the condition held (stage {session.stage}, phase {session.match.phase}, week {session.match.week}, t {clock.now})`
	)
end

local function planInput(session: Session.Session, week: number?): boolean
	return session.stage == "Input"
		and session.match.phase == "Plan"
		and (week == nil or session.match.week == week)
end

describe("bug hunt: the forfeit counter is consecutive", function()
	it("a connected week, even an idle one, resets the missed count", function()
		local s = humans()
		local clock: Clock = { now = 0 }
		play(s, clock, function()
			return planInput(s)
		end)
		-- Week A: player 2 drops and misses it.
		Session.disconnect(s, 2, clock.now)
		play(s, clock, function()
			return s.stage ~= "Input"
		end, { [2] = true })
		expect(s.seats[2].missed):toBe(1)

		-- Week B: back, but idle (never locks in).
		Session.reconnect(s, 2, clock.now)
		play(s, clock, function()
			return planInput(s)
		end)
		play(s, clock, function()
			return s.stage ~= "Input"
		end, { [2] = true })
		expect(s.seats[2].missed):toBe(0)

		-- Week C: drops again. That is one missed week in a row, not two.
		play(s, clock, function()
			return planInput(s)
		end)
		Session.disconnect(s, 2, clock.now)
		play(s, clock, function()
			return s.stage ~= "Input"
		end, { [2] = true })
		expect(s.stage ~= "Over"):toBe(true)
		expect(s.seats[2].missed):toBe(1)
	end)

	it("two missed weeks in a row still forfeit", function()
		local s = humans()
		local clock: Clock = { now = 0 }
		play(s, clock, function()
			return planInput(s)
		end)
		Session.disconnect(s, 2, clock.now)
		play(s, clock, function()
			return s.stage == "Over"
		end, { [2] = true })
		local result = s.result :: Session.Result
		expect(result.reason):toBe("Forfeit")
		expect(result.winner):toBe(1)
	end)
end)

describe("bug hunt: no election result before election night", function()
	local function shown(s: Session.Session): boolean
		if s.stage == "Show" and s.match.phase == "Election" then
			return true
		end
		local result = s.result
		return s.stage == "Over" and result ~= nil and result.reason == "Election"
	end

	it("no message of a whole match carries it before election night", function()
		local s = humans()
		local clock: Clock = { now = 0 }
		local sawResolve = false
		local sawNight = false
		play(
			s,
			clock,
			function()
				return s.stage == "Over"
			end,
			nil,
			function()
				for _, message in Session.drain(s) do
					local state = message.state
					if state then
						if state.view.election ~= nil then
							sawNight = true
						end
						local stageOf = if state.stage == "Over" then "Over" else state.stage
						local allowed = (stageOf == "Show" and state.view.phase == "Election")
							or (
								stageOf == "Over"
								and state.result ~= nil
								and state.result.reason == "Election"
							)
						if
							stageOf == "Reveal"
							and state.reveal == "Resolve"
							and state.view.phase == "Election"
						then
							sawResolve = true
						end
						expect(state.view.election ~= nil and not allowed):toBe(false)
					end
				end
			end
		)
		expect(sawResolve):toBe(true) -- week 12's resolve reveal was checked
		expect(sawNight):toBe(true)
		expect(shown(s)):toBe(true)
		expect(Session.payload(s, 1).view.election ~= nil):toBe(true)
	end)

	it("the last resolve reveal hides the result", function()
		local s = humans()
		local clock: Clock = { now = 0 }
		play(s, clock, function()
			return s.stage == "Reveal" and s.reveal == "Resolve" and s.match.phase == "Election"
		end)
		expect(Session.payload(s, 1).view.election):toBe(nil)
		expect(Session.payload(s, 2).view.election):toBe(nil)
		play(s, clock, function()
			return s.stage == "Show"
		end)
		expect(Session.payload(s, 1).view.election ~= nil):toBe(true)
	end)

	it("a forfeit after the last plan never reveals the unseen result", function()
		local s = humans()
		local clock: Clock = { now = 0 }
		play(s, clock, function()
			return planInput(s, 11)
		end)
		Session.disconnect(s, 2, clock.now)
		play(s, clock, function()
			return s.stage == "Over"
		end, { [2] = true })
		local result = s.result :: Session.Result
		expect(result.reason):toBe("Forfeit")
		expect(s.match.election ~= nil):toBe(true) -- computed by the last advance, never shown
		expect(Session.payload(s, 1).view.election):toBe(nil)
		for _, message in Session.drain(s) do
			expect(message.state and message.state.view.election):toBe(nil)
		end
	end)
end)

describe("bug hunt: clash priority stays hidden during Select", function()
	it("no State message carries priorityA until the map reveal", function()
		local s = humans()
		for _, message in Session.drain(s) do
			expect(message.state and message.state.view.phase):toBe("Select")
			expect(message.state and message.state.view.priorityA):toBe(nil)
		end
		expect(Session.payload(s, 1).view.priorityA):toBe(nil)
		local clock: Clock = { now = 0 }
		play(s, clock, function()
			return s.match.phase == "MapReveal"
		end)
		expect(Session.payload(s, 1).view.priorityA ~= nil):toBe(true)
	end)
end)
