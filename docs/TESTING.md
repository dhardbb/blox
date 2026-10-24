# Studio playtest checklists

One section per feature, newest last. Each item: what to do, what should happen, what to send back. Send back the **Output** window log (right-click → Copy all) and any screenshots listed, with the commit hash or version you tested.

## Testing without Studio (agents)

Every playtest flow below also runs headlessly. `tests/lib/FakeRoblox.luau` runs the real server and client scripts with simulated players. `lune run tests` includes `tests/e2e/` (whole matches, typed plans, time bank, private codes, disconnects, cheating payloads). To play by hand, step by step:

```sh
lune run tests/play.luau -- "p1: practice" "p1! Autoplay" "until p1 match over" "screen p1" "logs"
lune run tests/play.luau -- --seed 7 "p1: queue" "p2: queue" "p1: select hale jobs farms safety" "p2! Auto" "autoto Week 1 Plan · Input 120" "p1: plan rally TX jobs; fund TX" "screen p1"
```

The fake engine does not render anything and is not the real engine. Before calling a feature done, confirm it in Studio.

## Getting the build into Studio

Either:

- **Place file:** download the `270-place` artifact from the latest green CI run (GitHub → Actions → CI → the run → Artifacts), unzip, and open `270.rbxl` in Roblox Studio. Or build it yourself: `rojo build -o build/270.rbxl`.
- **Live sync:** clone once with `git clone https://github.com/dhardbb/blox ~/Documents/Code/270`, install the toolchain (`rokit install`), then in `~/Documents/Code/270/` run `rojo serve`, then in Studio open the Rojo plugin and click **Connect**. Edits to files sync into the open place.

Two-player tests use **Test → Clients and Servers → Local Server, 2 Players → Start**. That opens one server window and two client windows; the Output of each is separate.

---

## Playing online with a partner (Mac + iPad, different networks)

Studio's local 2-player test only works on one computer. To play from two places, publish the game to Roblox as a private experience and invite your partner as an early tester.

**Once, on the Mac (in Studio, with the latest build synced):**
1. Clear any debug attribute: Workspace → Properties → Attributes should not list `DebugScreen` or `DebugText`.
2. **File → Publish to Roblox**. Give it a name (e.g. "270 playtest"), pick a genre, **Save**. It stays private: only you and invited testers can play.
3. Be Roblox friends with your partner. **File → Invite early testers**, search for them, **Invite**. Roblox may ask you to verify your age first.
4. Optional, to keep ratings between sessions: Creator Dashboard → your experience → keep it private; DataStores work automatically in live servers.

**Each session:**
1. Mac: open the experience from the Creator Dashboard (or roblox.com → Create → your experience) and press **Play**. Studio is not needed.
2. iPad: open the Roblox app, find you in Friends, and press **Join** on your profile so you land in the same server (the in-game lobby only matches players in one server). If Join is greyed out, they can open the experience from the invite and you both retry until you are in one server; the lobby's queue count shows 1 when the other is there.
3. One of you presses **Host Private Match** and reads the 5-letter code out; the other types it under "Have a code?" and joins. (Or both press **Queue**.)
4. Play. A match is about 15 minutes.

**After updating the game:** Claude pushes code; Rojo syncs it into Studio; then **File → Publish to Roblox** again. Players in an old server keep the old version until they leave and rejoin.

**What to send back:** who won and by how much, the moment that felt best and the one that felt worst, any stance you regretted (and why), and screenshots of anything that looked wrong. Note which device saw it (iPad touch vs Mac).

## Drawn issues and colors, unique candidates (v0.8.0)

Design log: `docs/DESIGN.md` D-047 and D-048. Use **Test → Clients and Servers → Local Server, 2 Players** for steps 3–5 (an iPad as the second player works too).

1. Press **Practice**. The Select screen is now two steps.
   - Step 1 shows the eight candidates and a line "Your color this match: …" (no color buttons). One candidate card is greyed out and says "Taken by your opponent" (the bot's); tapping it does nothing.
   - Tap a free candidate, then **Next: issues**. Step 2 shows "2. Issues for <name>", the same color line, and eight issue chips, each with two lines: the issue, then "N EV · ×1.NN".
   - The chips' EV numbers differ from match to match, and a smaller EV has a bigger × (for example "108 EV · ×1.72" next to "161 EV · ×1.39").
2. Pick three issues and **Lock in**. On the map reveal, open a state card: its "Top issues" line names this match's two. Start a second practice match: the EV numbers and the top issues on the state cards are different.
3. Two players: both pick the **same candidate** and press **Next: issues** at about the same moment.
   - One goes to step 2; the other stays in step 1, sees that card turn "Taken by your opponent" and a message saying the opponent got it (or that they already have it). Pick another and carry on.
4. Two players: Player1 claims a candidate; Player2 watches step 1.
   - Within a second Player2's card for it greys out as taken.
5. Two players: let the 38-second timer run out without pressing anything.
   - Both still get different candidates and different colors; the match starts.
6. Phone/iPad check: both steps fit without scrolling and **Next: issues** / **Lock in** stay on screen.
7. Press **?** in the header: the Actions panel says the top issues are drawn each match and that niche issues hit harder, with the × range for this match and your own platform's numbers.

**Send back:** a screenshot of step 2 from two different matches (the EV and × numbers), what step 3 showed the player who lost the claim, and any `[270] UI audit` lines.

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
   - The status line walks through Select, MapReveal, 3 Draft rounds (8 before D-045), Week 1–12 (with Debate in weeks 4 and 9), Election, and ends back at `Lobby: Idle`.
   - The log shows `match over: Election`, and the board shows `YOU WON` or `You lost` with the EV score.
   - With Autoplay on, a match takes about 1½ minutes (the draft reveals and debates can't be skipped).
3. **Two players (both clients).** Press **Queue** in Player1, then in Player2.
   - Both status lines switch to `m2 · Select · Input · 30s · your move` (the match number may differ).
   - In Player1, type `select hale jobs farms safety` and press Enter. The status shows `LOCKED`. In Player2, press **Auto**. Both move on to MapReveal.
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
2. Press **Play vs Bot** and play a whole match by hand: pick a candidate, color and 3 issues; draft 3 rounds (home, then two battlegrounds) by tapping states or list rows; plan weeks by tapping a state, then Rally / Fundraise / Ad / Attack / Poll / GOTV, then **Lock in**; watch the results animation; answer Choice events; watch election night.
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
2. Right panel (16:9) / under the map (phone): "You have priority in round 1." (or "They have…"), "Your strongholds: … · theirs: …" (five each, ringed in each color on the map), the three lines on how the draft works, and the legend row with your color and theirs.
3. There is no Lock in button. Nothing is yellow-filled.
4. Phone: at the end of the panel there is a "Draft board ▾" row. Tap it: it opens and shows "You … home —" and "Them … home —".

Draft round (`Draft`, or any round in Practice)
1. Header: "Round 2 of 3 · Nominate" (phone: "Round 2 of 3") and the help line "Battleground: the state loses all draft bonuses…" (round 1 is "Home state").
2. Phone: right under the map you see the priority line, then the two chips "1st: —" "2nd: —", then the state list starting with California. You should not have to scroll to reach the list.
3. Tap a state in the list: the 1st chip reads "1st: CA" (or the state you tapped) with a × next to it; the bar at the bottom says "Tap a backup (optional)" and the yellow button says "Lock in".
4. Tap a state you can't pick (in a nomination round, a home: a row with a "their home" tag, or a dimmed map node; in the home round, a stronghold): the bar's status line turns red and says e.g. "OH: a home state, can't nominate". Wait 5 seconds: it is still there. Tap another (legal) state: the red line goes away.
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

## Map lenses (v0.8.0)

The map switch (`DESIGN.md` D-046). **Play vs Bot**; do it once in the Studio window (16:9) and once on the iPad (or **Test → Device → iPad**), portrait and landscape.

1. **Draft.** Over the map: a short grey line and four chips, **EV / Issues / Polls / $**. EV is outlined.
   - Every state shows its electoral votes under its name ("54" under CA); battlegrounds add a gold "B". Draft tags (H, B, 1, 2) still sit on top of the circles.
2. Tap **Issues**. Each state shows two codes (JOB, HLT, SCH, ENV, SAF, TRN, TEC, FRM); the ones on your platform are filled in your color. The grey line says how to read it. Tap **$**: each state shows a dollar amount.
3. Draft through to week 1. The campaign map should open on **$** (the lens is remembered). Tap **EV**.
   - Should: only the fill colors, owner rings, the EV numbers and any "*" from this week's event. No "H B G3" tags, no ▲ arrows. The line left of the chips explains EV and B.
4. Tap **Polls**. Each state shows the poll lead in the leader's color ("+3", "tie"). After a week with a Poll action, the polled states add "i+…" (your internal poll). Plan **Ground game** in a state: it shows "G1" right away. States with momentum show a ▲ in that side's color.
5. Tap **$**. Plan two or three **Fundraise** actions in one small state: its number drops with each, and it fades once your plan has used up its pool. The number matches the state card's Fundraise line.
6. In a Choice week, the stance screen (`Decision`, D-044) has no lens chips: its map shows only the stance preview. Lock in: on the plan screen the lens you picked is back.
7. **iPad / phone.** The chips are easy to hit with a thumb, nothing overlaps the map, and the pills stay readable on the big states. In the crowded Northeast the pills may overlap their neighbors in the Issues and Polls lenses: say if that makes them unreadable.

**Send back:** a screenshot of each lens on the campaign map (16:9 and iPad), whether the default map now feels calmer, which lens you used most, and the Output lines starting with `[270] UI audit`.

## Polls reveal ground game (v0.8.0)

`DESIGN.md` D-049. A paid internal poll now also shows the opponent's ground game in the polled states, and a ground-game unit costs $2.5 (was $2). Two-player test (**Test → Clients and Servers, 2 players**); do step 4 on the iPad or a phone too.

1. **The poll says what it is for.** On client 1, tap a state, then hover or read the preview under **Poll** and **Region poll**.
   - Poll: "next week you see their hidden ground game here (it counts only on election night) and true support within ±1; $1.0". Region poll: "their hidden ground game and true support in all N … states, next week; $3.0".
   - The state card has a grey line "Their ground game here: hidden. A poll shows it before election night."
2. **Their units show up where you poll.** On client 2, put **3** ground-game units in Ohio (the card says $2.5 each). On client 1, **Poll** Ohio. Both lock in.
   - Next week on client 1, Ohio's card reads in red "Their ground game here: 3 units, -4.5 for you on election night (your poll, end of week N)." In the map's **Polls** lens, Ohio shows "opp G3" in their color (not on the default EV map, D-046). The week card's internal-poll line ends "OH … (their ground game 3)".
   - Client 2 sees nothing about client 1's poll, and its own Ohio card still says their (client 1's) ground game is hidden.
3. **The reading stays, and ages.** Do not poll Ohio again for two weeks.
   - The card keeps the reading and adds "they may have added more since". Poll Ohio again after client 2 adds a unit: the card now says 4 units and the new week.
4. **A poll that sees none says so.** Poll a state where client 2 has no units: "Their ground game here: none when you polled (end of week N)." No map tag.
5. **Election night credits it.** Finish the match. On Results, "What decided it" has a line "Your polls found their ground game in OH (3 units; you had …, won it / lost it)."
6. **Help.** Tap **?** → Ground game and Polls: both say an internal poll is the only way to see their ground game before election night, and Ground game explains the "opp G3" tag.
7. **F2 / duel.** The F2 board shows "Your internal polls: OH … their gotv 3" and "Their gotv your polls saw: OH 3 (wk N)". `show OH` ends with the same "Their ground game here" line.

**Send back:** a screenshot of step 2 (card and map tag) on 16:9 and on the iPad, the Results line from step 5, and whether you changed a plan because of a reading (and which).

## Screens for stances and debates (v0.6.0)

The screens for D-039 to D-041 (`DESIGN.md` D-042). **Play vs Bot** is enough; do each step once on 16:9 (Studio window) and once on a phone (**Test → Device → an iPhone**, portrait, then landscape).

1. **A Choice week previews the stance on the map.** Play until the event card reads "Event · Choice · …" (it sits first in the side column).
   - Three full-width chips: "A · …", "B · …", "C · … (hedge, default)". C has the outline; nothing is gold except Lock in.
   - Above them, "States you need (within 5 points …): you trail … · you lead … You project N EV; 270 wins."
   - The map shows stance C: some states glow in your color with "+0.5" badges, the rest are faded. The line over the map starts "Map: stance C".
2. Tap **A**.
   - A's chip gets the outline. States that gain glow in your color with "+1.5" / "+0.5" badges, states that lose show red "-0.5" / "-1.5" badges. Any state marked **FLIP** would change poll leader.
   - The summary under the chips reads "Stance A · …: +X in N states (K you need: …) · -Y in M states (L you lead: …) · could flip … / no poll leader would change". Check two badges against the "Every state, stance by stance" lists below it.
3. **Hold** B (press and keep the finger or mouse down).
   - The map and the summary show B while you hold; let go and they go back to A. A stays selected.
4. Tap the event card's title row to collapse it.
   - The map goes back to the current lens (EV by default). Expand it again: the preview is back.
5. Lock in with A. Watch the week's results.
   - Once the stance lines are read out ("…: You took stance A · …"), the panel adds "You took A · …: +X in N states, -Y in M states." and "They took …", then either "On the polls you both saw, the stances flipped: …" (with a big callout line) or "…flipped no state". The map badges the states toward you (your color) or them (their color).
   - Next week's week card says the same under "Last week's event".
6. **The debate (week 4, and week 9).** Put 4/2/0 prep in week 3 so a gaffe is possible.
   - Each topic row adds "Your … win swung XX, YY, ZZ (+1.0 each)" or "Their …" or "… was a tie"; when a state changed leader the line is **bigger and bold** and ends "- PA flipped to you (+19 EV)". A gaffe adds a red line "Your gaffe on …: -0.6 in …".
   - As each topic lands, the map badges its states and marks FLIP where the leader changed.
   - After the last topic: "Every state also got: you +0.1 · them +0.1." and, if any, "And from the points every state got: …".
7. **Results.** Finish the match.
   - A "What decided it" panel: "Debates: … flipped to you (+N EV) · … to them (N EV) · kept on election night: …", the same for "Choice stances", and "Final gap: …".
8. **Help.** Tap **?** → Events and Debates.
   - Events says every other state hears a stance through its own top issues and explains the map preview (badges, red, FLIP, states within 5 points). Debates says a topic win adds +0.1 in every state and that the debate screen names the states it swung.
9. **Phone portrait and landscape.** Repeat steps 1, 2 and 6 on the iPhone.
   - The chips are full width and readable; nothing is cut off; Lock in stays on screen; the map badges are legible on the big states.
10. **F2.** In a Choice week press F2: the board has "States you need …" and three "Stance A/B/C · …" lines matching the event card.

**Send back:** screenshots of steps 2 and 6 on 16:9 and on the phone, one stance summary next to the week's actual poll changes (did the named states move that way?), the Results panel, and the Output lines starting with `[270] UI audit`.

## Issue-based choices and debates (unreleased)

Rules only (`DESIGN.md` D-039 to D-041). The screens for them are the section above (v0.6.0): the stance chips now carry names, and the lines quoted below are still in "Every state, stance by stance" and on the F2 board. Two-player test (**Test → Clients and Servers, 2 players**), or **Play vs Bot** where a step says so.

1. **A Choice week is a stance on an issue.** Reach a Choice week (the event card names a dispute, e.g. "Plant at a crossroads", and its issue). Open the card.
   - Three lines, one per stance, list every state the stance moves and by how much, e.g. "A · Stand with the plant: +1.5 in GA, IN, MI … · +0.5 in … · -0.5 in … · -1.5 in AL, KY, PA …". The ±1.5 states have that issue as a top issue; the ±0.5 ones hear it through their own issues; C (the hedge) lists only the issue's states, all at +0.5. If the issue is on your platform, the issue's states read ×1.5 (up to 2.0).
   - Pick **A** on one client and **B** on the other, lock in, and read the reveal and the next week card: "You took stance A, they took stance B: N states moved, +x / +y points in all". The F2 board prints the same.
   - Next week the public polls in the listed states have moved the way the lines said (minus that week's rallies and ads).
2. **The hedge is the default.** In a Choice week lock in without touching the stance buttons on one client.
   - The reveal shows that client took **C**, and only the issue's states moved, each by +0.5.
3. **The same event reacts the same way.** Start a second match, pick the same platform, and wait for the same Choice event (or compare with a teammate's match).
   - The three stance lines list the same states with the same numbers.
4. **Debates move the states they are about.** Pick any two candidates. In week 3 put **4/2/0** on one side and 2/2/2 on the other. Watch the week-4 debate reveal and then the map.
   - Each topic won reads as a list of states (the states that have that topic as a top issue) moved by **+1.0** for the winner; a gaffe (0 prep, lost) reads **-0.6** in the same states; everything else moves 0.1 per topic won. The F2 board prints `debate: <who> won <topic>` and one line per state that **flipped** in the polls ("PA flips to YOU in the polls after the debate (19 EV)").
   - The public polls on the map have already moved when the week-4 plan opens (the debate republishes them), and the projected EV with them.
5. **Prep still wins topics.** Across a few matches, the 4-vs-2 topic goes to the 4 about 8 times in 10 and the 0-vs-4 topic always goes to the 4.
6. **Nothing to guess.** There is no Attack / Defend / Ignore and no payoff table anywhere (event card, "How it works", F2 `rules`).

**Send back:** the stance lines for two different Choice events, the reveal line after step 1, a screenshot of the map before and after a debate (step 4), and whether the moved states matched the lines.

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

## Decision screens: debate focus and stances (D-044, v0.8.0)

Playtest 3 asked for debates and event choices "on a separate screen before the week decisions with a separate timer". **Play vs Bot** is enough for steps 1 to 6; step 7 needs **Test → Clients and Servers, 2 players**. Do steps 1 to 4 once on 16:9 and once on an iPad or phone (**Test → Device**).

1. **A Choice week opens on its own screen.** Play until a week with a Choice event (weeks 2 to 11).
   - Before the plan, a new screen: the header says "Week N of 12 · Take a stance" with its own countdown (20 s), the map, the event card with the three stance chips (C outlined), "States you need", the stance summary, and Lock in. No state card, no plan list, no week card, no Bank button, no money or AP in the header.
   - Tap A, B, C: the map previews each (badges, red losses, FLIP). Hold a chip to peek.
   - Lock in. Then the plan screen opens with the normal 50 s timer; the event card says "Your stance: A · …. Secret until the week resolves." and has no stance chips.
2. **Let the stance timer run out.** In another Choice week, touch nothing on the stance screen.
   - At 0:00 the plan screen opens; the event card says "Your stance: C · …". The week's reveal says you took C.
3. **The debate focus (week 4, and week 9).** At the start of week 4 a screen says "Debate focus" with a 20 s countdown and three big topic buttons, e.g. "Jobs (your platform) · 11 states, 142 EV". Under each: "You need N of them (X EV): trail OH by 2 · …", "Focus here: 4 vs their 2, plus a roll 0 to 3 each. You win 81% (38% if they focus here too).", "A win: +1.0 in each; could flip PA (+19 EV)."
   - Lock in is greyed and says "Pick a topic" until you tap one. Tap a topic: it gets the outline, the map badges its states "+1.0" (FLIP where a win would change the poll leader). Hold another topic to peek at it.
   - Lock in → the debate plays right away (10 s), then the week's plan (or the stance screen first, if this week also has a Choice event).
   - In the debate reveal and the week card, each topic's score reads e.g. "you 2 focus + 2 platform + 1 stat + roll 3 = 8 · them 1 stat + roll 2 = 3".
4. **Let the focus timer run out** (week 9, touch nothing). The debate runs with no focus for you; every topic you lost shows a red gaffe line ("Your gaffe on …: -0.6 in …").
5. **Hale.** Play as Marcus Hale: the focus lines say +3 instead of +2 ("Focus here: 6 vs …").
6. **Help and F2.** Tap **?** → Debates: it explains the focus (+2, one topic, the screen lists states and EV) and the gaffe with no focus. Press F2 on the focus screen: the board lists each topic's three lines; typing `focus jobs` (a topic of this debate) locks it in; on a stance screen `choice b` does.
7. **Two players.** Both reach the focus screen together. Lock in on one client: the other client's screen says "Opponent: locked in" and nothing about which topic. When both have locked in, the debate starts at once (no waiting for the timer). The same for a stance screen.

**Send back:** screenshots of the stance screen and the focus screen on 16:9 and on the iPad/phone, the plan screen's "Your stance" line, a debate reveal after a focus, how long the decision screens felt (is 20 s enough? too much?), and the Output lines starting with `[270] UI audit Decision`.

## A shorter draft (D-045, v0.8.0)

Strongholds are no longer drafted: each player gets their five strongest-leaning states at the map reveal, then the draft is three blind rounds (home, then two battleground nominations). Test in Studio with **Practice** (or two players via Test → Clients and Servers), once on a phone in portrait and once at 16:9.

1. Start a match and lock in Select. On the map reveal, look at the panel.
   - Should: "Your strongholds: … · theirs: …" lists five states each; those states have a ring in that player's color on the map and lean toward that player ("+5 you", "+6 them"). The "how it works" lines say strongholds come from the map and there are 3 blind rounds.
2. Home round ("Round 1 of 3 · Home state"): tap one of your own strongholds, then one of theirs.
   - Should: neither can be picked; the bar says "XX: a stronghold, can't be a home". Pick any other state and lock in.
3. Rounds 2 and 3 ("Nominate"): nominate one of the opponent's strongholds.
   - Should: allowed. After the draft the draft board lists it under "nominated by …", and in week 1 its state card says "Battleground" and "Was their stronghold".
4. Time the draft from the end of Select to the week-1 plan screen.
   - Should: about 70 seconds at most (5 s map reveal + 3 × 22 s), against about 3 minutes before.
5. Play two or three matches and note which home you picked and why, and whether your opponent picked the same one.

**Send back:** a screenshot of the map reveal (step 1) on the phone and at 16:9, the draft time from step 4, and your notes from step 5 (is there still one obvious home?). Plus the Output lines starting with `[270] UI audit Draft` (should say `0 problem(s)`).

## UI style v2 foundation (v0.9.0)

Agents: `lune run tests/ui/snap.luau` and look at `build/snaps/`; `lune run tests KitStyle` and `lune run tests Style`.

In Studio (one player is enough; Practice):

1. On Select, pick a candidate and press Next, pick 3 issues, then tap a 4th. **Expect:** the line above the button says "You already have 3; tap one to swap it" in **orange** (it was yellow). Send back a screenshot.
2. Play to Results and look at "What decided it", then tap it. **Expect:** the title ends in "−" while open and "+" once closed, never a short dash. Send back a screenshot of the open state.
3. Play to the first debate focus screen and wait out the timer without picking. **Expect:** the orange "No focus in time" line, Lock in still says "Pick a topic". Check the Output for lines starting `[270] UI audit`: lines with "pending" are expected; send back any line starting with `WARN`.
4. Optional: on the iPad, repeat 1. **Expect:** the same orange; the text is readable.

## UI style v2: Lobby, Select, map reveal and draft (v0.9.0)

Agents: `lune run tests/ui/snap.luau -- 0` (shots 01 to 06b) and look at `build/snaps/`; `lune run tests Lobby`, `lune run tests Select`, `lune run tests Draft`, `lune run tests Words.Setup`.

In Studio (one player is enough; do 1 to 6 on the Mac, then 1, 3 and 6 again on the iPad):

1. Open the game. **Expect:** "270", "Win the race to 270 votes.", a pink Play vs Bot, then Find match and Play a friend side by side, then "How to play". Tap How to play. **Expect:** the help opens. Close it.
2. Tap Play a friend. **Expect:** a sheet with "Make a code" and a code box + Join. Tap Make a code. **Expect:** the sheet closes, a big code shows with "Waiting for your friend…" under it and a red Cancel. Cancel. Send back a screenshot of the code screen.
3. Play vs Bot. On Select **expect:** a pink-outlined tip ("Each candidate has one strength and one weakness"), eight cards, none cut off, each with a green "+" line and a red "−" line; the bot's candidate is dimmed with "Taken". Tap a card. **Expect:** the tip goes away, the card gets a pink outline, "About <name>" appears under the cards; tap it. **Expect:** a sheet with the strength, weakness, actions per week, starting money and income. Send back a screenshot of step 1 (with the sheet closed).
4. Press Next: issues. **Expect:** chips like "Jobs" over "154 votes · +41% boost" (two lines on the iPad in portrait), the line under the header counting down ("Pick 3 issues", "Pick 2 more issues", … "All set? Lock in"). Tap "How issues work". **Expect:** four short sentences about votes and boost. Pick 3 and Lock in. **Expect:** the line says "Waiting for <bot's first name>…".
5. Map reveal (5 s). **Expect:** title "The map", a "Strongholds" card with your dot + "You" + five states and the bot's name + five states, "Round 1: ties go to …", and the legend ("Leans to you", "Leans to <name>"). Nothing to read beyond that; "How the draft works" opens the rules.
6. Draft round. **Expect:** "Round 1 of 3" (on wide screens "Home state" next to it), a tip "Tap a state to claim it…", a "Home state" pill with "Ties go to …", the 1st / 2nd boxes, 8 states with "N votes" and a colored lean pill, "Show all states". Tap a state. **Expect:** the tip goes away, the line says "Add a backup, or Lock in". Tap Show all states. **Expect:** every state, the ones you can't pick faded. Lock in. Send back a screenshot of the round and of the reveal ("You got …", "<name> got …").
7. Check the Output for lines starting `[270] UI audit`: send back any line starting with `WARN`.

## UI style v2: reveals, election night, results, help (WP-C, v0.9.0)

Agents: `lune run tests/ui/snap.luau -- <16..27>` and look at `build/snaps/`; `lune run tests Words`, `lune run tests Help`, `lune run tests Election`, `lune run tests Results`, `lune run tests Stances`.

In Studio, Practice, once at 16:9 and once on the iPad (or a phone in portrait):

1. **Week results.** Plan week 1 with two rallies in the same state, lock in, and watch the reveal. **Expect:** "Your week" with one line "Rally in <state> ×2 · <issue>", then "<Rex>'s week". When the new polls arrive, "What changed" lists any state that changed leader in green (to you) or red (to Rex), plus up to 3 tags like "TX +2.0 for you"; the map badges only those states. The first time, a tip says "Both plans are out! Marked states moved the most." Send back a screenshot.
2. **A Choice week.** After a stance week, the reveal shows "<event>: stance A · …" in each group, and "Why? +" opens the stance numbers.
3. **Debate (week 4).** **Expect:** a scoreboard, one row per topic ("Safety  2 – 1  You win") with one short line under it, then "You won 2 of 3 topics!" (or Rex's), and "Every state also got …". "Why? +" shows the score breakdown. The map has at most about 8 badges. Send back a screenshot.
4. **Election night.** **Expect:** the spotlight card says "Just called · <state> · N votes · Called for <name> by X points" in the winner's color, and "Too close to call … Counting the last votes" (outlined) before a close state. On the iPad/phone the names at the top are first names, never cut off. A tip "States are called one by one. First to 270 wins!" sits above the calls once.
5. **Results.** **Expect:** "You won"/"You lost", "280 votes to 258", the bar, two cards, "Why you won" with 3 bullets. "Full breakdown →" opens a sheet with what decided it, the closest states and the debates; × closes it. Play again is the only pink button.
6. **How to play.** Tap **?** during the plan, a stance, and election night. **Expect:** a sheet opens on "Your turn", "Events" and "How to win" respectively, with the countdown at the top right; each tab shows a small picture and a short paragraph; "All the numbers +" shows the full rules. × or tapping outside closes it.
7. Output: send back any line starting with `WARN [270] UI audit` (Election and Results should say `0 problem(s)`).

**Send back:** screenshots of steps 1, 3, 4, 5 and 6 on both devices, and whether the reveal makes it obvious why a state changed hands.

## UI style v2: campaign, decisions and the map (v0.9.0)

Agents: `lune run tests/ui/snap.luau -- campaign`, `-- decision`, `-- lens` and look at `build/snaps/`; `lune run tests Campaign`, `lune run tests Decision`, `lune run tests Lens`.

In Studio, Practice, once on the iPad (or Device emulation at 1024x768) and once on a phone size (390x844):

1. Reach the week-1 plan screen. **Expect:** no state card yet; under the header a line "Tap a state on the map" with "3 actions left · $…" at its right; a coach tip "Tap a state to see how it's leaning…". The Lock in button says "Skip this week".
2. Tap a state. **Expect:** a short card under (phone) or beside (iPad) the map: name and votes, at most three pills, one poll bar, then big Rally / Fundraise / Ad buttons (iPad: also Attack ad, Poll, Ground game) each saying what it does ("+4.1 support", "fly $2.0"). On the phone the three buttons are visible without scrolling. The now line says "Pick an action in …".
3. Tap Rally twice and Fundraise once. **Expect:** the line counts down ("1 action left", then "All set? Press Lock in"); the action bar says "Plan: Rally OH · …"; Lock in says "Lock in". Tap the state again: the card closes.
4. Tap "More actions", then "Details". **Expect:** Region poll and Pivot (phone: also Attack ad, Poll, Ground game) appear; Details shows the poll numbers, momentum, ground game and one long line per action.
5. Tap each lens chip (Votes, Issues, Polls, Money), then "Map key". **Expect:** one short mark inside each circle, nothing sticking out, and the Northeast column (VT to DC) with no circle or label touching another; the key sheet explains the lens in plain sentences.
6. Play to a Choice week. **Expect:** the stance screen's header names the event, the three stances each say "+N states · −N states", the hedge says "(safe)", "Why?" opens the rest. On the phone all three stances are visible without scrolling.
7. Play to a debate focus. **Expect:** "Week N · Debate prep"; three topics with "You win …%" (and "Your issue" on yours); tapping one previews its states on the map with at most a handful of badges.
8. Watch a resolve and a debate reveal. **Expect:** the header's line shows the latest result; the map labels only flips and the biggest moves.

**Send back:** screenshots of steps 2, 4, 5 (Polls lens) and 6 on the iPad and on the phone, anything clipped or overlapping, and any Output line starting with `[270] UI audit` that says `WARN`.

## UI overhaul: the whole flow (v0.9.0, D-051, D-052)

Agents: `lune run tests/ui/snap.luau` (every shot at 390x844, 1024x768, 1280x720) and read `build/snaps/`; `build/snaps/audit.txt` should list 0 findings for every shot.

In Studio, one Practice match from the lobby to the results, once on the Mac at 16:9 and once on the iPad. Then the three package checklists above for detail.

1. **The pink primary.** On every screen the one filled button (Play vs Bot, Next, Lock in, Skip, Play again) is pink with dark text, and so are the selection outlines, the timer and the coach-tip outlines. **Expect:** nothing else is pink; if you drew Amber, your name, votes and states are orange-gold and never look like a button. Send back one screenshot where you are Amber.
2. **The map reveal on the Mac.** **Expect:** the Strongholds card on the right, the legend note under the map, and no "home — · battlegrounds —" lines under it until the first draft round.
3. **A week's results.** **Expect:** the line under the header reads like "You: Rally in Texas" on one line, even on the iPad in portrait.
4. **A Windfall, Spotlight or Regional week.** **Expect:** the event says "20% more" / "50% more", never "×1.2".
5. **The first debate.** **Expect:** states that change leader say just "FLIP" on the map, and the map has no wide "+1.0 FLIP" tags covering their neighbours. Send back a screenshot.
6. **Results.** **Expect:** each card shows "280 votes" and "20 states" on separate lines. "Full breakdown →" says votes, never "EV". Open **?** → Actions → All the numbers: **expect** "3 actions (unused actions are lost)", never "AP".
7. Output: send back any line starting with `WARN [270] UI audit`.

**Send back:** screenshots of steps 1, 5 and 6 on both devices, and anything that is cut off, overlapping or hard to read.

## Polish foundation: press, sound, timer, lock-in, reduced motion (unreleased, D-053)

Agents: `lune run tests Motion`, `lune run tests Audio`, `lune run tests "Reduced motion"`, then `lune run tests/ui/snap.luau` (0 audit findings in every shot).

In Studio, a Practice match on the Mac, then the same on the iPad. Turn the volume up.

1. **Fonts.** **Expect:** body text in Builder Sans (rounder than before), and the big numbers, "Lock in" and "Week 3" style titles in Fredoka One (round and chunky). Send back a screenshot of the Campaign top bar and of the action bar. If Fredoka's digits look odd at 28 or 48 px, say so (the swap is one line).
2. **Any button.** Press and hold Play vs Bot, then let go. **Expect:** it shrinks a little while held, springs back, and clicks softly. Tap a lens chip (Votes, Issues…): **expect** a brighter click and the pink outline drawing in.
3. **Cards and buttons.** **Expect:** cards and grey buttons have a faint lighter top and a thin outline; the pink primary has a darker pink edge. Nothing should look blurry or banded.
4. **The sound button.** On any screen with a header, tap **♪** (left of **?**). **Expect:** a slash over it and silence everywhere (buttons, ticks, lock-in); tap again, it clicks and sounds return. Tell us if the ♪ shows as a box. On a phone-width screen it hides when the title needs the room (stance weeks, debate prep, election night); that is expected.
5. **Timer urgency.** Let a Plan week run down without locking in. **Expect:** the timer turns orange at 0:09, red at 0:04, and from 0:04 the number pops with a tick each second (4 ticks). The bar under the header stays pink until 0:04, then turns red.
6. **Lock-in flash.** Plan an action and press **Lock in**. **Expect:** the button flashes light for a moment, settles grey reading "Locked in", and you hear a short chime (cut short, not a long ring). Next week the button is pink again at once.
7. **Screen changes.** Go Lobby → Select → Draft. **Expect:** each new screen fades in and slides up a few pixels; you can tap it straight away.
8. **Reduce motion.** Roblox menu (Esc) → Settings → **Reduce Motion** on, then repeat 2, 5 and 7. **Expect:** no shrinking, no pops, screens appear with only a quick fade; numbers, colors and sounds still change. Turn it off again.
9. **Big window.** On the Mac make the Studio window as large as it goes (or use an iPad Pro). **Expect:** everything scales up evenly and still fills the screen exactly, no gap at the right or bottom. Send back a screenshot (this checks where Roblox's UIScale grows from).
10. **Sound IDs.** All 11 asset ids load in the published place (checked Oct 23). Listen once on a **non-owner** account in the published game: tap, the select click, the lock-in chime and the timer ticks. Tell us any that are silent, harsh or too loud. (The other cues arrive with the reveal, election and results packages.) Optional: run the Audio Discovery plugin on the place and send its list.
11. Output: send back any line starting with `WARN [270] audio` or `WARN [270] UI audit`.

**Send back:** screenshots from 1 and 9, which sounds you heard in 10, and anything that felt slow or got in the way of a tap.

**Icon images.** Twelve Lucide icons, 256x256, white on transparent, are in `assets/icons/`, uploaded; their ids are in `assets/icons/README.md`.

## Polish WP-1: board and map (unreleased, D-053)

Agents: `lune run tests "board motion"`, `lune run tests "Lens motion"`, `lune run tests "Decision motion"`, then `lune run tests/ui/snap.luau -- campaign` and `-- decision` at all three sizes (0 audit findings; `10a-campaign-planned` shows the badges, `10b-campaign-map-key` the color steps).

In Studio, a Practice match on the Mac, then the same on the iPad, sound on.

1. **Map colors.** **Expect:** states are grey (toss-up) or one of three strengths of a player's color, not a smooth blend; each circle is a touch lighter at the top, and the border lines between states are fainter than before. Tap **Map key**: four rows (Toss-up, Leans, Likely, Safe) with your dot and your opponent's dot. Send a screenshot of the map and of the key.
2. **Tap Ohio.** **Expect:** a soft click, Ohio's pink ring draws in quickly, the Ohio card fades in and its action buttons pop in one after another. Each action button starts with a small pink icon (a megaphone for Rally, coins for Fundraise) before its word.
3. **Hold Rally** (press and keep your finger down). **Expect:** a see-through tag over Ohio on the map saying what the rally would do ("+4.1"); it goes when you let go.
4. **Add Rally.** **Expect:** the button pops, a pop sound, a small icon badge appears at Ohio's top-right on the map, the plan row slides in, and the money at the top right counts down with a small "-$2.0" that rises and fades.
5. **Remove it** (× on the plan row). **Expect:** the row fades out, a soft "delete" sound, and Ohio's badge fades away.
6. **Switch lenses** (Votes → Polls → Money). **Expect:** the little numbers inside the circles fade in; the circles themselves never move.
7. **Over budget.** Add actions until **Lock in** turns grey and says what is wrong ("Not enough money"), then tap it. **Expect:** the action bar shakes and you hear a short "bonk"; nothing is sent.
8. **Opponent line.** **Expect:** at the bottom right "Rex: thinking" with dots that step along; when the bot locks in it rises and pops into "Rex: locked in ✓".
9. **Score.** Lock in and watch the week's results. **Expect:** when the projected votes change, the numbers at the top count to their new value and the bars slide, with a small "+12" chip rising from each name that changed.
10. **Decisions.** On a stance week (or debate prep) **expect** the three stances (or the topics) to pop in one after another.
11. **Reduce Motion on** (Esc → Settings), repeat 2, 4, 6 and 8. **Expect:** no pops, rings drawing or sliding, no rising chips, the dots stay "thinking..."; badges, numbers and sounds still appear at once.

**Send back:** the screenshots from 1, whether the map's four steps read at a glance on the iPad, and anything that felt slow or got in the way of a tap.

## Polish WP-2: reveals, election night, results (unreleased, D-053)

Agents: `lune run tests Reveal`, `lune run tests Election`, `lune run tests Results`, then `lune run tests/ui/snap.luau -- resolve` (and `-- debate`, `-- election`, `-- results`) at `--size phone`, `ipad` and `desktop`: 0 audit findings; look at `16a-resolve-beat`, `22a-election-tipping` and `23a-results-loss`.

In Studio, a Practice match (Autoplay off) on the Mac, then the same on the iPad. Sound on.

1. **Both plans are in.** Lock in a plan in week 1. **Expect:** a whoosh, then "Both plans are in" in pink at the top of the side panel for half a second, with one line under it: who goes first and why ("Rex trails, so Rex's actions land first", or "Your actions land first" when it's even).
2. **Actions land.** **Expect:** the actions come in one or two at a time, the trailing player's first. Each time, the state on the map bumps and sends out a ring in that player's color, with a soft pop (yours a little higher than theirs).
3. **New polls.** At the end of the week's reveal, **expect** every state that changed leader to ring in its new leader's color with one stinger, and the "What changed" rows to slide in one after another. The vote counts in the top bar count up to their new values.
4. **Skip** still works at any point and jumps straight to the end of the reveal.
5. **Debate.** In a debate week, **expect** each topic row to fade in with its verdict pill popping; a topic you win plays a bright hit, a tie or a loss a soft click. The headline pops in after the last topic.
6. **Election night pacing.** Watch without skipping. **Expect:** safe states go quickly (about one every 0.6 s, done by about 0:18 on the "Results in" clock), then the last 8 and the state that takes someone to 270 slow down: the call holds for a moment, then the spotlight says "Too close to call" (or "Still counting") and names the next state before it is called.
7. **Each call.** **Expect:** the state's circle fills with the winner's color and rings, the spotlight bumps, the vote numbers count up and the bar grows, and a ding plays that gets higher as the leader nears 270. The state in the spotlight is not also at the top of the list underneath; it joins the list when the next call (or the suspense) replaces it.
8. **270.** On the call that takes someone to 270, **expect** the spotlight to say "Dana reaches 270!", the 270 tick and "270 to win" to flash pink twice, and a stinger. "Results in" no longer turns red or ticks in its last 5 seconds.
9. **The end.** When every state is called, **expect** the banner in place of the counters, the spotlight gone and the list (all 51 calls) filling the side.
10. **Results, win.** **Expect:** "You won" pops in, both vote totals count up from 0, confetti in both players' colors falls once, and the victory stinger plays once. On the other player's screen (the loss): "You lost" fades in, no confetti, the defeat sound, and one pink line under the reasons: "Try next time: …".
11. **Reduce motion** on (Esc → Settings), replay a week and an election night. **Expect:** no bumps, rings, pops or confetti; every line, number and color still arrives, and the sounds still play.
12. **Sounds on a non-owner account** in the published game: whoosh, the landing pop, the flip stinger, the debate hit, the call ding, victory and defeat. Tell us any that are silent, harsh or too loud.

**Send back:** a screenshot of step 1 and of step 8 on the iPad, whether the election felt too fast or too slow (and where), and which sounds in 12 you heard.

## Polish: setup, help, settings and icons (unreleased, WP-3)

Agents: `lune run tests Lobby`, `lune run tests Select`, `lune run tests Draft`, `lune run tests Help`, `lune run tests CoachTip`, `lune run tests Icons`, then `lune run tests/ui/snap.luau -- lobby`, `-- select`, `-- draft`, `-- help` (0 audit findings in every shot at all three sizes).

**Icons.** The twelve PNGs in `assets/icons/` are uploaded; `assets/icons/README.md` lists each image id by name, and `src/client/UI/Icons.luau` holds them.

In Studio, a Practice match on the Mac, then the Lobby, Select and Draft again on the iPad. Volume up.

1. **Lobby arrival.** Open the game. **Expect:** the big "270" pops in, then the lines and buttons fade in top to bottom, quickly; you can press Play vs Bot straight away.
2. **Settings chips.** Under How to play: **Sound** (outlined) and **Reduce motion**. Tap Sound. **Expect:** its outline goes, the icon turns grey (with a slash or the "off" speaker), and buttons go silent; the ♪ in any header shows muted too. Tap it again: a click, sound is back. Tap Reduce motion. **Expect:** it gets the outline and presses and pops stop (screens only fade). Tap it again.
3. **Help settings.** In a match tap **?** → How to win. **Expect:** "Settings" with the same two chips at the top, in sync with the Lobby and the ♪ button. Then Actions and Polls: **expect** an icon beside each action name.
4. **Select.** **Expect:** the eight candidate cards pop in one after another; tapping one pops it and outlines it with a click. After Next, the issue cards pop in the same way, and the issues tip appears with a soft pip. The candidate tip that greets you is silent.
5. **Draft.** Tap a state in the list or on the map. **Expect:** it pops into the 1st slot, the state bumps on the map, and a soft pop plays; tapping it again takes it back with a lower sound. Tap a state you can't pick: **expect** the reason under the map shakes briefly, with a bonk. After the round, **expect** both "You got / Rex got" cards to pop in, each state rings in its player's color, and a whoosh.
6. **Toasts.** In the Lobby, Play a friend → type `AB1` → Join. **Expect:** the message box at the top appears in place, shakes, and bonks; after a few seconds it fades out. A notice (not an error) slides down a little instead.
7. **Icons.** The header ♪ button, the settings chips and the Help pictures show the drawn icons, never grey boxes, on the Mac and on the iPad.
8. **Reduce motion** (Roblox Settings or the chip). Repeat 1, 4 and 5. **Expect:** no pops, shakes or rings; everything still ends in the same place and sounds still play.

**Send back:** a screenshot of the Lobby and of **?** → How to win on the iPad, and anything that felt slow, noisy or got in the way of a tap.

## Polish: the whole flow (v0.10.0, D-053, D-054)

Agents: `lune run tests`, then `lune run tests/ui/snap.luau` (every shot at 390x844, 1024x768, 1280x720) and read `build/snaps/`; `build/snaps/audit.txt` lists 0 findings for every shot.

In Studio, one Practice match from the lobby to the results with sound on, once on the Mac and once on the iPad. Then the four polish checklists above for detail.

1. **Icons, not boxes.** **Expect:** the ♪ button, the Lobby's Sound and Reduce motion chips, every action button on a state card, the badges on planned states and **?** → Actions show drawn white or pink icons. A grey box or a missing picture anywhere: send a screenshot and say where.
2. **Plan badges on a small state.** On the iPad (and a phone if you have one), plan an action in a small state (Ohio, New Jersey). **Expect:** the badge sits on the circle's top-right rim and the state's letters stay readable.
3. **One bonk.** In a match, add actions until Lock in turns grey, then tap it: one bonk, the bar shakes. (A plan the server refuses shows a red message at the top and shakes the bar, still with one bonk.)
4. **The full arc.** Lobby fades in → Select cards pop → draft picks pop and ring → weeks: tap, add, lock in, "Both plans are in", the actions land, the polls flip → election night speeds up, slows for the last states, flashes 270 → Results: confetti and the stinger on a win; on a loss a quiet sound and a "Try next time" line. **Expect:** no sound plays twice on top of itself and nothing waits on an animation before you can tap.
5. **Reduce motion** (the Lobby chip): repeat 4 quickly. **Expect:** no pops, rings, shakes or confetti; every number, badge and sound still arrives.
6. Output: send back any line starting with `WARN [270] audio` or `WARN [270] UI audit`.

**Send back:** the screenshots from 1 and 2, anything that sounded harsh or too loud, and whether a full match still fits in about 15 minutes.

## Colors: red, blue and the Color Pass (v0.11.0, D-055)

Agents: `lune run tests "color pass"` (the Match, Profile and server/client specs), `lune run tests/ui/snap.luau -- color` (shots `01b`, `02c`, `02d`; 0 audit findings at all three sizes).

### Setting up the Color Pass (once, for the humans)

The color option stays hidden until this is done; until then every match is red and blue.

1. Go to the [Creator Dashboard](https://create.roblox.com/dashboard/creations) and open the experience of place **133510178057620**.
2. **Monetization → Passes → Create pass.** Name: **Pick Your Color**. Description, for example: "Choose your color: Crimson, Cobalt, Emerald, Amber, Violet or Teal. Yours every match." Upload a square icon (up to 512x512, keep it inside the circle). **Create pass.**
3. Open the new pass, put it **on sale** (in its sales settings) and set a price in Robux. **Save.**
4. Back on **Passes**: hover the pass, click **⋯ → Copy Asset ID**. Send that number to Claude. (Or put it yourself in `src/shared/Net/Products.luau`, line 17: `Products.COLOR_PASS_ID = <the number>`.)
5. After the new build is published (File → Publish to Roblox), the Lobby shows **Color**.

### In Studio (after the pass id is in the build)

Studio purchase prompts are **test purchases**: the prompt says so and nothing is charged. A test purchase counts for that Studio session only; your real account does not get the pass. DataStores need **Game Settings → Security → Enable Studio Access to API Services** to remember your color between sessions (otherwise it lasts the session).

1. **Play (F5)** alone. **Expect:** in the Lobby, under Sound and Reduce motion, a full-width **Color: red or blue** button.
2. Tap **Color**. **Expect:** a sheet "Your color": "Pick your color with the Color Pass.", six greyed swatches in rows of three (Crimson, Cobalt, Emerald / Amber, Violet, Teal), **Auto: red or blue** outlined, and **Get the Color Pass**. Tapping a greyed swatch does nothing.
3. Tap **Get the Color Pass**. **Expect:** Roblox's purchase prompt for "Pick Your Color" with its price, marked as a test purchase. Press **Cancel**: nothing changes. Tap it again and **Buy**. **Expect:** after the prompt closes, the swatches light up, the buy button goes, and the line reads "Tap a color. You get it every match."
4. Tap **Emerald**. **Expect:** Emerald gets the pink outline and the Lobby button reads **Color: Emerald** with a green dot.
5. Close the sheet, **Play vs Bot**. **Expect:** Select says "Your color: Emerald"; the bot is Crimson or Cobalt. Your states on the map are green.
6. Back in the Lobby, **Color → Auto: red or blue**, then **Play vs Bot** again. **Expect:** you are Crimson or Cobalt, the bot the other.
7. **Two players without the pass** (Test → Clients and Servers → Local Server, 2 Players; or the published game with a partner), **Find match** on both, three times. **Expect:** every match, one player is Crimson and the other Cobalt, not always the same way round.
8. **Two owners, same color** (published game, both bought the pass, both picked Teal). **Expect:** one of you is Teal, the other Crimson or Cobalt; over a few matches each of you gets Teal sometimes.
9. Output: any line with `Color Pass check` (a failed ownership check) or `rejected SetColor`.

**Send back:** a screenshot of the sheet before and after buying (iPad and Mac), the Select screen from step 5, the colors from step 7's three matches, and the Output lines from step 9.

## Claiming colors (unreleased, D-061)

Agents: `lune run tests "D-061"`, `lune run tests "Select color picker"`, `lune run tests/ui/snap.luau -- select-color` (shots `03b`, `03c`, `04b`; 0 audit findings at all three sizes).

Needs the Color Pass set up (above). Two owners means the published game with a partner who also owns it (a Studio test purchase lasts that session only).

1. **Alone, as an owner** (Color: Teal saved), **Play vs Bot**. **Expect:** under "Your color: Teal" a row of six round swatches with your initials, Teal outlined in white, each with its name underneath. The bot's color is not marked Taken (it was only dealt one).
2. Tap **Emerald**. **Expect:** the outline jumps to Emerald, the line reads "Your color: Emerald", and the map uses green after Select. Pick Crimson if the bot was Crimson: the bot switches to Cobalt.
3. Go to step 2 (issues). **Expect:** the swatches are still there and still work. Lock in, then tap another color before the bot locks: it still changes.
4. **Two owners, different saved colors** (Teal and Violet), **Find match**. **Expect:** each starts with their own; each sees the other's swatch dimmed with "Taken" and the other's initials; tapping it does nothing.
5. **Two owners, the same saved color** (both Teal), three matches. **Expect:** one of you is Teal; the other sees "Your opponent took Teal first. Pick another color." and can tap any free swatch. Not always the same person.
6. **Both tap the same free color at the same moment** (count down together). **Expect:** one gets it; the other sees "Rex took Amber first…" (with the opponent's name) and picks another.
7. **Without the pass:** no swatches, only "Your color: Crimson" (or Cobalt).
8. Output: any line with `rejected ClaimColor` or an error from `Select` or `Session`.

**Send back:** screenshots of step 1 (iPad and Mac) and of step 4 from both screens, who got which color in steps 4 to 6, and any Output lines from step 8.

## Front-page foundation (unreleased, D-056)

Client only. The other front-page packages (map, panels, moments) build on this; test it on an iPad if you can.

Before testing: the two decoration images need uploading first (`assets/ui/README.md`). Without them the game still runs; there are just no shadows or glows. Test once before the upload (nothing should error) and once after.

1. **Lobby.** The background is a deep navy, not black. Press and hold **Play vs Bot**: the white button (pink before D-058) sinks onto a slate lip under it and springs back on release. The grey buttons (**Find match**, **Play a friend**) do the same on a dark lip. *Send back:* a screenshot of the Lobby, and whether the press feels chunky or mushy.
2. **Main button shine.** Wait on any screen with the white main button for about 5 seconds: a soft light band sweeps across it, then again every few seconds. With Reduce Motion on (Settings chip or Roblox setting) it never sweeps. *Send back:* too much or fine?
3. **Color sheet** (with the Color Pass set up): each swatch is a circle with your initial in that color. Amber looks gold, clearly not the orange of a loss. *Send back:* a screenshot.
4. **Hosting a private match:** **Cancel** has an orange outline and orange text.
5. **Campaign:** the bottom bar sits on its own panel with a soft shadow above it (after the upload). The header's time bar is thicker, rounded, with a glowing white tip, and turns orange in the last 5 seconds; the timer text is orange under 10 seconds. Battleground states show their vote number in a white-outlined tag with a ★ (D-058), not orange.
6. **A sheet** (Map key, a state's Details): on the iPad it scales in from slightly smaller, has rounder corners and a shadow (after the upload); on a phone it has a small handle bar at the top.
7. **Losing:** finish a match you lose. "You lost" is orange; nothing on that screen is red unless it is the other player's color. In a debate week, a topic the other player wins shows an orange "Rex wins" tag.
8. **No errors:** the Output window shows no errors from `Kit`, `Assets`, `Header`, `ActionBar` or `Sheet`, before and after the upload. *Send back:* the Output log.

## Front-page map (unreleased)

Client only. Needs the foundation's images uploaded (shadow, glow) to see the glows; without them the map still works, just flatter. Best on the iPad and on a phone.

1. **Campaign map (iPad).** Behind the map there is a soft navy glow, like a lit table. Every state looks like a chunky token: a darker edge just under it, the top a little lighter than the bottom, a faint shadow. Lines between states are fainter than before. *Send back:* a screenshot; does the map look like the hero of the screen?
2. **Battlegrounds.** In the Votes lens a battleground shows "★" before its votes, on a dark tag with a white outline. Nothing on the map is orange unless it goes against you. *Send back:* can you spot the battlegrounds at a glance?
3. **Selecting a state.** Tap Ohio: its ring turns white and a soft white glow under it slowly breathes. Tap another state: the glow moves. With Reduce Motion on, the glow stays still.
4. **Polls lens.** Each lead ("+3") sits on a tag filled in the leader's color, readable on any state; a near-tie says "tie".
5. **Phone (portrait).** No state's circle overlaps another, and every two-letter code is readable, also in the Northeast and around Ohio, Pennsylvania and Virginia. The bigger states show their votes inside. *Send back:* a phone screenshot of the Campaign map and of the Draft map.
6. **A stance week.** Pick stance A or B: states it helps get a ring and soft glow in your color with "+1.0"-style tags filled in your color; states it hurts glow orange with an orange "-0.5" tag in dark text. A state that would flip says FLIP on a dark tag with a thick edge in the new leader's color.
7. **Debate reveal.** Moved states glow toward whoever gained; flips say FLIP with an edge in the new leader's color (a grey edge for a tie).
8. **Election night.** The state being counted ("?") glows; the map otherwise fills in as before.
9. **No errors** from `NodeMap`, `Lens` or `SwingMarks` in the Output window. *Send back:* the Output log.

## White accent (unreleased, D-058)

Client only. Pink is replaced by white everywhere.

1. **Lobby.** **Play vs Bot** is a solid white button with a dark label; press and hold it: it sinks onto a slate-blue lip and springs back. Nothing on any screen is pink. *Send back:* a screenshot, and whether the white button looks like the thing to press.
2. **Selection.** In the Campaign, tap a lens chip (**Issues**), a state, an action: each selected thing gets a white outline and the others none. *Send back:* is the selection obvious at a glance on the iPad?
3. **Battlegrounds.** On the map (Votes lens) a battleground's number reads "★13" in a white-outlined tag; the state card and the Draft's battleground round show "★ Battleground", outlined, not filled. The Draft's home-state round shows a plain "Home state" tag. *Send back:* could a battleground tag be mistaken for a button?
4. **Timer.** The time bar and timer are white; the timer turns orange under 10 seconds and the bar under 5, as before.
5. **Tips and toasts.** A coach tip has a grey outline and a grey **Got it** button that still works; a notice toast has a grey outline, a rejected plan an orange one.

## Start screen: leaderboard, bot levels, How to play, leaving a match (unreleased, D-059)

Agents: `lune run tests "D-059"` (the UI flows), `lune run tests "e2e: the global leaderboard"`, `lune run tests "e2e: leaving a match"`, `lune run tests/ui/snap.luau -- lobby`, `-- howto`, `-- leave` (shots `01`, `01c` to `01f`, `02e` to `02j`, `28`, `28a`, `28b`; 0 audit findings at all three sizes).

What each bot level does is in "Bot difficulty" (D-057), below.

**The leaderboard needs saved data.** It lives in an OrderedDataStore, which only works in a published place with **Game Settings → Security → Enable Studio Access to API Services** turned on. Without it the board says **Leaderboard unavailable** (that is correct, not a bug). Only matches against another player move a rating, so to see anyone listed you need two players to finish (or leave) a match against each other.

### Start screen (alone)

1. **Play (F5)** on the iPad layout (Studio's device emulator, iPad) and on the Mac. **Expect:** under **Play vs Bot**, four chips **Easy · Medium · Hard · Extreme**, Medium outlined. On the iPad and the Mac a **Leaderboard** card sits to the right of the buttons (up to 10 rows); on a phone (emulator, iPhone) it sits under the buttons with the top 3. With nobody ranked yet it says "No ranked players yet. Play someone (not the bot) to get on the board."; with API access off, "Leaderboard unavailable".
2. Tap **Hard**, then **Play vs Bot**. **Expect:** Hard gets the outline and the match starts and the bot plays at Hard (Output ends in `bot Hard`). Leave the match (below) and check the Lobby still has **Hard** outlined.
3. Tap **How to play**. **Expect:** a sheet "How to play", page "The goal" with the race bar, a short text, "1 of 5" and **Next** (no Back on page 1). **Next** through "Each week" (three numbered steps), "Your actions" (the six actions with icons), "Debates and events" (a debate scoreboard), "Election night" (three called states). On page 5 the button reads **Got it** and closes the sheet. **Back** goes back a page. Each page fits without scrolling on the iPad.
4. Tap **See all** on the leaderboard. **Expect:** a sheet "Top 50 players" with "Ranked by rating. Only matches against players count." and your own line ("You: …").

### Leaving a match

5. **Play vs Bot**. On any match screen (Select, the draft, a stance or debate screen, the plan, election night) tap **?**. **Expect:** at the end of the How to play sheet an orange-outlined **Leave match** button. Tap it. **Expect:** "Leave this practice match?", "Practice never changes your rating.", **Leave match** (orange) and **Keep playing**.
6. **Keep playing** closes it; the match carries on. Open it again and tap **Leave match**. **Expect:** straight back to the Lobby (no Results screen). Your rating does not change.
7. **Two players** (Test → Clients and Servers → Local Server, 2 Players, or the published game with a partner): **Find match** on both. On one, **? → Leave match**. **Expect:** "Leave and forfeit?", "This counts as a loss, and your opponent wins.", **Leave and forfeit**. Tap it. **Expect:** the leaver is back in the Lobby and their rating went down; the other player gets a message "Your opponent left the match. You win by forfeit." and the Results screen says "Your opponent forfeited the match.", with their rating up by the same amount.
8. With API access on, after step 7: both players' Lobbies show them on the leaderboard (it can take up to a minute to appear for a player on another server). The leaver's row is highlighted on their own screen, "You: #2 · 984" or similar.
9. Output (server): `left match m… (forfeit)`, `match m… over: Forfeit`, and any `could not read the leaderboard` or `could not write player …'s rating` lines.

**Send back:** screenshots of the Lobby on the iPad and the Mac (with the leaderboard), one How to play page, both Leave confirmations, the winner's Results from step 7, and the Output lines from step 9.

## Bot difficulty (unreleased, D-057)

Agents: `lune run tests difficulty` (sim, net and e2e specs), `lune run tests/harness/difficulty.luau` (the win-rate table, about a minute).

### In Studio (pick the level with the chips under Play vs Bot)

1. **Play (F5)** alone. Pick **Easy**, **Play vs Bot**, and play a normal match. **Expect:** you win comfortably; the bot still takes a turn every week, raises and spends money, and its debate focus sometimes looks random. Output: `match m1 started (Practice), seed …, bot Easy`.
2. Back in the Lobby, pick **Hard**, play again. **Expect:** a closer, tougher match; the bot rallies more than it fundraises and fights you in the states you are pushing. Output ends in `bot Hard`.
3. Same with **Extreme**. **Expect:** the hardest of the four; it defends the close states it leads and goes all-in on the ones it trails when behind. Output ends in `bot Extreme`.
4. Pick **Medium** (or no pick at all). **Expect:** the same bot as before this update. Output ends in `bot Medium`.
5. **Expect, every level:** no rating change after the match (practice is unrated); your practice record goes up by one; no `rejected` lines for the bot in Output; plans resolve without a pause when the bot's turn comes.

**Send back:** for each level you played, who won and the final EV score, whether each felt easier or harder than the one before, and any Output lines with `rejected` or `failed`.

## Front-page moments (unreleased, D-056, WP-3)

Client only: the week's results, the debate, election night and Results. Shadows and glows need the uploaded images (see "Front-page foundation"). Try each step once with Reduce Motion on too: everything should still appear, just without the slam or the flash.

1. **Week results** (end any week): the panel starts with a small grey "WEEK 3 RESULTS" over "You vs Rex"; "Your week" and "Rex's week" each have a colored circle with the candidate's initials. When the new polls are in, the title changes to who flipped what ("You flipped 2 · Rex flipped 1"). Under "What changed", a state that flipped to you has a green ▲ and its line in your color; one that flipped to Rex has an orange ▼ and its line in Rex's (lighter) red. The biggest moves are filled tags: green with ▲, orange with ▼. *Send back:* a screenshot of the finished panel.
2. **Debate** (week 4 or 9): each topic's score is in the round font; the verdict tags are filled green / orange / grey. After the last topic, "You won 2 of 3 topics!" (or "Rex won …") slams in as a tilted stamp, green or orange. *Send back:* a screenshot, and whether the stamp feels like a moment or like clutter.
3. **Election night, a call:** each state turns briefly white on the map, then takes the winner's color. The spotlight card shows the winner's initials, "JUST CALLED", and a "CALLED" stamp in the winner's color on its top-right corner. On a phone the stamp stays on screen. *Send back:* a phone screenshot mid-night.
4. **Election night, suspense:** before a close call the card says "TOO CLOSE TO CALL" in orange with a "?" circle, and that state glows on the map.
5. **Election night, 270:** when someone reaches 270, the tick flashes and "270 TO WIN" blinks; about half a second later a "270!" stamp lands on the bar. That state keeps a white ring until the end. If that was the last call, the stamp gets a moment before the banner replaces the strip. *Send back:* a screenshot right after the stamp lands.
6. **Election night, the end:** the banner reads "ELECTION NIGHT" over "Dana Okafor wins 280–258", edged (and, after the upload, glowing) in the winner's color. Feed rows have a thin bar in the winner's color on their left.
7. **Results, win and loss:** "You won" is a green tilted stamp that slams in, with confetti (both colors and white); "You lost" is an orange stamp with dark text, and nothing on the screen is red except Rex's own color. Below: the race bar with "270" over its tick, then two cards with big initials; the winner's card has a colored edge. **Full breakdown:** the closest states are listed in the players' colors and easy to read. *Send back:* both screenshots on the iPad.
8. **No errors:** the Output window shows no errors from `Reveal`, `Election` or `Results`.

## Front-page panels (unreleased, WP-2)

Client only: the Lobby, Select, the Draft, the stance and debate-prep screens, the Campaign side column and Help. Agents: `lune run tests/ui/snap.luau -- lobby` (and `-- select`, `-- draft`, `-- decision`, `-- campaign`, `-- help`, `-- howto`); 0 audit findings at all three sizes. Shadows and glows need the uploaded images (see "Front-page foundation").

1. **Lobby (iPad, Mac, phone).** "A 1V1 ELECTION STRATEGY GAME" over a big outlined "270" with a soft glow; the background has a faint navy glow. Under **Play vs Bot** the four levels sit in one dark track, the picked one raised with a white outline. The leaderboard's top three have gold, silver and bronze coins; your row is raised with a white bar on its left. On the phone everything fits without scrolling. *Send back:* a screenshot on each device, and whether it looks like a Roblox front-page game.
2. **Play a friend → Make a code.** "YOUR PRIVATE MATCH", then the code big in the round font on a lit plate; **Cancel** is orange-outlined.
3. **Select.** Every candidate card has a round portrait with initials in your color (Rex Calloway's, when taken, in Rex's red). Strength green with "+", weakness orange with "−", one line each even on a phone. Under the cards, your candidate's initials in your color and "Your color: …". *Send back:* a phone screenshot.
4. **Draft.** In the list, each lean is a filled tag: "+2 you" on your color, "+2 Rex" on red; "Even" is plain. On the map, home states have an "H" tag in their owner's color; picked battlegrounds a dark tag with a white ★ outline (on the Votes lens on a wide screen the ★ is in the number instead); your 1st and 2nd picks a dark tag with a white outline. After a round, the two cards say "You got WY" / "Rex got OH" in each color with a ★ Battleground (or Home state) tag. Nothing on the Draft is filled white except Lock in.
5. **A stance week.** Each of A, B, C has a thin bar on its left; the picked one's bar turns white with the outline. "+21 states" is green, "−10 states" orange. **Debate prep:** "You win 81%" is a green tag; your pick gets the white bar.
6. **Campaign header.** "310 Dana Okafor" at the left and "Rex Calloway 189" at the right over a thick two-color bar with a white tick at 270; names are readable (lighter red and blue). On a phone only the two numbers show over the bar, on one row. When the score changes the numbers count and the bar slides.
7. **State card.** The six actions each start with their icon on a small dark circle; the poll is a small race bar with a tick in the middle. The event card shows "THIS WEEK" over "Windfall · …". The **Key** chip (magnifier) beside the lens chips opens "How to read the map".
8. **Help (?).** The five tabs sit in one dark track (two rows on a phone), the open one raised with a white outline. "How to win" shows the race bar; "Actions" shows each icon on a round plate. At the end, under a thin line, **Leave match** is orange-outlined. **How to play** (Lobby): the step numbers are round, the election-night winners are tags filled blue / red.
9. **No errors** from `Lobby`, `Leaderboard`, `Select`, `Draft`, `TopBar`, `StateCard`, `EventCard`, `Focus` or `Help` in the Output window. *Send back:* the Output log.

## The week's results, move by move (unreleased, D-063)

Client only. Agents: `lune run tests RevealSteps`, `lune run tests "running tally"`, `lune run tests/ui/snap.luau -- resolve` (shots `16b-resolve-step1`, `16c-resolve-mid`, `16d-resolve-settle`, `17-resolve-end`; 0 audit findings at all three sizes).

1. **Play vs Bot**, plan week 1 with two or three rallies, lock in. **Expect:** "Both plans are in"; the header's two numbers stay where they were during planning (they no longer jump at once).
2. **Watch the moves land.** **Expect:** each line ("Rally in Texas · Jobs") is followed at once by its state bumping, its color moving, and a "+3.1" tag (your color) or "−2.0" tag (orange) on every state the move touched. When the move changes who leads a state: FLIP, a flash in the new leader's color, and the header line says so ("Rex: Rally · NY → Rex +28") while the header's numbers count and the bar slides. "Why?" holds one line saying the per-move points are estimates.
3. **The last step.** **Expect:** the header line says "New polls are in" in the round font; a pulse sweeps the map west to east; the panel shows a "New polls are in" stamp over "Polls shifted N states"; the map and the header land on the new polls (usually a few states move without a move of their own: momentum and poll noise); "What changed" lists the week's flips. When the next week opens, the header's numbers do not change again.
4. **Skip** (both players, or against the bot). **Expect:** the reveal fast-forwards and ends on the same numbers as step 3.
5. **Phone (390x844) and iPad.** **Expect:** while the moves land, the map and the header's numbers are on screen together; the panel scrolls under the map.
6. **No errors** from `Reveal`, `RevealSteps`, `TopBar` or `Campaign` in the Output window.

**Send back:** a phone and an iPad screenshot mid-reveal, whether each move's effect was easy to follow, whether "New polls are in" read as the polls updating (not as moves being undone), whether each move was on screen long enough to see it land, and any Output errors.
