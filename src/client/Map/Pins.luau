--!strict
-- Candidate pins on the map (D-062): where each candidate is right now
-- (PlayerView.location, public for every player), so you can find yourself at a
-- glance. A pin is compact: the candidate's face (a small disc in their color)
-- with a tab beside it in the same color, "You" on yours and the rival's first
-- name on theirs, and a tiny pointer under the face. The real map stands it
-- beside the state's code with a thin leader (ShapeMap's mark layout), never on
-- the code. Pins are edged in the stage navy so they stand off any fill
-- (nothing on the map is white: white means selected, D-058).
--
--   Pins.of(config, view) -> { Pin }     yours last (drawn on top)
--   Pins.face(name, color, px) -> Frame  the face: the ONE place that picks the
--                                        portrait (Kit.monogram until there is art)
--   Pins.build(pin, px) -> Frame "Pin<state>"   `px` the face; AnchorPoint at the
--                                        pointer's tip (bottom middle of the face)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)
local ViewModule = require(ReplicatedStorage.Shared.Sim.View)

local Kit = require(script.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.MapInterface)

type Pin = MapInterface.Pin

local Pins = {}

Pins.FLAG_H = Kit.size.caption + 2 -- px, the tab's height
local POINT = 0.35 -- the pointer's size, share of the face
local TAB_PAD = 3 -- px, the tab's side padding
local TAB_GAP = 1 -- px between the face and the tab
local TAB_CHAR = 8 -- px, an estimated character of the tab (AutomaticSize grows it if needed)
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

-- A pin: the face `px` wide, the tab right of it, the pointer under the face.
-- Not a tap target: taps go through to the state under it.
function Pins.build(pin: Pin, px: number): Frame
	local point = math.max(4, math.floor(px * POINT))
	local tabW = #pin.tag * TAB_CHAR + 2 * TAB_PAD
	local width = px + TAB_GAP + tabW
	local height = px + point // 2
	local root = Kit.dataColor(Kit.box({
		Name = `Pin{pin.state}`,
		AnchorPoint = Vector2.new(px / 2 / width, 1),
		Size = UDim2.fromOffset(width, height),
		ZIndex = 1,
	})) :: Frame
	root:SetAttribute("Overhang", true)
	-- The pointer: a small square turned 45°, half under the face.
	local tip = Kit.new("Frame", {
		Name = "Point",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, px / 2, 1, -point // 2),
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
	face.Position = UDim2.fromOffset(0, 0)
	face.ZIndex = 2
	face.Parent = root
	local edge = face:FindFirstChild("Edge") :: UIStroke?
	if edge then
		edge.Color = Kit.colors.background -- the monogram's edge, in the stage navy
		edge.Thickness = EDGE
	end
	-- The tab: "You" or the rival's first name, in the candidate's color.
	local flag = Kit.text(pin.tag, {
		Name = "Flag",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(px + TAB_GAP, px / 2),
		Size = UDim2.fromOffset(tabW, Pins.FLAG_H),
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
		PaddingLeft = UDim.new(0, TAB_PAD),
		PaddingRight = UDim.new(0, TAB_PAD),
		Parent = flag,
	})
	local flagEdge = Kit.stroke(Kit.colors.background, 1)
	flagEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	flagEdge.Parent = flag
	return root
end

return Pins
