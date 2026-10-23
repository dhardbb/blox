--!strict
-- Short copy for the first minutes of a match (docs/UI-STYLE.md §4.1-4.3, WP-A):
-- the Lobby, Select (candidates and issues), the map reveal and the draft. Plain
-- words a 12-year-old knows, labels of at most 8 words, "votes" in sentences.
-- The full numbers stay one tap away (a sheet); this module only words them. Pure.

local Candidates = require("../../Sim/Candidates")
local ConfigModule = require("../../Sim/Config")
local Numbers = require("../Numbers")

type Config = ConfigModule.Config

local Setup = {}

-- ---------------------------------------------------------------- Lobby

Setup.TAGLINE = "Win the race to 270 votes."
Setup.EYEBROW = "A 1v1 election strategy game" -- over the wordmark, in capitals
Setup.HOSTING_TITLE = "Your private match"
Setup.FRIEND_MAKE = "Make a code and send it to a friend."
Setup.FRIEND_ENTER = "Got a code from a friend? Type it here."
Setup.CODE_PLACEHOLDER = "Enter code"
Setup.HOSTING_HINT = "Tell your friend this code"
Setup.HOSTING_WAIT = "Waiting for your friend…"

-- The color option (D-055): shown only once the Color Pass is set up.
Setup.COLOR_TITLE = "Your color"
Setup.COLOR_AUTO = "Auto: red or blue"
Setup.COLOR_LOCKED = "Pick your color with the Color Pass."
Setup.COLOR_OWNED = "Tap a color. You get it every match."
Setup.COLOR_TIE = "Same pick as your opponent? A coin flip decides."
Setup.COLOR_BUY = "Get the Color Pass"

-- The Lobby button: "Color: Emerald", or "Color: red or blue" with no pick.
function Setup.colorButton(color: string?): string
	return if color then `Color: {color}` else "Color: red or blue"
end

-- ---------------------------------------------------------------- candidates

-- One strength and one weakness per candidate, each short enough for one line
-- on a phone card (Select step 1). The exact numbers are in Setup.candidateDetails.
local SHORT: { [string]: { strength: string, weakness: string } } = {
	okafor = { strength = "Raises more money", weakness = "No weakness" },
	calloway = { strength = "4 actions a week", weakness = "Weaker rallies" },
	venkat = { strength = "Cheap ads", weakness = "Half the income" },
	hale = { strength = "Better in debates", weakness = "No starting money" },
	alvarado = { strength = "Starts with $20", weakness = "Less income" },
	reyes = { strength = "Best as underdog", weakness = "Weaker when ahead" },
	strand = { strength = "Sees events early", weakness = "Weaker ads" },
	begay = { strength = "Cheap ground game", weakness = "Weaker rallies" },
}
Setup.NO_WEAKNESS = "No weakness"

-- The short strength and weakness of candidate `id` (falls back to the roster text).
function Setup.candidate(config: Config, id: string): { strength: string, weakness: string }
	local short = SHORT[id]
	if short then
		return short
	end
	local profile = Candidates.profile(config, id)
	return { strength = profile.perk, weakness = profile.drawback }
end

-- Every candidate that has short copy (the spec checks the roster is covered).
function Setup.hasShort(id: string): boolean
	return SHORT[id] ~= nil
end

-- "AP" is "actions" on every screen (docs/UI-STYLE.md §2.8).
local function plain(text: string): string
	return (string.gsub(text, "(%d+) AP", "%1 actions"))
end

-- The lines of a candidate's details sheet: the strength and weakness in full,
-- then the three numbers every candidate has.
function Setup.candidateDetails(config: Config, id: string): { string }
	local profile = Candidates.profile(config, id)
	local weakness = if profile.drawback == "None" then "None" else plain(profile.drawback)
	return {
		`{profile.archetype}`,
		`Strength: {plain(profile.perk)}.`,
		`Weakness: {weakness}.`,
		`Actions each week: {profile.apPerWeek}`,
		`Starting money: {Numbers.money(profile.startCash)}`,
		`Income: {Numbers.money(profile.passiveIncome)} a week`,
	}
end

-- "Dana" from "Dana Okafor".
function Setup.firstName(name: string): string
	return string.match(name, "^(%S+)") or name
end

-- ---------------------------------------------------------------- issues

-- "+41%": how much more a rally or ad on a platform issue earns in its states.
function Setup.boost(mult: number): string
	local percent = math.floor((mult - 1) * 100 + 0.5)
	return if percent >= 0 then `+{percent}%` else `{percent}%`
end

-- The small line on an issue chip: "154 votes · +41% boost", or two lines when
-- `narrow` (a phone's half-width chip).
function Setup.issueLine(votes: number?, mult: number?, narrow: boolean?): string
	if votes == nil then
		return ""
	end
	if mult == nil then
		return Setup.votes(votes)
	end
	local gap = if narrow then "\n" else " · "
	return `{Setup.votes(votes)}{gap}{Setup.boost(mult)} boost`
end

-- The "How issues work" sheet.
Setup.ISSUES_HELP = {
	"Every state cares most about two issues. They are drawn new each match.",
	"Votes: the electoral votes of the states that care about the issue.",
	"Boost: once the issue is on your platform, rallies and ads on it earn that much more in those states.",
	"Smaller issues get bigger boosts, so every pick can pay off. Pick the ones where you plan to fight.",
}

-- ---------------------------------------------------------------- the "now" line

Setup.NOW_CANDIDATE = "Pick your candidate"
Setup.NOW_CLAIMING = "Saving your pick…"
Setup.NOW_MAP = "Your color shows states that lean to you"

-- Select step 2: "Pick 3 issues", "Pick 2 more issues", then "All set? Lock in".
function Setup.nowIssues(picked: number, size: number): string
	local left = size - picked
	if left <= 0 then
		return "All set? Lock in"
	elseif picked == 0 then
		return `Pick {size} issues`
	end
	return if left == 1 then "Pick 1 more issue" else `Pick {left} more issues`
end

-- "Waiting for Rex…" once you are locked in.
function Setup.nowWaiting(opponent: string): string
	return `Waiting for {opponent}…`
end

-- The draft round's now line, before and after the first choice.
function Setup.nowDraft(kind: string, hasFirst: boolean): string
	if hasFirst then
		return "Add a backup, or Lock in"
	end
	return if kind == "Home" then "Pick your home state" else "Pick a battleground"
end

-- ---------------------------------------------------------------- draft

-- The round's kind as a short subtitle.
function Setup.roundKind(kind: string): string
	return if kind == "Home" then "Home state" else "Battleground"
end

-- "Ties go to you" / "Ties go to Rex": who wins a state you both want.
function Setup.priority(youHaveIt: boolean, opponent: string): string
	return if youHaveIt then "Ties go to you" else `Ties go to {opponent}`
end

-- "30 votes".
function Setup.votes(n: number): string
	return if n == 1 then "1 vote" else `{n} votes`
end

-- A state's lean as a pill: "+2 you", "+2 Rex" or "Even".
function Setup.lean(points: number, toYou: boolean?, opponent: string): string
	if toYou == nil or points <= 0 then
		return "Even"
	end
	return `+{points} {if toYou then "you" else opponent}`
end

-- The map reveal's line under the strongholds.
function Setup.strongholdsNote(config: Config): string
	return `Strongholds are the {config.STRONGHOLD_COUNT} states that lean most to each of you. They are ringed on the map.`
end

-- What a round's pick does, for the "How the draft works" sheet.
function Setup.roundRule(config: Config, kind: string): string
	if kind == "Home" then
		return `Home state: +{config.HOME_BONUS} support there (+{config.HOME_BONUS_BIG} in states with {config.BIG_STATE_EV}+ votes), and fundraisers there raise {Setup.boost(
			config.HOME_FUNDRAISE_MULT
		)} more all game.`
	end
	return `Battleground: the state loses its draft bonuses, and everything you do there counts {Setup.boost(
		config.BATTLEGROUND_MULT
	)} more. A home state can't be one.`
end

return Setup
