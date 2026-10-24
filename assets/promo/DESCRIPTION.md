# Experience page: draft text

A draft for the Roblox experience page. The humans decide what to publish. Paste the blocks as plain text; Roblox shows the description without Markdown formatting.

## Title

```
Landslide: Race to 270
```

22 characters. The name is the game's own and the tagline is the in-game ribbon, so the title, icon and lobby all match. Roblox advises keeping a name stable once players know it ("Renaming an experience too often reduces the chances that players can find it") and using one or two emojis at most; this title has none.

## One-line pitch

```
Run a 12-week campaign across the US map and race your rival to 270 votes.
```

Use it where a short line fits: the first line of the description, a group post, an update announcement (those have a 60-character limit, so there use "Race your rival to 270 votes on the US map!", 43 characters).

## Description

```
Run a 12-week campaign across the US map and race your rival to 270 electoral votes in this 1v1 strategy game!

Pick a candidate, choose your issues, then plan each week: rally, fundraise, run ads and build a ground game in the states that matter. Win debates to swing every state that cares about the topic, then watch election night as the states are called one by one.

- 1v1 strategy on a real US map: all 50 states and DC
- Live debates: Defend, Attack or Pivot in three rounds
- Play online: find a match on any server, or invite a friend to yours
- Bots at four levels from Easy to Extreme, and a 5-minute tutorial
- Daily Race: everyone plays the same candidate for a spot on today's board
- Global leaderboard: climb the ranks in rated matches

Every candidate, issue and event is made up. No real politicians, parties or policies. A match takes about 15 minutes.
```

872 characters. The Creator Hub's description box takes up to 1,000 characters; Roblox's docs give no number of their own, so check the counter when you paste. What the docs do ask, and this follows: say what the game is in the first sentence, use the keywords players search for (strategy, 1v1, election, campaign, debates, map, leaderboard), and don't repeat keywords or add unrelated ones, which "may result in demotion of your experience".

Before publishing, check (updated for 0.15.0, which shipped all of these):

- **Daily Race**, **matches across servers** and **invites** are in this build. Invites and matching across servers only work in the published game (not in a Studio playtest), so try them there once before you publish the text.
- **Four bot levels** (Easy, Medium, Hard, Extreme), the **short tutorial** (4 weeks, about 5 minutes) and the **private code** match the Lobby you publish.
- "about 15 minutes" is the typical length of a real match (D-005).

Why it is written this way: plain words for a young audience, one exclamation mark, no all-caps or emoji, no claims ("best", "#1", "most popular"), and no political content. The topics are the game's eight neutral issues (jobs, schools, farms and so on), never a side or a slogan.

## Content maturity questionnaire (expected answers)

Creator Dashboard → the experience → **Publish settings → Content rating → Start**. Answer for the most mature thing a player can meet in the game. Expected label: **Minimal**, with no content descriptors.

| Question | Answer | Why |
|---|---|---|
| Violence | None | No fighting, weapons or harm. "Attack" is an attack ad and a debate move: words only. |
| Blood | None | |
| Fear | None | No horror, jump scares or threats. |
| Crude humor | None | |
| Unplayable gambling | None | No casino, betting or dice. Campaign money is a game resource that can't be bought, and debates are decided by the moves, with no dice roll. |
| Strong language | None | All game text is written by us. Custom names go through Roblox's text filter plus a server blocklist. |
| Romantic themes | None | |
| Alcohol | None | |
| Social hangout | No | The main activity is a strategy match, not talking to people. Roblox chat is on (custom names need it), but that is Roblox's own chat. |
| Free-form user creation | No | Roblox defines this as drawing, painting or writing on surfaces. The game has none; a filtered candidate name is not drawing or writing on the world. |
| Sensitive issues | No (see note) | Roblox defines a sensitive issue as a current social, political or religious issue with "a limited number of strongly opposing viewpoints, with little room for compromise". The game takes no side on any issue. Its topics are neutral (Jobs, Health, Schools, Environment, Safety, Roads & Transit, Technology, Farms & Rural), candidates and events are invented, and there are no parties or positions. Electing someone is the game's setting, not a debate about a real issue. |
| Paid random items | No | The Color Pass and Name Pass are fixed Game Passes: you know what you get. No loot boxes. |
| Paid item trading | No | No trading. |
| Media | No | No in-game sharing of player-captured screenshots or video, and no feeds. |
| AI interaction | No | The bots are scripted rules, not generative AI. |

**Note on Sensitive issues.** This is the one answer that is a judgment call. Answering "Yes" would limit the game to players 16 and over, so answer from what the game actually contains: no real people, parties, positions or slogans, and issues with no "sides". If Roblox moderation ever asks about it, those are the reasons. If the game later adds anything resembling a real policy debate, revisit this answer (and CLAUDE.md's fictional-only rule forbids that anyway).

## Images

| File | Use |
|---|---|
| `icon.png` (= `icon-map.png`) | the experience icon (recommended) |
| `icon-faceoff.png`, `icon-stamp.png` | the other icon variants, if you want to compare |
| `thumb-1-hero.png` | thumbnail 1: the two candidates over election night |
| `thumb-2-campaign.png` | thumbnail 2: a real campaign week, "Race to 270 in 12 weeks" |
| `thumb-3-debate.png` | thumbnail 3: a real debate round, "Win the live debates" |
| `thumb-4-landslide.png` | thumbnail 4: the win, "Win by a LANDSLIDE" |

Upload steps are in `docs/TESTING.md`, "Promo art". Alt text for each thumbnail (Experience Detail Page tab):

1. "Two cartoon candidates face off over a US map of red and blue states, under the Landslide logo."
2. "The campaign screen: a US map with each state's votes, the race bar to 270 and the week's actions."
3. "A debate round: the question, the Defend, Attack and Pivot moves, and the states each move would swing."
4. "A cheering candidate, confetti, and a blue map with the words Win by a Landslide and a 386 to 152 score."
