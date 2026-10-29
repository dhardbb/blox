--!strict
-- Copy from the 0.15 new-player playtest (Fable review, items M2 and S3; M5 is
-- in Explain.spec): the rival's stance on the Decision screen and "same side"
-- in a resolved Choice week, and the closing weeks on the event strip, its
-- sheet and Help's numbers. Every number comes from Config.

local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Events = require("@sim/Events")
local Explain = require("@ui/Explain")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local PlanDraft = require("@ui/PlanDraft")
local Rig = require("./Rig")
local State = require("@sim/State")
local Swing = require("@ui/Swing")
local Test = require("@testlib/Test")
local Words = require("@ui/Words/Campaign")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local C = Config.defaults
local PLUS = `+{math.floor((C.CLOSING_MULT - 1) * 100 + 0.5)}%`
local SIZES = {
	{ name = "phone", screen = Rig.PHONE },
	{ name = "ipad", screen = { x = 1024, y = 768 } },
	{ name = "desktop", screen = { x = 1280, y = 720 } },
}

local function has(text: string, part: string)
	check(string.find(text, part, 1, true) ~= nil, `"{text}" lacks "{part}"`)
end

local function strictAudit(world: FakeRoblox.World, peer: FakeRoblox.Peer, screen: string): number
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	return Audit.run(FakeRoblox.find(peer, screen), screen, { strict = true })
end

-- The rival's first name, as the Campaign screen says it.
local function rivalName(view: any): string
	local them = if view.you == 1 then 2 else 1
	local player = view.players[them]
	if player.customName then
		return player.customName
	end
	local name = Candidates.profile(C, player.candidate).name
	return string.match(name, "^(%S+)") or name
end

describe("Playtest copy: the rival's stance (M2)", function()
	it("says the rival picks too, and what same and opposite sides do", function()
		expect(PlanDraft.rivalChoiceNote("Buster")):toBe(
			"Buster picks too, in secret. Same side: it mostly cancels. Opposite sides: both land."
		)
	end)

	for _, size in { SIZES[1], SIZES[2] } do
		it(`shows it under the stances, above Why?, with the rival's name ({size.name})`, function()
			local world, peer = Rig.fixture("Stance", size.screen)
			local note = Rig.need(peer, "Decision", "ChoiceRival")
			check(Rig.shown(note, "Decision"), "no rival line")
			local view = Rig.payloadOf(world, peer).view
			expect(note.Text):toBe(PlanDraft.rivalChoiceNote(rivalName(view)))
			local row = Rig.need(peer, "Decision", "ChoiceRow")
			local why = Rig.need(peer, "Decision", "ChoiceWhy")
			-- In the card's list: after the chips, before Why? (the fake engine's
			-- layout is too rough to compare positions here; the snapshot shows it).
			check(note.Parent == row.Parent and note.Parent == why.Parent, "not beside the stances")
			check(row.LayoutOrder < note.LayoutOrder and note.LayoutOrder < why.LayoutOrder, "out of order")
			expect(strictAudit(world, peer, "Decision")):toBe(0)
			Rig.noErrors(world)
		end)
	end

	it("a resolved week says same side mostly cancelled, only when nothing flipped", function()
		local view = State.deepCopy(Fixtures.payload(C, "ChoiceWeek").view) :: any
		local you, them = view.you, 3 - view.you
		local definition = Events.byId[view.event.id]
		local hedge = Events.defaultChoice()
		local side: any = nil
		for _, id in Events.CHOICES do
			local stance = Events.stance(definition, id)
			if stance and not stance.hedge then
				side = id
				break
			end
		end
		local function entry(mine: string, theirs: string, flips: { any }): any
			local choices = { "C", "C" }
			choices[you], choices[them] = mine, theirs
			local points = { 0, 0 }
			points[you], points[them] = 1.5, 1.5
			return {
				week = view.week,
				id = definition.id,
				choices = choices,
				moves = {
					{ state = "OH", points = points },
				},
				flips = flips,
			}
		end
		local SAME = "Same side, so most of it cancelled."
		local lines = Swing.choiceLines(C, view, entry(side, side, {}))
		expect(lines[#lines]):toBe(SAME)
		expect(lines[#lines - 1]):toBe("On the polls you both saw, the stances flipped no state.")
		local other = if side == "A" then "B" else "A"
		check(table.find(Swing.choiceLines(C, view, entry(side, other, {})), SAME) == nil, "different sides")
		check(table.find(Swing.choiceLines(C, view, entry(hedge, hedge, {})), SAME) == nil, "both hedged")
		local flipped =
			Swing.choiceLines(C, view, entry(side, side, { { state = "OH", from = them, to = you } }))
		check(table.find(flipped, SAME) == nil, "a state flipped")
	end)
end)

describe("Playtest copy: the closing weeks (S3)", function()
	it("names rallies and ads with the percent from Config, from the week before", function()
		local first = C.CLOSING_FROM_WEEK
		expect(Words.closing(C, first - 2)):toBe(nil)
		local before = Words.closing(C, first - 1) :: Words.Closing
		expect(before.line):toBe(`From next week: rallies, ads {PLUS}`)
		has(before.detail, `Closing weeks start next week: from week {first}`)
		has(before.detail, "attack ads too")
		for _, week in { first, C.WEEKS } do
			local closing = Words.closing(C, week) :: Words.Closing
			expect(closing.line):toBe(`Closing weeks: rallies and ads {PLUS}`)
			expect(closing.title):toBe("Closing weeks")
			expect(closing.alone):toBe(`Rallies and ads {PLUS}`)
			has(closing.detail, "until election night")
		end
		expect(Words.closing(Config.with(C, { CLOSING_MULT = 1 }), first)):toBe(nil)
		expect(Words.closing(Config.with(C, { CLOSING_MULT = 1.2 }), first).line):toBe(
			"Closing weeks: rallies and ads +20%"
		)
	end)

	it("Help's Your turn numbers say it in one line", function()
		local found: string? = nil
		for _, section in Explain.help(C, nil) do
			if section.id == "map" then
				for _, line in section.lines do
					if string.find(line, "Closing weeks", 1, true) then
						found = line
					end
				end
			end
		end
		check(found ~= nil, "no closing-weeks line in the map section")
		has(found :: string, `from week {C.CLOSING_FROM_WEEK}`)
		has(found :: string, `{PLUS} ({Explain.times(C.CLOSING_MULT)})`)
	end)

	-- The Plan fixture moved to `week`, with its event or none.
	local function atWeek(size: { x: number, y: number }, week: number, keepEvent: boolean)
		local world, peer = Rig.fixture("Plan", size)
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		payload.view.week = week
		payload.view.nextEvent = nil
		if keepEvent then
			payload.view.event.week = week
		else
			payload.view.event = nil
		end
		Rig.push(world, peer, payload)
		return world, peer
	end

	for _, size in SIZES do
		it(`the event strip carries it, and still fits ({size.name})`, function()
			local function text(peer: FakeRoblox.Peer, name: string): string
				return Rig.textOf(peer, "Campaign", name)
			end
			local function closingShown(peer: FakeRoblox.Peer): boolean
				return Rig.shown(Rig.need(peer, "Campaign", "EventClosing"), "Campaign")
			end
			-- Weeks before: no line.
			local world, peer = atWeek(size.screen, C.CLOSING_FROM_WEEK - 2, true)
			check(not closingShown(peer), "a closing line before its time")
			local plain = Rig.need(peer, "Campaign", "EventCard").AbsoluteSize.Y
			-- The week before, under the event's line.
			world, peer = atWeek(size.screen, C.CLOSING_FROM_WEEK - 1, true)
			check(closingShown(peer), "no heads-up the week before")
			expect(text(peer, "EventClosing")):toBe(`From next week: rallies, ads {PLUS}`)
			expect(strictAudit(world, peer, "Campaign")):toBe(0)
			-- A closing week with its event: a third line, the strip a line taller,
			-- still above the map.
			world, peer = atWeek(size.screen, C.CLOSING_FROM_WEEK, true)
			expect(text(peer, "EventClosing")):toBe(`Closing weeks: rallies and ads {PLUS}`)
			local strip = Rig.need(peer, "Campaign", "EventCard")
			check(strip.AbsoluteSize.Y > plain, "the strip did not grow")
			local body = Rig.need(peer, "Campaign", "Body")
			check(strip.AbsolutePosition.Y + strip.AbsoluteSize.Y <= body.AbsolutePosition.Y, "over the map")
			expect(strictAudit(world, peer, "Campaign")):toBe(0)
			Rig.tap(world, peer, "Campaign", "EventCard", 0.5)
			has(text(peer, "ClosingDetail"), "until election night")
			-- The last week has no event: the strip says the bonus alone.
			world, peer = atWeek(size.screen, C.WEEKS, false)
			check(Rig.shown(Rig.need(peer, "Campaign", "EventCard"), "Campaign"), "no strip in the last week")
			expect(text(peer, "EventTitle")):toBe("Closing weeks")
			expect(text(peer, "EventLine")):toBe(`Rallies and ads {PLUS}`)
			check(not closingShown(peer), "the bonus twice")
			expect(strictAudit(world, peer, "Campaign")):toBe(0)
			Rig.noErrors(world)
		end)
	end
end)
