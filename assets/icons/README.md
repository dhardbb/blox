# Icons

Twelve [Lucide](https://lucide.dev) icons (ISC License, see `docs/CREDITS.md`), from the npm package `lucide-static@0.460.0`. Each PNG is 256x256, white (#FFFFFF) on transparent, with Lucide's 2 px stroke scaled up. The game tints them with `ImageColor3`.

`src/` holds the original SVGs, unchanged. To rebuild a PNG: set `stroke="#FFFFFF"` and `width`/`height` to 256 in the SVG, then render it at 256x256 with a transparent background.

## Upload, then fill in the ids

Upload each PNG as a Roblox image (Studio MCP `upload_image`, or Creator Hub: Create → Development items → Images), named after its icon name. Then set the matching `id` in `src/client/UI/Icons.luau` to `"rbxassetid://<number>"`. Until an id is set, the game draws the glyph.

| File | Icon name (`Icons.luau` key) | Used for | Image id |
|---|---|---|---|
| `megaphone.png` | `megaphone` | Rally | |
| `coins.png` | `coins` | Fundraise, money | |
| `tv.png` | `tv` | Ad | |
| `zap.png` | `zap` | Attack ad | |
| `search.png` | `search` | Poll, region poll | |
| `footprints.png` | `footprints` | Ground game | |
| `vote.png` | `vote` | Votes | |
| `clock.png` | `clock` | The timer | |
| `volume-2.png` | `volume-2` | Sound on | |
| `volume-x.png` | `volume-x` | Sound off | |
| `sparkles.png` | `sparkles` | Reduce motion | |
| `plane.png` | `plane` | A flight | |
