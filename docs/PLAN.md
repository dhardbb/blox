# 270 — Roblox 1v1 Election Game: Build Plan for Opus

Oct 21, 2026 · @d · **Revision 2, Oct 22, 2026**

> **Revision 2** folds in the answers to the first-session review: blind draft rounds, public state leans, home-bonus cap, AR(1) poll noise, snapshot resolution, underdog cash rule cut, GOTV and attack changes, faster timers, and a revised candidate roster. Every change is logged with its reasoning in `docs/DESIGN.md` (D-001 to D-012). Where this doc and `Config.luau` disagree, `Config.luau` plus `DESIGN.md` win.

## How to use this doc

Export this doc as Markdown and paste the whole thing as the first message to Claude Opus 5.5 in Claude Code (cloud), with an empty GitHub repo attached. Everything from the next section onward is written to Opus. Have Opus commit it as `docs/PLAN.md` so later sessions can re-read it.

The ideas from the Instagram thread are folded in where they held up (state draft, poll noise, momentum rework, free polling, unlimited media, 4-player as a stretch goal). Nothing here is gospel: Opus is told to push back on anything that looks unfun, unbalanced, or technically risky before writing code.

Working title: **270**. Change it whenever.

## Mission and design pillars

You are building **270**: a 12–15 minute, turn-based, online 1v1 strategy game on Roblox where two fictional candidates fight over the US electoral map. It is inspired by iCivics' *Win the White House* but is a from-scratch competitive game, not a port. Two friends are building it with you; they will playtest in Roblox Studio and report back. You own the code.

Pillars, in priority order:

1. **Competitive first.** Every advantage comes from a decision with a trade-off. Information is imperfect but never unfairly random. Both players act simultaneously each week, so there is no first-mover advantage.
2. **Comebacks until the last week.** Leads are defended, not banked. Momentum decays, polls are noisy, and election day has variance.
3. **Readable in 60 seconds.** The map, the poll panel, and the resource bar tell the whole story at a glance. One plan timer, no sub-menus deeper than two taps.
4. **Replayable.** Asymmetric candidates, a drafted map every match, a seeded event deck with issue stances to learn, debates, and a practice bot that adapts.
5. **No teaching, no real politics.** Fictional candidates, generic issues, no real parties, people, slogans-as-quizzes, or policy positions. Must sit comfortably inside Roblox Community Standards for an all-ages audience.
6. **Server-authoritative.** The client is a renderer and an input device. Nothing it sends is trusted.

Non-goals: tutorials, quizzes, glossary, the original game's primary season, real-world political content, 3D gameplay (a 2D UI board is the game), voice chat.

## The source game and what changes

*Win the White House* is a single-player, 10-week campaign against a scripted opponent. Per its [teacher guide](https://cdn-educators.brainpop.com/wp-content/uploads/2019/11/2019-Guide_WtWH.pdf): each week you play action cards on states. Fundraising is free but only works in states where you already have support, and state cash pools slowly refill. Media costs $1 for one momentum boost; a personal appearance costs $1 for two boosts; both target an issue and can be positive or an attack on an opponent whose issues mismatch the state. Polling costs $1 and reveals a state's exact support, momentum, cash, and issues; unpolled states are gray. Momentum accumulates per state and eventually flips it. The primary is a quiz-style debate that earns your five issues, followed by a VP pick with a home state and skill. Most of that is single-player design and breaks in 1v1.

| Original mechanic | Why it fails in competitive 1v1 | What 270 does instead |
| --- | --- | --- |
| Primary quiz earns your issues | It's a lesson, not a decision | Cut. Character select + platform pick (3 of 8 generic issues, no right answers) |
| One media + one appearance per week | Money stops mattering once you have enough | Action points gate appearances; media is money-only with per-state saturation |
| Polling costs money and reveals exact numbers | In 1v1 nobody pays for info that also helps the opponent read the board | Public polls are free every week but noisy (±3); paid internal polls are exact and private |
| Momentum compounds forever | One early rally locks a state 8 weeks later; late game is dead | Momentum halves every week, is capped, and only nudges support; weeks 10–12 get a closing-argument bonus |
| Polls equal results | No tension on election night | Hidden true support, noisy polls, election-day variance, and a ground-game (GOTV) sink |
| Scripted AI opponent, alternating turns | Waiting is boring; first mover wins | Simultaneous hidden plans on a 50s timer, revealed and resolved together |
| Fundraise only where you have support; pools refill | Good idea | Keep. Yield scales with your support; pools regenerate 25%/week |
| Attack ads on mismatched issues | Good idea, no downside | Keep, add a backlash meter so spamming attacks eventually costs you |
| VP pick with home state and skill | Flavor | Folded into candidate perks; running mate is a stretch goal |
| Fixed map every game | Zero replayability | Seeded public state leans, strongholds that follow the leans, a blind draft of homes and battlegrounds, seeded events |
| Slogan picker | Cosmetic | Optional later; any free text must pass TextService filtering |

## Match flow

A full match runs about 12 minutes typical and at most about 17½ minutes (budget in `DESIGN.md` D-005). Every timed step auto-locks when the timer ends; a player can lock early, and the step ends when both have locked.

1. **Lobby.** Public queue, private match code, or practice vs the bot. Two players matched → a match instance starts in the same server (no teleport). Candidate, color and platform can be pre-picked in the lobby; rematch remembers them.
2. **Character and platform select (30s, one screen, simultaneous, hidden until both lock).** Pick a candidate, a player color (six options, none of them a party color pairing), and 3 of the 8 issues. Reveal both.
3. **Map reveal (5s).** The match's seeded state leans are shown, and with them each player's five strongholds: their strongest-leaning states (see Core mechanics → Draft; `DESIGN.md` D-044).
4. **State draft (3 blind rounds, 20s each, 2s reveal after each).** Round 0: home state. Rounds 1–2: one battleground nomination each. Each round both players secretly submit a ranked top 2; picks are revealed together after every round. Full rules in Core mechanics.
5. **Campaign, weeks 1–12.** Each week: *Plan* (50s, simultaneous, hidden: spend action points and money; the week card, meaning what the opponent did publicly, this week's event, and next debate's topics, sits in a side panel of the plan screen) → *Resolve* (8s animation: rallies, ads, fundraisers, momentum drift, new public polls; skips to 3s if both tap).
6. **Debates in weeks 4 and 9.** Prep points are allocated during the previous week's plan (prefilled 2/2/2); the debate resolves in a 10s sequence at the start of the week.
7. **Election night (45s, skippable if both skip).** Safe states called first, closest states last, EV counter ticking. 270 wins. Stats screen (flipped states, money raised, debate results, biggest swing), rating change, rematch and requeue buttons.

**Time bank.** Each player has 30s of extra plan time per match, taken in explicit 15s taps, visible to the opponent.

Disconnects: 30s grace, then the server auto-submits an empty plan (money banks, AP is lost). Two consecutive missed weeks is a forfeit. Each player gets at most two grace periods per match; after that a missed deadline auto-submits immediately. The opponent is told the moment the grace timer starts.

## Core mechanics

Every number below is a starting value and lives in `Config.luau` (collected in the Tunables section). The balance harness, not this doc, has the final say.

### Map

50 states + DC, 538 electoral votes using the 2024 apportionment, winner-take-all everywhere (Maine/Nebraska splits are a stretch goal). Each state record holds: EV, population weight, a fundraising pool (capacity in $), two top issues, a region, and an adjacency list (Alaska and Hawaii are reachable only by flight). All of it in `StateData.luau`. MVP rendering is a **node map**: one circle per state at its projected centroid, radius proportional to sqrt(EV), thin lines for adjacency, fill color blending the two players' public poll margin, a grey ring for undecided share. It is built entirely from UI frames so no art assets are needed. Put it behind a `MapInterface` so real state shapes can replace the nodes later.

### State support model

Each state tracks `support[playerId]` and `undecided`, which always sum to 100. Every state starts at 35 / 35 / 30 before leans and the draft. Store support keyed by player id in a list, never as `p1`/`p2` fields, so a 4-player mode is possible later.

```
gain(P, S, base) = base × issueMult × candidateMult × battlegroundMult × underdogMult × closingMult × saturation(P, S)
saturation(P, S) = clamp((SUPPORT_CAP − support[P]) / (SUPPORT_CAP − 35), 0.15, 1)   -- SUPPORT_CAP = 72
```

Positive gains draw 70% from undecided and 30% from the opponent while undecided ≥ 10; below that, 100% from the opponent. Attack-ad losses to the opponent go 60% to undecided and 40% to the attacker. Support never leaves \[0, 100\] and the three values are renormalized after every change.

**Simultaneous resolution (snapshot rule).** Each step of Resolve computes every player's effects from the same start-of-step snapshot and applies them together; no player's actions are ever applied first. Saturation, issue multipliers and fundraiser yield are all read from that snapshot. If two players fundraise in the same state in the same week, they split its pool in proportion to what each would have raised alone.

### Leans

Before the draft, each match seeds fictional state leans (never real-world partisanship) so the map has terrain:

- 30 of the 51 states get a lean of 2–6 points (integers), capped at 3 for states with 20+ EV.
- Mirroring: sort the leaned states by EV and walk them in pairs; each pair gets the same magnitude with opposite, randomly assigned sides. Reroll if the EV-weighted sum of leans exceeds 15 in either direction.
- A lean of L toward player P is applied as support[P] = 35 + L/2, support[other] = 35 − L/2, undecided 30.
- Leans are public and exact, shown on the map before the draft.
- A lean is terrain, not a draft bonus: battleground resets keep it.

### Draft

*Revised in D-044 (playtest: "a clear correct choice for both players"): strongholds are no longer drafted.* At the map reveal each player is given their five strongest-leaning states as strongholds (strongest lean first, then the bigger state), so both see them before any pick. Then three blind rounds, 20s each. Each round both players secretly submit a ranked top 2 legal states; both picks are revealed together after the round (2s), so every later round can react. If both players' first choices clash, the player with priority that round gets it and the other gets their second choice. If a player submits only one choice, the server fills the backup with the highest-EV legal state that matches their platform. Priority across the three rounds is A B B (A is chosen by the match seed): A wins a clash for the home, B for both nominations.

- **Home state** (round 0): +12 to the drafter in that state (+6 if the state has 20+ EV), and fundraisers there yield ×1.5 all game. A stronghold cannot be a home.
- **Strongholds** (assigned at the map reveal, five each): +8 in that state; +4 instead if the state has 20+ EV.
- **Battlegrounds** (rounds 1–2, one nomination each per round): a nominated state loses all draft bonuses (reset to 35 / 35 / 30 plus its lean), gets ×1.5 on every campaign effect for the whole game, and is marked on the map. Nominating an opponent's stronghold is the obvious play; nominating a neutral big state is the greedy one. A home state cannot be nominated.

All draft bonuses are applied before week 1 and the first public polls are then generated, so both players start with the same noisy picture.

### Resources

- **Money ($, in millions).** Start with $8. Passive income every week: $4 flat. Money banks. (The underdog cash bonus was cut; see `DESIGN.md` D-006.)
- **Action points (AP).** 3 per week. Use or lose; they do not bank.
- **Candidate location.** The candidate starts in the home state and ends each week wherever the last rally or fundraiser was.

### Weekly actions

A week's plan is a list of actions. Rallies and fundraisers form a **route**: each must be in the candidate's current state or a state adjacent to the previous stop; jumping anywhere else is a flight that costs $2 and no AP. Everything else is placed on any state.

| Action | Cost | Effect | Opponent sees |
| --- | --- | --- | --- |
| Rally | 1 AP (+ flight if not adjacent) | +3.0 base support in that state, +2 momentum; targets one issue | Yes, in the week card |
| Fundraiser | 1 AP (+ flight) | Raises min(pool, 2 + 6 × support share), drains the pool by that amount; pool refills 25% of capacity per week. Pool capacities are sized so no state (home included) can fund three fundraisers in one week. Perk and home multipliers apply after the pool cap and do not drain the pool | Yes (state, not amount) |
| Media buy | $3 | +1.6 base support, +1 momentum; targets an issue; positive or attack. Extra buys in the same state in the same week are worth 60%, then 36%, etc. | Yes, next week ("ads on air in OH") |
| Attack ad | $3 (a media buy flagged as attack) | −1.6 to the opponent (60% to undecided, 40% to you); earns no momentum; adds +1 to your backlash meter in that state. At 3+ backlash, each further attack there costs you −0.8 support and the meter resets. Meter decays 1 per week | Yes |
| Internal poll | $1 per state, or $3 for a region | Reveals true support ±1, true undecided, and both momentum values in that state for this week | No |
| Ground game (GOTV) | $2 per unit, max 4 units per state | Each unit adds +1.0 to your election-day margin in that state. Pays off only on election night | No |
| Platform pivot | 1 AP, once per match | Swap one platform issue; −1 national support spread across all states | Yes |

### Momentum

Momentum is recent buzz, not a bank. Per state per player:

```
momentum[P][S] = momentum[P][S] × MOMENTUM_DECAY + gainedThisWeek          -- decay 0.5, then clamp to [0, MOMENTUM_CAP = 6]
weeklyDrift(P, S) = min(DRIFT_RATE × max(0, momentum[P][S] − max over Q≠P of momentum[Q][S]), DRIFT_CAP)
                                                                         -- DRIFT_RATE = 0.6, DRIFT_CAP = 3
```

Only the player with the most momentum in a state drifts, by the gap to the runner-up. In 1v1 this is exactly `0.6 × (mA − mB)` capped at ±3; written this way it needs no change for 4-player mode. Drift is applied during Resolve after the week's direct effects and follows the same undecided/opponent split. A rally from 8 weeks ago contributes 2 × 0.5^8 ≈ 0.008 momentum, so the original game's "one appearance owns the state forever" problem is gone. Momentum is public: show it as small arrows on the node.

### Polling and information

- **Public poll, free, every week, every state:** shown margin = true margin + pollError(S), rounded; shown undecided = true + its own error term. Poll error is persistent, like a pollster's house effect: `error_t = ρ × error_{t−1} + √(1 − ρ²) × Gaussian(0, σ)` with ρ = 0.7 and σ = 3, so each week's error has the same ±3 spread but about 70% of it carries over. A 52–48 state can read 49–51 for two or three weeks with nothing having changed, and averaging old polls does not wash the error out. This is what makes "coasting on 52%" dangerous and what keeps internal polls worth buying.
- **National projection:** the EV count from public polls, shown to both. The true EV count is never sent to clients.
- **Internal poll:** see the table. This is the information economy: paying $1 to know whether Pennsylvania is really 51–49 or 55–45 is a real decision.
- **Opponent's money:** shown only as a bracket (Low < $4, Medium $4–10, High > $10). Opponent's AP spend is inferable from the week card.

### Platform and issues

Eight generic issues: Jobs, Health, Schools, Environment, Safety, Roads & Transit, Technology, Farms & Rural. Each state lists two top issues. Every rally and media buy targets an issue:

| Issue is... | Multiplier |
| --- | --- |
| In your platform and a top issue of the state | ×1.5 |
| A top issue of the state, not in your platform | ×1.2 |
| In your platform only | ×1.0 |
| Neither | ×0.8 |
| Attack on a state top issue the opponent's platform lacks | ×1.5 |

This keeps the original game's "match the message to the state" skill without any quiz. Expect the map data and both platforms to be the first thing a good player studies after the draft.

### Debates (weeks 4 and 9)

Three topics are drawn from the eight issues (seeded) and announced in the week card before the debate. During that week's plan, each player secretly allocates 6 prep points across the three topics, max 4 on one topic (prefilled 2/2/2).

```
topicScore(P) = prep[P][topic] + (2 if topic in platform[P]) + debateStat[P] + seededRandom(0..3)
```

Higher score wins the topic; an exact tie gives the topic to nobody. **Debates move states, not an average** (`DESIGN.md` D-040). Winning a topic adds `DEBATE_TOPIC_WIN` (1.0) support in every state where that topic is a top issue (fixed map data, the same every match) plus a flat `DEBATE_TOPIC_NATIONAL` (0.1) in every state. Losing a topic you put 0 prep on is a gaffe: `DEBATE_GAFFE` (0.6) lost in that topic's states. A 3–0 sweep adds a flat `DEBATE_SWEEP` (0.2) everywhere and +2 momentum in every battleground. Gains use the normal undecided/opponent split; losses go to undecided. Right after the debate the public polls are republished with the same error terms, so the map shows what the debate moved; the debate result carries every state's requested points (`moves`) and the states whose public-poll leader changed (`flips`), so the screen can say "your Jobs win swung OH, MI and PA; PA flipped to you (+19 EV)". Against the 0..3 roll a 2-point prep edge wins its topic 81% of the time and loses 6%; a 1-point edge wins 62%. No candidate's debate stat may exceed another's by more than 2. (Revision 1 had a 0..2 roll and national payoffs of 0.8 / 0.5 / −0.5; balance pass 1 cut them to 0.2 and widened the roll to 0..6, which made prep feel like noise; balance pass 2 set 0.3 per topic on a 0..3 roll; the issue-based pass replaced the national average with the state moves above: `DESIGN.md` D-019, D-033, D-040.)

### Events (Phase 5)

A seeded deck of 24 weekly events, shown at the start of Plan so both players can react; none in weeks 1 or 12; any single event is capped at ±2 points of effect per state. Four types: *Spotlight* (one issue ×1.3 nationwide this week), *Regional* (rallies in one region ×1.5), *Windfall* (fundraisers ×1.2 in states where you trail), and *Choice* (a dispute over one issue; each player secretly takes one of three stances and the states that care about that issue react). Private lobbies can toggle events off. The deck, the cap's exact meaning and the numbers are in `DESIGN.md` D-027 and D-039.

**Choice events are stance decisions** (`DESIGN.md` D-039). Each of the eight Choice events is about one issue and offers stances A and B (opposed) and C (the hedge). States where the event's issue is a top issue react by their *other* top issue: if the stance likes it, +`STANCE_POINTS` (1.5) support for you there; if it dislikes it, −1.5; otherwise +`STANCE_HEDGE` (0.5). Every other state hears a side a little through its own top issues: +`STANCE_SPILL` (0.5) per issue the stance likes, −0.5 per issue it dislikes. The hedge gives +0.5 in every state with the issue and nothing elsewhere. A candidate whose platform carries the issue is heard ×`STANCE_PLATFORM_MULT` (1.5, capped at the event cap) in the issue's states. The reactions come from fixed state data and your public platform, so the same event moves the same states the same way every match and the map previews every stance before you choose (`Events.stanceEffects`). The right answer depends on which of those states *you* need, so it differs per player and per map; both stances resolve simultaneously from one snapshot and are revealed with the week, with each state's requested points and the poll leaders they would flip. There is no payoff matrix and nothing to guess about the opponent (the D-036 matrix was removed: it read as random).

### Election night

```
finalMargin(S) = trueMargin(S) + Gaussian(0, σ = 2) + GOTV_PER_UNIT × (gotv[A][S] − gotv[B][S])   -- GOTV_PER_UNIT = 1.0
```

Winner takes the state's EV. 270 wins. A 269–269 tie goes to whoever won more states, then to the national popular vote (support × population weight). Results are revealed safe-states-first, closest-last, over about 45 seconds, skippable only if both players skip.

## Candidates (the character selector)

The character select replaces the original's primary. Eight fictional candidates, each with one perk that changes how you play and one drawback that keeps the perk honest. Names and portraits are placeholders; the humans may rename them. No candidate may resemble a real politician in name, likeness, or platform. Balance target: every candidate between 45% and 55% win rate in bot-vs-bot simulations and in the mirror-free human playtest log.

| Candidate | Archetype | Perk | Drawback |
| --- | --- | --- | --- |
| Dana Okafor | The Fundraiser | Fundraisers yield +25% (applied after the pool cap; the bonus does not drain the pool; D-023, D-037) | None (D-023) |
| Rex Calloway | The Barnstormer | 4 AP per week | Rallies +2.2 base instead of +3.0 ("more stops, smaller crowds"); media buys cost $4 |
| Priya Venkat | The Ad Wizard | Media buys cost $2; saturation steps are 65% / 42% (D-037) | Income $2 instead of $4 (D-023, D-037) |
| Marcus Hale | The Debater | 7 debate prep points instead of 6 (D-023, D-037) | Starts with no money |
| June Alvarado | The Insider | Starts with $18 | Passive income $3 instead of $4 |
| Tomas Reyes | The Insurgent | Underdog multipliers doubled; momentum gained +50% | Momentum keeps 25% per week instead of 50%; while leading by 40+ projected EV, rallies ×0.9 and fundraisers ×0.85 |
| Helen Strand | The Pollster | Sees next week's event a week early (her View alone carries it, D-035); two free internal polls per week | Media buys −10% (D-037) |
| Walt Begay | The Organizer | GOTV units cost $1 and cap at 6 per state | Rallies +2.4 base instead of +3.0 |

All eight have debate stat 1 and 6 prep points unless the table says otherwise. These are revision-2 values from a paper review (`DESIGN.md` D-011), except where a later entry is cited; `Candidates.luau` with `DESIGN.md` D-022, D-023 and D-035 has the current numbers, and the harness's 8×8 matchup matrix has the final say. Perks are data in `Candidates.luau` (a table of multipliers and overrides), not special-cased code, so adding a ninth candidate is a data change.

Presentation: each candidate is a Roblox avatar-style portrait built from a humanoid rig with a fixed outfit and color palette rendered to a ViewportFrame, so no uploaded images are required for MVP. Player color (six options: Crimson, Cobalt, Emerald, Amber, Violet, Teal) is picked separately so the two sides never read as real parties.

## Competitive balance and anti-snowball

The design has five anti-snowball levers and one rubber band; keep all of them tunable and keep the rubber band modest.

1. **Simultaneous turns.** No first-mover advantage in the campaign or the draft. Draft rounds are blind and simultaneous; clash priority follows A B B (D-044), and strongholds come from the mirrored leans, so neither seat gets better ones.
2. **Saturation cap.** `SUPPORT_CAP = 72` and the saturation multiplier make the last 10 points in a state cost 3–6× what the first 10 did. Piling onto a state you already own is a losing trade.
3. **Momentum decay and drift cap.** Decay 0.5, cap 6, drift ±3 per week. Early leads erode unless re-invested.
4. **Noise.** Poll σ 3 and election σ 2 mean a 52–48 state is a coin flip you cannot see; the counter is internal polls and GOTV, both of which cost money, which creates the spending decision.
5. **Closing argument.** Rallies and media in weeks 10–12 get ×1.15. Late game must matter at least as much as early game.
6. **Underdog rubber band (the only one).** Trailing by 40+ projected EV: fundraisers ×1.15, rallies ×1.10. Trailing by 100+: ×1.25 and ×1.20. Measured from public polls, so it is visible to both, but smoothed: the gap is an exponential average with weight 0.5 on the newest week, and a tier switches on at its threshold and only switches off once the smoothed gap falls 20 EV below it. One noisy poll cannot toggle it. There is no underdog cash bonus.

Variance budget. The only sources of randomness, all drawn from the per-match seed: draft priority (who is A), state leans, public poll noise, debate rolls (0–3 per topic), the event deck order, and election-day noise. Nothing else rolls dice. The same seed plus the same inputs must replay the same match exactly; this is also how replays, spectating, and regression tests work.

Required balance harness (`tests/harness/balance.luau`, run with Lune): play N bot-vs-bot matches (N = 2,000 should finish in under two minutes) and report per candidate win rate, the full 8×8 candidate matchup matrix, win rate by draft priority (A vs B), mean and median final EV margin, comeback rate (winner was trailing in true EV at week 8), average money unspent at the end, and distribution of game-deciding margins. Red flags that block a release: any candidate outside 45–55%, any matchup outside 40–60%, priority win rate outside 47–53%, comeback rate below 20% or above 40%, or more than 65% of matches decided by 40+ EV, a median margin over 60 EV, or more than 25% decided by 100+ EV (revised from "15% by 40+ EV", `DESIGN.md` D-024).

The harness also runs:

- **Dominance bots.** Bots that only fundraise, only rally, only attack, or never poll each play the balanced bot; each must win under 55%. A sandbag bot (never pads a state past true +4) must not beat the standard bot above 50%.
- **Map checks.** Tossup EV share (win probability 25–75%) after the draft and at the election (target ≤ 30% at the election); election-noise spread in EV (target ≤ 25); share of leaned states that flip during the campaign (target 20–40%); correlation between a side's leaned EV and its win rate (|r| < 0.05).
- **Rubber-band checks.** Share of underdog-bonus weeks whose beneficiary is truly ahead by 20+ EV (target < 10%); underdog tier changes per match (target ≤ 3 on average).
- **Mechanic impact.** Debates and GOTV each change the outcome in at least 10% of games; Choice stances change it in 5–25% and the bot that reads the map beats the same bot with random stances by 55% or more; per-candidate debate topic win rate; GOTV spend and election-night flips versus the week-12 projection.

The bot in `Bot.luau` must be decent, not optimal: weight states by EV × closeness × issue match, spend AP on a route through the nearest contested states, buy ads where saturation is low, poll the three closest big states, and bank GOTV money from week 9. It should beat a random-action bot 95% of the time and lose to a competent human most of the time.

## Technical architecture

One Rojo project, one Roblox place, many concurrent matches per server. The simulation is a pure Luau module with no Roblox APIs so it can be tested headlessly with Lune; the server wraps it, and clients only ever see the per-player `View`.

```
270/
  rokit.toml              -- pinned: rojo, lune, stylua, selene, luau-lsp
  default.project.json    -- Rojo tree (ReplicatedStorage.Shared, ServerScriptService.Server, StarterPlayerScripts.Client)
  wally.toml              -- only if a package earns its place
  CLAUDE.md               -- conventions, commands, rules below
  docs/PLAN.md            -- this document
  docs/DESIGN.md          -- decisions log: every mechanic/number change and why
  docs/TESTING.md         -- Studio playtest checklists per feature
  src/shared/
    Sim/
      Config.luau         -- every tunable, commented
      StateData.luau      -- 51 records: ev, popWeight, pool, topIssues, region, adjacency, centroid
      Candidates.luau     -- roster as data
      Issues.luau
      Rng.luau            -- seeded PRNG (xoshiro or PCG), Gaussian helper
      Match.luau          -- state machine: Select -> MapReveal -> Draft -> Week(n) -> Debate -> Election -> Done
      Plan.luau           -- plan schema + validation (AP, money, route adjacency, legal targets)
      Resolve.luau        -- weekly resolution in a fixed order: flights, rallies, fundraisers, media, pivots, momentum, drift, polls
      Debate.luau
      Events.luau
      Election.luau
      View.luau           -- builds what ONE player may see; the only exit for sim state
      Bot.luau            -- heuristic AI for practice mode and the balance harness
    Net/
      Remotes.luau        -- remote names + typed payloads
      Schemas.luau        -- runtime validation of every client payload
    Types.luau
  src/server/
    MatchService.luau     -- matchId -> Match; lifecycle; cleanup
    LobbyService.luau     -- public queue, private codes, practice-vs-bot
    TurnController.luau   -- deadlines, lock-ins, auto-submit, forfeit
    Replication.luau      -- sends View per player after each phase; never raw sim state
    DataService.luau      -- DataStore: rating, per-candidate W/L, last 10 matches; session-locked, retried
    Rating.luau           -- Elo, K = 32, start 1000
  src/client/
    App.client.luau       -- screen router
    Screens/              -- Lobby, Select (candidate + platform), Draft, Campaign, Debate, ElectionNight, Results
    Map/                  -- MapInterface.luau, NodeMap.luau (MVP), later ShapeMap.luau
    Components/           -- Button, Panel, Timer, Tooltip, StateCard, ActionTray
    Store.luau            -- client-side copy of the latest View + pending plan
  tests/
    sim/*.spec.luau       -- Lune unit tests
    harness/balance.luau
  .github/workflows/ci.yml -- selene, stylua --check, luau-lsp analyze, lune tests, rojo build -> artifact
```

Rules that are not negotiable:

- `Sim/` never references `game`, `Instance`, `task`, `os.time`, or any Roblox global. It takes (config, seed, inputs) and returns (newState, events). `--!strict` everywhere.
- The server validates every plan against the player's own `View` and the rules in `Plan.luau`. An invalid plan is rejected with a reason code; it never throws and never partially applies.
- True support, the opponent's plan before resolution, internal poll results, and GOTV units never leave the server. Add a test that serializes a `View` and asserts none of those fields are present.
- One server hosts up to 10 matches (player cap 20). Players in a match see only their match. The 3D world is a bare lobby room; the game is a `ScreenGui`.
- Timers: the server owns deadlines as absolute `workspace:GetServerTimeNow()` values; clients render countdowns from them. Lock-in is a remote; the server ends the phase when both lock or the deadline passes.
- UI is built with a thin component helper (or Fusion if you judge reactivity worth the dependency — justify it in DESIGN.md). Scale-based sizing, `UIListLayout`/`UIPadding` everywhere, touch targets at least 44 px, must work in 16:9 and in phone portrait.
- Any free text from players goes through `TextService:FilterStringAsync`. MVP has no free text.
- DataStore writes are session-locked, retried with backoff, and never on the hot path of a turn.
- Cross-server matchmaking via `MemoryStoreService` is Phase 6; the MVP queue is in-server.
- Content stays inside Roblox Community Standards: fictional candidates and issues only, no real-world political figures, parties, or policy positions.

## Working from Claude Code in the cloud

You cannot run Roblox Studio, so the project is organized so that most of the game is verifiable without it. Your loop is: write code and tests → run the toolchain → commit → the humans sync into Studio and playtest → they report back → you fix.

**Toolchain.** Install via [Rokit](https://github.com/rojo-rbx/rokit) from GitHub releases: Rojo (build and the Studio sync plugin), [Lune](https://github.com/lune-org/lune) (headless Luau runtime for tests and the harness), StyLua, Selene, and luau-lsp with the Roblox type definitions for `luau-lsp analyze`. Check current stable versions when you start and pin them in `rokit.toml`. If a download is refused in your environment, say so immediately; the humans will vendor the binaries.

**Commands** (put them in `CLAUDE.md`): `lune run tests` runs every spec and must pass before any commit; `lune run tests/harness/balance.luau` prints the balance report; `rojo build -o build/270.rbxl` must succeed; `selene src && stylua --check src && luau-lsp analyze src` must be clean. CI runs all four and attaches the `.rbxl` as an artifact.

**Handoff to the humans.** Each feature ships as one commit or PR with: a `CHANGELOG` entry, the `TESTING.md` checklist for that feature (what to click in Studio, what should happen, what to screenshot), and any asset IDs or settings you need from them. They open the `.rbxl` or sync with the Rojo plugin, test with Studio's *Start Server + 2 Players*, and reply with the output log and screenshots. Their local clone lives at `~/Documents/Code/270/`.

**Because you cannot see the UI:** build it defensively. Every screen gets a `DEBUG_UI` mode that renders with placeholder data from a fixture, logs each container's `AbsoluteSize` at startup, and fails loudly if any text label is truncated or any button is under 44 px. Prefer layouts that cannot overlap (list layouts, aspect constraints) over absolute positioning.

**Because you cannot look up API names in Studio:** use the official docs at create.roblox.com/docs for every Roblox API you touch, and let `luau-lsp analyze` with Roblox definitions catch typos before the humans do. Do not invent service methods.

**Optional, later:** if the humans add a Roblox Open Cloud API key as a repo secret, CI can publish the built place to a private test place through the Open Cloud place-publishing API, so playtesting needs no manual upload.

## Build phases

Build the game inside-out: simulation first, networking second, UI third. Each phase ends with tests green, `TESTING.md` updated, `DESIGN.md` updated, and a build the humans can open. Do not start a phase's UI before its sim logic has tests.

| Phase | Scope | Definition of done |
| --- | --- | --- |
| 0 Scaffold | Toolchain pinned, Rojo project, CI, `CLAUDE.md`, docs committed | `lune run tests` passes a smoke test; `rojo build` produces a `.rbxl`; CI green on `main` |
| 1 Simulation core | `Config`, `StateData`, `Rng`, `Match` state machine, draft, plans + validation, weekly resolve, momentum, polling `View`, election, bot | 40+ specs; invariants tested (support sums to 100, caps, determinism by seed, `View` leaks nothing hidden); bot vs bot completes a match; harness runs 500 matches in under 60 s |
| 2 Server and networking | `MatchService`, in-server `LobbyService`, `TurnController`, `Replication`, payload validation, disconnect handling | Two Studio clients finish a full match through a debug text UI; a malformed or cheating payload is rejected and logged |
| 3 Client MVP | Lobby, Select, Platform, Draft, Campaign screen (node map, action tray, route builder, poll panel, timer, resolve animation), Election Night, Results | A tester who has never seen the game finishes a match unprompted; works in 16:9 and phone portrait; `DEBUG_UI` fixtures for every screen |
| 4 Depth | Debates, candidate perks fully wired, internal polls, GOTV, attack backlash, practice-vs-bot mode | Harness shows all 8 candidates in 45–55%; debate and GOTV each change outcomes in at least 10% of harness games |
| 5 Replayability and retention | Event deck, rating + DataStore, per-candidate stats, rematch, private match codes, sound and animation polish (humans supply any asset IDs) | Rating persists across sessions; events toggle works; a full match feels finished, not prototyped |
| 6 Balance and scale | Balance pass from harness + human playtest log, cross-server queue via `MemoryStoreService`, first stretch goals | Release checklist in `TESTING.md` fully green; no red flags in the harness report |

## Starting tunables

Every value here goes in `Config.luau` with a one-line comment. They are first guesses; the harness and playtests change them, and every change gets a line in `DESIGN.md`.

| Key | Value | Notes |
| --- | --- | --- |
| WEEKS | 12 | Debates at 4 and 9 |
| AP\_PER\_WEEK | 3 | Use or lose |
| START\_CASH | 8 | $ millions |
| PASSIVE\_INCOME | 4 | Per week, flat (underdog cash cut) |
| BASE\_SUPPORT | 35 / 35 / 30 | Player A / Player B / undecided |
| SUPPORT\_CAP | 72 | Saturation ceiling |
| SATURATION\_FLOOR | 0.15 | Minimum multiplier near the cap |
| LEAN\_STATE\_COUNT / LEAN\_MIN / LEAN\_MAX | 30 / 2 / 6 | Seeded, public, pair-mirrored |
| LEAN\_BIG\_STATE\_CAP / LEAN\_MAX\_EV\_IMBALANCE | 3 / 15 | Cap for EV ≥ 20; reroll threshold on Σ EV × lean |
| HOME\_BONUS | 12 | 6 if EV ≥ 20; plus fundraiser ×1.5 at home |
| STRONGHOLD\_BONUS | 8 | 4 if EV ≥ 20 |
| BATTLEGROUND\_MULT | 1.5 | All effects in nominated states |
| RALLY\_SUPPORT / RALLY\_MOMENTUM | 3.0 / 2 |  |
| MEDIA\_COST / MEDIA\_SUPPORT / MEDIA\_MOMENTUM | 3 / 1.6 / 1 |  |
| MEDIA\_SATURATION | 0.6 | Geometric per extra buy in the same state and week |
| ATTACK\_LOSS / ATTACK\_MOMENTUM | 1.6 / 0 | 60% to undecided, 40% to attacker; attacks earn no momentum |
| BACKLASH\_THRESHOLD / BACKLASH\_PENALTY / BACKLASH\_DECAY | 3 / 0.8 / 1 | Per state |
| FLIGHT\_COST | 2 | $ for a non-adjacent hop |
| FUNDRAISER\_BASE / FUNDRAISER\_PER\_SHARE | 2 / 6 | Yield = min(pool, 2 + 6 × share) |
| POOL\_REFILL | 0.25 | Fraction of capacity per week |
| INTERNAL\_POLL\_COST / REGION\_POLL\_COST | 1 / 3 |  |
| GOTV\_COST / GOTV\_PER\_UNIT / GOTV\_MAX\_UNITS | 2 / 1.0 / 4 |  |
| PIVOT\_PENALTY | 1 | National, once per match |
| MOMENTUM\_DECAY / MOMENTUM\_CAP / DRIFT\_RATE / DRIFT\_CAP | 0.5 / 6 / 0.6 / 3 |  |
| POLL\_SIGMA / POLL\_RHO / ELECTION\_SIGMA | 3 / 0.7 / 2 | Poll error is AR(1) |
| ISSUE\_MULT | 1.5 / 1.2 / 1.0 / 0.8 | Platform+state / state only / platform only / neither |
| DEBATE\_PREP / DEBATE\_MAX\_PER\_TOPIC | 6 / 4 |  |
| DEBATE\_TOPIC\_WIN / DEBATE\_TOPIC\_NATIONAL / DEBATE\_SWEEP / DEBATE\_GAFFE | 1.0 / 0.1 / 0.2 / 0.6 | Support points: in the topic's states / in every state / flat for a sweep / lost in the topic's states (D-040) |
| STANCE\_POINTS / STANCE\_HEDGE / STANCE\_SPILL / STANCE\_PLATFORM\_MULT | 1.5 / 0.5 / 0.5 / 1.5 | Choice stances: liked or disliked state / hedge or indifferent state / other states per liked or disliked issue / heard harder on your platform (D-039, D-041) |
| CLOSING\_MULT / CLOSING\_FROM\_WEEK | 1.15 / 10 |  |
| UNDERDOG\_EV\_1 / UNDERDOG\_EV\_2 | 40 / 100 | Thresholds in projected EV |
| UNDERDOG\_MULTS\_1 / UNDERDOG\_MULTS\_2 | 1.15 fund, 1.10 rally / 1.25, 1.20 |  |
| UNDERDOG\_SMOOTHING / UNDERDOG\_HYSTERESIS | 0.5 / 20 | EMA weight on newest week; EV below threshold to leave a tier |
| EVENT\_CAP | 2 | Max points from one event |
| TIMER\_SELECT | 30 | Candidate, color and platform on one screen |
| TIMER\_MAP\_REVEAL | 5 | Leans shown before the draft |
| DRAFT\_ROUNDS / TIMER\_DRAFT\_ROUND / DRAFT\_REVEAL | 3 / 20 / 2 | Blind, ranked top 2: home, then two nominations (D-044) |
| STRONGHOLD\_COUNT | 5 | Assigned at the map reveal: each player's strongest-leaning states (D-044) |
| DRAFT\_PRIORITY | A B B | Clash priority per round |
| TIMER\_PLAN / TIME\_BANK / TIME\_BANK\_CHUNK | 50 / 30 / 15 | Seconds; bank is per player per match |
| TIMER\_RESOLVE / TIMER\_RESOLVE\_SKIPPED | 8 / 3 | Both players tap to skip |
| TIMER\_DEBATE / TIMER\_ELECTION | 10 / 45 | Election skippable if both skip |
| DISCONNECT\_GRACE / GRACE\_USES / FORFEIT\_MISSED\_WEEKS | 30 / 2 / 2 |  |
| ELO\_K / ELO\_START | 32 / 1000 |  |
| MATCHES\_PER\_SERVER | 10 | Player cap 20 |

## Stretch goals (after Phase 6)

None of these are in scope until the 1v1 game is balanced and finished, but several cost nothing to prepare for now, so the architecture notes are binding.

- **4-player free-for-all with elimination.** Four candidates run at once; anyone under 5% national true support at the end of a week drops out and their voters return to undecided; play continues until two remain, then the normal election. Prepare now: support is keyed by player id, the draft and `View` take a player list, and nothing assumes two sides.
- **Spoiler seat.** A third player who cannot win the presidency but wins their own objective (for example, finish above 5% nationally or deny either major candidate 270). Prepare now: win conditions are per-player objects, not a single global check.
- **Real state shapes.** The humans upload state decals; `ShapeMap.luau` implements `MapInterface` with image buttons. Maine and Nebraska district splits come with it.
- **Running mate.** A second pick at character select that adds a second home state and a minor perk.
- **Replays and spectating.** Seed + input log replays a match exactly; a spectator `View` with no fog after the match ends.
- **Ranked seasons and cosmetics.** Seasonal rating resets, candidate skins, map themes, a daily seeded challenge against the bot with a leaderboard.
- **Custom lobbies.** Toggle events, 8/12/16-week lengths, timer length, draft variants (sequential snake draft, auction draft).

## Your first session

*Status (Oct 22, 2026): steps 1–4 done. Phase 1 (simulation core) is complete: match state machine, draft, plans, resolve, View with the no-leak test, election, bot, and the balance harness. First harness results and open balance questions are in `DESIGN.md` D-017. Phase 2 (server and networking, debug text UI) is built and awaiting a Studio playtest (`TESTING.md` → Phase 2). See `CHANGELOG.md`.*

Do these in order and stop after step 1 for answers.

1. **Read everything above, then write back** a summary of the game in your own words (300 words max) and up to eight numbered questions or pushbacks. Flag specifically anything you believe is unfun, unbalanced, exploitable, or technically risky, and propose the alternative. Wait for the humans' answers before writing code.
2. **Confirm the environment.** Check current stable versions of Rokit, Rojo, Lune, StyLua, Selene, and luau-lsp; verify GitHub release downloads work from your sandbox; report anything blocked.
3. **Phase 0.** Scaffold the repo exactly as laid out in Technical architecture. Commit this document as `docs/PLAN.md`, start `docs/DESIGN.md` with a decisions log, and write `CLAUDE.md` with the commands, the non-negotiable rules, and the commit conventions. Get CI green.
4. **Phase 1, in this order:** `Rng` with tests → `StateData` with a test that EV sums to 538 and every adjacency is symmetric → `Config` → `Match` state machine → draft → plan validation → weekly resolve → `View` with the no-leak test → election → `Bot` → a full bot-vs-bot match test → the balance harness. No UI until the harness runs.
5. **Ask for what you need in one list, not drip-fed:** Roblox group or place IDs, asset IDs for sound and icons, an Open Cloud key if they want CI publishing, and the Discord or Slack channel for bug reports.

Ground rules for every session afterward: do not ask permission for anything this doc already decides; do ask before changing a mechanic's intent; prefer boring, strictly typed code over clever code; small commits with descriptive messages; every number lives in `Config.luau`; keep a full match at or under 15 minutes; when you change a number, say why in `DESIGN.md`; when the humans report a bug, write the failing test first.
