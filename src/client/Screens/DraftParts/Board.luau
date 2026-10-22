--!strict
-- The Draft screen's two small summaries: a legend for the map colors and a board
-- of what each candidate has drafted so far. Both are plain frames that size
-- themselves to their text, so the screen can drop them under the map or into the
-- scrolling panel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)
local View = require(ReplicatedStorage.Shared.Sim.View)

local Kit = require(script.Parent.Parent.Parent.UI.Kit)

type Config = ConfigModule.Config

export type Summary = {
	root: Frame,
	update: (self: Summary, config: Config, view: View.View, colors: { Color3 }) -> (),
}

export type Legend = {
	root: Frame,
	update: (self: Legend, view: View.View, rgb: { Colors.RGB }) -> (),
}

local Board = {}

local function auto(): { [string]: any }
	return { Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y }
end

-- "OH, PA" or a dash.
local function listText(ids: { string }): string
	if #ids == 0 then
		return "—"
	end
	return table.concat(ids, ", ")
end

-- The candidate's display name, or a fallback before one is known.
function Board.candidateName(config: Config, view: View.View, p: number): string
	local id = view.players[p].candidate
	if id ~= nil and Candidates.exists(id) then
		return Candidates.profile(config, id).name
	end
	return if p == view.you then "You" else "Opponent"
end

-- What each candidate has drafted: home, strongholds, nominated battlegrounds.
function Board.newSummary(): Summary
	local root = Kit.panel(auto())
	root.Name = "Board"
	Kit.list("Vertical", 6).Parent = root
	Kit.text("Draft board", {
		Name = "BoardTitle",
		Font = Kit.font.bold,
		LayoutOrder = 0,
		Parent = root,
	})

	local blocks: { [number]: { name: TextLabel, detail: TextLabel } } = {}

	local summary = {} :: any
	summary.root = root

	function summary.update(_self: Summary, config: Config, view: View.View, colors: { Color3 })
		for p, player in view.players do
			local block = blocks[p]
			if block == nil then
				local frame = Kit.box(auto())
				frame.Name = `BoardPlayer{p}`
				frame.LayoutOrder = p
				frame.Parent = root
				Kit.list("Vertical", 2).Parent = frame
				local name = Kit.text("", {
					Name = "Name",
					Font = Kit.font.bold,
					LayoutOrder = 1,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.fromScale(1, 0),
					Parent = frame,
				})
				local detail = Kit.text("", {
					Name = "Detail",
					TextSize = Kit.size.small,
					TextColor3 = Kit.colors.muted,
					LayoutOrder = 2,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.fromScale(1, 0),
					Parent = frame,
				})
				block = { name = name, detail = detail }
				blocks[p] = block
			end
			local who = if p == view.you then "You" else "Them"
			block.name.Text = `{who} · {Board.candidateName(config, view, p)}`
			block.name.TextColor3 = colors[p] or Kit.colors.text
			block.detail.Text =
				`Home {player.home or "—"}  ·  Strongholds {listText(player.strongholds)}  ·  Battlegrounds {listText(
					player.nominations
				)}`
		end
	end

	return summary :: Summary
end

-- Which color means what on the map.
function Board.newLegend(): Legend
	local root = Kit.box(auto())
	root.Name = "Legend"
	Kit.list("Vertical", 4).Parent = root

	local row = Kit.box({ Name = "LegendRow", Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, Parent = root })
	local swatches: { Frame } = {}
	local labels: { TextLabel } = {}
	for k = 1, 2 do
		local half = Kit.box({
			Name = `LegendKey{k}`,
			Position = UDim2.fromScale((k - 1) * 0.5, 0),
			Size = UDim2.fromScale(0.5, 1),
			Parent = row,
		})
		swatches[k] = Kit.new("Frame", {
			Name = "Swatch",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 2, 0.5, 0),
			Size = UDim2.fromOffset(16, 16),
			BorderSizePixel = 0,
			Parent = half,
		})
		Kit.round().Parent = swatches[k]
		labels[k] = Kit.text("", {
			Name = "Label",
			Position = UDim2.fromOffset(24, 0),
			Size = UDim2.new(1, -26, 1, 0),
			TextScaled = true,
			TextSize = Kit.size.small,
			Parent = half,
		})
	end
	local note = Kit.text("", {
		Name = "LegendNote",
		TextSize = Kit.size.small,
		TextColor3 = Kit.colors.muted,
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		Parent = root,
	})

	local legend = {} :: any
	legend.root = root

	function legend.update(_self: Legend, view: View.View, rgb: { Colors.RGB })
		local polled = view.states[1] ~= nil and view.states[1].poll ~= nil
		local them = 1
		for p in view.players do
			if p ~= view.you then
				them = p
			end
		end
		local sides = { view.you, them }
		for k, p in sides do
			swatches[k].BackgroundColor3 =
				Kit.color(Colors.mix(Colors.neutral, rgb[p] or Colors.neutral, 0.6))
			local who = if p == view.you then "you" else "them"
			labels[k].Text = if polled then `Polls lead toward {who}` else `Leans toward {who} (+N)`
		end
		note.Text = if polled
			then "Deeper color = bigger polling lead. Ring = who drafted it. H = home, B = battleground."
			else "Deeper color = bigger lean (N points). Ring = who drafted it. H = home, B = battleground."
	end

	return legend :: Legend
end

return Board
