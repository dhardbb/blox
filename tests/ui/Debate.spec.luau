--!strict
-- The Debate screen (D-062, src/client/Screens/Debate.luau) on the fake engine:
-- the intro, a live round, a clash and the verdict each route to it and pass
-- the strict UI audit on a phone, an iPad and 16:9; a round shows three moves
-- with the board's numbers above the pinned bar; one tap picks, Lock in sends
-- exactly { move, zinger }; the clash shows both moves, a stamp and what moved.

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Swing = require("@ui/Swing")
local Test = require("@testlib/Test")
local Words = require("@ui/Words/Debate")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local SIZES = {
	{ name = "16:9", screen = { x = 1280, y = 720 } },
	{ name = "iPad", screen = { x = 1024, y = 768 } },
	{ name = "phone", screen = Rig.PHONE },
}
local MOMENTS = { "DebateIntro", "DebateRound", "Clash", "Debate" }

local check = Rig.check
local function need(peer: FakeRoblox.Peer, name: string): any
	return Rig.need(peer, "Debate", name)
end
local function shown(inst: any): boolean
	return Rig.shown(inst, "Debate")
end
local function tap(world: FakeRoblox.World, peer: FakeRoblox.Peer, name: string)
	Rig.tap(world, peer, "Debate", name, 0.1)
end
local function textOf(peer: FakeRoblox.Peer, name: string): string
	return Rig.textOf(peer, "Debate", name)
end

local function strict(world: FakeRoblox.World, peer: FakeRoblox.Peer): { string }
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	local out = {}
	for _, finding in Audit.check(FakeRoblox.find(peer, "Debate")) do
		if not finding.onMap then
			table.insert(out, `{finding.rule}: {finding.message}`)
		end
	end
	return out
end

describe("Debate screen: every moment", function()
	for _, moment in MOMENTS do
		for _, size in SIZES do
			it(`routes {moment} to the Debate screen and passes the audit ({size.name})`, function()
				local world, peer = Rig.fixture(moment, size.screen)
				check(Rig.count(peer, "screen Debate") > 0, `{moment} did not route to the Debate screen`)
				check(Rig.count(peer, "UI audit Debate: 0 problem(s)") > 0, "no clean UI audit")
				local problems = strict(world, peer)
				check(#problems == 0, table.concat(problems, "; "))
				local stage = need(peer, "DebateStage")
				check(shown(stage), "no stage")
				-- The stage's own faces (the header has YouFace and ThemFace slots too).
				check(shown(stage:FindFirstChild("YouFace", true)), "no face for you")
				check(shown(stage:FindFirstChild("ThemFace", true)), "no face for them")
				check(shown(need(peer, "CrowdBar")), "no crowd meter")
				local lock = need(peer, "LockIn")
				check(shown(lock), "the action bar's primary is hidden")
				check(
					lock.AbsolutePosition.Y + 56 <= size.screen.y + 0.5,
					`the primary ends at {lock.AbsolutePosition.Y + 56} on a {size.screen.y} px screen`
				)
				expect(textOf(peer, "StageLabel")):toBe("Debate")
				Rig.noErrors(world)
			end)
		end
	end
end)

describe("Debate screen: a round", function()
	it("shows each move's strength and its three result cells, above the bar on a phone", function()
		local world, peer = Rig.fixture("DebateRound", Rig.PHONE)
		local view = Rig.payloadOf(world, peer).view
		local board = Swing.debateBoard(C, view)
		check(board ~= nil, "no board in the round fixture")
		local barTop = need(peer, "ActionBar").AbsolutePosition.Y
		for k, row in (board :: Swing.DebateBoard).rows do
			local button = need(peer, `Move{row.move}`)
			check(shown(button), `{row.move} is hidden`)
			expect(textOf(peer, `MoveTitle{row.move}`)):toBe(Words.moveTitle(row))
			expect(textOf(peer, `MoveCells{row.move}`)):toBe(Words.cells(row))
			check(
				button.AbsolutePosition.Y + button.AbsoluteSize.Y <= barTop + 0.5,
				`{row.move} ends under the bar`
			)
			check(k >= 1, "")
		end
		expect(textOf(peer, "Question")):toBe(`"{Words.question(board.topic)}"`)
		expect(textOf(peer, "NowText")):toBe("Pick Defend, Attack or Pivot")
		Rig.noErrors(world)
	end)

	it("needs one tap on a move; Lock in then sends exactly the move and the Zinger", function()
		local world, peer = Rig.fixture("DebateRound", nil)
		local lock = need(peer, "LockIn")
		expect(lock.Text):toBe("Pick a move")
		tap(world, peer, "LockIn")
		expect(Rig.count(peer, "[270] DEBUG_UI submit")):toBe(0)
		tap(world, peer, "MovePivot")
		check(need(peer, "MovePivot"):GetAttribute("Selected") == true, "Pivot is not selected")
		local view = Rig.payloadOf(world, peer).view
		local staked = view.debate.zingers[view.you] > 0
		if staked then
			tap(world, peer, "Zinger")
		end
		tap(world, peer, "LockIn")
		expect(Rig.count(peer, "[270] DEBUG_UI submit")):toBe(1)
		expect(Rig.count(peer, `[270] DEBUG_UI submit move=Pivot zinger={tostring(staked)}`)):toBe(1)
		expect(textOf(peer, "BarStatus")):toBe("Locked in · waiting for opponent")
		Rig.noErrors(world)
	end)

	it("tags a move that cannot lose as Safe in the first debate, and the Why sheet has the parts", function()
		local world, peer = Rig.fixture("DebateRound", nil)
		local board = Swing.debateBoard(C, Rig.payloadOf(world, peer).view) :: Swing.DebateBoard
		for _, row in board.rows do
			expect(need(peer, `MoveSafe{row.move}`).Visible):toBe(row.safe)
			expect(textOf(peer, `Why{row.move}`)):toBe(Words.parts(row))
		end
		Rig.noErrors(world)
	end)
end)

describe("Debate screen: the clash and the verdict", function()
	it("shows both moves, a stamp, and the round's line", function()
		local world, peer = Rig.fixture("Clash", nil)
		local view = Rig.payloadOf(world, peer).view
		local rounds = if view.debate then view.debate.rounds else view.debates[#view.debates].rounds
		local round = rounds[#rounds]
		check(shown(need(peer, "DebateClash")), "no clash panel")
		check(shown(need(peer, "ClashStamp")), "no stamp")
		expect(textOf(peer, "ClashLine")):toBe(Swing.debateRound(C, view, round).line)
		check(
			Rig.contains(textOf(peer, "ClashYouMove"), tostring(round.scores[view.you])),
			"no score for you"
		)
		check(not shown(need(peer, "DebateMoves")), "the moves show during the clash")
		Rig.noErrors(world)
	end)

	it("plays debateWin on a clash you win, and only then", function()
		local world, peer = Rig.fixture("Clash", nil)
		local view = Rig.payloadOf(world, peer).view
		local rounds = if view.debate then view.debate.rounds else view.debates[#view.debates].rounds
		local won = rounds[#rounds].winner == view.you
		local n = 0
		for _, cue in Rig.sounds(peer) do
			if cue == "debateWin" then
				n += 1
			end
		end
		expect(n):toBe(if won then 1 else 0)
		Rig.noErrors(world)
	end)

	it("the verdict says who won the crowd and can be skipped", function()
		local world, peer = Rig.fixture("Debate", nil)
		check(shown(need(peer, "ClashStamp")), "no verdict stamp")
		local lock = need(peer, "LockIn")
		expect(lock.Text):toBe("Skip")
		check(lock.Active ~= false, "Skip is disabled")
		Rig.noErrors(world)
	end)
end)

describe("Words.Debate", function()
	it("writes result cells with a sign, and splits as =", function()
		expect(Words.cell(3)):toBe("+3")
		expect(Words.cell(-2)):toBe("−2")
		expect(Words.cell(0)):toBe("=")
		expect(Words.cells({ cells = { 4, 0, -5 } } :: any)):toBe("D +4 · A = · P −5")
	end)

	it("says who leads the crowd and what the Zinger does, briefly", function()
		local view = { you = 1 } :: any
		expect(Words.crowdLine(view, { 4, 0 }, "Rex")):toBe("You +4")
		expect(Words.crowdLine(view, { 1, 3 }, "Rex")):toBe("Rex +2")
		expect(Words.crowdLine(view, { 2, 2 }, "Rex")):toBe("Even")
		local board = { zingers = 1, zingerMult = 2 } :: any
		expect(Words.zinger(board, false)):toBe("Stake Zinger: a win counts ×2")
		expect(Words.zinger(board, true)):toBe("Zinger staked: a win counts ×2")
		expect(Words.zinger({ zingers = 0, zingerMult = 2 } :: any, false)):toBe("Zinger spent")
	end)

	it("has a fictional, neutral question for every issue", function()
		for _, issue in
			{ "Jobs", "Health", "Schools", "Environment", "Safety", "Transit", "Technology", "Farms" }
		do
			local question = Words.question(issue)
			check(#question > 10 and #question < 90, `{issue}: "{question}"`)
		end
	end)
end)
