--!strict
-- Color tokens for the client, as plain {r, g, b} 0-255 tables so this module stays
-- pure (the client turns them into Color3 with Color3.fromRGB). Player colors are
-- the six picks from character select; none pairs into a real party's colors.

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
Colors.accent = rgb(255, 214, 102) -- timers, highlights
Colors.danger = rgb(232, 84, 84)
Colors.good = rgb(92, 200, 128)

-- Linear blend from a to b, t in [0, 1].
function Colors.mix(a: RGB, b: RGB, t: number): RGB
	local k = math.clamp(t, 0, 1)
	return {
		r = math.floor(a.r + (b.r - a.r) * k + 0.5),
		g = math.floor(a.g + (b.g - a.g) * k + 0.5),
		b = math.floor(a.b + (b.b - a.b) * k + 0.5),
	}
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
	return Colors.mix(Colors.neutral, colors[leader] or Colors.neutral, (best - second) / Colors.FULL_MARGIN)
end

return table.freeze(Colors)
