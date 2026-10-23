--!strict
-- The standard screen header (docs/DESIGN.md D-030, docs/UI-STYLE.md): one
-- Kit.HEADER_H (44 px) row with a bold title, a muted subtitle after it, and the
-- countdown at the right; optionally a time bar and a "what to do now" line. The timer is accent, danger once fewer than Kit.TIMER_WARN seconds are
-- left, and hidden when there is no deadline. With `onHelp`, a 44 px "?" button
-- (HelpButton) sits just left of the timer and opens the "How it works" overlay.
--
--   local header = Header.new(parent, { title = "Choose your campaign" })
--   header:setTitle(text)
--   header:setSubtitle(text?)                    -- nil or "" hides it
--   header:setTimer(secondsLeft?, warnBelow?, total?)  -- nil hides the timer; with
--                  `total` (the step's full length) a 3 px bar under the row shows
--                  the time left at a glance (TimerBar; danger under warnBelow)
--   header:setTimerLabel(label?)                 -- "Results in" -> "Results in 0:32"
--   header:setNow(text?)                         -- the "what to do now" line (needs
--                  opts.now); nil or "" leaves the row empty but keeps its space
--   header.root    Frame "Header" (or opts.name), Size (1, 0, 0, header.height)
--   header.height  Kit.HEADER_H, plus Kit.NOW_H with opts.now: where the owner's
--                  content starts
--   header.now     TextLabel "NowText" or nil
--   header.title   TextLabel "Title"; header.subtitle "Subtitle"; header.timer "Timer"
--   header.help    TextButton "HelpButton" or nil; header.rightWidth: px the timer
--                  (and help button) take at the right, for owners that lay out beside
--                  them (setTimerLabel widens the timer and updates it)
--
-- The owner positions `root` (it starts at the top-left of `parent`).

local Kit = require(script.Parent.Kit)

local Header = {}

local TIMER_W = 72 -- px, room for "10:00" at heading size
local LABELED_TIMER_W = 150 -- px, room for "Results in 0:32" (after setTimerLabel)
local TIMER_BAR_H = 3 -- px, the time bar under the row

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
	now: TextLabel?,
	height: number,
	rightWidth: number,
	setTitle: (self: Header, text: string) -> (),
	setSubtitle: (self: Header, text: string?) -> (),
	setTimer: (self: Header, secondsLeft: number?, warnBelow: number?, total: number?) -> (),
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
		Font = Kit.font.bold,
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

	-- The time bar: a track and a fill along the bottom of the row.
	local track = Kit.new("Frame", {
		Name = "TimerBar",
		Position = UDim2.fromOffset(0, Kit.HEADER_H - TIMER_BAR_H),
		Size = UDim2.new(1, 0, 0, TIMER_BAR_H),
		BackgroundColor3 = Kit.colors.raised,
		BorderSizePixel = 0,
		Visible = false,
		Parent = root,
	})
	local fill = Kit.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.colors.accent,
		BorderSizePixel = 0,
		Parent = track,
	})

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

	-- Lays the right side out for a timer `width` px wide; returns rightWidth.
	local function place(width: number): number
		timer.Size = UDim2.fromOffset(width, Kit.HEADER_H)
		local right = width
		if help then
			help.Position = UDim2.new(1, -(width + Kit.space.sm), 0, Kit.HEADER_H / 2)
			right += Kit.MIN_TOUCH + Kit.space.sm
		end
		left.Size = UDim2.new(1, -(right + Kit.space.sm), 0, Kit.HEADER_H)
		return right
	end
	local rightWidth = place(TIMER_W)

	local header: Header = {
		root = root,
		title = title,
		subtitle = subtitle,
		timer = timer,
		help = help,
		now = now,
		height = height,
		rightWidth = rightWidth,
		setTitle = function(self: Header, text: string)
			self.title.Text = text
		end,
		setSubtitle = function(self: Header, text: string?)
			self.subtitle.Text = text or ""
			self.subtitle.Visible = (text or "") ~= ""
		end,
		setTimer = function(self: Header, secondsLeft: number?, warnBelow: number?, total: number?)
			if secondsLeft == nil then
				self.timer.Visible = false
				track.Visible = false
				return
			end
			-- Compare what the player reads: Kit.clock rounds up.
			local shown = math.max(0, math.ceil(secondsLeft))
			local clock = Kit.clock(secondsLeft)
			self.timer.Text = if timerLabel then `{timerLabel} {clock}` else clock
			local urgent = shown < (warnBelow or Kit.TIMER_WARN)
			self.timer.TextColor3 = if urgent then Kit.colors.danger else Kit.colors.accent
			self.timer.Visible = true
			track.Visible = total ~= nil and total > 0
			if total and total > 0 then
				fill.Size = UDim2.fromScale(math.clamp(secondsLeft / total, 0, 1), 1)
				fill.BackgroundColor3 = if urgent then Kit.colors.danger else Kit.colors.accent
			end
		end,
		setTimerLabel = function(self: Header, label: string?)
			timerLabel = if label == "" then nil else label
			self.rightWidth = place(if timerLabel then LABELED_TIMER_W else TIMER_W)
		end,
		setNow = function(self: Header, text: string?)
			local label = self.now
			if label then
				label.Text = text or ""
			end
		end,
	}
	root.Parent = parent
	return header
end

return Header
