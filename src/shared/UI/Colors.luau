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
	Amber = rgb(240, 186, 36), -- hue 44: gold, kept clear of the loss orange (D-056)
	Violet = rgb(146, 84, 214),
	Teal = rgb(24, 168, 178),
} :: { [string]: RGB })

-- Neutrals (D-056): a navy stage, each step about 7 L* lighter than the last.
Colors.background = rgb(13, 17, 30) -- the stage behind everything
Colors.field = rgb(18, 23, 38) -- text boxes and read-only wells (between background and surface)
Colors.surface = rgb(24, 30, 48) -- cards and panels
Colors.surfaceTop = rgb(31, 38, 60) -- top stop of a card's top-light gradient (bottom: surface)
Colors.raised = rgb(38, 46, 70) -- buttons, chips, tags
Colors.raisedTop = rgb(46, 55, 82) -- top stop of a raised panel's gradient (bottom: raised)
Colors.raisedHover = rgb(54, 64, 94) -- a selected chip
Colors.raisedLip = rgb(9, 12, 22) -- the lip under a secondary button: darker than the stage, so it reads on any surface
Colors.line = rgb(70, 80, 112) -- hairlines (at 0.5 transparency), map adjacency lines, dividers
Colors.text = rgb(240, 243, 250) -- 14.9:1 on surface
Colors.muted = rgb(158, 168, 194) -- 7.0:1 on surface, 5.7:1 on raised
Colors.neutral = rgb(118, 124, 142) -- a state nobody leads
Colors.undecided = rgb(190, 196, 210) -- the undecided ring

-- Accent (D-058, was pink in D-051): white, "press here / selected". Color is
-- kept for meaning (players, gains, losses); the accent is a near-white, lighter
-- than every player and status color and a touch brighter than `text`.
Colors.accent = rgb(244, 246, 252) -- the primary button's face, selection outline, timer
Colors.accentEdge = rgb(196, 204, 224) -- the primary button's 2 px edge (cool light grey)
Colors.accentLip = rgb(110, 122, 158) -- the slate lip under the primary (2.4:1 on its shaded face, 3.9:1 on surface)
Colors.onAccent = Colors.background -- text on an accent fill (17.4:1)

-- Status (D-056): green is a gain; orange is anything against you. Red is a
-- player color, so it never means "bad".
Colors.good = rgb(92, 200, 128) -- a gain (7.9:1 on surface)
Colors.goodEdge = rgb(64, 136, 94) -- the stroke of a good fill (a filled "You win" pill)
Colors.loss = rgb(255, 122, 40) -- a loss, a warning, an error (6.4:1 on surface); always with a sign or a word
Colors.lossEdge = rgb(196, 84, 20) -- the stroke or lip of a loss fill
Colors.onLoss = Colors.background -- text on a loss fill (7.2:1)
Colors.warn = Colors.loss -- one orange: "be careful" and "you lost" read the same
Colors.danger = Colors.loss -- the old name for a loss or an error; kept for every caller
Colors.disabledText = Colors.muted -- labels of disabled buttons
Colors.glow = rgb(44, 62, 120) -- the tint of the map's backdrop glow

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

-- The readable variant of a player color for text on a dark surface: a quarter
-- of the way toward `text` (Crimson -> 214,100,116, 4.7:1 on surface). Fills,
-- dots, bars and rings keep the base color (D-056).
function Colors.textOn(color: RGB): RGB
	return Colors.tint(color, Colors.text, 0.25)
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
	table.freeze({ name = "lean", below = 8, share = 0.45 }),
	table.freeze({ name = "likely", below = 15, share = 0.75 }),
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
-- 45 / 75 / 100 % of the leader's color. Same inputs as stateFill.
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
