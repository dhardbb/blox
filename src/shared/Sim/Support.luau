--!strict
-- The state support model (docs/PLAN.md "State support model").
--
-- Effects are accumulated into a delta list read from one snapshot, then applied
-- together (D-001): callers build `delta` with the add* helpers while the state is
-- unchanged, then call Support.apply once. That way no player's effect is ever
-- computed after another player's has landed.

local ConfigModule = require("./Config")
local State = require("./State")
local StateData = require("./StateData")

type Config = ConfigModule.Config
type StateSim = State.StateSim

local Support = {}

-- Gain multiplier for a player at `support` in a state: 1 up to the base, falling
-- linearly to the floor at SUPPORT_CAP.
function Support.saturation(config: Config, support: number): number
	local room = (config.SUPPORT_CAP - support) / (config.SUPPORT_CAP - config.BASE_SUPPORT)
	return math.clamp(room, config.SATURATION_FLOOR, 1)
end

-- Delta list of zeros, one per player.
function Support.zero(s: StateSim): { number }
	return table.create(#s.support, 0)
end

-- Takes `amount` from player p's opponents in proportion to their support.
local function takeFromOpponents(s: StateSim, p: number, amount: number, delta: { number })
	local n = #s.support
	local total = 0
	for q = 1, n do
		if q ~= p then
			total += s.support[q]
		end
	end
	for q = 1, n do
		if q ~= p then
			local share = if total > 0 then s.support[q] / total else 1 / (n - 1)
			delta[q] -= amount * share
		end
	end
end

-- Player p gains `gain` points. Draws GAIN_FROM_UNDECIDED from undecided while the
-- snapshot's undecided is at least UNDECIDED_FLOOR, otherwise everything from
-- opponents. Returns the change to undecided.
function Support.addGain(config: Config, s: StateSim, p: number, gain: number, delta: { number }): number
	if gain <= 0 then
		return 0
	end
	local fromUndecided = if s.undecided >= config.UNDECIDED_FLOOR then config.GAIN_FROM_UNDECIDED else 0
	delta[p] += gain
	takeFromOpponents(s, p, gain * (1 - fromUndecided), delta)
	return -gain * fromUndecided
end

-- Attacker `a` costs `target` `loss` points: ATTACK_TO_UNDECIDED of it goes to
-- undecided, the rest to the attacker. Returns the change to undecided.
function Support.addAttack(config: Config, a: number, target: number, loss: number, delta: { number }): number
	if loss <= 0 then
		return 0
	end
	delta[target] -= loss
	delta[a] += loss * (1 - config.ATTACK_TO_UNDECIDED)
	return loss * config.ATTACK_TO_UNDECIDED
end

-- Player p loses `loss` points to undecided. Returns the change to undecided.
function Support.addLoss(p: number, loss: number, delta: { number }): number
	if loss <= 0 then
		return 0
	end
	delta[p] -= loss
	return loss
end

-- Applies a delta list and an undecided change, then clamps every share to [0, 100]
-- and rescales so support plus undecided is exactly 100.
function Support.apply(s: StateSim, delta: { number }, undecidedDelta: number)
	local total = 0
	for p = 1, #s.support do
		local value = math.clamp(s.support[p] + delta[p], 0, 100)
		s.support[p] = value
		total += value
	end
	local undecided = math.clamp(s.undecided + undecidedDelta, 0, 100)
	total += undecided
	if total <= 0 then
		local even = 100 / (#s.support + 1)
		for p = 1, #s.support do
			s.support[p] = even
		end
		s.undecided = even
		return
	end
	local scale = 100 / total
	for p = 1, #s.support do
		s.support[p] *= scale
	end
	s.undecided = undecided * scale
end

-- Convenience: player p gains `gain` points in s right now (no other effects).
function Support.gain(config: Config, s: StateSim, p: number, gain: number)
	local delta = Support.zero(s)
	local du = Support.addGain(config, s, p, gain, delta)
	Support.apply(s, delta, du)
end

-- Player p's lead over the best opponent in true support (negative = trailing).
function Support.margin(s: StateSim, p: number): number
	local best = -math.huge
	for q = 1, #s.support do
		if q ~= p and s.support[q] > best then
			best = s.support[q]
		end
	end
	return s.support[p] - best
end

-- National shifts (D-010): player p's national change xs[p] moves each state by
-- xs[p] x (that state's undecided / population-weighted mean undecided), so the
-- population-weighted average move is xs[p]. Gains use the normal split; losses
-- go to undecided. All players' shifts read the same snapshot.
function Support.national(config: Config, states: { StateSim }, xs: { number })
	local weighted, weights = 0, 0
	for i, s in states do
		local pop = StateData.list[i].pop
		weighted += pop * s.undecided
		weights += pop
	end
	local meanUndecided = weighted / weights
	if meanUndecided <= 0 then
		meanUndecided = 1
	end
	for _, s in states do
		local factor = s.undecided / meanUndecided
		local delta = Support.zero(s)
		local du = 0
		for p, x in xs do
			if x > 0 then
				du += Support.addGain(config, s, p, x * factor, delta)
			elseif x < 0 then
				du += Support.addLoss(p, -x * factor, delta)
			end
		end
		Support.apply(s, delta, du)
	end
end

return table.freeze(Support)
