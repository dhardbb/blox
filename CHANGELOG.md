# Changelog

Newest first. Each entry lists what changed, what to test (see `docs/TESTING.md`), and anything needed from the humans.

## Unreleased — ratings and saved stats (branch `phase5-data`)

Elo ratings and persistent player stats (`docs/DESIGN.md` D-028). The debug UI shows them; the real screens come later.

- `Net/Rating`, `Net/Profile`: Elo (K 32, start 1000, new `ELO_FLOOR` 100) and the saved record: rating, wins/losses, per-candidate record, last 10 matches, practice total. `Profile.migrate` repairs nil, garbage and older versions.
- `server/DataService`: the profile in a DataStore (`PlayerData_v1`, key `Player_<UserId>`), session-locked by server, retried with backoff, saved when a match ends, when the player leaves and on shutdown. Never on the hot path of a turn.
- Only human-vs-human matches ending by Election or Forfeit are rated. Practice and abandoned matches never move the rating. A forfeit costs the player who left.
- In an unpublished Studio place DataStores can't work: one warning, then it plays with an in-memory store (nothing is saved).
- Debug UI: the lobby line shows `Rating 1032 (12-7)`; after a rated match the log and board show `Rating 1032 → 1048`. New optional `profile` on the lobby status and a `Rating` message.
- Fake engine: a fake `DataStoreService` (with "not published" and transient-failure switches), `game.JobId`, `game:BindToClose` and `os.time` on the simulated clock.
- Specs: 271 (was 225). `tests/net/Rating.spec.luau` covers Elo math and profiles; `tests/e2e/Data.spec.luau` covers saving, the lobby display, practice, forfeit, locks, retries, unpublished mode and shutdown.

**Test:** `docs/TESTING.md` → Ratings and saved stats.

**Needed from the humans:** publish the place to Roblox and turn on Home → Game Settings → Security → **Enable Studio Access to API Services**, or saving can't be tested in Studio.

## Unreleased — balance pass 1 (branch `balance-pass-1`)

First tuning pass from the harness (`docs/DESIGN.md` D-018 to D-025). No UI change; the server self-test still runs.

- Harness: "debates change the winner" is a real counterfactual now. `Debate.resolve` records the support each debate moved (`StateSim.debateShift`, hidden) and `Election.count(..., { debates = false })` recounts without it, like the GOTV check. The paired replay it replaces was measuring chaos (D-018).
- Config (tuning): `DEBATE_ROLL_MAX` 2 → 6, `DEBATE_TOPIC_WIN` 0.8 → 0.2, `DEBATE_SWEEP` and `DEBATE_GAFFE` 0.5 → 0.2 (D-019); `UNDERDOG_HYSTERESIS` 20 → 30, `UNDERDOG_SMOOTHING` 0.5 → 0.4 (D-020); `GOTV_PER_UNIT` 1.0 → 1.5 (D-021). Bot: ground game from week 7.
- Candidates (tuning, D-022): Begay rallies 2.9, Alvarado $20 start / $3.75 income, Reyes momentum +65%, Strand media −15%, Calloway rallies 2.3, Hale starts with $0.
- Candidates (**proposed, needs the humans' approval**, D-023): Hale's perk is 8 prep points instead of debate stat 2; Venkat's drawback is $3 income instead of debate stat 0; Okafor loses her rally drawback and fundraises +50%.
- Result: all eight candidates 45–55% (was 20–89%), debates decide 16% of matches and swing 15 EV (was 42% / 61 EV), GOTV decides 12% (was 1.8%), comebacks 37%, tier changes 3.0 per match. Blowouts fall from 80% to 60% of matches, which is the winner-take-all floor; D-024 proposes a revised target. The wrong-leader underdog share rose to 22% because games are closer (D-020).
- Specs: 161 (was 156). New ones pin the debate counterfactual, a sweep under one national point, GOTV's place between a poorly and a well matched media buy, the bot placing ground game before week 9, and the new hysteresis arithmetic.

**Test:** `docs/TESTING.md` → Balance pass 1.

**Needed from the humans:** approve or pick alternatives for the three perk shapes in D-023; decide the blowout target (D-024) and the rubber-band trade-off (D-020).

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
