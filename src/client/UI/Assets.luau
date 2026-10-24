--!strict
-- The UI's images (docs/DESIGN.md D-056, D-062), uploaded as Roblox images like
-- the icons (assets/ui/README.md, assets/portraits/README.md).
--
-- Decorations: name -> { id, kind }, the same shape as UI/Icons; made by
-- assets/ui/make.py (PIL).
--   shadow  ui-shadow.png, 96x96: a 9-slice soft shadow (Kit.shadow)
--   glow    ui-glow.png, 256x256: a white radial glow, tinted (Kit.glow)
--   dots    ui-dots.png, 64x64: one dot, tiled (optional, unused for now)
-- While an id is "" the helpers still build their ImageLabel (attribute Asset
-- names it, so the headless snapshots draw a stand-in) but it shows nothing in
-- the game. After the upload, put each "rbxassetid://<number>" here.
--
-- Portraits (D-062): candidate id -> the image's asset id (a number), made by
-- assets/portraits/make.py (assets/portraits/<id>.png, 512x512). 0 = not
-- uploaded yet: Kit.portrait shows the candidate's initials on the plate
-- instead. The headless snapshots always draw the local PNG.

export type Asset = {
	id: string, -- "rbxassetid://…" or "" (not uploaded: draws nothing)
	kind: string, -- "slice" | "radial" | "tile"
}

export type Assets = {
	shadow: Asset,
	glow: Asset,
	dots: Asset,
	portraits: { [string]: number },
}

local Assets: Assets = {
	shadow = { id = "rbxassetid://81207934470509", kind = "slice" },
	glow = { id = "rbxassetid://109577761634341", kind = "radial" },
	dots = { id = "rbxassetid://77034414001634", kind = "tile" },
	portraits = table.freeze({
		okafor = 0, -- okafor.png
		calloway = 0, -- calloway.png
		venkat = 0, -- venkat.png
		hale = 0, -- hale.png
		alvarado = 0, -- alvarado.png
		reyes = 0, -- reyes.png
		strand = 0, -- strand.png
		begay = 0, -- begay.png
	}),
}

return table.freeze(Assets)
