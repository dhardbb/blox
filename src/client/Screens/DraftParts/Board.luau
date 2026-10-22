--!strict
-- The Draft screen's two small summaries: a legend for the map colors and a board
-- of what each candidate has drafted so far. Both are transparent frames that
-- size themselves to their text, so the screen can drop them under the map, into
-- the scrolling panel, or into the portrait "Draft board" card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)
local Drafted = require(ReplicatedStorage.Shared.UI.Drafted)
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

local LINE_H = 20 -- px, one board line (grows if the detail wraps)
local WHO_W = 52 -- px, "You" / "Them"
local SWATCH = 16 -- px, a legend key's dot
local LEGEND_TINT = 0.6 -- how far a legend dot leans toward the player's color

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

-- What each candidate has drafted, one line each: "You  Dana Okafor · home CA ·
-- strongholds TX, OH · battlegrounds PA". Transparent: the holder (the strip
-- under the map, or the portrait "Draft board" card) provides the surface.
function Board.newSummary(): Summary
	local root = Kit.box(auto())
	root.Name = "Board"
	Kit.list("Vertical", Kit.space.xs).Parent = root

	local blocks: { [number]: { name: TextLabel, detail: TextLabel } } = {}

	local summary = {} :: any
	summary.root = root

	function summary.update(_self: Summary, config: Config, view: View.View, colors: { Color3 })
		for p, player in view.players do
			local block = blocks[p]
			if block == nil then
				local frame = Kit.box({
					Name = `BoardPlayer{p}`,
					LayoutOrder = p,
					Size = UDim2.new(1, 0, 0, LINE_H),
					AutomaticSize = Enum.AutomaticSize.Y,
					Parent = root,
				})
				local name = Kit.text("", {
					Name = "Name",
					Size = UDim2.fromOffset(WHO_W, LINE_H),
					Font = Kit.font.bold,
					Parent = frame,
				})
				local detail = Kit.caption("", {
					Name = "Detail",
					Position = UDim2.fromOffset(WHO_W, 0),
					Size = UDim2.new(1, -WHO_W, 0, LINE_H),
					TextYAlignment = Enum.TextYAlignment.Center,
					Parent = frame,
				})
				block = { name = name, detail = detail }
				blocks[p] = block
			end
			block.name.Text = if p == view.you then "You" else "Them"
			block.name.TextColor3 = colors[p] or Kit.colors.text
			-- A stronghold someone nominated lost its bonus: list it apart (playtest 1).
			local active, nominated = Drafted.strongholds(view, p)
			local lost = {}
			for _, entry in nominated do
				if entry.by ~= p then
					table.insert(lost, entry.state)
				end
			end
			local text =
				`{Board.candidateName(config, view, p)} · home {player.home or "—"} · strongholds {listText(
					active
				)}`
			if #lost > 0 then
				text ..= ` · nominated by {if p == view.you then "the opponent" else "you"}: {listText(lost)}`
			end
			block.detail.Text = text .. ` · battlegrounds {listText(player.nominations)}`
		end
	end

	return summary :: Summary
end

-- Which color means what on the map: one 44 px row with the two leans, and a
-- caption line for rings and badges.
function Board.newLegend(): Legend
	local root = Kit.box(auto())
	root.Name = "Legend"
	Kit.list("Vertical", Kit.space.xs).Parent = root

	local row = Kit.box({
		Name = "LegendRow",
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		LayoutOrder = 1,
		Parent = root,
	})
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
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(SWATCH, SWATCH),
			BorderSizePixel = 0,
			Parent = half,
		})
		Kit.round().Parent = swatches[k]
		labels[k] = Kit.text("", {
			Name = "Label",
			Position = UDim2.fromOffset(SWATCH + Kit.space.sm, 0),
			Size = UDim2.new(1, -(SWATCH + Kit.space.sm), 1, 0),
			TextSize = Kit.size.caption,
			Parent = half,
		})
	end
	local note = Kit.caption("", { Name = "LegendNote", LayoutOrder = 2, Parent = root })

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
				Kit.color(Colors.tint(Colors.neutral, rgb[p] or Colors.neutral, LEGEND_TINT))
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
