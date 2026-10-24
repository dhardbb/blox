# Proposal: debates as live rounds (Oct 24, 2026, branch `debates`)

Status: **design for review, no game code yet.** Built on `front-page` v0.12.0. When it's approved it becomes a `DESIGN.md` entry (next free D-number), with `PLAN.md` "Debates" rewritten to match.

**Feedback.** Debates "kinda feel like glorified stance questions rather than their own thing". The designers chose: "Live rounds: short back-and-forth rounds: attack, defend or pivot to your platform, with visible counters. More drama, more reading the opponent." Standing priorities: fun first. Choices are skill-based and learnable, and tied to the states you need. No blind rock-paper-scissors ("removed the learning component"). Effects show on the map. Debates deciding about 1 match in 5 is fine. Humans make more mistakes than bots.

**Pitch.** A debate is its own stage: both portraits, a moderator, a crowd meter, three rounds. Each round the moderator asks about one of the debate's three topics (already announced weeks ahead). Both players secretly lock in **Defend**, **Attack** or **Pivot**, and may add their one **Zinger**. The cards flip, the clash plays, and the round's winner gains in the states that care about the topic, live on the map. No dice: every number comes from public facts and is printed on the button, along with how each move does against each of the opponent's three moves. Most rounds have a move that can't lose, and a player can learn to find it. The read (the Zinger's timing, the opponent's mistakes) is the bonus.

## 1. One round

**Strength of each move** (whole numbers, every part shown as a chip on the button):

| Move | Base | + | + | + |
|---|---|---|---|---|
| **Defend**: answer straight | 2 | **+4** if the topic is on *your* platform | **+1** if you lead the topic's states | |
| **Attack**: go after their record | 3 | **+2** if the topic is on *their* platform | **+1** if you trail the topic's states | **+2** if you trail the crowd |
| **Pivot**: steer to your issue | 3 | **+2** if the topic is *not* on your platform | **+1** if you lead the crowd | |

- **Counters, shown up front:** Defend beats Attack, Attack beats Pivot, Pivot beats Defend. The move that counters the opponent's move gets **+2**.
- **Repeat:** the same move as your previous round in this debate gets **−2** ("the crowd saw it coming"). So history is public and you can read it.
- **Zinger:** +3 to your move, **once per debate**. Whether each side still has one is shown on the stage. Hale: his Zinger is +5 (see §6).
- **"Lead the topic's states":** at the start of the round, the EV of the topic's states (`Debate.topicStates`) where you lead the public poll is more than your opponent's. Equal EV gives nobody the +1. So the debate prep is the campaign itself: build leads in the next debate's topic states.
- **Score** = strength + counter + Zinger. The higher score wins the round, and the margin is the difference. **Equal scores are a split.**

**What a round moves** (from one start-of-round snapshot, applied together, D-001):

| Result | Map effect | Crowd |
|---|---|---|
| Win | **+1.0** for the winner in each of its *landing states* (normal undecided/opponent split) | winner + margin (at most 4) |
| Split | **+0.5** for each player in their own landing states | — |
| Lost to a counter ("backfire") | **−0.5** for the loser in its own landing states (to undecided) | — |

*Landing states:* Defend and Attack land in the topic's states. **Pivot lands in your pivot issue's states.** Your pivot issue is the platform issue (other than this topic) whose states hold the most EV within 5 points of the public poll either way for you; ties go to platform order. It is public and recomputed each round, and the button names it ("Pivot → Safety"). So Pivot is the move for a topic whose states you don't need.

After each round the public polls are republished with the same error terms (`Polls.refresh`, no new draw). The map badges the points and calls FLIP the moment the clash lands, and the header's projected EV ticks.

**After round 3 (the verdict):** the crowd leader gains 0.05 × their crowd lead in every state (at most 0.5, the old sweep's size). A lead of 10 or more is a **standing ovation**: +2 momentum in every battleground (today's sweep momentum).

**Timeout:** a *canned answer*, meaning Defend scored a flat 2 (no bonuses, no Zinger). It counts as Defend for counters and repeats. It costs you, the way today's "no focus" does, but it can't wreck you. The client's AutoLock still sends a highlighted move when the timer runs out.

**Fair and general.** There is no randomness in a debate at all, so the `debate:{week}` stream is retired; no other stream changes. A split is equal and never broken by seat. Swapping seats with the same inputs mirrors every result (spec). For N players: "their platform" means any opponent's; the counter bonus is earned once if your move counters any opponent's move; the unique top score wins and a tie at the top splits between the tied players; "trail the crowd" means below the top. Payloads are `{ move = "Defend"|"Attack"|"Pivot", zinger = true? }`. They are rejected whole with a reason code (`BadMove`, `ZingerSpent`, `UnexpectedMove` in a plan, `WrongPhase`, `BadShape`), never thrown, never partly applied.

**All numbers** go in `Sim/Config` with a one-line comment: `DEBATE_ROUNDS` 3, `DEBATE_DEFEND_BASE` 2, `DEBATE_ATTACK_BASE` 3, `DEBATE_PIVOT_BASE` 3, `DEBATE_OWN_ISSUE` 4, `DEBATE_THEIR_ISSUE` 2, `DEBATE_OFF_ISSUE` 2, `DEBATE_GROUND` 1, `DEBATE_CROWD_TRAIL` 2, `DEBATE_CROWD_LEAD` 1, `DEBATE_COUNTER` 2, `DEBATE_REPEAT` 2, `DEBATE_ZINGER` 3, `DEBATE_ZINGERS` 1, `DEBATE_CANNED` 2, `DEBATE_ROUND_WIN` 1.0, `DEBATE_ROUND_SPLIT` 0.5, `DEBATE_BACKFIRE` 0.5, `DEBATE_CROWD_ROUND_MAX` 4, `DEBATE_CROWD_POINT` 0.05, `DEBATE_CROWD_CAP` 10, `DEBATE_OVATION` 10, `DEBATE_OVATION_MOMENTUM` 2, `DEBATE_PIVOT_CLOSE` 5, `TIMER_DEBATE_INTRO` 5, `TIMER_DEBATE_ROUND` 12, `TIMER_DEBATE_CLASH` 4, `TIMER_DEBATE_VERDICT` 6, `BOT_DEBATE_READ` 0.5, `BOT_EXTREME_HISTORY` 0.5. `DEBATE_ROUND_WIN` is the main lever for "debates decide 15–25%".

**Why these numbers** (a scratch paper model of a single round: random platforms, a coin-flip ground lead, every history case, no map; the harness replaces it). Before Zingers, **71% of round situations have a safe move** for both sides (a saddle point: a move that does at least as well whatever the other side does), and the safe move is Defend 34%, Attack 35%, Pivot 31%. Medium bot vs Medium bot: rounds won 42% / split 16% / lost 42%, moves D 36 / A 35 / P 29%. Medium vs a uniform-random mover: wins 64% of rounds, splits 9%, loses 27%, and takes the crowd in 80% of debates. *Rejected:* a counter worth 4 (safe moves in only 10% of rounds, which is blind RPS again); counter 1 on the old half-size scale (89% solved, so reads never matter); ground as the tie-breaker instead of splits (88% solved, and the leader in the topic's states wins nearly every round); no repeat penalty (63% safe, and Defend gets spammed).

## 2. Two worked rounds

Rex Calloway (Jobs, Safety, Transit) vs June Alvarado (Health, Schools, Farms). Week-4 topics: Jobs, Health, Technology. Each cell is Rex's score − June's.

**Round 1, Jobs** (Rex's issue). Rex leads Jobs' states 64–41 EV, the crowd is even, both have a Zinger.
Rex: Defend 2+4+1 = **7**, Attack **3**, Pivot→Safety **3**. June: Defend **2**, Attack 3+2+1 = **6**, Pivot→Farms 3+2 = **5**.

| Rex ↓ / June → | Defend | Attack | Pivot |
|---|---|---|---|
| Defend | +5 (7 v 2) | **+3** (9 v 6, June backfires) | **split** (7 v 7) |
| Attack | −1 (3 v 4, Rex backfires) | −3 | split (5 v 5) |
| Pivot | +3 (5 v 2) | −5 (Rex backfires) | −2 |

Rex's Defend never loses, and neither does June's Pivot, so the "correct" round is a split. June reads that Rex will Defend and spends her Zinger on Pivot: 5+2+3 = 10 vs 7. **June wins by 3**: +1.0 for June in Farms' states (WI flips to her live), and Rex's countered Defend backfires (−0.5 in Jobs' states). Crowd June +3.

**Round 2, Health** (June's issue). June leads Health's states 58–30, June leads the crowd, Rex still has his Zinger and June doesn't. Repeats: Rex's Defend −2, June's Pivot −2.
Rex: Defend 2−2 = **0**, Attack 3+2+1+2 = **8**, Pivot→Safety 3+2 = **5**. June: Defend 2+4+1 = **7**, Attack **3**, Pivot 3+1−2 = **2**.
Without Zingers Rex's Pivot never loses (split, split, win by 3) and June's Defend never loses either. But Rex's Zinger is visibly unused, and it lifts his Pivot to a win against everything: Pivot+Zinger = 10 vs Defend 7, 8 vs Attack 5. June can only limit the damage, by Defending. **Rex wins by 3**: +1.0 in Safety's states (GA flips), and June's countered Defend backfires in Health's states. Crowd back to even, so round 3 (Technology, nobody's issue) decides the verdict. The lesson a player can carry: *spend the Zinger where it turns a safe split into a sure win.*

## 3. Flow, timers, budget

Debate week: **Intro** (Show, 5 s: stage, topics, each side's platform, crowd 0) → three × [**Round** (Input, 12 s; both locked in ends it) → **Clash** (Reveal, 4 s)] → **Verdict** (Reveal, 6 s, skippable if both tap) → [Decision Stance if it's a Choice week] → Plan. The Focus decision is gone. Every deadline is `Session.setStage(now, duration)` with `now = workspace:GetServerTimeNow()`, so it's absolute. Disconnected players get the canned answer at the deadline and spend no grace (rounds are too short to wait for).

Worst case per debate: 5 + 3 × 16 + 6 = 59 s, against 30 s today (focus 20 + reveal 10). `Config.spec`'s old-steps worst case goes 940 → 920 + 118 = **1,038 s, still under the 1,050 s line**. The Decision steps drop from 200 s to 160 s at most (stances only). Typical: a round locks in after about 6 s, so a debate takes about 41 s against about 18 s today, roughly +45 s a match. By the D-005 model that keeps a typical match near 12 minutes, inside D-005's 15.

## 4. What clients see (View, no leaks)

`view.debate` (debate weeks only):
- `week`, `round`, `topics`
- `crowd` and `zingers` (per player)
- `board[p] = { move → { strength, parts = {label, points}… }, pivotIssue }` for every player, built by `Debate.board`, a pure function of public fields that the client, the bots and the duel screen all call
- `history`: each finished round's moves, Zingers, scores, winner, splits, backfires, per-state `moves` and `flips`
- `yourMove`: your own pending lock-in only

The opponent's pending move lives in `PlayerState.debateMove` and never leaves the server until its Clash. Seat "locked in" stays public, as today. `debateShift` stays hidden (harness recount). `View.spec`'s no-leak test gains `debateMove`.

## 5. Bots (each from its own View only, D-057)

- **Medium** (the harness bot) builds the 3×3 table from `Debate.board`. It values each cell by what its map moves are worth to it: EV × closeness, the same weight as `Bot.topicValue`, plus for the gains and backfires that land on the opponent. It plays the move whose worst cell is best, breaking ties by the average cell and then in the fixed order D, A, P. It uses the Zinger when that lifts the worst cell from a loss or split to a win, else in round 3.
- **Easy**: half the time (`BOT_EASY_SLIP`) a random move, and the Zinger in a random round.
- **Hard** predicts the opponent: half the weight (`BOT_DEBATE_READ`) on what Medium would play from their side of the public board, the rest even. It plays the best expected move and holds its Zinger until, under that prediction, it decides a round.
- **Extreme** = Hard, plus a read of the opponent's own move frequencies in this match's earlier rounds (public history, `BOT_EXTREME_HISTORY`), so a human who always Defends gets Pivoted. `BotDifficulty.spec`'s fair-play check (decisions unchanged when hidden fields change) covers debate rounds.

New harness styles `RandomMove`, `NoAnswer` (always the canned answer), `AlwaysDefend`, `AlwaysAttack` and `AlwaysPivot` replace `RandomFocus` and `NoFocus`.

## 6. Candidates

Everyone's debate stat is 1 today and cancels out, so `debateStat`, `DEBATE_STAT` and `DEBATE_MAX_STAT_GAP` go. **Marcus Hale: "Zinger +5 instead of +3"** (was focus +3). Paper model vs Medium: +5 wins 51% of rounds and loses 44% (crowd 49/35), close to today's edge (his topic win rate is 47% against 38–41% for the others). Two Zingers measured 61/28% of rounds and 78% of crowds: too strong. +4 measured 43/39%: no perk left.

## 7. Screens (phone 390×844, iPad 1024×768; UI audit stays 0)

```
PHONE (390 wide, portrait)
┌────────────────────────────────────┐
│ WEEK 4 DEBATE · ROUND 1 OF 3  ▬▬ 9s│  header + server-deadline bar
│ (RC) Rex ⚡1 ◀▓▓▓|░░░▶ ⚡1 June (JA) │
│ "Jobs: the plant is closing. What  │  moderator card
│  is your plan?"                    │
│ <Your issue> <You lead its states  │
│  64–41 EV>  R1 · R2 · R3 strip     │
├────────────────────────────────────┤
│  MAP, compact: Jobs states lit;    │  ~240 px
│  the held move's landing states    │
├────────────────────────────────────┤
│ [ DEFEND 7 ]        beats Attack   │  2 +4 your issue +1 lead
│   vs D +5 · vs A +3 · vs P =       │
│ [ ATTACK 3 ]        beats Pivot    │
│   vs D −1 · vs A −3 · vs P =       │
│ [ PIVOT → Safety 3 ] beats Defend  │
│   vs D +3 · vs A −5 · vs P −2      │
│ ( ⚡ Zinger +3 · 1 left )  June ⚡1 │  toggle chip
├────────────────────────────────────┤
│ June: thinking…        [ LOCK IN ] │  pinned action bar
└────────────────────────────────────┘

IPAD (1024x768, landscape): stage across the top, map left, moves right
┌──────────────────────────────────────────────────────────────┐
│ WEEK 4 DEBATE · ROUND 1 OF 3                         ▬▬▬ 9s  │
│ (RC) Rex ⚡1   ◀▓▓▓▓▓|░░░░░▶   ⚡1 June (JA)                    │
│ "Jobs: the plant is closing. What is your plan?"             │
├───────────────────────────────┬──────────────────────────────┤
│                               │ [ DEFEND 7 ]   beats Attack  │
│   MAP (Jobs states lit;       │  2 +4 your issue +1 you lead │
│   Pivot → Safety states       │  vs D +5 · vs A +3 · vs P =  │
│   outlined while held)        │ [ ATTACK 3 ]   beats Pivot   │
│                               │ [ PIVOT → Safety 3 ] b. Def. │
│                               │ ( ⚡ Zinger +3 · 1 left )     │
│ R1 Jobs · R2 Health · R3 Tech │ June: locked in ✓            │
├───────────────────────────────┴──────────────────────────────┤
│                                               [ LOCK IN ]    │
└──────────────────────────────────────────────────────────────┘

CLASH (4 s, both sizes): the two move cards fly in from the portraits and
flip; the counter arrow draws ("PIVOT ▶ beats ▶ DEFEND +2"); a Zinger card
bursts (+3); the scores tick up; Kit.stamp "JUNE WINS BY 3" (green "You win",
orange with a sign for a loss, plain "SPLIT"); the meter slides; map badges pop
(+1.0 in the winner's color, −0.5 orange backfire), FLIP callouts; the header's
projected EV ticks.
VERDICT (6 s): "June won the crowd by 3: +0.15 everywhere" and the states each
round flipped (the existing Swing lines); then the stance or plan screen.
```

Each button carries strength chips ("2 +4 your issue +1 you lead") and a three-cell result row against Defend, Attack and Pivot (`+3`, `=`, `−5`, sign always shown, D-056 `lossText`). The table assumes no Zingers; a line under it says when they still have one. A 44 px minimum tap height, one primary (Lock in). Holding a move previews its landing states on the map. New `Screens/Debate.luau` with `DebateParts/{Stage, Moves, Clash, Meter}.luau`, plus Router phase `Debate`. Coach tips: `debate.moves`, `debate.zinger`.

## 8. Duel harness

`ACTION NEEDED: Week 4 Debate round 1 of 3: Jobs`. Commands: `defend`, `attack`, `pivot`, each optionally followed by `zinger` (`attack zinger`). `WHAT TO DO` prints both boards with their parts, the 3×3 result table, crowd, Zingers and round history. The log gets one line per round: `R1 Jobs: you Defend 7, June Pivot+Zinger 10: June wins by 3; Farms +1.0 to June (WI flipped, +10 EV); your backfire -0.5 in Jobs states`. The harness default is the game's own timeout (canned answer). `focus` is removed (rejected as `WrongPhase`). `README.md` and `Verdict.spec` get updated.

## 9. Measuring it

`lune run tests/harness/balance.luau 2000`, plus a new `tests/harness/debate.luau [N]` (round-level stats by situation). Targets:

| Check | Target |
|---|---|
| Debates change the winner (D-018 counterfactual recount) / EV swung | 15–25% / 20–40 EV |
| Medium v Medium: splits / each move's share | ≤ 25% / every move 20–50% |
| AlwaysDefend, AlwaysAttack, AlwaysPivot vs Medium (match wins) | each ≤ 45%: no dominant move |
| RandomMove / NoAnswer vs Medium | ≤ 42% / ≤ 35% |
| Rounds with a safe move on the board (informational) / Medium took it | 55–80% / ≥ 90% |
| Rounds a Zinger decided; the round it's spent in | informational |
| Candidates / Hale's round win rate | 45–55% each / ≤ 60% |
| Seat 1 round wins (seats alternate) | 49–51% |
| Difficulty ladder (D-057 bands), comeback, blowout targets (D-024) | unchanged |

**Humans** (`TESTING.md`): did you know why you won or lost each round? Did you ever pick a move because of what they did last round? Did the map move where you expected?

## 10. Kept and removed

**Kept:**
- `Debate.drawTopics`, `nextWeek`, `topicStates`
- `Debate.moves`, generalized to landing states per player
- the snapshot apply block and `debateShift` (the recount)
- `Polls.refresh`, `PollFlip` events (`issue = "Debate"`)
- `View.nextDebate` (topics weeks ahead)
- the Swing flip lines, Results' "What decided it", `DebateResult` with `moves`/`flips` (now per round), the Kit stamp, monogram and race-bar parts

**Removed** (git history keeps them; file removals per the standing rule):
- the Focus decision (`Decision` keeps Stance), `PlayerState.debateFocus`, `View.debateFocus`
- `DEBATE_FOCUS`, `focusEdge`, `DEBATE_PLATFORM_BONUS`, `DEBATE_ROLL_MAX` and the roll, `Debate.odds`
- `DEBATE_TOPIC_WIN`, `DEBATE_TOPIC_NATIONAL`, `DEBATE_SWEEP` and `DEBATE_SWEEP_MOMENTUM` (all renamed into the table above), `DEBATE_GAFFE`, `TIMER_DEBATE`
- `Bot.focus`, `readFocus`, `BOT_FOCUS_READ`
- `CampaignParts/Focus.luau`, Reveal's debate scoreboard, `BadFocus` and `UnexpectedFocus`

**Specs first** (failing before code):
- `Debate.spec`: the strength table, counters, repeat, a single Zinger, canned default, split, backfire, crowd, ovation, the pivot-issue rule, the seat-swap mirror, determinism, a 3-player smoke test
- `Match.spec` and `Session.spec`: stage order and absolute deadlines
- `View.spec`, `Bot.spec`, `BotDifficulty.spec`
- `Config.spec`: the 1,038 s budget
- the UI specs, plus phone and iPad snapshots

## 11. Open questions (my judgment calls)

1. **Show a "can't lose" tag on the safe move?** I left it off: the result row already shows it, and spotting it is the skill. It could be on for the first debate, or for Easy practice only.
2. **Pivot's landing issue is picked automatically** (most in-play EV) to keep each round to one tap. The alternative is that the player picks it, which is a second tap and slower.
3. **The timeout is a weak Defend, not "no answer".** It's gentler than today's gaffe. Harsher would be: score 0 and a −0.6 gaffe.
4. **A split pays both sides +0.5.** The alternative is that it pays nothing, which is drier and makes bot-vs-bot debates quieter.
5. **Three rounds, one per topic.** A fourth "closing statement" round would add drama but costs about 16 s and breaks the 1,050 s line.
6. **Ground (+1) rewards whoever leads the topic's states.** That's a small snowball, and the harness's comeback check is what watches it.
7. **No time bank in rounds**, and no grace for disconnects (12 s rounds).
8. **The debate stat is removed** rather than kept at 1 for everyone.
