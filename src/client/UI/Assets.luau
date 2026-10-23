--!strict
-- The UI's decoration images (docs/DESIGN.md D-056): made by assets/ui/make.py
-- (PIL), uploaded as Roblox images like the icons (assets/ui/README.md). Plain
-- data: name -> { id, kind }, the same shape as UI/Icons.
--
--   shadow  ui-shadow.png, 96x96: a 9-slice soft shadow (Kit.shadow)
--   glow    ui-glow.png, 256x256: a white radial glow, tinted (Kit.glow)
--   dots    ui-dots.png, 64x64: one dot, tiled (optional, unused for now)
--
-- While an id is "" the helpers still build their ImageLabel (attribute Asset
-- names it, so the headless snapshots draw a stand-in) but it shows nothing in
-- the game. After the upload, put each "rbxassetid://<number>" here.

export type Asset = {
	id: string, -- "rbxassetid://…" or "" (not uploaded: draws nothing)
	kind: string, -- "slice" | "radial" | "tile"
}

local Assets: { [string]: Asset } = {
	shadow = { id = "", kind = "slice" },
	glow = { id = "", kind = "radial" },
	dots = { id = "", kind = "tile" },
}

return table.freeze(Assets)
