--!strict
-- Money and points as text, the same everywhere (debug UI, real screens, the duel
-- harness). Pure.
--
-- Money is floored to the shown precision, never rounded: cash is fractional
-- (fundraisers raise amounts like $13.55) while costs are whole or tenths, so
-- "$5.0" for $4.96 promised a $5 plan the server then rejected (playtest 1).
-- The same 1e-9 slack as Plan.validate keeps float noise from showing $4.9 for $5.

local Numbers = {}

local SLACK = 1e-9 -- Plan.validate accepts a plan that costs up to cash + 1e-9

-- Money rounded down to tenths, as a number.
function Numbers.moneyValue(amount: number): number
	return math.floor((amount + SLACK) * 10) / 10
end

-- "$4.9" for 4.96, "-$0.1" for -0.04.
function Numbers.money(amount: number): string
	local value = Numbers.moneyValue(amount)
	if value < 0 then
		return string.format("-$%.1f", -value)
	end
	return string.format("$%.1f", value)
end

-- A price: rounded up to tenths (costs are whole or tenths, so this is exact).
function Numbers.cost(amount: number): string
	return string.format("$%.1f", math.ceil((amount - SLACK) * 10) / 10)
end

-- Support, momentum and other points: one decimal, rounded, never "-0.0".
function Numbers.points(value: number): string
	if math.abs(value) < 0.05 then
		return "0.0"
	end
	return string.format("%.1f", value)
end

-- A signed change: "+0.4", "-0.2", never "+-0.2" or "-0.0".
function Numbers.signed(value: number): string
	if math.abs(value) < 0.05 then
		return "+0.0"
	end
	return string.format("%+.1f", value)
end

return table.freeze(Numbers)
