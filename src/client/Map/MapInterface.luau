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

export type Map = {
	root: GuiObject, -- the map box; parent it, size it, it keeps its own aspect ratio
	-- Fill colors from public polls, undecided rings, leans before polls exist.
	setView: (self: Map, view: View.View, colors: { Colors.RGB }) -> (),
	setMarks: (self: Map, marks: { [string]: Mark }) -> (),
	-- The candidate's planned route, in order; `flights[k]` marks a flown hop into stop k.
	setRoute: (self: Map, stops: { string }, flights: { boolean }) -> (),
	select: (self: Map, id: string?) -> (),
	onSelect: (self: Map, handler: (id: string) -> ()) -> (),
	destroy: (self: Map) -> (),
}

return {}
