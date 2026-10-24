# 270 UI style v2: audit, design system, redesign spec

Branch `ui-overhaul`, from v0.8.0 (playtest 4). The designers asked for "a deep UI beautification overhaul. Make it more intuitive, less cluttered, and easier to understand and pick up", after "The UI is very crowded and overwhelming." One player is on a Mac, one on an iPad (touch). The likely audience on Roblox is kids and teens.

This file has four parts: what is wrong today (§1), the design system every screen follows (§2), the principles behind it (§3), and a per-screen redesign spec (§4), split into three work packages that can run in parallel (§5). The earlier pass, `docs/UI-OVERHAUL.md` (v0.4.0), fixed layout and touch targets; this one is about clutter, wording and hierarchy. Its tokens (D-030) stay.

Scope guard, same as before: no rule, sim, server or payload changes; screens read only the Store and send only through Net. No `Version` bump in the packages; the lead bumps it when they merge.

---

## 0. Looking at the UI without Studio

```sh
lune run tests/ui/snap.luau                      # every shot at phone 390x844, iPad 1024x768, desktop 1280x720
lune run tests/ui/snap.luau -- campaign          # shots whose name contains "campaign"
lune run tests/ui/snap.luau -- --size phone      # one size: phone | ipad | desktop
lune run tests/ui/snap.luau -- --no-png          # SVG only (not on a Mac)
```

Output goes to `build/snaps/<size>/<shot>.svg` and `.png` (gitignored). On a Mac, `qlmanage` renders and `sips` crops; nothing is installed. Open the PNGs with your image viewer (agents: `Read` them). `build/snaps/audit.txt` lists each shot's UI audit findings, style rules included.

Shots: `00-kit` (every style v2 component on one page, the visual reference for this file), `01-lobby`, `02-lobby-hosting`, `03-select-candidate`, `04-select-issues`, `05-map-reveal`, `06-draft`, `07-decision-stance`, `08-decision-focus`, `09-campaign-plan`, `10-campaign-state-card`, `11..14-lens-{ev,issues,polls,money}`, `15-campaign-choice-week`, `16/17-resolve-{start,end}`, `18-choice-resolve`, `19/20-debate{,-late}`, `21/22-election-{start,late}`, `23-results`, `24-help`. Add a shot when you add a state: one entry in `SHOTS` in `tests/ui/snap.luau` (a fixture moment plus taps, the same way the specs drive screens).

How faithful it is (`tests/lib/Snapshot.luau`): it lays the tree out again with list, grid, padding, flex fill, AutomaticSize, aspect-ratio and size constraints, scrolling frames (clipped, with a red "+N px below ▼" marker for hidden content) and ZIndex. Text widths are estimated and Gotham is drawn as Helvetica, so line breaks are close to Studio but not exact. The dim strip at the top is the Roblox top bar (58 px) with its two menu buttons. Still confirm in Studio before calling a screen done.

---

## 1. Audit: what the snaps show

### 1.1 The ten problems that matter most

1. **Campaign's actions are a scroll away.** Rally, Fundraise, Ad, Attack ad, Poll and Ground game sit 1,100 to 1,300 px below the fold at every size (`09-campaign-plan`: "+1272 px below" on a phone, "+1102 px" at 1280x720). The first screen is the map, a stat grid and a 60-word momentum note. The plan list and the event card are further down. A new player sees no way to act.
2. **No "what to do now".** The only instruction is a 13 px status line above the pinned button ("Step 1 of 2 · Next: your issues", "AP 0/3 · $4.0 left · 0 flights") or a jargon caption over the map ("Number = electoral votes · B = battleground (×1.5)").
3. **Jargon everywhere.** EV, AP, ×1.41, B, i+5, G2, opp G, FLIP, "stat + roll", "pool size", "lean", "undecided", "momentum". Numbers lack units: "$4.0", "+2.3 instead of +3.0", "called by 16.6".
4. **Walls of text.** MapReveal's "how it works" (5 paragraphs on a 5-second timer), the state card's momentum note (60 words), each debate-focus topic (35+ words), the debate swing lines (heading-size paragraphs), Results' "What decided it" (50 words of state lists). The Help overlay is a 600-word rulebook with formulas ("$2.0 + $6.0 × your support share").
5. **Header subtitles clip or wrap on phones.** MapReveal ("toward one candidate. Your strongest leans" cut mid-line), Draft, Decision ("Take a / stance"), Campaign ("Plan your / week"), Election ("4 of 51 / states called"), Help.
6. **The map is noisy.** The Northeast column and the EV badges overlap their neighbours at every size; the debate reveal covers the map with 30+ "+1.0" and "+1.0 FLIP" labels (`19-debate`); every lens adds a legend line in jargon.
7. **Decision: the options are below the fold.** On a phone the stance screen shows A, half of B, and C 491 px down, behind a 50-word "States you need (within 5 points in the public poll; a 5-point lead holds about 92%...)" paragraph. Focus topics are long two-line labels ("Farms & Rural (your platform) · 15 states, 133 EV", 10 words).
8. **Select clips and confuses.** Candidate cards cut off their drawback line (Calloway, Reyes, Strand at every size). The color swatch is a filled 44 px rounded square that looks like a button (amber, next to a yellow primary). Issue chips say "154 EV · ×1.41", numbers a new player cannot use.
9. **Reveals read like logs.** The resolve feed repeats identical lines ("You rallied in Texas on Farms & Rural" twice), with no grouping and no before/after on the map. The debate panel shows dice math ("you 1 stat + roll 1 = 2").
10. **Color and type drift.** The Amber player color is close to the accent yellow, so "280 EV" in Amber looks like a button. Green marks neutral status ("Step 1 of 2"). Warning text used the accent. Results shows five text sizes. The expander glyph "–" after a title reads as punctuation ("What decided it –").

### 1.2 Per screen

**Lobby** (`01`, `02`). Clean: hero "270", one-line tagline, Play vs Bot (primary), Find Match, Host, code + Join. Problems: no way to learn the game before playing (Help lives only in matches); the rating line is empty until the profile arrives; the code field is a mono "CODE" placeholder with no hint of length. Hosting: good (big code, Cancel as danger).

**Select step 1** (`03`). Eight cards in two columns, each with name, archetype, a green "+" perk and a red "−" drawback, 1 to 3 lines each; cards are fixed-height and clip. "Taken by your opponent" in bold red. The color line ("Your color this match: Amber (drawn at random)") with a filled swatch that reads as a button. On desktop the cards use a third of the height and the rest is empty. Status line in green.

**Select step 2** (`04`). A 33-word hint in caption size ("Top issues are drawn new each match. EV: votes in the states where it is a top issue. ×: what a rally or ad on it earns there once it is on your platform. Niche issues hit harder."). Chips: "Jobs / 154 EV · ×1.41". The primary says what is missing ("Pick 1 more issue"): good.

**MapReveal** (`05`). Header subtitle clipped. A 5-second screen with a long panel: priority, both players' strongholds as state codes, four lines of draft rules, a legend, a "Draft board +" expander. Nothing to do but read, and no time to.

**Draft** (`06`). Header subtitle clipped. Strongholds line repeated from MapReveal. "1st: WY × 2nd: —" slot row is clear. The state list (all 51, "biggest first") is 2,350 px tall; rows show "+2 them"/"+2 you"/"even" (lean) in color: readable. Status "Tap a backup (optional)". Map: home "H" badges and pick "1" badges are good; NE overlap.

**Decision: stance** (`07`). Header "Week 7 of 12 / Take a / stance" wraps. Map caption "Map: stance C · badge = support for you · red = a loss · FLIP = poll leader changes". Event card title "Event · Choice · Clinic walkout –", then the question, flavor, the 50-word "states you need" paragraph, then the A/B/C options (two of three below the fold on a phone), then a 60-word explanation of the chosen stance. Lock in is enabled with C preselected (good: no empty state).

**Decision: focus** (`08`). Intro 30 words ("Pick one topic: +2 on it. Win a topic: +1.0 in every state where it is a top issue..."), then per topic: a 10-word label, a 35-word "You need 10 of them (67 EV): trail DE by 3 · lead WA by 3, MN by 2..." line and an odds line. Primary disabled "Pick a topic" with a warning status: good.

**Campaign: plan** (`09`, `10`, `15`). Top bar: "Week 3 of 12" + "Plan your week", score line "Dana 310 189 Rex" (projected EV, unlabeled), "$4.0", "3 AP", "?", timer. On a phone it wraps to three rows. Map caption (lens legend) + four lens chips. The state card opens on your home with "You are here", four stat cells ("Public poll / you 43 – 42 them · 15 undecided", "Lean / leans you +2", "Momentum / ▲ you 3.0 · them 5.0", "Ground game / 0 / 4 · pool size $11.0"), the momentum note, top issues, then message chips with multipliers ("Technology ×1.7"), "More +", and only then the action buttons. Lock in is enabled with an empty plan. "Bank +15s" is the secondary.

**Map lenses** (`11`–`14`). The lens idea is right (one layer at a time). Problems: the legend line above the map is jargon ("Poll lead · i = your poll · ▲ momentum · G / opp G = ground game"); the Polls lens stacks 2–3 pills under each node and overlaps neighbours; "$" is a symbol, not a word.

**Resolve** (`16`, `17`, `18`). "Week 3 results" feed, newest lines last, duplicates not grouped; "Tap a state on the map / All states · sorted closest first +" panel below it; "Skip" primary; "Results · 4 of 10" status. At the end "New public polls are in" (accent text) but the map does not show what changed.

**Debate** (`19`, `20`). The map is buried under badges. The panel: per topic, score bars and a heading-size bold paragraph ("Your Schools win swung NY, NJ, WA, MN, WI +9 more (+1.0 each) - DE flipped to you (+3 EV), KY slipped from them to a tie..."), then dice math. No button (cannot skip; fine), "Opponent: watching".

**Election night** (`21`, `22`). The best screen: a clear EV race bar with "270 to win", the map filling in, a feed of calls in player-tinted rows, "Skip to results". Problems: subtitle wraps on a phone; names truncate ("Dana Okaf…"); margins have no unit ("by 16.6"); feed rows' tints are off-palette (fine as data, but must be marked).

**Results** (`23`). "You won" hero, split bar, two player cards: good. "What decided it –" opens by default with 50 words of state lists. Five text sizes. Amber "280 EV" next to the yellow primary.

**Help** (`24`). One scrolling wall: "Actions", then every number of every action with formulas, 2,650 px tall. "Close" is a yellow primary over a screen that already has one.

---

## 2. Design system (style v2)

Everything here exists in code (`src/client/UI/Kit.luau` and friends; see the header of `Kit.luau` for signatures). The `00-kit` snap shows it.

### 2.1 Color tokens (`Shared/UI/Colors.luau`, `Kit.colors`)

One dark theme: a navy stage (front-page foundation, D-056; deepened in D-064). Use the token, never a literal (`tests/ui/Tokens.spec.luau` and the audit's `tokenColor` rule enforce it).

| Token | RGB | Use |
|---|---|---|
| `background` | 11, 16, 34 | the stage behind everything |
| `field` | 16, 23, 44 | text boxes, read-only wells, icon plates |
| `surface` | 22, 30, 55 | cards and panels (elevation 1) |
| `surfaceTop` | 29, 38, 68 | top stop of a card's gradient |
| `raised` | 36, 47, 80 | buttons, chips, pills (elevation 2) |
| `raisedTop` | 44, 56, 93 | top stop of an elevation-4 panel's gradient |
| `raisedHover` | 52, 65, 106 | a selected chip or card |
| `raisedLip` | 8, 12, 26 | the lip under a secondary or icon button |
| `line` | 68, 81, 124 | hairlines (at 0.5), dividers, sheet outline, map edges |
| `text` | 240, 243, 250 | everything a player must read (14.8:1 on surface) |
| `muted` | 156, 168, 204 | secondary text only (7.0:1 on surface) |
| `accent` | 244, 246, 252 (white, D-058; was pink, D-051) | **press here / selected**: the primary's face, the selection outline, the timer, the "now" mark |
| `accentEdge` | 196, 204, 224 | the primary's 2 px edge (cool light grey) |
| `accentLip` | 110, 122, 158 | the slate lip under the primary; the wordmark's outline |
| `onAccent` | = background | text on the accent (17.5:1) |
| `good` / `goodEdge` | 80, 212, 96 / 50, 140, 66 | a gain, "you lead", success; the edge of a filled good pill |
| `loss` / `lossEdge` | **255, 122, 40** / 196, 84, 20 | anything against you: a loss, a negative number, an error, a destructive button, the timer under 10 s; the edge of a filled loss tag |
| `onLoss` | = background | text on a loss fill (7.3:1) |
| `warn`, `danger`, `bad` | = `loss` | the old names, kept so every caller still works: there is one orange |
| `glow` | 40, 60, 136 | the map's backdrop glow |
| `neutral`, `undecided` | 70, 78, 104 / 164, 174, 204 | map only: a toss-up's dark slate fill (leads blend from it to a deep color, D-064), the default node ring (also the silver medal) |
| player colors | Crimson 212, 28, 66 · Cobalt 34, 98, 228 · Emerald 0, 170, 96 · Amber 246, 190, 8 · Violet 152, 56, 228 · Teal 0, 164, 186 (D-064) | that player's things: map fill, dots, bars, rings, monograms |

**Color means one thing (D-056).** Team colors mark ownership. Green marks a gain. Orange marks a loss or a warning: anything against you. White marks "press here / selected" (D-058). A battleground is marked by a ★ and a white outline, never a white fill, so it never looks like the primary or a selection; the 270 line is a plain white tick. **Red never means bad**: red and blue are the default player colors. A player's color as *text* goes through `Kit.playerText(view, p)` (`Colors.textOn`, D-064: the color itself if it reads at 4.5:1 on a card's lit top, else the same hue brightened, then lifted toward `text` only as far as needed; Crimson text is 252, 76, 113, 5.0:1 on surface); fills, dots, bars and rings keep the base color.

**Orange never carries meaning alone** (audit rule `lossText`): an orange tag or number of one or two words carries a sign ("−", "▼", "lost", "behind") or sits under attribute `Warn` (the status line's warn and bad tones, the timer, a danger button). A battleground is good news: an outlined ★ tag, never orange.

Rules: one accent-filled thing per screen (the primary button). Selection is an accent outline, never a fill. Data colors (map fills, feed-row tints, EV bars) come from `Colors.stateFill` / `Colors.tint` / `Kit.playerColor` and their container is marked `Kit.dataColor(inst)`. Status lines are `muted` unless they report a gain or a problem.

**Depth (D-053, D-056).** Cards (`Kit.card`) fill with `surfaceTop` and carry a vertical `UIGradient` ("Depth") down to `surface`. Every card, button, sheet and the action-bar plate has an "Edge" (`Kit.bevel`): a border in its base color (a 1 px `line` hairline at 0.5, the primary's 2 px `accentEdge`) lit from the top: the stroke is `text` and its own `UIGradient` "EdgeLight" fades it into the base over the top 30 %, which draws the top highlight without an extra frame (a frame would be moved by a list layout). Buttons shade to 80 % at the bottom. Shadows (`Kit.shadow`) sit beside free-standing objects (the action-bar plate, sheets, toasts, positioned tips, the spotlight); an object inside a list or grid gets no shadow (the layout would move it), its bevel carries the depth. Elevation 4 (the election spotlight, the results banner) is `Kit.depth(panel, Kit.colors.raisedTop, Kit.colors.raised)` plus a stroke in the moment's color and a glow.

**Map bands (D-053, display only).** `Colors.band(margin)` returns the band for a poll margin in points (`Colors.BANDS`: toss-up < 3, lean < 8, likely < 15, safe), and `Colors.bandFill(support, colors)` is the stepped twin of `stateFill`: neutral, then 60 / 82 / 100 % of the leader's color (D-064, was 45 / 75: a lean reads as a deep version of the color, not a grey pastel). `stateFill` eases in the same way (`FILL_CURVE` 0.6).

### 2.2 Type (`Kit.size`, `Kit.text/caption/heading/title/eyebrow`)

Five tokens plus the Lobby's wordmark; **a screen shows at most four** (`Kit.MAX_TEXT_SIZES`, audit rule `textSizes`; a monogram's initials do not count).

| Token | px | Font | Use |
|---|---|---|---|
| `caption` | 14 | `Kit.font.body` | secondary info only: tags, hints, legends, eyebrows |
| `body` | 16 | `body` / `medium` | sentences, list rows, secondary button labels, the "now" line |
| `heading` | 20 | `bold`; `display` for the primary's label and the timer | header title, card titles, the primary's label |
| `title` | 28 | `display` (`Kit.title`) | the one big number or headline on a screen (EV totals, stamps) |
| `hero` | 48 | `display` | "You won" / "You lost", the private code. Lobby and Results only |
| `wordmark` | 72 | `display` | the Lobby's "LANDSLIDE" only (`Kit.wordmark`, scaled down to fit a phone; the audit allows it on a text with attribute `Wordmark`, and the Lobby drops `title` for it) |

**Hero numbers are display type.** Fredoka One for vote totals, the timer, stamps, the wordmark and the primary's label; Builder Sans for everything you read. `Kit.eyebrow(text)` is a caption in upper case and medium weight over a title ("JUST CALLED", "WEEK 3 RESULTS"); Roblox has no letter spacing, upper case alone gives the broadcast feel. Display text on a colored fill (a stamp, the wordmark) gets a 2-3 px `Contextual` outline in the fill's edge color; display text on the navy gets none.

**Fonts (D-053).** Always `Kit.font.*`, never an `Enum.Font` literal (`Tokens.spec`). `body`/`medium`/`bold` are Builder Sans (Gotham where it is missing), `display` is Fredoka One (falls back to Builder Sans ExtraBold, then Gotham Black), `mono` stays Code (the match code). The snapshot draws all of them as Helvetica (Fredoka as bold), so check counters and "Lock in" in Studio.

**Big screens.** `App.client` puts a `UIScale` ("BoardScale") on the board: `clamp(min(w / 1024, h / 768), 1, 1.35)`. Phones, a 1024x768 iPad and 1280x720 stay at 1 (every snapshot size). Don't `TextScaled` body text, so `GuiService.PreferredTextSize` keeps working.

### 2.3 Spacing, shape, elevation

- Spacing `Kit.space`: xs 4 (inside a row), sm 8 (between items), md 12 (panel padding), lg 16 (between groups), xl 24 (screen sections). Cards pad 14. Screen edge padding is 10 (App).
- Corners `Kit.radius`: control 8 (chips, fields, icon buttons), button 12 (primary, secondary, danger), panel 12 (cards, toasts, coach tips), sheet 16 (sheets, the help overlay), pill (height / 2). One shape family: 8 / 12 / 16 / pill; strokes 1 / 2 / 3 px; shadows drop down (the action bar's up); lips always below.
- Elevation: 0 `background`; 1 card (surface gradient, bevel); 2 control (raised gradient, bevel; buttons add a lip); 3 sheet (surface gradient, 1 px `line` lit from the top, radius 16, shadow dy 8 spread 20, `background` scrim at 0.3); 4 spotlight / banner (`raisedTop → raised`, 2 px stroke in the moment's color, glow).
- Sizes: `MIN_TOUCH` 44 (every tap target, both ways), `PRIMARY_H` 56, `BAR_H` 84, `HEADER_H` 44, `NOW_H` 32, `PILL_H` 24, `MAP_NODE_MIN` 36, `SHEET_MAX_W` 560, `LIP_PRIMARY` 4, `LIP_SECONDARY` 3.

### 2.4 Buttons: one primary per screen

| Level | Kit | Look | Use |
|---|---|---|---|
| Primary | `variant = "primary"` in the `ActionBar` | solid white (accent) face, navy Fredoka 20 label, 2 px lit grey edge, 4 px slate `accentLip` below; pinned bottom; a light band sweeps it every 4.5 s | the one thing to do next: "Lock in", "Next", "Skip", "Play again". Disabled = says what is missing |
| Secondary | `variant = "secondary"` | raised face, 44 px, lit hairline, 3 px `raisedLip` | a real alternative: "+15 s", "Back to lobby", "Find match" |
| Tertiary | `variant = "ghost"` | no fill, text color, 44 px | "More", "Why?", "Show all states", "Got it" |
| Destructive | `variant = "danger"` | `loss` label and 1 px `loss` outline, no lip (attribute `Warn`) | "Cancel", "Clear", "Leave match" |
| Toggle | `Kit.chip`, `Kit.setSelected` | raised, no lip; selected = accent outline | lens, issue, message, action type |
| Option | `Kit.cardButton` | a tappable card, selected = accent outline | candidate, stance, debate topic |
| Icon | `Kit.iconButton` | 44x44 secondary with a lip, corner 8 | `?`, `×`, `+`, `−`, ♪ |

**Chunky buttons (D-056).** A primary or secondary is a face (the `TextButton` `Kit.button` returns: Name, attributes, `Activated` as before) inside a transparent holder `Frame` "`<Name>Holder`" (= `button.Parent`, `Kit.outer(button)`) that also holds the "Lip" (attribute `Decor`). The holder takes the caller's Parent, Size, Position, AnchorPoint, LayoutOrder, Visible and ZIndex; later changes to the face's Size, Visible and LayoutOrder pass to the holder by themselves. **Move or reparent a lipped button through `Kit.outer(button)`** (`Kit.outer(header.help).Position = …`, `Kit.outer(button).Parent = grid`); a face moved out of its holder loses its lip. Pressing moves the face down onto the lip (0.07 s, scale 0.98) and back (0.12 s, Back Out). `lip = false` makes a secondary without a holder (Collapsible's title row). The lip sits outside the holder's box (below it), so leave 4 px under a primary.

Labels: a verb or a noun, at most 8 words (`labelWords`), no numbers the player has to decode. At most one secondary next to the primary.

### 2.5 Containers and small parts

- **Card** (`Kit.card`): the one container style. Surface gradient, bevel, 12 px corner, 14 px padding, vertical list, grows with its content. No cards inside cards.
- **Pill** (`Kit.pill(text, tone, props)`): a 24 px read-only tag. Tone colors the text on a raised fill. `props.filled = true` fills it in the tone with readable text and a 1 px edge (a loss tag "−0.5", a verdict "You win"); `props.fill = color` fills it with a data color (marked `dataColor`); tone `"white"` is the battleground mark (D-058): "★ Battleground", a `field` fill with a 1.5 px `text` outline (`Kit.MARK_STROKE`) and bold white text; `paintPill` adds the ★ (`Kit.STAR`) to the text and removes it for other tones. The map's vote tag does the same ("★13", `LensPart.outlined`). `Kit.paintPill(pill, tone, filled?, fill?)` re-tones a pill that changes meaning. At most 3 pills in a row unless the row wraps.
- **Stack** (`Kit.stack`): a transparent list that grows; use it instead of hand-positioning rows.
- **Expander** (`UI/Collapsible`): a card-lit panel whose 44 px title row ("Why? +" / "Why? −") shows a details body. Collapsed by default unless it holds the screen's main decision.
- **Sheet** (`UI/Sheet`): bottom sheet on a phone (with a 36 x 4 drag handle), centered panel (≤ 560 px) on wide screens that scales in from 0.96; radius 16, lit 1 px line, shadow, scrim 0.3, × to close. Never holds the primary action.
- **Coach tip** (`UI/CoachTip`): §3.4. Raised, 2 px `muted` outline (its only stroke; white would read as selected), md padding, "Got it" a lipless secondary button; a positioned tip casts a shadow.
- **Header** (`UI/Header`): title, short subtitle, sound button, `?` (both lipped icon buttons, 8 px apart), timer (Fredoka); `now = true` adds the "what to do now" line; `setTimer(left, warn, total)` adds a 4 px rounded time bar under the title, stopping short of the buttons, with a glowing white (accent) dot at its end. The timer is white (accent), `loss` under 10 s (attribute `Warn`), with a pop and a "tick" each second under 5 s; the bar turns `loss` under 5 s.
- **Action bar** (`UI/ActionBar`): a lit `surface` plate ("Plate", decor) reaching 8 px past the bar left, right and up, with a shadow cast upward: the one persistent bottom bar. Status (left), opponent (right), secondary + primary. `bar:setProgress(fraction?)` shows the time left as a veil inside the primary; a primary that becomes a disabled "Locked in…" flashes and plays `lockIn`.
- **Toast** (`UI/Toast`): raised, 2 px stroke (`loss` for a rejection, `muted` for a notice), shadow.

### 2.5.1 Front-page parts (D-056)

Every one is in the `00-kit` snap. Signatures in the header of `Kit.luau`.

- `Kit.shadow(inst, { dy 4, spread 12, transparency 0.45 })`: a 9-slice soft shadow (`Assets.shadow`) as a sibling one ZIndex under `inst`, following its size, place, Visible and fade. Nil when `inst` has no parent or its parent lays children out.
- `Kit.glow(parent, color, { scale, px, transparency 0.6, stretch })`: a radial glow (`Assets.glow`) centered in `parent` under its other children (ZIndex 0). Behind the map, a selected node, a stamp, the wordmark, the results banner, the 270 tick. Nil in a list or grid.
- `Kit.stamp(text, color, { size })`: the big moments only (CALLED, 270!, You won / You lost, the debate headline). A plate of `color` tilted −6°, Fredoka label in its readable color with an outline, 2 px edge, glow; `Overhang`. `Motion.stamp` lands it from 1.6.
- `Kit.monogram(name, color, px)`: initials on a lit circle (gradient, darker edge, sheen): 24 on Select's color line, 36 in the color sheet and the Color Pass swatches (a color, not a face).
- `Kit.portrait(id, name, px, { ring?, fade? })` (D-062): a candidate's illustrated bust on a round neutral plate, ringed in a player color when it is someone's: 56 on Select cards (40 on a phone; free candidates have no ring), 64 on Results, 44 in the election spotlight and the debate face-off, 32 in reveal heads, 24 on the strongholds card, 22 in the Campaign header (wide screens), 40 on How to play's first page. Initials on the plate until the image is uploaded.
- `Kit.raceBar(parent, { h, mark, caption })`: the race to 270: a raised track, each player's segment from their end, the tick (3 px, overhanging 4 px each way) and an optional caption. `bar:set(l, r)`, `bar:setColors(l, r)`, `bar:cross()` (tick flash + glow pulse).
- `Kit.wordmark(px?, props?, opts?)`: the game's lockup (D-064). "LANDSLIDE" in Fredoka (up to `px`, scaled down to fit a narrow column), lit from the top, 3 px slate `accentLip` outline, 6 px `line` drop, a soft white glow; under it, riding up over the name's foot, the tagline "RACE TO 270" on a ribbon tilted −3°, split Cobalt | Crimson (the two default player colors: the race), Fredoka at heading size with a navy outline and edge and a shadow. The ribbon carries attribute `Lockup`: its text size does not count toward the screen's four. `Kit.wordmarkHeight(px?, tagline?)` gives its height.
- `Kit.iconPlate(name, px?)`: an icon in a round `field` plate (state-card actions, help rows, settings chips).
- `Kit.eyebrow`, `Kit.bevel`, `Kit.paintPill`, `Kit.playerText`, `Kit.textColor`, `Kit.outer`: above.

Images (`UI/Assets.luau`, `assets/ui/`): `ui-shadow.png` and `ui-glow.png` (plus an unused `ui-dots.png`), made by `assets/ui/make.py`. While an id is "" the helpers still build their `ImageLabel` (attribute `Asset`, so the snapshots draw a stand-in) and the game shows nothing there.

### 2.6 Icons and glyphs

No emoji. Glyphs: only those in `Kit.glyph` (`·` `•` `×` `+` `−` `▲` `▼` `→` `…` `✓` `✈` `♪`); not `▾` `▴` (boxes in Studio). They are WGL4 or Latin-1 characters, the set Gotham and Builder Sans cover. Player identity is a filled circle frame (`Kit.round()`), not a glyph.

Icons (D-053): twelve Lucide icons (ISC, `docs/CREDITS.md`) in `UI/Icons.luau` (`megaphone` Rally, `coins` Fundraise, `tv` Ad, `zap` Attack ad, `search` Poll, `footprints` Ground game, `vote`, `clock`, `volume-2`, `volume-x`, `sparkles` reduce motion, `plane` flight). `Kit.icon(name, size?, color?)` draws the uploaded image tinted with `ImageColor3`, or the icon's glyph while its id is "" (all twelve are uploaded; the glyph stays for a replaced or moderated image). `Kit.actionIcon(kind)` names the icon for a plan action. An icon never carries meaning alone: an action chip keeps its word.

### 2.7 Motion and sound (`UI/Motion`, `UI/Audio`; D-053)

Short and purposeful, and never in the way. Every animation goes through `UI/Motion` and every sound through `UI/Audio` (`Tokens.spec` forbids `TweenService` and `Sound`s elsewhere). Their timings and volumes are presentation numbers and live in those modules, not `Sim/Config`.

- **Timings** (`Motion.t`, s): press 0.07, release 0.12, fast 0.12, base 0.2, enter 0.25, exit 0.15, pop 0.22, count 0.5, beat 0.35, call 0.4, hero 0.45. `Kit.motion` (fast/base/slow) stays for old callers. Easings `Motion.ease`: `out` (Quad Out, the default), `in_`, `soft` (Quart Out, arrivals), `back` (Back Out, pops only), `linear` (bars).
- **Never block.** Nothing waits on `Tween.Completed` while the player plans; every effect starts and returns at once. A new tween on a property cancels the old one. Reveals pace themselves with the server's deadlines, not tweens.
- **Reduced motion.** Roblox's Reduce Motion setting (`GuiService.ReducedMotionEnabled`) or the in-game toggle (`Motion.setReduced`, session only): decorative effects (press, pop, ring, shake, confetti) do nothing; informational ones (tween, countTo, flash, typewriter) land at once; enter/exit keep a 0.1 s fade without the slide. Sound is unaffected.
- **Front-page effects (D-056).** `Motion.press` on a lipped button moves the face down its lip (scale 0.98) instead of shrinking it to 0.96. `Motion.stamp(inst, delay?)` lands a stamp (scale 1.6 → 1, Back Out, fading in 0.15 s). `Motion.shine(button)` sweeps a light band over the primary every 4.5 s while it is enabled (`ActionBar` runs it). `Motion.breathe(inst, prop, a, b, seconds)` ping-pongs a property (the wordmark's glow, 2.4 s). `Motion.pulseOnce(inst)` nudges 1 → 1.03 → 1 over 0.9 s. All four are decorative: nothing under reduced motion or headless (a stamp is simply there); `shine` and `breathe` return a cancel.
- **Every cue has a visual.** Sound never carries meaning alone, and it is muted from the header (session only).
- **Headless.** The fake engine has a stub TweenService (goals apply on Play, Completed fires on the next step), GuiService (`world.reducedMotion`), SoundService (`world.sounds` logs every play) and ContentProvider. Specs assert end states, never timings.

### 2.7.1 How to use Motion, Audio and Icons

Require them like Kit (`local Motion = require(script.Parent.Parent.UI.Motion)` from a screen). The full API is in each module's header; the common cases:

```lua
-- Buttons: nothing to do. Every Kit.button presses (0.96 while held) and
-- plays "tap" ("select" for a chip); Kit.setSelected draws the outline in.

-- A card or row arriving: fade in and slide up 12 px.
Motion.enter(card)
-- A list: each item gets its own delay (0.04 s apart, the last at most 0.3 s).
Motion.stagger(rows, function(row, _index, delay)
	Motion.enter(row, nil, delay)
end)
-- Something leaving: fade out, then remove it.
Motion.exit(row, function()
	row:Destroy()
end)

-- A chip or badge popping in; a value changing.
Motion.pop(chip) -- from 0.9; Motion.pop(badge, 0.6) for a bigger pop
Motion.tween(bar, { Size = UDim2.fromScale(share, 1) }, Motion.t.count, Motion.ease.soft)
Motion.countTo(evLabel, 189, 206, function(n)
	return tostring(math.floor(n + 0.5))
end)
Motion.flash(statusLabel, Kit.colors.bad) -- text color there and back

-- Errors and moments.
Motion.shake(bar.root) -- a rejected plan (with Audio.play("error"))
Motion.ring(node, Kit.playerColor(view, p)) -- a decorative ring, removes itself
Motion.confetti(resultsRoot, { Kit.playerColor(view, 1), Kit.playerColor(view, 2) }, 50)
local skip = Motion.typewriter(line) -- call skip() on a tap

-- The map (WP-1, WP-2): map:pulse(id, color?), map:ring(id, color),
-- map:badge(id, Kit.actionIcon("Rally")) / map:badge(id, nil), map:wipe(id, color).

-- Sound: one call next to the visual it belongs to.
Audio.play("planAdd")
Audio.play("planAdd", { pitch = 0.94 }) -- the opponent's action in a reveal
Audio.play("call", { pitch = 0.9 + 0.3 * math.min(votes / 270, 1) })
Audio.play("lockIn", { pitch = 0.8 }) -- time's up
-- Cues: tap, select, planAdd, planRemove, lockIn, error, tick, whoosh, flip,
-- debateWin, call, victory, defeat. Muted, cooling down or over 4 voices = silent.

-- Settings (WP-3's Help and Lobby chips): both session only, both fire `changed`.
Audio.setMuted(not Audio.muted())
Motion.setReduced(not Motion.reduced())
Audio.changed:Connect(function(muted) ... end)
Motion.changed:Connect(function(reduced) ... end)

-- Icons: an image once uploaded, else the glyph. Never alone: keep the word.
local icon = Kit.icon(Kit.actionIcon("Rally") or "megaphone", 16, Kit.colors.accent)
icon.Parent = chip

-- Header and action bar.
bar:setProgress(secondsLeft / total) -- the time left inside the primary
header:setTimer(left, Kit.TIMER_WARN, total) -- warn under 10 s, danger + tick under 5

-- Specs: Rig.fixture(moment, size, { reducedMotion = true }); Rig.sounds(peer)
-- lists the cues a client played; FakeRoblox.setReducedMotion(world, on).
```

Decorative frames Motion creates (`Ring`, `Confetti`) carry `Decor = true`, which the UI audit skips; the audit also divides a `MotionScale` UIScale out of the sizes it checks, so a held button never reads as 42 px.

### 2.8 Copy rules

- Plain words a 12-year-old knows. Game nouns stay (battleground, momentum, ground game, stance), but each is explained once in a `?` sheet and in a coach tip, not in every label.
- Prefer "votes" to "EV" in sentences ("Ohio · 17 votes"); keep the bare number on the map. "AP" becomes "actions" ("2 of 3 actions left").
- Numbers carry units or a sign: "+3 support", "$4.0", "15 s", "by 16.6 points". Money and points always go through `Shared/UI/Numbers` (money never rounds up: a player with $4.96 sees "$4.9", because a $5 plan is rejected).
- Labels ≤ 8 words. A sentence on screen ≤ 30 words (`wallOfText`); anything longer goes in a sheet or an expander (details areas are exempt).
- Say what to do, then why: "Pick 1 more issue", not "You have 2 of 3 issues".
- One name for one thing: "Lock in" (never "Submit", "Confirm", "Done" for the same act), "Skip", "+15 s".
- The opponent is "{their name}" or "your opponent", never "them" in a full sentence ("Rex leads by 2", not "them +2").
- Fictional only: no real politicians, parties or slogans; free text goes through `TextService:FilterStringAsync`.

### 2.9 How the rules are enforced

`UI/Audit.luau` runs in Studio (Router, 0.5 s after a mount) and in the specs. Layout rules (D-030) are unchanged. Style v2 adds four rules and the front-page foundation a fifth, checked by `Audit.run` and by `Audit.check(root, { style = true })`:

| Rule | Fires when |
|---|---|
| `tokenColor` | a visible fill, text or stroke color is not a token or a player color (map and `Kit.dataColor` subtrees skipped) |
| `textSizes` | a screen shows more than 4 distinct text sizes |
| `labelWords` | a button label has more than 8 words |
| `wallOfText` | a text has more than 30 words outside a details area (`Kit.details`, Sheet and Collapsible bodies) |
| `lossText` | an orange (`loss`) text of one or two words has no sign ("−", "-", "▼", "lost", "lose", "behind") and no `Warn` attribute on it or above it (D-056: orange never carries meaning alone) |

Not-yet-migrated screens are listed in `Audit.PENDING` (notes in the Output, not warnings; still notes under `strict`). `tests/ui/Style.spec.luau` fails if a screen breaks an unlisted style rule, or if a listed one no longer fires: **when you fix a screen, delete its line**. Today's list:

```
Select   = { wallOfText }             -- WP-A
Draft    = { tokenColor, wallOfText } -- WP-A
Decision = { labelWords, wallOfText } -- WP-B
Campaign = { wallOfText }             -- WP-B (state card) and WP-C (debate lines): the last one out deletes it
Election = { tokenColor }             -- WP-C
Results  = { textSizes }              -- WP-C
```

---

## 3. Principles

### 3.1 One primary action per screen

Every moment has exactly one accent button, pinned in the action bar, and its label is the next step. When the player cannot press it yet, it is disabled and says what is missing. Everything else is secondary, ghost, a chip or a card.

### 3.2 Progressive disclosure

Show the decision and the one number that drives it; put the rest one tap away. Three levels: (1) on screen: a short label, a pill, a number with a unit; (2) a ghost "Why?" or an expander under it for a sentence or two; (3) a sheet for the full breakdown and the rules. Long explanations from `Shared/UI/Explain` move to level 2 or 3.

### 3.3 A persistent "what to do now" line

Every input screen shows one line under the header (`Header.new(..., { now = true })`, `header:setNow(text)`), ≤ 8 words, imperative, updated as the player acts:

| Moment | Now line |
|---|---|
| Select 1 | Pick your candidate |
| Select 2 | Pick 3 issues (2 left) → Lock in when ready |
| MapReveal | Your color shows states that lean to you |
| Draft | Pick a state to claim → Pick a backup, or Lock in |
| Stance | Pick a side: A, B or C |
| Focus | Pick one debate topic |
| Plan | Tap a state → Pick an action → 1 action left → All set? Lock in |
| After Lock in | Waiting for {opponent}… |
| Resolve | Here's what happened this week |
| Debate | Debate! Watch each topic |
| Election | States are being called |

### 3.4 Coach tips for the first match

`UI/CoachTip.show(parent, { id, order | position })`: an accent-outlined card with one sentence and "Got it". It shows once per player (per session today: the module remembers; `CoachTip.useStore` can back it with the saved profile later, which needs a server change and is out of scope). Tips never block input, never cover the map nodes or the action bar, and at most one is visible at a time. The copy lives in `CoachTip.TIPS` (WP-C owns it); screens call it by id:

| Id | Screen, where | Text |
|---|---|---|
| `select.candidate` | Select 1, above the cards | Each candidate has one strength and one weakness. Pick one. |
| `select.issues` | Select 2, above the chips | Pick 3 issues. Rallies and ads on them count for more. |
| `draft.pick` | Draft, above the list | Tap a state to claim it. Bigger numbers mean more votes. |
| `decision.stance` | Stance, above the options | Pick a side. States that care about this issue react. |
| `decision.focus` | Focus, above the topics | Pick one debate topic to prepare. You get a bonus on it. |
| `campaign.map` | Plan, first week, over the side column | Tap a state to see how it's leaning and act there. |
| `campaign.actions` | Plan, after the first state tap, above the actions | Spend your actions and money, then press Lock in. |
| `campaign.lens` | Plan, week 2, next to the lens chips | These buttons change what the map shows. |
| `reveal.week` | first Resolve, top of the reveal panel | Here's what both of you did this week. |
| `election.night` | Election, under the race bar | States are called one by one. 270 votes wins. |

### 3.5 The map is the hero on Campaign

On Campaign, Decision, Draft and Election the map is the biggest thing on screen and the place you tap first. Panels go beside it (wide) or under it (phone) and never cover nodes. The map shows one layer at a time (lenses), labels never overlap, and reveal marks are limited to what matters (flips and the biggest moves, not every +1.0).

### 3.6 Same parts everywhere

Same header, same action bar, same card, same chip, same sheet on every screen. A player who learns Select's chips already knows Campaign's. Before writing a new widget, check `Kit`.

---

## 4. Per-screen redesign spec

Wireframes: phone portrait 390 wide (left) and wide 1280x720 / iPad landscape (right). `[PRIMARY]` is the accent button in the action bar. `( )` are chips, `[ ]` secondary buttons, `<x>` pills.

### 4.1 Lobby (WP-A)

```
phone                                   wide (centered column, max 480)
┌──────────────────────────────┐        ┌──────────────────────────────────────────┐
│                              │        │                   270                    │
│             270              │        │   Win the race to 270 electoral votes.   │
│  Win the race to 270 votes.  │        │   Rating 1012 · 3 won, 2 lost            │
│  Rating 1012 · 3 won 2 lost  │        │   [ PLAY VS BOT                        ] │
│ [ PLAY VS BOT              ] │        │   [ Find match ]  [ Play a friend ]      │
│ [ Find match ]               │        │   ( How to play )                        │
│ [ Play a friend ]            │        └──────────────────────────────────────────┘
│ ( How to play )   ghost      │
└──────────────────────────────┘
```
Keep: hero, Play vs Bot as the primary, Find match. Change: "Host Private Match" and the code row become one "Play a friend" secondary that opens a small sheet with two choices ("Make a code" / "Enter a code" + the 5-letter field). Add a ghost "How to play" that opens the Help sheet (`ctx.help`). Tagline ≤ 8 words. Hosting state as today (hero code, "Tell your friend this code", danger Cancel), plus "Waiting for your friend…" as the now line.

Color (D-055, `UI/ColorPick`): once the Color Pass is set up, a full-width secondary "Color: Teal" / "Color: red or blue" under the settings chips opens the "Your color" sheet (six swatches in rows of three, "Auto: red or blue"; greyed with one line and "Get the Color Pass" without the pass). Hidden while `Net/Products.COLOR_PASS_ID` is 0.

### 4.2 Select (WP-A)

```
phone                                   wide
┌──────────────────────────────┐        ┌──────────────────────────────────────────────────┐
│ Choose your candidate   ? 0:36│       │ Choose your candidate                     ?  0:36 │
│▌Pick your candidate          │        │▌Pick your candidate                                │
│ ┌────────────┐┌────────────┐ │        │ ┌──────────┐┌──────────┐┌──────────┐┌──────────┐ │
│ │Dana Okafor ││Rex Calloway│ │        │ │ Dana     ││ Rex      ││ Priya    ││ Marcus   │ │
│ │Fundraiser  ││<Taken>     │ │        │ │ Fundrais.││ <Taken>  ││ Ad Wizard││ Debater  │ │
│ │+ Bigger    ││            │ │        │ │ + …      ││          ││ + …      ││ + …      │ │
│ │  fundraisers││           │ │        │ │ − …      ││          ││ − …      ││ − …      │ │
│ │− (none)    ││            │ │        │ └──────────┘└──────────┘└──────────┘└──────────┘ │
│ └────────────┘└────────────┘ │        │   (second row of four)                             │
│   … 8 cards, 2 columns …     │        │ ● Your color: Amber                                │
│ ● Your color: Amber          │        │ ┌──────────────────────────────────────────────┐   │
│ Step 1 of 2   Rex: picking   │        │ │            NEXT: ISSUES                       │   │
│ [ NEXT: ISSUES             ] │        └──────────────────────────────────────────────────┘
└──────────────────────────────┘
```
Step 1: cards are `Kit.cardButton`s that grow with their text (no clipping); each shows name (body bold), archetype (caption), one short perk line and one short drawback line, ≤ 8 words each, written fresh in `src/shared/UI/Words/Setup.luau` (the full numbers stay in a "?" sheet per candidate, opened by a ghost "Details" on the selected card). The taken card shows a `<Taken>` pill and is dimmed. The color swatch becomes a 16 px dot plus text (not a 44 px filled square). Status line muted.
Step 2: the 33-word hint goes into a "How issues work" ghost → sheet. Chips show the issue name and one plain number: "Jobs · 154 votes" (the multiplier moves to the sheet and to the state card). Coach tips `select.candidate`, `select.issues`.

### 4.3 MapReveal and Draft (WP-A)

```
phone                                   wide
┌──────────────────────────────┐        ┌──────────────────────────────────────────────────────┐
│ Round 2 of 3            0:18 │        │ Round 2 of 3 · Battleground                 ?   0:18 │
│▌Pick a state to claim         │       │▌Pick a state to claim                                 │
│ (EV)(Issues)(Polls)(Money)   │        │ (EV)(Issues)(Polls)(Money)       ┌───────────────────┐│
│ ┌──────────────────────────┐ │        │ ┌───────────────────────────┐    │ Your pick         ││
│ │          MAP             │ │        │ │                           │    │ 1st: WY  ×        ││
│ │                          │ │        │ │           MAP             │    │ 2nd: —            ││
│ └──────────────────────────┘ │        │ │                           │    │ ───────────────── ││
│ 1st: WY ×   2nd: —           │        │ └───────────────────────────┘    │ FL  30  <+2 Rex>  ││
│ FL Florida   30   <+2 Rex>   │        │ ● You: home CA · 5 strongholds   │ NY  28  <+2 you>  ││
│ NY New York  28   <+2 you>   │        │ ● Rex: home TX · 5 strongholds   │ IL  19  <+2 Rex>  ││
│ ( Show all states )          │        │                                  │ ( Show all )      ││
│ Rex has priority  Rex: picked│        │                                  └───────────────────┘│
│ [ LOCK IN                  ] │        │ Rex has priority       Rex: picked   [ LOCK IN       ]│
└──────────────────────────────┘        └──────────────────────────────────────────────────────┘
```
MapReveal: no rules panel. The map fills the screen with the strongholds ringed; one card under/beside it: "You: home CA · strongholds VA CO AL VT MS" and the same for the opponent, a legend of two dots ("leans to you", "leans to Rex"), and a ghost "How the draft works" → sheet with today's four lines. Header subtitle ≤ 4 words or none.
Draft: the list shows the 8 best picks by default (sorted as today) with "Show all states" (ghost) to expand; rows are 44 px with code, name (wide only), votes and a lean pill. The battleground rule ("every effect ×1.5") is a `<Battleground>` pill plus one line in the "?" sheet, not the header. Legend swatches are `Kit.dataColor`. Coach tip `draft.pick`.

### 4.4 Decision: stance and focus (WP-B)

```
phone                                   wide
┌──────────────────────────────┐        ┌──────────────────────────────────────────────────────┐
│ Week 7 · Clinic walkout  0:18│        │ Week 7 · Clinic walkout                     ?   0:18 │
│▌Pick a side: A, B or C       │        │▌Pick a side: A, B or C                                │
│ ┌──────────────────────────┐ │        │ ┌──────────────────────────┐  ┌──────────────────────┐│
│ │ MAP (preview of choice)  │ │        │ │                          │  │ Health: staff vs     ││
│ └──────────────────────────┘ │        │ │   MAP (preview)          │  │ board. Who do you    ││
│ Health: staff vs board.      │        │ │                          │  │ back?                ││
│ ┌ A · Side with the staff ─┐ │        │ │                          │  │ ┌A · Side w/ staff ┐ ││
│ │ +2 states · −1 state     │ │        │ └──────────────────────────┘  │ │ +2 states −1     │ ││
│ └──────────────────────────┘ │        │                               │ └──────────────────┘ ││
│ ┌ B · Side with the board ─┐ │        │                               │ ┌B …┐ ┌C · Stay out┐ ││
│ └──────────────────────────┘ │        │                               │ ( Why? )             ││
│ ┌ C · Stay out (safe)  ────┐ │        │                               └──────────────────────┘│
│ ( Why? )                     │        │ Secret until the week ends   Rex: picking [ LOCK IN ]│
│ Secret until week ends       │        └──────────────────────────────────────────────────────┘
│ [ LOCK IN                  ] │
└──────────────────────────────┘
```
Stance: the event name goes in the header title; the question in one sentence; three `Kit.cardButton` options, each with a one-line effect summary ("+2 states · −1 state"); everything else ("states you need", the per-state list, the hedge rule) goes behind "Why?" (an expander or a sheet). The options must be on the first screen on a phone (no scrolling to C). Map caption: a two-dot legend, no sentence.
Focus: same layout with one card per topic: "Schools · 14 states" + one pill with your odds ("You win 81%"); the "you need" detail moves to "Why?". Coach tips `decision.stance`, `decision.focus`.

### 4.5 Campaign: plan (WP-B)

```
phone                                   wide
┌──────────────────────────────┐        ┌──────────────────────────────────────────────────────────────┐
│ Week 3 · $4 · 3 actions 0:48 │        │ Week 3 of 12   Dana 310 ━━━━━━━━|━━━━ 189 Rex   $4 · 3 actions  ? 0:48│
│ Dana 310 ━━━━━|━━━━ 189 Rex  │        │▌Tap a state, then pick an action                                │
│▌Tap a state on the map       │        │ (Votes)(Issues)(Polls)(Money)          ┌─────────────────────────┐│
│ (Votes)(Issues)(Polls)(Money)│        │ ┌──────────────────────────────────┐   │ Ohio · 17 votes   ( ? ) ││
│ ┌──────────────────────────┐ │        │ │                                  │   │ <Toss-up> <You +1>      ││
│ │                          │ │        │ │                                  │   │ (Rally)(Fundraise)(Ad)  ││
│ │          MAP (hero)      │ │        │ │             MAP (hero)           │   │ (Attack)(Poll)(Ground)  ││
│ │                          │ │        │ │                                  │   │ Message: (Jobs)(Health) ││
│ └──────────────────────────┘ │        │ │                                  │   │ ───────────────────────  ││
│ ┌ Ohio · 17 votes   ( ? ) ─┐ │        │ └──────────────────────────────────┘   │ Your plan (2 of 3)      ││
│ │ <Toss-up> <You +1>       │ │        │                                        │ 1 Rally OH · Jobs   ×   ││
│ │ (Rally)(Fund)(Ad)(More…) │ │        │                                        │ 2 Ad PA · Health    ×   ││
│ └──────────────────────────┘ │        │                                        └─────────────────────────┘│
│ Plan: Rally OH · Ad PA  (2/3)│        │ 2 of 3 actions · $1 left        Rex: thinking   [+15 s][ LOCK IN ]│
│ 2 of 3 actions  Rex: thinking│        └──────────────────────────────────────────────────────────────┘
│ [+15 s] [ LOCK IN          ] │
└──────────────────────────────┘
```
- **Top bar** (one row wide, two rows on a phone): week, the race bar (projected votes in player colors with a 270 tick; names, not "them"), money and actions as words ("$4 · 3 actions"), `?`, timer with the time bar. The now line under it. The event of the week, if any, is a pill in the top bar that opens a sheet ("Event: Donor retreat").
- **Map** is the hero: at least 55% of the height on a phone, 62% of the width wide. Lens chips read "Votes / Issues / Polls / Money"; the legend is a single ghost "Key" that opens a small sheet, not a caption line. No state card until the player taps a state (or week 1's coach tip points at the map); the home state no longer opens by default.
- **State card** (a card under the map on a phone, the side column wide): name and votes, at most 3 pills (who leads and by how much, Battleground, Your issue), then the **actions as chips right away**, the message chips, and nothing else. The stat grid, momentum note, ground game and pool size move to the card's "?" sheet ("Ohio in detail"). Target: the first action chip within the first 844 px on a phone with no scrolling.
- **Plan list**: one compact line on a phone ("Plan: Rally OH · Ad PA (2/3)", tap to open a sheet with remove buttons); a list wide. Remove = `×` icon button.
- **Action bar**: status "2 of 3 actions · $1 left" (muted), opponent on the right, secondary "+15 s" (was "Bank +15s"), primary "Lock in". An empty plan still locks in with one tap, as today, until the designers answer §5 question 1.
- Coach tips `campaign.map`, `campaign.actions`, `campaign.lens`.

### 4.6 Campaign: map visuals and lenses (WP-B)

- Nodes never overlap their neighbours' labels: re-place the Northeast column (`Shared/UI/MapLayout.luau`) and put the EV number inside the node (two lines: code over number) instead of a badge at its corner.
- One extra mark per node at most in any lens: Votes → number; Issues → two 3-letter codes, yours filled; Polls → one lead pill ("+3" in the leader's color; your poll and ground game go in the state sheet); Money → "$2.5".
- The real map (D-062) replaces the circles once its images are uploaded: true state shapes tinted like the circles, navy borders, Northeast callout chips at the right edge, codes on each state's anchor, the lens value under the code where the state has 24 px of room. Selection, owner rings and moved states are outlines (white for the selection). Polls is the one lens with more than one mark: the lead, ▲ momentum in the leader's color, ground-game dots (yours filled, theirs hollow, only as your polls saw them) and a legend row under the map. Candidate pins (face, "You" or the rival's name) show in every lens. While you draft, the plan preview (D-063) puts a faint signed tag under each state the plan moves (green gain, orange loss with its minus) on top of every lens, and "Plan: 268 → 281 votes" under the map.
- Reveal marks (resolve, debate, stances): only flips ("FLIP" ring in the new leader's color) and the 5 biggest moves get a badge; the rest get a soft glow. Never more than ~8 labels on the map at once.
- Selection: the tapped state gets a 3 px accent ring and its card opens; tapping it again closes the card.
- Front-page map (D-056): a navy stage glow behind the board; each node a lit token (a lip in its ring's color toward the background, a contact shadow, the circle 22 % see-through at the bottom over the lip); lens values on a `field` plate in Fredoka 14 with a hairline, a battleground "★13" outlined in `text` (no white fill: that means selected; the ★ drops on a circle under 40 px, the outline stays), Polls leads filled in the leader's color; map marks: badges filled in their color (a loss `loss` with `onLoss` text), FLIP a `field` tag with a 2 px edge in the new leader's color, a moved state an aura disc plus a soft bloom under every node; the selection (and any accent ring a screen sets) blooms in the accent, the selection's breathing. Glows and shadows live in the `Shadows` layer under the nodes, so they never tint a neighbour. On a map narrower than `MapLayout.PHONE_WIDTH` the drawn circle keeps its layout size inside its grown 36 px target.

### 4.7 Reveal: resolve and debate (WP-C, inside Campaign)

```
phone                                   wide (panel in the side column)
┌──────────────────────────────┐        ┌───────────────────────────┐
│ Week 3 results          0:06 │        │ Week 3 results            │
│▌Here's what happened         │        │ You   Rally TX ×2 · Ad NY │
│ ┌──────── MAP ─────────────┐ │        │ Rex   Rally NY · Rally TX │
│ │ (changed states glow)    │ │        │       Ad IL · Rally OH    │
│ └──────────────────────────┘ │        │ ───────────────────────── │
│ You  Rally TX ×2 · Ad NY     │        │ Biggest moves             │
│ Rex  Rally NY, TX · Ad IL    │        │ <TX you +3> <OH Rex +2>   │
│ Biggest moves                │        │ <NY tie>                  │
│ <TX you +3> <OH Rex +2>      │        │ ( Full results )          │
│ ( Full results )             │        └───────────────────────────┘
│ [ SKIP                     ] │
└──────────────────────────────┘
```
Resolve: group the feed by player and action ("Rally TX ×2"), one line each; then "Biggest moves" as up to 5 pills; then a ghost "Full results" (sheet with today's feed and the sortable state list). "New polls are in" becomes the now line; the map glows the states whose leader changed.
Debate: per topic one row: topic name, two score bars, a verdict pill ("You win", "Tie", "Rex wins") and one short line ("+1 in 12 states · DE flips to you"). The dice math and full state lists go behind "Why?". Map marks follow §4.6 (flips and top moves only).
Coach tip `reveal.week` on the first resolve.

### 4.8 Election night (WP-C)

Keep the layout (race bar, map, call feed, "Skip to results"). Changes: header subtitle off on a phone (the race bar already says "27 of 51 called" under it); names never truncate (first name only when narrow: "Dana 104 · 171 Rex"); feed rows "Ohio · 17 votes · Dana by 2.9 points"; rows and race bar marked `Kit.dataColor`; coach tip `election.night` once.

### 4.9 Results (WP-C)

```
┌──────────────────────────────┐
│           You won            │  hero, good color
│    280 votes to 258          │  body
│ ━━━━━━━━━━━━━━━━|━━━━━━━━━━━ │  data bar
│ ┌ ● Dana Okafor ─┐┌ ● Rex ─┐ │  cards: dot + name (heading), "20 states" (body)
│ └────────────────┘└────────┘ │
│ Key moments                  │
│ • Debate in week 9: +6 votes │  3 short bullets, ≤ 8 words each
│ • Won Ohio by 0.4 points     │
│ ( Full breakdown )   ghost   │  sheet: today's "What decided it", closest states
│ [Back to lobby] [ PLAY AGAIN]│
└──────────────────────────────┘
```
Four sizes: hero, heading, body, caption (drop the 28 px EV numbers to heading, or keep title and drop heading). Player color on the dot and the bar, not on big numbers next to the primary. "What decided it" collapses into 3 bullets + a sheet.

### 4.10 Help (WP-C)

Replace the rulebook with a "How to play" sheet (`UI/Sheet`) of five short cards, each ≤ 30 words with one example: **Goal** (270 votes), **Each week** (actions, money, Lock in), **Actions** (one line each: Rally, Fundraise, Ad, Attack ad, Poll, Ground game), **Debates and stances**, **Election night**. Then one expander per topic ("All the numbers: actions", "…: debates", …) holding today's exact text from `Shared/UI/Explain` (a details area, so the long text is allowed there). Close is the sheet's `×` and a secondary "Close", never a primary. Opened from the `?` in every header and from the Lobby's "How to play". `Help.mount(parent, ctx)` and `ctx.help` keep their signatures (App.client.luau is frozen).

---

## 5. Work packages

Three agents, in parallel, each on its own branch from `ui-overhaul` after this foundation commit. Each package owns the files listed; it may read anything, and edits only its own files plus its own lines in `Audit.PENDING`. Each ships with its tests green, the strict UI audit at 0 (`lune run tests`), `Style.spec` green with its PENDING lines deleted, fresh snaps checked by eye at all three sizes, a `CHANGELOG.md` bullet under "Unreleased" and a `docs/TESTING.md` checklist (append a section; don't edit others').

**Frozen for all three** (ask the lead; add helpers in your own files instead): `UI/Kit.luau`, `UI/Audit.luau` (except deleting your PENDING lines), `UI/Header.luau`, `UI/ActionBar.luau`, `UI/Sheet.luau`, `UI/Collapsible.luau`, `Shared/UI/Colors.luau`, `Router.luau`, `App.client.luau`, `Store.luau`, `Net.luau`, `Screens/Types.luau`, `Screens/Common/{AutoLock,Data,Messages}.luau`, the pure helpers in `Shared/UI` (`Explain`, `Swing`, `Numbers`, `PlanDraft`, `StateOrder`, `Drafted`, `Fixtures`: add new functions in a new file, never change an existing function's output, since specs depend on it), and the shared specs (`Audit`, `Kit`, `KitStyle`, `Style`, `Tokens`, `Helpers`). `tests/ui/Stances.spec.luau` and `tests/ui/Explained.spec.luau` cover screens from all three packages: change only the cases about your own screens, append new ones, leave the rest. New short copy goes in a new pure module the package owns under `src/shared/UI/Words/` (one per package, listed below), with a spec.

### WP-A: Lobby, Select, MapReveal and Draft

Owns: `src/client/Screens/Lobby.luau`, `Select.luau`, `Draft.luau`, `Screens/DraftParts/{Board,Logic,StateList}.luau`, `Screens/Common/Layout.luau` (keep `Layout.page`/`Layout.lane` signatures: Results and StateCard use them), new `src/shared/UI/Words/Setup.luau`; specs `tests/ui/{Lobby,Select,Draft,Drafted}.spec.luau`; PENDING lines `Select`, `Draft`. Spec: §4.1–4.3. Coach tip calls: `select.candidate`, `select.issues`, `draft.pick`.

### WP-B: Decision, Campaign and the map

Owns: `src/client/Screens/Decision.luau`, `Campaign.luau`, `Screens/CampaignParts/{Model,TopBar,StateCard,PlanList,EventCard,Focus,SwingMarks}.luau`, `src/client/Map/{NodeMap,Lens,LensToggle,MapInterface}.luau`, `src/shared/UI/MapLayout.luau`, new `src/shared/UI/Words/Campaign.luau`; specs `tests/ui/{Campaign,CampaignParts,Decision,Lens,NodeMap,Momentum}.spec.luau`; PENDING line `Decision` and the state-card half of `Campaign`. Spec: §4.4–4.6. Keep calling `Reveal.new(side, model, order, opts)` and the Reveal panel's methods as today (WP-C owns its inside). Coach tip calls: `decision.stance`, `decision.focus`, `campaign.map`, `campaign.actions`, `campaign.lens`.

### WP-C: Reveal, Debate, Election, Results, Help and coach tips

Owns: `src/client/Screens/CampaignParts/Reveal.luau`, `Screens/Election.luau`, `Screens/Results.luau`, `src/client/UI/Help.luau`, `src/client/UI/CoachTip.luau` (the copy in `TIPS` and any additive API change), `src/client/UI/Toast.luau`, new `src/shared/UI/Words/Reveal.luau`; specs `tests/ui/{Election,Results}.spec.luau` plus a new `tests/ui/Help.spec.luau`; PENDING lines `Election`, `Results` and the debate half of `Campaign`. Spec: §4.7–4.10, §3.4. Keep `Reveal.new`'s signature and `Help.mount`'s. Coach tip calls: `reveal.week`, `election.night`.

### Merge order

Any order; the packages do not share files. If two packages both need the same new Kit helper, each writes it locally and the lead promotes one copy into Kit after the merge. After all three: the lead runs the snaps at all sizes, empties `Audit.PENDING`, and logs the result in `docs/DESIGN.md`.

### Questions for the designers (do not block the packages)

1. Lock in with an empty plan: keep it one tap (today) or require a confirm?
2. "Votes" instead of "EV" in sentences, keeping "EV" on the map numbers: OK?
3. Amber vs the accent: keep Amber as a player color (and avoid big Amber text, as specced), or swap the accent to a white/cyan primary? *Decided: keep Amber; the accent is pink (D-051), since cyan sits next to Teal.*
4. Coach tips across sessions need the saved profile (a server change): worth it after playtest 5?
