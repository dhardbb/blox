# UI decoration images

Made by `make.py` (Pillow), run from the repository root: `python3 assets/ui/make.py`. White or black on transparent; the game tints them with `ImageColor3`. See `docs/DESIGN.md` D-056.

| File | Size | Used by | `Assets.luau` key | Settings in code |
|---|---|---|---|---|
| `ui-shadow.png` | 96x96 | `Kit.shadow`: the action bar plate, sheets, toasts, positioned coach tips, spotlights | `shadow` | `ScaleType = Slice`, `SliceCenter = Rect(40, 40, 56, 56)`, `SliceScale = 1`, black, 0.45 transparent |
| `ui-glow.png` | 256x256 | `Kit.glow`: the timer bar's tip, stamps, the wordmark, the race bar's crossing (and the map, after the map package) | `glow` | `ScaleType = Fit`, tinted |
| `ui-dots.png` | 64x64 | nothing yet (an optional dot pattern behind the map) | `dots` | tiled |

## Uploading

Upload `ui-shadow.png` and `ui-glow.png` as images (Studio MCP `upload_image`, or Creator Hub: Create → Development items → Images), then put each id in `src/client/UI/Assets.luau` as `"rbxassetid://<number>"`:

```lua
shadow = { id = "rbxassetid://…", kind = "slice" },
glow = { id = "rbxassetid://…", kind = "radial" },
```

While an id is `""` the helpers still create their image labels (so the headless snapshots can draw a stand-in), but the game shows nothing there.
