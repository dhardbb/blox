--!strict
-- Shared/UI/Words/Setup (WP-A, docs/UI-STYLE.md §2.8): the short copy of the
-- Lobby, Select, the map reveal and the draft. Plain words, labels of at most
-- 8 words, "votes" in sentences, "actions" for AP, and numbers that match Config
-- and the candidate roster.

local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Test = require("@testlib/Test")
local Words = require("@ui/Words/Setup")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local CARD_LINE = 18 -- characters a candidate card line holds on a phone (one line)

local function words(text: string): number
	local n = 0
	for _ in string.gmatch(text, "%S+") do
		n += 1
	end
	return n
end

describe("Words.Setup: candidates", function()
	it("gives every candidate a one-line strength and weakness", function()
		for _, id in Candidates.ids do
			expect(Words.hasShort(id)):toBe(true)
			local short = Words.candidate(C, id)
			for _, line in { short.strength, short.weakness } do
				expect(words(line) <= 8):toBe(true)
				expect(utf8.len(line) :: number <= CARD_LINE):toBe(true)
				expect(string.find(line, "AP", 1, true)):toBe(nil)
			end
		end
	end)

	it("lists each candidate's real numbers in the details, with actions for AP", function()
		for _, id in Candidates.ids do
			local profile = Candidates.profile(C, id)
			local lines = Words.candidateDetails(C, id)
			expect(lines[1]):toBe(profile.archetype)
			expect(lines[4]):toBe(`Actions each week: {profile.apPerWeek}`)
			expect(string.find(lines[5], "Starting money: $", 1, true) ~= nil):toBe(true)
			expect(string.find(lines[6], " a week", 1, true) ~= nil):toBe(true)
			for _, line in lines do
				expect(string.find(line, " AP", 1, true)):toBe(nil)
			end
		end
		expect(Words.candidateDetails(C, "calloway")[2]):toBe("Strength: 4 actions per week.")
	end)

	it("takes the first name", function()
		expect(Words.firstName("Rex Calloway")):toBe("Rex")
		expect(Words.firstName("Rex")):toBe("Rex")
	end)
end)

describe("Words.Setup: issues", function()
	it("words a multiplier as a percent boost", function()
		expect(Words.boost(1.41)):toBe("+41%")
		expect(Words.boost(2)):toBe("+100%")
		expect(Words.boost(1)):toBe("+0%")
	end)

	it("puts votes and boost on one line, or two on a phone", function()
		expect(Words.issueLine(154, 1.41)):toBe("154 votes · +41% boost")
		expect(Words.issueLine(154, 1.41, true)):toBe("154 votes\n+41% boost")
		expect(Words.issueLine(154, nil)):toBe("154 votes")
		expect(Words.issueLine(nil, nil)):toBe("")
	end)

	it("keeps the issues help in a sheet-sized handful of sentences", function()
		for _, line in Words.ISSUES_HELP do
			expect(words(line) <= 30):toBe(true)
		end
	end)
end)

describe("Words.Setup: the now line", function()
	it("counts down the issues to pick", function()
		expect(Words.nowIssues(0, 3)):toBe("Pick 3 issues")
		expect(Words.nowIssues(1, 3)):toBe("Pick 2 more issues")
		expect(Words.nowIssues(2, 3)):toBe("Pick 1 more issue")
		expect(Words.nowIssues(3, 3)):toBe("All set? Lock in")
	end)

	it("says what each draft round wants", function()
		expect(Words.nowDraft("Home", false)):toBe("Pick your home state")
		expect(Words.nowDraft("Nominate", false)):toBe("Pick a battleground")
		expect(Words.nowDraft("Nominate", true)):toBe("Add a backup, or Lock in")
		expect(Words.nowWaiting("Rex")):toBe("Waiting for Rex…")
	end)

	it("keeps every fixed line at 8 words or fewer", function()
		for _, line in
			{ Words.TAGLINE, Words.NOW_CANDIDATE, Words.NOW_CLAIMING, Words.NOW_MAP, Words.HOSTING_WAIT }
		do
			expect(words(line) <= 8):toBe(true)
		end
	end)
end)

describe("Words.Setup: the draft", function()
	it("says on a battleground round what one does, for both (S4)", function()
		expect(Words.battlegroundCaption(C)):toBe(
			`Battleground: every rally and ad here counts ×{C.BATTLEGROUND_MULT}, for both of you. Pick where you can win.`
		)
		expect(Words.battlegroundCaption(Config.with(C, { BATTLEGROUND_MULT = 2 }))):toBe(
			"Battleground: every rally and ad here counts ×2, for both of you. Pick where you can win."
		)
	end)

	it("names the opponent instead of them", function()
		expect(Words.lean(2, true, "Rex")):toBe("+2 you")
		expect(Words.lean(3, false, "Rex")):toBe("+3 Rex")
		expect(Words.lean(0, nil, "Rex")):toBe("Even")
		expect(Words.priority(true, "Rex")):toBe("Ties go to you")
		expect(Words.priority(false, "Rex")):toBe("Ties go to Rex")
		expect(Words.votes(1)):toBe("1 vote")
		expect(Words.votes(30)):toBe("30 votes")
	end)

	it("states the round rules from Config, without multipliers", function()
		local home = Words.roundRule(C, "Home")
		expect(string.find(home, `+{C.HOME_BONUS} support`, 1, true) ~= nil):toBe(true)
		local battleground = Words.roundRule(C, "Nominate")
		expect(string.find(battleground, Words.boost(C.BATTLEGROUND_MULT), 1, true) ~= nil):toBe(true)
		expect(string.find(battleground, "×", 1, true)):toBe(nil)
		expect(string.find(Words.strongholdsNote(C), tostring(C.STRONGHOLD_COUNT), 1, true) ~= nil):toBe(true)
	end)
end)
