--!strict
-- The two session settings as a row of chips (GAMEPLAN §4.3, WP-3): "Sound"
-- (Audio.setMuted) and "Reduce motion" (Motion.setReduced). The Help sheet's
-- How to win tab and the Lobby show one each. A chip is outlined (like a
-- picked issue) and its icon lit while its setting is on; the sound icon also
-- changes (volume-2 / volume-x). The labels stay put, so a screen reads the
-- same with either setting (tests/ui/ReducedMotion.spec). Both follow
-- changes made anywhere else (the header's sound button), and both are session
-- only: a saved setting needs the profile, a server change. Roblox's own
-- Reduce Motion setting is honored whatever the chip says.
--
--   local row = Settings.row({ Name?, LayoutOrder?, Parent? })
--   row  Frame "Settings" (44 px tall): SoundChip and MotionChip, half each,
--        attribute On = true while that setting is on
--
-- The Lobby's corner (D-075): the same two settings as compact 44 px icon
-- toggles side by side, for the top-right corner of a screen. Each toggle is
-- outlined (Kit.setSelected) and its icon lit while its setting is on; the
-- sound icon also changes (volume-2 / volume-x, struck through as a glyph).
-- Each carries its label as attribute Label ("Sound on", "Reduce motion off"),
-- and a small tooltip at the pair's left, on the same row (so it never covers
-- what sits under the corner), shows that label while a mouse or a gamepad is
-- on the toggle, and for Settings.TIP_SECONDS after a tap, so a touch player
-- reads what they just changed.
--
--   local corner = Settings.corner({ Name?, Parent?, onTimers? })
--   corner  Frame "CornerSettings" (transparent, anchored top-right at (1, 0)
--           of the parent, 44 px tall, wide enough for the tooltip): Toggles
--           (SoundToggle and MotionToggle, attributes On and Label, at the
--           right) and the TextLabel "SettingsTip" (hidden until wanted)
--
-- Admins (D-081): a third toggle, TimersToggle (the clock, struck through and
-- lit while on), left of the pair, shown only after Settings.setTimers(corner,
-- off) with a boolean (nil hides it: everyone who is not an admin). A tap
-- repaints it at once and calls props.onTimers(off); the server's answer comes
-- back through setTimers. Labels "Timers off (admin)" / "Timers on (admin)".

local Audio = require(script.Parent.Audio)
local Kit = require(script.Parent.Kit)
local Motion = require(script.Parent.Motion)

local Settings = {}

local ICON = 24 -- px, a chip's icon plate (Kit.iconPlate)
local TOGGLE_ICON = 22 -- px, a corner toggle's icon
local TIP_H = 28 -- px, the corner tooltip's height
local TIP_W = 160 -- px, the corner tooltip's width ("Timers off (admin)")
Settings.TIP_SECONDS = 1.5 -- how long the corner tooltip stays after a tap

-- What each corner toggle says it does (its Label attribute and its tooltip).
function Settings.soundLabel(on: boolean): string
	return if on then "Sound on" else "Sound off"
end

function Settings.motionLabel(reduced: boolean): string
	return if reduced then "Reduce motion on" else "Reduce motion off"
end

function Settings.timersLabel(off: boolean): string
	return if off then "Timers off (admin)" else "Timers on (admin)"
end

-- Each corner's admin setter (Settings.setTimers); weak, so a destroyed corner goes.
local timerSetters: { [Frame]: (off: boolean?) -> () } = setmetatable({}, { __mode = "k" }) :: any

type Paint = (on: boolean, text: string, icon: string) -> ()

-- A chip with an icon (in a round plate) at the left of its label (a "Label" TextLabel; the
-- button's own text stays empty), and the function that repaints it.
local function chip(name: string, order: number, onActivate: () -> ()): (TextButton, Paint)
	local button = Kit.chip("", onActivate, {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(0.5, -Kit.space.sm / 2, 1, 0),
	})
	local content = Kit.box({ Name = "Content", Parent = button })
	local list = Kit.list("Horizontal", Kit.space.sm)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = content
	local label = Kit.text("", {
		Name = "Label",
		LayoutOrder = 2,
		Size = UDim2.new(1, -(ICON + Kit.space.sm), 1, 0),
		Font = Kit.font.medium,
		TextScaled = true,
		TextWrapped = false,
		Parent = content,
	})
	Kit.new("UITextSizeConstraint", {
		MaxTextSize = Kit.size.body,
		MinTextSize = Kit.MIN_TEXT,
		Parent = label,
	})
	local function paint(on: boolean, text: string, icon: string)
		local old = content:FindFirstChild("IconPlate")
		if old then
			old:Destroy()
		end
		local plate = Kit.iconPlate(icon, ICON, if on then Kit.colors.accent else Kit.colors.muted)
		plate.LayoutOrder = 1
		plate.Parent = content
		label.Text = text
		button:SetAttribute("On", on)
		Kit.setSelected(button, on)
	end
	return button, paint
end

function Settings.row(props: { [string]: any }?): Frame
	local p: { [string]: any } = props or {}
	local row = Kit.box({
		Name = p.Name or "Settings",
		LayoutOrder = p.LayoutOrder or 0,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
	})
	Kit.list("Horizontal", Kit.space.sm).Parent = row

	local sound, paintSound = chip("SoundChip", 1, function()
		Audio.setMuted(not Audio.muted())
		if not Audio.muted() then
			Audio.play("select")
		end
	end)
	local motion, paintMotion = chip("MotionChip", 2, function()
		Motion.setReduced(not Motion.reduced())
	end)
	sound.Parent = row
	motion.Parent = row

	local function render()
		local on = not Audio.muted()
		paintSound(on, "Sound", if on then "volume-2" else "volume-x")
		local reduced = Motion.reduced()
		paintMotion(reduced, "Reduce motion", "sparkles")
	end
	render()

	-- Follow changes from anywhere; a destroyed row drops its connections on
	-- the next change.
	local connections: { any } = {}
	local function follow()
		if row.Parent == nil then
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			return
		end
		render()
	end
	table.insert(connections, Audio.changed:Connect(follow))
	table.insert(connections, Motion.changed:Connect(follow))

	if p.Parent then
		row.Parent = p.Parent
	end
	return row
end

-- One corner toggle: a 44 px chip holding only an icon.
local function toggle(name: string, order: number, onActivate: () -> ()): TextButton
	return Kit.chip("", onActivate, {
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(Kit.MIN_TOUCH, Kit.MIN_TOUCH),
	})
end

-- `strike` strikes a glyph through (an icon with no "off" form); `always`
-- strikes an uploaded image too (the admin's clock, D-081, has none).
local function paintToggle(
	button: TextButton,
	on: boolean,
	icon: string,
	label: string,
	strike: boolean,
	always: boolean?
)
	for _, child in button:GetChildren() do
		if child.Name == "Icon" or child.Name == "Slash" then
			child:Destroy()
		end
	end
	local tint = if on then Kit.colors.accent else Kit.colors.muted
	local glyph = Kit.icon(icon, TOGGLE_ICON, tint)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Parent = button
	if strike and (always == true or glyph:IsA("TextLabel")) then
		-- The glyph has no "off" form: strike it through (as Header's sound button).
		Kit.new("Frame", {
			Name = "Slash",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(TOGGLE_ICON, 2),
			Rotation = -45,
			BackgroundColor3 = tint,
			BorderSizePixel = 0,
			Parent = button,
		})
	end
	button:SetAttribute("On", on)
	button:SetAttribute("Label", label)
	Kit.setSelected(button, on)
end

function Settings.corner(props: { [string]: any }?): Frame
	local p: { [string]: any } = props or {}
	local pairWidth = 2 * Kit.MIN_TOUCH + Kit.space.sm
	local timersOff: boolean? = nil -- the admin toggle (D-081); nil: not shown
	local root = Kit.box({
		Name = p.Name or "CornerSettings",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(TIP_W + Kit.space.sm + pairWidth, Kit.MIN_TOUCH),
		ZIndex = 5,
	})
	local pair = Kit.box({
		Name = "Toggles",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, pairWidth, 1, 0),
		Parent = root,
	})
	local list = Kit.list("Horizontal", Kit.space.sm)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.Parent = pair

	-- The tooltip at the pair's left, on the same row.
	local tip = Kit.text("", {
		Name = "SettingsTip",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -(pairWidth + Kit.space.sm), 0.5, 0),
		Size = UDim2.fromOffset(TIP_W, TIP_H),
		BackgroundTransparency = 0,
		BackgroundColor3 = Kit.colors.raised,
		TextSize = Kit.size.caption,
		Font = Kit.font.medium,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Visible = false,
		ZIndex = 6,
		Parent = root,
	})
	Kit.corner(Kit.radius.control).Parent = tip

	local hovered: TextButton? = nil
	local tipToken = 0
	local function showTip(button: TextButton?, linger: boolean)
		tipToken += 1
		if button == nil then
			tip.Visible = false
			return
		end
		tip.Text = tostring(button:GetAttribute("Label") or "")
		tip.Visible = true
		if linger then
			local token = tipToken
			task.delay(Settings.TIP_SECONDS, function()
				if token == tipToken and hovered == nil then
					tip.Visible = false
				end
			end)
		end
	end

	local sound: TextButton
	local motion: TextButton
	local render: () -> ()
	sound = toggle("SoundToggle", 1, function()
		Audio.setMuted(not Audio.muted())
		if not Audio.muted() then
			Audio.play("select")
		end
		render()
		showTip(sound, true)
	end)
	motion = toggle("MotionToggle", 2, function()
		Motion.setReduced(not Motion.reduced())
		render()
		showTip(motion, true)
	end)
	sound.Parent = pair
	motion.Parent = pair
	-- Admins only (D-081): turn the choice timers off in their own matches.
	local timers: TextButton
	timers = toggle("TimersToggle", 0, function()
		local off = not (timersOff == true)
		timersOff = off
		render()
		showTip(timers, true)
		local onTimers = p.onTimers
		if onTimers then
			onTimers(off)
		end
	end)
	timers.Visible = false
	timers.Parent = pair
	for _, button in { sound, motion, timers } do
		local function enter()
			hovered = button
			showTip(button, false)
		end
		local function leave()
			if hovered == button then
				hovered = nil
				showTip(nil, false)
			end
		end
		button.MouseEnter:Connect(enter)
		button.MouseLeave:Connect(leave)
		button.SelectionGained:Connect(enter)
		button.SelectionLost:Connect(leave)
	end

	render = function()
		local on = not Audio.muted()
		paintToggle(sound, on, if on then "volume-2" else "volume-x", Settings.soundLabel(on), not on)
		local reduced = Motion.reduced()
		paintToggle(motion, reduced, "sparkles", Settings.motionLabel(reduced), false)
		-- The admin toggle widens the row by one button while it shows.
		local off = timersOff
		timers.Visible = off ~= nil
		if off ~= nil then
			paintToggle(timers, off, "clock", Settings.timersLabel(off), off, true)
		end
		local width = pairWidth + (if off ~= nil then Kit.MIN_TOUCH + Kit.space.sm else 0)
		pair.Size = UDim2.new(0, width, 1, 0)
		root.Size = UDim2.fromOffset(TIP_W + Kit.space.sm + width, Kit.MIN_TOUCH)
		tip.Position = UDim2.new(1, -(width + Kit.space.sm), 0.5, 0)
		local shown = hovered
		if tip.Visible and shown then
			tip.Text = tostring(shown:GetAttribute("Label") or "")
		end
	end
	render()

	-- Follow changes from anywhere (the Help sheet's chips); a destroyed corner
	-- drops its connections on the next change.
	local connections: { any } = {}
	local function follow()
		if root.Parent == nil then
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			return
		end
		render()
	end
	table.insert(connections, Audio.changed:Connect(follow))
	table.insert(connections, Motion.changed:Connect(follow))
	timerSetters[root] = function(off: boolean?)
		timersOff = off
		render()
	end

	if p.Parent then
		root.Parent = p.Parent
	end
	return root
end

-- Shows a corner's admin toggle with `off` (the saved "Timers off", D-081), or
-- hides it (nil: not an admin).
function Settings.setTimers(corner: Frame, off: boolean?)
	local set = timerSetters[corner]
	if set then
		set(off)
	end
end

return Settings
