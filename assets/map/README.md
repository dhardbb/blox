# Real map images

Made by `scripts/mapgen/make.py` (Pillow) from `scripts/mapgen/data/states-albers-10m.json` (us-atlas 3.0.1, ISC license in `scripts/mapgen/data/LICENSE-us-atlas`; US Census Bureau boundaries, public domain). Run from the repository root: `python3 scripts/mapgen/make.py`. It also writes `src/shared/UI/MapShapeData.luau`. See `docs/DESIGN.md` D-070.

| File | Size | What | `Assets.luau` key |
|---|---|---|---|
| `map-states-1.png` | 1024x944 | white state shapes on transparent, packed (an atlas) | `mapStates1` |
| `map-states-2.png` | 926x281 | the rest of the states | `mapStates2` |
| `map-borders.png` | 1023x645 | the borders between states as white lines | `mapBorders` |

The game tints them (`ImageColor3`), so they are white. Each state shows its own rectangle of an atlas (`ImageRectOffset` / `ImageRectSize`).

## Uploading

Upload all three as images (Studio MCP `upload_image`, or Creator Hub: Create, Development items, Images), then put each id in `src/client/UI/Assets.luau`:

```lua
mapStates1 = { id = "rbxassetid://…", kind = "atlas" },
mapStates2 = { id = "rbxassetid://…", kind = "atlas" },
mapBorders = { id = "rbxassetid://…", kind = "overlay" },
```

Uploaded Oct 24, 2026 (ids in `Assets.luau`). If any id is empty the game keeps the old circle map. If the generator is run again and the PNGs change, upload them again (the rectangles in `MapShapeData.luau` must match the uploaded images).
