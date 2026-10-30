# Icons

Sixteen [Lucide](https://lucide.dev) icons (ISC License, see `docs/CREDITS.md`), from the npm package `lucide-static@0.460.0`, redrawn as marker doodles for the whiteboard look (`docs/proposals/whiteboard.md`). Each PNG is 256x256, white (#FFFFFF) on transparent; the game tints them with `ImageColor3`.

`src/` holds the original SVGs, unchanged. `make.py` (Pillow) follows each SVG's paths and draws them again by hand, with the shared marker strokes in `assets/ui/marker.py`: lines wobble a little, closed shapes overshoot where they meet, circles are loose loops, each part sits a hair off its place. The stroke is 2.2 of 24 units (Lucide's is 2), so they still read at 20 to 24 px. Seeded by the icon's name, so a rerun gives the same bytes:

```sh
python3 assets/icons/make.py                     # rewrites every <name>.png
python3 assets/icons/make.py --sheet build/icons.png   # plus a preview at 128, 48, 24, 20 px
```

**Re-upload needed (whiteboard):** all 16 PNGs changed. The ids below are the old drawings and keep working until each is replaced; upload the new PNGs and put each new id in `src/client/UI/Icons.luau`.

## Uploaded ids

All but `scale` and `chart-column` (D-092, the map tabs: they draw their glyph until uploaded) are uploaded as Roblox images, named after their icon names, and their ids are in `src/client/UI/Icons.luau`. To replace one, upload the new PNG (Studio MCP `upload_image`, or Creator Hub: Create → Development items → Images) and set its `id` there. An icon whose id is `""` draws its glyph instead; the glyphs stay in `Icons.luau` as that fallback.

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
| `scale.png` | `scale` | The Issues map tab | not uploaded yet |
| `chart-column.png` | `chart-column` | The Polls map tab | not uploaded yet |
