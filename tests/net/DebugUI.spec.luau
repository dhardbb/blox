--!strict
-- The Phase 2 debug UI's command parser and text formatter.

local Test = require("@testlib/Test")
local Bot = require("@sim/Bot")
local Commands = require("@shared/DebugUI/Commands")
local Config = require("@sim/Config")
local Format = require("@shared/DebugUI/Format")
local Match = require("@sim/Match")
local Rng = require("@sim/Rng")
local Session = require("@net/Session")
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

	it("parses a Choice answer, and the validator takes it in a Choice week", function()
		local parsed = Commands.parse("plan choice DEFEND; poll OH")
		expect(parsed.input):toEqual({ actions = { { kind = "Poll", state = "OH" } }, choice = "Defend" })
		expect(Commands.parse("plan choice surrender").kind):toBe("Error")
		local match = Match.new(C, 3, { "a", "b" })
		while not (match.phase == "Plan" and match.week == 2) do
			match = Match.advance(C, match, {})
		end
		match.eventDeck[2] = "clip"
		local ok, reason = Match.validate(C, match, 1, Commands.parse("plan choice attack").input)
		expect(reason):toBe(nil)
		expect(ok):toBe(true)
	end)

	it("shows this week's event and last week's revealed answers on the board", function()
		local session = Session.new(C, "m1", 11, {
			{ id = "1", kind = "Human" },
			{ id = "bot", kind = "Bot", candidate = "reyes" },
		}, 0)
		local match = session.match
		while not (match.phase == "Plan" and match.week == 2) do
			match = Match.advance(C, match, {})
		end
		match.eventDeck[2] = "expo"
		match.eventDeck[3] = "clip"
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
		session.match = Match.advance(C, match, { { actions = {}, choice = "Attack" } })
		board = Format.board(Session.payload(session, 1), 0)
		expect(
			string.find(board, "Last week's event Viral clip: you Attack (+0.2), them Ignore (-0.2)", 1, true)
				~= nil
		):toBe(true)
		expect(string.find(board, "choice Ignore", 1, true) ~= nil):toBe(true)
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
end)
