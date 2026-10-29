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
--   bar:setProgress(fraction?)           -- time left (0..1) as a fill inside the
--                                        -- primary, shrinking from the right; nil hides it
--   bar:setQuiet(on)                     -- a quiet primary (a Skip, D-098): the secondary's
--                                        -- raised look and no shine while enabled, so a
--                                        -- skip is never the brightest thing on screen
--   bar:lockFlash(pitch?)                -- the lock-in moment: the primary flashes
--                                        -- light and settles into its disabled look,
--                                        -- with the "lockIn" cue (pitch 0.8 for time's up)
--   bar.root       Frame "ActionBar": Size (1, 0, 0, BAR_H), AnchorPoint (0, 1), Position (0, 0, 1, 0)
--   bar.primary    TextButton (default Name "Primary"), attribute PrimaryAction = true;
--                  its holder (Kit.outer) "PrimaryHolder" with the lip
--   bar.secondary  TextButton (default Name "Secondary"), in "SecondaryHolder"
--   bar.plate      Frame "Plate": the bar's surface plate (decor), lit, with a
--                  shadow cast upward (D-056: the one persistent bottom bar)
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
--
-- Lock-in flash (docs/DESIGN.md D-053): setPrimary runs lockFlash by itself
-- when an enabled primary becomes a disabled "Locked in…", so every screen that
-- already says "Locked in" gets the flash and the cue. The first setPrimary
-- after new() never flashes (a screen that mounts already locked in).

local Audio = require(script.Parent.Audio)
local Kit = require(script.Parent.Kit)
local Motion = require(script.Parent.Motion)

local ActionBar = {}

local STATUS_H = 20 -- px, the status line
local GAP = Kit.space.xs -- px, between the status line and the buttons, and below them
local SECONDARY_SHARE = 0.3 -- the secondary's share of the width
local PROGRESS_TRANSPARENCY = 0.8 -- the time fill over the primary: a light veil, the label stays readable
local LOCKED = "Locked in" -- a primary label starting with this is the lock-in moment

export type Tone = "muted" | "ok" | "warn" | "bad"

local TONES: { [string]: Color3 } = {
	muted = Kit.colors.muted,
	ok = Kit.colors.good,
	warn = Kit.colors.loss,
	bad = Kit.colors.loss,
}
local PLATE_PAD = Kit.space.sm -- px the plate reaches past the bar on the left, right and top
local PLATE_SHADOW_DY = -4 -- px: the plate's shadow falls upward, over the board

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
	plate: Frame,
	primary: TextButton,
	secondary: TextButton,
	status: TextLabel,
	opponent: TextLabel,
	setPrimary: (self: ActionBar, text: string, enabled: boolean) -> (),
	setSecondary: (self: ActionBar, text: string?, enabled: boolean) -> (),
	setStatus: (self: ActionBar, text: string, tone: Tone) -> (),
	setOpponent: (self: ActionBar, text: string?) -> (),
	setProgress: (self: ActionBar, fraction: number?) -> (),
	lockFlash: (self: ActionBar, pitch: number?) -> (),
	setQuiet: (self: ActionBar, on: boolean) -> (),
}

function ActionBar.new(parent: Instance, options: Options): ActionBar
	local root = Kit.box({
		Name = options.name or "ActionBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, Kit.BAR_H),
	})

	-- The plate: a card-lit surface behind the status line and the buttons.
	local plate = Kit.new("Frame", {
		Name = "Plate",
		Position = UDim2.fromOffset(-PLATE_PAD, -PLATE_PAD),
		Size = UDim2.new(1, 2 * PLATE_PAD, 1, PLATE_PAD),
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = root,
	}) :: Frame
	plate:SetAttribute("Decor", true)
	Kit.depth(plate, Kit.colors.surfaceTop, Kit.colors.surface)
	Kit.corner(Kit.radius.panel).Parent = plate
	Kit.bevel(plate)
	Kit.shadow(plate, { dy = PLATE_SHADOW_DY })

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
	-- The time left, as a veil over the primary from the left (setProgress).
	local timeFill = Kit.new("Frame", {
		Name = "TimeFill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.colors.raisedHover,
		BackgroundTransparency = PROGRESS_TRANSPARENCY,
		BorderSizePixel = 0,
		Visible = false,
		Parent = primary,
	})
	Kit.corner(Kit.radius.button).Parent = timeFill
	Motion.shine(primary)
	local armed = false -- set by the first setPrimary: later changes may flash
	local wasEnabled = false
	local quiet = false -- setQuiet: the primary wears the raised look (D-098)

	-- An enabled quiet primary: the disabled look's raised fill, hairline and
	-- lip, but readable text, still tappable, and no light sweeping it.
	local function paintQuiet(enabled: boolean)
		local band = primary:FindFirstChild("Shine")
		if band and band:IsA("GuiObject") then
			band.Visible = not quiet
		end
		if not (quiet and enabled) then
			return
		end
		Kit.setEnabled(primary, false)
		primary.Active = true
		primary.AutoButtonColor = true
		primary.TextColor3 = Kit.colors.text
	end

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
		plate = plate,
		primary = primary,
		secondary = secondary,
		status = status,
		opponent = opponent,
		setPrimary = function(self: ActionBar, text: string, enabled: boolean)
			local lockingIn = armed and wasEnabled and not enabled and string.sub(text, 1, #LOCKED) == LOCKED
			self.primary.Text = text
			Kit.setEnabled(self.primary, enabled)
			paintQuiet(enabled)
			armed = true
			wasEnabled = enabled
			if lockingIn then
				self:lockFlash()
			end
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
			-- Orange text says "careful" or "that failed" (the audit's lossText rule).
			self.status:SetAttribute("Warn", tone == "warn" or tone == "bad")
		end,
		setOpponent = function(self: ActionBar, text: string?)
			self.opponent.Text = text or ""
			self.opponent.Visible = (text or "") ~= ""
			layout()
		end,
		setProgress = function(_self: ActionBar, fraction: number?)
			if fraction == nil then
				timeFill.Visible = false
				return
			end
			local k = math.clamp(fraction, 0, 1)
			timeFill.Visible = k > 0
			timeFill.Size = UDim2.fromScale(k, 1)
		end,
		setQuiet = function(_self: ActionBar, on: boolean)
			if on == quiet then
				return
			end
			quiet = on
			Kit.setEnabled(primary, wasEnabled)
			paintQuiet(wasEnabled)
		end,
		lockFlash = function(self: ActionBar, pitch: number?)
			timeFill.Visible = false
			local resting = self.primary.BackgroundColor3
			-- The face is white (D-058), so the flash dips to its grey edge and back.
			self.primary.BackgroundColor3 = Kit.colors.accentEdge
			Motion.tween(self.primary, { BackgroundColor3 = resting }, Motion.t.base)
			Audio.play("lockIn", if pitch then { pitch = pitch } else nil)
		end,
	}
	root.Parent = parent
	return bar
end

return ActionBar
