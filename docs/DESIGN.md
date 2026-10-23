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
- **Bug hunt fixes (server pass).** The forfeit counter is now really consecutive: a Plan close where the player was connected (locked in or just idle) resets `missed` to 0, so two drops with a played or idle week between them no longer forfeit. `Session.payload` strips `view.election` unless it is election night (Show stage in phase Election) or the match ended by `Election`: week 12's resolve reveal already runs in phase Election, and a forfeit after it leaves a computed result nobody saw. `View.priorityA` is absent during Select (it becomes public at the map reveal); the client's Draft screen only reads it from the map reveal on.

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

## Phase 5: ratings and saved stats

### D-028 — Elo rating, the saved profile, and session-locked DataStore saves (Oct 22, 2026, branch `phase5-data`)

**Rating** (`Net/Rating.luau`, pure). Standard Elo with `ELO_K` 32 and `ELO_START` 1000 from `Sim/Config`, and one new number, `ELO_FLOOR` 100 (nobody can fall below it). Ratings are whole numbers. The change is rounded half away from zero, so both players of a match always move by equal and opposite amounts and each side can be computed on its own from the two pre-match ratings. Only the floor can break that symmetry (a player at the floor creates rating points instead of losing them). An election can't tie (`Election.count` flips a seeded coin on an exact popular-vote tie), so there is no draw path; a result with winner 0 is treated as unrated.

**What is rated.** Queued and private human-versus-human matches that end by `Election` or `Forfeit`. A match is rated only if both players' saved ratings were loaded and writable when it started; otherwise it is logged as unrated and nobody's rating moves. A forfeit costs the player who left even after they have left the server: their stored record is updated on its own thread (`DataService.update` returns `"Offline"`). Practice against the bot never moves the rating; it adds to a separate `practice = { games, wins, losses }` total and is kept out of `perCandidate` and `recent`, so those stay honest ladder stats. An `Abandoned` match changes nothing.

**The record.** DataStore `PlayerData_v1`, key `Player_<UserId>`:

```
{ lock = { jobId = string, at = unix seconds }?,
  data = { version = 1, rating, games, wins, losses,
           perCandidate = { [candidateId] = { wins, losses } },
           recent = { { at, opponentRating, candidate, opponentCandidate, won, evFor?, evAgainst?, reason } },  -- last 10, oldest first
           practice = { games, wins, losses } } }
```

`Profile.migrate` accepts nil, garbage and any older version (no version, or a version before 1, is read field by field and the unreadable fields default). A record saved by a newer version of the game is shown but never overwritten.

**Session locking** (`server/DataService.luau`). Loading is one `UpdateAsync` that writes `lock = { jobId = game.JobId, at = os.time() }` and returns the migrated profile. If another server's lock is younger than 120 s the load retries 4 times with backoff (1.5, 3, 6 s), then reads the profile with `GetAsync` and leaves it read-only (logged; nothing is saved, the match is unrated). A lock older than 120 s belongs to a crashed server and is taken over. Every save refreshes the lock; leaving or shutting down clears it. A save that finds another server's fresh lock does not write and the player goes read-only. `UpdateAsync` callbacks reset their state on entry (Roblox may call them more than once), never yield, and return plain tables. Errors are retried 5 times with exponential backoff (1, 2, 4, 8 s).

**When it saves.** On load (the lock), when a match ends (in memory at once, written on a background thread), on `PlayerRemoving`, and in `game:BindToClose`, which waits at most 25 s of Roblox's 30. It never runs inside a turn: `MatchService` reads ratings from memory and every request is on its own thread.

**Unpublished places.** DataStores error in an unpublished Studio place (or with API access off). The first request that fails with that error switches the whole service to an in-memory store with the single warning `[270] DataStore unavailable (publish the place and enable Studio API access to save); using memory`. Play works; nothing survives. This fallback is Studio-only (`RunService:IsStudio()`); a live server keeps retrying instead of silently dropping saves.

**Wire.** `Remotes.LobbyStatus.profile` is an optional `{ rating, games, wins, losses }` (absent until the profile loads, or if it can't). A new message kind `"Rating"` carries `rating = { matchId, before, after }` and is sent once to each human after a rated match. The debug UI shows `Rating 1032 (12-7)` in the lobby line and `Rating 1032 → 1048` in the log and on the result board.

**Known limits.** A player who leaves a rated match and joins another server before the match ends can't be charged the forfeit (their record is locked there; the update is retried 4 times, then dropped with a warning). The lock is not refreshed on a timer, only by saves, which is enough because a player can't be in two servers and the lock only guards the moments around a server hop. A server crash loses only what changed since the last match end. Request budgets (`GetRequestBudgetForRequestType`) aren't tracked: a player causes about three requests per match.

**Roblox APIs used** (checked against the creator-docs reference): `DataStoreService:GetDataStore(name)`; `GlobalDataStore:UpdateAsync(key, transform)` and `:GetAsync(key)` (`DataStore` inherits both); `DataModel:BindToClose(fn)` (30 s limit, functions run in parallel); `DataModel.JobId` (empty in Studio, so the lock owner there is `"studio"`); `RunService:IsStudio()`; `Players.PlayerAdded`/`PlayerRemoving`.

**Bug hunt fixes (server pass).**

- **A result is never dropped for a reloading player.** `DataService.update` returns `"Queued"` for a profile that is still loading and applies the transform, in order, the moment the load finishes (saved right after; dropped with a warning only if the profile ends up read-only). An optional `applied` callback runs when the change is in memory, so the "Rating a → b" message still reaches a player who came back mid-match. Ratings stay zero-sum.
- **Leaving twice during a slow save no longer leaks.** A load waiting on an earlier visit's entry is registered in `pending`; `DataService.remove` cancels it, so it never creates an entry and takes a lock nobody would release.
- **An unrated human match changes nothing.** Practice stats are only for matches against the bot (`MatchService.settle` returns early for a human match with no recorded starting ratings).
- **A forfeit records no electoral votes.** `evFor` and `evAgainst` are written only when the match ended by `Election`; after week 12's plan the server has computed a result nobody was shown.
- **`DataService.rating` ignores an entry that is leaving**, so a player who rejoins while their old record is still saving is not rated into a match on stale data. (A save that finds another live server's lock already refused to write; there is now a spec for it.)
- **The lobby status follows the server.** Whenever the queue, the open codes or the number of running matches changes (a match starts or ends, a queue/host/join request, a queued or hosting player leaves), `MatchService.broadcastLobby` sends the current status to every player who is not in a match, so "server full" and the queue count never go stale. A rejected request or a pre-pick still answers only the requester.

## Phase 3: client MVP

### D-029 — Client structure and UI rules (Oct 22, 2026)

- Screens are modules with one contract (`mount(parent, ctx) -> { update, tick?, destroy }`); a router picks one per state. They read only the Store (the server's payload: the player's own View) and send only through Net. Pure helpers (colors, map layout, plan preview, fixtures) live in `Shared/UI` so they are tested headlessly.
- **Map nodes are exempt from the 44 px touch rule.** Small states are small circles by design (tap targets are at least 30 px); every screen that picks states also offers a list. The layout audit skips buttons inside `NodeMap`.
- The game's ScreenGui uses `CoreUISafeInsets` so Roblox's own top-left buttons never cover it; a separate backdrop fills the screen.
- The debug text panel stays in the build, hidden (F2 or `DebugText`), because agents and the e2e specs drive matches through it.

### Bug hunt fixes (client pass, Oct 22, 2026)

- **Auto-lock on timeout.** 0.5 s before the deadline the client sends what the player has, once per step: Select if complete, Draft if at least one state is picked, Campaign only if `PlanDraft.problem` is nil. Otherwise nothing is sent and the server default applies. A manual lock marks the step spent, so nothing is sent twice. `PrePick` is sent whenever a Select pick becomes complete.
- **State list.** The campaign state card offers a collapsible list of every state (two taps to select), so small states on the node map are never the only way in. Ordering lives in `Shared/UI/StateOrder` (closest, biggest, A to Z).
- **Messages carry growing ids** (`Store.say`), and screens compare ids, never counts, so detection survives the 20-line cap.
- **"Server full" never disables lobby buttons**; the server's answer decides.

### Bug hunt fixes (rules, Oct 22, 2026)

- With 3 or more players the 1v1 lean-balance threshold is often unreachable; `Leans.generate` now keeps the most balanced draw it saw instead of erroring after `MAX_ATTEMPTS`. 1v1 maps are unchanged.
- Election tiebreaks (EV, then states, then popular vote, then the seeded coin) narrow to the tied players at each step, so a player who lost on EV can't win on states.

## UI overhaul (v0.4.0)

### D-030 — The design system and the one-primary rule (Oct 22, 2026)

The client gets one visual language before the screens are redone (plan: the UI overhaul, work packages WP0 to WP4). WP0 lays the foundation below; each later package adds a sub-bullet here when it lands. No rule, sim number, payload or View field changes.

- **One accent fill per screen, and it is the primary action.** Selection is an accent *outline* (chips, candidate cards, Choice answers), never a fill. Timer digits stay accent. The UI audit enforces it (`oneAccent`).
- **Type scale, five sizes only:** `Kit.size.caption` 13, `body` 16, `heading` 20, `title` 28, `hero` 48 (the old `small`/`large`/`huge` are gone). `Kit.MIN_TEXT` 12 is the floor of every `UITextSizeConstraint` (was 9 for text, 10 for buttons). TextScaled only for single-line labels in a fixed box.
- **Spacing and shape:** `Kit.space` xs 4 / sm 8 / md 12 / lg 16 / xl 24; `Kit.radius` control 8 / panel 12 / pill 999. Panels pad 12 with a 12 px corner. Buttons are 44 px or, for the one pinned primary, `Kit.PRIMARY_H` 56. `Kit.BAR_H` 84, `Kit.HEADER_H` 44, `Kit.MAP_NODE_MIN` 36 (map tap targets; was 30, replaces the D-029 exemption once WP1 lands).
- **Colors:** `Colors.luau` stays the single, pure source. New tokens `onAccent` (= background), `field` (22, 25, 33), `warn` (= accent), `disabledText` (= muted); `Colors.tint` (the public name of `mix`, which stays as an alias) and `Colors.onColor(rgb)` (dark text when the Rec. 709 luma is above 0.5, so Amber, Teal and Emerald swatches get dark labels). `Kit.colors` mirrors every token as a Color3 and `Kit.playerColor(view, p)` replaces three copies in the screens. Screens and the map never write a `Color3` literal.
- **Button variants** (`Kit.button(text, fn, { variant = ... })`): `primary` (accent, onAccent bold; disabled = raised bg + muted text, so a disabled Lock in reads as a grey button whose label says what is missing), `secondary` (default), `danger` (surface, danger text, 1 px danger stroke), `chip` (selected = 2 px accent stroke + raisedHover). `Kit.setEnabled` and the new `Kit.setSelected` touch only what the variant owns. Buttons made without a variant keep the old fade until their screen moves over.
- **Shared components:** `UI/ActionBar` (status line, opponent line, optional secondary, the primary with attribute `PrimaryAction`; pinned to the bottom with explicit offsets), `UI/Header` (title, subtitle, timer: accent, danger under `Kit.TIMER_WARN` 10 s, the one threshold for every screen), `UI/Toast` (one layer above every screen, newest Store message, 5 s, danger stroke for rejections, never hidden by a reveal), `UI/Collapsible` (a panel with a 44 px title row). APIs are documented in each module's header and in `Kit.luau`.
- **Wording.** Primary "Lock in" (disabled: what is missing, e.g. "Pick a state"); after locking "Locked in · waiting for opponent"; opponent "Opponent: thinking / locked in / skipped / disconnected / back"; reveal skip "Skip", then "Waiting for opponent…". Player-facing action names everywhere (buttons, plan list, reveal): Rally, Fundraise, Ad, Attack ad, Poll, Region poll, Ground game, Pivot. PLAN.md keeps its rule names (media buy, GOTV).
- **Settled with the humans** (plan §6, as recommended): the Northeast inset ladder on the map (WP1); event card collapsed to a two-line row outside Choice weeks, week card collapsed on phones (WP3); Region poll and Pivot in the action grid (WP3); two-tap Clear (WP3); the timer warning at 10 s everywhere. Results stats that need new View fields are a later server ticket.
- **UI audit** (`UI/Audit`, same `[270] UI audit ...` output plus a pending count and the number of distinct text sizes). New rules: text floor, button width, map nodes at least 36 px, contained (inside the screen and any fixed parent; children of a ScrollingFrame horizontally only), exactly one pinned `PrimaryAction` (zero when the screen root has attribute `PrimaryOptional`), one accent fill, type scale. The Router now audits only in Studio or with `DebugScreen`/`DebugText` set (it ran on live servers before), and again 0.5 s after the orientation flips.
- **Transition.** While the packages were in progress, `Audit.PENDING` listed the rules each screen (and `NodeMap`, for the map on every screen) still breaks; those findings print as "pending" notes and are not counted, so `lune run tests` stays green. A package makes its screens strict by deleting their entries; `Audit.run(root, label, { strict = true })` ignores the list. `tests/ui/Tokens.spec` does the same for source files (no Color3 or TextSize literals, no 48/52/64/104 px heights in `Screens/` and `Map/`): its `PENDING` caps each listed file's offending lines and fails once a listed file is clean, so the entry gets deleted.
- **Fake engine.** `tests/lib/FakeRoblox` now reports `AbsolutePosition` (from Position and AnchorPoint; list layouts are still not run) and honors `UISizeConstraint`, so the containment and primary rules can be checked headlessly; `FakeRoblox.require` loads a client module into a peer and `world.studio` switches `RunService:IsStudio()`.
- **Transition done.** All four packages landed; `Audit.PENDING` and `Tokens.spec`'s `PENDING` are empty, so every screen is audited strictly.
- **WP1, Map.**
  - WP1 map ladder: VT, NH, MA, RI, CT, NJ, DE, MD, DC leave the projection for a fixed column at x = 0.952 (box widths), centers evenly from 0.08 to 0.92 of the box height, radius 0.0305, with a 1 px `line`-color leader to the projected center. The projection's east edge moved from 0.95 to 0.86 to make room; land borders are not drawn for ladder states (their leader replaces them).
  - Circle radius is now 0.0293 + 0.0040 * sqrt(EV) box widths (was 0.004 + 0.0062 * sqrt(EV)) so every label box (0.85 of the diameter) is at least 24 px at a 390 px map; the layout is sized for `MapLayout.PHONE_WIDTH = 390`. The plan's "0.8 · 2r · 390" formula with its ladder radius 0.0275 gave a 17 px box, not 21, so the label share went to 0.85 and the ladder radius to 0.0305 (20.2 px); nine of those only fit if the column spans the full map height.
  - Tap targets: `MapLayout.hitRadius(n) = max(r, MIN_HIT / 2 / PHONE_WIDTH)` in box widths, plus a 36 px `UISizeConstraint` minimum. The layout keeps every target inside the box at 390 px; on smaller maps the target's anchor makes it grow inward, so it still never pokes out. Targets overlap on phones (36 px targets, 24-30 px circles); smaller states are created last so they win the overlap.
  - `MapInterface.Mark` gains `arrow: ("up" | "down")?` and `arrowColor: Color3?` (default: text color). The plan named only `arrow`; the color was added because the arrow is drawn in the momentum leader's color and NodeMap cannot know who that is.
  - Audit (`src/client/UI/Audit.luau`, outside WP1's files, additive): the `contained` rule skips rotated objects, because Roblox reports a rotated frame's unrotated box; every map border, leader and route segment is rotated and stays between two in-map points. `Audit.PENDING.NodeMap` and the NodeMap line in `Tokens.spec` PENDING are gone; `Audit.spec`'s filing test now installs a temporary NodeMap entry.
  - No `Sim/Config.luau` numbers changed.
- **WP2, Lobby, Select and Results.**
  - WP2 (Lobby, Select, Results): all three screens are strict. They are gone from `Audit.PENDING` and `Tokens.spec` PENDING.
    - **Lobby** doesn't scroll, so its primary ("Play vs Bot") is never inside a ScrollingFrame. On screens shorter than 480 px the pitch line hides to make room. While queued, hosting or starting there is nothing to press first, so the screen sets `PrimaryOptional`.
    - **Select** stacks its scroll content with explicit pixel positions instead of the page's list layout. This lets the fake engine measure it, and lets the status line know whether the issues are below the fold (the "▾"). Card heights follow the plan: 112 px on 16:9 and 124 px on phones. On a phone the issues still scroll: the plan's portrait estimate left out the gaps between blocks, so "only the last two rows below the fold" is not reached. The pinned bar says so instead.
    - **Swatches** keep their own color. They don't use `Kit.setSelected`/`setEnabled`, which repaint a chip's background. Selection is a 3 px outline in the text color plus "✓", and the label color comes from `Colors.onColor`.
    - **Rejected Lock in (B4):** the reason stays in the status line in red until the next change. The toast is the attention-getter.
- **WP3, Campaign.**
  - **Campaign (WP3).** Lock in, Bank and the plan status move into the pinned `ActionBar` (primary named `LockIn` while planning, `SkipButton` during the resolve reveal; none during the debate, which sets `PrimaryOptional`). Side column order: reveal → event (first in Choice weeks) → state card → event → debate prep → plan list → week card, so prep is always above the plan and Lock in (B2). The event card is hidden during every reveal (B1). Region poll gets a button (B3) using `PlanDraft.regionOf` and the server's existing RegionPoll action (`REGION_POLL_COST`); the client offers one region poll per region per week. Message chips: `PlanDraft.messageChoices` (≤ `PlanDraft.MESSAGE_CHOICES` = 5, a UI number, best first). Map marks carry `arrow = "up"` and `arrowColor` (the leader's color) where the momentum lead is ≥ 0.5 (a display threshold in `Campaign.luau`, not a rule). The state card stays up read-only during the resolve reveal. Clear is two-tap (3 s). No Config numbers changed.
- **WP4, Draft and Election night.**
  - **WP4 (Draft, Election night).** Both screens use `Header` and `ActionBar` and are strict in the UI audit (their `Audit.PENDING` and `Tokens.spec` entries are gone; only the map's `NodeMap` entry still applies to them). Big boxes are explicitly positioned so the fake engine can measure them: on phones the map is `min(width / MapLayout.ASPECT, 34 %)` of the height on Draft and `38 %` on Election, the panel starts `Kit.space.sm` under it, re-laid out when the screen size changes. Draft: the state list follows the pick chips; the legend and board sit under the map on 16:9 and in a collapsed `Collapsible` at the end on phones; the map reveal puts the legend in the panel and sets `PrimaryOptional` (as does a round's reveal). An illegal tap or a rejected lock-in is the bar's status (tone bad) until the next tap; no timed hint. Draft titles drop the round kind in portrait (the help line starts with it), because the header's title and timer share one 44 px row. Election: one 72 px strip, one shared bar with fills from both ends and the 270 tick inside a 22 px box; the banner replaces the strip at the end; the opponent's status comes from their seat (`skip`, `connected`), not only ours. No sim, payload or Config change.
  - Element names that changed for agents: Draft's `LockBar`/`LockStatus`/`OpponentStatus`/`Hint`/`ClearChoices` are gone (use `ActionBar`, `BarStatus`, `BarOpponent`; `Clear1`/`Clear2` remain); the header title is `Header > … > Title`, its subtitle keeps the name `Explain` on Draft and `CallStatus` on Election. Draft's Lock in reads "Lock in" / "Locked in" (was "Lock In" / "Locked"); Election's Skip reads "Waiting for opponent…" after the tap (was "Waiting for opponent to skip…").

## Playtest 1 fixes (v0.4.1)

### D-031 — Display rules from the first agent playtest (Oct 22, 2026, no Config changes)

- **Money floors.** Every money display floors to $0.1 with the validator's 1e-9 slack (`UI/Numbers.money`); prices round up (`Numbers.cost`); points round to one decimal; signed numbers never read "+-" or "-0.0". *Why:* cash is fractional while costs are whole or tenths, so rounding to nearest showed "$5.0" for $4.96 and a $5 plan was rejected. The validator (`Plan.validate`, `cost.cash > cash + 1e-9`) was right and is unchanged.
- **Money rejections are explained on the client.** The server still sends only `NotEnoughMoney`; the client knows its own plan and cash and builds "Plan costs X, you have Y (items)" from `PlanDraft.costItems`. No wire change.
- **Color clashes are announced.** The rule is unchanged: a seeded shuffle orders the players, the first keeps a clashing color, the rest get the first free color (`Match` resolveSelect). `tests/sim/Match.spec` checks over 400 seeds that neither seat is favored (D-001). New: `PlayerState.pickedColor`, and `PlayerView.pickedColor` for the viewer only, after Select. The client toasts the change once per match (`Colors.clashNotice`).
- **Nominated strongholds are shown as battlegrounds.** A nominated state stays in its drafter's `strongholds` list (and keeps `owner`) but has no bonus (PLAN.md "Battlegrounds"); `UI/Drafted.strongholds` splits the list for every screen. Sim unchanged.
- **Debate scoring checked against the docs** (playtesters felt prep did not matter): `Debate.resolve` matches D-019 (roll 0..6, 0.2 per topic, sweep 0.2, gaffe 0.2) and the PLAN.md formula otherwise. PLAN.md "Debates" still quotes the pre-D-019 numbers (roll 0..2, +0.8 per topic, +0.5 sweep, -0.5 gaffe). With a 0..6 roll a 2-point prep edge (the most a 4/2 split moves one topic) still ties or loses about 3 times in 10, and platform (+2) and debate stat count as much as prep, which is what the testers saw. Left for the humans with the other balance notes. (Resolved in balance pass 2: D-033 retuned debates and updated PLAN.md.)


## Explaining the numbers (v0.5.0)

### D-032 — Explaining the numbers on screen (no rule changes)

- **One pure explainer.** `Shared/UI/Explain` turns Config, Candidates and the player's own View into words. It requires Sim modules read-only and calls their formulas (`Resolve.issueMult`/`attackMult`/`closingMult`, `Support.saturation`, `Polls.underdogMults` on a stand-in, `Events.supportMult`/`fundMult`/`choicePayoffs`, `Plan.isAdjacent`, `Leans.startingSupport`; pool size from the View's `capacity`), so a Config or candidate change (including Strand's perk or the Choice matrix) shows up with no edit. It copies only the order of Resolve's steps (gain split, repeat-ad factor, backlash meter, pool sharing), which a sim change would also need to update; `tests/ui/Explain.spec` pins them.
- **Honest about what is hidden.** The sim reads true support; the preview uses your internal poll of that state if you have one this week, else the public poll ("about"). Fundraise is "up to about": the pool's level is hidden (`View` never includes it), so the preview assumes a full pool shared only with your own earlier fundraisers. Event bonuses are capped at `EVENT_CAP` as if nothing else in the state used the cap. Nothing new is sent to the client.
- **Momentum is explained as it works.** The request suggested "adds to rallies"; in the sim momentum never changes a rally, it drives drift (`DRIFT_RATE` per point of lead, capped). The card says that, with next week's drift if nobody campaigns there (both sides' decay applied).
- **Debate rolls are derived.** The result carries prep and the total; the roll is total − prep − platform bonus − debate stat. The breakdown is shown in the debate week only, before a later pivot could change the platform; out-of-range values print as "other" instead of a false roll.
- **Election odds.** "A 3-point poll lead holds about 80%" uses a normal margin error of sqrt(POLL_SIGMA² + ELECTION_SIGMA²), ignoring ground game and poll rounding.
- **Help overlay.** `UI/Help` is mounted once by App above the screens (ZIndex 40, below the toast's 50) and opened through `ctx.help` from the header "?" (`Header.new{ onHelp }`). It is its own audit root ("Help"), with one pinned primary (Close), so the screen underneath keeps its own single primary. The header countdown column shrank from 150 px to 72 px unless `setTimerLabel` is set.

Limits: The previews are expected values from the start-of-week snapshot. They do not model the opponent's simultaneous moves in the same state, drift, or support moved by earlier actions in your own plan (each step reads one snapshot, so this matches the sim within a step). The help screen reads Config, so its debate numbers follow D-033.

## Balance pass 2 (Oct 22, 2026, v0.5.0)

Evidence: six agent playtesters, three full matches through `tests/duel.luau` (277–261, 273–265, 289–249; fun 6–8/10), learning only from the screens. Their consistent balance notes: debates barely matter and prep does not visibly win topics, so Hale (8 prep, $0) is the weakest pick; fundraising is a week-1 bonanza at home and dries up after; Strand's free polls look worthless because public polls cover every state every week; Choice events feel like a trap (Attack lost both times, Defend paid nothing). The humans approved a pass on those four areas (debates, fundraising, Strand's perk, Choice payoffs); everything else here is tuning or a proposal.

**Targets, stated first** (harness, 2,000 matches, defaults; pass 1's targets still apply):
- Debates: a 2-point prep edge wins its topic ≥ 75% and loses ≤ 12% (arithmetic on the roll, `Config.spec`); a 4-point edge always wins; debates change the winner in 15–30% of matches (was 16.4%) and swing 20–40 EV on average (was 15.3), i.e. a sweep is worth about one big close state, "a week of good campaigning".
- Fundraising: a home state worked once a week pays within 10% of the same amount every week (`Resolve.spec`); three week-1 home fundraisers raise under $10 (was $18–20); the harness's new "raised in weeks 1–3 / weeks 10–12" ratio ≤ 1.5; average money raised stays within 25% of pass 1's $50 so money is not irrelevant.
- Candidates: all eight in 45–55%, Hale and Strand included; Hale's topic win rate ≤ 60%.
- Choice: every exchange pays the winner a positive and the loser a negative number; each answer is the unique best reply to some answer; the bot's equilibrium mix plays every answer ≥ 15%; every payoff under a debate sweep and inside `EVENT_CAP`.
- Unchanged: D-005 (match ≤ 15 min; no timer changed), priority-A 47–53%, comeback 20–40%, blowout targets of D-024.

### D-033 — Debates: roll 0..3, 0.3 per topic, sweep 0.3, gaffe 0.3 (tuning)

`DEBATE_ROLL_MAX` 6 → 3, `DEBATE_TOPIC_WIN` 0.2 → 0.3, `DEBATE_SWEEP` 0.2 → 0.3, `DEBATE_GAFFE` 0.2 → 0.3. A sweep is now worth 1.2 national points (was 0.8); `Config.spec` pins 1–2.

*Why:* D-019 widened the roll to 0..6 to stop Hale's then flat +1 stat from being a lock. Hale's edge is prep now (D-023), which a player chooses where to stack, so the roll can shrink: against 0..6 a 2-point prep edge (the most a 4/2/0 split moves one topic against 2/2/2) won 69% and lost 20%; against 0..3 it wins 81%, ties 12%, loses 6%, and a 1-point edge wins 62% (0..2 made it 89%: a lock again). The payoff rose because 0.2 per topic moved a state by 0.2–0.4 points and nobody could see it; 0.3 is the most the blowout targets allow (grid, 2,000 matches each, roll 0..3: 0.3 per topic → debates decide 22%, 40+ EV 63.8%, 100+ EV 24.2%; 0.4 → 25%, 66.6%, 29.3%; 0.5 → 29%, 70%, 33%). The national shift still lands hardest on the tied block of undrafted states (D-019), which is why it cannot go higher without a map or bot change (listed under proposals).

*Result:* debates change the winner in 19–21% of matches and swing about 21 EV; topic win rates 38% (ties are the rest), Hale 54%. `Election.spec` plays 150 debates with a 4/2/0 vs 2/2/4 split and checks the 2-point edge wins ≥ 72% and the 4-vs-0 topic always. `docs/PLAN.md` "Debates" now quotes these numbers (it still had revision 1's).

### D-034 — Fundraising: pools start half full, refill 50%, home ×1.25 (tuning)

New `POOL_START` 0.5 (a new match's pools hold half their capacity), `POOL_REFILL` 0.25 → 0.5, `HOME_FUNDRAISE_MULT` 1.5 → 1.25. Capacities (`POOL_BASE`, `POOL_PER_MILLION`, `POOL_MAX`) and the yield formula are unchanged, so D-012's "no pool funds three fundraisers" still holds.

*Why:* with full pools and a 25% refill, two home fundraisers in week 1 raised $14–20 and the same state paid $4.5 a week from week 5 on (playtest: "$13–16 early, $4–5 once pools drain; funds worthless in week 12"). A pool that refills half its capacity a week covers one plain fundraiser (the biggest states' 12 × 0.5 = 6 ≥ a 47%-support yield of 4.8), so a state worked weekly pays the same every week: a home state $5.6–6.0 for a plain candidate, every week (model and `Resolve.spec`), and three week-1 home fundraisers $7.5 instead of $18. The home multiplier came down because home funding was the whole economy ("fund PA ×2 = $16 beats any other fund").

*Harness:* money raised per player $50.1 → $41.5 (the bot fundraises when rallies are not worth it, and it still can), weeks 1–3 / 10–12 ratio 1.02 → 0.58 (the bot now fundraises more late, when pools are full and rallies saturate), GOTV decides 10.0%, FundraiseOnly 18% (was 2%: a steady economy makes fundraising a real strategy; still far under 55%). Refill 0.35 and 0.4 were tried: $38–40 raised, ratio 0.6, no better on any flag. The flat economy moved the money-shaped candidates hard (Okafor 54 → 65%, Venkat 54 → 67%, Strand 45 → 37%, Reyes 46 → 40%), which pass 1 predicted ("money-shaped perks register weakly" while money dried up); D-037 retunes them. Week 12 fundraisers still arrive too late to spend: a UI warning is proposed, not a rule change.

### D-035 — Helen Strand previews next week's event (approved reshape)

Perk: "Sees next week's event a week early; two free internal polls a week" (was the polls alone). Drawback unchanged. Data: `Profile.eventPreview` (weeks ahead; 1 for Strand, 0 for everyone else). `View.nextEvent` carries week w+1's event, during week w's Plan and Debate phases, for a viewer whose candidate has `eventPreview ≥ 1`; nothing for week 11 (week 12 has no event), after the campaign, or with events off. The debug board prints it as `Next week's event (your pollster's briefing): …`; the campaign screen is the client agent's. The bot uses it: with a Regional due next week it ends the route in that region (saving the flight and starting the ×1.5 rallies in place).

*Why:* the playtesters were right that two ±1 polls add little when the public table shows every state weekly (D-002's persistent error is real but invisible to them). D-027 refused to preview events for everyone because a preview rewards flying into a Regional a week early for free; as one candidate's perk that is exactly the information edge the Pollster is meant to have, and it is a decision every week (position for the Regional, hold cash for a Windfall where you trail, hold media for a Spotlight issue, expect a Choice). It respects the leak rules: only `View.build` adds it, only for her seat, only one week ahead; `View.spec` checks her opponent's view has nothing, that changing any deck entry beyond week w+1 leaves her view byte-identical, and that the forbidden `eventDeck` key never appears.

*Harness:* 45.4% → 45.7% with the preview alone (the bot uses only the Regional case). Alternatives considered: sharper public polls for her view (would leak true support by subtracting the two polls), exact internal polls (more of what the testers found useless), the opponent's exact cash (not a pollster).

### D-036 — Choice payoffs: winners gain, losers lose (tuning)

| | vs Attack | vs Defend | vs Ignore |
|---|---|---|---|
| **Attack** | −0.2 (mudslinging) | −0.3 (backfire) | **+0.3** (it lands) |
| **Defend** | **+0.2** (turned around) | 0 (quiet week) | −0.2 (looks weak) |
| **Ignore** | −0.2 (it lands) | **+0.2** (above it) | 0 |

Still a cycle (Attack beats Ignore, Defend beats Attack, Ignore beats Defend), so no answer is dominant; in margin terms the edges are 0.59 / 0.56 / 0.46 and the bot's equilibrium mix is Attack : Defend : Ignore = 29 / 37 / 35% (was 21 / 48 / 31). Every payoff is inside `EVENT_CAP` and under a debate sweep (`Config.spec`).

*Why:* the D-027 matrix paid 0 to a successful Defend or Ignore and −0.2 to both players in two of the three mirror cells, so the only outcomes a player ever saw were "Attack −0.3" and "nothing": a trap with a hidden rulebook. With the UI about to show the matrix (another branch reads these Config keys), each cell has to read as a reason to pick that row. A landed attack (+0.3) is worth one debate topic. A first draft at +0.4 / +0.3 / +0.2 pushed 100+ EV blowouts to 26–27% (the national shift hits the tied block, D-019), so the numbers were scaled to ±0.3 with the mix kept even. `Helpers.spec` and `DebugUI.spec` lines that quoted the old cells were updated.

### D-037 — Candidates retuned for the flat economy (tuning + one bot heuristic)

Measured with D-033 to D-036 in place, one change at a time in copies of the tree at 3,000 matches (±3.6 points per candidate), then the package at 6,000 (±2.5).

| Candidate | Change | Before → after | Why |
|---|---|---|---|
| Dana Okafor | fundraisers +50% → +25% | 65% → 54% | Pass 1 raised the perk because money barely registered; with pools that refill, it does. +25% alone brought Reyes (40 → 46%) and Alvarado (44 → 46%) back too, because Okafor had been beating them 2:1. |
| Priya Venkat | income $3 → $2; repeat buys keep 70% → 65% | 67% → 55% | Cheap ads convert a steady economy best. Income $2.5 measured 57%, $2 alone 54–55%, saturation 0.6 alone 61%. Still at the line (55.5 ± 2.5 at 6,000); a third notch is listed under proposals rather than taken, because her perk is the point of the candidate. |
| Marcus Hale | prep 8 → 7 | 57% → 49% | With debates that decide topics, two spare prep points were worth about +8; one is worth about +1 over the field (topic win rate 48%, others 38–40%, the rest ties). "Income $3.5" with 8 prep measured the same (50%) but doubled a money drawback humans already feel. |
| Helen Strand | media −15% → −10% | 37% → 44% | See below. |
| Bot | `gotvPremium` 1.2 → 1.3 (heuristic, not a rule) | GOTV decides 9.4% → 10.0% | The flat economy pulled the bot's late money into closing-week ads; the premium restores the D-021 spend (about $8 a player). |

*Strand.* Her number is the harness's known blind spot, not a drawback problem: with no drawback at all she measured 47.4% (3,000 matches), because the bot cannot use information (NeverPoll sits at 54–56% in every pass, D-022, D-027) and uses the preview only for Regional weeks. Every drawback shape then costs its usual 3–5 points: media −5% 44.9%, start $4 44.3%, media −10% 43–44%, −15% 37–41%. −10% was kept (the D-022 number) so humans feel it. A bot that reads the preview more widely (hold cash for a Windfall, hold ads for a Spotlight) is the fix, under proposals. Alvarado (44–47%) is the same story for start cash (D-022: the bot cannot spend it early) and Begay (48–49%) is within noise.

### D-038 — Balance pass 2: final harness report (Oct 22, 2026)

`lune run tests/harness/balance.luau`, 2,000 matches (the standard run) with the 6,000-match run in brackets where they differ by more than noise. "Before" is the pass-1/events report (D-027, the start of this branch).

| Check | After | Before (D-027) | Target |
|---|---|---|---|
| Candidates | Okafor 54 [55], Calloway 53, **Venkat 59 [55.5]**, Hale 49, **Alvarado 44 [47]**, Reyes 47 [49], **Strand 44**, Begay 49 [48] | 47–55 (Hale 48, Strand 47) | 45–55% |
| Worst matchup | Venkat vs Strand 70% [65%] | Strand vs Begay 33% | 40–60% (noise ±12 at 71 games) |
| Priority A win rate | 50.3% | 51.7% | 47–53% ✓ |
| Comeback rate | 36.6% | 38.3% | 20–40% ✓ |
| Median margin / 40+ EV / 100+ EV | 58 / **65.0%** / **25.6%** [24.7%] | 54 / 62.4% / 20.1% | ≤ 60 / ≤ 65% / ≤ 25% |
| Money raised per player / weeks 1–3 ÷ 10–12 | $38.1 / 0.57 | $50.1 / 1.02 (measured on this branch) | within 25% / ≤ 1.5 ✓ |
| GOTV changes the winner (spend) | 10.1% ($8.3) | 11.8% ($7.6) | ≥ 10% ✓ |
| Debates change the winner (EV swung) | 17.7% (19.3) [19.2% (20.1)] | 16.4% (15.3) | 15–30% (20–40) ✓ |
| Debate topic win rates | 38–40%, Hale 48% | 41–44%, Hale 53% | Hale ≤ 60% ✓ |
| 2-point prep edge wins / loses a topic | 81% / 6% | 69% / 20% | ≥ 75% / ≤ 12% ✓ |
| Underdog wrong-leader weeks / tier changes | 18.9% / 3.19 | 21.8% / 3.10 | < 10% / ≤ 3 (D-020: structural) |
| Random / fundraise / rally / attack / never-poll / sandbag | 0 / 15.5 / 42.5 / 41 / 51 [55.2] / 39% | 0 / 0.8 / 43 / 40 / 54.5 / 40% | ≤ 5, < 55, ≤ 50 |

Red after this pass: Venkat and the 40+/100+ EV shares sit on their lines (noise-level at 2,000, inside at 6,000 for 100+ EV), Strand and Alvarado are the information/start-cash blind spots (D-037), the two rubber-band flags are D-020's, and NeverPoll is the pass-1 poll-value question. Everything that passed in D-027 still passes except the one matchup cell, which moves with the seed set.

*Proposals for the humans (not done here; each changes a mechanic's intent or a part another branch owns):*
1. **The tied block** (D-019, D-024) is what caps the debate and Choice payoffs: about 13 undrafted, unleaned states finish at exactly 35/35 in bot games and any national shift decides all of them at once. Humans rally those states (the playtesters did), bots do not. A bot that values tipping-point states, or leans on more states, would let debates be worth more than 0.3 a topic.
2. **A bot that reads Strand's preview** beyond Regional weeks (hold cash for a Windfall, hold ads for a Spotlight issue), and values polls at all, so the harness can measure information perks. Until then Strand and Alvarado will read 44–47%.
3. **Week-12 fundraisers** still pay money nobody can spend. The screen should warn (client branch); a rule change (e.g. week-12 fundraisers add to the popular vote tiebreak) was not approved.
4. **Calloway's 4th AP vs Okafor** and **nominations stripping big strongholds**: the playtesters flagged both; the harness has Calloway at 53% and the lean/draft checks green, so nothing was changed. If the humans want nominations softer, "a nominated stronghold keeps half its bonus" is the smallest rule change to test.
5. **Venkat** at the 55% line: "media $2.5" or "income $2 and repeat buys keep 60%" are the next notches if human play confirms her edge.

## Issue-based choices and debates (Oct 22, 2026, branch `issue-choices`)

Approved by the designers after playtest 2: Choice events and debates must be skill-based, tied to each state's issues, and visibly matter. Their words: debates deciding about one match in five is fine, but "in those 20% of games it isn't obvious that the debates did anything unless you do a nerd breakdown of the stats"; the D-036 Choice matrix "has caused confusion and made choice events feel too random", and the direction is "a right answer would be helpful, but it may decrease the politician's popularity in states where that position is unpopular, so you have to answer based on the issues of the states you need to win." Both mechanics' intent changed, which they approved. Every spec below failed before the code.

### D-039 — Choice events are stances on an issue (approved reshape)

**Rules.** The deck has 24 cards: the eight Spotlights, five Regionals and three Windfalls of D-027 plus **eight Choice events, one per issue** (`Sim/Events.luau`: `plant` Jobs, `walkout` Health, `calendar` Schools, `river` Environment, `patrol` Safety, `toll` Transit, `datacenter` Technology, `water` Farms). A match deals 10, so it sees about 3.3 Choice weeks (0.4% of matches see none). Each Choice event is a fictional dispute over its issue and offers three stance slots, always in this shape: **A** and **B** are opposed sides, **C** is the hedge. A stance is data: a name, a line of flavor, and the issues it `likes` and `dislikes` (B likes what A dislikes and vice versa; C likes nothing).

A state with the event's issue among its two top issues reacts by its *other* top issue: if the stance likes that issue, +`STANCE_POINTS` (1.5) support for the candidate who took it; if it dislikes it, −1.5; otherwise +`STANCE_HEDGE` (0.5). Every other state hears a side a little through its own top issues: +`STANCE_SPILL` (0.5) per issue the stance likes, −0.5 per issue it dislikes (so a state whose two issues are one liked and one disliked does not move). The hedge gives +0.5 in every state with the issue and nothing elsewhere. A candidate whose platform carries the event's issue is heard harder in the issue's states: ×`STANCE_PLATFORM_MULT` (1.5), clamped to ±`EVENT_CAP` (2). Gains use the normal undecided/opponent split, losses go to undecided, and both players' stances are applied together from one start-of-step snapshot (D-001), after pivots, where the D-036 shift used to be. A missing stance, an empty plan or a timeout is the hedge (`Events.defaultChoice()`); any value outside `"A" | "B" | "C"` is `BadChoice`, a stance outside a Choice week `UnexpectedChoice`, exactly as before.

**Why this shape.** The reaction is a pure function of fixed state data (`StateData` issues) and the public platform, so the same event moves the same states the same way in every match and a player can learn them; the client previews every stance on the map with the same function the server applies (`Events.stanceEffects(config, event, id, platform)`, `Events.stanceEffect` per state). The "right" answer is the stance whose moves are worth the most in the states *you* need, so it differs per player and per map, and there is nothing to guess about the opponent (the matrix is gone). Camps were drawn so each side's liked states hold at least a quarter of the issue's EV (spec), e.g. Jobs: A (Transit, Farms camp: GA, IN, MI, NV, SC, DE, IA, ND, 69 EV) against B (Health, Safety camp: AL, KY, PA, IL, TN, 66 EV), with OH, LA indifferent. The issue's states (8–15 of them) carry the big moves; the spillover (D-041) makes the rest of the map lean a little toward one side or the other, so a stance is about 25 points of gross movement that nets near zero, not a national shift that lands on the tied block (D-019). The hedge is the sure, small answer: with every camp state close it is right, and the bot takes it about one week in ten. Platform credibility is the one asymmetry between two candidates who say the same thing, and it gives platform choice a job beyond debate topics (playtest 2: "platform choice feels solved").

**What the clients get.** `View.event` for a Choice week carries `issue` and `stances = { { id, name, text } × 3 }`. After the week, `View.eventLog[k]` carries `choices` (each player's stance), `moves` (`{ state, points = { per player } }` for every state that reacted) and `flips` (leader changes projected on the start-of-week public polls: `Polls.projectFlips`, public arithmetic), and the week card's `choice` is the stance. The resolve event stream has one `Choice` event per player (`issue` = the stance id, `amount` = its points summed over states). Hidden: nothing new leaves the server; `StateSim.stanceShift` (the support each stance actually moved, for the harness recount) is forbidden in `View.spec` like `debateShift`.

**Rejected.** (1) Reactions by region instead of the other top issue: easier to see on a map, but the designers asked for issues, and a region split does not teach the state data. (2) Reactions that depend on the public poll (a stance wins over states you trail in, hurts where you lead): asymmetric and good for comebacks, but then the same event reacts differently every week and the leader always hedges. (3) Two stances only: the hedge is what makes "I need both camps" a real answer instead of a coin flip. (4) No spillover, `STANCE_POINTS` 2.0, `STANCE_HEDGE` 0 or 0.3, a stronger platform multiplier: none of them made the decision worth more than 52–54% against random stances (D-041); the spillover did.

### D-040 — Debates move states, not a national average (approved reshape)

**Rules.** The roll (0..3), prep, platform bonus and stat are unchanged, so a 2-point prep edge still wins its topic 81% of the time and loses 6%. What a topic is worth changed: winning it adds `DEBATE_TOPIC_WIN` (1.0) support in **every state where that topic is a top issue** (`Debate.topicStates`, fixed data) plus a flat `DEBATE_TOPIC_NATIONAL` (0.1) in every state; losing a topic you put 0 prep on costs `DEBATE_GAFFE` (0.6) in that topic's states; a 3–0 sweep adds a flat `DEBATE_SWEEP` (0.2) everywhere and the usual battleground momentum. Gains use the normal split, losses go to undecided, everything from one snapshot. Then the public polls are **republished with the same error terms** (`Polls.refresh`, no new draw), so the map and the projected EV show the debate the moment the week's plan opens.

**Why.** The old national shift was undecided-weighted (×undecided ÷ mean undecided), so its per-state effect leaked true undecided and could not be shown; 0.3 of it per topic was invisible on any single state. A topic win is now a visible +1.0 in 8–13 named states, "your Jobs win swung OH, MI and PA". `DEBATE_TOPIC_WIN` 1.2 measured debates deciding 25–26% of matches (target 15–25%), 1.0 measured 24%; the national part is deliberately a nudge (0.1 on a 35/35 tied-block state is nothing against election noise of 2), it exists so a debate is felt everywhere a little. The gaffe is worth more than before (0.6 in the topic's states against 0.3 national) because it is now a named, local cost. The poll republish is what makes the debate "obvious": before, the week-4 plan opened on polls that predated the debate.

**What the clients get.** `DebateResult` adds `gaffes` (`[player][topic]`), `moves` (`{ state, points = { per player } }`, the targeted points: topic wins and gaffes; the flat `national` per player applies everywhere on top) and `flips` (states whose public-poll leader changed when the polls were republished, with `from` and `to`, 0 = tied). The resolve events add one `PollFlip` per flipped state (`state`, `player` = new leader, `amount` = its EV, `issue = "Debate"`). `Debate.topicStates(topic)` and `Debate.odds(config, edge)` are public helpers for the prep screen. No-leak: every number in `moves` is public arithmetic on the result; the republished poll differs from the previous one by exactly those points (rounded), both of which are public.

### D-041 — Bot, skill check and the harness report (Oct 22, 2026)

**Bot.** `Bot.choose` takes the stance whose public per-state moves (`Events.stanceEffects`, with its own platform) are worth the most expected EV on its map: each state's points as margin (a gain also takes 1 − `GAIN_FROM_UNDECIDED` from the opponent; a loss goes to undecided) weighted by `EV × pdf(margin ÷ sigma) ÷ sigma`, the same closeness weight the rest of the bot uses. Ties go to the first slot, so no seat is favored. `Bot.prep` values each topic by what its states (plus the flat part everywhere) would be worth, then tries every legal split of its prep points (at most `DEBATE_MAX_PER_TOPIC` each) against `Debate.odds` of the edge over an opponent assumed to spread evenly, counting a zero's gaffe risk; the exhaustive search replaced a greedy one because the roll makes returns convex near a big deficit (the first point on a lost cause buys nothing, the fourth buys the topic). `Bot.spec` checks the stance follows the camp it needs (A, then B, then the hedge when both camps are close) and the prep follows the topic whose states are close. New style `RandomStance`: the standard bot with uniformly random stances.

**Skill check.** `tests/harness/skill.luau` plays the standard bot against `RandomStance` (seats alternating, two different candidates per match) and the balance harness repeats it at 800 games. The target is a RandomStance win rate ≤ 45% (the bot that reads the map wins ≥ 55%). The first numbers (`STANCE_POINTS` 1.5, `STANCE_HEDGE` 0.3, no spillover) measured **47.9% ± 1.5** over 4,000 matches: the decision was worth about 2 points of win rate. The reason is structural and worth knowing: both bots weigh the same close states, so they took the same stance in **91–93%** of Choice weeks, and two candidates who say the same thing move the same way (the recount with the stances removed changed the winner in only 3–4% of matches). Tried and rejected at 2,000 matches each: `STANCE_POINTS` 2.0 (46.0%), `STANCE_HEDGE` 0 (46.8%), a ×2 platform multiplier on 1.0 points (45.0%). What worked was the **spillover** (`STANCE_SPILL`): states that do not have the issue still move ±0.5 per top issue of theirs that a side likes or dislikes, so a stance is a map-wide tilt whose sign a player can read off the state data, not a nudge to a dozen states. 0.25 → 42.5%, 0.35 → 41.4%, 0.5 → 34.8%; with the hedge raised to 0.5 so it stays a real answer, 36.0%, and **39.0% ± 1.5 at 4,000 matches** once the platform multiplier was kept out of the spillover (an early build let it leak there). Final: `STANCE_SPILL` 0.5, `STANCE_HEDGE` 0.5: the bot that reads the map wins 61% of otherwise mirrored matches.

**Debates.** `DEBATE_TOPIC_WIN` 1.2 measured 24.9–26.4% of winners changed by the recount at 2,000 matches; 1.0 measured 23.8–25.4% and swings about 21 EV, so 1.0 is the number (the target band is 15–25% and 1.2 sat on its edge). Hale's topic win rate is unchanged at 47% (others 38–41%), so the prep perk is neither stronger nor weaker than in D-037.

**Harness report** (`lune run tests/harness/balance.luau`, 2,000 matches; "before" is the D-038 report measured on this branch's start).

| Check | After | Before (D-038) | Target |
|---|---|---|---|
| Candidates | **Okafor 57.7**, Calloway 50.3, **Venkat 56.7**, Hale 45.3, **Alvarado 44.8**, Reyes 49.8, **Strand 44.8**, Begay 51.1 | Okafor 54, Calloway 53, **Venkat 59**, Hale 49, **Alvarado 44**, Reyes 47, **Strand 44**, Begay 49 | 45–55% |
| Worst matchup | Alvarado vs Okafor 36% | Venkat vs Strand 70% | 40–60% (±12 at 71 games) |
| Priority A / comeback | 50.9% / 39.0% | 50.3% / 36.6% | 47–53% / 20–40% ✓ |
| Median margin / 40+ EV / 100+ EV | 52 / 61.3% / 20.8% | 58 / **65.0%** / **25.6%** | ≤ 60 / ≤ 65% / ≤ 25% ✓ |
| Money raised / weeks 1–3 ÷ 10–12 | $37.1 / 0.58 | $38.1 / 0.57 | ✓ |
| GOTV changes the winner (spend) | 12.2% ($8.4) | 10.1% ($8.3) | ≥ 10% ✓ |
| Debates change the winner (EV swung) | 23.2% (21.5) | 17.7% (19.3) | 15–25% (20–40) ✓ |
| Topic win rates | 38–41%, Hale 47% | 38–40%, Hale 48% | Hale ≤ 60% ✓ |
| Choice stances change the winner (EV swung) | 5.1% (4.7) | — (matrix: not measured) | informational |
| Choice events per match / stances A, B, C | 3.32 / 44, 36, 20% | 2 (4 of 20 cards) | — |
| Both players took the same stance | 90.7% | — | informational |
| RandomStance win rate | **39.1%** (39.0 ± 1.5 at 4,000) | — | ≤ 45% ✓ |
| Underdog wrong-leader weeks / tier changes | 17.4% / 3.12 | 18.9% / 3.19 | < 10% / ≤ 3 (D-020: structural) |
| Random / fundraise / rally / attack / never-poll / sandbag | 0 / 10.2 / 38 / 42 / 54.5 / 42% | 0 / 15.5 / 42.5 / 41 / 51 / 39% | ≤ 5, < 55, ≤ 50 ✓ |

Red after this pass: the candidate band is where pass 2 left it, at noise level (±2.2 per candidate at 2,000 matches; across five runs of this branch Okafor measured 53.5–57.7 and Venkat 53.4–59.0, so Okafor is the one genuinely over the line, by a point or two, and Alvarado and Strand are the D-037 blind spots), one matchup cell at noise level, and the two D-020 rubber-band flags. The blowout shares fell under their lines, because the debate's national shift no longer decides the tied block (D-019) all at once.

*For the designers.* (1) The symmetric-bot wash (both take the same stance 93% of the time) will be smaller between humans, who weigh "my base" and "their base" differently; the human-side check is in `docs/TESTING.md`. (2) The stance texts in `Sim/Events.luau` are placeholders in the "side with X" shape; the camps (which issues each side likes) are the balance-bearing data and are listed in each event's definition. (3) Debates at 25% of winners changed is the top of the agreed band; `DEBATE_TOPIC_WIN` 0.8 is the next notch down if human matches feel debate-heavy.


## Screens for stances and debates (v0.6.0)

### D-042 — Show what stances and debates move, on the map (no rule changes)

The designers, after the rules pass (D-039, D-040): debates deciding about one match in five is fine, but "it isn't obvious that the debates did anything unless you do a nerd breakdown of the stats"; a Choice event should make a player "calculate whether or not they should get popular in one state cuz it could decrease their popularity in a state they are relying on". No `Sim/` file, Config number, payload or View field changed.

- **One pure helper, `Shared/UI/Swing`.** It turns the sim's public arithmetic into what the screens say: `Events.stanceEffects` for a stance, `Polls.projectFlips` for leader changes (called on a stand-in `{ states = view.states }`, since `StateView` carries the `id` and `poll` it reads, in match order), `Debate.topicStates` and `Debate.moves` for a debate. The client, the F2 board and the duel harness all print its lines, so the three never disagree. `tests/ui/Swing.spec` pins the numbers, `tests/ui/Stances.spec` the screens.
- **"States you need" is public and concrete:** a state is in play when its public-poll margin between you and your best rival is within `Explain.IN_PLAY` = 5 points either way (a UI number; a 5-point lead holds about 92% on election night by `Explain.leadWinChance`, so anything inside it can still go either way). The event card lists them ("you trail WI by 2 · you lead OH by 3 · tied NV") with your projected EV. A stance's summary counts its gains among them ("4 you need: OH, PA…") and names the states you lead where it loses, closest first ("2 you lead: KY by 3…"). *Rejected:* "states the projection gives you narrowly" (the same set, said less plainly), and an EV-weighted "worth" number (the bot's closeness weight, D-041: correct but opaque to a player).
- **Stance preview on the map.** While the event card is open in a Choice week, the map shows the selected stance (default C): gains as a "+1.5" badge in your color with a soft glow, losses as a red "-1.5" badge, a state whose public-poll leader would change as FLIP with a strong glow, untouched states dimmed. Holding a chip previews that stance without selecting it; collapsing the card gives the usual map back. The flips are on today's polls from your stance alone: the opponent's stance is secret, so the preview never guesses it, and says so in the help text. Chips are full width so stance names fit on a phone; the hedge reads "(hedge, default)".
- **Debate reveal.** Each topic row adds one line, "Your Jobs win swung OH, MI, PA, GA, NC +4 more (+1.0 each) - PA flipped to you (+19 EV)", heading size and bold when a state flipped, and a red gaffe line. A flip is credited to the first topic (in order) whose states include it and that had a winner or a gaffe; flips no topic explains (the flat +0.1 or the sweep) are listed after the last topic. The map badges the net targeted points toward you (your color) or them (their color) as each topic lands, with FLIP in the new leader's color. The flat part is left out of the badges because it is the same small number everywhere and is in the summary ("Every state also got: you +0.2 · them +0.1").
- **Resolve reveal after a Choice week.** Once the stances are read out, the panel says what each side's stance gained and lost and which leaders they flipped on the polls both players saw (the server's `EventResult.flips`), the flip as a heading-size callout, and the map badges the net points per state. The week card repeats it next week.
- **Results: "What decided it".** The states debates and stances flipped on the polls, to whom and for how many EV, which of them the flipped-to side then won on election night, and the final gap against how far the flips moved the projected gap. These are poll flips, not a recount (the harness's counterfactual uses hidden true support): honest, and short.
- **Map marks.** `MapInterface.Mark` gains `badgeColor`, `halo`/`haloStrong` and `note`/`noteColor`; the halo is capped at the tap target so it stays inside the map.
- **Stopgaps replaced:** the rules pass's Choice effect line ("Take a stance: A / B / C"), the long `choiceNote`, `choiceVerb`, the Choice part of `lastEventLine`, Reveal's "points over the states that reacted" caption, and the help text, which said only the issue's states react and that a topic win adds +0.1 "everywhere else" (it is every state).

Limits: the preview adds your points straight to the shown poll shares, as `Polls.projectFlips` does; the real week also splits gains between undecided and the opponent, moves the opponent's own stance and everything else in both plans. The debate's flips are real (the polls were republished); the stance flips in the reveal are projected on the start-of-week polls, as the server reports them.

## Your base hears your stance (playtest 3)

### D-043 — A stance counts double in your base; the hedge costs there (approved reshape, Oct 22, 2026)

**Playtest 3** (v0.6.0, four Sonnet players, evaluated by a Fable agent; notes in the session scratchpad): fun 8/7/8/7 and all four would replay, debates read clearly, but in 5 of 6 Choice weeks both players took the same stance and the reveal said "flipped no state", and the hedge was called "strictly good". The cause is structural: "states you need" (D-042) is the same set for both players in a 1v1, so both read the same right answer off the same data, and two candidates who say the same thing move the same way. The hedge was never wrong because a side's camps net near zero by design (D-039) while the hedge was always positive. The designers chose, from four options, "base-weighted reactions plus a costly hedge".

**Rules.** A candidate's base is their home and strongholds (`Events.baseOf`, public once the draft is revealed). A side (A or B) counts ×`STANCE_BASE_MULT` (2) in the taker's base, both in the issue's states and in spillover. The hedge moves no state at all, except −`STANCE_HEDGE_COST` (0.5) in each base state where the issue is a top issue: those voters want you to pick a side. The platform multiplier (×1.5) still applies in the issue's states, to the hedge's cost too. Stance points are clamped to ±`STANCE_CAP` (3), not `EVENT_CAP` (2), so a doubled liked reaction on your platform reads +3 instead of being cut to 2. `STANCE_HEDGE` (0.5) is now only what a side gives in an issue state whose other top issue it neither likes nor dislikes. `Events.stanceEffect(s)` take the base as a last argument; Resolve, Bot, the event card, the rules text and the duel screens pass it.

**Why.** Drafts differ, so the same event now has a different right answer for each player, still read off public data (the state's issues and your own draft): "this stance plays well in my strongholds" is the calculation the designers asked for ("whether or not they should get popular in one state cuz it could decrease their popularity in a state they are relying on"), now with your own states carrying the stakes.

**Harness** (2,000 matches; before = D-041): stances change the winner **14.6%** (5.1%), EV swung 14.2 (4.7); RandomStance win rate **34.0%** (39.1%), so reading the card is worth more; debates 23.2% (unchanged); comeback 38.3%; candidates Okafor 52.9, Venkat 54.9, Hale 51.7, Alvarado 46.0, Strand 44.6. The bots still take the same stance **83.8%** of the time (90.7%) and never take the hedge (0%): both bots weigh the same close states, and the base is only 5–7 states of 50, so the shared battlegrounds still dominate a bot's sum. Humans, who care more about "my states", should split more; the duel playtests are the check. Variants at 1,000 matches: `STANCE_BASE_MULT` 3 moved the winner in 17.2% but pushed Okafor to 57.7 and Venkat to 62.5 (rejected); `STANCE_HEDGE_COST` 0.25 left the hedge unused (C 0%); `UNDECIDED_FLOOR` 5 with `BATTLEGROUND_MULT` 1.3 (the evaluator's proposal against one-state tug-of-wars) did not change mirroring and dropped Hale to 39.7 (not adopted; the harness does not measure "one state decided it", so that needs a metric first).

*For the designers.* The hedge is now a niche answer: right only when both sides would cost you in your own base. If playtests show nobody ever takes it, a small positive outside your base (+0.25 in the issue's other states) would bring it back without making it the safe default again.

## Decision screens and the debate focus (playtest 3)

### D-044 — The stance and the debate focus get their own screen and timer; prep becomes one focus topic (approved, Oct 23, 2026, branch `decide`)

**Asked.** The designer, after playtest 3: "On weeks with debates or event choices, they should be on a separate screen before the week decisions with a separate timer" (the UI was overwhelming). Then, while this was being built: replace the 6-point prep spread with "pick 1 focus topic", one tap, a large edge on that topic, tuned so focus matters but is not automatic; the screen must show per topic the states that care, their EV and which of them you need; a default on timeout; an equivalent for Hale's +1 prep; bots pick the topic covering the most needed EV.

**The phase.** A new input phase, `Decision` (`Sim/Decision.luau`), with `MatchState.decision` = `"Focus"` or `"Stance"`. Order inside a week:

- debate week: `Decision Focus` → `Debate` → (`Decision Stance` if the week's event is a Choice) → `Plan`
- Choice week: `Decision Stance` → `Plan`
- any other week: `Plan`

*Why this order.* The focus is chosen on its own screen right before the debate it feeds (it used to be prep in the previous week's plan, a week early and buried in the plan screen). A stance in a debate week comes after the debate, so the republished polls (D-040) are on the table when you choose; the stance resolves with the week, as before. *Rejected:* one combined screen for both (crowded, the thing the humans asked to stop), and the stance before the debate (decided on stale polls).

**Payloads and validation.** `{ focus = <one of this debate's topics> }` or `{ choice = "A"|"B"|"C" }`, validated like plans: rejected whole with a reason code (`BadFocus`, `UnexpectedFocus`, `BadChoice`, `UnexpectedChoice`, `WrongPhase`, `BadShape`), never thrown, never partially applied, normalized (unknown fields dropped). A plan that carries `focus` or `choice` is rejected (`UnexpectedFocus`, `UnexpectedChoice`); the plan payload is `{ actions }` only. Timeout default: the hedge (C) for a stance; **no focus** for the debate (see below). Both stay hidden as before: the focus in `PlayerState.debateFocus` until the debate, the stance in `PlayerState.stance` until the week resolves; `View` shows each player only their own (`view.debateFocus`, `view.stance`), `view.decision` names the step. Determinism and simultaneity are unchanged: `Decision.apply` sets every player's choice at once; specs in `tests/sim/Decision.spec`.

**The focus (replaces prep).** `topicScore = focus + platform bonus + stat + roll(0..3)`, where focus is `DEBATE_FOCUS` (**2**) on the one topic you picked and 0 on the others. An uncontested focus wins its topic 81%, ties 12%, loses 6% (Debate.odds(2)), so it usually decides the topic but not always; if both focus on the same topic the edges cancel. `DebateResult.focus` (topic index per player, 0 = none) is revealed after the debate; `DebateResult.prep[p][t]` now holds the edge each focus added, so the score breakdown reads "you 2 focus + 2 platform + 1 stat + roll 3 = 8". *Default: no focus*, not your platform's topic: it is the only default that does not pick for you, and the timeout should cost something. *Gaffe redefined:* "lost a topic you put 0 prep on" would now hit every unfocused topic (about one per debate per player) and turn the gaffe into noise, so a gaffe is now losing a topic **when you took no focus at all** (the timeout): every topic you lose then costs `DEBATE_GAFFE` (0.6) in its states. *Hale:* "Debate focus +3 instead of +2" (`focusEdge` 3; was 7 prep points of 6), the same one extra point on the topic that matters. *Rejected:* edge 1 (62% uncontested: the pick barely matters; NoFocus still lost only 33%) and 3 (94%: automatic, and Hale's +4 would be a lock).

**Bots.** `Bot.focus` picks the topic with the most expected EV a win is worth on its map (`Bot.topicValue`: each of the topic's states weighted by EV × closeness, the same "needed EV" the screen lists); ties go to the first topic. New styles `RandomFocus` and `NoFocus` for the harness; `Bot.decide` answers both Decision kinds.

**Timer.** `TIMER_DECISION` = **20 s**: one decision with the facts on one screen; the old plan timer had to cover the plan, prep and a stance in 50 s, so 20 s for a single pick is generous, and both locking in ends it at once. No time bank (it stays a plan resource). `TIMER_PLAN` unchanged. *Budget, for the designers:* D-005's worst case (every timer run out) was 1,042 s; decisions add at most 10 × 20 = 200 s (two debates and a stance in every event week with the worst deck), about 105 s with a typical deck (3.3 Choice events). That breaks the 17.5-minute worst-case line `Config.spec` pins for the old steps (still 1,042 s there; the new spec pins the decisions separately). Typical play, where both lock in within seconds, adds well under a minute. If matches run long, `TIMER_DECISION` 15 or a smaller `TIMER_PLAN` are the levers.

**Screens.** A new `Decision` screen (Router: phase `Decision` while the step is open): the Campaign header (stage "Debate focus" or "Take a stance", its own countdown, no money or AP), the map previewing the pick, one panel, and the pinned Lock in. Nothing else: no state card, plan list, week card or Bank. Focus panel (`CampaignParts/Focus`): one full-width chip per topic, "Jobs (your platform) · 15 states, 160 EV", then "You need 10 of them (103 EV): trail PA by 2 … · lead IL by 4 …", "Focus here: 5 vs their 3, plus a roll 0 to 3 each. You win 81% (19% if they focus here too).", "A win: +1.0 in each; could flip DE (+3 EV)." (all from `Shared/UI/Swing.focus`); Lock in reads "Pick a topic" until one is tapped; the map badges the picked (or held) topic's states. Stance: the event card's chips, need line and summary, as before (D-042), C preselected. The plan screen loses the prep panel and the stance chips; in a Choice week the event card says "Your stance: A · …. Secret until the week resolves."

**Harness** (2,000 matches; before = this branch's start, D-043; with `DEBATE_FOCUS` 1 / 2 / 3 for comparison, Hale fixed at 3):

| Check | Focus 2 (chosen) | Before | Focus 1 | Focus 3 |
|---|---|---|---|---|
| Debates change the winner | 24.1% (21.7 EV) | 23.2% (21.3 EV) | 25.3% | 22.9% |
| Hale / his topic win rate | 47.7% / 47.3% | 51.7% / 47.6% | 53.7% / 52.7% | 38.6% / 40.4% (no perk left) |
| NoFocus (timeout default) win rate | **22.8%** | — | 32.6% | 21.2% |
| RandomFocus win rate | 50.4% (49.2 ± 1.8 at 3,000) | — | 50.8% | 48.6% |
| Both bots focus on the same topic | 93.8% | — | 93.8% | 93.8% |
| Choice stances change the winner / RandomStance | 14.8% / 34.2% | 14.6% / 34.0% | — | — |
| Candidates | Okafor 54.6, Calloway 55.6, Venkat 54.2, Hale 47.7, Alvarado 47.7, Reyes 47.3, Strand 46.0, Begay 46.9 | Okafor 52.9, Calloway 56.6, Venkat 54.9, Hale 51.7, Alvarado 46.0, Reyes 49.2, Strand 44.6, Begay 44.4 | | |
| Comeback / median margin / 40+ / 100+ EV | 38.1% / 52 / 61.7% / 21.0% | 38.3% / 52 / 62.3% / 21.6% | | |

*Reading it.* The focus clearly matters: a player who lets the timer run out wins 23%. Which topic matters less between two bots: they need the same states, so they pick the same topic 94% of the time and cancel, and a random pick does as well (50%), the same structural wash D-041 found for stances before D-043. Between humans, who read "states I need" differently and can guess the opponent's pick, the choice should matter more; the "19% if they focus here too" line makes the guessing visible. *For the designers:* if playtests show both players always pick the same topic, the D-043 lever applies here too (a topic win counts double in your own base, so each player's best topic differs).

**Duel harness.** Decision steps are their own turn (`Week 4 Decision: debate focus`, `Week 5 Decision: stance`) with `focus TOPIC` and `choice a|b|c`; the README explains them. The harness default on a stance step is `choice c`, on a focus step `auto`.

## A shorter draft (playtest feedback)

### D-045 — Strongholds follow the leans; the draft is home + two nominations (approved reshape, Oct 23, 2026)

*Built on its own branch (`shortdraft`, logged there as D-044) and merged after D-044; the harness numbers below are from before D-044. With both, the old steps' worst case is 932 s (pinned in `Config.spec`) plus at most 200 s of decision screens (D-044).*

**Feedback.** "The state selection could be optimized because there's a clear correct choice for both players to make." The harness agrees: with drafted strongholds, GA, OH, MI and NC were somebody's stronghold in 98–100% of matches, and both players' first choice for home was the same state in 81% (CA or TX in 89% of homes). The designers chose a shorter draft: players pick only their home and two battleground nominations; strongholds are assigned from the map's leans.

**Rules.** When Select ends (`Match.advance` → `Draft.assignStrongholds`), each player gets their `STRONGHOLD_COUNT` (5) strongest-leaning states as strongholds: states leaning toward them, ordered by lean (largest first), then EV (larger first), then id. They own them from the map reveal on, so both players see both sets on the map (rings) and on the draft screen ("Your strongholds: … · theirs: …") before the home round. The bonuses are unchanged (+8, +4 at 20+ EV) and still applied after the last round, so a nominated stronghold still loses its bonus but keeps its lean. Then three blind rounds (`Draft.rounds` = 1 + `NOMINATION_ROUNDS`): round 0 home (a stronghold cannot be a home: it is owned), rounds 1–2 nominations (any state but a home or a battleground, either player's strongholds included). `DRAFT_PRIORITY` is A B B. `STRONGHOLD_ROUNDS` is gone; `Draft.Kind` and `DraftPick.kind` are `"Home" | "Nominate"`. The draft goes from 8 rounds and 181 s (5 s reveal + 8 × 22 s) to 3 rounds and 71 s, 110 s shorter; the worst-case match budget falls from 1,042 s to 932 s.

**Why this assignment.**
- *Fair by construction.* Leans come in EV-adjacent pairs of equal magnitude, one to each side (D-008), so in a 1v1 both players' stronghold leans are the same multiset and the EVs nearly match: the stronghold EV gap is 2 at the median, 4 at p90, 16 at worst (6,000 matches), and the side with more stronghold EV wins 48.8% (no edge). Each player's set comes only from their own leans, so the order players are served in cannot matter; a spec mirrors every lean and checks the strongholds swap seats exactly.
- *Deterministic and readable.* It is a pure function of the seeded leans: "your strongholds are the states leaning your way the most". Nothing new is random and the player can check it on the map.
- *Visible before every pick.* Assigned at the end of Select (not in `Match.new`, so the Select screen cannot read a lean's direction off `owner`, D-008).
- *Rejected.* (1) Strongholds near each player's home, after the home round: they could not be shown before the home pick, and a blind home clash would then decide strongholds too. (2) A seeded draw among each side's leaned states: less learnable and wider EV gaps. (3) Searching for the most EV-balanced subset: unnecessary at a p90 gap of 4 EV. (4) The weakest leans (spreading safe states wider): the strongest is the simpler rule and the one the designers proposed; the harness shows no reason to prefer the other.

**Why the rounds stay blind with priority.** Three rounds are short enough that the reveal-after-each-round rhythm costs little, and the home round is the only one where clashes happen: both bots' first choice for home is the same state 82% of the time, while nominations almost never clash (27% of all rounds clash ≈ 82% / 3). So priority is effectively "who gets the contested home", A by seed. Priority A wins **48.9%** of 6,000 matches (47–53% target). Merging both nominations into one round (22 s faster) was considered and not taken: it removes the reaction to the opponent's first nomination for a small saving. Priority for the home was not split or compensated because the harness shows no seat edge.

**Bots.** No change needed: `Bot.draft` already values a home and a nomination from the View (leans plus owners), and the assigned strongholds enter its margins as owned states. 0 invalid bot inputs.

**Harness** (`lune run tests/harness/balance.luau 2000`, same seeds; before = this branch's start, D-043 rules; 6,000-match run in brackets).

| Check | Before | After | Target |
|---|---|---|---|
| Draft rounds / seconds | 8 / 181 s | **3 / 71 s** | |
| Priority A win rate | 49.6% | 47.8% [48.9%] | 47–53% ✓ |
| Candidates | Okafor 52.9, **Calloway 56.6**, Venkat 54.9, Hale 51.7, Alvarado 46.0, Reyes 49.2, **Strand 44.6**, **Begay 44.4** | Okafor 54.2 [55.1], **Calloway 57.2** [54.2], Venkat 54.0 [54.3], Hale 47.5 [47.2], **Alvarado 44.6** [46.6], Reyes 50.0 [51.7], Strand 45.0 [45.1], Begay 47.7 [46.3] | 45–55% (±2.2 at 2,000) |
| Comeback rate | 38.3% | 39.9% [37.5%] | 20–40% ✓ |
| Mean / median EV margin | 63 / 52 | 60 / 50 | median ≤ 60 ✓ |
| 40+ / 100+ EV | 62.3% / 21.6% | 60.9% / 19.2% | ≤ 65% / ≤ 25% ✓ |
| Tossup EV after the draft | 24.4% | 33.4% | informational |
| Leaned states that flip | 27.2% | 20.6% | 20–40% (near the edge) |
| Stronghold EV per player / gap p50, p90, max | 95 / 14, 30, 59 | 44 / 2, 4, 16 | |
| Most common strongholds | GA 100, OH 99, MI 98, NC 98% | VA 28, MI 28, NC 28, NJ 27% | |
| Both first choices for home the same | 80.6% | 81.5% | |
| Money raised per player / GOTV spend | $37.1 / $8.3 | $29.7 / $6.7 | |
| Stances change the winner | 14.6% | 11.4% | informational |
| RandomStance win rate | 34.0% | 34.9% | ≤ 45% ✓ |

The pass/fail lines are where they were: Calloway's and Okafor's over-55 readings swap between runs at this sample size, the D-020 rubber-band flags and GOTV at 9–10% were red before. What moved: a third more of the map is still in play after the draft (strongholds no longer turn the best unleaned mid-size states, GA, OH, MI and NC, into locks; they make already-leaning states safer), so margins and blowouts fell a little. Side effects worth watching: money raised fell 19% because the old strongholds were the big fundraising pools (strongholds feed fundraisers through support share), and base-weighted stances (D-043) matter a little less because a base is now mostly already-safe states. Neither was tuned here.

*For the designers.* The stronghold choice is gone, but the home is still a clear choice for bots: CA or TX in 92% of homes, the same first choice 82% of the time, settled by priority. If humans show the same, the smallest options are (a) cap the home bonus lower in big states (e.g. +4) or drop the ×1.25 fundraiser there, so a mid-size home near your strongholds competes, or (b) let a home only be chosen among states not leaning to the opponent. Both change a mechanic's intent, so neither was done.
