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
