--!strict
-- Results screen (placeholder until the real screen lands).

local Kit = require(script.Parent.Parent.UI.Kit)
local Types = require(script.Parent.Types)

local Screen = {}

function Screen.mount(parent: Frame, _ctx: Types.Ctx): Types.Screen
	local label = Kit.text("Results", {
		Name = "Title",
		Size = UDim2.fromScale(1, 0.2),
		TextSize = Kit.size.title,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = parent,
	})
	return {
		update = function(state: Types.State)
			local payload = state.payload
			label.Text = if payload then `Results · {payload.view.phase} · {payload.stage}` else "Results"
		end,
		tick = nil,
		destroy = function() end,
	}
end

return Screen
