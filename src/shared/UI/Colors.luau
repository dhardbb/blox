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
	-- Deep, saturated picks (D-067, were lighter and greyer in D-056). Every pair
	-- is at least 19 CIEDE2000 (39 CIE76) apart and each is at least 27 (45) from
	-- the loss orange; red and blue stay 42 (107) apart.
	Crimson = rgb(212, 28, 66), -- hue 348: a cherry red, a little cooler than the loss orange
	Cobalt = rgb(34, 98, 228),
	Emerald = rgb(0, 170, 96),
	Amber = rgb(246, 190, 8), -- hue 46: gold, kept clear of the loss orange (D-056)
	Violet = rgb(152, 56, 228), -- hue 273: pushed toward purple, away from Cobalt
	Teal = rgb(0, 164, 186),
} :: { [string]: RGB })

-- Neutrals (D-056): a navy stage, each step about 4 L* lighter than the last.
-- D-067 deepened the blue in every step (same lightness, about a third more
-- chroma), so the stage reads navy rather than grey.
Colors.background = rgb(11, 16, 34) -- the stage behind everything (was 13, 17, 30)
Colors.field = rgb(16, 23, 44) -- text boxes and read-only wells (between background and surface)
Colors.surface = rgb(22, 30, 55) -- cards and panels (was 24, 30, 48)
Colors.surfaceTop = rgb(29, 38, 68) -- top stop of a card's top-light gradient (bottom: surface)
Colors.raised = rgb(36, 47, 80) -- buttons, chips, tags (was 38, 46, 70)
Colors.raisedTop = rgb(44, 56, 93) -- top stop of a raised panel's gradient (bottom: raised)
Colors.raisedHover = rgb(52, 65, 106) -- a selected chip
Colors.raisedLip = rgb(8, 12, 26) -- the lip under a secondary button: darker than the stage, so it reads on any surface
Colors.line = rgb(68, 81, 124) -- hairlines (at 0.5 transparency), map adjacency lines, dividers
Colors.text = rgb(240, 243, 250) -- 14.8:1 on surface
Colors.muted = rgb(156, 168, 204) -- 7.0:1 on surface, 5.6:1 on raised
Colors.neutral = rgb(70, 78, 104) -- a state nobody leads: a dark slate, so a lead blends to a deep color, not a pastel (D-067, was 118, 124, 142)
Colors.undecided = rgb(164, 174, 204) -- the undecided ring: a slate that frames a fill without washing it (D-067, was 190, 196, 210)

-- Accent (D-058, was pink in D-051): white, "press here / selected". Color is
-- kept for meaning (players, gains, losses); the accent is a near-white, lighter
-- than every player and status color and a touch brighter than `text`.
Colors.accent = rgb(244, 246, 252) -- the primary button's face, selection outline, timer
Colors.accentEdge = rgb(196, 204, 224) -- the primary button's 2 px edge (cool light grey)
Colors.accentLip = rgb(110, 122, 158) -- the slate lip under the primary (2.4:1 on its shaded face, 3.9:1 on surface)
Colors.onAccent = Colors.background -- text on an accent fill (17.5:1)

-- Status (D-056): green is a gain; orange is anything against you. Red is a
-- player color, so it never means "bad".
Colors.good = rgb(80, 212, 96) -- a gain (8.6:1 on surface; D-067, was a minty 92, 200, 128)
Colors.goodEdge = rgb(50, 140, 66) -- the stroke of a good fill (a filled "You win" pill)
Colors.loss = rgb(255, 122, 40) -- a loss, a warning, an error (6.3:1 on surface); always with a sign or a word
Colors.lossEdge = rgb(196, 84, 20) -- the stroke or lip of a loss fill
Colors.onLoss = Colors.background -- text on a loss fill (7.3:1)
Colors.warn = Colors.loss -- one orange: "be careful" and "you lost" read the same
Colors.danger = Colors.loss -- the old name for a loss or an error; kept for every caller
Colors.disabledText = Colors.muted -- labels of disabled buttons
Colors.glow = rgb(40, 60, 136) -- the tint of the map's backdrop glow

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
local LIFT_STEP = 0.05 -- textOn's search step, for brightening and for the tint toward text

-- The readable variant of a player color for text on a dark surface (D-067, was
-- a fixed quarter toward `text` in D-056): the color itself when it already reads
-- at TEXT_CONTRAST on surfaceTop; else the same color brightened (channels scaled
-- up, so the hue and saturation stay); and only if full brightness is not enough,
-- tinted toward `text` as little as it takes. Crimson -> 252, 76, 113 (5.1:1 on
-- surface); Emerald, Teal and Amber stay as they are. Fills, dots, bars and rings
-- keep the base color.
function Colors.textOn(color: RGB): RGB
	local ground = Colors.surfaceTop
	if Colors.contrast(color, ground) >= Colors.TEXT_CONTRAST then
		return { r = color.r, g = color.g, b = color.b }
	end
	local top = math.max(color.r, color.g, color.b, 1)
	local k = 1 + LIFT_STEP
	while top * k <= 255 do
		local lifted = {
			r = math.floor(color.r * k + 0.5),
			g = math.floor(color.g * k + 0.5),
			b = math.floor(color.b * k + 0.5),
		}
		if Colors.contrast(lifted, ground) >= Colors.TEXT_CONTRAST then
			return lifted
		end
		k += LIFT_STEP
	end
	local bright = {
		r = math.min(255, math.floor(color.r * 255 / top + 0.5)),
		g = math.min(255, math.floor(color.g * 255 / top + 0.5)),
		b = math.min(255, math.floor(color.b * 255 / top + 0.5)),
	}
	for step = 0, math.round(1 / LIFT_STEP) do
		local lifted = Colors.tint(bright, Colors.text, step * LIFT_STEP)
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
