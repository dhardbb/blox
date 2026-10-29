# Icons

Fourteen [Lucide](https://lucide.dev) icons (ISC License, see `docs/CREDITS.md`), from the npm package `lucide-static@0.460.0`. Each PNG is 256x256, white (#FFFFFF) on transparent, with Lucide's 2 px stroke scaled up. The game tints them with `ImageColor3`.

`src/` holds the original SVGs, unchanged. To rebuild a PNG: set `stroke="#FFFFFF"` and `width`/`height` to 256 in the SVG, then render it at 256x256 with a transparent background.

## Uploaded ids

All twelve are uploaded as Roblox images, named after their icon names, and their ids are in `src/client/UI/Icons.luau`. To replace one, upload the new PNG (Studio MCP `upload_image`, or Creator Hub: Create → Development items → Images) and set its `id` there. An icon whose id is `""` draws its glyph instead; the glyphs stay in `Icons.luau` as that fallback.

| File | Icon name (`Icons.luau` key) | Used for | Image id |
|---|---|---|---|
| `megaphone.png` | `megaphone` | Rally | `rbxassetid://74407986384819` |
| `coins.png` | `coins` | Fundraise, money | `rbxassetid://115479549167953` |
| `tv.png` | `tv` | Ad | `rbxassetid://85002016534519` |
| `zap.png` | `zap` | Attack ad | `rbxassetid://106519025012778` |
| `search.png` | `search` | Poll, region poll | `rbxassetid://81766020463454` |
| `footprints.png` | `footprints` | Ground game | `rbxassetid://123779238671058` |
| `vote.png` | `vote` | Votes | `rbxassetid://91914610961279` |
| `clock.png` | `clock` | The timer | `rbxassetid://95158744203759` |
| `volume-2.png` | `volume-2` | Sound on | `rbxassetid://108064289798339` |
| `volume-x.png` | `volume-x` | Sound off | `rbxassetid://79580394049787` |
| `sparkles.png` | `sparkles` | Reduce motion | `rbxassetid://85604574793056` |
| `plane.png` | `plane` | A flight | `rbxassetid://136061807700836` |
| `flame.png` | `flame` | A Daily Race streak (D-090) | not uploaded yet (`""`) |
| `bug.png` | `bug` | Report a bug (D-090) | not uploaded yet (`""`) |
