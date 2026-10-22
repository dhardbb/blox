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

**Findings, for the humans** (no numbers were changed; these need a decision):

1. **Debates decide too much, and the debate stat decides debates.** Hale's +1 stat wins 64% of topics and Venkat's −1 loses 83%. A national shift moves every state at once, including the ~20 unleaned states that start exactly 35/35, so 0.8 points per topic swings many states together. Even at 0.3 per topic Hale wins 82%. Options: (a) keep debate stats equal and make Hale's perk something else (extra prep points, say); (b) apply debate shifts only to battlegrounds and states within ±5 in the polls; (c) cut `DEBATE_TOPIC_WIN` to about 0.3 and narrow the stat gap to 1.
2. **Priya Venkat's cheap media is the strongest perk once debates are neutral** (77% with debates off). Her debate-0 drawback is currently doing all the balancing.
3. **Blowouts.** Even without debates, 56% of matches end 40+ EV apart. The "≤ 15% decided by 40+ EV" target may not be reachable with winner-take-all and correlated national swings. It needs either a model change (all 51 states leaned, or smaller national effects) or a looser target.
4. **GOTV rarely matters (1.8%) and Walt Begay is at 37%.** Partly the bot (it values GOTV conservatively), partly that blowout margins dwarf a few GOTV points. Revisit after 1 and 3.
5. **Underdog tiers flip 4.1 times a match** (target ≤ 3). Projected EV swings because many states poll near 50–50. Raising `UNDERDOG_HYSTERESIS` from 20 to 30 is the obvious tuning knob.
6. **The "debates change the winner" metric is confounded.** In a paired replay with debates off, the bots react to a different board, so the two matches diverge. A 0.3-point debate still "changes" about 50% of winners, which is mostly chaos. Replace it with a counterfactual that removes only the debates' support deltas from the final state.

## Phase 2: server and networking

### D-018 — The server core is pure and lives in Shared/Net (Oct 22, 2026)

- `Net/Session` is the PLAN's TurnController: it owns phase timers, lock-ins, the time bank, skips, reveals, disconnect grace and forfeits for one match. It takes the server time as an argument, so `tests/net/` covers every timer path headlessly. `server/MatchService` only feeds it requests and `workspace:GetServerTimeNow()`. It lives in `ReplicatedStorage.Shared` because Roblox server scripts can't require ServerScriptService modules by string path, and Lune needs string paths. Clients can read it, but it holds no secrets: every hidden value stays in the server's `MatchState`, and clients receive only `View.build` output.
- **One request remote, one message remote.** Each request carries the `step` it was made for. A request for an earlier step is rejected as `StaleStep`, so a late click can't land in the next phase.
- **Rules the PLAN left open:** the time bank extends only the tapping player's own deadline, and the opponent sees the bank drop. A disconnected player's grace can hold a phase past its deadline. Only weeks missed while disconnected count toward the forfeit; a connected player who idles gets the empty-plan default every week but isn't forfeited. Draft reveals and debates can't be skipped. A match with no human left after grace is abandoned with no result.
- **Rate limit:** 40 requests per player per 10 s, well above what play needs (a whole plan is one request).
- **Reconnect window:** a player who comes back during an Input stage they haven't locked is guaranteed `RECONNECT_WINDOW` (15 s, new in `Sim/Config`) from the moment they return, even if their deadline already passed while grace held the stage open. Only their own deadline moves; it doesn't spend time bank or show the opponent anything, and it resets with the next Input stage. A rate-limited player is warned and told once per window; the rest of their requests are dropped silently.
- **If a match throws:** `MatchService` abandons it (`Session.abort`, result `Abandoned`) and frees the lobby, so a bug can't trap players in a stuck match.
