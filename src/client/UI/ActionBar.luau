--!strict
-- The standard pinned action bar (docs/DESIGN.md D-030): a status line and the
-- opponent's status (caption, 20 px) over an optional secondary button and the
-- screen's one primary button (56 px). Kit.BAR_H (84 px) tall, anchored to the
-- bottom of its parent with explicit offsets (no list layout), so the fake
-- engine can measure it and the UI audit can prove it is on screen.
--
--   local bar = ActionBar.new(parent, {
--       primary = "Lock in", onPrimary = fn,
--       secondary = "Bank +15s", onSecondary = fn,  -- both optional
--       primaryName = "LockIn", secondaryName = "Bank", -- element names (optional)
--   })
--   bar:setPrimary(text, enabled)        -- disabled label says what is missing
--   bar:setSecondary(text?, enabled)     -- nil hides it; primary takes the full width
--   bar:setStatus(text, tone)            -- tone: "muted" | "ok" | "warn" | "bad"
--   bar:setOpponent(text?)               -- "Opponent: thinking" | ... ; nil hides it
--   bar.root       Frame "ActionBar": Size (1, 0, 0, BAR_H), AnchorPoint (0, 1), Position (0, 0, 1, 0)
--   bar.primary    TextButton (default Name "Primary"), attribute PrimaryAction = true
--   bar.secondary  TextButton (default Name "Secondary")
--   bar.status     TextLabel "BarStatus"; bar.opponent TextLabel "BarOpponent"
--
-- The owning screen sizes its scroll region to
-- UDim2.new(1, 0, 1, -(Kit.BAR_H + Kit.space.sm)). The secondary takes 30 % of
-- the width at most; the primary never less than 70 %.
--
-- Standard wording: primary "Lock in" (disabled: what is missing, e.g. "Pick a
-- state"); status after locking "Locked in · waiting for opponent" (tone ok);
-- opponent "Opponent: thinking" / "locked in" / "skipped" / "disconnected" /
-- "back"; reveal skip "Skip" then "Waiting for opponent…" (disabled).

local Kit = require(script.Parent.Kit)

local ActionBar = {}

local STATUS_H = 20 -- px, the status line
local GAP = Kit.space.xs -- px, between the status line and the buttons, and below them
local SECONDARY_SHARE = 0.3 -- the secondary's share of the width

export type Tone = "muted" | "ok" | "warn" | "bad"

local TONES: { [string]: Color3 } = {
	muted = Kit.colors.muted,
	ok = Kit.colors.good,
	warn = Kit.colors.warn,
	bad = Kit.colors.danger,
}

export type Options = {
	primary: string,
	onPrimary: () -> (),
	secondary: string?,
	onSecondary: (() -> ())?,
	primaryName: string?,
	secondaryName: string?,
	name: string?, -- the root's Name (default "ActionBar")
}

export type ActionBar = {
	root: Frame,
	primary: TextButton,
	secondary: TextButton,
	status: TextLabel,
	opponent: TextLabel,
	setPrimary: (self: ActionBar, text: string, enabled: boolean) -> (),
	setSecondary: (self: ActionBar, text: string?, enabled: boolean) -> (),
	setStatus: (self: ActionBar, text: string, tone: Tone) -> (),
	setOpponent: (self: ActionBar, text: string?) -> (),
}

function ActionBar.new(parent: Instance, options: Options): ActionBar
	local root = Kit.box({
		Name = options.name or "ActionBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, Kit.BAR_H),
	})

	local status = Kit.text("", {
		Name = "BarStatus",
		Size = UDim2.new(1, 0, 0, STATUS_H),
		TextSize = Kit.size.caption,
		TextScaled = true,
		TextColor3 = TONES.muted,
		Parent = root,
	})
	local opponent = Kit.text("", {
		Name = "BarOpponent",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.4, 0, 0, STATUS_H),
		TextSize = Kit.size.caption,
		TextScaled = true,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Visible = false,
		Parent = root,
	})

	local buttonsY = STATUS_H + GAP
	local secondary = Kit.button(options.secondary or "", function()
		local handler = options.onSecondary
		if handler then
			handler()
		end
	end, {
		variant = "secondary",
		Name = options.secondaryName or "Secondary",
		Position = UDim2.fromOffset(0, buttonsY),
		Size = UDim2.new(SECONDARY_SHARE, -GAP, 0, Kit.PRIMARY_H),
		Visible = options.secondary ~= nil,
		Parent = root,
	})
	local primary = Kit.button(options.primary, options.onPrimary, {
		variant = "primary",
		Name = options.primaryName or "Primary",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, buttonsY),
		Size = UDim2.new(1, 0, 0, Kit.PRIMARY_H),
		Parent = root,
	})
	primary:SetAttribute("PrimaryAction", true)

	local function layout()
		-- The status line gives way to the opponent's line; the primary to the secondary.
		status.Size = if opponent.Visible
			then UDim2.new(0.6, -GAP, 0, STATUS_H)
			else UDim2.new(1, 0, 0, STATUS_H)
		primary.Size = if secondary.Visible
			then UDim2.new(1 - SECONDARY_SHARE, 0, 0, Kit.PRIMARY_H)
			else UDim2.new(1, 0, 0, Kit.PRIMARY_H)
	end
	layout()

	local bar: ActionBar = {
		root = root,
		primary = primary,
		secondary = secondary,
		status = status,
		opponent = opponent,
		setPrimary = function(self: ActionBar, text: string, enabled: boolean)
			self.primary.Text = text
			Kit.setEnabled(self.primary, enabled)
		end,
		setSecondary = function(self: ActionBar, text: string?, enabled: boolean)
			if text == nil then
				self.secondary.Visible = false
			else
				self.secondary.Text = text
				self.secondary.Visible = true
				Kit.setEnabled(self.secondary, enabled)
			end
			layout()
		end,
		setStatus = function(self: ActionBar, text: string, tone: Tone)
			self.status.Text = text
			self.status.TextColor3 = TONES[tone]
		end,
		setOpponent = function(self: ActionBar, text: string?)
			self.opponent.Text = text or ""
			self.opponent.Visible = (text or "") ~= ""
			layout()
		end,
	}
	root.Parent = parent
	return bar
end

return ActionBar
