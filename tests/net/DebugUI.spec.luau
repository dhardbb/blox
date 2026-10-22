--!strict
-- The Phase 2 debug UI's command parser and text formatter.

local Test = require("@testlib/Test")
local Bot = require("@sim/Bot")
local Commands = require("@shared/DebugUI/Commands")
local Config = require("@sim/Config")
local Fixtures = require("@ui/Fixtures")
local Format = require("@shared/DebugUI/Format")
local Match = require("@sim/Match")
local Rng = require("@sim/Rng")
local Session = require("@net/Session")
local State = require("@sim/State")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

describe("Commands.parse", function()
	it("parses lobby commands", function()
		expect(Commands.parse("practice")):toEqual({ kind = "Request", op = "Practice" })
		expect(Commands.parse("  Queue ")):toEqual({ kind = "Request", op = "Queue" })
		expect(Commands.parse("join ab3cd")):toEqual({ kind = "Request", op = "Join", code = "AB3CD" })
		expect(Commands.parse("join abc").kind):toBe("Error")
		expect(Commands.parse("host")):toEqual({ kind = "Request", op = "Host" })
		expect(Commands.parse("host noevents")):toEqual({ kind = "Request", op = "Host", events = false })
		expect(Commands.parse("host loud").kind):toBe("Error")
	end)

	it("parses selections and pre-picks, case-insensitively", function()
		local pick = { candidate = "hale", color = "Teal", platform = { "Jobs", "Transit", "Farms" } }
		expect(Commands.parse("select Hale teal jobs TRANSIT farms")):toEqual({
			kind = "Request",
			op = "Submit",
			input = pick,
		})
		expect(Commands.parse("pick hale teal jobs transit farms")):toEqual({
			kind = "Request",
			op = "PrePick",
			pick = pick,
		})
		expect(Commands.parse("select nobody teal jobs transit farms").kind):toBe("Error")
		expect(Commands.parse("select hale teal jobs").kind):toBe("Error")
	end)

	it("parses draft picks", function()
		expect(Commands.parse("draft oh pa")):toEqual({
			kind = "Request",
			op = "Submit",
			input = { choices = { "OH", "PA" } },
		})
		expect(Commands.parse("draft ohio").kind):toBe("Error")
	end)

	it("parses a full plan into Plan.validate's shape", function()
		local parsed = Commands.parse(
			"plan rally OH jobs; fund PA, media MI health; attack IA farms; poll OH; rpoll pacific; gotv OH 2; pivot schools farms; prep 4 2 0"
		)
		expect(parsed.kind):toBe("Request")
		expect(parsed.input):toEqual({
			actions = {
				{ kind = "Rally", state = "OH", issue = "Jobs" },
				{ kind = "Fundraise", state = "PA" },
				{ kind = "Media", state = "MI", issue = "Health" },
				{ kind = "Attack", state = "IA", issue = "Farms" },
				{ kind = "Poll", state = "OH" },
				{ kind = "RegionPoll", region = "Pacific" },
				{ kind = "Gotv", state = "OH", units = 2 },
				{ kind = "Pivot", drop = "Schools", add = "Farms" },
			},
			prep = { 4, 2, 0 },
		})
		expect(Commands.parse("plan rally OH").kind):toBe("Error")
		expect(Commands.parse("plan dance OH").kind):toBe("Error")
		expect(Commands.parse("pass")):toEqual({ kind = "Request", op = "Submit", input = { actions = {} } })
	end)

	it("a parsed plan passes the real validator", function()
		local match = Match.new(C, 3, { "a", "b" })
		while match.phase ~= "Plan" do
			match = Match.advance(C, match, {})
		end
		local home = match.players[1].location :: string
		local parsed = Commands.parse(`plan rally {home} jobs; fund {home}; poll OH`)
		local ok, reason = Match.validate(C, match, 1, parsed.input)
		expect(reason):toBe(nil)
		expect(ok):toBe(true)
	end)

	it("parses a Choice stance, and the validator takes it in a Choice week", function()
		local parsed = Commands.parse("plan choice b; poll OH")
		expect(parsed.input):toEqual({ actions = { { kind = "Poll", state = "OH" } }, choice = "B" })
		expect(Commands.parse("plan choice surrender").kind):toBe("Error")
		expect(Commands.parse("plan choice attack").kind):toBe("Error")
		local match = Match.new(C, 3, { "a", "b" })
		while not (match.phase == "Plan" and match.week == 2) do
			match = Match.advance(C, match, {})
		end
		match.eventDeck[2] = "plant"
		local ok, reason = Match.validate(C, match, 1, Commands.parse("plan choice A").input)
		expect(reason):toBe(nil)
		expect(ok):toBe(true)
	end)

	it("shows this week's event and last week's revealed stances on the board", function()
		local session = Session.new(C, "m1", 11, {
			{ id = "1", kind = "Human" },
			{ id = "bot", kind = "Bot", candidate = "reyes" },
		}, 0)
		local match = session.match
		while not (match.phase == "Plan" and match.week == 2) do
			match = Match.advance(C, match, {})
		end
		match.eventDeck[2] = "expo"
		match.eventDeck[3] = "plant"
		session.match = match
		local board = Format.board(Session.payload(session, 1), 0)
		expect(
			string.find(
				board,
				"Event this week: Tech expo (Spotlight: rallies and ads on Technology x1.3",
				1,
				true
			) ~= nil
		):toBe(true)
		match = Match.advance(C, match, {})
		session.match = Match.advance(C, match, { { actions = {}, choice = "A" } })
		board = Format.board(Session.payload(session, 1), 0)
		local moved = #(session.match.eventLog[#session.match.eventLog].moves :: { State.StateMove })
		expect(
			string.find(
				board,
				`Last week's event Plant at a crossroads: you took stance A, them C ({moved} states moved)`,
				1,
				true
			) ~= nil
		):toBe(true)
		expect(string.find(board, "choice C", 1, true) ~= nil):toBe(true)
	end)

	it("parses local actions and rejects nonsense", function()
		expect(Commands.parse("auto")):toEqual({ kind = "Local", action = "auto" })
		expect(Commands.parse("autoplay ON")):toEqual({ kind = "Local", action = "autoplay", arg = "on" })
		expect(Commands.parse("show oh")):toEqual({ kind = "Local", action = "show", arg = "OH" })
		expect(Commands.parse("").kind):toBe("Error")
		expect(Commands.parse("dance").kind):toBe("Error")
	end)
end)

describe("Format", function()
	it("renders every payload of a full practice match without errors", function()
		local session = Session.new(C, "m1", 11, {
			{ id = "1", kind = "Human" },
			{ id = "bot", kind = "Bot", candidate = "reyes" },
		}, 0)
		local rng = Rng.new(1)
		local t = 0
		local rendered = 0
		for _ = 1, 300 do
			for _, message in Session.drain(session) do
				local payload = message.state
				if payload then
					local text = Format.board(payload, t)
					expect(#text > 0):toBe(true)
					expect(#Format.status(payload, nil, t) > 0):toBe(true)
					expect(#Format.state(payload, "OH") > 0):toBe(true)
					rendered += 1
				end
			end
			if session.stage == "Over" then
				break
			end
			if session.stage == "Input" and not session.seats[1].locked then
				local input = Bot.act(C, View.build(C, session.match, 1), rng, "okafor")
				Session.submit(session, 1, session.step, input, t)
			else
				t = Session.nextWake(session)
				Session.update(session, t)
			end
		end
		expect(session.stage):toBe("Over")
		expect(rendered > 30):toBe(true)
	end)

	it("shows the lobby when no match is running", function()
		local text = Format.status(nil, { state = "Hosting", code = "AB3CD", queued = 0, full = false }, 0)
		expect(string.find(text, "join AB3CD", 1, true) ~= nil):toBe(true)
		expect(Format.status(nil, nil, 0)):toBe("Connecting...")
	end)

	it("shows the saved rating in the lobby line once it has loaded", function()
		local profile = { rating = 1032, games = 19, wins = 12, losses = 7 }
		local text = Format.status(nil, { state = "Idle", queued = 0, full = false, profile = profile }, 0)
		expect(string.find(text, "Rating 1032 (12-7)", 1, true) ~= nil):toBe(true)
		local bare = Format.status(nil, { state = "Idle", queued = 0, full = false }, 0)
		expect(string.find(bare, "Rating", 1, true)):toBe(nil)
	end)

	it("formats a rating change", function()
		expect(Format.ratingChange({ matchId = "m1", before = 1032, after = 1048 })):toBe(
			"Rating 1032 → 1048"
		)
	end)
end)

describe("Format.rejected (playtest 1, bug 2)", function()
	it("explains NotEnoughMoney with the plan's cost and the cash", function()
		local payload = Fixtures.payload(C, "Plan")
		local view = payload.view
		local me = view.players[view.you]
		me.cash = 4.96
		local input = Commands.parse("plan rpoll pacific; rpoll mountain").input
		local text = Format.rejected(payload, "Submit", "NotEnoughMoney", input)
		expect(text):toBe(
			string.format(
				"rejected Submit: NotEnoughMoney. Plan costs $%.1f, you have $4.9 (2 region polls $%.1f).",
				2 * C.REGION_POLL_COST,
				2 * C.REGION_POLL_COST
			)
		)
	end)

	it("keeps other rejections short, and never throws on odd input", function()
		local payload = Fixtures.payload(C, "Plan")
		expect(Format.rejected(payload, "Submit", "NotEnoughAP", nil)):toBe("rejected Submit: NotEnoughAP")
		expect(Format.rejected(nil, nil, nil, nil)):toBe("rejected ?: ?")
		expect(Format.rejected(payload, "Submit", "NotEnoughMoney", { actions = { { kind = "Gotv" } } })):toBe(
			"rejected Submit: NotEnoughMoney"
		)
	end)
end)

describe("Format.events and Format.debate (playtest 1, bugs 3 to 5)", function()
	it("says what each player picked in a draft reveal, not just 'Pick Pick'", function()
		local lines = Format.events({
			{ kind = "Pick", player = 1, state = "OH", issue = "Home" },
			{ kind = "Pick", player = 2, state = "PA", issue = "Home" },
		}, 2)
		expect(lines):toEqual({ "P1 picked OH (home)", "P2 (you) picked PA (home)" })
		lines = Format.events({
			{ kind = "Pick", player = 2, state = "TX", issue = "Stronghold" },
			{ kind = "Pick", player = 1, state = "FL", issue = "Nominate" },
		}, 1)
		expect(lines):toEqual({ "P2 picked TX (stronghold)", "P1 (you) nominated FL (battleground)" })
	end)

	it("formats money and points in event lines", function()
		local lines = Format.events({
			{ kind = "Raised", player = 1, amount = 13.550725999999997, private = true },
			{ kind = "Choice", player = 2, issue = "A", amount = -0.2 },
			{ kind = "Rally", player = 2, state = "OH", issue = "Jobs" },
			{ kind = "Flights", player = 1, amount = 1 },
			{ kind = "Polls" },
		}, 1)
		expect(lines):toEqual({
			"you raised $13.5",
			"P2 took stance A (-0.2 points over the states that reacted)",
			"P2 rallied in OH on Jobs",
			"P1 (you) took 1 flight",
			"new public polls",
		})
		for _, line in lines do
			expect(string.find(line, "%d%.%d%d") == nil):toBe(true)
		end
	end)

	it("prints debate national points with one sign each", function()
		local text = Format.debate(
			{
				week = 9,
				topics = { "Transit", "Environment", "Safety" },
				prep = { { 4, 2, 0 }, { 2, 2, 2 } },
				scores = { { 8, 5, 3 }, { 8, 7, 6 } },
				winners = { 0, 2, 2 },
				national = { -0.2, 0.4 },
			} :: any,
			1
		)
		expect(text):toBe(
			"Debate week 9: Transit tie (prep 4/2), Environment them (prep 2/2), Safety them (prep 0/2); national -0.2 you, +0.4 them"
		)
	end)
end)

describe("Format color clash (playtest 1, bug 6)", function()
	it("puts the actual color on the board and explains the clash", function()
		local payload = Fixtures.payload(C, "Plan")
		local me = payload.view.players[payload.you]
		local other = payload.view.players[3 - payload.you]
		me.pickedColor = other.color
		me.color = if other.color == "Crimson" then "Cobalt" else "Crimson"
		local board = Format.board(payload, 0)
		expect(string.find(board, `({me.color})`, 1, true) ~= nil):toBe(true)
		expect(string.find(board, "coin flip gave it to them", 1, true) ~= nil):toBe(true)
		me.pickedColor = me.color
		expect(string.find(Format.board(payload, 0), "coin flip", 1, true)):toBe(nil)
	end)
end)

describe("Format explanations (playtest 2: the numbers were opaque)", function()
	local Explain = require("@ui/Explain")
	local PlanDraft = require("@ui/PlanDraft")

	local function has(text: string, part: string)
		if string.find(text, part, 1, true) == nil then
			error(`"{text}" lacks "{part}"`, 0)
		end
	end

	it("tags a lean from the viewer's side", function()
		local payload = Fixtures.payload(C, "Plan")
		local s = payload.view.states[State.indexOf.OH]
		s.lean, s.leanTo = 4, payload.you
		expect(table.find(Format.stateTags(s, payload.you), "leans you +4") ~= nil):toBe(true)
		s.leanTo = 3 - payload.you
		expect(table.find(Format.stateTags(s, payload.you), "leans them +4") ~= nil):toBe(true)
	end)

	it("explains a state and previews each action there with show", function()
		local payload = Fixtures.payload(C, "Plan")
		local view = payload.view
		local text = Format.state(payload, "OH")
		local s = view.states[State.indexOf.OH]
		has(text, Explain.leanText(view, s))
		has(text, Explain.momentumNote(C, view, s))
		local message = PlanDraft.bestIssue(C, view, "OH")
		for _, entry in Explain.previews(C, view, PlanDraft.new(), "OH", message) do
			has(text, entry.text)
		end
	end)

	it("prints every help section with rules", function()
		expect(Commands.parse("rules")):toEqual({ kind = "Local", action = "rules" })
		local payload = Fixtures.payload(C, "Plan")
		local text = Format.rules(payload)
		for _, section in Explain.help(C, payload.view) do
			has(text, `== {section.title} ==`)
			has(text, section.lines[1])
		end
		has(Format.rules(nil), "standard ones")
	end)

	it("says what an underdog tier gives on the board", function()
		local payload = Fixtures.payload(C, "Plan")
		payload.view.players[payload.you].underdogTier = 2
		has(Format.board(payload, 0), Explain.underdogText(C, payload.view, payload.you) :: string)
	end)
end)

describe("Commands: player-facing action names (playtest 2, bug 1)", function()
	local function has(text: string, part: string)
		expect(string.find(text, part, 1, true) ~= nil):toBe(true)
	end

	it("takes ad, attack ad and attackad like media and attack (D-030 names)", function()
		local media = { kind = "Media", state = "MI", issue = "Health" }
		local attack = { kind = "Attack", state = "IA", issue = "Farms" }
		expect(Commands.parse("plan ad MI health").input):toEqual({ actions = { media } })
		expect(Commands.parse("plan Ad mi HEALTH").input):toEqual({ actions = { media } })
		expect(Commands.parse("plan media MI health").input):toEqual({ actions = { media } })
		expect(Commands.parse("plan attack ad IA farms").input):toEqual({ actions = { attack } })
		expect(Commands.parse("plan attackad IA farms").input):toEqual({ actions = { attack } })
		expect(Commands.parse("plan attack IA farms").input):toEqual({ actions = { attack } })
		expect(Commands.parse("plan fundraise PA").input):toEqual({
			actions = { { kind = "Fundraise", state = "PA" } },
		})
		expect(Commands.parse("plan ad MI").kind):toBe("Error")
		expect(Commands.parse("plan attack ad IA").kind):toBe("Error")
	end)

	it("help names the actions as the game does, and every plan in it parses", function()
		has(Commands.HELP, "ad MI Jobs")
		has(Commands.HELP, "attack ad IA Farms")
		expect(string.find(Commands.HELP, "media", 1, true)):toBe(nil)
		local plan = string.match(Commands.HELP, "Plan: (plan [^\n]-);?\n") :: string
		local parsed = Commands.parse(plan)
		expect(parsed.message):toBe(nil)
		expect(#parsed.input.actions):toBe(6)
	end)
end)
