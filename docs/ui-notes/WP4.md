# WP4: Draft (incl. MapReveal) and Election night

Notes for the merge into `CHANGELOG.md`, `docs/TESTING.md` and `docs/DESIGN.md`
(this package does not edit those files; see `docs/UI-OVERHAUL.md` §5).

## Changelog bullets

- Draft: the standard header ("Round 4 of 8 · Stronghold", the round's help line, the timer, red under 10 s while picking) and the standard pinned action bar ("Lock in", disabled "Pick a state", "Locked in · waiting for opponent", "Opponent: thinking / locked in / disconnected").
- Draft: your two picks are one row of chips, "1st: TX" and "2nd: —", each with a 44 px × once filled. "Clear both" is gone (the two × do it). Tapping a chip still aims the next pick at that slot; the aimed chip gets the accent outline.
- Draft: on phones the state list now comes right after the picks (it was 8th in the scroll, B10), and the legend and draft board moved into a "Draft board ▾" card at the end, collapsed. The map and the panel split by pixel math with no dead band (B11).
- Draft: a tap on a state you can't pick says why in the bar ("TX: already drafted") until your next tap, instead of a hint that vanished after 3 s. A rejected lock-in shows there too (and in the toast).
- Draft map reveal: the side panel shows the priority line, the legend and three lines on how the draft works, so it is no longer mostly empty.
- Draft reveal: "You got OH" and "They got PA" side by side, each outlined in its owner's color, with the clash note under them.
- Draft: legend reduced to one row plus a caption; the board is one line per candidate. State list rows are 44 px, the "your home" tag is caption size (was 11 px, B14).
- Election night: a header with "Results in 0:32" (B8) and the call status ("35 of 51 states called" / "Too close to call: …").
- Election night: both candidates share one 72 px strip with a single EV bar (your fill from the left, theirs from the right) and the 270 tick inside the bar's box (B9). "270 to win" now shows on phones too.
- Election night: the call feed has 44 px rows (state and EV on the left, who it was called for on the right) and bottom padding, so the last row is never clipped (B6). "Skip to results" is the pinned primary; after your tap it reads "Waiting for opponent…".
- Election night: the bar now says "Opponent: skipped" when they skip (B7), "Opponent: watching" before that, "Opponent: disconnected" if they drop.

## TESTING.md checklist

Run each in Studio twice: once in the device emulator as a phone in portrait (e.g. iPhone 14, 390 x 844) and once at 16:9 (e.g. 1920 x 1080 or the default window). Offline fixtures: in the command bar run `workspace:SetAttribute("DebugScreen", "MapReveal")` (then `"Draft"`, then `"Election"`) before **Play**. Live: **Practice** and play through.

Map reveal (`MapReveal`)
1. Look at the header: "The map for this match" (phone: "The map") on the left, the countdown on the right in yellow.
2. Right panel (16:9) / under the map (phone): "You have priority in round 1." (or "They have…"), the three lines on how the draft works, and the legend row with your color and theirs.
3. There is no Lock in button. Nothing is yellow-filled.
4. Phone: at the end of the panel there is a "Draft board ▾" row. Tap it: it opens and shows "You … home —" and "Them … home —".

Draft round (`Draft`, or any round in Practice)
1. Header: "Round 4 of 8 · Stronghold" (phone: "Round 4 of 8") and the help line "Stronghold: +8 support there…".
2. Phone: right under the map you see the priority line, then the two chips "1st: —" "2nd: —", then the state list starting with California. You should not have to scroll to reach the list.
3. Tap a state in the list: the 1st chip reads "1st: CA" (or the state you tapped) with a × next to it; the bar at the bottom says "Tap a backup (optional)" and the yellow button says "Lock in".
4. Tap a state that is already drafted (a row with a "their stronghold" tag, or a dimmed map node): the bar's status line turns red and says e.g. "OH: already drafted". Wait 5 seconds: it is still there. Tap another (legal) state: the red line goes away.
5. Tap "1st: …" (it gets a yellow outline), then tap a different state: that state replaces your 1st choice.
6. Tap the × next to the 1st chip: your 2nd choice moves up. Tap × again: "1st: —", and the button reads "Pick a state" in grey.
7. Pick one state and tap **Lock in**: the button reads "Locked in" (grey), the status line is green "Locked in · waiting for opponent", the × buttons disappear.
8. With 10 s or less left, the timer turns red.
9. After both lock in: the reveal shows "You got …" and "They got …" side by side, each outlined in that player's color, and no button at the bottom.
10. 16:9: the legend row and a two-line draft board ("You … home CA · strongholds … · battlegrounds …") sit under the map. Phone: they are inside the "Draft board ▾" card at the end of the list.
11. Rotate the emulator (portrait ↔ landscape) mid-round: the layout follows within half a second and your picks stay.

Election night (`Election`, or the end of a Practice match with Autoplay off)
1. Header: "Election night" with "N of 51 states called" next to it, and "Results in 0:32" counting down on the right.
2. Under it one strip: your EV number and name on the left, theirs on the right, "270 to win" in the middle, and one bar with a white tick near the middle. The tick does not stick out above or below the bar.
3. The Calls list fills from the top (newest first). Scroll to the bottom: the oldest row is fully visible above the bar, not cut off.
4. The bottom bar: "Safe states first, closest last" on the left, "Opponent: watching" (or "skipped" against the bot, which skips at once) on the right, and a yellow "Skip to results" button.
5. Two-player test (Test → Clients and Servers, 2 players): on player 2 tap Skip to results. Player 1's bar says "Opponent: skipped"; player 2's button says "Waiting for opponent…" in grey.
6. At the end the strip is replaced by "<name> wins 289–249" with a colored outline.

Send back: one screenshot of each step marked with a phone or 16:9 at the top (MapReveal 1, Draft 2, 4, 9, 10, Election 2, 3, 6), plus the Output lines that start with `[270] UI audit Draft` and `[270] UI audit Election` (they should say `0 problem(s)`; the map may still list pending notes until WP1 lands).

## DESIGN.md notes (a sub-bullet under D-030)

- **WP4 (Draft, Election night).** Both screens use `Header` and `ActionBar` and are strict in the UI audit (their `Audit.PENDING` and `Tokens.spec` entries are gone; only the map's `NodeMap` entry still applies to them). Big boxes are explicitly positioned so the fake engine can measure them: on phones the map is `min(width / MapLayout.ASPECT, 34 %)` of the height on Draft and `38 %` on Election, the panel starts `Kit.space.sm` under it, re-laid out when the screen size changes. Draft: the state list follows the pick chips; the legend and board sit under the map on 16:9 and in a collapsed `Collapsible` at the end on phones; the map reveal puts the legend in the panel and sets `PrimaryOptional` (as does a round's reveal). An illegal tap or a rejected lock-in is the bar's status (tone bad) until the next tap; no timed hint. Draft titles drop the round kind in portrait (the help line starts with it), because the header's title and timer share one 44 px row. Election: one 72 px strip, one shared bar with fills from both ends and the 270 tick inside a 22 px box; the banner replaces the strip at the end; the opponent's status comes from their seat (`skip`, `connected`), not only ours. No sim, payload or Config change.
- Element names that changed for agents: Draft's `LockBar`/`LockStatus`/`OpponentStatus`/`Hint`/`ClearChoices` are gone (use `ActionBar`, `BarStatus`, `BarOpponent`; `Clear1`/`Clear2` remain); the header title is `Header > … > Title`, its subtitle keeps the name `Explain` on Draft and `CallStatus` on Election. Draft's Lock in reads "Lock in" / "Locked in" (was "Lock In" / "Locked"); Election's Skip reads "Waiting for opponent…" after the tap (was "Waiting for opponent to skip…").
