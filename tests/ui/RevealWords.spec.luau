--!strict
-- Shared/UI/Words/Reveal (WP-C, docs/UI-STYLE.md §4.7 to §4.10): the short copy
-- of the reveal, the debate scoreboard, election night, Results and Help. Pure,
-- so it runs on the fixtures directly: merged lines never repeat, flips and
-- moves come from two public polls, the map gets a handful of badges, and every
-- line stays short and says "votes", never "EV".

local Config = require("@sim/Config")
local Fixtures = require("@ui/Fixtures")
local SimState = require("@sim/State")
local Swing = require("@ui/Swing")
local Test = require("@testlib/Test")
local Words = require("@ui/Words/Reveal")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function words(text: string): number
	local n = 0
	for _ in string.gmatch(text, "%S+") do
		n += 1
	end
	return n
end

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for key, child in value do
		out[key] = deepCopy(child)
	end
	return out
end

describe("Words: the week's groups", function()
	it("merges the same action in the same state into one line", function()
		local payload = Fixtures.payload(C, "Resolve")
		local groups = Words.group(payload.view, payload.events)
		for _, side in { groups.mine, groups.theirs } do
			local seen: { [string]: boolean } = {}
			for _, line in side do
				check(not seen[line], `"{line}" is listed twice`)
				seen[line] = true
				check(not string.find(line, "EV", 1, true), `"{line}" says EV`)
			end
		end
		-- The fixture rallies twice in Texas on the same issue.
		local merged = false
		for _, line in groups.mine do
			if string.find(line, "Rally in Texas ×2", 1, true) then
				merged = true
			end
		end
		check(merged, "no merged line: " .. table.concat(groups.mine, " | "))
		check(#groups.theirs > 0, "the opponent's week is empty")
	end)

	it("puts each side's events in its own group, and only those it shows", function()
		local view = Fixtures.payload(C, "Resolve").view
		local them = if view.you == 1 then 2 else 1
		local events: { SimState.Event } = {
			{ kind = "Rally", player = view.you, state = "OH", issue = "Jobs" },
			{ kind = "Media", player = them, state = "PA", issue = "Health" },
			{ kind = "Rally", player = view.you, state = "OH", issue = "Jobs" },
			{ kind = "Polls" },
			{ kind = "Flights", player = view.you, amount = 2 },
			{ kind = "Raised", player = view.you, amount = 3.25 },
		}
		local groups = Words.group(view, events)
		expect(groups.mine[1]):toBe("Rally in Ohio ×2 · Jobs")
		expect(groups.mine[2]):toBe("Raised $3.2 in all")
		expect(groups.mine[3]):toBe("Took 2 flights")
		expect(#groups.mine):toBe(3)
		expect(groups.theirs[1]):toBe("Ad in Pennsylvania · Health")
		expect(#Words.group(view, events, 1).mine):toBe(1)
	end)

	it("writes a Choice stance with the event's name", function()
		local payload = Fixtures.payload(C, "ChoiceResolve")
		local groups = Words.group(payload.view, payload.events)
		local entry = Swing.lastChoice(payload.view)
		check(entry ~= nil, "no Choice result")
		local stance = false
		for _, line in groups.mine do
			if string.find(line, ": stance ", 1, true) then
				stance = true
			end
		end
		check(stance, "no stance line: " .. table.concat(groups.mine, " | "))
	end)
end)

describe("Words: what changed", function()
	it("finds every flip and the biggest moves between two polls", function()
		local new = Fixtures.payload(C, "Resolve").view
		local old = deepCopy(new)
		-- Hand Ohio to the rival on the old poll and move Texas by 4 points.
		local them = if new.you == 1 then 2 else 1
		local oh = old.states[SimState.indexOf.OH]
		local newOh = new.states[SimState.indexOf.OH]
		check(oh.poll ~= nil and newOh.poll ~= nil, "no Ohio poll in the fixture")
		oh.poll.support[new.you] = 30
		oh.poll.support[them] = 60
		local tx = old.states[SimState.indexOf.TX]
		local margin = tx.poll.support[new.you] - tx.poll.support[them]
		tx.poll.support[new.you] -= 0.04 -- under 0.05: not a move
		local changes = Words.pollChanges(old, new)
		local ohFlip = false
		for _, flip in changes.flips do
			if flip.state == "OH" then
				ohFlip = true
				expect(flip.from):toBe(them)
				expect(flip.ev):toBe(17)
			end
		end
		local newMargin = newOh.poll.support[new.you] - newOh.poll.support[them]
		check(ohFlip == (newMargin >= 0), "Ohio's flip was missed")
		for _, move in changes.moves do
			check(move.state ~= "TX", `Texas moved by {move.delta} (margin {margin})`)
		end
		for k = 2, #changes.moves do
			check(
				math.abs(changes.moves[k - 1].delta) >= math.abs(changes.moves[k].delta),
				"moves are not biggest first"
			)
		end
	end)

	it("says flips in votes and names the opponent", function()
		local view = Fixtures.payload(C, "Resolve").view
		local them = if view.you == 1 then 2 else 1
		expect(Words.flipLine(view, { state = "OH", from = them, to = view.you, ev = 17 }, "Rex")):toBe(
			"Ohio flips to you · 17 votes"
		)
		expect(Words.flipLine(view, { state = "OH", from = view.you, to = them, ev = 17 }, "Rex")):toBe(
			"Ohio flips to Rex · 17 votes"
		)
		expect(Words.flipTone(view, { state = "OH", from = view.you, to = 0, ev = 17 })):toBe("bad")
		expect(Words.movePill({ state = "TX", delta = -2.5, ev = 40 }, "Rex")):toBe("TX +2.5 for Rex")
	end)

	it("badges the flips and only the few biggest other moves", function()
		local net: { [string]: number } = {}
		for k, id in { "OH", "PA", "TX", "CA", "NY", "FL", "WA", "IL" } do
			net[id] = k * (if k % 2 == 0 then -1 else 1)
		end
		local marks = Words.topMarks(net, { { state = "OH", from = 2, to = 1, ev = 17 } })
		local count = 0
		for _ in marks do
			count += 1
		end
		expect(count):toBe(1 + Words.MAP_MARKS)
		expect(marks.OH):toBe(1)
		expect(marks.IL):toBe(-8)
		expect(marks.PA):toBe(nil)
	end)
end)

describe("Words: debates", function()
	it("gives each topic a verdict and one short line", function()
		local view = Fixtures.payload(C, "Debate").view
		local result = view.debates[#view.debates]
		for t = 1, #result.topics do
			local verdict, tone = Words.verdict(view, result.winners[t], "Rex")
			check(verdict == "You win" or verdict == "Tie" or verdict == "Rex wins", verdict)
			check(tone ~= nil, "no tone")
			local line = Words.topicLine(C, view, result, t, "Rex")
			check(words(line) <= 20, `topic line is {words(line)} words: {line}`)
		end
		local headline = Words.debateHeadline(view, result, "Rex")
		check(string.find(headline, "topic", 1, true) ~= nil, headline)
		check(
			string.find(Words.everyState(view, result, "Rex"), "Every state also got", 1, true) ~= nil,
			"no flat points line"
		)
	end)
end)

describe("Words: election night and Results", function()
	it("calls a state in votes and points", function()
		expect(Words.stateLine("OH")):toBe("Ohio · 17 votes")
		expect(Words.callLine({ state = "OH", winner = 2, margin = 2.94 }, { "Dana", "Rex" })):toBe(
			"Rex by 2.9 points"
		)
		expect(Words.callLine({ state = "OH", winner = 0, margin = 0 }, { "Dana", "Rex" })):toBe(
			"Dead heat: no votes"
		)
	end)

	it("gives three short reasons for the winner", function()
		local payload = Fixtures.payload(C, "Over")
		local view = payload.view
		local election = view.election
		check(election ~= nil, "no election in the fixture")
		for _, winner in { 1, 2 } do
			local reasons = Words.keyReasons(C, view, winner, { "Dana", "Rex" })
			expect(#reasons):toBe(3)
			for _, text in reasons do
				check(words(text) <= Words.REASON_WORDS, `"{text}" is {words(text)} words`)
				check(not string.find(text, "EV", 1, true), `"{text}" says EV`)
			end
		end
		expect(#Words.keyReasons(C, view, 0, { "Dana", "Rex" })):toBe(0)
	end)
end)

describe("Words: Help", function()
	it("has five short tabs, each pointing at Explain's numbers", function()
		local tabs = Words.help(C)
		expect(#tabs):toBe(5)
		local ids: { [string]: boolean } = {}
		for _, tab in tabs do
			check(words(tab.text) <= Words.HELP_WORDS, `{tab.id} has {words(tab.text)} words`)
			check(words(tab.label) <= 3, `{tab.id} label is long`)
			check(#tab.sections > 0, `{tab.id} has no numbers`)
			for _, id in tab.sections do
				check(not ids[id], `section {id} is in two tabs`)
				ids[id] = true
			end
		end
		-- Every Explain.help section is behind some tab.
		local Explain = require("@ui/Explain")
		for _, section in Explain.help(C, nil) do
			check(ids[section.id] == true, `section {section.id} is in no tab`)
		end
	end)
end)

describe("Words: plain votes and actions", function()
	it("says EV as votes and AP as actions, leaving the rest alone", function()
		expect(Words.inVotes("DE flipped to you (+6 EV)")):toBe("DE flipped to you (+6 votes)")
		expect(Words.plain("Each week you get 3 AP (unused AP is lost) and $4.0 income.")):toBe(
			"Each week you get 3 actions (unused actions are lost) and $4.0 income."
		)
		expect(Words.plain("Rally (1 AP): +3.0 support")):toBe("Rally (1 action): +3.0 support")
		expect(Words.plain("no extra AP. States with 10+ EV")):toBe("no extra action. States with 10+ votes")
		expect(Words.plain("APPLE and EVENTS stay")):toBe("APPLE and EVENTS stay")
	end)
end)

describe("Words: reveal order and next time (polish WP-2)", function()
	it("puts the player behind on the polls first, yours on a tie", function()
		local view = deepCopy(Fixtures.payload(C, "Plan").view)
		local first, trails = Words.revealFirst(view)
		check(first == 1 or first == 2, "no first player")
		-- The same polls from the other seat: the same player goes first.
		local other = deepCopy(view)
		other.you = if view.you == 1 then 2 else 1
		local otherFirst, otherTrails = Words.revealFirst(other)
		if trails then
			expect(otherFirst):toBe(first)
			expect(otherTrails):toBe(true)
		end
		-- No polls at all: a tie, so each seat sees its own first.
		local blank = deepCopy(view)
		for _, s in blank.states do
			s.poll = nil
		end
		local tieFirst, tieTrails = Words.revealFirst(blank)
		expect(tieFirst):toBe(blank.you)
		expect(tieTrails):toBe(false)
		expect(Words.orderLine(blank, blank.you, false, "Rex")):toBe("Your actions land first")
		expect(Words.orderLine(blank, blank.you, true, "Rex")):toBe("You trail, so your actions land first")
		local rival = if blank.you == 1 then 2 else 1
		expect(Words.orderLine(blank, rival, true, "Rex")):toBe("Rex trails, so Rex's actions land first")
	end)

	it("gives the loser one short tip and the winner none", function()
		local view = Fixtures.payload(C, "Over").view
		local rival = if view.you == 1 then 2 else 1
		local tip = Words.nextTime(C, view, rival, { "Dana", "Rex" })
		check(tip ~= nil, "no tip after a loss")
		check(string.sub(tip :: string, 1, 15) == "Try next time: ", `tip "{tip}"`)
		check(words(tip :: string) <= Words.REASON_WORDS + 2, `"{tip}" is long`)
		check(not string.find(tip :: string, "EV", 1, true), "the tip says EV")
		expect(Words.nextTime(C, view, view.you, { "Dana", "Rex" })):toBe(nil)
		expect(Words.nextTime(C, view, 0, { "Dana", "Rex" })):toBe(nil)
	end)
end)
