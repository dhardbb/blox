# Duel harness: two agents play one match

`tests/duel.luau` runs one full match on the real server and client code (fake engine, simulated clock) and lets two players, usually two AI agents, play it through files. It is a playtest tool, not a spec: `lune run tests` ignores it.

## Run a match

```sh
mkdir -p ../duel/m1
lune run tests/duel.luau -- --dir ../duel/m1 --seed 11 --timeout 3600   # in the background
tests/duel/wait.sh ../duel/m1 1        # player 1: block until there is a new screen, print it
tests/duel/send.sh ../duel/m1 1 'select okafor jobs health schools'
```

The draft is three blind rounds (home state, then two battleground nominations); each player's five strongholds are assigned from the map's leans before it and listed on the draft screen. Each player loops `wait.sh` → think → `send.sh` until `wait.sh` prints `MATCH OVER`. The simulated clock stops whenever a player must act, so agents have unlimited real time. Reveals, debates and election night run by themselves.

Options: `--seed N` (map and deck), `--timeout S` (real seconds a screen may wait for a command before the harness plays the default for that player; default 600), `--attempts K` (rejected command files per turn before it does the same; default 5), `--screen WxH` (the simulated screen size). Fallbacks are listed under HARNESS NOTES in `result.txt`.

The default is `pass` in a plan week, `choice c` on a stance step (both what the game does when the timer runs out) and `auto` (the built-in bot) everywhere else, debate rounds included (there is no command for the game's timeout, a canned answer). After a rejection the next screen says how many attempts are left in a `!!!` line under the header, and the verdict says it too. Info commands (`show`, `rules`, `help`, `bank`, `resync`, `skip`) never use an attempt at any stage: a file of only those gets the verdict `INFO: not locked in yet, no attempt used ...` (a file that also holds a rejected move is `REJECTED`). `tests/duel/Verdict.luau` holds these rules and `Verdict.spec.luau` pins them. When the harness plays the default, the verdict's status is `AUTO-SUBMITTED (this turn is over for you)`, followed by the harness's line and then your last command file for reference.

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

## Debate rounds and Choice stances

**Debates (D-062)** are three live rounds in weeks 4 and 9, one per topic, each its own turn: `ACTION NEEDED: Week 4 Debate round 1 of 3: Jobs`. Both players pick at once, in secret:

- `defend`, `attack` or `pivot`; add `zinger` to stake your one Zinger on this round (`attack zinger`): a round you win then counts ×2 on the map and the crowd (Hale ×3). Win or lose, it is spent.
- Defend beats Attack, Attack beats Pivot, Pivot beats Defend: the counter adds +2 in round 1, +3 after. Higher score wins the round; equal is a split. The same move as last round is −2.
- `WHAT TO DO` explains the rules; the `BOARD` prints the round: the facts (your issue / theirs, who leads the topic's states, the crowd, Zingers), their strengths, and for each of your moves its strength with its parts and the result cells against their Defend, Attack and Pivot (`vs D +4 · vs A +3 · vs P +0 (split)`), "(cannot lose)" when no cell is below 0, and what a win would flip on today's polls.
- A win: +1.0 in every state of the topic (Defend, Attack) or of your pivot issue (Pivot); a split +0.5 each; losing to a counter −0.5 where your move aimed. The polls are republished after every round.
- The log has one line per round: `R1 Jobs: you Defend 6, them Attack+Zinger 5: you win by 3`. `DEBATES AND EVENTS SO FAR` repeats every round's moves and scores and what it swung.
- `focus` is gone (an error says so); a `plan` or `pass` in a debate round is rejected (`BadMove`).

**Stances** (`choice a`, `choice b` or `choice c`) are their own Decision step before a Choice week's plan (D-044): `ACTION NEEDED: Week 5 Decision: stance`. `WHAT TO DO` lists every state each stance moves for you (`A · Side with the staff: +1.5 in GA, IN … · -1.5 in AL …`) and each stance's flavor line. The `BOARD` has the states you need and one summary per stance: `Stance A · …: +6.0 total over 9 states (4 you need: OH, PA …) · -3.0 total over 5 states (2 you lead: KY by 3 …) · could flip PA (+19 EV), lose WI (-10 EV)`. Flips are on today's public polls, from your stance alone (the opponent's is secret). A debate week with a Choice event runs debate, then stance, then plan. A plan that still carries `focus`, `choice` or a move is rejected (`UnexpectedFocus`, `UnexpectedChoice`, `UnexpectedMove`). The week after a Choice event the board says what both stances moved and which poll leaders they flipped.

## Polls and ground game

Ground game (`gotv`) is hidden from the public polls and the projection; it counts only on election night. A paid internal poll (`poll ST`, or `rpoll REGION` for every state in a region) is the only way to see the opponent's: next turn, `Your internal polls` on the board ends `their gotv N` for each polled state with any, and `Their gotv your polls saw: OH 3 (wk 8), …` lists your latest reading of every state you ever polled (exact, as of the end of that week; they may have added units since). The state list tags those states `their gotv N (-X for you; your poll, end of week W)`, and `show ST` ends with the same sentence the game's state card shows. `WHAT TO DO` repeats the rule once per plan turn. The opponent sees your units only where they poll.

## Scripted players

`tests/duel/scripted_agent.sh DIR N [candidate] [pass|example]` is a dumb player used to prove the protocol end to end: it picks a fixed candidate, drafts the first two legal states, then passes every week (or, with `example`, sends each week's first example plan); on a stance step it sends the screen's first example (`choice a`), in a debate round `defend`. It needs no `timeout` command, so it runs on macOS as is.
