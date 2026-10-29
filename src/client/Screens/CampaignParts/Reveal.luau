--!strict
-- The reveal panel (docs/UI-STYLE.md §4.7), at the top of the side column while
-- the week's reveal plays. Its buttons live in the action bar (Skip). The copy
-- is Shared/UI/Words/Reveal. Debates have their own screen (Screens/Debate, D-072).
--
-- Resolve, in three beats (docs/UI-STYLE.md §2.7, D-053), as a running tally
-- (D-066, Shared/UI/RevealSteps). One: "Both plans are in" (RevealIntro) and
-- who goes first, for REVEAL_INTRO seconds; the map and the score still show
-- the week's start. Two: the moves land one step at a time, the trailing
-- player's first (Words.revealFirst on the polls before the week, so the leader
-- answers last). A step is one move (with the still events around it, such as
-- a flight or a fundraiser), followed at once by its effect: its states bump
-- with a ring in the actor's color and a pop, the map's fill and leads move to
-- the running tally, every touched state shows its points toward you
-- (SwingMarks.step: your color up, orange down), a leader change says FLIP,
-- flashes in the new leader's color and rides on the header line ("Buster: Rally ·
-- NY → Buster +28"), and the header's projected votes and race bar count to it.
-- Those per-move numbers are estimates from the polls both players saw (the
-- server never says what one action did; RevealSteps says why); one line behind
-- Why? says so. Three: "New polls are in", the real new polls, with their own
-- look: a stamp, "Polls shifted 4 states", a pulse sweeping the map west to
-- east, the header line in the display font. The map and the score land
-- exactly on them, a ring on every state they flipped, and "What changed" rows
-- (the whole week's real flips and biggest moves) come in one after another.
-- Every cue goes with one of those visuals.
-- The week's events arrive one step at a time, merged into two groups,
-- "Your week" and "{Buster}'s week" (one line per action and state: "Rally in
-- Texas ×2 · Farms & Rural", never the same line twice). Once the new polls are
-- in, "What changed": every state whose poll leader flipped, one bold line each
-- in the new leader's readable color behind a ▲ (your way, green) or ▼
-- (against you, orange), and the biggest moves as filled pills (green ▲ /
-- orange ▼); the map badges only those (flips and the Words.MAP_MARKS biggest
-- moves). The title then says who flipped how many (Words.flipHeadline), and
-- the line under it the week's net in projected votes, the header's score
-- before and after ("Projection: 310 → 324 (+14 for you)", M4); with no leader
-- change, how the close states moved instead ("You lost ground in 3 close
-- states", the map's Close filter). It shows only once the new polls are in,
-- when the header's score is the new polls' (D-066). A
-- Choice week's stances are a line in each group; their numbers are behind "Why?".
-- The panel's head is an eyebrow ("WEEK 3 RESULTS") over the title ("You vs
-- Buster"); each group head has the player's 32 px portrait (D-068).
--
--   local reveal = Reveal.new(parent, model, order, hooks)
--     hooks.caption(text, polls?)   the header's now line (polls: the "New polls are in" step)
--     hooks.paint(view)     repaint the map (and the header's score) from this view's polls
--     hooks.focus(id?)      highlight a state on the map
--     hooks.swing(swing?)   badge what moved on the map (nil: the usual marks)
--     hooks.map             the map, for its motion (pulse, ring); optional
--   reveal:remember(view)   the last plan-stage view (the polls before a resolve)
--   reveal:render(p)        shows the panel during a reveal
--   reveal:tick(p, now)     starts a new reveal and moves it along
--   reveal:status(p) -> string   the action bar's status line during a reveal
--
-- Element names: RevealPanel, RevealEyebrow, RevealTitle, RevealTally, RevealIntro, RevealOrder, RevealGroups, YouGroup, YouHead,
-- RevealLine<k> (your lines), ThemGroup, ThemHead, RevealThem<k>, RevealChanged,
-- RevealFlipRow<k> (its Mark and RevealFlip<k>), RevealFlipMore, RevealMoves, RevealMove<k>, RevealPolls (its stamp's label is
-- RevealPollsStamp, RevealPollsLine), RevealSummary,
-- WhyButton, RevealWhy (details), RevealEstimate, RevealChoice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedFolder = ReplicatedStorage.Shared
local Swing = require(SharedFolder.UI.Swing)
local SimState = require(SharedFolder.Sim.State)
local RevealSteps = require(SharedFolder.UI.RevealSteps)
local ViewModule = require(SharedFolder.Sim.View)
local StateData = require(SharedFolder.Sim.StateData)
local Words = require(SharedFolder.UI.Words.Reveal)

local Audio = require(script.Parent.Parent.Parent.UI.Audio)
local CoachTip = require(script.Parent.Parent.Parent.UI.CoachTip)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Lens = require(script.Parent.Parent.Parent.Map.Lens)
local MapInterface = require(script.Parent.Parent.Parent.Map.MapInterface)
local Model = require(script.Parent.Model)
local Motion = require(script.Parent.Parent.Parent.UI.Motion)

type View = ViewModule.View
type Event = SimState.Event
type Payload = Model.Payload

local Reveal = {}

local REVEAL_TAIL = 2 -- seconds kept at the end of the resolve reveal for the new polls
local REVEAL_INTRO = 0.5 -- seconds of "Both plans are in" before the first action lands
local SWEEP = 0.6 -- seconds the "New polls are in" pulse takes to cross the map, west to east
local SWEEP_WEST, SWEEP_EAST = -125, -67 -- longitudes the sweep runs between (Alaska and Hawaii go first)
local LAND_MAX = 3 -- most states one beat bumps on the map (a catch-up beat can hold many)
local THEIR_PITCH = 0.94 -- the opponent's actions land a little lower than yours
local REVEAL_BEAT = 0.25 -- fastest pace: one tick of the router
local REVEAL_SLOW = 0.8 -- slowest pace, when there are few steps
local GROUP_LINES = 6 -- lines per side before "+N more"
local PORTRAIT = 32 -- px, a player's portrait in a group head
local MARK_W = 20 -- px, the ▲/▼ column of a "What changed" row
local STAMP_SLACK = 24 -- px over the stamp's height in its row: room for its tilt
local STAMP_INSET = 6 -- px a stamp keeps from each side (its tilted corners stay in)

export type Hooks = {
	caption: (text: string, polls: boolean?) -> (),
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

-- A group head: the player's portrait (filled in by `portrait`) and "Your week".
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

-- Puts candidate `id`'s portrait ringed in `color` into a group head's slot
-- (once per candidate, name and color).
local function portrait(slot: Frame, id: string?, name: string, color: Color3, px: number?)
	local rgb = Kit.rgb(color)
	local key = `{id}|{name}|{rgb.r},{rgb.g},{rgb.b}`
	if slot:GetAttribute("For") == key then
		return
	end
	slot:SetAttribute("For", key)
	for _, child in slot:GetChildren() do
		child:Destroy()
	end
	Kit.portrait(id, name, px or PORTRAIT, { ring = color }).Parent = slot
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
	-- The week's net, once the new polls are in (M4).
	local tallyLine = Kit.text(
		"",
		grows({
			Name = "RevealTally",
			LayoutOrder = 3,
			Font = Kit.font.medium,
			Visible = false,
			Parent = headBox,
		})
	)

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
		Kit.stack({ Name = "RevealChanged", LayoutOrder = 5, Parent = root }, "Vertical", Kit.space.xs)
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

	-- ------------------------------------------------------------ summary and Why?

	-- The last step (D-066): a "New polls are in" stamp and what the polls
	-- shifted, right under the title (above the groups, so a phone sees it).
	local pollsBox = Kit.stack(
		{ Name = "RevealPolls", LayoutOrder = 2, Visible = false, Parent = root },
		"Vertical",
		Kit.space.xs
	)
	local pollsStampBox = Kit.box({
		Name = "PollsStampBox",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, Kit.size.heading + 28 + STAMP_SLACK),
		Parent = pollsBox,
	})
	local pollsLine = Kit.text("", {
		Name = "RevealPollsLine",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.bold,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = pollsBox,
	})
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
	-- The per-move numbers are estimates: said once, behind Why? (D-066).
	local estimateText = Kit.caption("", { Name = "RevealEstimate", LayoutOrder = 0, Parent = why })
	local choiceText = Kit.caption(
		"",
		{ Name = "RevealChoice", LayoutOrder = 1, TextColor3 = Kit.colors.text, Parent = why }
	)
	local function setWhy(available: boolean)
		whyButton.Visible = available
		if not available then
			whyOpen = false
			why.Visible = false
			whyButton.Text = "Why? +"
		end
	end

	-- A stamp in `box` (cleared first), as wide as its words, never wider than
	-- the panel, slammed in; its label is named `labelName`.
	local function stampInto(box: Frame, text: string, color: Color3, labelName: string)
		for _, child in box:GetChildren() do
			child:Destroy()
		end
		local stamp = Kit.stamp(text, color, {
			size = Kit.size.heading,
			Name = "Stamp",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
		})
		local natural = stamp.Size
		stamp.Size = UDim2.new(1, -2 * STAMP_INSET, 0, natural.Y.Offset)
		Kit.new(
			"UISizeConstraint",
			{ MaxSize = Vector2.new(natural.X.Offset, natural.Y.Offset), Parent = stamp }
		)
		local label = (stamp:FindFirstChild("Plate") :: Frame):FindFirstChild("Label") :: TextLabel
		label.Name = labelName
		label.TextTransparency = 0 -- the resting value Motion.stamp's fade ends on
		stamp.Parent = box
		Motion.stamp(stamp)
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
		portrait(
			youDot,
			view.players[view.you].candidate,
			Model.candidateName(config, view, view.you),
			Kit.playerColor(view, view.you)
		)
		portrait(
			themDot,
			view.players[them].candidate,
			Model.candidateName(config, view, them),
			Kit.playerColor(view, them)
		)
		changed.Visible = false
		summary.Text = ""
		tallyLine.Text = ""
		tallyLine.Visible = false
		pollsBox.Visible = false
		estimateText.Text = if oldView then Words.ESTIMATE_NOTE else ""
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
		if short == nil then
			return ""
		end
		-- A leader change rides along, short enough for a phone: "You: Rally · OH → you +17".
		local flip = entry.flips[1]
		if flip then
			local kind = string.match(short, "^(.-) in ") or short
			return `{who}: {kind} {Kit.glyph.dot} {Words.leaderArrow(view, flip, themName(view))}`
		end
		return `{who}: {short}`
	end

	-- "New polls are in": a pulse crosses the map west to east over every
	-- polled state (decorative: nothing under reduced motion).
	local function sweep(view: View)
		local map = hooks.map
		if map == nil or Motion.reduced() then
			return
		end
		for _, s in view.states do
			if s.poll then
				local lon = math.clamp(StateData.byId[s.id].lon, SWEEP_WEST, SWEEP_EAST)
				local delay = SWEEP * (lon - SWEEP_WEST) / (SWEEP_EAST - SWEEP_WEST)
				task.delay(delay, function()
					if root.Parent ~= nil then
						map:pulse(s.id, Kit.colors.muted)
					end
				end)
			end
		end
	end

	local function tickResolve(p: Payload, now: number)
		local view = p.view
		local current = tally
		if current == nil then
			return
		end
		local steps = current.steps
		local n = #steps
		-- A reveal is always timed (only choices go without, D-075).
		local duration = math.max(REVEAL_BEAT, (p.deadline or p.stageStart) - p.stageStart)
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
			-- Every state the move touched shows its points; a leader change says FLIP.
			hooks.swing({ net = latest.net, flips = latest.flips, step = true })
			if next(latest.net) ~= nil then
				setWhy(true)
			end
		end
		ringFlips(view, rings)
		local map = hooks.map
		if map then
			-- A leader change also bumps the state in its new leader's color.
			for _, flip in rings do
				map:pulse(
					flip.state,
					if flip.to > 0 then Kit.playerColor(view, flip.to) else Kit.colors.muted
				)
			end
		end
		if latest then
			hooks.caption(stepCaption(view, latest), latest.kind == "Settle")
		end
		hooks.paint(RevealSteps.viewAt(current, count))
		-- Once the moves are done, the map follows the player's own pick again.
		hooks.focus(if count < n then focus else model.selected)
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
		-- The week's net: the header's score now is the new polls' (D-066), and
		-- it started the reveal on the polls before the week.
		if old then
			local ground = if #flips == 0 then Words.groundLine(old, view, Lens.CLOSE) else nil
			tallyLine.Text = ground
				or Words.projectionLine(old.projectedEV[view.you] or 0, view.projectedEV[view.you] or 0)
		end
		tallyLine.Visible = old ~= nil
		-- The polls' own look: a stamp, what they shifted, a sweep across the map.
		pollsLine.Text = if old then Words.pollShift(#steps[n].flips) else ""
		pollsLine.Visible = old ~= nil
		pollsBox.Visible = true
		if not flipsRung then
			-- Beat three, once: the stamp, the sweep, rings on what the polls flipped.
			flipsRung = true
			stampInto(pollsStampBox, Words.SETTLE, Kit.colors.raisedHover, "RevealPollsStamp")
			if old then
				sweep(view)
				ringFlips(view, steps[n].flips)
			end
			Motion.pop(title)
			Motion.enter(tallyLine, 4)
			Motion.enter(pollsLine, 4)
			enterChanged()
		end
		summary.Text = if #flips > 0 then "Tap a state for details." else "No state changed leader this week."
	end

	local reveal: Reveal = {
		root = root,
		remember = function(_self: Reveal, view: View)
			planView = view
		end,
		render = function(_self: Reveal, p: Payload)
			root.Visible = p.reveal == "Resolve"
			groups.Visible = p.reveal == "Resolve" and shown >= 0
			intro.Visible = p.reveal == "Resolve" and shown == -1
			choiceText.Visible = p.reveal == "Resolve" and choiceText.Text ~= ""
			estimateText.Visible = p.reveal == "Resolve" and estimateText.Text ~= ""
			if p.reveal ~= "Resolve" then
				changed.Visible = false
				pollsBox.Visible = false
				tallyLine.Visible = false
			end
		end,
		tick = function(_self: Reveal, p: Payload, now: number)
			if p.reveal == "Resolve" then
				if step ~= p.step then
					startResolve(p)
				end
				tickResolve(p, now)
				choiceText.Visible = choiceText.Text ~= ""
				estimateText.Visible = estimateText.Text ~= ""
			end
		end,
		status = function(_self: Reveal, _p: Payload): string
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
