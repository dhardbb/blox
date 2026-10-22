--!strict
-- Shared type definitions for the simulation, server, and client.

export type Issue =
	"Jobs"
	| "Health"
	| "Schools"
	| "Environment"
	| "Safety"
	| "Transit"
	| "Technology"
	| "Farms"

export type Region =
	"NewEngland"
	| "MidAtlantic"
	| "GreatLakes"
	| "Plains"
	| "SouthAtlantic"
	| "DeepSouth"
	| "SouthCentral"
	| "Mountain"
	| "Pacific"

-- Weekly event types (Sim/Events.luau, DESIGN.md D-027).
export type EventKind = "Spotlight" | "Regional" | "Windfall" | "Choice"

-- A player's secret stance on a Choice event: one of the event's three stance
-- slots (Sim/Events.luau). "A" and "B" are the two opposed positions, "C" the hedge.
export type Choice = "A" | "B" | "C"

-- Static data for one state (see Sim/StateData.luau).
export type StateRecord = {
	id: string, -- postal code, e.g. "OH"
	name: string,
	ev: number, -- electoral votes
	pop: number, -- population in millions
	region: Region,
	issues: { Issue }, -- exactly two top issues
	adjacent: { string }, -- ids of states sharing a land border
	lat: number, -- geographic center
	lon: number,
}

return {}
