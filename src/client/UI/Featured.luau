--!strict
-- A featured button (docs/DESIGN.md D-090): a secondary Kit.button that stands
-- out as the main thing to press where it is, without being the screen's
-- PrimaryAction: "Invite a friend" in the friend sheet, "Play the tutorial" on
-- How to play's last page (both in the accent look, which the UI audit allows
-- inside an open sheet), and the Daily Race card's Play (gold: the Daily
-- Race's color). The face takes the fill, dark text in Fredoka and a darker
-- lip; turning it off restores the secondary look. Attribute Featured = true
-- while on.
--
--   Featured.set(button, Kit.colors.accent)   -- on, in that fill
--   Featured.set(button, nil)                 -- back to a plain secondary

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)

local Kit = require(script.Parent.Kit)

local Featured = {}

Featured.LIP_SHADE = 0.45 -- the lip: the fill this far toward the stage color

-- The Daily Race's color: the gold player color, never a "good" or "bad" signal.
Featured.GOLD = Kit.color(Colors.player.Amber)

function Featured.set(button: TextButton, fill: Color3?)
	local lip = Kit.outer(button):FindFirstChild("Lip") :: Frame?
	if fill then
		button.BackgroundColor3 = fill
		button.TextColor3 = Kit.colors.onAccent
		button.Font = Kit.font.display
		local edge = if fill == Kit.colors.accent then Kit.colors.accentEdge else fill
		Kit.bevel(button, edge, 2, 1)
		if lip then
			local k, stage = Featured.LIP_SHADE, Kit.colors.background
			lip.BackgroundColor3 = Color3.new(
				fill.R + (stage.R - fill.R) * k,
				fill.G + (stage.G - fill.G) * k,
				fill.B + (stage.B - fill.B) * k
			)
		end
		button:SetAttribute("Featured", true)
	else
		button.BackgroundColor3 = Kit.colors.raised
		button.TextColor3 = Kit.colors.text
		button.Font = Kit.font.medium
		Kit.bevel(button)
		if lip then
			lip.BackgroundColor3 = Kit.colors.raisedLip
		end
		button:SetAttribute("Featured", nil)
	end
end

return Featured
