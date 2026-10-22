--!strict
-- The candidate roster as data. Each candidate is the default profile (built from
-- Config) plus a few overrides, so a ninth candidate is a data change, not code.
-- Values are revision 2 (docs/DESIGN.md D-011) as retuned by the first balance pass
-- (D-022, D-023) and the second (D-035, D-037). Names are fictional placeholders.

local ConfigModule = require("./Config")

type Config = ConfigModule.Config

-- Everything about a candidate the simulation reads. Multipliers default to 1.
export type Profile = {
	id: string,
	name: string,
	archetype: string,
	perk: string,
	drawback: string,
	apPerWeek: number,
	startCash: number,
	passiveIncome: number,
	rallySupport: number, -- base support per rally
	rallyMult: number,
	fundraiseMult: number, -- applied after the pool cap; the bonus does not drain the pool
	mediaCost: number,
	mediaMult: number, -- effect of media buys (positive and attack)
	mediaSaturation: number, -- value of each extra buy in the same state and week
	freePolls: number, -- free single-state internal polls per week
	eventPreview: number, -- weeks ahead this candidate sees the event deck (0 = only this week's event)
	gotvCost: number,
	gotvMaxUnits: number,
	momentumGainMult: number,
	momentumDecay: number, -- share of momentum kept each week
	underdogScale: number, -- scales the bonus part of underdog multipliers (2 = doubled)
	frontrunnerEV: number?, -- when leading by this much projected EV, the frontrunner mults apply
	frontrunnerRallyMult: number,
	frontrunnerFundMult: number,
	debateStat: number,
	debatePrep: number,
}

type Entry = {
	id: string,
	name: string,
	archetype: string,
	perk: string,
	drawback: string,
	overrides: { [string]: number },
}

local ROSTER: { Entry } = {
	{
		id = "okafor",
		name = "Dana Okafor",
		archetype = "The Fundraiser",
		perk = "Fundraisers yield +25%",
		drawback = "None",
		overrides = { fundraiseMult = 1.25 },
	},
	{
		id = "calloway",
		name = "Rex Calloway",
		archetype = "The Barnstormer",
		perk = "4 AP per week",
		drawback = "Rallies +2.3 instead of +3.0; media buys cost $4",
		overrides = { apPerWeek = 4, rallySupport = 2.3, mediaCost = 4 },
	},
	{
		id = "venkat",
		name = "Priya Venkat",
		archetype = "The Ad Wizard",
		perk = "Media buys cost $2; repeat buys keep 65% of their value",
		drawback = "Income $2 a week instead of $4",
		overrides = { mediaCost = 2, mediaSaturation = 0.65, passiveIncome = 2 },
	},
	{
		id = "hale",
		name = "Marcus Hale",
		archetype = "The Debater",
		perk = "7 debate prep points instead of 6",
		drawback = "Starts with no money",
		overrides = { debatePrep = 7, startCash = 0 },
	},
	{
		id = "alvarado",
		name = "June Alvarado",
		archetype = "The Insider",
		perk = "Starts with $20",
		drawback = "Income $3.75 a week instead of $4",
		overrides = { startCash = 20, passiveIncome = 3.75 },
	},
	{
		id = "reyes",
		name = "Tomas Reyes",
		archetype = "The Insurgent",
		perk = "Underdog bonuses doubled; momentum gained +65%",
		drawback = "Momentum fades faster; weaker rallies and fundraisers while far ahead",
		overrides = {
			underdogScale = 2,
			momentumGainMult = 1.65,
			momentumDecay = 0.25,
			frontrunnerEV = 40,
			frontrunnerRallyMult = 0.9,
			frontrunnerFundMult = 0.85,
		},
	},
	{
		id = "strand",
		name = "Helen Strand",
		archetype = "The Pollster",
		perk = "Sees next week's event a week early; two free internal polls a week",
		drawback = "Media buys -10%",
		overrides = { eventPreview = 1, freePolls = 2, mediaMult = 0.9 },
	},
	{
		id = "begay",
		name = "Walt Begay",
		archetype = "The Organizer",
		perk = "Ground game costs $1 per unit and caps at 6 per state",
		drawback = "Rallies +2.9 instead of +3.0",
		overrides = { gotvCost = 1, gotvMaxUnits = 6, rallySupport = 2.9 },
	},
}

local Candidates = {}

-- Player colors, picked separately from the candidate. None of them pairs into a
-- real party's colors.
Candidates.colors = table.freeze({ "Crimson", "Cobalt", "Emerald", "Amber", "Violet", "Teal" })

Candidates.ids = table.freeze((function()
	local ids = {}
	for i, entry in ROSTER do
		ids[i] = entry.id
	end
	return ids
end)())

local byId: { [string]: Entry } = {}
for _, entry in ROSTER do
	byId[entry.id] = entry
end

function Candidates.exists(id: string): boolean
	return byId[id] ~= nil
end

-- Full profile for a candidate under a given config.
function Candidates.profile(config: Config, id: string): Profile
	local entry = byId[id]
	assert(entry, `unknown candidate {id}`)
	local profile: Profile = {
		id = entry.id,
		name = entry.name,
		archetype = entry.archetype,
		perk = entry.perk,
		drawback = entry.drawback,
		apPerWeek = config.AP_PER_WEEK,
		startCash = config.START_CASH,
		passiveIncome = config.PASSIVE_INCOME,
		rallySupport = config.RALLY_SUPPORT,
		rallyMult = 1,
		fundraiseMult = 1,
		mediaCost = config.MEDIA_COST,
		mediaMult = 1,
		mediaSaturation = config.MEDIA_SATURATION,
		freePolls = 0,
		eventPreview = 0,
		gotvCost = config.GOTV_COST,
		gotvMaxUnits = config.GOTV_MAX_UNITS,
		momentumGainMult = 1,
		momentumDecay = config.MOMENTUM_DECAY,
		underdogScale = 1,
		frontrunnerEV = nil,
		frontrunnerRallyMult = 1,
		frontrunnerFundMult = 1,
		debateStat = config.DEBATE_STAT,
		debatePrep = config.DEBATE_PREP,
	}
	local writable = profile :: any
	for key, value in entry.overrides do
		assert(writable[key] ~= nil or key == "frontrunnerEV", `unknown profile field {key} on {id}`)
		writable[key] = value
	end
	return table.freeze(profile)
end

return table.freeze(Candidates)
