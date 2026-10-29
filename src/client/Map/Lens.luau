--!strict
-- Map lenses (D-046, docs/UI-STYLE.md §4.6): what the map shows at each
-- state's label, one layer at a time, so the map stays quiet (who leads by fill
-- color) and the details live in the state card. One mark per state, except
-- Polls (D-070). The fill by public-poll leader is the same in every lens;
-- screens keep their event and stance badges (the Tags layer) and the
-- candidate pins in every lens.
--
--   EV      "Votes": the state's electoral votes on a dark plate; on a
--           battleground "★13", outlined in white (good news, never orange,
--           and never a white fill, which means "selected": D-056)
--   Issues  the state's top issue as its symbol (D-076; the short code while
--           the image is missing): the first one on your platform (filled in
--           your color), else its first top issue. The legend row names the
--           symbols on the map (yours first) and the Map key lists all eight
--   Polls   the public-poll lead ("+3") on a plate filled in the leader's
--           color, "tie", or the lean before the first poll ("~+2", the
--           leader's readable text color: a lean, not a poll). Under it, a
--           small row (D-070): ▲ in the momentum leader's color (▲▲ for a
--           lead of Lens.STRONG or more: their support drifts up each week),
--           your ground-game units as filled dots in your color, and the
--           opponent's as hollow dots, only as your internal polls saw them
--           (View.scouted, D-049). Polls is the lens for "where is it moving
--           and who is working it", so it may carry three marks; the map's
--           legend row (Lens.mapLegend) says what they mean. Your internal
--           poll numbers stay on the state card (Details)
--   Money   what one more fundraiser would raise there this week
--           (Explain.action, the state card's number) as dollars on every
--           state ("$6.1", D-092: the user asked for the values back after
--           D-079's coins); the Lens.MONEY_TOP richest pools in gold; dim when
--           your plan already empties the pool
--
-- Close (D-079): a filter on top of any lens, remembered like the lens. On, a
-- state whose public-poll lead (or lean, before the first poll) is more than
-- Lens.CLOSE points is quiet: its fill at 40 % and no value, so the map shows
-- only the states still in play.
--
-- Reads only the player's own View (and, for Money, their drafted plan): public
-- momentum, your own ground game and your own scouting. The lens choice is
-- remembered for the session: a module-level value, so every screen that mounts
-- a map starts on the lens the player last picked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Colors = require(Shared.UI.Colors)
local ConfigModule = require(Shared.Sim.Config)
local Explain = require(Shared.UI.Explain)
local IssueMap = require(Shared.Sim.IssueMap)
local Issues = require(Shared.Sim.Issues)
local Numbers = require(Shared.UI.Numbers)
local PlanDraft = require(Shared.UI.PlanDraft)
local StateData = require(Shared.Sim.StateData)
local ViewModule = require(Shared.Sim.View)

local IssueIcons = require(script.Parent.Parent.UI.IssueIcons)
local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.MapInterface)

type View = ViewModule.View
type StateView = ViewModule.StateView
type Part = MapInterface.LensPart
type Line = MapInterface.LensLine
type LegendItem = MapInterface.LegendItem

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
Lens.MOMENTUM = 0.05 -- a momentum lead under this shows no chevron (nobody drifts)
Lens.STRONG = 2 -- a momentum lead of this much or more shows ▲▲
Lens.MONEY_TOP = 8 -- Money shows this many of the richest pools in gold (ties by votes)
Lens.CLOSE = 8 -- points: the Close filter keeps states within this lead
local COIN = Kit.color(Colors.player.Amber) -- the Money lens's gold (the event strip's money plate)

-- Short codes for the issues (UI/IssueIcons): what the map shows while an
-- issue's symbol is missing. An issue without one shows its first three letters.
Lens.ISSUE_CODE = (function(): { [string]: string }
	local codes: { [string]: string } = {}
	for issue, icon in IssueIcons.icons do
		codes[issue] = icon.code
	end
	return table.freeze(codes)
end)()

-- ---------------------------------------------------------------- session memory

local current: Id = "EV"
local closeOnly = false

function Lens.current(): Id
	return current
end

function Lens.set(id: Id)
	if Lens.LABEL[id] ~= nil then
		current = id
	end
end

-- The Close filter (remembered for the session, like the lens).
function Lens.close(): boolean
	return closeOnly
end

function Lens.setClose(on: boolean)
	closeOnly = on
end

-- One short line on how to read the lens, in plain words (fits beside the
-- chips on a phone). The Campaign screen's "Map key" sheet says more.
function Lens.legend(_config: ConfigModule.Config, id: Id): string
	if id == "Issues" then
		return "Top issue · filled = one of yours"
	elseif id == "Polls" then
		return `Poll lead · {Kit.glyph.up} momentum · {Kit.glyph.bullet} ground game`
	elseif id == "Money" then
		return `$ one fundraiser raises · gold: the {Lens.MONEY_TOP} richest`
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
	return Kit.issueCode(issue)
end

-- The issue each state shows in the Issues lens: the first top issue on your
-- platform, else its first; nil for a state without top issues.
function Lens.shownIssue(view: View, s: StateView): (string?, boolean)
	local platform = view.players[view.you].platform or {}
	local issues = Lens.issuesOf(view, s)
	for _, issue in issues do
		if table.find(platform, issue :: any) ~= nil then
			return issue, true
		end
	end
	return issues[1], false
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
	local issue, yours = Lens.shownIssue(view, s)
	if issue == nil then
		return { parts = {} }
	end
	if yours then
		return {
			parts = {
				{
					text = Lens.issueCode(issue),
					icon = issue,
					color = colorOf(view, view.you),
					filled = true,
				},
			},
		}
	end
	return { parts = { { text = Lens.issueCode(issue), icon = issue } } }
end

-- The momentum leader's color and whether the lead is strong, or nil.
function Lens.momentumOf(view: View, s: StateView): (Color3?, boolean)
	local leader, lead = leaderOf(s.momentum)
	if leader == nil or lead < Lens.MOMENTUM then
		return nil, false
	end
	return colorOf(view, leader), lead >= Lens.STRONG
end

-- Ground-game pips: yours (filled), then each opponent's as your polls saw it (hollow).
function Lens.pipsOf(view: View, s: StateView): { MapInterface.Pips }
	local pips: { MapInterface.Pips } = {}
	if s.gotv > 0 then
		table.insert(pips, { count = s.gotv, color = colorOf(view, view.you) })
	end
	local scout = Explain.scoutOf(view, s.id)
	if scout then
		for p, units in scout.gotv do
			if p ~= view.you and units > 0 then
				table.insert(pips, { count = units, color = colorOf(view, p), hollow = true })
			end
		end
	end
	return pips
end

local function pollsLine(ctx: Context, s: StateView): Line
	local view = ctx.view
	local parts: { Part } = {}
	if s.poll then
		parts = { leadPart(view, s.poll.support, "") }
	elseif s.leanTo and s.lean > 0 then
		-- Before the first poll: the lean, marked "~".
		parts = {
			{ text = `~+{math.floor(s.lean + 0.5)}`, color = Kit.textColor(colorOf(view, s.leanTo)) },
		}
	end
	local momentum, strong = Lens.momentumOf(view, s)
	local pips = Lens.pipsOf(view, s)
	return {
		parts = parts,
		momentum = momentum,
		momentumStrong = if momentum and strong then true else nil,
		pips = if #pips > 0 then pips else nil,
	}
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
			{
				text = Numbers.money(money),
				-- A phone's map drops the "$" (the lens and its legend say it is money).
				short = string.gsub(Numbers.money(money), "%$", ""),
				color = if drained then Kit.colors.muted else Kit.colors.text,
			},
		},
		dim = drained,
	}
end

-- Money shows every pool's dollars and the MONEY_TOP richest in gold
-- (D-092; before, D-079 drew 1 to 3 coins on those 8 and no dollars).
local function topPools(ctx: Context, lines: { [string]: Line })
	local ids: { string } = {}
	local amount: { [string]: number } = {}
	for _, s in ctx.view.states do
		amount[s.id] = Lens.fundraise(ctx, s.id)
		if amount[s.id] >= Lens.DRAINED then
			table.insert(ids, s.id)
		end
	end
	table.sort(ids, function(a: string, b: string): boolean
		if math.abs(amount[a] - amount[b]) > 1e-9 then
			return amount[a] > amount[b]
		end
		local ea, eb = StateData.byId[a].ev, StateData.byId[b].ev
		if ea ~= eb then
			return ea > eb
		end
		return a < b
	end)
	local keep: { [string]: boolean } = {}
	for k = 1, math.min(Lens.MONEY_TOP, #ids) do
		keep[ids[k]] = true
	end
	for id, line in lines do
		local part = line.parts[1]
		if keep[id] and part then
			part.color = Kit.textColor(COIN)
		end
	end
end

local LINES: { [Id]: (Context, StateView) -> Line } = {
	EV = evLine,
	Issues = issuesLine,
	Polls = pollsLine,
	Money = moneyLine,
}

-- The map's legend row for lens `id` (D-070): Polls explains its extra marks;
-- the other lenses need none (their one mark is in Lens.legend and the Map key).
function Lens.mapLegend(ctx: Context, id: Id): { LegendItem }?
	if id == "Issues" then
		return Lens.issueLegend(ctx.view)
	elseif id ~= "Polls" then
		return nil
	end
	local view = ctx.view
	-- "▲ momentum   ● ○ ground game": the dots in your color (filled) and the
	-- opponent's (hollow); the Map key says the hollow ones are what your polls saw.
	local items: { LegendItem } = {
		{ mark = "up", text = "momentum" },
		-- ▲▲: a momentum lead of Lens.STRONG or more (D-079).
		-- (Dropped first on a phone's narrow strip, D-092; the Map key still says it.)
		{ mark = "none", text = `{Kit.glyph.up}{Kit.glyph.up} strong`, color = Kit.colors.muted, drop = 1 },
		{ mark = "pip", color = colorOf(view, view.you), text = "" },
	}
	local rival = nil
	for p in view.players do
		if p ~= view.you then
			rival = p
			break
		end
	end
	table.insert(items, {
		mark = "hollow",
		color = if rival then colorOf(view, rival) else Kit.colors.muted,
		text = "ground game",
	})
	return items
end

-- The Issues lens's legend row (D-076): each symbol on the map with its name,
-- your platform's first (in your color, always shown), then the others in
-- Issues order (dropped first on a narrow map). Nil when no state shows one.
function Lens.issueLegend(view: View): { LegendItem }?
	local shown: { [string]: boolean } = {}
	for _, s in view.states do
		local issue = Lens.shownIssue(view, s)
		if issue then
			shown[issue] = true
		end
	end
	local items: { LegendItem } = {}
	local platform: { string } = (view.players[view.you].platform or {}) :: any
	for _, issue in platform do
		if shown[issue] then
			table.insert(items, {
				mark = "issue",
				issue = issue,
				color = colorOf(view, view.you),
				text = Kit.issueName(issue),
			})
			shown[issue] = nil
		end
	end
	for _, issue in Issues.list do
		if shown[issue] then
			table.insert(items, { mark = "issue", issue = issue, text = Kit.issueName(issue), drop = 1 })
		end
	end
	return if #items > 0 then items else nil
end

-- The public lead (or lean, before the first poll) in points, or nil for a
-- state nobody leads yet.
function Lens.leadOf(s: StateView): number?
	if s.poll then
		local _, lead = leaderOf(s.poll.support)
		return lead
	elseif s.leanTo and s.lean > 0 then
		return s.lean
	end
	return nil
end

-- Is `s` close enough for the Close filter (within Lens.CLOSE points, or not led)?
function Lens.isClose(s: StateView): boolean
	local lead = Lens.leadOf(s)
	return lead == nil or lead <= Lens.CLOSE
end

-- Every state's line in lens `id`, keyed by state id. With `close` (the Close
-- filter, default Lens.close()), a safe state's line is quiet and empty.
function Lens.lines(id: Id, ctx: Context, close: boolean?): { [string]: Line }
	local build = LINES[id] or evLine
	local out: { [string]: Line } = {}
	for _, s in ctx.view.states do
		out[s.id] = build(ctx, s)
	end
	if id == "Money" then
		topPools(ctx, out)
	end
	local filter = if close == nil then closeOnly else close
	if filter then
		for _, s in ctx.view.states do
			if not Lens.isClose(s) then
				out[s.id] = { parts = {}, quiet = true }
			end
		end
	end
	return out
end

return Lens
