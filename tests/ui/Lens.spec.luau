--!strict
-- Map lenses (src/client/Map/Lens.luau, LensToggle.luau, D-046, UI-STYLE §4.6)
-- on the fake engine: the Votes lens is the default and the map's tags keep
-- only what is relevant now; the chips switch lenses and the choice is
-- remembered for the session; each lens shows one mark per state, inside its
-- circle; the "Map key" sheet says how to read each lens; and every lens passes
-- the strict UI audit, with each mark inside the map, at phone and tablet sizes
-- on the Campaign and Draft screens.

local Config = require("@sim/Config")
local Explain = require("@ui/Explain")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local IssueMap = require("@sim/IssueMap")
local Numbers = require("@ui/Numbers")
local PlanDraft = require("@ui/PlanDraft")
local Rig = require("./Rig")
local StateData = require("@sim/StateData")
local Test = require("@testlib/Test")
local Words = require("@ui/Words/Campaign")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local C = Config.defaults
local LENSES = { "EV", "Issues", "Polls", "Money" }
local SIZES = {
	{ x = 390, y = 844 }, -- phone portrait
	{ x = 844, y = 390 }, -- phone landscape
	{ x = 768, y = 1024 }, -- iPad portrait
	{ x = 1024, y = 768 }, -- iPad landscape
	{ x = 1280, y = 720 }, -- 16:9
}

local function mapOf(peer: FakeRoblox.Peer, screen: string): any
	return Rig.need(peer, screen, "NodeMap")
end

-- The texts of state `id`'s visible lens pills, in order.
local function pills(peer: FakeRoblox.Peer, screen: string, id: string): { string }
	local row = mapOf(peer, screen).Nodes:FindFirstChild(id):FindFirstChild("Lens")
	local out = {}
	if row.Visible == false then
		return out
	end
	for k = 1, 8 do
		local part = row:FindFirstChild(`Part{k}`)
		if part == nil or part.Visible == false then
			break
		end
		table.insert(out, part.Text)
	end
	return out
end

local function pill(peer: FakeRoblox.Peer, screen: string, id: string, k: number): any
	return mapOf(peer, screen).Nodes:FindFirstChild(id):FindFirstChild("Lens"):FindFirstChild(`Part{k}`)
end

local function same(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
end

local function modules(world: FakeRoblox.World, peer: FakeRoblox.Peer): (any, any)
	return FakeRoblox.require(world, peer, "src/client/Map/Lens.luau"),
		FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
end

-- "+3" for the leader's lead in `support`, "tie" under half a point.
local function leadText(support: { number }, prefix: string): (string, number?)
	local best, first, second = nil, -math.huge, -math.huge
	for p, value in support do
		if value > first then
			best, first, second = p, value, first
		elseif value > second then
			second = value
		end
	end
	local lead = first - second
	if best == nil or lead < 0.5 then
		return `{prefix}tie`, nil
	end
	return `{prefix}+{math.floor(lead + 0.5)}`, best
end

local function selected(peer: FakeRoblox.Peer, screen: string): { string }
	local out = {}
	for _, id in LENSES do
		if Rig.need(peer, screen, `Lens{id}`):GetAttribute("Selected") == true then
			table.insert(out, id)
		end
	end
	return out
end

-- Every visible lens row and pill of the map sits inside the map's box.
local function rowsInside(peer: FakeRoblox.Peer, screen: string, label: string)
	local box = mapOf(peer, screen)
	local p0, s0 = box.AbsolutePosition, box.AbsoluteSize
	for _, node in box.Nodes:GetChildren() do
		local row = node:FindFirstChild("Lens")
		if row and row.Visible ~= false then
			local p, s = row.AbsolutePosition, row.AbsoluteSize
			check(
				p.X >= p0.X - 1
					and p.Y >= p0.Y - 1
					and p.X + s.X <= p0.X + s0.X + 1
					and p.Y + s.Y <= p0.Y + s0.Y + 1,
				`{label}: {node.Name}'s lens row leaves the map`
			)
		end
	end
end

local function auditClean(world: FakeRoblox.World, peer: FakeRoblox.Peer, screen: string, label: string)
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	local root = FakeRoblox.find(peer, screen)
	local problems = {}
	for _, finding in Audit.check(root) do
		table.insert(problems, finding.message)
	end
	check(#problems == 0, `{label}: {table.concat(problems, " | ")}`)
	local loose = Rig.audit(peer, screen)
	check(#loose == 0, `{label}: {table.concat(loose, "; ")}`)
	rowsInside(peer, screen, label)
end

describe("Map lenses", function()
	it(
		"starts on Votes: each state shows its votes, a starred outlined tag on a battleground, tags keep only the event's *",
		function()
			local world, peer = Rig.fixture("Plan")
			local _, Kit = modules(world, peer)
			local view = Fixtures.payload(C, "Plan").view
			expect(selected(peer, "Campaign")):toEqual({ "EV" })
			for _, s in view.states do
				local ev = tostring(StateData.byId[s.id].ev)
				local part = pill(peer, "Campaign", s.id, 1)
				local edge = part:FindFirstChild("Edge")
				-- The number is white on the dark plate everywhere (never orange).
				check(same(part.TextColor3, Kit.colors.text), `{s.id}: the number is not the text color`)
				check(same(part.BackgroundColor3, Kit.colors.field), `{s.id}: the plate is not the field`)
				if s.battleground then
					-- D-056/D-058: a battleground is good news: a star and a white
					-- outline, never a white fill (that means "selected").
					expect(pills(peer, "Campaign", s.id)):toEqual({ Kit.STAR .. ev })
					check(
						same(edge.Color, Kit.colors.text) and edge.Transparency == 0,
						`{s.id}: a battleground's plate is not outlined in white`
					)
				else
					expect(pills(peer, "Campaign", s.id)):toEqual({ ev })
					check(edge.Transparency > 0, `{s.id}: a plain plate has a solid outline`)
				end
			end
			-- The old crowded tags ("H B G3 *") and the momentum arrows are gone from the default map.
			local map = mapOf(peer, "Campaign")
			for _, tag in map.Tags:GetChildren() do
				if tag.Visible ~= false then
					expect(tag.Text):toBe("*")
				end
			end
			for _, node in map.Nodes:GetChildren() do
				local arrow = node:FindFirstChild("Arrow")
				check(arrow == nil or arrow.Visible == false, `{node.Name} still shows a momentum arrow`)
			end
			-- No legend line over the map: a "Map key" button opens a sheet.
			check(Rig.findIn(peer, "Campaign", "Caption") == nil, "a caption line over the map")
			check(not Rig.shown(Rig.need(peer, "Campaign", "MapKeySheet"), "Campaign"), "the key starts open")
			Rig.tap(world, peer, "Campaign", "MapKey")
			check(Rig.shown(Rig.need(peer, "Campaign", "MapKeySheet"), "Campaign"), "the key did not open")
			for k, line in Words.key("EV") do
				expect(Rig.textOf(peer, "Campaign", `KeyLine{k}`)):toBe(line)
			end
			Rig.noErrors(world)
		end
	)

	it("switches with the chips, one selected at a time, and says how to read each lens", function()
		local world, peer = Rig.fixture("Plan")
		local Lens = modules(world, peer)
		for _, id in { "Issues", "Polls", "Money", "EV" } do
			Rig.tap(world, peer, "Campaign", `Lens{id}`)
			expect(selected(peer, "Campaign")):toEqual({ id })
			expect(Lens.current()):toBe(id)
			expect(Rig.textOf(peer, "Campaign", "KeyLine3")):toBe(Words.key(id)[3])
			check(Lens.legend(C, id :: any) ~= "", `no legend for {id}`)
		end
		expect(Rig.textOf(peer, "Campaign", "LensEV")):toBe("Votes")
		local chip = Rig.need(peer, "Campaign", "LensMoney")
		expect(chip.Text):toBe("Money")
		check(chip.AbsoluteSize.X >= 44 and chip.AbsoluteSize.Y >= 44, "a lens chip is under 44 px")
		Rig.noErrors(world)
	end)

	it("Issues: the state's top issue as a code, one of yours filled in your color", function()
		local world, peer = Rig.fixture("Plan")
		local Lens, Kit = modules(world, peer)
		Rig.tap(world, peer, "Campaign", "LensIssues")
		local view = Fixtures.payload(C, "Plan").view
		local platform = view.players[view.you].platform :: { string }
		local mine = Kit.playerColor(view, view.you)
		local filledSeen, drawnSeen = 0, 0
		for _, s in view.states do
			-- This match's drawn issues (D-047), not the static flavor.
			local issues = IssueMap.of(view.issueMap, s.id)
			if table.concat(issues, ",") ~= table.concat(StateData.byId[s.id].flavor, ",") then
				drawnSeen += 1
			end
			local shownIssue = issues[1]
			for _, issue in issues do
				if table.find(platform, issue) then
					shownIssue = issue
					break
				end
			end
			expect(pills(peer, "Campaign", s.id)):toEqual({ Lens.issueCode(shownIssue) })
			local part = pill(peer, "Campaign", s.id, 1)
			if table.find(platform, shownIssue) then
				filledSeen += 1
				check(
					same(part.BackgroundColor3, mine),
					`{s.id}: {shownIssue} is on your platform but not filled`
				)
			else
				check(same(part.BackgroundColor3, Kit.colors.field), `{s.id}: {shownIssue} is filled`)
			end
		end
		check(filledSeen > 0, "no state shares an issue with your platform")
		check(
			drawnSeen > 0,
			"the fixture's drawn issues match the flavor everywhere: the spec cannot tell them apart"
		)
		expect(Lens.issueCode("Jobs")):toBe("JOB")
		expect(Lens.issueCode("Weather")):toBe("WEA") -- an issue added later still gets a code
		-- The lens reads the View's issue map, whatever it says.
		local fake = table.clone(view) :: any
		fake.issueMap = table.clone(view.issueMap)
		for i, record in StateData.list do
			if record.id == view.states[1].id then
				fake.issueMap[i] = { "Transit", "Farms" }
			end
		end
		expect(Lens.issuesOf(fake, view.states[1])):toEqual({ "Transit", "Farms" })
	end)

	it("Polls: the public lead filled in the leader's color, the lean before a poll, nothing else", function()
		local world, peer = Rig.fixture("Plan")
		local _, Kit = modules(world, peer)
		local payload = Rig.deepCopy(Fixtures.payload(C, "Plan"))
		local view = payload.view
		local you = view.you
		local them = if you == 1 then 2 else 1
		-- An internal poll in OH and ground game in PA: on the state card, not the map.
		local support = table.create(#view.players, 0)
		support[you], support[them] = 52, 40
		view.internalPolls = {
			{
				state = "OH",
				support = support,
				undecided = 8,
				momentum = { 0, 0 },
				gotv = table.create(#view.players, 0),
			},
		}
		for _, s in view.states do
			if s.id == "PA" then
				s.gotv = 2
			end
		end
		Rig.push(world, peer, payload)
		Rig.tap(world, peer, "Campaign", "LensPolls")
		for _, s in view.states do
			local got = pills(peer, "Campaign", s.id)
			check(#got <= 1, `{s.id} shows {#got} marks`)
			if s.poll then
				local text, leader = leadText(s.poll.support, "")
				expect(got):toEqual({ text })
				if leader then
					local part = pill(peer, "Campaign", s.id, 1)
					check(
						same(part.BackgroundColor3, Kit.playerColor(view, leader)),
						`{s.id}'s lead is not filled in the leader's color`
					)
					check(
						same(part.TextColor3, Kit.colors.text) or same(part.TextColor3, Kit.colors.background),
						`{s.id}'s lead text is not readable on the fill`
					)
				end
			elseif s.leanTo and s.lean > 0 then
				expect(got):toEqual({ `~+{math.floor(s.lean + 0.5)}` })
			end
		end
		Rig.tap(world, peer, "Campaign", "OH")
		check(
			Rig.contains(Rig.textOf(peer, "Campaign", "CardInternal"), "52.0"),
			"the internal poll is not on the card"
		)
		Rig.tap(world, peer, "Campaign", "PA")
		check(
			Rig.contains(Rig.textOf(peer, "Campaign", "CardGround"), "2 /"),
			"the ground game is not on the card"
		)
		Rig.noErrors(world)
	end)

	it("Polls also marks momentum and ground game, from your own View only (D-070)", function()
		local world, peer = Rig.fixture("Plan")
		local Lens, Kit = modules(world, peer)
		local view = Rig.deepCopy(Fixtures.payload(C, "Plan").view)
		local you = view.you
		local them = if you == 1 then 2 else 1
		local byId = {}
		for _, s in view.states do
			s.momentum = table.create(#view.players, 0)
			s.gotv = 0
			byId[s.id] = s
		end
		byId.OH.momentum[them] = 3 -- a strong lead: ▲▲ in their color
		byId.PA.momentum[you], byId.PA.momentum[them] = 1.5, 1 -- a small one: ▲ in yours
		byId.WI.momentum[you], byId.WI.momentum[them] = 2, 2 -- tied: nobody drifts
		byId.PA.gotv = 2
		local scouted = table.create(#view.players, 0)
		scouted[them] = 3
		view.scouted = { { state = "PA", week = 2, gotv = scouted } }
		local lines = Lens.lines("Polls", { config = C, view = view })
		check(same(lines.OH.momentum, Kit.playerColor(view, them)), "OH's chevron is not theirs")
		expect(lines.OH.momentumStrong):toBe(true)
		check(same(lines.PA.momentum, Kit.playerColor(view, you)), "PA's chevron is not yours")
		expect(lines.PA.momentumStrong):toBe(nil)
		expect(lines.WI.momentum):toBe(nil)
		local pips = lines.PA.pips
		check(pips ~= nil and #pips == 2, "PA should show your pips and their polled ones")
		expect(pips[1].count):toBe(2)
		expect(pips[1].hollow):toBe(nil)
		expect(pips[2].count):toBe(3)
		expect(pips[2].hollow):toBe(true)
		-- Their ground game is never guessed: no poll of yours saw OH.
		expect(lines.OH.pips):toBe(nil)
		-- Only Polls carries the extras.
		for _, id in { "EV", "Issues", "Money" } do
			local other = Lens.lines(id :: any, { config = C, view = view })
			check(other.OH.momentum == nil and other.PA.pips == nil, `{id} shows the Polls marks`)
		end
		-- The legend explains them, in Polls only.
		local legend = Lens.mapLegend({ config = C, view = view }, "Polls")
		check(legend ~= nil and #legend == 3, "no Polls legend")
		expect(Lens.mapLegend({ config = C, view = view }, "EV")):toBe(nil)
		Rig.noErrors(world)
	end)

	it("shows the Polls marks and their legend on the Campaign map", function()
		local world, peer = Rig.fixture("Plan")
		local payload = Rig.deepCopy(Fixtures.payload(C, "Plan"))
		for _, s in payload.view.states do
			if s.id == "TX" then
				s.gotv = 3
			end
		end
		Rig.push(world, peer, payload)
		local map = mapOf(peer, "Campaign")
		Rig.tap(world, peer, "Campaign", "LensEV")
		expect(map.MapLegend.Visible):toBe(false)
		expect(map.Nodes.TX.Lens.Pips.Visible):toBe(false)
		Rig.tap(world, peer, "Campaign", "LensPolls")
		expect(map.MapLegend.Visible):toBe(true)
		-- In the lead's own pill (D-075), never on their own.
		expect(map.Nodes.TX.Lens.Visible):toBe(true)
		expect(map.Nodes.TX.Lens.Pips.Visible):toBe(true)
		local yours = 0
		for _, pip in map.Nodes.TX.Lens.Pips:GetChildren() do
			if pip.Name == "Yours" then
				yours += 1
			end
		end
		expect(yours):toBe(3)
		Rig.noErrors(world)
	end)

	it(
		"Money: Explain's number on the 8 richest pools, a coin each; dimmed once your plan empties one",
		function()
			local world, peer = Rig.fixture("Plan")
			local Lens = modules(world, peer)
			Rig.tap(world, peer, "Campaign", "LensMoney")
			local view = Fixtures.payload(C, "Plan").view
			local empty = PlanDraft.new()
			local amounts = {}
			for _, s in view.states do
				table.insert(amounts, Explain.action(C, view, empty, s.id, "Fundraise").money or 0)
			end
			table.sort(amounts, function(a: number, b: number): boolean
				return a > b
			end)
			local floor = amounts[Lens.MONEY_TOP]
			local shown = 0
			for _, s in view.states do
				local money = Explain.action(C, view, empty, s.id, "Fundraise").money or 0
				local got = pills(peer, "Campaign", s.id)
				if #got > 0 then
					shown += 1
					expect(got):toEqual({ Numbers.money(money) })
					check(money >= floor - 1e-9, `{s.id} shows {got[1]} but is not among the richest`)
					local row = mapOf(peer, "Campaign").Nodes:FindFirstChild(s.id).Lens
					check(row:FindFirstChild("Icon1") ~= nil, `{s.id} has no coin`)
				elseif money > floor + 1e-9 then
					error(`{s.id} ({Numbers.money(money)}) is among the richest but shows nothing`)
				end
			end
			check(shown > 0 and shown <= Lens.MONEY_TOP, `{shown} money values on the map`)
			-- Enough fundraisers in OH take the whole pool: one more raises nothing.
			local draft = PlanDraft.new()
			for _ = 1, 40 do
				if Lens.fundraise({ config = C, view = view, draft = draft }, "OH") < Lens.DRAINED then
					break
				end
				PlanDraft.add(draft, { kind = "Fundraise", state = "OH" } :: any)
			end
			check(#draft.actions >= 2, `one fundraiser drained OH ({#draft.actions})`)
			local lines = Lens.lines("Money", { config = C, view = view, draft = draft })
			expect(lines.OH.dim):toBe(true)
			expect(lines.OH.parts[1].text):toBe("$0.0")
			expect(lines.PA.dim):toBe(false)
			Rig.noErrors(world)
		end
	)

	it("dims a drained state on the circle map and lights it again in another lens", function()
		local world, peer = Rig.fixture("Plan")
		-- A circle map of its own, driven directly.
		local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
		local NodeMap = FakeRoblox.require(world, peer, "src/client/Map/NodeMap.luau")
		local gui = Kit.new("ScreenGui", { Name = "TestGui" })
		local stage =
			Kit.box({ Name = "Stage", Size = FakeRoblox.types.UDim2.fromOffset(832, 520), Parent = gui })
		local m = NodeMap.circles()
		m.root.Parent = stage
		local node = m.root.Nodes:FindFirstChild("OH")
		local label = node:FindFirstChild("Label")
		local y0 = label.Position.Y.Scale
		m:setLens({ OH = { parts = { { text = "$0.0" } }, dim = true } })
		expect(node.Circle.BackgroundTransparency > 0):toBe(true)
		expect(node.Lens.Visible):toBe(true)
		check(label.Position.Y.Scale < y0, "the label does not move up over the lens value")
		-- The value sits inside the circle, under the code.
		local circle, row = node.Circle, node.Lens
		local cy = circle.AbsolutePosition.Y + circle.AbsoluteSize.Y / 2
		check(row.AbsolutePosition.Y + row.AbsoluteSize.Y / 2 > cy, "the value is not under the middle")
		check(
			row.AbsolutePosition.Y + row.AbsoluteSize.Y
				<= circle.AbsolutePosition.Y + circle.AbsoluteSize.Y + 1,
			"the value pokes out under the circle"
		)
		m:setLens({ OH = { parts = { { text = "17" } } } })
		expect(node.Circle.BackgroundTransparency):toBe(0)
		expect(node.Lens.Part1.Text):toBe("17")
		m:setLens({})
		expect(node.Lens.Visible):toBe(false)
		expect(label.Position.Y.Scale):toBe(y0)
	end)

	it("dims a drained state on the real map and shows its value beside the code (D-070)", function()
		local world, peer = Rig.fixture("Plan")
		local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
		local NodeMap = FakeRoblox.require(world, peer, "src/client/Map/NodeMap.luau")
		local gui = Kit.new("ScreenGui", { Name = "TestGui" })
		local stage =
			Kit.box({ Name = "Stage", Size = FakeRoblox.types.UDim2.fromOffset(832, 520), Parent = gui })
		local m = NodeMap.new()
		m.root.Parent = stage
		local node = m.root.Nodes:FindFirstChild("OH")
		local shape = m.root.Shapes.ShapeOH
		m:setLens({ OH = { parts = { { text = "$0.0" } }, dim = true } })
		FakeRoblox.run(world, 0.05) -- the mark layout runs once a frame
		check(shape.ImageTransparency > 0, "a drained state is not dimmed")
		expect(node.Lens.Visible):toBe(true)
		local label, row = node.Label, node.Lens
		-- Beside or under the code, never on it (D-070's mark layout).
		local lp, ls, rp, rs =
			label.AbsolutePosition, label.AbsoluteSize, row.AbsolutePosition, row.AbsoluteSize
		check(
			not (
					rp.X + 1 < lp.X + ls.X
					and lp.X + 1 < rp.X + rs.X
					and rp.Y + 1 < lp.Y + ls.Y
					and lp.Y + 1 < rp.Y + rs.Y
				),
			"the value covers the code"
		)
		m:setLens({ OH = { parts = { { text = "17" } } } })
		expect(shape.ImageTransparency):toBe(0)
		expect(node.Lens.Part1.Text):toBe("17")
		m:setLens({})
		expect(node.Lens.Visible):toBe(false)
	end)

	it("remembers the lens for the session, from the draft into the campaign", function()
		local world, peer = Rig.practice(11)
		Rig.toDraftInput(world, peer)
		Rig.tap(world, peer, "Draft", "LensMoney")
		expect(selected(peer, "Draft")):toEqual({ "Money" })
		local function anyMoney(screen: string, view: any): boolean
			for _, s in view.states do
				if string.sub(pills(peer, screen, s.id)[1] or "", 1, 1) == "$" then
					return true
				end
			end
			return false
		end
		local p = Rig.payloadOf(world, peer)
		check(anyMoney("Draft", p.view), "the draft map shows no money")
		local driven: { [number]: boolean } = {}
		Rig.waitFor(world, function()
			local q = Rig.payloadOf(world, peer)
			if q ~= nil and q.stage == "Input" and q.view.phase == "Draft" and not driven[q.step] then
				driven[q.step] = true
				Rig.tap(world, peer, "Draft", `Row_{Rig.safeState(q.view)}`, 0.05)
				Rig.tap(world, peer, "Draft", "LockIn", 0.1)
			end
			return q ~= nil and q.stage == "Input" and q.view.phase == "Plan"
		end, 900, "the first plan")
		FakeRoblox.run(world, 1)
		expect(selected(peer, "Campaign")):toEqual({ "Money" })
		local q = Rig.payloadOf(world, peer)
		check(anyMoney("Campaign", q.view), "the campaign map shows no money")
		Rig.noErrors(world)
	end)

	it("passes the strict audit in every lens at phone and tablet sizes (Campaign)", function()
		for _, size in SIZES do
			for _, moment in { "Plan", "ChoiceWeek" } do
				local world, peer = Rig.fixture(moment, size)
				for _, id in LENSES do
					Rig.tap(world, peer, "Campaign", `Lens{id}`)
					auditClean(world, peer, "Campaign", `{moment} {id} at {size.x}x{size.y}`)
				end
				local chips = Rig.need(peer, "Campaign", "LensToggle")
				local map = mapOf(peer, "Campaign")
				check(
					chips.AbsolutePosition.Y + chips.AbsoluteSize.Y <= map.AbsolutePosition.Y + 0.5,
					`{moment} at {size.x}x{size.y}: the chips overlap the map`
				)
				Rig.noErrors(world)
			end
		end
	end)

	it("passes the strict audit in every lens at phone and tablet sizes (Draft and map reveal)", function()
		for _, size in SIZES do
			for _, moment in { "Draft", "MapReveal" } do
				local world, peer = Rig.fixture(moment, size)
				for _, id in LENSES do
					Rig.tap(world, peer, "Draft", `Lens{id}`)
					auditClean(world, peer, "Draft", `{moment} {id} at {size.x}x{size.y}`)
				end
				Rig.noErrors(world)
			end
		end
	end)
end)

describe("Lens motion", function()
	it("fades the lens pills in on a switch and draws the selected ring in", function()
		local world, peer = Rig.fixture("Plan")
		Rig.tap(world, peer, "Campaign", "LensPolls", 0.5)
		local map = Rig.need(peer, "Campaign", "NodeMap")
		local shownPills = 0
		for _, inst in map:GetDescendants() do
			if string.match(inst.Name, "^Part%d") and inst.Visible ~= false then
				shownPills += 1
				expect(inst.TextTransparency):toBe(0)
				check(math.abs(inst.BackgroundTransparency) < 1e-6, `{inst.Name} backing did not settle`)
			end
		end
		check(shownPills > 10, `only {shownPills} lens pills`)
		Rig.tap(world, peer, "Campaign", "OH", 0.5)
		-- The real map outlines the selection (3 px); a callout state's chip edge draws in.
		local outline = map.Outlines:FindFirstChild("OutlineOH")
		check(outline ~= nil and outline.Visible, "no selection outline")
		expect(outline:GetChildren()[1].Size.Y.Offset):toBe(3)
		Rig.tap(world, peer, "Campaign", "RI", 0.5)
		local ring = map.Nodes.RI.Chip:FindFirstChildOfClass("UIStroke")
		expect(ring.Thickness):toBe(3)
		Rig.noErrors(world)
	end)
end)
