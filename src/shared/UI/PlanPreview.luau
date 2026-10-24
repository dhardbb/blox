--!strict
-- The plan preview (docs/DESIGN.md D-071): while you draft a week's plan, what
-- it would do on the map if nothing else changes. Pure: reads only your own
-- View and draft, and Explain's per-action estimates (the numbers the state
-- card shows), so the map and the card always agree.
--
-- Per state, the expected change in your margin (your support minus the
-- opponent's, in points), summed over the plan's actions there, each estimated
-- with the actions queued before it (a second ad is a repeat ad, a second
-- attack fills the backlash meter):
--   Rally, Media   your gain minus the opponent's loss from Explain
--   Attack         your gain (less any backlash) plus the opponent's loss
--   Gotv           units x GOTV_PER_UNIT (it counts on election night)
--   Fundraise, Poll, RegionPoll, Pivot: no margin there (money, information,
--   or a national change), so no number
-- Then the projected votes: the header's count (public-poll leaders,
-- Polls.projectedEV) with each polled state's lead moved by its change. The
-- opponent's plan is unknown, so this is an estimate, and says so.

local ConfigModule = require("../Sim/Config")
local Explain = require("./Explain")
local Numbers = require("./Numbers")
local PlanDraft = require("./PlanDraft")
local StateData = require("../Sim/StateData")
local ViewModule = require("../Sim/View")

type View = ViewModule.View
type Config = ConfigModule.Config

local PlanPreview = {}

PlanPreview.SHOWN = 0.05 -- a state's change under this many points shows no number

local function opponentOf(view: View): number
	return if view.you == 1 then 2 else 1
end

-- Every state's expected margin change from `draft`, keyed by state id
-- (states the plan does not move are absent).
function PlanPreview.changes(config: Config, view: View, draft: PlanDraft.Draft): { [string]: number }
	local out: { [string]: number } = {}
	local before = PlanDraft.new()
	for _, action in draft.actions do
		local id = action.state
		local change = 0
		if id ~= nil then
			if action.kind == "Rally" or action.kind == "Media" or action.kind == "Attack" then
				local preview = Explain.action(config, view, before, id, action.kind, action.issue)
				change = (preview.you or 0) - (preview.them or 0)
			elseif action.kind == "Gotv" then
				change = (action.units or 0) * config.GOTV_PER_UNIT
			end
			if change ~= 0 then
				out[id] = (out[id] or 0) + change
			end
		end
		PlanDraft.add(before, action)
	end
	for id, value in out do
		if math.abs(value) < PlanPreview.SHOWN then
			out[id] = nil
		end
	end
	return out
end

-- Your projected votes now and after the plan, if nothing else changes.
function PlanPreview.votes(config: Config, view: View, draft: PlanDraft.Draft): (number, number)
	local me, rival = view.you, opponentOf(view)
	local now = view.projectedEV[me] or 0
	local changes = PlanPreview.changes(config, view, draft)
	local after = now
	for _, s in view.states do
		local change = changes[s.id]
		local poll = s.poll
		if change and poll then
			local record = StateData.byId[s.id]
			local ev = if record then record.ev else 0
			local margin = (poll.support[me] or 0) - (poll.support[rival] or 0)
			local was = if margin > 0 then 1 elseif margin < 0 then -1 else 0
			local moved = margin + change
			local will = if moved > 0 then 1 elseif moved < 0 then -1 else 0
			-- Gain the state when you take the lead; lose it when you fall behind.
			if was <= 0 and will > 0 then
				after += ev
			elseif was > 0 and will <= 0 then
				after -= ev
			end
		end
	end
	return now, after
end

-- "Plan: 268 → 281 EV" (short: it shares the map's legend row on a phone).
function PlanPreview.votesText(now: number, after: number): string
	return `Plan: {now} → {after} EV`
end

PlanPreview.CAVEAT = "if nothing else changes"

export type Tag = { text: string, negative: boolean? }

-- The map's tags ("+4.1", "-0.6": Numbers.signed) and the votes line, or nil
-- when the plan moves no state yet.
function PlanPreview.build(config: Config, view: View, draft: PlanDraft.Draft): ({ [string]: Tag }, string?)
	local tags: { [string]: Tag } = {}
	local any = false
	for id, change in PlanPreview.changes(config, view, draft) do
		tags[id] = { text = Numbers.signed(change), negative = if change < 0 then true else nil }
		any = true
	end
	if not any then
		return tags, nil
	end
	return tags, PlanPreview.votesText(PlanPreview.votes(config, view, draft))
end

return table.freeze(PlanPreview)
