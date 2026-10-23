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
-- To add the uploaded images, set each `id` to "rbxassetid://<number>"
-- (docs/TESTING.md lists the twelve files by name). This module is plain data:
-- name -> { id, glyph }.

export type Icon = {
	id: string, -- "rbxassetid://…" or "" (draw the glyph)
	glyph: string, -- the fallback character
}

local Icons: { [string]: Icon } = {
	megaphone = { id = "", glyph = "!" }, -- Rally
	coins = { id = "", glyph = "$" }, -- Fundraise
	tv = { id = "", glyph = "►" }, -- Ad (Media)
	zap = { id = "", glyph = "▼" }, -- Attack ad
	search = { id = "", glyph = "?" }, -- Poll, region poll
	footprints = { id = "", glyph = "»" }, -- Ground game
	vote = { id = "", glyph = "✓" }, -- votes / electoral votes
	clock = { id = "", glyph = "○" }, -- the timer
	["volume-2"] = { id = "", glyph = "♪" }, -- sound on
	["volume-x"] = { id = "", glyph = "♪" }, -- sound off (Header draws a slash over the glyph)
	sparkles = { id = "", glyph = "☼" }, -- reduce motion
	plane = { id = "", glyph = "✈" }, -- a flight
}

return Icons
