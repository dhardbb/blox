# Proposal: debates as live rounds (revision 2, Oct 24, 2026, branch `debates`)

Status: **revised after the lead's review; being built.** The `DESIGN.md` entry is the record once it lands; this file keeps the reasoning.

**Feedback.** Debates "kinda feel like glorified stance questions rather than their own thing". The designers chose: "Live rounds: short back-and-forth rounds: attack, defend or pivot to your platform, with visible counters. More drama, more reading the opponent." Standing priorities: fun first. Choices are skill-based and learnable, and tied to the states you need. No blind rock-paper-scissors ("removed the learning component"). Effects show on the map. Debates deciding about 1 match in 5 is fine. Humans make more mistakes than bots.

**Pitch.** A debate is its own stage: both portraits, a moderator, a crowd meter, three rounds. Each round the moderator asks about one of the debate's three topics (already announced weeks ahead). Both players secretly lock in **Defend**, **Attack** or **Pivot**, and may stake their one **Zinger** on it. The cards flip, the clash plays, and the round's winner gains in the states that care about the topic, live on the map. No dice: every strength comes from public facts, and each button shows how that move does against each of the opponent's three moves. Some rounds have a move that can't lose; the rest are a read of the opponent.

**What revision 2 changed** (lead's audit, `scratchpad/audit/`):
1. The Zinger is a stakes multiplier (it doubles the map effect and crowd gain of a round you win), not +3 to the score. As +3 it was spent in round 1 93% of the time and both sides cancelled 86%, and it made the "can't lose" table lie.
2. Fewer rounds are decided before anyone moves: own platform is +3 (was +4), and the counter grows (+2 in round 1, +3 after). The paper model now draws the ground lead correlated with platform ownership.
3. The round timer is 15 s. A button shows only the move, its strength and three result cells; the parts sit behind "Why 7?". In your first debate of the session a coach tip tags the no-minus row "safe".
4. The 0.05-per-crowd-point national bonus is cut (invisible under poll noise). Only the standing ovation stays, at 8.
5. A canned answer (timeout or disconnect) can't be countered, and the crowd gain against it is capped at 1. A debate spends at most one grace use.
6. Pivot's +1 crowd-lead chip is cut. The worst-case time is stated in full: the old steps plus the decision steps.

## 1. One round

**Strength** (whole numbers):

| Move | Base | + | + | + |
|---|---|---|---|---|
| **Defend** | 2 | **+3** topic on *your* platform | **+1** you lead the topic's states | |
| **Attack** | 2 | **+2** topic on *their* platform | **+1** you trail the topic's states | **+2** you trail the crowd |
| **Pivot** | 3 | **+1** topic *not* on your platform | | |

- **Counters:** Defend beats Attack, Attack beats Pivot, Pivot beats Defend. The counter adds **+2 in round 1 and +3 in rounds 2 and 3** (`DEBATE_COUNTER = {2, 3, 3}`).
- **Repeat:** the same move as your last round in this debate is **−2**.
- **Lead the topic's states:** at the start of the round, the EV of the topic's states where you lead the public poll is greater than your opponent's. Equal EV gives nobody the bonus.
- **Score** = strength + counter. The higher score wins and the margin is the gap. Equal scores are a **split**.
- **Zinger** (one per debate; staking it is public once the round reveals): if you win the round, its map effect and crowd gain are **×2**. Hale's is ×3. Win or lose, it's spent.

**What a round moves** (one start-of-round snapshot, applied together, D-001; then `Polls.refresh` republishes the polls with the same error terms, so the map shows it live):

| Result | Map | Crowd |
|---|---|---|
| Win | **+1.0** × Zinger multiplier for the winner in its landing states | winner + min(margin, 4) × multiplier |
| Split | **+0.5** each, in their own landing states | — |
| Lost to a counter | **−0.5** for the loser in its own landing states | — |

Landing states: Defend and Attack land in the topic's states. Pivot lands in your **pivot issue's** states. That's your platform issue (not this topic) whose states hold the most EV within 5 points of the public poll either way; ties go to platform order. It's public, recomputed each round, and named on the button.

**Verdict:** a crowd lead of **8 or more** is a standing ovation: +2 momentum in every battleground. There is no flat national bonus.

**Canned answer** (timeout, disconnect): Defend at a flat 2. It counts as Defend for the next round's repeat. It never earns or suffers a counter bonus and never backfires. Crowd gained against it is capped at 1.

**Fair and general.** No randomness at all in a debate. A split is never broken by seat, and a seat-swap spec mirrors every result. For N players: "their platform" is any opponent's; the counter bonus is earned once if your move counters any (non-canned) opponent's move; the unique top score wins and a tie at the top splits; "trail the crowd" means below the top. The payload `{ move = "Defend"|"Attack"|"Pivot", zinger = true? }` is rejected whole with `BadMove`, `ZingerSpent`, `BadShape` or `WrongPhase` (and `UnexpectedMove` in a plan). It never throws and never partly applies.

## 2. Why these numbers (paper model)

`scratchpad/debate-model/model2.py`: every round-1/2/3 situation, platforms 3 of 8, and the ground lead correlated with platform (70% for the topic's only owner). A round is "pre-decided" when both sides' maximin moves meet in a saddle point with a winner.

| Variant | Pre-decided (R1 / R2 / R3) | Safe move (R1) | Medium v Medium splits | Medium v random, rounds won | Medium's moves D / A / P |
|---|---|---|---|---|---|
| Revision 1 (own 4, counter 2), no pivot chip | 43% (14 / 57 / 57) | 55% (60) | 22% | 66% | 44 / 25 / 31 |
| Counter 1/2/3 | 43% (45 / 57 / 28) | 55% (78) | 29% | 68% | 39 / 30 / 31 |
| Own 3, counter 2 | 39% (14 / 51 / 51) | 49% (44) | 13% | 67% | 37 / 32 / 31 |
| Own 3, counter 1/2/3 | 29% (15 / 51 / 21) | 57% (86) | 34% | 66% | 35 / 28 / 37 |
| **Own 3, counter 2/3/3, Attack base 2, Pivot +1 (chosen)** | **19% (14 / 22 / 22)** | **37% (60)** | **15%** | **64%** | **46 / 27 / 27** |

The chosen version won because it's the only one that keeps every round under the 40% line while round 1 still has a readable safe move 60% of the time. With 1/2/3, round 2 stays a formality (51–57%). With a flat counter, rounds 2–3 are. The Zinger never changes who wins a round, so the table stays honest. In paper Medium-vs-Medium debates it's spent in rounds 1/2/3 at 26/37/38%, and both stake the same round 33% of the time.

## 3. Two worked rounds

Rex Calloway (Jobs, Safety, Transit) vs June Alvarado (Health, Schools, Farms). Topics: Jobs, Health, Technology. Each cell is Rex's score minus June's.

**Round 1, Jobs** (Rex's issue; Rex leads its states 64–41 EV; counter +2). Rex: Defend 6, Attack 2, Pivot→Safety 3. June: Defend 2, Attack 5, Pivot→Farms 4.

| Rex ↓ / June → | Defend | Attack | Pivot |
|---|---|---|---|
| Defend | +4 | +3 (June backfires) | split |
| Attack | −2 (Rex backfires) | −3 | split |
| Pivot | +3 (June backfires) | −4 (Rex backfires) | −1 |

Rex's Defend can't lose, and neither can June's Pivot. Rex stakes his Zinger, because Jobs' states are the ones he needs. June attacks his record anyway. Rex wins by 3 ×2: **+2.0 in every Jobs state**, crowd +6, and June's countered Attack costs her −0.5 there. PA flips to Rex on the live map.

**Round 2, Health** (June's issue; she leads its states; June trails the crowd; repeats: Rex Defend, June Attack; counter +3). Rex: Defend 0, Attack 5, Pivot→Safety 4. June: Defend 6, Attack 2, Pivot 3.

| Rex ↓ / June → | Defend | Attack | Pivot |
|---|---|---|---|
| Defend | −6 | +1 | −6 |
| Attack | −4 | +3 | +5 |
| Pivot | +1 | −1 | +1 |

Nobody has a safe move, so this is the read. Rex's Pivot loses only to an Attack, and June's Attack is weak after her repeat. June bets Rex will Pivot away from her issue, attacks with her Zinger, and wins by 1 ×2: **+2.0 in Health's states**, crowd +2. Rex's countered Pivot costs him −0.5 in Safety's states. The crowd now reads Rex +4 going into round 3.

## 4. Flow, timers, budget

Debate week: **Intro** (Show, 3 s) → three × [**Round** (Input, 15 s; ends early once both lock in) → **Clash** (Reveal, 4 s)] → **Verdict** (Reveal, 5 s, skippable) → [Stance] → Plan. Deadlines are absolute `GetServerTimeNow()` values. A disconnect during a debate spends at most one grace use for the whole debate.

Per debate: 3 + 3 × 19 + 5 = 65 s worst (today 30 s). The old steps go 940 → 920 + 130 = **1,050 s** (the 17.5-minute line). The decision steps drop from 200 to 160 s at most. **True worst case: 1,210 s (20:10), against 1,140 s (19:00) today.** Typical: rounds lock in after about 7 s, so a debate is about 41 s against about 18 s today, roughly +46 s a match.

## 5. View, bots, candidates, screens, harness

- **View:** `view.debate` holds the week, round, topics, crowd, Zingers left, the board, the finished rounds and `yourMove` (your own pending move only). The board is `Debate.board`: each player's three strengths with their parts, the pivot issue, the ground, this round's counter. The opponent's pending move stays in `PlayerState.debateMove` until the clash.
- **Bots** (View only): Medium plays the move with the best worst-case cell (cells valued by the EV × closeness its map gives the landing states). It stakes the Zinger in the round where a likely win lands on the most valuable states, judging later topics by their facts, and in round 3 otherwise. Easy is random half the time. Hard best-responds to Medium's move from the opponent's side (`BOT_DEBATE_READ` 0.5). Extreme also blends in the opponent's past moves (`BOT_EXTREME_HISTORY` 0.5).
- **Hale:** Zinger ×3. If that tests too strong, the fallback is a different perk.
- **Screens:** the stage of revision 1 (mockups in `a5387c8`), with the buttons trimmed to "DEFEND 6 · vs D +4 · vs A +3 · vs P =", a "Why 6?" sheet for the parts, and a Zinger toggle that reads "Stake ⚡: win ×2".
- **Duel:** `defend|attack|pivot [zinger]`.
- **Harness targets:** debates change the winner 15–25%; every move 20–50% of Medium's picks; AlwaysDefend/Attack/Pivot each ≤ 45% against Medium; RandomMove ≤ 42%; candidates 45–55%; seat 1 rounds 49–51%.

## 6. Open questions (judgment calls)

1. Pivot's landing issue is automatic, to keep a round to one tap.
2. A split pays both sides +0.5.
3. Three rounds; a fourth would break the 1,050 s line.
4. Ground (+1) rewards the leader in the topic's states. That's a small snowball, and the comeback check watches it.
5. The debate stat (1 for everyone) is removed.
6. The "safe" tag shows only in your first debate of the session.
