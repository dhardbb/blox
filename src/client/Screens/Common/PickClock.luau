--!strict
-- The last seconds of a pick (D-091): the candidate and issue pick, a draft
-- round, a stance. The header's timer already turns orange under
-- Kit.TIMER_WARN and ticks under Kit.TIMER_CRITICAL; on these screens the
-- pinned Lock in also changes look: from Kit.TIMER_WARN seconds left a veil
-- drains across it (ActionBar:setProgress) and it pulses once as that starts
-- (Motion.pulseOnce: nothing under reduced motion). Locked in, or with time to
-- spare, the button looks as usual.
--
--   local clock = PickClock.new(bar)
--   clock:paint(secondsLeft?, active)    -- every tick; active = still picking

local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Motion = require(script.Parent.Parent.Parent.UI.Motion)

export type PickClock = {
	paint: (self: PickClock, secondsLeft: number?, active: boolean) -> (),
}

type Bar = {
	primary: TextButton,
	setProgress: (self: any, fraction: number?) -> (),
}

local PickClock = {}

function PickClock.new(bar: Bar): PickClock
	local urgent = false -- the veil is showing
	local clock = {}
	function clock.paint(_self: PickClock, secondsLeft: number?, active: boolean)
		local left = secondsLeft
		if left == nil or not active or left >= Kit.TIMER_WARN then
			if urgent then
				urgent = false
				bar:setProgress(nil)
			end
			return
		end
		if not urgent then
			urgent = true
			Motion.pulseOnce(bar.primary)
		end
		bar:setProgress(math.max(left, 0) / Kit.TIMER_WARN)
	end
	return clock :: PickClock
end

return PickClock
