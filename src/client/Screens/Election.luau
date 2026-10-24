--!strict
-- Election night: states are called one at a time (safest first, closest last)
-- while both vote counts climb toward 270. The pace comes from the clock, not
-- from a tick count: tick(now) works out how many calls should have happened by
-- `now` and draws exactly that many, so it is safe to call as often as you like.
--
-- The show (docs/UI-STYLE.md §2.7, D-053): the safe states go quickly (all of
-- them in FAST_SHARE of the stage), then the last SLOW_CALLS and the call that
-- takes someone to 270 get a SLOW_BEAT each: the call holds for half the beat,
-- then "Too close to call" (or "Still counting") names the next one. Each call
-- wipes its state on the map, pops the spotlight, slides its row into the feed,
-- tweens the bar, counts the votes up and plays "call", higher as the leader
-- nears 270. Crossing 270 flashes the tick and plays "flip". The spotlight's
-- call is not in the feed until the next one replaces it (never shown twice);
-- once everything is called the spotlight steps aside and the feed has it all.
--
-- The front-page look (docs/DESIGN.md D-056, WP-3): the strip is a lit card
-- with Kit.raceBar (14 px, the tick named Marker270) and Fredoka totals; a
-- call flashes its state white and lands a "CALLED" stamp in the winner's color
-- on the spotlight (whose stroke and portrait ring turn that color, eyebrow "JUST
-- CALLED"; the suspense says "TOO CLOSE TO CALL" in orange); crossing 270
-- flashes the tick with a glow and, CROSS_STAMP later, stamps "270!" over it;
-- the tipping state is outlined in white before its call and keeps the ring
-- and an accent glow after it (its call has no CALLED stamp: one stamp per
-- moment; when it is the last call, the banner waits BANNER_HOLD for it).
-- On the map (D-079) states not called yet are hollow (a dark fill and a
-- hairline), each call shakes its state, and nothing carries a tag: the race
-- bar's "270!" is the night's one big label. Feed rows carry a
-- left bar in the winner's color. The banner: eyebrow "ELECTION NIGHT", the
-- line in Fredoka, the winner's stroke and glow.
--
-- Stable names for tests and agents: SkipButton (the pinned primary), EvYou,
-- EvThem, Feed, Banner (plus CallStatus, Tiebreak, MapBox, Counters, Bar,
-- Marker270, Stamp270, Spotlight, SpotLabel (an eyebrow: upper case), SpotState,
-- SpotCall, SpotPortrait, CalledStamp, BannerEyebrow, BarStatus, BarOpponent,
-- Goal, and the header's Timer). Screen.schedule and Screen.tippingCall are the pacing, for
-- the specs.
--
-- Layout (docs/UI-STYLE.md §4.8), every big box explicitly positioned:
--   Header        "Election night" · CallStatus subtitle (wide screens only: on a
--                 phone the spotlight says it) · "?" (How to play) · "Results in 0:32"
--   Counters      one 72 px strip: both candidates (first names on a phone, so
--                 nothing truncates) and one shared bar with the 270 tick
--   BannerPanel   replaces the strip once everything is called
--   Body          map 66 % | Side 34 % on wide screens; on phones the map takes
--                 min(width / ASPECT, 38 % of the screen) and Side the rest.
--   Side          the Spotlight (the latest call, big, or "Too close to call…"
--                 before a close one), the Feed of every call (newest on top:
--                 "Ohio · 17 votes" over "Dana by 2.9 points", tinted by the
--                 winner; Kit.dataColor) and the pinned ActionBar.
-- The coach tip "election.night" sits at the top of the feed, once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local Audio = require(script.Parent.Parent.UI.Audio)
local CoachTip = require(script.Parent.Parent.UI.CoachTip)
local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Header = require(script.Parent.Parent.UI.Header)
local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.Parent.Map.MapInterface)
local Motion = require(script.Parent.Parent.UI.Motion)
local NodeMap = require(script.Parent.Parent.Map.NodeMap)
local State = require(ReplicatedStorage.Shared.Sim.State)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local Types = require(script.Parent.Types)
local View = require(ReplicatedStorage.Shared.Sim.View)
local Words = require(ReplicatedStorage.Shared.UI.Words.Reveal)

local Screen = {}

local END_BUFFER = 5 -- s, every state is called this long before the stage ends
local CLOSE_MARGIN = 2 -- points; a state decided by less is "too close to call"
local FAST_SHARE = 0.6 -- of the stage: the quick calls are all in by then
local SLOW_CALLS = 8 -- the last (closest) calls that each get a slow beat
local SLOW_BEAT = 1.2 -- s, one slow call: the call holds, then the suspense for the next
local SUSPENSE_AT = 0.5 -- share of a slow beat after which the next state is "too close"
local CATCH_UP = 3 -- more new calls than this in one frame (a rejoin): no per-call effects
local FLASH_270 = 0.3 -- s, each half of the "270 to win" flash (it flashes twice)
local CROSS_STAMP = 0.6 -- s after the tipping call, the "270!" stamp lands on the tick
local CALL_FLASH = 0.12 -- s a called state's disc leans white before taking the winner's color
local BANNER_HOLD = 1.6 -- s the banner waits when the last call is the one that crosses 270 (its stamp's moment)
local CALL_PITCH = 0.9 -- the "call" cue's pitch at 0 votes; +CALL_RISE at 270
local CALL_RISE = 0.3
local GAP = Kit.space.sm -- px, between the big blocks
local STRIP_H = 72 -- px, the counters strip and a banner without a tiebreak note
local TIEBREAK_H = 96 -- px, banner plus the tiebreak note on a wide screen
local TIEBREAK_H_PORTRAIT = 132 -- px, same on a phone (the note wraps to more lines)
local ROW_TOP = 30 -- px, the strip's name/EV row
local BAR_H = 14 -- px, the EV bar (Kit.raceBar: 22 px with the tick's overhang)
local EV_W = 60 -- px, the EV number
local GOAL_W = 76 -- px, "270 to win" between the two sides
local SPOT_H = 92 -- px, the spotlight card: an eyebrow, the state, the call
local SPOT_PORTRAIT = 44 -- px, the winner's portrait in the spotlight
local BANNER_EYEBROW_H = 16 -- px, "ELECTION NIGHT" over the banner's line
local LINE_BAR_W = 4 -- px, a feed row's left bar in the winner's color
local CALL_POP = 0.94 -- the spotlight's scale as a call lands (it springs to 1)
local LINE_H = Kit.MIN_TOUCH -- px, smallest feed row
local MAP_SHARE = 0.66 -- of the width, wide screens
local MAP_SHARE_PORTRAIT = 0.38 -- of the height at most, phones
local WINNER_TINT = 0.3 -- how far a feed row leans toward the winner's color
local BANNER_GLOW = 0.65 -- the banner's glow in the winner's color (transparency)

local TOTAL_EV = 0 -- every electoral vote on the map; the bar fills against it
for _, record in StateData.list do
	TOTAL_EV += record.ev
end

-- ---------------------------------------------------------------- pacing

-- The call that takes a candidate to `need` votes (counted in call order), or nil.
local function tippingCall(results: { State.StateResult }, need: number): number?
	local ev: { [number]: number } = {}
	for k, result in results do
		if result.winner > 0 then
			ev[result.winner] = (ev[result.winner] or 0) + StateData.byId[result.state].ev
			if ev[result.winner] >= need then
				return k
			end
		end
	end
	return nil
end

-- When each call happens, in seconds after the stage starts, and which calls
-- are slow. The quick calls share FAST_SHARE of the stage; the last SLOW_CALLS
-- and the tipping call take SLOW_BEAT each; everything ends END_BUFFER before
-- the deadline (squeezed evenly when the stage is too short for that).
local function schedule(
	results: { State.StateResult },
	need: number,
	stageSeconds: number
): ({ number }, { [number]: boolean })
	local n = #results
	local slow: { [number]: boolean } = {}
	for k = math.max(1, n - SLOW_CALLS + 1), n do
		slow[k] = true
	end
	local tipping = tippingCall(results, need)
	if tipping then
		slow[tipping] = true
	end
	local slowCount = 0
	for _ in slow do
		slowCount += 1
	end
	local fastCount = n - slowCount
	local fastTotal = if fastCount > 0 then FAST_SHARE * stageSeconds else 0
	local slowTotal = slowCount * SLOW_BEAT
	local span = math.max(1, stageSeconds - END_BUFFER)
	local squeeze = math.min(1, span / math.max(1e-6, fastTotal + slowTotal))
	local fastBeat = if fastCount > 0 then fastTotal * squeeze / fastCount else 0
	local slowBeat = SLOW_BEAT * squeeze
	local ends: { number } = {}
	local t = 0
	for k = 1, n do
		t += if slow[k] then slowBeat else fastBeat
		ends[k] = t
	end
	return ends, slow
end

Screen.schedule = schedule
Screen.tippingCall = tippingCall

-- How many calls have happened `position` seconds into the stage.
local function called(ends: { number }, position: number): number
	local count = 0
	for k, finish in ends do
		if finish <= position + 1e-9 then
			count = k
		else
			break
		end
	end
	return count
end

-- ---------------------------------------------------------------- pieces

type Side = {
	name: TextLabel,
	ev: TextLabel,
	states: TextLabel,
	fill: Frame,
}

-- One candidate's half of the strip: the EV number at the outer edge, the name
-- over "N states" next to it, and that candidate's fill of the shared bar.
local function buildSide(strip: Frame, fill: Frame, evName: string, right: boolean): Side
	local align = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	local half = Kit.box({
		Name = if right then "ThemSide" else "YouSide",
		AnchorPoint = Vector2.new(if right then 1 else 0, 0),
		Position = UDim2.fromScale(if right then 1 else 0, 0),
		Size = UDim2.new(0.5, -(GOAL_W // 2), 0, ROW_TOP),
		Parent = strip,
	})
	local ev = Kit.text("0", {
		Name = evName,
		AnchorPoint = Vector2.new(if right then 1 else 0, 0),
		Position = UDim2.fromScale(if right then 1 else 0, 0),
		Size = UDim2.new(0, EV_W, 1, 0),
		Font = Kit.font.display,
		TextSize = Kit.size.title,
		TextScaled = true,
		TextXAlignment = align,
		Parent = half,
	})
	local textX = if right then 0 else EV_W + Kit.space.sm
	local name = Kit.text("", {
		Name = "Name",
		Position = UDim2.fromOffset(textX, 0),
		Size = UDim2.new(1, -(EV_W + Kit.space.sm), 0, 16),
		Font = Kit.font.medium,
		TextSize = Kit.size.body,
		TextScaled = true,
		-- One line: a long name shrinks to MIN_TEXT, then ends in "…".
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = align,
		Parent = half,
	})
	local states = Kit.text("", {
		Name = "States",
		Position = UDim2.fromOffset(textX, 16),
		Size = UDim2.new(1, -(EV_W + Kit.space.sm), 0, ROW_TOP - 16),
		TextSize = Kit.size.caption,
		TextScaled = true,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = align,
		Parent = half,
	})
	fill.Name = if right then "FillThem" else "FillYou"
	return { name = name, ev = ev, states = states, fill = fill }
end

-- A stamp's label at an explicit resting transparency, so it rests the same
-- with or without Motion.stamp's fade (which ends on 0).
local function settle(stamp: Frame)
	local label = stamp:FindFirstChild("Label", true) :: TextLabel?
	if label then
		label.TextTransparency = 0
	end
end

local function plural(n: number, one: string, many: string): string
	return if n == 1 then `{n} {one}` else `{n} {many}`
end

-- ---------------------------------------------------------------- screen

function Screen.mount(parent: Frame, ctx: Types.Ctx): Types.Screen
	local root = Kit.box({ Name = "ElectionScreen", Parent = parent })

	-- Static facts, filled the first time a payload with an election arrives.
	local payload: any = ctx.store.get().payload
	local results: { State.StateResult } = {}
	local ends: { number } = {}
	local slowCalls: { [number]: boolean } = {}
	local scheduledFor = -1 -- the stage length `ends` was worked out for
	local tipping: number? = nil -- the call that takes someone to 270
	local built = false
	local shown = 0 -- calls drawn so far
	local feedShown = 0 -- calls in the feed (all but the one in the spotlight)
	local suspenseShown = false -- the spotlight is naming the next close state
	local evShown: { number } = {} -- the votes each counter shows (or counts toward)
	local pressed = false -- this player tapped Skip
	local colors: { Colors.RGB } = {}
	local youIndex = 1
	local themIndex = 2
	local names: { string } = {}
	local faces: { string } = {} -- each player's candidate id (their portrait)
	local shortNames: { string } = {} -- first names, for the calls
	local map: MapInterface.Map = NodeMap.new()
	local drawn = false -- render() has run at least once
	local hasTiebreak = false -- the banner is showing a tiebreak note
	local bannerShown = false
	local laidOut = "" -- the shape applyLayout last laid out for
	local onSkip: () -> () = function() end

	local header =
		Header.new(root, { title = "Election night", subtitle = "Polls have closed", onHelp = ctx.help })
	header.subtitle.Name = "CallStatus"
	header:setTimerLabel("Results in")

	-- The counters strip: both candidates and one shared bar.
	local counters = Kit.depth(
		Kit.box({
			Name = "Counters",
			Position = UDim2.fromOffset(0, Kit.HEADER_H + GAP),
			Size = UDim2.new(1, 0, 0, STRIP_H),
			BackgroundTransparency = 0,
			Parent = root,
		}),
		Kit.colors.surfaceTop,
		Kit.colors.surface
	)
	Kit.corner(Kit.radius.panel).Parent = counters
	Kit.bevel(counters)
	Kit.shadow(counters)
	Kit.pad(Kit.space.sm).Parent = counters
	local need = ctx.config.EV_TO_WIN
	local mark = math.clamp(need / TOTAL_EV, 0, 1)
	local goal = Kit.text(string.upper(`{need} to win`), {
		Name = "Goal",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(mark, 0),
		Size = UDim2.fromOffset(GOAL_W, ROW_TOP),
		Font = Kit.font.medium,
		TextSize = Kit.size.caption,
		TextScaled = true,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Parent = counters,
	})
	-- The race to 270: one 14 px bar, you from the left, them from the right.
	local race = Kit.raceBar(counters, { h = BAR_H, mark = mark, name = "Bar" })
	race.root.Position = UDim2.fromOffset(0, ROW_TOP + Kit.space.xs)
	race.tick.Name = "Marker270"
	local stamp270: Frame? = nil -- "270!" over the tick, once someone gets there
	local youSide: Side = buildSide(counters, race.left, "EvYou", false)
	local themSide: Side = buildSide(counters, race.right, "EvThem", true)

	-- The banner, in the strip's place once every state is called.
	local bannerPanel = Kit.depth(
		Kit.panel({
			Name = "BannerPanel",
			Position = counters.Position,
			Size = UDim2.new(1, 0, 0, STRIP_H),
			Visible = false,
			Parent = root,
		}),
		Kit.colors.raisedTop,
		Kit.colors.raised
	)
	Kit.shadow(bannerPanel)
	local bannerGlow =
		Kit.glow(bannerPanel, Kit.colors.accent, { scale = 1, stretch = true, transparency = BANNER_GLOW })
	local bannerStroke = Kit.stroke(Kit.colors.accent, 2)
	bannerStroke.Parent = bannerPanel
	Kit.eyebrow("Election night", {
		Name = "BannerEyebrow",
		Size = UDim2.new(1, 0, 0, BANNER_EYEBROW_H),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = bannerPanel,
	})
	local banner = Kit.text("", {
		Name = "Banner",
		Position = UDim2.fromOffset(0, BANNER_EYEBROW_H),
		Size = UDim2.new(1, 0, 0, 32),
		Font = Kit.font.display,
		TextSize = Kit.size.title,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = bannerPanel,
	})
	local tiebreak = Kit.text("", {
		Name = "Tiebreak",
		Position = UDim2.fromOffset(0, BANNER_EYEBROW_H + 32 + Kit.space.xs),
		Size = UDim2.new(1, 0, 1, -(BANNER_EYEBROW_H + 32 + Kit.space.xs)),
		TextSize = Kit.size.caption,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
		Parent = bannerPanel,
	})

	-- The body: map and side panel.
	local body = Kit.box({ Name = "Body", Parent = root })
	local mapBox = Kit.box({ Name = "MapBox", Parent = body })
	map.root.AnchorPoint = Vector2.new(0.5, 0.5)
	map.root.Position = UDim2.fromScale(0.5, 0.5)
	map.root.Parent = mapBox

	local side = Kit.panel({ Name = "Side", Parent = body })

	-- The spotlight: the call that just happened, or the suspense before a close one.
	-- Elevation 4 (UI-STYLE §2): lit raised plate, a 2 px stroke in the moment's
	-- color, a shadow. The winner's portrait on the left, the words on the right.
	local spotlight = Kit.depth(
		Kit.panel({
			Name = "Spotlight",
			Size = UDim2.new(1, 0, 0, SPOT_H),
			Parent = side,
		}),
		Kit.colors.raisedTop,
		Kit.colors.raised
	)
	Kit.shadow(spotlight)
	local spotStroke = Kit.stroke(Kit.colors.line, 2)
	spotStroke.Parent = spotlight
	local spotPortrait = Kit.box({
		Name = "SpotPortrait",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(SPOT_PORTRAIT, SPOT_PORTRAIT),
		Parent = spotlight,
	})
	local spotWords = Kit.box({
		Name = "SpotWords",
		Position = UDim2.fromOffset(SPOT_PORTRAIT + Kit.space.md, 0),
		Size = UDim2.new(1, -(SPOT_PORTRAIT + Kit.space.md), 1, 0),
		Parent = spotlight,
	})
	Kit.list("Vertical", 2).Parent = spotWords
	local spotLabel = Kit.eyebrow("Polls have closed", {
		Name = "SpotLabel",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, Kit.size.caption + 4),
		AutomaticSize = Enum.AutomaticSize.None,
		Parent = spotWords,
	})
	local spotState = Kit.text("The first states are coming in", {
		Name = "SpotState",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, Kit.size.heading + 6),
		Font = Kit.font.bold,
		TextSize = Kit.size.heading,
		TextScaled = true,
		Parent = spotWords,
	})
	local spotCall = Kit.text("", {
		Name = "SpotCall",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, Kit.size.body + 6),
		Font = Kit.font.medium,
		TextScaled = true,
		Parent = spotWords,
	})
	local calledStamp: Frame? = nil -- "CALLED" over the spotlight's top-right corner
	local portraitFor = "" -- whose portrait the spotlight shows

	local feedTop = SPOT_H + GAP
	local feed = Kit.new("ScrollingFrame", {
		Name = "Feed",
		Position = UDim2.fromOffset(0, feedTop),
		Size = UDim2.new(1, 0, 1, -(feedTop + Kit.BAR_H + GAP)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = side,
	})
	Kit.list("Vertical", Kit.space.xs).Parent = feed
	-- Bottom padding so the oldest row is never clipped; room for the scroll bar.
	Kit.new("UIPadding", {
		PaddingBottom = UDim.new(0, Kit.space.sm),
		PaddingRight = UDim.new(0, Kit.space.sm),
		Parent = feed,
	})
	-- Once per session: what this screen is. Above every call (calls go -k).
	CoachTip.show(feed, { id = "election.night", order = -1e6 })

	local actionBar = ActionBar.new(side, {
		primary = "Skip to results",
		onPrimary = function()
			onSkip()
		end,
		primaryName = "SkipButton",
	})
	actionBar:setStatus("Safe states first, closest last", "muted")

	-- Sizes that depend on the screen shape and on the banner. Pixel math for the
	-- phone split, so it is re-run whenever the screen size changes.
	local function applyLayout()
		local portrait = ctx.portrait()
		local size = root.AbsoluteSize
		local shape = `{portrait}:{size.X}x{size.Y}:{bannerShown}:{hasTiebreak}`
		if shape == laidOut then
			return
		end
		laidOut = shape
		local stripH = if hasTiebreak then (if portrait then TIEBREAK_H_PORTRAIT else TIEBREAK_H) else STRIP_H
		counters.Visible = not bannerShown
		bannerPanel.Visible = bannerShown
		-- Once everything is called the spotlight steps aside: the feed has it all.
		spotlight.Visible = not bannerShown
		local top = if bannerShown then 0 else feedTop
		feed.Position = UDim2.fromOffset(0, top)
		feed.Size = UDim2.new(1, 0, 1, -(top + Kit.BAR_H + GAP))
		bannerPanel.Size = UDim2.new(1, 0, 0, stripH)
		top = Kit.HEADER_H + GAP + stripH + GAP
		body.Position = UDim2.fromOffset(0, top)
		body.Size = UDim2.new(1, 0, 1, -top)
		if portrait then
			local maxH = MAP_SHARE_PORTRAIT * size.Y
			local mapH = math.floor(math.min(size.X / map:aspectFor(size.X, maxH), maxH))
			mapBox.Position = UDim2.fromScale(0, 0)
			mapBox.Size = UDim2.new(1, 0, 0, mapH)
			side.Position = UDim2.fromOffset(0, mapH + GAP)
			side.Size = UDim2.new(1, 0, 1, -(mapH + GAP))
		else
			mapBox.Position = UDim2.fromScale(0, 0)
			mapBox.Size = UDim2.new(MAP_SHARE, -GAP // 2, 1, 0)
			side.Position = UDim2.new(MAP_SHARE, GAP // 2, 0, 0)
			side.Size = UDim2.new(1 - MAP_SHARE, -GAP // 2, 1, 0)
		end
	end

	local function nameOf(index: number): string
		local player = payload.view.players[index]
		if player and player.customName then
			return player.customName -- the Name Pass (D-069)
		end
		local candidate = if player then player.candidate else nil
		if candidate and Candidates.exists(candidate) then
			return Candidates.profile(ctx.config, candidate).name
		end
		return `Player {index}`
	end

	local function firstName(name: string): string
		return string.match(name, "^(%S+)") or name
	end

	-- First payload with an election: names, colors, counters, schedule.
	local function build()
		if built or payload == nil or payload.view.election == nil then
			return
		end
		built = true
		local view: View.View = payload.view
		local election = view.election :: State.ElectionResult
		results = election.results
		tipping = tippingCall(results, need)
		youIndex = payload.you
		themIndex = (youIndex % #view.players) + 1
		for p, player in view.players do
			colors[p] = Colors.of(player.color)
			names[p] = nameOf(p)
			faces[p] = player.candidate or ""
			-- A custom name stays whole: it is short, and its first word may not be a name.
			shortNames[p] = if player.customName then names[p] else firstName(names[p])
		end
		local short = ctx.portrait()
		youSide.name.Text = if short then shortNames[youIndex] else names[youIndex]
		themSide.name.Text = if short then shortNames[themIndex] else names[themIndex]
		-- Names in the readable variant of their color; the bar in the base colors.
		youSide.name.TextColor3 = Kit.textColor(Kit.color(colors[youIndex]))
		themSide.name.TextColor3 = Kit.textColor(Kit.color(colors[themIndex]))
		race:setColors(Kit.color(colors[youIndex]), Kit.color(colors[themIndex]))
	end

	-- Fill and rings for the first `count` calls. Calls from `wipeFrom` on are
	-- new this frame: they start uncalled and wipe to the winner's color (with
	-- `flash`, through a CALL_FLASH lean to white first: the called-state flash).
	local function paintMap(count: number, wipeFrom: number, flash: boolean)
		local view: View.View = payload.view
		local winners: { [string]: number } = {}
		for k = 1, math.min(count, wipeFrom - 1) do
			winners[results[k].state] = results[k].winner
		end
		local states: { View.StateView } = {}
		for i, s in view.states do
			local copy = table.clone(s)
			copy.poll = nil
			copy.leanTo = nil
			copy.lean = 0
			local winner = winners[s.id]
			if winner and winner > 0 then
				-- A 20-point margin is a full-strength fill in Colors.stateFill.
				local support = table.create(#view.players, 40)
				support[winner] = 60
				copy.poll = { support = support, undecided = 0 }
			end
			states[i] = copy
		end
		local shownView = table.clone(view)
		shownView.states = states
		map:setView(shownView, colors)
		for k = wipeFrom, count do
			local result = results[k]
			if result.winner > 0 then
				local color = Kit.color(colors[result.winner])
				if flash and not Motion.reduced() then
					local id = result.state
					map:wipe(id, Kit.colors.text)
					task.delay(CALL_FLASH, function()
						if root.Parent ~= nil then
							map:wipe(id, color)
						end
					end)
				else
					map:wipe(result.state, color)
				end
			else
				map:ring(result.state, Kit.colors.muted)
			end
			-- The call lands: the state shakes (nothing under reduced motion).
			if flash then
				map:shake(result.state)
			end
		end

		-- Not called yet: drawn hollow, a dark fill and a hairline (D-079), so
		-- the slate fill keeps meaning "toss-up" on every other screen.
		local marks: { [string]: MapInterface.Mark } = {}
		for k = count + 1, #results do
			marks[results[k].state] = { hollow = true }
		end
		if count > 0 then
			marks[results[count].state] = { ring = Kit.colors.accent }
		end
		-- The state that will take someone to 270 is outlined in white before
		-- its call (the suspense); once called it keeps the ring and a glow all
		-- night. The race bar's "270!" stays the only big label: no tags here.
		if tipping and count >= tipping then
			marks[results[tipping].state] =
				{ ring = Kit.colors.text, halo = Kit.colors.accent, haloStrong = true }
		elseif tipping then
			marks[results[tipping].state] = { ring = Kit.colors.text, hollow = true }
		end
		local nextResult = results[count + 1]
		if nextResult and slowCalls[count + 1] then
			-- The state everyone is waiting on glows in the accent (the tipping
			-- state keeps its white ring).
			local waiting = marks[nextResult.state]
			waiting.ring = waiting.ring or Kit.colors.accent
			waiting.halo = Kit.colors.accent
		end
		map:setMarks(marks)
	end

	-- One feed row: "Ohio · 17 votes" over "Dana by 2.9 points", tinted by the winner.
	local function addLine(k: number, live: boolean)
		local result = results[k]
		local color = Kit.colors.raised
		if result.winner > 0 then
			color = Kit.color(Colors.tint(Colors.raised, colors[result.winner], WINNER_TINT))
		end
		local line = Kit.dataColor(Kit.box({
			Name = `Line{k}`,
			Size = UDim2.new(1, 0, 0, LINE_H),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
			LayoutOrder = -k,
			Parent = feed,
		}))
		Kit.corner(Kit.radius.control).Parent = line
		-- A left bar in the winner's base color (a dead heat has none).
		if result.winner > 0 then
			local bar = Kit.new("Frame", {
				Name = "WinnerBar",
				Position = UDim2.fromOffset(Kit.space.xs, Kit.space.xs),
				Size = UDim2.new(0, LINE_BAR_W, 1, -2 * Kit.space.xs),
				BackgroundColor3 = Kit.color(colors[result.winner]),
				BorderSizePixel = 0,
				Parent = line,
			})
			Kit.round().Parent = bar
		end
		local inset = Kit.space.xs + LINE_BAR_W + Kit.space.sm
		local words = Kit.box({
			Name = "Words",
			Position = UDim2.fromOffset(inset, 0),
			Size = UDim2.new(1, -inset, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = line,
		})
		Kit.new("UIPadding", {
			PaddingRight = UDim.new(0, Kit.space.sm),
			PaddingTop = UDim.new(0, Kit.space.xs),
			PaddingBottom = UDim.new(0, Kit.space.xs),
			Parent = words,
		})
		Kit.list("Vertical", 0).Parent = words
		local stateText = Kit.text(Words.stateLine(result.state), {
			Name = "State",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, Kit.size.body + 4),
			Font = Kit.font.bold,
			TextScaled = true,
			Parent = words,
		})
		local callText = Kit.text(Words.callLine(result, shortNames), {
			Name = "Text",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, Kit.size.caption + 4),
			TextSize = Kit.size.caption,
			TextScaled = true,
			Parent = words,
		})
		if live then
			Motion.enter(line, 0)
			Motion.enter(stateText, 0)
			Motion.enter(callText, 0)
		end
	end

	-- The spotlight's eyebrow (upper case, like every eyebrow); `warn`: orange.
	local function setSpotLabel(text: string, color: Color3, warn: boolean?)
		spotLabel.Text = string.upper(text)
		spotLabel.TextColor3 = color
		spotLabel:SetAttribute("Warn", if warn then true else nil)
	end

	-- The spotlight's portrait: player `p`'s candidate ringed in their color
	-- (Kit.portrait), or a "?" plate while counting.
	local function setPortrait(p: number?)
		local key = if p then tostring(p) else "?"
		if key == portraitFor then
			return
		end
		portraitFor = key
		for _, child in spotPortrait:GetChildren() do
			child:Destroy()
		end
		local face = if p
			then Kit.portrait(faces[p], names[p] or "?", SPOT_PORTRAIT, { ring = Kit.color(colors[p]) })
			else Kit.portrait(nil, "?", SPOT_PORTRAIT)
		face.Parent = spotPortrait
	end

	-- "CALLED" in the winner's color over the spotlight's top-right corner
	-- (nil: none). `slam`: it lands with Motion.stamp (a live call).
	local function setCalled(color: Color3?, slam: boolean)
		if calledStamp then
			calledStamp:Destroy()
			calledStamp = nil
		end
		if color == nil then
			return
		end
		local stamp = Kit.stamp("CALLED", color, {
			size = Kit.size.heading,
			Name = "CalledStamp",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -Kit.space.xs, 0, -Kit.space.xs),
			ZIndex = 5,
			Parent = spotlight,
		})
		calledStamp = stamp
		settle(stamp)
		if slam then
			Motion.stamp(stamp)
		end
	end

	-- The spotlight after `count` calls: the suspense before a slow call, else
	-- the latest call in the winner's color. `live`: a call just landed.
	local function paintSpotlight(count: number, suspense: boolean, live: boolean)
		local nextResult = results[count + 1]
		if nextResult and suspense then
			local close = nextResult.margin < CLOSE_MARGIN
			if close then
				setSpotLabel("Too close to call", Kit.colors.loss, true)
			else
				setSpotLabel("Still counting", Kit.colors.muted)
			end
			spotState.Text = `{Words.stateLine(nextResult.state)}…`
			spotCall.Text = "Counting the last votes"
			spotCall.TextColor3 = Kit.colors.muted
			spotStroke.Color = Kit.colors.accent
			setPortrait(nil)
			setCalled(nil, false)
			return
		end
		local latest = results[count]
		if latest == nil then
			setSpotLabel("Polls have closed", Kit.colors.muted)
			spotState.Text = "The first states are coming in"
			spotCall.Text = ""
			spotStroke.Color = Kit.colors.line
			setPortrait(nil)
			setCalled(nil, false)
			return
		end
		setSpotLabel(if count == #results then "Last call" else "Just called", Kit.colors.muted)
		if count == tipping and latest.winner > 0 then
			setSpotLabel(`{shortNames[latest.winner]} reaches {need}!`, Kit.colors.text)
		end
		spotState.Text = Words.stateLine(latest.state)
		if latest.winner > 0 then
			local color = Kit.color(colors[latest.winner])
			spotCall.Text = `Called for {Words.callLine(latest, shortNames)}`
			spotCall.TextColor3 = Kit.textColor(color)
			spotStroke.Color = color
			setPortrait(latest.winner)
			-- One stamp per moment: the crossing call's is "270!" over the bar.
			setCalled(if count == tipping then nil else color, live)
		else
			spotCall.Text = Words.callLine(latest, shortNames)
			spotCall.TextColor3 = Kit.colors.text
			spotStroke.Color = Kit.colors.line
			setPortrait(nil)
			setCalled(nil, false)
		end
	end

	local function showBanner(election: State.ElectionResult)
		local winner = election.winner
		local loser = (winner % #colors) + 1
		banner.Text = `{names[winner]} wins {election.ev[winner]}–{election.ev[loser]}`
		bannerStroke.Color = Kit.color(colors[winner])
		if bannerGlow then
			bannerGlow.ImageColor3 = Kit.color(colors[winner])
		end
		local why: string? = nil
		if election.decidedBy == "States" then
			why =
				`Tied {election.ev[winner]}–{election.ev[loser]} on electoral votes. {names[winner]} wins the tiebreak by carrying more states ({election.statesWon[winner]} to {election.statesWon[loser]}).`
		elseif election.decidedBy == "Popular" then
			why =
				`Tied on electoral votes and on states ({election.statesWon[winner]} each). {names[winner]} wins the tiebreak with the national popular vote.`
		elseif election.decidedBy == "Coin" then
			why =
				`A dead heat on electoral votes, states and popular vote. A coin toss decided it for {names[winner]}.`
		end
		tiebreak.Visible = why ~= nil
		tiebreak.Text = why or ""
		banner.Size = if why then UDim2.new(1, 0, 0, 32) else UDim2.new(1, 0, 1, -BANNER_EYEBROW_H)
		header:setSubtitle(nil)
		bannerShown = true
		hasTiebreak = why ~= nil
		applyLayout()
	end

	-- "270!" in the accent, stamped over the tick (once a night). `slam`: it lands
	-- with Motion.stamp; otherwise (a rejoin) it is simply there.
	local function stampGoal(slam: boolean)
		if stamp270 ~= nil or root.Parent == nil then
			return
		end
		local stamp = Kit.stamp(`{need}!`, Kit.colors.accent, {
			Name = "Stamp270",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(mark, 0, 0, ROW_TOP + Kit.space.xs + (BAR_H + 8) // 2),
			ZIndex = 6,
			Parent = counters,
		})
		stamp270 = stamp
		settle(stamp)
		-- The stamp says it now; "270 TO WIN" would peek out from under it.
		goal.Visible = false
		if slam then
			Motion.stamp(stamp)
		end
	end

	-- Someone just reached 270: the tick flashes with a glow, "270 to win"
	-- flashes twice, and CROSS_STAMP later "270!" lands on the tick.
	local function flash270()
		Audio.play("flip")
		race:cross()
		Motion.flash(goal, Kit.colors.accent, FLASH_270)
		task.delay(FLASH_270, function()
			Motion.flash(goal, Kit.colors.accent, FLASH_270)
		end)
		-- D-058: the accent is white like the tick, so the tick blinks dim and back
		-- (race:cross() keeps its glow pulse; its color tween is replaced).
		Motion.cancel(race.tick)
		for k = 0, 3 do
			task.delay(k * FLASH_270, function()
				race.tick.BackgroundColor3 = if k % 2 == 0 then Kit.colors.line else Kit.colors.text
			end)
		end
		task.delay(CROSS_STAMP, function()
			stampGoal(true)
		end)
	end

	local function wholeVotes(n: number): string
		return tostring(math.floor(n + 0.5))
	end

	-- Draws everything up to `count` calls; `suspense`: the spotlight names the
	-- next (slow) call instead of the last one.
	local function render(count: number, suspense: boolean)
		local election = payload.view.election :: State.ElectionResult
		local before = shown
		-- A call or three since the last frame plays out; a rejoin's catch-up does not.
		local live = drawn and count > before and count - before <= CATCH_UP
		local ev = table.create(#colors, 0)
		local won = table.create(#colors, 0)
		for k = 1, count do
			local result = results[k]
			if result.winner > 0 then
				ev[result.winner] += StateData.byId[result.state].ev
				won[result.winner] += 1
			end
		end
		if count == #results then
			-- The server's totals are the truth, however the tally came out.
			ev, won = election.ev, election.statesWon
		end
		-- The feed has every call but the one the spotlight shows.
		-- The last call is the crossing: the spotlight keeps it while "270!" lands
		-- (BANNER_HOLD), then the feed takes it and the banner shows.
		local hold = live and tipping == count and count == #results
		local spotlit = count > 0 and (count < #results or hold) and not suspense
		local feedTarget = if spotlit then count - 1 else count
		local rowsLive = drawn and feedTarget - feedShown <= CATCH_UP
		for k = feedShown + 1, feedTarget do
			addLine(k, rowsLive)
		end
		feedShown = math.max(feedShown, feedTarget)
		shown = count
		suspenseShown = suspense
		drawn = true
		local function setSide(counter: Side, index: number, who: string?)
			local from = evShown[index] or 0
			evShown[index] = ev[index]
			local seconds = if live then Motion.t.call else 0
			Motion.countTo(counter.ev, from, ev[index], wholeVotes, seconds)
			local states = plural(won[index], "state", "states")
			counter.states.Text = if who then `{who} · {states}` else states
			Motion.tween(
				counter.fill,
				{ Size = UDim2.fromScale(math.clamp(ev[index] / TOTAL_EV, 0, 1), 1) },
				seconds,
				Motion.ease.soft
			)
		end
		-- "You · 9 states" wraps on a phone; there the name's color says who you are.
		setSide(youSide, youIndex, if ctx.portrait() then nil else "You")
		setSide(themSide, themIndex, nil)
		paintMap(count, if live then before + 1 else count + 1, live)
		paintSpotlight(count, suspense, live and count > before)
		if live then
			Motion.pop(spotlight, CALL_POP)
			local lead = math.max(ev[youIndex] or 0, ev[themIndex] or 0)
			Audio.play("call", { pitch = CALL_PITCH + CALL_RISE * math.min(lead / need, 1) })
			if tipping and before < tipping and count >= tipping then
				flash270()
			end
		elseif tipping and count >= tipping then
			-- A rejoin past the crossing: the stamp is already there.
			stampGoal(false)
		end
		if count == #results then
			if hold then
				-- The last call is the crossing: let "270!" land before the banner.
				header:setSubtitle(if ctx.portrait() then nil else `{count} of {#results} states called`)
				task.delay(BANNER_HOLD, function()
					if root.Parent ~= nil then
						for k = feedShown + 1, #results do
							addLine(k, true)
						end
						feedShown = #results
						showBanner(election)
					end
				end)
			else
				showBanner(election)
			end
		elseif ctx.portrait() then
			-- On a phone the spotlight says it; the subtitle would wrap.
			header:setSubtitle(nil)
		elseif count == 0 then
			header:setSubtitle("Polls have closed")
		else
			local nextResult = results[count + 1]
			if nextResult and suspense then
				local lead = if nextResult.margin < CLOSE_MARGIN
					then "Too close to call"
					else "Still counting"
				header:setSubtitle(`{lead}: {StateData.byId[nextResult.state].name}…`)
			else
				header:setSubtitle(`{count} of {#results} states called`)
			end
		end
	end

	-- The opponent's seat: the other index in this 1v1.
	local function opponentText(): string?
		if payload == nil then
			return nil
		end
		for p, seat in payload.seats do
			if p ~= payload.you then
				if not seat.connected then
					return "Opponent: disconnected"
				elseif seat.skip then
					return "Opponent: skipped"
				end
				return "Opponent: watching"
			end
		end
		return nil
	end

	local function updateBar()
		local seat = if payload then payload.seats[payload.you] else nil
		local waiting = pressed or (seat ~= nil and seat.skip)
		actionBar:setPrimary(if waiting then "Waiting for opponent…" else "Skip to results", not waiting)
		actionBar:setOpponent(opponentText())
	end

	onSkip = function()
		if pressed then
			return
		end
		pressed = true
		ctx.net.skip()
		updateBar()
	end

	local function refresh(now: number)
		if payload == nil then
			header:setTimer(nil)
			return
		end
		-- "Results in" is not a deadline to beat: no warning colors, no ticks.
		-- (Election night is always timed; only choices can go without, D-075.)
		local deadline = payload.deadline or payload.stageStart
		header:setTimer(deadline - now, 0)
		build()
		if not built then
			return
		end
		applyLayout()
		local stage = deadline - payload.stageStart
		if stage ~= scheduledFor then
			scheduledFor = stage
			ends, slowCalls = schedule(results, need, stage)
		end
		local position = math.max(0, now - payload.stageStart)
		local count = math.max(shown, called(ends, position))
		-- Half way through a slow call's beat, the spotlight turns to it.
		local suspense = false
		if count < #results and slowCalls[count + 1] then
			local start = if count > 0 then ends[count] else 0
			suspense = position >= start + SUSPENSE_AT * (ends[count + 1] - start)
		end
		if not drawn or count ~= shown or suspense ~= suspenseShown then
			render(count, suspense)
		end
	end

	applyLayout()
	updateBar()
	refresh(ctx.now())

	return {
		update = function(state: Types.State)
			payload = state.payload
			updateBar()
			refresh(ctx.now())
		end,
		tick = function(now: number)
			refresh(now)
		end,
		destroy = function()
			map:destroy()
			root:Destroy()
		end,
	}
end

return Screen
