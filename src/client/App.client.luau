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

local DebugPanel = require(script.Parent.DebugPanel)
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

local gui = Kit.new("ScreenGui", {
	Name = "Game",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local background = Kit.new("Frame", {
	Name = "Background",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Kit.colors.background,
	BorderSizePixel = 0,
	Parent = gui,
})
local container = Kit.box({ Name = "Screens", Parent = background })
Kit.pad(10).Parent = container

local debugButton = Kit.button("Debug", DebugPanel.toggle, {
	Name = "DebugToggle",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -6, 1, -6),
	Size = UDim2.fromOffset(72, 44),
	BackgroundTransparency = 0.6,
	TextSize = 13,
	ZIndex = 50,
	Parent = gui,
})
debugButton.TextTransparency = 0.3

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
