--!strict
-- A round check badge that marks a pick (D-091): a candidate card, an issue
-- tile, a stance. A filled circle in a color (the player's own, or the accent)
-- with a ✓ in the readable color on it, edged in the background color so it
-- reads on any card. It pops in when it appears (Motion.pop, so nothing under
-- reduced motion) and simply hides when the pick goes away.
--
--   local badge = CheckBadge.new({ Parent = card, Position = ..., AnchorPoint = ... })
--   CheckBadge.set(badge, on, color?)   -- shows or hides it; color repaints the fill
--
-- The badge is Frame "Check" (attribute Overhang: it may sit on a portrait's
-- rim) with TextLabel "Mark". Its fill is the player's color, so it is marked
-- Kit.dataColor. Place it in a parent without a list layout (a list would
-- move it into the flow).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)

local Kit = require(script.Parent.Kit)
local Motion = require(script.Parent.Motion)

local CheckBadge = {}

CheckBadge.SIZE = 24 -- px, the badge's circle
local EDGE = 2 -- px, its outline in the background color
local POP_FROM = 0.5 -- scale it pops from when it appears

function CheckBadge.new(props: { [string]: any }?): Frame
	local badge = Kit.dataColor(Kit.new("Frame", {
		Name = "Check",
		Size = UDim2.fromOffset(CheckBadge.SIZE, CheckBadge.SIZE),
		BackgroundColor3 = Kit.colors.accent,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 5,
	})) :: Frame
	badge:SetAttribute("Overhang", true)
	Kit.round().Parent = badge
	Kit.new("UIStroke", {
		Name = "Edge",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Kit.colors.background,
		Thickness = EDGE,
		Parent = badge,
	})
	Kit.text(Kit.glyph.check, {
		Name = "Mark",
		Size = UDim2.fromScale(1, 1),
		Font = Kit.font.bold,
		TextSize = Kit.size.caption,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Kit.colors.onAccent,
		ZIndex = 6,
		Parent = badge,
	})
	if props then
		for key, value in props do
			(badge :: any)[key] = value
		end
	end
	return badge
end

-- Shows (popping in) or hides the badge; `color` repaints its fill and mark.
function CheckBadge.set(badge: Frame, on: boolean, color: Color3?)
	if color then
		badge.BackgroundColor3 = color
		local mark = badge:FindFirstChild("Mark") :: TextLabel?
		if mark then
			mark.TextColor3 = Kit.color(Colors.onColor(Kit.rgb(color)))
		end
	end
	if on and not badge.Visible then
		badge.Visible = true
		Motion.pop(badge, POP_FROM)
	elseif not on then
		badge.Visible = false
	end
end

return CheckBadge
