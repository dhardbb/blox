--!strict
-- The whiteboard's props (docs/proposals/whiteboard.md): the board texture, sticky
-- notes, marker outlines, magnets, circled stamps, tape and taped-up photos.
-- Each helper adds images from UI/Assets (made by assets/ui/make.py) to a
-- GuiObject a screen already built, and falls back when the image's id is ""
-- (not uploaded yet): it does nothing, or draws a flat stand-in where noted.
-- The screen's own colors and strokes stay the fallback look, so nothing breaks
-- before the upload.
--
--   Board.ready(name) -> boolean   the Assets entry `name` has an id
--   Board.texture(root, opts?) -> ImageLabel?   "BoardTexture": board.png tiled
--     over root's background (root keeps Colors.background as the flat look)
--   Board.sticky(frame, color?, opts?) -> ImageLabel?   "Sticky": a 9-slice note
--     behind frame's children, tinted `color` (default Colors.sticky); frame's
--     own background turns clear. Fallback: frame's background becomes `color`
--   Board.markerBox(target, color?, opts?) -> ImageLabel?   "MarkerBox": a wobbly
--     marker rectangle over target's edges (default ink: Colors.text); target's
--     UIStroke children are disabled while it shows. Fallback: nothing (the
--     strokes stay)
--   Board.magnet(target, color, opts?) -> GuiObject   "Magnet": a magnet pinned
--     at target's top center. Fallback: a flat dot in `color`
--   Board.circle(target, color?, opts?) -> ImageLabel?   "Circled": a loose marker
--     circle around target (a stamp, a "circled" note). Fallback: nothing
--   Board.tape(target, opts?) -> { ImageLabel }   "Tape": masking tape across
--     target's top edge (or its two top corners). Fallback: none ({})
--   Board.photo(face, px, opts?) -> Frame   "Photo": a white instant-photo card px
--     wide around `face` (a GuiObject, or an image id for an ImageLabel),
--     tilted `opts.tilt` degrees and taped on. The card is plain frames, so
--     it always shows; only the tape waits for its upload
--
-- A parent that lays its children out (a UIListLayout or UIGridLayout) would
-- move an added image into the flow, so sticky, markerBox, magnet, circle and
-- tape fall back there; put the prop on a wrapper frame instead.
--
-- Every image added here carries the attributes Decor = true (the UI audit
-- skips it) and Asset = its Assets key. Nothing animates: each helper sets its
-- images once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)

local Assets = require(script.Parent.Assets)

local Board = {}

-- The image ids the props use: nil for UI/Assets (the specs set a stand-in
-- list to see the images applied before they are uploaded).
Board.assets = nil :: { [string]: Assets.Asset }?

Board.TILE = 512 -- px, one board.png tile drawn at its own size
Board.STICKY_SLICE = Rect.new(32, 32, 88, 88) -- sticky.png's 9-slice center (assets/ui/make.py)
Board.STICKY_PAD = { left = 4, top = 4, right = 12, bottom = 12 } -- px of sticky.png around the paper (shadow and curl)
Board.BOX_SLICE = Rect.new(40, 40, 88, 88) -- marker-box.png's 9-slice center
Board.BOX_SCALE = 0.5 -- marker-box.png is drawn at 2x: a 3 px line on screen
Board.BOX_PAD = 7 -- px the marker box reaches past the edges (its lines sit 14 image px in, at half scale)
Board.MAGNET = 28 -- px, a magnet's default size
Board.MAGNET_DOT = 0.6 -- the flat fallback dot's size, a share of the magnet
Board.CIRCLE_SCALE = 1.35 -- the circle's size, a share of its target's
Board.TAPE_W = 0.55 -- the tape strip's length, a share of the target's width
Board.TAPE_ASPECT = 48 / 128 -- tape.png's height over its width
Board.TAPE_TILT = -4 -- degrees, the default tilt of a strip
Board.CORNER_TILT = 38 -- degrees, a corner strip's tilt
Board.PHOTO_MARGIN = 0.07 -- the photo's white border at the sides and top, a share of its width
Board.PHOTO_CHIN = 0.2 -- the photo's thicker bottom border, a share of its width
Board.PHOTO_EDGE_FADE = 0.6 -- transparency of the photo's 1 px line edge
Board.DECOR_Z = 0 -- ZIndex of an image drawn behind a frame's other children
Board.PROP_Z = 6 -- ZIndex of a prop drawn on top (magnet, tape, circle, marker box)

local function assetList(): any
	return Board.assets or Assets
end

local function color3(c: Colors.RGB): Color3
	return Color3.fromRGB(c.r, c.g, c.b)
end

function Board.ready(name: string): boolean
	local entry = assetList()[name]
	return entry ~= nil and type(entry.id) == "string" and entry.id ~= ""
end

local function idOf(name: string): string
	return assetList()[name].id
end

local function laysOut(parent: Instance): boolean
	return parent:FindFirstChildOfClass("UIListLayout") ~= nil
		or parent:FindFirstChildOfClass("UIGridLayout") ~= nil
end

local function decor<T>(inst: T, asset: string): T
	local target = inst :: any
	target:SetAttribute("Decor", true)
	target:SetAttribute("Asset", asset)
	return inst
end

local function image(name: string, asset: string, props: { [string]: any }): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Image = idOf(asset)
	for key, value in props do
		(label :: any)[key] = value
	end
	return decor(label, asset)
end

export type TextureOptions = { zIndex: number? }

-- board.png tiled at its own size over root's background, under root's other
-- children. Nil while board has no id or root lays out its children.
function Board.texture(root: GuiObject, opts: TextureOptions?): ImageLabel?
	if not Board.ready("board") or laysOut(root) then
		return nil
	end
	local o: TextureOptions = opts or {}
	local label = image("BoardTexture", "board", {
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Tile,
		TileSize = UDim2.fromOffset(Board.TILE, Board.TILE),
		ZIndex = o.zIndex or Board.DECOR_Z,
	})
	label.Parent = root
	return label
end

export type PropOptions = { zIndex: number? }

-- A sticky note behind frame's children: the 9-slice note tinted `color`
-- (default Colors.sticky), its paper exactly on frame's edges, the shadow and
-- curl just outside them. Without the image, frame itself turns the color.
function Board.sticky(frame: GuiObject, color: Color3?, opts: PropOptions?): ImageLabel?
	local tint = color or color3(Colors.sticky)
	if not Board.ready("sticky") or laysOut(frame) then
		frame.BackgroundColor3 = tint
		frame.BackgroundTransparency = 0
		return nil
	end
	local o: PropOptions = opts or {}
	local pad = Board.STICKY_PAD
	local label = image("Sticky", "sticky", {
		Position = UDim2.fromOffset(-pad.left, -pad.top),
		Size = UDim2.new(1, pad.left + pad.right, 1, pad.top + pad.bottom),
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Board.STICKY_SLICE,
		SliceScale = 1,
		ImageColor3 = tint,
		ZIndex = o.zIndex or Board.DECOR_Z,
	})
	frame.BackgroundTransparency = 1
	label.Parent = frame
	return label
end

-- A hand-drawn marker rectangle over target's edges, in `color` (default the
-- black ink). Turns off target's UIStroke children while it shows (the marker
-- box replaces them). Nil while markerBox has no id: the strokes stay.
function Board.markerBox(target: GuiObject, color: Color3?, opts: PropOptions?): ImageLabel?
	if not Board.ready("markerBox") or laysOut(target) then
		return nil
	end
	local o: PropOptions = opts or {}
	local pad = Board.BOX_PAD
	local label = image("MarkerBox", "markerBox", {
		Position = UDim2.fromOffset(-pad, -pad),
		Size = UDim2.new(1, 2 * pad, 1, 2 * pad),
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Board.BOX_SLICE,
		SliceScale = Board.BOX_SCALE,
		ImageColor3 = color or color3(Colors.text),
		ZIndex = o.zIndex or Board.PROP_Z,
	})
	for _, child in target:GetChildren() do
		if child:IsA("UIStroke") then
			(child :: UIStroke).Enabled = false
		end
	end
	label.Parent = target
	return label
end

export type MagnetOptions = { px: number?, zIndex: number? }

-- A magnet in `color` pinning target at its top center. Without the image (or
-- in a laid-out parent) a flat round dot in the color.
function Board.magnet(target: GuiObject, color: Color3, opts: MagnetOptions?): GuiObject
	local o: MagnetOptions = opts or {}
	local px = o.px or Board.MAGNET
	local z = o.zIndex or Board.PROP_Z
	if Board.ready("magnet") and not laysOut(target) then
		local label = image("Magnet", "magnet", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(px, px),
			ScaleType = Enum.ScaleType.Fit,
			ImageColor3 = color,
			ZIndex = z,
		})
		label.Parent = target
		return label
	end
	local dot = Instance.new("Frame")
	dot.Name = "Magnet"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0)
	local d = math.floor(px * Board.MAGNET_DOT + 0.5)
	dot.Size = UDim2.fromOffset(d, d)
	dot.BackgroundColor3 = color
	dot.BorderSizePixel = 0
	dot.ZIndex = z
	dot:SetAttribute("Decor", true)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = dot
	if not laysOut(target) then
		dot.Parent = target
	end
	return dot
end

export type CircleOptions = { scale: number?, zIndex: number? }

-- A loose marker circle around target, `opts.scale` (default 1.35) times its
-- size, stretched to its shape. Nil while scribbleCircle has no id.
function Board.circle(target: GuiObject, color: Color3?, opts: CircleOptions?): ImageLabel?
	if not Board.ready("scribbleCircle") or laysOut(target) then
		return nil
	end
	local o: CircleOptions = opts or {}
	local k = o.scale or Board.CIRCLE_SCALE
	local label = image("Circled", "scribbleCircle", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(k, k),
		ScaleType = Enum.ScaleType.Stretch,
		ImageColor3 = color or color3(Colors.text),
		ZIndex = o.zIndex or Board.PROP_Z,
	})
	label.Parent = target
	return label
end

export type TapeOptions = {
	at: string?, -- "top" (default): one strip across the top edge; "corners": one on each top corner
	px: number?, -- a strip's length; default Board.TAPE_W of target's width
	tilt: number?, -- degrees for a "top" strip (default Board.TAPE_TILT)
	zIndex: number?,
}

-- Masking tape holding target to the board. {} while tape has no id.
function Board.tape(target: GuiObject, opts: TapeOptions?): { ImageLabel }
	if not Board.ready("tape") or laysOut(target) then
		return {}
	end
	local o: TapeOptions = opts or {}
	local z = o.zIndex or Board.PROP_Z
	local length = o.px or math.floor(target.AbsoluteSize.X * Board.TAPE_W + 0.5)
	local size = if length > 0
		then UDim2.fromOffset(length, math.floor(length * Board.TAPE_ASPECT + 0.5))
		else UDim2.fromScale(Board.TAPE_W, Board.TAPE_W * Board.TAPE_ASPECT)
	local strips: { ImageLabel } = {}
	if o.at == "corners" then
		for _, side in { 0, 1 } do
			local strip = image("Tape", "tape", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(side, 0),
				Size = UDim2.new(size.X.Scale * 0.6, size.X.Offset * 0.6, size.Y.Scale, size.Y.Offset),
				ScaleType = Enum.ScaleType.Stretch,
				Rotation = if side == 0 then -Board.CORNER_TILT else Board.CORNER_TILT,
				ZIndex = z,
			})
			strip.Parent = target
			table.insert(strips, strip)
		end
		return strips
	end
	local strip = image("Tape", "tape", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0),
		Size = size,
		ScaleType = Enum.ScaleType.Stretch,
		Rotation = o.tilt or Board.TAPE_TILT,
		ZIndex = z,
	})
	strip.Parent = target
	table.insert(strips, strip)
	return strips
end

export type PhotoOptions = {
	tilt: number?, -- degrees the whole photo is turned (default 0); vary it per photo
	tape: boolean?, -- false: no tape (default: taped at the top)
	backdrop: Color3?, -- behind the face (default Colors.raised)
	name: string?, -- the root's Name (default "Photo")
}

-- An instant photo of `face` taped to the board: a paper card `px` wide with a
-- thicker bottom border, the face in its square window. `face` is a GuiObject
-- (it is moved into the window and sized to fill it) or an image id (an
-- ImageLabel is made for it, Fit). The card always draws; the tape needs its
-- upload. Rotation is not compatible with ClipsDescendants, so nothing inside
-- relies on clipping.
function Board.photo(face: GuiObject | string, px: number, opts: PhotoOptions?): Frame
	local o: PhotoOptions = opts or {}
	local margin = math.floor(px * Board.PHOTO_MARGIN + 0.5)
	local window = px - 2 * margin
	local chin = math.floor(px * Board.PHOTO_CHIN + 0.5)
	local card = Instance.new("Frame")
	card.Name = o.name or "Photo"
	card.Size = UDim2.fromOffset(px, margin + window + chin)
	card.BackgroundColor3 = color3(Colors.surfaceTop)
	card.BorderSizePixel = 0
	card.Rotation = o.tilt or 0
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = color3(Colors.line)
	edge.Transparency = Board.PHOTO_EDGE_FADE
	edge.Thickness = 1
	edge.Parent = card
	local frame = Instance.new("Frame")
	frame.Name = "Window"
	frame.Position = UDim2.fromOffset(margin, margin)
	frame.Size = UDim2.fromOffset(window, window)
	frame.BackgroundColor3 = o.backdrop or color3(Colors.raised)
	frame.BorderSizePixel = 0
	frame.Parent = card
	local content: GuiObject
	if type(face) == "string" then
		local label = Instance.new("ImageLabel")
		label.Name = "Face"
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Image = face
		label.ScaleType = Enum.ScaleType.Fit
		content = label
	else
		content = face
	end
	content.AnchorPoint = Vector2.new(0, 0)
	content.Position = UDim2.fromOffset(0, 0)
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = frame
	if o.tape ~= false then
		Board.tape(card, { px = math.floor(px * Board.TAPE_W + 0.5) })
	end
	return card
end

return Board
