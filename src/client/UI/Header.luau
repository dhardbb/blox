--!strict
-- The standard screen header (docs/DESIGN.md D-030): one Kit.HEADER_H (44 px)
-- row with a bold title, a muted subtitle after it, and the countdown at the
-- right. The timer is accent, danger once fewer than Kit.TIMER_WARN seconds are
-- left, and hidden when there is no deadline. With `onHelp`, a 44 px "?" button
-- (HelpButton) sits just left of the timer and opens the "How it works" overlay.
--
--   local header = Header.new(parent, { title = "Choose your campaign" })
--   header:setTitle(text)
--   header:setSubtitle(text?)                    -- nil or "" hides it
--   header:setTimer(secondsLeft?, warnBelow?)    -- nil hides the timer
--   header:setTimerLabel(label?)                 -- "Results in" -> "Results in 0:32"
--   header.root    Frame "Header" (or opts.name), Size (1, 0, 0, Kit.HEADER_H)
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

export type Options = {
	title: string,
	subtitle: string?,
	name: string?, -- the root's Name (default "Header")
	onHelp: (() -> ())?, -- adds the "?" button
}

export type Header = {
	root: Frame,
	title: TextLabel,
	subtitle: TextLabel,
	timer: TextLabel,
	help: TextButton?,
	rightWidth: number,
	setTitle: (self: Header, text: string) -> (),
	setSubtitle: (self: Header, text: string?) -> (),
	setTimer: (self: Header, secondsLeft: number?, warnBelow: number?) -> (),
	setTimerLabel: (self: Header, label: string?) -> (),
}

function Header.new(parent: Instance, options: Options): Header
	local root = Kit.box({
		Name = options.name or "Header",
		Size = UDim2.new(1, 0, 0, Kit.HEADER_H),
	})

	local onHelp = options.onHelp
	local left = Kit.box({
		Name = "Left",
		ClipsDescendants = true,
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

	local timerLabel: string? = nil

	-- Lays the right side out for a timer `width` px wide; returns rightWidth.
	local function place(width: number): number
		timer.Size = UDim2.new(0, width, 1, 0)
		local right = width
		if help then
			help.Position = UDim2.new(1, -(width + Kit.space.sm), 0.5, 0)
			right += Kit.MIN_TOUCH + Kit.space.sm
		end
		left.Size = UDim2.new(1, -(right + Kit.space.sm), 1, 0)
		return right
	end
	local rightWidth = place(TIMER_W)

	local header: Header = {
		root = root,
		title = title,
		subtitle = subtitle,
		timer = timer,
		help = help,
		rightWidth = rightWidth,
		setTitle = function(self: Header, text: string)
			self.title.Text = text
		end,
		setSubtitle = function(self: Header, text: string?)
			self.subtitle.Text = text or ""
			self.subtitle.Visible = (text or "") ~= ""
		end,
		setTimer = function(self: Header, secondsLeft: number?, warnBelow: number?)
			if secondsLeft == nil then
				self.timer.Visible = false
				return
			end
			-- Compare what the player reads: Kit.clock rounds up.
			local shown = math.max(0, math.ceil(secondsLeft))
			local clock = Kit.clock(secondsLeft)
			self.timer.Text = if timerLabel then `{timerLabel} {clock}` else clock
			self.timer.TextColor3 = if shown < (warnBelow or Kit.TIMER_WARN)
				then Kit.colors.danger
				else Kit.colors.accent
			self.timer.Visible = true
		end,
		setTimerLabel = function(self: Header, label: string?)
			timerLabel = if label == "" then nil else label
			self.rightWidth = place(if timerLabel then LABELED_TIMER_W else TIMER_W)
		end,
	}
	root.Parent = parent
	return header
end

return Header
