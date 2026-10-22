# 270 client UI overhaul (v0.3.1 → v0.4.0)

Worktree: `scratchpad/blox-phase3`, branch `phase3-client`. File:line refs are to that tree as read on 2026-10-22. Evidence comes from three sources in `ui-data/`: `flows.md` (tap counts, wording, feedback gaps), `layout/` (fake-engine dumps at 1280x720 and 390x844; the fake does not run UIListLayout, so anything inside a list reads at (0,0) and only explicitly positioned boxes have real numbers), and `shots/*.png` (real Studio captures at a ~1725x1055 viewport; no portrait captures exist).

Scope guard: nothing here changes a rule, the sim, the server, the payloads, or what a player may see. Every change is in `src/client`, `src/shared/UI`, `tests/ui`, and docs. Screens still read only the Store and send only through Net (D-029).

---

## 1. Diagnosis: the ten problems worth fixing

Ordered by how much they hurt a first-time phone player.

### P1. The primary action is below the fold on the screen that matters most
Campaign's **Lock in** lives in the Tray, which is the 4th panel in a scrolling side column (`Campaign.luau:758` order 3, after EventBanner 0 and StateCard 2; built at `:789-804`). On the 1725-wide Studio capture (`shots/Plan.png`, `shots/DebatePrep.png`, `shots/ChoiceWeek.png`) "Your plan this week" is already cut off at the bottom edge, so Lock in is never on screen without scrolling even on a desktop. On a phone the side column is 467 px tall under a 275 px map (`layout/dumps/Plan_390x844.txt:64,691`) and the banner + card alone are taller than that. Draft and Select pin their Lock In (`Draft.luau:267-305`, `Select.luau:126-132`); Campaign does not. The 50 s plan timer makes this the single costliest defect: the player who cannot find Lock in gets auto-locked or loses the week.

### P2. Debate prep is invisible
PrepPanel has LayoutOrder 4, *below* the Tray (order 3) (`Campaign.luau:715` vs `:758`). The DebatePrep fixture is correct (week 8, prep due for week 9: `Fixtures.luau:57-58`; the dump shows `PrepTitle = "Debate prep for week 9..."` at `dumps/DebatePrep_1280x720.txt:1584`), but `shots/DebatePrep.png` shows nothing prep-related because it is the fifth panel down. A player who never scrolls past Lock in never sees the one decision that decides a debate (and loses a topic with 0 prep = gaffe). The capture agent's "fixture may be wrong" flag is resolved: fixture fine, layout wrong.

### P3. Campaign hides turn state and feedback in places players don't look
- Toasts (rejections, notices) are written into the map caption line (`Campaign.luau:1809-1824`) and suppressed entirely during reveals (`:1811`). Select shows no message at all on a rejected lock (`Select.luau:416-421`); Draft's hint vanishes after 3 s (`Draft.luau:34, 685-688`); Election and Results show nothing.
- "Your turn / locked / waiting" is spread over the stage label (`:1058-1068`), the caption (`:1817-1819`), the LockedNote inside the tray (`:766-772`) and the button text (`:1535`). The opponent's state ("Thinking..." / "Locked in") sits at the far right of the top bar in muted 16 px text (`:1091-1106`, `shots/Plan.png`).
- Lock in is silently disabled when the plan has a problem; the reason is a line inside the tray (`:1530-1536`). Bank, Clear, × and the prep ± are disabled with no reason (`:1542, 1418-1419`).

### P4. Six stacked panels of 14 px prose in the Campaign side column
The side column is EventBanner → RevealPanel → StateCard → Tray → PrepPanel → Feed (`Campaign.luau:509-847`). The state card alone is a title + toggle button + eight `Kit.size.small` (14 px) sentences (`:649-660`) + message button + a 3x2 grid + a hint. `shots/Plan.png`: the card's stats are a grey text block; momentum and lean are raw numbers ("Momentum: you 2.0 · them 2.0", "Lean: 3 toward them") where PLAN wants arrows on the node (`docs/PLAN.md:135`). The week card repeats the event and the next debate that the banner already shows. Campaign moments render 304–357 visible GUI objects (`layout/SUMMARY.md` table).

### P5. The top bar squeezes 10 labels into 26 px rows
`ROW_H = 26` (`Campaign.luau:50`); every label is `scaled()` down from 20 px (`:270-287`) into 2 rows (3 on phones, 86 px: `dumps/Plan_390x844.txt:32`). `shots/Plan.png`: "Week 3 of 12 / Plan your week / 0:28 / Money $4.5 / AP 3 of 3" then "Dana Okafor · 261 EV vs 251 EV · Rex Calloway Their money: Medium Locked in" read as one grey ribbon; the timer, the most urgent number on screen, is the same size as "Their money". The EV labels are mirrored ("Name · N EV" vs "N EV · Name", `:1085-1087`), which reads as a typo.

### P6. Select hides the platform picker on every screen size
Candidate cards are 170 px tall (224 portrait) for ~90 px of text (`Select.luau:29-31`; `shots/Select.png`: cards are half empty), so section "3. Platform (0/3)" starts at the bottom edge even at 1725x1055 and its chips are never visible without scrolling. The footer says "Still to pick: ... 3 more issue(s)" but gives no hint that they are below. With a 30 s timer this is the second-costliest defect. Lock In here is also the Kit default grey (`:289-296` sets no BackgroundColor3), so the primary action does not look primary.

### P7. The node map's Northeast is unreadable and tap targets are 30 px
`shots/MapReveal.png`, `shots/Draft.png`: NH/VT/MA/RI/CT/NJ/DE/MD/DC overlap; CT, DE, DC, NH labels are partly covered. `MapLayout.luau:68-96` relaxes overlaps by pushing circles apart, which cannot work where nine states share the space of one. `NodeMap.luau:18` sets `MIN_TAP = 30`; the audit exempts map nodes (`Audit.luau:23-26`, D-029). On a 390-wide phone the map is 243 px tall (`dumps/Plan_390x844.txt:69`) and the NE cluster is a smear.

### P8. The Draft panel buries the list on phones and wastes the map column on desktop
Portrait: map 30 %, panel 69 %, legend and board move *into* the scroll ahead of the state list, which is order 8 (`Draft.luau:316-326, 263`); the list starts roughly 600 px down a 478 px scroll region (`dumps/Draft_390x844.txt:658,717,1563`). Lock bar is 104 px (`:32`). Landscape: `shots/MapReveal.png` shows the right panel 80 % empty while the legend + board sit under the map at 14 px. The disabled "Pick a state to lock in" primary is accent at 40 % transparency (`Kit.setEnabled`, `Kit.luau:201-206`): low-contrast gold on gold, visible in `shots/Draft.png`.

### P9. Twelve text sizes, five button heights, ~38 background colors, four lock-in wordings
Kit defines 14/16/20/28/40 (`Kit.luau:21-27`); screens add 11, 15, 18, 22, 30, 64, 72 (`StateList.luau` tag 11 px; `Draft.luau:115,124,150,232,292`; `Lobby.luau:43,210`; `Results.luau:219`; `NodeMap.luau:113,126`). TextScaled floors are 9 px for text and 10 px for buttons (`Kit.luau:161,194`). Button heights: 44, 48, 52, 64, 104. Lock wording: "Lock In" / "Lock in" / "Locked — waiting for opponent" / "Your picks are locked in." / "Locked in. Waiting for your opponent..." (`flows.md §3`). Action nouns differ between buttons, tray, reveal and PLAN ("GOTV +1" / "Ground game +N" / "ran ads" / "media buy"). Timer warning is 5 s on Select and Draft, 10 s on Campaign, absent on Election (`Select.luau:27`, `Draft.luau:684`, `Campaign.luau:1073`).

### P10. Election night has no clock, clips its feed, and only shows your own skip
No countdown anywhere (`Election.luau:48-62` derives pacing from the deadline and never shows it). The feed's last row is clipped (`shots/Election.png`, "MA (11)" half visible; `:271-282` has no bottom padding and the newest row is at the top via `LayoutOrder = -k`, so the clipped row is the oldest; fine, but it looks broken). `updateSkip` reads only `seats[you]` (`:484-489`), so "Waiting for opponent to skip…" never changes when they do. "270 to win" is hidden in portrait (`:315`). The two Marker270 frames sit at y = -4 relative to their bar (`dumps/Election_1280x720.txt:52,71`): `Size = (0,3,1,8)` with anchor 0.5 (`:154-163`) deliberately overhangs the 14 px bar by 4 px each side. Not a visual bug, but it will trip the new "inside its parent" audit rule, so size the bar instead.

Two smaller things that are still in scope: the Lobby column is 480 px on a 1700 px viewport (`shots/Lobby.png`: two thirds of the screen is empty; fine on phones, bare on desktop), and the Results banner mixes "YOU WON" with "You lost" (`Results.luau:205-207`).

---

## 2. Design system

One rule above all others: **every screen has exactly one solid-accent (yellow) element, and it is the primary action.** Selection is shown with an accent outline, never a fill. Today "Ignore" (`shots/ChoiceWeek.png`), picked issue chips (`Select.luau:348`), the message button, and the timer all compete with Lock in.

### 2.1 Type scale (5 sizes, nothing else)

| Token | px | Font | Use |
|---|---|---|---|
| `Kit.size.caption` | 13 | Gotham | stat lines, tags, hints, legend, feed rows |
| `Kit.size.body` | 16 | Gotham / GothamMedium | buttons, sentences, list rows |
| `Kit.size.heading` | 20 | GothamBold | panel titles, state name, timer |
| `Kit.size.title` | 28 | GothamBold | screen titles, EV counters, "N of 51 states called" |
| `Kit.size.hero` | 48 | GothamBold | "270" on the Lobby, "You won", the private match code |

Rules: `Kit.MIN_TEXT = 12` is the floor for every `UITextSizeConstraint` (replaces 9 and 10). Nothing sets `TextSize` to a literal in `src/client/Screens` or `src/client/Map` (static test, §5). TextScaled only on single-line labels that must fit a fixed box (timer, EV number, map labels); everything else wraps at its token size. Remove `small`, `large`, `huge` from `Kit.size`; keep `body` and `title`; add `caption`, `heading`, `hero`.

### 2.2 Spacing and shape

```
Kit.space = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 }
Kit.radius = { control = 8, panel = 12, pill = 999 }   -- Kit.round() stays for circles
Kit.MIN_TOUCH = 44          -- unchanged
Kit.PRIMARY_H = 56          -- the one pinned primary button
Kit.BAR_H = 84              -- action bar: 20 status + 4 gap + 56 buttons + 4 (see 2.5)
Kit.HEADER_H = 44           -- one row; portrait Campaign adds a 28 px second row
Kit.MAP_NODE_MIN = 36       -- map tap target (was 30)
```

Panels: padding `md` (12) all round, inner list gap `sm` (8), corner `panel`. Rows inside a panel: gap `xs` (4). Between the big blocks of a screen: `sm` (8), same as today's `GAP`. Button heights are 44 or 56, nothing else (removes 48, 52, 64, 104). Grid cells (Select cards, chips) are 44 or a documented card height.

### 2.3 Color tokens

Keep `Colors.luau` as the single source and keep it pure. Current tokens stay (background, surface, raised, raisedHover, line, text, muted, neutral, undecided, accent, danger, good, player.*). Add:

```lua
Colors.onAccent = Colors.background         -- text on an accent fill
Colors.field = rgb(22, 25, 33)              -- text boxes and read-only wells (between background and surface)
Colors.warn = Colors.accent                 -- alias: timers under threshold use danger, not accent
Colors.disabledText = Colors.muted
function Colors.tint(base: RGB, color: RGB, t: number): RGB   -- public name for mix(), used by Election feed rows (0.35) and the legend (0.6)
```

`Kit.colors` mirrors every token as Color3 plus `Kit.playerColor(view, p)` (today duplicated in `Campaign.luau:115-118`, `Results.luau:52-55`, `Draft.luau:482-487`). Data colors (map fills from `Colors.stateFill`, player colors, Election row tints) are the only non-token colors allowed, and they must go through `Colors.stateFill` / `Colors.tint` / `Kit.playerColor`. Remove `Color3.new(1,1,1)` and the black TextStroke on swatches (`Select.luau:224-226`): the swatch label becomes `onAccent`-style dark text on light swatches (Amber, Teal) and `text` on dark ones, via a `Colors.onColor(rgb)` helper that returns `background` when the luminance is above 0.5 and `text` otherwise. The "38 distinct backgrounds" number will not go to 12 because map fills are blends; the static test instead asserts zero `Color3.` literals in screens.

### 2.4 Buttons

`Kit.button(text, onActivate, props)` keeps its signature; `props.variant` picks the look. `Kit.setEnabled(button, enabled)` and the new `Kit.setSelected(button, selected)` only touch the properties the variant owns, so a disabled primary never becomes transparent gold.

| Variant | Size | Background | Text | Stroke | Disabled |
|---|---|---|---|---|---|
| `primary` | full width x 56 (or 44 in a row) | accent | onAccent, GothamBold, body | none | bg raised, text muted (looks like a disabled secondary; the label says why, e.g. "Pick a state") |
| `secondary` (default) | 44 | raised | text, GothamMedium | none | bg surface, text muted |
| `danger` | 44 | surface | danger, GothamMedium | danger 1 px | text muted, stroke line |
| `chip` | 44, width by content or grid | raised | text | none; **selected = accent 2 px stroke + raisedHover bg** | text muted |

Toggle chips (candidate cards, swatches, issue chips, Choice answers, message issues, sort mode) all use `chip` + `setSelected`. The only accent fills left are the primary button and the timer digits. `AutoButtonColor` stays on for all enabled variants.

Also in Kit: `Kit.iconButton(glyph, onActivate, props)` = a 44x44 secondary for "×", "+", "−", "▾" (replaces the ad-hoc `Size = UDim2.new(0, BUTTON_H, 1, 0)` buttons in the tray and prep rows).

### 2.5 The standard pinned action bar (`src/client/UI/ActionBar.luau`)

Used by Select, Draft (Input), Campaign (Plan, Resolve), Election, Results. Anchored to the bottom of its column with explicit offsets (not a list layout), so the fake engine can measure it and the audit can prove it is on screen.

```
┌───────────────────────────────────────────────────────────────┐
│ status (caption, left, tone)             opponent (caption)   │  20 px
│ ┌──────────────┐ ┌──────────────────────────────────────────┐ │
│ │ secondary    │ │ PRIMARY                                  │ │  56 px
│ └──────────────┘ └──────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘  = Kit.BAR_H (84) incl. 4 px gaps
```

API:
```lua
local bar = ActionBar.new(parent, { primary = "Lock in", onPrimary = fn, secondary = "Bank +15s"?, onSecondary = fn? })
bar:setPrimary(text: string, enabled: boolean)
bar:setSecondary(text: string?, enabled: boolean)        -- nil hides it; primary takes the full width
bar:setStatus(text: string, tone: "muted" | "ok" | "warn" | "bad")
bar:setOpponent(text: string?)                           -- "Opponent: thinking" | "locked in" | "skipped" | "disconnected"
bar.root : Frame                                          -- Size = (1, 0, 0, Kit.BAR_H), AnchorPoint (0,1), Position (0,1,0,0)
bar.primary : TextButton                                  -- Name = "Primary"; also sets attribute PrimaryAction = true (audit)
```
The owning screen sizes its scroll region to `UDim2.new(1, 0, 1, -(Kit.BAR_H + Kit.space.sm))`. Secondary is at most 30 % of the width; primary never under 60 %.

Standard wording, used everywhere (fixes the four lock-in phrasings):
- primary: **"Lock in"** (enabled) / what is missing when disabled ("Pick a candidate", "Pick a state", "Fix your plan").
- status after locking: **"Locked in · waiting for opponent"** (tone ok).
- opponent: **"Opponent: thinking"**, **"Opponent: locked in"**, **"Opponent: skipped"**, **"Opponent: disconnected"**, **"Opponent: back"** for 4 s.
- reveal skip: primary **"Skip"** → **"Waiting for opponent…"** (disabled) after the tap.

### 2.6 The standard header (`src/client/UI/Header.luau`)

```
┌ title (heading, bold)   ·  subtitle (body, muted)        timer (heading, mono-ish digits) ┐  44 px
```
API: `Header.new(parent, { title })` → `setTitle`, `setSubtitle`, `setTimer(secondsLeft: number?, warnBelow: number?)`, `setTimerLabel("Results in")`. Timer color: accent, **danger when `secondsLeft < Kit.TIMER_WARN` (10 s)**; nil hides it. Select, Draft, Campaign and Election use it (Election with label "Results in"). The Campaign header gets a second optional row (28 px, portrait only) for the score line; see §3.4.

Single warning threshold: `Kit.TIMER_WARN = 10`. Remove `WARNING_SECONDS` (`Select.luau:27`), the literal 5 in `Draft.luau:684`, the literal 10 in `Campaign.luau:1073`.

### 2.7 Toasts (`src/client/UI/Toast.luau`, mounted once by `App.client.luau`)

One toast layer above the Screens container, not per screen. It subscribes to the Store, tracks the newest message id (`Messages.newestAfter`), and shows the latest message at top-center: max width 480, min height 44, caption-body text, `panel` corner, bg surface with a 2 px stroke (danger for `rejected`, accent for notices), 5 s, replaced by a newer one. Never hidden by a reveal. Removes: Lobby's toast label (`Lobby.luau:71-81, 115-119`), Campaign's caption toast (`:1809-1824`), Draft's rejection hint path (`:470-475`). Screens may still mirror a rejection into their action-bar status line (tone bad) so it persists; the toast is the attention-getter.

Placement: top-center sits under the Roblox top-left buttons' row but inside CoreUISafeInsets; on phones it is the only safe place that never covers the pinned bar.

### 2.8 Kit / Colors API summary (what WP0 adds or changes)

`Colors.luau`: add `onAccent`, `field`, `disabledText`, `tint` (rename of `mix`, keep `mix` as alias), `onColor(rgb)`.
`Kit.luau`: `size` → caption/body/heading/title/hero; add `space`, `radius`, `PRIMARY_H`, `BAR_H`, `HEADER_H`, `TIMER_WARN`, `MIN_TEXT`, `MAP_NODE_MIN`; `button` gains `variant`; add `setSelected`, `iconButton`, `playerColor(view, p)`, `caption(text, props)` (a wrapped caption-size label), `heading(text, props)`, `stat(parent, label, value)` (two-column caption/body pair for the state card); `panel` padding 12 and radius 12; `text` and `button` floors use `MIN_TEXT`. Remove nothing else; the old size names die when the last caller moves (CI will fail on `Kit.size.small` once removed, which is the intent).
New modules: `UI/Header.luau`, `UI/ActionBar.luau`, `UI/Toast.luau`, `UI/Collapsible.luau` (a panel with a 44 px title row that toggles its body; used for the event card, week card, state list).

---

## 3. Per-screen redesign

Tap-count targets are for the core task on each screen with no scrolling needed to reach the primary action.

### 3.1 Lobby (`Screens/Lobby.luau`)

Keep the single centered column; it works. Changes:
- Column max width 560 (was 480) so three buttons and the code row fill a desktop a little better; the "270" title uses `hero` + a one-line subtitle in `caption` muted.
- Buttons: "Play vs Bot" `primary` (56), "Find Match" and "Host Private Match" `secondary` (44). Join row: code box (field bg, mono, body) + "Join" secondary.
- Record line ("Rating 1000 · 3 won, 2 lost") in caption muted under the title, always reserved (so the layout does not jump when the profile arrives).
- Waiting state: the code in `hero` on a `field` well; "Cancel" `danger`.
- Toasts come from the global layer; delete the local toast.
- Naming: "Play vs Bot" is the name everywhere ("Play vs Bot again" on Results).

```
16:9 (and portrait: same, full width)
            ┌──────────────────────────┐
            │           270            │ hero
            │ Race a rival to 270 ...  │ caption
            │ Rating 1000 · 3W 2L      │ caption muted
            │ [    Play vs Bot       ] │ primary 56
            │ [    Find Match        ] │ secondary 44
            │ [ Host Private Match   ] │ secondary 44
            │ Have a code?             │
            │ [ CODE      ] [  Join  ] │ 44
            └──────────────────────────┘
```
Taps: practice 1, queue 1, join 1 + typing. Unchanged.

### 3.2 Select (`Screens/Select.luau`)

Goal: everything a player must tap is visible without scrolling on 16:9, and on a phone only the last two issue rows can be below the fold, with the pinned bar saying so.

- Header: `Header` ("Choose your campaign", timer).
- Candidates: `chip` cards, 4 columns x 2 rows at **112 px** on 16:9, 2 columns x 4 rows at **124 px** in portrait (was 170/224). Card contents: name (heading, TextScaled to one line), archetype (caption muted), "+ perk" (caption, good) and "− drawback" (caption, danger) wrapped; padding 8; no empty space. Selected = accent stroke 3 px (as now) + raisedHover.
- Colors: six `chip` swatches in **one row of 6 in both orientations** (390/6 = 61 px wide, 44 tall: fine). Label text uses `Colors.onColor`. Selected = white 3 px stroke + a "✓" prefix.
- Platform: heading "3. Platform (1/3)", chips 4x2 (16:9) / 2x4 (portrait) at 44; label "Jobs · 118 EV" on one line (drop the newline). Selected = accent stroke + "✓". A fourth tap while full flashes the status line "You already have 3; tap one to swap it" (tone warn, 3 s) instead of doing nothing silently.
- Pinned `ActionBar`: status = "Still to pick: a color, 2 issues ▾" (the "▾" tells the player it is below), or "Ready" (ok), or "Locked in · waiting for opponent"; opponent = "Opponent: thinking / locked in". Primary = "Lock in" (disabled label "Pick a candidate" / "Pick a color" / "Pick 2 more issues"). Rejections: toast + status (tone bad) + the lock is released (already handled at `:416-421`).
- Remove the pre-pick restore surprise: when `applyPrePick` fills everything, status says "Your last pick is loaded · Lock in or change it".

Height check, 16:9 at 1280x720: content = 720 − 44 header − 84 bar − 3 x 8 gaps = 568; needs 26 + 2x112+8 + 26 + 44 + 26 + 20 hint + 2x44+8 = 444. Fits. Portrait 390x844: 844 − 44 − 84 − 24 = 692; needs 26 + 4x124+24 + 26 + 44 + 26 + 20 + 4x44+24 = 862: the last two issue rows scroll; the status line tells the player.

```
16:9                                                   portrait
┌ Choose your campaign                      0:21 ┐     ┌ Choose your campaign        0:21 ┐
│ 1. Candidate                                   │     │ 1. Candidate                      │
│ [Okafor ][Calloway][Venkat ][Hale   ]  112     │     │ [Okafor    ][Calloway  ] 124      │
│ [Alvarado][Reyes  ][Strand ][Begay  ]  112     │     │ [Venkat    ][Hale      ]          │
│ 2. Color                                       │     │ [Alvarado  ][Reyes     ]          │
│ [Crim][Coba][Emer][Ambe][Viol][Teal]    44     │     │ [Strand    ][Begay     ]          │
│ 3. Platform (1/3)   caption hint               │     │ 2. Color                          │
│ [Jobs 118][Health 96][Schools][Environment]    │     │ [Cr][Co][Em][Am][Vi][Te]  44      │
│ [Safety  ][Roads    ][Tech   ][Farms      ]    │     │ 3. Platform (1/3)                 │
├────────────────────────────────────────────────┤     │ [Jobs 118 ][Health 96 ]  ↓ scroll │
│ Still to pick: a color, 2 issues ▾   Opp: ...  │     ├───────────────────────────────────┤
│ [              Pick a color                  ] │     │ Still to pick: 2 issues ▾  Opp:.. │
└────────────────────────────────────────────────┘     │ [        Pick 2 more issues     ] │
                                                       └───────────────────────────────────┘
```
Taps: 6 first time (1 + 1 + 3 + 1), 1 on rematch. Same as now, but with no scrolling on desktop and at most one flick on a phone.

### 3.3 Draft (`Screens/Draft.luau`, `DraftParts/*`), including MapReveal

- Header: `Header` with title "Round 4 of 8 · Stronghold" (or "The map for this match" during MapReveal, "Round 4 · picks revealed" during Reveal), subtitle = the one-line help (`Logic.help`), timer.
- Panel order (scroll): priority line (caption: "You have priority: ties go to you") → **Slots row** (one 44 px row: two `chip`s "1st: —" / "2nd: —", each with an inline "×" when filled; tapping a chip targets it, as now) → **the state list immediately** (`StateList`, rows 44, tag text raised to caption 13) → reveal box (Reveal mode only). "Clear both" goes away (the two × do it). The hint sentences move to the action-bar status line.
- Legend and Draft board: on 16:9 they stay under the map (`Below`), rebuilt as one 44 px legend row + a two-line board. In portrait they move into a `Collapsible` **at the end** of the panel ("Draft board ▾", collapsed by default) instead of ahead of the list. The map's own badges (H/B, rings, "1"/"2") already carry the information.
- Pinned `ActionBar` (Input mode only): status "Choose your 1st choice" / "Backup: tap another state (optional)" / "Locked in · waiting for opponent" / an illegal-tap reason (tone bad, until the next tap, not 3 s); opponent status; primary "Lock in" (disabled "Pick a state"). Bar height 84 replaces the 104 px LockBar.
- Portrait split: map takes `min(width / 1.6, 34 % of height)` (390 → 244 px, as now) and the panel the rest; no 1 % dead band (`:318,321`).
- Reveal (2 s, server-timed): the two chips "You got OH · stronghold" / "They got PA · stronghold" become one row of two `chip`-styled panels with the owner's color stroke; the clash note under them. No action bar (nothing to press).
- MapReveal: the right panel gets the legend (moved up from under the map), the "You have priority in round 1" line and a 3-line "How the draft works" caption, so it is not 80 % empty. Timer in the header.

```
16:9                                                            portrait
┌ Round 4 of 8 · Stronghold  +8 support there...    0:14 ┐     ┌ Round 4 of 8 · Stronghold          0:14 ┐
│ ┌ map 65% ───────────────┐ ┌ panel 35% ──────────────┐ │     │ ┌ map (244 px) ─────────────────────┐  │
│ │                        │ │ You have priority       │ │     │ │                                   │  │
│ │       ● ● ●            │ │ [1st: TX ×] [2nd: —   ] │ │     │ └───────────────────────────────────┘  │
│ │     ●  ●  ●  ●   [NE]  │ │ All states, biggest first│ │     │ You have priority                      │
│ │   ●   ●  ●  ●    ladder│ │ [CA California 54  even]│ │     │ [1st: TX ×] [2nd: —   ]                │
│ │                        │ │ [TX Texas  40  +3 them ]│ │     │ [CA California 54 EV    even       ]   │
│ │ ● AK  ● HI             │ │ [FL Florida 30  +3 you ]│ │     │ [TX Texas 40 EV      +3 them       ]   │
│ ├────────────────────────┤ │ ...                     │ │     │ [FL Florida 30 EV    +3 you        ]   │
│ │ ● leans you ● leans them│ ├─────────────────────────┤ │     │ ... scroll ...                          │
│ │ You: home CA · TX, OH  │ │ Ready · Opp: locked in  │ │     ├────────────────────────────────────────┤
│ │ Them: home FL · IL, PA │ │ [       Lock in       ] │ │     │ Backup optional · Opp: locked in       │
│ └────────────────────────┘ └─────────────────────────┘ │     │ [            Lock in                 ] │
└────────────────────────────────────────────────────────┘     └────────────────────────────────────────┘
```
Taps per round: 2 (state + Lock in), 3 with a backup. Unchanged, but on a phone the list is now the second thing on screen instead of the eighth.

### 3.4 Campaign (`Screens/Campaign.luau` → split into `CampaignParts/`)

This is the big one. Three structural moves, then the panel details.

**Move 1: Lock in, Bank and the plan status go into a pinned ActionBar** under the side column (16:9) or at the bottom of the screen (portrait). Primary "Lock in" (disabled label from `PlanDraft.problem`: "Not enough money" etc., via `Net.reasonText` shortened); secondary "Bank +15s" (hidden when the bank is empty, disabled with label "Bank used" otherwise... keep it simple: hidden when `bank < chunk`); status line = "AP 2/3 · $3.0 left · 1 flight" while editing, the problem text (tone bad) when the plan is invalid, "Locked in · waiting for opponent" after; opponent status at the right. During Resolve the bar's primary is "Skip" / "Waiting for opponent…"; during Debate the bar shows status "Debate · topic 2 of 3" and no buttons (server: NotSkippable).

**Move 2: the side column order becomes State card → Event card → Debate prep → Plan list → Week card.** Prep is only built in prep weeks and sits right under the event, above the plan, so it is seen before Lock in. The event card is a `Collapsible` that is *expanded* in Choice weeks (the answer chips live in it) and on Spotlight/Regional weeks, *collapsed to its title row* ("Event · Donor retreat ▾") otherwise. The week card is a `Collapsible`, collapsed by default on phones, expanded on 16:9. The RevealPanel replaces the state card during reveals, as now.

**Move 3: the header becomes one 44 px row on 16:9, two rows on phones**, via `Header` plus a score strip:

```
16:9:  Week 3 of 12 · Plan your week          Dana Okafor 261 ◂ ▸ 251 Rex Calloway          $4.5 · 3 AP        0:28
portrait row 1:  Week 3 of 12 · Plan                                        0:28
portrait row 2:  Dana 261 ◂▸ 251 Rex   ·   $4.5   ·   3 AP                 (28 px, body)
```
Numbers are colored with the player colors; "◂ ▸" is a 2-segment bar (two thin frames, widths proportional to projected EV) rather than text, 8 px tall under the names on 16:9. Opponent status and "Their money: Medium" leave the header (status → action bar; money bracket → week card). The disconnect notice stays as an extra 24 px row (as now).

**State card** (`CampaignParts/StateCard.luau`):
- Title row: "Ohio · 17 EV" (heading) + tags as small pills ("Battleground", "Your stronghold", "You are here") in caption on a raised pill, not an accent sentence.
- Stats as a 2-column grid of `Kit.stat` pairs (caption label over body value), 4 cells: Public poll "35 – 37 · 28 undecided"; Lean "+3 them"; Momentum "you 2.0 · them 2.0" with ▲/▼ glyphs colored by who leads; Ground game "0 / 4 · pool $8.9". Internal poll, when present, is a fifth full-width cell in `good`. "Top issues: Jobs, Schools" stays a caption line. The move line ("flight from TX, $2.0") is folded into the Rally/Fundraise button labels ("Rally ✈ $2.0") and removed as a sentence.
- Message chips: replace the "Message: Jobs ×1.5 (change)" button + 8-button picker with one horizontal row of ≤5 `chip`s: the state's two top issues and your three platform issues, deduplicated, each labeled "Jobs ×1.5", best one pre-selected (`PlanDraft.bestIssue`), plus a "More ▾" chip that expands the remaining issues as a second row. Changing the message is 1 tap (was 2).
- Action grid 3x3: **Rally · Fundraise · Ad / Attack ad · Poll · Ground game / Region poll · Pivot · (empty)**. Labels carry the extra cost ("Ad $3.0", "Ground game +1 $2.0", "Region poll $3.0") and the short reason when greyed ("Poll (polled)"). Region poll uses the selected state's region (`StateData.byId[id].region`, cost `config.REGION_POLL_COST`) and is the fix for the unreachable action (`flows.md §1e`). Pivot moves here from the tray and opens its two-step chooser (drop → add) *in place of the action grid*, with a "Cancel" secondary. The hint line under the grid stays (caption) and shows the full reason for the first greyed button.
- The state list toggle ("Pick a state from the list") becomes a 44 px `Collapsible` title row at the bottom of the card ("All states ▾ · sorted closest"), with the sort as a `chip` row inside, rows 44 px.

**Plan list** (`CampaignParts/PlanList.luau`): title row "Your plan · 2 of 3 AP" with a `danger` "Clear" at the right (two-tap confirm: label turns to "Clear? tap again" for 3 s). Rows: "1. Rally · Ohio · Jobs ✈" in body, "×" `iconButton`. The cost line moves to the action-bar status. Empty state: "Tap a state, then an action." in caption.

**Debate prep** (`CampaignParts/Prep.luau`): title "Debate prep · week 9 · 6 points"; three rows: topic name + platform tag (caption), [−] value [+] as `iconButton`s, and a 6-cell dot strip under the value showing the allocation. When a button is disabled the row's caption says why ("max 4" / "take from another topic"). Footer caption: "0 prep on a lost topic is a gaffe." The action-bar status in prep weeks appends "· prep 2/2/2".

**Event card** (`CampaignParts/EventCard.luau`): title row "Event · Windfall · Donor retreat ▾" (caption kind, heading name); body = text (caption muted) + effect (body); Choice weeks add the answer row of three `chip`s (selected = accent stroke; "Ignore" preselected as now) and the rules caption. The map "*" badge stays.

**Reveal panel**: Resolve lines as now (8 max, body), the summary in accent, no Skip button inside (moved to the bar). Debate: three topic rows, each "Schools" + two thin bars (you / them) with the scores at the ends and "you win / tie / they win" in caption, revealed one per 2 s as now; the callouts (Gaffe!, Sweep!) under them in accent.

**Bug fixes folded in** (also listed in §4): hide the event card during the Debate reveal; keep the state card selectable (read-only) during Resolve so a player can inspect a state while results play; selecting a state never closes the list on 16:9 (it does on phones).

```
16:9 (1280x720)
┌ Week 3 of 12 · Plan your week      Dana Okafor 261 ◂▸ 251 Rex Calloway      $4.5 · 3 AP      0:28 ┐ 44
│ ┌ map 62% ──────────────────────────────┐ ┌ side 38% (scroll) ────────────────────────────────┐ │
│ │ Tap a state to plan there    (caption) │ │ Ohio · 17 EV  [Battleground][You are here]        │ │
│ │                                        │ │ Public poll        Lean                          │ │
│ │          ● ●  ●                        │ │ 35 – 37 · 28 und.  +3 them                       │ │
│ │       ●  ●  ●  ●  ●   [NE]             │ │ Momentum           Ground game                   │ │
│ │     ●   ●  ●  ●  ●    ladder           │ │ ▲ you 2.0 · 2.0    0 / 4 · pool $8.9             │ │
│ │                                        │ │ Message: [Jobs ×1.5][Schools ×1.2][Health ×1.0][More ▾]
│ │  ● AK  ● HI                            │ │ [Rally     ][Fundraise ][Ad $3.0   ]              │ │
│ │                                        │ │ [Attack $3 ][Poll $1.0 ][Ground +1 $2]            │ │
│ │                                        │ │ [Region $3 ][Pivot     ][           ]             │ │
│ │                                        │ │ All states ▾ · sorted closest                     │ │
│ │                                        │ │ Event · Windfall · Donor retreat ▾                │ │
│ │                                        │ │ Your plan · 2 of 3 AP                   [Clear]   │ │
│ │                                        │ │ 1. Rally · Ohio · Jobs                      [×]   │ │
│ │                                        │ │ 2. Fundraise · Florida ✈ $2.0               [×]   │ │
│ │                                        │ │ Week card ▾                                       │ │
│ │                                        │ ├───────────────────────────────────────────────────┤ │
│ │                                        │ │ AP 2/3 · $1.5 left · 1 flight    Opponent: thinking │ 20
│ │                                        │ │ [Bank +15s] [              Lock in              ] │ 56
│ └────────────────────────────────────────┘ └───────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘

portrait (390x844)
┌ Week 3 of 12 · Plan                 0:28 ┐ 44
│ Dana 261 ◂▸ 251 Rex  ·  $4.5  ·  3 AP     │ 28
│ ┌ map 390x244 ─────────────────────────┐  │
│ │        ● ●  ●                        │  │
│ │     ●  ●  ●  ●  ●   [NE]             │  │
│ │   ●   ●  ●  ●  ●                     │  │
│ └──────────────────────────────────────┘  │
│ Ohio · 17 EV  [Battleground]              │ ┐
│ Public poll 35–37·28   Lean +3 them       │ │ side scroll
│ Momentum ▲2.0·2.0      Ground 0/4 · $8.9  │ │ (844-44-28-8-244-8-84-8 = 420 px)
│ [Jobs ×1.5][Schools ×1.2][More ▾]         │ │
│ [Rally  ][Fundraise][Ad $3.0 ]            │ │
│ [Attack ][Poll $1  ][Ground+1]            │ │
│ [Region ][Pivot    ][        ]            │ ┘ ... scroll for list, event, plan, week card
├───────────────────────────────────────────┤
│ AP 2/3 · $1.5 left        Opp: thinking   │ 20
│ [Bank +15s][          Lock in           ] │ 56
└───────────────────────────────────────────┘
```
On a 390 px phone the first 420 px of the side column show the whole state card through the action grid; that is the entire "tap a state → tap an action" loop with Lock in pinned beneath. The list, event and plan need one flick.

**Tap-count targets** (core task from `flows.md §1d`: rally in two states, fundraise in a third, lock in): 7 today → **6** (the home-state rally needs no state tap, as today; the message is preselected; Lock in is always on screen so no scroll). Internal poll: 3 → 3. Change the message: +2 → **+1**. Answer a Choice: 2 → 2 (the event card is first in Choice weeks). Region poll: unreachable → 3.

**Resolve / ChoiceWeek / DebatePrep / Debate moments** are the same screen with: Resolve = reveal panel + bar "Skip"; ChoiceWeek = event card first and expanded; DebatePrep = prep panel between event and plan, bar status "· prep 2/2/2"; Debate = reveal panel with topic bars, event card hidden, bar with status only.

### 3.5 Election (`Screens/Election.luau`)

- Header: `Header` with title "Election night", subtitle "35 of 51 states called" / "Too close to call: Pennsylvania…", timer labeled "Results in 0:32" (`deadline − now`; fixes "no clock").
- Counters: one 72 px strip with both candidates: name (body, colored), EV (title), states (caption), and a shared 14 px bar with the 270 tick (one bar, two fills from each end, the tick in the middle at 270/538): reads as "who is closer to the line" at a glance and halves the height on phones (was 112). The tick is a child of a 22 px-tall bar container so nothing overhangs its parent (fixes the y = −4 dump finding at `:154-163`).
- Banner at the end: replaces the subtitle and the strip with "Rex Calloway wins 289–249" (title, winner's color stroke) + the tiebreak sentence in caption.
- Map 66 % / feed 34 % on 16:9; portrait: counters 72, map `min(width/1.6, 38 %)`, feed the rest. Feed rows 44 min height, caption EV + body text, winner tint via `Colors.tint`, newest on top, **UIPadding bottom 8** so the last row is never clipped.
- Pinned `ActionBar`: primary "Skip to results" → "Waiting for opponent…"; opponent status "Opponent: skipped" when `seats[them].skip` (fixes `:484-489`); status "Safe states first, closest last" (caption muted).

```
16:9
┌ Election night · 35 of 51 states called                                      Results in 0:32 ┐
│ Dana Okafor 179 ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬|270|▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬ 252 Rex Calloway     12 · 23 states  │ 72
│ ┌ map 66% ───────────────────────────┐ ┌ Calls ─────────────────────────────────────────────┐ │
│ │                                    │ │ KY 8   called for Rex Calloway by 2.8              │ │
│ │                                    │ │ NJ 14  called for Dana Okafor by 3.0               │ │
│ │                                    │ │ ...                                                │ │
│ │                                    │ ├────────────────────────────────────────────────────┤ │
│ │                                    │ │ Safe states first, closest last     Opp: watching  │ │
│ │                                    │ │ [                Skip to results                 ] │ │
│ └────────────────────────────────────┘ └────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────────────────────┘
```
Taps: 1 to skip. Unchanged.

### 3.6 Results (`Screens/Results.luau`)

Already the cleanest screen (`shots/Over.png`). Changes:
- Banner "You won" / "You lost" / "No result" in `hero` (sentence case both; fixes `:205-207`), reason in body muted, rating line reserved (never shifts the layout when it arrives).
- EV bar 14 px with the 270 tick, the two player panels side by side as now (each ~185 px on a phone: fine), the EV number in `title` not `huge`.
- Closest states and debates as two `Collapsible`s expanded by default; rows in body.
- Pinned `ActionBar`: primary "Play vs Bot again" / "Play again", secondary "Back to lobby". Stats PLAN §7 asks for (flipped states, money raised, biggest swing) are **not** in the View today (`flows.md §2 Results`); listed in §6 as a server-side follow-up, not done here.

Taps: 1 either way. Unchanged.

---

## 4. Bugs found (not style)

Each gets a failing spec first (CLAUDE.md working rules).

| # | Bug | Where | Fix | Package |
|---|---|---|---|---|
| B1 | **Choice prompt shown during the Debate reveal.** `shownEvent` hides the event only for `reveal == "Resolve"` (`Campaign.luau:236-241`); during `reveal == "Debate"` the week's Choice event renders with "Choose how to respond: Attack / Defend / Ignore" and no buttons (`shots/Debate.png`, `dumps/Debate_1280x720.txt:694-704`). | Campaign | `shownEvent` returns nil for any non-nil `reveal`; the event card appears when the Plan stage starts. | WP3 |
| B2 | **Debate prep panel below Lock in and below the fold.** Order 4 after Tray order 3 (`:715,758`); `shots/DebatePrep.png` shows no prep at all. Fixture is correct (`Fixtures.luau:57-58`). | Campaign | Prep between event and plan; Lock in pinned. Spec: in the DebatePrep fixture, `PrepPanel.AbsolutePosition.Y < LockIn.AbsolutePosition.Y` and both inside the screen. | WP3 |
| B3 | **Region poll unreachable.** Tray text supports it (`:221-222`), no button (`:691`). | Campaign | 7th action button; region from `StateData.byId[id].region`. Spec: tapping it adds `{kind="RegionPoll", region=...}` and the tray line names the region. | WP3 |
| B4 | **Silent Select rejections.** `Select.luau:416-421` releases the lock but shows nothing; the screen has no message surface. | Select + Toast | Global toast + action-bar status (tone bad) with `Net.reasonText`. Spec: a `BadPlatform` rejection after Lock in shows the text and re-enables the chips. | WP0 (toast) + WP2 |
| B5 | **Campaign toasts suppressed during reveals** (`:1811`). A rejection of Skip or Bank during Resolve is invisible. | Campaign | Toast layer is screen-independent. | WP0 |
| B6 | **Election feed clips its last row** (`shots/Election.png`; `Election.luau:271-282` no bottom padding, `Size = 1,-(FEED_TITLE+SKIP_HEIGHT+GAP)`). | Election | UIPadding bottom 8 and the bar outside the feed. Spec (fake): `Feed.AbsoluteSize.Y + Feed.AbsolutePosition.Y <= Side bottom − BAR_H`. | WP4 |
| B7 | **Election ignores the opponent's skip** (`:484-489` reads only `seats[you]`). | Election | Read `seats[them].skip` into the bar's opponent status. Spec: a payload with the other seat's `skip = true` shows "Opponent: skipped". | WP4 |
| B8 | **No countdown on Election** (`:48-62`). | Election | Header timer "Results in". Spec: the header timer text equals `Kit.clock(deadline − now)`. | WP4 |
| B9 | **Marker270 overhangs its bar by 4 px** (`:154-163`, dump y = −4). Harmless today, fails the new containment audit. | Election | Tick inside a 22 px bar container. | WP4 |
| B10 | **Draft state list ordered after legend and board in portrait** (`Draft.luau:263, 323-326`); list is 8th in the scroll. | Draft | List right after the slots; board collapsible at the end. Spec (fake, portrait): `StateList.LayoutOrder < Board.LayoutOrder`. | WP4 |
| B11 | **1 % dead band between the Draft map and panel in portrait** (`:318` map 0.30, `:321` panel at 0.31). | Draft | Explicit pixel math: `panel.Position = (0, mapH + GAP)`. | WP4 |
| B12 | **Northeast nodes overlap and hide labels** (`shots/MapReveal.png`; `MapLayout.luau:68-96`). | MapLayout | NE inset ladder (§5 WP1). Spec: no two nodes overlap by more than `GAP`, every label box ≥ 24 px wide at a 390 px map. | WP1 |
| B13 | **Map tap targets 30 px** (`NodeMap.luau:18`) vs the 44 px PLAN rule and the D-029 "at least 30" exemption. | NodeMap | `MIN_TAP = Kit.MAP_NODE_MIN = 36`; the list alternative stays. Audit checks ≥ 36 instead of skipping map nodes. | WP1 |
| B14 | **TextScaled floors of 9/10 px** (`Kit.luau:161,194`) and an 11 px tag (`StateList.luau`, tag cell `TextSize = 11`). | Kit, StateList | `MIN_TEXT = 12`, tag → caption. Audit rule. | WP0 + WP4 |
| B15 | **Audit runs once, 0.5 s after mount, in production too** (`Router.luau:70-74`), and never after an orientation flip. | Router, Audit | Run only when `DebugScreen` or `DebugText` is set (or RunService:IsStudio()), and re-run after `ctx.portrait()` changes. | WP0 |
| B16 | **`Kit.setEnabled` makes a disabled primary 40 % transparent gold** (`Kit.luau:201-206`; `shots/Draft.png` "Pick a state to lock in"). | Kit | Variant-aware disabled look (§2.4). | WP0 |
| B17 | **Debug panel buttons are 37 px wide on a 390 px screen** (`layout/SUMMARY.md` last bullet; `DebugPanel.luau`). Hidden by default, but agents use it on phones. | DebugPanel | Wrap the command row into two rows of 44 px; the audit's new width rule covers it when visible. | WP0 (small) |

Not bugs, recorded so nobody chases them: Marker y = −4 is intentional overhang (B9 is about the audit); the DebatePrep fixture is right; "Locked in" for the opponent in the Plan capture is the bot having locked instantly.

---

## 5. Implementation order: five work packages

Rules: WP0 lands first and alone. WP1–WP4 are independent of each other and touch disjoint files; they can run in parallel branches off WP0. Docs are append-only per package (`CHANGELOG.md` one bullet block each, `docs/TESTING.md` one section each, `docs/DESIGN.md` D-030 written by WP0 and extended with a sub-bullet per package). Every package ends with the four CLAUDE.md commands clean and `lune run tests` green.

### WP0 — Foundation (everyone builds on this)

Files: `src/shared/UI/Colors.luau`, `src/client/UI/Kit.luau`, `src/client/UI/Audit.luau`, **new** `src/client/UI/Header.luau`, `src/client/UI/ActionBar.luau`, `src/client/UI/Toast.luau`, `src/client/UI/Collapsible.luau`, `src/client/App.client.luau` (mount Toast, pass nothing new in ctx), `src/client/Router.luau` (audit gating + re-run on orientation), `src/client/DebugPanel.luau` (B17), `src/client/Screens/Common/Layout.luau` (use `space`/`radius`; `heading` uses `Kit.size.heading`), `tests/ui/Helpers.spec.luau`, **new** `tests/ui/Kit.spec.luau`, `tests/ui/Audit.spec.luau`, `tests/ui/Tokens.spec.luau`, and the split of `tests/ui/ClientFixes.spec.luau` into `tests/ui/Select.spec.luau`, `tests/ui/Results.spec.luau`, plus moving its Campaign/Draft/Lobby cases into the existing per-screen specs (so WP2–WP4 never edit the same spec file). Docs: `docs/DESIGN.md` D-030 (the design system and the one-primary rule), `CHANGELOG.md`, `docs/TESTING.md`.

Also in WP0, mechanical only: replace `Kit.size.small/large/huge` with the new names across all screens (search-and-replace, no layout change), so the old names can be deleted and CI enforces the scale from day one. This is the only time WP0 touches screen files, and it happens before the branches fork.

Acceptance:
- `Kit.spec`: `button` variants set the documented colors; `setEnabled(false)` on a primary yields raised bg + muted text; `setSelected(true)` on a chip sets a 2 px accent stroke; every `UITextSizeConstraint` created by Kit has `MinTextSize == 12`; `Kit.size` has exactly five keys; `ActionBar.new` places `root` at the bottom with height 84 and a `PrimaryAction` attribute on the primary; `Header.setTimer(9)` turns the timer danger-colored and `setTimer(10)` does not; `Toast` shows the newest Store message, replaces it, hides after 5 s on the fake clock, and shows rejections with the danger stroke.
- `Tokens.spec` (static, reads files with `@lune/fs` from the repo root): no `Color3.new|fromRGB` and no `TextSize = <digits>` in `src/client/Screens/**` and `src/client/Map/**` (DebugPanel excluded); no `Size = UDim2.new(1, 0, 0, 52)`/`48`/`64`/`104` button heights (regex on `0, (48|52|64|104))` in those folders — crude but catches regressions).
- `Audit.spec`: builds small fake trees that violate each rule below and asserts one problem per violation; a compliant tree yields zero.

New Audit rules (`Audit.run(root, label)` keeps its signature and output format `[270] UI audit ...`):
1. **Text floor:** a visible TextLabel/TextButton with `TextSize < 12`, or TextScaled with a `UITextSizeConstraint.MinTextSize < 12` (or none), is a problem.
2. **Button width:** visible non-map GuiButtons under 44 px wide are a problem (today only height is checked).
3. **Map nodes ≥ 36:** replace the NodeMap exemption with a 36 px minimum (both axes).
4. **Inside its parent and the screen:** a visible GuiObject whose AbsolutePosition/AbsoluteSize falls outside the root by more than 1 px, or outside its nearest ScrollingFrame ancestor's canvas width, is a problem. Children of a ScrollingFrame are checked horizontally only (vertical overflow is what scrolling is for).
5. **Primary action pinned:** exactly one visible button with attribute `PrimaryAction` per screen (zero allowed on Lobby-waiting, MapReveal, Draft-reveal, Debate); it must not have a ScrollingFrame ancestor and must be fully inside the root. (Fake engine: holds because the bar is explicitly positioned.)
6. **One accent fill:** at most one visible GuiButton with `BackgroundColor3 == Kit.colors.accent`.
7. **Type scale:** every visible text's `TextSize` is one of the five tokens (TextScaled labels report their max); anything else is a problem. Also print the distinct-size count in the summary line.
8. **Audit gating (Router):** run only under DebugScreen/DebugText or in Studio; re-run after an orientation change; keep the 0.5 s delay.

### WP1 — Map (`MapLayout`, `NodeMap`, `MapInterface`)

Files: `src/shared/UI/MapLayout.luau`, `src/client/Map/NodeMap.luau`, `src/client/Map/MapInterface.luau`, `tests/sim/MapLayout.spec.luau` (new or extend the existing MapLayout coverage; pure), `tests/ui/NodeMap.spec.luau` (new, fake engine).

Work:
- **Northeast inset ladder:** VT, NH, MA, RI, CT, NJ, DE, MD, DC leave the projection and become a vertical column of equal-radius nodes at x ≈ 0.955, y from 0.20 to 0.62 (one per 0.052), with a thin leader line (`line` color, 1 px) from each ladder node to its true centroid. ME stays on the map. `MapLayout.INSETS` grows accordingly; relaxation runs on the remaining 42 nodes only. Expose `MapLayout.LADDER` (ordered ids) so NodeMap draws leaders and tests can assert the order.
- `MIN_TAP = Kit.MAP_NODE_MIN` (36). Node label: `Kit.size.caption` minimum via `MIN_TEXT` (TextScaled max heading). Badge text ≥ 12.
- `Mark` gains `arrow: ("up" | "down")?` (momentum lead: ▲ in the leader's color under the node, ▼ never needed — show the arrow only for the leader; two arrows if tied above a threshold is noise, so: one arrow, leader's color). Campaign will set it in WP3; until then nothing changes on screen. `MapInterface.Map` gains nothing else.
- AK/HI insets stay.

Acceptance:
- `MapLayout.spec`: no pair of nodes overlaps (distance ≥ r1 + r2 + GAP); every node inside [r, 1−r] × [r, H−r]; the nine ladder ids are at the same x in the listed order; at a 390 px wide map every label box (0.8 · 2r · 390) is ≥ 24 px for the 42 projected states and ≥ 20 px for ladder nodes (ladder radius chosen to make that true: r = 0.0275 → 21 px box at 390; the hit box is 36 px regardless).
- `NodeMap.spec`: every `hit` has `UISizeConstraint.MinSize ≥ (36,36)`; leaders exist for the nine ladder nodes; `setMarks` with `arrow` creates/hides the glyph; audit rule 3 passes on a mounted map at 390x244.

### WP2 — Lobby, Select, Results (the `Layout.page` screens)

Files: `src/client/Screens/Lobby.luau`, `src/client/Screens/Select.luau`, `src/client/Screens/Results.luau`, `src/client/Screens/Common/Data.luau`, `tests/ui/Lobby.spec.luau`, `tests/ui/Select.spec.luau`, `tests/ui/Results.spec.luau`.

Work: §3.1, §3.2, §3.6, bug B4.

Acceptance:
- Select at 1280x720 (fake): `Issues` grid's bottom (`AbsolutePosition.Y + AbsoluteSize.Y`, computed from the explicit card/row heights: WP2 sets `Candidates`/`Colors`/`Issues` frames to explicit heights instead of AutomaticSize so the fake can measure them) ≤ scroll bottom, i.e. no scrolling needed; at 390x844 the `LockIn` primary is inside the screen and not inside the ScrollingFrame; status text reads "Still to pick: ... ▾" when something is below the fold.
- Select: a 4th issue tap sets the status line to the swap hint; a rejected lock shows a toast containing `Net.reasonText("BadPlatform")` and re-enables chips (existing retry spec moves here).
- Results: banner text is "You won"/"You lost"; `PlayAgain` carries `PrimaryAction`; rating line visible only for the matching matchId (existing specs).
- Lobby: "Play vs Bot" is the only accent button; Join validation unchanged (existing spec); no local toast object exists.
- Audit clean on all three at both sizes.

### WP3 — Campaign

Files: `src/client/Screens/Campaign.luau` (shrinks to mount + routing of moments), **new** `src/client/Screens/CampaignParts/{TopBar,StateCard,PlanList,Prep,EventCard,Reveal}.luau`, `src/shared/UI/PlanDraft.luau` (add `messageChoices(config, view, id): { {issue, mult} }` — the ≤5 chips; `regionOf(id)`; `shortProblem(reason)` for the disabled primary label), `src/shared/UI/StateOrder.luau` (no change expected; listed so nobody else touches it), `src/client/Net.luau` (REASONS wording to fit "Lock in: {reason}" and the greyed buttons; no new codes), `tests/ui/Campaign.spec.luau`, **new** `tests/ui/CampaignParts.spec.luau`, `tests/ui/PlanDraft.spec.luau` (pure; extend if it exists under tests/sim, else create under tests/ui).

Work: §3.4, bugs B1, B2, B3, momentum arrows via `Mark.arrow` (from WP1; if WP1 is not merged yet, set the field anyway: NodeMap ignores unknown fields).

Acceptance (fake engine unless noted):
- Plan fixture at 390x844 and 1280x720: `LockIn` has `PrimaryAction`, no ScrollingFrame ancestor, and `AbsolutePosition.Y + 56 ≤ screen height`; exactly one accent-filled button.
- DebatePrep fixture: `PrepPanel.LayoutOrder < PlanList.LayoutOrder`; both `PrepPlus1` and `PrepMinus1` are 44x44; disabled steppers write their reason into the row caption.
- Debate fixture: `EventCard` not visible (B1); `DebateTopic1..3` names still exist (agents and e2e read them).
- ChoiceWeek fixture: `EventCard` is the first visible side panel and expanded; `ChoiceIgnore` is selected via stroke (no accent fill); answering then Lock in sends `choice` (existing spec).
- Region poll: tapping `RegionPoll` on a selected state adds a RegionPoll action for that state's region; the plan line reads "Region poll · Mid-Atlantic"; cost shows `REGION_POLL_COST`.
- Message chips: `PlanDraft.messageChoices` returns ≤ 5 entries, best first, deduplicated, with the state's top issues and the platform; tapping a chip changes the next Rally's issue (1 tap).
- Clear needs two taps within 3 s (fake clock).
- Resolve: `Primary` reads "Skip", then "Waiting for opponent…" disabled; the state card stays visible and read-only (no action buttons).
- Header: at 1280x720 one row of 44; at 390x844 two rows (44 + 28); timer danger-colored under 10 s.
- Audit clean on all five Campaign moments at both sizes; the existing "follows a whole autoplayed practice match" spec still passes.
- Studio (humans, TESTING.md): Lock in visible without scrolling on a phone emulator in portrait; the prep panel visible in week 3 and week 8; a wrong plan shows why on the Lock in button.

### WP4 — Draft and Election (map + side + pinned bar screens)

Files: `src/client/Screens/Draft.luau`, `src/client/Screens/DraftParts/{Board,StateList,Logic}.luau`, `src/client/Screens/Election.luau`, `tests/ui/Draft.spec.luau`, `tests/ui/Election.spec.luau`.

Work: §3.3, §3.5, bugs B6–B11, B14 (StateList tag).

Acceptance:
- Draft Input at 390x844: `StateList.LayoutOrder < Board.LayoutOrder`; `LockIn` has `PrimaryAction`, inside the screen, not in a ScrollingFrame; the illegal-tap reason stays in the bar status until the next tap (no 3 s expiry); "Clear both" no longer exists and the `Clear1`/`Clear2` glyph buttons are 44x44.
- Draft MapReveal: no `PrimaryAction` (allowed by rule 5); the panel shows the legend and the priority line.
- Draft at 1280x720: `map` height = 0.66 of the column as now; `Below` holds legend + board.
- Election: header timer text present and equals `Kit.clock(deadline − now)` on the fake clock; `Feed` bottom ≤ side bottom − 84; opponent `skip = true` shows "Opponent: skipped"; `Marker` inside its bar container (rule 4 passes); counters strip 72 px; audit clean at both sizes; the existing pacing/tiebreak/skip specs pass unchanged.

### Merge order and docs

WP0 → (WP1 ‖ WP2 ‖ WP3 ‖ WP4) → a final "v0.4.0 UI overhaul" CHANGELOG header that references the four blocks, TESTING.md section "UI overhaul (v0.4.0)" with one phone-portrait and one 16:9 checklist per screen (what to tap, what must be visible without scrolling, what to screenshot), and `Version.luau` bump. No numbers in `Sim/Config.luau` change, so DESIGN.md gets only D-030 (design system, one-primary rule, map ladder, naming table) and no tuning entries.

---

## 6. Decisions the humans should make (ask before WP1/WP3 start)

1. **Northeast inset ladder** (WP1): the nine small NE states move into a labeled column at the right edge of the map with leader lines. This changes how the map looks; the alternative is to keep the projection and accept overlap, relying on the list. Recommendation: ladder.
2. **Only one yellow thing per screen** (WP0): selection becomes an outline, the timer digits stay yellow, Lock in is the only filled yellow button. "Ignore"/picked chips stop being solid yellow. Recommendation: yes; it is what makes Lock in findable.
3. **Collapsed cards by default** (WP3): the event card is collapsed on non-Choice weeks and the week card is collapsed on phones (expanded on 16:9). Risk: players miss the event's effect line. Alternative: event always expanded, week card always collapsed. Recommendation: event collapsed to a two-line row (kind + name + effect), never to a single line.
4. **Action names** (WP3): buttons/tray/reveal all say Rally, Fundraise, Ad, Attack ad, Poll, Region poll, Ground game, Pivot. PLAN.md says "media buy" and "GOTV". Recommendation: the player-facing names above; PLAN keeps its rule names.
5. **Region poll and Pivot in the action grid** (WP3): region poll is in the rules and the server but has never had a button. Confirm it was not cut on purpose (DESIGN.md D-027 and the region note at `docs/DESIGN.md:120` suggest it is live).
6. **Timer warning at 10 s everywhere** (WP0): Select and Draft move from 5 to 10. Recommendation: yes.
7. **Two-tap Clear** (WP3) instead of a confirm dialog or nothing. Recommendation: two-tap.
8. **Results stats** (PLAN §7: flipped states, money raised, biggest swing): need View fields the server does not send today; out of this overhaul; a later server/sim ticket.
