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
	-- Marker inks (D-102, whiteboard; were D-067's bright picks for a navy
	-- stage): each reads at 4.5:1 or more as text on the board, paper and
	-- raised; map fills blend them toward the board. Red and blue stay the default pair.
	Crimson = rgb(200, 20, 70), -- red marker, a cherry: 43 (CIE76) from the loss orange
	Cobalt = rgb(31, 91, 208), -- blue marker
	Emerald = rgb(11, 115, 67), -- green marker
	Amber = rgb(116, 104, 0), -- an olive gold: a bright yellow ink can't be read on white, a mustard is too near the loss orange
	Violet = rgb(140, 40, 210),
	Teal = rgb(8, 108, 124),
} :: { [string]: RGB })

-- Neutrals (D-102, whiteboard; were D-056/D-067's navy stage): an off-white
-- dry-erase board, paper cards on it, black marker for lines and text.
Colors.background = rgb(243, 241, 234) -- the board behind everything
Colors.field = rgb(248, 246, 240) -- text boxes and read-only wells (between the board and paper)
Colors.surface = rgb(251, 250, 245) -- paper cards and panels
Colors.surfaceTop = rgb(255, 254, 250) -- top stop of a card's top-light gradient (bottom: surface)
Colors.raised = rgb(236, 232, 222) -- magnetic labels, chips, tags
Colors.raisedTop = rgb(242, 239, 231) -- top stop of a raised panel's gradient (bottom: raised)
Colors.raisedHover = rgb(225, 220, 205) -- a selected chip
Colors.raisedLip = rgb(196, 190, 174) -- the shadow under a secondary button: a magnet's edge on the board
Colors.line = rgb(143, 139, 128) -- hairlines, map adjacency lines, dividers (never text)
Colors.text = rgb(29, 29, 31) -- black marker: 16.1:1 on paper, 14.9:1 on the board
Colors.muted = rgb(87, 84, 76) -- pencil grey: 7.2:1 on paper, 6.2:1 on raised
Colors.neutral = rgb(243, 241, 234) -- a state nobody leads: blank board, so a lead blends toward its ink
Colors.undecided = rgb(143, 139, 128) -- the undecided ring: pencil grey
Colors.sticky = rgb(255, 242, 168) -- a sticky note: coach tips, the week's event (ink on it 15:1)
Colors.ghost = rgb(228, 225, 216) -- erased-marker ghosting on the board (texture and flat fallback only)

-- Accent (D-102, replacing D-058's white, which can't show on a white
-- board): black marker for "press here / selected".
Colors.accent = rgb(29, 29, 31) -- the primary button's face, selection outline, timer
Colors.accentEdge = rgb(0, 0, 0) -- the primary button's 2 px edge
Colors.accentLip = rgb(120, 116, 106) -- the shadow under the primary (on the board)
Colors.onAccent = Colors.background -- text on an accent fill (14.9:1)

-- Status (D-056, darkened for the board in D-102): green is a gain; orange is
-- anything against you. Red is a player color, so it never means "bad".
Colors.good = rgb(23, 114, 58) -- a gain (5.7:1 on paper)
Colors.goodEdge = rgb(14, 80, 40) -- the stroke of a good fill (a filled "You win" pill)
Colors.loss = rgb(176, 74, 0) -- a loss, a warning, an error: burnt orange (5.1:1 on paper, 4.5:1 on raised); always with a sign or a word
Colors.lossEdge = rgb(124, 52, 0) -- the stroke or lip of a loss fill
Colors.onLoss = Colors.background -- text on a loss fill (4.9:1)
Colors.warn = Colors.loss -- one orange: "be careful" and "you lost" read the same
Colors.danger = Colors.loss -- the old name for a loss or an error; kept for every caller
Colors.disabledText = Colors.muted -- labels of disabled buttons
Colors.glow = rgb(228, 225, 216) -- the tint of the map's backdrop: an erased smudge
-- A key state's mark (D-102, was D-101's pale gold): highlighter yellow, a
-- band inside the state's border, never text.
Colors.keyGold = rgb(255, 227, 71)
-- Gold (the Daily Race, first medals, the 270 badge; was the Amber player
-- color, now too dark to read as gold): the same highlighter, with ink on it.
Colors.highlight = Colors.keyGold

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

-- Readable text on a fill of `color`: black marker (text) on light fills,
-- the board's off-white on dark ones (D-102: the board is the light one now).
function Colors.onColor(color: RGB): RGB
	return if Colors.luma(color) > 0.5 then Colors.text else Colors.background
end

-- WCAG relative luminance (sRGB), 0 for black to 1 for white.
local function luminance(color: RGB): number
	local function channel(v: number): number
		local c = v / 255
		return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b)
end

-- WCAG contrast ratio between two colors, 1 to 21.
function Colors.contrast(a: RGB, b: RGB): number
	local x, y = luminance(a), luminance(b)
	return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end

Colors.TEXT_CONTRAST = 4.5 -- what textOn guarantees on a card's lit top (surfaceTop)
local LIFT_STEP = 0.05 -- textOn's search step, for darkening (brightening) and for the tint toward text

-- The readable variant of a color for text on a card (D-067, turned around for
-- the board in D-102): the color itself when it already reads at TEXT_CONTRAST
-- on surfaceTop; else, on a light ground, the same color darkened (channels
-- scaled down, so the hue stays), on a dark ground brightened; and only if that
-- is not enough, tinted toward `text` as little as it takes. Every player ink
-- already reads, so they stay as they are. Fills, dots, bars and rings keep the
-- base color.
function Colors.textOn(color: RGB): RGB
	local ground = Colors.surfaceTop
	if Colors.contrast(color, ground) >= Colors.TEXT_CONTRAST then
		return { r = color.r, g = color.g, b = color.b }
	end
	local light = luminance(ground) > 0.5
	local top = math.max(color.r, color.g, color.b, 1)
	local step = 1
	while true do
		local k = if light then 1 - step * LIFT_STEP else 1 + step * LIFT_STEP
		if k <= 0 or top * k > 255 then
			break
		end
		local shifted = {
			r = math.floor(color.r * k + 0.5),
			g = math.floor(color.g * k + 0.5),
			b = math.floor(color.b * k + 0.5),
		}
		if Colors.contrast(shifted, ground) >= Colors.TEXT_CONTRAST then
			return shifted
		end
		step += 1
	end
	local base = if light
		then color
		else {
			r = math.min(255, math.floor(color.r * 255 / top + 0.5)),
			g = math.min(255, math.floor(color.g * 255 / top + 0.5)),
			b = math.min(255, math.floor(color.b * 255 / top + 0.5)),
		}
	for k = 0, math.round(1 / LIFT_STEP) do
		local lifted = Colors.tint(base, Colors.text, k * LIFT_STEP)
		if Colors.contrast(lifted, ground) >= Colors.TEXT_CONTRAST then
			return lifted
		end
	end
	return { r = Colors.text.r, g = Colors.text.g, b = Colors.text.b }
end

-- Player color by name, neutral if unknown (e.g. before Select ends).
function Colors.of(name: string?): RGB
	return if name ~= nil and Colors.player[name] ~= nil then Colors.player[name] else Colors.neutral
end

Colors.FULL_MARGIN = 12 -- poll margin (points) at which a state shows its leader's full color
Colors.FILL_CURVE = 0.6 -- stateFill's share is (margin / FULL_MARGIN) ^ this: a small lead already reads as its color (D-067)

-- Fill for a state from its public poll: neutral at a tie, moving to the leader's
-- color as the margin grows to FULL_MARGIN, quickly at first (FILL_CURVE): a
-- 3-point lead is 44 % of the way, 6 points 66 %. `support` is by player index.
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
	local share = math.clamp((best - second) / Colors.FULL_MARGIN, 0, 1) ^ Colors.FILL_CURVE
	return Colors.tint(Colors.neutral, colors[leader] or Colors.neutral, share)
end

-- Map bands (display only, docs/DESIGN.md D-053): a state's fill steps by its
-- poll margin in points instead of blending. `below` is the band's upper bound
-- (exclusive); `share` is how far from neutral toward the leader's color.
export type Band = {
	name: string, -- "tossup" | "lean" | "likely" | "safe"
	below: number,
	share: number,
}

Colors.BANDS = table.freeze({
	table.freeze({ name = "tossup", below = 3, share = 0 }),
	table.freeze({ name = "lean", below = 8, share = 0.6 }), -- was 0.45: a lean reads as the color, deep (D-067)
	table.freeze({ name = "likely", below = 15, share = 0.82 }), -- was 0.75
	table.freeze({ name = "safe", below = math.huge, share = 1 }),
} :: { Band })

-- The band for a poll margin in points (the leader's share minus the runner-up's).
function Colors.band(margin: number): Band
	local m = math.abs(margin)
	for _, band in Colors.BANDS do
		if m < band.below then
			return band
		end
	end
	return Colors.BANDS[#Colors.BANDS]
end

-- Banded fill for a state from its public poll: neutral for a toss-up, then
-- 60 / 82 / 100 % of the leader's color. Same inputs as stateFill.
function Colors.bandFill(support: { number }?, colors: { RGB }): RGB
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
	local band = Colors.band(best - second)
	return Colors.tint(Colors.neutral, colors[leader] or Colors.neutral, band.share)
end

return table.freeze(Colors)
