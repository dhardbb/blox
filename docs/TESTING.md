# Studio playtest checklists

One section per feature, newest last. Each item: what to do, what should happen, what to send back. Send back the **Output** window log (right-click → Copy all) and any screenshots listed, with the commit hash or version you tested.

## Testing without Studio (agents)

Every playtest flow below also runs headlessly. `tests/lib/FakeRoblox.luau` runs the real server and client scripts with simulated players. `lune run tests` includes `tests/e2e/` (whole matches, typed plans, time bank, private codes, disconnects, cheating payloads). To play by hand, step by step:

```sh
lune run tests/play.luau -- "p1: practice" "p1! Autoplay" "until p1 match over" "screen p1" "logs"
lune run tests/play.luau -- --seed 7 "p1: queue" "p2: queue" "p1: select hale teal jobs farms safety" "p2! Auto" "autoto Week 1 Plan · Input 120" "p1: plan rally TX jobs; fund TX" "screen p1"
```

The fake engine does not render anything and is not the real engine. Before calling a feature done, confirm it in Studio.

## Getting the build into Studio

Either:

- **Place file:** download the `270-place` artifact from the latest green CI run (GitHub → Actions → CI → the run → Artifacts), unzip, and open `270.rbxl` in Roblox Studio. Or build it yourself: `rojo build -o build/270.rbxl`.
- **Live sync:** clone once with `git clone https://github.com/dhardbb/blox ~/Documents/Code/270`, install the toolchain (`rokit install`), then in `~/Documents/Code/270/` run `rojo serve`, then in Studio open the Rojo plugin and click **Connect**. Edits to files sync into the open place.

Two-player tests use **Test → Clients and Servers → Local Server, 2 Players → Start**. That opens one server window and two client windows; the Output of each is separate.

---

## Phase 0: Scaffold (v0.0.1)

1. Open `270.rbxl` and press **Play** (F5).
   - Output shows `[270] server up: v0.0.1 (0 Scaffold), 12 weeks`.
   - Output shows `[270] client up: v0.0.1 (0 Scaffold)`.
   - No red errors.
2. In the Explorer, check the tree:
   - `ReplicatedStorage > Shared` contains `Version` and a `Sim` folder with `Config`.
   - `ServerScriptService > Server` contains `Main`.
   - `StarterPlayer > StarterPlayerScripts > Client` contains `App`.
   - Screenshot the expanded Explorer.
3. Optional, Rojo sync: with `rojo serve` running and the plugin connected, change `VERSION` in `src/shared/Version.luau`, press Play again, and confirm the new version prints.

**Send back:** the Output log from step 1 and the Explorer screenshot from step 2.

## Phase 1: Simulation core (v0.1.0)

There's still no game UI. This checks that the simulation, which so far has only run under Lune, also runs inside Roblox.

1. Open `270.rbxl` and press **Play** (F5).
   - Output shows `[270] server up: v0.1.0 (1 Simulation core), 12 weeks`.
   - Within a second or two, Output shows a line like `[270] sim self-test: seed 1761091234: Dana Okafor 281 - 257 Rex Calloway, winner Dana Okafor, 25 phases in 140 ms`.
   - The two EV numbers add up to 538.
   - No red errors, and no `sim self-test FAILED` warning.
2. Stop and press **Play** again. The seed changes, so the candidates and score should usually change too.
3. In the Explorer, check that `ReplicatedStorage > Shared > Sim` contains `Bot`, `Debate`, `Draft`, `Election`, `Leans`, `Match`, `Plan`, `Polls`, `Resolve`, `State`, `Support` and `View`, next to the Phase 0 modules.

**Send back:** the two Output lines from step 1 (and the `FAILED` warning in full, if you see one), plus the milliseconds figure from both runs.

## Phase 2: Server and networking (v0.2.0)

The screen is a plain text debug UI: a yellow status line, the board as text, a log, a row of buttons, and a command box. It's ugly on purpose; Phase 3 replaces it.

Start with **Test → Clients and Servers → Local Server, 2 Players → Start**. You get a server window and two client windows (Player1, Player2).

1. **Both clients load.**
   - Each client shows the debug UI and the status line says `Lobby: Idle · 0 in queue`.
   - The server Output shows `[270] server up: v0.2.0 (2 Server and networking), 12 weeks` and the sim self-test line.
   - Each client's Output shows a `[270] debug UI sizes: ...` line and **no** `button ... under 44px` or `truncated` warnings. If you see those, screenshot the client window.
2. **Practice vs the bot (one client).** In Player1, press **Practice**, then **Autoplay**.
   - The status line walks through Select, MapReveal, 8 Draft rounds, Week 1–12 (with Debate in weeks 4 and 9), Election, and ends back at `Lobby: Idle`.
   - The log shows `match over: Election`, and the board shows `YOU WON` or `You lost` with the EV score.
   - With Autoplay on, a match takes about 1½ minutes (the draft reveals and debates can't be skipped).
3. **Two players (both clients).** Press **Queue** in Player1, then in Player2.
   - Both status lines switch to `m2 · Select · Input · 30s · your move` (the match number may differ).
   - In Player1, type `select hale teal jobs farms safety` and press Enter. The status shows `LOCKED`. In Player2, press **Auto**. Both move on to MapReveal.
   - Turn **Autoplay** on in both clients and let the match finish. Both should see the same final EV score, mirrored (yours first).
4. **A hand-typed week.** In a new two-player match, play to Week 1 with Auto. Then, in Player1:
   - Type `show OH` to see a state's details.
   - Press **Bank** before locking: your countdown jumps up by 15 s, and the other client shows your bank dropping from 30 to 15.
   - Type `plan gotv OH 9`. That's over the per-state cap, so the log shows `rejected Submit: GotvCap`, and the server Output shows a `[270] rejected Submit from Player1 ...` line. Nothing is spent and you're still unlocked.
   - Type a plan that uses your home state (shown as `home XX` on your `YOU` line), for example `plan rally XX jobs; fund XX; poll OH`. It should lock without a rejection.
5. **Private code.** In Player1 press **Host**: the status line shows `your code ABCDE`. In Player2 type `join ABCDE` with that code. A match starts. Typing `join ZZZZZ` instead should log `rejected Join: NoSuchCode`.
6. **Disconnect.** During a two-player match, close the Player2 window.
   - Player1's log says `Opponent disconnected...`, and the board shows `DISCONNECTED (grace 30s)` counting down.
   - After 30 s Player2's turns auto-submit. Two weeks later Player1 wins by forfeit: `YOU WON (Forfeit)`.
7. **A cheating client (optional).** In Player1's command bar (View → Command Bar, set to the client), run:
   `game.ReplicatedStorage.Remotes.ToServer:FireServer({ op = "Submit", matchId = "x", step = 1, input = { actions = { { kind = "Rally", state = "OH", issue = "Jobs", support = 99 } } } })`
   The server Output shows `[270] rejected Submit from Player1 (...): NotInMatch` (or `StaleStep`/a plan reason during a match), and nothing changes.

**Send back:** the server Output and both client Outputs (right-click → Copy all) from steps 1–3, any rejection or red error lines from the rest, a screenshot of one client mid-campaign, and how long the step 2 practice match took.

## Balance pass 1 (unreleased)

Numbers only; nothing new to click. Confirms the retuned roster loads in Roblox.

1. Open `270.rbxl` and press **Play** (F5).
   - Output shows the `[270] sim self-test:` line as in Phase 1, with no `FAILED` warning. The two EV numbers add up to 538.
2. Press **Play** a few more times. Over several runs you should see different candidates named; any of the eight may appear and win.

**Send back:** the self-test lines from three runs.

## Ratings and saved stats (unreleased)

Saving needs a real DataStore, and Studio only gets one when the place is **published to Roblox** and **Home → Game Settings → Security → Enable Studio Access to API Services** is on. Without both, the game still works: it warns once and keeps ratings in memory only. (The headless tests cover everything except the real DataStore.)

Use **Test → Clients and Servers → Local Server, 2 Players → Start** as before. Studio test players have negative user ids, so their records are keys like `Player_-1` in the game's real `PlayerData_v1` store. They are harmless test data; reset a player by removing the key in Creator Hub → your experience → Data Stores.

**A. Unpublished, or API access off (the fallback).**
1. Start the 2-player server on a place that isn't published, or with API access off.
   - Server Output has exactly one warning: `[270] DataStore unavailable (publish the place and enable Studio API access to save); using memory`.
   - Both clients show `Lobby: Idle · Rating 1000 (0-0) · 0 in queue`.
2. Queue both players and play a match with Autoplay.
   - Both see `Rating 1000 → 1016` or `Rating 1000 → 984` (one each way) in the log and under the result, and the lobby line shows the new rating and record, e.g. `Rating 1016 (1-0)`.
   - Stop the test and start it again: ratings are back at 1000. That is expected in this mode.

**B. Published, API access on (real saving).**
1. Start the 2-player server.
   - Server Output: `[270] loaded Player1: rating 1000 (0-0)` for each player, and **no** `DataStore unavailable` warning.
2. Queue both and play a match to the end. Ratings move by equal and opposite amounts (16 on a first match). Stop the test. The server Output shows no `could not save` warnings.
3. Start the test again.
   - Each client's lobby line shows the rating and record from before, e.g. `Rating 1016 (1-0)` and `Rating 984 (0-1)`.
4. Practice: press **Practice** and play with Autoplay.
   - The lobby rating does not change (no `Rating a → b` line). Stop and restart: still the same rating.
5. Forfeit: in a two-player match, close Player2's window. After the forfeit, Player1's log shows `Rating ... → ...` (a gain). Restart the test: Player2's lobby line shows the loss (the rating dropped), even though they were gone when the match ended.
6. In Creator Hub → Data Stores → `PlayerData_v1`, open a `Player_-1` key (optional): `data.rating`, `wins`, `losses`, `perCandidate` and `recent` are there, and `lock` is gone after the test stopped (a `lock` with a `jobId` while it runs is correct).

**Send back:** the server Output from A step 1 and B steps 1–3, the lobby lines before and after the restart in B step 3, and any `[270] ... DataStore` warning lines you didn't expect.

## Phase 5: event deck (unreleased)

Simulation, server and debug UI only; the campaign screen shows events later. Events are on in the queue and practice, and off in a private match hosted with `host noevents`.

**Headless check (agents):** play a practice match to week 2 and read the board. Seed 3 deals a Regional there, and weeks 10 and 11 are Choice events:

```sh
lune run tests/play.luau -- --seed 3 "p1: practice" "autoto Week 2 Plan · Input 300" "screen p1"
#   Event this week: Coastal festival (Regional: rallies in Pacific x1.5, max +2 per state). Music festivals line the Pacific coast all week.
lune run tests/play.luau -- --seed 3 "p1: practice" "autoto Week 10 Plan · Input 900" "p1: plan choice attack" "until p1 \"Week 11 Plan\" 120" "screen p1"
#   Last week's event Rumor mill: you Attack (-0.2), them Attack (-0.2)
#   Opponent last week: ..., choice Attack
```

In Studio (**Local Server, 2 Players**):

1. **Practice.** In Player1 press **Practice**, then **Auto** until `Week 2 Plan`.
   - The board has a line `Event this week: <name> (<what it does>). <flavor text>`. Week 1 has no event line.
   - Turn **Autoplay** on. Every week from 2 to 11 shows a different event; week 12 shows none.
2. **A Choice week.** Keep pressing **Auto** until the event line says `Choice: add "choice attack|defend|ignore" ...`. Then type `plan choice defend` (add other actions if you like, e.g. `plan rally XX jobs; choice defend`). It locks.
   - The next week the board shows `Last week's event <name>: you Defend (...), them <answer> (...)`, and `Opponent last week:` ends with `choice <answer>`.
   - In a week that isn't a Choice week, `plan choice attack` is rejected with `rejected Submit: UnexpectedChoice`. `plan choice maybe` gives a local error.
3. **Private match without events.** In Player1 type `host noevents`, and in Player2 `join <code>`. Play to week 2 with **Auto**: there is no `Event this week` line all match. A plain `host` match does have one.

**Send back:** the board text (copy the client Output or a screenshot) from steps 1 and 2, and the rejection line from step 2.

## Phase 3: Client MVP (v0.3.0)

1. In Studio, open a Baseplate, connect Rojo (Plugins → Rojo → Connect) and press **Play**.
   - The Lobby shows "270", your rating (once saved data loads) and Play vs Bot / Find Match / Host / Join.
2. Press **Play vs Bot** and play a whole match by hand: pick a candidate, color and 3 issues; draft 8 rounds by tapping states or list rows; plan weeks by tapping a state, then Rally / Fundraise / Ad / Attack / Poll / GOTV, then **Lock in**; watch the results animation; answer Choice events; watch election night.
   - Nothing overlaps; every button is easy to hit; the countdown runs; the Results screen shows the winner and "Back to lobby" works.
3. Phone check: Studio's **Test → Device** emulator, pick a phone in portrait, repeat a few steps.
4. Any screen without a server: in the command bar run `workspace:SetAttribute("DebugScreen", "Plan")` (or Select, Draft, Resolve, ChoiceWeek, Election, Over...) before **Play**.

**Send back:** screenshots of each screen, anything confusing, and the Output lines starting with `[270] UI audit`.

## Bug hunt fixes (v0.3.1)

1. **Play vs Bot**, reach a plan week on a phone (Test → Device, portrait). Tap **Pick a state from the list**, then **DC**.
   - The list shows all 51 states; the sort button cycles closest / biggest / A to Z; tapping DC selects it and closes the list.
2. In a plan week, queue a valid plan and **don't** press Lock in. Let the timer run out.
   - Your plan is used (the week card shows your actions), not a blank week.
3. Do the same in Select (candidate, color and 3 issues chosen) and in the Draft (one state picked).
   - The match moves on with your choices.
4. Two-player test (Test → Clients and Servers, 2 players): during the Draft, close one client.
   - The other sees "Opponent: disconnected"; once the grace time is up the notice says "Opponent disconnected" with no negative countdown.

**Send back:** anything that looks off, with a screenshot and the Output lines starting with `[270]`.

## UI overhaul (v0.4.0)

### Foundation (design system)

Groundwork only: the screens are redesigned by the next four packages. This build should look and play like v0.3.1.

1. Connect Rojo, press **Play** and play a few weeks against the bot.
   - Every screen still works; small grey text is a touch smaller (13 px); panels have slightly rounder corners.
2. In the Lobby, type `ZZZZ9` in the code box and press **Join**.
   - A message box appears at the top center with a red outline and disappears after about 5 seconds (the Lobby's own message line still shows too, until the Lobby package removes it).
3. Press **F2** with the phone emulator (Test → Device, a phone in portrait).
   - The debug panel's buttons sit in two rows (Practice … Autoplay, then Pass … Help); none is squashed.
4. With `workspace:SetAttribute("DebugScreen", "Plan")` before **Play**, then rotate the emulated device (or switch between a phone and a 16:9 device).
   - The Output shows `[270] UI audit Campaign: 0 problem(s), N pending, M text size(s)` once after the screen appears and again after the rotation, plus a few `[270] UI audit Campaign pending ...` lines. No `WARN` lines.

**Send back:** the Output lines starting with `[270] UI audit`, and a screenshot of the toast from step 2.

### Map

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

### Lobby, Select and Results

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

### Campaign

Run in Studio twice: once with the device emulator at a phone in **portrait** (e.g. iPhone 14, 390x844), once at a plain **16:9** window. Start "Play vs Bot".

1. **Week 1 plan, phone portrait.** Without scrolling you should see: the header (week, stage, timer) and the score row under it (your name and EV, the bar, theirs, money, AP), the map, the state card down to the action grid, and the **Lock in** bar at the bottom. Lock in must be visible without touching the screen. Screenshot it.
2. Tap a state on the map, then **Rally**, **Fundraise** in another state, **Ad**. The bar's status line should change ("AP 2/3 · $... left · 1 flight"). Scroll the side column: "Your plan · 2 of 3 AP" lists the three lines.
3. Tap a different **message chip** (e.g. "Health ×1.0"), then Rally: the new plan line names that issue. Tap **More ▾**: the remaining issues appear.
4. Tap **Region poll** on a state: the plan line reads "Region poll · <region>" and the button greys out ("polled"). (Week 1 has no money; try it from week 2.)
5. Make a plan you can't afford (e.g. several Ads): **Lock in** turns grey and reads "Not enough money"; the status line says why in red. Remove a line with ×: Lock in comes back.
6. Tap **Clear** once: it reads "Clear? tap again". Wait 4 seconds: it goes back to "Clear". Tap twice quickly: the plan empties.
7. Tap **Pivot**: the grid is replaced by "Drop which issue?"; tap **Cancel** and the grid comes back.
8. Tap **Lock in**: it reads "Locked in", the status line "Locked in · waiting for opponent", the opponent line "Opponent: locked in" once the bot locks.
9. **Results reveal**: the reveal panel is at the top, the state card under it with no buttons; tap a state on the map and the card follows. The bar's button reads **Skip**; tap it: "Waiting for opponent…".
10. **Week 3 and week 8** (the weeks before a debate): **Debate prep** is right under the event card and above "Your plan", on both phone and 16:9, without scrolling past Lock in. Push one topic to 4: its + greys out and the row says "+: max 4". The status line ends with "prep 4/1/1".
11. **A Choice week** (an event that asks Attack/Defend/Ignore): the event card is the first panel, open, with three answer chips; Ignore has a yellow outline (not a yellow fill). Only **Lock in** is filled yellow anywhere on screen.
12. **Debate reveal** (weeks 4 and 9): no event card and no "Choose how to respond" text anywhere; the three topics appear one by one with two thin score bars; the bar shows "Debate · topic N of 3" and no button.
13. Let the timer run down: it turns red at 0:09.
14. **16:9**: the header is a single row; the week card is open at the bottom of the side column; the state list ("All states · sorted closest ▾") stays open after picking a state. On the phone the week card starts collapsed and the list closes after a pick.

Send back: the screenshots from steps 1, 9, 10 (week 3 and week 8), 11 and 12 at both sizes, and the Output lines that start with `[270] UI audit Campaign` (they should say `0 problem(s)`).

### Draft and Election night

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

## Playtest 1 fixes (v0.4.1)

1. **Play vs Bot**, reach a plan week and fundraise once (Fundraise in your home state), then lock in. In the next week, look at your money in the top bar.
   - It shows one decimal and never more than you have: a plan that costs exactly the shown amount locks in.
2. Queue Ads until the plan costs more than your money (add a state you need to fly to, if you can).
   - Lock in is grey and reads "Not enough money"; the bar says "Plan costs $X, you have $Y (...)" and lists the flights and ads.
3. Two-player test (Test → Clients and Servers, 2 players): on both clients pick the **same color** at Select and lock in.
   - One player keeps it. The other sees a toast "Your opponent also picked ... and the coin flip gave it to them: you are ... this match." The map and names use the actual colors on both clients.
4. In the same test, during the two Nominate rounds, nominate one of the other player's strongholds.
   - On the Draft board that player's line lists it under "nominated by ..." and not under "strongholds". In the campaign, the state card for it says "Battleground" and "Was your stronghold" / "Was their stronghold".
5. Press **F2** (debug text panel) during the Draft and after week 1.
   - The log names the picks ("P1 picked OH (home)") and last week's events in words; money has one decimal and no long decimals anywhere; debate lines read "national -0.2 you, +0.4 them".

**Send back:** a screenshot of anything that looks off (especially a money amount that seems wrong, or a toast that is cut off on a phone), with the Output lines starting with `[270]`.

## Balance pass 2 (v0.5.0)

Numbers and one perk reshape (`DESIGN.md` D-033 to D-036); the only new thing on screen is Helen Strand's event preview. Two-player test (**Test → Clients and Servers, 2 players**), or **Play vs Bot** where a step says so. Press **F2** for the debug text panel when a step asks for the board.

1. **Debates feel like prep matters.** Pick any two candidates. In week 3 put **4/2/0** on one side and leave the other at 2/2/2 (or play vs bot, which spreads its points). Watch the week-4 debate reveal.
   - The 4-vs-2 topic goes to the 4 most of the time (about 8 in 10 across matches), and the 0-vs-2 topic goes to the 2 almost always, with "gaffe" on the zero. Each topic won reads **+0.3** national, a 3-0 sweep **+1.2**.
   - On the board after the debate, the projected EV should visibly move (one or two close states) when one side wins 2-1 or better.
2. **Fundraising is flat.** Play vs Bot as Dana Okafor or anyone else. Fundraise **once in your home state** in weeks 1, 2, 3 and 4 (plus whatever else you like).
   - "You raised" is about the same every week (about $5.5-7 at home for a plain candidate, 50% more for Okafor), not $7 then $4.5. Three home fundraisers in week 1 raise under $10 in total, not $18-20.
   - A fundraiser in a state the opponent also funded still splits the pool (lower yield that week).
3. **Helen Strand's briefing.** Pick Helen Strand on one client. From week 1 on, her event card (and the F2 board line `Next week's event (your pollster's briefing): ...`) names **next week's** event as well as this week's; the other client sees only this week's. In week 11 she sees no preview (week 12 has no event). Her two free polls still work (Poll on two states costs $0).
   - If the campaign screen does not yet show the preview (the client is being updated separately), the F2 board line is what to check.
4. **Choice weeks have a payoff.** In a Choice week pick different answers on the two clients, e.g. Defend vs Attack, then Ignore vs Defend the next time.
   - The reveal line shows the winner with a **positive** number and the loser with a negative one: Attack over Ignore +0.3 / -0.2, Defend over Attack +0.2 / -0.3, Ignore over Defend +0.2 / -0.2. Same answers: Attack/Attack -0.2 each, Defend/Defend and Ignore/Ignore 0.
5. **Candidates.** Over several bot matches, Marcus Hale (7 prep) and Helen Strand should win about as often as anyone else; the roster numbers on the Select screen match `Candidates.luau` (Strand: "Sees next week's event a week early; two free internal polls a week").

**Send back:** the debate reveal screenshots from step 1 (both weeks), the "You raised" amounts from step 2, and whether Strand's preview was visible on the campaign screen or only on the F2 board.

## Explaining the numbers (v0.5.0)

1. **Play vs Bot**, reach week 1's plan. Tap a state near your candidate.
   - Under the action buttons, "What each action does here –" lists eight lines, one per button. Rally and Ad say "about +N you, -N them here (Issue ×N …)"; Fundraise says "up to about $N here (… pool $N when full …)".
2. Tap a different message chip (e.g. a ×0.8 issue).
   - The Rally and Ad lines change to that issue and show smaller numbers.
3. Tap **Ad** twice in the same state.
   - The Ad line now says "repeat ad #3 ×0.36" (or similar) and a smaller number.
4. With at least $9, tap **Attack ad** three times in one state, then read the Attack ad line (it previews the fourth).
   - It reads "backlash costs you 0.8 and resets" and the "you" number is smaller or negative.
5. Tap a state far away (not next to your route).
   - Rally and Fundraise lines end with "1 AP + flight $2.0".
6. Read the state card's **Lean** and **Momentum**.
   - Lean says "leans you +N", "leans them +N" or "no lean". A line under the stats says what momentum does there next week.
7. Tap **?** in the header.
   - "How it works" covers the screen with eight panels; the countdown keeps running at the top right; scroll to the bottom; tap **Close**. You are back on the campaign with your plan intact.
8. Repeat step 7 at the candidate Select screen and during a Draft round.
9. In a **Choice** week, open the event card.
   - Under Attack / Defend / Ignore, three lines show what each answer pays against each of the opponent's.
10. In the week before a debate, look at the prep panel.
    - Each topic row shows "You: N prep + … = N, plus a roll 0 to 6 · them: …". The last line gives the chance to win a topic level and 2 points ahead.
11. Watch the debate (week 4).
    - Each topic row shows both sides' prep, platform, stat and roll adding up to the score. The week card says the same in the debate week.
12. Phone check: Test → Device → an iPhone in portrait, then landscape. Repeat steps 1 and 7.
    - Nothing is cut off; Close and Lock in are always on screen.
13. Press **F2**, type `rules` and `show OH`.
    - `rules` prints the help text; `show OH` adds the lean, momentum and the eight action lines.

**Send back:** any preview number that looked wrong after the week resolved (state, action, what the line said, what the poll did), screenshots of the help screen on a phone, and the Output lines starting with `[270] UI audit`.

## Playtest 2 fixes (unreleased)

1. Open a practice match, press **F2** for the debug panel, and at Week 1 Plan type `plan ad <your state> jobs`. Should: lock in like `media` did (if you have $3). Send back: the log line.
2. In the campaign, select a state where one side has momentum (the ▲ on the map). Should: the state card says "about +X support drifts to … next week" and "Drift: … about 0.3 support next week per point of momentum lead shown now …". Next week, check the state moved by about that much if nobody campaigned there. Send back: a screenshot of the card, and the two polls.
3. Open "?" (How it works) → "Leans, momentum, backlash, underdog". Should: the same drift sentence, with your candidate's numbers (Tomas Reyes: 25% kept, 0.15 per point). Send back: a screenshot.
