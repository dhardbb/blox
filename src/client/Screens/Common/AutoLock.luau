--!strict
-- Every timed step locks itself when its timer ends (PLAN.md), but a pick the
-- player finished and never locked must not be thrown away. A screen asks this
-- gate once per tick; it says yes at most once per step, shortly before the
-- seat's own deadline (payload.deadline already includes the banked time), and
-- only for a step that is still open and not locked. A server rejection leaves
-- the server's default in place: the gate never asks twice.

local AutoLock = {}

AutoLock.LEAD = 0.5 -- seconds before the deadline
AutoLock.LATE = 1 -- seconds after the deadline when it is too late to bother

export type Gate = {
	-- True when the screen should submit its current valid selection now.
	due: (self: Gate, payload: any, now: number, locked: boolean) -> boolean,
	-- The player submitted by hand (or the screen already sent): never auto-submit this step.
	spent: (self: Gate, payload: any) -> (),
}

local function keyOf(payload: any): string
	return `{payload.matchId}:{payload.step}`
end

function AutoLock.new(): Gate
	local used: string? = nil
	local gate = {} :: any

	function gate.due(_self: Gate, payload: any, now: number, locked: boolean): boolean
		if locked or payload == nil or payload.stage ~= "Input" then
			return false
		end
		-- A step without a deadline (the tutorial, D-075) never locks itself.
		if payload.deadline == nil then
			return false
		end
		local left = payload.deadline - now
		if left > AutoLock.LEAD or left < -AutoLock.LATE then
			return false
		end
		local key = keyOf(payload)
		if used == key then
			return false
		end
		used = key
		return true
	end

	function gate.spent(_self: Gate, payload: any)
		if payload ~= nil then
			used = keyOf(payload)
		end
	end

	return gate :: Gate
end

return AutoLock
