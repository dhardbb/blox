--!strict
-- The start screen's backdrop (docs/DESIGN.md D-090): a faint red and blue map
-- of the states behind the "LANDSLIDE" wordmark, with a scatter of stars, so
-- the first screen says "election night" before a word is read. Decorative
-- only (attribute Decor: the UI audit skips it): every state is the real map's
-- shape (the same atlases as Map/ShapeMap, Shared/UI/MapShape) at
-- MAP_FADE, red or blue by a fixed scatter that follows no real election, and
-- the stars twinkle slowly unless motion is reduced.
--
--   local map = BrandMap.new(props)   Frame "BrandMap" (Decor), ASPECT kept
--   map.root · map.stop()             stop the twinkle (the screen's destroy)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local MapShape = require(ReplicatedStorage.Shared.UI.MapShape)

local Assets = require(script.Parent.Assets)
local Kit = require(script.Parent.Kit)
local Motion = require(script.Parent.Motion)

local BrandMap = {}

BrandMap.MAP_FADE = 0.86 -- the states' image transparency: a backdrop, not a map
BrandMap.STAR_FADE = 0.45 -- a star's text transparency at rest
local STAR_W = 24 -- px, a star's box: room for the glyph (three bytes in UTF-8)
BrandMap.TWINKLE = 2.4 -- s, one star's slow fade there and back
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
	for _, shape in MapShape.list() do
		local asset = (Assets :: any)[`mapStates{shape.atlas}`]
		local image = Kit.new("ImageLabel", {
			Name = `Shape{shape.id}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(shape.x + shape.w / 2, shape.y + shape.h / 2),
			Size = UDim2.fromScale(shape.w, shape.h),
			BackgroundTransparency = 1,
			Image = if asset then asset.id else "",
			ImageRectOffset = Vector2.new(shape.ox, shape.oy),
			ImageRectSize = Vector2.new(shape.ow, shape.oh),
			ImageColor3 = if sideOf(shape.id) then red else blue,
			ImageTransparency = BrandMap.MAP_FADE,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = 0,
			Parent = root,
		})
		image:SetAttribute("Asset", "mapShape")
		image:SetAttribute("MapShape", shape.id)
	end
	local stops: { () -> () } = {}
	local stopped = false
	for k, at in BrandMap.STARS do
		local star = Kit.text(Kit.STAR, {
			Name = `Star{k}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(at[1], at[2]),
			Size = UDim2.fromOffset(STAR_W, Kit.size.caption + 2),
			TextSize = Kit.size.caption,
			TextColor3 = Kit.colors.text,
			TextTransparency = BrandMap.STAR_FADE,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = false,
			ZIndex = 0,
			Parent = root,
		})
		-- Each star on its own beat, so they never pulse together.
		task.delay(k * BrandMap.TWINKLE / #BrandMap.STARS, function()
			if not stopped and star.Parent ~= nil then
				table.insert(
					stops,
					Motion.breathe(star, "TextTransparency", BrandMap.STAR_FADE, 0.9, BrandMap.TWINKLE)
				)
			end
		end)
	end
	local p: { [string]: any } = props or {}
	for key, value in p do
		(root :: any)[key] = value
	end
	return {
		root = root,
		stop = function()
			stopped = true
			for _, stop in stops do
				stop()
			end
			table.clear(stops)
		end,
	}
end

return BrandMap
