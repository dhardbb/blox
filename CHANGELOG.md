# Changelog

Newest first. Each entry lists what changed, what to test (see `docs/TESTING.md`), and anything needed from the humans.

## Unreleased — issue-based choices and debates

Rules pass approved by the designers: Choice events and debates are skill-based, tied to each state's issues, and visibly move states. Design log: `docs/DESIGN.md` "Issue-based choices and debates" (D-039 to D-041), with the before/after harness table in D-041. `docs/PLAN.md` "Debates" and "Events" describe the new mechanics.

- **Choice events are stances on an issue (D-039).** Eight Choice events, one per issue (24-card deck). Each offers stances **A** and **B** (opposed) and **C** (the hedge). States where the event's issue is a top issue react by their other top issue: +1.5 support where the stance is liked, -1.5 where it is not, +0.5 otherwise; every other state moves +0.5 per top issue the side likes and -0.5 per one it dislikes; the hedge is +0.5 in every state with the issue and nothing elsewhere; a candidate whose platform carries the issue is heard ×1.5 there (capped at the event cap of 2). Reactions come from fixed state data and the public platform, so the same event moves the same states every match and the client can preview every stance on the map (`Events.stanceEffects`). The right stance depends on which states *you* need. Both stances resolve from one snapshot and are revealed with the week, with each state's points (`EventResult.moves`) and the poll leaders they would flip (`EventResult.flips`). The D-036 Attack / Defend / Ignore payoff matrix is gone. A missing stance is the hedge.
- **Debates move states (D-040).** Winning a topic adds 1.0 support in every state where the topic is a top issue plus a flat 0.1 everywhere; a gaffe costs 0.6 in the topic's states; a sweep adds a flat 0.2 and battleground momentum. The public polls are republished right after the debate (same error terms), so the map shows the debate at once. `DebateResult` carries `moves` (every state's points per player), `flips` (states whose public-poll leader changed) and `gaffes`; the resolve events add `PollFlip` lines with the EV.
- **Bot (D-041).** Takes the stance worth the most expected EV on its own map (`Bot.choose`), and splits debate prep by the EV each topic's states are worth, trying every split against the roll odds (`Bot.prep`, `Debate.odds`). New harness style `RandomStance` (the same bot with random stances) for the skill check.
- **Harness.** New lines: Choice stances change the winner (counterfactual recount, like debates), average EV they swing, Choice events per match, stances taken, how often both players took the same stance, and the RandomStance win rate (target ≤ 45%).
- **UI contract for the client pass** (screens are a separate pass): `View.event.stances` (`{ id, name, text }` ×3) and `View.event.issue` for Choice events; `Events.stanceEffects(config, Events.byId[event.id], stanceId, platform)` for the map preview; the plan field is still `choice`, now `"A" | "B" | "C"`; `Explain.choiceLines(config, event, platform)` returns one line per stance; `Debate.topicStates(topic)` and `Debate.odds(config, edge)` for the prep screen.
- **Kept green with minimal edits outside the rules** (the client pass will replace them): `UI/Explain` (`choiceLines`, `stanceEffects`, help text), `UI/PlanDraft` (`choiceNote`, `choiceVerb`, `lastEventLine`, the Choice effect line), `UI/Fixtures` (fixture seed 7 → 18 so weeks 3 and 8 stay Windfalls with the 24-card deck), `client/Screens/Campaign` (default stance C), `client/CampaignParts/EventCard` and `Reveal` (text and the `choiceLines` call), `DebugUI/Commands` (`choice a|b|c`) and `DebugUI/Format` (stance lines, poll flips), and the specs that quoted the old answers. `tests/duel.luau` still prints the old Choice lines and will error on `e.national` in a Choice week; it is another agent's file and is listed for them.

**To test:** `docs/TESTING.md`, "Issue-based choices and debates". Nothing needed from the humans except the fictional stance texts in `Sim/Events.luau` if they want different flavor.

## 0.5.0 — Balance pass 2 and explained numbers (Oct 22, 2026)

### Balance pass 2

Numbers from the first agent playtest (three duel matches, six playtesters' notes), one approved perk reshape, and nothing new on the client except the data for it. Design log: `docs/DESIGN.md` "Balance pass 2" (D-033 to D-038), with the before/after harness table in D-038.

- **Debates decide things (D-033).** The topic roll is 0..3 (was 0..6), so a 2-point prep edge wins its topic about 8 times in 10 and 4-vs-0 always; each topic is worth 0.3 national points (was 0.2), a sweep 1.2 in all, a gaffe 0.3. Debates now change the winner in about one match in five and swing about 21 EV. `docs/PLAN.md` "Debates" quotes the current formula.
- **Fundraising is flat (D-034).** Pools start half full (new `POOL_START`), refill 50% a week (was 25%) and the home-state bonus is ×1.25 (was ×1.5). A home fundraiser pays about the same every week instead of $7 for four weeks and $4.5 after; three week-1 home fundraisers raise under $10, not $18–20.
- **Helen Strand previews next week's event (D-035).** New perk text: "Sees next week's event a week early; two free internal polls a week". Her View (and only hers) carries `nextEvent`; the debug board prints it. The campaign event card shows it as "Next week, from your pollster: …". The bot uses the preview to end its route where a Regional event is coming.
- **Choice weeks pay the winner (D-036).** Attack over Ignore +0.3 / −0.2, Defend over Attack +0.2 / −0.3, Ignore over Defend +0.2 / −0.2; both attack −0.2 each; both defend or both ignore 0. The old matrix paid 0 to a successful Defend or Ignore, which is why it read as a trap.
- **Candidates retuned for the flat economy (D-037).** Money matters more now, so the money-shaped perks were measured again: Okafor fundraisers +50% → +25%; Venkat income $3 → $2 and repeat ads keep 65% (was 70%); Hale 8 → 7 prep points (two spare points were worth +8 once debates counted); Strand's media drawback −15% → −10%. The bot values ground game a little higher (`gotvPremium` 1.3) so GOTV still decides one match in ten.
- **Harness.** New lines: average money raised per player, and the ratio of money raised in weeks 1–3 to weeks 10–12 (target ≤ 1.5). Specs: 608 (was 600).

**To test:** `docs/TESTING.md`, "Balance pass 2". Nothing needed from the humans except a look at the proposals listed under D-038.

### Explaining the numbers

No rules, payloads or `Sim/` files changed for this part.

- **Action previews.** Under the state card's action grid, "What each action does here" lists every button's expected effect in the selected state: support for you and for them, with every multiplier named (issue, battleground, underdog, closing weeks, event, your candidate, diminishing returns near the cap), momentum gained, money raised, AP, flights and backlash. Examples: "Rally: about +3.9 you, -1.2 them here (Jobs ×1.5); +2 momentum; 1 AP" and "Fundraise: up to about $6.6 here (your candidate ×1.5, pool $8.9 when full, shared with them); 1 AP". Repeat ads say they are worth less; attack ads say when backlash will cost you. The list is collapsible (title row), one line per button, so it works on touch.
- **"How it works" screen.** A "?" in the Campaign, Select and Draft headers opens one short panel per topic: actions, flights and routes, leans/momentum/backlash/underdog, ground game, polls (public vs internal), debates (prep, the roll and its odds, what a topic and a sweep are worth), events and the Choice payoffs, and election night (why the result can differ from the projection). Every number is read from Config and your candidate when it opens. The countdown keeps running in its header; Close is its one yellow button.
- **Choice weeks show the payoffs.** The event card lists what each answer pays against each of the opponent's ("Attack: -0.2 if they attack · -0.3 if they defend · +0.2 if they ignore").
- **Debates show why.** The debate reveal and the week card split each topic into prep, platform bonus, debate stat and roll ("you 2 prep + 2 platform + 1 stat + roll 3 = 8 · them 4 prep + 1 stat + roll 5 = 10"). Each prep row shows your known score, and the prep panel gives the odds of winning a topic level and 2 points ahead.
- **Labels from your side.** Lean reads "leans you +3" / "leans them +3" (was "+3 them"). The state card explains what momentum will do there next week ("You lead momentum: about +0.6 support drifts to you next week…") and shows your attack backlash. The week card names either side's underdog tier and what it gives.
- **Debug text UI and duel harness.** Same labels; `show ST` adds what each action would do there; a new `rules` command prints the "How it works" text; duel plan screens list the previews at the candidate's location, the Choice payoff lines and this week's debate breakdown. The duel's fixed "$2 flight", "25%" and "35/35/30" now come from Config.
- **Header.** The countdown column is 72 px (150 px only once a label like "Results in" is set), so the "?" fits beside it on phones.
- **Tests:** new `tests/ui/Explain.spec` (the helper's numbers against hand-worked formulas from Config) and `tests/ui/Explained.spec` (the screens show what the helper says; strict UI audit of the overlay and every Campaign moment at 1280x720, 844x390 and 390x844), plus debug UI cases in `tests/net/DebugUI.spec`. Specs: 646.

**To test:** `docs/TESTING.md`, "Explaining the numbers". Nothing needed from the humans.

## 0.4.1 — Playtest 1 fixes (Oct 22, 2026)

Fixes from the first agent-vs-agent playtest (three matches through `tests/duel.luau`). No rules or `Sim/Config.luau` numbers changed. Every game fix has a spec that failed before it. Specs: 600.

- **Money never shows rounded up.** Cash is fractional (fundraisers raise amounts like $13.55) and every display rounded to the nearest $0.1, so $4.96 read "$5.0" and a $5 plan was rejected. All money now floors to $0.1 (debug UI, campaign screens, duel harness): you can always spend what you see. New shared `UI/Numbers` module.
- **"Not enough money" says why.** The campaign bar and the debug log now read e.g. "Plan costs $7.0, you have $4.9 (1 flight $2.0, 1 ad $3.0, 1 region poll $3.0)", for the local check and for a server rejection. Worked out on the client from your own plan and View; the wire is unchanged.
- **Readable event lines.** The debug log says what happened instead of "events: Pick Pick" or raw floats: "P1 picked OH (home)", "P2 (you) nominated FL (battleground)", "you raised $13.5", "P2 answered Attack (-0.2 national)". Signed numbers have one sign ("-0.2", "+0.4"; was "+-0.2").
- **Color clash notice.** When both players pick the same color, the seeded coin flip still decides who keeps it (no seat favored) and the other still gets the first free color, but now they are told: a toast when the match starts ("Your opponent also picked Cobalt and the coin flip gave it to them: you are Crimson this match."), a debug log line, and a NOTE on the debug board. Your own pick is in your View as `pickedColor` (D-031).
- **Nominated strongholds.** A stronghold the opponent nominated lost its bonus and is a battleground, but screens still listed it as a stronghold. The draft board, the debug board ("Your draft" line, "SH P1 nominated" tag), the campaign state card ("Was your stronghold") and the duel harness now list it apart.
- **Duel harness.** `show`/`help` no longer bump TURN (a REFRESH line does instead, and `wait.sh` follows it); each fact appears once per screen; `--attempts` defaults to 5 and a rejected screen says how many are left; AUTO-SUBMITTED leads its verdict instead of sitting under REJECTED. `tests/duel/README.md` updated.
- **Version** 0.4.1.

**To test:** `docs/TESTING.md`, "Playtest 1 fixes (v0.4.1)". Nothing needed from the humans.

## 0.4.0 — UI overhaul (Oct 22, 2026)

Every screen redone on one design system (`docs/DESIGN.md` D-030, plan in `docs/UI-OVERHAUL.md`): five text sizes, one yellow button per screen (the main action, pinned at the bottom so it never scrolls away), a standard header with the countdown, toasts for every message, and a map whose small Northeast states sit in a labeled column. The layout audit now enforces all of it on every screen at 16:9 and phone sizes. No rules, numbers or payloads changed. Specs: 573.

### Foundation
- **Kit and Colors.** A five-size type scale (caption 13, body 16, heading 20, title 28, hero 48), spacing and corner tokens, the 56 px primary, the 84 px action bar and 44 px header heights, a 12 px text floor, and new color tokens (`onAccent`, `field`, `warn`, `disabledText`, `tint`, `onColor`). Buttons take a `variant` (primary, secondary, danger, chip); a disabled primary is grey with a label, never faded gold; chips are selected with an outline. New `Kit.caption`, `Kit.heading`, `Kit.stat`, `Kit.iconButton`, `Kit.setSelected`, `Kit.playerColor`.
- **New shared pieces:** the pinned action bar, the screen header with its countdown (danger under 10 s), the global toast (shown above every screen, including during reveals), and the collapsible card.
- **UI audit.** New checks: text under 12 px, buttons under 44 px wide, map nodes under 36 px, boxes poking out of the screen or their parent, exactly one pinned primary, one accent fill, the type scale. It now runs only in Studio or with `DebugScreen`/`DebugText`, and again after the screen rotates. Findings the old screens are known to have are listed as "pending" until their package lands.
- **Debug panel:** the command buttons wrap into two 44 px rows, so none is narrower than 44 px on a phone.
- **Tests:** `tests/ui/ClientFixes.spec` is split into the per-screen specs (new `Select.spec` and `Results.spec`), with shared helpers in `tests/ui/Rig.luau`; new `Kit.spec`, `Audit.spec` and `Tokens.spec`. The fake engine reports `AbsolutePosition` and honors `UISizeConstraint`.

### Map

- Map: the nine small Northeast states (VT, NH, MA, RI, CT, NJ, DE, MD, DC) now stand in a labeled column at the right edge of the map, top to bottom in that order, each with a thin line back to where the state really is. Maine, New York and Pennsylvania stay on the map. No two circles overlap any more (B12).
- Map: every state's circle is big enough to read its two-letter label on a phone (at least 24 px label box on a 390 px wide map, 20 px in the Northeast column). Small states got bigger and the biggest got a little smaller, so sizes vary less than before.
- Map: every state's tap target is at least 36 px in both directions (was 30) and stays inside the map; where two targets overlap, the smaller state wins the tap (B13).
- Map: the H/B/1/2/G/* badge now sits in a band at the top of the state's tap target, and a new momentum arrow (▲/▼ in the leading player's color) can show under a state. Nothing sets the arrow yet; Campaign will (WP3).
- Map text uses the type scale only (labels up to 20 px, badges and arrows up to 16 px, never under 12 px). The map passes the strict UI audit, so map findings now count as problems on every screen.

### Lobby, Select and Results

- Lobby: one centered column up to 560 px wide that no longer scrolls. "270" is now hero size. "Play vs Bot" is the only yellow button. Find Match, Host Private Match and Join are grey. Cancel is outlined in red. The code box uses the darker field color.
- Lobby: the record line ("Rating 1000 · 3 won, 2 lost") keeps its space before the profile arrives, so the buttons don't jump down. A private match code shows in hero size on a dark well.
- Lobby: the Lobby's own toast is gone. Server messages and the "Enter the 5-character code" warning use the global toast at the top of the screen.
- Select: the standard header with the timer, which turns red under 10 s (was 5 s). Lock in is pinned in a bar at the bottom.
- Select: everything fits without scrolling at 16:9. Cards are 112 px on 16:9 and 124 px on phones (were 170 and 224). The six colors sit in one row in both orientations, with two-letter names on phones. Issue chips read "Jobs · 160 EV" on one line.
- Select: picks show as an outline plus a "✓". Nothing is filled yellow except Lock in.
- Select: when a pick is missing, the disabled Lock in button names it ("Pick a candidate", "Pick a color", "Pick 2 more issues"). The status line says "Still to pick: …", with "▾" when the issues are below the fold. Other status lines: "Ready", "Locked in · waiting for opponent", and "Opponent: thinking / locked in / disconnected".
- Select: tapping a fourth issue shows "You already have 3; tap one to swap it" for 3 s. Before, nothing happened.
- Select: when the pick is restored from your last match, the status says "Your last pick is loaded · Lock in or change it".
- Select (bug B4): a rejected Lock in now says why. The reason shows in the toast and stays in the status line in red until you change something, and the picks unlock. Before, nothing was shown.
- Results: the banner reads "You won" / "You lost" / "No result" at hero size, and the EV totals use title size. The rating line keeps its space, so nothing shifts when it arrives.
- Results: the EV bar has a 270 tick. Closest states and debates are collapsible sections, open by default. "Play vs Bot again" (or "Play again") and "Back to lobby" are pinned at the bottom.

### Campaign

- Campaign: **Lock in is always on screen.** It lives in a pinned action bar under the side column (16:9) or at the bottom of the screen (phones), with "Bank +15s" beside it (hidden when the bank is empty), the plan status ("AP 2/3 · $1.5 left · 1 flight · prep 2/2/2") and the opponent's status ("Opponent: thinking / locked in / skipped / disconnected / back"). A plan with a problem greys Lock in and says why on the button ("Not enough money") and in red on the status line.
- Campaign: **debate prep sits above the plan** (B2): state card → event card → debate prep → your plan → week card. In Choice weeks the event card comes first, expanded, with the answers as outlined chips (Ignore preselected).
- Campaign: **the Choice prompt no longer shows during the debate reveal** (B1); the event card is hidden during every reveal and comes back when the plan starts.
- Campaign: **Region poll has a button** (B3): "Region poll $3.0" polls the selected state's whole region; the plan line reads "Region poll · Mid-Atlantic".
- Campaign: the action grid is 3x3: Rally, Fundraise, Ad, Attack ad, Poll, Ground game +1, Region poll, Pivot. Costs are on the buttons ("Rally ✈ $2.0", "Ad $3.0"), and a greyed button says why ("Poll (polled)"); the line under the grid gives the full reason. Pivot opens its chooser in place of the grid, with Cancel.
- Campaign: the rally/ad message is one tap: a row of up to five chips (best first, the state's top issues and your platform, "Jobs ×1.5"), plus "More ▾" for the rest.
- Campaign: the state card shows its numbers as a grid (Public poll, Lean, Momentum with ▲ in the leader's color, Ground game), tags as pills, and the full state list behind "All states · sorted closest ▾" with sort chips. The list stays open after a pick on 16:9 and closes on phones.
- Campaign: during the resolve reveal the state card stays up, read-only, so you can tap states while the results play. Skip is the bar's primary ("Skip", then "Waiting for opponent…"); the debate has no button, only "Debate · topic 2 of 3".
- Campaign: the header is one row on 16:9 ("Week 3 of 12 · Plan your week", both candidates with projected EV over a two-color bar, money and AP, the timer) and two rows on phones. The timer turns red under 10 seconds. "Their money" moved to the week card.
- Campaign: "Your plan · 2 of 3 AP" lists the plan with a × per line; Clear needs a second tap within 3 seconds ("Clear? tap again").
- Campaign: the map gets a ▲ in the leader's color on states where one side leads momentum by 0.5 or more (drawn once the map package lands).
- Code: `Screens/Campaign.luau` is split into `Screens/CampaignParts/{Model,TopBar,StateCard,PlanList,Prep,EventCard,Reveal}.luau`. `PlanDraft` gains `messageChoices`, `regionOf`, `shortProblem`. The Campaign screen is strict in the UI audit and in `Tokens.spec`.

### Draft and Election night

- Draft: the standard header ("Round 4 of 8 · Stronghold", the round's help line, the timer, red under 10 s while picking) and the standard pinned action bar ("Lock in", disabled "Pick a state", "Locked in · waiting for opponent", "Opponent: thinking / locked in / disconnected").
- Draft: your two picks are one row of chips, "1st: TX" and "2nd: —", each with a 44 px × once filled. "Clear both" is gone (the two × do it). Tapping a chip still aims the next pick at that slot; the aimed chip gets the accent outline.
- Draft: on phones the state list now comes right after the picks (it was 8th in the scroll, B10), and the legend and draft board moved into a "Draft board ▾" card at the end, collapsed. The map and the panel split by pixel math with no dead band (B11).
- Draft: a tap on a state you can't pick says why in the bar ("TX: already drafted") until your next tap, instead of a hint that vanished after 3 s. A rejected lock-in shows there too (and in the toast).
- Draft map reveal: the side panel shows the priority line, the legend and three lines on how the draft works, so it is no longer mostly empty.
- Draft reveal: "You got OH" and "They got PA" side by side, each outlined in its owner's color, with the clash note under them.
- Draft: legend reduced to one row plus a caption; the board is one line per candidate. State list rows are 44 px, the "your home" tag is caption size (was 11 px, B14).
- Election night: a header with "Results in 0:32" (B8) and the call status ("35 of 51 states called" / "Too close to call: …").
- Election night: both candidates share one 72 px strip with a single EV bar (your fill from the left, theirs from the right) and the 270 tick inside the bar's box (B9). "270 to win" now shows on phones too.
- Election night: the call feed has 44 px rows (state and EV on the left, who it was called for on the right) and bottom padding, so the last row is never clipped (B6). "Skip to results" is the pinned primary; after your tap it reads "Waiting for opponent…".
- Election night: the bar now says "Opponent: skipped" when they skip (B7), "Opponent: watching" before that, "Opponent: disconnected" if they drop.

**Test:** `docs/TESTING.md` → UI overhaul (v0.4.0).

## 0.3.1 — Bug hunt fixes (Oct 22, 2026)

Fixes from the first test build's four bug hunts (rules, server and saving, client, and a 2,900-match soak with 0 script errors). Every fix has a spec that failed before it. Specs: 448.

- **Client.**
  - The campaign state card has "Pick a state from the list": all 51 states with EV, public poll margin and your momentum, sorted closest, biggest or A to Z. Small states (DC, DE, RI...) are now easy to pick on a phone.
  - When the timer runs out, a finished pick or plan is locked in for you (0.5 s before the deadline) instead of being lost; an unfinished one falls back to the server default.
  - Rejection and toast messages are tracked by id, so they keep working after 20 messages.
  - The Draft lock bar says "Opponent: disconnected"; the forfeit notice stops counting below zero.
  - Every server reason code has player-facing text; the state card reads "pool size $X".
  - "Server full" is information only: the lobby buttons stay usable.
  - Removed the space left for the old Debug button.
- **Server and saving.** The forfeit counter is truly consecutive; election results never leak before election night; a player's result is never dropped while their profile reloads; a double leave during a slow save no longer leaks a lock; unrated human matches and forfeits record nothing they shouldn't; the lobby status is re-sent to everyone in the lobby whenever it changes. Details in `docs/DESIGN.md` (Phase 2 and ratings sections).
- **Rules (3–4 players only; 1v1 unaffected).** Map leans no longer error when a balanced draw is impossible; election tiebreaks compare only the tied players.

**Test:** `docs/TESTING.md` → Bug hunt fixes (v0.3.1).

## 0.3.0 — Phase 3: Client MVP (first test build, Oct 22, 2026)

The real game screens replace the text UI (still available as a debug panel: F2, or the workspace attribute `DebugText`).

- Six screens: Lobby (practice, find match, host / join by code, your rating), Select (candidate, color, three-issue platform with EV coverage), Draft (map reveal, ranked top-2 picks from the map or a state list, per-round reveals), Campaign (node map, state card, action buttons with cost and problem preview, plan tray, time bank, pivot, debate prep, this week's event with Attack / Defend / Ignore in Choice weeks, week card, animated resolve and debate reveals), Election night (states called safest first, EV counters, winner banner) and Results (winner, EV, closest states, rating change, play again).
- Node map: circles sized by EV, colored by public polls, undecided rings, land-border lines, route preview; built from frames, behind a MapInterface so real shapes can replace it.
- Plan preview: cost and problems before Lock in, using the server's own cost rules.
- DEBUG_UI: set the workspace attribute `DebugScreen` (Lobby, Select, MapReveal, Draft, Plan, ChoiceWeek, Resolve, DebatePrep, Debate, Election, Over) to render any screen from a fixture without a server; every screen runs a layout audit (buttons under 44 px, truncated text).
- Works in 16:9 and phone portrait; content stays clear of Roblox's own buttons.
- Includes the balance pass, the event deck and ratings below.

**Test:** `docs/TESTING.md` → Phase 3.

## Unreleased — ratings and saved stats (branch `phase5-data`)

Elo ratings and persistent player stats (`docs/DESIGN.md` D-028). The debug UI shows them; the real screens come later.

- `Net/Rating`, `Net/Profile`: Elo (K 32, start 1000, new `ELO_FLOOR` 100) and the saved record: rating, wins/losses, per-candidate record, last 10 matches, practice total. `Profile.migrate` repairs nil, garbage and older versions.
- `server/DataService`: the profile in a DataStore (`PlayerData_v1`, key `Player_<UserId>`), session-locked by server, retried with backoff, saved when a match ends, when the player leaves and on shutdown. Never on the hot path of a turn.
- Only human-vs-human matches ending by Election or Forfeit are rated. Practice and abandoned matches never move the rating. A forfeit costs the player who left.
- In an unpublished Studio place DataStores can't work: one warning, then it plays with an in-memory store (nothing is saved).
- Debug UI: the lobby line shows `Rating 1032 (12-7)`; after a rated match the log and board show `Rating 1032 → 1048`. New optional `profile` on the lobby status and a `Rating` message.
- Fake engine: a fake `DataStoreService` (with "not published" and transient-failure switches), `game.JobId`, `game:BindToClose` and `os.time` on the simulated clock.
- Specs: 271 (was 225). `tests/net/Rating.spec.luau` covers Elo math and profiles; `tests/e2e/Data.spec.luau` covers saving, the lobby display, practice, forfeit, locks, retries, unpublished mode and shutdown.

**Test:** `docs/TESTING.md` → Ratings and saved stats.

**Needed from the humans:** publish the place to Roblox and turn on Home → Game Settings → Security → **Enable Studio Access to API Services**, or saving can't be tested in Studio.

## Unreleased — event deck (branch `phase5-events`)

Phase 5's seeded weekly event deck: simulation, server and debug text UI. The campaign screen will show events once the Phase 3 UI lands. Details in `docs/DESIGN.md` D-027.

- `Sim/Events`: 20 generic events (8 Spotlight, one per issue; 5 Regional; 3 Windfall; 4 Choice). Each match shuffles them with its own seed and deals one to each of weeks 2–11, with no repeats and nothing in weeks 1 or 12. Only the current week's event is shown (`View.event`); the rest of the deck stays on the server.
- Effects in Resolve: Spotlight ×1.3 on rallies and positive ads on the issue; Regional ×1.5 on rallies in the region; Windfall ×1.2 on fundraisers where you trail in the public poll. An event adds at most 2 support points (or $2) to one player in one state per week.
- Choice events: plans take `choice = "Attack" | "Defend" | "Ignore"` (default Ignore; `BadChoice` / `UnexpectedChoice` otherwise). A symmetric payoff matrix in national points (at most 0.3) resolves both answers together. Both answers are revealed after the week in the week card and `View.eventLog`.
- Bot: plays toward the spotlight issue, the regional region and trailing-state fundraisers, and answers Choices with the matrix's equilibrium mix.
- Private lobbies: `host noevents` in the debug UI (a `Host` request with `events = false`) plays the match without events. The queue and practice always have them. No timer or phase changes.
- Debug UI: the board shows `Event this week: ...` and last week's revealed answers; `plan ...; choice attack|defend|ignore`.
- Config: `EVENTS_ENABLED`, `EVENT_FIRST_WEEK` / `EVENT_LAST_WEEK`, the three multipliers, `EVENT_CAP`, and nine `CHOICE_*` payoffs. Tuning: Windfall ×1.5 → ×1.2, because the harness traced a Venkat edge to it (D-027).
- Harness: same three red flags as before events (one noise-level matchup cell, the two rubber-band checks). `EVENTS_ENABLED=false` is accepted as a variant.
- Specs: 255 (was 225), 30 new: `tests/sim/Events.spec.luau` plus event cases in the View, Bot, Config, Lobby, Session, DebugUI and e2e specs. No existing spec needed changing: none pinned an outcome that events move.

**Test:** `docs/TESTING.md` → Phase 5: event deck.

**Needed from the humans:** nothing to supply. Look over the deck's names and flavor text, and the Windfall change from the PLAN's ×1.5 (D-027).

## Unreleased — balance pass 1 (branch `balance-pass-1`)

First tuning pass from the harness (`docs/DESIGN.md` D-018 to D-025). No UI change; the server self-test still runs.

- Harness: "debates change the winner" is a real counterfactual now. `Debate.resolve` records the support each debate moved (`StateSim.debateShift`, hidden) and `Election.count(..., { debates = false })` recounts without it, like the GOTV check. The paired replay it replaces was measuring chaos (D-018).
- Config (tuning): `DEBATE_ROLL_MAX` 2 → 6, `DEBATE_TOPIC_WIN` 0.8 → 0.2, `DEBATE_SWEEP` and `DEBATE_GAFFE` 0.5 → 0.2 (D-019); `UNDERDOG_HYSTERESIS` 20 → 30, `UNDERDOG_SMOOTHING` 0.5 → 0.4 (D-020); `GOTV_PER_UNIT` 1.0 → 1.5 (D-021). Bot: ground game from week 7.
- Candidates (tuning, D-022): Begay rallies 2.9, Alvarado $20 start / $3.75 income, Reyes momentum +65%, Strand media −15%, Calloway rallies 2.3, Hale starts with $0.
- Candidates (**proposed, needs the humans' approval**, D-023): Hale's perk is 8 prep points instead of debate stat 2; Venkat's drawback is $3 income instead of debate stat 0; Okafor loses her rally drawback and fundraises +50%.
- Result: all eight candidates 45–55% (was 20–89%), debates decide 16% of matches and swing 15 EV (was 42% / 61 EV), GOTV decides 12% (was 1.8%), comebacks 37%, tier changes 3.0 per match. Blowouts fall from 80% to 60% of matches, which is the winner-take-all floor; D-024 proposes a revised target. The wrong-leader underdog share rose to 22% because games are closer (D-020).
- Specs: 161 (was 156). New ones pin the debate counterfactual, a sweep under one national point, GOTV's place between a poorly and a well matched media buy, the bot placing ground game before week 9, and the new hysteresis arithmetic.

**Test:** `docs/TESTING.md` → Balance pass 1.

**Needed from the humans:** approve or pick alternatives for the three perk shapes in D-023; decide the blowout target (D-024) and the rubber-band trade-off (D-020).

## 0.2.0 — Phase 2: Server and networking (Oct 22, 2026)

Two players can now play a full match in Studio through a temporary text UI. The real screens come in Phase 3.

- `Net/Session`: one live match on the server: input timers, lock-ins, the 2 × 15 s time bank, resolve and election skips, map/draft/resolve/debate reveals, disconnect grace (30 s, twice per match), forfeit after two missed weeks, abandonment, and bot seats. It's pure (the server passes the clock in), so it's tested like the sim.
- `Net/Lobby`: public queue, private 5-character match codes, practice against the bot; at most 10 matches per server.
- `Net/Schemas`, `Net/Remotes`: every client request is size-checked and shape-checked before anything reads it. Game inputs are then checked by `Match.validate`. Rejections are logged in the server Output with a reason code and echoed to the client.
- `server/Replication`, `server/MatchService`: the two RemoteEvents, rate limiting, and the clock that drives every match. Each player only ever receives their own `View`.
- `client/App`: a debug text UI. It has buttons for Practice, Queue, Host, Auto (the bot fills in your current step from your own view), Autoplay, Pass, Bank, Skip and Help, plus a command line for typed moves (`plan rally OH Jobs; fund PA; ...`).
- Fixed: election night was skipped; a player reconnecting after the deadline lost their turn (they now get 15 s to finish it); a thrown error could wedge a match and its lobby slot forever (the match is now abandoned and freed); debug-UI autoplay could skip a step in a second match; rate-limited players no longer flood the log and Output.
- 220 specs. `Net/` and `DebugUI/` are held to the same purity rules as `Sim/`.

**Test:** `docs/TESTING.md` → Phase 2.

## 0.1.0 — Phase 1: Simulation core (Oct 22, 2026)

The whole game runs headless: two bots can play a full match, and the balance harness reports on thousands of them. There's no UI yet.

- `Sim/Rng`: seeded xoshiro128** generator with named substreams; matches reference vectors.
- `Sim/StateData`, `Sim/Issues`, `Types`: 51 states (EV sums to 538, symmetric land-border adjacency, nine regions, balanced generic issues). See `docs/DESIGN.md` D-014.
- `Sim/Config`: every tunable from `docs/PLAN.md` revision 2, with variants for the balance harness; pool capacity derived from population, capped at $12 (D-015).
- `Sim/Candidates`: the eight candidates as data (revision-2 values) and the six player colors.
- `Sim/Match`: the state machine (Select → MapReveal → 8 draft rounds → 12 weeks with debates in weeks 4 and 9 → Election → Done). Pure: each step returns a new state, and missing or invalid inputs get defaults.
- `Sim/Leans`, `Sim/Draft`: seeded, mirrored public leans; the blind ranked-top-2 draft with A B B A B A A B priority, auto-fill, bonuses, and battleground resets.
- `Sim/Plan`: plan schema and validation with reason codes (AP, money, route flights, GOTV caps, pivot, polls, debate prep). Fuzzed so it never throws.
- `Sim/Resolve`, `Sim/Support`, `Sim/Polls`: weekly resolution under the snapshot rule (D-001): rallies, pooled fundraisers, media saturation, attacks and backlash, pivots, momentum and drift, AR(1) public polls, underdog tiers with hysteresis, internal polls.
- `Sim/Debate`, `Sim/Election`: seeded topics and rolls, sweeps and gaffes; GOTV, election noise, tiebreaks, reveal order.
- `Sim/View`: the only exit for sim state. A spec walks every view of a full match for hidden fields, and checks that changing any hidden value leaves a view byte-identical.
- `Sim/Bot`: heuristic bot playing from its own View, plus six restricted styles for the dominance checks.
- `tests/harness/balance.luau`: 2,000 bot-vs-bot matches plus side checks in about 70 s; prints every PLAN.md metric against its target. First results and open balance questions are in `docs/DESIGN.md` D-017.
- 156 specs. CI runs on every branch and reports every failing check, not just the first.
- Server startup now plays one bot-vs-bot match as a self-test and prints the result.

**Test:** `docs/TESTING.md` → Phase 1.

**Needed from the humans:** answers to the balance questions in `docs/DESIGN.md` D-017 (debate strength, the blowout target).

## 0.0.1 — Phase 0: Scaffold (Oct 22, 2026)

- Rojo project (`default.project.json`): `ReplicatedStorage.Shared`, `ServerScriptService.Server`, `StarterPlayerScripts.Client`.
- Pinned toolchain in `rokit.toml` (Rojo 7.7.1, Lune 0.11.1, StyLua 2.6.0, Selene 0.31.0, luau-lsp 1.70.1); `scripts/bootstrap.sh` builds the same versions from crates.io where GitHub downloads are blocked.
- Lune test runner (`lune run tests`) with a small describe/it/expect framework; smoke tests; a purity test that keeps the simulation free of Roblox APIs, clocks and unseeded randomness.
- CI (`.github/workflows/ci.yml`): StyLua, Selene (two configs), Lune tests, luau-lsp type check, Rojo build; uploads `270.rbxl` as an artifact.
- Docs: `docs/PLAN.md` revision 2 (first-session decisions folded in), `docs/DESIGN.md` decisions log D-001 to D-013, `docs/TESTING.md`, `CLAUDE.md`.

**Test:** `docs/TESTING.md` → Phase 0.
