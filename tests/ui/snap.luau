--!strict
-- Headless screenshots of every screen and state, for reviewing the UI without
-- Studio. Not a spec: `lune run tests` ignores it. Run from the repo root:
--
--   lune run tests/ui/snap.luau                      every shot at every size
--   lune run tests/ui/snap.luau -- campaign          shots whose name contains "campaign"
--   lune run tests/ui/snap.luau -- --size phone      one size: phone | ipad | desktop
--   lune run tests/ui/snap.luau -- --no-png          SVG only
--
-- Writes build/snaps/<size>/<shot>.svg (build/ is gitignored) and, on a Mac,
-- a .png next to each (qlmanage renders, sips crops; nothing is installed).
-- build/snaps/audit.txt lists each shot's strict UI audit findings (UI/Audit).
--
-- Each shot starts the client offline on a fixture (the DEBUG_UI path in
-- App.client.luau, Shared/UI/Fixtures), then taps through the real screen the
-- way the specs do (tests/ui/Rig.luau). The picture comes from
-- tests/lib/Snapshot.luau: layout is approximated (see its header), and the
-- dim strip at the top is the Roblox top bar.

local fs = require("@lune/fs")
local process = require("@lune/process")

local Config = require("@sim/Config")
local FakeRoblox = require("@testlib/FakeRoblox")
local EVChart = require("@ui/EVChart")
local Events = require("@sim/Events")
local Fixtures = require("@ui/Fixtures")
local PollMiss = require("@ui/PollMiss")
local Snapshot = require("@testlib/Snapshot")
local Rig = require("./Rig")

local UDim2 = FakeRoblox.types.UDim2

type World = FakeRoblox.World
type Peer = FakeRoblox.Peer

local SIZES = {
	{ name = "phone", x = 390, y = 844 },
	{ name = "ipad", x = 1024, y = 768 },
	{ name = "desktop", x = 1280, y = 720 },
}

type Shot = {
	name: string,
	moment: string, -- a DebugScreen fixture moment
	screen: string, -- the screen holder taps go to
	steps: ((world: World, peer: Peer) -> ())?,
}

local function tapIf(world: World, peer: Peer, screen: string, name: string, wait: number?)
	if Rig.findIn(peer, screen, name) then
		Rig.tap(world, peer, screen, name, wait)
	else
		print(`  (no {name} on {screen})`)
	end
end

-- Steps that put deck event `id` in the shown week (or, with `upcoming`, only
-- in next week's preview, as for Helen Strand) on the Plan fixture.
local function withEvent(id: string, upcoming: boolean?): (World, Peer) -> ()
	return function(world: World, peer: Peer)
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		local found: any = nil
		for _, definition in Events.deck do
			if definition.id == id then
				found = definition
			end
		end
		assert(found, `no deck event {id}`)
		local view = payload.view
		local event = {
			week = view.week + (if upcoming then 1 else 0),
			id = found.id,
			kind = found.kind,
			name = found.name,
			text = found.text,
			issue = found.issue,
			region = found.region,
		}
		if upcoming then
			view.event = nil
			view.nextEvent = event
		else
			view.event = event
		end
		Rig.push(world, peer, payload)
	end
end

-- The Polls lens with ground game (D-070): your units in PA, WI and GA, and
-- what your polls saw of theirs in PA and AZ.
local function pollsGround(world: World, peer: Peer)
	local payload = Fixtures.payload(Config.defaults, "Plan")
	local units = { PA = 3, WI = 2, GA = 1 }
	for _, s in payload.view.states do
		s.gotv = units[s.id] or s.gotv
	end
	payload.view.scouted = {
		{ state = "PA", week = 2, gotv = { 3, 2 } },
		{ state = "AZ", week = 2, gotv = { 0, 3 } },
	}
	local shift = world.clock - payload.stageStart
	payload.stageStart += shift
	payload.deadline += shift
	Rig.push(world, peer, payload)
	tapIf(world, peer, "Campaign", "LensPolls")
end

-- Rallies in PA twice and in OH once (presses, so a repeated button is found).
local function planPreview(world: World, peer: Peer)
	for _, name in { "PA", "Rally", "Rally", "OH", "Rally" } do
		if FakeRoblox.find(peer, name) then
			FakeRoblox.press(world, peer, name)
			FakeRoblox.run(world, 0.3)
		else
			print(`  (no {name})`)
		end
	end
end

local function lens(id: string): (World, Peer) -> ()
	return function(world, peer)
		tapIf(world, peer, "Campaign", `Lens{id}`)
	end
end

-- The style v2 kit on one page (docs/UI-STYLE.md): a reference picture for
-- the screen packages. Built over the Lobby fixture, which it hides.
local function kitGallery(world: World, peer: Peer)
	local function load(name: string): any
		return FakeRoblox.require(world, peer, `src/client/UI/{name}.luau`)
	end
	world.current = peer
	local Vector2 = FakeRoblox.types.Vector2
	local Kit = load("Kit")
	local Header = load("Header")
	local ActionBar = load("ActionBar")
	local CoachTip = load("CoachTip")
	local Sheet = load("Sheet")
	local Collapsible = load("Collapsible")
	local screens = FakeRoblox.find(peer, "Screens")
	screens.Visible = false
	local gui =
		Kit.new("ScreenGui", { Name = "KitGallery", Parent = peer.player:FindFirstChild("PlayerGui") })
	local root = Kit.box({ Name = "Gallery", Parent = gui })
	Kit.pad(10).Parent = root
	root:SetAttribute("PrimaryOptional", true)
	local header =
		Header.new(root, { title = "Week 3 of 12", subtitle = "Plan", now = true, onHelp = function() end })
	header:setNow("Tap a state on the map")
	header:setTimer(32, nil, 50)
	local scroll = Kit.box({
		Name = "Body",
		Position = UDim2.fromOffset(0, header.height + Kit.space.sm),
		Size = UDim2.new(1, 0, 1, -(header.height + Kit.space.sm + Kit.BAR_H + Kit.space.sm)),
		Parent = root,
	})
	-- Two columns on a wide screen (the parts, then the front-page pieces); one
	-- on a phone, without the expander and the ghost button.
	local wide = world.screen.x > 700
	local function column(name: string, x: number): any
		local frame = Kit.box({
			Name = name,
			Position = UDim2.new(x, if x > 0 then Kit.space.sm else 0, 0, 0),
			Size = UDim2.new(if wide then 0.5 else 1, if wide then -Kit.space.sm else 0, 1, 0),
			Parent = scroll,
		})
		return Kit.stack({ Name = "Stack", Parent = frame }, "Vertical", Kit.space.md)
	end
	local columnA = column("ColumnA", 0)
	local columnB = if wide then column("ColumnB", 0.5) else columnA
	CoachTip.reset()
	CoachTip.show(columnA, { id = "campaign.map", order = 1 })
	local card = Kit.card({ LayoutOrder = 2, Parent = columnA })
	Kit.heading("Ohio · 17 votes", { Parent = card, LayoutOrder = 1 })
	local pills = Kit.stack({ LayoutOrder = 2, Parent = card }, "Horizontal", Kit.space.xs)
	pills:FindFirstChildOfClass("UIListLayout").Wraps = true
	Kit.pill("Battleground", "white", { Parent = pills, LayoutOrder = 1 })
	Kit.pill("You lead +3", "good", { Parent = pills, LayoutOrder = 2 })
	Kit.pill("Your issue", "accent", { Parent = pills, LayoutOrder = 3 })
	Kit.pill("−0.5", "loss", { filled = true, Parent = pills, LayoutOrder = 4 })
	Kit.pill("+1.0", "good", { filled = true, Parent = pills, LayoutOrder = 5 })
	Kit.text("You lead by 3. Rally here to grow it.", { LayoutOrder = 3, Parent = card })
	Kit.caption("Public poll · updated this week", { LayoutOrder = 4, Parent = card })
	local chips = Kit.stack({ LayoutOrder = 3, Parent = columnA }, "Horizontal", Kit.space.sm)
	for i, label in { "Rally", "Ad $3", "Poll $0.5" } do
		local chip = Kit.chip(
			label,
			function() end,
			{ Size = UDim2.fromOffset(100, Kit.MIN_TOUCH), LayoutOrder = i, Parent = chips }
		)
		Kit.setSelected(chip, i == 1)
	end
	local option = Kit.cardButton(function() end, { LayoutOrder = 4, Parent = columnA })
	Kit.text("A · Side with the staff", { Font = Kit.font.bold, LayoutOrder = 1, Parent = option })
	Kit.caption("+1.5 where Health is a top issue", { LayoutOrder = 2, Parent = option })
	Kit.setSelected(option, true)
	if wide then
		local more = Collapsible.new(columnA, { title = "Why?", order = 5 })
		Kit.caption("Details live here, one tap away.", { Parent = more.body })
		Kit.button("More details", function() end, { variant = "ghost", LayoutOrder = 6, Parent = columnA })
	end

	-- The front-page pieces (D-056): a lit spotlight card with its shadow, a
	-- monogram and a CALLED stamp; the wordmark; the race bar.
	local cobalt = Kit.color({ r = 52, g = 104, b = 214 })
	local crimson = Kit.color({ r = 206, g = 52, b = 72 })
	local split = if wide then 0.5 else 0.62 -- the spotlight's share of the row
	local show = Kit.box({
		Name = "Showcase",
		LayoutOrder = 10,
		Size = UDim2.new(1, 0, 0, Kit.wordmarkHeight() + Kit.space.sm),
		Parent = columnB,
	})
	local spot = Kit.card({
		Name = "Spotlight",
		Position = UDim2.fromOffset(0, Kit.space.lg),
		Size = UDim2.new(split, -Kit.space.sm, 0, 0),
		Parent = show,
	})
	Kit.shadow(spot)
	local row = Kit.stack({ Name = "Row", Parent = spot }, "Horizontal", Kit.space.sm)
	Kit.monogram("Dana Okafor", cobalt, 44).Parent = row
	local words = Kit.stack({ Name = "Words", Size = UDim2.new(1, -52, 0, 0), Parent = row }, "Vertical", 0)
	Kit.eyebrow("Just called", { LayoutOrder = 1, Parent = words })
	Kit.text("Utah · 6 votes", { Font = Kit.font.bold, LayoutOrder = 2, Parent = words })
	Kit.stamp("CALLED", cobalt, {
		size = Kit.size.heading,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(split, -Kit.space.lg, 0, Kit.space.lg),
		ZIndex = 5,
		Parent = show,
	})
	Kit.wordmark(nil, {
		Position = UDim2.new(split, Kit.space.lg, 0, Kit.space.sm),
		Size = UDim2.new(1 - split, -Kit.space.lg, 0, Kit.wordmarkHeight()),
		Parent = show,
	})
	local race = Kit.raceBar(columnB, { h = 14, mark = 270 / 538, caption = "270", order = 11 })
	race:setColors(cobalt, crimson)
	race:set(310 / 538, 189 / 538)
	local bar = ActionBar.new(root, {
		primary = "Lock in",
		onPrimary = function() end,
		secondary = "Bank +15s",
		onSecondary = function() end,
	})
	bar:setStatus("2 of 3 actions used", "muted")
	bar:setOpponent("Opponent: thinking")
	if world.screen.x > 1100 then
		local sheet = Sheet.new(root, { title = "How rallies work" })
		Kit.text("A rally adds support in one state. On your issues it adds more.", { Parent = sheet.body })
		sheet:open()
	end
	world.current = nil
	FakeRoblox.run(world, 0.2)
end

local SHOTS: { Shot } = {
	{ name = "00-kit", moment = "Lobby", screen = "KitGallery", steps = kitGallery },
	{ name = "01-lobby", moment = "Lobby", screen = "Lobby" },
	{
		name = "02-lobby-hosting",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			world.current = peer
			Rig.storeOf(world, peer).setLobby({ state = "Hosting", code = "AB3CD", queued = 0, full = false })
			world.current = nil
			FakeRoblox.run(world, 0.5)
		end,
	},
	{
		name = "02b-lobby-friend",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			tapIf(world, peer, "Lobby", "PlayFriend")
		end,
	},
	{
		-- An admin (D-069): the color option free and "Review names (2)".
		name = "01g-lobby-admin",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			world.current = peer
			local lobby = Fixtures.lobby("Idle", { colorPass = "owned", color = "Teal" })
			lobby.review = { count = 2 }
			Rig.storeOf(world, peer).setLobby(lobby)
			world.current = nil
			FakeRoblox.run(world, 0.5)
		end,
	},
	{
		name = "02k-lobby-review",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			world.current = peer
			local lobby = Fixtures.lobby("Idle", { colorPass = "owned", color = "Teal" })
			lobby.review = { count = 2 }
			local store = Rig.storeOf(world, peer)
			store.setLobby(lobby)
			store.setReview({
				ok = true,
				entries = {
					{
						userId = "101",
						name = "Big Wave",
						owner = "MapleFox",
						count = 3,
						first = 1792800000,
						last = 1792972800,
					},
					{
						userId = "102",
						name = "Sir Zorkalot",
						owner = "QuietComet",
						count = 1,
						first = 1792972800,
						last = 1792972800,
					},
				},
			})
			world.current = nil
			FakeRoblox.run(world, 0.5)
			tapIf(world, peer, "Lobby", "ReviewButton", 0.5)
		end,
	},
	{
		name = "01b-lobby-color",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			world.current = peer
			Rig.storeOf(world, peer).setLobby(Fixtures.lobby("Idle", { colorPass = "owned", color = "Teal" }))
			world.current = nil
			FakeRoblox.run(world, 0.5)
		end,
	},
	{
		name = "02c-lobby-color-locked",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			world.current = peer
			Rig.storeOf(world, peer).setLobby(Fixtures.lobby("Idle", { colorPass = "locked" }))
			world.current = nil
			FakeRoblox.run(world, 0.5)
			tapIf(world, peer, "Lobby", "ColorButton")
		end,
	},
	{
		name = "02d-lobby-color-owned",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			world.current = peer
			Rig.storeOf(world, peer)
				.setLobby(Fixtures.lobby("Idle", { colorPass = "owned", color = "Emerald" }))
			world.current = nil
			FakeRoblox.run(world, 0.5)
			tapIf(world, peer, "Lobby", "ColorButton")
		end,
	},
	{
		-- Bot level picker (D-059): Hard picked.
		name = "01c-lobby-bot-hard",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			tapIf(world, peer, "Lobby", "Level_Hard")
		end,
	},
	{
		-- The leaderboard (D-059) for a ranked player outside the top 50.
		name = "01d-lobby-board-unlisted",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			world.current = peer
			Rig.storeOf(world, peer).setLeaderboard(Fixtures.leaderboard({ you = 0 }))
			world.current = nil
			FakeRoblox.run(world, 0.5)
		end,
	},
	{
		-- Nobody ranked yet.
		name = "01e-lobby-board-empty",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			world.current = peer
			Rig.storeOf(world, peer).setLeaderboard(Fixtures.leaderboard({ count = 0, you = -1 }))
			world.current = nil
			FakeRoblox.run(world, 0.5)
		end,
	},
	{
		-- The store could not be read and there is no earlier list.
		name = "01f-lobby-board-unavailable",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			world.current = peer
			Rig.storeOf(world, peer)
				.setLeaderboard(Fixtures.leaderboard({ count = 0, you = -1, status = "Unavailable" }))
			world.current = nil
			FakeRoblox.run(world, 0.5)
		end,
	},
	{
		name = "02e-lobby-leaderboard-sheet",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			tapIf(world, peer, "Lobby", "LeaderboardSeeAll")
		end,
	},
	{
		name = "02f-howto-1-goal",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			tapIf(world, peer, "Lobby", "HowToPlay")
		end,
	},
	{
		name = "02g-howto-2-week",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			tapIf(world, peer, "Lobby", "HowToPlay")
			tapIf(world, peer, "Lobby", "HowToNext")
		end,
	},
	{
		name = "02h-howto-3-actions",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			tapIf(world, peer, "Lobby", "HowToPlay")
			tapIf(world, peer, "Lobby", "HowToNext")
			tapIf(world, peer, "Lobby", "HowToNext")
		end,
	},
	{
		-- The eight issue symbols with their names (D-076).
		name = "02h2-howto-4-issues",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			tapIf(world, peer, "Lobby", "HowToPlay")
			for _ = 1, 3 do
				tapIf(world, peer, "Lobby", "HowToNext")
			end
		end,
	},
	{
		name = "02i-howto-5-events",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			tapIf(world, peer, "Lobby", "HowToPlay")
			for _ = 1, 4 do
				tapIf(world, peer, "Lobby", "HowToNext")
			end
		end,
	},
	-- D-075: the corner settings' tooltip after a tap.
	{
		name = "01h-lobby-corner-tip",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			tapIf(world, peer, "Lobby", "MotionToggle")
		end,
	},
	{
		name = "02j-howto-6-night",
		moment = "Lobby",
		screen = "Lobby",
		steps = function(world, peer)
			tapIf(world, peer, "Lobby", "HowToPlay")
			for _ = 1, 5 do
				tapIf(world, peer, "Lobby", "HowToNext")
			end
		end,
	},
	{ name = "03a-select-start", moment = "Select", screen = "Select" },
	{
		name = "03-select-candidate",
		moment = "Select",
		screen = "Select",
		steps = function(world, peer)
			tapIf(world, peer, "Select", "Candidate_okafor")
		end,
	},
	{
		name = "04-select-issues",
		moment = "Select",
		screen = "Select",
		steps = function(world, peer)
			tapIf(world, peer, "Select", "Candidate_okafor")
			tapIf(world, peer, "Select", "LockIn", 0.5)
			tapIf(world, peer, "Select", "Issue_Jobs")
			tapIf(world, peer, "Select", "Issue_Health")
		end,
	},
	{
		-- A Color Pass owner (D-061): Violet held, Teal claimed by Rex.
		name = "03b-select-color",
		moment = "SelectColor",
		screen = "Select",
		steps = function(world, peer)
			tapIf(world, peer, "Select", "Candidate_okafor")
		end,
	},
	{
		name = "03c-select-color-change",
		moment = "SelectColor",
		screen = "Select",
		steps = function(world, peer)
			tapIf(world, peer, "Select", "Candidate_okafor")
			tapIf(world, peer, "Select", "ColorSwatch_Emerald", 0.5)
		end,
	},
	{
		name = "04b-select-color-issues",
		moment = "SelectColor",
		screen = "Select",
		steps = function(world, peer)
			tapIf(world, peer, "Select", "Candidate_okafor")
			tapIf(world, peer, "Select", "LockIn", 0.5)
			tapIf(world, peer, "Select", "Issue_Jobs")
		end,
	},
	{
		-- A Name Pass owner (D-069): "Captain Zed" against "Big Wave".
		name = "03d-select-name",
		moment = "SelectName",
		screen = "Select",
		steps = function(world, peer)
			tapIf(world, peer, "Select", "Candidate_okafor")
		end,
	},
	{
		name = "03e-select-name-sheet",
		moment = "SelectName",
		screen = "Select",
		steps = function(world, peer)
			tapIf(world, peer, "Select", "Candidate_okafor")
			tapIf(world, peer, "Select", "NameButton", 0.5)
		end,
	},
	{
		-- Eligible without the pass: the line offers it.
		name = "03f-select-name-buy",
		moment = "SelectNameBuy",
		screen = "Select",
		steps = function(world, peer)
			tapIf(world, peer, "Select", "Candidate_okafor")
		end,
	},
	{
		-- Reporting the opponent's custom name from the Help sheet (D-069).
		name = "03g-select-report",
		moment = "SelectName",
		screen = "Select",
		steps = function(world, peer)
			tapIf(world, peer, "Select", "HelpButton", 0.5)
			tapIf(world, peer, "HelpOverlay", "HelpReport", 0.5)
		end,
	},
	{ name = "05-map-reveal", moment = "MapReveal", screen = "Draft" },
	{
		name = "06-draft",
		moment = "Draft",
		screen = "Draft",
		steps = function(world, peer)
			local id = Rig.safeState(Rig.payloadOf(world, peer).view)
			tapIf(world, peer, "Draft", `Row_{id}`)
		end,
	},
	{ name = "06a-draft-start", moment = "Draft", screen = "Draft" },
	{
		name = "06b-draft-reveal",
		moment = "Draft",
		screen = "Draft",
		steps = function(world, peer)
			-- The fixture's round, revealed: you got your pick, they got the next free state.
			local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
			local mine = Rig.safeState(payload.view)
			tapIf(world, peer, "Draft", `Row_{mine}`)
			tapIf(world, peer, "Draft", "LockIn")
			local theirs = "OH"
			payload.step += 1
			payload.stage = "Reveal"
			payload.reveal = "Draft"
			local round = payload.view.draftRound
			payload.events = {
				{ kind = "Pick", player = payload.you, state = mine, issue = "Nominate" },
				{ kind = "Pick", player = 3 - payload.you, state = theirs, issue = "Nominate" },
			}
			for _, pick in payload.events do
				table.insert(
					payload.view.draftLog,
					{ round = round, player = pick.player, state = pick.state, kind = "Nominate" }
				)
				table.insert(payload.view.players[pick.player].nominations, pick.state)
				for _, sv in payload.view.states do
					if sv.id == pick.state then
						sv.battleground = true
					end
				end
			end
			Rig.push(world, peer, payload)
		end,
	},
	{ name = "07-decision-stance", moment = "Stance", screen = "Decision" },
	{ name = "08-debate-intro", moment = "DebateIntro", screen = "Debate" },
	{ name = "08a-debate-round", moment = "DebateRound", screen = "Debate" },
	{
		-- A move picked and the Zinger staked: the map previews where a win lands.
		name = "08b-debate-picked",
		moment = "DebateRound",
		screen = "Debate",
		steps = function(world, peer)
			tapIf(world, peer, "Debate", "MovePivot")
			tapIf(world, peer, "Debate", "Zinger")
		end,
	},
	{ name = "09-campaign-plan", moment = "Plan", screen = "Campaign" },
	-- D-075: the tutorial's plan (no timer, no "+15 s") and a plan against the
	-- Easy bot (the plan timer doubled).
	{ name = "09t-campaign-plan-tutorial", moment = "PlanTutorial", screen = "Campaign" },
	{ name = "09u-campaign-plan-easy", moment = "PlanEasy", screen = "Campaign" },
	-- D-065: the event strip under the score for every kind of week (the Plan
	-- fixture is a Windfall week, 15 a Choice week), next week's event alone,
	-- and the details sheet a tap opens.
	{ name = "09b-event-spotlight", moment = "Plan", screen = "Campaign", steps = withEvent("bridges") },
	{ name = "09c-event-regional", moment = "Plan", screen = "Campaign", steps = withEvent("regatta") },
	{
		name = "09d-event-next-week",
		moment = "Plan",
		screen = "Campaign",
		steps = withEvent("bridges", true),
	},
	{
		name = "09e-event-sheet",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			tapIf(world, peer, "Campaign", "EventCard")
		end,
	},
	{
		name = "10-campaign-state-card",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			tapIf(world, peer, "Campaign", "OH")
		end,
	},
	{
		-- Every message chip with its issue's symbol (D-076), and the state's
		-- top issues under Details.
		name = "10g-campaign-messages",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			tapIf(world, peer, "Campaign", "OH")
			tapIf(world, peer, "Campaign", "MessageMore")
			tapIf(world, peer, "Campaign", "DetailsToggle")
		end,
	},
	{
		-- Two actions planned: each planned state wears its action's icon badge.
		name = "10a-campaign-planned",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			tapIf(world, peer, "Campaign", "OH")
			tapIf(world, peer, "Campaign", "Ad")
			tapIf(world, peer, "Campaign", "PA")
			tapIf(world, peer, "Campaign", "Fundraise")
		end,
	},
	-- The plan preview (D-071): an empty plan, then a rally in PA twice and one in OH.
	{ name = "10c-plan-preview-empty", moment = "Plan", screen = "Campaign" },
	{
		name = "10d-plan-preview",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			planPreview(world, peer)
		end,
	},
	{
		-- The same plan on the Polls lens with ground game: the tags stay readable.
		name = "10e-plan-preview-polls",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			pollsGround(world, peer)
			planPreview(world, peer)
		end,
	},
	{
		-- Both candidates in Ohio, a plan there: the pins and tags stay off the codes.
		name = "10f-pins-same-state",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			local payload = Fixtures.payload(Config.defaults, "Plan")
			for _, player in payload.view.players do
				player.location = "OH"
			end
			local shift = world.clock - payload.stageStart
			payload.stageStart += shift
			payload.deadline += shift
			Rig.push(world, peer, payload)
			for _, name in { "OH", "Rally" } do
				FakeRoblox.press(world, peer, name)
				FakeRoblox.run(world, 0.3)
			end
		end,
	},
	{
		-- The map key: what the four color steps mean, in both players' colors.
		name = "10b-campaign-map-key",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			tapIf(world, peer, "Campaign", "MapKey")
		end,
	},
	{ name = "11-lens-ev", moment = "Plan", screen = "Campaign", steps = lens("EV") },
	{ name = "12-lens-issues", moment = "Plan", screen = "Campaign", steps = lens("Issues") },
	{
		-- The map key in the Issues lens (D-076): every issue's symbol with its name.
		name = "12a-lens-issues-key",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			tapIf(world, peer, "Campaign", "LensIssues")
			tapIf(world, peer, "Campaign", "MapKey")
		end,
	},
	{ name = "13-lens-polls", moment = "Plan", screen = "Campaign", steps = lens("Polls") },
	{
		-- The Polls lens with ground game on the map (D-070): your units in PA, WI
		-- and GA, and what your polls saw of theirs in PA and AZ.
		name = "13b-lens-polls-ground",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			pollsGround(world, peer)
		end,
	},
	{ name = "14-lens-money", moment = "Plan", screen = "Campaign", steps = lens("Money") },
	{
		-- The Close filter (D-079): only the states within 8 points keep their fill and value.
		name = "14b-close-filter",
		moment = "Plan",
		screen = "Campaign",
		steps = lens("Close"),
	},
	{
		-- The Close filter on the Polls lens.
		name = "14c-close-polls",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			tapIf(world, peer, "Campaign", "LensPolls")
			tapIf(world, peer, "Campaign", "LensClose")
		end,
	},
	{ name = "15-campaign-choice-week", moment = "ChoiceWeek", screen = "Campaign" },
	{
		-- Beat one of the reveal: "Both plans are in" and who goes first.
		name = "16a-resolve-beat",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			-- The shot is taken 0.9 s after the push (0.3 + the 0.6 settle), so
			-- start the stage 0.7 s from now: 0.2 s into the 0.5 s intro beat.
			local payload = Fixtures.payload(Config.defaults, "Resolve")
			local shift = world.clock + 0.7 - payload.stageStart
			payload.stageStart += shift
			payload.deadline += shift
			Rig.push(world, peer, payload)
		end,
	},
	{ name = "16-resolve-start", moment = "Resolve", screen = "Campaign" },
	{
		-- The running tally (D-066): the first step has landed (shot 0.7 s into
		-- the stage: the 0.5 s intro, then step 1), map and score moved with it.
		name = "16b-resolve-step1",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			local payload = Fixtures.payload(Config.defaults, "Resolve")
			local shift = world.clock - payload.stageStart
			payload.stageStart += shift
			payload.deadline += shift
			Rig.push(world, peer, payload)
			FakeRoblox.run(world, 0.1)
		end,
	},
	{
		-- Halfway through the moves (3.2 s in): the tally so far on map and score.
		name = "16c-resolve-mid",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			local payload = Fixtures.payload(Config.defaults, "Resolve")
			local shift = world.clock - payload.stageStart
			payload.stageStart += shift
			payload.deadline += shift
			Rig.push(world, peer, payload)
			FakeRoblox.run(world, 2.6)
		end,
	},
	{
		-- The moment "New polls are in" lands (just after the last move, 2.1 s
		-- before the end): its stamp, the sweep, the real score.
		name = "16d-resolve-settle",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			local payload = Fixtures.payload(Config.defaults, "Resolve")
			local shift = world.clock - payload.stageStart
			payload.stageStart += shift
			payload.deadline += shift
			Rig.push(world, peer, payload)
			FakeRoblox.run(world, payload.deadline - payload.stageStart - 2.7)
		end,
	},
	{
		-- From the week-3 plan, so the reveal knows the polls before it ("What changed").
		name = "17-resolve-end",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			local payload = Fixtures.payload(Config.defaults, "Resolve")
			local shift = world.clock - payload.stageStart
			payload.stageStart += shift
			payload.deadline += shift
			Rig.push(world, peer, payload)
			FakeRoblox.run(world, payload.deadline - payload.stageStart - 0.9) -- the end of the reveal (it grows with its steps, D-066)
		end,
	},
	{ name = "18-choice-resolve", moment = "ChoiceResolve", screen = "Campaign" },
	{ name = "19-debate-clash", moment = "Clash", screen = "Debate" },
	{ name = "20-debate-verdict", moment = "Debate", screen = "Debate" },
	{ name = "21-election-start", moment = "Election", screen = "Election" },
	{
		name = "22-election-late",
		moment = "Election",
		screen = "Election",
		steps = function(world, _peer)
			FakeRoblox.run(world, 12)
		end,
	},
	{
		-- The call that takes someone to 270 (the tick flashes).
		name = "22a-election-tipping",
		moment = "Election",
		screen = "Election",
		steps = function(world, peer)
			-- The suspense beat just before the call that takes someone to 270:
			-- the shot is taken 0.9 s after the push (0.3 + the 0.6 settle).
			local Election = FakeRoblox.require(world, peer, "src/client/Screens/Election.luau")
			local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
			local results = payload.view.election.results
			local stage = payload.deadline - payload.stageStart
			local ends = Election.schedule(results, Config.defaults.EV_TO_WIN, stage)
			local tipping = Election.tippingCall(results, Config.defaults.EV_TO_WIN) or #results
			payload.stageStart = world.clock + 0.9 - (ends[tipping] - 0.2)
			payload.deadline = payload.stageStart + stage
			Rig.push(world, peer, payload)
		end,
	},
	{
		-- Just after the call that takes someone to 270: the tick has flashed and
		-- the "270!" stamp (CROSS_STAMP after the call) sits over the bar.
		name = "22b-election-270",
		moment = "Election",
		screen = "Election",
		steps = function(world, peer)
			-- The call lands 0.3 s after the push (a live call, not a catch-up);
			-- 0.5 s more here and the 0.6 s settle put the shot 1.1 s after it.
			local Election = FakeRoblox.require(world, peer, "src/client/Screens/Election.luau")
			local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
			local results = payload.view.election.results
			local stage = payload.deadline - payload.stageStart
			local ends = Election.schedule(results, Config.defaults.EV_TO_WIN, stage)
			local tipping = Election.tippingCall(results, Config.defaults.EV_TO_WIN) or #results
			payload.stageStart = world.clock + 0.3 - ends[tipping]
			payload.deadline = payload.stageStart + stage
			Rig.push(world, peer, payload)
			FakeRoblox.run(world, 0.5)
		end,
	},
	{ name = "23-results", moment = "Over", screen = "Results" },
	{
		-- The same match seen by the loser: no confetti, and a "Try next time" line.
		name = "23a-results-loss",
		moment = "Over",
		screen = "Results",
		steps = function(world, peer)
			local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
			payload.matchId = "snap-loss"
			local winner = payload.you
			payload.you = 3 - winner
			if payload.view.you ~= nil then
				payload.view.you = payload.you
			end
			payload.result = { winner = winner, reason = "Election" }
			Rig.push(world, peer, payload)
		end,
	},
	-- D-062: the same screen after a landslide, for the winner and for the loser
	-- (23-results is the ordinary win: no stamp).
	{ name = "23b-results-landslide", moment = "Landslide", screen = "Results" },
	{ name = "23c-results-landslide-loss", moment = "LandslideLoss", screen = "Results" },
	-- D-073: the end screen's Map tab (final polls, then the real results with a
	-- missed state tapped) and Graph tab (then a debate or stance marker tapped).
	{
		name = "23d-results-map",
		moment = "Over",
		screen = "Results",
		steps = function(world, peer)
			tapIf(world, peer, "Results", "Tab_Map")
		end,
	},
	{
		name = "23e-results-map-real",
		moment = "Over",
		screen = "Results",
		steps = function(world, peer)
			tapIf(world, peer, "Results", "Tab_Map")
			tapIf(world, peer, "Results", "Mode_Result")
			local misses = PollMiss.misses(PollMiss.rows(Rig.payloadOf(world, peer).view))
			if misses[1] then
				tapIf(world, peer, "Results", misses[1].id)
			end
		end,
	},
	{
		name = "23f-results-graph",
		moment = "Over",
		screen = "Results",
		steps = function(world, peer)
			tapIf(world, peer, "Results", "Tab_Graph")
		end,
	},
	{
		name = "23g-results-graph-marker",
		moment = "Over",
		screen = "Results",
		steps = function(world, peer)
			tapIf(world, peer, "Results", "Tab_Graph")
			local view = Rig.payloadOf(world, peer).view
			local markers = EVChart.markers(view, {})
			if markers[1] then
				tapIf(world, peer, "Results", `Marker_{markers[1].week}_{markers[1].kind}`)
			end
		end,
	},
	{
		name = "24-help",
		moment = "Plan",
		screen = "Campaign",
		steps = function(world, peer)
			tapIf(world, peer, "Campaign", "HelpButton")
		end,
	},
	{
		name = "25-results-breakdown",
		moment = "Over",
		screen = "Results",
		steps = function(world, peer)
			tapIf(world, peer, "Results", "FullBreakdown")
		end,
	},
	{
		name = "26-help-actions",
		moment = "Plan",
		screen = "HelpOverlay",
		steps = function(world, peer)
			tapIf(world, peer, "Campaign", "HelpButton")
			tapIf(world, peer, "HelpOverlay", "HelpTab_actions")
			tapIf(world, peer, "HelpOverlay", "HelpMoreButton_actions")
		end,
	},
	{
		-- "Leave match" at the end of the Help sheet (D-059), in a live match.
		name = "28-help-leave",
		moment = "Plan",
		screen = "HelpOverlay",
		steps = function(world, peer)
			tapIf(world, peer, "Campaign", "HelpButton")
		end,
	},
	{
		-- The confirmation against a person: "Leave and forfeit?"
		name = "28a-leave-human",
		moment = "Plan",
		screen = "LeaveOverlay",
		steps = function(world, peer)
			local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
			for _, seat in payload.seats do
				seat.kind = "Human"
			end
			Rig.push(world, peer, payload)
			tapIf(world, peer, "Campaign", "HelpButton")
			tapIf(world, peer, "HelpOverlay", "HelpLeave")
		end,
	},
	{
		-- The confirmation against the bot: "Leave this practice match?"
		name = "28b-leave-bot",
		moment = "Plan",
		screen = "LeaveOverlay",
		steps = function(world, peer)
			tapIf(world, peer, "Campaign", "HelpButton")
			tapIf(world, peer, "HelpOverlay", "HelpLeave")
		end,
	},
	{
		name = "27-help-win",
		moment = "Election",
		screen = "HelpOverlay",
		steps = function(world, peer)
			tapIf(world, peer, "Election", "HelpButton")
		end,
	},
}

-- ------------------------------------------------------------- arguments

local filter: string? = nil
local onlySize: string? = nil
local png = true
do
	local args = process.args
	local i = 1
	while i <= #args do
		local arg = args[i]
		if arg == "--size" then
			onlySize = args[i + 1]
			i += 1
		elseif arg == "--no-png" then
			png = false
		elseif arg ~= "--" then
			filter = arg
		end
		i += 1
	end
end

if not fs.isFile("default.project.json") then
	print("Run from the repository root: lune run tests/ui/snap.luau")
	process.exit(1)
end

local function canConvert(): boolean
	if not png then
		return false
	end
	local ok = pcall(function()
		local q = process.exec("which", { "qlmanage" })
		local s = process.exec("which", { "sips" })
		assert(q.ok and s.ok, "qlmanage or sips is missing")
	end)
	return ok
end
local convert = canConvert()

-- qlmanage only makes square thumbnails, so it renders a square copy of the
-- picture (content centered) and sips crops the middle back out.
local function toPng(squareSvg: string, dir: string, name: string, w: number, h: number)
	local tmp = `{dir}/_{name}.svg`
	fs.writeFile(tmp, squareSvg)
	local side = math.max(w, h)
	local result = process.exec("qlmanage", { "-t", "-s", tostring(side), "-o", dir, tmp })
	local thumb = tmp .. ".png"
	if result.ok and fs.isFile(thumb) then
		process.exec("sips", { "-c", tostring(h), tostring(w), thumb, "--out", `{dir}/{name}.png` })
		fs.removeFile(thumb)
	else
		print(`  png failed for {name}`)
	end
	fs.removeFile(tmp)
end

-- ------------------------------------------------------------- run

fs.writeDir("build/snaps")
local auditLines: { string } = {}
local count = 0
for _, size in SIZES do
	if onlySize and size.name ~= onlySize then
		continue
	end
	local dir = `build/snaps/{size.name}`
	fs.writeDir(dir)
	for _, shot in SHOTS do
		if filter and not string.find(shot.name, filter, 1, true) then
			continue
		end
		print(`{size.name} {shot.name}`)
		local world, peer = Rig.fixture(shot.moment, { x = size.x, y = size.y })
		if shot.steps then
			shot.steps(world, peer)
		end
		-- Let the Router's audit (0.5 s after a mount) and any tweens settle.
		FakeRoblox.run(world, 0.6)
		for _, e in world.errors do
			print(`  script error: {e}`)
		end
		local path = `{dir}/{shot.name}.svg`
		fs.writeFile(path, Snapshot.svg(peer))
		if convert then
			toPng(Snapshot.svg(peer, { square = true }), dir, shot.name, size.x, size.y)
		end
		-- The strict audit (UI/Audit.check, style rules included) of the screen on show.
		local audit = peer.modules[`{world.root}/src/client/UI/Audit.luau`]
		local holder = FakeRoblox.find(peer, shot.screen)
		if audit and holder then
			local findings, sizes = audit.check(holder, { style = true })
			table.insert(
				auditLines,
				`== {size.name} {shot.name}: {#findings} finding(s), {sizes} text size(s)`
			)
			for _, finding in findings do
				table.insert(auditLines, `   {finding.rule}: {finding.message}`)
			end
		else
			table.insert(auditLines, `== {size.name} {shot.name}: {shot.screen} not mounted`)
		end
		count += 1
	end
end
fs.writeFile("build/snaps/audit.txt", table.concat(auditLines, "\n") .. "\n")
print(`{count} shot(s) in build/snaps{if convert then " (svg + png)" else " (svg)"}`)
