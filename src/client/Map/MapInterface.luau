--!strict
-- What every map implementation offers. The MVP is NodeMap (circles); a later
-- ShapeMap with real state shapes implements the same interface (PLAN.md).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local View = require(ReplicatedStorage.Shared.Sim.View)

-- Per-state decoration a screen can ask for.
export type Mark = {
	ring: Color3?, -- outline color (e.g. a drafted state's owner)
	badge: string?, -- one short glyph in the tag on the node's top edge (e.g. "H" home, "B" battleground, "+1.5")
	badgeColor: Color3?, -- the badge's color (default: accent)
	dim: boolean?, -- fade the node (e.g. not pickable this round)
	-- Momentum: a ▲ (or ▼) under the node. Show it for the leader only, in their color.
	arrow: ("up" | "down")?,
	arrowColor: Color3?, -- the arrow's color (default: the text color)
	-- A short word in the node's tag, after the badge (e.g. "FLIP" when the poll
	-- leader changes); the tag is then filled with noteColor (default: the text color).
	note: string?,
	noteColor: Color3?,
	-- A glow behind the circle (a state a stance or a debate moves), stronger
	-- for a state whose poll leader changes.
	halo: Color3?,
	haloStrong: boolean?,
}

-- One short pill in a state's lens row (Map/Lens): "17", "JOB", "+3", "$2.4".
export type LensPart = {
	text: string,
	color: Color3?, -- the text's color (default: the text color)
	filled: boolean?, -- fill the pill in `color` instead (e.g. an issue on your platform)
}

-- What the current lens shows under a state's label. Empty `parts` shows nothing.
export type LensLine = {
	parts: { LensPart },
	dim: boolean?, -- fade the node (e.g. a pool your plan already empties)
}

export type Map = {
	root: GuiObject, -- the map box; parent it, size it, it keeps its own aspect ratio
	-- Fill colors from public polls, undecided rings, leans before polls exist.
	setView: (self: Map, view: View.View, colors: { Colors.RGB }) -> (),
	setMarks: (self: Map, marks: { [string]: Mark }) -> (),
	-- The lens row under each state's label; states missing from `lines` show none.
	setLens: (self: Map, lines: { [string]: LensLine }) -> (),
	-- The candidate's planned route, in order; `flights[k]` marks a flown hop into stop k.
	setRoute: (self: Map, stops: { string }, flights: { boolean }) -> (),
	select: (self: Map, id: string?) -> (),
	-- Motion (UI/Motion; decorative ones do nothing under reduced motion):
	-- pulse: the circle bumps 1.15 -> 1 (and rings in `color` if given);
	-- ring: a ring in `color` grows out of the circle and fades;
	-- badge: a 16 px icon (UI/Icons name) at the node's top-right, nil removes it;
	-- wipe: the circle's fill turns to `color` (0.4 s) with a ring (an election call).
	pulse: (self: Map, id: string, color: Color3?) -> (),
	ring: (self: Map, id: string, color: Color3) -> (),
	badge: (self: Map, id: string, icon: string?) -> (),
	wipe: (self: Map, id: string, color: Color3) -> (),
	onSelect: (self: Map, handler: (id: string) -> ()) -> (),
	destroy: (self: Map) -> (),
}

return {}
