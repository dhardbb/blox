--!strict
-- The "How it works" overlay (playtest 2): one short panel per concept, every
-- number from Config and Candidates at open time (Shared/UI/Explain.help), so
-- a balance change needs no edit here. Mounted once by App.client above the
-- screens (below the toast); the Campaign, Select and Draft headers open it with
-- their "?" button (ctx.help). It covers the screen while open, keeps the
-- current step's countdown in its header (the clock keeps running), and its one
-- pinned primary is Close.
--
--   local help = Help.mount(parent, ctx)
--   help.open() · help.close() · help.isOpen() -> boolean · help.destroy()
--   help.root   Frame "HelpOverlay" (Visible only while open)
--   Elements: HelpHeader, HelpBody (ScrollingFrame), HelpSection_<id>,
--   HelpTitle_<id>, HelpText_<id>, HelpBar, HelpClose (attribute PrimaryAction).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Explain = require(ReplicatedStorage.Shared.UI.Explain)

local ActionBar = require(script.Parent.ActionBar)
local Audit = require(script.Parent.Audit)
local Header = require(script.Parent.Header)
local Kit = require(script.Parent.Kit)
local Types = require(script.Parent.Parent.Screens.Types)

local Help = {}

Help.MAX_WIDTH = 760 -- px, the readable column on wide screens
local EDGE = 10 -- px, the same inset as the screens container
local TICK = 0.25 -- s between countdown refreshes

export type Help = {
	root: Frame,
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	destroy: () -> (),
}

function Help.mount(parent: Instance, ctx: Types.Ctx): Help
	local root = Kit.new("Frame", {
		Name = "HelpOverlay",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Kit.colors.background,
		BorderSizePixel = 0,
		Active = true, -- swallows taps meant for the screen underneath
		ZIndex = 40,
		Visible = false,
	}) :: Frame

	local column = Kit.box({
		Name = "HelpColumn",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, EDGE),
		Size = UDim2.new(1, -2 * EDGE, 1, -2 * EDGE),
		Parent = root,
	})
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(Help.MAX_WIDTH, math.huge), Parent = column })

	local header = Header.new(column, { title = "How it works", name = "HelpHeader" })
	header:setSubtitle("the clock keeps running")

	local top = Kit.HEADER_H + Kit.space.sm
	local body = Kit.new("ScrollingFrame", {
		Name = "HelpBody",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, top),
		Size = UDim2.new(1, 0, 1, -(top + Kit.BAR_H + Kit.space.sm)),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		Parent = column,
	}) :: ScrollingFrame
	Kit.list("Vertical", Kit.space.sm).Parent = body
	Kit.new("UIPadding", { PaddingRight = UDim.new(0, EDGE), Parent = body })

	local isOpen = false
	local connection: RBXScriptConnection? = nil
	local elapsed = 0

	local function close()
		isOpen = false
		root.Visible = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	local bar = ActionBar.new(column, {
		primary = "Close",
		onPrimary = close,
		primaryName = "HelpClose",
		name = "HelpBar",
	})
	bar:setStatus("Numbers are for this match's rules and your candidate.", "muted")

	local function countdown()
		local payload = ctx.store.get().payload
		if payload == nil or payload.deadline == nil then
			header:setTimer(nil)
			return
		end
		header:setTimer(payload.deadline - ctx.now(), if payload.stage == "Input" then Kit.TIMER_WARN else 0)
	end

	local function fill()
		for _, child in body:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local payload = ctx.store.get().payload
		local view = if payload then payload.view else nil
		for k, section in Explain.help(ctx.config, view) do
			local panel = Kit.panel({
				Name = `HelpSection_{section.id}`,
				LayoutOrder = k,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = body,
			})
			Kit.list("Vertical", Kit.space.xs).Parent = panel
			Kit.heading(section.title, {
				Name = `HelpTitle_{section.id}`,
				LayoutOrder = 1,
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = panel,
			})
			Kit.caption(table.concat(section.lines, "\n"), {
				Name = `HelpText_{section.id}`,
				LayoutOrder = 2,
				TextColor3 = Kit.colors.text,
				Parent = panel,
			})
		end
	end

	local function auditing(): boolean
		return RunService:IsStudio()
			or workspace:GetAttribute("DebugScreen") ~= nil
			or workspace:GetAttribute("DebugText") == true
	end

	local function open()
		fill()
		body.CanvasPosition = Vector2.new(0, 0)
		isOpen = true
		root.Visible = true
		countdown()
		if connection == nil then
			elapsed = 0
			connection = RunService.RenderStepped:Connect(function(dt: number)
				elapsed += dt
				if elapsed >= TICK then
					elapsed = 0
					countdown()
				end
			end)
		end
		if auditing() then
			task.delay(0.5, function()
				if isOpen then
					Audit.run(root, "Help")
				end
			end)
		end
	end

	root.Parent = parent
	return {
		root = root,
		open = open,
		close = close,
		isOpen = function(): boolean
			return isOpen
		end,
		destroy = function()
			close()
			root:Destroy()
		end,
	}
end

return Help
