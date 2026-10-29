--!strict
-- The public landslide count next to a name (docs/DESIGN.md D-094): a small
-- gold pill "▲3", shown only from 1 up. The count is the player's landslide
-- wins in rated public matches (the queue), from the server: the Lobby's
-- profile summary (`landslides`), a leaderboard entry (`landslides`) and a
-- match seat (SeatInfo.landslides). Read-only; it never takes a tap.
--
--   local badge = LandslideBadge.new(count, props?)  -- TextLabel "LandslideBadge", or nil under 1
--   LandslideBadge.text(count)                       -- "▲3" ("" under 1)
--   LandslideBadge.words(count)                      -- "3 landslides" (a caption or tooltip)
--   LandslideBadge.line(count)                       -- "▲3 landslides" ("" under 1), for a text line
--   LandslideBadge.WIDTH                             -- px a caller reserves for a badge up to 999
--
-- Screens place it themselves (beside a name, inside a row); it sizes to its
-- text (AutomaticSize X) at Kit.PILL_H tall unless props say otherwise.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)

local Kit = require(script.Parent.Kit)

local LandslideBadge = {}

LandslideBadge.WIDTH = 48 -- px: a pill with "▲999" at caption size, padding included
-- Gold, the leaderboard's first medal (the Amber player color): a data color,
-- kept clear of the loss orange, so the badge is marked Kit.dataColor.
local GOLD = Kit.color(Colors.player.Amber)

local function whole(count: any): number
	if type(count) ~= "number" or count ~= count or count == math.huge then
		return 0
	end
	return math.max(0, math.floor(count))
end

function LandslideBadge.text(count: number?): string
	local n = whole(count)
	return if n >= 1 then `{Kit.glyph.up}{n}` else ""
end

function LandslideBadge.words(count: number?): string
	local n = whole(count)
	return if n == 1 then "1 landslide" else `{n} landslides`
end

function LandslideBadge.line(count: number?): string
	local n = whole(count)
	return if n >= 1 then `{LandslideBadge.text(n)} {if n == 1 then "landslide" else "landslides"}` else ""
end

-- The pill, or nil for no landslides. `props` go to the label (Name, Position,
-- LayoutOrder, Parent…).
function LandslideBadge.new(count: number?, props: { [string]: any }?): TextLabel?
	local n = whole(count)
	if n < 1 then
		return nil
	end
	local merged: { [string]: any } = {
		Name = "LandslideBadge",
		Font = Kit.font.bold,
		TextColor3 = GOLD,
	}
	local given: { [string]: any } = props or {}
	for key, value in given do
		merged[key] = value
	end
	local label = Kit.dataColor(Kit.pill(LandslideBadge.text(n), "text", merged))
	label:SetAttribute("Landslides", n)
	return label
end

return LandslideBadge
