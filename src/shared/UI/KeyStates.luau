--!strict
-- Key states (docs/DESIGN.md D-088): the few states that decide who reaches
-- 270 this week, highlighted on the campaign map as a learning aid.
--
-- The rule, in one sentence: line the states up by your public-poll lead, find
-- the tipping state (the one that carries the leader past 269), and the key
-- states are it and the biggest states polling within KEY_STATE_BAND points of
-- it, KEY_STATES at most.
--
-- Pure, and reads only the player's own View: the public polls everyone sees
-- (each state's lean before the first poll) and the states' electoral votes.
-- Never true support, internal polls, ground game or anyone's plan. In 1v1 both
-- players line up the same public polls from opposite ends, so both see the
-- same tipping state and nearly always the same key states: the aid favors no
-- seat. Nothing in Sim or Bot reads it.
--
--   KeyStates.of(config, view) -> { Key }       biggest first, at most KEY_STATES
--   KeyStates.set(config, view) -> { [id]: true }
--   KeyStates.tipping(config, view) -> Key?      the tipping state

local ConfigModule = require("../Sim/Config")
local StateData = require("../Sim/StateData")
local ViewModule = require("../Sim/View")

type Config = ConfigModule.Config
type View = ViewModule.View
type StateView = ViewModule.StateView

export type Key = {
	id: string,
	ev: number,
	margin: number, -- your public-poll lead there, points (negative: you trail)
	tipping: boolean, -- the state that carries the leader past 269
}

local KeyStates = {}

-- Your lead in one state: your public-poll share minus the best other share;
-- before the first poll, its public lean (+ your way).
function KeyStates.margin(view: View, s: StateView): number
	local poll = s.poll
	if poll == nil then
		if s.leanTo == nil or s.lean == 0 then
			return 0
		end
		return if s.leanTo == view.you then s.lean else -s.lean
	end
	local mine = poll.support[view.you] or 0
	local best = -math.huge
	for p, share in poll.support do
		if p ~= view.you and share > best then
			best = share
		end
	end
	return mine - (if best == -math.huge then 0 else best)
end

type Row = { id: string, ev: number, margin: number }

-- Every state, your safest first (ties: bigger first, then by code).
local function lineUp(view: View): { Row }
	local rows: { Row } = {}
	for _, s in view.states do
		local record = StateData.byId[s.id]
		if record then
			table.insert(rows, { id = s.id, ev = record.ev, margin = KeyStates.margin(view, s) })
		end
	end
	table.sort(rows, function(a, b)
		if a.margin ~= b.margin then
			return a.margin > b.margin
		elseif a.ev ~= b.ev then
			return a.ev > b.ev
		end
		return a.id < b.id
	end)
	return rows
end

-- The tipping state: walking from your safest state down, the one whose votes
-- take your running total to EV_TO_WIN. Your opponent walks the same polls from
-- the other end and stops at the same place, so it is the same state for both:
-- - states that tie on that margin are one step, and its biggest state (then by
--   code) is the tipping state;
-- - when the states safer than a step hold exactly half the votes (269-269),
--   both steps beside that line tip it, and the closer one in the polls counts
--   (then the one with the bigger state).
local function tippingRow(config: Config, rows: { Row }): Row?
	-- Steps of equal margin, safest first; lineUp puts the biggest of a tie first.
	type Step = { first: Row, ev: number }
	local steps: { Step } = {}
	local all = 0
	for _, row in rows do
		local last = steps[#steps]
		if last and last.first.margin == row.margin then
			last.ev += row.ev
		else
			table.insert(steps, { first = row, ev = row.ev })
		end
		all += row.ev
	end
	local before = 0
	for k, step in steps do
		if before + step.ev >= config.EV_TO_WIN then
			local other = steps[k - 1]
			if other and 2 * before == all then
				local a, b = step.first, other.first
				if math.abs(a.margin) ~= math.abs(b.margin) then
					return if math.abs(a.margin) < math.abs(b.margin) then a else b
				elseif a.ev ~= b.ev then
					return if a.ev > b.ev then a else b
				end
				return if a.id < b.id then a else b
			end
			return step.first
		end
		before += step.ev
	end
	return nil
end

function KeyStates.tipping(config: Config, view: View): Key?
	local row = tippingRow(config, lineUp(view))
	if row == nil then
		return nil
	end
	return { id = row.id, ev = row.ev, margin = row.margin, tipping = true }
end

-- The key states this week, biggest first (ties: nearer the tipping state, then
-- by code). The tipping state is always one of them.
function KeyStates.of(config: Config, view: View): { Key }
	local rows = lineUp(view)
	local tip = tippingRow(config, rows)
	if tip == nil or config.KEY_STATES < 1 then
		return {}
	end
	local near: { Row } = {}
	for _, row in rows do
		if row ~= tip and math.abs(row.margin - tip.margin) <= config.KEY_STATE_BAND then
			table.insert(near, row)
		end
	end
	table.sort(near, function(a, b)
		if a.ev ~= b.ev then
			return a.ev > b.ev
		end
		local da, db = math.abs(a.margin - tip.margin), math.abs(b.margin - tip.margin)
		if da ~= db then
			return da < db
		end
		return a.id < b.id
	end)
	local chosen: { Row } = { tip }
	for k = 1, math.min(#near, config.KEY_STATES - 1) do
		table.insert(chosen, near[k])
	end
	table.sort(chosen, function(a, b)
		if a.ev ~= b.ev then
			return a.ev > b.ev
		end
		return a.id < b.id
	end)
	local out: { Key } = {}
	for k, row in chosen do
		out[k] = { id = row.id, ev = row.ev, margin = row.margin, tipping = row == tip }
	end
	return out
end

function KeyStates.set(config: Config, view: View): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, key in KeyStates.of(config, view) do
		out[key.id] = true
	end
	return out
end

return table.freeze(KeyStates)
