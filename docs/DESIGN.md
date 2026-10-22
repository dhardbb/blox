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
