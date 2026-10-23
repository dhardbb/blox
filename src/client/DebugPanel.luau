--!strict
-- The debug text panel: renders the server's State messages as text and takes
-- typed commands (select, draft, plan ..., auto, autoplay). Phase 2's whole UI;
-- since Phase 3 it sits on top of the real screens, hidden unless toggled with
-- F2, the corner "Debug" button, or the workspace attribute DebugText = true.
-- Agents and tests/e2e drive it by element name. It renders only what the
-- server sent: the player's own View.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Bot = require(Shared.Sim.Bot)
local Candidates = require(Shared.Sim.Candidates)
local Config = require(Shared.Sim.Config)
local Rng = require(Shared.Sim.Rng)
local Commands = require(Shared.DebugUI.Commands)
local Format = require(Shared.DebugUI.Format)
local Remotes = require(Shared.Net.Remotes)
local Session = require(Shared.Net.Session)

local player = Players.LocalPlayer

local folder = ReplicatedStorage:WaitForChild(Remotes.FOLDER)
local toServer = folder:WaitForChild(Remotes.TO_SERVER) :: RemoteEvent
local toClient = folder:WaitForChild(Remotes.TO_CLIENT) :: RemoteEvent

-- ---------------------------------------------------------------- UI

local MIN_TOUCH = 44 -- px, PLAN.md minimum touch target
local ROW_H = 44 -- px, each of the two button rows
local INPUT_H = 52 -- px, the command box row
local GAP = 6 -- px between rows and buttons
-- Two rows, so each button stays wider than MIN_TOUCH on a 390 px phone.
local BUTTON_ROWS = {
	{ "Practice", "Queue", "Host", "Auto", "Autoplay" },
	{ "Pass", "Bank", "Skip", "Help" },
}

local gui = Instance.new("ScreenGui")
gui.Name = "DebugUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10
gui.Enabled = workspace:GetAttribute("DebugText") == true

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
root.BorderSizePixel = 0
root.Parent = gui
local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.PaddingLeft = UDim.new(0, 8)
padding.PaddingRight = UDim.new(0, 8)
padding.Parent = root
local column = Instance.new("UIListLayout")
column.FillDirection = Enum.FillDirection.Vertical
column.SortOrder = Enum.SortOrder.LayoutOrder
column.Padding = UDim.new(0, 6)
column.Parent = root

local function label(order: number, height: UDim, size: number): TextLabel
	local text = Instance.new("TextLabel")
	text.LayoutOrder = order
	text.Size = UDim2.new(UDim.new(1, 0), height)
	text.BackgroundTransparency = 1
	text.TextColor3 = Color3.fromRGB(230, 232, 238)
	text.Font = Enum.Font.Code
	text.TextSize = size
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Text = ""
	text.Parent = root
	return text
end

local status = label(1, UDim.new(0, 40), 18)
status.Name = "Status"
status.TextColor3 = Color3.fromRGB(255, 214, 102)

local scroll = Instance.new("ScrollingFrame")
scroll.LayoutOrder = 2
scroll.Size = UDim2.new(1, 0, 1, -(40 + 100 + 2 * ROW_H + INPUT_H + 5 * GAP))
scroll.BackgroundColor3 = Color3.fromRGB(28, 31, 40)
scroll.BorderSizePixel = 0
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollBarThickness = 8
scroll.Parent = root
local board = Instance.new("TextLabel")
board.Size = UDim2.new(1, -12, 0, 0)
board.AutomaticSize = Enum.AutomaticSize.Y
board.BackgroundTransparency = 1
board.TextColor3 = Color3.fromRGB(220, 224, 232)
board.Font = Enum.Font.Code
board.TextSize = 15
board.TextWrapped = true
board.TextXAlignment = Enum.TextXAlignment.Left
board.TextYAlignment = Enum.TextYAlignment.Top
board.Text = "Waiting for the server..."
board.Name = "Board"
board.Parent = scroll

local log = label(3, UDim.new(0, 100), 14)
log.Name = "Log"
log.TextColor3 = Color3.fromRGB(160, 200, 255)

local function button(order: number, text: string, parent: Instance, width: UDim): TextButton
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.new(width, UDim.new(1, 0))
	b.BackgroundColor3 = Color3.fromRGB(58, 64, 82)
	b.TextColor3 = Color3.fromRGB(240, 240, 245)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 16
	b.TextWrapped = true -- "Autoplay ON" takes two lines on a phone
	b.Text = text
	b.Name = text
	b.Parent = parent
	return b
end

local buttons: { [string]: TextButton } = {}
for r, names in BUTTON_ROWS do
	local row = Instance.new("Frame")
	row.Name = `ButtonRow{r}`
	row.LayoutOrder = 3 + r
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.BackgroundTransparency = 1
	row.Parent = root
	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, GAP)
	rowLayout.Parent = row
	for k, text in names do
		buttons[text] = button(k, text, row, UDim.new(1 / #names, -GAP))
	end
end

local inputRow = Instance.new("Frame")
inputRow.LayoutOrder = 6
inputRow.Size = UDim2.new(1, 0, 0, INPUT_H)
inputRow.BackgroundTransparency = 1
inputRow.Parent = root
local inputLayout = Instance.new("UIListLayout")
inputLayout.FillDirection = Enum.FillDirection.Horizontal
inputLayout.Padding = UDim.new(0, GAP)
inputLayout.SortOrder = Enum.SortOrder.LayoutOrder
inputLayout.Parent = inputRow
local box = Instance.new("TextBox")
box.Name = "CommandBox"
box.LayoutOrder = 1
box.Size = UDim2.new(1, -126, 1, 0)
box.BackgroundColor3 = Color3.fromRGB(36, 40, 52)
box.TextColor3 = Color3.fromRGB(240, 240, 245)
box.PlaceholderText = "type a command (help) and press Enter"
box.ClearTextOnFocus = false
box.Font = Enum.Font.Code
box.TextSize = 16
box.TextXAlignment = Enum.TextXAlignment.Left
box.Text = ""
box.Parent = inputRow
local send = button(2, "Send", inputRow, UDim.new(0, 120))

gui.Parent = player:WaitForChild("PlayerGui")

-- Fail loudly on layouts that break the PLAN.md rules (DEBUG_UI checks).
task.defer(function()
	task.wait(1)
	if not gui.Enabled then
		return -- hidden panels are not checked; it is a debug tool, not a game screen
	end
	for text, b in buttons do
		if b.AbsoluteSize.Y < MIN_TOUCH then
			warn(`[270] debug UI: button {text} is {b.AbsoluteSize.Y}px tall, under {MIN_TOUCH}px`)
		end
		if b.AbsoluteSize.X < MIN_TOUCH then
			warn(`[270] debug UI: button {text} is {b.AbsoluteSize.X}px wide, under {MIN_TOUCH}px`)
		end
		if not b.TextFits then
			warn(`[270] debug UI: button {text} label is truncated at {b.AbsoluteSize.X}px wide`)
		end
	end
	print(
		`[270] debug UI sizes: root {root.AbsoluteSize}, board {scroll.AbsoluteSize}, buttons {buttons.Help.AbsoluteSize}`
	)
end)

-- ---------------------------------------------------------------- state

local current: Session.StatePayload? = nil
local lobby: Remotes.LobbyStatus? = nil
local ratingChange: Remotes.RatingChange? = nil -- after the last rated match
local autoplay = false
local autoKey = "" -- "matchId:step" of the last state autoplay acted on (steps restart each match)
local lastSubmit: any? = nil -- the last Submit input sent, to explain a NotEnoughMoney rejection
local logLines: { string } = {}
local rng = Rng.new(player.UserId % 2147483647 + 1)

local function say(text: string)
	table.insert(logLines, text)
	while #logLines > 5 do
		table.remove(logLines, 1)
	end
	log.Text = table.concat(logLines, "\n")
end

local function render()
	status.Text = Format.status(current, lobby, workspace:GetServerTimeNow())
	local payload = current
	if payload then
		board.Text = Format.board(payload, workspace:GetServerTimeNow(), ratingChange)
	end
end

local function request(message: { [string]: any })
	toServer:FireServer(message)
end

local function matchRequest(op: string, input: any?)
	local payload = current
	if payload == nil or payload.stage == "Over" then
		say(`not in a match ({op})`)
		return
	end
	request({ op = op, matchId = payload.matchId, step = payload.step, input = input })
end

-- The bot's choice for this step, built from our own View.
local function autoInput(payload: Session.StatePayload): any?
	if payload.stage ~= "Input" or payload.seats[payload.you].locked then
		return nil
	end
	local candidate = Candidates.ids[Rng.nextInt(rng, 1, #Candidates.ids)]
	return Bot.act(Config.defaults, payload.view, rng, candidate)
end

local function runAuto()
	local payload = current
	if payload == nil then
		say("auto: no match")
		return
	end
	if payload.stage == "Input" then
		local input = autoInput(payload)
		if input then
			lastSubmit = input
			matchRequest("Submit", input)
		end
	elseif payload.reveal == "Resolve" or (payload.stage == "Show" and payload.view.phase == "Election") then
		matchRequest("Skip")
	end
end

local function command(text: string)
	local parsed = Commands.parse(text)
	if parsed.kind == "Error" then
		say(parsed.message or "?")
	elseif parsed.kind == "Local" then
		if parsed.action == "help" then
			say(Commands.HELP)
		elseif parsed.action == "auto" then
			runAuto()
		elseif parsed.action == "autoplay" then
			autoplay = parsed.arg == "on"
			buttons.Autoplay.Text = if autoplay then "Autoplay ON" else "Autoplay"
			say(`autoplay {parsed.arg}`)
			runAuto()
		elseif parsed.action == "rules" then
			say(Format.rules(current))
		elseif parsed.action == "show" and current then
			say(Format.state(current :: Session.StatePayload, parsed.arg :: string))
		end
	else
		local op = parsed.op :: string
		if op == "Submit" or op == "Claim" or op == "Bank" or op == "Skip" then
			if op == "Submit" then
				lastSubmit = parsed.input
			end
			matchRequest(op, parsed.input)
		else
			request({ op = op, code = parsed.code, pick = parsed.pick, events = parsed.events })
		end
	end
end

local NOTICES = {
	OpponentDisconnected = "Opponent disconnected: their moves auto-submit after the grace period.",
	OpponentReconnected = "Opponent reconnected.",
	CandidateTaken = "Your opponent claimed that candidate at the same moment and won the coin flip. Pick another.",
}

toClient.OnClientEvent:Connect(function(message: Remotes.Message)
	if message.kind == "State" and message.state then
		local payload = message.state
		local isNew = current == nil or current.step ~= payload.step or current.matchId ~= payload.matchId
		current = payload
		if isNew and #payload.events > 0 then
			local lines = Format.events(payload.events, payload.you)
			if #lines > 0 then
				say(`events: {table.concat(lines, "; ")}`)
			end
		end
		if payload.stage == "Over" and payload.result then
			say(`match over: {payload.result.reason}`)
		end
		local key = `{payload.matchId}:{payload.step}`
		if autoplay and key ~= autoKey then
			autoKey = key
			task.delay(0.3, runAuto)
		end
	elseif message.kind == "Lobby" then
		lobby = message.lobby
	elseif message.kind == "Rating" and message.rating then
		ratingChange = message.rating
		say(Format.ratingChange(message.rating))
	elseif message.kind == "Notice" then
		say(NOTICES[message.notice or ""] or (message.notice or "notice"))
	elseif message.kind == "Rejected" then
		say(Format.rejected(current, message.op, message.reason, lastSubmit))
	end
	render()
end)

box.FocusLost:Connect(function(enterPressed: boolean)
	if enterPressed and box.Text ~= "" then
		command(box.Text)
		box.Text = ""
	end
end)
send.Activated:Connect(function()
	if box.Text ~= "" then
		command(box.Text)
		box.Text = ""
	end
end)
for text, b in buttons do
	b.Activated:Connect(function()
		if text == "Autoplay" then
			command(if autoplay then "autoplay off" else "autoplay on")
		else
			command(string.lower(text))
		end
	end)
end

-- Countdown refresh.
local elapsed = 0
RunService.RenderStepped:Connect(function(dt: number)
	elapsed += dt
	if elapsed >= 0.25 then
		elapsed = 0
		status.Text = Format.status(current, lobby, workspace:GetServerTimeNow())
	end
end)

say("Type help, or press Practice to play the bot, or Queue on two clients.")
request({ op = "Resync" })
render()

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if not processed and input.KeyCode == Enum.KeyCode.F2 then
		gui.Enabled = not gui.Enabled
	end
end)

return {
	gui = gui,
	toggle = function()
		gui.Enabled = not gui.Enabled
	end,
}
