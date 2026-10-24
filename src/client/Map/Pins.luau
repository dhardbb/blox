--!strict
-- Candidate pins on the map (D-062): where each candidate is right now
-- (PlayerView.location, public for every player), so you can find yourself at a
-- glance. A pin is the candidate's face on a disc in their color with a point
-- under it, and a small flag over it in the same color: "You" on yours, the
-- rival's first name on theirs. Pins are edged in the stage navy so they stand
-- off any fill (nothing on the map is white: white means selected, D-058).
-- Both maps (ShapeMap, NodeMap's circles) draw pins with Pins.build.
--
--   Pins.of(config, view) -> { Pin }     yours last (drawn on top)
--   Pins.face(name, color, px) -> Frame  the face: the ONE place that picks the
--                                        portrait (Kit.monogram until there is art)
--   Pins.build(pin, px) -> Frame "Pin<state>"   AnchorPoint at the point's tip

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)
local ViewModule = require(ReplicatedStorage.Shared.Sim.View)

local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.MapInterface)

type Pin = MapInterface.Pin

local Pins = {}

Pins.FLAG_H = Kit.size.caption + 2 -- px, the flag's height
local POINT = 0.42 -- the point's size, share of the face
local FLAG_PAD = 4 -- px, the flag's side padding
local EDGE = 2 -- px, the white edge around the face

local function candidateName(config: ConfigModule.Config, view: ViewModule.View, p: number): string
	local player = view.players[p]
	if player and player.candidate and Candidates.exists(player.candidate) then
		return Candidates.profile(config, player.candidate).name
	end
	return if p == view.you then "You" else "Rival"
end

-- Every candidate with a known location: the rivals first, yours last.
function Pins.of(config: ConfigModule.Config, view: ViewModule.View): { Pin }
	local pins: { Pin } = {}
	local mine: Pin? = nil
	for p, player in view.players do
		local state = player.location
		if state then
			local name = candidateName(config, view, p)
			local pin: Pin = {
				state = state,
				name = name,
				color = Kit.playerColor(view, p),
				tag = if p == view.you then "You" else (string.match(name, "^(%S+)") or name),
				you = if p == view.you then true else nil,
			}
			if p == view.you then
				mine = pin
			else
				table.insert(pins, pin)
			end
		end
	end
	if mine then
		table.insert(pins, mine)
	end
	return pins
end

-- The candidate's face, `px` wide. Swap the portrait here.
function Pins.face(name: string, color: Color3, px: number): Frame
	return Kit.monogram(name, color, px)
end

-- A pin `px` wide (the face), its AnchorPoint on the point's tip: place it at
-- the spot it marks. The flag sits over the face. Not a tap target: taps go
-- through to the state under it.
function Pins.build(pin: Pin, px: number): Frame
	local point = math.floor(px * POINT)
	local height = Pins.FLAG_H + px + point // 2
	local root = Kit.dataColor(Kit.box({
		Name = `Pin{pin.state}`,
		AnchorPoint = Vector2.new(0.5, 1),
		Size = UDim2.fromOffset(px, height),
		ZIndex = 1,
	})) :: Frame
	root:SetAttribute("Overhang", true)
	-- The point: a square turned 45°, half hidden under the face.
	local tip = Kit.new("Frame", {
		Name = "Point",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 1, -point // 2),
		Size = UDim2.fromOffset(point, point),
		Rotation = 45,
		BackgroundColor3 = pin.color,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = root,
	})
	local tipEdge = Kit.stroke(Kit.colors.background, EDGE)
	tipEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tipEdge.Parent = tip
	local face = Pins.face(pin.name, pin.color, px)
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0)
	face.Position = UDim2.new(0.5, 0, 0, Pins.FLAG_H)
	face.ZIndex = 2
	face.Parent = root
	local edge = face:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Color = Kit.colors.background -- the monogram's edge, in the stage navy
		edge.Thickness = EDGE
	end
	-- The flag: "You" or the rival's first name, in the candidate's color.
	local flag = Kit.text(pin.tag, {
		Name = "Flag",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		-- A width estimate (AutomaticSize grows it if the font needs more).
		Size = UDim2.fromOffset(#pin.tag * 9 + 2 * FLAG_PAD, Pins.FLAG_H),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = Kit.size.caption,
		Font = Kit.font.bold,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextColor3 = Kit.color(Colors.onColor(Kit.rgb(pin.color))),
		BackgroundColor3 = pin.color,
		BackgroundTransparency = 0,
		ZIndex = 3,
		Parent = root,
	})
	flag:SetAttribute("Overhang", true)
	Kit.new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = flag })
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, FLAG_PAD),
		PaddingRight = UDim.new(0, FLAG_PAD),
		Parent = flag,
	})
	local flagEdge = Kit.stroke(Kit.colors.background, 1)
	flagEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	flagEdge.Parent = flag
	return root
end

return Pins
