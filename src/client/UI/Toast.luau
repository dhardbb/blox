--!strict
-- The one toast layer (docs/DESIGN.md D-030), mounted once by App.client above
-- the Screens container, so no screen and no reveal can hide it. It follows the
-- Store and shows the newest message at the top center for Toast.SECONDS: max
-- width 480, at least 44 px tall, body text on a raised panel (elevation 2, so
-- it stands off the cards under it) with a 2 px stroke (danger for a rejection,
-- accent for a notice). It slides in a few pixels (Kit.motion.base); a newer
-- message replaces it at once.
--
--   local toast = Toast.mount(parent, store)   -- store: { get, subscribe }
--   toast.root   Frame "ToastLayer" (full size, transparent, never takes input)
--   toast.frame  Frame "Toast"; toast.label TextLabel "ToastText"
--   toast.destroy()
--
-- Screens may still mirror a rejection into their action-bar status line
-- (tone "bad") so it persists; the toast is what catches the eye.

local Messages = require(script.Parent.Parent.Screens.Common.Messages)
local Kit = require(script.Parent.Kit)
local Types = require(script.Parent.Parent.Screens.Types)

local Toast = {}

Toast.SECONDS = 5 -- how long a toast stays up
Toast.MAX_WIDTH = 480 -- px
Toast.TOP = 8 -- px from the top of the safe area
Toast.SLIDE = 12 -- px the toast slides down as it appears

export type StoreLike = {
	get: () -> Types.State,
	subscribe: (listener: (Types.State) -> ()) -> () -> (),
}

export type Toast = {
	root: Frame,
	frame: Frame,
	label: TextLabel,
	destroy: () -> (),
}

function Toast.mount(parent: Instance, store: StoreLike): Toast
	local root = Kit.box({ Name = "ToastLayer", ZIndex = 50 })
	local frame = Kit.new("Frame", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Toast.TOP),
		Size = UDim2.new(1, -2 * Kit.space.lg, 0, Kit.MIN_TOUCH),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Kit.colors.raised,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 50,
		Parent = root,
	}) :: Frame
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(Toast.MAX_WIDTH, math.huge), Parent = frame })
	Kit.corner(Kit.radius.panel).Parent = frame
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, Kit.space.md),
		PaddingRight = UDim.new(0, Kit.space.md),
		PaddingTop = UDim.new(0, Kit.space.sm),
		PaddingBottom = UDim.new(0, Kit.space.sm),
		Parent = frame,
	})
	local stroke = Kit.new("UIStroke", {
		Name = "ToastStroke",
		Color = Kit.colors.accent,
		Thickness = 2,
		Parent = frame,
	}) :: UIStroke
	local label = Kit.text("", {
		Name = "ToastText",
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH - 2 * Kit.space.sm),
		AutomaticSize = Enum.AutomaticSize.Y,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 51,
		Parent = frame,
	})

	local seen = Messages.lastId(store.get()) -- show only what arrives after mounting
	local shownId = 0

	local function show(message: Types.Message)
		shownId = message.id
		label.Text = message.text
		stroke.Color = if message.rejected then Kit.colors.danger else Kit.colors.accent
		frame:SetAttribute("Rejected", message.rejected)
		frame.Position = UDim2.new(0.5, 0, 0, Toast.TOP - Toast.SLIDE)
		frame.Visible = true
		Kit.tween(frame, { Position = UDim2.new(0.5, 0, 0, Toast.TOP) }, Kit.motion.base)
		local id = message.id
		task.delay(Toast.SECONDS, function()
			if shownId == id then
				frame.Visible = false
			end
		end)
	end

	local function update(state: Types.State)
		local message = Messages.newestAfter(state, seen)
		if message then
			seen = message.id
			show(message)
		end
	end

	local unsubscribe = store.subscribe(update)
	root.Parent = parent

	return {
		root = root,
		frame = frame,
		label = label,
		destroy = function()
			unsubscribe()
			shownId = -1
			root:Destroy()
		end,
	}
end

return Toast
