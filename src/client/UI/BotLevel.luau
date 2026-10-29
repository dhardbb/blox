--!strict
-- The bot level picker (docs/DESIGN.md D-059): a row of four chips, Easy,
-- Medium, Hard and Extreme, under the Lobby's "Play vs Bot". The picked one is
-- outlined; Easy until the player picks (D-087). BotLevel.note is a caption
-- line that says what the picked level is like (Words.LEVEL_NOTES). The pick lasts for the session (this
-- module stays loaded while the screens come and go), so Results' "Play vs Bot
-- again" uses it too. Play vs Bot sends it as the Practice request's
-- `difficulty`; the server decides what each level does.
--
-- Each chip carries a colored dot ("LevelDot", D-090) that climbs with the
-- level, so the four read apart at a glance: green, gold, red, violet (the
-- player colors; decorative, the word says the level).
--
-- It reads as one segmented control: the chips sit in a `field` track, the
-- picked one raised with the white selection outline, the others flat with
-- muted labels (still 44 px tall tap targets).
--
--   local level = BotLevel.new({ LayoutOrder = 2, Parent = column })
--   level.root   Frame "BotLevel" (BotLevel.HEIGHT tall, the track): chips
--                Level_Easy … Level_Extreme, attribute Level = the picked level
--   BotLevel.get() -> "Easy" | "Medium" | "Hard" | "Extreme"
--   BotLevel.set(level)   (unknown names are ignored)
--   BotLevel.note(props) -> TextLabel "BotLevelNote" (one caption line, follows the pick)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Words = require(ReplicatedStorage.Shared.UI.Words.Lobby)

local Kit = require(script.Parent.Kit)

local BotLevel = {}

local INSET = 3 -- px between the track's edge and the chips
BotLevel.HEIGHT = Kit.MIN_TOUCH + 2 * INSET -- px, the track
BotLevel.NOTE_HEIGHT = Kit.size.caption + Kit.space.xs -- px, the note's one line
local DOT = 8 -- px, a level's dot
local DOT_INSET = 10 -- px from the chip's left edge to its dot

-- Each level's dot (D-090): easy to hard, like trail markers.
BotLevel.DOT_COLORS = table.freeze({
	Easy = Colors.player.Emerald,
	Medium = Colors.player.Amber,
	Hard = Colors.player.Crimson,
	Extreme = Colors.player.Violet,
})

local picked: string = Words.DEFAULT_LEVEL
local rows: { () -> () } = {} -- repaint functions of the mounted pickers

export type Picker = {
	root: Frame,
}

function BotLevel.get(): string
	return picked
end

function BotLevel.set(level: string)
	if table.find(Words.LEVELS, level) == nil then
		return
	end
	picked = level
	for _, repaint in table.clone(rows) do
		repaint()
	end
end

function BotLevel.new(props: { [string]: any }?): Picker
	local p: { [string]: any } = props or {}
	local root = Kit.new("Frame", {
		Name = p.Name or "BotLevel",
		LayoutOrder = p.LayoutOrder or 0,
		Size = UDim2.new(1, 0, 0, BotLevel.HEIGHT),
		BackgroundColor3 = Kit.colors.field,
		BorderSizePixel = 0,
	}) :: Frame
	Kit.corner(Kit.radius.button).Parent = root
	Kit.bevel(root)
	Kit.pad(INSET).Parent = root
	Kit.list("Horizontal", INSET).Parent = root
	local count = #Words.LEVELS
	local gap = INSET * (count - 1) / count
	local chips: { [string]: TextButton } = {}
	for k, level in Words.LEVELS do
		chips[level] = Kit.chip(level, function()
			BotLevel.set(level)
		end, {
			Name = `Level_{level}`,
			LayoutOrder = k,
			Size = UDim2.new(1 / count, -gap, 1, 0),
			Parent = root,
		})
		local rgb = BotLevel.DOT_COLORS[level]
		if rgb then
			local dot = Kit.new("Frame", {
				Name = "LevelDot",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, DOT_INSET - Kit.space.sm, 0.5, 0), -- inside the chip's padding
				Size = UDim2.fromOffset(DOT, DOT),
				BackgroundColor3 = Kit.color(rgb),
				BorderSizePixel = 0,
				Parent = chips[level],
			})
			Kit.round().Parent = dot
			Kit.dataColor(dot)
		end
	end

	local parented = false
	local function repaint()
		if parented and root.Parent == nil then
			-- A destroyed picker stops following the pick.
			local at = table.find(rows, repaint)
			if at then
				table.remove(rows, at)
			end
			return
		end
		for level, chip in chips do
			local on = level == picked
			Kit.setSelected(chip, on)
			-- Segmented: only the picked chip is a raised button.
			chip.BackgroundTransparency = if on then 0 else 1
			chip.TextColor3 = if on then Kit.colors.text else Kit.colors.muted
		end
		root:SetAttribute("Level", picked)
	end
	table.insert(rows, repaint)
	repaint()

	if p.Parent then
		root.Parent = p.Parent
		parented = true
	end
	return { root = root }
end

-- The picked level's one-line description, kept in step with every picker.
function BotLevel.note(props: { [string]: any }?): TextLabel
	local p: { [string]: any } = props or {}
	local label = Kit.caption("", {
		Name = p.Name or "BotLevelNote",
		LayoutOrder = p.LayoutOrder or 0,
		Size = UDim2.new(1, 0, 0, BotLevel.NOTE_HEIGHT),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}) :: TextLabel
	local parented = false
	local function repaint()
		if parented and label.Parent == nil then
			-- A destroyed note stops following the pick.
			local at = table.find(rows, repaint)
			if at then
				table.remove(rows, at)
			end
			return
		end
		label.Text = Words.LEVEL_NOTES[picked] or ""
		label:SetAttribute("Level", picked)
	end
	table.insert(rows, repaint)
	repaint()
	if p.Parent then
		label.Parent = p.Parent
		parented = true
	end
	return label
end

return BotLevel
