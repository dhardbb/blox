--!strict
-- The reveal panel (docs/UI-STYLE.md §4.7), at the top of the side column while
-- a reveal plays. Its buttons live in the action bar (Skip for the resolve
-- reveal; the debate cannot be skipped). The copy is Shared/UI/Words/Reveal.
--
-- Resolve, in three beats (docs/UI-STYLE.md §2.7, D-053), as a running tally
-- (D-063, Shared/UI/RevealSteps). One: "Both plans are in" (RevealIntro) and
-- who goes first, for REVEAL_INTRO seconds; the map and the score still show
-- the week's start. Two: the moves land one step at a time, the trailing
-- player's first (Words.revealFirst on the polls before the week, so the leader
-- answers last). A step is one move (with the still events around it, such as
-- a flight or a fundraiser), followed at once by its effect: its states bump
-- with a ring in the actor's color and a pop, the map's fill and leads move to
-- the running tally (badged with the step's points; FLIP and a ring where the
-- leader changes) and the header's projected votes and race bar count to it.
-- Those per-move numbers are estimates from the polls both players saw (the
-- server never says what one action did; RevealSteps says why), and the panel
-- says so. Three: "Polls settle", the real new polls: the map and the score
-- land exactly on them, a ring on every state the settle flipped, and "What
-- changed" rows (the whole week's real flips and biggest moves) come in one
-- after another. Every cue goes with one of those visuals.
-- The week's events arrive one step at a time, merged into two groups,
-- "Your week" and "{Rex}'s week" (one line per action and state: "Rally in
-- Texas ×2 · Farms & Rural", never the same line twice). Once the new polls are
-- in, "What changed": every state whose poll leader flipped, one bold line each
-- in the new leader's readable color behind a ▲ (your way, green) or ▼
-- (against you, orange), and the biggest moves as filled pills (green ▲ /
-- orange ▼); the map badges only those (flips and the Words.MAP_MARKS biggest
-- moves). The title then says who flipped how many (Words.flipHeadline). A
-- Choice week's stances are a line in each group; their numbers are behind "Why?".
-- The panel's head is an eyebrow ("WEEK 3 RESULTS", "WEEK 4 DEBATE") over the
-- title ("You vs Rex"); each group head has the player's 24 px monogram.
-- Debate: a scoreboard, one row per topic revealed every DEBATE_BEAT seconds
-- (the row fades in, its verdict pill pops, a win plays "debateWin")
-- (topic, "you – them" score in Fredoka, a filled verdict pill) with one short
-- line on what it swung; then the headline ("You won 2 of 3 topics!") lands as a
-- stamp (green for you, orange for them, raised for even) and the points every
-- state got. The dice math and the full state lists are behind "Why?". The map
-- badges the flips and the biggest moves only.
--
--   local reveal = Reveal.new(parent, model, order, hooks)
--     hooks.caption(text)   the line over the map
--     hooks.paint(view)     repaint the map (and the header's score) from this view's polls
--     hooks.focus(id?)      highlight a state on the map
--     hooks.swing(swing?)   badge what moved on the map (nil: the usual marks)
--     hooks.map             the map, for its motion (pulse, ring); optional
--   reveal:remember(view)   the last plan-stage view (the polls before a resolve)
--   reveal:render(p)        shows the panel during a reveal
--   reveal:tick(p, now)     starts a new reveal and moves it along
--   reveal:status(p) -> string   the action bar's status line during a reveal
--
-- Element names: RevealPanel, RevealEyebrow, RevealTitle, RevealIntro, RevealOrder, RevealGroups, YouGroup, YouHead,
-- RevealLine<k> (your lines), ThemGroup, ThemHead, RevealThem<k>, RevealChanged,
-- RevealFlipRow<k> (its Mark and RevealFlip<k>), RevealFlipMore, RevealMoves, RevealMove<k>, RevealNote, RevealSummary,
-- WhyButton, RevealWhy (details), RevealChoice; DebateRows, DebateHead,
-- DebateRow<t>, DebateTopic<t>, DebateScore<t>, DebateVerdict<t>,
-- DebateSwing<t>, DebateGaffe<t>, DebateHeadlineBox (its Stamp's label is
-- DebateHeadline), DebateOther, DebateParts<t>,
-- DebateDetail<t>, DebateCallouts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedFolder = ReplicatedStorage.Shared
local Swing = require(SharedFolder.UI.Swing)
local Explain = require(SharedFolder.UI.Explain)
local SimState = require(SharedFolder.Sim.State)
local RevealSteps = require(SharedFolder.UI.RevealSteps)
local ViewModule = require(SharedFolder.Sim.View)
local Words = require(SharedFolder.UI.Words.Reveal)

local Audio = require(script.Parent.Parent.Parent.UI.Audio)
local CoachTip = require(script.Parent.Parent.Parent.UI.CoachTip)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.Parent.Parent.Map.MapInterface)
local Model = require(script.Parent.Model)
local Motion = require(script.Parent.Parent.Parent.UI.Motion)

type View = ViewModule.View
type Event = SimState.Event
type Payload = Model.Payload

local Reveal = {}

local REVEAL_TAIL = 2 -- seconds kept at the end of the resolve reveal for the new polls
local REVEAL_INTRO = 0.5 -- seconds of "Both plans are in" before the first action lands
local LAND_MAX = 3 -- most states one beat bumps on the map (a catch-up beat can hold many)
local THEIR_PITCH = 0.94 -- the opponent's actions land a little lower than yours
local REVEAL_BEAT = 0.25 -- fastest pace: one tick of the router
local REVEAL_SLOW = 0.8 -- slowest pace, when there are few steps
local GROUP_LINES = 6 -- lines per side before "+N more"
local DEBATE_BEAT = 2 -- seconds per debate topic
local PORTRAIT = 24 -- px, a player's monogram in a group head
local MARK_W = 20 -- px, the ▲/▼ column of a "What changed" row
local ROW_H = 28 -- px, one scoreboard row
local SCORE_W = 84 -- px, the scoreboard's score column
local VERDICT_W = 96 -- px, the scoreboard's verdict column
local STAMP_SLACK = 24 -- px over the stamp's height in its row: room for its tilt
local STAMP_INSET = 6 -- px the debate stamp keeps from each side (its tilted corners stay in)

export type Hooks = {
	caption: (text: string) -> (),
	paint: (view: View) -> (),
	focus: (id: string?) -> (),
	swing: (swing: Model.RevealSwing?) -> (),
	map: MapInterface.Map?,
}

export type Reveal = {
	root: Frame,
	remember: (self: Reveal, view: View) -> (),
	render: (self: Reveal, p: Payload) -> (),
	tick: (self: Reveal, p: Payload, now: number) -> (),
	status: (self: Reveal, p: Payload) -> string,
}

local function grows(props: { [string]: any }): { [string]: any }
	props.Size = UDim2.fromScale(1, 0)
	props.AutomaticSize = Enum.AutomaticSize.Y
	return props
end

-- A group head: the player's monogram (filled in by `portrait`) and "Your week".
local function groupHead(parent: Instance, name: string): (Frame, TextLabel)
	local row = Kit.box({
		Name = name,
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, PORTRAIT + 2),
		Parent = parent,
	})
	local slot = Kit.box({
		Name = "Portrait",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(PORTRAIT, PORTRAIT),
		Parent = row,
	})
	local label = Kit.text("", {
		Name = "Label",
		Position = UDim2.fromOffset(PORTRAIT + Kit.space.sm, 0),
		Size = UDim2.new(1, -(PORTRAIT + Kit.space.sm), 1, 0),
		Font = Kit.font.bold,
		Parent = row,
	})
	return slot, label
end

-- Puts `name`'s monogram in `color` into a group head's slot (once per name and color).
local function portrait(slot: Frame, name: string, color: Color3)
	local rgb = Kit.rgb(color)
	local key = `{name}|{rgb.r},{rgb.g},{rgb.b}`
	if slot:GetAttribute("For") == key then
		return
	end
	slot:SetAttribute("For", key)
	for _, child in slot:GetChildren() do
		child:Destroy()
	end
	Kit.monogram(name, color, PORTRAIT).Parent = slot
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
	-- Lit like a card (the elevation of a moment), not a flat panel.
	Kit.depth(root, Kit.colors.surfaceTop, Kit.colors.surface)
	Kit.bevel(root)
	Kit.list("Vertical", Kit.space.md).Parent = root
	local headBox = Kit.stack({ Name = "RevealHead", LayoutOrder = 1, Parent = root }, "Vertical", 2)
	local eyebrow = Kit.eyebrow("", { Name = "RevealEyebrow", LayoutOrder = 1, Parent = headBox })
	local title = Kit.heading("", { Name = "RevealTitle", LayoutOrder = 2, Parent = headBox })

	-- Beat one: both plans are in, and who goes first.
	local intro =
		Kit.stack({ Name = "RevealIntroBox", LayoutOrder = 2, Visible = false, Parent = root }, "Vertical", 2)
	local introLine = Kit.text("Both plans are in", {
		Name = "RevealIntro",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, Kit.size.heading + 8),
		Font = Kit.font.display,
		TextSize = Kit.size.heading,
		TextColor3 = Kit.colors.text,
		Parent = intro,
	})
	local orderLine = Kit.caption("", { Name = "RevealOrder", LayoutOrder = 2, Parent = intro })

	-- ------------------------------------------------------------ resolve

	local groups =
		Kit.stack({ Name = "RevealGroups", LayoutOrder = 3, Parent = root }, "Vertical", Kit.space.md)
	local function group(
		name: string,
		order2: number,
		prefix: string
	): (Frame, Frame, TextLabel, { TextLabel })
		local box =
			Kit.stack({ Name = name, LayoutOrder = order2, Parent = groups }, "Vertical", Kit.space.xs)
		local dot, head = groupHead(box, if prefix == "RevealLine" then "YouHead" else "ThemHead")
		local lines: { TextLabel } = {}
		for k = 1, GROUP_LINES do
			lines[k] =
				Kit.text("", grows({ Name = `{prefix}{k}`, LayoutOrder = k, Visible = false, Parent = box }))
		end
		return box, dot, head, lines
	end
	local youGroup, youDot, youHead, youLines = group("YouGroup", 1, "RevealLine")
	local themGroup, themDot, themHead, themLines = group("ThemGroup", 2, "RevealThem")

	local changed =
		Kit.stack({ Name = "RevealChanged", LayoutOrder = 4, Parent = root }, "Vertical", Kit.space.xs)
	Kit.text(
		"What changed",
		{ Name = "ChangedHead", LayoutOrder = 0, Font = Kit.font.bold, Parent = changed }
	)
	-- One row per flip: the ▲/▼ in its own column (green or orange), the line
	-- in the new leader's readable color.
	local flipRows: { Frame } = {}
	local flipMarks: { TextLabel } = {}
	local flipLines: { TextLabel } = {}
	for k = 1, Words.FLIP_LINES do
		local row = Kit.box({
			Name = `RevealFlipRow{k}`,
			LayoutOrder = k,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Visible = false,
			Parent = changed,
		})
		flipRows[k] = row
		flipMarks[k] = Kit.text("", {
			Name = "Mark",
			Size = UDim2.fromOffset(MARK_W, Kit.size.body + 6),
			Font = Kit.font.bold,
			Parent = row,
		})
		flipLines[k] = Kit.text("", {
			Name = `RevealFlip{k}`,
			Position = UDim2.fromOffset(MARK_W, 0),
			Size = UDim2.new(1, -MARK_W, 0, Kit.size.body + 6),
			AutomaticSize = Enum.AutomaticSize.Y,
			Font = Kit.font.bold,
			Parent = row,
		})
	end
	local flipMore = Kit.caption("", {
		Name = "RevealFlipMore",
		LayoutOrder = Words.FLIP_LINES + 1,
		Visible = false,
		Parent = changed,
	})
	local movesRow = Kit.stack({
		Name = "RevealMoves",
		LayoutOrder = Words.FLIP_LINES + 2,
		Size = UDim2.fromScale(1, 0),
		Parent = changed,
	}, "Horizontal", Kit.space.xs)
	local movePills: { TextLabel } = {}
	for k = 1, Words.MOVE_PILLS do
		movePills[k] = Kit.pill(
			"",
			"text",
			{ Name = `RevealMove{k}`, LayoutOrder = k, Visible = false, Parent = movesRow }
		)
	end

	-- ------------------------------------------------------------ debate

	type TopicRow = {
		row: Frame,
		topic: TextLabel,
		score: TextLabel,
		verdict: TextLabel,
		swing: TextLabel,
		gaffe: TextLabel,
	}
	local debateBox =
		Kit.stack({ Name = "DebateRows", LayoutOrder = 3, Parent = root }, "Vertical", Kit.space.sm)
	local headRow = Kit.box({
		Name = "DebateHead",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, Kit.size.caption + 4),
		Parent = debateBox,
	})
	Kit.caption("Topic", {
		Name = "TopicHead",
		Size = UDim2.new(1, -(SCORE_W + VERDICT_W), 1, 0),
		AutomaticSize = Enum.AutomaticSize.None,
		Parent = headRow,
	})
	local scoreHead = Kit.caption("", {
		Name = "ScoreHead",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -VERDICT_W, 0, 0),
		Size = UDim2.new(0, SCORE_W, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = headRow,
	})
	local topicRows: { TopicRow } = {}
	for t = 1, config.DEBATE_TOPICS do
		local block = Kit.stack(
			{ Name = `DebateRow{t}`, LayoutOrder = t, Visible = false, Parent = debateBox },
			"Vertical",
			2
		)
		local line =
			Kit.box({ Name = "Score", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, ROW_H), Parent = block })
		local topic = Kit.text("", {
			Name = `DebateTopic{t}`,
			Size = UDim2.new(1, -(SCORE_W + VERDICT_W), 1, 0),
			Font = Kit.font.bold,
			TextScaled = true,
			Parent = line,
		})
		local score = Kit.text("", {
			Name = `DebateScore{t}`,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -VERDICT_W, 0, 0),
			Size = UDim2.new(0, SCORE_W, 1, 0),
			Font = Kit.font.display,
			TextSize = Kit.size.heading,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = line,
		})
		local verdictBox = Kit.box({
			Name = "VerdictBox",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, VERDICT_W, 1, 0),
			Parent = line,
		})
		local verdict = Kit.pill("", "text", {
			Name = `DebateVerdict{t}`,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Parent = verdictBox,
		})
		topicRows[t] = {
			row = block,
			topic = topic,
			score = score,
			verdict = verdict,
			swing = Kit.caption("", { Name = `DebateSwing{t}`, LayoutOrder = 2, Parent = block }),
			gaffe = Kit.caption("", {
				Name = `DebateGaffe{t}`,
				LayoutOrder = 3,
				TextColor3 = Kit.colors.bad,
				Visible = false,
				Parent = block,
			}),
		}
	end
	-- The headline's row; its stamp is made when the last topic is in.
	local headlineBox = Kit.box({
		Name = "DebateHeadlineBox",
		LayoutOrder = config.DEBATE_TOPICS + 1,
		Size = UDim2.new(1, 0, 0, Kit.size.heading + 28 + STAMP_SLACK),
		Visible = false,
		Parent = debateBox,
	})
	local headlineText = "" -- what the stamp in headlineBox says
	local debateOther = Kit.text(
		"",
		grows({
			Name = "DebateOther",
			LayoutOrder = config.DEBATE_TOPICS + 2,
			Font = Kit.font.bold,
			Visible = false,
			Parent = debateBox,
		})
	)

	-- ------------------------------------------------------------ summary and Why?

	-- While the moves land: their points on the map are estimates (D-063).
	local note = Kit.caption("", { Name = "RevealNote", LayoutOrder = 5, Visible = false, Parent = root })
	local summary = Kit.caption("", { Name = "RevealSummary", LayoutOrder = 6, Parent = root })

	local whyOpen = false
	local whyButton: TextButton
	local why = Kit.details(
		Kit.stack(
			{ Name = "RevealWhy", LayoutOrder = 8, Visible = false, Parent = root },
			"Vertical",
			Kit.space.xs
		)
	)
	whyButton = Kit.button("Why? +", function()
		whyOpen = not whyOpen
		why.Visible = whyOpen
		whyButton.Text = if whyOpen then `Why? {Kit.glyph.minus}` else "Why? +"
	end, {
		variant = "ghost",
		Name = "WhyButton",
		LayoutOrder = 7,
		Size = UDim2.fromOffset(120, Kit.MIN_TOUCH),
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		Parent = root,
	})
	local choiceText = Kit.caption(
		"",
		{ Name = "RevealChoice", LayoutOrder = 1, TextColor3 = Kit.colors.text, Parent = why }
	)
	local debateWhy =
		Kit.stack({ Name = "DebateWhy", LayoutOrder = 2, Parent = why }, "Vertical", Kit.space.xs)
	local partLines: { TextLabel } = {}
	local detailLines: { TextLabel } = {}
	for t = 1, config.DEBATE_TOPICS do
		detailLines[t] = Kit.caption("", {
			Name = `DebateDetail{t}`,
			LayoutOrder = 2 * t - 1,
			TextColor3 = Kit.colors.text,
			Parent = debateWhy,
		})
		partLines[t] = Kit.caption("", { Name = `DebateParts{t}`, LayoutOrder = 2 * t, Parent = debateWhy })
	end
	local callouts = Kit.caption("", {
		Name = "DebateCallouts",
		LayoutOrder = 2 * config.DEBATE_TOPICS + 1,
		TextColor3 = Kit.colors.text,
		Parent = debateWhy,
	})

	local function setWhy(available: boolean)
		whyButton.Visible = available
		if not available then
			whyOpen = false
			why.Visible = false
			whyButton.Text = "Why? +"
		end
	end

	-- ------------------------------------------------------------ state

	local planView: View? = nil
	local step: number? = nil
	local tally: RevealSteps.Tally? = nil
	-- Steps shown: -2 before the first tick, -1 during "Both plans are in".
	local shown = -2
	local flipsRung = false -- the new polls' flips have had their rings
	local choiceRung = false -- the stance's flips have had their rings (no week start to tally from)
	local oldView: View? = nil
	local debateShown = 0
	local debateTopics = 0
	local tipShown = false

	local function themName(view: View): string
		return Model.firstName(config, view, Model.opponentOf(view))
	end

	-- A ring out of each flipped state, in the new leader's color (muted for a
	-- tie), and one "flip" for the lot.
	local function ringFlips(view: View, flips: { Swing.Flip })
		if #flips == 0 then
			return
		end
		local map = hooks.map
		if map then
			for _, flip in flips do
				local color = if flip.to > 0 then Kit.playerColor(view, flip.to) else Kit.colors.muted
				map:ring(flip.state, color)
			end
		end
		Audio.play("flip")
	end

	-- Beat two: the states of the newly shown steps bump on the map, a ring in
	-- the actor's color, and the newest one's pop sound (yours a little higher).
	local function land(view: View, steps: { RevealSteps.Step }, from: number, to: number)
		local landed: { Event } = {}
		for k = math.max(1, from), to do
			local entry = steps[k]
			if entry and entry.kind == "Move" then
				for _, event in entry.events do
					if event.state ~= nil then
						table.insert(landed, event)
					end
				end
			end
		end
		if #landed == 0 then
			return
		end
		local map = hooks.map
		if map then
			for k = math.max(1, #landed - LAND_MAX + 1), #landed do
				local event = landed[k]
				local actor = event.player or view.you
				map:pulse(event.state :: string, Kit.playerColor(view, actor))
			end
		end
		local last = landed[#landed]
		local mine = last.player == nil or last.player == view.you
		Audio.play("planAdd", { pitch = if mine then 1 else THEIR_PITCH })
	end

	-- Beat three: "What changed" rows come in one after another.
	local function enterChanged()
		local list: { GuiObject } = {}
		for _, row in flipRows do
			if row.Visible then
				table.insert(list, row)
			end
		end
		if flipMore.Visible then
			table.insert(list, flipMore)
		end
		for _, pill in movePills do
			if pill.Visible then
				table.insert(list, pill)
			end
		end
		Motion.stagger(list, function(item: GuiObject, _index: number, delay: number)
			if item:IsA("TextLabel") and item.Parent == movesRow then
				Motion.pop(item, nil, delay)
			else
				Motion.enter(item, nil, delay)
			end
		end)
	end

	local function fillLines(labels: { TextLabel }, texts: { string })
		for k, label in labels do
			local text = texts[k]
			if k == #labels and #texts > #labels then
				text = `+{#texts - #labels + 1} more`
			end
			label.Text = text or ""
			label.Visible = text ~= nil
		end
	end

	local function showFlips(view: View, flips: { Swing.Flip })
		local them = themName(view)
		for k, label in flipLines do
			local flip = flips[k]
			flipRows[k].Visible = flip ~= nil
			if flip then
				local up = Words.flipTone(view, flip) == "good"
				label.Text = Words.flipLine(view, flip, them)
				-- Ownership changed: the line is the new leader's color; the mark says
				-- whether that was good for you.
				label.TextColor3 = if flip.to > 0 then Kit.playerText(view, flip.to) else Kit.colors.text
				flipMarks[k].Text = Words.mark(up)
				flipMarks[k].TextColor3 = if up then Kit.colors.good else Kit.colors.loss
			end
		end
		local extra = #flips - #flipLines
		flipMore.Text = if extra > 0 then `+{extra} more states changed leader` else ""
		flipMore.Visible = extra > 0
	end

	local function showMoves(view: View, moves: { Words.Move })
		local them = themName(view)
		for k, pill in movePills do
			local move = moves[k]
			pill.Visible = move ~= nil
			if move then
				local up = move.delta > 0
				pill.Text = Words.marked(Words.movePill(move, them), up)
				Kit.paintPill(pill, if up then "good" else "loss", true)
			end
		end
		movesRow.Visible = #moves > 0
	end

	local function maybeTip()
		if tipShown then
			return
		end
		tipShown = true
		CoachTip.show(root, { id = "reveal.week", order = 2 })
	end

	local function startResolve(p: Payload)
		step = p.step
		shown = -2
		flipsRung = false
		choiceRung = false
		local view = p.view
		local old = planView
		oldView = if old and old.week == view.week - 1 then old else nil
		-- The trailing player's moves first, from the polls before the week.
		local built = RevealSteps.build(config, oldView, view, p.events)
		tally = built
		orderLine.Text = Words.orderLine(view, built.first, built.trails, themName(view))
		hooks.swing(nil)
		Audio.play("whoosh")
		eyebrow.Text = string.upper(`Week {math.max(1, view.week - 1)} results`)
		title.Text = `You vs {themName(view)}`
		youHead.Text = "Your week"
		themHead.Text = `{themName(view)}'s week`
		local them = Model.opponentOf(view)
		portrait(youDot, Model.candidateName(config, view, view.you), Kit.playerColor(view, view.you))
		portrait(themDot, Model.candidateName(config, view, them), Kit.playerColor(view, them))
		changed.Visible = false
		summary.Text = ""
		note.Text = Words.ESTIMATE_NOTE
		note.Visible = false
		choiceText.Text = ""
		setWhy(false)
		maybeTip()
	end

	-- The header's one line for a step: who and what ("You: Rally in Texas";
	-- the panel has the issue), or the settle.
	local function stepCaption(view: View, entry: RevealSteps.Step): string
		if entry.kind == "Settle" then
			return Words.SETTLE
		end
		local event = RevealSteps.lead(entry)
		if event == nil then
			return ""
		end
		local who = if event.player == nil or event.player == view.you then "You" else themName(view)
		local one = Words.group(view, { event })
		local text = one.mine[1] or one.theirs[1]
		local short = if text then string.match(text, "^(.-) · ") or text else nil
		return if short then `{who}: {short}` else ""
	end

	local function tickResolve(p: Payload, now: number)
		local view = p.view
		local current = tally
		if current == nil then
			return
		end
		local steps = current.steps
		local n = #steps
		local duration = math.max(REVEAL_BEAT, p.deadline - p.stageStart)
		local window = math.max(REVEAL_BEAT, duration - REVEAL_TAIL - REVEAL_INTRO)
		local beats = math.max(1, math.floor(window / REVEAL_BEAT))
		local perBeat = math.max(1, math.ceil(n / beats))
		local beatCount = math.max(1, math.ceil(n / perBeat))
		local interval = math.clamp(window / beatCount, REVEAL_BEAT, REVEAL_SLOW)
		local elapsed = now - p.stageStart - REVEAL_INTRO
		local count = if elapsed < 0 then -1 else math.min(n, (math.floor(elapsed / interval) + 1) * perBeat)
		if count == shown then
			return
		end
		local before = shown
		shown = count

		-- Beat one: both plans are in; the map and the score still show the week's start.
		if count < 0 then
			intro.Visible = true
			groups.Visible = false
			changed.Visible = false
			Motion.pop(introLine)
			Motion.enter(orderLine, 4)
			hooks.caption("Both plans are in")
			hooks.paint(RevealSteps.viewAt(current, 0))
			return
		end
		intro.Visible = false
		groups.Visible = true
		land(view, steps, before + 1, count)
		local events = RevealSteps.eventsUpTo(current, count)
		local choiceShown = false
		local focus: string? = nil
		for _, event in events do
			if event.kind == "Choice" then
				choiceShown = true
			end
		end
		local latest = steps[count]
		local lead = if latest then RevealSteps.lead(latest) else nil
		if latest and lead and latest.kind == "Move" then
			focus = lead.state
		end
		local grouped = Words.group(view, events)
		fillLines(youLines, grouped.mine)
		fillLines(themLines, grouped.theirs)
		youGroup.Visible = true
		themGroup.Visible = #grouped.theirs > 0

		-- The stances: their numbers behind Why?. Their points land on the map
		-- with their steps; with no week start to tally from, the map badges
		-- what the stances asked for (public) instead.
		local entry = if choiceShown then Swing.lastChoice(view) else nil
		local choiceFlips: { Swing.Flip } = {}
		if entry then
			choiceText.Text = table.concat(Swing.choiceLines(config, view, entry), "\n")
			setWhy(true)
			if oldView == nil then
				choiceFlips = Swing.flips(entry.flips)
				hooks.swing({
					net = Words.topMarks(Swing.net(entry.moves, view), choiceFlips),
					flips = choiceFlips,
				})
				if not choiceRung then
					choiceRung = true
					ringFlips(view, choiceFlips)
				end
			end
		end

		-- The newest step's effect: its points and flips on the map, a ring on
		-- every flip the newly shown steps made, the map and the score at the tally.
		local rings: { Swing.Flip } = {}
		for k = math.max(1, before + 1), count do
			local entry2 = steps[k]
			if entry2 and entry2.kind == "Move" then
				for _, flip in entry2.flips do
					table.insert(rings, flip)
				end
			end
		end
		if oldView and latest and latest.kind == "Move" then
			hooks.swing({ net = Words.topMarks(latest.net, latest.flips), flips = latest.flips })
		end
		ringFlips(view, rings)
		if latest then
			hooks.caption(stepCaption(view, latest))
		end
		hooks.paint(RevealSteps.viewAt(current, count))
		-- Once the moves are done, the map follows the player's own pick again.
		hooks.focus(if count < n then focus else model.selected)
		note.Visible = oldView ~= nil and count < n
		if count < n then
			return
		end

		-- What changed: the week's flips and biggest moves on the new public polls.
		local old = oldView
		local flips: { Swing.Flip } = choiceFlips
		local moves: { Words.Move } = {}
		if old then
			local changes = Words.pollChanges(old, view)
			flips, moves = changes.flips, changes.moves
			local net: { [string]: number } = {}
			for _, move in moves do
				net[move.state] = move.delta
			end
			hooks.swing({ net = Words.topMarks(net, flips), flips = flips })
			hooks.paint(view)
		end
		showFlips(view, flips)
		showMoves(view, moves)
		changed.Visible = #flips > 0 or #moves > 0
		title.Text = Words.flipHeadline(view, flips, themName(view))
		if not flipsRung then
			-- Beat three, once: rings on what the settle flipped.
			flipsRung = true
			if old then
				ringFlips(view, steps[n].flips)
			end
			Motion.pop(title)
			enterChanged()
		end
		summary.Text = Words.settleLine(old ~= nil, #flips > 0)
	end

	local function startDebate(p: Payload)
		step = p.step
		shown = -1
		intro.Visible = false
		debateShown = 0
		summary.Text = ""
		local view = p.view
		eyebrow.Text = string.upper(`Week {view.week} debate`)
		title.Text = `You vs {themName(view)}`
		scoreHead.Text = `You – {themName(view)}`
		for _, entry in topicRows do
			entry.row.Visible = false
		end
		headlineBox.Visible = false
		debateOther.Visible = false
		choiceText.Text = ""
		callouts.Text = ""
		setWhy(false)
		hooks.swing(nil)
	end

	-- The debate's headline as a stamp in its tone's color (green: you won it;
	-- orange: they did; raised: even), slammed in once.
	local function stampHeadline(text: string, tone: Words.Tone)
		for _, child in headlineBox:GetChildren() do
			child:Destroy()
		end
		local color = if tone == "good"
			then Kit.colors.good
			elseif tone == "loss" or tone == "bad" then Kit.colors.loss
			else Kit.colors.raisedHover
		local stamp = Kit.stamp(text, color, {
			size = Kit.size.heading,
			Name = "Stamp",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
		-- As wide as the words need, never wider than the panel (the label scales).
		local natural = stamp.Size
		stamp.Size = UDim2.new(1, -2 * STAMP_INSET, 0, natural.Y.Offset)
		Kit.new(
			"UISizeConstraint",
			{ MaxSize = Vector2.new(natural.X.Offset, natural.Y.Offset), Parent = stamp }
		)
		local label = (stamp:FindFirstChild("Plate") :: Frame):FindFirstChild("Label") :: TextLabel
		label.Name = "DebateHeadline"
		label.TextTransparency = 0 -- the resting value Motion.stamp's fade ends on
		stamp.Parent = headlineBox
		Motion.stamp(stamp)
	end

	local function tickDebate(p: Payload, now: number)
		local view = p.view
		local result = view.debates[#view.debates]
		if result == nil then
			eyebrow.Text = "DEBATE"
			return
		end
		local you, them = view.you, Model.opponentOf(view)
		local rival = themName(view)
		local topics = #result.topics
		debateTopics = topics
		local elapsed = math.max(0, now - p.stageStart)
		local count = math.min(topics, math.floor(elapsed / DEBATE_BEAT) + 1)
		if count == shown then
			return
		end
		local before = math.max(0, shown)
		shown = count
		debateShown = count
		for t, entry in topicRows do
			local visible = t <= count and t <= topics
			entry.row.Visible = visible
			if visible then
				local verdict, tone = Words.verdict(view, result.winners[t] or 0, rival)
				local mine = result.scores[you] and result.scores[you][t] or 0
				local theirs = result.scores[them] and result.scores[them][t] or 0
				entry.topic.Text = Model.issueName(result.topics[t])
				entry.score.Text = `{mine} – {theirs}`
				entry.verdict.Text = verdict
				-- A win or a loss is a filled pill (green, orange); a tie stays plain (D-056).
				Kit.paintPill(entry.verdict, tone :: Kit.Tone, tone ~= "muted")
				entry.swing.Text = Words.topicLine(config, view, result, t, rival)
				local moved = Swing.debateTopic(config, view, result, t)
				entry.gaffe.Text = table.concat(moved.gaffeLines, "\n")
				entry.gaffe.Visible = #moved.gaffeLines > 0
				detailLines[t].Text = moved.line
				partLines[t].Text = Explain.debateLine(config, view, result, t)
			else
				detailLines[t].Text = ""
				partLines[t].Text = ""
			end
		end
		setWhy(true)
		-- The new rows come in: the row fades in, its verdict pops; the newest
		-- one's sound says who won it.
		for t = before + 1, count do
			local entry = topicRows[t]
			if entry then
				local delay = (t - before - 1) * Motion.STAGGER_STEP
				Motion.enter(entry.topic, 4, delay)
				Motion.enter(entry.score, 4, delay)
				Motion.enter(entry.swing, 4, delay)
				Motion.pop(entry.verdict, 0.6, delay)
			end
		end
		if count > before then
			local winner = result.winners[count]
			if winner == you then
				Audio.play("debateWin")
			else
				Audio.play("select")
			end
		end
		-- The map badges the flips so far and the biggest moves, nothing else.
		local flips: { Swing.Flip } = {}
		for t = 1, count do
			for _, flip in Swing.debateTopic(config, view, result, t).flips do
				table.insert(flips, flip)
			end
		end
		local other: { Swing.Flip } = if count >= topics then Swing.debateOther(view, result) else {}
		for _, flip in other do
			table.insert(flips, flip)
		end
		local net = Swing.debateNet(config, view, result, count)
		hooks.swing({ net = Words.topMarks(net, flips), flips = flips })
		hooks.paint(view)
		local latest = topicRows[count]
		hooks.caption(
			if latest then `{latest.topic.Text}: {latest.verdict.Text} {latest.score.Text}` else "Debate"
		)
		if count < topics then
			return
		end
		local text, tone = Words.debateHeadline(view, result, rival)
		if text ~= headlineText or not headlineBox.Visible then
			headlineText = text
			stampHeadline(text, tone :: Words.Tone)
		end
		headlineBox.Visible = true
		if #other > 0 then
			local phrases: { string } = {}
			for _, flip in other do
				table.insert(phrases, Words.flipLine(view, flip, rival))
			end
			debateOther.Text = `Also: {table.concat(phrases, ", ")}`
			debateOther.Visible = true
		end
		local notes: { string } = {}
		for p2 = 1, #view.players do
			local who = if p2 == you then "You" else rival
			for t = 1, topics do
				local prep = result.prep[p2]
				local winner = result.winners[t]
				if prep and prep[t] == 0 and winner ~= p2 and winner ~= 0 then
					table.insert(notes, `{who} lost {Model.issueName(result.topics[t])} with no prep.`)
				end
			end
		end
		callouts.Text = table.concat(notes, "\n")
		summary.Text = Words.everyState(view, result, rival)
	end

	local reveal: Reveal = {
		root = root,
		remember = function(_self: Reveal, view: View)
			planView = view
		end,
		render = function(_self: Reveal, p: Payload)
			local show = p.reveal == "Resolve" or p.reveal == "Debate"
			root.Visible = show
			groups.Visible = p.reveal == "Resolve" and shown >= 0
			intro.Visible = p.reveal == "Resolve" and shown == -1
			debateBox.Visible = p.reveal == "Debate"
			debateWhy.Visible = p.reveal == "Debate"
			choiceText.Visible = p.reveal == "Resolve" and choiceText.Text ~= ""
			if p.reveal ~= "Resolve" then
				changed.Visible = false
				note.Visible = false
			end
		end,
		tick = function(_self: Reveal, p: Payload, now: number)
			if p.reveal == "Resolve" then
				if step ~= p.step then
					startResolve(p)
				end
				tickResolve(p, now)
				choiceText.Visible = choiceText.Text ~= ""
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
			local n = if tally then #(tally :: RevealSteps.Tally).steps else 0
			if shown < 0 then
				return "Both plans are in"
			end
			return if shown >= n then "Results are in" else `Results · {shown} of {n}`
		end,
	}
	return reveal
end

return Reveal
