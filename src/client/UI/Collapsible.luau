--!strict
-- A panel whose 44 px title row toggles its body (docs/DESIGN.md D-030): the
-- event card, the week card, the state list, the Draft board on phones. The
-- title row reads "Title +" when collapsed and "Title −" (minus) when expanded.
-- The panel grows with its body (AutomaticSize Y), so it belongs in a list
-- layout. The body is a details area (Kit.details): longer text is allowed
-- there, because the player opened it (UI audit rule wallOfText).
--
--   local card = Collapsible.new(parent, { title = "Week card", expanded = false,
--       name = "WeekCard", order = 5, onToggle = function(expanded) end })
--   card:setTitle(text)
--   card:setExpanded(expanded)     -- does not call onToggle
--   card:isExpanded() -> boolean
--   card.root    Frame (opts.name, default "Collapsible"): a Kit.panel
--   card.toggle  TextButton "Toggle", the title row (attribute Expanded)
--   card.body    Frame "Body": put content here; it has a vertical list (gap xs)

local Kit = require(script.Parent.Kit)

local Collapsible = {}

local COLLAPSED = "+" -- Gotham has no ▾/▴ (they render as boxes)
local EXPANDED = "−" -- U+2212, the same width as "+"

export type Options = {
	title: string,
	expanded: boolean?, -- default false
	name: string?,
	order: number?, -- LayoutOrder of the root
	onToggle: ((expanded: boolean) -> ())?, -- after a tap on the title row
}

export type Collapsible = {
	root: Frame,
	toggle: TextButton,
	body: Frame,
	setTitle: (self: Collapsible, text: string) -> (),
	setExpanded: (self: Collapsible, expanded: boolean) -> (),
	isExpanded: (self: Collapsible) -> boolean,
}

function Collapsible.new(parent: Instance, options: Options): Collapsible
	local title = options.title
	local expanded = options.expanded == true

	local root = Kit.panel({
		Name = options.name or "Collapsible",
		LayoutOrder = options.order or 0,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	Kit.list("Vertical", Kit.space.xs).Parent = root

	local card: Collapsible
	local toggle = Kit.button("", function()
		card:setExpanded(not expanded)
		local handler = options.onToggle
		if handler then
			handler(expanded)
		end
	end, {
		variant = "secondary",
		Name = "Toggle",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Font = Kit.font.bold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	})
	local body = Kit.box({
		Name = "Body",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	Kit.list("Vertical", Kit.space.xs).Parent = body
	Kit.details(body)

	local function render()
		toggle.Text = `{title} {if expanded then EXPANDED else COLLAPSED}`
		toggle:SetAttribute("Expanded", expanded)
		body.Visible = expanded
	end

	card = {
		root = root,
		toggle = toggle,
		body = body,
		setTitle = function(_self: Collapsible, text: string)
			title = text
			render()
		end,
		setExpanded = function(_self: Collapsible, value: boolean)
			expanded = value
			render()
		end,
		isExpanded = function(_self: Collapsible): boolean
			return expanded
		end,
	}
	render()
	root.Parent = parent
	return card
end

return Collapsible
