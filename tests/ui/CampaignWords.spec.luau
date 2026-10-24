--!strict
-- The Campaign and Decision screens' short copy (src/shared/UI/Words/Campaign.luau,
-- docs/UI-STYLE.md §4.4-4.6), pure: the now line in at most eight words, the
-- action buttons' effects match Explain's numbers, no multipliers, plain units.

local Config = require("@sim/Config")
local Explain = require("@ui/Explain")
local Fixtures = require("@ui/Fixtures")
local Numbers = require("@ui/Numbers")
local PlanDraft = require("@ui/PlanDraft")
local Swing = require("@ui/Swing")
local Test = require("@testlib/Test")
local Words = require("@ui/Words/Campaign")

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

describe("Words.Campaign", function()
	it("says what to do now in at most eight words", function()
		local base: Words.NowInput = {
			locked = false,
			opponent = "Rex",
			problem = false,
			actionsLeft = 3,
			planned = 0,
			selected = nil,
		}
		local function now(changes: { [string]: any }): string
			local input = table.clone(base) :: any
			for key, value in changes do
				input[key] = value
			end
			local text = Words.planNow(input)
			check(words(text) <= 8, `"{text}" has {words(text)} words`)
			return text
		end
		expect(now({})):toBe("Tap a state on the map")
		expect(now({ selected = "Ohio" })):toBe("Pick an action in Ohio")
		expect(now({ planned = 1, actionsLeft = 2 })):toBe("Tap another state, or Lock in")
		expect(now({ actionsLeft = 0, planned = 3, selected = "Ohio" })):toBe("All set? Press Lock in")
		expect(now({ problem = true, selected = "Ohio" })):toBe("Change the plan, then Lock in")
		expect(now({ locked = true })):toBe("Waiting for Rex…")
	end)

	it("counts actions and money in words, money never rounded up", function()
		expect(Words.budget(3, 4.96)):toBe("3 actions left · $4.9")
		expect(Words.budget(1, 0)):toBe("1 action left · $0.0")
		expect(Words.budget(-1, 2)):toBe("0 actions left · $2.0")
	end)

	it("gives each action's effect from Explain's numbers, without multipliers", function()
		local view = Fixtures.payload(C, "Plan").view
		local draft = PlanDraft.new()
		local issue = PlanDraft.bestIssue(C, view, "OH")
		local rally = Explain.action(C, view, draft, "OH", "Rally", issue)
		expect(Words.effect(C, view, draft, "OH", "Rally", issue, "Rex")):toBe(
			`{Numbers.signed(rally.you or 0)} support`
		)
		local ad = Explain.action(C, view, draft, "OH", "Media", issue)
		expect(Words.effect(C, view, draft, "OH", "Ad", issue, "Rex")):toBe(
			`{Numbers.signed(ad.you or 0)} support`
		)
		local fund = Explain.action(C, view, draft, "OH", "Fundraise")
		expect(Words.effect(C, view, draft, "OH", "Fundraise", nil, "Rex")):toBe(
			`+{Numbers.money(fund.money or 0)}`
		)
		local attack = Explain.action(C, view, draft, "OH", "Attack")
		expect(Words.effect(C, view, draft, "OH", "Attack", nil, "Rex")):toBe(
			`Rex {Numbers.signed(attack.them or 0)}`
		)
		expect(Words.effect(C, view, draft, "OH", "Gotv", nil, "Rex")):toBe(
			`+{Numbers.points(C.GOTV_PER_UNIT)} on election day`
		)
		for _, entry in Words.ACTIONS do
			local text = Words.effect(C, view, draft, "OH", entry.name, issue, "Rex")
			check(string.find(text, "×", 1, true) == nil, `{entry.name}: "{text}" shows a multiplier`)
			check(words(text) <= 4, `{entry.name}: "{text}" is long`)
		end
	end)

	it("prices an action in plain words", function()
		expect(Words.cost(3, false)):toBe("$3.0")
		expect(Words.cost(2, true)):toBe("Flight $2.0")
		expect(Words.cost(0, false, true)):toBe("free")
		expect(Words.cost(0, false)):toBe(nil)
		expect(Words.reason("NotEnoughMoney")):toBe("Not enough money")
		expect(Words.reason("Something new")):toBe("Not now")
	end)

	it("writes the plan on one line", function()
		local plan: { any } = {
			{ kind = "Rally", state = "OH", issue = "Jobs" },
			{ kind = "Media", state = "PA", issue = "Jobs" },
			{ kind = "Gotv", state = "OH", units = 2 },
			{ kind = "RegionPoll", region = "Pacific" },
		}
		local line = Words.planLine(plan)
		check(string.find(line, "Rally OH · Ad PA · Ground game OH ×2 · Poll ", 1, true) == 1, line)
		expect(Words.planLine({})):toBe("")
	end)

	it("sums up a stance in a few words", function()
		local stance = Fixtures.payload(C, "Stance").view
		local preview = Swing.stance(C, stance, "A")
		local text = Words.stanceEffect(preview)
		if #preview.gains > 0 then
			check(string.find(text, `+{#preview.gains} state`, 1, true) ~= nil, text)
		end
		expect(Words.stanceEffect({ gains = {}, losses = {} })):toBe("No change")
		expect(Words.stanceEffect({ gains = { "OH" }, losses = { "PA", "MI" } })):toBe(
			"+1 state · −2 states"
		)
	end)

	it("explains every lens in a few short sentences", function()
		for _, id in { "EV", "Issues", "Polls", "Money" } do
			local lines = Words.key(id)
			check(#lines >= 3 and #lines <= 8, `{id}: {#lines} lines`)
			for _, line in lines do
				check(words(line) <= 14, `{id}: "{line}" is long`)
			end
		end
	end)

	it("reads the number an action's effect leads with, for the map's ghost tag", function()
		expect(Words.gain("+4.1 support\nFlight $2.0")):toBe("+4.1")
		expect(Words.gain("+$5.2")):toBe("+$5.2")
		expect(Words.gain("Rex -2.4")):toBe("-2.4")
		expect(Words.gain("+1.5 on election day")):toBe("+1.5")
		expect(Words.gain("See true support\n$1.0")):toBe(nil)
		expect(Words.gain("Not enough money")):toBe(nil)
	end)

	it("names the map's four color steps in order", function()
		local bands = Words.bands()
		expect(#bands):toBe(4)
		expect(bands[1].text):toBe("Toss-up: closer than 3 points")
		expect(bands[2].text):toBe("Leans: ahead by 3 to 8 points")
		expect(bands[4].text):toBe("Safe: ahead by 15 points or more")
		for _, band in bands do
			check(words(band.text) <= 8, band.text)
		end
	end)

	it("says an event's multiplier as a percent", function()
		expect(Words.percent("Fundraisers raise ×1.2 this week")):toBe(
			"Fundraisers raise 20% more this week"
		)
		expect(Words.percent("Rallies are worth ×1.5 this week")):toBe(
			"Rallies are worth 50% more this week"
		)
		expect(Words.percent("worth ×0.75")):toBe("worth 25% less")
		expect(Words.percent("no multiplier")):toBe("no multiplier")
	end)
end)

describe("Campaign words: the event strip (D-065)", function()
	local function event(kind: string, extra: { [string]: any }?): any
		local e: { [string]: any } = { week = 3, id = "x", kind = kind, name = "Test week", text = "Story." }
		for k, v in extra or {} do
			e[k] = v
		end
		return e
	end

	it("titles this week's event by kind and name, next week's by name", function()
		expect(Words.eventTitle(event("Windfall"))):toBe("Windfall · Test week")
		expect(Words.eventTitle(event("Windfall"), true)):toBe("Next week: Test week")
	end)

	it("says what each kind does in one short line, as a signed percent", function()
		expect(Words.eventLine(C, event("Windfall"))):toBe("Fundraisers where you trail +20%")
		expect(Words.eventLine(C, event("Spotlight", { issue = "Transit" }))):toBe(
			"Roads & Transit rallies and ads +30%"
		)
		expect(Words.eventLine(C, event("Regional", { region = "SouthAtlantic" }))):toBe(
			"Rallies in the South Atlantic +50%"
		)
		local stances =
			{ { id = "A", name = "Side with the staff" }, { id = "B", name = "Side with the board" } }
		expect(Words.eventLine(C, event("Choice", { issue = "Health", stances = stances }), "A")):toBe(
			"Stance A: Side with the staff"
		)
		expect(Words.eventLine(C, event("Choice", { issue = "Health", stances = stances }))):toBe(
			"Take a stance on Health"
		)
	end)
end)
