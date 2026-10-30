--!strict
-- The game's icons: Lucide (ISC license, docs/CREDITS.md), exported as 256x256
-- white PNGs on transparent and uploaded as Roblox images. Kit.icon(name)
-- draws the image tinted with ImageColor3, or the glyph while the id is ""
-- (before the upload, in the headless tests, or if an image is moderated).
-- Icons never carry meaning alone: an action chip keeps its word.
--
-- The glyphs are WGL4 or Latin-1 characters (the set Gotham and Builder Sans
-- cover, docs/UI-STYLE.md §2.6); ♪ ► ○ ☼ still need one look in Studio.
--
-- The ids are the uploaded images (assets/icons/README.md lists them by file).
-- A replaced image gets its new "rbxassetid://<number>" here. This module is
-- plain data: name -> { id, glyph }.

export type Icon = {
	id: string, -- "rbxassetid://…" or "" (draw the glyph)
	glyph: string, -- the fallback character
}

local Icons: { [string]: Icon } = {
	megaphone = { id = "rbxassetid://132783140685126", glyph = "!" }, -- Rally
	coins = { id = "rbxassetid://74039686747031", glyph = "$" }, -- Fundraise
	tv = { id = "rbxassetid://90248933714784", glyph = "►" }, -- Ad (Media)
	zap = { id = "rbxassetid://123188961303041", glyph = "▼" }, -- Attack ad
	search = { id = "rbxassetid://99364688118037", glyph = "?" }, -- Poll, region poll
	footprints = { id = "rbxassetid://72104035766896", glyph = "»" }, -- Ground game
	vote = { id = "rbxassetid://121116056767773", glyph = "✓" }, -- votes / electoral votes
	clock = { id = "rbxassetid://119040873019081", glyph = "○" }, -- the timer
	["volume-2"] = { id = "rbxassetid://129962085125040", glyph = "♪" }, -- sound on
	["volume-x"] = { id = "rbxassetid://102943499451293", glyph = "♪" }, -- sound off (Header draws a slash over the glyph)
	sparkles = { id = "rbxassetid://119180397835041", glyph = "☼" }, -- reduce motion
	plane = { id = "rbxassetid://79122591461203", glyph = "✈" }, -- a flight
	-- D-090, D-092: the newer icons (all redrawn as marker doodles for D-102).
	flame = { id = "rbxassetid://86000295015080", glyph = "♦" }, -- a Daily Race streak
	bug = { id = "rbxassetid://131741779323007", glyph = "¤" }, -- Report a bug
	scale = { id = "rbxassetid://102255188387006", glyph = "◊" }, -- the Issues map tab (D-092)
	["chart-column"] = { id = "rbxassetid://82089459017562", glyph = "%" }, -- the Polls map tab (D-092)
}

return Icons
