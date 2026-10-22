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
