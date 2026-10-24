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
--
-- If a map id is ever emptied again, the game falls back to the circle map
-- (Map/NodeMap) until all three are set.
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
	portraits: { [string]: number },
}

local Assets: Assets = {
	shadow = { id = "rbxassetid://81207934470509", kind = "slice" },
	glow = { id = "rbxassetid://109577761634341", kind = "radial" },
	dots = { id = "rbxassetid://77034414001634", kind = "tile" },
	portraits = table.freeze({
		okafor = 73894932919763, -- okafor.png
		calloway = 130077821883991, -- calloway.png
		venkat = 124950397232830, -- venkat.png
		hale = 76413574965513, -- hale.png
		alvarado = 90937358620227, -- alvarado.png
		reyes = 77139396727119, -- reyes.png
		strand = 100121291325203, -- strand.png
		begay = 81926103007775, -- begay.png
	}),
	mapStates1 = { id = "rbxassetid://105693687672536", kind = "atlas" },
	mapStates2 = { id = "rbxassetid://84531905119471", kind = "atlas" },
	mapBorders = { id = "rbxassetid://127447041117262", kind = "overlay" },
}

return table.freeze(Assets)
