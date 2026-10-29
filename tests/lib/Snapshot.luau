--!strict
-- Headless screenshots: turns a FakeRoblox GUI tree (a client's PlayerGui) into
-- an SVG so agents can look at a screen without Studio (tests/ui/snap.luau).
--
-- The fake engine's own layout skips list, grid and padding layouts (good enough
-- for the audit's checks, not for a picture), so this module lays the tree out
-- again with a closer approximation of Roblox:
--   Size/Position/AnchorPoint against the parent's padded content box,
--   UIPadding, UIListLayout (alignment, padding, Wraps, UIFlexItem Fill),
--   UIGridLayout, UISizeConstraint, UIAspectRatioConstraint, AutomaticSize
--   (frames from their children, texts from an estimate of their bounds),
--   ScrollingFrame (clipped at CanvasPosition 0; a "+N px below" marker shows
--   how much is hidden), ClipsDescendants, ZIndex (sibling order), Rotation.
-- Drawn: BackgroundColor3/Transparency, UICorner (per-corner radii as a path),
-- UIStroke (border, or text outline when Contextual on a text), UIGradient
-- (Color and Transparency keypoints and Rotation, on the fill and the text of
-- its parent, or on the border of its parent UIStroke), UIScale (around the
-- object's anchor point), CanvasGroup.GroupTransparency, text with color, size,
-- font weight, X/Y alignment, wrapping, TextScaled (UITextSizeConstraint),
-- TextTruncate, TextStroke. Images: a Kit.icon image as its glyph in a dashed
-- box of its tint; a decoration image (attribute Asset, UI/Assets) as a
-- stand-in: "shadow" four stacked rounded rects (a fake blur: qlmanage drops
-- SVG filters) under the object named by its Follow attribute, "glow" a radial
-- gradient in ImageColor3, "dots" a dot pattern, "mapShape" the state's
-- outline (attribute MapShape, from Shared/UI/MapShape) filled in ImageColor3,
-- "mapBorders" (and "mapInk") every state's outline stroked in ImageColor3; a Kit.portrait
-- face (attribute Portrait = candidate id) as assets/portraits/<id>.png,
-- clipped to its UICorner, whether or not the game has its asset id yet (the
-- portrait's stand-in initials, attribute PortraitFallback, are not drawn);
-- a Kit.issueIcon image (attribute IssueIcon = issue) as its PNG from
-- assets/issues/ (UI/IssueIcons) tinted in its ImageColor3 (a mask), uploaded
-- or not;
-- any other image as a labeled
-- dashed box. Text widths are estimated (Builder Sans and Gotham
-- are drawn as Helvetica; the handwriting fonts in their own faces), so line
-- breaks are close to Studio, not exact.
--
-- Not drawn: UIGradient Offset, Scale and Type, TileMode; a UIGradient's effect
-- on its parent's UIStroke; Rotation's effect on clipping; images' real pixels
-- (except the portraits and the issue symbols).
--
-- Snapshot.svg(peer, options?) -> string
--   options.topInset  px the Roblox top bar takes from ScreenGuis that respect
--                     the core UI inset (default 58; drawn as a dim strip)
--   options.square    pad the picture to a square, content centered (qlmanage
--                     only renders square thumbnails; snap.luau crops it back)
-- The world's screen may carry device safe-area insets (FakeRoblox.Screen left,
-- right, bottom, deviceTop): a gui that respects them is laid out inside them,
-- the notch is drawn as a black cutout on the side it is on (the left in
-- landscape, the top in portrait) and the home bar as a white pill.
--
-- Snapshot.boxes(peer, options?) -> { [Name]: Box }: where each visible element
-- is drawn and what of it its scrolling ancestors leave in view (specs that
-- need list layouts, e.g. tests/ui/PortraitPhone.spec).
--
-- Snapshot.measure(peer, options?) -> Measure: the same layout, measured (the
-- orientation study): the map's drawn size, the smallest visible text, visible
-- buttons under 44 px (off the map and on it), and how far content runs past a
-- scrolling frame or the screen's bottom.

local fs = require("@lune/fs")

local Icons = require("../../src/client/UI/Icons")
local IssueIcons = require("../../src/client/UI/IssueIcons")
local MapShape = require("../../src/shared/UI/MapShape")

local Snapshot = {}

export type Options = {
	topInset: number?,
	square: boolean?,
}

type Node = {
	inst: any,
	x: number, -- relative to the parent node's top-left corner
	y: number,
	w: number,
	h: number,
	children: { Node },
	contentH: number?, -- ScrollingFrame: height of what it holds
	text: { string }?, -- wrapped lines
	textSize: number?,
}

local GUI = {
	Frame = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
	ImageButton = true,
	ScrollingFrame = true,
	CanvasGroup = true,
	ViewportFrame = true,
}
local TEXT = { TextLabel = true, TextButton = true, TextBox = true }

local function props(inst: any): { [string]: any }
	return rawget(inst, "_props")
end

local function class(inst: any): string
	return rawget(inst, "_class")
end

local function kids(inst: any): { any }
	return rawget(inst, "_children")
end

local function enum(value: any, default: string): string
	return if value == nil then default else tostring(value.Name)
end

local function childOf(inst: any, className: string): any
	for _, child in kids(inst) do
		if class(child) == className then
			return child
		end
	end
	return nil
end

local function attrs(inst: any): { [string]: any }
	return rawget(inst, "_attributes") or {}
end

local function udim(value: any, total: number): number
	if value == nil then
		return 0
	end
	return value.Scale * total + value.Offset
end

-- ------------------------------------------------------------- text metrics

-- Approximate advance of one character in em (Gotham-like proportions).
local function charWidth(c: string, bold: boolean): number
	local w
	if string.find(c, "^[ilj'|!.,:;]$") then
		w = 0.28
	elseif string.find(c, "^[ftrI%(%)%[%]]$") then
		w = 0.36
	elseif string.find(c, "^[mwMW]$") then
		w = 0.86
	elseif string.find(c, "^[A-Z]$") then
		w = 0.68
	elseif string.find(c, "^[0-9]$") then
		w = 0.6
	elseif string.byte(c) and (string.byte(c) :: number) >= 0xC0 then
		w = 0.85 -- glyphs and symbols
	else
		w = 0.55
	end
	return if bold then w * 1.07 else w
end

local function utf8chars(s: string): { string }
	local out = {}
	for _, code in utf8.codes(s) do
		table.insert(out, utf8.char(code))
	end
	return out
end

local function measure(s: string, size: number, bold: boolean, mono: boolean): number
	local w = 0
	for _, c in utf8chars(s) do
		w += if mono then 0.6 else charWidth(c, bold)
	end
	return w * size
end

local function stripRich(s: string): string
	return (string.gsub(s, "<[^>]+>", ""))
end

-- The board's handwriting fonts (Kit.font.display and hand, D-102): drawn in
-- their real faces, embedded from tests/lib/fonts (Google Fonts, OFL/Apache),
-- so a picture shows the look instead of Helvetica.
local HAND_FONTS: { [string]: { family: string, file: string } } = {
	PermanentMarker = { family = "Permanent Marker", file = "tests/lib/fonts/PermanentMarker-Regular.ttf" },
	PatrickHand = { family = "Patrick Hand", file = "tests/lib/fonts/PatrickHand-Regular.ttf" },
}

local function fontOf(p: { [string]: any }): (boolean, boolean, string)
	local font = enum(p.Font, "Legacy")
	-- Fredoka One (Kit.font.display) has one heavy weight: draw it bold.
	local bold = string.find(font, "Bold") ~= nil
		or string.find(font, "Black") ~= nil
		or string.find(font, "Fredoka") ~= nil
	local medium = string.find(font, "Medium") ~= nil or string.find(font, "Semi") ~= nil
	local mono = font == "Code" or font == "RobotoMono"
	local weight = if bold then "700" elseif medium then "500" else "400"
	return bold, mono, weight
end

local LINE = 1.2 -- line height in em

-- Lines of `text` wrapped to `width` (no wrapping when width is nil).
local function wrap(text: string, size: number, bold: boolean, mono: boolean, width: number?): { string }
	local lines = {}
	for paragraph in string.gmatch(text .. "\n", "(.-)\n") do
		if width == nil then
			table.insert(lines, paragraph)
			continue
		end
		local line = ""
		for word in string.gmatch(paragraph, "%S+") do
			local candidate = if line == "" then word else line .. " " .. word
			if line ~= "" and measure(candidate, size, bold, mono) > width then
				table.insert(lines, line)
				line = word
			else
				line = candidate
			end
		end
		table.insert(lines, line)
	end
	return lines
end

local function widest(lines: { string }, size: number, bold: boolean, mono: boolean): number
	local w = 0
	for _, line in lines do
		w = math.max(w, measure(line, size, bold, mono))
	end
	return w
end

-- ------------------------------------------------------------- layout

local DEFAULT_SIZE: { [string]: { number } } = {
	TextLabel = { 200, 50 },
	TextButton = { 200, 50 },
	TextBox = { 200, 50 },
}

local function visibleGui(inst: any): boolean
	return GUI[class(inst)] == true and props(inst).Visible ~= false
end

local function padding(inst: any, w: number, h: number): (number, number, number, number)
	local pad = childOf(inst, "UIPadding")
	if pad == nil then
		return 0, 0, 0, 0
	end
	local p = props(pad)
	return udim(p.PaddingLeft, w), udim(p.PaddingRight, w), udim(p.PaddingTop, h), udim(p.PaddingBottom, h)
end

local function constrain(inst: any, w: number, h: number): (number, number)
	for _, child in kids(inst) do
		local c = class(child)
		local p = props(child)
		if c == "UISizeConstraint" then
			if p.MaxSize then
				w, h = math.min(w, p.MaxSize.X), math.min(h, p.MaxSize.Y)
			end
			if p.MinSize then
				w, h = math.max(w, p.MinSize.X), math.max(h, p.MinSize.Y)
			end
		elseif c == "UIAspectRatioConstraint" then
			local ratio = p.AspectRatio or 1
			local kind = enum(p.AspectType, "FitWithinMaxSize")
			local dominant = enum(p.DominantAxis, "Width")
			if kind == "ScaleWithParentSize" then
				if dominant == "Width" then
					h = w / ratio
				else
					w = h * ratio
				end
			elseif w / math.max(h, 1e-6) > ratio then
				w = h * ratio
			else
				h = w / ratio
			end
		end
	end
	return w, h
end

local layoutNode: (inst: any, availW: number, availH: number, forced: { number }?) -> Node

-- Sizes of a text's content: wrapped lines and the size they are drawn at.
local function layoutText(node: Node)
	local p = props(node.inst)
	local raw = tostring(p.Text or "")
	if class(node.inst) == "TextBox" and raw == "" then
		raw = tostring(p.PlaceholderText or "")
	end
	if p.RichText then
		raw = stripRich(raw)
	end
	local bold, mono = fontOf(p)
	local pl, pr, pt, pb = padding(node.inst, node.w, node.h)
	local boxW, boxH = math.max(1, node.w - pl - pr), math.max(1, node.h - pt - pb)
	local size = p.TextSize or 14
	local autoX = enum(p.AutomaticSize, "None") == "X" or enum(p.AutomaticSize, "None") == "XY"
	local wrapped = p.TextWrapped == true and not autoX
	if p.TextScaled then
		local constraint = childOf(node.inst, "UITextSizeConstraint")
		local maxSize = if constraint then props(constraint).MaxTextSize or 100 else 100
		local minSize = if constraint then props(constraint).MinTextSize or 1 else 1
		size = minSize
		local s = math.floor(maxSize)
		while s >= minSize do
			local lines = wrap(raw, s, bold, mono, if wrapped then boxW else nil)
			local fitsWidth = widest(lines, s, bold, mono) <= boxW + 0.5
			if #lines * s * LINE <= boxH + 0.5 and fitsWidth then
				size = s
				break
			end
			s -= 1
		end
	end
	local lines = wrap(raw, size, bold, mono, if wrapped then boxW else nil)
	if not wrapped and enum(p.TextTruncate, "None") == "AtEnd" then
		for i, line in lines do
			if measure(line, size, bold, mono) > boxW then
				local chars = utf8chars(line)
				local cut = ""
				for _, c in chars do
					if measure(cut .. c .. "…", size, bold, mono) > boxW then
						break
					end
					cut ..= c
				end
				lines[i] = cut .. "…"
			end
		end
	end
	node.text = lines
	node.textSize = size
end

local function textExtent(node: Node): (number, number)
	local p = props(node.inst)
	local bold, mono = fontOf(p)
	local size = node.textSize or 14
	local lines = node.text or {}
	return widest(lines, size, bold, mono), #lines * size * LINE
end

-- Lays out the GUI children of `node` inside its padded content box.
local function layoutChildren(node: Node)
	local inst = node.inst
	local pl, pr, pt, pb = padding(inst, node.w, node.h)
	local cw, ch = math.max(0, node.w - pl - pr), math.max(0, node.h - pt - pb)
	local scrolling = class(inst) == "ScrollingFrame"
	if scrolling then
		local canvas = props(inst).CanvasSize
		local canvasH = udim(canvas and canvas.Y, node.h)
		if canvasH > 0 then
			ch = math.max(0, canvasH - pt - pb)
		end
	end
	local guis: { any } = {}
	for _, child in kids(inst) do
		if visibleGui(child) then
			table.insert(guis, child)
		end
	end
	node.children = {}
	local list = childOf(inst, "UIListLayout")
	local grid = childOf(inst, "UIGridLayout")
	local layout = list or grid
	if layout then
		local lp = props(layout)
		local order: { [any]: number } = {}
		for i, child in guis do
			order[child] = i
		end
		local byName = enum(lp.SortOrder, "LayoutOrder") == "Name"
		table.sort(guis, function(a, b)
			if byName then
				return tostring(props(a).Name) < tostring(props(b).Name)
			end
			local la, lb = props(a).LayoutOrder or 0, props(b).LayoutOrder or 0
			if la ~= lb then
				return la < lb
			end
			return order[a] < order[b]
		end)
	end

	if list then
		local lp = props(list)
		local horizontal = enum(lp.FillDirection, "Vertical") == "Horizontal"
		local gap = udim(lp.Padding, if horizontal then cw else ch)
		local hAlign = enum(lp.HorizontalAlignment, "Left")
		local vAlign = enum(lp.VerticalAlignment, "Top")
		local wraps = lp.Wraps == true and horizontal
		local nodes: { Node } = {}
		local total = 0
		local fills: { number } = {}
		for i, child in guis do
			local n = layoutNode(child, cw, ch)
			nodes[i] = n
			total += if horizontal then n.w else n.h
			local flex = childOf(child, "UIFlexItem")
			if flex and enum(props(flex).FlexMode, "None") ~= "None" then
				table.insert(fills, i)
			end
		end
		total += gap * math.max(0, #nodes - 1)
		local main = if horizontal then cw else ch
		if #fills > 0 and not wraps and total < main then
			local extra = (main - total) / #fills
			for _, i in fills do
				local n = nodes[i]
				local forced = if horizontal then { n.w + extra, n.h } else { n.w, n.h + extra }
				nodes[i] = layoutNode(guis[i], cw, ch, forced)
			end
			total = main
		end
		-- Rows (one unless Wraps): each a list of node indexes.
		local rows: { { number } } = { {} }
		local cursor = 0
		for i, n in nodes do
			local len = if horizontal then n.w else n.h
			local row = rows[#rows]
			if wraps and #row > 0 and cursor + len > main + 0.5 then
				rows[#rows + 1] = {}
				row = rows[#rows]
				cursor = 0
			end
			table.insert(row, i)
			cursor += len + gap
		end
		local cross = 0
		for _, row in rows do
			local length, thick = 0, 0
			for k, i in row do
				local n = nodes[i]
				length += (if horizontal then n.w else n.h) + (if k > 1 then gap else 0)
				thick = math.max(thick, if horizontal then n.h else n.w)
			end
			local start = 0
			local align = if horizontal then hAlign else vAlign
			if align == "Center" then
				start = (main - length) / 2
			elseif align == "Right" or align == "Bottom" then
				start = main - length
			end
			local at = start
			for _, i in row do
				local n = nodes[i]
				if horizontal then
					n.x = pl + at
					local off = if vAlign == "Center"
						then (if wraps then (thick - n.h) / 2 else (ch - n.h) / 2)
						elseif vAlign == "Bottom" then (if wraps then thick - n.h else ch - n.h)
						else 0
					n.y = pt + cross + off
					at += n.w + gap
				else
					n.y = pt + at
					local off = if hAlign == "Center"
						then (cw - n.w) / 2
						elseif hAlign == "Right" then cw - n.w
						else 0
					n.x = pl + off
					at += n.h + gap
				end
				table.insert(node.children, n)
			end
			cross += thick + gap
		end
	elseif grid then
		local gp = props(grid)
		local cellW = if gp.CellSize then udim(gp.CellSize.X, cw) else 100
		local cellH = if gp.CellSize then udim(gp.CellSize.Y, ch) else 100
		local padX = if gp.CellPadding then udim(gp.CellPadding.X, cw) else 5
		local padY = if gp.CellPadding then udim(gp.CellPadding.Y, ch) else 5
		local perRow = math.max(1, math.floor((cw + padX + 0.5) / (cellW + padX)))
		local maxCells = gp.FillDirectionMaxCells or 0
		if maxCells > 0 then
			perRow = math.min(perRow, maxCells)
		end
		local center = enum(gp.HorizontalAlignment, "Left") == "Center"
		for i, child in guis do
			local n = layoutNode(child, cw, ch, { cellW, cellH })
			local col = (i - 1) % perRow
			local row = (i - 1) // perRow
			local inRow = math.min(perRow, #guis - row * perRow)
			local rowW = inRow * cellW + (inRow - 1) * padX
			local start = if center then (cw - rowW) / 2 else 0
			n.x = pl + start + col * (cellW + padX)
			n.y = pt + row * (cellH + padY)
			table.insert(node.children, n)
		end
	else
		for _, child in guis do
			local n = layoutNode(child, cw, ch)
			local p = props(child)
			local pos, anchor = p.Position, p.AnchorPoint
			n.x = pl + (if pos then udim(pos.X, cw) else 0) - (if anchor then anchor.X * n.w else 0)
			n.y = pt + (if pos then udim(pos.Y, ch) else 0) - (if anchor then anchor.Y * n.h else 0)
			table.insert(node.children, n)
		end
	end
end

local function contentBottom(node: Node): (number, number)
	local right, bottom = 0, 0
	for _, child in node.children do
		right = math.max(right, child.x + child.w)
		bottom = math.max(bottom, child.y + child.h)
	end
	return right, bottom
end

layoutNode = function(inst: any, availW: number, availH: number, forced: { number }?): Node
	local p = props(inst)
	local c = class(inst)
	local w, h
	if forced then
		w, h = forced[1], forced[2]
	elseif p.Size then
		w, h = udim(p.Size.X, availW), udim(p.Size.Y, availH)
	else
		local default = DEFAULT_SIZE[c] or { 100, 100 }
		w, h = default[1], default[2]
	end
	w, h = constrain(inst, math.max(0, w), math.max(0, h))
	local node: Node = { inst = inst, x = 0, y = 0, w = w, h = h, children = {} }
	local auto = enum(p.AutomaticSize, "None")
	if TEXT[c] then
		layoutText(node)
	end
	layoutChildren(node)
	if auto ~= "None" then
		local pl, pr, pt, pb = padding(inst, w, h)
		local right, bottom = contentBottom(node)
		local growW, growH = right + pr, bottom + pb
		if TEXT[c] then
			local tw, th = textExtent(node)
			growW = math.max(growW, pl + tw + pr)
			growH = math.max(growH, pt + th + pb)
		end
		local nw = if auto == "X" or auto == "XY" then math.max(w, growW) else w
		local nh = if auto == "Y" or auto == "XY" then math.max(h, growH) else h
		nw, nh = constrain(inst, nw, nh)
		if nw ~= w or nh ~= h then
			node.w, node.h = nw, nh
			if TEXT[c] then
				layoutText(node)
			end
			layoutChildren(node)
		end
	end
	if c == "ScrollingFrame" then
		local _, bottom = contentBottom(node)
		local _, _, _, pb = padding(inst, node.w, node.h)
		node.contentH = bottom + pb
	end
	return node
end

-- ------------------------------------------------------------- drawing

local function esc(s: string): string
	s = string.gsub(s, "&", "&amp;")
	s = string.gsub(s, "<", "&lt;")
	s = string.gsub(s, ">", "&gt;")
	s = string.gsub(s, '"', "&quot;")
	return s
end

local function hex(color: any, default: string): string
	if color == nil then
		return default
	end
	local function ch(v: number): number
		return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
	end
	return string.format("#%02x%02x%02x", ch(color.R), ch(color.G), ch(color.B))
end

local function num(v: number): string
	return string.format("%.1f", v)
end

local function radiusOf(inst: any, w: number, h: number): number
	local corner = childOf(inst, "UICorner")
	if corner == nil then
		return 0
	end
	local r = props(corner).CornerRadius
	local value = if r then r.Scale * math.min(w, h) + r.Offset else 8
	return math.clamp(value, 0, math.min(w, h) / 2)
end

-- The four corner radii (top-left, top-right, bottom-right, bottom-left), or
-- nil when every corner is the same (a plain rx).
local function cornersOf(inst: any, w: number, h: number): { number }?
	local corner = childOf(inst, "UICorner")
	if corner == nil then
		return nil
	end
	local p = props(corner)
	if
		p.TopLeftRadius == nil
		and p.TopRightRadius == nil
		and p.BottomRightRadius == nil
		and p.BottomLeftRadius == nil
	then
		return nil
	end
	local base = radiusOf(inst, w, h)
	local function one(value: any): number
		if value == nil then
			return base
		end
		return math.clamp(value.Scale * math.min(w, h) + value.Offset, 0, math.min(w, h) / 2)
	end
	return { one(p.TopLeftRadius), one(p.TopRightRadius), one(p.BottomRightRadius), one(p.BottomLeftRadius) }
end

type Out = {
	lines: { string },
	clips: number,
	ids: number,
	portraits: { [string]: boolean },
	fonts: { [string]: boolean }, -- the board's handwriting fonts this picture uses (embedded once at the end)
}

local function emit(out: Out, s: string)
	table.insert(out.lines, s)
end

local function nextId(out: Out, prefix: string): string
	out.ids += 1
	return `{prefix}{out.ids}`
end

local WHITE = { R = 1, G = 1, B = 1 }

-- A sequence's value at `t` (keypoints sorted by Time; numbers or Color3s).
local function sample(points: { any }, t: number): any
	if #points == 0 then
		return nil
	end
	if t <= points[1].Time then
		return points[1].Value
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if t <= b.Time then
			local k = if b.Time > a.Time then (t - a.Time) / (b.Time - a.Time) else 1
			if type(a.Value) == "number" then
				return a.Value + (b.Value - a.Value) * k
			end
			return {
				R = a.Value.R + (b.Value.R - a.Value.R) * k,
				G = a.Value.G + (b.Value.G - a.Value.G) * k,
				B = a.Value.B + (b.Value.B - a.Value.B) * k,
			}
		end
	end
	return points[#points].Value
end

-- Defines a linearGradient for UIGradient `gradient` over the box (x, y, w, h)
-- of a paint of `base` color at `alpha`, and returns its id. UIGradient
-- multiplies the paint's color and transparency; Rotation 0 runs left to
-- right, 90 top to bottom.
local function gradientDef(
	out: Out,
	gradient: any,
	x: number,
	y: number,
	w: number,
	h: number,
	base: any,
	alpha: number
): string
	local gp = props(gradient)
	local colors = if gp.Color
		then gp.Color.Keypoints
		else { { Time = 0, Value = WHITE }, { Time = 1, Value = WHITE } }
	local fades = if gp.Transparency
		then gp.Transparency.Keypoints
		else { { Time = 0, Value = 0 }, { Time = 1, Value = 0 } }
	local times: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, list in { colors, fades } do
		for _, point in list do
			if not seen[point.Time] then
				seen[point.Time] = true
				table.insert(times, point.Time)
			end
		end
	end
	table.sort(times)
	local theta = math.rad(gp.Rotation or 0)
	local dx, dy = math.cos(theta), math.sin(theta)
	local length = math.abs(w * dx) + math.abs(h * dy)
	local cx, cy = x + w / 2, y + h / 2
	local id = nextId(out, "g")
	local stops = {}
	local color = base or WHITE
	for _, t in times do
		local c = sample(colors, t) or WHITE
		local fade = sample(fades, t) or 0
		table.insert(
			stops,
			string.format(
				'<stop offset="%s" stop-color="%s" stop-opacity="%s"/>',
				string.format("%.3f", t),
				hex({ R = c.R * color.R, G = c.G * color.G, B = c.B * color.B }, "#ffffff"),
				string.format("%.3f", math.clamp((1 - fade) * alpha, 0, 1))
			)
		)
	end
	emit(
		out,
		string.format(
			'<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%s" y1="%s" x2="%s" y2="%s">%s</linearGradient>',
			id,
			num(cx - dx * length / 2),
			num(cy - dy * length / 2),
			num(cx + dx * length / 2),
			num(cy + dy * length / 2),
			table.concat(stops)
		)
	)
	return id
end

local function enabledChild(inst: any, className: string): any
	local child = childOf(inst, className)
	if child and props(child).Enabled ~= false then
		return child
	end
	return nil
end

-- The start of a rounded box element: a rect with rx, or a path when the
-- corners differ. The caller appends its paint attributes and "/>".
local function shapeAt(x: number, y: number, w: number, h: number, r: number, corners: { number }?): string
	if corners == nil then
		return string.format(
			'<rect x="%s" y="%s" width="%s" height="%s" rx="%s"',
			num(x),
			num(y),
			num(w),
			num(h),
			num(r)
		)
	end
	local tl, tr, br, bl = corners[1], corners[2], corners[3], corners[4]
	return string.format(
		'<path d="M %s %s H %s A %s %s 0 0 1 %s %s V %s A %s %s 0 0 1 %s %s H %s A %s %s 0 0 1 %s %s V %s A %s %s 0 0 1 %s %s Z"',
		num(x + tl),
		num(y),
		num(x + w - tr),
		num(tr),
		num(tr),
		num(x + w),
		num(y + tr),
		num(y + h - br),
		num(br),
		num(br),
		num(x + w - br),
		num(y + h),
		num(x + bl),
		num(bl),
		num(bl),
		num(x),
		num(y + h - bl),
		num(y + tl),
		num(tl),
		num(tl),
		num(x + tl),
		num(y)
	)
end

local function drawText(out: Out, node: Node, ax: number, ay: number)
	local p = props(node.inst)
	local lines = node.text
	if lines == nil or #lines == 0 or (#lines == 1 and lines[1] == "") then
		return
	end
	local isPlaceholder = class(node.inst) == "TextBox" and (p.Text == nil or p.Text == "")
	local opacity = 1 - (p.TextTransparency or 0)
	if opacity <= 0.01 then
		return
	end
	local _, mono, weight = fontOf(p)
	local size = node.textSize or 14
	local pl, pr, pt, pb = padding(node.inst, node.w, node.h)
	local x0, y0 = ax + pl, ay + pt
	local bw, bh = node.w - pl - pr, node.h - pt - pb
	local xAlign = enum(p.TextXAlignment, "Center")
	local yAlign = enum(p.TextYAlignment, "Center")
	local blockH = #lines * size * LINE
	local top = if yAlign == "Top"
		then y0
		elseif yAlign == "Bottom" then y0 + bh - blockH
		else y0 + (bh - blockH) / 2
	local anchor, tx = "start", x0
	if xAlign == "Center" then
		anchor, tx = "middle", x0 + bw / 2
	elseif xAlign == "Right" then
		anchor, tx = "end", x0 + bw
	end
	local fill = if isPlaceholder then hex(p.PlaceholderColor3, "#8a8f9c") else hex(p.TextColor3, "#1b2a35")
	local gradient = enabledChild(node.inst, "UIGradient")
	if gradient and not isPlaceholder then
		fill = `url(#{gradientDef(out, gradient, ax, ay, node.w, node.h, p.TextColor3, 1)})`
	end
	local fontName = enum(p.Font, "Legacy")
	local hand = HAND_FONTS[fontName]
	local family = if hand
		then `'{hand.family}', 'Helvetica Neue', Helvetica, sans-serif`
		elseif mono then "Menlo, Consolas, monospace"
		else "Gotham, Montserrat, 'Helvetica Neue', Helvetica, Arial, sans-serif"
	if hand then
		out.fonts[fontName] = true
	end
	local strokeAttr = ""
	local stroke = childOf(node.inst, "UIStroke")
	if
		stroke
		and props(stroke).Enabled ~= false
		and enum(props(stroke).ApplyStrokeMode, "Contextual") == "Contextual"
	then
		local sp = props(stroke)
		strokeAttr = string.format(
			' stroke="%s" stroke-width="%s" stroke-opacity="%s" paint-order="stroke"',
			hex(sp.Color, "#000000"),
			num((sp.Thickness or 1) * 2),
			num(1 - (sp.Transparency or 0))
		)
	elseif p.TextStrokeTransparency ~= nil and p.TextStrokeTransparency < 1 then
		strokeAttr = string.format(
			' stroke="%s" stroke-width="2" stroke-opacity="%s" paint-order="stroke"',
			hex(p.TextStrokeColor3, "#000000"),
			num(1 - p.TextStrokeTransparency)
		)
	end
	for i, line in lines do
		local baseline = top + (i - 1) * size * LINE + size * 0.95
		emit(
			out,
			string.format(
				'<text x="%s" y="%s" font-family="%s" font-size="%s" font-weight="%s" fill="%s" fill-opacity="%s" text-anchor="%s"%s>%s</text>',
				num(tx),
				num(baseline),
				family,
				num(size),
				weight,
				fill,
				num(opacity),
				anchor,
				strokeAttr,
				esc(line)
			)
		)
	end
end

-- A decoration image's stand-in (attribute Asset, UI/Assets): see the header.
local function drawAsset(
	out: Out,
	node: Node,
	ax: number,
	ay: number,
	siblings: { [string]: Node },
	ox: number,
	oy: number
)
	local inst = node.inst
	local p = props(inst)
	local a = attrs(inst)
	local alpha = 1 - (p.ImageTransparency or 0)
	if alpha <= 0.01 then
		return
	end
	local w, h = node.w, node.h
	if a.Asset == "shadow" then
		local dy = a.Dy or 4
		local spread = a.Spread or 12
		local x, y, bw, bh, r = ax + spread, ay + spread, w - 2 * spread, h - 2 * spread, 12
		local target = if type(a.Follow) == "string" then siblings[a.Follow] else nil
		if target then
			x, y, bw, bh = ox + target.x, oy + target.y + dy, target.w, target.h
			r = radiusOf(target.inst, bw, bh)
		end
		local color = hex(p.ImageColor3, "#000000")
		local layers = { 0.07, 0.16, 0.28, 0.45 }
		for i, share in layers do
			local grow = (#layers - i) * 3
			emit(
				out,
				shapeAt(x - grow, y - grow, bw + 2 * grow, bh + 2 * grow, r + grow, nil)
					.. string.format(' fill="%s" fill-opacity="%s"/>', color, num(alpha * share))
			)
		end
	elseif a.Asset == "glow" then
		local rx, ry = w / 2, h / 2
		if enum(p.ScaleType, "Stretch") == "Fit" then
			rx = math.min(w, h) / 2
			ry = rx
		end
		local id = nextId(out, "r")
		local color = hex(p.ImageColor3, "#ffffff")
		local stops = {}
		for _, d in { 0, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1 } do
			table.insert(
				stops,
				string.format(
					'<stop offset="%s" stop-color="%s" stop-opacity="%s"/>',
					num(d),
					color,
					string.format("%.3f", alpha * math.max(0, 1 - d) ^ 2.2)
				)
			)
		end
		emit(
			out,
			string.format(
				'<radialGradient id="%s" cx="0.5" cy="0.5" r="0.5">%s</radialGradient>',
				id,
				table.concat(stops)
			)
		)
		emit(
			out,
			string.format(
				'<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="url(#%s)"/>',
				num(ax + w / 2),
				num(ay + h / 2),
				num(rx),
				num(ry),
				id
			)
		)
	elseif a.Asset == "mapShape" and type(a.MapShape) == "string" then
		-- The state's outline in its sprite rect, filled like the tinted image.
		local shape = MapShape.get(a.MapShape)
		if shape then
			local d = {}
			for _, ring in shape.rings do
				for i = 1, #ring, 2 do
					local x = ax + (ring[i] - shape.x) / shape.w * w
					local y = ay + (ring[i + 1] - shape.y) / shape.h * h
					table.insert(d, string.format("%s%s %s", if i == 1 then "M" else "L", num(x), num(y)))
				end
				table.insert(d, "Z")
			end
			local gradient = enabledChild(inst, "UIGradient")
			local paint
			if gradient then
				local id = gradientDef(out, gradient, ax, ay, w, h, p.ImageColor3, alpha)
				paint = string.format('fill="url(#%s)"', id)
			else
				paint =
					string.format('fill="%s" fill-opacity="%s"', hex(p.ImageColor3, "#ffffff"), num(alpha))
			end
			emit(out, string.format('<path d="%s" fill-rule="evenodd" %s/>', table.concat(d, " "), paint))
		end
	elseif a.Asset == "mapBorders" or a.Asset == "mapInk" then
		-- The border overlay: every state's outline over the land rect, as thick
		-- as the image's lines come out at this size (the ink overlay: its own
		-- rect, Alaska and Hawaii left out).
		local ink = a.Asset == "mapInk"
		local b = if ink then MapShape.data.ink else MapShape.data.borders
		local boxW, boxH = w / b.w, h / b.h
		local ox0, oy0 = ax - b.x * boxW, ay - b.y * boxH
		local width = math.max(0.6, (if ink then 2.6 else 2.2) * w / b.pw)
		local d = {}
		for _, shape in MapShape.list() do
			for _, ring in if ink and (shape.id == "AK" or shape.id == "HI") then {} else shape.rings do
				for i = 1, #ring, 2 do
					local x = ox0 + ring[i] * boxW
					local y = oy0 + ring[i + 1] * boxH
					table.insert(d, string.format("%s%s %s", if i == 1 then "M" else "L", num(x), num(y)))
				end
				table.insert(d, "Z")
			end
		end
		emit(
			out,
			string.format(
				'<path d="%s" fill="none" stroke="%s" stroke-opacity="%s" stroke-width="%s" stroke-linejoin="round"/>',
				table.concat(d, " "),
				hex(p.ImageColor3, "#000000"),
				num(alpha),
				string.format("%.2f", width)
			)
		)
	elseif a.Asset == "dots" then
		local tile = if p.TileSize then udim(p.TileSize.X, w) else 64
		local id = nextId(out, "p")
		emit(
			out,
			string.format(
				'<pattern id="%s" x="%s" y="%s" width="%s" height="%s" patternUnits="userSpaceOnUse"><circle cx="%s" cy="%s" r="1" fill="%s"/></pattern>',
				id,
				num(ax),
				num(ay),
				num(tile),
				num(tile),
				num(tile / 2),
				num(tile / 2),
				hex(p.ImageColor3, "#ffffff")
			)
		)
		emit(
			out,
			string.format(
				'<rect x="%s" y="%s" width="%s" height="%s" fill="url(#%s)" fill-opacity="%s"/>',
				num(ax),
				num(ay),
				num(w),
				num(h),
				id,
				num(alpha)
			)
		)
	end
end

-- Base64 of a binary string (for data: URIs).
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(data: string): string
	local out = table.create(math.ceil(#data / 3))
	for i = 1, #data, 3 do
		local a, b, c = string.byte(data, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local k1, k2 = bit32.extract(n, 18, 6) + 1, bit32.extract(n, 12, 6) + 1
		local k3, k4 = bit32.extract(n, 6, 6) + 1, bit32.extract(n, 0, 6) + 1
		table.insert(
			out,
			string.sub(B64, k1, k1)
				.. string.sub(B64, k2, k2)
				.. (if b then string.sub(B64, k3, k3) else "=")
				.. (if c then string.sub(B64, k4, k4) else "=")
		)
	end
	return table.concat(out)
end

local PORTRAIT_SIDE = 512 -- px, assets/portraits/<id>.png
local portraitData: { [string]: string | false } = {}

-- The data: URI of a candidate's portrait PNG, or nil when there is none.
local function portraitUri(id: string): string?
	local cached = portraitData[id]
	if cached == nil then
		local ok, bytes = pcall(fs.readFile, `assets/portraits/{id}.png`)
		cached = if ok and type(bytes) == "string" then "data:image/png;base64," .. base64(bytes) else false
		portraitData[id] = cached
	end
	return if cached then cached else nil
end

-- A Kit.portrait face (attribute Portrait): the local PNG, defined once per
-- picture and clipped to the image's rounded shape.
local function drawPortrait(out: Out, node: Node, ax: number, ay: number, id: string)
	local p = props(node.inst)
	local alpha = 1 - (p.ImageTransparency or 0)
	local uri = portraitUri(id)
	if uri == nil or alpha <= 0.01 then
		return
	end
	local defId = `portrait_{id}`
	if not out.portraits[id] then
		out.portraits[id] = true
		emit(
			out,
			string.format(
				'<defs><image id="%s" width="%d" height="%d" xlink:href="%s"/></defs>',
				defId,
				PORTRAIT_SIDE,
				PORTRAIT_SIDE,
				uri
			)
		)
	end
	local w, h = node.w, node.h
	local side = math.min(w, h)
	local x, y = ax + (w - side) / 2, ay + (h - side) / 2
	local clip = nextId(out, "pc")
	emit(
		out,
		string.format(
			'<clipPath id="%s">%s/></clipPath>',
			clip,
			shapeAt(x, y, side, side, radiusOf(node.inst, side, side), nil)
		)
	)
	emit(
		out,
		string.format(
			'<g clip-path="url(#%s)" opacity="%s"><use xlink:href="#%s" transform="translate(%s %s) scale(%s)"/></g>',
			clip,
			num(alpha),
			defId,
			num(x),
			num(y),
			string.format("%.4f", side / PORTRAIT_SIDE)
		)
	)
end

local ISSUE_SIDE = 256 -- px, assets/issues/<file>.png
local issueData: { [string]: string | false } = {}

-- The data: URI of an issue symbol's PNG (UI/IssueIcons), or nil when there is none.
local function issueUri(issue: string): string?
	local cached = issueData[issue]
	if cached == nil then
		local icon = IssueIcons.icons[issue]
		local ok, bytes = false, nil
		if icon then
			ok, bytes = pcall(fs.readFile, `assets/issues/{icon.file}.png`)
		end
		cached = if ok and type(bytes) == "string" then "data:image/png;base64," .. base64(bytes) else false
		issueData[issue] = cached
	end
	return if cached then cached else nil
end

-- A Kit.issueIcon image (attribute IssueIcon): the local PNG, defined once per
-- picture, used as a mask over a square of its ImageColor3 (the game's tint).
local function drawIssueIcon(out: Out, node: Node, ax: number, ay: number, issue: string)
	local p = props(node.inst)
	local alpha = 1 - (p.ImageTransparency or 0)
	local uri = issueUri(issue)
	if uri == nil or alpha <= 0.01 then
		return
	end
	local defId = `issue_{issue}`
	if not out.portraits[defId] then
		out.portraits[defId] = true
		emit(
			out,
			string.format(
				'<defs><image id="%s" width="%d" height="%d" xlink:href="%s"/></defs>',
				defId,
				ISSUE_SIDE,
				ISSUE_SIDE,
				uri
			)
		)
	end
	local w, h = node.w, node.h
	local side = math.min(w, h)
	local x, y = ax + (w - side) / 2, ay + (h - side) / 2
	local mask = nextId(out, "im")
	emit(
		out,
		string.format(
			'<mask id="%s" maskUnits="userSpaceOnUse" x="%s" y="%s" width="%s" height="%s"><use xlink:href="#%s" transform="translate(%s %s) scale(%s)"/></mask>',
			mask,
			num(x),
			num(y),
			num(side),
			num(side),
			defId,
			num(x),
			num(y),
			string.format("%.4f", side / ISSUE_SIDE)
		)
	)
	emit(
		out,
		string.format(
			'<rect x="%s" y="%s" width="%s" height="%s" fill="%s" fill-opacity="%s" mask="url(#%s)"/>',
			num(x),
			num(y),
			num(side),
			num(side),
			hex(p.ImageColor3, "#ffffff"),
			num(alpha),
			mask
		)
	)
end

local function drawNode(out: Out, node: Node, ox: number, oy: number, siblings: { [string]: Node }?)
	local inst = node.inst
	local p = props(inst)
	local c = class(inst)
	local ax, ay = ox + node.x, oy + node.y
	local w, h = node.w, node.h
	if w <= 0 or h <= 0 then
		return
	end
	local groups = 0
	-- UIScale scales the object and everything in it about its anchor point.
	local scale = childOf(inst, "UIScale")
	local k = if scale then props(scale).Scale or 1 else 1
	if k ~= 1 then
		local anchor = p.AnchorPoint
		local px = ax + (if anchor then anchor.X else 0) * w
		local py = ay + (if anchor then anchor.Y else 0) * h
		emit(
			out,
			string.format(
				'<g transform="translate(%s %s) scale(%s) translate(%s %s)">',
				num(px),
				num(py),
				string.format("%.3f", k),
				num(-px),
				num(-py)
			)
		)
		groups += 1
	end
	if c == "CanvasGroup" and (p.GroupTransparency or 0) > 0 then
		emit(out, string.format('<g opacity="%s">', num(1 - p.GroupTransparency)))
		groups += 1
	end
	local rotation = p.Rotation or 0
	if rotation ~= 0 then
		emit(
			out,
			string.format('<g transform="rotate(%s %s %s)">', num(rotation), num(ax + w / 2), num(ay + h / 2))
		)
		groups += 1
	end
	local r = radiusOf(inst, w, h)
	local corners = cornersOf(inst, w, h)
	local bgAlpha = 1 - (p.BackgroundTransparency or 0)
	if bgAlpha > 0.01 then
		local gradient = enabledChild(inst, "UIGradient")
		local paint
		if gradient then
			local id = gradientDef(out, gradient, ax, ay, w, h, p.BackgroundColor3, bgAlpha)
			paint = string.format(' fill="url(#%s)"/>', id)
		else
			paint = string.format(
				' fill="%s" fill-opacity="%s"/>',
				hex(p.BackgroundColor3, "#a3a2a5"),
				num(bgAlpha)
			)
		end
		emit(out, shapeAt(ax, ay, w, h, r, corners) .. paint)
	end
	local assetName = attrs(inst).Asset
	if (c == "ImageLabel" or c == "ImageButton") and type(assetName) == "string" then
		drawAsset(out, node, ax, ay, siblings or {}, ox, oy)
	end
	local portrait = attrs(inst).Portrait
	if c == "ImageLabel" and type(portrait) == "string" and portrait ~= "" then
		drawPortrait(out, node, ax, ay, portrait)
		assetName = "portrait" -- not a plain image
	end
	local issueIcon = attrs(inst).IssueIcon
	if c == "ImageLabel" and type(issueIcon) == "string" then
		drawIssueIcon(out, node, ax, ay, issueIcon)
		assetName = "issue" -- not a plain image
	end
	local attributes = rawget(inst, "_attributes")
	local iconName = if attributes then attributes.Icon else nil
	local icon = if type(iconName) == "string" then Icons[iconName] else nil
	local plainImage = type(assetName) ~= "string"
	if plainImage and c == "ImageLabel" and icon then
		-- A Kit.icon image: its glyph in its tint, in a dashed box of the same tint.
		local alpha = 1 - (p.ImageTransparency or 0)
		if alpha > 0.01 then
			local tint = hex(p.ImageColor3, "#ffffff")
			emit(
				out,
				string.format(
					'<rect x="%s" y="%s" width="%s" height="%s" rx="2" fill="none" stroke="%s" stroke-opacity="%s" stroke-dasharray="2 2"/>',
					num(ax + 0.5),
					num(ay + 0.5),
					num(w - 1),
					num(h - 1),
					tint,
					num(alpha * 0.6)
				)
			)
			emit(
				out,
				string.format(
					'<text x="%s" y="%s" font-family="Helvetica" font-size="%s" font-weight="bold" fill="%s" fill-opacity="%s" text-anchor="middle">%s</text>',
					num(ax + w / 2),
					num(ay + h / 2 + h * 0.25),
					num(h * 0.7),
					tint,
					num(alpha),
					esc(icon.glyph)
				)
			)
		end
	elseif plainImage and (c == "ImageLabel" or c == "ImageButton" or c == "ViewportFrame") then
		local alpha = 1 - (p.ImageTransparency or 0)
		if alpha > 0.01 then
			emit(
				out,
				string.format(
					'<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="none" stroke="#7a8094" stroke-dasharray="4 3"/>',
					num(ax + 1),
					num(ay + 1),
					num(w - 2),
					num(h - 2),
					num(r)
				)
			)
			emit(
				out,
				string.format(
					'<text x="%s" y="%s" font-family="Helvetica" font-size="10" fill="#7a8094" text-anchor="middle">%s</text>',
					num(ax + w / 2),
					num(ay + h / 2 + 3),
					esc(c == "ViewportFrame" and "3D view" or "image")
				)
			)
		end
	end
	local stroke = childOf(inst, "UIStroke")
	if stroke and props(stroke).Enabled ~= false then
		local sp = props(stroke)
		local mode = enum(sp.ApplyStrokeMode, "Contextual")
		if not (TEXT[c] and mode == "Contextual") and (sp.Thickness or 1) > 0 then
			local t = sp.Thickness or 1
			local x, y, bw, bh = ax - t / 2, ay - t / 2, w + t, h + t
			local strokeAlpha = 1 - (sp.Transparency or 0)
			local light = enabledChild(stroke, "UIGradient")
			local paint
			if light then
				local id = gradientDef(out, light, x, y, bw, bh, sp.Color, strokeAlpha)
				paint = string.format(' fill="none" stroke="url(#%s)" stroke-width="%s"/>', id, num(t))
			else
				paint = string.format(
					' fill="none" stroke="%s" stroke-width="%s" stroke-opacity="%s"/>',
					hex(sp.Color, "#000000"),
					num(t),
					num(strokeAlpha)
				)
			end
			local grown = if corners
				then { corners[1] + t / 2, corners[2] + t / 2, corners[3] + t / 2, corners[4] + t / 2 }
				else nil
			emit(out, shapeAt(x, y, bw, bh, if r > 0 then r + t / 2 else 0, grown) .. paint)
		end
	end
	-- A portrait's initials stand in for an image the game has not uploaded;
	-- the snapshots always draw the image, so they skip them.
	if TEXT[c] and attrs(inst).PortraitFallback ~= true then
		drawText(out, node, ax, ay)
	end
	local clips = c == "ScrollingFrame" or p.ClipsDescendants == true
	if clips then
		out.clips += 1
		local id = `c{out.clips}`
		emit(
			out,
			string.format(
				'<clipPath id="%s"><rect x="%s" y="%s" width="%s" height="%s" rx="%s"/></clipPath><g clip-path="url(#%s)">',
				id,
				num(ax),
				num(ay),
				num(w),
				num(h),
				num(r),
				id
			)
		)
	end
	local ordered = table.clone(node.children)
	local index: { [Node]: number } = {}
	for i, child in ordered do
		index[child] = i
	end
	table.sort(ordered, function(a, b)
		local za, zb = props(a.inst).ZIndex or 1, props(b.inst).ZIndex or 1
		if za ~= zb then
			return za < zb
		end
		return index[a] < index[b]
	end)
	local byName: { [string]: Node } = {}
	for _, child in node.children do
		local name = tostring(props(child.inst).Name)
		byName[name] = byName[name] or child
	end
	for _, child in ordered do
		drawNode(out, child, ax, ay, byName)
	end
	if clips then
		emit(out, "</g>")
	end
	local hidden = (node.contentH or 0) - h
	if c == "ScrollingFrame" and hidden > 4 then
		emit(
			out,
			string.format(
				'<rect x="%s" y="%s" width="%s" height="16" rx="8" fill="#6b5cff" fill-opacity="0.85"/>',
				num(ax + w - 108),
				num(ay + h - 18),
				"104"
			)
		)
		emit(
			out,
			string.format(
				'<text x="%s" y="%s" font-family="Helvetica" font-size="10" font-weight="700" fill="#ffffff" text-anchor="middle">+%d px below ▼</text>',
				num(ax + w - 56),
				num(ay + h - 7),
				math.floor(hidden)
			)
		)
	end
	for _ = 1, groups do
		emit(out, "</g>")
	end
end

-- A ScreenGui's root node: the screen less the insets it respects.
local function guiRoot(g: any, W: number, H: number, topInset: number, screen: any): Node
	local p = props(g)
	local insets = enum(p.ScreenInsets, "CoreUISafeInsets")
	local left, right, bottom = screen.left or 0, screen.right or 0, screen.bottom or 0
	if p.IgnoreGuiInset == true or insets == "None" then
		return { inst = g, x = 0, y = 0, w = W, h = H, children = {} }
	elseif insets == "DeviceSafeInsets" then
		local top = screen.deviceTop or 0
		return { inst = g, x = left, y = top, w = W - left - right, h = H - top - bottom, children = {} }
	end
	return { inst = g, x = left, y = topInset, w = W - left - right, h = H - topInset - bottom, children = {} }
end

-- The SVG for everything a client's PlayerGui shows.
function Snapshot.svg(peer: any, options: Options?): string
	local world = rawget(peer.player, "_world")
	local W, H = world.screen.x, world.screen.y
	local topInset = if options and options.topInset ~= nil then options.topInset else 58
	local square = options ~= nil and options.square == true
	local S = math.max(W, H)
	local dx, dy = if square then (S - W) / 2 else 0, if square then (S - H) / 2 else 0
	local out: Out = { lines = {}, clips = 0, ids = 0, portraits = {}, fonts = {} }
	local cw, chh = if square then S else W, if square then S else H
	emit(
		out,
		string.format(
			'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="%d" height="%d" viewBox="0 0 %d %d">',
			cw,
			chh,
			cw,
			chh
		)
	)
	emit(out, string.format('<rect width="%d" height="%d" fill="#3a3a3a"/>', cw, chh))
	emit(out, string.format('<g transform="translate(%s %s)">', num(dx), num(dy)))
	emit(out, string.format('<clipPath id="screen"><rect width="%d" height="%d"/></clipPath>', W, H))
	emit(out, '<g clip-path="url(#screen)">')
	emit(out, string.format('<rect width="%d" height="%d" fill="#000000"/>', W, H))

	local playerGui = peer.player:FindFirstChild("PlayerGui")
	local guis: { any } = {}
	if playerGui then
		for _, child in kids(playerGui) do
			if class(child) == "ScreenGui" and props(child).Enabled ~= false then
				table.insert(guis, child)
			end
		end
	end
	local order: { [any]: number } = {}
	for i, g in guis do
		order[g] = i
	end
	table.sort(guis, function(a, b)
		local da, db = props(a).DisplayOrder or 0, props(b).DisplayOrder or 0
		if da ~= db then
			return da < db
		end
		return order[a] < order[b]
	end)
	local screen = world.screen
	local left, bottom = screen.left or 0, screen.bottom or 0
	local deviceTop = screen.deviceTop or 0
	for _, g in guis do
		local root = guiRoot(g, W, H, topInset, screen)
		layoutChildren(root)
		local byName: { [string]: Node } = {}
		for _, child in root.children do
			local name = tostring(props(child.inst).Name)
			byName[name] = byName[name] or child
		end
		for _, child in root.children do
			drawNode(out, child, root.x, root.y, byName)
		end
	end
	if deviceTop > 0 then
		-- A portrait notch (the status bar's middle): a black cutout.
		emit(
			out,
			string.format(
				'<rect x="%s" y="0" width="%s" height="%s" rx="15" fill="#000000"/>',
				num(W / 2 - 80),
				"160",
				num(math.min(deviceTop - 13, 34))
			)
		)
	elseif left > 0 then
		-- A landscape notch on the left edge: a black cutout.
		emit(
			out,
			string.format(
				'<rect x="0" y="%s" width="%s" height="160" rx="15" fill="#000000"/>',
				num(H / 2 - 80),
				num(math.min(left - 13, 34))
			)
		)
	end
	if bottom > 0 then
		-- The home indicator.
		emit(
			out,
			string.format(
				'<rect x="%s" y="%s" width="134" height="5" rx="2.5" fill="#ffffff" fill-opacity="0.85"/>',
				num(W / 2 - 67),
				num(H - math.min(bottom, 21) / 2 - 4)
			)
		)
	end
	if topInset > 0 then
		-- The Roblox top bar: its menu buttons sit over the game, below a
		-- portrait notch and right of a landscape one.
		local barY = deviceTop + (topInset - deviceTop - 44) / 2
		emit(
			out,
			string.format(
				'<rect x="%s" y="%s" width="44" height="44" rx="22" fill="#000000" fill-opacity="0.45"/>',
				num(left + 12),
				num(barY)
			)
		)
		emit(
			out,
			string.format(
				'<rect x="%s" y="%s" width="44" height="44" rx="22" fill="#000000" fill-opacity="0.45"/>',
				num(left + 64),
				num(barY)
			)
		)
	end
	for name in out.fonts do
		local face = HAND_FONTS[name]
		local ok, bytes = pcall(fs.readFile, face.file)
		if ok and type(bytes) == "string" then
			emit(
				out,
				`<style>@font-face \{ font-family: '{face.family}'; src: url(data:font/ttf;base64,{base64(
					bytes
				)}) format('truetype'); }</style>`
			)
		end
	end
	emit(out, "</g></g></svg>")
	return table.concat(out.lines, "\n")
end

export type Measure = {
	mapW: number, -- the largest visible map ("NodeMap"), drawn size (0: none)
	mapH: number,
	minText: number, -- the smallest visible text's drawn size (0: no text)
	minTextName: string,
	smallTaps: { string }, -- visible buttons off the map under 44 px in either direction: "Name WxH"
	smallMapTaps: number, -- ... on the map (state hit boxes, chips)
	belowFold: number, -- px the tallest scrolling frame holds past its bottom, or content past the screen's
	belowName: string,
}

local MIN_TAP = 44

-- The study's numbers for what the peer's PlayerGui shows (see the header).
function Snapshot.measure(peer: any, options: Options?): Measure
	local world = rawget(peer.player, "_world")
	local W, H = world.screen.x, world.screen.y
	local topInset = if options and options.topInset ~= nil then options.topInset else 58
	local result: Measure = {
		mapW = 0,
		mapH = 0,
		minText = 0,
		minTextName = "",
		smallTaps = {},
		smallMapTaps = 0,
		belowFold = 0,
		belowName = "",
	}
	local playerGui = peer.player:FindFirstChild("PlayerGui")
	if playerGui == nil then
		return result
	end
	local function walk(
		node: Node,
		ax: number,
		ay: number,
		onMap: boolean,
		scrolled: boolean,
		bottomEdge: number,
		inDecor: boolean?
	)
		local inst = node.inst
		local p = props(inst)
		local c = class(inst)
		local x, y = ax + node.x, ay + node.y
		if node.w <= 0 or node.h <= 0 then
			return
		end
		local name = tostring(p.Name)
		local map = onMap or name == "NodeMap"
		if name == "NodeMap" and node.w * node.h > result.mapW * result.mapH then
			result.mapW, result.mapH = math.floor(node.w + 0.5), math.floor(node.h + 0.5)
		end
		local decor = inDecor == true or attrs(inst).Decor == true or attrs(inst).Asset ~= nil
		if TEXT[c] and not decor and node.text and #node.text > 0 and node.text[1] ~= "" then
			local fade = p.TextTransparency or 0
			if fade < 0.95 and node.textSize and (result.minText == 0 or node.textSize < result.minText) then
				result.minText = node.textSize
				result.minTextName = name
			end
		end
		if (c == "TextButton" or c == "ImageButton") and not decor then
			if node.w < MIN_TAP - 0.5 or node.h < MIN_TAP - 0.5 then
				if map then
					result.smallMapTaps += 1
				else
					table.insert(result.smallTaps, `{name} {math.floor(node.w)}x{math.floor(node.h)}`)
				end
			end
		end
		if not scrolled and not map and not decor and y + node.h > bottomEdge + 1 then
			local past = y + node.h - bottomEdge
			if past > result.belowFold then
				result.belowFold, result.belowName = math.floor(past), `{name} (off screen)`
			end
		end
		if c == "ScrollingFrame" then
			local hidden = (node.contentH or 0) - node.h
			if hidden > result.belowFold then
				result.belowFold, result.belowName = math.floor(hidden), `{name} (scroll)`
			end
		end
		local inner = scrolled or c == "ScrollingFrame" or p.ClipsDescendants == true
		for _, child in node.children do
			walk(child, x, y, map, inner, bottomEdge, decor)
		end
	end
	for _, g in kids(playerGui) do
		if class(g) ~= "ScreenGui" or props(g).Enabled == false then
			continue
		end
		local root = guiRoot(g, W, H, topInset, world.screen)
		layoutChildren(root)
		for _, child in root.children do
			walk(child, root.x, root.y, false, false, root.y + root.h)
		end
	end
	return result
end

export type Box = {
	x: number, -- screen px, as drawn
	y: number,
	w: number,
	h: number,
	clip: { x: number, y: number, w: number, h: number }, -- what its scrolling or clipping ancestors leave visible
}

-- Where each visible element of the peer's PlayerGui is drawn (the same layout
-- as Snapshot.svg, list layouts included, which the fake engine's AbsolutePosition
-- ignores), by Name; the first one in drawing order wins a repeated name.
-- A scrolling frame shows its canvas from the top (CanvasPosition 0).
function Snapshot.boxes(peer: any, options: Options?): { [string]: Box }
	local world = rawget(peer.player, "_world")
	local W, H = world.screen.x, world.screen.y
	local topInset = if options and options.topInset ~= nil then options.topInset else 58
	local result: { [string]: Box } = {}
	local playerGui = peer.player:FindFirstChild("PlayerGui")
	if playerGui == nil then
		return result
	end
	type Clip = { x: number, y: number, w: number, h: number }
	local function cut(a: Clip, x: number, y: number, w: number, h: number): Clip
		local x0, y0 = math.max(a.x, x), math.max(a.y, y)
		local x1, y1 = math.min(a.x + a.w, x + w), math.min(a.y + a.h, y + h)
		return { x = x0, y = y0, w = math.max(x1 - x0, 0), h = math.max(y1 - y0, 0) }
	end
	local function walk(node: Node, ax: number, ay: number, clip: Clip)
		local inst = node.inst
		local p = props(inst)
		if p.Visible == false then
			return
		end
		local x, y = ax + node.x, ay + node.y
		local name = tostring(p.Name)
		if result[name] == nil then
			result[name] = { x = x, y = y, w = node.w, h = node.h, clip = clip }
		end
		local inner = clip
		if class(inst) == "ScrollingFrame" or p.ClipsDescendants == true then
			inner = cut(clip, x, y, node.w, node.h)
		end
		for _, child in node.children do
			walk(child, x, y, inner)
		end
	end
	for _, g in kids(playerGui) do
		if class(g) ~= "ScreenGui" or props(g).Enabled == false then
			continue
		end
		local root = guiRoot(g, W, H, topInset, world.screen)
		layoutChildren(root)
		local screen = { x = 0, y = 0, w = W, h = H }
		for _, child in root.children do
			walk(child, root.x, root.y, screen)
		end
	end
	return result
end

return Snapshot
