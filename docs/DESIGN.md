# Design decisions log

Every change to a mechanic or number, and why. Newest last. A decision that changes a mechanic's *intent* needs the humans' OK first (noted as "Approved"); pure tuning does not but is still logged here.

Format: **D-NNN — title** (date, status). What changed, why, and how the harness checks it.

---

## Revision 2: first-session review (Oct 22, 2026)

Paper review of `docs/PLAN.md` revision 1 by the lead designer (Claude), plus four independent design reviews (draft/timing, leans, underdog income, candidates) with small Monte Carlo models. All approved by the humans on Oct 22, 2026. Every number here is a starting value until the balance harness runs.

### D-001 — Snapshot resolution (approved)

Each Resolve step computes all players' effects from one start-of-step snapshot and applies them together. Saturation, issue multipliers and fundraiser yield read the snapshot. Two fundraisers in the same state and week split the pool in proportion to what each would have raised alone.

*Why:* with simultaneous plans, any "apply A then B" order hands one player a structural edge (B's saturation would be computed after A's gains). *Check:* a spec swaps the player order of identical plans and asserts mirrored results.

### D-002 — Persistent poll error, AR(1) (approved)

Public poll error per state follows `e_t = 0.7 e_{t−1} + √(1−0.49) · N(0, 3)`. The spread each week is still σ 3.

*Why:* with fresh noise each week, averaging four weeks cut the error to about ±1.5. That rewarded keeping a spreadsheet and made $1 internal polls nearly worthless. Persistent error behaves like a real pollster's house effect. *Check:* per-candidate win rate for Helen Strand and the never-poll dominance bot.

### D-003 — GOTV is worth +1.0 per unit (was +0.5) (approved)

*Why:* at +0.5, $8 of GOTV bought +2 election-day margin, while $9 of media bought about +3 lasting margin plus momentum, so GOTV was strictly worse. At +1.0 it is roughly at par with media per dollar, and it is hidden, immune to poll noise, and never saturates. *Check:* GOTV changes the outcome in ≥ 10% of harness games; Walt Begay stays within 45–55%.

### D-004 — Attack ads earn no momentum (approved)

*Why:* an attack moved the margin about 2.24 against about 2.08 for a positive ad, and it ignored the attacker's own saturation. Removing momentum makes attacks a situational tool, not the default. *Check:* the attack-only dominance bot wins < 55% against the balanced bot.

### D-005 — Match flow and timers (approved)

- Character, color and platform are picked on one 30s screen (was 45s + 30s); they can be pre-picked in the lobby, and rematch remembers them.
- Draft: 8 blind rounds × 20s + 2s reveal (was 16 sequential picks × 20s). See D-007.
- Plan timer 50s flat (was 60s), plus a per-player 30s time bank taken in visible 15s taps.
- The week card moves into a side panel of the plan screen (was its own step).
- Resolve skips to 3s if both players tap; election night is skippable if both skip.
- Debate prep is prefilled 2/2/2.
- Each player gets at most two disconnect grace periods per match.

*Why:* revision 1 timed out at about 16½ min typical and 22½ min worst case, over the 15-minute target. Budget (the slower player sets the pace; players use 60/70/80% of the plan timer in weeks 1–4/5–8/9–12):

| Format | Typical | Worst |
|---|---|---|
| Revision 1 | 16:24 | 22:38 |
| First proposal (8 blind rounds, 45s plan, 60s bank) | 13:18 | 19:14 |
| **Revision 2** | **12:13** | **17:22** |

Worst case = 30 select + 176 draft + 5 map reveal + 600 plan + 60 bank + 96 resolve + 20 debates + 45 election + 10 transitions = 1,042s. Shorter plans in weeks 1–3 were rejected: week 1 is when players read the drafted map, and early lock-in already saves that time. *Check:* the server logs per-phase durations; the playtest log tracks real match length.

### D-006 — Underdog cash bonus cut; multipliers smoothed (approved)

Removed `UNDERDOG_INCOME_PER_10`; passive income is a flat $4. The underdog rally and fundraiser multipliers stay but key off a smoothed projected-EV gap (EMA weight 0.5 on the newest week), with 20 EV of hysteresis.

*Why:* national margins never reach 10 points, so the original rule paid $0. The proposed replacement ($0.5 per 20 EV behind, cap $2) paid someone in about 85% of weeks, averaging 33% of passive income. About 14% of those dollars went to the player who was truly ahead by 20+ EV, because projected EV swings 40+ on noise alone in about half of all weeks. Stacked on the multipliers it gave a 100+ EV trailer about +63% resources. *Check:* comeback rate stays 20–40% (if it drops below 20%, raise the tier-1 fundraiser multiplier to 1.25 before bringing cash back); < 10% of bonus-weeks go to a true 20+ EV leader; ≤ 3 tier changes per match; the sandbag bot doesn't beat the standard bot.

### D-007 — Blind simultaneous draft (approved)

Each of 8 rounds: both players secretly submit a ranked top 2; reveal after every round; on a first-choice clash the priority player wins and the other gets their second choice. Priority order A B B A B A A B (Thue–Morse), A chosen by seed. A missing backup is auto-filled with the highest-EV legal state matching the player's platform.

*Why:* halves draft time, removes waiting, and fits the "simultaneous, no first mover" pillar. Revealing after every round keeps the between-round reactions (seeing the opponent's home before picking strongholds). Denial becomes a priority-settled guessing game instead of a guarantee. Nominations are cleaner blind, because each side mostly nominates from the other's public strongholds. Hybrid formats (sequential strongholds) cost 200s for little gain. *Check:* priority-A vs priority-B win rate within 47–53% (replaces "draft-order win rate").

### D-008 — Seeded public state leans (approved)

30 states get a lean of 2–6 points (capped at 3 for EV ≥ 20). Leans are paired by EV with opposite random signs, rerolled if |Σ EV·lean| > 15, applied as ±L/2 to the two candidates, public and exact before the draft. Battleground resets keep the lean. No regional clustering in v1.

*Why:* with every undrafted state at exactly 35/35, a model found 66% of EV still a coin flip on election night, the expected-EV leader losing 42% of equal-bot games, and a "solved" draft (everyone takes the same six 16–19 EV states). With leans, tossup EV drops to about 25% and election-noise spread from about 33 to about 24 EV. ±1–3 leans barely help (43% tossup); ±4–10 become locks. Hidden or noisy leans would make the blind draft a lottery, and week-1 polls would leak them anyway. Issue-intensity variation was rejected because it never moves an untouched state off 50/50. *Risks:* narrowing the fight to 8–15 states ("only Ohio matters"); seeds that hand one side better issue matches. *Check:* tossup EV ≤ 30% at the election; noise spread ≤ 25 EV; 20–40% of leaned states flip during the campaign; |r| < 0.05 between a side's leaned EV and its win rate. Clustering is a later harness variant.

### D-009 — Home bonus +6 for states with 20+ EV (approved)

*Why:* with the home bonus uncapped and homes immune to nomination, first pick took the 54-EV state; first pick won 57.7% in the leans model. This mirrors the existing stronghold rule (+4 at 20+ EV). *Check:* priority win rate (D-007).

### D-010 — Rules clarifications (tuning)

- **Momentum drift for N players:** only the player with the most momentum in a state drifts, by `0.6 × (gap to the runner-up)`, capped at 3. Identical to the revision-1 formula in 1v1; needs no change for 4-player mode.
- **"National" debate shifts are averages:** a shift of X moves each state by X × undecided ÷ (population-weighted mean undecided). Reviewers found the original wording could be read two ways, roughly a 50× difference in debate value.
- **Debate ties:** an exact topic-score tie gives the topic to nobody.
- **No debate stat may exceed another candidate's by more than 2.**

### D-011 — Candidate roster revisions (approved)

Values were estimated in contested-state margin points (MP), where 1 AP ≈ 6 MP ≈ $6 of media.

| Candidate | Rev 1 net | Change | Est. net after |
|---|---|---|---|
| Marcus Hale | +51 (87% topic win rate) | Debate stat 2 (was 3), 6 prep (was 8), start $4 (was $5) | ≈ +15 (≈ 65% topic win rate) |
| Rex Calloway | +38 | Keep 4 AP and $4 media; rallies 2.2 base (was 3.0) | ≈ +5 |
| Tomas Reyes | +28 (drawback was a net gain) | Momentum keeps 25%/week (was 35%); frontrunner band: leading 40+ EV → rallies ×0.9, fundraisers ×0.85 | ≈ baseline drift, burstier |
| Helen Strand | +15 | 2 free polls/week (was 3); media −10% (was −15%) | ≈ +10 |
| June Alvarado | −4, perk invisible | Start $18 (was $14) | ≈ +1 |
| Priya Venkat | +7, but 94% debate losses vs old Marcus | 6 prep (was 5); stat stays 0 | ≈ +7 |
| Dana Okafor | +13 | +30% applied after the pool cap, doesn't drain the pool | unchanged |
| Walt Begay | +4 after D-003 | none | +4 |

*Rejected:* Rex at 4 AP only in odd weeks (still +17), and Rex trading income for AP ($24 ≈ 24 MP, not enough). *Check:* full 8×8 matchup matrix, every pair in 40–60%, every candidate 45–55%; per-candidate topic win rate; Helen tested against both the standard bot and a non-polling bot (her value depends on how often opponents poll); Tomas's share of weeks in the underdog bands.

### D-012 — Fundraiser pool sizing and harness additions (approved)

- Pool capacities are set so no state, home included, can fund three fundraisers in one week. *Why:* one fundraiser AP raised about $5, which bought about 1.7 media buys placeable anywhere, beating a route-bound rally.
- Harness additions: dominance bots (fundraise-only, rally-only, attack-only, never-poll; each < 55% vs balanced), a sandbag bot, the 8×8 matrix, map checks (D-008), rubber-band checks (D-006).

---

## Technical decisions

### D-013 — Toolchain and code layout (Oct 22, 2026)

- **Shared code uses string-path `require` ("./Rng").** Roblox's `require` reference confirms require-by-string (`./`, `../`, `@self/`, `@game/`), and Lune resolves the same paths, so Sim modules run unchanged in both. No darklua step. Only tests use `.luaurc` aliases (`@sim`, `@shared`, `@testlib`); game code never does.
- **Two Selene configs:** `selene.toml` (Roblox std) for all game code, and `selene.sim.toml` (plain Luau) for `src/shared/Sim` and `tests`, so the linter itself rejects Roblox globals in the simulation. `tests/sim/Purity.spec.luau` additionally bans `os.*`, `task.*`, `math.random`, `Random.new`, `tick()`, `wait()` and requires `--!strict` in every Sim module.
- **In-house test framework** (`tests/lib/Test.luau`, ~150 lines of describe/it/expect) instead of a package: no Wally dependency, and it runs on plain Lune.
- **Toolchain install:** `rokit install` normally; `scripts/bootstrap.sh` falls back to building from crates.io when GitHub release downloads are blocked (the Claude cloud sandbox as of Oct 22, 2026). luau-lsp is not on crates.io, so type checking runs in CI only there.
- **Replays are bit-exact per runtime only:** Gaussian draws use `math.log`/`math.cos`, which may differ in the last bit between platforms. Replays and determinism tests compare within one runtime.

## Phase 1: simulation core

### D-014 — Map data conventions (Oct 22, 2026)

- **Regions are the nine US Census divisions** (renamed: New England, Mid-Atlantic, Great Lakes, Plains, South Atlantic, Deep South, South Central, Mountain, Pacific), not the four Census regions. *Why:* the $3 region poll and Regional events need groups of comparable size; the four-region split puts 17 states in the South.
- **Adjacency is shared land borders only.** Water-only neighbors (MI–MN, NY–RI) and the Four Corners point contacts (AZ–CO, UT–NM) are excluded, DC borders MD and VA, and Alaska and Hawaii have no neighbors (flight only). *Why:* a rule a player can check by looking at a map.
- **Top issues are generic game data,** balanced so each issue is a top issue for 100–170 EV (current spread 106–160). Texas uses Farms instead of Technology to keep Technology from covering 180 EV. A spec enforces the band.
- **Fundraising pools are derived, not stored:** capacity will be computed in `Config.luau` from state population (the next step), so pool tuning stays in one file.

### D-015 — Pool capacity formula; POOL_MAX 14 → 12 (Oct 22, 2026, tuning)

Capacity = min(`POOL_MAX`, `POOL_BASE` + `POOL_PER_MILLION` × population), computed by `Config.poolCapacity`. `POOL_MAX` drops from 14 to 12; only Texas (13.3) and California (14) change.

*Why:* D-012 says no state, home included, may fund three fundraisers in one week. The smallest yield is 2 + 6 × 0.35 = 4.1 at starting support, so three need 12.3. At 14, a California home (41% support, 4.5 per fundraiser) could fund three. *Check:* `tests/sim/Config.spec` asserts every capacity is below three starting-support yields.

### D-016 — Rules clarifications from implementing the sim (Oct 22, 2026, tuning)

Places where `PLAN.md` left a choice open. None changes a mechanic's intent; flag any that feel wrong in playtests.

- **Draft bonuses** (home, stronghold) are applied after the last draft round through the normal gain split (70% from undecided, 30% from the opponent), with no saturation or multipliers. A +12 home moves the margin by 15.6.
- **Draft auto-fill** never nominates the player's own stronghold.
- **Battleground ×1.5** applies to the support effects of rallies, media buys and attacks. It does not apply to fundraising, momentum or drift.
- **Attack issue multiplier:** ×1.5 on a state top issue the target's platform lacks, otherwise ×0.8. An attack is never worth more than the "mismatch" case, so it stays a situational tool (D-004).
- **Repeat media buys** (positive and attack share one sequence per player, state and week) scale both support and momentum by 0.6^(k−1).
- **Backlash:** an attack made while the meter is at 3+ costs the attacker 0.8 support and resets the meter to 0; otherwise it adds 1. The meter decays by 1 at the end of each week.
- **Money timing:** a plan's costs are paid at the start of Resolve; fundraiser money and passive income arrive at the end. Week 1 is planned with the starting cash only.
- **Internal polls** report the truth at the end of the week they were bought, alongside the new public polls. Support is within ±1 (zero-sum offsets, one decimal); undecided and momentum are exact.
- **Rubber band timing:** tiers and Tomas's frontrunner flag are computed from each week's new public polls and apply to the next week. The frontrunner flag uses the same smoothed lead, without hysteresis.
- **National shifts:** positive ones (debate wins) use the normal gain split; negative ones (pivot, gaffe) go to undecided. Debates do not trigger a new poll; their effect appears in the next weekly poll.
- **Colors** are unique per match; on a clash a seeded order decides and the other player gets the first free color.
- **Noise for N players:** poll error and election noise are zero-sum per-player components with sd σ/√2, which is exactly the margin formula in 1v1 and needs no change for 4-player mode.
- **What a player sees of their own hidden data:** their own GOTV units, internal poll results, backlash meters and fundraiser yields are in their `View`. Opponents' are not. Pool levels are hidden from everyone, because a pool's drop reveals the fundraiser's true support.

### D-017 — Bot heuristics and the first harness baseline (Oct 22, 2026, no Config changes)

**Bot.** It plays from its own `View` only. A state is worth `EV × pdf(margin/σ)/σ` per point of margin: expected EV per point, so big close states matter most. σ combines poll error (or ±1 after an internal poll), election noise, and 2 points of variance per week left. AP goes greedily to the best rally or fundraiser on the route, then money goes to the best media buy, attack or (from week 9) GOTV unit per dollar. The bot buys one paid internal poll a week from week 4, of the closest big state. A dollar is valued at 0.4 × the best media buy per dollar: at 1.0 the bot over-fundraised and lost 82% to the rally-only bot, and at 3 polls a week it lost 69% to the never-poll bot. Bot tunables live in `Bot.tuning`, not `Config`, because they aren't gameplay numbers.

**Baseline, 2,000 matches, default Config** (`lune run tests/harness/balance.luau`, 67 s including side checks):

| Check | Result | Target |
|---|---|---|
| Candidates | Okafor 49, Calloway 52, **Venkat 20**, **Hale 89**, Alvarado 46, Reyes 53, Strand 55, **Begay 37** | 45–55% |
| Worst matchup | Venkat vs Hale 3% | 40–60% |
| Priority A win rate | 51.4% | 47–53% ✓ |
| Comeback rate | 25.3% | 20–40% ✓ |
| Decided by 40+ EV | **80.5%** (median margin 108 EV) | ≤ 15% |
| Tossup EV at election / noise spread | 10.3% / 16.6 EV | ≤ 30% / ≤ 25 ✓ |
| Leaned states that flip / lean–win correlation | 30.4% / −0.03 | 20–40% / \|r\| < 0.05 ✓ |
| Underdog bonus to a true 20+ leader / tier changes | 8.9% / **4.1 per match** | < 10% ✓ / ≤ 3 |
| GOTV changes the winner | **1.8%** (bots spend ~$3 each) | ≥ 10% |
| Debates change the winner | 49.6% | ≥ 10% ✓ (but see below) |
| Random bot / fundraise-only / rally-only / attack-only / never-poll / sandbag vs balanced | 0 / 4 / 46 / 45 / 53 / 42% | ≤ 5, < 55, ≤ 50 (sandbag) ✓ |

**Variant runs (500 matches each):**

| Variant | Hale | Venkat | 40+ EV |
|---|---|---|---|
| Defaults | 88% | 17% | 80% |
| Debates off | 53% | **77%** | 56% |
| `DEBATE_TOPIC_WIN` 0.3, `SWEEP` 0.2, `GAFFE` 0.2 | 82% | 41% | 66% |
| Same, plus `LEAN_STATE_COUNT` 50 | 72% | 50% | 60% |

**Findings, for the humans** (no numbers were changed; these need a decision). *Acted on in balance pass 1, D-018 to D-025.*

1. **Debates decide too much, and the debate stat decides debates.** Hale's +1 stat wins 64% of topics and Venkat's −1 loses 83%. A national shift moves every state at once, including the ~20 unleaned states that start exactly 35/35, so 0.8 points per topic swings many states together. Even at 0.3 per topic Hale wins 82%. Options: (a) keep debate stats equal and make Hale's perk something else (extra prep points, say); (b) apply debate shifts only to battlegrounds and states within ±5 in the polls; (c) cut `DEBATE_TOPIC_WIN` to about 0.3 and narrow the stat gap to 1.
2. **Priya Venkat's cheap media is the strongest perk once debates are neutral** (77% with debates off). Her debate-0 drawback is currently doing all the balancing.
3. **Blowouts.** Even without debates, 56% of matches end 40+ EV apart. The "≤ 15% decided by 40+ EV" target may not be reachable with winner-take-all and correlated national swings. It needs either a model change (all 51 states leaned, or smaller national effects) or a looser target.
4. **GOTV rarely matters (1.8%) and Walt Begay is at 37%.** Partly the bot (it values GOTV conservatively), partly that blowout margins dwarf a few GOTV points. Revisit after 1 and 3.
5. **Underdog tiers flip 4.1 times a match** (target ≤ 3). Projected EV swings because many states poll near 50–50. Raising `UNDERDOG_HYSTERESIS` from 20 to 30 is the obvious tuning knob.
6. **The "debates change the winner" metric is confounded.** In a paired replay with debates off, the bots react to a different board, so the two matches diverge. A 0.3-point debate still "changes" about 50% of winners, which is mostly chaos. Replace it with a counterfactual that removes only the debates' support deltas from the final state.

## Balance pass 1 (Oct 22, 2026, branch `balance-pass-1`)

Worked from the D-017 baseline with the harness, a scratch per-week trace of true EV, and isolated candidate pairs at 2,000–4,000 matches (per-candidate noise ≈ ±2 points at 2,000 harness matches, ±6 per matchup cell). Every number below is bot-vs-bot; the bot values money low (a dollar at 0.4 of the best media buy), which is correct in this economy (raising it to 0.55 makes the rally-only bot beat the balanced bot 55%, at 1.0 it wins 94%), but it means money-shaped perks and drawbacks register weakly. Treat money-shaped numbers as the ones most likely to move again after human playtests.

### D-018 — "Debates change the winner" is now a counterfactual recount (tuning, harness only)

`Debate.resolve` records, per state and player, the support each debate actually moved (`StateSim.debateShift`, hidden: `View` never copies it and the no-leak spec forbids the key). `Election.count` takes `debates = false` and recounts the final board with those shifts subtracted and the same seeded election noise, exactly like the GOTV check. The paired replay with debates switched off was dropped: the bots react to a different board, so the two matches diverge and the number mostly measured chaos.

*Numbers:* on the D-017 baseline the paired replay said 49.6%; the recount says **41.6% of winners change and the debates swing 61 EV on average** (an okafor-vs-okafor mirror, so no stat edge at all, still gave 40% and 51 EV). Pure luck in the debate rolls was deciding two matches in five.

### D-019 — Debates: roll 0..6, 0.2 per topic (tuning)

`DEBATE_ROLL_MAX` 2 → 6, `DEBATE_TOPIC_WIN` 0.8 → 0.2, `DEBATE_SWEEP` 0.5 → 0.2, `DEBATE_GAFFE` 0.5 → 0.2. A 3-0 sweep is now worth 0.8 national points (was 2.9); `tests/sim/Config.spec` pins "under one point".

*Why:* two findings. (1) Against a 0..2 roll, a +1 debate stat wins 67% of topics and loses 11% (net +1.67 topics per debate); even +2 prep on one topic wins it 89%. (2) The national shift is leveraged by the winner-take-all map: about 13 undrafted, unleaned states (77 EV) finish the campaign at exactly 35/35 and any national shift decides all of them together, and about 150 EV sits within ±3 points every week. Hale vs Okafor measured 64% with debates off, 63.5% at 0.05 per topic, 67% at 0.1, 76% at 0.25 and 75% at 0.4: the effect saturates once a 2-1 result moves the tied block past election noise. Raising only the roll (0..4) left Hale at 88%. Each topic is now worth roughly 12 EV of close states rather than 50.

*Result (final harness):* debates change the winner in 16.2% of matches (target ≥ 10%) and swing 15.2 EV on average; topic win rates are 41–44% for everyone except Hale (53%, D-023). *Rejected:* `LEAN_STATE_COUNT` 50 removes the tied block (debates decide 12%, swing 11 EV, blowouts 58%) but pushes the comeback rate to 42–44% (target ≤ 40%) and tossup EV at the election down to 6.6%, so the map keeps 30 leaned states; revisit if Phase 5 events add more national shifts, which hit the same tied block.

### D-020 — Rubber band: hysteresis 30, smoothing 0.4 (tuning)

`UNDERDOG_HYSTERESIS` 20 → 30, `UNDERDOG_SMOOTHING` 0.5 → 0.4. Tier changes per match 4.1 → 3.0 (target ≤ 3).

*Trade-off, for the humans:* "underdog weeks paid to a true 20+ EV leader" rose from 8.9% to 22% (target < 10%), but that rise comes from the other changes, not from this one: with the old 20 / 0.5 under the new package it is already 18%, because matches are closer and the true leader now changes about four times a match, so any poll-smoothed gap lags reality. The two targets conflict under this volatility (grid: 20/0.5 → 4.0 changes, 18% wrong; 30/0.5 → 3.8, 20%; 30/0.4 → 3.1, 22%; 30/0.3 → 2.5, 25%). The tier-1 bonus is ×1.10 rallies / ×1.15 fundraisers for one week, so a wrong week costs little; either relax the wrong-leader target to about 25% or accept 4 tier changes. A real fix needs a different gap signal (a mechanic change).

### D-021 — Ground game +1.5 per unit; the bot starts it in week 7 (tuning + bot)

`GOTV_PER_UNIT` 1.0 → 1.5; `Bot.tuning.gotvFromWeek` 9 → 7. At 1.0 a $2 unit bought 0.5 margin per dollar against about 0.7–1.0 for a media buy, so the correct play was to never buy it (bots spent $2.8 a game, GOTV decided 1.8%). At 1.5 it beats a poorly matched media buy per dollar and loses to a well matched one (`Config.spec` pins both), so it is a late sink for states where ads saturate, not the default. 1.25 was tried: 8.9%.

*Result:* GOTV changes the winner in 12.2% (target ≥ 10%); average spend $7.6 per player. `Bot.spec` checks units are placed before week 9. Walt Begay: see D-022.

### D-022 — Candidate numbers (tuning)

Measured with everything above in place; "before" is the roster-wide win rate under the new Config with the D-011 roster.

| Candidate | Change | Before → after | Why |
|---|---|---|---|
| Walt Begay | rallies 2.4 → 2.9 | 37% → 54% | At 2.4 the rally drawback cost far more than a $1 ground game earned even at 1.5 per unit (2.8 gave 45–50%). He now buys about 26 units a game. |
| June Alvarado | start $18 → $20, income $3 → $3.75 | 42% → 52% | Start cash is almost worthless to the bot ($18 and $26 measured the same, 41.5% vs Calloway); income is what it feels. $3.5 still gave 44%. Likely to move again with humans, who can use early money. |
| Tomas Reyes | momentum gained +50% → +65% | 46% → 50% | His perk disappeared once debates shrank and others were fixed. +70% measured 55% on the harness's seeds, +60% 47%. |
| Rex Calloway | rallies 2.2 → 2.3 | 45% → 53% | Sat at 45–47% in every run once the others were fixed. Media cost $5 and rallies 2.1 were tried earlier and overshot (42%). |
| Helen Strand | media −10% → −15% | 57% → 48% | Free polls are worth little to the bot (never-poll wins 53%); her strength was the small media drawback. 0.8 gave 47%. |
| Marcus Hale | start $4 → $0 | −5 to −7 points | Part of the Hale fix (D-023); the $4 drawback measured as nothing. Week 1 he can only rally and fundraise. |

Specs that encoded the old numbers were updated with them (Tomas momentum, Hale's starting cash, Okafor's fundraiser multiplier).

### D-023 — Three perk shapes (approved Oct 22, 2026)

Approved by the humans on Oct 22, 2026, as proposed below (the perk changes, not the tuning-only alternatives). Tuning alone could not fix these; each is the smallest change that measured inside 45–55%. Pure-tuning alternatives and their numbers are listed so the humans can choose.

1. **Marcus Hale: "debate stat 2" → "8 prep points instead of 6".** A flat +1 on every topic score is not a decision and cannot be made small: at 0.2 per topic he was 66%, at 0.15 (debates deciding only 10% of matches) still 62%. Extra prep is a choice of where to stack and is bounded by `DEBATE_MAX_PER_TOPIC`. With prep 8 and $0 start: 51% (prep 8 at $4: 59%). Tuning-only alternative: stat 2 with $0 start → 59%.
2. **Priya Venkat: drawback "debate stat 0" → "income $3".** Stat 0 was a lottery drawback and worth nothing once debates were small (she was 59% with it, 77% with debates off). Income $3 alone: 52–53%. Both together: 43%. Her perk is untouched.
3. **Dana Okafor: drawback "rallies −10%" removed; perk +30% → +50%.** The bot's rally-or-fundraise choice is threshold-sensitive: rallies ×0.9 → 41%, ×0.95 → 42%, ×1.0 → 48–51%. Fundraising multipliers barely register (1.3 and 1.5 measured the same with the drawback in place), so +50% is a buff for humans at no measured cost. Tuning-only alternative: ×0.95 and +50% → 42%. If a drawback is wanted, "income $3" measured 42% (too much) and nothing between was tried.


### D-024 — The blowout target is structural; revised target (approved Oct 22, 2026)

"≤ 15% decided by 40+ EV" is not reachable with winner-take-all. A per-week trace of true EV in okafor-vs-okafor mirrors with debates off (perfect symmetry, no perk or stat edge) shows the margin jump from 23 EV after the draft to about 50 EV after week 1 and then wander at 55–60 EV for the rest of the campaign, with about 150 EV within ±3 true points every week and the true-EV leader changing four times a match: not a snowball, a wide random walk. Whoever is a point ahead in the tipping-point states takes all of them. That symmetric floor is 61% decided by 40+ EV with a median margin of 52; the final package sits on it (60.4%, median 52, p25/p75 24/88, down from 80.5% and 108). Reducing the national debate shift and killing the Hale/Venkat edge is what moved it; `LEAN_STATE_COUNT` 50 buys another 2–3 points at the cost of the comeback target (D-019).

*Revised target (approved by the humans on Oct 22, 2026; the harness checks it):* ≤ 65% decided by 40+ EV, median margin ≤ 60 EV, and ≤ 25% decided by 100+ EV (now about 20%), with the comeback rate (38%) and "week-12 projected leader loses" (27%) as the real anti-snowball checks. Getting lower would need a mechanic (a bot or player that concentrates on tipping-point states converges; proportional allocation for some states; smaller leans of larger count) rather than a number.

### D-025 — Balance pass 1: final harness report (Oct 22, 2026)

`lune run tests/harness/balance.luau`, 2,000 matches, defaults, on commit `b27bdda` (59 s). The D-017 baseline is in the right-hand column.

| Check | After | Baseline (D-017) | Target |
|---|---|---|---|
| Candidates | Okafor 50, Calloway 53.5, Venkat 51.6, Hale 48.1, Alvarado 46.8, Reyes 50.0, Strand 48.4, Begay 51.5 | Venkat 20, Hale 89, Begay 37, others 46–55 | 45–55% ✓ |
| Worst matchup | Calloway vs Alvarado 63% (71 games/pair, ±12 at 95%) | Venkat vs Hale 3% | 40–60% (noise-level) |
| Priority A win rate | 52.3% | 51.4% | 47–53% ✓ |
| Comeback rate | 36.8% | 25.3% | 20–40% ✓ |
| Decided by 40+ EV (median margin) | **60.1%** (52; p25/p75 24/86) | 80.5% (108) | ≤ 15%: see D-024 |
| Tossup EV at election / noise spread | 15.0% / 17.7 EV | 10.3% / 16.6 | ≤ 30% / ≤ 25 ✓ |
| Leaned states that flip / lean–win correlation | 23.0% / −0.046 | 30.4% / −0.03 | 20–40% / \|r\| < 0.05 ✓ |
| Underdog weeks to a true 20+ leader / tier changes | **21.5%** / 3.03 | 8.9% / 4.1 | < 10% / ≤ 3: see D-020 |
| GOTV changes the winner (spend per player) | 12.2% ($7.6) | 1.8% ($2.8) | ≥ 10% ✓ |
| Debates change the winner, counterfactual (EV swung) | 16.2% (15.2 EV) | 41.6% (61 EV) | ≥ 10% ✓ |
| Debate topic win rates | 41–44%, Hale 53% | Venkat 17, Hale 64 | — |
| Week-12 projected leader loses | 28.7% | 11.2% | — |
| Random / fundraise / rally / attack / never-poll / sandbag vs balanced | 0 / 0.5 / 39 / 41 / 52 / 34% | 0 / 4 / 46 / 45 / 53 / 42% | ≤ 5, < 55, ≤ 50 ✓ |

Still red: the blowout share (structural, revised target in D-024), the wrong-leader share (conflicts with the tier-change target, D-020), and one matchup cell at 63%, which is within the ±12-point noise of 71 games (about one cell in 28 lands outside 40–60 by chance at every run; the cell that does changes with the seed set). Everything that passed in D-017 still passes.

*Next, if the humans want to go further:* a bot that values states by tipping-point probability rather than margin density would make both bots converge on the same states and should cut the blowout share and lift the comeback signal; a smoother underdog gap signal (true-EV-free, e.g. a longer poll average) would separate the two rubber-band targets; and the money-shaped perks (Okafor, Alvarado, Venkat) should be re-measured after human playtests, because the bot values money low.

## Phase 2: server and networking

### D-026 — The server core is pure and lives in Shared/Net (Oct 22, 2026)

- `Net/Session` is the PLAN's TurnController: it owns phase timers, lock-ins, the time bank, skips, reveals, disconnect grace and forfeits for one match. It takes the server time as an argument, so `tests/net/` covers every timer path headlessly. `server/MatchService` only feeds it requests and `workspace:GetServerTimeNow()`. It lives in `ReplicatedStorage.Shared` because Roblox server scripts can't require ServerScriptService modules by string path, and Lune needs string paths. Clients can read it, but it holds no secrets: every hidden value stays in the server's `MatchState`, and clients receive only `View.build` output.
- **One request remote, one message remote.** Each request carries the `step` it was made for. A request for an earlier step is rejected as `StaleStep`, so a late click can't land in the next phase.
- **Rules the PLAN left open:** the time bank extends only the tapping player's own deadline, and the opponent sees the bank drop. A disconnected player's grace can hold a phase past its deadline. Only weeks missed while disconnected count toward the forfeit; a connected player who idles gets the empty-plan default every week but isn't forfeited. Draft reveals and debates can't be skipped. A match with no human left after grace is abandoned with no result.
- **Rate limit:** 40 requests per player per 10 s, well above what play needs (a whole plan is one request).
- **Reconnect window:** a player who comes back during an Input stage they haven't locked is guaranteed `RECONNECT_WINDOW` (15 s, new in `Sim/Config`) from the moment they return, even if their deadline already passed while grace held the stage open. Only their own deadline moves; it doesn't spend time bank or show the opponent anything, and it resets with the next Input stage. A rate-limited player is warned and told once per window; the rest of their requests are dropped silently.
- **If a match throws:** `MatchService` abandons it (`Session.abort`, result `Abandoned`) and frees the lobby, so a bug can't trap players in a stuck match.

## Phase 5: event deck

### D-027 — The weekly event deck, made concrete (Oct 21, 2026, tuning + rules clarifications)

`docs/PLAN.md` "Events (Phase 5)" left the details open. Code: `Sim/Events.luau` (deck and rules), `Resolve.week` (effects), `Plan.validate` (Choice answers), `View.event` / `View.eventLog`, `Bot`, and the private-lobby toggle in `Net/`. Specs: `tests/sim/Events.spec.luau`, plus additions to the View, Bot, Config, Lobby, Session and DebugUI specs.

**The deck (20 events, generic and fictional).**

| Kind | Events |
|---|---|
| Spotlight (8, one per issue) | Factory reopening (Jobs), Flu season (Health), Back to school (Schools), Storm season (Environment), Safety summit (Safety), Infrastructure week (Roads & Transit), Tech expo (Technology), Harvest festival (Farms & Rural) |
| Regional (5) | Lakeshore fair (Great Lakes), Coastal festival (Pacific), Riverfront regatta (South Atlantic), Rodeo season (South Central), Trail days (Mountain) |
| Windfall (3) | Donor retreat, Small-dollar surge, Matching-gift week |
| Choice (4) | Leaked memo, Viral clip, Rumor mill, Endorsement fight |

A match deals 10 of them, so it sees about 4 Spotlights, 2.5 Regionals, 1.5 Windfalls and 2 Choices. One Spotlight per issue means the deck favors no platform.

**Draw and visibility.**
- `Match.new` shuffles the deck with the `"events"` fork of the match seed and deals one event to each week from `EVENT_FIRST_WEEK` (2) to `EVENT_LAST_WEEK` (11). A shuffled deck means no repeats. Weeks 1 and 12 get nothing. The deck order is the only randomness events add, as the PLAN's variance budget says. A fork never advances its parent, so turning events off leaves leans, draft priority and debate topics unchanged (spec). With events off the harness reproduces the pre-events report exactly.
- `MatchState.eventDeck` (week → id) stays hidden. `View.event` shows only the current week's event, during that week's Debate and Plan phases. The server's resolve reveal already carries the next week's view, so the event appears when Plan starts and both players can react to it. **Next week's event is not shown.** A preview would let a player fly into a Regional's region a week early for free, and the event would reward remembering the deck instead of reacting to it. Debates are announced ahead because they take prep; events don't. `View.spec` checks that changing any other week's deck entry leaves the view byte-for-byte the same, and it forbids the key `eventDeck`.

**Effects** (during that week's Resolve, all from the step's start snapshot, D-001):
- **Spotlight**: rallies and *positive* media on the issue get ×`EVENT_SPOTLIGHT_MULT` (1.3) in every state. Attacks are never boosted, so an event never makes attack ads stronger (D-004's spirit).
- **Regional**: rallies only, in the region's states, get ×`EVENT_REGIONAL_MULT` (1.5).
- **Windfall**: a fundraiser gets ×`EVENT_WINDFALL_MULT` (**1.2, not the PLAN's 1.5**, see below) in a state where the fundraiser trails in the *start-of-week public poll*, the one both players saw. A tie doesn't count as trailing. The multiplier applies after the pool cap together with the perk and home multipliers, and like them it doesn't drain the pool.
- Events multiply the action's direct support or money only. Momentum, drift and saturation work as before.

**The ±2 cap, concretely.** An event can add at most `EVENT_CAP` (2) to one player, in one state, in one week, beyond what that player's actions would have given there without it. For Spotlight and Regional this is support points, and rallies and media share the allowance. For Windfall it is money ($2M). `Events.grant` keeps a ledger per state and player during Resolve. Knock-on effects (a bigger rally saturating a later ad, a larger poll lead) aren't counted against the cap; they only ever make the difference smaller. Choice payoffs are national points clamped to ±`EVENT_CAP`, and the matrix below never exceeds 0.3. Specs: the cap binds exactly at 2 for three spotlight rallies and for a strong Windfall, and holds for bot plans in every boosting event, every state and every player.

**Choice events.**
- In a Choice week the plan may carry `choice = "Attack" | "Defend" | "Ignore"` (exact strings). A missing answer, an empty plan or a timeout means `"Ignore"`. Any other value is rejected whole as `BadChoice`. An answer in any other week is rejected as `UnexpectedChoice`.
- Payoff matrix, in national points for the row answer against the column answer (Config `CHOICE_*`):

  |  | vs Attack | vs Defend | vs Ignore |
  |---|---|---|---|
  | **Attack** | −0.2 (mudslinging) | −0.3 (backfire) | +0.2 |
  | **Defend** | 0 (defense pays off) | −0.2 (wasted) | −0.2 (wasted) |
  | **Ignore** | −0.2 (it lands) | 0 | 0 |

  The matrix is the same for every seat, so swapping seats mirrors the result exactly (spec). In margin terms (a national gain also takes 30% from the opponent) it is a cycle: Attack beats Ignore by 0.46, Defend beats Attack by 0.3, Ignore beats Defend by 0.2. No answer is dominant. The mixed equilibrium plays Attack : Defend : Ignore = 0.2 : 0.46 : 0.3 (21% / 48% / 31%), and the game is worth 0 to both sides.
  *Why not the brief's example numbers* (+0.5 / −0.5 for an attack on an ignorer, −0.3 backfire, −0.1 defend cost): an attack that lands would swing about 1.15 points of national margin, more than a whole 3-0 debate sweep (about 1.04, D-019), and those national shifts hit the tied block of close states (D-019). Defend would also be nearly dominant (71% at equilibrium). `Config.spec` pins every payoff inside the cap and below a debate sweep.
- Resolution happens right after pivots, as one national shift (`Support.national`: gains use the normal split, losses go to undecided) from one snapshot. With more than two players, each one's payoff is the sum against every opponent, then clamped. Both answers are revealed after the week: `WeekCard.choice`, `View.eventLog` (`choices` and the `national` points) and a public `Choice` event per player. Until then an answer exists only in the server's locked seat input, never in `MatchState`. `View.spec` checks that seat 1's payload is identical whatever seat 2 has locked in.

**Bot.** It ranks issues with the Spotlight multiplier included, values rallies in a Regional's region and Windfall fundraisers in trailing states at their bonus (tracking the cap per state like Resolve), and answers a Choice by sampling the equilibrium above with its own seeded stream (`Bot.choiceWeights`; the Random style picks uniformly). `Bot.spec` checks that it plays more spotlight-issue actions, more Pacific rallies under Coastal festival and no fewer trailing-state fundraisers, and that its answers match the mix.

**Toggle.** `EVENTS_ENABLED` (true). Private lobbies only: a `Host` request may carry `events = false`, which `Net/Schemas` checks is a boolean. `Lobby.host` keeps it with the code and hands it to the `Match` outcome, and `MatchService` passes `{ events = false }` to `Session.new`, which plays the match on `Config.with(config, { EVENTS_ENABLED = false })`. The public queue and practice always have events on. Debug UI: `host noevents`. Events change no phase, timer or deadline (`Session.spec`).

**Harness** (2,000 matches, `lune run tests/harness/balance.luau`):
- *Before* (events off, identical to the D-025 report): 3 red flags, the same as D-025: the noise-level matchup cell (Calloway vs Alvarado 63.4%), wrong-leader underdog weeks 21.5%, and tier changes 3.03.
- *With the PLAN's numbers* (Windfall ×1.5): 6 red flags. The three new ones were Venkat 56.7%, Strand 44.8% and NeverPoll 55.8%. A probe of 8,000 matches on two separate seed ranges (about 2,000 games per candidate, ±2.2 points at 95%) traced Venkat to Windfall: 52.1 / 52.8% with events off and 55.4 / 56.2% on. With Spotlight, Regional or Choice switched off she still measured 55.4–56.8%, but with Windfall off she measured 50.9 / 52.3%. Extra money is worth most to the candidate whose media costs $2. Windfall ×1.25 gave 53.3 / 53.9% and ×1.2 gave 53.0 / 52.7%. **`EVENT_WINDFALL_MULT` 1.5 → 1.2.**
- Strand measures 47.0 / 45.2% with events off and 46.4 / 45.6% at the final numbers. That's her true rate, not an event effect, and she sits close to the 45% line either way. NeverPoll's check plays only 400 games (±5 points). At 2,000 games it measures 56.6% with events off and 57.6% with them on, so it was already over 55% before events. **For the humans:** paid polls are worth little to the bot (D-022 said the same about Strand's free polls). That is a bot or poll-value question and is not touched here.
- *After* (final numbers): **3 red flags, the same three as before**. Candidates 47.0–54.9% (Venkat 54.9). Worst matchup Strand vs Begay 32.9% (a different noise-level cell; it was already 38% before events). Wrong-leader underdog weeks 21.8%, tier changes 3.10. Every other check passes: priority A 51.7%, comeback 38.3%, median margin 54, 40+ EV 62.4%, 100+ EV 20.1%, GOTV decides 11.8%, debates 16.4%, NeverPoll 54.5%.
