# WP1 — Map (MapLayout, NodeMap, MapInterface)

## Changelog

- Map: the nine small Northeast states (VT, NH, MA, RI, CT, NJ, DE, MD, DC) now stand in a labeled column at the right edge of the map, top to bottom in that order, each with a thin line back to where the state really is. Maine, New York and Pennsylvania stay on the map. No two circles overlap any more (B12).
- Map: every state's circle is big enough to read its two-letter label on a phone (at least 24 px label box on a 390 px wide map, 20 px in the Northeast column). Small states got bigger and the biggest got a little smaller, so sizes vary less than before.
- Map: every state's tap target is at least 36 px in both directions (was 30) and stays inside the map; where two targets overlap, the smaller state wins the tap (B13).
- Map: the H/B/1/2/G/* badge now sits in a band at the top of the state's tap target, and a new momentum arrow (▲/▼ in the leading player's color) can show under a state. Nothing sets the arrow yet; Campaign will (WP3).
- Map text uses the type scale only (labels up to 20 px, badges and arrows up to 16 px, never under 12 px). The map passes the strict UI audit, so map findings now count as problems on every screen.

## TESTING.md checklist

Map (Draft, Campaign, Election). Test at phone portrait (e.g. iPhone 14 emulator, 390 wide) and at 16:9 (1280x720 or the Studio default).

1. Start a practice match and wait for "The map for this match" (MapReveal).
   - Must see: a column of nine circles at the right edge of the map labeled VT, NH, MA, RI, CT, NJ, DE, MD, DC from top to bottom, each with a thin grey line running left toward New England / the Mid-Atlantic.
   - Must see: every state's two letters readable, no circle covering another, ME next to NY, AK and HI bottom left.
2. In the Draft, tap RI, then DE, then DC in the column (phone portrait).
   - Each tap selects the state you tapped (yellow ring). Tell us if a tap ever picks the neighbor above or below instead.
3. Tap a few small inland states (e.g. DE's neighbor MD, WV, CT, NH, VT) and a big one next to a small one (PA next to NJ in the column, TX next to OK).
   - The tapped state is selected every time.
4. During the Draft and Campaign, look at the badges (H, B, 1, 2, G2, *).
   - They sit at the top edge of the circle, readable, not hidden behind the next state.
5. In Campaign, pick a state in the column (e.g. MA) and plan a Rally route through NJ and PA.
   - The route line goes to the column circle and back; nothing is drawn outside the map.
6. Rotate the phone emulator to landscape during the Campaign.
   - The map shrinks but every circle and its label stay inside the map.

Send back: one screenshot of MapReveal at phone portrait and one at 16:9, any state that was hard to tap (which one, which screen, what got selected instead), and the Output lines starting with "[270] UI audit" (there should be no WARN lines mentioning NodeMap, a state id, Label, Badge or Arrow).

## DESIGN.md notes (for D-030)

- WP1 map ladder: VT, NH, MA, RI, CT, NJ, DE, MD, DC leave the projection for a fixed column at x = 0.952 (box widths), centers evenly from 0.08 to 0.92 of the box height, radius 0.0305, with a 1 px `line`-color leader to the projected center. The projection's east edge moved from 0.95 to 0.86 to make room; land borders are not drawn for ladder states (their leader replaces them).
- Circle radius is now 0.0293 + 0.0040 * sqrt(EV) box widths (was 0.004 + 0.0062 * sqrt(EV)) so every label box (0.85 of the diameter) is at least 24 px at a 390 px map; the layout is sized for `MapLayout.PHONE_WIDTH = 390`. The plan's "0.8 · 2r · 390" formula with its ladder radius 0.0275 gave a 17 px box, not 21, so the label share went to 0.85 and the ladder radius to 0.0305 (20.2 px); nine of those only fit if the column spans the full map height.
- Tap targets: `MapLayout.hitRadius(n) = max(r, MIN_HIT / 2 / PHONE_WIDTH)` in box widths, plus a 36 px `UISizeConstraint` minimum. The layout keeps every target inside the box at 390 px; on smaller maps the target's anchor makes it grow inward, so it still never pokes out. Targets overlap on phones (36 px targets, 24-30 px circles); smaller states are created last so they win the overlap.
- `MapInterface.Mark` gains `arrow: ("up" | "down")?` and `arrowColor: Color3?` (default: text color). The plan named only `arrow`; the color was added because the arrow is drawn in the momentum leader's color and NodeMap cannot know who that is.
- Audit (`src/client/UI/Audit.luau`, outside WP1's files, additive): the `contained` rule skips rotated objects, because Roblox reports a rotated frame's unrotated box; every map border, leader and route segment is rotated and stays between two in-map points. `Audit.PENDING.NodeMap` and the NodeMap line in `Tokens.spec` PENDING are gone; `Audit.spec`'s filing test now installs a temporary NodeMap entry.
- No `Sim/Config.luau` numbers changed.
