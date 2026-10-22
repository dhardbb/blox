# Duel harness: two agents play one match

`tests/duel.luau` runs one full match on the real server and client code (fake engine, simulated clock) and lets two players, usually two AI agents, play it through files. It is a playtest tool, not a spec: `lune run tests` ignores it.

## Run a match

```sh
mkdir -p ../duel/m1
lune run tests/duel.luau -- --dir ../duel/m1 --seed 11 --timeout 3600   # in the background
tests/duel/wait.sh ../duel/m1 1        # player 1: block until there is a new screen, print it
tests/duel/send.sh ../duel/m1 1 'select okafor crimson jobs health schools'
```

Each player loops `wait.sh` → think → `send.sh` until `wait.sh` prints `MATCH OVER`. The simulated clock stops whenever a player must act, so agents have unlimited real time. Reveals, debates and election night run by themselves.

Options: `--seed N` (map and deck), `--timeout S` (real seconds a screen may wait for a command before the harness plays the default for that player; default 600), `--attempts K` (rejected command files per screen before it does the same; default 3). Fallbacks are listed under HARNESS NOTES in `result.txt`, `--screen WxH`.

Exit code: 0 the match finished, 1 a script error happened, 3 the harness gave up.

## Files in the match folder

| File | Written by | What |
|---|---|---|
| `state.txt` | harness | `starting`, `running`, `waiting p1`, `waiting p1 p2` or `done` |
| `map.txt` | harness | static map data (EV, issues, region, neighbors, pool size), written once |
| `pN.screen.txt` | harness | what player N must answer now; first line `TURN: k` grows with every new screen |
| `pN.cmd.txt` | player | one or more command lines; the harness types each into the debug command box, then deletes the file |
| `pN.result.txt` | harness | the verdict on the last command file (`ACCEPTED` / `REJECTED` and why) |
| `result.txt` | harness | the match result, written just before `state.txt` says `done` |

All writes are atomic (temp file, then rename). The commands are the debug panel's (`help` lists them); each screen shows examples.

## Scripted players

`tests/duel/scripted_agent.sh DIR N [candidate] [pass|example]` is a dumb player used to prove the protocol end to end: it picks a fixed candidate, drafts the first two legal states, then passes every week (or, with `example`, sends each week's first example plan).
