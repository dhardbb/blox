# Candidate portraits

Made by `make.py` (Pillow 11), run from the repository root: `python3 assets/portraits/make.py` (add `--preview DIR` for a sheet of all eight on their plates at 40, 80 and 160 px). See `docs/DESIGN.md` D-068.

One 512x512 PNG per candidate in `src/shared/Sim/Candidates.luau`, named by candidate id: a flat head-and-shoulders bust on a transparent background, drawn at 4x and scaled down. `Kit.portrait` puts it on a round neutral plate and clips it to the circle (a `UICorner` on the image), so each bust is centered and fits the image's inscribed circle.

| File | Candidate | The prop that hints at the perk |
|---|---|---|
| `okafor.png` | Dana Okafor, The Fundraiser | gold coin earrings and brooch |
| `calloway.png` | Rex Calloway, The Barnstormer | straw boater, rolled sleeves, braces |
| `venkat.png` | Priya Venkat, The Ad Wizard | headset microphone |
| `hale.png` | Marcus Hale, The Debater | bow tie, suit, beard |
| `alvarado.png` | June Alvarado, The Insider | access badge on a lanyard, pearls |
| `reyes.png` | Tomas Reyes, The Insurgent | lightning-bolt pin, bomber jacket |
| `strand.png` | Helen Strand, The Pollster | round glasses, pencil behind the ear |
| `begay.png` | Walt Begay, The Organizer | field cap, work vest |

## Uploading

Upload each PNG as an image (Studio MCP `upload_image`, or Creator Hub: Create, Development items, Images), then put each number in `src/client/UI/Assets.luau` under `portraits`:

```lua
portraits = table.freeze({
	okafor = 1234567890, -- okafor.png
	...
}),
```

While a number is 0 the game shows that candidate's initials on the plate. The headless snapshots (`tests/ui/snap.luau`) always draw the local PNGs.
