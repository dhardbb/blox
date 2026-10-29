--!strict
-- The match-record summary (D-094; tests/lib/Records, tests/harness/records.luau):
-- JSON lines in (raw records or Open Cloud entries), a balance-style report out.

local serde = require("@lune/serde")

local Test = require("@testlib/Test")
local Bot = require("@sim/Bot")
local Config = require("@sim/Config")
local MatchRecord = require("@net/MatchRecord")
local Records = require("@testlib/Records")
local Rng = require("@sim/Rng")
local Session = require("@net/Session")
local View = require("@sim/View")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

-- A human (a bot-made input each time, as the debug UI's "auto" builds one)
-- playing candidate `a` against a practice bot playing `b`, to the end.
local function botMatch(seed: number, a: string, b: string): Session.Session
	local session = Session.new(C, `m{seed}`, seed, {
		{ id = "100", kind = "Human", prePick = { candidate = a } },
		{ id = "bot", kind = "Bot", candidate = b, difficulty = "Extreme" },
	}, 0)
	local rng = Rng.new(seed)
	local t = 0
	for _ = 1, 2000 do
		if session.stage == "Over" then
			break
		end
		if session.stage == "Input" and not session.seats[1].locked then
			local input = Bot.act(session.config, View.build(session.config, session.match, 1), rng, a)
			assert(Session.submit(session, 1, session.step, input, t))
			continue
		end
		t = math.max(t + 0.1, Session.nextWake(session))
		Session.update(session, t)
	end
	assert(session.stage == "Over", "the match never finished")
	return session
end

local function recordOf(session: Session.Session, mode: MatchRecord.Mode): MatchRecord.Record
	return MatchRecord.build(session, {
		mode = mode,
		rated = false,
		version = "0.17.0",
		at = 1793232000,
		ended = 720,
		server = "job",
	})
end

local function has(lines: { string }, text: string): boolean
	for _, l in lines do
		if string.find(l, text, 1, true) then
			return true
		end
	end
	return false
end

describe("Records: summarizing exported match records (D-094)", function()
	local sessions = { botMatch(301, "okafor", "hale"), botMatch(302, "venkat", "strand") }
	local records = { recordOf(sessions[1], "Practice"), recordOf(sessions[2], "Queue") }

	it("reads raw records and Open Cloud entries, skipping anything else", function()
		local text = table.concat({
			serde.encode("json", records[1]),
			"",
			serde.encode("json", { path = "x", value = records[2] }),
			"not json",
			serde.encode("json", { v = MatchRecord.SCHEMA + 1, seats = {} }),
		}, "\n")
		local parsed, skipped = Records.parse(text)
		expect(#parsed):toBe(2)
		expect(skipped):toBe(2)
		expect(parsed[2].seed):toBe(302)
	end)

	it("prints the harness's sections with the right counts", function()
		local parsed =
			Records.parse(serde.encode("json", records[1]) .. "\n" .. serde.encode("json", records[2]))
		local lines = Records.summarize(parsed)
		expect(lines[1]):toBe("270 match records: 2 matches, 2 reached election night")
		expect(has(lines, "Modes: Queue 1 · Practice 1")):toBe(true)
		expect(has(lines, "Candidates (mirror matches excluded)")):toBe(true)
		expect(has(lines, "Matchup matrix (row's win rate vs column)")):toBe(true)
		expect(has(lines, "Landslides (winner over 70% of EV)")):toBe(true)
		expect(has(lines, "Debate decisive")):toBe(true)
		expect(has(lines, "Full match minutes p50 / p90")):toBe(true)
		-- Each match counts once for each candidate.
		local okafor = 0
		for _, l in lines do
			if string.find(l, "Goldie Pennywhistle", 1, true) then
				okafor += 1
				expect(string.find(l, "of 1", 1, true) ~= nil):toBe(true)
			end
		end
		expect(okafor):toBe(1)
	end)

	it("filters by mode, people only and version", function()
		expect(#Records.filter(records, { mode = "Queue" })):toBe(1)
		expect(#Records.filter(records, { humans = true })):toBe(0)
		expect(#Records.filter(records, { version = "0.16.0" })):toBe(0)
		local lines = Records.summarize({})
		expect(lines[1]):toBe("270 match records: 0 matches, 0 reached election night")
	end)
end)
