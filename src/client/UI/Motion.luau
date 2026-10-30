--!strict
-- Every animation in the client goes through here (docs/UI-STYLE.md §2.7,
-- docs/DESIGN.md D-053). Timings are presentation numbers, not game rules, so
-- they live here and not in Sim/Config.
--
--   Motion.t        press 0.07 · release 0.12 · fast 0.12 · base 0.2 · enter 0.25
--                   exit 0.15 · pop 0.22 · count 0.5 · beat 0.35 · call 0.4 · hero 0.45 (s)
--   Motion.ease     out (Quad Out) · in_ (Quad In) · soft (Quart Out) · back (Back Out) · linear
--   Motion.reduced() -> boolean     GuiService.ReducedMotionEnabled, or Motion.setReduced(true)
--   Motion.setReduced(on)           the in-game toggle (session only); fires Motion.changed
--   Motion.changed                  signal(reduced: boolean): :Connect(fn)
--   Motion.headless                 true without a TweenService: goals apply at once
--
--   Motion.tween(inst, goals, seconds?, ease?) -> cancel()
--                   a new tween on a property cancels the old one on that property
--   Motion.cancel(inst)             stops every tween and timed effect on inst
--   Motion.scale(inst) -> UIScale   get-or-create the child UIScale "MotionScale"
--   Motion.press(button)            shrinks to 0.96 while held, springs back on release;
--                   a button with attribute Lip (Kit's primary and secondary)
--                   instead travels down onto its lip (Lip px) at 0.98
--   Motion.stamp(inst, delay?)      a stamp lands: scale 1.6 -> 1 (pop, Back Out) as it
--                   fades in (0.15 s); under reduced motion it is simply there
--   Motion.shine(button) -> cancel  a light band sweeps the primary every 4.5 s
--                   while it is enabled (decorative)
--   Motion.breathe(inst, prop, a, b, seconds) -> cancel   ping-pongs a number
--                   property between a and b (Sine in/out; decorative)
--   Motion.pulseOnce(inst)          1 -> 1.03 -> 1 over 0.9 s (the "your turn" nudge)
--   Motion.pop(inst, from?, delay?) UIScale from (0.9) to 1.0, Back Out
--   Motion.enter(inst, dy?, delay?) fades in from transparent, sliding up dy (12) px
--   Motion.exit(inst, onDone)       fades out; onDone when it finishes
--   Motion.stagger(list, fn, step?, cap?)
--                   calls fn(item, index, delay) at once for every item, with
--                   delay = (index - 1) × step (0.04 s), the last one at most cap
--                   (0.3 s): pass `delay` on to enter/pop so nothing waits
--   Motion.countTo(label, from, to, format, seconds?)  counts label.Text up or down
--   Motion.flash(textLabel, color, seconds?)           text color to color and back (0.3 s)
--   Motion.ring(parent, color, size?) -> Frame?        a ring grows 1 -> 1.8 and fades (0.5 s)
--   Motion.shake(inst, px?, seconds?)                  ±4 px, 3 swings, 0.18 s (errors only)
--   Motion.confetti(parent, colors, n?) -> Frame?      up to 60 pieces fall for 1.2 s
--   Motion.typewriter(label, cps?) -> skip()           reveals text at 50 chars/s
--   Motion.drawOn(inst, delay?)                        a marker line draws out to its width (0.35 s)
--   Motion.erase(parent, board, felt) -> Frame?        an eraser wipes across a new screen (0.4 s)
--
-- Rules. Nothing waits on Tween.Completed while the player plans: every effect
-- starts and returns at once, and input is never blocked. Decorative effects
-- (press, pop, ring, shake, confetti, drawOn, erase) do nothing under reduced motion.
-- Informational ones (tween, countTo, flash, typewriter) jump to their end
-- state; enter and exit keep a 0.1 s fade with no slide. Without a
-- TweenService (Motion.headless) everything lands on its end state at once.
-- Ring and Confetti frames carry attribute Decor = true; the UI audit skips
-- them, and divides a "MotionScale" UIScale out of the sizes it checks.

local Signal = require(script.Parent.Signal)

local Motion = {}

local function service(name: string): any
	local ok, found = pcall(function()
		return game:GetService(name)
	end)
	return if ok then found else nil
end

local tweenService: any = service("TweenService")
local guiService: any = service("GuiService")
local runService: any = service("RunService")

export type Ease = { style: Enum.EasingStyle, direction: Enum.EasingDirection }

-- Durations in seconds.
Motion.t = {
	press = 0.07, -- a button going down
	release = 0.12, -- a button springing back
	fast = 0.12, -- chip selection, small color changes
	base = 0.2, -- panels and sheets, a value changing
	enter = 0.25, -- a card or screen arriving
	exit = 0.15, -- leaving is quicker than arriving
	pop = 0.22, -- a chip, badge or pill popping in
	count = 0.5, -- a number counting up
	beat = 0.35, -- one step of a reveal
	call = 0.4, -- one election call
	hero = 0.45, -- the results banner
}

Motion.ease = {
	out = { style = Enum.EasingStyle.Quad, direction = Enum.EasingDirection.Out } :: Ease,
	in_ = { style = Enum.EasingStyle.Quad, direction = Enum.EasingDirection.In } :: Ease,
	soft = { style = Enum.EasingStyle.Quart, direction = Enum.EasingDirection.Out } :: Ease,
	back = { style = Enum.EasingStyle.Back, direction = Enum.EasingDirection.Out } :: Ease,
	linear = { style = Enum.EasingStyle.Linear, direction = Enum.EasingDirection.Out } :: Ease,
}

Motion.PRESS_SCALE = 0.96 -- a held button's size
Motion.LIP_PRESS_SCALE = 0.98 -- a held lipped button's size (it also travels down its lip)
Motion.STAMP_FROM = 1.6 -- where a stamp's scale starts
Motion.STAMP_FADE = 0.15 -- s, a stamp fading in
Motion.SHINE_EVERY = 4.5 -- s between two shines on the primary (a decorative loop)
Motion.SHINE_SECONDS = 0.6 -- s, one sweep
Motion.SHINE_W = 40 -- px, the light band
Motion.SHINE_TRANSPARENCY = 0.75
Motion.PULSE_SCALE = 1.03
Motion.PULSE_SECONDS = 0.9 -- s, there and back
Motion.POP_FROM = 0.9 -- where a pop starts
Motion.ENTER_DY = 12 -- px an entering element slides up
Motion.REDUCED_FADE = 0.1 -- s, enter/exit fade under reduced motion
Motion.STAGGER_STEP = 0.04 -- s between two items of a list
Motion.STAGGER_CAP = 0.3 -- s, the last item's delay at most
Motion.FLASH = 0.3 -- s, a flash there and back
Motion.RING_GROW = 1.8 -- a ring's final scale
Motion.RING_SECONDS = 0.5
Motion.SHAKE_PX = 4
Motion.SHAKE_SWINGS = 3
Motion.SHAKE_SECONDS = 0.18
Motion.CONFETTI_N = 40 -- pieces by default
Motion.CONFETTI_MAX = 60
Motion.CONFETTI_SECONDS = 1.2
Motion.TYPE_CPS = 50 -- characters a second

Motion.headless = tweenService == nil
Motion.changed = Signal.new() :: Signal.Signal<boolean>

local forced = false

function Motion.reduced(): boolean
	if forced then
		return true
	end
	if guiService == nil then
		return false
	end
	local ok, value = pcall(function()
		return guiService.ReducedMotionEnabled
	end)
	return ok and value == true
end

function Motion.setReduced(on: boolean)
	forced = on
	Motion.changed:Fire(Motion.reduced())
end

if guiService then
	pcall(function()
		guiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Connect(function()
			Motion.changed:Fire(Motion.reduced())
		end)
	end)
end

-- ---------------------------------------------------------------- tweens

-- inst -> property -> the tween driving it (weak keys: destroyed UI goes away).
local active: { [any]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any

local function apply(inst: any, goals: { [string]: any })
	for key, value in goals do
		inst[key] = value
	end
end

local function forget(inst: any, tween: any)
	local props = active[inst]
	if props == nil then
		return
	end
	for key, current in props do
		if current == tween then
			props[key] = nil
		end
	end
end

local function cancelProps(inst: any, goals: { [string]: any })
	local props = active[inst]
	if props == nil then
		return
	end
	for key in goals do
		local tween = props[key]
		if tween then
			forget(inst, tween)
			tween:Cancel()
		end
	end
end

-- Plays a tween whatever the motion setting (callers decide); `onDone` runs
-- when it finishes (not when cancelled). Returns a cancel function.
local function play(
	inst: any,
	goals: { [string]: any },
	seconds: number,
	ease: Ease,
	onDone: (() -> ())?,
	delay: number?
): () -> ()
	cancelProps(inst, goals)
	if tweenService == nil then
		apply(inst, goals)
		if onDone then
			onDone()
		end
		return function() end
	end
	local info = TweenInfo.new(seconds, ease.style, ease.direction, 0, false, delay or 0)
	local tween = tweenService:Create(inst, info, goals)
	local props = active[inst]
	if props == nil then
		props = {}
		active[inst] = props
	end
	for key in goals do
		props[key] = tween
	end
	tween.Completed:Connect(function(state: any)
		forget(inst, tween)
		if onDone and state ~= nil and state.Name == "Completed" then
			onDone()
		end
	end)
	tween:Play()
	return function()
		if active[inst] then
			forget(inst, tween)
			tween:Cancel()
		end
	end
end

function Motion.tween(inst: Instance, goals: { [string]: any }, seconds: number?, ease: Ease?): () -> ()
	if Motion.reduced() then
		cancelProps(inst, goals)
		apply(inst, goals)
		return function() end
	end
	return play(inst, goals, seconds or Motion.t.base, ease or Motion.ease.out)
end

-- ---------------------------------------------------------------- the frame loop

-- Timed effects that are not tweens (countTo, shake, typewriter, flash) share
-- one Heartbeat connection, made when the first starts and dropped when the
-- last ends. One job per (instance, kind): a new one replaces the old.
type Job = {
	elapsed: number,
	duration: number,
	step: (alpha: number) -> (),
	done: () -> (),
}

local jobs: { [any]: { [string]: Job } } = setmetatable({}, { __mode = "k" }) :: any
local connection: any = nil

local function stopLoopIfIdle()
	if next(jobs) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function frame(dt: number)
	local finished: { Job } = {}
	for inst, kinds in jobs do
		for kind, job in kinds do
			job.elapsed += dt
			if job.elapsed >= job.duration then
				kinds[kind] = nil
				table.insert(finished, job)
			else
				job.step(job.elapsed / job.duration)
			end
		end
		if next(kinds) == nil then
			jobs[inst] = nil
		end
	end
	for _, job in finished do
		job.done()
	end
	stopLoopIfIdle()
end

-- Starts (or replaces) a timed job; finishes at once without a frame loop.
local function run(inst: any, kind: string, duration: number, step: (number) -> (), done: () -> ())
	local kinds = jobs[inst]
	if kinds == nil then
		kinds = {}
		jobs[inst] = kinds
	end
	local old = kinds[kind]
	if old then
		kinds[kind] = nil
		old.done()
	end
	if runService == nil or duration <= 0 then
		done()
		return
	end
	kinds[kind] = { elapsed = 0, duration = duration, step = step, done = done }
	step(0)
	if connection == nil then
		connection = runService.Heartbeat:Connect(frame)
	end
end

local function stopJob(inst: any, kind: string, finish: boolean)
	local kinds = jobs[inst]
	local job = if kinds then kinds[kind] else nil
	if job and kinds then
		kinds[kind] = nil
		if finish then
			job.done()
		end
	end
end

function Motion.cancel(inst: Instance)
	local props = active[inst]
	if props then
		local seen = {}
		for _, tween in props do
			if not seen[tween] then
				seen[tween] = true
				tween:Cancel()
			end
		end
		active[inst] = nil
	end
	local kinds = jobs[inst]
	if kinds then
		jobs[inst] = nil
		for _, job in kinds do
			job.done()
		end
	end
	stopLoopIfIdle()
end

-- ---------------------------------------------------------------- scale effects

function Motion.scale(inst: Instance): UIScale
	local existing = inst:FindFirstChild("MotionScale")
	if existing and existing:IsA("UIScale") then
		return existing :: UIScale
	end
	local scale = Instance.new("UIScale")
	scale.Name = "MotionScale"
	scale.Scale = 1
	scale.Parent = inst
	return scale
end

local function isPress(input: any): boolean
	local kind = if input then input.UserInputType else nil
	local name = if kind then kind.Name else nil
	return name == "MouseButton1" or name == "Touch"
end

function Motion.press(button: GuiButton)
	local scale: UIScale? = nil
	local function lip(): number
		local value = button:GetAttribute("Lip")
		return if type(value) == "number" then value else 0
	end
	local function release()
		if scale and scale.Scale ~= 1 then
			play(scale, { Scale = 1 }, Motion.t.release, Motion.ease.back)
		end
		if lip() > 0 and button.Position.Y.Offset ~= 0 then
			play(button, { Position = UDim2.fromOffset(0, 0) }, Motion.t.release, Motion.ease.back)
		end
	end
	button.InputBegan:Connect(function(input: InputObject)
		if not isPress(input) or button.Active == false or Motion.reduced() then
			return
		end
		scale = scale or Motion.scale(button)
		local travel = lip()
		play(
			scale :: UIScale,
			{ Scale = if travel > 0 then Motion.LIP_PRESS_SCALE else Motion.PRESS_SCALE },
			Motion.t.press,
			Motion.ease.out
		)
		if travel > 0 then
			play(button, { Position = UDim2.fromOffset(0, travel) }, Motion.t.press, Motion.ease.out)
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if isPress(input) then
			release()
		end
	end)
	button.MouseLeave:Connect(release)
end

function Motion.pop(inst: Instance, from: number?, delay: number?)
	if Motion.reduced() then
		return
	end
	local scale = Motion.scale(inst)
	scale.Scale = from or Motion.POP_FROM
	play(scale, { Scale = 1 }, Motion.t.pop, Motion.ease.back, nil, delay)
end

-- ---------------------------------------------------------------- enter and exit

-- The transparency properties a fade drives on `inst`, at their resting values.
local resting: { [any]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any

local function fadeProps(inst: Instance): { [string]: number }
	local saved = resting[inst]
	if saved then
		return saved
	end
	local any = inst :: any
	local props: { [string]: number } = {}
	local function take(name: string)
		local value = any[name]
		props[name] = if type(value) == "number" then value else 0
	end
	if inst:IsA("CanvasGroup") then
		take("GroupTransparency")
	else
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			take("TextTransparency")
		elseif inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
			take("ImageTransparency")
		end
		if inst:IsA("GuiObject") then
			local bg = any.BackgroundTransparency
			if type(bg) == "number" and bg < 1 then
				props.BackgroundTransparency = bg
			end
		end
	end
	return props
end

-- Where an element entering right now comes to rest (an enter that starts
-- while another runs keeps the first one's resting place).
local restPosition: { [any]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any

function Motion.enter(inst: Instance, dy: number?, delay: number?)
	local target = inst :: any
	local props = fadeProps(inst)
	resting[inst] = props
	local reduced = Motion.reduced()
	local goals: { [string]: any } = table.clone(props)
	for key in props do
		target[key] = 1
	end
	local slide = if reduced then 0 else (dy or Motion.ENTER_DY)
	local position: UDim2? = restPosition[inst] or target.Position
	if slide ~= 0 and position ~= nil then
		local rest = position :: UDim2
		restPosition[inst] = rest
		target.Position = UDim2.new(rest.X.Scale, rest.X.Offset, rest.Y.Scale, rest.Y.Offset + slide)
		goals.Position = rest
	end
	local seconds = if reduced then Motion.REDUCED_FADE else Motion.t.enter
	play(inst, goals, seconds, Motion.ease.soft, function()
		resting[inst] = nil
		restPosition[inst] = nil
	end, delay)
end

function Motion.exit(inst: Instance, onDone: () -> ())
	local props = fadeProps(inst)
	local goals: { [string]: any } = {}
	for key in props do
		goals[key] = 1
	end
	if Motion.headless or Motion.reduced() then
		cancelProps(inst, goals)
		apply(inst, goals)
		onDone()
		return
	end
	play(inst, goals, Motion.t.exit, Motion.ease.in_, onDone)
end

function Motion.stagger<T>(
	list: { T },
	fn: (item: T, index: number, delay: number) -> (),
	step: number?,
	cap: number?
)
	local n = #list
	local gap = step or Motion.STAGGER_STEP
	if n > 1 then
		gap = math.min(gap, (cap or Motion.STAGGER_CAP) / (n - 1))
	end
	local still = Motion.headless or Motion.reduced()
	for index, item in list do
		fn(item, index, if still then 0 else (index - 1) * gap)
	end
end

-- ---------------------------------------------------------------- timed effects

local function easeOutQuart(a: number): number
	return 1 - (1 - a) ^ 4
end

function Motion.countTo(
	label: TextLabel | TextButton,
	from: number,
	to: number,
	format: (number) -> string,
	seconds: number?
)
	local target = label :: any
	if Motion.headless or Motion.reduced() then
		stopJob(target, "count", false)
		target.Text = format(to)
		return
	end
	run(target, "count", seconds or Motion.t.count, function(alpha)
		target.Text = format(from + (to - from) * easeOutQuart(alpha))
	end, function()
		target.Text = format(to)
	end)
end

local function lerpColor(a: Color3, b: Color3, k: number): Color3
	return Color3.new(a.R + (b.R - a.R) * k, a.G + (b.G - a.G) * k, a.B + (b.B - a.B) * k)
end

-- A label's own color while a flash runs (so a second flash restores it).
local flashBase: { [any]: Color3 } = setmetatable({}, { __mode = "k" }) :: any

function Motion.flash(label: TextLabel | TextButton, color: Color3, seconds: number?)
	local target = label :: any
	local base: Color3 = flashBase[target] or target.TextColor3
	local duration = seconds or Motion.FLASH
	if Motion.headless then
		target.TextColor3 = base
		return
	end
	flashBase[target] = base
	local function done()
		target.TextColor3 = base
		flashBase[target] = nil
	end
	if Motion.reduced() then
		-- No motion: the color switches, holds, and switches back.
		run(target, "flash", duration, function()
			target.TextColor3 = color
		end, done)
		return
	end
	run(target, "flash", duration, function(alpha)
		local k = if alpha < 0.5 then alpha * 2 else (1 - alpha) * 2
		target.TextColor3 = lerpColor(base, color, k)
	end, done)
end

function Motion.ring(parent: Instance, color: Color3, size: number?): Frame?
	if Motion.headless or Motion.reduced() then
		return nil
	end
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring:SetAttribute("Decor", true)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = if size then UDim2.fromOffset(size, size) else UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.ZIndex = 10
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Transparency = 0
	stroke.Parent = ring
	local scale = Motion.scale(ring)
	ring.Parent = parent
	play(scale, { Scale = Motion.RING_GROW }, Motion.RING_SECONDS, Motion.ease.soft)
	play(stroke, { Transparency = 1 }, Motion.RING_SECONDS, Motion.ease.soft)
	task.delay(Motion.RING_SECONDS, function()
		ring:Destroy()
	end)
	return ring
end

function Motion.shake(inst: GuiObject, px: number?, seconds: number?)
	if Motion.headless or Motion.reduced() then
		return
	end
	local target = inst :: any
	local base = target.Position
	if base == nil then
		return
	end
	local kinds = jobs[target]
	if kinds and kinds.shake then
		-- Already shaking: finish it first, so `base` is the resting position.
		stopJob(target, "shake", true)
		base = target.Position
	end
	local amplitude = px or Motion.SHAKE_PX
	run(target, "shake", seconds or Motion.SHAKE_SECONDS, function(alpha)
		local offset = amplitude * math.sin(alpha * Motion.SHAKE_SWINGS * 2 * math.pi) * (1 - alpha)
		target.Position = UDim2.new(base.X.Scale, base.X.Offset + offset, base.Y.Scale, base.Y.Offset)
	end, function()
		target.Position = base
	end)
end

function Motion.confetti(parent: Instance, colors: { Color3 }, n: number?): Frame?
	if Motion.headless or Motion.reduced() or #colors == 0 then
		return nil
	end
	local count = math.clamp(n or Motion.CONFETTI_N, 0, Motion.CONFETTI_MAX)
	local layer = Instance.new("Frame")
	layer.Name = "Confetti"
	layer:SetAttribute("Decor", true)
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.ClipsDescendants = true
	layer.ZIndex = 60
	layer.Parent = parent
	local random = Random.new()
	for k = 1, count do
		local piece = Instance.new("Frame")
		piece.Name = "Piece"
		piece.BorderSizePixel = 0
		piece.BackgroundColor3 = colors[(k - 1) % #colors + 1]
		piece.Size = UDim2.fromOffset(random:NextInteger(6, 10), random:NextInteger(10, 14))
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		local x = random:NextNumber(0.05, 0.95)
		piece.Position = UDim2.fromScale(x, random:NextNumber(-0.15, -0.02))
		piece.Rotation = random:NextInteger(0, 360)
		piece.ZIndex = 60
		piece.Parent = layer
		local fall = Motion.CONFETTI_SECONDS * random:NextNumber(0.7, 1)
		play(piece, {
			Position = UDim2.fromScale(x + random:NextNumber(-0.12, 0.12), 1.08),
			Rotation = piece.Rotation + random:NextInteger(-360, 360),
		}, fall, Motion.ease.in_)
	end
	task.delay(Motion.CONFETTI_SECONDS, function()
		layer:Destroy()
	end)
	return layer
end

function Motion.typewriter(label: TextLabel | TextButton, cps: number?): () -> ()
	local target = label :: any
	local function skip()
		stopJob(target, "type", false)
		target.MaxVisibleGraphemes = -1
	end
	local total = utf8.len(tostring(target.Text)) or #tostring(target.Text)
	if Motion.headless or Motion.reduced() or total == 0 then
		skip()
		return skip
	end
	local rate = cps or Motion.TYPE_CPS
	run(target, "type", total / rate, function(alpha)
		target.MaxVisibleGraphemes = math.floor(total * alpha)
	end, function()
		target.MaxVisibleGraphemes = -1
	end)
	return skip
end

-- ---------------------------------------------------------------- front page (D-056)

-- The GuiObjects under `inst` (itself included) and the transparency
-- properties a fade-in drives on each, at their resting values.
local function fadeTargets(inst: Instance): { { inst: any, props: { [string]: number } } }
	local out = {}
	for _, node in { inst, table.unpack(inst:GetDescendants()) } do
		if node:IsA("GuiObject") then
			table.insert(out, { inst = node, props = fadeProps(node) })
		end
	end
	return out
end

Motion.DRAW_ON = 0.35 -- s, a marker line drawing itself out (D-102)
Motion.ERASE = 0.4 -- s, the eraser wiping across a new screen (D-102)
Motion.ERASER_W = 56 -- px, the eraser's felt block at the wipe's leading edge

-- A line (an underline, a stroke) drawn on: its width grows from nothing to
-- what it is now, once. Decorative.
function Motion.drawOn(inst: GuiObject, delay: number?)
	if Motion.headless or Motion.reduced() then
		return
	end
	local size = inst.Size
	inst.Size = UDim2.new(0, 0, size.Y.Scale, size.Y.Offset)
	play(inst, { Size = size }, Motion.DRAW_ON, Motion.ease.out, nil, delay)
end

-- The board wiped clean as a new screen arrives: a panel in `board` with an
-- eraser in `felt` at its leading edge slides off to the right, uncovering
-- the screen under it, then goes. Decorative; input is never blocked (the
-- panel takes no input and is gone in Motion.ERASE).
function Motion.erase(parent: Instance, board: Color3, felt: Color3): Frame?
	if Motion.headless or Motion.reduced() then
		return nil
	end
	local wipe = Instance.new("Frame")
	wipe.Name = "EraserWipe"
	wipe.Size = UDim2.fromScale(1, 1)
	wipe.BackgroundColor3 = board
	wipe.BorderSizePixel = 0
	wipe.Active = false
	wipe.ZIndex = 1000
	wipe:SetAttribute("Decor", true)
	local eraser = Instance.new("Frame")
	eraser.Name = "Eraser"
	eraser.AnchorPoint = Vector2.new(0.5, 0.5)
	eraser.Position = UDim2.fromScale(0, 0.5)
	eraser.Size = UDim2.new(0, Motion.ERASER_W, 0.3, 0)
	eraser.BackgroundColor3 = felt
	eraser.BorderSizePixel = 0
	eraser.ZIndex = 1001
	eraser:SetAttribute("Decor", true)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = eraser
	eraser.Parent = wipe
	wipe.Parent = parent
	play(wipe, { Position = UDim2.fromScale(1.05, 0) }, Motion.ERASE, Motion.ease.soft, function()
		wipe:Destroy()
	end)
	return wipe
end

function Motion.stamp(inst: Instance, delay: number?)
	if Motion.headless or Motion.reduced() then
		return
	end
	local scale = Motion.scale(inst)
	scale.Scale = Motion.STAMP_FROM
	play(scale, { Scale = 1 }, Motion.t.pop, Motion.ease.back, nil, delay)
	for _, target in fadeTargets(inst) do
		local goals = table.clone(target.props)
		for key in goals do
			target.inst[key] = 1
		end
		play(target.inst, goals, Motion.STAMP_FADE, Motion.ease.out, nil, delay)
	end
end

-- The light is a layer the size and shape of `button` (its UICorner copied)
-- whose UIGradient carries the band and slides across it (Offset), so it never
-- shows past the button: clipping fails on a rotated parent (a tilted stamp)
-- and on rounded corners (GuiObject.ClipsDescendants, UICorner).
function Motion.shine(button: GuiObject): () -> ()
	if Motion.headless or Motion.reduced() then
		return function() end
	end
	local alive = true
	local band = Instance.new("Frame")
	band.Name = "Shine"
	band:SetAttribute("Decor", true)
	band.Size = UDim2.fromScale(1, 1)
	band.BackgroundColor3 = Color3.new(1, 1, 1)
	band.BackgroundTransparency = 1
	band.BorderSizePixel = 0
	band.ZIndex = 2
	local corner = button:FindFirstChildOfClass("UICorner")
	if corner then
		local round = Instance.new("UICorner")
		round.CornerRadius = corner.CornerRadius
		round.Parent = band
	end
	local soft = Instance.new("UIGradient")
	soft.Rotation = 20
	soft.Parent = band
	band.Parent = button
	local function sweep()
		if not alive or band.Parent == nil then
			return
		end
		if (button :: any).Active ~= false and not Motion.reduced() then
			-- The band's share of the width: SHINE_W px, within reason.
			local width = button.AbsoluteSize.X
			local half = math.clamp(if width > 0 then Motion.SHINE_W / width / 2 else 0.1, 0.02, 0.2)
			soft.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5 - half, 1),
				NumberSequenceKeypoint.new(0.5, 0),
				NumberSequenceKeypoint.new(0.5 + half, 1),
				NumberSequenceKeypoint.new(1, 1),
			})
			-- Past either edge the gradient holds its end value: transparent.
			local reach = 0.5 + half
			soft.Offset = Vector2.new(-reach, 0)
			band.BackgroundTransparency = Motion.SHINE_TRANSPARENCY
			play(
				soft,
				{ Offset = Vector2.new(reach, 0) },
				Motion.SHINE_SECONDS,
				Motion.ease.linear,
				function()
					band.BackgroundTransparency = 1
				end
			)
		end
		task.delay(Motion.SHINE_EVERY, sweep)
	end
	task.delay(Motion.SHINE_EVERY, sweep)
	return function()
		alive = false
		band:Destroy()
	end
end

function Motion.breathe(inst: Instance, prop: string, a: number, b: number, seconds: number): () -> ()
	local target = inst :: any
	if Motion.headless or Motion.reduced() then
		return function() end
	end
	cancelProps(target, { [prop] = true })
	target[prop] = a
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = tweenService:Create(inst, info, { [prop] = b })
	local props = active[target] or {}
	active[target] = props
	props[prop] = tween
	tween:Play()
	return function()
		if props[prop] == tween then
			props[prop] = nil
		end
		tween:Cancel()
		target[prop] = a
	end
end

function Motion.pulseOnce(inst: Instance)
	if Motion.headless or Motion.reduced() then
		return
	end
	local scale = Motion.scale(inst)
	cancelProps(scale, { Scale = true })
	scale.Scale = 1
	local info =
		TweenInfo.new(Motion.PULSE_SECONDS / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true)
	tweenService:Create(scale, info, { Scale = Motion.PULSE_SCALE }):Play()
end

return Motion
