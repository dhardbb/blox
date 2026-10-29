--!strict
-- Picks the screen for the current state, mounts it, keeps it updated, and runs
-- the DEBUG_UI layout audit (UI/Audit) 0.5 s after a screen appears and again
-- after the orientation flips. The audit only runs in Studio or when the
-- workspace attribute DebugScreen or DebugText is set, never on a live server.
--
-- Screen change (docs/DESIGN.md D-053): the old screen goes at once (its logic
-- and its UI: two live screens would share element names), and the new one
-- fades in and slides up (Motion.enter) inside a CanvasGroup "ScreenFade" that
-- exists only for the transition; when it ends the screen moves back under the
-- container. Under reduced motion it is a 0.1 s fade; headless, instant.
--
-- The tutorial (D-080) runs on its own short schedule (Config.tutorial): while
-- a tutorial match is on screen, ctx.config is that config (so "Week 2 of 4",
-- the debate week and Help's numbers follow it) and the coach tips use their
-- tutorial copy (CoachTip.setTutorial). Back in the Lobby both return to normal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)

local Audit = require(script.Parent.UI.Audit)
local CoachTip = require(script.Parent.UI.CoachTip)
local Motion = require(script.Parent.UI.Motion)
local Types = require(script.Parent.Screens.Types)

local AUDIT_DELAY = 0.5 -- s after a mount or an orientation flip, so the layout has settled

local SCREENS: { [string]: { mount: (Frame, Types.Ctx) -> Types.Screen } } = {
	Lobby = require(script.Parent.Screens.Lobby),
	Select = require(script.Parent.Screens.Select),
	Draft = require(script.Parent.Screens.Draft),
	Decision = require(script.Parent.Screens.Decision),
	Debate = require(script.Parent.Screens.Debate),
	Campaign = require(script.Parent.Screens.Campaign),
	Election = require(script.Parent.Screens.Election),
	Results = require(script.Parent.Screens.Results),
}

local Router = {}

export type Name = "Lobby" | "Select" | "Draft" | "Decision" | "Debate" | "Campaign" | "Election" | "Results"

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
	elseif
		(phase == "Debate" and payload.reveal == nil)
		or payload.reveal == "DebateIntro"
		or payload.reveal == "Clash"
		or payload.reveal == "Verdict"
	then
		return "Debate" -- the debate's live rounds, their clashes and the verdict (D-072)
	elseif phase == "Decision" and payload.stage == "Input" then
		return "Decision" -- a stance, on its own before the plan (D-044)
	elseif phase == "Election" and payload.stage == "Show" then
		return "Election"
	end
	return "Campaign"
end

-- Whether the screen for this state is a tutorial match's (D-080).
function Router.tutorial(state: Types.State): boolean
	local payload = state.payload
	return payload ~= nil and payload.tutorial == true and Router.pick(state) ~= "Lobby"
end

-- Whether this client runs the layout audit.
function Router.auditing(): boolean
	return RunService:IsStudio()
		or workspace:GetAttribute("DebugScreen") ~= nil
		or workspace:GetAttribute("DebugText") == true
end

-- Mounts screens into `container` and follows the store. Returns a stop function.
function Router.start(
	container: Frame,
	ctx: Types.Ctx,
	subscribe: (fn: (Types.State) -> ()) -> () -> ()
): () -> ()
	local currentName: Name? = nil
	local current: Types.Screen? = nil
	-- The match's config (D-080): the tutorial's short schedule or the normal one.
	local baseConfig = ctx.config
	local tutorialConfig = ConfigModule.tutorial(baseConfig)
	local holder: Frame? = nil
	local auditing = Router.auditing()
	local auditToken = 0 -- only the newest scheduled audit runs
	-- The size class audited last ("portrait", "compact" or "wide", D-089): a
	-- rotation or a landscape phone's layout gets its own audit.
	local function sizeClass(): string
		local compact = ctx.compact
		if ctx.portrait() then
			return "portrait"
		end
		return if compact and compact() then "compact" else "wide"
	end
	local auditedClass = sizeClass()

	local function scheduleAudit(frame: Frame, name: Name)
		auditedClass = sizeClass()
		if not auditing then
			return
		end
		auditToken += 1
		local token = auditToken
		task.delay(AUDIT_DELAY, function()
			if token == auditToken and holder == frame then
				Audit.run(frame, name)
			end
		end)
	end

	-- Fades a freshly mounted screen in. Input is never blocked: the screen is
	-- live from the first frame, only its look is still arriving.
	local fade: CanvasGroup? = nil
	local function fadeIn(frame: Frame)
		if fade then
			fade:Destroy()
			fade = nil
		end
		if Motion.headless then
			return
		end
		local group = Instance.new("CanvasGroup")
		group.Name = "ScreenFade"
		group.Size = UDim2.fromScale(1, 1)
		group.BackgroundTransparency = 1
		group.BorderSizePixel = 0
		group.GroupTransparency = 0
		group.Parent = container
		frame.Parent = group
		fade = group
		Motion.enter(group, Motion.ENTER_DY)
		task.delay(if Motion.reduced() then Motion.REDUCED_FADE else Motion.t.enter, function()
			if fade == group then
				if frame.Parent == group then
					frame.Parent = container
				end
				group:Destroy()
				fade = nil
			end
		end)
	end

	local function show(state: Types.State)
		local name: Name = Router.pick(state)
		local tutorial = Router.tutorial(state)
		ctx.config = if tutorial then tutorialConfig else baseConfig
		CoachTip.setTutorial(tutorial)
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
			fadeIn(frame)
			scheduleAudit(frame, name)
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
		local frame: Frame?, name: Name? = holder, currentName
		if frame and name and sizeClass() ~= auditedClass then
			scheduleAudit(frame, name)
		end
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
