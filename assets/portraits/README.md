# Candidate portraits

Made by `make.py` (Pillow 11), run from the repository root: `python3 assets/portraits/make.py`. Options: `--review PATH` writes the review sheet (each at 512 with name and genre, a 32/48/72 px strip in color and in greyscale, and the round and taped crops; use `build/portraits-review.png`); `--photos PATH` writes how `Board.photo` tapes each one up at 48, 72 and 96 px; `--preview DIR` writes an unlabeled copy of the sheet. It always writes `sheet.png`: all eight in `Kit.portrait`'s round crop at 40, 80 and 160 px, labeled. See `docs/DESIGN.md` D-068, the names-only reskin D-097 and the whiteboard D-102.

One 512x512 PNG per candidate in `src/shared/Sim/Candidates.luau`, named by candidate id (ids never change, D-097). Each is a **photograph, not a marker drawing**: the whiteboard tapes the faces up as instant photos, so they are full-bleed square snapshots taken on the campaign trail, with no outlines. Soft light from one side gives the face its form; the setting behind is out of focus; a color grade, a vignette and a little film grain finish it. Everything is painted at 4x and scaled down, and every random choice is seeded by the id, so the script always paints the same pictures.

`Kit.portrait` clips the same square to a circle (a `UICorner` on the image), so each face sits in the middle of the inscribed circle; `Board.photo` shows the whole square.

## The eight: a genre of politician each

Each is a believable person. The genre is carried by the setting, the light and the pose, not by a gag or a prop costume, and the faces differ through ordinary features (face shape, hair, age, glasses, clothes, expression). All are fictional; no real person, party, flag, seal, logo or slogan appears.

| File | Candidate | Genre | The photo: setting, light, pose |
|---|---|---|---|
| `okafor.png` | Goldie Pennywhistle | The Fundraiser | a gala ballroom's warm golden bokeh; leaning in with a big welcoming smile; locs up in a high bun, gold hoops and pendant, an evening dress |
| `calloway.png` | Buster Cannonball | The Barnstormer | an outdoor rally in daylight under mustard-and-cream bunting swags, the crowd behind; mid-speech, collar open, sleeve rolled, a fist up; copper hair, freckles |
| `venkat.png` | Mavis Glimmer | The Ad Wizard | a dark TV studio with glowing monitors, a teal back light tracing her edge; a perfectly held, camera-ready smile; long glossy hair |
| `hale.png` | Percy Quibble | The Debater | a debate stage's row of lights; squared up behind the lectern's edge and microphone, an open hand raised to take the floor; mustache, greying temples, dark suit |
| `alvarado.png` | Opal Crumpet | The Insider | a wood-panelled hallway lit by a brass sconce, a marble column beside her; strong side light leaves half her face in shadow; a knowing half-smile; swept-back silver hair, pearls, a lapel pin |
| `reyes.png` | Dash Kickflip | The Insurgent | a brick street at night caught in a camera flash; off-axis and turned away, a hand-lettered cardboard sign ("HEAR US!") pushing into frame; undercut, hoodie, a set jaw |
| `strand.png` | Esme Moonbeam | The Pollster | an office wall papered with crosstabs, bar charts and trend lines under cool fluorescent light; round glasses, a pencil behind her ear, eyes on the numbers; short white hair, cardigan |
| `begay.png` | Gus Bramble | The Organizer | a leafy street at golden hour, the background streaked as the camera pans to keep up; clipboard of sign-up checkboxes, lanyard and badge, a cap; white beard, a warm grin |

At 48 px they part by setting (warm dark, bright sky, dark teal, steel-blue stage, brown wood and white column, night street and sign, pale paper wall, green leaves) and by hair and pose; the review sheet's greyscale strip checks that the values differ too.

`sheet.png` is for people only; it is not uploaded.

## On the whiteboard: photos taped up at run time

`UI/Board.photo(face, px, { tilt = ... })` puts a face in a white instant-photo card (7% border, a thicker chin), turns it a few degrees and tapes it on with `assets/ui/tape.png`; the full-bleed photo fills the card's square window. Doing the card at run time rather than baking it into the PNG keeps the face big at the 48 to 96 px the game shows it, lets each photo lean its own way, and keeps the card's border and tilt tunable without new uploads. A rotated frame can't clip its children (Roblox's `Rotation` ignores `ClipsDescendants`), so the card relies on none.

## Uploading

Upload each PNG as an image (Studio MCP `upload_image`, or Creator Hub: Create, Development items, Images), then put each number in `src/client/UI/Assets.luau` under `portraits`:

```lua
portraits = table.freeze({
	okafor = 1234567890, -- okafor.png
	...
}),
```

While a number is 0 the game shows that candidate's initials on the plate. The headless snapshots (`tests/ui/snap.luau`) always draw the local PNGs.
