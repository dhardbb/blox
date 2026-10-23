--!strict
-- Color tokens for the client, as plain {r, g, b} 0-255 tables so this module stays
-- pure (the client turns them into Color3 with Color3.fromRGB). Player colors are
-- the six picks from character select; none pairs into a real party's colors.
--
-- Design system (docs/DESIGN.md D-030): these are the only colors the client
-- uses. Data colors (map fills, player colors, feed tints) are derived from them
-- through stateFill, tint and onColor, never written as literals in a screen.

export type RGB = { r: number, g: number, b: number }

local Colors = {}

local function rgb(r: number, g: number, b: number): RGB
	return table.freeze({ r = r, g = g, b = b })
end

Colors.player = table.freeze({
	Crimson = rgb(206, 52, 72),
	Cobalt = rgb(52, 104, 214),
	Emerald = rgb(36, 168, 108),
	Amber = rgb(232, 164, 40),
	Violet = rgb(146, 84, 214),
	Teal = rgb(24, 168, 178),
} :: { [string]: RGB })

Colors.background = rgb(16, 18, 24)
Colors.surface = rgb(28, 31, 40) -- panels
Colors.raised = rgb(40, 44, 56) -- buttons, cards
Colors.raisedHover = rgb(56, 62, 78)
Colors.line = rgb(64, 70, 86) -- map adjacency lines, dividers
Colors.text = rgb(234, 236, 242)
Colors.muted = rgb(150, 156, 172)
Colors.neutral = rgb(118, 122, 134) -- a state nobody leads
Colors.undecided = rgb(190, 194, 204) -- the undecided ring
Colors.accent = rgb(255, 128, 214) -- pink: the primary button, selection outline, timer; far from every player color (D-051)
Colors.danger = rgb(232, 84, 84)
Colors.good = rgb(92, 200, 128)
Colors.onAccent = Colors.background -- text on an accent fill
Colors.field = rgb(22, 25, 33) -- text boxes and read-only wells (between background and surface)
Colors.warn = rgb(255, 150, 64) -- warning text and icons, never a fill (docs/UI-STYLE.md); not the accent, so "careful" never looks like "press here"
Colors.disabledText = Colors.muted -- labels of disabled buttons

-- Linear blend from `base` toward `color`, t in [0, 1]. Used for map fills, the
-- Election feed rows (0.35) and the draft board legend (0.6).
function Colors.tint(base: RGB, color: RGB, t: number): RGB
	local k = math.clamp(t, 0, 1)
	return {
		r = math.floor(base.r + (color.r - base.r) * k + 0.5),
		g = math.floor(base.g + (color.g - base.g) * k + 0.5),
		b = math.floor(base.b + (color.b - base.b) * k + 0.5),
	}
end

-- The old name for tint; kept so existing callers keep working.
Colors.mix = Colors.tint

-- Luma (Rec. 709 weights on 0-255 channels), 0 for black to 1 for white.
function Colors.luma(color: RGB): number
	return (0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b) / 255
end

-- Readable text on a fill of `color`: dark (background) on light fills such as
-- Amber, Teal and Emerald, light (text) on dark ones.
function Colors.onColor(color: RGB): RGB
	return if Colors.luma(color) > 0.5 then Colors.background else Colors.text
end

-- Player color by name, neutral if unknown (e.g. before Select ends).
function Colors.of(name: string?): RGB
	return if name ~= nil and Colors.player[name] ~= nil then Colors.player[name] else Colors.neutral
end

Colors.FULL_MARGIN = 12 -- poll margin (points) at which a state shows its leader's full color

-- Fill for a state from its public poll: neutral at a tie, moving to the leader's
-- color as the margin grows to FULL_MARGIN. `support` is by player index.
function Colors.stateFill(support: { number }?, colors: { RGB }): RGB
	if support == nil or #support < 2 then
		return Colors.neutral
	end
	local best, second, leader = -math.huge, -math.huge, 0
	for p, share in support do
		if share > best then
			second, best, leader = best, share, p
		elseif share > second then
			second = share
		end
	end
	if best == second or leader == 0 then
		return Colors.neutral
	end
	return Colors.tint(Colors.neutral, colors[leader] or Colors.neutral, (best - second) / Colors.FULL_MARGIN)
end

return table.freeze(Colors)
