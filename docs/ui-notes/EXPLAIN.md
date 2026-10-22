# Explaining the numbers (branch `explain-numbers`)

Notes to fold into `CHANGELOG.md`, `docs/TESTING.md` and `docs/DESIGN.md`. They live here so the branch does not touch those files while the balance pass edits them.

## Changelog bullets

Under a new "Unreleased: explain the numbers" entry. No rules, payloads, View fields or `Sim/Config.luau` numbers changed. No `Sim/` file changed.

- **Action previews.** Under the state card's action grid, "What each action does here" lists every button's expected effect in the selected state: support for you and for them, with every multiplier named (issue, battleground, underdog, closing weeks, event, your candidate, diminishing returns near the cap), momentum gained, money raised, AP, flights and backlash. Examples: "Rally: about +3.9 you, -1.2 them here (Jobs ×1.5); +2 momentum; 1 AP" and "Fundraise: up to about $6.6 here (your candidate ×1.5, pool $8.9 when full, shared with them); 1 AP". Repeat ads say they are worth less; attack ads say when backlash will cost you. The list is collapsible (title row), one line per button, so it works on touch.
- **"How it works" screen.** A "?" in the Campaign, Select and Draft headers opens one short panel per topic: actions, flights and routes, leans/momentum/backlash/underdog, ground game, polls (public vs internal), debates (prep, the roll and its odds, what a topic and a sweep are worth), events and the Choice payoffs, and election night (why the result can differ from the projection). Every number is read from Config and your candidate when it opens. The countdown keeps running in its header; Close is its one yellow button.
- **Choice weeks show the payoffs.** The event card lists what each answer pays against each of the opponent's ("Attack: -0.2 if they attack · -0.3 if they defend · +0.2 if they ignore").
- **Debates show why.** The debate reveal and the week card split each topic into prep, platform bonus, debate stat and roll ("you 2 prep + 2 platform + 1 stat + roll 3 = 8 · them 4 prep + 1 stat + roll 5 = 10"). Each prep row shows your known score, and the prep panel gives the odds of winning a topic level and 2 points ahead.
- **Labels from your side.** Lean reads "leans you +3" / "leans them +3" (was "+3 them"). The state card explains what momentum will do there next week ("You lead momentum: about +0.6 support drifts to you next week…") and shows your attack backlash. The week card names either side's underdog tier and what it gives.
- **Debug text UI and duel harness.** Same labels; `show ST` adds what each action would do there; a new `rules` command prints the "How it works" text; duel plan screens list the previews at the candidate's location, the Choice payoff lines and this week's debate breakdown. The duel's fixed "$2 flight", "25%" and "35/35/30" now come from Config.
- **Header.** The countdown column is 72 px (150 px only once a label like "Results in" is set), so the "?" fits beside it on phones.
- **Tests:** new `tests/ui/Explain.spec` (the helper's numbers against hand-worked formulas from Config) and `tests/ui/Explained.spec` (the screens show what the helper says; strict UI audit of the overlay and every Campaign moment at 1280x720, 844x390 and 390x844), plus debug UI cases in `tests/net/DebugUI.spec`. Specs: 646.

**To test:** `docs/TESTING.md`, "Explaining the numbers". Nothing needed from the humans.

## TESTING.md section

### Explaining the numbers

1. **Play vs Bot**, reach week 1's plan. Tap a state near your candidate.
   - Under the action buttons, "What each action does here –" lists eight lines, one per button. Rally and Ad say "about +N you, -N them here (Issue ×N …)"; Fundraise says "up to about $N here (… pool $N when full …)".
2. Tap a different message chip (e.g. a ×0.8 issue).
   - The Rally and Ad lines change to that issue and show smaller numbers.
3. Tap **Ad** twice in the same state.
   - The Ad line now says "repeat ad #3 ×0.36" (or similar) and a smaller number.
4. With at least $9, tap **Attack ad** three times in one state, then read the Attack ad line (it previews the fourth).
   - It reads "backlash costs you 0.8 and resets" and the "you" number is smaller or negative.
5. Tap a state far away (not next to your route).
   - Rally and Fundraise lines end with "1 AP + flight $2.0".
6. Read the state card's **Lean** and **Momentum**.
   - Lean says "leans you +N", "leans them +N" or "no lean". A line under the stats says what momentum does there next week.
7. Tap **?** in the header.
   - "How it works" covers the screen with eight panels; the countdown keeps running at the top right; scroll to the bottom; tap **Close**. You are back on the campaign with your plan intact.
8. Repeat step 7 at the candidate Select screen and during a Draft round.
9. In a **Choice** week, open the event card.
   - Under Attack / Defend / Ignore, three lines show what each answer pays against each of the opponent's.
10. In the week before a debate, look at the prep panel.
    - Each topic row shows "You: N prep + … = N, plus a roll 0 to 6 · them: …". The last line gives the chance to win a topic level and 2 points ahead.
11. Watch the debate (week 4).
    - Each topic row shows both sides' prep, platform, stat and roll adding up to the score. The week card says the same in the debate week.
12. Phone check: Test → Device → an iPhone in portrait, then landscape. Repeat steps 1 and 7.
    - Nothing is cut off; Close and Lock in are always on screen.
13. Press **F2**, type `rules` and `show OH`.
    - `rules` prints the help text; `show OH` adds the lean, momentum and the eight action lines.

**Send back:** any preview number that looked wrong after the week resolved (state, action, what the line said, what the poll did), screenshots of the help screen on a phone, and the Output lines starting with `[270] UI audit`.

## DESIGN.md notes (proposed D-032)

### D-032 — Explaining the numbers on screen (no rule changes)

- **One pure explainer.** `Shared/UI/Explain` turns Config, Candidates and the player's own View into words. It requires Sim modules read-only and calls their formulas (`Resolve.issueMult`/`attackMult`/`closingMult`, `Support.saturation`, `Polls.underdogMults` on a stand-in, `Events.supportMult`/`fundMult`/`choicePayoffs`, `Plan.isAdjacent`, `Leans.startingSupport`; pool size from the View's `capacity`), so a Config or candidate change (including Strand's perk or the Choice matrix) shows up with no edit. It copies only the order of Resolve's steps (gain split, repeat-ad factor, backlash meter, pool sharing), which a sim change would also need to update; `tests/ui/Explain.spec` pins them.
- **Honest about what is hidden.** The sim reads true support; the preview uses your internal poll of that state if you have one this week, else the public poll ("about"). Fundraise is "up to about": the pool's level is hidden (`View` never includes it), so the preview assumes a full pool shared only with your own earlier fundraisers. Event bonuses are capped at `EVENT_CAP` as if nothing else in the state used the cap. Nothing new is sent to the client.
- **Momentum is explained as it works.** The request suggested "adds to rallies"; in the sim momentum never changes a rally, it drives drift (`DRIFT_RATE` per point of lead, capped). The card says that, with next week's drift if nobody campaigns there (both sides' decay applied).
- **Debate rolls are derived.** The result carries prep and the total; the roll is total − prep − platform bonus − debate stat. The breakdown is shown in the debate week only, before a later pivot could change the platform; out-of-range values print as "other" instead of a false roll.
- **Election odds.** "A 3-point poll lead holds about 80%" uses a normal margin error of sqrt(POLL_SIGMA² + ELECTION_SIGMA²), ignoring ground game and poll rounding.
- **Help overlay.** `UI/Help` is mounted once by App above the screens (ZIndex 40, below the toast's 50) and opened through `ctx.help` from the header "?" (`Header.new{ onHelp }`). It is its own audit root ("Help"), with one pinned primary (Close), so the screen underneath keeps its own single primary. The header countdown column shrank from 150 px to 72 px unless `setTimerLabel` is set.

## Not done / for later

- The previews are expected values from the start-of-week snapshot. They do not model the opponent's simultaneous moves in the same state, drift, or support moved by earlier actions in your own plan (each step reads one snapshot, so this matches the sim within a step).
- PLAN.md "Debates" still quotes the pre-D-019 numbers (noted in D-031); the help screen reads Config, so it is right either way.
