# Changelog

Newest first. Each entry lists what changed, what to test (see `docs/TESTING.md`), and anything needed from the humans.

## Unreleased

### Map polish (D-079)

- **A bigger, readable map on phones (D-079):** in portrait the map stands up (390x312 on a 390 px phone, was 390x244), its land fills the width and the nine small Northeast states sit in one row of chips under it. Every state shows its number on one line ("PA 19"), or its code stacked over its number where it is tiny, nudged so no two overlap (a number that has to move gets a thin line to its state); the chips show code over value. The plan's badge and preview number sit on their state's line. iPad and desktop keep their layout.
- **Polls in one pill:** the lead, ▲ momentum and the ground-game dots sit together ("+8 ▲ ●●"); nothing floats on its own.
- **Fewer, better labels:** a reveal, a debate and a stance preview never show more than 8 tags; a flip is an outline in the new leader's color plus ▲ (your way) or ▼ (away from you) on the 5 biggest. Fills fade to each step's polls as the week plays. A stance preview outlines what it helps in green and what it hurts in orange, matching its key.
- **Calmer marks:** candidate pins are faces (yours a little bigger); the name shows in week 1 and when you tap the state. One thin bracket replaces the nine Northeast leader lines; a chip's line shows when you tap it. Alaska and Hawaii sit in small boxes, Hawaii bigger. Money marks the 8 richest states with 1 to 3 coins (more coins, more money; the dollars are on the card). Hawaii's box is filled in its color. The Polls legend explains ▲▲ (strong momentum). Issues show their symbols on a round disc. Results marks a missed poll with a dashed outline and "×" instead of a MISS tag. Election night draws uncalled states hollow, shakes each call, and outlines the state that will decide it in white.
- **Close filter:** a "Close" chip beside the lenses fades every state more than 8 points from close, so only the races still in play show their numbers. Remembered for the session; off by default.
- Studio checklist: `docs/TESTING.md`, "Map polish". Nothing needed from the humans.

## Unreleased: the tutorial, slower bot matches, corner settings (D-075)

Studio checklist: `docs/TESTING.md`, "The tutorial, bot timers and corner settings". Nothing needed from the humans.

- **Your first bot match is a tutorial with no timers (D-075).** Every choice (pick your candidate, the draft, stances, debate rounds, every week's plan) waits until you lock in; the clock's place reads "No timer" and there is no "+15 s". Reveals and election night still play by themselves (Skip still works). Coach tips show as before. It counts as done when that match ends (a win, a loss or Leave match) and is saved with your profile; players who have played before never get it unasked.
- **Replay it any time** from **How to play**: "Play the tutorial" under the pages starts it again against the Easy bot, with every coach tip back.
- **More time against easier bots (D-075).** Every choice timer is ×2 against the Easy bot and ×1.5 against Medium (a 100 s / 75 s plan instead of 50 s); Hard and Extreme, and matches against people, are unchanged. New `Config.BOT_TIME_MULT_EASY` (2) and `BOT_TIME_MULT_MEDIUM` (1.5).
- **Sound and Reduce motion are in the Lobby's top-right corner** as two small icon toggles (outlined while on, with a short label on hover and after a tap). The in-match settings are where they were.
## Unreleased

### Issue symbols (D-076)

Client only: no rule, sim, server, payload or Config changes. Studio checklist: `docs/TESTING.md`, "Issue symbols".

**Needed from the humans:** upload the eight PNGs in `assets/issues/` (`jobs.png`, `health.png`, `schools.png`, `environment.png`, `safety.png`, `transit.png`, `technology.png`, `farms.png`) and send their ids (until then the game shows the old codes and names).

- **Issues have symbols:** a briefcase for Jobs, a heart with a pulse for Health, a graduation cap for Schools, a leaf for Environment, a shield for Safety, a bus for Roads & Transit, a microchip for Technology, wheat for Farms & Rural.
- **Map, Issues tab:** each state shows its top issue's symbol instead of a code (filled in your color when it is one of yours). The row under the map names the symbols on it, the Map key lists all eight, and tapping a state shows its top issues with symbols and names.
- The symbols also sit beside the names on the issue cards when you pick your platform, the message chips, the event strip for an issue event, the debate's rounds, and the How to play pages, which get a new page, "Your issues".
## Unreleased

### Fixes

- **Reporting a name from Results hides it at once:** after **Report** on the opponent's card, the banner, both cards, the Map and Graph tabs switch to the candidate's own name and the Report button goes away. (The match is over, so the server sends no new screen; the client now hides the name itself when the server confirms the report.)
- **The LANDSLIDE shine stays on the stamp:** the light that sweeps the winner's tilted LANDSLIDE stamp no longer shows outside it. Roblox does not clip inside a rotated frame or to rounded corners, so the light is now a gradient on a layer the stamp's own shape. The primary button's shine moves the same way.
- **Long custom names fit the debate on a phone:** the clash and verdict stamps never run past the column; with a name over 10 letters they say "THEY WIN BY 3" / "THEY WON THE CROWD", and the crowd meter "Them +2". The names over the faces shrink to fit instead of cutting off.
- **A held debate move no longer sticks:** the map preview of a held move ends when the finger slides off and lifts, when a touch is cancelled, or when the mouse leaves the button.
- **Results cleans up after itself:** the LANDSLIDE shine, the glow's breathing and the Map tab's map stop when the screen closes (no animations left running in the lobby).
- **No error on a payload without your seat** after Lock in on the debate, plan and decision screens.
- **Server and saved-data fixes** (Studio checklist: `docs/TESTING.md`, "Server and saved-data fixes (unreleased)"):
  - **A loss follows a player to another server.** Leaving a rated match and joining another server used to skip the loss: the result was dropped or overwritten. A result for a player whose data another server holds now waits in their saved record, and that server adds it (once) on its next save, within about a minute; the leaderboard follows.
  - **Saved data:** a server refreshes each player's lock every minute, merges instead of overwriting, writes changes in a batch every 15 s and skips profiles that did not change. A match result is still saved at once.
  - **Win trading (D-077):** a forfeit or a drop before week 1 makes the match unrated for both players, and one pair of players gets at most 3 rated games a day; the next is unrated. Both are announced.
  - **Spam:** SetColor (1 s) and SetName (2 s) have cooldowns, and re-saving the name already in use skips the text filter.
  - **Name review (D-078):** a removed name blocks itself as whole words only ("Ann" no longer blocks "Hannah"); only the exact removed name is cleared from saved data. Keep and Remove act only on the name the admin saw. A failed blocklist save changes nothing, and a reload never brings a removed name back. Until the blocklist has loaded, no new name is accepted.
  - **Reports:** the daily report limit is saved (rejoining no longer resets it), and the review queue is split over eight keys.
  - **Debates:** a drop during the reveal before a debate no longer uses up that debate's one grace period.
  - **Rejoins:** after a rejoin mid-round the Debate screen shows the move and Zinger you locked in (the server now sends them as `view.debate.yourMove`); custom names no longer vanish for the rest of the match after a rejoin or a slow chat check.
  - **Reveal timer:** the week's reveal no longer runs longer when the opponent bought internal polls.
  - **More than two players:** forfeits, the bot's opponent and the plan preview no longer assume two players (two-player play is unchanged).


## 0.13.0: Landslide (Oct 24, 2026)

The game is now **Landslide** ("Race to 270"). This release puts a real US map under the campaign, turns debates into three live rounds on their own screen, gives every candidate an illustrated portrait, lets eligible players name their candidate (the Name Pass), plays the week's results move by move, deepens the colors, and adds Map and Graph tabs to the end screen. Polls cost half. Studio checklists: `docs/TESTING.md`, "0.13.0: Landslide".

**Needed from the humans:**
1. **Rename the experience** to `Landslide` in Studio (Game Settings → Basic Info) and on the Creator Hub, description starting "Race to 270." (`docs/TESTING.md`, "The new name: Landslide").
2. **Color Pass and Name Pass ids:** both are still 0 in `src/shared/Net/Products.luau`, so neither pass is on sale yet. Create the passes ("Setting up the Color Pass" and "Setting up the Name Pass" in `docs/TESTING.md`) and send both ids. Admins get both free meanwhile.
3. **Studio API access:** Home → Game Settings → Security → **Enable Studio Access to API Services** (in the published place), so saved colors and names, reports, the review queue and the leaderboard work in Studio; and chat on in Experience Settings → Communication (custom names need it).
4. Upload the eight portraits in `assets/portraits/` and send their ids (until then the plates show initials).

### The name: Landslide (D-064)

- **New name: Landslide, "Race to 270" (D-064).** The Lobby's logo is a big outlined "LANDSLIDE" with the tagline "RACE TO 270" on a tilted red-and-blue ribbon under it (scaled to fit a phone). 270 as the votes to win is unchanged everywhere.

### The Landslide stamp (D-062)

- **Landslide stamp (D-062):** win with more than 70% of the votes (377 of 538 or more) and Results stamps a big **LANDSLIDE** in your color under "You won", with extra confetti, a second hit and a light sweeping across it. Your opponent sees "REX WON BY A / LANDSLIDE" in Rex's color under "You lost". New `Config.LANDSLIDE_EV_SHARE` (0.70); the rules of winning do not change.

### The week's event under the score (D-065)

- **The week's event is at the top (D-065):** on the plan screen it is a strip right under the score, above the map, on every screen size: a gold icon, the event's name and one line of what it does ("Fundraisers where you trail +20%"; in a Choice week, your stance). Tap it for the full story and effect. It no longer sits in the side column.

### Polls at half price (D-063)

- **Polls cost half (D-063):** a state poll is $0.5 (was $1), a region poll $1.5 (was $3). Every price on screen follows. In the bot-vs-bot harness the bots buy about as many polls and put the saved money into ads and ground game; win rates moved within noise.

### The real US map (D-070)

Client only: no rule, sim, server, payload or Config changes. Studio checklist: `docs/TESTING.md`, "Real US map". The three map images are uploaded and their ids are in `Assets.luau` (if one is ever emptied, the game falls back to the circle map).

- **The map is a real map of the United States:** every state in its true shape, filled by who leads its poll as before, with thin dark borders. Alaska and Hawaii sit in the bottom left. The nine small Northeast states (VT, NH, MA, RI, CT, NJ, DE, MD, DC) are labeled chips in a column at the right edge, each with a thin line to where it really is.
- Tap anywhere inside a state to pick it, even a small one next to a big neighbor; tap a chip for the small Northeast states. The selected state gets a white outline.
- **Polls tab:** under each lead, ▲ in a player's color shows who has momentum there (▲▲: a lot), filled dots are your ground-game units, hollow dots the opponent's as your internal polls last saw them. A legend under the map says so, and the Map key explains it. The other tabs are unchanged.
- **Candidate pins:** your candidate stands on the state you are in, with your portrait and a "You" flag; the opponent's pin has their portrait and first name (or custom name). On every tab, on the plan and stance screens.
- The map's images and their data are made by `scripts/mapgen/make.py` from public-domain Census boundaries (us-atlas, ISC).

### Plan preview on the map (D-071)

Client only: no rule, sim, server, payload or Config changes. Studio checklist: `docs/TESTING.md`, "Plan preview".

- **While you plan a week, the map shows what your plan would do:** a faint number beside every state an action moves ("+4.1" green, "-0.6" orange), added up when several actions hit the same state, and under the map "Plan: 268 → 281 EV, if nothing else changes".
- **A tidier map:** marks (values, tags, plan numbers, pins) are placed beside each state's code and never cover any code; far ones get a thin line back to their state. Pins are smaller (face and a "You" tab) and never overlap each other; the planned route is thinner and fainter.
- It updates as you add or remove actions, shows in every map tab, and disappears when you lock in. It is your own estimate: the opponent's plan is unknown.

### Debates as live rounds (D-072)

Debates were "glorified stance questions". Now each debate is its own event: a stage, three quick rounds, a clash after each. Sim, server, payloads, bots, the debug and duel harnesses, and a new Debate screen. Studio checklist: `docs/TESTING.md`, "Debates as live rounds". The old debate scoreboard in the week's reveal is gone.

- **Three rounds, one per topic.** In each round both players pick **Defend**, **Attack** or **Pivot** in 15 s, in secret. Defend beats Attack, Attack beats Pivot, Pivot beats Defend.
- **Strengths are public.** They come from your platform and theirs, who leads the topic's states, the crowd, and your last move. Every button shows its strength and how it does against each of their moves ("D +4 · A +3 · P −1"). There is no dice roll.
- **Results land on the map live.** A win is +0.8 in the topic's states (Pivot: in your own issue's states); a split gives +0.5 each; losing to a counter costs −0.5. The polls update after every round.
- **One Zinger per debate:** stake it on a round, and a win counts ×2 (Marcus Hale ×4). A crowd meter fills as rounds are won; a lead of 8 is a standing ovation (+2 momentum in every battleground).
- **No move in time** is a weak Defend (2) that can't be countered. The debate focus screen is gone. A Choice week's stance still comes after the debate, on its own screen.
- **Bots** read the same board: Medium plays the move whose worst outcome is best; Hard and Extreme also read you (Extreme remembers what you played).
- **Debug and duel:** `defend`, `attack`, `pivot`, each optionally followed by `zinger`. The board prints every result cell.
- **Timing:** a debate takes about 40 s when both pick quickly (it was about 18 s). With every timer run out it takes 65 s. Together with the longer reveals of busy weeks, a match with every timer run out now takes 18 min 42 s on the main steps (21 min 22 s with every stance screen too), past the old 17.5-minute line: D-074 lists the levers for the designers. A typical match still takes about 12½ minutes (D-074).
- Wire: `{ move, zinger }`; new reasons `BadMove`, `ZingerSpent`, `UnexpectedMove`; `view.debate`; reveals `DebateIntro`, `Clash`, `Verdict`.

### The week's results tally up move by move (D-066)

Client only: no rule, payload or Config changes. Studio checklist: `docs/TESTING.md`, "The week's results, move by move".

- **Each move is followed by its effect.** In the end-of-week results, every shown move (yours and your opponent's, in the order shown) now moves the map's colors and leads and the header's projected votes and race bar right away. Every state the move touched shows its points ("+1.5" in your color, "−1.5" in orange against you); a lead change says FLIP, flashes in the new leader's color and shows in the header ("Rex: Rally · NY → Rex +28").
- **"New polls are in" is the last step,** with its own look: a stamp, "Polls shifted 4 states", a pulse sweeping the map. It lands exactly on the real new polls (momentum and poll noise on top of the moves). "What changed" still lists the whole week's real flips and biggest moves.
- The per-move numbers are estimates from the polls both players saw (the server never reveals true support); one line behind "Why?" says so.
- The header no longer jumps to the week's result when the reveal opens. Skip still ends it early.
- **Busy weeks get a longer reveal** so each move is seen to land: 4.5 s + 0.55 s per step, between 8 and 14 s (9.4 s on average, about +16 s a match). New Config: `TIMER_RESOLVE_BASE`, `TIMER_RESOLVE_PER_STEP`, `TIMER_RESOLVE_MAX`.

### A deeper, richer palette (D-067)

Client colors only: no rule, sim, server, payload or Config changes. Studio checklist: `docs/TESTING.md`, "Richer colors".

- **The campaign map is no longer pastel.** Toss-ups are a dark slate instead of light grey, and a lead shows as a deep version of the leader's color right away (a lean is 60 % of the color, was 45 %); safe states are the full, bright color. The light ring around every state is now a slate one, so it no longer washes the fill out.
- **Player colors are deeper and more saturated** (Crimson 212, 28, 66; Cobalt 34, 98, 228; Emerald, Amber, Violet and Teal likewise). Red stays clear of the loss orange, Violet moved farther from Cobalt.
- **Player names in color are vivid, not pink.** Readable text keeps the color's own hue (brightened just enough), instead of fading it toward white.
- **Gains are a clear green, not mint**, and the navy stage, cards and buttons are a richer navy at the same brightness. Every contrast floor still holds.

### Candidate portraits (D-068)

Client and assets only: no rule, sim, server or Config changes. Studio checklist: `docs/TESTING.md`, "Candidate portraits". Needed from the humans: upload the eight PNGs in `assets/portraits/` and send the ids (until then the game shows initials on the plates).

- **Every candidate has an illustrated portrait:** a friendly flat bust with their own face, hair, outfit and a prop that hints at the perk (Rex's straw boater, Helen's glasses and pencil, Walt's field cap, Priya's headset, ...).
- **Select:** the eight cards show the eight faces on the same neutral plate; a ring in your color marks your pick, a ring in your opponent's color (dimmed) marks theirs. Cards are a little taller for the bigger faces; a phone still fits step 1 without scrolling.
- Portraits also on the map reveal's strongholds card, the Campaign header (wide screens), the week reveal, the Debate screen's stage, the candidate pins on the map (ringed in each player's color), the election spotlight, Results and How to play.
- New `Kit.portrait`; `Kit.monogram` is unchanged. The headless snapshots draw the PNGs.

### The Name Pass: a custom name for your candidate (D-069)

Server, payload, Select, Help, Results and the Lobby. New Config values (name limits, reports, review, admins; no rule changes). Studio checklist: `docs/TESTING.md`, "The Name Pass". Needed from the humans: the pass and its id.

- **A Game Pass to give your candidate a name of your own** (up to 16 characters), entered on Select and remembered for your next matches. The candidate keeps its portrait and perk. Bots never get custom names.
- **Only for players Roblox lets chat, and only shown to them** (the stand-in for 16+: Roblox gives games no age). A viewer sees a name only if Roblox would let the two of them chat.
- **Filtered like chat:** Roblox's filter when you set it, and again for each viewer at their own level; anything hidden, or a filter that can't be reached, shows the candidate's own name. Letters, spaces, - ' and . only (no digits, emoji, links or handles), at least 2 letters, no letter three times in a row.
- **A server-only blocklist** of real politicians, parties and slogans, Roblox staff words, social-app and Robux bait, and the game's own words, matched through look-alike spellings. A note says names must follow Roblox's Community Standards.
- **Report name:** in the in-match "?" sheet and on Results. The reporter stops seeing that name at once and in later matches; the report waits for the owners. The sheet also points to Roblox's own Report for serious cases (games can't open it).
- **Owner review:** admins get "Review names (N)" in the Lobby: Keep, or Remove (the name is cleared, its owner told, and it and names like it are blocked on every server).
- **Admins** (the owner and originalyellowboss) get the color picker and custom names free, even before the passes exist.
- Wire: requests `SetName`, `ReportName`, `ReviewList`, `ReviewKeep`, `ReviewRemove`; message `Review`; DataStores `NameReports_v1`, `NameBlocklist_v1`; MessagingService topic `NameBlocklist`.

### The end screen: final polls vs the result, and votes week by week (D-073)

Results only; no rule or Config changes. Studio checklist: `docs/TESTING.md`, "End screen: Map and Graph".

- **Summary | Map | Graph tabs on the end screen.** Summary is the screen you know (who won, the Landslide stamp, why).
- **Map:** switch between **Final polls** (each state's last public poll, as you saw it the last week) and **Real results** (election night's winner and margin). States the polls got wrong wear a **MISS** tag, and one line names them ("Polls missed 3 states: CA, SC, OK"). Tap a state to compare its poll and its result.
- **Graph:** both players' projected votes week by week (the header's numbers), then the real result, with the 270 line and "D"/"S" chips on debate and stance weeks: tap one to see what happened that week.
- The match now keeps its weekly projected votes and sends them with the final results, so the graph is there after a rejoin too.

### Timer budget (D-074)

- No timer changed. With the reveal's longer busy weeks (+72 s) and live debates (+110 s) together, the worst case on the D-005 steps is 1,122 s (18 min 42 s), past the old 17.5-minute line; `Config.spec` now pins it under 19 minutes. **For the designers:** keep it, or pick a lever in D-074 (for example `TIMER_PLAN` 50 → 44 s).

## 0.12.0: Front-page look, leaderboard, bot levels, leaving, How to play (Oct 23, 2026)

A new look (navy stage, white accent, orange losses, chunky buttons, a lit map, stamps for the big moments), a global leaderboard, Easy to Extreme bots, Leave match, How to play, and Color Pass colors claimed first come, first served. Needed from the humans: the Color Pass id (see 0.11.0).

### Color Pass colors are claimed, first come, first served (D-061)

Sim, server, payload and the Select screen (no Config changes). Studio checklist: `docs/TESTING.md`, "Claiming colors".

- **Two Color Pass owners who want the same color:** whoever claims it first gets it; the other sees it taken and picks any other free color. They are no longer stuck with red or blue (D-055's tie rule is gone).
- **Your saved color is claimed for you as Select opens.** If you both saved the same one, a fair coin flip decides and the other player is told to pick another.
- Owners may change color until Select ends; a new color frees the old one. Players without the pass are still dealt red or blue, and colors never repeat.
- Wire: new request `ClaimColor { matchId, step, color }`; reasons `ColorTaken`, `NoColorPass`, `UnknownColor`; notice `ColorTaken`; View fields `colorClaims` and `canPickColor`.
- **Select gets a color picker for pass owners:** six round swatches under "Your color"; yours outlined in white, your opponent's dimmed and marked "Taken"; tap another to switch. Everyone else sees the color line as before.
- New notice: "Rex took Crimson first. Pick another color." Debug: `color Teal`.
- Fixed four client type errors (no behavior change).

### Front-page panels: Lobby, Select, Draft, stances, Campaign, Help (WP-2)

Client only: no rule, sim, server, payload or Config changes. Studio checklist: `docs/TESTING.md`, "Front-page panels".

- **Lobby.** The big "270" logo (round font, outlined, a soft glow) under "A 1V1 ELECTION STRATEGY GAME", on a navy stage glow. The bot levels are one segmented control under Play vs Bot. The leaderboard has gold, silver and bronze coins for the top three, ratings in the round font, and your own row raised with a white bar; beside the buttons it casts a shadow. A private match's code sits on a lit plate in the round font.
- **Select.** Every candidate card leads with a round portrait of their initials in your color (the taken one in your opponent's); the strength and weakness are one line each. The color line shows your candidate's initials in your color.
- **Draft.** Lean tags are filled in the leaning player's color ("+2 Rex" on red, "+2 you" on blue). On the map, a battleground is the outlined ★ tag (never a white fill), home is "H" in its owner's color, and your picks' numbers are outlined like the selection ring. The reveal names each pick in its taker's color with a ★ Battleground or Home tag.
- **Stances and debate prep.** Each choice has a bar on its left that turns white when picked; a stance's loss ("−10 states") is orange, its gain green. Good debate odds (50 % or better) are a green tag.
- **Campaign.** The header's score is the chunky race bar with the 270 tick, the vote counts in the round font at each end, names in readable player colors (numbers only on a phone). The state card's six actions have their icons on round plates, its poll is a small race bar. The event card says "THIS WEEK" over its title. "Map key" is now a **Key** chip with a magnifier.
- **Help ("?") and How to play.** The tabs are one segmented control; the pictures use the real race bar and the action icons on plates. **Leave match** sits under a line, orange-outlined. How to play's winners are tags filled in each player's color.

### Front-page map

Client only (and display numbers in `MapLayout`): no rule, sim, server, payload or Config changes. Studio checklist: `docs/TESTING.md`, "Front-page map".

- **The map is lit.** A soft navy glow sits behind the board; every state is a chunky token: a darker lip under it, a soft shadow, the top lighter than the bottom, its code with a thin dark outline.
- **The selected state glows** white (the accent) and the glow breathes slowly (off with Reduce Motion). On election night the state being counted glows the same way.
- **Map numbers are on dark plates** in the round display font. A battleground reads "★13" with a white outline (never orange, never a white fill). The lens line reads "Votes · ★ = battleground".
- **Polls lens:** each lead sits on a plate filled in the leader's color, so it reads on any state ("tie" stays plain).
- **Marks on the map:** a gain is a tag filled in your color; a loss is an orange tag with a dark "−0.5"; FLIP is a dark tag with a thick edge in the new leader's color. A moved state gets a colored ring and a soft bloom under it.
- **Phone:** states no longer overlap: circles keep their real size where the 36 px tap area is bigger, and the layout leaves a little more room between them.
- Draft: the map key's "Leans to you / Rex" words and the board's names use the readable version of each player's color.

### White accent (D-058)

Client only: no rule, sim, server, payload or Config changes. Studio checklist: `docs/TESTING.md`, "White accent".

- **The pink is gone.** The main button is solid white with a dark label on a slate lip; selected chips, cards and states get a white outline; the timer and its bar are white (orange near the end, as before).
- **Battlegrounds wear a star**: "★ Battleground" and "★13" on the map are outlined in white, never filled white, so they can't be mistaken for a button or a selection.
- Tips and notices have a soft grey outline; "Got it" is a small grey button.

### Front-page foundation (D-056)

Client only: no rule, sim, server, payload or Config changes. Studio checklist: `docs/TESTING.md`, "Front-page foundation".

- **Losses are orange, never red.** Anything that goes against you (a lost state, a negative number, an error, a destructive button, the timer's last 10 seconds, "You lost") is orange now. Red is only a player's color.
- **Battlegrounds are no longer orange**: on the map's numbers, the Draft and the state card (now a ★ tag, see "White accent").
- **A navy stage.** The background, cards and buttons move from grey-black to navy, with a visible light-from-the-top on every card and button edge.
- **Chunky buttons.** The main button and the grey ones sit on a darker lip and press down onto it; the main button's label is the round display font, and a light band sweeps it now and then.
- **The bottom bar is a panel** with a soft shadow; sheets have rounder corners, a shadow and (on a phone) a drag handle; the header's time bar is thicker with a glowing tip.
- **Color sheet:** each swatch shows your initial in that color. Amber is a little more golden so it never looks like the loss orange.
- Debate verdicts are filled tags: green "You win", orange "Rex wins".
- **Needed from the humans:** upload `assets/ui/ui-shadow.png` and `assets/ui/ui-glow.png` as images and send the two ids (they go in `src/client/UI/Assets.luau`; `assets/ui/README.md`). Until then there are no shadows or glows in the game; nothing breaks.

### Start screen: leaderboard, bot levels, How to play, leaving a match (D-059)

Server, net and client. No Config numbers changed. Studio checklist: `docs/TESTING.md`, "Start screen: leaderboard, bot levels, How to play, leaving a match".

- **Global leaderboard on the start screen.** Players ranked by rating: the top 10 beside the buttons on the iPad and the Mac, the top 3 on a phone, **See all** for the top 50. Your own row is highlighted, with "You: #4" (or "not in the top 50" and your rating). Only matches against players count, so playing the bot never moves you. Needs saved data (Studio: Enable Studio Access to API Services); otherwise it says "Leaderboard unavailable".
- **Bot levels.** Easy, Medium, Hard and Extreme chips under **Play vs Bot** (Medium to start; your pick is kept until you leave the game, and "Play vs Bot again" uses it too). What each level does: "Bot difficulty" below (D-057).
- **How to play** on the start screen is now five short pages for new players: the goal, a week, the actions, debates and events, election night. The full rules stay in the **?** during a match.
- **Leave a match.** **? → Leave match** on every match screen. Against a person it asks "Leave and forfeit?" and counts as a loss (rated, like a disconnect forfeit); your opponent is told they won by forfeit. Against the bot it just ends the practice match. Either way you go straight back to the start screen.

### Bot difficulty (D-057)

Sim, net and server.

- **Bot difficulty: Easy, Medium, Hard, Extreme** (D-057). A practice match can ask for a level: `{ op = "Practice", difficulty = "Easy" | "Medium" | "Hard" | "Extreme" }` (absent or unknown = Medium, today's bot, unchanged). Easy misjudges which states matter and picks half its debate focuses and stances at random; Hard predicts your plan from the public board and plays for the chance of reaching 270; Extreme pushes that further. Every level sees only what a human sees, and none gets extra money. Against the Medium bot: Easy wins about 19%, Hard 66%, Extreme 78%. Practice stays unrated. The State payload shows the level on the bot's seat (`seats[i].difficulty`) and the server log says `bot Hard`. Pick the level with the chips under **Play vs Bot** (above). Debug panel: `practice hard`. Studio checklist: `docs/TESTING.md`, "Bot difficulty".

### Front-page moments: reveal, debate, election night, results (D-056, WP-3)

Client only: no rule, sim, server, payload or Config changes. Studio checklist: `docs/TESTING.md`, "Front-page moments".

- **Week results** open with a small "WEEK 3 RESULTS" line over "You vs Rex", and end on a headline of who flipped what ("You flipped 4 · Rex flipped 7"). Each side's group has the candidate's initials in a colored circle. "What changed" lines are in the new leader's color with a green ▲ (went your way) or an orange ▼ (went against you); the biggest moves are filled green or orange tags.
- **Debates:** the score is in the round display font, and "You won 2 of 3 topics!" lands as a tilted stamp: green when you won the debate, orange when Rex did, grey when even.
- **Election night:** the score strip is a lit card with a thicker race bar and big round numbers. Each call flashes its state white on the map and slaps a "CALLED" stamp in the winner's color on the spotlight card, which shows the winner's initials. The suspense line reads "TOO CLOSE TO CALL" in orange and the state everyone waits on glows. The call that reaches 270 flashes the tick and, a moment later, stamps "270!" over the bar; that state keeps a white ring all night. Feed rows have a bar in the winner's color. The final banner has an "ELECTION NIGHT" line and glows in the winner's color.
- **Results:** "You won" is a green stamp and "You lost" an orange one (dark text, no red anywhere), with the winner's glow behind; the vote bar is the race bar with the 270 tick; each player's card shows big initials, and the winner's card is edged in their color. Confetti adds white. In Full breakdown, the closest states are in readable player colors.

## 0.11.0: Colors: red, blue and the Color Pass (Oct 23, 2026)

The designers asked for red and blue by default and a color pick for Robux (D-055). Sim, server, client. No Config numbers changed; the balance report is identical. Studio checklist: `docs/TESTING.md`, "Colors: red, blue and the Color Pass".

- **Red and blue by default.** Two players who did not pick a color are always one red (Crimson) and one blue (Cobalt), a coin flip deciding who gets which. With more players, the other four follow.
- **Color Pass (Game Pass, Robux).** Owners pick any of the six colors in the Lobby: **Color** opens a sheet with the six swatches and "Auto: red or blue". The color is saved and used every match. If both players picked the same color, a coin flip decides and the other gets red or blue. Without the pass the swatches are greyed and **Get the Color Pass** opens Roblox's purchase prompt.
- The server checks ownership with Roblox itself, never the client; if the check fails, the player gets red or blue.
- Select's color line no longer says colors are drawn at random.
- **Needed from the humans:** create the pass and send its id (`docs/TESTING.md`, "Setting up the Color Pass"). Until then the color option is hidden and every match is red and blue. The id goes in `src/shared/Net/Products.luau`, `COLOR_PASS_ID`.

## 0.10.0: Polish: motion and sound (Oct 23, 2026)

The polish foundation (D-053) and its three packages (the board and the map; reveals, election night and results; setup, help, settings and icons) merged together, the twelve icon images uploaded, then one pass over every snapshot at all three sizes (D-054). No rule, sim, server or payload changes; no Config numbers changed. Studio checklists: `docs/TESTING.md`, "Polish: the whole flow" first, then one section per package below.

- **Icons are images now.** The twelve Lucide icons are uploaded; action buttons, plan badges, the ♪ button, the settings chips and the Help pictures draw them (the glyphs stay as the fallback).
- **Plan badges sit on the circle's rim** instead of inside its corner, so the state's letters stay readable on a phone.
- **One "bonk" per refusal.** A plan the server turns down shows the red toast and shakes the action bar, with one error sound between them.
- **Results reasons:** a winner with fewer states reads "Dana won the bigger states (20 to 31)", not "carried 20 states to 31".

### Polish WP-1: the board and the map (D-053)

Client only: no rule, sim, server, payload or Config changes. Studio checklist: `docs/TESTING.md`, "Polish WP-1: board and map".

- **Map colors in four steps.** A state is grey when it's a toss-up (closer than 3 points), then leans, likely or safe (3, 8, 15 points) in the leader's color, instead of a smooth blend. **Map key** shows the four steps with both players' dots. Circles are lit a little from the top; border lines are fainter so the states stand out.
- **Tapping a state** clicks, draws its pink ring in, and fades its card in; the action buttons pop in one after another and each starts with its icon.
- **Planning shows on the map.** Holding an action button shows what it would do over the state ("+4.1"); each planned state wears its action's icon badge; removing the action fades the badge.
- **Adding and removing** an action pops its button, slides the plan row in (or fades it out) and plays a pop (or delete) sound, once per change.
- **Numbers count.** The projected votes and the money left count to their new values; the vote bars slide; a small "+12" / "-$2.0" chip rises and fades.
- **Lens switch** fades the numbers in the circles in; the circles never move.
- **Saying no.** A plan the server turns down, or a tap on a greyed-out Lock in, shakes the action bar with a short "bonk".
- **The opponent by name:** "Rex: thinking..." (the dots step along) and "Rex: locked in ✓", which rises and pops in. Same on the Decision screen, whose options now pop in one after another.
- Reduce Motion: no pops, rings, slides or rising chips, and the dots hold still; every value, badge and sound still lands.

### Polish: reveals, election night, results (WP-2, D-053)

Client only: no rule, sim, server, payload or Config changes. Studio checklist: `docs/TESTING.md`, "Polish WP-2".

- **The week's reveal in three beats.** "Both plans are in" with a whoosh and one line on who goes first; then the actions land one beat at a time, the trailing player's first (from the polls before the week, so the leader answers last), each one bumping its state on the map with a ring in the player's color and a pop; then the new polls: every state that changed leader rings in its new leader's color with a stinger, and the "What changed" rows slide in one after another.
- **Debate rows** fade in one per topic with the verdict pill popping; a topic you win plays a bright hit. The headline pops in.
- **Election night as a show.** The safe states are called quickly (all in the first 60% of the night), then the last 8 and the state that takes someone to 270 get 1.2 s each: the call holds, then "Too close to call" (or "Still counting") names the next one. Each call fills its state with a ring, bumps the spotlight, counts the votes up, grows the bar and dings higher as the leader nears 270. Reaching 270 says "Dana reaches 270!", flashes the 270 tick twice and plays a stinger.
- **Fixed:** election night showed the newest call twice (spotlight and list). The list now holds every call except the one in the spotlight; once all are called the spotlight steps aside and the list has all 51. "Results in" no longer turns red and ticks in its last 5 seconds.
- **Results.** A win pops "You won", counts both totals up, drops confetti in both colors and plays the victory stinger once; a loss fades in quietly with the defeat sound and adds one line under the reasons: "Try next time: …" (from the biggest reason the other player won). Once per match, never both.
- Reduce motion: no bumps, rings, pops or confetti; every line and number still arrives.

### Polish: setup, help, settings and icons (WP-3)

Client only: no rule, sim, server, payload or Config changes. Studio checklist: `docs/TESTING.md`, "Polish: setup, help, settings and icons".

- **Settings.** Two chips, **Sound** and **Reduce motion**, under How to play in the Lobby and at the top of **?** → How to win. A chip is outlined while its setting is on; both last for the session and follow the header's ♪ button. Roblox's own Reduce Motion setting still counts.
- **Lobby.** The "270" is in Fredoka One and pops in; the lines below fade in top to bottom.
- **Select.** Each step's cards pop in one after another; a card pops as you pick it.
- **Draft.** A state you pick pops into its slot, bumps on the map and plays a soft pop (a lower one when you take it back); a refused state shakes the status line with a bonk. When picks are revealed both cards pop, each state rings in its taker's color, with a whoosh.
- **Coach tips** pop in with a soft pip (the match's very first tip, on the candidate screen, stays quiet).
- **Toasts** slide in and fade out; a rejection (a bad code, a refused plan) shakes in place with a bonk.
- **Help pictures:** Actions and Polls show each action's icon beside its name.
- **Icons.** The twelve Lucide icons are in `assets/icons/` as 256x256 white PNGs (sources in `assets/icons/src/`, license in `docs/CREDITS.md`), uploaded, with their ids in `assets/icons/README.md` and `UI/Icons.luau`. An icon without an id shows its glyph.

### Polish foundation: motion, sound, type and depth (D-053)

The base the polish packages build on. Client only: no rule, sim, server, payload or Config changes. Studio checklist: `docs/TESTING.md`, "Polish foundation".

- **Every button moves and clicks.** Buttons shrink a little while pressed and spring back, with a soft click (chips a brighter one); a chip's pink outline draws in.
- **Sound.** Thirteen sound cues (Roblox UI sounds and two APM stingers; all eleven asset ids load in the published place) with a mute button (♪) in every header, left of **?**. Mute lasts for the session. Long clips are cut short so quick repeats don't smear.
- **Timer urgency.** The timer turns orange under 10 s and red under 5 s, where each second pops with a tick. The pink lock-in button flashes and chimes when you lock in.
- **Screens fade in** and slide up a few pixels; you can tap them straight away.
- **Reduce motion.** Roblox's Reduce Motion setting turns off every press, pop, ring and slide; values still update and screens still fade (briefly).
- **Type and depth.** Builder Sans for text, Fredoka One for big numbers, titles and the primary button; captions 14 px (from 13). Cards and buttons get a faint top-light gradient and a thin outline; the primary a darker pink edge. On big screens (iPad Pro, a large Mac window) the whole board scales up to 1.35×.
- **For the next packages:** `UI/Motion` (tweens, pops, enter/exit, stagger, count-ups, flashes, rings, shake, confetti, typewriter), `UI/Audio` (cues, mute, volume), `UI/Icons` + `Kit.icon` (the 12 Lucide images, glyphs as the fallback), map bands (`Colors.band`), `map:pulse/ring/badge/wipe`, `bar:setProgress`. How to use them: `docs/UI-STYLE.md` §2.7.1. Credits: `docs/CREDITS.md`.
- **Needed from the humans:** listen to the cues on a non-owner account (TESTING step 10).

## 0.9.0: UI overhaul (Oct 23, 2026)

The style v2 foundation (D-050) and its three screen packages (Lobby, Select and the draft; the campaign, decisions and the map; reveals, debates, election night, results and help) merged together, then one polish pass at all three sizes (D-052). No rule, sim, server or payload changes; no Config numbers changed. Studio checklists: `docs/TESTING.md`, "UI overhaul: the whole flow" first, then one section per package below.

- Version 0.9.0, phase "UI overhaul". The UI audit's pending list is empty: every screen passes the style rules (one primary, at most 4 text sizes, short labels, no walls of text, palette colors only).

### Polish after the merge (D-052)

- **Debate and reveal map:** a state that changes leader says just "FLIP" (its points are in the panel), so the debate map no longer stacks wide "+1.0 FLIP" tags over its neighbours.
- **Plain words:** the reveal's top line is one line ("You: Rally in Texas"); events say "20% more" instead of "×1.2"; action costs say "Flight $2.0"; Results' full breakdown and Help's "All the numbers" say votes and actions instead of EV and AP; the debate's "every state also got" line drops a side that got nothing.
- **Layout:** Results cards put votes and states on their own lines (no "20 / states" break on a phone); the map reveal on a wide screen hides the empty draft board (the Strongholds card says it); the waiting line on the private-match screen gets room above Cancel; an empty plan takes no extra gap; the stance and focus status lines fit on one line ("Stance C · kept secret").

### The primary color is pink (D-051)

- The primary button, the selection outline, the timer and the coach-tip outline are pink instead of yellow, so the Amber player's name and states no longer look like a button. Test in Studio: `docs/TESTING.md`, "UI overhaul: the whole flow".

### UI style v2: Lobby, Select, map reveal and draft (WP-A)

- **Lobby.** "270", one short line ("Win the race to 270 votes."), then Play vs Bot. Find match and Play a friend sit side by side under it; Play a friend opens a small sheet with "Make a code" and the code box + Join. A "How to play" link opens the help. While hosting, the code says "Waiting for your friend…" under it.
- **Select, step 1.** Each candidate card shows a one-line strength and weakness ("+ 4 actions a week", "− Weaker rallies"), so no card clips. The opponent's candidate is dimmed with a "Taken" pill. "About Dana" (under the cards) opens the exact numbers. Your color is a small dot and a line, not a square that looks like a button.
- **Select, step 2.** Issue chips say "154 votes · +41% boost" (two lines on a phone) instead of "154 EV · ×1.41"; "How issues work" explains both in a sheet.
- **Map reveal.** No rules wall: a "Strongholds" card (your dot, your five states; the same for the opponent, by name), who wins ties in round 1, the two-color legend, and "How the draft works" for the rules.
- **Draft rounds.** The header says the round, a line under it says what to do ("Pick a battleground", then "Add a backup, or Lock in", then "Waiting for Rex…"). The list shows the 8 best picks with a lean pill ("+2 you", "+2 Rex", "Even"); "Show all states" shows the rest. The battleground rule moved into "How the draft works" ("+50% more", not "×1.5"). On wide screens the legend sits beside the lens buttons.
- **Everywhere:** the "what to do now" line, a time bar under the timer, first-match coach tips on Select and the draft, the opponent called by name instead of "them", "votes" instead of "EV" in sentences.
- Test in Studio: `docs/TESTING.md`, "UI style v2: Lobby, Select, map reveal and draft". Nothing needed from the humans.

### UI style v2, WP-C: the big moments (reveals, debates, election night, results, help)

- **Week results, grouped.** The reveal after each week lists "Your week" and "Rex's week" (one line per action and state: "Rally in Texas ×2 · Farms & Rural", never the same line twice), then "What changed": every state whose poll leader flipped, one bold green or red line each ("Ohio flips to Rex · 17 votes"), and the three biggest moves as tags. The map badges only those flips and the 3 biggest moves. A Choice week's stances are a line in each group; their numbers are behind "Why?".
- **Debates as a scoreboard.** One row per topic: the topic, "you – them" score, a "You win" / "Tie" / "Rex wins" tag, and one short line ("You gain +1.0 in 14 states · DE flips to you"). Then the headline ("You won 2 of 3 topics!") and the points every state got. The dice math and the full state lists are behind "Why?". The map shows the flips and the 3 biggest moves instead of 30+ badges.
- **Election night.** A spotlight card shows the call that just happened ("Ohio · 17 votes", "Called for Dana by 2.9 points" in Dana's color) and builds suspense before a close one ("Too close to call", "Counting the last votes"). Calls read "Ohio · 17 votes" over "Dana by 2.9 points"; first names on a phone, so nothing is cut off. The header has the "?" too.
- **Results.** "You won" big, "280 votes to 258", the vote bar, two cards (color dot, name, votes and states, debate topics won), then "Why you won" in three short reasons (debates, close races, the biggest prize, your ground game…). "What decided it", the closest states and every debate moved to a "Full breakdown →" sheet. Four text sizes, player colors only on the dots and the bar.
- **How to play.** The 600-word rulebook is now a sheet with five tabs (How to win, Your turn, Actions, Events, Polls), each a small picture and at most 60 words; "All the numbers +" under each still has every exact rule. It opens on the tab for the moment, keeps the countdown, and closes with × or a tap outside.
- **Coach tips** reworded (at most 12 words, one per first-match moment); the toast stands off the screen (raised fill) and slides in. Fix: a coach tip in a list no longer breaks the UI audit.
- Test in Studio: `docs/TESTING.md`, "UI style v2: reveals, election night, results, help". Nothing needed from the humans.

### UI style v2, WP-B: the campaign screen, the decision screens and the map

- **Campaign: what to do now, always in sight.** Under the header a line says the next step ("Tap a state on the map", "Pick an action in Ohio", "All set? Press Lock in", "Waiting for Rex…") with the actions and money left at its right ("2 actions left · $4.0"). The header is one row on every screen size: the week, both candidates' projected votes on one bar with a halfway tick, `?` and the timer with its time bar. During a reveal the line shows the latest result.
- **The map is the hero; the state card is compact.** The week starts on the map with no card. Tapping a state opens a short card: name and votes, up to three pills (Battleground, Your home, You are here, Your issue), who leads the poll on one bar, then the actions as big buttons that say what they do in plain words ("Rally +4.1 support, fly $2.0", "Fundraise +$5.2", "Attack ad Rex -2.4, $3.0"). Phones show Rally, Fundraise and Ad, wide screens also Attack ad, Poll and Ground game; "More actions" has the rest. Message chips are plain issue names (no "×1.7"). "Details" opens the poll numbers, momentum, ground game, top issues and the full math per action. × or tapping the state again closes the card. Greyed-out buttons say why ("Not enough money").
- **Plan and Lock in.** The action bar shows the plan on one line ("Plan: Rally OH · Ad PA"); Lock in reads "Skip this week" on an empty plan (still one tap); the time-bank button is "+15 s". The plan list has a × on each line and Clear only when there is something to clear. The full state list is its own "All states" panel; the week card is now "News", collapsed.
- **Map.** One mark per state, inside its circle under the code: Votes (orange on a battleground), Issues (the top issue, filled when it is one of yours), Polls (the lead, "tie" or the lean), Money. Lens chips read Votes / Issues / Polls / Money; the legend line is gone, a "Map key" button opens a short sheet instead. Circles are drawn a little smaller with a thin ring, so the Northeast column and its neighbors no longer touch; small circles on a phone show their code only. Reveals and previews badge only flips and the five biggest moves; every other moved state glows.
- **Decision screens.** The header names the event ("Week 7 · Clinic walkout") or "Debate prep". The three stances are big chips with what each does ("+21 states · −10 states"; the hedge is "(safe)"); the three debate topics show "Schools · 14 states" with "You win 81%" and "Your issue" pills. The rest (states you need, odds, per-state lists) is behind "Why?". On a phone every option is on the first screen. The map key is two dots: helps you, hurts you.
- **Coach tips** (first match, once per session): the map, how to finish the plan (after the first action), the lens chips (week 2+), the stance and the focus.
- Tests: new `tests/ui/CampaignWords.spec.luau`; Campaign, Decision, Lens, Explained and Stances specs follow the new layout; the fake engine's `Vector2.new()` is (0, 0) as in Roblox. `Audit.PENDING` no longer lists Decision or Campaign.
- Test in Studio: `docs/TESTING.md`, "UI style v2: campaign, decisions and the map". Nothing needed from the humans.

### UI style v2, phase 1: foundation (D-050)

- **Screenshots without Studio.** `lune run tests/ui/snap.luau` renders every screen and state (lobby, both Select steps, map reveal, draft, stance, focus, plan, state card, each lens, resolve, debate, election night, results, help) at phone, iPad and desktop sizes into `build/snaps/` as SVG and PNG, with each shot's UI audit in `build/snaps/audit.txt`. `00-kit` shows every component.
- **Audit and plan.** `docs/UI-STYLE.md`: what is cluttered or unclear on each screen, the style v2 design system, the principles (one primary action, details one tap away, a "what to do now" line, first-match coach tips, the map as the hero) and a per-screen redesign split into three parallel work packages.
- **New building blocks** (no screen uses them yet, so nothing looks different except below): ghost buttons, cards, tappable option cards, chips, pills, stacks, dividers, a sheet (bottom on phones, centered on wide screens), coach tips (shown once per session), the header's "what to do now" line and time bar, motion durations and `Kit.tween`.
- **Small visible changes:** warning text is orange instead of the accent yellow (only Select's "tap one to swap it" and Decision's "No focus in time" use it today), and an expanded section's title ends in "−" instead of "–".
- **UI audit style rules:** colors only from the palette, at most 4 text sizes per screen, button labels at most 8 words, no text over 30 words outside a details area. Screens not yet redone are listed as pending (notes, not warnings).
- Test in Studio: `docs/TESTING.md`, "UI style v2 foundation". Nothing needed from the humans; four design questions are at the end of `docs/UI-STYLE.md`.

## 0.8.0: Playtest 4: cleaner choices (Oct 23, 2026)

Five branches merged for playtest 4 (`docs/DESIGN.md` D-044 to D-049). Each was tuned on its own; the combined harness numbers are below. Studio checklists: `docs/TESTING.md`, one section per feature below.

- **Combined harness** (2,000 matches, all five together): priority A 51.2%, comeback 37.5%, median margin 52 EV (40+ EV 60.8%, 100+ EV 20.8%); debates change the winner 25.9%, stances 11.5%, GOTV 8.9%; NoFocus 26.6%, RandomStance 28.9%, NeverPoll 53.0%, TopIssues / NicheIssues 49.6 / 48.0%; draft 3 rounds / 71 s; 0 invalid bot inputs. Red: Calloway 57.4%, Venkat 55.1%, Alvarado 43.1%, Okafor vs Hale 65%, the D-020 underdog flags (16.9% / 3.13) and GOTV 8.9%, all red before or within noise of the separate runs. No numbers were tuned in the merge.
- Version 0.8.0, phase "Playtest 4: cleaner choices".

### Decision screens and the debate focus (D-044)

- **Stances and debates get their own screen.** In a Choice week the stance is taken on its own screen before the plan, with its own 20 s timer (no stance in time: C). Right before each debate, a second screen asks for your debate focus. Each shows only the decision, the map preview, the countdown and Lock in; when both players lock in it moves on at once. The plan screen keeps its 50 s and loses the prep panel and the stance chips; it says "Your stance: A · …" in one line.
- **Prep is now one focus topic.** One tap: the topic you focus on gets +2 (Marcus Hale: +3, replacing his 7th prep point). The screen lists each topic's states and EV, the ones you need (within 5 points in the public poll) and your odds ("You win 81% (38% if they focus here too)"). No focus in time: every topic you lose is a gaffe (-0.6 in its states). Gaffes no longer come from a 0-prep topic.
- **Harness:** debates change the winner in 24.1% of matches (was 23.2%); a player who never picks a focus wins 22.8%; Hale 47.7% (was 51.7%). Between two bots the topic choice itself is a wash (both pick the same topic 94% of the time); see `docs/DESIGN.md` D-044.
- **Debug and duel.** F2 and the duel harness have `focus TOPIC` and `choice a|b|c` as their own step (no longer inside `plan`); the duel README explains the Decision steps.
- **Test in Studio:** `docs/TESTING.md`, "Decision screens: debate focus and stances". Nothing needed from the humans except a view on the 20 s timer and the match length (D-044, "Timer").

### A shorter draft (D-045)

- **Strongholds are no longer drafted.** At the map reveal each player is given their five strongest-leaning states as strongholds (same +8 / +4 bonuses), shown for both players on the map and in a "Your strongholds: … · theirs: …" line, before any pick. A stronghold can't be a home.
- **The draft is three blind rounds**: home state, then two battleground nominations (priority A, B, B). It takes about 71 s instead of 181 s.
- Harness (2,000 matches): priority A 47.8% (48.9% at 6,000), comeback 39.9%, median margin 50 EV (was 52), stronghold EV gap between players 2 EV at the median. The most common stronghold is now in 28% of matches (GA, OH, MI, NC were in 98–100%). Homes are still mostly CA or TX: see `docs/DESIGN.md` D-045 for options.
- Bots, the balance harness (new "Draft" section), the duel harness and its README, the F2 board and the specs follow the new draft.
- Test in Studio: `docs/TESTING.md`, "A shorter draft (D-045, v0.8.0)". Nothing needed from the humans.

### Map lenses (D-046)

- **The map shows one thing at a time.** Four chips over the map, **EV / Issues / Polls / $**, switch what each state shows under its name: its electoral votes (default, "B" on a battleground); its two top issues, yours filled in your color; the public poll lead in the leader's color with your internal poll ("i+5"), momentum ▲ and ground game ("G2"); or what one more fundraiser there would raise this week (dim once your plan empties the pool). Works on the Campaign and Draft screens and stays picked for the session.
- **Less on the default map.** The "H B G3" tags and the momentum arrows are gone from the campaign map; the tag above a state now appears only when it matters (the week's event *, stance previews, reveals, draft picks). The fill by poll leader and the owner rings are unchanged.
- The line over the campaign map explains the current lens. New specs `tests/ui/Lens.spec` (each lens's text per state, switching, session memory, strict UI audit at 390x844, 844x390, 768x1024, 1024x768 and 1280x720).

- **To test:** `docs/TESTING.md`, "Map lenses". Nothing needed from the humans.

### Drawn issues and colors, unique candidates (D-047, D-048)

- **Top issues are drawn every match.** Each state's two top issues come from the match seed (regional flavor kept: Farms still leans to the Plains), balanced so every issue covers 108–161 EV. Every issue now tops the EV ranking in some matches; the bot's platform is the match's three biggest issues 2% of the time (was 29%), and every issue is 12–13% of platform picks (Schools and Farms were never picked).
- **Niche issues hit harder.** A platform issue's rally/ad multiplier grows as its EV shrinks: ×1.72 at 108 EV, ×1.5 at the mean, ×1.39 at 161. Running on the three biggest or three smallest issues wins about as often as a mixed platform.
- **Colors are drawn**, distinct and seat-blind; the color picker and the color-clash toast are gone. Your color shows as a line on the Select screen.
- **Two players never share a candidate.** Select is two steps: claim a candidate ("Next: issues"), then pick three issues. The opponent's candidate shows "Taken" at once; a same-moment clash goes to a seeded coin flip and the loser picks again. Select timer 30 → 38 s.
- The issue chips, state cards, help text, debug board, duel harness and its `map.txt` read this match's issues. Debug: `claim CANDIDATE`; `select CANDIDATE ISSUE ISSUE ISSUE` (no color).
- **To test:** `docs/TESTING.md`, "Drawn issues and colors, unique candidates". Nothing needed from the humans.

### Polls reveal ground game (D-049)

- A paid internal poll (state or region) now also shows the opponent's ground-game units in each polled state, exactly, as of the end of the week you polled. Only the player who polled sees it. Before this, nothing showed ground game until election night.
- The state card keeps your latest reading ("Their ground game here: 3 units, -4.5 for you on election night (your poll, end of week 8)"), or says "hidden. A poll shows it" where you never polled. The map's Polls lens tags those states "opp G3". The week card's internal-poll line, the F2 board and the duel harness show the same.
- Results: "What decided it" adds "Your polls found their ground game in OH (3 units; you had 4, won it)".
- The Poll and Region poll previews and the help screen now say what a poll is for: seeing their hidden ground game before election night.
- Ground game costs $2.5 a unit (was $2): at $1.33 a point of margin it was the cheapest point in the game. Walt Begay still pays $1.
- Bots scout close states from week 7 (not while the opponent's cash shows Low), count what they see against their own margin there, and start ground game a week earlier.
- Harness (2,000 matches): GOTV changes the winner 10.4%, average GOTV spend $7.7, candidates 45.8–55.3%. The never-poll bot still wins about 55% against the polling bot: see D-049 for why the bots cannot use the information and what would change it.
- Test: `docs/TESTING.md`, "Polls reveal ground game". Nothing needed from the humans.

## 0.7.0: your base hears your stance (D-043)

- Choice events: a side (A or B) now counts double in your own home state and strongholds. The hedge (C) no longer gives anything; it costs 0.5 in each of your home and strongholds where the issue is a top issue. Stance moves are capped at 3 a state (was 2).
- The rules text, the event card's stance lines and the duel screens explain the new rule, including the platform ×1.5 and the cap (playtest 3 found the old text left them out).
- Harness: stances now change the winner in 14.6% of matches (was 5.1%); the bot that reads the card beats random stances 66–34 (was 61–39).
- Test in Studio: in a Choice week, your home and strongholds should show the biggest badges; selecting C should show red badges only on your own base states that have the issue.

## Unreleased: map tags

- Map badges and FLIP markers now share one solid tag on each circle's top edge, drawn above every state, so they no longer cover neighboring states' names. A flip fills the tag in its color ("+0.5 FLIP").
- Dimmed states are less faded.

## Unreleased — screens for stances and debates

The client pass for D-039 to D-041, version 0.6.0 ("Issue-based choices"). Design log: `docs/DESIGN.md` D-042. No rules, Config numbers, payloads or `Sim/` files changed.

- **Choice weeks show the stance on the map.** The event card lists the three stances as full-width chips ("A · Side with the staff", "C · Offer to mediate (hedge, default)"). While the card is open the map previews the selected stance: states that gain glow in your color with "+1.5" badges, states that lose show red "-1.5" badges, states whose poll leader would change say FLIP. Hold a chip to peek at a stance without picking it; collapse the card for the normal map.
- **"States you need".** Every state within 5 points in the public poll, either way, with your projected EV. Each stance gets one summary line: "Stance A · …: +6.0 in 9 states (4 you need: OH, PA…) · -3.0 in 5 states (2 you lead: KY by 3…) · could flip PA (+19 EV), lose WI (-10 EV)". The full per-state lists stay under "Every state, stance by stance".
- **Debates say what they did.** Each topic in the debate reveal reads "Your Jobs win swung OH, MI, PA (+1.0 each) - PA flipped to you (+19 EV)" (big when a state flips), gaffes read "Their gaffe on Safety: -0.6 in TX, AZ…", and the map badges and FLIPs the states as each topic lands. The week card keeps the prep/platform/stat/roll breakdown and adds the same lines.
- **The week after a Choice event**, the resolve reveal and the week card say what both stances moved and flipped, and the map badges it.
- **Results: "What decided it".** What debates and stances flipped on the polls, for whom, which of those states held on election night, and the final gap.
- **Help and text.** "How it works" describes the spillover, the +0.1 a topic win adds in every state, and the map previews; the effect line reads "Take a stance on Jobs: each state reacts by its own top issues". The rules pass's stopgaps (`PlanDraft` Choice note, verb and last-event line, the Reveal caption) are gone.
- **Debug board and duel harness.** The F2 board prints the states you need and one summary per stance in a Choice week, both stances afterwards, and each debate topic's swing and flips. `tests/duel.luau` no longer errors in Choice weeks; its screens list every state each stance moves, its examples take `choice a`, and the README explains Choice weeks and debates. Scripted smoke matches (pass and example) finish with exit 0.
- **For developers.** New `Shared/UI/Swing` (pure) and `CampaignParts/SwingMarks`; `MapInterface.Mark` gains `badgeColor`, `halo`, `haloStrong`, `note`, `noteColor`; new fixture moment `ChoiceResolve`; the fake engine fires `InputEnded`. New specs `tests/ui/Swing.spec` and `tests/ui/Stances.spec` (previews, flip callouts, results section, strict UI audit of the Choice week, both reveals and Results at 1280x720, 844x390 and 390x844). Specs: 691.

**To test:** `docs/TESTING.md`, "Screens for stances and debates". Nothing needed from the humans.

## Unreleased — issue-based choices and debates

Rules pass approved by the designers: Choice events and debates are skill-based, tied to each state's issues, and visibly move states. Design log: `docs/DESIGN.md` "Issue-based choices and debates" (D-039 to D-041), with the before/after harness table in D-041. `docs/PLAN.md` "Debates" and "Events" describe the new mechanics.

- **Choice events are stances on an issue (D-039).** Eight Choice events, one per issue (24-card deck). Each offers stances **A** and **B** (opposed) and **C** (the hedge). States where the event's issue is a top issue react by their other top issue: +1.5 support where the stance is liked, -1.5 where it is not, +0.5 otherwise; every other state moves +0.5 per top issue the side likes and -0.5 per one it dislikes; the hedge is +0.5 in every state with the issue and nothing elsewhere; a candidate whose platform carries the issue is heard ×1.5 there (capped at the event cap of 2). Reactions come from fixed state data and the public platform, so the same event moves the same states every match and the client can preview every stance on the map (`Events.stanceEffects`). The right stance depends on which states *you* need. Both stances resolve from one snapshot and are revealed with the week, with each state's points (`EventResult.moves`) and the poll leaders they would flip (`EventResult.flips`). The D-036 Attack / Defend / Ignore payoff matrix is gone. A missing stance is the hedge.
- **Debates move states (D-040).** Winning a topic adds 1.0 support in every state where the topic is a top issue plus a flat 0.1 everywhere; a gaffe costs 0.6 in the topic's states; a sweep adds a flat 0.2 and battleground momentum. The public polls are republished right after the debate (same error terms), so the map shows the debate at once. `DebateResult` carries `moves` (every state's points per player), `flips` (states whose public-poll leader changed) and `gaffes`; the resolve events add `PollFlip` lines with the EV.
- **Bot (D-041).** Takes the stance worth the most expected EV on its own map (`Bot.choose`), and splits debate prep by the EV each topic's states are worth, trying every split against the roll odds (`Bot.prep`, `Debate.odds`). New harness style `RandomStance` (the same bot with random stances) for the skill check.
- **Harness.** New lines: Choice stances change the winner (counterfactual recount, like debates), average EV they swing, Choice events per match, stances taken, how often both players took the same stance, and the RandomStance win rate (target ≤ 45%).
- **UI contract for the client pass** (screens are a separate pass): `View.event.stances` (`{ id, name, text }` ×3) and `View.event.issue` for Choice events; `Events.stanceEffects(config, Events.byId[event.id], stanceId, platform)` for the map preview; the plan field is still `choice`, now `"A" | "B" | "C"`; `Explain.choiceLines(config, event, platform)` returns one line per stance; `Debate.topicStates(topic)` and `Debate.odds(config, edge)` for the prep screen.
- **Kept green with minimal edits outside the rules** (the client pass will replace them): `UI/Explain` (`choiceLines`, `stanceEffects`, help text), `UI/PlanDraft` (`choiceNote`, `choiceVerb`, `lastEventLine`, the Choice effect line), `UI/Fixtures` (fixture seed 7 → 18 so weeks 3 and 8 stay Windfalls with the 24-card deck), `client/Screens/Campaign` (default stance C), `client/CampaignParts/EventCard` and `Reveal` (text and the `choiceLines` call), `DebugUI/Commands` (`choice a|b|c`) and `DebugUI/Format` (stance lines, poll flips), and the specs that quoted the old answers. `tests/duel.luau` still prints the old Choice lines and will error on `e.national` in a Choice week; it is another agent's file and is listed for them.

**To test:** `docs/TESTING.md`, "Issue-based choices and debates". Nothing needed from the humans except the fictional stance texts in `Sim/Events.luau` if they want different flavor.

## Unreleased — playtest 2 fixes

Four small bugs from the second agent playtest. No rules, payloads or `Sim/` files changed.

- **`ad` works as a plan command.** The debug command box takes the names the game shows (D-030): `ad MI jobs`, `attack ad PA jobs` (or `attackad`), `fundraise OH`, next to the old `media`/`attack`/`fund`. `help` and the duel screens' commands and examples use the new names.
- **Info commands are never a rejection.** In the duel harness, `rules` (and every info line: `show`, `help`, `bank`, `resync`, `skip`) gets the verdict `INFO: not locked in yet, no attempt used`, at Select, Draft and Plan alike; before, `rules` read "REJECTED: nothing locked" and used an attempt.
- **The duel screen follows `show`.** After `show NY` the refreshed screen's "WHAT EACH ACTION WOULD DO" points at NY (its numbers are in the command output on the same screen) instead of the candidate's state.
- **Momentum drift is quoted at its real size.** Momentum first keeps 50% (Reyes 25%), then the leader gains 0.6 per point of what is left, so a lead you see drifts 0.3 support per point next week. The state card note, "How it works", the debug board and the duel table all say so; `tests/ui/Momentum.spec.luau` checks the text against a real sim week.

**To test:** `docs/TESTING.md`, "Playtest 2 fixes".

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
