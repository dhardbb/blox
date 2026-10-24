--!strict
-- The standard screen header (docs/DESIGN.md D-030, docs/UI-STYLE.md): one
-- Kit.HEADER_H (44 px) row with a bold title, a muted subtitle after it, and the
-- countdown at the right; optionally a time bar and a "what to do now" line.
-- The timer (Fredoka One) is accent, loss orange once fewer than Kit.TIMER_WARN
-- (10) seconds are left (attribute Warn), and under Kit.TIMER_CRITICAL (5) each new second pops the
-- number and plays the "tick" cue; it is hidden when there is no deadline. A
-- 44 px sound button (SoundButton, ♪ or the volume icon) mutes and unmutes
-- every cue (UI/Audio, session only); it steps aside (hidden) when the title
-- would not fit beside it (or keep less than 170 px), e.g. a phone with a long
-- title or a labeled timer. With `onHelp`,
-- a 44 px "?" button (HelpButton) sits between them and opens the "How it
-- works" overlay. Right to left: timer, ?, sound.
--
--   local header = Header.new(parent, { title = "Choose your campaign" })
--   header:setTitle(text)
--   header:setSubtitle(text?)                    -- nil or "" hides it
--   header:setTimer(secondsLeft?, warnBelow?, total?)  -- nil hides the timer; with
--                  `total` (the step's full length) a 4 px rounded bar under the
--                  title (it stops short of the buttons) shows the time left at a
--                  glance, with a glowing dot at its end (TimerBar; loss under
--                  the critical mark)
--   header:setNoTimer(text?)                     -- a step with no deadline (the
--                  tutorial, D-075): the timer's place reads "No timer"
--                  (Header.NO_TIMER), muted, no bar, no warning, no ticks;
--                  attribute NoTimer = true until the next setTimer. An
--                  admin's "Timers off" (D-080) passes Header.noTimerText(payload):
--                  "No timer" over "(admin)" on two lines, in the same place
--   header:setTimerLabel(label?)                 -- "Results in" -> "Results in 0:32"
--   header:setNow(text?)                         -- the "what to do now" line (needs
--                  opts.now); nil or "" leaves the row empty but keeps its space
--   header.root    Frame "Header" (or opts.name), Size (1, 0, 0, header.height)
--   header.height  Kit.HEADER_H, plus Kit.NOW_H with opts.now: where the owner's
--                  content starts
--   header.now     TextLabel "NowText" or nil
--   header.title   TextLabel "Title"; header.subtitle "Subtitle"; header.timer "Timer"
--   header.help    TextButton "HelpButton" or nil; header.sound TextButton
--                  "SoundButton" (lipped icon buttons: Kit.outer(button) is the
--                  holder Header places); header.rightWidth: px the timer and the buttons
--                  take at the right, for owners that lay out beside them
--                  (setTimerLabel widens the timer and updates it)
--
-- The owner positions `root` (it starts at the top-left of `parent`).

local Audio = require(script.Parent.Audio)
local Kit = require(script.Parent.Kit)
local Motion = require(script.Parent.Motion)

local Header = {}

Header.NO_TIMER = "No timer" -- what the timer's place reads in a step without a deadline (D-075)
Header.NO_TIMER_ADMIN = "No timer\n(admin)" -- the same while an admin has the timers off (D-080)

-- What the timer's place reads in a step without a deadline: nil (the plain
-- "No timer") or, while an admin has the timers off, Header.NO_TIMER_ADMIN.
function Header.noTimerText(payload: any): string?
	return if payload ~= nil and payload.adminNoTimer == true then Header.NO_TIMER_ADMIN else nil
end

local TIMER_W = 72 -- px, room for "10:00" at heading size
local LABELED_TIMER_W = 150 -- px, room for "Results in 0:32" (after setTimerLabel)
local TIMER_BAR_H = 4 -- px, the time bar under the row
local TIMER_DOT = 12 -- px, the glow at the time bar's leading end
local TIMER_DOT_TRANSPARENCY = 0.2
local TICK_POP = 1.15 -- the timer's scale on each new second under Kit.TIMER_CRITICAL
local ICON_PX = 22 -- px, the sound button's icon
local MIN_TITLE_W = 170 -- px the title keeps before the sound button steps aside

export type Options = {
	title: string,
	subtitle: string?,
	name: string?, -- the root's Name (default "Header")
	onHelp: (() -> ())?, -- adds the "?" button
	now: boolean?, -- adds the "what to do now" line under the row (Kit.NOW_H)
}

export type Header = {
	root: Frame,
	title: TextLabel,
	subtitle: TextLabel,
	timer: TextLabel,
	help: TextButton?,
	sound: TextButton,
	now: TextLabel?,
	height: number,
	rightWidth: number,
	setTitle: (self: Header, text: string) -> (),
	setSubtitle: (self: Header, text: string?) -> (),
	setTimer: (self: Header, secondsLeft: number?, warnBelow: number?, total: number?) -> (),
	setNoTimer: (self: Header, text: string?) -> (),
	setTimerLabel: (self: Header, label: string?) -> (),
	setNow: (self: Header, text: string?) -> (),
}

function Header.new(parent: Instance, options: Options): Header
	local height = Kit.HEADER_H + (if options.now then Kit.NOW_H else 0)
	local root = Kit.box({
		Name = options.name or "Header",
		Size = UDim2.new(1, 0, 0, height),
	})

	local onHelp = options.onHelp
	local left = Kit.box({
		Name = "Left",
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, Kit.HEADER_H),
		Parent = root,
	})
	local row = Kit.list("Horizontal", Kit.space.sm)
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Parent = left

	local title = Kit.text(options.title, {
		Name = "Title",
		LayoutOrder = 1,
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Kit.font.bold,
		TextSize = Kit.size.heading,
		Parent = left,
	})
	local subtitle = Kit.text(options.subtitle or "", {
		Name = "Subtitle",
		LayoutOrder = 2,
		Size = UDim2.fromScale(0, 1),
		TextColor3 = Kit.colors.muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Visible = (options.subtitle or "") ~= "",
		Parent = left,
	})
	-- The subtitle takes whatever width the title leaves.
	Kit.new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = subtitle })

	local timer = Kit.text("", {
		Name = "Timer",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(TIMER_W, Kit.HEADER_H),
		Font = Kit.font.display,
		TextSize = Kit.size.heading,
		TextScaled = true,
		TextColor3 = Kit.colors.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		Parent = root,
	})

	local help: TextButton? = nil
	if onHelp then
		help = Kit.iconButton("?", onHelp, {
			Name = "HelpButton",
			AnchorPoint = Vector2.new(1, 0.5),
			Parent = root,
		})
	end

	-- The sound toggle: the volume icon (or ♪ with a slash while muted).
	local sound = Kit.iconButton("", function()
		Audio.setMuted(not Audio.muted())
		if not Audio.muted() then
			Audio.play("select")
		end
	end, {
		Name = "SoundButton",
		AnchorPoint = Vector2.new(1, 0.5),
		Parent = root,
	})
	local function paintSound()
		local old = sound:FindFirstChild("Icon")
		if old then
			old:Destroy()
		end
		local slash = sound:FindFirstChild("Slash")
		if slash then
			slash:Destroy()
		end
		local muted = Audio.muted()
		local icon = Kit.icon(
			if muted then "volume-x" else "volume-2",
			ICON_PX,
			if muted then Kit.colors.muted else Kit.colors.text
		)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Parent = sound
		if muted and icon:IsA("TextLabel") then
			-- The glyph has no "off" form: strike it through.
			Kit.new("Frame", {
				Name = "Slash",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(ICON_PX, 2),
				Rotation = -45,
				BackgroundColor3 = Kit.colors.muted,
				BorderSizePixel = 0,
				Parent = sound,
			})
		end
		sound:SetAttribute("Muted", muted)
	end
	paintSound()
	-- Follow mutes from anywhere (the Help settings too). A destroyed header's
	-- button has no parent: the first mute after that drops the connection.
	local soundConnection: any = nil
	soundConnection = Audio.changed:Connect(function()
		if sound.Parent == nil then
			soundConnection:Disconnect()
			return
		end
		paintSound()
	end)

	-- The time bar: a track and a fill along the bottom of the row, rounded,
	-- with a glowing dot riding the fill's end.
	local track = Kit.new("Frame", {
		Name = "TimerBar",
		Position = UDim2.fromOffset(0, Kit.HEADER_H - TIMER_BAR_H),
		Size = UDim2.new(1, 0, 0, TIMER_BAR_H),
		BackgroundColor3 = Kit.colors.raised,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	})
	Kit.corner(Kit.radius.pill).Parent = track
	local fill = Kit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.colors.accent,
		BorderSizePixel = 0,
		Parent = track,
	})
	Kit.corner(Kit.radius.pill).Parent = fill
	local dot = Kit.glow(fill, Kit.colors.accent, { px = TIMER_DOT, transparency = TIMER_DOT_TRANSPARENCY })
	if dot then
		dot.Position = UDim2.fromScale(1, 0.5)
		dot.ZIndex = 2
	end

	local now: TextLabel? = nil
	if options.now then
		local line = Kit.box({
			Name = "Now",
			Position = UDim2.fromOffset(0, Kit.HEADER_H),
			Size = UDim2.new(1, 0, 0, Kit.NOW_H),
			Parent = root,
		})
		Kit.new("Frame", {
			Name = "Mark",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(4, Kit.size.body + 4),
			BackgroundColor3 = Kit.colors.accent,
			BorderSizePixel = 0,
			Parent = line,
		})
		now = Kit.text("", {
			Name = "NowText",
			Position = UDim2.fromOffset(Kit.space.md, 0),
			Size = UDim2.new(1, -Kit.space.md, 1, 0),
			Font = Kit.font.medium,
			TextScaled = true,
			Parent = line,
		})
	end

	local timerLabel: string? = nil
	local timerWraps = timer.TextWrapped -- as built; "No timer" turns wrapping off
	local lastShown: number? = nil -- the whole seconds shown last (for the tick)

	-- Lays the right side out for a timer `width` px wide; returns rightWidth.
	-- The sound button steps aside when the title would not fit beside it
	-- (a phone with a long title, or a labeled timer: "Results in 0:32").
	-- The title row ("Left") is resized only while Header still owns its size:
	-- an owner that lays the row out itself (CampaignParts/TopBar) keeps its
	-- layout and reads header.rightWidth instead. `force` resizes it anyway.
	local timerWidth = TIMER_W
	local ownLeft: UDim2? = nil -- the row size Header set last
	-- The title's width in px: its TextBounds, or an estimate where the engine
	-- has none yet (the headless tests).
	local function titleWidth(): number
		local bounds = (title :: any).TextBounds
		if bounds ~= nil and bounds.X > 0 then
			return bounds.X
		end
		local text = tostring(title.Text)
		return (utf8.len(text) or #text) * title.TextSize * 0.55
	end
	local function place(width: number, force: boolean?): number
		timerWidth = width
		timer.Size = UDim2.fromOffset(width, Kit.HEADER_H)
		local right = width
		if help then
			Kit.outer(help).Position = UDim2.new(1, -(right + Kit.space.sm), 0, Kit.HEADER_H / 2)
			right += Kit.MIN_TOUCH + Kit.space.sm
		end
		local rowWidth = root.AbsoluteSize.X
		local room = rowWidth - (right + 2 * Kit.space.sm + Kit.MIN_TOUCH)
		sound.Visible = rowWidth <= 0 or room >= math.max(MIN_TITLE_W, titleWidth())
		if sound.Visible then
			Kit.outer(sound).Position = UDim2.new(1, -(right + Kit.space.sm), 0, Kit.HEADER_H / 2)
			right += Kit.MIN_TOUCH + Kit.space.sm
		end
		-- The time bar runs under the title, stopping short of the buttons.
		track.Size = UDim2.new(1, -(right + Kit.space.sm), 0, TIMER_BAR_H)
		if force or ownLeft == nil or left.Size == ownLeft then
			local size = UDim2.new(1, -(right + Kit.space.sm), 0, Kit.HEADER_H)
			left.Size = size
			ownLeft = size
		end
		return right
	end
	local rightWidth = place(TIMER_W)

	local header: Header = {
		root = root,
		title = title,
		subtitle = subtitle,
		timer = timer,
		help = help,
		sound = sound,
		now = now,
		height = height,
		rightWidth = rightWidth,
		setTitle = function(self: Header, text: string)
			self.title.Text = text
			self.rightWidth = place(timerWidth)
		end,
		setSubtitle = function(self: Header, text: string?)
			self.subtitle.Text = text or ""
			self.subtitle.Visible = (text or "") ~= ""
		end,
		setTimer = function(self: Header, secondsLeft: number?, warnBelow: number?, total: number?)
			self.timer:SetAttribute("NoTimer", nil)
			self.timer.TextWrapped = timerWraps
			if secondsLeft == nil then
				self.timer.Visible = false
				track.Visible = false
				lastShown = nil
				return
			end
			-- Compare what the player reads: Kit.clock rounds up.
			local shown = math.max(0, math.ceil(secondsLeft))
			local clock = Kit.clock(secondsLeft)
			self.timer.Text = if timerLabel then `{timerLabel} {clock}` else clock
			local warnAt = warnBelow or Kit.TIMER_WARN
			local urgent = shown < warnAt
			local critical = shown < math.min(warnAt, Kit.TIMER_CRITICAL)
			self.timer.TextColor3 = if urgent then Kit.colors.loss else Kit.colors.accent
			self.timer:SetAttribute("Warn", urgent)
			self.timer.Visible = true
			track.Visible = total ~= nil and total > 0
			if total and total > 0 then
				fill.Size = UDim2.fromScale(math.clamp(secondsLeft / total, 0, 1), 1)
				-- The bar turns orange (loss) under the critical mark.
				fill.BackgroundColor3 = if critical then Kit.colors.loss else Kit.colors.accent
			end
			-- Each new second under the critical mark: a pop and a tick.
			if critical and shown > 0 and lastShown ~= nil and shown < lastShown then
				Motion.pop(self.timer, TICK_POP)
				Audio.play("tick")
			end
			lastShown = shown
		end,
		setNoTimer = function(self: Header, text: string?)
			self.timer.Text = text or Header.NO_TIMER
			-- One line, scaled down to the clock's place, never two stacked words.
			self.timer.TextWrapped = false
			self.timer.TextColor3 = Kit.colors.muted
			self.timer:SetAttribute("Warn", false)
			self.timer:SetAttribute("NoTimer", true)
			self.timer.Visible = true
			track.Visible = false
			lastShown = nil
		end,
		setTimerLabel = function(self: Header, label: string?)
			timerLabel = if label == "" then nil else label
			self.rightWidth = place(if timerLabel then LABELED_TIMER_W else TIMER_W, true)
		end,
		setNow = function(self: Header, text: string?)
			local label = self.now
			if label then
				label.Text = text or ""
			end
		end,
	}
	root.Parent = parent
	-- Now that the row has a width, check the sound button's room again (and
	-- whenever the screen turns or resizes).
	header.rightWidth = place(timerWidth)
	pcall(function()
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			header.rightWidth = place(timerWidth)
		end)
		title:GetPropertyChangedSignal("TextBounds"):Connect(function()
			header.rightWidth = place(timerWidth)
		end)
	end)
	return header
end

return Header
