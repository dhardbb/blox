--!strict
-- DEBUG_UI checks (PLAN.md "Because you cannot see the UI"; docs/DESIGN.md
-- D-030): after a screen is laid out, log its size and warn loudly about anything
-- that breaks the design system. Warnings start with "[270] UI audit" so tests
-- and agents can grep the Output for them. The Router runs it 0.5 s after a
-- screen mounts and again after the orientation flips, only in Studio or when
-- DebugScreen / DebugText is set.
--
-- Rules (Audit.Rule):
--   buttonHeight  a visible button off the map is under 44 px tall
--   buttonWidth   a visible button off the map is under 44 px wide
--   mapNodes      a map button (inside "NodeMap") is under Kit.MAP_NODE_MIN in either direction
--   truncated     a text that neither wraps nor scales does not fit
--   textFloor     a text under Kit.MIN_TEXT, or TextScaled without a UITextSizeConstraint
--                 whose MinTextSize is at least Kit.MIN_TEXT
--   typeScale     a text size that is not one of the five Kit.size tokens (TextScaled
--                 texts are judged by their MaxTextSize)
--   contained     a visible object pokes more than 1 px outside the screen, outside its
--                 parent (when the parent has no list/grid layout and no AutomaticSize),
--                 or, under a ScrollingFrame, outside the frame's width (vertical
--                 overflow is what scrolling is for)
--   primary       not exactly one visible button with attribute PrimaryAction (zero is
--                 fine when the screen root has attribute PrimaryOptional = true), or the
--                 primary sits in a ScrollingFrame or outside the screen
--   oneAccent     more than one visible button filled with the accent color
--
-- Transition (UI overhaul v0.4.0): the screens are redesigned one work package
-- at a time, so findings a screen is known to have are reported as "pending"
-- (printed, not counted, no WARN) until its package lands. Audit.PENDING lists,
-- per audit label (the screen name), the rules still pending there; the key
-- "NodeMap" covers everything inside the node map on any screen. To make a screen
-- strict, delete its entry. `Audit.run(root, label, { strict = true })` ignores
-- PENDING altogether (the specs use it to prove a screen is clean).

local Kit = require(script.Parent.Kit)

local Audit = {}

export type Rule =
	"buttonHeight"
	| "buttonWidth"
	| "mapNodes"
	| "truncated"
	| "textFloor"
	| "typeScale"
	| "contained"
	| "primary"
	| "oneAccent"

export type Finding = {
	rule: Rule,
	name: string, -- the offending instance's Name (the root's for screen-wide rules)
	message: string,
	onMap: boolean, -- inside a NodeMap
}

export type Options = {
	strict: boolean?, -- ignore Audit.PENDING
}

-- Rules each screen still breaks while the overhaul is in progress. Each work
-- package empties (deletes) its own entries; keep one entry per line.
Audit.PENDING = {
	-- WP1 (map): NodeMap tap targets under 36 px, label/badge sizes, badges overhanging nodes.
	NodeMap = { mapNodes = true, typeScale = true, contained = true },
	-- WP2: Lobby, Select, Results.
	Lobby = { primary = true, typeScale = true },
	Select = { primary = true, oneAccent = true },
	Results = { primary = true, typeScale = true },
	-- WP3: Campaign.
	Campaign = { primary = true, oneAccent = true },
	-- WP4: Draft, Election.
	Draft = { primary = true, typeScale = true },
} :: { [string]: { [Rule]: boolean } }

-- The rules in the order they are reported.
local RULES: { Rule } = {
	"buttonHeight",
	"buttonWidth",
	"mapNodes",
	"truncated",
	"textFloor",
	"typeScale",
	"contained",
	"primary",
	"oneAccent",
}
Audit.RULES = RULES

local TOLERANCE = 1 -- px a box may poke outside before it counts
local SCALE: { [number]: boolean } = {
	[Kit.size.caption] = true,
	[Kit.size.body] = true,
	[Kit.size.heading] = true,
	[Kit.size.title] = true,
	[Kit.size.hero] = true,
}

local function isText(inst: Instance): boolean
	return inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")
end

local function sameColor(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.003 and math.abs(a.G - b.G) < 0.003 and math.abs(a.B - b.B) < 0.003
end

-- An Enum value's name; works with real EnumItems and the fake engine's.
local function enumName(value: any): string
	return if value == nil then "None" else tostring(value.Name)
end

-- The size a text is judged by: TextScaled texts by their constraint's maximum.
local function textSizeOf(inst: Instance): number
	local text = inst :: any
	local constraint = inst:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint?
	return if text.TextScaled and constraint then constraint.MaxTextSize else text.TextSize
end

type Rect = { x0: number, y0: number, x1: number, y1: number }

local function rectOf(inst: GuiObject): Rect
	local position, size = inst.AbsolutePosition, inst.AbsoluteSize
	return { x0 = position.X, y0 = position.Y, x1 = position.X + size.X, y1 = position.Y + size.Y }
end

local function outside(inner: Rect, outer: Rect, vertical: boolean): boolean
	if inner.x0 < outer.x0 - TOLERANCE or inner.x1 > outer.x1 + TOLERANCE then
		return true
	end
	return vertical and (inner.y0 < outer.y0 - TOLERANCE or inner.y1 > outer.y1 + TOLERANCE)
end

-- Every finding under `root`, pending or not, and the number of distinct text
-- sizes among the visible texts.
function Audit.check(root: Instance): ({ Finding }, number)
	local findings: { Finding } = {}
	local function add(rule: Rule, inst: Instance, message: string, onMap: boolean)
		table.insert(findings, { rule = rule, name = inst.Name, message = message, onMap = onMap })
	end

	local function visible(inst: Instance): boolean
		local node: Instance? = inst
		while node and node ~= root do
			if node:IsA("GuiObject") and not (node :: GuiObject).Visible then
				return false
			end
			node = node.Parent
		end
		return true
	end

	-- The nearest ScrollingFrame between `inst` and `root`, if any.
	local function scrollerOf(inst: Instance): ScrollingFrame?
		local node = inst.Parent
		while node and node ~= root do
			if node:IsA("ScrollingFrame") then
				return node :: ScrollingFrame
			end
			node = node.Parent
		end
		return nil
	end

	local rootRect: Rect? = if root:IsA("GuiObject") then rectOf(root :: GuiObject) else nil
	local primaries: { GuiButton } = {}
	local sizes: { [number]: boolean } = {}
	local accents: { string } = {}

	for _, inst in root:GetDescendants() do
		if not inst:IsA("GuiObject") or not visible(inst) then
			continue
		end
		local gui = inst :: GuiObject
		local onMap = inst:FindFirstAncestor("NodeMap") ~= nil or inst.Name == "NodeMap"
		local size = gui.AbsoluteSize

		if inst:IsA("GuiButton") then
			local button = inst :: GuiButton
			if onMap then
				if size.X < Kit.MAP_NODE_MIN - 0.5 or size.Y < Kit.MAP_NODE_MIN - 0.5 then
					add(
						"mapNodes",
						inst,
						`map button {inst.Name} is {math.floor(size.X)}x{math.floor(size.Y)}px (min {Kit.MAP_NODE_MIN})`,
						true
					)
				end
			else
				if size.Y < Kit.MIN_TOUCH - 0.5 then
					add(
						"buttonHeight",
						inst,
						`button {inst.Name} is {math.floor(size.Y)}px tall (min 44)`,
						false
					)
				end
				if size.X < Kit.MIN_TOUCH - 0.5 then
					add(
						"buttonWidth",
						inst,
						`button {inst.Name} is {math.floor(size.X)}px wide (min 44)`,
						false
					)
				end
			end
			if button:GetAttribute("PrimaryAction") == true then
				table.insert(primaries, button)
			end
			local fill = button.BackgroundColor3
			if fill and button.BackgroundTransparency < 1 and sameColor(fill, Kit.colors.accent) then
				table.insert(accents, inst.Name)
			end
		end

		if isText(inst) then
			local text = inst :: any
			if text.Text ~= "" then
				local constraint = inst:FindFirstChildOfClass("UITextSizeConstraint") :: UITextSizeConstraint?
				local quoted = string.sub(text.Text, 1, 30)
				if
					not inst:IsA("TextBox")
					and not text.TextWrapped
					and not text.TextScaled
					and not text.TextFits
				then
					add("truncated", inst, `text "{quoted}" in {inst.Name} is truncated`, onMap)
				end
				if text.TextScaled then
					if constraint == nil or constraint.MinTextSize < Kit.MIN_TEXT then
						add(
							"textFloor",
							inst,
							`scaled text "{quoted}" in {inst.Name} can shrink under {Kit.MIN_TEXT}px`,
							onMap
						)
					end
				elseif text.TextSize < Kit.MIN_TEXT then
					add("textFloor", inst, `text "{quoted}" in {inst.Name} is {text.TextSize}px`, onMap)
				end
				local px = textSizeOf(inst)
				sizes[px] = true
				if not SCALE[px] then
					add("typeScale", inst, `text "{quoted}" in {inst.Name} is {px}px (not a Kit.size)`, onMap)
				end
			end
		end

		if rootRect and size.X > 0 and size.Y > 0 then
			local rect = rectOf(gui)
			local scroller = scrollerOf(inst)
			local escapes = if scroller
				then outside(rect, rectOf(scroller), false)
				else outside(rect, rootRect, true)
			local parent = inst.Parent
			if not escapes and parent and parent ~= root and parent:IsA("GuiObject") then
				local p = parent :: GuiObject
				local laidOut = parent:FindFirstChildOfClass("UIListLayout") ~= nil
					or parent:FindFirstChildOfClass("UIGridLayout") ~= nil
				if
					not laidOut
					and not parent:IsA("ScrollingFrame")
					and enumName(p.AutomaticSize) == "None"
				then
					escapes = outside(rect, rectOf(p), true)
				end
			end
			if escapes then
				add(
					"contained",
					inst,
					`{inst.Name} at ({math.floor(rect.x0)}, {math.floor(rect.y0)}) size {math.floor(size.X)}x{math.floor(
						size.Y
					)} pokes outside its parent or the screen`,
					onMap
				)
			end
		end
	end

	local optional = root:GetAttribute("PrimaryOptional") == true
	if #primaries == 0 and not optional then
		add("primary", root, "no visible PrimaryAction button", false)
	elseif #primaries > 1 then
		add("primary", root, `{#primaries} visible PrimaryAction buttons (want 1)`, false)
	end
	for _, button in primaries do
		if scrollerOf(button) then
			add("primary", button, `primary {button.Name} scrolls (it must be pinned)`, false)
		elseif rootRect and outside(rectOf(button), rootRect, true) then
			add("primary", button, `primary {button.Name} is not fully on screen`, false)
		end
	end
	if #accents > 1 then
		add("oneAccent", root, `{#accents} accent-filled buttons: {table.concat(accents, ", ")}`, false)
	end
	local distinct = 0
	for _ in sizes do
		distinct += 1
	end
	return findings, distinct
end

-- Audits every visible GUI object under `root`, warns about each problem and
-- prints one summary line. Returns the number of problems (pending ones excluded).
function Audit.run(root: Instance, label: string, options: Options?): number
	local strict = options ~= nil and options.strict == true
	local screenPending = if strict then nil else Audit.PENDING[label]
	local mapPending = if strict then nil else Audit.PENDING.NodeMap
	local problems = 0
	local pending: { [string]: { string } } = {}
	local pendingCount = 0
	local findings, distinctSizes = Audit.check(root)
	for _, finding in findings do
		local allow = if finding.onMap then mapPending else screenPending
		if allow and allow[finding.rule] then
			pendingCount += 1
			local list = pending[finding.rule] or {}
			pending[finding.rule] = list
			table.insert(list, finding.message)
		else
			problems += 1
			warn(`[270] UI audit {label}: {finding.message}`)
		end
	end
	for _, rule in RULES do
		local list = pending[rule]
		if list then
			print(`[270] UI audit {label} pending {rule}: {#list}, e.g. {list[1]}`)
		end
	end
	local size = if root:IsA("GuiObject") then (root :: GuiObject).AbsoluteSize else nil
	print(
		`[270] UI audit {label}: {problems} problem(s), {pendingCount} pending, {distinctSizes} text size(s){if size
			then ` at {size}`
			else ""}`
	)
	return problems
end

return Audit
