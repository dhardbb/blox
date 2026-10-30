# UI decoration images

Made by `make.py` (Pillow), run from the repository root: `python3 assets/ui/make.py`. White or black on transparent; the game tints them with `ImageColor3`. See `docs/DESIGN.md` D-056.

| File | Size | Used by | `Assets.luau` key | Settings in code |
|---|---|---|---|---|
| `ui-shadow.png` | 96x96 | `Kit.shadow`: the action bar plate, sheets, toasts, positioned coach tips, spotlights | `shadow` | `ScaleType = Slice`, `SliceCenter = Rect(40, 40, 56, 56)`, `SliceScale = 1`, black, 0.45 transparent |
| `ui-glow.png` | 256x256 | `Kit.glow`: the timer bar's tip, stamps, the wordmark, the race bar's crossing (and the map, after the map package) | `glow` | `ScaleType = Fit`, tinted |
| `ui-dots.png` | 64x64 | nothing yet (an optional dot pattern behind the map) | `dots` | tiled |

## The whiteboard set

Same script; the strokes come from `marker.py` (seeded wobbly marker lines, shared with `assets/icons/make.py` and `assets/promo/make.py`). Applied by `src/client/UI/Board.luau`. Each falls back while its id is `""`: nothing is added, except the sticky note (the frame turns flat sticky yellow) and the magnet (a flat dot).

| File | Size | Colors | Used by | `Assets.luau` key | Settings in code |
|---|---|---|---|---|---|
| `board.png` | 512x512 | full color: the board `#F3F1EA` with erased-marker ghosts, luminance 235 to 241 | `Board.texture` behind a screen | `board` | `ScaleType = Tile`, `TileSize = 512x512 px`, not tinted |
| `sticky.png` | 128x128 | white paper, grey shadow and curl | `Board.sticky` | `sticky` | `ScaleType = Slice`, `SliceCenter = Rect(32, 32, 88, 88)`, `SliceScale = 1`, tinted to the note color; the paper spans 4 to 116, so the image reaches 4 px past the frame's top and left and 12 px past its right and bottom |
| `marker-box.png` | 128x128 | white strokes | `Board.markerBox` (buttons, cards) | `markerBox` | `ScaleType = Slice`, `SliceCenter = Rect(40, 40, 88, 88)`, `SliceScale = 0.5` (drawn at 2x: a 3 px line), 7 px past each edge, tinted to the ink |
| `magnet.png` | 128x128 | greys, white gloss | `Board.magnet` (pins, face badges) | `magnet` | `ScaleType = Fit`, tinted |
| `scribble-circle.png` | 256x256 | white stroke | `Board.circle` (circled stamps and notes) | `scribbleCircle` | `ScaleType = Stretch`, 1.35x its target, tinted |
| `tape.png` | 128x48 | full color, about 80% opaque | `Board.tape`, `Board.photo` | `tape` | `ScaleType = Stretch`, turned a few degrees, not tinted |

`python3 assets/ui/make.py` rewrites all nine images; a rerun gives the same bytes (every random draw is seeded).

## Uploading

Upload `ui-shadow.png` and `ui-glow.png` (and the whiteboard set above) as images (Studio MCP `upload_image`, or Creator Hub: Create → Development items → Images), then put each id in `src/client/UI/Assets.luau` as `"rbxassetid://<number>"`:

```lua
shadow = { id = "rbxassetid://…", kind = "slice" },
glow = { id = "rbxassetid://…", kind = "radial" },
board = { id = "rbxassetid://…", kind = "tile" },
```

While an id is `""` the helpers still create their image labels (so the headless snapshots can draw a stand-in), but the game shows nothing there.
