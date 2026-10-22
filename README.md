# 270

A 12-minute, turn-based, online 1v1 strategy game on Roblox: two fictional candidates fight over the electoral map. Draft your strongholds, plan each week in secret, read noisy polls, and win 270 electoral votes on election night.

- Design and build plan: [`docs/PLAN.md`](docs/PLAN.md)
- Decisions log: [`docs/DESIGN.md`](docs/DESIGN.md)
- Playtest checklists: [`docs/TESTING.md`](docs/TESTING.md)
- Changes: [`CHANGELOG.md`](CHANGELOG.md)

## Quick start

```sh
rokit install                         # or scripts/bootstrap.sh
lune run tests
mkdir -p build && rojo build -o build/270.rbxl
```

Open `build/270.rbxl` in Roblox Studio, or run `rojo serve` and connect with the Rojo Studio plugin.
