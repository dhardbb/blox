--!strict
-- The issue symbols (D-076, UI/IssueIcons, Kit.issueIcon and friends): every
-- issue has a symbol (a 256x256 PNG from assets/issues/make.py, an id that is
-- "" or "rbxassetid://<n>", a short code); Kit draws the image once it can and
-- the old text until then; the map's Issues lens, its legend row and the Map
-- key show the symbols; chips and cards lead with them; and every screen that
-- shows them passes the strict UI audit at phone, iPad and desktop sizes, with
-- the symbols and without them (before the upload).

local fs = require("@lune/fs")

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Issues = require("@sim/Issues")
local Rig = require("./Rig")
local Test = require("@testlib/Test")
local IssueIcons = require("../../src/client/UI/IssueIcons")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local C = Config.defaults
local UDim2 = FakeRoblox.types.UDim2
local PATH = "src/client/UI/IssueIcons.luau"
local SIZES = {
	{ x = 390, y = 844 }, -- phone
	{ x = 1024, y = 768 }, -- iPad
	{ x = 1280, y = 720 }, -- desktop
}

-- The symbols as they were before the upload: every id "".
local function notUploaded(): { [string]: any }
	local icons = {}
	for issue, icon in IssueIcons.icons do
		local copy = table.clone(icon)
		copy.id = ""
		icons[issue] = copy
	end
	return icons
end

-- A fixture client whose issue symbols are not uploaded (and not previewed).
local function fallbackFixture(
	moment: string,
	screen: { x: number, y: number }?
): (FakeRoblox.World, FakeRoblox.Peer)
	local world = Rig.newWorld(3, screen)
	FakeRoblox.setModuleField(world, PATH, "preview", false)
	FakeRoblox.setModuleField(world, PATH, "icons", notUploaded())
	local peer = FakeRoblox.join(world, "P", { DebugScreen = moment })
	FakeRoblox.run(world, 1.5)
	return world, peer
end

-- Select's second step (the platform), two issues picked.
local function toIssues(world: FakeRoblox.World, peer: FakeRoblox.Peer)
	Rig.tap(world, peer, "Select", "Candidate_okafor")
	Rig.tap(world, peer, "Select", "LockIn", 0.5)
	Rig.tap(world, peer, "Select", "Issue_Jobs")
	Rig.tap(world, peer, "Select", "Issue_Health")
end

local function kit(world: FakeRoblox.World, peer: FakeRoblox.Peer): any
	return FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
end

local function strictAudit(world: FakeRoblox.World, peer: FakeRoblox.Peer, screen: string): number
	local Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
	return Audit.run(Rig.need(peer, "Screens", screen), screen, { strict = true })
end

-- A PNG's width and height from its IHDR chunk.
local function pngSize(bytes: string): (number, number)
	local function u32(at: number): number
		local a, b, c, d = string.byte(bytes, at, at + 3)
		return ((a * 256 + b) * 256 + c) * 256 + d
	end
	return u32(17), u32(21)
end

-- The issues the state `id` shows on the map's lens row: "symbol:<issue>" or the text.
local function marks(peer: FakeRoblox.Peer, id: string): { string }
	local row = Rig.need(peer, "Campaign", "NodeMap").Nodes:FindFirstChild(id):FindFirstChild("Lens")
	local out = {}
	if row.Visible == false then
		return out
	end
	local part = row:FindFirstChild("Part1")
	if part and part.Visible ~= false then
		local icon = part:FindFirstChild("IssueIcon")
		table.insert(out, if icon then `symbol:{icon:GetAttribute("IssueIcon")}` else part.Text)
	end
	return out
end

describe("Issue symbols (D-076)", function()
	it("gives every issue a symbol: a 256 px PNG, an empty or rbxassetid id, a code", function()
		local count = 0
		for issue, icon in IssueIcons.icons do
			count += 1
			check(Issues.isIssue(issue), `{issue} is not an issue`)
			check(
				icon.id == "" or string.match(icon.id, "^rbxassetid://%d+$") ~= nil,
				`{issue}: bad id {icon.id}`
			)
			check(#icon.code == 3, `{issue}: the code {icon.code} is not three letters`)
			local path = `assets/issues/{icon.file}.png`
			check(fs.isFile(path), `{issue}: no {path}`)
			local w, h = pngSize(fs.readFile(path))
			check(w == 256 and h == 256, `{path} is {w}x{h}, not 256x256`)
		end
		expect(count):toBe(#Issues.list)
		for _, issue in Issues.list do
			check(IssueIcons.icons[issue] ~= nil, `{issue} has no symbol`)
		end
		check(fs.isFile("assets/issues/make.py"), "no generator")
		expect(IssueIcons.preview):toBe(false) -- only the tests preview them
	end)

	it("draws the image once it can, the code (alone) or the name (beside) until then", function()
		local world, peer = Rig.fixture("Lobby")
		local Kit = kit(world, peer)
		local Live = FakeRoblox.require(world, peer, PATH)
		-- Previewed in the tests: the image, named, with its issue.
		local icon = Kit.issueIcon("Farms", 20)
		expect(icon.ClassName):toBe("ImageLabel")
		expect(icon:GetAttribute("IssueIcon")):toBe("Farms")
		expect(icon:GetAttribute("IssueName")):toBe("Farms & Rural")
		expect(icon.Size.X.Offset):toBe(20)
		local tag = Kit.issueTag("Transit")
		check(tag:FindFirstChild("IssueIcon") ~= nil, "the tag has no symbol")
		expect(tag:FindFirstChild("IssueText").Text):toBe("Roads & Transit")

		-- Not uploaded: the code alone, the name alone beside, no lead.
		Live.preview = false
		Live.icons = notUploaded()
		local fallback = Kit.issueIcon("Farms", 20)
		expect(fallback.ClassName):toBe("TextLabel")
		expect(fallback.Text):toBe("FRM")
		expect(fallback:GetAttribute("IconFallback")):toBe(true)
		local plain = Kit.issueTag("Transit")
		check(plain:FindFirstChild("IssueIcon") == nil, "a symbol before the upload")
		expect(plain:FindFirstChild("IssueText").Text):toBe("Roads & Transit")
		local label = Kit.text("Jobs", { Size = UDim2.fromOffset(200, 22) })
		expect(Kit.issueLead(label, "Jobs")):toBe(nil)
		check(label:FindFirstChild("IssueIcon") == nil, "a lead before the upload")

		-- Uploaded: the real id.
		Live.icons.Jobs.id = "rbxassetid://1"
		local image = Kit.issueIcon("Jobs")
		Live.icons.Jobs.id = ""
		expect(image.ClassName):toBe("ImageLabel")
		expect(image.Image):toBe("rbxassetid://1")
		expect(Kit.issueCode("Weather")):toBe("WEA") -- an issue added later still gets a code
		Rig.noErrors(world)
	end)

	it("leads a label with the symbol when it has room, and can swap or drop it", function()
		local world, peer = Rig.fixture("Lobby")
		local Kit = kit(world, peer)
		local gui = Kit.new("ScreenGui", { Name = "TestGui" })
		local wide = Kit.text("Environment", { Size = UDim2.fromOffset(200, 22), Parent = gui })
		local icon = Kit.issueLead(wide, "Environment", 20)
		check(icon ~= nil and icon.Visible, "no symbol in a wide label")
		expect(wide:FindFirstChildOfClass("UIPadding").PaddingLeft.Offset):toBe(24)
		-- It follows the text's color.
		wide.TextColor3 = Kit.colors.muted
		check(icon.ImageColor3 == Kit.colors.muted, "the symbol did not follow the text color")
		-- Too narrow for the symbol and the word: the word alone.
		local narrow = Kit.text("Environment", { Size = UDim2.fromOffset(70, 22), Parent = gui })
		local hidden = Kit.issueLead(narrow, "Environment", 20)
		check(hidden ~= nil and hidden.Visible == false, "a symbol squeezes the word")
		expect(narrow:FindFirstChildOfClass("UIPadding").PaddingLeft.Offset):toBe(0)
		-- Again with another issue: one symbol, the new one; nil removes it.
		Kit.issueLead(wide, "Health", 20)
		local found = 0
		for _, child in wide:GetChildren() do
			if child.Name == "IssueIcon" then
				found += 1
				expect(child:GetAttribute("IssueIcon")):toBe("Health")
			end
		end
		expect(found):toBe(1)
		Kit.issueLead(wide, nil)
		check(wide:FindFirstChild("IssueIcon") == nil, "nil did not remove the symbol")
		expect(wide:FindFirstChildOfClass("UIPadding").PaddingLeft.Offset):toBe(0)
		Rig.noErrors(world)
	end)

	it("shows each state's top issue by its symbol, and the code before the upload", function()
		local view = Fixtures.payload(C, "Plan").view
		local world, peer = Rig.fixture("Plan")
		local Lens = FakeRoblox.require(world, peer, "src/client/Map/Lens.luau")
		Rig.tap(world, peer, "Campaign", "LensIssues")
		local plain, plainPeer = fallbackFixture("Plan")
		Rig.tap(plain, plainPeer, "Campaign", "LensIssues")
		for _, s in view.states do
			local issue = Lens.shownIssue(view, s)
			if issue then
				expect(marks(peer, s.id)):toEqual({ `symbol:{issue}` })
				expect(marks(plainPeer, s.id)):toEqual({ Lens.issueCode(issue) })
			end
		end
		Rig.noErrors(world)
		Rig.noErrors(plain)
	end)

	it("names the symbols in the legend row (yours first) and in the Map key", function()
		local world, peer = Rig.fixture("Plan", { x = 1280, y = 720 })
		local Lens = FakeRoblox.require(world, peer, "src/client/Map/Lens.luau")
		local view = Fixtures.payload(C, "Plan").view
		local items = Lens.mapLegend({ config = C, view = view }, "Issues")
		check(items ~= nil and #items > 0, "no legend for the Issues lens")
		local platform = view.players[view.you].platform :: { string }
		local seenOther = false
		for _, item in items do
			expect(item.mark):toBe("issue")
			local mine = table.find(platform, item.issue) ~= nil
			check(not (mine and seenOther), `{item.issue}: yours after another`)
			check(mine == (item.drop == nil), `{item.issue}: drop {item.drop}`)
			seenOther = seenOther or not mine
		end
		Rig.tap(world, peer, "Campaign", "LensIssues")
		local legend = Rig.need(peer, "Campaign", "MapLegend")
		local symbols = 0
		for _, d in legend:GetDescendants() do
			if d.Name == "Mark" and d:GetAttribute("IssueIcon") then
				symbols += 1
			end
		end
		check(symbols > 0, "the legend row shows no symbol")
		Rig.tap(world, peer, "Campaign", "MapKey")
		local key = Rig.need(peer, "Campaign", "KeyIssues")
		check(key.Visible == true, "the Map key hides the symbols in the Issues lens")
		for _, issue in Issues.list do
			local cell = key:FindFirstChild(`KeyIssue_{issue}`)
			check(cell ~= nil and cell:FindFirstChild("IssueIcon") ~= nil, `no {issue} in the key`)
			expect(cell:FindFirstChild("IssueText").Text):toBe(Issues.displayName[issue])
		end
		Rig.noErrors(world)
	end)

	it("leads the issue cards, the message chips and the debate topics with the symbols", function()
		local world, peer = Rig.fixture("Select", { x = 1024, y = 768 })
		toIssues(world, peer)
		for _, issue in Issues.list do
			local card = Rig.findIn(peer, "Select", `Issue_{issue}`)
			if card then
				local name = card:FindFirstChild("IssueName")
				local icon = name and name:FindFirstChild("IssueIcon")
				check(icon ~= nil and icon:GetAttribute("IssueIcon") == issue, `{issue} card has no symbol`)
			end
		end
		local plan, planPeer = Rig.fixture("Plan", { x = 1280, y = 720 })
		Rig.tap(plan, planPeer, "Campaign", "OH")
		local chip = Rig.need(planPeer, "Campaign", "IssueJobs")
		check(chip:FindFirstChild("IssueIcon") ~= nil, "the Jobs message chip has no symbol")
		local debate, debatePeer = Rig.fixture("DebateIntro")
		local topics = Rig.need(debatePeer, "Debate", "RoundTopics")
		check(topics.Visible == true, "the intro lists no topics")
		local tags = 0
		for _, d in topics:GetDescendants() do
			if d.Name == "IssueIcon" then
				tags += 1
			end
		end
		expect(tags):toBe(#Fixtures.payload(C, "DebateIntro").view.debate.topics)
		Rig.noErrors(world)
		Rig.noErrors(plan)
		Rig.noErrors(debate)
	end)

	it("passes the strict audit with the symbols and without, at three sizes", function()
		for _, size in SIZES do
			for _, make in { Rig.fixture, fallbackFixture } do
				local world, peer = make("Plan", size)
				Rig.tap(world, peer, "Campaign", "LensIssues")
				expect(strictAudit(world, peer, "Campaign")):toBe(0)
				Rig.tap(world, peer, "Campaign", "MapKey")
				expect(strictAudit(world, peer, "Campaign")):toBe(0)
				local select, selectPeer = make("Select", size)
				toIssues(select, selectPeer)
				expect(strictAudit(select, selectPeer, "Select")):toBe(0)
				local debate, debatePeer = make("DebateIntro", size)
				expect(strictAudit(debate, debatePeer, "Debate")):toBe(0)
				Rig.noErrors(world)
			end
		end
	end)
end)
