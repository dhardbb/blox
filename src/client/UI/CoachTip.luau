--!strict
-- First-match coach tips (docs/UI-STYLE.md, "Coach tips"): one short line that
-- points at the thing to do next, with a "Got it" button. Each tip shows once
-- per player per session; dismissing it (or pressing the thing it points at,
-- if the screen calls CoachTip.markSeen) hides it for good. Tips never block
-- input and never hold the primary action.
--
--   local tip = CoachTip.show(parent, { id = "campaign.map", order = 2 })
--   -- nil when the tip was already seen or tips are off; else:
--   tip.root  Frame "CoachTip" (attribute TipId) · tip.button TextButton "GotIt"
--   tip:dismiss()                      -- marks it seen and removes it
--   CoachTip.TIPS[id] -> text          -- the copy, one place for all screens
--   CoachTip.seen(id) -> boolean · CoachTip.markSeen(id) · CoachTip.reset()
--   CoachTip.setEnabled(enabled)       -- off: show() returns nil (tests, replays)
--   CoachTip.useStore(store)           -- persist "seen" elsewhere (e.g. the
--                                         saved profile, a later package)
--
-- Arrival (docs/UI-STYLE.md §2.7.1): a tip pops in from 0.9 and fades in, with
-- a soft "pip" (the "select" cue, pitched up) unless `quiet` is set. Under
-- reduced motion it only fades; nothing waits on it.
--
-- Look: a raised card with a 2 px accent outline; a positioned tip also casts
-- a shadow (Kit.shadow).
--
-- Placement: in a list layout pass `order` (LayoutOrder); anywhere else pass
-- `position` and `anchorPoint` (and `width`, default the parent's width, at
-- most 360 px). Keep tips off the map's nodes and off the action bar.

local Audio = require(script.Parent.Audio)
local Kit = require(script.Parent.Kit)
local Motion = require(script.Parent.Motion)

local CoachTip = {}

local MAX_W = 360 -- px, widest a tip gets
local PIP_PITCH = 1.2 -- the "select" cue, pitched up, as a tip appears

-- The copy for every tip, by id: plain words, at most 12 words (KitStyle.spec),
-- one per key moment of the first match (docs/UI-STYLE.md §3.4).
CoachTip.TIPS = table.freeze({
	["select.candidate"] = "Pick your candidate. Each has one big strength and one weakness.",
	["select.issues"] = "Choose 3 issues. Rallies and ads on them hit harder.",
	["draft.pick"] = "Claim a state! Bigger numbers mean more votes.",
	["decision.stance"] = "Take a side, or stay out. States that care will react.",
	["decision.focus"] = "Prep one topic. Win it and its states swing your way.",
	["campaign.map"] = "Tap any state to see who's ahead there.",
	["campaign.actions"] = "Pick your actions, then Lock in. Your plan stays secret.",
	["campaign.lens"] = "These buttons switch the map: votes, issues, polls, money.",
	["reveal.week"] = "Both plans are out! Marked states moved the most.",
	["election.night"] = "States are called one by one. First to 270 wins!",
} :: { [string]: string })

export type Store = {
	get: (id: string) -> boolean,
	set: (id: string) -> (),
}

export type Options = {
	id: string, -- a key of CoachTip.TIPS
	text: string?, -- overrides the copy (prefer adding to TIPS)
	name: string?, -- default "CoachTip"
	order: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	width: number?, -- px
	quiet: boolean?, -- no pip (a tip that comes up with its screen, right after a tap)
}

export type Tip = {
	root: Frame,
	button: TextButton,
	dismiss: (self: Tip) -> (),
}

local seenThisSession: { [string]: boolean } = {}
local store: Store? = nil
local enabled = true

function CoachTip.seen(id: string): boolean
	if seenThisSession[id] then
		return true
	end
	local s = store
	return s ~= nil and s.get(id)
end

function CoachTip.markSeen(id: string)
	seenThisSession[id] = true
	local s = store
	if s then
		s.set(id)
	end
end

function CoachTip.reset()
	table.clear(seenThisSession)
end

function CoachTip.setEnabled(value: boolean)
	enabled = value
end

function CoachTip.useStore(value: Store?)
	store = value
end

-- Shows tip `options.id` in `parent`, or returns nil if it was seen already.
function CoachTip.show(parent: Instance, options: Options): Tip?
	local id = options.id
	local text = options.text or CoachTip.TIPS[id]
	if not enabled or text == nil or CoachTip.seen(id) then
		return nil
	end
	local inList = options.position == nil
	local root = Kit.card({
		Name = options.name or "CoachTip",
		LayoutOrder = options.order or 0,
		BackgroundColor3 = Kit.colors.raised,
		Size = if inList then UDim2.fromScale(1, 0) else UDim2.fromOffset(options.width or MAX_W, 0),
		Position = options.position or UDim2.fromOffset(0, 0),
		AnchorPoint = options.anchorPoint or Vector2.new(0, 0),
		ZIndex = 20,
	})
	root:SetAttribute("TipId", id)
	-- The accent outline is the tip's only stroke (it replaces the card's edge).
	local edge = root:FindFirstChild("Edge")
	if edge then
		edge:Destroy()
	end
	-- A tip is compact: the old md padding, not a card's 14 px.
	local pad = root:FindFirstChildOfClass("UIPadding")
	if pad then
		local px = UDim.new(0, Kit.space.md)
		pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = px, px, px, px
	end
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(MAX_W, math.huge), Parent = root })
	Kit.new("UIStroke", {
		Name = "TipStroke",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Kit.colors.accent,
		Thickness = 2,
		Parent = root,
	})
	local row = Kit.box({
		Name = "Row",
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	Kit.text(text, {
		Name = "TipText",
		Size = UDim2.new(1, -(96 + Kit.space.sm), 0, Kit.MIN_TOUCH),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = row,
	})
	local tip: Tip
	local button = Kit.button("Got it", function()
		tip:dismiss()
	end, {
		variant = "ghost",
		Name = "GotIt",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(96, Kit.MIN_TOUCH),
		TextColor3 = Kit.colors.accent,
		Parent = row,
	})
	tip = {
		root = root,
		button = button,
		dismiss = function(_self: Tip)
			CoachTip.markSeen(id)
			root:Destroy()
		end,
	}
	root.Parent = parent
	Kit.shadow(root) -- a positioned tip only: in a list there is no room for one
	Motion.pop(root, Motion.POP_FROM)
	Motion.enter(root)
	if not options.quiet then
		Audio.play("select", { pitch = PIP_PITCH })
	end
	return tip
end

return CoachTip
