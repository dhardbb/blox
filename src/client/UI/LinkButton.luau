--!strict
-- A text link (D-091): "About Goldie →", "Rename →", "How the draft works →".
-- A ghost button whose label is right-aligned with an arrow after it, in a
-- target taller and wider than the words (LinkButton.HEIGHT), so it reads as
-- "more over here" and is easy to hit. It replaces the loose ghost buttons
-- whose words floated in the middle of a wide empty box.
--
--   local link = LinkButton.new("About Goldie", onTap, { Name = "Details", Parent = row, ... })
--   link.Text = "How issues work"          -- the label is the button's own Text
--
-- The arrow is TextLabel "Arrow" in the button's right padding (the label stops
-- before it). Props are set on the TextButton as for Kit.button.

local Kit = require(script.Parent.Kit)

local LinkButton = {}

LinkButton.HEIGHT = 48 -- px, the link's tap target (Kit.MIN_TOUCH is the floor)
LinkButton.ARROW = 20 -- px, the arrow's box

function LinkButton.new(text: string, onTap: () -> (), props: { [string]: any }?): TextButton
	local base: { [string]: any } = {
		variant = "ghost",
		Size = UDim2.new(1, 0, 0, LinkButton.HEIGHT),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Kit.font.bold,
	}
	if props then
		for key, value in props do
			base[key] = value
		end
	end
	local button = Kit.button(text, onTap, base)
	local pad = button:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingRight = UDim.new(0, LinkButton.ARROW + Kit.space.sm)
	end
	Kit.text(Kit.glyph.arrow, {
		Name = "Arrow",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(1, Kit.space.xs, 0.5, 0),
		Size = UDim2.fromOffset(LinkButton.ARROW, LinkButton.ARROW),
		Font = Kit.font.bold,
		TextSize = Kit.size.body,
		TextScaled = true,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Kit.colors.muted,
		Parent = button,
	})
	return button
end

return LinkButton
