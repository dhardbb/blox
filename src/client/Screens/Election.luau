--!strict
-- Election night: states are called one at a time (safest first, closest last)
-- while both vote counts climb toward 270. The pace comes from the clock, not
-- from a tick count: tick(now) works out how many calls should have happened by
-- `now` and draws exactly that many, so it is safe to call as often as you like.
--
-- Stable names for tests and agents: SkipButton (the pinned primary), EvYou,
-- EvThem, Feed, Banner (plus CallStatus, Tiebreak, MapBox, Counters, Marker270,
-- Spotlight, SpotLabel, SpotState, SpotCall, BarStatus, BarOpponent, and the
-- header's Timer).
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
local CoachTip = require(script.Parent.Parent.UI.CoachTip)
local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Header = require(script.Parent.Parent.UI.Header)
local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.Parent.Map.MapInterface)
local MapLayout = require(ReplicatedStorage.Shared.UI.MapLayout)
local NodeMap = require(script.Parent.Parent.Map.NodeMap)
local State = require(ReplicatedStorage.Shared.Sim.State)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local Types = require(script.Parent.Types)
local View = require(ReplicatedStorage.Shared.Sim.View)
local Words = require(ReplicatedStorage.Shared.UI.Words.Reveal)

local Screen = {}

local END_BUFFER = 5 -- s, every state is called this long before the stage ends
local CLOSE_MARGIN = 2 -- points; a state decided by less is "too close to call"
local CLOSE_WEIGHT = 2.5 -- a close call takes this many times as long as a safe one
local GAP = Kit.space.sm -- px, between the big blocks
local STRIP_H = 72 -- px, the counters strip and a banner without a tiebreak note
local TIEBREAK_H = 96 -- px, banner plus the tiebreak note on a wide screen
local TIEBREAK_H_PORTRAIT = 132 -- px, same on a phone (the note wraps to more lines)
local ROW_TOP = 30 -- px, the strip's name/EV row
local BAR_BOX_H = 22 -- px, the box holding the 14 px bar and the 270 tick
local BAR_H = 14 -- px, the EV bar
local EV_W = 60 -- px, the EV number
local GOAL_W = 76 -- px, "270 to win" between the two sides
local SPOT_H = 92 -- px, the spotlight card: a caption, the state, the call
local LINE_H = Kit.MIN_TOUCH -- px, smallest feed row
local MAP_SHARE = 0.66 -- of the width, wide screens
local MAP_SHARE_PORTRAIT = 0.38 -- of the height at most, phones
local WINNER_TINT = 0.35 -- how far a feed row leans toward the winner's color

local TOTAL_EV = 0 -- every electoral vote on the map; the bar fills against it
for _, record in StateData.list do
	TOTAL_EV += record.ev
end

-- ---------------------------------------------------------------- pacing

-- The end of each call's time slot, in slot units, and the total. Call k happens
-- when the clock reaches ends[k]; a close state's slot is the "too close" beat.
local function schedule(results: { State.StateResult }): ({ number }, number)
	local ends: { number } = {}
	local total = 0
	for k, result in results do
		total += if result.margin < CLOSE_MARGIN then CLOSE_WEIGHT else 1
		ends[k] = total
	end
	return ends, total
end

-- Slot units elapsed at `now` (0 to total).
local function elapsed(stageStart: number, deadline: number, now: number, total: number): number
	local span = math.max(1, deadline - stageStart - END_BUFFER)
	return math.clamp((now - stageStart) / span, 0, 1) * total
end

-- How many calls have happened once `position` slot units have passed.
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
local function buildSide(strip: Frame, bar: Frame, evName: string, right: boolean): Side
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
		Font = Kit.font.bold,
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
	local fill = Kit.box({
		Name = if right then "FillThem" else "FillYou",
		AnchorPoint = Vector2.new(if right then 1 else 0, 0),
		Position = UDim2.fromScale(if right then 1 else 0, 0),
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.colors.muted,
		ZIndex = 2,
		Parent = bar,
	})
	Kit.corner(Kit.radius.pill).Parent = fill
	return { name = name, ev = ev, states = states, fill = fill }
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
	local totalSlots = 0
	local built = false
	local shown = 0 -- calls drawn so far
	local pressed = false -- this player tapped Skip
	local colors: { Colors.RGB } = {}
	local youIndex = 1
	local themIndex = 2
	local names: { string } = {}
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
	local counters = Kit.box({
		Name = "Counters",
		Position = UDim2.fromOffset(0, Kit.HEADER_H + GAP),
		Size = UDim2.new(1, 0, 0, STRIP_H),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.colors.surface,
		Parent = root,
	})
	Kit.corner(Kit.radius.panel).Parent = counters
	Kit.pad(Kit.space.sm).Parent = counters
	local need = ctx.config.EV_TO_WIN
	Kit.text(`{need} to win`, {
		Name = "Goal",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(GOAL_W, ROW_TOP),
		TextSize = Kit.size.caption,
		TextScaled = true,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = counters,
	})
	local barBox = Kit.box({
		Name = "BarBox",
		Position = UDim2.fromOffset(0, ROW_TOP + Kit.space.xs),
		Size = UDim2.new(1, 0, 0, BAR_BOX_H),
		Parent = counters,
	})
	local bar = Kit.box({
		Name = "Bar",
		Position = UDim2.fromOffset(0, (BAR_BOX_H - BAR_H) // 2),
		Size = UDim2.new(1, 0, 0, BAR_H),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.colors.raised,
		Parent = barBox,
	})
	Kit.corner(Kit.radius.pill).Parent = bar
	Kit.box({
		Name = "Marker270",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(math.clamp(need / TOTAL_EV, 0, 1), 0),
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.colors.text,
		ZIndex = 3,
		Parent = barBox,
	})
	local youSide: Side = buildSide(counters, bar, "EvYou", false)
	local themSide: Side = buildSide(counters, bar, "EvThem", true)

	-- The banner, in the strip's place once every state is called.
	local bannerPanel = Kit.panel({
		Name = "BannerPanel",
		Position = counters.Position,
		Size = UDim2.new(1, 0, 0, STRIP_H),
		Visible = false,
		Parent = root,
	})
	local bannerStroke = Kit.stroke(Kit.colors.accent, 2)
	bannerStroke.Parent = bannerPanel
	local banner = Kit.text("", {
		Name = "Banner",
		Size = UDim2.new(1, 0, 0, 34),
		Font = Kit.font.bold,
		TextSize = Kit.size.title,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = bannerPanel,
	})
	local tiebreak = Kit.text("", {
		Name = "Tiebreak",
		Position = UDim2.fromOffset(0, 34 + Kit.space.xs),
		Size = UDim2.new(1, 0, 1, -(34 + Kit.space.xs)),
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
	local spotlight = Kit.panel({
		Name = "Spotlight",
		Size = UDim2.new(1, 0, 0, SPOT_H),
		BackgroundColor3 = Kit.colors.raised,
		Parent = side,
	})
	Kit.list("Vertical", 2).Parent = spotlight
	local spotStroke = Kit.stroke(Kit.colors.line, 2)
	spotStroke.Parent = spotlight
	local spotLabel = Kit.text("Polls have closed", {
		Name = "SpotLabel",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, Kit.size.caption + 4),
		TextSize = Kit.size.caption,
		TextColor3 = Kit.colors.muted,
		Parent = spotlight,
	})
	local spotState = Kit.text("The first states are coming in", {
		Name = "SpotState",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, Kit.size.heading + 6),
		Font = Kit.font.bold,
		TextSize = Kit.size.heading,
		TextScaled = true,
		Parent = spotlight,
	})
	local spotCall = Kit.text("", {
		Name = "SpotCall",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, Kit.size.body + 6),
		Font = Kit.font.medium,
		TextScaled = true,
		Parent = spotlight,
	})

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
		bannerPanel.Size = UDim2.new(1, 0, 0, stripH)
		local top = Kit.HEADER_H + GAP + stripH + GAP
		body.Position = UDim2.fromOffset(0, top)
		body.Size = UDim2.new(1, 0, 1, -top)
		if portrait then
			local mapH = math.floor(math.min(size.X / MapLayout.ASPECT, MAP_SHARE_PORTRAIT * size.Y))
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
		ends, totalSlots = schedule(results)
		youIndex = payload.you
		themIndex = (youIndex % #view.players) + 1
		for p, player in view.players do
			colors[p] = Colors.of(player.color)
			names[p] = nameOf(p)
			shortNames[p] = firstName(names[p])
		end
		local short = ctx.portrait()
		youSide.name.Text = if short then firstName(names[youIndex]) else names[youIndex]
		themSide.name.Text = if short then firstName(names[themIndex]) else names[themIndex]
		youSide.name.TextColor3 = Kit.color(colors[youIndex])
		themSide.name.TextColor3 = Kit.color(colors[themIndex])
		youSide.fill.BackgroundColor3 = Kit.color(colors[youIndex])
		themSide.fill.BackgroundColor3 = Kit.color(colors[themIndex])
	end

	-- Fill and rings for the first `count` calls.
	local function paintMap(count: number)
		local view: View.View = payload.view
		local winners: { [string]: number } = {}
		for k = 1, count do
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

		local marks: { [string]: MapInterface.Mark } = {}
		if count > 0 then
			marks[results[count].state] = { ring = Kit.colors.accent }
		end
		local nextResult = results[count + 1]
		if nextResult and nextResult.margin < CLOSE_MARGIN then
			marks[nextResult.state] = { ring = Kit.colors.accent, badge = "?" }
		end
		map:setMarks(marks)
	end

	-- One feed row: "Ohio · 17 votes" over "Dana by 2.9 points", tinted by the winner.
	local function addLine(k: number)
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
		Kit.new("UIPadding", {
			PaddingLeft = UDim.new(0, Kit.space.sm),
			PaddingRight = UDim.new(0, Kit.space.sm),
			PaddingTop = UDim.new(0, Kit.space.xs),
			PaddingBottom = UDim.new(0, Kit.space.xs),
			Parent = line,
		})
		Kit.list("Vertical", 0).Parent = line
		Kit.text(Words.stateLine(result.state), {
			Name = "State",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, Kit.size.body + 4),
			Font = Kit.font.bold,
			TextScaled = true,
			Parent = line,
		})
		Kit.text(Words.callLine(result, shortNames), {
			Name = "Text",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, Kit.size.caption + 4),
			TextSize = Kit.size.caption,
			TextScaled = true,
			Parent = line,
		})
	end

	-- The spotlight after `count` calls: the suspense before a close call, else
	-- the latest call in the winner's color.
	local function paintSpotlight(count: number)
		local nextResult = results[count + 1]
		if nextResult and nextResult.margin < CLOSE_MARGIN and count < #results then
			spotLabel.Text = "Too close to call"
			spotLabel.TextColor3 = Kit.colors.warn
			spotState.Text = `{Words.stateLine(nextResult.state)}…`
			spotCall.Text = "Counting the last votes"
			spotCall.TextColor3 = Kit.colors.muted
			spotStroke.Color = Kit.colors.accent
			return
		end
		local latest = results[count]
		if latest == nil then
			spotLabel.Text = "Polls have closed"
			spotLabel.TextColor3 = Kit.colors.muted
			spotState.Text = "The first states are coming in"
			spotCall.Text = ""
			spotStroke.Color = Kit.colors.line
			return
		end
		spotLabel.Text = if count == #results then "Last call" else "Just called"
		spotLabel.TextColor3 = Kit.colors.muted
		spotState.Text = Words.stateLine(latest.state)
		if latest.winner > 0 then
			spotCall.Text = `Called for {Words.callLine(latest, shortNames)}`
			spotCall.TextColor3 = Kit.color(colors[latest.winner])
			spotStroke.Color = Kit.color(colors[latest.winner])
		else
			spotCall.Text = Words.callLine(latest, shortNames)
			spotCall.TextColor3 = Kit.colors.text
			spotStroke.Color = Kit.colors.line
		end
	end

	local function showBanner(election: State.ElectionResult)
		local winner = election.winner
		local loser = (winner % #colors) + 1
		banner.Text = `{names[winner]} wins {election.ev[winner]}–{election.ev[loser]}`
		bannerStroke.Color = Kit.color(colors[winner])
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
		banner.Size = if why then UDim2.new(1, 0, 0, 34) else UDim2.fromScale(1, 1)
		header:setSubtitle(nil)
		bannerShown = true
		hasTiebreak = why ~= nil
		applyLayout()
	end

	-- Draws everything up to `count` calls.
	local function render(count: number)
		local election = payload.view.election :: State.ElectionResult
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
		for k = shown + 1, count do
			addLine(k)
		end
		shown = count
		drawn = true
		local function setSide(counter: Side, index: number, who: string?)
			counter.ev.Text = tostring(ev[index])
			local states = plural(won[index], "state", "states")
			counter.states.Text = if who then `{who} · {states}` else states
			counter.fill.Size = UDim2.fromScale(math.clamp(ev[index] / TOTAL_EV, 0, 1), 1)
		end
		-- "You · 9 states" wraps on a phone; there the name's color says who you are.
		setSide(youSide, youIndex, if ctx.portrait() then nil else "You")
		setSide(themSide, themIndex, nil)
		paintMap(count)
		paintSpotlight(count)
		if count == #results then
			showBanner(election)
		elseif ctx.portrait() then
			-- On a phone the spotlight says it; the subtitle would wrap.
			header:setSubtitle(nil)
		elseif count == 0 then
			header:setSubtitle("Polls have closed")
		else
			local nextResult = results[count + 1]
			if nextResult and nextResult.margin < CLOSE_MARGIN then
				header:setSubtitle(`Too close to call: {StateData.byId[nextResult.state].name}…`)
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
		header:setTimer(payload.deadline - now)
		build()
		if not built then
			return
		end
		applyLayout()
		local position = elapsed(payload.stageStart, payload.deadline, now, totalSlots)
		local count = math.max(shown, called(ends, position))
		if not drawn or count ~= shown then
			render(count)
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
