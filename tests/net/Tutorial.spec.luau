--!strict
-- The tutorial and bot-match timers (D-075): choice timers scale with the
-- practice bot's level (Easy x2, Medium x1.5, Hard and Extreme x1), the
-- tutorial's choices have no deadline at all (math.huge inside the session, nil
-- on the wire), reveals stay timed, and the "tutorial done" flag's lifecycle in
-- the profile, the lobby and the request schema.

local Test = require("@testlib/Test")
local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local Lobby = require("@net/Lobby")
local Profile = require("@net/Profile")
local Resolve = require("@sim/Resolve")
local Rng = require("@sim/Rng")
local Schemas = require("@net/Schemas")
local Session = require("@net/Session")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

-- Absolute times carry float error (stageStart + length): compare closely.
local function near(got: number, want: number)
	check(math.abs(got - want) < 1e-6, `expected {want}, got {got}`)
end

local function vsBot(difficulty: Bot.Difficulty?, tutorial: boolean?, seed: number?): Session.Session
	return Session.new(C, "t1", seed or 11, {
		{ id = "100", kind = "Human" },
		{ id = "bot", kind = "Bot", candidate = "hale", difficulty = difficulty },
	}, 0, { tutorial = tutorial })
end

local function auto(session: Session.Session, p: number): any
	-- The session's own config: the tutorial's is its short schedule (D-080).
	local view = View.build(session.config, session.match, p)
	return Bot.act(session.config, view, Rng.new(p), "okafor")
end

-- The Input timer each choice phase should get at `scale`.
local function choiceTimer(phase: string, scale: number): number
	local base = if phase == "Select"
		then C.TIMER_SELECT
		elseif phase == "Draft" then C.TIMER_DRAFT_ROUND
		elseif phase == "Decision" then C.TIMER_DECISION
		elseif phase == "Debate" then C.TIMER_DEBATE_ROUND
		else C.TIMER_PLAN
	return base * scale
end

-- Plays a whole match: the human locks in `think` seconds into every Input
-- stage, and every Show and Reveal runs to its end. Calls `seen(session)` at
-- the start of each new stage. Returns the session at the end.
local function playOut(session: Session.Session, think: number, seen: (Session.Session) -> ())
	local t = 0
	local lastStep = -1
	for _ = 1, 400 do
		if session.step ~= lastStep then
			lastStep = session.step
			seen(session)
		end
		if session.stage == "Over" then
			return
		end
		if session.stage == "Input" and not session.seats[1].locked then
			t = session.stageStart + think
			local ok, reason = Session.submit(session, 1, session.step, auto(session, 1), t)
			assert(ok, `submit rejected: {reason}`)
		else
			t = Session.nextWake(session)
			Session.update(session, t)
		end
	end
	error("the match did not end")
end

describe("Session: choice timers against a bot (D-075)", function()
	it("scales by level: Easy x2, Medium x1.5, Hard and Extreme x1, none x1", function()
		expect(C.BOT_TIME_MULT_EASY):toBe(2)
		expect(C.BOT_TIME_MULT_MEDIUM):toBe(1.5)
		expect(Session.timeScale(C, "Easy")):toBe(2)
		expect(Session.timeScale(C, "Medium")):toBe(1.5)
		expect(Session.timeScale(C, "Hard")):toBe(1)
		expect(Session.timeScale(C, "Extreme")):toBe(1)
		expect(Session.timeScale(C, nil)):toBe(1)
	end)

	for _, level in { "Easy", "Medium", "Hard", "Extreme" } :: { Bot.Difficulty } do
		it(`multiplies every choice timer, and no reveal, against the {level} bot`, function()
			local scale = Session.timeScale(C, level)
			local session = vsBot(level)
			expect(session.timeScale):toBe(scale)
			local kinds: { [string]: boolean } = {}
			playOut(session, 1, function(s)
				local length = s.deadline - s.stageStart
				if s.stage == "Input" then
					local phase = s.match.phase :: string
					kinds[phase] = true
					near(length, choiceTimer(phase, scale))
					expect(Session.payload(s, 1).deadline):toBe(s.deadline)
				elseif s.reveal == "Draft" then
					near(length, C.DRAFT_REVEAL)
				elseif s.reveal == "Resolve" then
					near(length, Resolve.revealTime(C, s.events))
				elseif s.reveal == "Clash" then
					near(length, C.TIMER_DEBATE_CLASH)
				elseif s.reveal == "Verdict" then
					near(length, C.TIMER_DEBATE_VERDICT)
				elseif s.reveal == "DebateIntro" then
					near(length, C.TIMER_DEBATE_INTRO)
				elseif s.stage == "Show" and s.match.phase == "MapReveal" then
					near(length, C.TIMER_MAP_REVEAL)
				elseif s.stage == "Show" and s.match.phase == "Election" then
					near(length, C.TIMER_ELECTION)
				end
			end)
			for _, phase in { "Select", "Draft", "Debate", "Plan" } do
				check(kinds[phase] == true, `no {phase} stage was seen`)
			end
		end)
	end

	it("the Easy bot doubles a timer that really runs out: the plan closes at 100 s, not 50", function()
		local session = vsBot("Easy")
		local t = 0
		while not (session.match.phase == "Plan" and session.stage == "Input") do
			if session.stage == "Input" then
				local ok = Session.submit(session, 1, session.step, auto(session, 1), t)
				assert(ok, "submit rejected")
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
		local start = session.stageStart
		expect(Session.nextWake(session)):toBe(start + 2 * C.TIMER_PLAN)
		Session.update(session, start + C.TIMER_PLAN + 1)
		expect(session.stage):toBe("Input") -- 50 s would have closed it
		-- The time bank still adds its plain chunk on top.
		expect((Session.bank(session, 1, session.step, start + 60))):toBe(true)
		expect(Session.payload(session, 1).deadline):toBe(start + 2 * C.TIMER_PLAN + C.TIME_BANK_CHUNK)
		Session.update(session, start + 2 * C.TIMER_PLAN + C.TIME_BANK_CHUNK)
		expect(session.stage):toBe("Reveal")
	end)

	it("people against people, and a harness bot with a style, keep every timer as it was", function()
		local people = Session.new(C, "p1", 3, {
			{ id = "100", kind = "Human" },
			{ id = "200", kind = "Human" },
		}, 0)
		expect(people.timeScale):toBe(1)
		expect(people.deadline):toBe(C.TIMER_SELECT)
		local harness = Session.new(C, "h1", 3, {
			{ id = "100", kind = "Human" },
			{ id = "bot", kind = "Bot", style = "Balanced" },
		}, 0)
		expect(harness.timeScale):toBe(1)
		expect(harness.deadline):toBe(C.TIMER_SELECT)
		-- A practice bot with no level given (the server always gives one) plays
		-- the harness style and keeps x1 too.
		local plain = Session.new(C, "b1", 3, {
			{ id = "100", kind = "Human" },
			{ id = "bot", kind = "Bot" },
		}, 0)
		expect(plain.timeScale):toBe(1)
	end)
end)

describe("Session: the tutorial has no choice deadline (D-075)", function()
	it("every Input stage waits: nil on the wire, math.huge inside, nothing closes it", function()
		local session = vsBot("Easy", true)
		expect(session.tutorial):toBe(true)
		expect(session.stage):toBe("Input")
		expect(session.deadline):toBe(Session.NO_DEADLINE)
		expect(Session.NO_DEADLINE):toBe(math.huge)
		local payload = Session.payload(session, 1)
		expect(payload.deadline):toBe(nil)
		expect(payload.tutorial):toBe(true)
		-- Nothing to wake for, and an update a day later changes nothing.
		expect(Session.nextWake(session)):toBe(math.huge)
		local step = session.step
		Session.update(session, 86400)
		expect(session.stage):toBe("Input")
		expect(session.step):toBe(step)
		expect(session.match.phase):toBe("Select")
		-- The player locks in a day later: accepted, and the match goes on.
		local ok, reason = Session.submit(session, 1, session.step, auto(session, 1), 86400)
		expect(ok):toBe(true)
		expect(reason):toBe(nil)
		expect(session.match.phase ~= "Select"):toBe(true)
	end)

	it("plays a whole match with a slow player; reveals and election night stay timed", function()
		local session = vsBot("Easy", true)
		local inputs, timed = 0, 0
		playOut(session, 600, function(s)
			if s.stage == "Input" then
				inputs += 1
				expect(s.deadline):toBe(Session.NO_DEADLINE)
				expect(Session.payload(s, 1).deadline):toBe(nil)
				expect(Session.nextWake(s)):toBe(math.huge)
			elseif s.stage ~= "Over" then
				timed += 1
				local deadline = Session.payload(s, 1).deadline
				check(deadline ~= nil and deadline < math.huge, `a {s.stage} stage has no deadline`)
				check((deadline :: number) - s.stageStart <= C.TIMER_ELECTION, "a reveal is too long")
			end
		end)
		-- The short tutorial (D-080): Select, 3 draft rounds, 4 plans, 1 stance,
		-- 3 debate rounds.
		expect(inputs):toBe(1 + #C.DRAFT_PRIORITY + C.TUTORIAL_WEEKS + 1 + C.DEBATE_TOPICS)
		check(timed > 10, `only {timed} timed stages`)
		expect((session.result :: Session.Result).reason):toBe("Election")
	end)

	it("tells the player first, has no time bank, and sends only finite numbers", function()
		local session = vsBot("Easy", true)
		local first = Session.drain(session)
		expect(first[1].kind):toBe("Notice")
		expect(first[1].notice):toBe(Session.TUTORIAL)
		expect(first[2].kind):toBe("State")
		local function finite(value: any, path: string)
			if type(value) == "number" then
				check(value == value and value ~= math.huge and value ~= -math.huge, `{path} is not finite`)
			elseif type(value) == "table" then
				for key, child in value do
					finite(child, `{path}.{key}`)
				end
			end
		end
		local t = 0
		for _ = 1, 400 do
			for _, message in Session.drain(session) do
				finite(message, "message")
			end
			if session.stage == "Over" then
				break
			end
			if session.stage == "Input" and not session.seats[1].locked then
				-- No bank in a plan or a debate round (D-085) without a deadline.
				if session.match.phase == "Plan" or session.match.phase == "Debate" then
					expect(select(2, Session.bank(session, 1, session.step, t))):toBe(Session.Reason.NoTimer)
				end
				t += 30
				assert((Session.submit(session, 1, session.step, auto(session, 1), t)), "submit rejected")
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
		expect(session.stage):toBe("Over")
		-- An ordinary practice match never says it is the tutorial.
		local normal = vsBot("Easy")
		expect(Session.payload(normal, 1).tutorial):toBe(nil)
		expect(Session.drain(normal)[1].kind):toBe("State")
	end)

	it("a disconnect still ends it: grace runs out and the match is abandoned", function()
		local session = vsBot("Easy", true)
		Session.disconnect(session, 1, 100)
		expect(session.stage):toBe("Input")
		expect(Session.nextWake(session)):toBe(100 + C.DISCONNECT_GRACE)
		Session.update(session, 100 + C.DISCONNECT_GRACE)
		expect(session.stage):toBe("Over")
		expect((session.result :: Session.Result).reason):toBe("Abandoned")
	end)

	it("a player back within grace finds the step still waiting, with no deadline", function()
		local session = vsBot("Easy", true)
		Session.disconnect(session, 1, 100)
		Session.reconnect(session, 1, 110)
		expect(session.seats[1].bankUsed):toBe(0)
		expect(Session.payload(session, 1).deadline):toBe(nil)
		Session.update(session, 10000)
		expect(session.stage):toBe("Input")
	end)
end)

describe("Lobby and requests: asking for the tutorial (D-075)", function()
	it("the tutorial always plays the Easy bot, the first one and a replay (D-080)", function()
		local lobby = Lobby.new(C)
		local replay = Lobby.practice(lobby, "1", "Hard", "Replay") :: Lobby.Outcome
		expect(replay.kind):toBe("Practice")
		expect(replay.difficulty):toBe("Easy")
		expect(replay.tutorial):toBe(true)
		local first = Lobby.practice(lobby, "2", "Hard", "First") :: Lobby.Outcome
		expect(first.difficulty):toBe("Easy")
		expect(first.tutorial):toBe(true)
		local normal = Lobby.practice(lobby, "3", "Hard") :: Lobby.Outcome
		expect(normal.difficulty):toBe("Hard")
		expect(normal.tutorial):toBe(nil)
		-- Still a match like any other: a player in one cannot start another.
		local again, reason = Lobby.practice(lobby, "1", "Easy", "Replay")
		expect(again):toBe(nil)
		expect(reason):toBe("InMatch")
	end)

	it("the schema keeps only tutorial = true and never rejects the field", function()
		local function parse(raw: any): any
			local ok, reason, request = Schemas.request(raw)
			assert(ok, `rejected: {reason}`)
			return request
		end
		expect(parse({ op = "Practice", difficulty = "Easy", tutorial = true }).tutorial):toBe(true)
		expect(parse({ op = "Practice", tutorial = false }).tutorial):toBe(nil)
		expect(parse({ op = "Practice", tutorial = "yes" }).tutorial):toBe(nil)
		expect(parse({ op = "Practice" }).tutorial):toBe(nil)
		-- Only Practice reads it.
		expect(parse({ op = "Queue", tutorial = true }).tutorial):toBe(nil)
	end)
end)

describe("Profile: tutorial done (D-075)", function()
	it("a new player needs it; done once marked; no profile means a normal match", function()
		local fresh = Profile.new(C)
		expect(Profile.needsTutorial(fresh)):toBe(true)
		expect(Profile.needsTutorial(nil)):toBe(false)
		local done = Profile.withTutorialDone(fresh)
		expect(done.tutorialDone):toBe(true)
		expect(fresh.tutorialDone):toBe(nil) -- never mutates its argument
		expect(Profile.needsTutorial(done)):toBe(false)
	end)

	it("players with any game on record skip it, even without the flag", function()
		local practiced = Profile.migrate({ practice = { games = 3, wins = 1, losses = 2 } }, C)
		expect(Profile.needsTutorial(practiced)):toBe(false)
		local rated = Profile.migrate({ wins = 1, losses = 0, games = 1 }, C)
		expect(Profile.needsTutorial(rated)):toBe(false)
	end)

	it("survives saving: migrate keeps true, drops anything else, keeps the version", function()
		local done = Profile.withTutorialDone(Profile.new(C))
		local loaded = Profile.migrate(done, C)
		expect(loaded.tutorialDone):toBe(true)
		expect(loaded.version):toBe(1)
		expect(Profile.migrate({ tutorialDone = "yes" }, C).tutorialDone):toBe(nil)
		expect(Profile.isFromFuture(done)):toBe(false)
		-- Applying a result keeps it.
		local after = Profile.applyResult(loaded, {
			at = 1,
			reason = "Election",
			rated = false,
			won = true,
		}, C)
		expect(after.tutorialDone):toBe(true)
	end)
end)
