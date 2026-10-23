--!strict
-- Map lenses (D-046): what the map shows under each state's label, one layer at
-- a time, so the default map stays quiet (who leads by fill color, EV) and the
-- details live one tap away. The fill by public-poll leader is the same in
-- every lens; screens keep their event and stance badges (the Tags layer).
--
--   EV      electoral votes; "B" on a battleground
--   Issues  the state's top issues as short codes; yours (your platform) filled
--   Polls   the public-poll lead in the leader's color; "i+5" your internal poll
--           there; a momentum arrow; then Lens.pollDetails (your ground game "G2")
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

-- An extra pill for a state in the Polls lens, or nil for none.
export type Detail = (ctx: Context, s: StateView) -> Part?

local Lens = {}

Lens.ORDER = table.freeze({ "EV", "Issues", "Polls", "Money" } :: { Id })
Lens.LABEL = table.freeze({ EV = "EV", Issues = "Issues", Polls = "Polls", Money = "$" } :: { [Id]: string })

-- Display only (UI numbers, not gameplay).
Lens.MOMENTUM_ARROW = 0.5 -- momentum lead that earns the leader a ▲ (as the map had before D-046)
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

-- One short caption line on how to read the lens (fits beside the chips on a phone).
function Lens.legend(config: ConfigModule.Config, id: Id): string
	if id == "Issues" then
		return "Top issues · filled = on your platform"
	elseif id == "Polls" then
		return "Poll lead · i = your internal poll · ▲ momentum · G = ground game"
	elseif id == "Money" then
		return "One more fundraiser there this week · dim = pool used up"
	end
	return `Number = electoral votes · B = battleground (×{config.BATTLEGROUND_MULT})`
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

-- "+3" in the leader's color, "tie" when under Lens.TIE; `prefix` marks the kind.
local function leadPart(view: View, support: { number }, prefix: string): Part
	local leader, lead = leaderOf(support)
	if leader == nil or lead < Lens.TIE then
		return { text = `{prefix}tie`, color = Kit.colors.muted }
	end
	return { text = `{prefix}+{math.floor(lead + 0.5)}`, color = colorOf(view, leader) }
end

-- The state's top issues: from the View when it carries them (issues per match),
-- else the static state data.
function Lens.issuesOf(s: StateView): { string }
	local fromView = (s :: any).issues
	if type(fromView) == "table" then
		return fromView
	end
	local record = StateData.byId[s.id]
	return if record then record.issues :: { any } else {}
end

function Lens.issueCode(issue: string): string
	return Lens.ISSUE_CODE[issue] or string.upper(string.sub(issue, 1, 3))
end

-- ---------------------------------------------------------------- one line per lens

local function evLine(_ctx: Context, s: StateView): Line
	local record = StateData.byId[s.id]
	local parts: { Part } = { { text = if record then tostring(record.ev) else "?" } }
	if s.battleground then
		table.insert(parts, { text = "B", color = Kit.colors.accent })
	end
	return { parts = parts }
end

local function issuesLine(ctx: Context, s: StateView): Line
	local view = ctx.view
	local platform = view.players[view.you].platform or {}
	local mine = colorOf(view, view.you)
	local parts: { Part } = {}
	for _, issue in Lens.issuesOf(s) do
		local ours = table.find(platform, issue :: any) ~= nil
		table.insert(parts, {
			text = Lens.issueCode(issue),
			color = if ours then mine else Kit.colors.text,
			filled = ours,
		})
	end
	return { parts = parts }
end

local function internalOf(view: View, id: string): { number }?
	for _, poll in view.internalPolls do
		if poll.state == id then
			return poll.support
		end
	end
	return nil
end

local function momentumPart(view: View, s: StateView): Part?
	local leader, lead = leaderOf(s.momentum)
	if leader == nil or lead < Lens.MOMENTUM_ARROW then
		return nil
	end
	return { text = "▲", color = colorOf(view, leader) }
end

-- Your ground game here: placed units plus the ones in the plan you are drafting.
local function groundGame(ctx: Context, s: StateView): Part?
	local units = s.gotv
	local draft = ctx.draft
	if draft then
		for _, action in draft.actions do
			if action.kind == "Gotv" and action.state == s.id then
				units += action.units or 0
			end
		end
	end
	return if units > 0 then { text = `G{units}`, color = colorOf(ctx.view, ctx.view.you) } else nil
end

-- Extra pills for the Polls lens, in order. Add one to show more per state (for
-- example what a poll reveals about the opponent's ground game).
Lens.pollDetails = { groundGame } :: { Detail }

local function pollsLine(ctx: Context, s: StateView): Line
	local view = ctx.view
	local parts: { Part } = {}
	if s.poll then
		table.insert(parts, leadPart(view, s.poll.support, ""))
	elseif s.leanTo and s.lean > 0 then
		-- Before the first poll: the lean, marked "~".
		table.insert(parts, { text = `~+{math.floor(s.lean + 0.5)}`, color = colorOf(view, s.leanTo) })
	end
	local internal = internalOf(view, s.id)
	if internal then
		table.insert(parts, leadPart(view, internal, "i"))
	end
	local arrow = momentumPart(view, s)
	if arrow then
		table.insert(parts, arrow)
	end
	for _, detail in Lens.pollDetails do
		local part = detail(ctx, s)
		if part then
			table.insert(parts, part)
		end
	end
	return { parts = parts }
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
