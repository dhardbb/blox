# Changelog

Newest first. Each entry lists what changed, what to test (see `docs/TESTING.md`), and anything needed from the humans.

## 0.2.0 — Phase 2: Server and networking (Oct 22, 2026)

Two players can now play a full match in Studio through a temporary text UI. The real screens come in Phase 3.

- `Net/Session`: one live match on the server: input timers, lock-ins, the 2 × 15 s time bank, resolve and election skips, map/draft/resolve/debate reveals, disconnect grace (30 s, twice per match), forfeit after two missed weeks, abandonment, and bot seats. It's pure (the server passes the clock in), so it's tested like the sim.
- `Net/Lobby`: public queue, private 5-character match codes, practice against the bot; at most 10 matches per server.
- `Net/Schemas`, `Net/Remotes`: every client request is size-checked and shape-checked before anything reads it. Game inputs are then checked by `Match.validate`. Rejections are logged in the server Output with a reason code and echoed to the client.
- `server/Replication`, `server/MatchService`: the two RemoteEvents, rate limiting, and the clock that drives every match. Each player only ever receives their own `View`.
- `client/App`: a debug text UI. It has buttons for Practice, Queue, Host, Auto (the bot fills in your current step from your own view), Autoplay, Pass, Bank, Skip and Help, plus a command line for typed moves (`plan rally OH Jobs; fund PA; ...`).
- Fixed: election night was skipped; a player reconnecting after the deadline lost their turn (they now get 15 s to finish it); a thrown error could wedge a match and its lobby slot forever (the match is now abandoned and freed); debug-UI autoplay could skip a step in a second match; rate-limited players no longer flood the log and Output.
- 220 specs. `Net/` and `DebugUI/` are held to the same purity rules as `Sim/`.

**Test:** `docs/TESTING.md` → Phase 2.

## 0.1.0 — Phase 1: Simulation core (Oct 22, 2026)

The whole game runs headless: two bots can play a full match, and the balance harness reports on thousands of them. There's no UI yet.

- `Sim/Rng`: seeded xoshiro128** generator with named substreams; matches reference vectors.
- `Sim/StateData`, `Sim/Issues`, `Types`: 51 states (EV sums to 538, symmetric land-border adjacency, nine regions, balanced generic issues). See `docs/DESIGN.md` D-014.
- `Sim/Config`: every tunable from `docs/PLAN.md` revision 2, with variants for the balance harness; pool capacity derived from population, capped at $12 (D-015).
- `Sim/Candidates`: the eight candidates as data (revision-2 values) and the six player colors.
- `Sim/Match`: the state machine (Select → MapReveal → 8 draft rounds → 12 weeks with debates in weeks 4 and 9 → Election → Done). Pure: each step returns a new state, and missing or invalid inputs get defaults.
- `Sim/Leans`, `Sim/Draft`: seeded, mirrored public leans; the blind ranked-top-2 draft with A B B A B A A B priority, auto-fill, bonuses, and battleground resets.
- `Sim/Plan`: plan schema and validation with reason codes (AP, money, route flights, GOTV caps, pivot, polls, debate prep). Fuzzed so it never throws.
- `Sim/Resolve`, `Sim/Support`, `Sim/Polls`: weekly resolution under the snapshot rule (D-001): rallies, pooled fundraisers, media saturation, attacks and backlash, pivots, momentum and drift, AR(1) public polls, underdog tiers with hysteresis, internal polls.
- `Sim/Debate`, `Sim/Election`: seeded topics and rolls, sweeps and gaffes; GOTV, election noise, tiebreaks, reveal order.
- `Sim/View`: the only exit for sim state. A spec walks every view of a full match for hidden fields, and checks that changing any hidden value leaves a view byte-identical.
- `Sim/Bot`: heuristic bot playing from its own View, plus six restricted styles for the dominance checks.
- `tests/harness/balance.luau`: 2,000 bot-vs-bot matches plus side checks in about 70 s; prints every PLAN.md metric against its target. First results and open balance questions are in `docs/DESIGN.md` D-017.
- 156 specs. CI runs on every branch and reports every failing check, not just the first.
- Server startup now plays one bot-vs-bot match as a self-test and prints the result.

**Test:** `docs/TESTING.md` → Phase 1.

**Needed from the humans:** answers to the balance questions in `docs/DESIGN.md` D-017 (debate strength, the blowout target).

## 0.0.1 — Phase 0: Scaffold (Oct 22, 2026)

- Rojo project (`default.project.json`): `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayerScripts.Client`.
- Pinned toolchain in `rokit.toml` (Rojo 7.7.1, Lune 0.11.1, StyLua 2.6.0, Selene 0.31.0, luau-lsp 1.70.1); `scripts/bootstrap.sh` builds the same versions from crates.io where GitHub downloads are blocked.
- Lune test runner (`lune run tests`) with a small describe/it/expect framework; smoke tests; a purity test that keeps the simulation free of Roblox APIs, clocks and unseeded randomness.
- CI (`.github/workflows/ci.yml`): StyLua, Selene (two configs), Lune tests, luau-lsp type check, Rojo build; uploads `270.rbxl` as an artifact.
- Docs: `docs/PLAN.md` revision 2 (first-session decisions folded in), `docs/DESIGN.md` decisions log D-001 to D-013, `docs/TESTING.md`, `CLAUDE.md`.

**Test:** `docs/TESTING.md` → Phase 0.
