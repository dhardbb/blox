# Proposal: Landslide as whiteboard art (the campaign's planning room)

Status: approved by the designers (Oct 29, 2026) after Studio screenshots; rolled out as D-102 on branch `whiteboard`. Changes found in Studio: state codes on the map are Permanent Marker and map numbers Builder Sans Bold (Patrick Hand read too small there); callout chips are pale.

This changes the look only. No rule, sim, payload, View or gameplay Config number changes; the balance report stays byte-identical. Scope: `src/client`, `src/shared/UI`, `assets`, `scripts/mapgen`, docs.

## The idea

Every screen is the wall of the candidate's planning room: a big off-white dry-erase board with faint ghosts of erased marker. On it:
- the US map drawn in black marker;
- states colored in with scribbled marker, hatched;
- codes and votes hand-lettered;
- a TRACKER table for the tally;
- sticky notes, magnets, arrows and circled notes.

The photos show the look we want. We copy none of their text.

## Palette

All values are sRGB. Contrast is the WCAG ratio against the board, paper and raised colors. The floor for text is 4.5:1, and every ink clears it on all three. Every player ink is at least 40 (CIE76) from the loss orange and at least 35 from every other ink (the D-056/D-067 spec still runs).

| Token | Role | Hex | on board | on paper | on raised |
|---|---|---|---|---|---|
| background | the board | `#F3F1EA` | — | — | — |
| field | text boxes, wells | `#F8F6F0` | — | — | — |
| surface | paper cards, sticky backs | `#FBFAF5` | — | — | — |
| surfaceTop | top of a card's gradient | `#FFFEFA` | — | — | — |
| raised | magnet labels, chips | `#ECE8DE` | — | — | — |
| raisedHover | a selected chip | `#E1DCCD` | — | — | — |
| sticky | a sticky note: coach tips, the week's event | `#FFF2A8` | ink on it 14.8 | — | — |
| ghost | erased-marker smudges (board texture only) | `#E4E1D8` | — | — | — |
| text (ink) | black marker | `#1D1D1F` | 14.9 | 16.1 | 13.8 |
| muted | pencil grey | `#57544C` | 6.7 | 7.2 | 6.2 |
| line | hairlines, dividers (not text) | `#8F8B80` | 3.0 | 3.3 | 2.8 |
| good | a gain (green marker) | `#17723A` | 5.3 | 5.7 | 4.9 |
| loss | a loss or warning (burnt orange, always with a sign or arrow, D-056) | `#B04A00` | 4.9 | 5.3 | 4.5 |
| Crimson | player ink (a cherry red) | `#C81446` | 5.1 | 5.5 | 4.7 |
| Cobalt | player ink | `#1F5BD0` | 5.4 | 5.8 | 5.0 |
| Emerald | player ink | `#0B7343` | 5.2 | 5.7 | 4.8 |
| Amber | player ink (an olive gold; a bright yellow can't be read on white, a mustard sits too near the loss orange) | `#746800` | 5.0 | 5.4 | 4.6 |
| Violet | player ink | `#8C28D2` | 5.5 | 6.0 | 5.1 |
| Teal | player ink | `#086C7C` | 5.4 | 5.8 | 5.0 |
| accent | "press here / selected": black marker | `#1D1D1F` | 14.9 | 16.1 | 13.8 |
| highlight | key states, and "gold" (the Daily Race, first medals, the 270 badge): highlighter yellow, a fill behind ink, never text | `#FFE347` | ink on it 13.1 | — | — |

Notes:
- **Inks are darker than today's picks.** On a white board the old bright colors read as text at only 2–3:1. Map fills use the same ink at reduced strength, blended toward the board, so a "lean" is a lighter scribble and a "safe" state a dense one. All six inks keep their names, and Crimson and Cobalt stay the default pair.
- **`Colors.textOn` reverses.** Today it brightens a color until it reads on a dark card. On the board it darkens instead, choosing the direction from the ground's lightness. Every caller stays the same.
- **Losses stay orange.** The orange is a burnt orange so it reads on white, and it still always comes with a sign or an arrow (the `lossText` rule). Red and a readable orange sit close on white, so Crimson moved toward cherry and Amber toward olive gold to keep them apart.

## Accent: replacing white (D-058)

A white accent can't work on a white board. Proposed:
- **Selection and "press here":** black marker. The primary button is a solid black marker box with board-colored text. The selected state is a thick black marker outline drawn on top of every other border.
- **Key states:** a highlighter-yellow band traced just inside the state's border (replacing D-101's pale gold, which disappears on white), plus the asterisk from photo 4 next to the code. The asterisk means the mark reads in greyscale too.
- **The timer:** black, turning loss orange in the last seconds as it does today.

## Fonts

All are Roblox built-ins, checked against the `Enum.Font` reference (AmaticSC, IndieFlower, Kalam, PatrickHand and PermanentMarker are all listed). Two new fonts:

| Use | Font | Why |
|---|---|---|
| Headings, the LANDSLIDE wordmark, stamps (CALLED, 270!, LANDSLIDE) | **Permanent Marker** | Thick, reads as a real marker, legible at 20 px and up. |
| State codes, big numbers (votes, scores, the tracker), short labels on magnets | **Patrick Hand** | Neat hand-lettering with clear digits (1 vs 7, 0 vs 8) down to 14 px. |
| Body text, the state card, tips, anything over a few words | Builder Sans (unchanged) | Readability beats charm. |

Fredoka One (today's display font) leaves. Amatic SC and Indie Flower are too thin to read at phone sizes, and Kalam is too close to Patrick Hand to justify a third font.

## Colorblind: hatch direction

Each player's scribble slants its own way: seat 1 `/`, seat 2 `\`. This follows the seat, not the color, so it holds for any Color Pass pair, and the map reads in greyscale. That takes two grayscale fill atlases (one per slant). ShapeMap picks the atlas by the leading seat and still tints it with ImageColor3. Toss-ups stay blank board with no fill.

## Map rules kept (designers)

- **A state's code never moves** (D-092 stays). Only the view's value moves around it.
- **Borders don't cover each other.** Every outline runs just inside its own state's border (D-092 and D-101). The selection's black outline is drawn on top of everything, the highlighter included.
- **Money shows dollar amounts**, not coins (as of 0.17).
- **Small Northeast states** keep their side chips. They become hand-lettered "CT 7 ■" rows with a colored square, like photo 4.

## Decisions this replaces

- **D-056** (navy stage, chunky buttons): the stage becomes the board. Buttons become marker-outlined boxes (secondary) and solid black marker boxes (primary). Losses stay orange.
- **D-058** (white accent): replaced by black marker for selection, plus highlighter yellow for key states (above).
- **D-067** (deep palette): replaced by the ink palette above. Same six names, same pairing rules, checked again for distance from the loss orange.
- **D-079, in part:** the map's dark plates behind labels go. Codes and values are written straight on the board, and a value too big for its state gets a pencil leader line.
- **D-101** (gold key edge): the gold becomes highlighter yellow, plus the asterisk.

## New images

Everything comes from generator scripts in the repo, as before. The upload list goes to you in one batch. Until uploaded, each falls back to today's flat drawing.

| File | What | Size |
|---|---|---|
| `assets/ui/board.png` | Tiling board texture with faint erased-marker ghosts | 512x512 |
| `assets/ui/marker-box.png` | 9-slice wobbly marker rectangle (buttons, cards) | 128x128 |
| `assets/ui/sticky.png` | 9-slice sticky note with a curled corner and shadow | 128x128 |
| `assets/ui/magnet.png` | Round magnet (pins, face badges) | 128x128 |
| `assets/ui/scribble-circle.png` | Hand-drawn circle for stamps and "circled" notes | 256x256 |
| `assets/map/map-states-1a/2a.png` | State fills, hatched `/` (grayscale, tintable) | 1024 atlases |
| `assets/map/map-states-1b/2b.png` | State fills, hatched `\` | 1024 atlases |
| `assets/map/map-borders.png` | Black marker borders, slightly wobbly | ≤1024 wide |
| `assets/icons/*.png` | The 17 icons redrawn as marker doodles | as today |
| `assets/portraits/*.png` | The 8 portraits as photos taped to the board | as today |
| `assets/promo/*` | Experience icon and thumbnails in the new look | as today |

A marker squeak sound is optional and would need an audio upload. Not planned unless you want it.

## Motion

- **Draw-on:** a heading's underline or a circle sweeps in once, about 0.3 s.
- **Eraser wipe:** a transition between screens.
- **Reduce motion** turns both off.
- Nothing animates every frame on an idle screen.

## Risks

- **Snapshots can't show the look.** The headless snapshots draw every font as Helvetica and skip image textures. Layout and contrast are still checked there, but the look must be judged in Studio (phone 390x844, iPad 1024x768, desktop 1280x720).
- **Handwriting at 14 px on a phone.** Patrick Hand is the smallest we go. If a code is hard to read in Studio we drop back to Builder Sans Bold for codes only.
- **Pale fills on white.** A "lean" scribble at low strength may read too faint. The hatch density, not only the tint, steps up with the band.
- **Map atlases double** (two slants). This adds 2 images; memory is still well inside budget.
- **Dark-mode habit.** Players used to the navy board may find the white bright at night. This is a deliberate change, and we can add a "dim board" setting later if playtests ask.
- **Asset ids.** New images need your upload. The game falls back to flat colors until then, so nothing breaks.
