--!strict
-- Match sessions: timers, lock-ins, skips, the time bank, disconnect grace,
-- forfeits, bots, stale requests, and what each seat is sent.

local Test = require("@testlib/Test")
local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local Rng = require("@sim/Rng")
local Session = require("@net/Session")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function humans(now: number?): Session.Session
	return Session.new(C, "m1", 7, {
		{ id = "100", kind = "Human" },
		{ id = "200", kind = "Human" },
	}, now or 0)
end

local function practice(): Session.Session
	return Session.new(C, "m2", 7, {
		{ id = "100", kind = "Human" },
		{ id = "bot", kind = "Bot", candidate = "hale" },
	}, 0)
end

local SELECTION = { candidate = "okafor", platform = { "Jobs", "Health", "Schools" } }
local OTHER = { candidate = "venkat", platform = { "Jobs", "Health", "Schools" } }

-- A bot-made input for seat p, the way the debug UI's "auto" button builds one.
local function auto(session: Session.Session, p: number): any
	local view = View.build(C, session.match, p)
	return Bot.act(C, view, Rng.new(p), "okafor")
end

-- Each seat's color.
local function colorsOfSession(session: Session.Session): { string }
	local out = {}
	for p, player in session.match.players do
		out[p] = player.color
	end
	return out
end

-- Locks every human seat with a bot-made input, at time `now`.
local function lockAll(session: Session.Session, now: number)
	for p, seat in session.seats do
		if seat.kind == "Human" and seat.connected and not seat.locked and session.stage == "Input" then
			local ok, reason = Session.submit(session, p, session.step, auto(session, p), now)
			assert(ok, `auto submit rejected: {reason}`)
		end
	end
end

describe("Session: stages and timers", function()
	it("opens with a Select input stage and sends each seat its own view", function()
		local session = humans()
		expect(session.stage):toBe("Input")
		expect(session.match.phase):toBe("Select")
		expect(session.deadline):toBe(C.TIMER_SELECT)
		local messages = Session.drain(session)
		expect(#messages):toBe(2)
		expect(messages[1].state and messages[1].state.you):toBe(1)
		expect(messages[2].state and messages[2].state.you):toBe(2)
		expect(#Session.drain(session)):toBe(0)
	end)

	it("closes early once everyone locks, then shows the map", function()
		local session = humans()
		expect((Session.submit(session, 1, session.step, SELECTION, 1))):toBe(true)
		expect(session.stage):toBe("Input")
		expect((Session.submit(session, 2, session.step, OTHER, 2))):toBe(true)
		expect(session.match.phase):toBe("MapReveal")
		expect(session.stage):toBe("Show")
		expect(session.deadline):toBe(2 + C.TIMER_MAP_REVEAL)
		Session.update(session, 2 + C.TIMER_MAP_REVEAL)
		expect(session.match.phase):toBe("Draft")
		expect(session.stage):toBe("Input")
	end)

	it("auto-submits defaults when the timer runs out", function()
		local session = humans()
		Session.update(session, C.TIMER_SELECT - 0.01)
		expect(session.match.phase):toBe("Select")
		Session.update(session, C.TIMER_SELECT)
		expect(session.match.phase):toBe("MapReveal")
		expect(session.match.players[1].candidate ~= ""):toBe(true)
	end)

	it("uses a lobby pre-pick when Select times out", function()
		local session = Session.new(C, "m", 3, {
			{ id = "1", kind = "Human", prePick = SELECTION },
			{ id = "2", kind = "Human" },
		}, 0)
		Session.update(session, C.TIMER_SELECT)
		expect(session.match.players[1].candidate):toBe("okafor")
		expect(session.match.players[1].platform):toEqual(SELECTION.platform)
	end)

	it("reveals each draft pick, then shows the resolve after each week", function()
		local session = humans()
		lockAll(session, 0)
		Session.update(session, C.TIMER_MAP_REVEAL)
		expect(session.match.phase):toBe("Draft")
		lockAll(session, 6)
		expect(session.stage):toBe("Reveal")
		expect(session.events[1].kind):toBe("Pick")
		Session.update(session, 6 + C.DRAFT_REVEAL)
		expect(session.match.draftRound):toBe(1)
		local t = 10
		while session.match.phase == "Draft" or session.stage == "Reveal" do
			lockAll(session, t)
			Session.update(session, t + C.DRAFT_REVEAL)
			t += C.DRAFT_REVEAL
		end
		expect(session.match.phase):toBe("Plan")
		lockAll(session, t)
		expect(session.stage):toBe("Reveal")
		expect(session.deadline):toBe(t + C.TIMER_RESOLVE)
	end)

	it("plays a whole match to the election and a result", function()
		local session = humans()
		local t = 0
		for _ = 1, 200 do
			if session.stage == "Over" then
				break
			end
			if session.stage == "Input" then
				lockAll(session, t)
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
		expect(session.stage):toBe("Over")
		local result = session.result :: Session.Result
		expect(result.reason):toBe("Election")
		expect(result.winner == 1 or result.winner == 2):toBe(true)
		local last = Session.payload(session, 1)
		expect(last.view.election ~= nil):toBe(true)
	end)
end)

-- Plays (everyone locks the bot's choice) until the week-12 Plan has just closed.
-- Returns the time of the last step.
local function toWeekTwelveReveal(session: Session.Session): number
	local t = 0
	for _ = 1, 200 do
		if session.match.phase == "Election" then
			return t
		end
		if session.stage == "Input" then
			lockAll(session, t)
		else
			t = Session.nextWake(session)
			Session.update(session, t)
		end
	end
	error("never reached election night")
end

describe("Session: unique candidates (D-048)", function()
	-- The notices queued for seat p.
	local function notices(session: Session.Session, p: number): { string }
		local out = {}
		for _, message in Session.drain(session) do
			if message.seat == p and message.kind == "Notice" then
				table.insert(out, message.notice :: string)
			end
		end
		return out
	end

	it("a claim is first come, first served, and shows as taken at once", function()
		local session = humans()
		expect((Session.claim(session, 1, session.step, "hale", 1))):toBe(true)
		Session.update(session, 1)
		expect(session.match.claims.hale):toBe(1)
		local messages = Session.drain(session)
		local seen = false
		for _, message in messages do
			if message.seat == 2 and message.state then
				seen = message.state.view.claims.hale == 1
			end
		end
		expect(seen):toBe(true)
		local ok, reason = Session.claim(session, 2, session.step, "hale", 2)
		expect(ok):toBe(false)
		expect(reason):toBe("CandidateTaken")
		ok, reason =
			Session.submit(session, 2, session.step, { candidate = "hale", platform = SELECTION.platform }, 2)
		expect(ok):toBe(false)
		expect(reason):toBe("CandidateTaken")
		expect(session.seats[2].locked):toBe(false)
		-- Seat 1 locks in its claim; seat 2 picks another and the match goes on.
		expect(
			(
				Session.submit(
					session,
					1,
					session.step,
					{ candidate = "hale", platform = SELECTION.platform },
					3
				)
			)
		):toBe(true)
		expect((Session.submit(session, 2, session.step, OTHER, 3))):toBe(true)
		expect(session.match.players[1].candidate):toBe("hale")
		expect(session.match.players[2].candidate):toBe("venkat")
	end)

	it("claims in the same server step go to a seeded coin flip, and the loser is told", function()
		local wins = { 0, 0 }
		for seed = 1, 200 do
			local session = Session.new(C, "m", seed, {
				{ id = "1", kind = "Human" },
				{ id = "2", kind = "Human" },
			}, 0)
			Session.drain(session)
			expect((Session.claim(session, 2, session.step, "strand", 1))):toBe(true)
			expect((Session.claim(session, 1, session.step, "strand", 1))):toBe(true)
			expect(Session.nextWake(session) <= 1):toBe(true)
			Session.update(session, 1)
			local winner = session.match.claims.strand
			wins[winner] += 1
			local loser = 3 - winner
			local told = notices(session, loser)
			expect(told[1]):toBe(Session.CANDIDATE_TAKEN)
			-- The loser picks again.
			expect((Session.claim(session, loser, session.step, "begay", 2))):toBe(true)
			Session.update(session, 2)
			expect(session.match.claims.begay):toBe(loser)
		end
		expect(wins[1] > 70 and wins[2] > 70):toBe(true)
	end)

	it("a timeout keeps the claim and the pre-pick's platform, and defaults to a free candidate", function()
		local session = Session.new(C, "m", 5, {
			{
				id = "1",
				kind = "Human",
				prePick = { candidate = "reyes", platform = { "Farms", "Safety", "Transit" } },
			},
			{
				id = "2",
				kind = "Human",
				prePick = { candidate = "reyes", platform = { "Jobs", "Health", "Schools" } },
			},
		}, 0)
		expect((Session.claim(session, 1, session.step, "okafor", 1))):toBe(true)
		Session.update(session, 1)
		Session.update(session, C.TIMER_SELECT)
		expect(session.match.phase):toBe("MapReveal")
		expect(session.match.players[1].candidate):toBe("okafor")
		expect(session.match.players[1].platform):toEqual({ "Farms", "Safety", "Transit" })
		expect(session.match.players[2].candidate):toBe("reyes")
	end)

	it("a practice bot seat plays the difficulty it was given (D-057)", function()
		for _, level in { "Easy", "Medium", "Hard", "Extreme" } :: { Bot.Difficulty } do
			local session = Session.new(C, "m3", 7, {
				{ id = "100", kind = "Human" },
				{ id = "bot", kind = "Bot", candidate = "hale", difficulty = level },
			}, 0)
			local seat = session.seats[2]
			expect(seat.botDifficulty):toBe(level)
			expect(seat.botStyle):toBe(Bot.styleFor(level))
			expect(session.seats[1].botDifficulty):toBe(nil)
			-- The human sees the bot's level on the seat list.
			local payload = Session.payload(session, 1)
			expect(payload.seats[2].difficulty):toBe(level)
			expect(payload.seats[1].difficulty):toBe(nil)
		end
		-- An explicit style (the harness) wins, and a bot with neither plays Balanced.
		local styled = Session.new(C, "m4", 7, {
			{ id = "100", kind = "Human" },
			{ id = "bot", kind = "Bot", candidate = "hale", style = "NeverPoll", difficulty = "Hard" },
		}, 0)
		expect(styled.seats[2].botStyle):toBe("NeverPoll")
		expect(styled.seats[2].botDifficulty):toBe(nil)
		expect(practice().seats[2].botStyle):toBe(nil)
	end)

	it("a practice bot's moves follow from the seed at every difficulty (D-057)", function()
		for _, level in { "Easy", "Hard", "Extreme" } :: { Bot.Difficulty } do
			local function run(): any
				local session = Session.new(C, "m5", 31, {
					{ id = "100", kind = "Human" },
					{ id = "bot", kind = "Bot", candidate = "venkat", difficulty = level },
				}, 0)
				-- Select, the draft and four weeks: the bot locks at once each time.
				for _ = 1, 12 do
					lockAll(session, Session.nextWake(session))
					Session.update(session, Session.nextWake(session))
				end
				return session.match
			end
			expect(run()):toEqual(run())
		end
	end)

	it("a practice bot claims its candidate as Select opens", function()
		local session = practice()
		expect(session.match.claims.hale):toBe(2)
		expect(select(2, Session.claim(session, 1, session.step, "hale", 1))):toBe("CandidateTaken")
		expect((Session.claim(session, 1, session.step, "okafor", 1))):toBe(true)
	end)
end)

describe("Session: color claims (D-061)", function()
	local function owners(seed: number, one: string?, two: string?): Session.Session
		return Session.new(C, "m", seed, {
			{ id = "1", kind = "Human", colorPass = true, color = one },
			{ id = "2", kind = "Human", colorPass = true, color = two },
		}, 0)
	end

	local function notices(session: Session.Session, p: number): { string }
		local out = {}
		for _, message in Session.drain(session) do
			if message.seat == p and message.kind == "Notice" then
				table.insert(out, message.notice :: string)
			end
		end
		return out
	end

	it("claims a saved favorite as Select opens; only owners may pick, and they see it", function()
		local session = Session.new(C, "m", 3, {
			{ id = "1", kind = "Human", colorPass = true, color = "Teal" },
			{ id = "2", kind = "Human", color = "Violet" }, -- not an owner: the favorite is ignored
		}, 0)
		expect(session.match.players[1].color):toBe("Teal")
		local other = session.match.players[2].color
		expect(other == "Crimson" or other == "Cobalt"):toBe(true)
		expect(Session.payload(session, 1).view.canPickColor):toBe(true)
		expect(Session.payload(session, 2).view.canPickColor):toBe(false)
		expect(Session.payload(session, 2).view.colorClaims.Teal):toBe(1)
		local ok, reason = Session.claimColor(session, 2, session.step, "Amber", 1)
		expect(ok):toBe(false)
		expect(reason):toBe("NoColorPass")
	end)

	it("is first come, first served; a taken color is turned down at once", function()
		local session = owners(5)
		expect((Session.claimColor(session, 1, session.step, "Emerald", 1))):toBe(true)
		Session.update(session, 1)
		expect(session.match.colorClaims.Emerald):toBe(1)
		local seen = false
		for _, message in Session.drain(session) do
			if message.seat == 2 and message.state then
				seen = message.state.view.colorClaims.Emerald == 1
					and message.state.view.players[1].color == "Emerald"
			end
		end
		expect(seen):toBe(true)
		local ok, reason = Session.claimColor(session, 2, session.step, "Emerald", 2)
		expect(ok):toBe(false)
		expect(reason):toBe("ColorTaken")
		expect((Session.claimColor(session, 2, session.step, "Amber", 2))):toBe(true)
		Session.update(session, 2)
		expect(session.match.players[2].color):toBe("Amber")
		-- A change of mind releases the old color, even after locking in.
		expect((Session.submit(session, 1, session.step, SELECTION, 3))):toBe(true)
		expect((Session.claimColor(session, 1, session.step, "Violet", 3))):toBe(true)
		Session.update(session, 3)
		expect(session.match.colorClaims):toEqual({ Violet = 1, Amber = 2 })
		-- Stale steps and the end of Select turn claims down.
		expect(select(2, Session.claimColor(session, 2, session.step - 1, "Teal", 4))):toBe("StaleStep")
		expect(select(2, Session.claimColor(session, 2, session.step, "Gold", 4))):toBe("UnknownColor")
		expect((Session.submit(session, 2, session.step, OTHER, 4))):toBe(true)
		expect(session.match.phase):toBe("MapReveal")
		expect(colorsOfSession(session)):toEqual({ "Violet", "Amber" })
		expect(select(2, Session.claimColor(session, 2, session.step, "Teal", 5))):toBe("NotInput")
	end)

	it("claims of one color in the same server step go to a seeded coin flip; the loser is told", function()
		local wins = { 0, 0 }
		for seed = 1, 200 do
			local session = owners(seed)
			Session.drain(session)
			expect((Session.claimColor(session, 2, session.step, "Teal", 1))):toBe(true)
			expect((Session.claimColor(session, 1, session.step, "Teal", 1))):toBe(true)
			expect(Session.nextWake(session) <= 1):toBe(true)
			Session.update(session, 1)
			local winner = session.match.colorClaims.Teal
			wins[winner] += 1
			local loser = 3 - winner
			expect(notices(session, loser)):toEqual({ Session.COLOR_TAKEN })
			-- The loser picks another; nobody is stuck with a default.
			expect((Session.claimColor(session, loser, session.step, "Violet", 2))):toBe(true)
			Session.update(session, 2)
			expect(session.match.players[loser].color):toBe("Violet")
		end
		expect(wins[1] > 70 and wins[2] > 70):toBe(true)
	end)

	it("two owners with the same favorite: one gets it, the other is told to pick another", function()
		local wins = { 0, 0 }
		for seed = 1, 200 do
			local session = owners(seed, "Amber", "Amber")
			local winner = session.match.colorClaims.Amber
			wins[winner] += 1
			local loser = 3 - winner
			expect(notices(session, loser)):toEqual({ Session.COLOR_TAKEN })
			expect(Session.payload(session, loser).view.canPickColor):toBe(true)
			expect((Session.claimColor(session, loser, session.step, "Emerald", 1))):toBe(true)
			Session.update(session, 1)
			expect(session.match.players[loser].color):toBe("Emerald")
		end
		expect(wins[1] > 70 and wins[2] > 70):toBe(true)
	end)

	it("an owner who never picks is dealt red or blue when Select ends, never a taken color", function()
		for seed = 1, 50 do
			local session = owners(seed)
			expect((Session.claimColor(session, 1, session.step, "Crimson", 1))):toBe(true)
			Session.update(session, C.TIMER_SELECT)
			expect(session.match.phase):toBe("MapReveal")
			expect(colorsOfSession(session)):toEqual({ "Crimson", "Cobalt" })
		end
	end)
end)

describe("Session: election night", function()
	it("shows the last resolve, then a full election night, then ends", function()
		local session = humans()
		local t = toWeekTwelveReveal(session)
		expect(session.stage):toBe("Reveal")
		expect(session.reveal):toBe("Resolve")

		t = Session.nextWake(session)
		Session.update(session, t)
		expect(session.stage):toBe("Show")
		expect(session.match.phase):toBe("Election")
		expect(session.deadline):toBe(t + C.TIMER_ELECTION)
		expect(Session.payload(session, 1).view.election ~= nil):toBe(true)

		Session.update(session, t + C.TIMER_ELECTION - 0.01)
		expect(session.stage):toBe("Show")
		Session.update(session, t + C.TIMER_ELECTION)
		expect(session.stage):toBe("Over")
		expect((session.result :: Session.Result).reason):toBe("Election")
	end)

	it("ends at once when both humans skip election night", function()
		local session = humans()
		toWeekTwelveReveal(session)
		local t = Session.nextWake(session)
		Session.update(session, t)
		expect(session.stage):toBe("Show")
		expect((Session.skip(session, 1, session.step, t + 1))):toBe(true)
		expect(session.stage):toBe("Show")
		expect((Session.skip(session, 2, session.step, t + 2))):toBe(true)
		expect(session.stage):toBe("Over")
	end)

	it("ends at once in practice when the human skips (the bot always does)", function()
		local session = practice()
		toWeekTwelveReveal(session)
		local t = Session.nextWake(session)
		Session.update(session, t)
		expect(session.stage):toBe("Show")
		expect((Session.skip(session, 1, session.step, t + 1))):toBe(true)
		expect(session.stage):toBe("Over")
		expect((session.result :: Session.Result).reason):toBe("Election")
	end)
end)

describe("Session: requests", function()
	it("rejects stale steps, double locks and invalid input with reason codes", function()
		local session = humans()
		local step = session.step
		expect(select(2, Session.submit(session, 1, step - 1, SELECTION, 1))):toBe("StaleStep")
		expect(select(2, Session.submit(session, 1, step, { candidate = "nobody" }, 1))):toBe(
			"UnknownCandidate"
		)
		expect((Session.submit(session, 1, step, SELECTION, 1))):toBe(true)
		expect(select(2, Session.submit(session, 1, step, SELECTION, 1))):toBe("AlreadyLocked")
	end)

	it("a rejected submission leaves the seat unlocked and the match untouched", function()
		local session = humans()
		local before = session.match
		Session.submit(session, 1, session.step, "garbage", 1)
		expect(session.seats[1].locked):toBe(false)
		expect(session.match):toBe(before)
	end)

	it("the time bank adds 15 s to one seat's Plan deadline, twice at most", function()
		local session = practice()
		lockAll(session, 0)
		Session.update(session, C.TIMER_MAP_REVEAL)
		local t = C.TIMER_MAP_REVEAL
		while not (session.match.phase == "Plan" and session.stage == "Input") do
			if session.stage == "Input" then
				expect(select(2, Session.bank(session, 1, session.step, t))):toBe("NotInput")
				lockAll(session, t)
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
		local base = session.deadline
		expect((Session.bank(session, 1, session.step, t))):toBe(true)
		expect(Session.payload(session, 1).deadline):toBe(base + C.TIME_BANK_CHUNK)
		expect((Session.bank(session, 1, session.step, t))):toBe(true)
		expect(select(2, Session.bank(session, 1, session.step, t))):toBe("NoBank")
		Session.update(session, base + 1)
		expect(session.stage):toBe("Input") -- still waiting on the banked seat
		Session.update(session, base + 2 * C.TIME_BANK_CHUNK)
		expect(session.stage):toBe("Reveal")
		expect(session.seats[1].bank):toBe(0)
	end)

	it("resolve ends early only when every seat skips", function()
		local session = humans()
		local t = 0
		while session.reveal ~= "Resolve" do
			if session.stage == "Input" then
				lockAll(session, t)
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
		local start = session.stageStart
		expect(select(2, Session.skip(session, 1, session.step - 1, start))):toBe("StaleStep")
		expect((Session.skip(session, 1, session.step, start))):toBe(true)
		expect(session.skippedTo):toBe(nil)
		expect((Session.skip(session, 2, session.step, start))):toBe(true)
		expect(session.skippedTo):toBe(start + C.TIMER_RESOLVE_SKIPPED)
	end)

	it("draft reveals cannot be skipped", function()
		local session = humans()
		lockAll(session, 0)
		Session.update(session, C.TIMER_MAP_REVEAL)
		lockAll(session, 6)
		expect(session.stage):toBe("Reveal")
		expect(select(2, Session.skip(session, 1, session.step, 6))):toBe("NotSkippable")
	end)
end)

describe("Session: the Decision stage (D-044)", function()
	-- Plays (everyone locks the bot's choice) until the first Focus decision opens.
	local function toDecision(kind: string): (Session.Session, number)
		local session = humans()
		local t = 0
		for _ = 1, 400 do
			if
				session.match.phase == "Decision"
				and session.match.decision == kind
				and session.stage == "Input"
			then
				return session, t
			end
			if session.stage == "Input" then
				lockAll(session, t)
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
		error(`no {kind} decision came up`)
	end

	it("opens with its own absolute deadline, then the debate, with no reveal of its own", function()
		local session, t = toDecision("Focus")
		expect(session.deadline):toBe(t + C.TIMER_DECISION)
		local messages = Session.drain(session)
		local state = messages[#messages].state :: Session.StatePayload
		expect(state.view.decision):toBe("Focus")
		expect(state.deadline):toBe(t + C.TIMER_DECISION)
		-- The time bank is for plans only.
		expect(select(2, Session.bank(session, 1, session.step, t))):toBe("NotInput")
		lockAll(session, t + 1)
		expect(session.stage):toBe("Reveal")
		expect(session.reveal):toBe("Debate")
	end)

	it("both locking in ends it early; the opponent's pick never reaches the other seat", function()
		local session, t = toDecision("Focus")
		local topics = session.match.debateTopics[session.match.week]
		Session.drain(session)
		expect((Session.submit(session, 2, session.step, { focus = topics[3] }, t + 1))):toBe(true)
		expect(session.stage):toBe("Input")
		for _, message in Session.drain(session) do
			if message.seat == 1 and message.state then
				expect(message.state.view.debateFocus):toBe(nil)
			end
		end
		expect((Session.submit(session, 1, session.step, { focus = topics[1] }, t + 2))):toBe(true)
		expect(session.reveal):toBe("Debate")
		local debate = session.match.debates[#session.match.debates]
		expect(debate.focus):toEqual({ 1, 3 })
	end)

	it("rejects a bad decision with a reason code and leaves the seat open", function()
		local session, t = toDecision("Focus")
		local ok, reason = Session.submit(session, 1, session.step, { focus = "Nothing" }, t)
		expect(ok):toBe(false)
		expect(reason):toBe("BadFocus")
		expect(session.seats[1].locked):toBe(false)
		ok, reason = Session.submit(session, 1, session.step, { actions = {} }, t)
		expect(reason):toBe("BadFocus")
	end)

	it("auto-submits the defaults when its timer runs out: no focus, the hedge", function()
		local session, t = toDecision("Focus")
		Session.update(session, t + C.TIMER_DECISION - 0.01)
		expect(session.match.phase):toBe("Decision")
		Session.update(session, t + C.TIMER_DECISION)
		expect(session.reveal):toBe("Debate")
		expect(session.match.debates[#session.match.debates].focus):toEqual({ 0, 0 })

		session, t = toDecision("Stance")
		expect(session.deadline):toBe(t + C.TIMER_DECISION)
		Session.update(session, t + C.TIMER_DECISION)
		expect(session.match.phase):toBe("Plan")
		expect(session.stage):toBe("Input")
		expect(session.match.players[1].stance):toBe("C")
		expect(session.match.players[2].stance):toBe("C")
		expect(session.deadline):toBe(t + C.TIMER_DECISION + C.TIMER_PLAN)
	end)

	it("a bot seat decides by itself", function()
		local session = practice()
		local t = 0
		for _ = 1, 400 do
			if session.match.phase == "Decision" and session.stage == "Input" then
				break
			end
			if session.stage == "Input" then
				lockAll(session, t)
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
		expect(session.match.phase):toBe("Decision")
		expect(session.seats[2].locked):toBe(true)
		expect(session.seats[2].input ~= nil):toBe(true)
	end)
end)

describe("Session: disconnects", function()
	-- Advances a two-human session to its first Plan stage.
	local function toPlan(): (Session.Session, number)
		local session = humans()
		local t = 0
		while session.match.phase ~= "Plan" or session.stage ~= "Input" do
			if session.stage == "Input" then
				lockAll(session, t)
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
		return session, t
	end

	it("tells the opponent at once and waits out the grace period", function()
		local session, t = toPlan()
		Session.drain(session)
		Session.disconnect(session, 2, t)
		local notices = 0
		for _, message in Session.drain(session) do
			if message.kind == "Notice" then
				expect(message.seat):toBe(1)
				expect(message.notice):toBe("OpponentDisconnected")
				notices += 1
			end
		end
		expect(notices):toBe(1)
		lockAll(session, t)
		expect(session.stage):toBe("Input") -- seat 2 is still in grace
		Session.update(session, t + C.DISCONNECT_GRACE)
		expect(session.stage):toBe("Reveal") -- auto-submitted after grace
		expect(session.seats[2].missed):toBe(1)
	end)

	it("waits past the plan deadline for a player still in grace", function()
		local session, t = toPlan()
		Session.disconnect(session, 2, session.deadline - 5)
		lockAll(session, t)
		Session.update(session, session.deadline + 1)
		expect(session.stage):toBe("Input")
		Session.update(session, session.deadline - 5 + C.DISCONNECT_GRACE)
		expect(session.stage):toBe("Reveal")
	end)

	it("a player who returns after the plan deadline gets time to finish the turn", function()
		local session = toPlan()
		local deadline = session.deadline
		Session.disconnect(session, 2, deadline - 5)
		lockAll(session, deadline - 5)
		Session.update(session, deadline + 10)
		expect(session.stage):toBe("Input") -- grace still holds the stage open
		Session.reconnect(session, 2, deadline + 10)
		expect(session.stage):toBe("Input")
		expect(Session.payload(session, 2).deadline):toBe(deadline + 10 + C.RECONNECT_WINDOW)
		expect(Session.payload(session, 1).deadline):toBe(deadline) -- nobody else's clock moves
		expect(session.seats[2].bank):toBe(C.TIME_BANK) -- and no bank is spent
		local ok, reason = Session.submit(session, 2, session.step, auto(session, 2), deadline + 12)
		expect(reason):toBe(nil)
		expect(ok):toBe(true)
		expect(session.stage):toBe("Reveal")
		expect(session.seats[2].input ~= nil):toBe(true) -- their own plan was played
		expect(session.seats[2].missed):toBe(0)
	end)

	it("a returning player who does not act is closed out after the reconnect window", function()
		local session = toPlan()
		local deadline = session.deadline
		Session.disconnect(session, 2, deadline - 5)
		lockAll(session, deadline - 5)
		Session.reconnect(session, 2, deadline + 10)
		Session.update(session, deadline + 10 + C.RECONNECT_WINDOW - 0.01)
		expect(session.stage):toBe("Input")
		expect(Session.nextWake(session)):toBe(deadline + 10 + C.RECONNECT_WINDOW)
		Session.update(session, deadline + 10 + C.RECONNECT_WINDOW)
		expect(session.stage):toBe("Reveal")
		expect(session.seats[2].input == nil):toBe(true) -- defaults, no plan
		expect(session.seats[2].missed):toBe(0) -- they were connected at the end
	end)

	it("a reconnect with plenty of time left changes no deadline", function()
		local session, t = toPlan()
		Session.disconnect(session, 2, t)
		Session.reconnect(session, 2, t + 1)
		expect(Session.payload(session, 2).deadline):toBe(session.deadline)
	end)

	it("the extension ends with the stage: the next Input stage starts clean", function()
		local session = toPlan()
		Session.disconnect(session, 2, session.deadline - 1)
		Session.reconnect(session, 2, session.deadline - 1)
		expect(session.seats[2].bankUsed > 0):toBe(true)
		lockAll(session, session.deadline)
		local t = session.deadline
		while session.stage ~= "Input" do
			t = Session.nextWake(session)
			Session.update(session, t)
		end
		expect(session.seats[2].bankUsed):toBe(0)
		expect(Session.payload(session, 2).deadline):toBe(session.deadline)
	end)

	it("a reconnect within grace resumes play and resets nothing else", function()
		local session, t = toPlan()
		Session.disconnect(session, 2, t)
		Session.drain(session)
		Session.reconnect(session, 2, t + 5)
		local gotState = false
		for _, message in Session.drain(session) do
			if message.seat == 2 and message.kind == "State" then
				gotState = true
			end
		end
		expect(gotState):toBe(true)
		expect(session.seats[2].graceLeft):toBe(C.GRACE_USES - 1)
		lockAll(session, t + 6)
		expect(session.stage):toBe("Reveal")
		expect(session.seats[2].missed):toBe(0)
	end)

	it("after the grace periods run out, a disconnect auto-submits at once", function()
		local session, t = toPlan()
		session.seats[2].graceLeft = 0
		Session.disconnect(session, 2, t)
		lockAll(session, t)
		expect(session.stage):toBe("Reveal")
	end)

	it("two missed weeks in a row forfeit the match", function()
		local session, t = toPlan()
		session.seats[2].graceLeft = 0
		Session.disconnect(session, 2, t)
		for _ = 1, 20 do
			if session.stage == "Over" then
				break
			end
			if session.stage == "Input" then
				lockAll(session, t)
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
		expect(session.stage):toBe("Over")
		expect(session.result):toEqual({ winner = 1, reason = "Forfeit" })
		expect(session.match.week):toBe(3)
	end)

	it("a match with nobody left is abandoned", function()
		local session, t = toPlan()
		Session.disconnect(session, 1, t)
		Session.disconnect(session, 2, t)
		Session.update(session, t + C.DISCONNECT_GRACE)
		expect(session.result):toEqual({ winner = 0, reason = "Abandoned" })
	end)
end)

describe("Session: abort", function()
	it("ends a live match as abandoned and tells every connected human", function()
		local session = humans()
		Session.drain(session)
		local before = session.step
		Session.abort(session, 3)
		expect(session.stage):toBe("Over")
		expect(session.result):toEqual({ winner = 0, reason = "Abandoned" })
		expect(session.step):toBe(before + 1)
		expect(Session.nextWake(session)):toBe(math.huge)
		local messages = Session.drain(session)
		expect(#messages):toBe(2)
		for _, message in messages do
			local state = message.state :: Session.StatePayload
			expect(state.stage):toBe("Over")
			expect(state.result):toEqual({ winner = 0, reason = "Abandoned" })
		end
		Session.update(session, 1000)
		expect(session.stage):toBe("Over")
	end)

	it("leaves a finished match's result alone", function()
		local session = humans()
		local t = 0
		while session.stage ~= "Over" do
			if session.stage == "Input" then
				lockAll(session, t)
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
		Session.drain(session)
		local step = session.step
		Session.abort(session, t)
		expect((session.result :: Session.Result).reason):toBe("Election")
		expect(session.step):toBe(step)
		expect(#Session.drain(session)):toBe(0)
	end)
end)

describe("Session: options", function()
	it("a private lobby can turn the event deck off; the default keeps it (D-027)", function()
		local seats: { Session.SeatSpec } = { { id = "1", kind = "Human" }, { id = "2", kind = "Human" } }
		local off = Session.new(C, "m", 4, seats, 0, { events = false })
		expect(off.config.EVENTS_ENABLED):toBe(false)
		expect(next(off.match.eventDeck)):toBe(nil)
		local on = Session.new(C, "m", 4, seats, 0)
		expect(on.config.EVENTS_ENABLED):toBe(true)
		expect(next(on.match.eventDeck) ~= nil):toBe(true)
		-- Timers and flow are untouched: same deadline, same first stage.
		expect(off.deadline):toBe(on.deadline)
		expect(off.stage):toBe(on.stage)
		expect(Session.new(C, "m", 4, seats, 0, { events = true }).config.EVENTS_ENABLED):toBe(true)
	end)
end)

describe("Session: bots and replication", function()
	it("a bot seat locks in by itself every input stage", function()
		local session = practice()
		expect(session.seats[2].locked):toBe(true)
		Session.submit(session, 1, session.step, SELECTION, 1)
		expect(session.match.players[2].candidate):toBe("hale")
		Session.update(session, 1 + C.TIMER_MAP_REVEAL)
		expect(session.match.phase):toBe("Draft")
		expect(session.seats[2].locked):toBe(true)
	end)

	it("practice: the human plays a full match against the bot", function()
		local session = practice()
		local t = 0
		for _ = 1, 200 do
			if session.stage == "Over" then
				break
			end
			if session.stage == "Input" then
				lockAll(session, t)
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
		expect((session.result :: Session.Result).reason):toBe("Election")
	end)

	it("payloads are plain data that a RemoteEvent can carry", function()
		local session = humans()
		lockAll(session, 0)
		local function check(value: any, path: string)
			local kind = type(value)
			assert(kind ~= "function" and kind ~= "userdata" and kind ~= "thread", `{path} is a {kind}`)
			if kind ~= "table" then
				return
			end
			local count, numeric, text = 0, 0, 0
			for key in value do
				count += 1
				if type(key) == "number" then
					numeric += 1
				elseif type(key) == "string" then
					text += 1
				else
					error(`{path} has a {type(key)} key`)
				end
			end
			-- No mixed tables, and arrays have no holes.
			assert(numeric == 0 or text == 0, `{path} mixes numeric and string keys`)
			assert(numeric == 0 or #value == numeric, `{path} is a sparse array`)
			for key, child in value do
				check(child, `{path}.{key}`)
			end
		end
		local t = 0
		for _ = 1, 200 do
			for _, message in Session.drain(session) do
				check(message, "message")
			end
			if session.stage == "Over" then
				break
			end
			if session.stage == "Input" then
				lockAll(session, t)
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
	end)
end)
