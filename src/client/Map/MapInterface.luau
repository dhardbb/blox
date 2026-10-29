--!strict
-- What every map implementation offers: ShapeMap (real state shapes, D-070)
-- and NodeMap's circles (the fallback until the shape images are uploaded).
-- NodeMap.new() picks one. setPins and setLegend came with the real map; the
-- rest is unchanged, so screens drive either map the same way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local View = require(ReplicatedStorage.Shared.Sim.View)

-- Per-state decoration a screen can ask for.
export type Mark = {
	ring: Color3?, -- outline color (e.g. a drafted state's owner)
	badge: string?, -- one short glyph in the tag on the node's top edge (e.g. "H" home, "B" battleground, "+1.5")
	badgeColor: Color3?, -- the badge's fill (default: accent); the map picks a readable text color
	dim: boolean?, -- fade the node (e.g. not pickable this round)
	-- Momentum: a ▲ (or ▼) under the node. Show it for the leader only, in their color.
	arrow: ("up" | "down")?,
	arrowColor: Color3?, -- the arrow's color (default: the text color)
	-- A short word in the node's tag, after the badge (e.g. "FLIP" when the poll
	-- leader changes); the tag is then a dark plate edged 2 px in noteColor
	-- (default: a hairline), white text.
	note: string?,
	noteColor: Color3?,
	-- A glow behind the circle (a state a stance or a debate moves), stronger
	-- for a state whose poll leader changes.
	halo: Color3?,
	haloStrong: boolean?,
	-- D-079: `ring` drawn dashed and 2 px (a state the final polls called
	-- wrong); `hollow`: the state drawn empty, a dark fill and a hairline
	-- outline (not called yet on election night).
	dashed: boolean?,
	hollow: boolean?,
	-- D-088: a key state this week (Shared/UI/KeyStates): a soft accent glow
	-- behind the state (a chip: a glowing plate around it) and a dashed accent
	-- outline where nothing else outlines it. An owner's ring keeps its color.
	key: boolean?,
}

-- One short pill in a state's lens row (Map/Lens): "17", "+3", "$2.4", or an
-- issue's symbol (D-076).
export type LensPart = {
	text: string, -- with `icon`: what the pill says while the symbol is missing ("JOB")
	icon: string?, -- an issue: the pill shows its symbol (Kit.issueIcon) instead of `text`
	color: Color3?, -- the text's color (default: the text color)
	filled: boolean?, -- fill the pill in `color` instead (e.g. an issue on your platform)
	outlined: boolean?, -- the battleground mark (D-058): field fill, a white outline, white text
	-- D-079: a Kit.icon name (Money's coin) drawn `glyphs` times (default 1)
	-- before the text, in `glyphColor` (default `color`); `text` may be "".
	-- (The real map draws an issue's `icon` alone, 20 px on a 24 px disc.)
	glyph: string?,
	glyphColor: Color3?,
	glyphs: number?,
	short: string?, -- D-092: what a small map (a phone's) shows instead of `text` ("5.2" for "$5.2")
}

-- A run of ground-game pips: `count` dots in `color`, hollow when it is the
-- opponent's ground game as your internal polls saw it (D-049).
export type Pips = {
	count: number,
	color: Color3,
	hollow: boolean?,
}

-- What the current lens shows under a state's label. Empty `parts` shows nothing.
export type LensLine = {
	parts: { LensPart },
	dim: boolean?, -- fade the node (e.g. a pool your plan already empties)
	-- Polls lens only (D-070): a small row under the parts. `momentum` is the
	-- momentum leader's color (a chevron: their support drifts up each week;
	-- `momentumStrong` doubles it); `pips` are ground-game units.
	momentum: Color3?,
	momentumStrong: boolean?,
	pips: { Pips }?,
	-- D-079: the Close filter's safe state: its fill at 40 % and no value.
	quiet: boolean?,
}

-- A candidate's pin on the state they are in (D-070).
export type Pin = {
	state: string,
	name: string, -- the candidate's name (a custom one if the viewer may see it): the face's initials until its portrait is uploaded
	candidate: string?, -- the candidate's id: their portrait (Kit.portrait); nil = a monogram of `name`
	color: Color3,
	tag: string, -- the word on the pin's flag: "You", or the rival's first name
	you: boolean?, -- your own pin (drawn on top)
	label: boolean?, -- show the flag at rest (the first week); else only while its state is selected (D-079)
}

-- One item of the map's small legend row (D-070): a mark and a word or two.
-- "none": the text alone; "issue": the symbol of `issue` (D-076). When the row
-- is too narrow (a phone), items with the highest `drop` go first, a whole
-- level at a time (nil: always shown).
export type LegendItem = {
	mark: "up" | "pip" | "hollow" | "none" | "issue" | "key", -- "key": a key state's glowing dashed swatch (D-088)
	issue: string?, -- mark "issue": which one
	color: Color3?,
	text: string,
	drop: number?,
}

-- The plan preview's number on a state (D-071): a faint signed tag, orange
-- when `negative` (the plan would cost you margin there).
export type PreviewTag = {
	text: string,
	negative: boolean?,
}

export type Map = {
	root: GuiObject, -- the map box; parent it, size it, it keeps its own aspect ratio
	-- Fill colors from public polls, undecided rings, leans before polls exist.
	-- `animate` (a reveal): a fill that changes tweens to its new color.
	setView: (self: Map, view: View.View, colors: { Colors.RGB }, animate: boolean?) -> (),
	setMarks: (self: Map, marks: { [string]: Mark }) -> (),
	-- The lens row under each state's label; states missing from `lines` show none.
	-- `fade`: the pills fade in (the player just switched lenses).
	setLens: (self: Map, lines: { [string]: LensLine }, fade: boolean?) -> (),
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
	-- shake: a short shake of the state (an election call landing; nothing
	-- under reduced motion).
	shake: (self: Map, id: string) -> (),
	-- ghost: while an action button is held, what it would do ("+4.1") as a
	-- see-through tag on the node; nil hides it. One ghost at a time.
	ghost: (self: Map, id: string, text: string?) -> (),
	onSelect: (self: Map, handler: (id: string) -> ()) -> (),
	-- Candidate pins (replaces the previous set; empty removes them).
	setPins: (self: Map, pins: { Pin }) -> (),
	-- The small legend row under the map (nil or empty hides it).
	setLegend: (self: Map, items: { LegendItem }?) -> (),
	-- The plan preview: one faint tag per state, on top of everything (nil or
	-- empty hides them).
	setPreview: (self: Map, tags: { [string]: PreviewTag }?) -> (),
	-- The box's aspect (width / height) in a frame up to `widthPx` x `heightPx`
	-- (D-079: the real map stands up on a phone; the circles stay at 1.6).
	aspectFor: (self: Map, widthPx: number, heightPx: number?) -> number,
	destroy: (self: Map) -> (),
}

return {}
