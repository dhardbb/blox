# WP2: Lobby, Select, Results (UI overhaul v0.4.0)

Notes for the merge step to fold into `CHANGELOG.md`, `docs/TESTING.md` and `docs/DESIGN.md`.

## Changelog bullets

- Lobby: one centered column up to 560 px wide that no longer scrolls. "270" is now hero size. "Play vs Bot" is the only yellow button. Find Match, Host Private Match and Join are grey. Cancel is outlined in red. The code box uses the darker field color.
- Lobby: the record line ("Rating 1000 · 3 won, 2 lost") keeps its space before the profile arrives, so the buttons don't jump down. A private match code shows in hero size on a dark well.
- Lobby: the Lobby's own toast is gone. Server messages and the "Enter the 5-character code" warning use the global toast at the top of the screen.
- Select: the standard header with the timer, which turns red under 10 s (was 5 s). Lock in is pinned in a bar at the bottom.
- Select: everything fits without scrolling at 16:9. Cards are 112 px on 16:9 and 124 px on phones (were 170 and 224). The six colors sit in one row in both orientations, with two-letter names on phones. Issue chips read "Jobs · 160 EV" on one line.
- Select: picks show as an outline plus a "✓". Nothing is filled yellow except Lock in.
- Select: when a pick is missing, the disabled Lock in button names it ("Pick a candidate", "Pick a color", "Pick 2 more issues"). The status line says "Still to pick: …", with "▾" when the issues are below the fold. Other status lines: "Ready", "Locked in · waiting for opponent", and "Opponent: thinking / locked in / disconnected".
- Select: tapping a fourth issue shows "You already have 3; tap one to swap it" for 3 s. Before, nothing happened.
- Select: when the pick is restored from your last match, the status says "Your last pick is loaded · Lock in or change it".
- Select (bug B4): a rejected Lock in now says why. The reason shows in the toast and stays in the status line in red until you change something, and the picks unlock. Before, nothing was shown.
- Results: the banner reads "You won" / "You lost" / "No result" at hero size, and the EV totals use title size. The rating line keeps its space, so nothing shifts when it arrives.
- Results: the EV bar has a 270 tick. Closest states and debates are collapsible sections, open by default. "Play vs Bot again" (or "Play again") and "Back to lobby" are pinned at the bottom.

## TESTING.md checklist

Test each screen twice: at 16:9 (Studio's default window, or Device: 1920x1080) and at phone portrait (Device emulator: iPhone 14 or any 390x844).

**Lobby**
1. Open the place and press Play. You should see "270" in large yellow, a one-line pitch, a grey record line, then "Play vs Bot" (yellow, taller), "Find Match" and "Host Private Match" (grey), "Have a code?", and a dark code box with a grey Join.
2. Check that no other button is yellow and that nothing scrolls on either size.
3. Type `AB` in the code box and tap Join. A toast with a red outline should appear at the top: "Enter the 5-character code…". It goes away after about 5 s.
4. Tap Host Private Match. The code should show large on a dark panel, with a red-outlined Cancel. Tap Cancel to go back.
5. Send back: one screenshot per size, idle and hosting.

**Select** (tap Play vs Bot)
1. At 16:9, without scrolling, you should see 8 candidate cards (4x2), 6 colors in one row, and 8 issue chips (4x2), with the Lock in bar at the bottom. The timer is at the top right.
2. Before you pick anything, Lock in should be grey and read "Pick a candidate". The status above it should read "Still to pick: a candidate, a color, 3 issues". On a phone it ends in "▾".
3. Pick a candidate, then a color. The card gets a yellow outline and the swatch gets a white outline and "✓". Lock in should change to "Pick a color", then "Pick 3 more issues".
4. Pick 3 issues. Each shows "✓" and a yellow outline, not a yellow fill. Tap a 4th: the status should show "You already have 3; tap one to swap it" for 3 s.
5. Tap Lock in. The status should read "Locked in · waiting for opponent" in green, and the picks stop responding.
6. Let the timer run under 10 s on a later match. The timer should turn red.
7. On a phone: the colors read Cr / Co / Em / Am / Vi / Te. The issues are below the fold, Lock in stays visible, and one flick reaches the issues.
8. Play a second match. Your last pick should be preloaded and the status should say "Your last pick is loaded · Lock in or change it".
9. Send back: screenshots of steps 1, 4 and 7, and anything cut off or overlapping inside a candidate card, especially The Insurgent and The Ad Wizard on a phone.

**Results** (finish a match, or Autoplay in the debug panel)
1. You should see "You won" or "You lost" in large type, a muted reason line, and the EV bar with a thin white tick at 270. Below are both player panels side by side, then "Closest states ▴" and "Debate topics won … ▴" open.
2. Tap a section title. It should fold. Tap again to open it.
3. At the bottom, "Back to lobby" (grey, narrow) and "Play vs Bot again" (yellow) should stay pinned while the rest scrolls.
4. Send back: screenshots at both sizes.

The Studio Output should show `[270] UI audit Lobby|Select|Results: 0 problem(s), 0 pending` on every screen at both sizes. Send back any `WARN [270] UI audit` line.

## DESIGN.md notes (sub-bullet for D-030)

- WP2 (Lobby, Select, Results): all three screens are strict. They are gone from `Audit.PENDING` and `Tokens.spec` PENDING.
  - **Lobby** doesn't scroll, so its primary ("Play vs Bot") is never inside a ScrollingFrame. On screens shorter than 480 px the pitch line hides to make room. While queued, hosting or starting there is nothing to press first, so the screen sets `PrimaryOptional`.
  - **Select** stacks its scroll content with explicit pixel positions instead of the page's list layout. This lets the fake engine measure it, and lets the status line know whether the issues are below the fold (the "▾"). Card heights follow the plan: 112 px on 16:9 and 124 px on phones. On a phone the issues still scroll: the plan's portrait estimate left out the gaps between blocks, so "only the last two rows below the fold" is not reached. The pinned bar says so instead.
  - **Swatches** keep their own color. They don't use `Kit.setSelected`/`setEnabled`, which repaint a chip's background. Selection is a 3 px outline in the text color plus "✓", and the label color comes from `Colors.onColor`.
  - **Rejected Lock in (B4):** the reason stays in the status line in red until the next change. The toast is the attention-getter.
