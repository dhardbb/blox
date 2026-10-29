--!strict
-- AnalyticsService funnels and custom events: where players drop off
-- (docs/DESIGN.md D-094). Server only; the client sends nothing for it.
--
-- Two funnels (AnalyticsService allows 10 per experience, steps 1-100):
--   * Onboarding (LogOnboardingFunnelStepEvent): a new player's path from the
--     first join through the tutorial to their first real match, the queue, a
--     rematch and the Daily Race (Analytics.Step). Logged only for players who
--     joined as new players from 0.17 on (their profile's stats.onboard), so
--     veterans never pollute it; a step is logged once, moving forward only
--     (Roblox counts skipped steps as done), and the step is saved.
--   * "Visit" (LogFunnelStepEvent with a funnel session id per visit): every
--     player's visit: in the lobby, looked for a game, played one, finished
--     it, played another, finished that.
-- Custom events (LogCustomEvent; 100 names allowed, this uses 6): MatchStarted,
-- MatchEnded (value: seconds), Landslide, QueueJoined, QueueLeft (value:
-- seconds waited), Rematch. Their custom fields (3 at most, string values,
-- Enum.AnalyticsCustomFieldKeys.CustomField01-03) are the mode, the bot level
-- or outcome, and the candidate: well under the 8,000 combinations allowed.
--
-- Every call is pcall'd and counted against MAX_PER_MINUTE (the documented
-- limit is 120 + 20 x CCU requests a minute; this stays under the base), so
-- analytics can never break a request or a match. In Studio the calls do
-- nothing visible (Roblox records events from live servers only).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent.DataService)
local Profile = require(ReplicatedStorage.Shared.Net.Profile)

local Analytics = {}

local MAX_PER_MINUTE = 100 -- AnalyticsService calls this server makes in a minute, at most

-- The onboarding funnel's steps (D-094). Never renumber a step: add new ones
-- at the end (Roblox charts a funnel by step number).
Analytics.Step = table.freeze({
	Joined = 1,
	TutorialStarted = 2,
	TutorialWeek1 = 3, -- weeks 1-4 of the tutorial: 3 + week - 1
	TutorialDone = 7,
	FirstMatch = 8, -- the first match that is not the tutorial (a bot or a person)
	FirstMatchDone = 9,
	Queued = 10, -- joined the public queue
	RatedDone = 11, -- finished a rated match
	Rematch = 12, -- asked for a rematch
	Daily = 13, -- started a Daily Race
})
local STEP_NAMES = {
	"Joined",
	"Tutorial started",
	"Tutorial week 1",
	"Tutorial week 2",
	"Tutorial week 3",
	"Tutorial week 4",
	"Tutorial finished",
	"First match started",
	"First match finished",
	"Joined the queue",
	"Finished a rated match",
	"Asked for a rematch",
	"Played the Daily Race",
}
Analytics.STEP_NAMES = table.freeze(STEP_NAMES)
local TUTORIAL_WEEKS = 4 -- the tutorial's weeks with a funnel step (D-080)

-- The visit funnel's steps.
Analytics.Visit = table.freeze({
	Lobby = 1,
	Looking = 2, -- queue, bot, Daily Race or a code
	Playing = 3,
	Finished = 4,
	Again = 5,
	FinishedAgain = 6,
})
local VISIT_NAMES = {
	"In the lobby",
	"Looked for a game",
	"Match started",
	"Match finished",
	"Played again",
	"Finished again",
}
Analytics.VISIT_FUNNEL = "Visit"

-- The service calls this uses (AnalyticsService has them). Tests supply their own.
export type Service = {
	LogOnboardingFunnelStepEvent: (
		self: any,
		player: Player,
		step: number,
		stepName: string?,
		customFields: any?
	) -> (),
	LogFunnelStepEvent: (
		self: any,
		player: Player,
		funnelName: string,
		funnelSessionId: string?,
		step: number?,
		stepName: string?,
		customFields: any?
	) -> (),
	LogCustomEvent: (self: any, player: Player, eventName: string, value: number?, customFields: any?) -> (),
}

export type Options = {
	service: Service?, -- default: game:GetService("AnalyticsService")
	clock: (() -> number)?, -- default: os.clock (the rate window)
}

local service: Service? = nil
local override: Service? = nil
local clock: () -> number = os.clock
local windowStart = -math.huge
local windowCalls = 0
local warnedLimit = false
local visits: { [string]: { session: string, step: number, matches: number } } = {}
local tutorialWeek: { [string]: number } = {} -- match id -> the last tutorial week logged

local function getService(): Service?
	if service then
		return service
	end
	if override then
		service = override
		return service
	end
	local ok, found = pcall(function(): any
		return game:GetService("AnalyticsService")
	end)
	if ok and found then
		service = found :: any
	end
	return service
end

-- Room for one more call this minute?
local function allowed(): boolean
	local t = clock()
	if t - windowStart >= 60 then
		windowStart = t
		windowCalls = 0
	end
	if windowCalls >= MAX_PER_MINUTE then
		if not warnedLimit then
			warnedLimit = true
			warn("[270] analytics: this server's call limit for the minute is reached; dropping events")
		end
		return false
	end
	windowCalls += 1
	return true
end

local function playerOf(id: string): Player?
	local userId = tonumber(id)
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

-- Custom fields as AnalyticsService takes them: CustomField01-03, string values.
local function fields(one: string?, two: string?, three: string?): { [string]: string }
	local out: { [string]: string } = {}
	local values = { one, two, three }
	local keys = { "CustomField01", "CustomField02", "CustomField03" }
	for k = 1, 3 do
		local value = values[k]
		if value ~= nil then
			local key = (Enum.AnalyticsCustomFieldKeys :: any)[keys[k]].Name
			out[key] = string.sub(value, 1, 50)
		end
	end
	return out
end

local function call(fn: (Service, Player) -> (), id: string)
	local player = playerOf(id)
	local s = getService()
	if player == nil or s == nil or not allowed() then
		return
	end
	local ok, err = pcall(function(): string?
		fn(s :: Service, player :: Player)
		return nil
	end)
	if not ok then
		warn(`[270] analytics call failed: {err}`)
	end
end

-- A custom event for player `id` (one of the six names above).
function Analytics.event(id: string, name: string, value: number?, one: string?, two: string?, three: string?)
	call(function(s: Service, player: Player)
		s:LogCustomEvent(player, name, value or 1, fields(one, two, three))
	end, id)
end

-- The onboarding funnel: logs `step` for a player who is in it and has not
-- reached it yet, and saves it. Only for a loaded profile (never an offline write).
function Analytics.onboard(id: string, step: number)
	local profile = DataService.profile(id)
	local stats = if profile then profile.stats else nil
	local at = if stats then stats.onboard else nil
	if profile == nil or at == nil or step <= at or step > #STEP_NAMES then
		return
	end
	if stats and stats.v > Profile.STATS_VERSION then
		return
	end
	DataService.update(id, function(saved: Profile.Profile): Profile.Profile
		return Profile.withOnboard(saved, step, os.time())
	end)
	call(function(s: Service, player: Player)
		s:LogOnboardingFunnelStepEvent(player, step, STEP_NAMES[step])
	end, id)
end

-- The visit funnel: logs `step` once per visit, moving forward only.
function Analytics.visit(id: string, step: number)
	local visit = visits[id]
	if visit == nil or step <= visit.step then
		return
	end
	visit.step = step
	call(function(s: Service, player: Player)
		s:LogFunnelStepEvent(player, Analytics.VISIT_FUNNEL, visit.session, step, VISIT_NAMES[step])
	end, id)
end

-- A player's profile loaded: their visit begins, and a brand-new player
-- (nothing played, no tutorial, no onboarding yet) starts the onboarding funnel.
function Analytics.joined(id: string)
	if visits[id] == nil then
		local ok, guid = pcall(function(): string
			return HttpService:GenerateGUID(false)
		end)
		visits[id] = { session = if ok then guid else `{id}-{os.time()}`, step = 0, matches = 0 }
		Analytics.visit(id, Analytics.Visit.Lobby)
	end
	local profile = DataService.profile(id)
	if profile == nil or not Profile.needsTutorial(profile) then
		return
	end
	if profile.stats and profile.stats.onboard ~= nil then
		return
	end
	DataService.update(id, function(saved: Profile.Profile): Profile.Profile
		return Profile.withOnboard(saved, Analytics.Step.Joined, os.time())
	end)
	call(function(s: Service, player: Player)
		s:LogOnboardingFunnelStepEvent(player, Analytics.Step.Joined, STEP_NAMES[Analytics.Step.Joined])
	end, id)
end

function Analytics.left(id: string)
	visits[id] = nil
end

-- What a match looks like to analytics.
export type MatchFacts = {
	id: string, -- match id
	mode: string, -- Net/MatchRecord.Mode
	level: string?, -- the bot's level
	humans: { string },
	candidates: { [string]: string }, -- player id -> candidate id (when known)
	tutorial: boolean,
}

-- A match started.
function Analytics.matchStarted(facts: MatchFacts)
	for _, id in facts.humans do
		Analytics.event(id, "MatchStarted", 1, facts.mode, facts.level or "Human")
		if facts.tutorial then
			Analytics.onboard(id, Analytics.Step.TutorialStarted)
		else
			Analytics.onboard(id, Analytics.Step.FirstMatch)
		end
		if facts.mode == "Daily" then
			Analytics.onboard(id, Analytics.Step.Daily)
		end
		local visit = visits[id]
		if visit then
			visit.matches += 1
			Analytics.visit(id, if visit.matches == 1 then Analytics.Visit.Playing else Analytics.Visit.Again)
		end
	end
end

-- The tutorial reached week `week` (MatchService calls this as weeks open).
function Analytics.tutorialWeek(matchId: string, humans: { string }, week: number)
	if week < 1 or week > TUTORIAL_WEEKS or (tutorialWeek[matchId] or 0) >= week then
		return
	end
	tutorialWeek[matchId] = week
	for _, id in humans do
		Analytics.onboard(id, Analytics.Step.TutorialWeek1 + week - 1)
	end
end

-- A match ended. `outcomes`: player id -> "Won" | "Lost" | "None" (abandoned).
function Analytics.matchEnded(
	facts: MatchFacts,
	reason: string,
	seconds: number,
	outcomes: { [string]: string },
	rated: boolean,
	landslideBy: string?
)
	tutorialWeek[facts.id] = nil
	for _, id in facts.humans do
		local outcome = outcomes[id] or "None"
		Analytics.event(id, "MatchEnded", math.max(0, math.floor(seconds)), facts.mode, reason, outcome)
		if landslideBy == id then
			Analytics.event(id, "Landslide", 1, facts.mode, facts.level or "Human", facts.candidates[id])
		end
		if reason ~= "Abandoned" then
			if facts.tutorial then
				Analytics.onboard(id, Analytics.Step.TutorialDone)
			else
				Analytics.onboard(id, Analytics.Step.FirstMatchDone)
			end
			if rated then
				Analytics.onboard(id, Analytics.Step.RatedDone)
			end
		end
		local visit = visits[id]
		if visit then
			Analytics.visit(
				id,
				if visit.matches <= 1 then Analytics.Visit.Finished else Analytics.Visit.FinishedAgain
			)
		end
	end
end

-- The player asked for a game (queue, bot, Daily Race, a code).
function Analytics.looking(id: string)
	Analytics.visit(id, Analytics.Visit.Looking)
end

function Analytics.queued(id: string)
	Analytics.event(id, "QueueJoined", 1)
	Analytics.onboard(id, Analytics.Step.Queued)
	Analytics.looking(id)
end

-- Left the queue after `seconds`, by `how` ("Matched", "Left", "Bot").
function Analytics.unqueued(id: string, seconds: number, how: string)
	Analytics.event(id, "QueueLeft", math.max(0, math.floor(seconds)), how)
end

function Analytics.rematch(id: string, mode: string)
	Analytics.event(id, "Rematch", 1, mode)
	Analytics.onboard(id, Analytics.Step.Rematch)
end

-- Sets the service (tests). Call once at start.
function Analytics.start(options: Options?)
	if options then
		override = options.service
		if options.clock then
			clock = options.clock
		end
	end
end

return Analytics
