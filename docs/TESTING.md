# Studio playtest checklists

One section per feature, newest last. Each item: what to do, what should happen, what to send back. Send back the **Output** window log (right-click → Copy all) and any screenshots listed, with the commit hash or version you tested.

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

## Balance pass 1 (unreleased)

Numbers only; nothing new to click. Confirms the retuned roster loads in Roblox.

1. Open `270.rbxl` and press **Play** (F5).
   - Output shows the `[270] sim self-test:` line as in Phase 1, with no `FAILED` warning. The two EV numbers add up to 538.
2. Press **Play** a few more times. Over several runs you should see different candidates named; any of the eight may appear and win.

**Send back:** the self-test lines from three runs.
