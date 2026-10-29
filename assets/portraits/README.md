# Candidate portraits

Made by `make.py` (Pillow 11), run from the repository root: `python3 assets/portraits/make.py` (add `--preview DIR` for an unlabeled copy of the sheet). It also writes `sheet.png`: all eight on their plates at 40, 80 and 160 px, labeled. See `docs/DESIGN.md` D-068 and the names-only reskin D-097.

One 512x512 PNG per candidate in `src/shared/Sim/Candidates.luau`, named by candidate id (ids never change, D-097): a flat head-and-shoulders bust on a transparent background, drawn at 4x and scaled down. `Kit.portrait` puts it on a round neutral plate and clips it to the circle (a `UICorner` on the image), so each bust is centered and fits the image's inscribed circle.

| File | Candidate | The look (the headwear sets the silhouette) |
|---|---|---|
| `okafor.png` | Goldie Pennywhistle, The Fundraiser | gold-trimmed tricorn, doubloon earrings and pendant |
| `calloway.png` | Buster Cannonball, The Barnstormer | red stunt helmet with goggles, epaulettes |
| `venkat.png` | Mavis Glimmer, The Ad Wizard | top hat, high-collared cape, sparkles |
| `hale.png` | Percy Quibble, The Debater | beret, monocle, handlebar mustache, quill |
| `alvarado.png` | Opal Crumpet, The Insider | lilac beehive, cat-eye glasses, pearls, gold key |
| `reyes.png` | Dash Kickflip, The Insurgent | teal-tipped spikes, sweatband, bolt pin |
| `strand.png` | Esme Moonbeam, The Pollster | starry headscarf, round glasses, crystal ball |
| `begay.png` | Gus Bramble, The Organizer | ranger hat, bushy white beard, neckerchief, badges |

`sheet.png` is for people only; it is not uploaded.

## Uploading

Upload each PNG as an image (Studio MCP `upload_image`, or Creator Hub: Create, Development items, Images), then put each number in `src/client/UI/Assets.luau` under `portraits`:

```lua
portraits = table.freeze({
	okafor = 1234567890, -- okafor.png
	...
}),
```

While a number is 0 the game shows that candidate's initials on the plate. The headless snapshots (`tests/ui/snap.luau`) always draw the local PNGs.
