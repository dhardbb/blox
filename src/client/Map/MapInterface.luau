--!strict
-- What every map implementation offers. The MVP is NodeMap (circles); a later
-- ShapeMap with real state shapes implements the same interface (PLAN.md).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local View = require(ReplicatedStorage.Shared.Sim.View)

-- Per-state decoration a screen can ask for.
export type Mark = {
	ring: Color3?, -- outline color (e.g. a drafted state's owner)
	badge: string?, -- one short glyph shown above the node (e.g. "H" home, "B" battleground)
	dim: boolean?, -- fade the node (e.g. not pickable this round)
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
