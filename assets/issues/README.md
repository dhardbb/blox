# Issue symbols

The eight campaign issues' symbols (`docs/DESIGN.md` D-075). Original drawings made by `make.py` (Pillow), run from the repository root: `python3 assets/issues/make.py` (add `--preview DIR` for a sheet of every symbol at 16 to 48 px). Each PNG is 256x256, white on transparent; the game tints them with `ImageColor3` (`Kit.issueIcon`). They are drawn on the 24-unit grid of the Lucide UI icons (`assets/icons/`), with a heavier line and a filled core so they read at 16 px on the map. No logos, flags, party or campaign symbols.

## Uploading

Upload each PNG as an image (Studio MCP `upload_image`, or Creator Hub: Create → Development items → Images), named after its file, then put its id in `src/client/UI/IssueIcons.luau` as `"rbxassetid://<number>"`. While an id is `""` the game shows the text it showed before: the short code on the map ("JOB"), the name alone on chips and cards.

| File | Issue (`IssueIcons.luau` key) | Symbol | Image id |
|---|---|---|---|
| `jobs.png` | `Jobs` | a briefcase | not uploaded |
| `health.png` | `Health` | a heart with a pulse line | not uploaded |
| `schools.png` | `Schools` | a graduation cap | not uploaded |
| `environment.png` | `Environment` | a leaf | not uploaded |
| `safety.png` | `Safety` | a shield with a check mark | not uploaded |
| `transit.png` | `Transit` (Roads & Transit) | a bus from the front | not uploaded |
| `technology.png` | `Technology` | a microchip | not uploaded |
| `farms.png` | `Farms` (Farms & Rural) | a stalk of wheat | not uploaded |
