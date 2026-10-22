--!strict
-- Client entry point: hides Roblox's default chat and menus, builds the game's
-- full-screen board, and routes between screens as the server's State changes.
--
-- DEBUG_UI mode: set the workspace attribute DebugScreen to a fixture moment
-- ("Lobby", "Select", "MapReveal", "Draft", "Plan", "Resolve", "DebatePrep",
-- "Debate", "Election", "Over") before pressing Play. The client then renders that
-- screen from a fixture (Shared/UI/Fixtures) without talking to the server, logs
-- its sizes, and runs the UI audit. Sends are printed instead of fired.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Version = require(Shared:WaitForChild("Version"))
local Config = require(Shared.Sim.Config)
local Fixtures = require(Shared.UI.Fixtures)

local _DebugPanel = require(script.Parent.DebugPanel) -- builds the hidden debug panel
local Kit = require(script.Parent.UI.Kit)
local Net = require(script.Parent.Net)
local Router = require(script.Parent.Router)
local Store = require(script.Parent.Store)
local Types = require(script.Parent.Screens.Types)

local player = Players.LocalPlayer
print(`[270] client up: v{Version.VERSION} ({Version.PHASE})`)

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

-- The board fills the whole screen behind everything; the game itself stays
-- inside the area Roblox's own buttons and device notches leave free.
local backdrop = Kit.new("ScreenGui", {
	Name = "Backdrop",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = -1,
})
Kit.new("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Kit.colors.background,
	BorderSizePixel = 0,
	Parent = backdrop,
})
local gui = Kit.new("ScreenGui", {
	Name = "Game",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local background = Kit.box({ Name = "Background", Parent = gui })
local container = Kit.box({ Name = "Screens", Parent = background })
Kit.pad(10).Parent = container

-- The debug panel opens with F2 or the workspace attribute DebugText = true;
-- there is no on-screen button, so it never covers the game.
backdrop.Parent = player:WaitForChild("PlayerGui")
gui.Parent = player:WaitForChild("PlayerGui")

local ctx: Types.Ctx = {
	config = Config.defaults,
	store = Store,
	net = Net,
	now = function()
		return workspace:GetServerTimeNow()
	end,
	portrait = function()
		local size = background.AbsoluteSize
		return size.Y > size.X
	end,
}

local fixture = workspace:GetAttribute("DebugScreen")
if type(fixture) == "string" then
	-- DEBUG_UI: render a fixture screen offline.
	local fakeNet = table.clone(Net) :: any
	fakeNet.send = function(op: string, fields: any?)
		print(`[270] DEBUG_UI send {op}`, fields)
	end
	fakeNet.submit = function(input: any)
		print("[270] DEBUG_UI submit", input)
	end
	fakeNet.bank = function()
		print("[270] DEBUG_UI bank")
	end
	fakeNet.skip = function()
		print("[270] DEBUG_UI skip")
	end
	ctx.net = fakeNet
	if fixture == "Lobby" then
		Store.setLobby(Fixtures.lobby("Idle"))
	else
		local payload = Fixtures.payload(Config.defaults, fixture :: any)
		-- Keep countdowns running: shift the fixture's times to now.
		local shift = workspace:GetServerTimeNow() - payload.stageStart
		payload.stageStart += shift
		payload.deadline += shift
		Store.setPayload(payload)
	end
	print(`[270] DEBUG_UI fixture {fixture}, screen {Router.pick(Store.get())}`)
else
	Net.start()
end

Router.start(container, ctx, Store.subscribe)
