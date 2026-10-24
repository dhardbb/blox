--!strict
-- The server's own list of names custom candidate names may not use (the Name
-- Pass, docs/DESIGN.md D-069). SERVER ONLY: never sent to clients and never
-- shown to players (a refusal just says "That name isn't allowed. Try
-- another."). It complements Roblox's text filter, which every name still
-- goes through; it never replaces it. Names a reviewer removes are added at
-- run time from the NameBlocklist_v1 DataStore (server/NameReview).
--
-- Matching is CustomName.blocked: names and entries are folded (lower case,
-- accents and look-alikes such as 0/o and 1/l/i folded, only letters kept).
--   "word"   the folded name contains the folded entry, or something within
--            Config.NAME_SIMILAR_DISTANCE edits of it (entries of 5+ letters)
--   "=word"  whole words only (short or common words that are parts of
--            ordinary names: "Bush" but not "Bushnell"; "you" but not "Young")
--
-- What is on it, following Roblox's Community Standards (no political content
-- about real people, parties or movements; no impersonation; no off-platform
-- contact or scams):
--   real heads of state and government and leading politicians, recent and
--   current (US and UK first, then other major countries); national parties;
--   well-known political slogans and movements; Roblox, its staff and
--   moderation; social apps and contact bait; Robux scams; the game's own
--   words for players ("You", "Rival", "Bot", ...) that would confuse a screen.
-- Titles ("President", "Senator", "Governor") stay allowed on fictional
-- names: a real surname is what makes a name political.

local NameBlocklist: { string } = {
	-- United States
	"=trump",
	"donaldtrump",
	"=biden",
	"joebiden",
	"obama",
	"kamala",
	"=harris",
	"=pence",
	"=vance",
	"=walz",
	"=clinton",
	"hillary",
	"=bush",
	"=sanders",
	"=bernie",
	"desantis",
	"=haley",
	"=newsom",
	"pelosi",
	"mcconnell",
	"schumer",
	"=aoc",
	"ocasio",
	"=cruz",
	"=rubio",
	"ramaswamy",
	"=rfk",
	"=musk",
	"=reagan",
	"=nixon",
	"jimmycarter",
	"=melania",
	-- United Kingdom
	"starmer",
	"=sunak",
	"=truss",
	"borisjohnson",
	"=boris",
	"=farage",
	"=corbyn",
	"thatcher",
	"=blair",
	"badenoch",
	"davidcameron",
	"=theresa may",
	-- Other heads of state and government
	"=putin",
	"zelensky",
	"zelenskyy",
	"jinping",
	"=xi",
	"=modi",
	"=macron",
	"trudeau",
	"=carney",
	"poilievre",
	"=scholz",
	"=merz",
	"=meloni",
	"netanyahu",
	"erdogan",
	"=milei",
	"=lula",
	"bolsonaro",
	"=orban",
	"kimjong",
	"maduro",
	"khamenei",
	"=hitler",
	"=stalin",
	"=mao",
	-- Parties
	"democrat",
	"republican",
	"=gop",
	"=dnc",
	"=rnc",
	"=labour",
	"=tory",
	"=tories",
	"conservative",
	"=libdem",
	"=lib dems",
	"=reform uk",
	"=snp",
	"=ukip",
	"libertarian",
	"communist",
	"=nazi",
	"fascist",
	"=kkk",
	-- Slogans and movements
	"=maga",
	"makeamerica",
	"letsgobrandon",
	"=fjb",
	"lockherup",
	"stopthesteal",
	"buildthewall",
	"yeswecan",
	"brexit",
	"takebackcontrol",
	"blacklivesmatter",
	"alllivesmatter",
	"=blm",
	"antifa",
	"proudboys",
	"defundthepolice",
	"prolife",
	"prochoice",
	"freepalestine",
	"standwithisrael",
	"=from the river",
	-- Roblox, staff, moderation
	"roblox",
	"builderman",
	"=admin",
	"administrator",
	"moderator",
	"=mod",
	"=mods",
	"=official",
	"=staff",
	"=developer",
	-- Off-platform contact and scams
	"discord",
	"=snap",
	"snapchat",
	"=insta",
	"instagram",
	"tiktok",
	"youtube",
	"=yt",
	"twitch",
	"=twitter",
	"=dm me",
	"=dm",
	"=add me",
	"=follow me",
	"=sub to",
	"robux",
	"=rbx",
	"=giveaway",
	-- The game's own words for players
	"=you",
	"=rival",
	"=bot",
	"=tie",
	"=nobody",
	"=opponent",
	"=player",
	"=unknown",
}

return table.freeze(NameBlocklist)
