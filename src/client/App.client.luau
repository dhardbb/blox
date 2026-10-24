--!strict
-- Client entry point: hides Roblox's default chat and menus, builds the game's
-- full-screen board, and routes between screens as the server's State changes.
--
-- DEBUG_UI mode: set the workspace attribute DebugScreen to a fixture moment
-- ("Lobby", "Select", "MapReveal", "Draft", "Plan", "Stance", "ChoiceWeek",
-- "Resolve", "ChoiceResolve", "DebateIntro", "DebateRound", "Clash", "Debate",
-- "Election", "Over") before
-- pressing Play. The client then renders that
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
local Audio = require(script.Parent.UI.Audio)
local FoundPrompt = require(script.Parent.UI.FoundPrompt)
local Kit = require(script.Parent.UI.Kit)
local Help = require(script.Parent.UI.Help)
local LeaveMatch = require(script.Parent.UI.LeaveMatch)
local ReportName = require(script.Parent.UI.ReportName)
local Net = require(script.Parent.Net)
local Router = require(script.Parent.Router)
local Store = require(script.Parent.Store)
local Toast = require(script.Parent.UI.Toast)
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

-- Big screens (an iPad Pro, a large Mac window) scale the whole board up, so
-- text and buttons don't look tiny: min(width / 1024, height / 768), between
-- 1 and BOARD_SCALE_MAX. Phones, a 1024x768 iPad and 1280x720 stay at 1. The
-- board is drawn 1/scale its size and scaled back up, so it still fills the
-- screen exactly (a UIScale multiplies AbsoluteSize).
local BOARD_SCALE_MAX = 1.35
local BOARD_BASE = Vector2.new(1024, 768) -- px, the size the layout is designed at
local boardScale = Kit.new("UIScale", { Name = "BoardScale", Scale = 1, Parent = background })
local function viewport(): Vector2?
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return nil
end
local function fitBoard()
	local size = viewport()
	if size == nil or size.X <= 0 or size.Y <= 0 then
		return
	end
	local scale = math.clamp(math.min(size.X / BOARD_BASE.X, size.Y / BOARD_BASE.Y), 1, BOARD_SCALE_MAX)
	boardScale.Scale = scale
	background.Size = UDim2.fromScale(1 / scale, 1 / scale)
end
fitBoard()
pcall(function()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitBoard)
	end
end)
local container = Kit.box({ Name = "Screens", Parent = background })
Kit.pad(10).Parent = container
-- One toast layer above every screen (rejections and notices), so no screen
-- or reveal can hide a message.
Toast.mount(background, Store)

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

-- The "How it works" overlay: above the screens, below the toast (ZIndex 40 < 50).
local help = Help.mount(background, ctx)
ctx.help = help.open
-- "Leave match" (D-059): above Help, below the toast (ZIndex 45).
ctx.leave = LeaveMatch.mount(background, ctx).open
-- "Report name" (D-069): the same layer as Leave.
ctx.report = ReportName.mount(background, ctx).open

local fixture = workspace:GetAttribute("DebugScreen")
if type(fixture) == "string" then
	-- DEBUG_UI: render a fixture screen offline.
	local fakeNet = table.clone(Net) :: any
	fakeNet.send = function(op: string, fields: any?)
		print(`[270] DEBUG_UI send {op}`, fields)
	end
	fakeNet.submit = function(input: any)
		-- One readable line: "move=Pivot zinger=true", "choice=B", "actions=[3]".
		local parts: { string } = {}
		if type(input) == "table" then
			for key, value in input do
				table.insert(
					parts,
					if type(value) == "table" then `{key}=[{#value}]` else `{key}={tostring(value)}`
				)
			end
			table.sort(parts)
		end
		print("[270] DEBUG_UI submit", table.concat(parts, " "))
	end
	fakeNet.claim = function(candidate: string)
		print("[270] DEBUG_UI claim", candidate)
		-- Offline there is no server: grant the claim when the candidate is free.
		local payload = Store.get().payload
		if payload and payload.view.claims[candidate] == nil then
			local copy = table.clone(payload)
			copy.view = table.clone(payload.view)
			copy.view.claims = table.clone(payload.view.claims)
			copy.view.claims[candidate] = payload.you
			Store.setPayload(copy)
		end
	end
	fakeNet.claimColor = function(color: string)
		print("[270] DEBUG_UI claimColor", color)
		-- Offline: grant a color nobody else claimed (D-061). Whoever was only
		-- dealt it gets your old color, so colors stay distinct.
		local payload = Store.get().payload
		if payload == nil or not payload.view.canPickColor then
			return
		end
		local owner = payload.view.colorClaims[color]
		if owner ~= nil and owner ~= payload.you then
			return
		end
		local copy = table.clone(payload)
		copy.view = table.clone(payload.view)
		local claims = table.clone(payload.view.colorClaims)
		local players = table.clone(payload.view.players)
		local old = players[payload.you].color
		for name, p in payload.view.colorClaims do
			if p == payload.you then
				claims[name] = nil
			end
		end
		claims[color] = payload.you
		for p, seat in players do
			if seat.color == color and p ~= payload.you then
				players[p] = table.clone(seat)
				players[p].color = old
			end
		end
		players[payload.you] = table.clone(players[payload.you])
		players[payload.you].color = color
		copy.view.colorClaims = claims
		copy.view.players = players
		Store.setPayload(copy)
	end
	fakeNet.bank = function()
		print("[270] DEBUG_UI bank")
	end
	fakeNet.setColor = function(color: string?)
		print("[270] DEBUG_UI setColor", color or "auto")
		-- Offline there is no server: save it in the fixture's lobby status.
		local lobby = Store.get().lobby
		if lobby then
			local copy = table.clone(lobby)
			copy.color = color
			Store.setLobby(copy)
		end
	end
	fakeNet.buyPass = function(passId: number)
		print("[270] DEBUG_UI buyPass", passId)
	end
	fakeNet.reportName = function(userId: string)
		print("[270] DEBUG_UI reportName", userId)
	end
	fakeNet.setName = function(name: string?)
		print("[270] DEBUG_UI setName", name or "(own)")
		-- Offline there is no server or filter: use the name as typed, trimmed.
		local payload = Store.get().payload
		local naming = if payload then payload.naming else nil
		if payload == nil or naming == nil or not naming.owned then
			return
		end
		local trimmed = if name then string.match(name, "^%s*(.-)%s*$") else nil
		local named = table.clone(naming)
		named.name = if trimmed ~= "" then trimmed else nil
		local copy = table.clone(payload)
		copy.naming = named
		copy.view = table.clone(payload.view)
		copy.view.players = table.clone(payload.view.players)
		copy.view.players[payload.you] = table.clone(payload.view.players[payload.you])
		copy.view.players[payload.you].customName = named.name
		Store.setPayload(copy)
	end
	fakeNet.skip = function()
		print("[270] DEBUG_UI skip")
	end
	fakeNet.forfeit = function()
		print("[270] DEBUG_UI forfeit")
	end
	fakeNet.answer = function(accept: boolean)
		print("[270] DEBUG_UI answer", accept)
	end
	fakeNet.rematch = function()
		print("[270] DEBUG_UI rematch")
	end
	fakeNet.invite = function(code: string)
		print("[270] DEBUG_UI invite", code)
	end
	ctx.net = fakeNet
	if fixture == "Lobby" then
		Store.setLobby(Fixtures.lobby("Idle"))
		Store.setLeaderboard(Fixtures.leaderboard())
		Store.setDaily(Fixtures.daily({ now = workspace:GetServerTimeNow() }))
	else
		local payload = Fixtures.payload(Config.defaults, fixture :: any)
		-- Keep countdowns running: shift the fixture's times to now.
		local shift = workspace:GetServerTimeNow() - payload.stageStart
		payload.stageStart += shift
		if payload.deadline ~= nil then
			payload.deadline += shift
		end
		Store.setPayload(payload)
	end
	print(`[270] DEBUG_UI fixture {fixture}, screen {Router.pick(Store.get())}`)
else
	Net.start()
end

-- "Opponent found! Leave this bot game?" (D-080): over any screen while a
-- bot game is played in the queue; the same layer as Leave.
FoundPrompt.mount(background, ctx)

-- Load the sound cues in the background (never waits).
Audio.preload()

Router.start(container, ctx, Store.subscribe)
