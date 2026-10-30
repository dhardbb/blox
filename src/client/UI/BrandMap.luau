--!strict
-- The start screen's backdrop (docs/DESIGN.md D-090, redrawn for the
-- whiteboard in D-102): the US map in marker behind the "LANDSLIDE" wordmark,
-- states scribbled in red and blue by a fixed scatter that follows no real
-- election (red slanting one way, blue the other, as on the game's map), the
-- black marker borders over them, and a few marker asterisks around it, so the
-- first screen says "election night" before a word is read. Decorative only
-- (attribute Decor: the UI audit skips it) and still: nothing animates. Until
-- the scribbled atlases or the ink overlay are uploaded it draws the flat
-- fills and no borders.
--
--   local map = BrandMap.new(props)   Frame "BrandMap" (Decor), ASPECT kept
--   map.root · map.stop()             kept for the screen's destroy (nothing runs)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local MapShape = require(ReplicatedStorage.Shared.UI.MapShape)

local Assets = require(script.Parent.Assets)
local Kit = require(script.Parent.Kit)

local BrandMap = {}

BrandMap.MAP_FADE = 0.8 -- the scribbles' transparency: a backdrop, not a map (their white gaps lighten it further; the flat fills use FLAT_FADE)
BrandMap.FLAT_FADE = 0.86 -- the flat fills' transparency before the scribbles are uploaded
BrandMap.INK_FADE = 0.78 -- the marker borders' transparency
BrandMap.STAR_FADE = 0.45 -- a marker asterisk's transparency
local STAR = "*" -- a marker asterisk, as on a hand-drawn election map
local STAR_W = 24 -- px, an asterisk's box
-- Where the stars stand, as fractions of the map box (above and around the land).
BrandMap.STARS = table.freeze({
	{ 0.06, 0.12 },
	{ 0.2, 0.04 },
	{ 0.36, 0.1 },
	{ 0.52, 0.02 },
	{ 0.68, 0.08 },
	{ 0.84, 0.03 },
	{ 0.95, 0.16 },
	{ 0.12, 0.88 },
	{ 0.88, 0.9 },
})

export type BrandMap = {
	root: Frame,
	stop: () -> (),
}

-- Red or blue for a state: a fixed scatter from its id (no real map).
local function sideOf(id: string): boolean
	local sum = 0
	for i = 1, #id do
		sum += string.byte(id, i) * i
	end
	return sum % 2 == 0
end

function BrandMap.new(props: { [string]: any }?): BrandMap
	local root = Kit.box({
		Name = "BrandMap",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
	})
	root:SetAttribute("Decor", true)
	Kit.new("UIAspectRatioConstraint", { AspectRatio = MapShape.ASPECT, Parent = root })
	local red = Kit.color(Colors.player.Crimson)
	local blue = Kit.color(Colors.player.Cobalt)
	local list = Assets :: any
	local function uploaded(key: string): boolean
		local asset = list[key]
		return asset ~= nil and asset.id ~= ""
	end
	-- The scribbles only when all four atlases are in (as ShapeMap.hatched).
	local hatched = uploaded("mapStates1a")
		and uploaded("mapStates2a")
		and uploaded("mapStates1b")
		and uploaded("mapStates2b")
	for _, shape in MapShape.list() do
		local isRed = sideOf(shape.id)
		-- Red slants like seat 1 ("a"), blue like seat 2 ("b").
		local key = if hatched
			then `mapStates{shape.atlas}{if isRed then "a" else "b"}`
			else `mapStates{shape.atlas}`
		local asset = list[key]
		local image = Kit.new("ImageLabel", {
			Name = `Shape{shape.id}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(shape.x + shape.w / 2, shape.y + shape.h / 2),
			Size = UDim2.fromScale(shape.w, shape.h),
			BackgroundTransparency = 1,
			Image = if asset then asset.id else "",
			ImageRectOffset = Vector2.new(shape.ox, shape.oy),
			ImageRectSize = Vector2.new(shape.ow, shape.oh),
			ImageColor3 = if isRed then red else blue,
			ImageTransparency = if hatched then BrandMap.MAP_FADE else BrandMap.FLAT_FADE,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = 0,
			Parent = root,
		})
		image:SetAttribute("Asset", key)
		image:SetAttribute("MapShape", shape.id)
	end
	-- The black marker borders and coast over the scribbles (the ink overlay's
	-- own rect in the map box).
	if uploaded("mapInk") then
		local rect = MapShape.data.ink
		local ink = Kit.new("ImageLabel", {
			Name = "Ink",
			Position = UDim2.fromScale(rect.x, rect.y),
			Size = UDim2.fromScale(rect.w, rect.h),
			BackgroundTransparency = 1,
			Image = list.mapInk.id,
			ImageColor3 = Kit.colors.text,
			ImageTransparency = BrandMap.INK_FADE,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = 0,
			Parent = root,
		})
		ink:SetAttribute("Asset", "mapInk")
	end
	for k, at in BrandMap.STARS do
		Kit.text(STAR, {
			Name = `Star{k}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(at[1], at[2]),
			Size = UDim2.fromOffset(STAR_W, Kit.size.caption + 2),
			TextSize = Kit.size.caption,
			Font = Kit.font.display,
			TextColor3 = if k % 2 == 1 then red else blue,
			TextTransparency = BrandMap.STAR_FADE,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			ZIndex = 0,
			Parent = root,
		})
	end
	local p: { [string]: any } = props or {}
	for key, value in p do
		(root :: any)[key] = value
	end
	return {
		root = root,
		stop = function() end,
	}
end

return BrandMap
