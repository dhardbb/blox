--!strict
-- Map lenses (D-046, docs/UI-STYLE.md §4.6): what the map shows inside each
-- state's circle, under its code, one layer at a time and one mark per state, so
-- the map stays quiet (who leads by fill color) and the details live in the
-- state card. The fill by public-poll leader is the same in every lens; screens
-- keep their event and stance badges (the Tags layer).
--
--   EV      "Votes": the state's electoral votes on a dark plate; on a
--           battleground "★13", outlined in white (good news, never orange,
--           and never a white fill, which means "selected": D-056)
--   Issues  the state's top issue as a short code: the first one on your
--           platform (filled in your color), else its first top issue
--   Polls   the public-poll lead ("+3") on a plate filled in the leader's
--           color, "tie", or the lean before the first poll ("~+2", the
--           leader's readable text color: a lean, not a poll). Your internal
--           polls, momentum and ground game are on the state card (Details)
--   Money   what one more fundraiser there would raise this week, from
--           Explain.action (the state card's number); dim when your plan
--           already empties the pool
--
-- Reads only the player's own View (and, for Money, their drafted plan). The
-- lens choice is remembered for the session: a module-level value, so every
-- screen that mounts a map starts on the lens the player last picked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local ConfigModule = require(Shared.Sim.Config)
local Explain = require(Shared.UI.Explain)
local IssueMap = require(Shared.Sim.IssueMap)
local Numbers = require(Shared.UI.Numbers)
local PlanDraft = require(Shared.UI.PlanDraft)
local StateData = require(Shared.Sim.StateData)
local ViewModule = require(Shared.Sim.View)

local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.MapInterface)

type View = ViewModule.View
type StateView = ViewModule.StateView
type Part = MapInterface.LensPart
type Line = MapInterface.LensLine

export type Id = "EV" | "Issues" | "Polls" | "Money"

-- What a lens needs to draw: the config, the View, and the plan being drafted
-- (Campaign; nil elsewhere).
export type Context = {
	config: ConfigModule.Config,
	view: View,
	draft: PlanDraft.Draft?,
}

local Lens = {}

Lens.ORDER = table.freeze({ "EV", "Issues", "Polls", "Money" } :: { Id })
Lens.LABEL =
	table.freeze({ EV = "Votes", Issues = "Issues", Polls = "Polls", Money = "Money" } :: { [Id]: string })

-- Display only (UI numbers, not gameplay).
Lens.TIE = 0.5 -- a public-poll lead under this many points reads "tie"
Lens.DRAINED = 0.05 -- $ a fundraiser would still raise: under this, the pool is spent

-- Short codes for the issue chips. An issue without one shows its first three letters.
Lens.ISSUE_CODE = table.freeze({
	Jobs = "JOB",
	Health = "HLT",
	Schools = "SCH",
	Environment = "ENV",
	Safety = "SAF",
	Transit = "TRN",
	Technology = "TEC",
	Farms = "FRM",
} :: { [string]: string })

-- ---------------------------------------------------------------- session memory

local current: Id = "EV"

function Lens.current(): Id
	return current
end

function Lens.set(id: Id)
	if Lens.LABEL[id] ~= nil then
		current = id
	end
end

-- One short line on how to read the lens, in plain words (fits beside the
-- chips on a phone). The Campaign screen's "Map key" sheet says more.
function Lens.legend(_config: ConfigModule.Config, id: Id): string
	if id == "Issues" then
		return "Top issue · filled = one of yours"
	elseif id == "Polls" then
		return "Who leads the poll, by how much"
	elseif id == "Money" then
		return "What one more fundraiser raises"
	end
	return `Votes · {Kit.STAR} = battleground`
end

-- ---------------------------------------------------------------- helpers

local function colorOf(view: View, p: number): Color3
	local player = view.players[p]
	return if player and player.color then Kit.playerColor(view, p) else Kit.colors.accent
end

-- The leader of `values` by index and their lead over the next best (0 on a tie).
local function leaderOf(values: { number }): (number?, number)
	local best, first, second = nil, -math.huge, -math.huge
	for p, value in values do
		if value > first then
			best, first, second = p, value, first
		elseif value > second then
			second = value
		end
	end
	if best == nil then
		return nil, 0
	end
	return best, if second == -math.huge then first else first - second
end

-- "+3" on a plate filled in the leader's color (the map makes its text
-- readable), "tie" when under Lens.TIE; `prefix` marks the kind.
local function leadPart(view: View, support: { number }, prefix: string): Part
	local leader, lead = leaderOf(support)
	if leader == nil or lead < Lens.TIE then
		return { text = `{prefix}tie`, color = Kit.colors.muted }
	end
	return { text = `{prefix}+{math.floor(lead + 0.5)}`, color = colorOf(view, leader), filled = true }
end

-- The state's top issues this match, from the View's issue map (D-047).
function Lens.issuesOf(view: View, s: StateView): { string }
	return IssueMap.of(view.issueMap, s.id) :: { any }
end

function Lens.issueCode(issue: string): string
	return Lens.ISSUE_CODE[issue] or string.upper(string.sub(issue, 1, 3))
end

-- ---------------------------------------------------------------- one line per lens

local function evLine(_ctx: Context, s: StateView): Line
	local record = StateData.byId[s.id]
	local votes = if record then tostring(record.ev) else "?"
	return {
		parts = {
			{
				text = if s.battleground then Kit.STAR .. votes else votes,
				-- A battleground is good news (D-056): a star and a white outline,
				-- never orange, never a white fill, which means "selected" (D-058).
				outlined = if s.battleground then true else nil,
			},
		},
	}
end

-- The state's top issue to show: the first one on your platform, else its first.
local function issuesLine(ctx: Context, s: StateView): Line
	local view = ctx.view
	local platform = view.players[view.you].platform or {}
	local issues = Lens.issuesOf(view, s)
	for _, issue in issues do
		if table.find(platform, issue :: any) ~= nil then
			return {
				parts = { { text = Lens.issueCode(issue), color = colorOf(view, view.you), filled = true } },
			}
		end
	end
	local first = issues[1]
	return { parts = if first then { { text = Lens.issueCode(first) } } else {} }
end

local function pollsLine(ctx: Context, s: StateView): Line
	local view = ctx.view
	if s.poll then
		return { parts = { leadPart(view, s.poll.support, "") } }
	elseif s.leanTo and s.lean > 0 then
		-- Before the first poll: the lean, marked "~".
		return {
			parts = {
				{ text = `~+{math.floor(s.lean + 0.5)}`, color = Kit.textColor(colorOf(view, s.leanTo)) },
			},
		}
	end
	return { parts = {} }
end

-- What one more fundraiser here would raise (Explain's number), from the plan so far.
function Lens.fundraise(ctx: Context, id: string): number
	local draft = ctx.draft or PlanDraft.new()
	return Explain.action(ctx.config, ctx.view, draft, id, "Fundraise").money or 0
end

local function moneyLine(ctx: Context, s: StateView): Line
	local money = Lens.fundraise(ctx, s.id)
	local drained = money < Lens.DRAINED
	return {
		parts = {
			{ text = Numbers.money(money), color = if drained then Kit.colors.muted else Kit.colors.good },
		},
		dim = drained,
	}
end

local LINES: { [Id]: (Context, StateView) -> Line } = {
	EV = evLine,
	Issues = issuesLine,
	Polls = pollsLine,
	Money = moneyLine,
}

-- Every state's line in lens `id`, keyed by state id.
function Lens.lines(id: Id, ctx: Context): { [string]: Line }
	local build = LINES[id] or evLine
	local out: { [string]: Line } = {}
	for _, s in ctx.view.states do
		out[s.id] = build(ctx, s)
	end
	return out
end

return Lens
