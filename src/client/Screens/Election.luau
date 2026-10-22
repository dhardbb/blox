--!strict
-- Election night: states are called one at a time (safest first, closest last)
-- while two EV counters climb toward 270. The pace comes from the clock, not from
-- a tick count: tick(now) works out how many calls should have happened by `now`
-- and draws exactly that many, so it is safe to call as often as you like.
--
-- Stable names for tests and agents: SkipButton, EvYou, EvThem, Feed, Banner
-- (plus CallStatus, Tiebreak, MapBox).
--
-- Layout: wide screens put the counters on top, then a status/banner strip, then
-- the map on the left and the call feed on the right. Phones in portrait stack
-- counters, strip, map, feed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.Parent.Map.MapInterface)
local NodeMap = require(script.Parent.Parent.Map.NodeMap)
local State = require(ReplicatedStorage.Shared.Sim.State)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local Types = require(script.Parent.Types)
local View = require(ReplicatedStorage.Shared.Sim.View)

local Screen = {}

local END_BUFFER = 5 -- s, every state is called this long before the stage ends
local CLOSE_MARGIN = 2 -- points; a state decided by less is "too close to call"
local CLOSE_WEIGHT = 2.5 -- a close call takes this many times as long as a safe one
local COUNTER_HEIGHT = 112 -- px
local STRIP_HEIGHT = 76 -- px, the status line or a banner without a tiebreak note
local TIEBREAK_HEIGHT = 100 -- px, banner plus the tiebreak note on a wide screen
local TIEBREAK_HEIGHT_PORTRAIT = 150 -- px, same on a phone (the note wraps to more lines)
local GAP = 8 -- px
local FEED_TITLE = 30 -- px
local SKIP_HEIGHT = 48 -- px

local TOTAL_EV = 0 -- every electoral vote on the map; the bars fill against it
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

type Counter = {
	frame: Frame,
	name: TextLabel,
	goal: TextLabel,
	ev: TextLabel,
	states: TextLabel,
	fill: Frame,
}

-- One candidate's EV counter: name, big EV number, states won, and a bar that
-- fills toward the 270 marker. `evName` is the stable name of the number label.
local function buildCounter(parent: Frame, evName: string, need: number): Counter
	local frame = Kit.panel({ Name = evName .. "Panel", Parent = parent })
	Kit.list("Vertical", 4).Parent = frame

	local nameRow =
		Kit.box({ Name = "NameRow", Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, Parent = frame })
	local name = Kit.text("", {
		Name = "Name",
		Size = UDim2.fromScale(0.62, 1),
		TextScaled = true,
		TextSize = Kit.size.heading,
		Font = Kit.font.bold,
		TextColor3 = Kit.colors.text,
		Parent = nameRow,
	})
	local goal = Kit.text(`{need} to win`, {
		Name = "Goal",
		Size = UDim2.fromScale(0.38, 1),
		Position = UDim2.fromScale(0.62, 0),
		TextScaled = true,
		TextSize = Kit.size.body,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = nameRow,
	})

	local evRow = Kit.box({ Name = "EvRow", Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2, Parent = frame })
	local ev = Kit.text("0", {
		Name = evName,
		Size = UDim2.fromScale(0.5, 1),
		TextScaled = true,
		TextSize = Kit.size.hero,
		Font = Kit.font.bold,
		Parent = evRow,
	})
	local states = Kit.text("0 states", {
		Name = "States",
		Size = UDim2.fromScale(0.5, 1),
		Position = UDim2.fromScale(0.5, 0),
		TextScaled = true,
		TextSize = Kit.size.heading,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = evRow,
	})

	local bar = Kit.box({
		Name = "Bar",
		Size = UDim2.new(1, 0, 0, 14),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.colors.raised,
		LayoutOrder = 3,
		Parent = frame,
	})
	Kit.corner(7).Parent = bar
	local fill = Kit.box({
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.colors.muted,
		ZIndex = 2,
		Parent = bar,
	})
	Kit.corner(7).Parent = fill
	Kit.box({
		Name = "Marker270",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(math.clamp(need / TOTAL_EV, 0, 1), 0.5),
		Size = UDim2.new(0, 3, 1, 8),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.colors.text,
		ZIndex = 3,
		Parent = bar,
	})
	return { frame = frame, name = name, goal = goal, ev = ev, states = states, fill = fill }
end

local function plural(n: number, one: string, many: string): string
	return if n == 1 then `{n} {one}` else `{n} {many}`
end

-- A feed row's background: the surface color leaning toward the winner's.
local function tint(color: Colors.RGB): Color3
	return Kit.color(Colors.mix(Colors.raised, color, 0.35))
end

-- ---------------------------------------------------------------- screen

function Screen.mount(parent: Frame, ctx: Types.Ctx): Types.Screen
	local root = Kit.box({ Name = "ElectionScreen", Parent = parent })
	local layout = Kit.list("Vertical", GAP)
	layout.Parent = root

	-- Static facts, filled the first time a payload with an election arrives.
	local payload: any = ctx.store.get().payload
	local results: { State.StateResult } = {}
	local ends: { number } = {}
	local totalSlots = 0
	local built = false
	local shown = 0 -- calls drawn so far
	local pressed = false -- this player tapped Skip
	local wasPortrait = ctx.portrait()
	local colors: { Colors.RGB } = {}
	local youIndex = 1
	local themIndex = 2
	local names: { string } = {}
	local map: MapInterface.Map = NodeMap.new()
	local drawn = false -- render() has run at least once
	local hasTiebreak = false -- the banner is showing a tiebreak note
	local onSkip: () -> () = function() end

	-- The counters row.
	local counters = Kit.box({
		Name = "Counters",
		Size = UDim2.new(1, 0, 0, COUNTER_HEIGHT),
		LayoutOrder = 1,
		Parent = root,
	})
	local need = ctx.config.EV_TO_WIN
	local youCounter: Counter = buildCounter(counters, "EvYou", need)
	local themCounter: Counter = buildCounter(counters, "EvThem", need)
	youCounter.frame.Size = UDim2.new(0.5, -GAP // 2, 1, 0)
	youCounter.frame.Position = UDim2.fromScale(0, 0)
	themCounter.frame.Size = UDim2.new(0.5, -GAP // 2, 1, 0)
	themCounter.frame.Position = UDim2.new(0.5, GAP // 2, 0, 0)

	-- The strip: a status line while counting, the banner once everything is called.
	local strip =
		Kit.box({ Name = "Strip", Size = UDim2.new(1, 0, 0, STRIP_HEIGHT), LayoutOrder = 2, Parent = root })
	local stripHeight = STRIP_HEIGHT
	local callStatus = Kit.text("Polls have closed", {
		Name = "CallStatus",
		Size = UDim2.fromScale(1, 1),
		TextScaled = true,
		TextSize = Kit.size.title,
		Font = Kit.font.bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = strip,
	})
	local bannerPanel = Kit.panel({ Name = "BannerPanel", Visible = false, Parent = strip })
	Kit.list("Vertical", 2).Parent = bannerPanel
	local bannerStroke = Kit.stroke(Kit.colors.accent, 3)
	bannerStroke.Parent = bannerPanel
	local banner = Kit.text("", {
		Name = "Banner",
		Size = UDim2.fromScale(1, 1),
		LayoutOrder = 1,
		TextScaled = true,
		TextSize = Kit.size.title,
		Font = Kit.font.bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = bannerPanel,
	})
	local tiebreak = Kit.text("", {
		Name = "Tiebreak",
		Size = UDim2.new(1, 0, 1, -36),
		LayoutOrder = 2,
		TextScaled = true,
		TextSize = Kit.size.body,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = bannerPanel,
	})

	-- The body: map and side panel.
	local body = Kit.box({ Name = "Body", Size = UDim2.fromScale(1, 1), LayoutOrder = 3, Parent = root })
	local mapBox = Kit.box({ Name = "MapBox", Parent = body })
	map.root.AnchorPoint = Vector2.new(0.5, 0.5)
	map.root.Position = UDim2.fromScale(0.5, 0.5)
	map.root.Parent = mapBox

	local side = Kit.panel({ Name = "Side", Parent = body })
	Kit.text("Calls", {
		Name = "FeedTitle",
		Size = UDim2.new(1, 0, 0, FEED_TITLE - 6),
		TextScaled = true,
		TextSize = Kit.size.heading,
		Font = Kit.font.bold,
		Parent = side,
	})
	local feed = Kit.new("ScrollingFrame", {
		Name = "Feed",
		Position = UDim2.fromOffset(0, FEED_TITLE),
		Size = UDim2.new(1, 0, 1, -(FEED_TITLE + SKIP_HEIGHT + GAP)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = side,
	})
	Kit.list("Vertical", 4).Parent = feed
	local skipButton: TextButton = Kit.button("Skip to results", function()
		onSkip()
	end, {
		Name = "SkipButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, SKIP_HEIGHT),
		Parent = side,
	})

	-- Sizes that depend on the screen shape.
	local function applyLayout(portrait: boolean)
		wasPortrait = portrait
		if portrait then
			mapBox.Size = UDim2.fromScale(1, 0.38)
			mapBox.Position = UDim2.fromScale(0, 0)
			side.Size = UDim2.new(1, 0, 0.62, -GAP)
			side.Position = UDim2.new(0, 0, 0.38, GAP)
		else
			mapBox.Size = UDim2.new(0.66, -GAP // 2, 1, 0)
			mapBox.Position = UDim2.fromScale(0, 0)
			side.Size = UDim2.new(0.34, -GAP // 2, 1, 0)
			side.Position = UDim2.new(0.66, GAP // 2, 0, 0)
		end
		-- The strip grows to fit a tiebreak note, and the body takes what the
		-- counters and strip leave (a list layout cannot say "the rest").
		stripHeight = if hasTiebreak
			then (if portrait then TIEBREAK_HEIGHT_PORTRAIT else TIEBREAK_HEIGHT)
			else STRIP_HEIGHT
		strip.Size = UDim2.new(1, 0, 0, stripHeight)
		body.Size = UDim2.new(1, 0, 1, -(COUNTER_HEIGHT + stripHeight + 2 * GAP))
		for _, counter in { youCounter, themCounter } do
			counter.goal.Visible = not portrait
			counter.name.Size = if portrait then UDim2.fromScale(1, 1) else UDim2.fromScale(0.62, 1)
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
		end
		youCounter.name.Text = `{names[youIndex]} (you)`
		themCounter.name.Text = names[themIndex]
		youCounter.name.TextColor3 = Kit.color(colors[youIndex])
		themCounter.name.TextColor3 = Kit.color(colors[themIndex])
		youCounter.fill.BackgroundColor3 = Kit.color(colors[youIndex])
		themCounter.fill.BackgroundColor3 = Kit.color(colors[themIndex])
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

	local function addLine(k: number)
		local result = results[k]
		local record = StateData.byId[result.state]
		local text: string
		local color = Kit.colors.raised
		if result.winner > 0 then
			text = `{result.state} ({record.ev}) — called for {names[result.winner]} by {string.format(
				"%.1f",
				result.margin
			)}`
			color = tint(colors[result.winner])
		else
			text = `{result.state} ({record.ev}) — dead heat, no electoral votes awarded`
		end
		local line = Kit.text(text, {
			Name = `Line{k}`,
			Size = UDim2.new(1, 0, 0, 30),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 0,
			BackgroundColor3 = color,
			LayoutOrder = -k,
			TextSize = Kit.size.body,
			Parent = feed,
		})
		Kit.corner(6).Parent = line
		Kit.pad(6).Parent = line
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
		bannerPanel.Visible = true
		callStatus.Visible = false
		hasTiebreak = why ~= nil
		applyLayout(wasPortrait)
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
		local function setCounter(counter: Counter, index: number)
			counter.ev.Text = tostring(ev[index])
			counter.states.Text = plural(won[index], "state", "states")
			counter.fill.Size = UDim2.fromScale(math.clamp(ev[index] / TOTAL_EV, 0, 1), 1)
		end
		setCounter(youCounter, youIndex)
		setCounter(themCounter, themIndex)
		paintMap(count)
		if count == #results then
			showBanner(election)
		else
			local nextResult = results[count + 1]
			if nextResult and nextResult.margin < CLOSE_MARGIN then
				callStatus.Text = `Too close to call: {StateData.byId[nextResult.state].name}…`
			else
				callStatus.Text = `{count} of {#results} states called`
			end
		end
	end

	local function updateSkip()
		local seat = if payload then payload.seats[payload.you] else nil
		local waiting = pressed or (seat ~= nil and seat.skip)
		skipButton.Text = if waiting then "Waiting for opponent to skip…" else "Skip to results"
		Kit.setEnabled(skipButton, not waiting)
	end

	onSkip = function()
		if pressed then
			return
		end
		pressed = true
		ctx.net.skip()
		updateSkip()
	end

	local function refresh(now: number)
		if payload == nil then
			return
		end
		build()
		if not built then
			return
		end
		local portrait = ctx.portrait()
		if portrait ~= wasPortrait then
			applyLayout(portrait)
		end
		local position = elapsed(payload.stageStart, payload.deadline, now, totalSlots)
		local count = math.max(shown, called(ends, position))
		if not drawn or count ~= shown then
			render(count)
		end
	end

	applyLayout(wasPortrait)
	updateSkip()
	refresh(ctx.now())

	return {
		update = function(state: Types.State)
			payload = state.payload
			updateSkip()
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
