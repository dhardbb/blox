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
	kind: string, -- "slice" | "radial" | "tile" | "atlas" | "overlay"
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
}

return table.freeze(Assets)
