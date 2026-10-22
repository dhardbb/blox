--!strict
-- Layout pieces shared by the Lobby, Select and Results screens: a page with an
-- optional pinned header and footer around a scrolling, centered column (capped
-- width on wide screens, full width on phone portrait), and grids whose column
-- count the screen sets from ctx.portrait().

local Kit = require(script.Parent.Parent.Parent.UI.Kit)

local Layout = {}

Layout.GAP = 8 -- px between grid cells and stacked rows
-- The corner Debug button (App.client.luau) is 72 x 44 px with a 6 px margin; keep
-- pinned footers clear of it: sideways on landscape, above it on portrait.
Layout.DEBUG_INSET = 84 -- px
Layout.DEBUG_DROP = 52 -- px

export type Page = {
	root: Frame,
	header: Frame?, -- pinned lane above the scroll area
	content: Frame, -- the vertical column inside the scroll area
	scroll: ScrollingFrame,
	footer: Frame?, -- pinned lane below the scroll area
	setPortrait: (portrait: boolean) -> (),
}

export type PageOptions = {
	maxWidth: number, -- px, the widest the column gets
	header: number?, -- px height of the pinned header
	footer: number?, -- px height of the pinned footer
}

-- A frame centered in `parent` that never grows wider than `maxWidth`.
function Layout.lane(parent: Instance, maxWidth: number, props: { [string]: any }?): Frame
	local lane = Kit.box(props)
	lane.AnchorPoint = Vector2.new(0.5, 0)
	lane.Position = UDim2.fromScale(0.5, 0)
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(maxWidth, math.huge), Parent = lane })
	lane.Parent = parent
	return lane
end

function Layout.page(parent: Instance, options: PageOptions): Page
	local headerH = options.header or 0
	local footerH = options.footer or 0
	local root = Kit.box({ Name = "Page", Parent = parent })

	local header: Frame? = nil
	if headerH > 0 then
		header = Layout.lane(root, options.maxWidth, { Name = "Header", Size = UDim2.new(1, 0, 0, headerH) })
	end

	local scroll = Kit.new("ScrollingFrame", {
		Name = "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 6,
		Parent = root,
	}) :: ScrollingFrame
	local content = Layout.lane(scroll, options.maxWidth, {
		Name = "Content",
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	})
	Kit.list("Vertical", 12).Parent = content
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, if footerH > 0 then 12 else Layout.DEBUG_DROP + 8),
		Parent = content,
	})

	local footerBar: Frame? = nil
	local footerPad: UIPadding? = nil
	local footer: Frame? = nil
	if footerH > 0 then
		local bar = Kit.box({ Name = "FooterBar", AnchorPoint = Vector2.new(0, 1), Parent = root })
		footerBar = bar
		footerPad = Kit.new("UIPadding", { Parent = bar })
		footer = Layout.lane(bar, options.maxWidth, { Name = "Footer", Size = UDim2.fromScale(1, 1) })
	end

	local function setPortrait(portrait: boolean)
		local inset = if portrait then 0 else Layout.DEBUG_INSET
		local drop = if portrait then Layout.DEBUG_DROP else 0
		local top = if headerH > 0 then headerH + Layout.GAP else 0
		local bottom = if footerH > 0 then footerH + drop + Layout.GAP else 0
		scroll.Position = UDim2.fromOffset(0, top)
		scroll.Size = UDim2.new(1, 0, 1, -(top + bottom))
		if footerBar and footerPad then
			footerBar.Size = UDim2.new(1, 0, 0, footerH)
			footerBar.Position = UDim2.new(0, 0, 1, -drop)
			footerPad.PaddingRight = UDim.new(0, inset)
		end
	end
	setPortrait(false)

	return {
		root = root,
		header = header,
		content = content,
		scroll = scroll,
		footer = footer,
		setPortrait = setPortrait,
	}
end

-- A grid that grows with its cells. Call Layout.setGrid to choose columns.
function Layout.grid(parent: Instance, name: string, order: number): (Frame, UIGridLayout)
	local frame = Kit.box({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	local layout = Kit.new("UIGridLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = frame,
	}) :: UIGridLayout
	return frame, layout
end

-- `columns` equal cells across, each `height` px tall, `gap` px apart.
function Layout.setGrid(layout: UIGridLayout, columns: number, height: number, gap: number?)
	local g = gap or Layout.GAP
	-- The extra pixel keeps rounding from pushing the last cell onto a new row.
	layout.CellPadding = UDim2.fromOffset(g, g)
	layout.CellSize = UDim2.new(1 / columns, -(g * (columns - 1) / columns) - 1, 0, height)
end

-- A section heading.
function Layout.heading(parent: Instance, text: string, order: number, name: string?): TextLabel
	return Kit.text(text, {
		Name = name or "Heading",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 26),
		Font = Kit.font.bold,
		TextSize = Kit.size.large,
		TextScaled = true,
		Parent = parent,
	})
end

return Layout
