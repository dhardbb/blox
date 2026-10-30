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

## The whiteboard look: photos taped up at run time

The whiteboard restyle (`docs/proposals/whiteboard.md`) keeps these images unchanged; there is nothing to re-upload. `UI/Board.photo(face, px, { tilt = ... })` puts a face in a white instant-photo card (7% border, a thicker chin), turns it a few degrees and tapes it on with `assets/ui/tape.png`. We picked that over baking a polaroid into new PNGs because, at the sizes the game shows faces (48 to 96 px):

- the face stays big: a baked polaroid with its tilt and tape fits a 512 image only at about 65% of the width, so a 64 px slot would show a 40 px face; at run time the card is the slot and the face fills 86% of it;
- each photo can lean its own way (a row of eight identical tilts looks printed, not taped), and the card's border and tilt can be tuned in code without new uploads;
- the 8 uploaded ids keep working, and the tape is the only new image (shared with every other taped thing).

The cost is a few more GuiObjects per face, and a rotated frame can't clip its children (Roblox's `Rotation` ignores `ClipsDescendants`), so the card relies on none. `python3 assets/portraits/make.py --photos PATH` writes a review sheet: each face as `Board.photo` draws it at 48, 72 and 96 px, and the baked alternative below it.

## Uploading

Upload each PNG as an image (Studio MCP `upload_image`, or Creator Hub: Create, Development items, Images), then put each number in `src/client/UI/Assets.luau` under `portraits`:

```lua
portraits = table.freeze({
	okafor = 1234567890, -- okafor.png
	...
}),
```

While a number is 0 the game shows that candidate's initials on the plate. The headless snapshots (`tests/ui/snap.luau`) always draw the local PNGs.
