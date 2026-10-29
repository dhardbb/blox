--!strict
-- The Debate screen (D-072, src/client/Screens/Debate.luau) on the fake engine:
-- the intro, a live round, a clash and the verdict each route to it and pass
-- the strict UI audit on a phone, an iPad and 16:9; a round shows three moves
-- with the board's numbers above the pinned bar; one tap picks, Lock in sends
-- exactly { move, zinger }; the clash shows both moves, a stamp and what moved.

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
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
		-- A landscape phone (D-098): the three moves are tiles in one row, their
		-- cells packed ("D+4 A+3 P="), every tile whole above the action bar.
		local world, peer = Rig.fixture("DebateRound", Rig.PHONE)
		local view = Rig.payloadOf(world, peer).view
		local board = Swing.debateBoard(C, view)
		check(board ~= nil, "no board in the round fixture")
		local barTop = need(peer, "ActionBar").AbsolutePosition.Y
		for k, row in (board :: Swing.DebateBoard).rows do
			local button = need(peer, `Move{row.move}`)
			check(shown(button), `{row.move} is hidden`)
			expect(textOf(peer, `MoveTitle{row.move}`)):toBe(Words.moveTitle(row))
			expect(textOf(peer, `MoveCells{row.move}`)):toBe(Words.cellsShort(row))
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

-- A stand-in InputObject: a press of `kind` whose Changed fires as its state moves.
local function press(kind: string): any
	local handlers: { (string) -> () } = {}
	local input: any = { UserInputType = { Name = kind }, UserInputState = { Name = "Begin" } }
	input.Changed = {
		Connect = function(_self: any, fn: (string) -> ())
			table.insert(handlers, fn)
			return {
				Disconnect = function()
					local at = table.find(handlers, fn)
					if at then
						table.remove(handlers, at)
					end
				end,
			}
		end,
	}
	function input.move(state: string)
		input.UserInputState = { Name = state }
		for _, fn in table.clone(handlers) do
			fn("UserInputState")
		end
	end
	return input
end

describe("Debate screen: the downside and the Zinger (M1, S1)", function()
	it("Why? has each move's loss line and the rival's live Zinger by name", function()
		local world, peer = Rig.fixture("DebateRound", Rig.PHONE)
		local payload = Rig.payloadOf(world, peer)
		local view = payload.view
		local board = Swing.debateBoard(C, view) :: Swing.DebateBoard
		for _, row in board.rows do
			expect(textOf(peer, `WhyLoss{row.move}`)):toBe(row.lossLine)
		end
		expect(need(peer, "WhyRivalZinger").Visible):toBe(board.theirZingers > 0)
		-- Their Zinger live: one line, by their name; spent: the line goes.
		local Model = FakeRoblox.require(world, peer, "src/client/Screens/CampaignParts/Model.luau")
		local name = Model.firstName(C, view, board.rival)
		for _, left in { 1, 0 } do
			local copy = Rig.deepCopy(payload)
			copy.view.debate.board.players[board.rival].zingers = left
			copy.view.debate.zingers[board.rival] = left
			Rig.push(world, peer, copy)
			local line = need(peer, "WhyRivalZinger")
			expect(line.Visible):toBe(left > 0)
			if left > 0 then
				local live = Swing.debateBoard(C, copy.view) :: Swing.DebateBoard
				expect(line.Text):toBe(Words.rivalZinger(live, name))
				check(Rig.contains(line.Text, `{name} still has a Zinger`), line.Text)
			end
		end
		Rig.noErrors(world)
	end)

	it("warns in the bar when a Safe move that can split is picked with the Zinger staked", function()
		local world, peer = Rig.fixture("DebateRound", nil)
		local view = Rig.payloadOf(world, peer).view
		local board = Swing.debateBoard(C, view) :: Swing.DebateBoard
		check(board.zingers > 0, "the round fixture has no Zinger to stake")
		tap(world, peer, "Zinger")
		for _, row in board.rows do
			tap(world, peer, `Move{row.move}`)
			local want = Words.safeZinger(board, row, true) or `{row.move} + Zinger · kept secret`
			expect(textOf(peer, "BarStatus")):toBe(want)
		end
		-- Unstaked: the plain line.
		tap(world, peer, "Zinger")
		expect(textOf(peer, "BarStatus")):toBe(`{board.rows[3].move} · kept secret`)
		Rig.noErrors(world)
	end)
end)

describe("Debate screen: the time bank (D-085)", function()
	it("offers +15 s in a round while the bank holds a chunk, and sends it", function()
		local world, peer = Rig.fixture("DebateRound", Rig.PHONE)
		local button = need(peer, "BankButton")
		check(shown(button), "no +15 s in a debate round")
		expect(button.Text):toBe(`+{C.TIME_BANK_CHUNK} s`)
		tap(world, peer, "BankButton")
		check(Rig.count(peer, "[270] DEBUG_UI bank") == 1, "+15 s sent nothing")
		local lock = need(peer, "LockIn")
		check(lock.AbsolutePosition.Y + 56 <= Rig.PHONE.y + 0.5, "the primary is pushed off a phone")
		-- An empty bank, a round without a deadline (tutorial, admin timers off),
		-- a locked seat: no button.
		local base = Rig.payloadOf(world, peer)
		local empty = Rig.deepCopy(base)
		empty.seats[empty.you].bank = C.TIME_BANK_CHUNK - 1
		Rig.push(world, peer, empty)
		check(not shown(need(peer, "BankButton")), "+15 s shows with an empty bank")
		local untimed = Rig.deepCopy(base)
		untimed.deadline = nil
		Rig.push(world, peer, untimed)
		check(not shown(need(peer, "BankButton")), "+15 s shows without a deadline")
		local locked = Rig.deepCopy(base)
		locked.seats[locked.you].locked = true
		locked.step += 1
		Rig.push(world, peer, locked)
		check(not shown(need(peer, "BankButton")), "+15 s shows after Lock in")
		Rig.noErrors(world)
	end)

	it("has no +15 s in the clash or the verdict", function()
		for _, moment in { "Clash", "Debate", "DebateIntro" } do
			local world, peer = Rig.fixture(moment, nil)
			check(not shown(need(peer, "BankButton")), `+15 s shows in {moment}`)
			Rig.noErrors(world)
		end
	end)
end)

describe("Debate screen: a rejoin mid-round", function()
	it("shows the move and Zinger you locked in before you left, as locked", function()
		local world, peer = Rig.fixture("DebateRound", nil)
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		local view = payload.view
		local staked = view.debate.zingers[view.you] > 0
		-- The server's State after the rejoin: your seat is locked, with your move.
		payload.seats[payload.you].locked = true
		view.debate.yourMove = { move = "Attack", zinger = staked }
		payload.step += 1
		Rig.push(world, peer, payload)
		check(need(peer, "MoveAttack"):GetAttribute("Selected") == true, "Attack is not shown as picked")
		expect(need(peer, "MoveDefend"):GetAttribute("Selected") == true):toBe(false)
		expect(need(peer, "Zinger"):GetAttribute("Selected") == true):toBe(staked)
		expect(need(peer, "LockIn").Text):toBe("Locked in")
		expect(textOf(peer, "BarStatus")):toBe("Locked in · waiting for opponent")
		-- Tapping another move changes nothing: it is locked.
		tap(world, peer, "MovePivot")
		check(need(peer, "MoveAttack"):GetAttribute("Selected") == true, "a locked pick changed")
		Rig.noErrors(world)
	end)
end)

describe("Debate screen: a payload without your seat", function()
	it("does not break after Lock in", function()
		local world, peer = Rig.fixture("DebateRound", nil)
		tap(world, peer, "MovePivot")
		tap(world, peer, "LockIn")
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		payload.seats[payload.you] = nil
		Rig.push(world, peer, payload)
		Rig.noErrors(world)
	end)
end)

describe("Debate screen: holding a move", function()
	-- The Moves part alone, with a stand-in screen model that counts renders.
	local function moves(): (FakeRoblox.World, any, any)
		local world, peer = Rig.fixture("DebateRound", Rig.PHONE)
		local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
		local Moves = FakeRoblox.require(world, peer, "src/client/Screens/DebateParts/Moves.luau")
		local pick = { move = nil, held = nil, zinger = false, showSafe = false }
		local model = { config = C, render = function() end }
		local stage = Kit.box({ Name = "Stage", Parent = Kit.new("ScreenGui", { Name = "TestGui" }) })
		world.current = peer
		local part = Moves.new(stage, model, pick, 1)
		world.current = nil
		return world, part.root:FindFirstChild("MoveAttack", true), pick
	end

	it(
		"previews while held and stops when the press ends anywhere, is cancelled, or the mouse leaves",
		function()
			local world, button, pick = moves()
			for _, finish in { "End", "Cancel", "Leave" } do
				local input = press(if finish == "Leave" then "MouseButton1" else "Touch")
				button.InputBegan.fire(input)
				FakeRoblox.run(world, 0.1)
				expect(pick.held):toBe("Attack")
				if finish == "Leave" then
					button.MouseLeave.fire()
				else
					input.move(finish) -- lifted off the button: no InputEnded on it
				end
				FakeRoblox.run(world, 0.1)
				check(pick.held == nil, `the preview stuck after {finish}`)
			end
			-- A release on the button still ends it.
			local input = press("Touch")
			button.InputBegan.fire(input)
			FakeRoblox.run(world, 0.1)
			button.InputEnded.fire(input)
			FakeRoblox.run(world, 0.1)
			expect(pick.held):toBe(nil)
			Rig.noErrors(world)
		end
	)
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

-- Fixture `moment` against an opponent with a 16-character custom name who won
-- the last clash and the crowd.
local LONG_NAME = "Bartholomew Zork" -- 16 letters, the most a custom name may have
local function longNamed(
	moment: string,
	name: string,
	screen: { x: number, y: number }
): (FakeRoblox.World, FakeRoblox.Peer)
	local world, peer = Rig.fixture("Lobby", screen)
	local payload = Fixtures.payload(C, moment :: any)
	local them = 3 - payload.you
	payload.view.players[them].customName = name
	local last = payload.view.debates[#payload.view.debates]
	local rounds = if payload.view.debate then payload.view.debate.rounds else last.rounds
	local round = rounds[#rounds]
	round.winner, round.margin = them, 3
	if last and last.crowd then
		last.crowd[them] = (last.crowd[payload.you] or 0) + 4
	end
	Rig.push(world, peer, payload)
	FakeRoblox.run(world, 1)
	return world, peer
end

describe("Debate screen: a long custom name", function()
	-- 16 letters: the stamp says THEY; 10 (the most it spells out): it narrows.
	local cases = {
		{ moment = "Clash", name = LONG_NAME, words = "THEY WIN BY 3" },
		{ moment = "Debate", name = LONG_NAME, words = "THEY WON THE CROWD" },
		{ moment = "Debate", name = "Wilhelmina", words = "WILHELMINA WON THE CROWD" },
	}
	for _, case in cases do
		for _, size in SIZES do
			it(`keeps the {case.moment} stamp inside the column, {case.name} ({size.name})`, function()
				local world, peer = longNamed(case.moment, case.name, size.screen)
				local stamp = need(peer, "ClashStamp")
				expect(stamp:FindFirstChild("Label", true).Text):toBe(case.words)
				local row = need(peer, "StampRow")
				check(
					stamp.AbsoluteSize.X <= row.AbsoluteSize.X,
					`the stamp is {stamp.AbsoluteSize.X} px in a {row.AbsoluteSize.X} px column`
				)
				local problems = strict(world, peer)
				check(#problems == 0, table.concat(problems, "; "))
				Rig.noErrors(world)
			end)
		end
	end
end)

describe("Words.Debate", function()
	it("names a short name on a stamp and says THEY for a long one", function()
		expect((Words.crowdStamp(-2, "Buster"))):toBe("BUSTER WON THE CROWD")
		expect((Words.crowdStamp(-2, LONG_NAME))):toBe("THEY WON THE CROWD")
		expect((Words.crowdStamp(3, LONG_NAME))):toBe("YOU WON THE CROWD")
		expect((Words.crowdStamp(0, LONG_NAME))):toBe("AN EVEN CROWD")
		local view: any = { you = 1 }
		local round: any = { winner = 2, margin = 3 }
		expect((Words.stamp(view, round, "Buster"))):toBe("BUSTER WINS BY 3")
		expect((Words.stamp(view, round, LONG_NAME))):toBe("THEY WIN BY 3")
	end)

	it("writes result cells with a sign, and splits as =", function()
		expect(Words.cell(3)):toBe("+3")
		expect(Words.cell(-2)):toBe("−2")
		expect(Words.cell(0)):toBe("=")
		expect(Words.cells({ cells = { 4, 0, -5 } } :: any)):toBe("D +4 · A = · P −5")
	end)

	it("says who leads the crowd and what the Zinger does, briefly", function()
		local view = { you = 1 } :: any
		expect(Words.crowdLine(view, { 4, 0 }, "Buster")):toBe("You +4")
		expect(Words.crowdLine(view, { 1, 3 }, "Buster")):toBe("Buster +2")
		expect(Words.crowdLine(view, { 2, 2 }, "Buster")):toBe("Even")
		expect(Words.crowdLine(view, { 1, 3 }, LONG_NAME)):toBe("Them +2")
		local board = { zingers = 1, zingerMult = 2, theirZingers = 1, theirZingerMult = 4 } :: any
		-- M1: the Zinger is used up on a split or a loss too (Sim/Debate.round).
		expect(Words.zinger(board, false)):toBe("Stake Zinger: win ×2 · used either way")
		expect(Words.zinger(board, true)):toBe("Zinger staked: win ×2, used either way")
		expect(Words.zinger({ zingers = 0, zingerMult = 2 } :: any, false)):toBe("Zinger spent")
		-- The bar's warning: only a Safe move that can split, with the Zinger staked.
		local splits = { safe = true, cells = { 2, 0, 1 } } :: any
		local wins = { safe = true, cells = { 2, 1, 1 } } :: any
		local risky = { safe = false, cells = { 2, -1, 0 } } :: any
		expect(Words.safeZinger(board, splits, true)):toBe("A split still uses the Zinger")
		expect(Words.safeZinger(board, splits, false)):toBe(nil)
		expect(Words.safeZinger(board, wins, true)):toBe(nil)
		expect(Words.safeZinger(board, risky, true)):toBe(nil)
		-- S1: the rival's live Zinger, with their name and multiplier.
		expect(Words.rivalZinger(board, "Buster")):toBe(
			"Buster still has a Zinger: a round they win, even by 1, can count ×4."
		)
		expect(Words.rivalZinger({ theirZingers = 0, theirZingerMult = 2 } :: any, "Buster")):toBe(nil)
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
