--!strict
-- The UI's decoration images (docs/DESIGN.md D-056): made by assets/ui/make.py
-- (PIL), uploaded as Roblox images like the icons (assets/ui/README.md). Plain
-- data: name -> { id, kind }, the same shape as UI/Icons.
--
--   shadow  ui-shadow.png, 96x96: a 9-slice soft shadow (Kit.shadow)
--   glow    ui-glow.png, 256x256: a white radial glow, tinted (Kit.glow)
--   dots    ui-dots.png, 64x64: one dot, tiled (optional, unused for now)
--   mapStates1, mapStates2   assets/map/map-states-<k>.png: the real map's state
--           fill atlases (D-062, scripts/mapgen/make.py), tinted per state
--   mapBorders  assets/map/map-borders.png: the state border lines, tinted dark
--
-- If a map id is ever emptied again, the game falls back to the circle map
-- (Map/NodeMap) until all three are set.
-- While an id is "" the helpers still build their ImageLabel (attribute Asset
-- names it, so the headless snapshots draw a stand-in) but it shows nothing in
-- the game. After the upload, put each "rbxassetid://<number>" here.

export type Asset = {
	id: string, -- "rbxassetid://…" or "" (not uploaded: draws nothing)
	kind: string, -- "slice" | "radial" | "tile" | "atlas" | "overlay"
}

local Assets: { [string]: Asset } = {
	shadow = { id = "rbxassetid://81207934470509", kind = "slice" },
	glow = { id = "rbxassetid://109577761634341", kind = "radial" },
	dots = { id = "rbxassetid://77034414001634", kind = "tile" },
	mapStates1 = { id = "rbxassetid://105693687672536", kind = "atlas" },
	mapStates2 = { id = "rbxassetid://84531905119471", kind = "atlas" },
	mapBorders = { id = "rbxassetid://127447041117262", kind = "overlay" },
}

return table.freeze(Assets)
