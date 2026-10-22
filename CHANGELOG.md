# Changelog

Newest first. Each entry lists what changed, what to test (see `docs/TESTING.md`), and anything needed from the humans.

## Unreleased — Phase 1: Simulation core (in progress)

- `Sim/Rng`: seeded xoshiro128** generator with named substreams; matches reference vectors.
- `Sim/StateData`, `Sim/Issues`, `Types`: 51 states (EV sums to 538, symmetric land-border adjacency, nine regions, balanced generic issues). See `docs/DESIGN.md` D-014.
- `Sim/Config`: every tunable from `docs/PLAN.md` revision 2, with variants for the balance harness.
- `Sim/Candidates`: the eight candidates as data (revision-2 values).
- CI runs on every branch and reports every failing check, not just the first.

Nothing new to test in Studio yet; the game still only prints its version.

## 0.0.1 — Phase 0: Scaffold (Oct 22, 2026)

- Rojo project (`default.project.json`): `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayerScripts.Client`.
- Pinned toolchain in `rokit.toml` (Rojo 7.7.1, Lune 0.11.1, StyLua 2.6.0, Selene 0.31.0, luau-lsp 1.70.1); `scripts/bootstrap.sh` builds the same versions from crates.io where GitHub downloads are blocked.
- Lune test runner (`lune run tests`) with a small describe/it/expect framework; smoke tests; a purity test that keeps the simulation free of Roblox APIs, clocks and unseeded randomness.
- CI (`.github/workflows/ci.yml`): StyLua, Selene (two configs), Lune tests, luau-lsp type check, Rojo build; uploads `270.rbxl` as an artifact.
- Docs: `docs/PLAN.md` revision 2 (first-session decisions folded in), `docs/DESIGN.md` decisions log D-001 to D-013, `docs/TESTING.md`, `CLAUDE.md`.

**Test:** `docs/TESTING.md` → Phase 0.
