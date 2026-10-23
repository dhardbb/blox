--!strict
-- The Draft screen's small summaries: a legend for the map colors, a board of
-- what each candidate has drafted so far, and the map reveal's strongholds card.
-- All size themselves to their text, so the screen can drop them under the map,
-- into the scrolling panel, or into the portrait "Draft board" card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)
local Drafted = require(ReplicatedStorage.Shared.UI.Drafted)
local View = require(ReplicatedStorage.Shared.Sim.View)
local Words = require(ReplicatedStorage.Shared.UI.Words.Setup)

local Kit = require(script.Parent.Parent.Parent.UI.Kit)

type Config = ConfigModule.Config

export type Summary = {
	root: Frame,
	update: (self: Summary, config: Config, view: View.View, colors: { Color3 }) -> (),
}

export type Legend = {
	root: Frame,
	row: Frame, -- the two keys; the screen may move it beside the lens chips
	note: TextLabel,
	update: (self: Legend, view: View.View, rgb: { Colors.RGB }, opponent: string) -> (),
}

export type Strongholds = {
	root: Frame,
	update: (self: Strongholds, config: Config, view: View.View, colors: { Color3 }) -> (),
}

local Board = {}

local LINE_H = 20 -- px, one board line (grows if the detail wraps)
local WHO_W = 64 -- px, "You" / "Rex"
local DOT = 12 -- px, a player's dot
local SWATCH = 16 -- px, a legend key's dot
local LEGEND_TINT = 0.6 -- how far a legend dot leans toward the player's color

local function auto(): { [string]: any }
	return { Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y }
end

-- "OH PA" or a dash.
local function listText(ids: { string }): string
	if #ids == 0 then
		return "—"
	end
	return table.concat(ids, " ")
end

-- The candidate's display name, or a fallback before one is known.
function Board.candidateName(config: Config, view: View.View, p: number): string
	local id = view.players[p].candidate
	if id ~= nil and Candidates.exists(id) then
		return Candidates.profile(config, id).name
	end
	return if p == view.you then "You" else "Opponent"
end

-- "You" for the player, the opponent's first name ("Rex") otherwise.
function Board.who(config: Config, view: View.View, p: number): string
	if p == view.you then
		return "You"
	end
	return Words.firstName(Board.candidateName(config, view, p))
end

-- A filled circle in a player's color (data-colored).
local function dot(parent: Instance, name: string, size: number): Frame
	local frame = Kit.dataColor(Kit.new("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(size, size),
		BorderSizePixel = 0,
		BackgroundColor3 = Kit.colors.neutral,
		Parent = parent,
	}))
	Kit.round().Parent = frame
	return frame
end

-- What each candidate has drafted, one line each: "You  home CA · strongholds
-- TX OH · battlegrounds PA". Transparent: the holder (the strip under the map,
-- or the portrait "Draft board" card) provides the surface.
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
					LayoutOrder = if p == view.you then 1 else 2,
					Size = UDim2.new(1, 0, 0, LINE_H),
					AutomaticSize = Enum.AutomaticSize.Y,
					Parent = root,
				})
				local name = Kit.text("", {
					Name = "Name",
					Size = UDim2.fromOffset(WHO_W, LINE_H),
					Font = Kit.font.bold,
					TextScaled = true,
					TextWrapped = false,
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
			block.name.Text = Board.who(config, view, p)
			-- A player's color as text goes through its readable variant (D-056).
			block.name.TextColor3 = if colors[p] then Kit.textColor(colors[p]) else Kit.colors.text
			-- A stronghold someone nominated lost its bonus: list it apart (playtest 1).
			local active, nominated = Drafted.strongholds(view, p)
			local lost = {}
			for _, entry in nominated do
				if entry.by ~= p then
					table.insert(lost, entry.state)
				end
			end
			local text = `home {player.home or "—"} · strongholds {listText(active)}`
			if #lost > 0 then
				text ..= ` · nominated by {if p == view.you then "the opponent" else "you"}: {listText(lost)}`
			end
			block.detail.Text = text .. ` · battlegrounds {listText(player.nominations)}`
		end
	end

	return summary :: Summary
end

-- Which color means what on the map: one 44 px row with the two leans (`row`,
-- which the screen may move next to the lens chips), and a caption for rings
-- and badges (`note`).
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
		swatches[k] = dot(half, "Swatch", SWATCH)
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
	legend.row = row
	legend.note = note

	function legend.update(_self: Legend, view: View.View, rgb: { Colors.RGB }, opponent: string)
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
			local who = if p == view.you then "you" else opponent
			labels[k].Text = if polled then `Polls lead to {who}` else `Leans to {who}`
			-- The words in the player's readable text color, so the key matches the map.
			labels[k].TextColor3 = if rgb[p] then Kit.color(Colors.textOn(rgb[p])) else Kit.colors.text
		end
		note.Text = if polled
			then "Deeper color: a bigger poll lead. Ring: who drafted it. H: home. ★: battleground."
			else "Deeper color: a bigger lean. Ring: who drafted it. H: home. ★: battleground."
	end

	return legend :: Legend
end

-- The map reveal's card: each player's dot, name and strongholds, and why they
-- are theirs.
function Board.newStrongholds(): Strongholds
	local root = Kit.card({ Name = "StrongholdsCard" })
	Kit.text("Strongholds", {
		Name = "CardTitle",
		LayoutOrder = 1,
		Font = Kit.font.bold,
		Parent = root,
	})
	local rows: { [number]: { dot: Frame, who: TextLabel, list: TextLabel } } = {}
	for k = 1, 2 do
		local line = Kit.box({
			Name = if k == 1 then "StrongholdsYou" else "StrongholdsThem",
			LayoutOrder = 1 + k,
			Size = UDim2.new(1, 0, 0, Kit.size.body + 8),
			Parent = root,
		})
		local d = dot(line, "Dot", DOT)
		local who = Kit.text("", {
			Name = "Who",
			Position = UDim2.fromOffset(DOT + Kit.space.sm, 0),
			Size = UDim2.new(0, WHO_W, 1, 0),
			Font = Kit.font.medium,
			TextScaled = true,
			TextWrapped = false,
			Parent = line,
		})
		local list = Kit.text("", {
			Name = "List",
			Position = UDim2.fromOffset(DOT + Kit.space.sm + WHO_W, 0),
			Size = UDim2.new(1, -(DOT + Kit.space.sm + WHO_W), 1, 0),
			Font = Kit.font.medium,
			Parent = line,
		})
		rows[k] = { dot = d, who = who, list = list }
	end
	local note = Kit.caption("", { Name = "StrongholdsNote", LayoutOrder = 4, Parent = root })

	local card = {} :: any
	card.root = root

	function card.update(_self: Strongholds, config: Config, view: View.View, colors: { Color3 })
		local them = view.you
		for p in view.players do
			if p ~= view.you then
				them = p
			end
		end
		for k, p in { view.you, them } do
			local r = rows[k]
			r.dot.BackgroundColor3 = colors[p] or Kit.colors.neutral
			r.who.Text = Board.who(config, view, p)
			r.list.Text = listText(view.players[p].strongholds)
		end
		note.Text = Words.strongholdsNote(config)
	end

	return card :: Strongholds
end

return Board
