--!strict
-- The bot level picker (docs/DESIGN.md D-056): a row of four chips, Easy,
-- Medium, Hard and Extreme, under the Lobby's "Play vs Bot". The picked one is
-- outlined; Medium until the player picks. The pick lasts for the session (this
-- module stays loaded while the screens come and go), so Results' "Play vs Bot
-- again" uses it too. Play vs Bot sends it as the Practice request's
-- `difficulty`; the server decides what each level does.
--
--   local level = BotLevel.new({ LayoutOrder = 2, Parent = column })
--   level.root   Frame "BotLevel" (44 px tall): chips Level_Easy … Level_Extreme,
--                attribute Level = the picked level
--   BotLevel.get() -> "Easy" | "Medium" | "Hard" | "Extreme"
--   BotLevel.set(level)   (unknown names are ignored)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Words = require(ReplicatedStorage.Shared.UI.Words.Lobby)

local Kit = require(script.Parent.Kit)

local BotLevel = {}

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
	local root = Kit.box({
		Name = p.Name or "BotLevel",
		LayoutOrder = p.LayoutOrder or 0,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
	})
	Kit.list("Horizontal", Kit.space.sm).Parent = root
	local count = #Words.LEVELS
	local gap = Kit.space.sm * (count - 1) / count
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
			Kit.setSelected(chip, level == picked)
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

return BotLevel
