--!strict
-- The Campaign header (UI overhaul §3.4, move 3): one Kit.HEADER_H row on 16:9,
-- two rows on phones.
--
--   16:9      Week 3 of 12 · Plan your week   Dana Okafor 261 ▬▬  ▬▬ 251 Rex Calloway  $4.5  3 AP   0:28
--   portrait  Week 3 of 12 · Plan your week                                          0:28
--             Dana 261 ▬▬  ▬▬ 251 Rex                                      $4.5  3 AP   (28 px)
--
-- Under the names, a two-segment bar shows each side's projected EV out of the
-- whole map. The disconnect notice adds a 24 px row. The opponent's lock status
-- lives in the action bar and their money bracket in the week card.
--
--   local top = TopBar.new(parent, model)
--   top:place(portrait)      -- lays the rows out; returns the height
--   top:render(now) -> bool  -- true when the height changed (the notice came or went)
--   top.root   Frame "TopBar"
--   Elements: WeekLabel, StageLabel, Countdown (the header), YouLabel, ThemLabel,
--   EvBar (YouBar, ThemBar), MoneyLabel, APLabel, OpponentNotice.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlanDraft = require(ReplicatedStorage.Shared.UI.PlanDraft)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)

local Header = require(script.Parent.Parent.Parent.UI.Header)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Model = require(script.Parent.Model)

local TopBar = {}

local SCORE_H = 28 -- px, the phone's second row
local NOTICE_H = 24 -- px, the disconnected notice
local NAMES_H = 26 -- px, the names line in the 16:9 score strip
local BAR_H = 6 -- px, the EV bar in the 16:9 strip
local PORTRAIT_NAMES_H = 20 -- px, the names line in the phone score row
local PORTRAIT_BAR_H = 4 -- px
local SCORE_START = 0.36 -- share of the 16:9 row where the score strip starts

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
	local root = Kit.box({ Name = "TopBar", Size = UDim2.new(1, 0, 0, Kit.HEADER_H) })

	local header = Header.new(root, { title = "Week", subtitle = "", name = "Header" })
	header.title.Name = "WeekLabel"
	header.subtitle.Name = "StageLabel"
	header.timer.Name = "Countdown"
	local left = header.root:FindFirstChild("Left") :: Frame
	local leftFull = left.Size
	local timerW = header.timer.Size.X.Offset

	-- The score strip: names and EV over a two-segment bar, then money and AP.
	local score = Kit.box({ Name = "Score", Parent = root })
	local function label(name: string, props: { [string]: any }): TextLabel
		local base: { [string]: any } = {
			Name = name,
			Font = Kit.font.bold,
			TextScaled = true,
			TextSize = Kit.size.heading,
			Parent = score,
		}
		for key, value in props do
			base[key] = value
		end
		return Kit.text("", base)
	end
	local you = label("YouLabel", { TextXAlignment = Enum.TextXAlignment.Right })
	local them = label("ThemLabel", {})
	local moneyLabel =
		label("MoneyLabel", { TextColor3 = Kit.colors.good, TextXAlignment = Enum.TextXAlignment.Right })
	local apLabel = label("APLabel", { TextXAlignment = Enum.TextXAlignment.Right })
	local bar = Kit.new("Frame", {
		Name = "EvBar",
		BackgroundColor3 = Kit.colors.raised,
		BorderSizePixel = 0,
		Parent = score,
	}) :: Frame
	Kit.corner(Kit.radius.pill).Parent = bar
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

	local notice = Kit.text("", {
		Name = "OpponentNotice",
		Size = UDim2.new(1, 0, 0, NOTICE_H),
		TextSize = Kit.size.caption,
		TextScaled = true,
		TextColor3 = Kit.colors.danger,
		Visible = false,
		Parent = root,
	})

	local portrait = false
	local rows = Kit.HEADER_H

	local function height(): number
		return rows + (if notice.Visible then NOTICE_H else 0)
	end

	local function layout()
		if portrait then
			left.Size = leftFull
			score.Position = UDim2.fromOffset(0, Kit.HEADER_H)
			score.Size = UDim2.new(1, 0, 0, SCORE_H)
			you.Position = UDim2.fromScale(0, 0)
			you.Size = UDim2.new(0.3, 0, 0, PORTRAIT_NAMES_H)
			them.Position = UDim2.fromScale(0.34, 0)
			them.Size = UDim2.new(0.3, 0, 0, PORTRAIT_NAMES_H)
			bar.Position = UDim2.fromOffset(0, PORTRAIT_NAMES_H + 2)
			bar.Size = UDim2.new(0.64, 0, 0, PORTRAIT_BAR_H)
			moneyLabel.Position = UDim2.fromScale(0.66, 0)
			moneyLabel.Size = UDim2.new(0.17, 0, 0, PORTRAIT_NAMES_H)
			apLabel.Position = UDim2.fromScale(0.83, 0)
			apLabel.Size = UDim2.new(0.17, 0, 0, PORTRAIT_NAMES_H)
			rows = Kit.HEADER_H + SCORE_H
		else
			left.Size = UDim2.new(SCORE_START, -Kit.space.sm, 1, 0)
			score.Position = UDim2.fromScale(SCORE_START, 0)
			score.Size = UDim2.new(1 - SCORE_START, -(timerW + Kit.space.sm), 0, Kit.HEADER_H)
			you.Position = UDim2.fromOffset(0, 4)
			you.Size = UDim2.new(0.37, 0, 0, NAMES_H)
			them.Position = UDim2.new(0.41, 0, 0, 4)
			them.Size = UDim2.new(0.37, 0, 0, NAMES_H)
			bar.Position = UDim2.fromOffset(0, NAMES_H + 8)
			bar.Size = UDim2.new(0.78, 0, 0, BAR_H)
			moneyLabel.Position = UDim2.fromScale(0.8, 0)
			moneyLabel.Size = UDim2.fromScale(0.1, 1)
			apLabel.Position = UDim2.fromScale(0.9, 0)
			apLabel.Size = UDim2.fromScale(0.1, 1)
			rows = Kit.HEADER_H
		end
		notice.Position = UDim2.fromOffset(0, rows)
		root.Size = UDim2.new(1, 0, 0, height())
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
			if p.reveal == "Resolve" then
				week -= 1
				stage = "Results"
			elseif p.reveal == "Debate" then
				stage = "Debate"
			elseif p.stage ~= "Input" then
				stage = "Campaign"
			elseif Model.isLocked(model, p) then
				stage = "Locked in"
			end
			header:setTitle(`Week {math.clamp(week, 1, config.WEEKS)} of {config.WEEKS}`)
			header:setSubtitle(stage)
			-- Only an open input step warns: reveals end on their own.
			header:setTimer(p.deadline - now, if p.stage == "Input" then Kit.TIMER_WARN else 0)

			local ap, cash = PlanDraft.remaining(config, view, model.draft)
			moneyLabel.Text = Model.money(cash)
			moneyLabel.TextColor3 = if cash < 0 then Kit.colors.danger else Kit.colors.good
			apLabel.Text = `{ap} AP`
			apLabel.TextColor3 = if ap < 0 then Kit.colors.danger else Kit.colors.text

			local ev = view.projectedEV
			local mine, theirs = ev[me] or 0, ev[rival] or 0
			local myName = if portrait
				then Model.firstName(config, view, me)
				else Model.candidateName(config, view, me)
			local theirName = if portrait
				then Model.firstName(config, view, rival)
				else Model.candidateName(config, view, rival)
			you.Text = `{myName} {mine}`
			them.Text = `{theirs} {theirName}`
			local myColor, theirColor = Kit.playerColor(view, me), Kit.playerColor(view, rival)
			you.TextColor3 = myColor
			them.TextColor3 = theirColor
			youBar.BackgroundColor3 = myColor
			themBar.BackgroundColor3 = theirColor
			youBar.Size = UDim2.fromScale(math.clamp(mine / TOTAL_EV, 0, 1), 1)
			themBar.Size = UDim2.fromScale(math.clamp(theirs / TOTAL_EV, 0, 1), 1)

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
