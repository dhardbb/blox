--!strict
-- Picks the screen for the current state, mounts it, keeps it updated, and runs
-- the DEBUG_UI layout audit whenever a screen appears.

local RunService = game:GetService("RunService")

local Audit = require(script.Parent.UI.Audit)
local Types = require(script.Parent.Screens.Types)

local SCREENS: { [string]: { mount: (Frame, Types.Ctx) -> Types.Screen } } = {
	Lobby = require(script.Parent.Screens.Lobby),
	Select = require(script.Parent.Screens.Select),
	Draft = require(script.Parent.Screens.Draft),
	Campaign = require(script.Parent.Screens.Campaign),
	Election = require(script.Parent.Screens.Election),
	Results = require(script.Parent.Screens.Results),
}

local Router = {}

export type Name = "Lobby" | "Select" | "Draft" | "Campaign" | "Election" | "Results"

-- Which screen a state belongs on.
function Router.pick(state: Types.State): Name
	local payload = state.payload
	if payload == nil then
		return "Lobby"
	end
	if payload.stage == "Over" then
		return if state.resultSeen then "Lobby" else "Results"
	end
	local phase = payload.view.phase
	if phase == "Select" then
		return "Select"
	elseif phase == "MapReveal" or phase == "Draft" or payload.reveal == "Draft" then
		return "Draft"
	elseif phase == "Election" and payload.stage == "Show" then
		return "Election"
	end
	return "Campaign"
end

-- Mounts screens into `container` and follows the store. Returns a stop function.
function Router.start(
	container: Frame,
	ctx: Types.Ctx,
	subscribe: (fn: (Types.State) -> ()) -> () -> ()
): () -> ()
	local currentName: Name? = nil
	local current: Types.Screen? = nil
	local holder: Frame? = nil

	local function show(state: Types.State)
		local name: Name = Router.pick(state)
		if name ~= currentName then
			if current then
				current.destroy()
			end
			if holder then
				holder:Destroy()
			end
			local frame = Instance.new("Frame")
			frame.Name = name
			frame.Size = UDim2.fromScale(1, 1)
			frame.BackgroundTransparency = 1
			frame.Parent = container
			holder = frame
			current = SCREENS[name].mount(frame, ctx)
			currentName = name
			task.delay(0.5, function()
				if holder == frame then
					Audit.run(frame, name)
				end
			end)
		end
		if current then
			current.update(state)
		end
	end

	local unsubscribe = subscribe(show)
	show(ctx.store.get())

	local elapsed = 0
	local connection = RunService.RenderStepped:Connect(function(dt: number)
		elapsed += dt
		if elapsed < 0.25 then
			return
		end
		elapsed = 0
		local screen = current
		if screen and screen.tick then
			screen.tick(ctx.now())
		end
	end)

	return function()
		unsubscribe()
		connection:Disconnect()
		if current then
			current.destroy()
		end
	end
end

return Router
