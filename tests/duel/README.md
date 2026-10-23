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

Options: `--seed N` (map and deck), `--timeout S` (real seconds a screen may wait for a command before the harness plays the default for that player; default 600), `--attempts K` (rejected command files per turn before it does the same; default 5), `--screen WxH` (the simulated screen size). Fallbacks are listed under HARNESS NOTES in `result.txt`.

The default is `pass` in a plan week and `auto` (the built-in bot) everywhere else. After a rejection the next screen says how many attempts are left in a `!!!` line under the header, and the verdict says it too. Info commands (`show`, `rules`, `help`, `bank`, `resync`, `skip`) never use an attempt at any stage: a file of only those gets the verdict `INFO: not locked in yet, no attempt used ...` (a file that also holds a rejected move is `REJECTED`). `tests/duel/Verdict.luau` holds these rules and `Verdict.spec.luau` pins them. When the harness plays the default, the verdict's status is `AUTO-SUBMITTED (this turn is over for you)`, followed by the harness's line and then your last command file for reference.

Exit code: 0 the match finished, 1 a script error happened, 3 the harness gave up.

## Files in the match folder

| File | Written by | What |
|---|---|---|
| `state.txt` | harness | `starting`, `running`, `waiting p1`, `waiting p1 p2` or `done` |
| `map.txt` | harness | static map data (EV, issues, region, neighbors, pool size), written once |
| `pN.screen.txt` | harness | what player N must answer now. Line 1 `TURN: k` grows with every new turn and after a rejection; line 2 `REFRESH: r` grows when info commands (`show`, `rules`, `help`, `bank`) rewrote the same turn's screen with their output (TURN stays) |
| `pN.cmd.txt` | player | one or more command lines; the harness types each into the debug command box, then deletes the file |
| `pN.result.txt` | harness | the verdict on the last command file: `ACCEPTED`, `REJECTED` and why (uses an attempt), `INFO` (info lines only, no attempt) or `AUTO-SUBMITTED` |
| `result.txt` | harness | the match result, written just before `state.txt` says `done` |

All writes are atomic (temp file, then rename). The commands are the debug panel's and use the game's action names: `rally`, `fund` (or `fundraise`), `ad`, `attack ad` (or `attack`), `poll`, `rpoll` (Region poll), `gotv` (Ground game), `pivot`; `media` still works for `ad` (`help` lists them; `rules` explains every action, poll, debate, event and election night with the current numbers; `show ST` adds what each action would do in that state); each screen shows examples. `wait.sh` returns when TURN or REFRESH changes, so it is safe to call after an info command too.

## What a screen holds

Header (TURN, REFRESH, player, attempt), the output of your last command file (after `show ST` that is where its numbers are), `WHAT TO DO` (the stage's rules, your cash and route, costs, what each action would do in the state of your last `show` this turn, else where your candidate is, commands, examples), `BOARD` (the debug panel's board: players, projection, this week's event, next debate, your draft with nominated strongholds listed apart, the closest states), debates and events so far, the projected-EV trend, `LOG SINCE YOUR LAST TURN` (the debug panel's log: last week's events in words, rejections, notices; lines already shown as command output are left out) and, after Select, every state. Each fact appears once. Money is floored to $0.1 (you can always spend what you see); a plan rejected for money says what it costs and what you have.

## Choice weeks and debates

A Choice week asks for a stance on one issue: add `choice a`, `choice b` or `choice c` to the plan (`c`, the hedge, is the default; `pass` takes it). The screen shows what the game's event card and map show, in words:

- `WHAT TO DO` lists every state each stance moves for you (`A · Side with the staff: +1.5 in GA, IN … · -1.5 in AL …`) and each stance's flavor line.
- The `BOARD` has the states you need (within 5 points in the public poll, either way: "you trail WI by 2 · you lead OH by 3") and one summary per stance: `Stance A · …: +6.0 total over 9 states (4 you need: OH, PA …) · -3.0 total over 5 states (2 you lead: KY by 3 …) · could flip PA (+19 EV), lose WI (-10 EV)`. Flips are on today's public polls, from your stance alone (the opponent's is secret).
- The week after, the board says what both stances moved and which poll leaders they flipped; earlier Choice weeks are under `DEBATES AND EVENTS SO FAR`.

After a debate the board names the states each topic swung and every flip (`Your Jobs win swung OH, MI, PA (+1.0 each) - PA flipped to you (+19 EV)`, `Their gaffe on Safety: -0.6 in TX, AZ`); the score breakdown (prep, platform, stat, roll) is under `DEBATES AND EVENTS SO FAR`, and the log has one line per flipped state.

## Scripted players

`tests/duel/scripted_agent.sh DIR N [candidate] [pass|example]` is a dumb player used to prove the protocol end to end: it picks a fixed candidate, drafts the first two legal states, then passes every week (or, with `example`, sends each week's first example plan, which takes stance `a` in a Choice week). It needs no `timeout` command, so it runs on macOS as is.
