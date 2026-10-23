--!strict
-- The Select screen on the fake Roblox engine: the v0.3.1 bug-hunt cases
-- (auto-submit before the timer ends, the pre-pick, retrying a rejected lock-in,
-- the pinned footer) and the UI overhaul (WP2, docs/UI-OVERHAUL.md §3.2): picks
-- above the pinned action bar, the bar's wording, the swap hint, and B4 (a
-- rejected lock-in says why).

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Snapshot = require("@testlib/Snapshot")
local Test = require("@testlib/Test")
local Words = require("@ui/Words/Setup")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

describe("Select auto-submit before the timer ends", function()
	it("Select locks a complete, unlocked pick", function()
		local world, peer = Rig.practice(3)
		Rig.tap(world, peer, "Lobby", "Practice", 1)
		local picked = Rig.pickAll(world, peer)
		local calls = Rig.spySubmits(world, peer)
		Rig.waitFor(world, function()
			return Rig.payloadOf(world, peer).view.phase ~= "Select"
		end, 60, "the end of Select")
		local me = Rig.payloadOf(world, peer).view.players[1]
		expect(me.candidate):toBe(picked)
		check(me.color ~= nil and me.color ~= "", "no drawn color")
		expect(#calls):toBe(1)
		Rig.noErrors(world)
	end)

	it("Select leaves an incomplete pick to the server", function()
		local world, peer = Rig.practice(3)
		Rig.tap(world, peer, "Lobby", "Practice", 1)
		Rig.tap(world, peer, "Select", `Candidate_{Rig.freeCandidate(world, peer)}`)
		local calls = Rig.spySubmits(world, peer)
		Rig.waitFor(world, function()
			return Rig.payloadOf(world, peer).view.phase ~= "Select"
		end, 60, "the end of Select")
		expect(#calls):toBe(0)
		Rig.noErrors(world)
	end)

	it("Select sends the pre-pick as soon as the pick is complete", function()
		local world, peer = Rig.fixture("Select", nil)
		Rig.claim(world, peer)
		Rig.tap(world, peer, "Select", "Issue_Jobs")
		Rig.tap(world, peer, "Select", "Issue_Health")
		expect(Rig.count(peer, "DEBUG_UI send PrePick")):toBe(0)
		Rig.tap(world, peer, "Select", "Issue_Schools")
		expect(Rig.count(peer, "DEBUG_UI send PrePick")):toBe(1)
		-- Locking the same pick does not send it again.
		Rig.tap(world, peer, "Select", "LockIn")
		expect(Rig.count(peer, "DEBUG_UI send PrePick")):toBe(1)
		expect(Rig.count(peer, "DEBUG_UI submit")):toBe(1)
		Rig.noErrors(world)
	end)
end)

describe("Select rejections", function()
	it("lets Select retry a rejected lock-in", function()
		local world, peer = Rig.practice(3)
		Rig.tap(world, peer, "Lobby", "Practice", 1)
		Rig.pickAll(world, peer)
		Rig.sabotageSubmits(world, peer, { candidate = "hale", platform = { "Jobs" } })
		Rig.tap(world, peer, "Select", "LockIn", 1)
		expect(Rig.textOf(peer, "Select", "LockIn")):toBe("Lock in")
		check(Rig.enabled(peer, "Select", "LockIn"), "Lock in stays disabled after a rejection")
		Rig.noErrors(world)
	end)

	it("Select keeps a lock-in the server accepted", function()
		local world, peer = Rig.practice(3)
		Rig.tap(world, peer, "Lobby", "Practice", 1)
		Rig.pickAll(world, peer)
		local store = Rig.storeOf(world, peer)
		Rig.tap(world, peer, "Select", "LockIn", 0.01)
		-- An unrelated message arriving must not reopen a locked pick.
		store.say("Your opponent is back.")
		FakeRoblox.run(world, 0.05)
		if Rig.findIn(peer, "Select", "LockIn") then
			expect(Rig.textOf(peer, "Select", "LockIn")):toBe("Locked in")
		end
		Rig.noErrors(world)
	end)
end)

describe("Select keeps no space for a Debug button", function()
	it("pins the Select footer to the bottom edge on a phone", function()
		local _, peer = Rig.fixture("Select", Rig.PHONE)
		local bar = Rig.need(peer, "Select", "FooterBar")
		expect(bar.Position.Y.Offset):toBe(0)
	end)

	it("leaves the footer full width on a wide screen", function()
		local _, peer = Rig.fixture("Select", nil)
		local bar = Rig.need(peer, "Select", "FooterBar")
		local pad = bar:FindFirstChildOfClass("UIPadding")
		check(pad == nil or pad.PaddingRight.Offset == 0, "the footer is padded away from the right edge")
	end)
end)

-- ------------------------------------------------------------------ UI overhaul (WP2)

-- The global toast's text while it shows, or nil.
local function toastText(peer: FakeRoblox.Peer): string?
	local layer = FakeRoblox.find(peer, "ToastLayer")
	local frame = if layer then layer:FindFirstChild("Toast") else nil
	if frame == nil or frame.Visible == false then
		return nil
	end
	return tostring(frame:FindFirstChild("ToastText").Text)
end

local function same(a: any, b: any): boolean
	return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
end

local function status(peer: FakeRoblox.Peer): string
	return Rig.textOf(peer, "Select", "BarStatus")
end

local function now(peer: FakeRoblox.Peer): string
	return Rig.textOf(peer, "Select", "NowText")
end

-- The most a scroll area hides below its bottom edge, laid out the way Roblox
-- would (tests/lib/Snapshot runs the list and grid layouts the fake engine skips).
local function hiddenBelow(peer: FakeRoblox.Peer): number
	local most = 0
	for n in string.gmatch(Snapshot.svg(peer), "%+(%d+) px below") do
		most = math.max(most, tonumber(n) or 0)
	end
	return most
end

local function bottom(inst: any): number
	return inst.AbsolutePosition.Y + inst.AbsoluteSize.Y
end

local function inScroll(inst: any): boolean
	local node = inst.Parent
	while node ~= nil do
		if node.ClassName == "ScrollingFrame" then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Runs the UI audit on the mounted Select screen with no pending allowances.
local function strictAudit(world: FakeRoblox.World, peer: FakeRoblox.Peer): number
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	return Audit.run(Rig.need(peer, "Screens", "Select"), "Select", { strict = true })
end

describe("Select rejections say why (B4)", function()
	it("shows the reason in a toast and the bar, and reopens the pick", function()
		local world, peer = Rig.practice(3)
		Rig.tap(world, peer, "Lobby", "Practice", 1)
		Rig.pickAll(world, peer)
		Rig.sabotageSubmits(world, peer, { candidate = "hale", platform = { "Jobs" } })
		Rig.tap(world, peer, "Select", "LockIn", 1)
		local want = Rig.netOf(world, peer).reasonText("BadPlatform")
		expect(toastText(peer)):toBe(want)
		check(Rig.contains(status(peer), want), `status line: {status(peer)}`)
		for _, name in { "Issue_Jobs", "Issue_Schools", "LockIn" } do
			check(Rig.enabled(peer, "Select", name), `{name} stays disabled after a rejection`)
		end
		-- The next change clears the reason from the bar.
		Rig.tap(world, peer, "Select", "Issue_Jobs")
		check(not Rig.contains(status(peer), want), "the rejection outlives the next change")
		Rig.noErrors(world)
	end)

	it("disables the picks while locked", function()
		local world, peer = Rig.fixture("Select", nil)
		Rig.pickAll(world, peer)
		Rig.tap(world, peer, "Select", "LockIn")
		for _, name in { "Candidate_hale", "Issue_Jobs", "Issue_Schools", "LockIn" } do
			check(not Rig.enabled(peer, "Select", name), `{name} is enabled while locked`)
		end
		expect(status(peer)):toBe("Locked in")
		-- The fixture's opponent holds Rex Calloway.
		expect(now(peer)):toBe("Waiting for Rex…")
		Rig.noErrors(world)
	end)
end)

describe("Select fits above the pinned bar", function()
	it("needs no scrolling at 1280x720 and 1024x768, in either step", function()
		for _, screen in { { x = 1280, y = 720 }, { x = 1024, y = 768 } } do
			local world, peer = Rig.fixture("Select", screen)
			check(Rig.findIn(peer, "Select", "CoachTip") ~= nil, "no coach tip on the first visit")
			expect(hiddenBelow(peer)):toBe(0)
			expect(strictAudit(world, peer)):toBe(0)
			Rig.claim(world, peer)
			expect(hiddenBelow(peer)):toBe(0)
			expect(strictAudit(world, peer)):toBe(0)
			Rig.noErrors(world)
		end
	end)

	it("pins Lock in on a phone; both steps fit without scrolling", function()
		local world, peer = Rig.fixture("Select", Rig.PHONE)
		expect(strictAudit(world, peer)):toBe(0)
		-- Step 1 fits even with its coach tip showing.
		check(Rig.findIn(peer, "Select", "CoachTip") ~= nil, "no coach tip on the first visit")
		expect(hiddenBelow(peer)):toBe(0)
		Rig.claim(world, peer)
		local lockIn = Rig.need(peer, "Select", "LockIn")
		check(not inScroll(lockIn), "Lock in scrolls")
		check(bottom(lockIn) <= Rig.PHONE.y, `Lock in ends at {bottom(lockIn)}`)
		check(lockIn:GetAttribute("PrimaryAction") == true, "Lock in is not the primary action")
		expect(hiddenBelow(peer)):toBe(0)
		expect(now(peer)):toBe("Pick 3 issues")
		expect(strictAudit(world, peer)):toBe(0)
		Rig.noErrors(world)
	end)

	it("shows the drawn color as a line in both steps (D-047)", function()
		for _, screen in { Rig.PHONE, { x = 1280, y = 720 } } do
			local world, peer = Rig.fixture("Select", screen)
			local me = Rig.payloadOf(world, peer).view
			local color = me.players[me.you].color
			check(
				Rig.contains(Rig.textOf(peer, "Select", "ColorLine"), color),
				"the color line misses the color"
			)
			check(Rig.findIn(peer, "Select", "Color_Teal") == nil, "a color picker is still there")
			Rig.claim(world, peer)
			check(Rig.shown(Rig.need(peer, "Select", "ColorLine"), "Select"), "no color line in step 2")
			Rig.noErrors(world)
		end
	end)
end)

describe("Select in two steps (D-048)", function()
	it("shows candidates first, then the issues with this match's votes and boost", function()
		local world, peer = Rig.fixture("Select", nil)
		check(Rig.shown(Rig.need(peer, "Select", "Candidates"), "Select"), "no candidates in step 1")
		check(not Rig.shown(Rig.need(peer, "Select", "Issues"), "Select"), "issues shown in step 1")
		Rig.claim(world, peer)
		check(not Rig.shown(Rig.need(peer, "Select", "Candidates"), "Select"), "candidates left in step 2")
		check(Rig.shown(Rig.need(peer, "Select", "Issues"), "Select"), "no issues in step 2")
		local view = Rig.payloadOf(world, peer).view
		local IssueMap = require("@sim/IssueMap")
		local ev = IssueMap.evByIssue(view.issueMap).Farms
		local text = tostring(Rig.need(peer, "Select", "Issue_Farms"):FindFirstChild("IssueLine").Text)
		check(Rig.contains(text, `{ev} votes`), `no votes on the chip: {text}`)
		check(
			Rig.contains(text, `{Words.boost(view.platformMults.Farms)} boost`),
			`no boost on the chip: {text}`
		)
		check(not Rig.contains(text, "×") and not Rig.contains(text, "EV"), `jargon on the chip: {text}`)
		Rig.noErrors(world)
	end)

	it("greys out the opponent's candidate as taken and never claims it", function()
		local world, peer = Rig.fixture("Select", nil)
		local view = Rig.payloadOf(world, peer).view
		local taken: string? = nil
		for id, owner in view.claims do
			if owner ~= view.you then
				taken = id
			end
		end
		check(taken ~= nil, "the fixture's bot holds no candidate")
		local name = `Candidate_{taken}`
		check(Rig.shown(Rig.need(peer, "Select", name):FindFirstChild("Taken"), "Select"), "no Taken tag")
		check(not Rig.enabled(peer, "Select", name), "a taken candidate is tappable")
		Rig.tap(world, peer, "Select", name)
		expect(Rig.need(peer, "Select", name):GetAttribute("Selected")):toBe(false)
		expect(Rig.textOf(peer, "Select", "LockIn")):toBe("Pick a candidate")
		Rig.noErrors(world)
	end)

	it("a live practice match: the bot's candidate is taken, a claim moves to step 2", function()
		local world, peer = Rig.practice(5)
		Rig.tap(world, peer, "Lobby", "Practice", 1)
		local view = Rig.payloadOf(world, peer).view
		local bots = 0
		for _, owner in view.claims do
			if owner ~= view.you then
				bots += 1
			end
		end
		expect(bots):toBe(1)
		local id = Rig.claim(world, peer)
		check(Rig.shown(Rig.need(peer, "Select", "Issues"), "Select"), "no step 2 after the claim")
		expect(now(peer)):toBe("Pick 3 issues")
		expect(Rig.payloadOf(world, peer).view.claims[id]):toBe(view.you)
		Rig.noErrors(world)
	end)
end)

describe("Select action bar", function()
	it("names what is missing on the disabled Lock in", function()
		local world, peer = Rig.fixture("Select", nil)
		local function lockText(): string
			return Rig.textOf(peer, "Select", "LockIn")
		end
		expect(lockText()):toBe("Pick a candidate")
		check(not Rig.enabled(peer, "Select", "LockIn"), "Lock in is enabled with nothing picked")
		expect(status(peer)):toBe("Step 1 of 2")
		expect(now(peer)):toBe("Pick your candidate")
		Rig.tap(world, peer, "Select", "Candidate_hale")
		expect(lockText()):toBe("Next: issues")
		expect(Rig.textOf(peer, "Select", "Details")):toBe("About Marcus")
		Rig.tap(world, peer, "Select", "LockIn")
		expect(lockText()):toBe("Pick 3 more issues")
		expect(status(peer)):toBe("Step 2 of 2")
		expect(now(peer)):toBe("Pick 3 issues")
		Rig.tap(world, peer, "Select", "Issue_Jobs")
		Rig.tap(world, peer, "Select", "Issue_Health")
		expect(lockText()):toBe("Pick 1 more issue")
		expect(now(peer)):toBe("Pick 1 more issue")
		Rig.tap(world, peer, "Select", "Issue_Farms")
		expect(lockText()):toBe("Lock in")
		expect(now(peer)):toBe("All set? Lock in")
		check(Rig.enabled(peer, "Select", "LockIn"), "Lock in is disabled with a full pick")
		-- The fixture's opponent (Rex Calloway) has locked already.
		expect(Rig.textOf(peer, "Select", "BarOpponent")):toBe("Rex: locked in")
		Rig.noErrors(world)
	end)

	it("says how to swap when a fourth issue is tapped", function()
		local world, peer = Rig.fixture("Select", nil)
		Rig.pickAll(world, peer)
		Rig.tap(world, peer, "Select", "Issue_Safety")
		expect(status(peer)):toBe("You already have 3; tap one to swap it")
		FakeRoblox.run(world, 3.5)
		expect(status(peer)):toBe("Step 2 of 2")
		Rig.noErrors(world)
	end)

	it("marks picks with an outline and a check, never an accent fill", function()
		local world, peer = Rig.fixture("Select", nil)
		local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
		Rig.pickAll(world, peer)
		local chip = Rig.need(peer, "Select", "Issue_Jobs")
		local name = tostring(chip:FindFirstChild("IssueName").Text)
		local line = tostring(chip:FindFirstChild("IssueLine").Text)
		check(string.sub(name, 1, 3) == "•", `picked chip reads {name}`)
		check(Rig.contains(line, "votes") and Rig.contains(line, "boost"), `chip reads {line}`)
		local other = tostring(Rig.need(peer, "Select", "Issue_Safety"):FindFirstChild("IssueName").Text)
		expect(other):toBe("Safety")
		check(not same(chip.BackgroundColor3, Kit.colors.accent), "a picked chip is filled with the accent")
		expect(chip:GetAttribute("Selected")):toBe(true)
		expect(Rig.need(peer, "Select", "Candidate_hale"):GetAttribute("Selected")):toBe(true)
		Rig.noErrors(world)
	end)

	it("says the last pick is loaded instead of filling it silently", function()
		local world, peer = Rig.fixture("Select", nil)
		world.current = peer
		Rig.storeOf(world, peer).setPrePick({ candidate = "hale", platform = { "Jobs", "Health", "Farms" } })
		world.current = nil
		FakeRoblox.run(world, 0.3)
		-- Step 1 shows the remembered candidate; claiming it brings the issues back.
		expect(Rig.need(peer, "Select", "Candidate_hale"):GetAttribute("Selected")):toBe(true)
		expect(Rig.textOf(peer, "Select", "LockIn")):toBe("Next: issues")
		Rig.tap(world, peer, "Select", "LockIn")
		expect(status(peer)):toBe("Your last pick is loaded")
		expect(Rig.textOf(peer, "Select", "LockIn")):toBe("Lock in")
		Rig.tap(world, peer, "Select", "Issue_Jobs")
		expect(status(peer)):toBe("Step 2 of 2")
		expect(now(peer)):toBe("Pick 1 more issue")
		Rig.noErrors(world)
	end)

	it("shows the header timer in warn under ten seconds and danger under five", function()
		local world, peer = Rig.fixture("Select", nil)
		local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		payload.deadline = world.clock + 8
		Rig.push(world, peer, payload)
		local timer = Rig.need(peer, "Select", "Timer")
		check(same(timer.TextColor3, Kit.colors.warn), "the timer is not warn under 10 s")
		payload = Rig.deepCopy(payload)
		payload.deadline = world.clock + 4
		Rig.push(world, peer, payload)
		check(same(timer.TextColor3, Kit.colors.danger), "the timer is not danger under 5 s")
		Rig.noErrors(world)
	end)
end)

-- ------------------------------------------------------------------ style v2 (WP-A, docs/UI-STYLE.md §4.2)

describe("Select style v2: details one tap away", function()
	it("opens the picked candidate's numbers from About <name>", function()
		local world, peer = Rig.fixture("Select", Rig.PHONE)
		check(not Rig.shown(Rig.need(peer, "Select", "Details"), "Select"), "About shows with no candidate")
		Rig.tap(world, peer, "Select", "Candidate_calloway")
		-- Rex is taken by the fixture's bot: nothing to read about yet.
		check(not Rig.shown(Rig.need(peer, "Select", "Details"), "Select"), "About shows for a taken card")
		Rig.tap(world, peer, "Select", "Candidate_venkat")
		Rig.tap(world, peer, "Select", "Details")
		local sheet = Rig.need(peer, "Select", "CandidateSheet")
		check(sheet.Visible == true, "the candidate sheet did not open")
		local lines = Words.candidateDetails(Config.defaults, "venkat")
		for k, line in lines do
			expect(tostring(sheet:FindFirstChild(`DetailLine{k}`, true).Text)):toBe(line)
		end
		expect(lines[4]):toBe("Actions each week: 3")
		local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
		expect(Audit.run(Rig.need(peer, "Screens", "Select"), "Select", { strict = true })):toBe(0)
		Rig.noErrors(world)
	end)

	it("explains votes and boost in a sheet, not on the screen", function()
		local world, peer = Rig.fixture("Select", nil)
		Rig.claim(world, peer)
		expect(Rig.textOf(peer, "Select", "Details")):toBe("How issues work")
		Rig.tap(world, peer, "Select", "Details")
		local sheet = Rig.need(peer, "Select", "IssuesSheet")
		check(sheet.Visible == true, "the issues sheet did not open")
		expect(tostring(sheet:FindFirstChild("HelpLine2", true).Text)):toBe(Words.ISSUES_HELP[2])
		Rig.noErrors(world)
	end)

	it("dims the taken card behind a Taken pill and hides its lines", function()
		local _world, peer = Rig.fixture("Select", nil)
		local card = Rig.need(peer, "Select", "Candidate_calloway")
		local pill = card:FindFirstChild("Taken")
		check(Rig.shown(pill, "Select"), "no Taken pill")
		expect(tostring(pill.Text)):toBe("Taken")
		expect(card:FindFirstChild("Perk").Visible):toBe(false)
		check(card.BackgroundTransparency > 0, "the taken card is not dimmed")
	end)

	it("shows the drawn color as a dot, not a filled square button", function()
		local _world, peer = Rig.fixture("Select", nil)
		local dot = Rig.need(peer, "Select", "ColorDot")
		expect(dot.AbsoluteSize.X):toBe(16)
		expect(dot:GetAttribute("DataColor")):toBe(true)
		expect(Rig.findIn(peer, "Select", "ColorSwatch")):toBe(nil)
	end)
end)
