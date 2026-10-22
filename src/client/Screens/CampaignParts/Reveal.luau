--!strict
-- The reveal panel (UI overhaul §3.4), at the top of the side column while a
-- reveal plays. Its buttons live in the action bar (Skip for the resolve
-- reveal; the debate cannot be skipped).
--
-- Resolve: the week's events one line at a time (the newest REVEAL_LINES), the
-- map still showing last week's polls until "New public polls are in", then a
-- summary of the biggest swings and the projected EV.
-- Debate: one row per topic, revealed every DEBATE_BEAT seconds, each with the
-- two scores as thin bars, the verdict and each side's score split into prep,
-- platform, stat and roll (Shared/UI/Explain); then national support and the
-- callouts (Gaffe!, Sweep!).
--
--   local reveal = Reveal.new(parent, model, order, hooks)
--     hooks.caption(text)   the line over the map
--     hooks.paint(view)     repaint the map from this view's polls
--     hooks.focus(id?)      highlight a state on the map
--   reveal:remember(view)   the last plan-stage view (the polls before a resolve)
--   reveal:render(p)        shows the panel during a reveal
--   reveal:tick(p, now)     starts a new reveal and moves it along
--   reveal:status(p) -> string   the action bar's status line during a reveal
--
-- Element names: RevealPanel, RevealTitle, RevealLines, RevealLine<k>,
-- DebateRows, DebateRow<t>, DebateTopic<t>, DebateBars<t>, DebateParts<t>, RevealSummary.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedFolder = ReplicatedStorage.Shared
local ConfigModule = require(SharedFolder.Sim.Config)
local Events = require(SharedFolder.Sim.Events)
local Explain = require(SharedFolder.UI.Explain)
local PlanDraft = require(SharedFolder.UI.PlanDraft)
local SimState = require(SharedFolder.Sim.State)
local ViewModule = require(SharedFolder.Sim.View)

local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Model = require(script.Parent.Model)

type View = ViewModule.View
type Event = SimState.Event
type Payload = Model.Payload

local Reveal = {}

local REVEAL_TAIL = 2 -- seconds kept at the end of the resolve reveal for the new polls
local REVEAL_BEAT = 0.25 -- fastest pace: one tick of the router
local REVEAL_SLOW = 0.8 -- slowest pace, when there are few events
local REVEAL_LINES = 8 -- event lines listed in the panel
local DEBATE_BEAT = 2 -- seconds per debate topic
local SWINGS = 3 -- biggest poll swings named after the resolve reveal
local SCORE_BAR_H = 6 -- px, one debate score bar

export type Hooks = {
	caption: (text: string) -> (),
	paint: (view: View) -> (),
	focus: (id: string?) -> (),
}

export type Reveal = {
	root: Frame,
	remember: (self: Reveal, view: View) -> (),
	render: (self: Reveal, p: Payload) -> (),
	tick: (self: Reveal, p: Payload, now: number) -> (),
	status: (self: Reveal, p: Payload) -> string,
}

type Item = { caption: string, state: string?, polls: boolean }

-- One line for a resolve event, or nil for events the reveal does not show.
local function eventCaption(config: ConfigModule.Config, view: View, event: Event): string?
	local who = "Someone"
	if event.player == view.you then
		who = "You"
	elseif event.player ~= nil then
		who = Model.candidateName(config, view, event.player)
	end
	local kind = event.kind
	local amount = event.amount or 0
	local where = Model.stateName(event.state)
	local issue = Model.issueName(event.issue)
	if kind == "Rally" then
		return `{who} rallied in {where} on {issue}`
	elseif kind == "Fundraise" then
		return `{who} held a fundraiser in {where}`
	elseif kind == "Media" then
		return `{who} ran an ad in {where} on {issue}`
	elseif kind == "Attack" then
		return `{who} ran an attack ad in {where} on {issue}`
	elseif kind == "Backlash" then
		return `Backlash in {where}: too many attacks cost {who} support`
	elseif kind == "Pivot" then
		return `{who} pivoted the platform to {issue}`
	elseif kind == "Flights" then
		return `{who} took {Model.plural(amount, "flight")}`
	elseif kind == "Raised" then
		return `You raised {Model.money(amount)} from fundraisers`
	elseif kind == "InternalPolls" then
		return `Your {Model.plural(amount, "internal poll")} came back`
	elseif kind == "Polls" then
		return "New public polls are in"
	elseif kind == "Choice" then
		-- The event's Choice answers, revealed with the week (D-027).
		local name = "Event"
		for _, result in view.eventLog do
			local definition = Events.byId[result.id]
			if result.week == view.week - 1 and definition then
				name = definition.name
			end
		end
		return `{name}: {who} {PlanDraft.choiceVerb(event.issue or "C")} ({PlanDraft.points(amount)} points over the states that reacted)`
	end
	return nil
end

local function swingsText(old: View, new: View): string?
	local you, them = new.you, Model.opponentOf(new)
	local swings: { { id: string, delta: number } } = {}
	for i, s in new.states do
		local before = old.states[i]
		if s.poll and before and before.poll then
			local now = (s.poll.support[you] or 0) - (s.poll.support[them] or 0)
			local was = (before.poll.support[you] or 0) - (before.poll.support[them] or 0)
			if now ~= was then
				table.insert(swings, { id = s.id, delta = now - was })
			end
		end
	end
	if #swings == 0 then
		return nil
	end
	table.sort(swings, function(a, b)
		return math.abs(a.delta) > math.abs(b.delta)
	end)
	local parts: { string } = {}
	for k = 1, math.min(SWINGS, #swings) do
		local swing = swings[k]
		local toward = if swing.delta > 0 then "you" else "them"
		table.insert(parts, `{swing.id} {math.abs(swing.delta)} toward {toward}`)
	end
	return `Biggest poll swings: {table.concat(parts, ", ")}.`
end

local function stack(parent: Instance, order: number, name: string, gap: number): Frame
	local frame = Kit.box({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Kit.list("Vertical", gap).Parent = frame
	return frame
end

function Reveal.new(parent: Instance, model: Model.Model, order: number, hooks: Hooks): Reveal
	local config = model.config
	local root = Kit.panel({
		Name = "RevealPanel",
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = parent,
	})
	Kit.list("Vertical", Kit.space.sm).Parent = root
	local title = Kit.heading("", { Name = "RevealTitle", LayoutOrder = 1, Parent = root })

	local lineBox = stack(root, 2, "RevealLines", Kit.space.xs)
	local lines: { TextLabel } = {}
	for k = 1, REVEAL_LINES do
		lines[k] = Kit.text("", {
			Name = `RevealLine{k}`,
			LayoutOrder = k,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Visible = false,
			Parent = lineBox,
		})
	end

	type TopicRow = { row: Frame, label: TextLabel, mine: Frame, theirs: Frame, parts: TextLabel }
	local debateBox = stack(root, 3, "DebateRows", Kit.space.sm)
	local topicRows: { TopicRow } = {}
	for t = 1, config.DEBATE_TOPICS do
		local row = stack(debateBox, t, `DebateRow{t}`, Kit.space.xs)
		row.Visible = false
		local label = Kit.text("", {
			Name = `DebateTopic{t}`,
			LayoutOrder = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = row,
		})
		local bars = Kit.box({
			Name = `DebateBars{t}`,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 2 * SCORE_BAR_H + Kit.space.xs),
			Parent = row,
		})
		local function bar(name: string, y: number): Frame
			local track = Kit.new("Frame", {
				Name = `{name}Track`,
				Position = UDim2.fromOffset(0, y),
				Size = UDim2.new(1, 0, 0, SCORE_BAR_H),
				BackgroundColor3 = Kit.colors.raised,
				BorderSizePixel = 0,
				Parent = bars,
			}) :: Frame
			Kit.corner(Kit.radius.pill).Parent = track
			local fill = Kit.new("Frame", {
				Name = name,
				Size = UDim2.fromScale(0, 1),
				BorderSizePixel = 0,
				Parent = track,
			}) :: Frame
			Kit.corner(Kit.radius.pill).Parent = fill
			return fill
		end
		topicRows[t] = {
			row = row,
			label = label,
			mine = bar("YouScore", 0),
			theirs = bar("ThemScore", SCORE_BAR_H + Kit.space.xs),
			parts = Kit.caption("", { Name = `DebateParts{t}`, LayoutOrder = 3, Parent = row }),
		}
	end
	local summary = Kit.text("", {
		Name = "RevealSummary",
		LayoutOrder = 4,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextColor3 = Kit.colors.accent,
		Parent = root,
	})

	local planView: View? = nil
	local step: number? = nil
	local items: { Item } = {}
	local shown = -1
	local oldView: View? = nil
	local debateShown = 0
	local debateTopics = 0

	local function showLines(texts: { string })
		local first = math.max(1, #texts - REVEAL_LINES + 1)
		for k = 1, REVEAL_LINES do
			local text = texts[first + k - 1]
			lines[k].Text = text or ""
			lines[k].Visible = text ~= nil
		end
	end

	local function startResolve(p: Payload)
		step = p.step
		items = {}
		shown = -1
		showLines({})
		local view = p.view
		for _, event in p.events do
			local text = eventCaption(config, view, event)
			if text then
				table.insert(items, { caption = text, state = event.state, polls = event.kind == "Polls" })
			end
		end
		local old = planView
		oldView = if old and old.week == view.week - 1 then old else nil
		title.Text = `Week {math.max(1, view.week - 1)} results`
		summary.Text = ""
	end

	local function tickResolve(p: Payload, now: number)
		local view = p.view
		local n = #items
		local duration = math.max(REVEAL_BEAT, p.deadline - p.stageStart)
		local window = math.max(REVEAL_BEAT, duration - REVEAL_TAIL)
		local beats = math.max(1, math.floor(window / REVEAL_BEAT))
		local perBeat = math.max(1, math.ceil(n / beats))
		local steps = math.max(1, math.ceil(n / perBeat))
		local interval = math.clamp(window / steps, REVEAL_BEAT, REVEAL_SLOW)
		local elapsed = math.max(0, now - p.stageStart)
		local count = math.min(n, (math.floor(elapsed / interval) + 1) * perBeat)
		if count == shown then
			return
		end
		shown = count
		local texts: { string } = {}
		local pollsIn = oldView == nil
		local focus: string? = nil
		for k = 1, count do
			local item = items[k]
			table.insert(texts, item.caption)
			if item.polls then
				pollsIn = true
			end
			if item.state then
				focus = item.state
			end
		end
		showLines(texts)
		local last = items[count]
		hooks.caption(if last then last.caption else "New public polls are in")
		hooks.paint(if pollsIn then view else oldView :: View)
		-- Once the events are done, the map follows the player's own pick again.
		hooks.focus(if count < n then focus else model.selected)
		if count >= n then
			local old = oldView
			local swings = if old then swingsText(old, view) else nil
			local you, them = view.you, Model.opponentOf(view)
			summary.Text = (swings or "The map shows the new public polls.")
				.. ` Projected EV: you {view.projectedEV[you] or 0} - {view.projectedEV[them] or 0} them.`
		end
	end

	local function startDebate(p: Payload)
		step = p.step
		shown = -1
		debateShown = 0
		showLines({})
		summary.Text = ""
		title.Text = `Debate · week {p.view.week}`
		for _, entry in topicRows do
			entry.row.Visible = false
		end
	end

	local function tickDebate(p: Payload, now: number)
		local view = p.view
		local result = view.debates[#view.debates]
		if result == nil then
			title.Text = "Debate"
			return
		end
		local you, them = view.you, Model.opponentOf(view)
		local topics = #result.topics
		debateTopics = topics
		local elapsed = math.max(0, now - p.stageStart)
		local count = math.min(topics, math.floor(elapsed / DEBATE_BEAT) + 1)
		if count == shown then
			return
		end
		shown = count
		debateShown = count
		local themName = Model.candidateName(config, view, them)
		local best = 1
		for p2 = 1, #view.players do
			for t = 1, topics do
				best = math.max(best, result.scores[p2] and result.scores[p2][t] or 0)
			end
		end
		for t, entry in topicRows do
			local visible = t <= count and t <= topics
			entry.row.Visible = visible
			if visible then
				local winner = result.winners[t]
				local verdict = if winner == you
					then "you win"
					elseif winner == 0 then "tie"
					else `{themName} wins`
				local mine = result.scores[you] and result.scores[you][t] or 0
				local theirs = result.scores[them] and result.scores[them][t] or 0
				entry.label.Text =
					`{Model.issueName(result.topics[t])}: you {mine} - {theirs} them · {verdict}`
				entry.parts.Text = Explain.debateLine(config, view, result, t)
				entry.mine.BackgroundColor3 = Kit.playerColor(view, you)
				entry.theirs.BackgroundColor3 = Kit.playerColor(view, them)
				entry.mine.Size = UDim2.fromScale(math.clamp(mine / best, 0, 1), 1)
				entry.theirs.Size = UDim2.fromScale(math.clamp(theirs / best, 0, 1), 1)
			end
		end
		local latest = topicRows[count]
		hooks.caption(if latest then latest.label.Text else "Debate")
		if count < topics then
			return
		end
		local callouts: { string } = {}
		for p2 = 1, #view.players do
			local who = if p2 == you then "You" else themName
			local sweep = topics > 0
			for t = 1, topics do
				if result.winners[t] ~= p2 then
					sweep = false
				end
				local prep = result.prep[p2]
				local winner = result.winners[t]
				if prep and prep[t] == 0 and winner ~= p2 and winner ~= 0 then
					table.insert(
						callouts,
						`Gaffe! {who} lost {Model.issueName(result.topics[t])} with no prep.`
					)
				end
			end
			if sweep then
				table.insert(
					callouts,
					1,
					`Sweep! {who} won every topic: extra support and momentum in every battleground.`
				)
			end
		end
		summary.Text = `National support: you {PlanDraft.points(result.national[you] or 0)} · them {PlanDraft.points(
			result.national[them] or 0
		)}.` .. (if #callouts > 0 then " " .. table.concat(callouts, " ") else "")
	end

	local reveal: Reveal = {
		root = root,
		remember = function(_self: Reveal, view: View)
			planView = view
		end,
		render = function(_self: Reveal, p: Payload)
			local show = p.reveal == "Resolve" or p.reveal == "Debate"
			root.Visible = show
			lineBox.Visible = p.reveal == "Resolve"
			debateBox.Visible = p.reveal == "Debate"
		end,
		tick = function(_self: Reveal, p: Payload, now: number)
			if p.reveal == "Resolve" then
				if step ~= p.step then
					startResolve(p)
				end
				tickResolve(p, now)
			elseif p.reveal == "Debate" then
				if step ~= p.step then
					startDebate(p)
				end
				tickDebate(p, now)
			end
		end,
		status = function(_self: Reveal, p: Payload): string
			if p.reveal == "Debate" then
				return if debateTopics > 0
					then `Debate · topic {debateShown} of {debateTopics}`
					else "Debate"
			end
			local n = #items
			return if shown >= n then "Results are in" else `Results · {math.max(0, shown)} of {n}`
		end,
	}
	return reveal
end

return Reveal
