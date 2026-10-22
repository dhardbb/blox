--!strict
-- The standard screen header (docs/DESIGN.md D-030): one Kit.HEADER_H (44 px)
-- row with a bold title, a muted subtitle after it, and the countdown at the
-- right. The timer is accent, danger once fewer than Kit.TIMER_WARN seconds are
-- left, and hidden when there is no deadline.
--
--   local header = Header.new(parent, { title = "Choose your campaign" })
--   header:setTitle(text)
--   header:setSubtitle(text?)                    -- nil or "" hides it
--   header:setTimer(secondsLeft?, warnBelow?)    -- nil hides the timer
--   header:setTimerLabel(label?)                 -- "Results in" -> "Results in 0:32"
--   header.root    Frame "Header" (or opts.name), Size (1, 0, 0, Kit.HEADER_H)
--   header.title   TextLabel "Title"; header.subtitle "Subtitle"; header.timer "Timer"
--
-- The owner positions `root` (it starts at the top-left of `parent`).

local Kit = require(script.Parent.Kit)

local Header = {}

local TIMER_W = 150 -- px, room for "Results in 0:32" at heading size

export type Options = {
	title: string,
	subtitle: string?,
	name: string?, -- the root's Name (default "Header")
}

export type Header = {
	root: Frame,
	title: TextLabel,
	subtitle: TextLabel,
	timer: TextLabel,
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

	local left = Kit.box({
		Name = "Left",
		Size = UDim2.new(1, -(TIMER_W + Kit.space.sm), 1, 0),
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
		Size = UDim2.new(0, TIMER_W, 1, 0),
		Font = Kit.font.bold,
		TextSize = Kit.size.heading,
		TextScaled = true,
		TextColor3 = Kit.colors.accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		Parent = root,
	})

	local timerLabel: string? = nil

	local header: Header = {
		root = root,
		title = title,
		subtitle = subtitle,
		timer = timer,
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
		setTimerLabel = function(_self: Header, label: string?)
			timerLabel = if label == "" then nil else label
		end,
	}
	root.Parent = parent
	return header
end

return Header
