# WP3 — Campaign screen (UI overhaul v0.4.0)

## Changelog bullets

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

## TESTING.md checklist

Run in Studio twice: once with the device emulator at a phone in **portrait** (e.g. iPhone 14, 390x844), once at a plain **16:9** window. Start "Play vs Bot".

1. **Week 1 plan, phone portrait.** Without scrolling you should see: the header (week, stage, timer) and the score row under it (your name and EV, the bar, theirs, money, AP), the map, the state card down to the action grid, and the **Lock in** bar at the bottom. Lock in must be visible without touching the screen. Screenshot it.
2. Tap a state on the map, then **Rally**, **Fundraise** in another state, **Ad**. The bar's status line should change ("AP 2/3 · $... left · 1 flight"). Scroll the side column: "Your plan · 2 of 3 AP" lists the three lines.
3. Tap a different **message chip** (e.g. "Health ×1.0"), then Rally: the new plan line names that issue. Tap **More ▾**: the remaining issues appear.
4. Tap **Region poll** on a state: the plan line reads "Region poll · <region>" and the button greys out ("polled"). (Week 1 has no money; try it from week 2.)
5. Make a plan you can't afford (e.g. several Ads): **Lock in** turns grey and reads "Not enough money"; the status line says why in red. Remove a line with ×: Lock in comes back.
6. Tap **Clear** once: it reads "Clear? tap again". Wait 4 seconds: it goes back to "Clear". Tap twice quickly: the plan empties.
7. Tap **Pivot**: the grid is replaced by "Drop which issue?"; tap **Cancel** and the grid comes back.
8. Tap **Lock in**: it reads "Locked in", the status line "Locked in · waiting for opponent", the opponent line "Opponent: locked in" once the bot locks.
9. **Results reveal**: the reveal panel is at the top, the state card under it with no buttons; tap a state on the map and the card follows. The bar's button reads **Skip**; tap it: "Waiting for opponent…".
10. **Week 3 and week 8** (the weeks before a debate): **Debate prep** is right under the event card and above "Your plan", on both phone and 16:9, without scrolling past Lock in. Push one topic to 4: its + greys out and the row says "+: max 4". The status line ends with "prep 4/1/1".
11. **A Choice week** (an event that asks Attack/Defend/Ignore): the event card is the first panel, open, with three answer chips; Ignore has a yellow outline (not a yellow fill). Only **Lock in** is filled yellow anywhere on screen.
12. **Debate reveal** (weeks 4 and 9): no event card and no "Choose how to respond" text anywhere; the three topics appear one by one with two thin score bars; the bar shows "Debate · topic N of 3" and no button.
13. Let the timer run down: it turns red at 0:09.
14. **16:9**: the header is a single row; the week card is open at the bottom of the side column; the state list ("All states · sorted closest ▾") stays open after picking a state. On the phone the week card starts collapsed and the list closes after a pick.

Send back: the screenshots from steps 1, 9, 10 (week 3 and week 8), 11 and 12 at both sizes, and the Output lines that start with `[270] UI audit Campaign` (they should say `0 problem(s)`).

## DESIGN.md notes

Sub-bullet for D-030 (WP3, Campaign):

- **Campaign (WP3).** Lock in, Bank and the plan status move into the pinned `ActionBar` (primary named `LockIn` while planning, `SkipButton` during the resolve reveal; none during the debate, which sets `PrimaryOptional`). Side column order: reveal → event (first in Choice weeks) → state card → event → debate prep → plan list → week card, so prep is always above the plan and Lock in (B2). The event card is hidden during every reveal (B1). Region poll gets a button (B3) using `PlanDraft.regionOf` and the server's existing RegionPoll action (`REGION_POLL_COST`); the client offers one region poll per region per week. Message chips: `PlanDraft.messageChoices` (≤ `PlanDraft.MESSAGE_CHOICES` = 5, a UI number, best first). Map marks carry `arrow = "up"` and `arrowColor` (the leader's color) where the momentum lead is ≥ 0.5 (a display threshold in `Campaign.luau`, not a rule). The state card stays up read-only during the resolve reveal. Clear is two-tap (3 s). No Config numbers changed.
