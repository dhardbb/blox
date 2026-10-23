--!strict
-- The Campaign header (docs/UI-STYLE.md §4.5): the standard Header with its
-- "what to do now" line, on every screen size the same two rows. The Decision
-- screen (D-044) uses it too: the title names the decision, and the actions
-- and money are left out.
--
--   wide      Week 3 of 12      Dana Okafor 310 ━━━━━━━|━━━━ 189 Rex Calloway      ?  0:48
--             ▌Pick an action in Ohio                           2 actions left · $4.0
--   phone     Week 3   Dana 310 ━━━|━━ 189 Rex     ?  0:48
--             ▌Tap a state on the map         3 actions left · $4.0
--   Decision  Week 7 · Clinic walkout                    ?  0:18   (phone: no score)
--             ▌Pick a side: A, B or C
--
-- The score is each side's projected votes over a two-segment bar with a tick
-- at the halfway mark (270 of 538). The time bar under the first row shows the
-- step's time left. The disconnect notice adds a 24 px row under the now line.
-- The step's name ("Plan your week", "Results", "Debate", "Locked in", "Debate
-- focus", "Take a stance") is kept on the hidden StageLabel: the now line says
-- the same thing as an instruction.
--
-- Motion (docs/DESIGN.md D-053): when a side's projected votes or the money
-- left change, the number counts to its new value (Motion.countTo), the vote
-- bar slides (0.5 s), and a small "+12" / "-$3.0" chip ("Delta", decorative)
-- rises 12 px from it and fades. Under reduced motion the numbers just change.
--
--   local top = TopBar.new(parent, model)
--   top:place(portrait)      -- lays the rows out; returns the height
--   top:render(now) -> bool  -- true when the height changed (the notice came or went)
--   top.root   Frame "TopBar"
--   Elements: WeekLabel, StageLabel (hidden), Countdown, HelpButton, NowText,
--   Score (YouLabel, ThemLabel, EvBar with YouBar, ThemBar, Mid), APLabel,
--   MoneyLabel, OpponentNotice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlanDraft = require(ReplicatedStorage.Shared.UI.PlanDraft)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local Words = require(ReplicatedStorage.Shared.UI.Words.Campaign)

local Header = require(script.Parent.Parent.Parent.UI.Header)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Model = require(script.Parent.Model)
local Motion = require(script.Parent.Parent.Parent.UI.Motion)

local TopBar = {}

local NOTICE_H = 24 -- px, the disconnected notice
local NAMES_H = 22 -- px, the names line in the score strip
local BAR_H = 6 -- px, the vote bar under the names
local SCORE_START = 0.24 -- share of the row where the score strip starts (wide)
local PORTRAIT_SCORE_START = 0.25 -- ... on a phone, after the short "Week 3"
local BUDGET_SHARE = 0.44 -- share of the now line the actions and money take
local MID_W = 2 -- px, the halfway tick on the vote bar
local DELTA_RISE = 12 -- px, a delta chip rises this far
local DELTA_SECONDS = 0.6 -- s, ... while it fades
local DELTA_H = Kit.size.caption + 4 -- px, a delta chip's height

-- A "+12" chip under `anchor` that rises and fades, then removes itself
-- (decorative: none under reduced motion; the number itself still changes).
local function deltaChip(anchor: GuiObject, text: string, color: Color3)
	if Motion.reduced() then
		return
	end
	local chip = Kit.text(text, {
		Name = "Delta",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, DELTA_H),
		TextSize = Kit.size.caption,
		Font = Kit.font.bold,
		TextColor3 = color,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = Kit.colors.background,
		BackgroundTransparency = 0.2,
		ZIndex = 10,
		Parent = anchor,
	})
	chip:SetAttribute("Decor", true)
	Kit.corner(4).Parent = chip
	Motion.tween(chip, {
		Position = UDim2.new(0.5, 0, 1, -DELTA_RISE),
		TextTransparency = 1,
		BackgroundTransparency = 1,
	}, DELTA_SECONDS, Motion.ease.soft)
	task.delay(DELTA_SECONDS, function()
		chip:Destroy()
	end)
end

local TOTAL_EV = 0
for _, record in StateData.list do
	TOTAL_EV += record.ev
end

export type TopBar = {
	root: Frame,
	place: (self: TopBar, portrait: boolean) -> number,
	render: (self: TopBar, now: number) -> boolean,
}

function TopBar.new(parent: Instance, model: Model.Model): TopBar
	local config = model.config
	local root = Kit.box({ Name = "TopBar", Size = UDim2.new(1, 0, 0, Kit.HEADER_H + Kit.NOW_H) })

	local header = Header.new(root, { title = "Week", name = "Header", onHelp = model.ctx.help, now = true })
	header.title.Name = "WeekLabel"
	header.subtitle.Name = "StageLabel"
	header.timer.Name = "Countdown"
	local left = header.root:FindFirstChild("Left") :: Frame
	-- The timer and the buttons at the right: header.rightWidth, read at each
	-- layout (the sound button steps aside when a long title needs the room).
	local laidOutRight = header.rightWidth

	-- The score strip: names and projected votes over a two-segment bar.
	local score = Kit.box({ Name = "Score", Parent = header.root })
	Kit.dataColor(score)
	local function name(labelName: string, align: Enum.TextXAlignment): TextLabel
		return Kit.text("", {
			Name = labelName,
			Size = UDim2.new(0.5, -Kit.space.xs, 0, NAMES_H),
			Font = Kit.font.bold,
			TextScaled = true,
			TextSize = Kit.size.body,
			TextXAlignment = align,
			Parent = score,
		})
	end
	local you = name("YouLabel", Enum.TextXAlignment.Left)
	local them = name("ThemLabel", Enum.TextXAlignment.Right)
	them.AnchorPoint = Vector2.new(1, 0)
	them.Position = UDim2.fromScale(1, 0)
	local bar = Kit.new("Frame", {
		Name = "EvBar",
		Position = UDim2.fromOffset(0, NAMES_H + 4),
		Size = UDim2.new(1, 0, 0, BAR_H),
		BackgroundColor3 = Kit.colors.raised,
		BorderSizePixel = 0,
		Parent = score,
	}) :: Frame
	Kit.corner(BAR_H // 2).Parent = bar
	local youBar = Kit.new("Frame", {
		Name = "YouBar",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	}) :: Frame
	local themBar = Kit.new("Frame", {
		Name = "ThemBar",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0, 1),
		Parent = bar,
	}) :: Frame
	-- The halfway tick: whoever crosses it has a majority.
	Kit.new("Frame", {
		Name = "Mid",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, MID_W, 1, 0),
		BackgroundColor3 = Kit.colors.text,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = bar,
	})

	-- The actions left and the money, at the right end of the now line.
	local nowLine = header.root:FindFirstChild("Now") :: Frame
	local nowText = header.now :: TextLabel
	nowText.Size = UDim2.new(1 - BUDGET_SHARE, -Kit.space.md, 1, 0)
	local budget = Kit.box({
		Name = "Budget",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(BUDGET_SHARE, 1),
		Parent = nowLine,
	})
	local budgetList = Kit.list("Horizontal", Kit.space.sm)
	budgetList.HorizontalAlignment = Enum.HorizontalAlignment.Right
	budgetList.VerticalAlignment = Enum.VerticalAlignment.Center
	budgetList.Parent = budget
	local function budgetLabel(labelName: string, order: number): TextLabel
		return Kit.text("", {
			Name = labelName,
			LayoutOrder = order,
			Size = UDim2.fromOffset(0, Kit.NOW_H),
			AutomaticSize = Enum.AutomaticSize.X,
			Font = Kit.font.medium,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = budget,
		})
	end
	local apLabel = budgetLabel("APLabel", 1)
	local moneyLabel = budgetLabel("MoneyLabel", 2)

	local notice = Kit.text("", {
		Name = "OpponentNotice",
		Size = UDim2.new(1, 0, 0, NOTICE_H),
		Position = UDim2.fromOffset(0, header.height),
		TextSize = Kit.size.caption,
		TextScaled = true,
		TextColor3 = Kit.colors.danger,
		Visible = false,
		Parent = root,
	})

	local portrait = false
	local scoreShown = true
	-- What the score and money showed at the last render (nil before the first).
	local shownMine: number?, shownTheirs: number? = nil, nil
	local shownCash: number? = nil
	local namesShown = ""

	-- Shows `value` on `label` as format(value): counts there from `before`
	-- (with a delta chip) when the value changed, else sets it.
	local function show(
		label: TextLabel,
		before: number?,
		value: number,
		format: (number) -> string,
		delta: string?,
		color: Color3
	)
		if before ~= nil and before ~= value then
			Motion.countTo(label, before, value, format)
			if delta then
				deltaChip(label, delta, color)
			end
		elseif before == nil then
			label.Text = format(value)
		end
	end

	local function height(): number
		return header.height + (if notice.Visible then NOTICE_H else 0)
	end

	local function layout()
		local start = if portrait then PORTRAIT_SCORE_START else SCORE_START
		local rightW = header.rightWidth
		laidOutRight = rightW
		if scoreShown then
			left.Size = UDim2.new(start, -Kit.space.sm, 0, Kit.HEADER_H)
		else
			left.Size = UDim2.new(1, -(rightW + Kit.space.sm), 0, Kit.HEADER_H)
		end
		score.Visible = scoreShown
		score.Position = UDim2.new(start, 0, 0, (Kit.HEADER_H - (NAMES_H + 4 + BAR_H)) // 2)
		score.Size = UDim2.new(1 - start, -(rightW + Kit.space.lg), 0, NAMES_H + 4 + BAR_H)
		root.Size = UDim2.new(1, 0, 0, height())
	end

	-- The now line for this moment.
	local function nowFor(p: Model.Payload, theirName: string): string
		local deciding = Model.deciding(p)
		if deciding ~= nil then
			if Model.isLocked(model, p) then
				return `Waiting for {theirName}…`
			end
			return if deciding == "Focus" then "Pick one debate topic" else "Pick a side: A, B or C"
		elseif p.reveal == "Resolve" then
			return model.caption or "Here's what happened this week"
		elseif p.reveal == "Debate" then
			return model.caption or "Debate! Watch each topic"
		elseif not Model.planning(p) then
			return ""
		end
		local view = p.view
		local ap = PlanDraft.remaining(config, view, model.draft)
		local selected = model.selected
		return Words.planNow({
			locked = Model.isLocked(model, p),
			opponent = theirName,
			problem = PlanDraft.problem(config, view, model.draft) ~= nil,
			actionsLeft = ap,
			planned = #model.draft.actions,
			selected = if selected then Model.stateName(selected) else nil,
		})
	end

	local top: TopBar = {
		root = root,
		place = function(_self: TopBar, isPortrait: boolean): number
			portrait = isPortrait
			layout()
			return height()
		end,
		render = function(_self: TopBar, now: number): boolean
			local p = model.payload
			if p == nil then
				return false
			end
			local view = p.view
			local me, rival = view.you, Model.opponentOf(view)
			local week = view.week
			local stage = "Plan your week"
			local deciding = Model.deciding(p)
			if deciding ~= nil then
				stage = if Model.isLocked(model, p)
					then "Locked in"
					elseif deciding == "Focus" then "Debate focus"
					else "Take a stance"
			elseif p.reveal == "Resolve" then
				week -= 1
				stage = "Results"
			elseif p.reveal == "Debate" then
				stage = "Debate"
			elseif p.stage ~= "Input" then
				stage = "Campaign"
			elseif Model.isLocked(model, p) then
				stage = "Locked in"
			end
			week = math.clamp(week, 1, config.WEEKS)
			local title = if portrait then `Week {week}` else `Week {week} of {config.WEEKS}`
			if deciding == "Stance" and view.event then
				title = `Week {week} · {view.event.name}`
			elseif deciding == "Focus" then
				title = `Week {week} · Debate prep`
			end
			header:setTitle(title)
			header:setSubtitle(stage)
			header.subtitle.Visible = false
			-- Only an open input step warns: reveals end on their own.
			header:setTimer(
				p.deadline - now,
				if p.stage == "Input" then Kit.TIMER_WARN else 0,
				p.deadline - p.stageStart
			)
			local theirFirst = Model.firstName(config, view, rival)
			header:setNow(nowFor(p, theirFirst))

			local planning = Model.planning(p)
			budget.Visible = planning
			local ap, cash = PlanDraft.remaining(config, view, model.draft)
			local actionsLeft = math.max(0, ap)
			apLabel.Text = `{actionsLeft} {if actionsLeft == 1 then "action" else "actions"} left`
			apLabel.TextColor3 = if ap < 0 then Kit.colors.danger else Kit.colors.text
			local cashBefore = shownCash
			local moneyNow = Model.money(cash)
			if planning and cashBefore ~= nil and Model.money(cashBefore) ~= moneyNow then
				local change = cash - cashBefore
				show(
					moneyLabel,
					cashBefore,
					cash,
					Model.money,
					if change > 0 then `+{Model.money(change)}` else Model.money(change),
					if change > 0 then Kit.colors.good else Kit.colors.danger
				)
			elseif cashBefore == nil or Model.money(cashBefore) ~= moneyNow or not planning then
				Motion.cancel(moneyLabel)
				moneyLabel.Text = moneyNow
			end
			shownCash = if planning then cash else nil
			moneyLabel.TextColor3 = if cash < 0 then Kit.colors.danger else Kit.colors.good

			-- The score: on a phone the Decision title needs the whole row.
			local wantScore = not (portrait and deciding ~= nil)
			if wantScore ~= scoreShown or header.rightWidth ~= laidOutRight then
				scoreShown = wantScore
				layout()
			end
			local ev = view.projectedEV
			local mine, theirs = ev[me] or 0, ev[rival] or 0
			local myName = if portrait
				then Model.firstName(config, view, me)
				else Model.candidateName(config, view, me)
			local theirName = if portrait then theirFirst else Model.candidateName(config, view, rival)
			local myColor, theirColor = Kit.playerColor(view, me), Kit.playerColor(view, rival)
			local function myText(n: number): string
				return `{myName} {math.floor(n + 0.5)}`
			end
			local function theirText(n: number): string
				return `{math.floor(n + 0.5)} {theirName}`
			end
			local function signed(n: number): string
				return if n > 0 then `+{n}` else tostring(n)
			end
			local names = `{myName}|{theirName}`
			if names ~= namesShown then
				-- A new layout (phone names) or a new match: no count, just the values.
				namesShown = names
				shownMine, shownTheirs = nil, nil
				Motion.cancel(you)
				Motion.cancel(them)
			end
			local mineBefore, theirsBefore = shownMine, shownTheirs
			show(you, mineBefore, mine, myText, signed(mine - (mineBefore or mine)), myColor)
			show(them, theirsBefore, theirs, theirText, signed(theirs - (theirsBefore or theirs)), theirColor)
			shownMine, shownTheirs = mine, theirs
			you.TextColor3 = myColor
			them.TextColor3 = theirColor
			youBar.BackgroundColor3 = myColor
			themBar.BackgroundColor3 = theirColor
			local youSize = UDim2.fromScale(math.clamp(mine / TOTAL_EV, 0, 1), 1)
			local themSize = UDim2.fromScale(math.clamp(theirs / TOTAL_EV, 0, 1), 1)
			if mineBefore == nil or mineBefore ~= mine then
				Motion.tween(youBar, { Size = youSize }, Motion.t.count, Motion.ease.soft)
			end
			if theirsBefore == nil or theirsBefore ~= theirs then
				Motion.tween(themBar, { Size = themSize }, Motion.t.count, Motion.ease.soft)
			end

			local seat = p.seats[rival]
			local away = seat ~= nil and not seat.connected
			if away then
				local grace = (seat :: Session.SeatInfo).graceUntil
				notice.Text = if grace ~= nil and grace > now
					then `Opponent disconnected · their moves auto-submit in {Kit.clock(grace - now)}`
					else "Opponent disconnected"
			end
			if notice.Visible ~= away then
				notice.Visible = away
				layout()
				return true
			end
			return false
		end,
	}
	layout()
	root.Parent = parent
	return top
end

return TopBar
