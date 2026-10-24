--!strict
-- The eight issue symbols (docs/DESIGN.md D-075): white glyphs on transparent,
-- 256x256, drawn by assets/issues/make.py (PIL) and uploaded as Roblox images.
-- Kit.issueIcon(issue) draws one tinted with ImageColor3. While an issue's id
-- is "" (before the upload, or if an image is moderated) the game shows the
-- text it showed before the symbols: `code` where a symbol stands alone (the
-- map), the issue's name alone where the symbol sits beside its name.
--
-- The ids are the uploaded images (assets/issues/README.md lists them by
-- file); put each as "rbxassetid://<number>". `file` is the PNG's name under
-- assets/issues/ (the headless snapshots draw it). `preview` (tests only,
-- tests/ui/Rig.luau): lay the symbols out as if every one were uploaded, so the
-- specs and snapshots see the real layout before the upload (the image itself
-- stays "", so a live game would show nothing there).
--
-- Plain data: an unfrozen table, so the tests can set `preview`.

export type IssueIcon = {
	id: string, -- "rbxassetid://…" or "" (show the text instead)
	code: string, -- the short code a symbol alone falls back to ("JOB")
	file: string, -- assets/issues/<file>.png
}

local IssueIcons = {
	preview = false,
	icons = {
		Jobs = { id = "", code = "JOB", file = "jobs" }, -- a briefcase
		Health = { id = "", code = "HLT", file = "health" }, -- a heart with a pulse line
		Schools = { id = "", code = "SCH", file = "schools" }, -- a graduation cap
		Environment = { id = "", code = "ENV", file = "environment" }, -- a leaf
		Safety = { id = "", code = "SAF", file = "safety" }, -- a shield with a check mark
		Transit = { id = "", code = "TRN", file = "transit" }, -- a bus
		Technology = { id = "", code = "TEC", file = "technology" }, -- a microchip
		Farms = { id = "", code = "FRM", file = "farms" }, -- a stalk of wheat
	} :: { [string]: IssueIcon },
}

return IssueIcons
