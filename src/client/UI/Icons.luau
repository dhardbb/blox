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
	megaphone = { id = "rbxassetid://74407986384819", glyph = "!" }, -- Rally
	coins = { id = "rbxassetid://115479549167953", glyph = "$" }, -- Fundraise
	tv = { id = "rbxassetid://85002016534519", glyph = "►" }, -- Ad (Media)
	zap = { id = "rbxassetid://106519025012778", glyph = "▼" }, -- Attack ad
	search = { id = "rbxassetid://81766020463454", glyph = "?" }, -- Poll, region poll
	footprints = { id = "rbxassetid://123779238671058", glyph = "»" }, -- Ground game
	vote = { id = "rbxassetid://91914610961279", glyph = "✓" }, -- votes / electoral votes
	clock = { id = "rbxassetid://95158744203759", glyph = "○" }, -- the timer
	["volume-2"] = { id = "rbxassetid://108064289798339", glyph = "♪" }, -- sound on
	["volume-x"] = { id = "rbxassetid://79580394049787", glyph = "♪" }, -- sound off (Header draws a slash over the glyph)
	sparkles = { id = "rbxassetid://85604574793056", glyph = "☼" }, -- reduce motion
	plane = { id = "rbxassetid://136061807700836", glyph = "✈" }, -- a flight
	-- D-090: not uploaded yet (assets/icons/README.md); the glyph shows until then.
	flame = { id = "rbxassetid://78499241852859", glyph = "♦" }, -- a Daily Race streak
	bug = { id = "rbxassetid://101977001168955", glyph = "¤" }, -- Report a bug
	scale = { id = "rbxassetid://72936421925165", glyph = "◊" }, -- the Issues map tab (D-092)
	["chart-column"] = { id = "rbxassetid://74425153139668", glyph = "%" }, -- the Polls map tab (D-092)
}

return Icons
