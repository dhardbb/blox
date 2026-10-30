--!strict
-- The UI's images (docs/DESIGN.md D-056, D-068), uploaded as Roblox images like
-- the icons (assets/ui/README.md, assets/portraits/README.md).
--
-- Decorations: name -> { id, kind }, the same shape as UI/Icons; made by
-- assets/ui/make.py (PIL).
--   shadow  ui-shadow.png, 96x96: a 9-slice soft shadow (Kit.shadow)
--   glow    ui-glow.png, 256x256: a white radial glow, tinted (Kit.glow)
--   dots    ui-dots.png, 64x64: one dot, tiled (optional, unused for now)
--   mapStates1, mapStates2   assets/map/map-states-<k>.png: the real map's state
--           fill atlases (D-070, scripts/mapgen/make.py), tinted per state
--   mapBorders  assets/map/map-borders.png: the state border lines, tinted dark
--   mapStates1a, mapStates2a  assets/map/map-states-<k>a.png: the same atlases as
--           marker scribble slanted / (the whiteboard map, seat 1)
--   mapStates1b, mapStates2b  ... slanted \ (seat 2)
--   mapInk  assets/map/map-ink.png: every border and the coast in wobbly marker
--
-- The whiteboard set (docs/proposals/whiteboard.md), applied by UI/Board; each
-- one is skipped (or drawn flat) while its id is "":
--   board   board.png, 512x512: the board in full color with faint erased
--           ghosts, tiled behind a screen (Board.texture)
--   sticky  sticky.png, 128x128: a 9-slice sticky note in white, tinted to the
--           note color, curled corner and shadow (Board.sticky)
--   markerBox  marker-box.png, 128x128: a 9-slice wobbly marker rectangle,
--           white, tinted to the ink, drawn at 2x (Board.markerBox)
--   magnet  magnet.png, 128x128: a round glossy magnet in greys, tinted (Board.magnet)
--   scribbleCircle  scribble-circle.png, 256x256: a loose marker circle, white,
--           tinted (Board.circle)
--   tape    tape.png, 128x48: a strip of masking tape in full color (Board.tape)
--
-- If a map id is ever emptied again, the game falls back to the circle map
-- (Map/NodeMap) until all three are set. Until all four scribbled atlases are
-- set the map keeps the flat fills, and until mapInk is set the old borders.
--
-- While an id is "" the helpers still build their ImageLabel (attribute Asset
-- names it, so the headless snapshots draw a stand-in) but it shows nothing in
-- the game. After the upload, put each "rbxassetid://<number>" here.
--
-- Portraits (D-068): candidate id -> the image's asset id (a number), made by
-- assets/portraits/make.py (assets/portraits/<id>.png, 512x512). 0 = not
-- uploaded yet: Kit.portrait shows the candidate's initials on the plate
-- instead. The headless snapshots always draw the local PNG.

export type Asset = {
	id: string, -- "rbxassetid://…" or "" (not uploaded: draws nothing)
	kind: string, -- "slice" | "radial" | "tile" | "atlas" | "overlay" | "sprite" (drawn whole, Fit or Stretch)
}

export type Assets = {
	shadow: Asset,
	glow: Asset,
	dots: Asset,
	mapStates1: Asset,
	mapStates2: Asset,
	mapBorders: Asset,
	mapStates1a: Asset,
	mapStates2a: Asset,
	mapStates1b: Asset,
	mapStates2b: Asset,
	mapInk: Asset,
	board: Asset,
	sticky: Asset,
	markerBox: Asset,
	magnet: Asset,
	scribbleCircle: Asset,
	tape: Asset,
	portraits: { [string]: number },
}

local Assets: Assets = {
	shadow = { id = "rbxassetid://81207934470509", kind = "slice" },
	glow = { id = "rbxassetid://109577761634341", kind = "radial" },
	dots = { id = "rbxassetid://77034414001634", kind = "tile" },
	portraits = table.freeze({
		okafor = 125434917567861, -- okafor.png
		calloway = 136996676609904, -- calloway.png
		venkat = 80486112194483, -- venkat.png
		hale = 137090183313203, -- hale.png
		alvarado = 83415943025124, -- alvarado.png
		reyes = 104553481645494, -- reyes.png
		strand = 105519082316345, -- strand.png
		begay = 129888340974432, -- begay.png
	}),
	mapStates1 = { id = "rbxassetid://105693687672536", kind = "atlas" },
	mapStates2 = { id = "rbxassetid://84531905119471", kind = "atlas" },
	mapBorders = { id = "rbxassetid://127447041117262", kind = "overlay" },
	mapStates1a = { id = "rbxassetid://90520641329820", kind = "atlas" }, -- map-states-1a.png
	mapStates2a = { id = "rbxassetid://107187629382097", kind = "atlas" }, -- map-states-2a.png
	mapStates1b = { id = "rbxassetid://127992949925508", kind = "atlas" }, -- map-states-1b.png
	mapStates2b = { id = "rbxassetid://87162744091815", kind = "atlas" }, -- map-states-2b.png
	mapInk = { id = "rbxassetid://72265671361806", kind = "overlay" }, -- map-ink.png
	board = { id = "", kind = "tile" }, -- assets/ui/board.png
	sticky = { id = "", kind = "slice" }, -- assets/ui/sticky.png
	markerBox = { id = "", kind = "slice" }, -- assets/ui/marker-box.png
	magnet = { id = "", kind = "sprite" }, -- assets/ui/magnet.png
	scribbleCircle = { id = "", kind = "sprite" }, -- assets/ui/scribble-circle.png
	tape = { id = "", kind = "sprite" }, -- assets/ui/tape.png
}

return table.freeze(Assets)
