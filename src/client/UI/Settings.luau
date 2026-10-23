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

local Audio = require(script.Parent.Audio)
local Kit = require(script.Parent.Kit)
local Motion = require(script.Parent.Motion)

local Settings = {}

local ICON = 24 -- px, a chip's icon plate (Kit.iconPlate)

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

return Settings
