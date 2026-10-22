# 270: working notes for Claude

A 1v1 turn-based election strategy game for Roblox. Read `docs/PLAN.md` (the design and build plan) and the latest entries of `docs/DESIGN.md` (decisions log) before changing gameplay. The humans playtest in Roblox Studio and cannot read code; you own the code.

## Commands

Run from the repo root. All four must be clean before any commit.

```sh
lune run tests                                   # every spec; filter: lune run tests Rng
lune run tests/harness/balance.luau              # balance report (from Phase 1)
lune run tests/play.luau -- "p1: practice" "p1! Autoplay" "until p1 match over" "screen p1"   # play headlessly
mkdir -p build && rojo build -o build/270.rbxl   # place file
stylua --check src tests && selene --config selene.sim.toml src/shared/Sim src/shared/Net src/shared/DebugUI src/shared/UI tests && selene src
```

Type check (CI runs it; locally only if luau-lsp is installed):

```sh
rojo sourcemap default.project.json -o sourcemap.json
curl -fsSL -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json --definitions=@roblox=globalTypes.d.luau src
```

Toolchain: `rokit install`, or `scripts/bootstrap.sh` if GitHub release downloads are blocked (it builds from crates.io; luau-lsp then runs only in CI). In a sandbox, also run `export PATH="$HOME/.cargo/bin:$PATH"`. `selene src` needs the Roblox std, which Selene downloads on first run; if that's blocked, rely on CI for it.

## Layout

- `src/shared/Sim/`: the game rules as pure Luau. Takes (config, seed, inputs), returns (newState, events).
- `src/shared/Net/`: remote names, request schemas, and the pure server core: `Session` (one live match: timers, lock-ins, time bank, skips, disconnect grace, forfeits, bots, per-seat State messages) and `Lobby` (queue, private codes, practice). Pure like `Sim/`: callers pass `now`, so it is tested in `tests/net/`.
- `src/server/`: match lifecycle, lobby, turn timers, replication, DataStore.
- `src/client/`: screens, map, components. Renders the per-player `View` only.
- `tests/sim/*.spec.luau`: Lune specs. `tests/lib/Test.luau`: describe/it/expect.
- `tests/harness/`: bot-vs-bot balance harness.
- `tests/lib/FakeRoblox.luau`: a fake Roblox engine that runs the real `src/server` and `src/client` scripts under Lune with simulated players and a simulated clock. `tests/e2e/` plays whole matches through it; `tests/play.luau` lets an agent play step by step and read each player's screen (usage in its header). It fakes remotes, Players, the task library and a rough UI layout, not rendering or the real engine.

## Testing in real Roblox Studio

Studio is installed on the humans' Mac and the official Roblox Studio MCP server is registered with Claude Code (`claude mcp list` shows `Roblox_Studio`). With Studio open and **Assistant → settings → Enable Studio as MCP server** on, an agent can start and stop play tests, read the Output, run Luau (`execute_luau`), take screenshots and send input. Use it after the headless tests pass, to confirm behavior in the real engine. Live code sync: `rojo serve` in the repo, then the Rojo plugin's **Connect** in Studio.

## Non-negotiable rules

- `Sim/` and `Net/` never reference `game`, `workspace`, `script`, `Instance`, `Enum`, `task`, `os`, `math.random`, `Random.new`, `tick`, `wait`, or any Roblox global. `tests/sim/Purity.spec.luau` and `selene.sim.toml` enforce this.
- `--!strict` at the top of every Luau file.
- Shared code requires siblings by string path (`require("./Rng")`, `require("../Types")`). Server and client code may use instance paths (`ReplicatedStorage.Shared.Sim.X`). The `.luaurc` aliases (`@sim`, `@shared`, `@testlib`) are for tests only: Roblox does not read `.luaurc`.
- All randomness comes from the per-match seed via `Sim/Rng.luau`. Same seed + same inputs = same match.
- Resolution is simultaneous: each step reads one start-of-step snapshot and applies all players' effects together (`DESIGN.md` D-001). No code path may favor player 1.
- Support is keyed by player id in lists, never `p1`/`p2` fields. Nothing assumes exactly two players.
- The server validates every client payload against `Plan.luau` and the player's own `View`. Invalid plans are rejected with a reason code; they never throw and never partially apply.
- True support, the opponent's unrevealed plan, internal poll results, and GOTV units never leave the server. Only `View.luau` builds what a client sees.
- Server-owned deadlines are absolute `workspace:GetServerTimeNow()` values.
- Every gameplay number lives in `Sim/Config.luau` with a one-line comment. Changing one means adding a line to `docs/DESIGN.md` saying why.
- Fictional candidates and issues only. No real politicians, parties, slogans, or policy positions. Any free text goes through `TextService:FilterStringAsync`.
- Check every Roblox API you use against the official docs; don't invent methods. If create.roblox.com is unreachable, read the same pages from `https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/...` (engine reference is under `reference/engine/`).

## Working rules

- Build inside-out: simulation, then networking, then UI. No UI for a phase until its sim logic has tests.
- When the humans report a bug, write the failing test first.
- Don't ask permission for anything `docs/PLAN.md` already decides. Do ask before changing a mechanic's intent. Tuning numbers via the harness is pre-approved if logged in `DESIGN.md`.
- Prefer boring, strictly typed code over clever code. Match the surrounding style. StyLua formats everything.
- Each feature ships with a `CHANGELOG.md` entry, a `docs/TESTING.md` checklist (what to click in Studio, what should happen, what to send back), and any asset IDs or settings needed from the humans.
- Keep a full match at or under 15 minutes typical (`DESIGN.md` D-005).

## Commits

- Small commits, imperative subject line ≤ 72 chars, optionally prefixed by area: `sim:`, `server:`, `client:`, `net:`, `tests:`, `docs:`, `ci:`, `build:`.
- The body says what and why. Mention the `DESIGN.md` entry if numbers changed.
- Never commit `build/`, `sourcemap.json`, `roblox.yml`, or `globalTypes.d.luau`.
