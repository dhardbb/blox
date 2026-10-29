# Real map images

Made by `scripts/mapgen/make.py` (Pillow) from `scripts/mapgen/data/states-albers-10m.json` (us-atlas 3.0.1, ISC license in `scripts/mapgen/data/LICENSE-us-atlas`; US Census Bureau boundaries, public domain). Run from the repository root: `python3 scripts/mapgen/make.py`. It also writes `src/shared/UI/MapShapeData.luau`. See `docs/DESIGN.md` D-070.

| File | Size | What | `Assets.luau` key |
|---|---|---|---|
| `map-states-1.png` | 1024x944 | white state shapes on transparent, packed (an atlas) | `mapStates1` |
| `map-states-2.png` | 926x281 | the rest of the states | `mapStates2` |
| `map-borders.png` | 1023x645 | the borders between states as white lines | `mapBorders` |
| `map-states-1a.png` | 1024x944 | `map-states-1.png` as marker scribble slanted `/` (the whiteboard map, seat 1) | `mapStates1a` |
| `map-states-2a.png` | 926x281 | ... the rest of the states | `mapStates2a` |
| `map-states-1b.png` | 1024x944 | the same slanted `\` (seat 2) | `mapStates1b` |
| `map-states-2b.png` | 926x281 | ... the rest of the states | `mapStates2b` |
| `map-ink.png` | 1023x650 | every border and the lower 48's coast as wobbly white marker lines, tinted ink | `mapInk` |

The game tints them (`ImageColor3`), so they are white. Each state shows its own rectangle of an atlas (`ImageRectOffset` / `ImageRectSize`).

## Uploading

Upload each as an image (Studio MCP `upload_image`, or Creator Hub: Create, Development items, Images), then put each id in `src/client/UI/Assets.luau`:

```lua
mapStates1 = { id = "rbxassetid://…", kind = "atlas" },
mapStates2 = { id = "rbxassetid://…", kind = "atlas" },
mapBorders = { id = "rbxassetid://…", kind = "overlay" },
```

The scribbled atlases share the flat atlases' packing (the same rectangles), so `MapShapeData.luau` serves both. The game shows the scribbles only when all four are uploaded, and the ink overlay when `mapInk` is; until then it keeps the flat fills and `map-borders.png`. The generator is seeded: running it again gives the same files.

The flat atlases and borders were uploaded Oct 24, 2026 (ids in `Assets.luau`); the scribbles and the ink overlay are not uploaded yet. If any id is empty the game keeps the old circle map. If the generator is run again and the PNGs change, upload them again (the rectangles in `MapShapeData.luau` must match the uploaded images).
