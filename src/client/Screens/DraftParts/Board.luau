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
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
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
	fit: (self: Legend) -> (), -- side by side or stacked for the row's width now (the screen calls it after moving the row)
}

export type Strongholds = {
	root: Frame,
	update: (self: Strongholds, config: Config, view: View.View, colors: { Color3 }) -> (),
}

local Board = {}

local LINE_H = 20 -- px, one board line (grows if the detail wraps)
local WHO_W = 64 -- px, "You" / "Buster"
local HOLD_FACE = 36 -- px, a player's candidate portrait on the strongholds card (D-068; D-091 was 24)
local HOLD_ROW_H = 28 -- px, one stronghold's row on that card
local HOLD_CODE_W = 30 -- px, its code ("VA"; 36 left "South Carolina" no room on a phone, fix17)
local HOLD_EV_W = 24 -- px, its votes at the right
local SWATCH = 16 -- px, a legend key's dot
local LEGEND_TINT = 0.6 -- how far a legend dot leans toward the player's color
local LEGEND_PAIR_W = 300 -- px of row for the two keys side by side; narrower, they stack (an iPad's slot beside the lens chips, fix17)
local LEGEND_WORDS_W = 160 -- px of row for "Leans to Buster"; narrower (an iPad's map reveal), only the names

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

-- The candidate's display name (a custom name when the view carries one,
-- D-069), or a fallback before one is known.
function Board.candidateName(config: Config, view: View.View, p: number): string
	local custom = view.players[p].customName
	if custom ~= nil then
		return custom
	end
	local id = view.players[p].candidate
	if id ~= nil and Candidates.exists(id) then
		return Candidates.profile(config, id).name
	end
	return if p == view.you then "You" else "Opponent"
end

-- "You" for the player, the opponent's first name ("Buster") otherwise.
function Board.who(config: Config, view: View.View, p: number): string
	if p == view.you then
		return "You"
	end
	return view.players[p].customName or Words.firstName(Board.candidateName(config, view, p))
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
	local halves: { Frame } = {}
	for k = 1, 2 do
		local half = Kit.box({
			Name = `LegendKey{k}`,
			Position = UDim2.fromScale((k - 1) * 0.5, 0),
			Size = UDim2.fromScale(0.5, 1),
			Parent = row,
		})
		halves[k] = half
		swatches[k] = dot(half, "Swatch", SWATCH)
		labels[k] = Kit.text("", {
			Name = "Label",
			Position = UDim2.fromOffset(SWATCH + Kit.space.sm, 0),
			Size = UDim2.new(1, -(SWATCH + Kit.space.sm), 1, 0),
			TextSize = Kit.size.caption,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = half,
		})
	end
	-- Side by side when the row has room, else one over the other (each one
	-- line, never "Leans / to / Buster" in a narrow half); narrower still, the
	-- names alone (the colors say the rest, and the Map key spells it out).
	local words: { string } = { "", "" }
	local names: { string } = { "", "" }
	local function placeKeys()
		local w = row.AbsoluteSize.X
		local stacked = w > 0 and w < LEGEND_PAIR_W
		local short = w > 0 and w < LEGEND_WORDS_W
		for k, label in labels do
			label.Text = if short then names[k] else words[k]
		end
		for k, half in halves do
			half.Position = if stacked
				then UDim2.fromScale(0, (k - 1) * 0.5)
				else UDim2.fromScale((k - 1) * 0.5, 0)
			half.Size = if stacked then UDim2.fromScale(1, 0.5) else UDim2.fromScale(0.5, 1)
			swatches[k].Size = if stacked
				then UDim2.fromOffset(SWATCH * 3 // 4, SWATCH * 3 // 4)
				else UDim2.fromOffset(SWATCH, SWATCH)
		end
	end
	placeKeys()
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeKeys)
	local note = Kit.caption("", { Name = "LegendNote", LayoutOrder = 2, Parent = root })

	local legend = {} :: any
	legend.root = root
	legend.row = row
	legend.note = note
	function legend.fit(_self: Legend)
		placeKeys()
	end

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
			words[k] = if polled then `Polls lead to {who}` else `Leans to {who}`
			names[k] = if p == view.you then "You" else opponent
			labels[k].Text = words[k]
			-- The words in the player's readable text color, so the key matches the map.
			labels[k].TextColor3 = if rgb[p] then Kit.color(Colors.textOn(rgb[p])) else Kit.colors.text
		end
		placeKeys() -- the row may have moved (beside the chips, into the panel)
		note.Text = if polled
			then "Deeper color: a bigger poll lead. Ring: who drafted it. H: home. ★: battleground."
			else "Deeper color: a bigger lean. Ring: who drafted it. H: home. ★: battleground."
	end

	return legend :: Legend
end

-- The map reveal's card (D-091): one column per player, side by side: a
-- header with the portrait (ringed in their color), the name and the votes the
-- strongholds hold, then each stronghold as a row ("VA  Virginia  13"),
-- biggest first, and why they are theirs under both columns. Each column keeps
-- "List", the codes in one line, for the sheet and the tests (hidden).
function Board.newStrongholds(): Strongholds
	local root = Kit.card({ Name = "StrongholdsCard" })
	Kit.text("Strongholds", {
		Name = "CardTitle",
		LayoutOrder = 1,
		Font = Kit.font.bold,
		Parent = root,
	})
	local columns = Kit.box(auto())
	columns.Name = "Columns"
	columns.LayoutOrder = 2
	columns.Parent = root
	Kit.list("Horizontal", Kit.space.md).Parent = columns
	type Column = { face: Frame, who: TextLabel, total: TextLabel, list: TextLabel, rows: Frame }
	local cols: { [number]: Column } = {}
	for k = 1, 2 do
		local column = Kit.box({
			Name = if k == 1 then "StrongholdsYou" else "StrongholdsThem",
			LayoutOrder = k,
			Size = UDim2.new(0.5, -Kit.space.md // 2, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = columns,
		})
		Kit.list("Vertical", Kit.space.xs).Parent = column
		local head = Kit.box({
			Name = "Head",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, HOLD_FACE),
			Parent = column,
		})
		local face = Kit.box({
			Name = "Face",
			Size = UDim2.fromOffset(HOLD_FACE, HOLD_FACE),
			Parent = head,
		})
		local who = Kit.text("", {
			Name = "Who",
			Position = UDim2.fromOffset(HOLD_FACE + Kit.space.sm, 0),
			Size = UDim2.new(1, -(HOLD_FACE + Kit.space.sm), 0.5, 0),
			Font = Kit.font.bold,
			TextScaled = true,
			TextWrapped = false,
			Parent = head,
		})
		local total = Kit.text("", {
			Name = "Total",
			Position = UDim2.new(0, HOLD_FACE + Kit.space.sm, 0.5, 0),
			Size = UDim2.new(1, -(HOLD_FACE + Kit.space.sm), 0.5, 0),
			TextSize = Kit.size.caption,
			TextColor3 = Kit.colors.muted,
			TextWrapped = false,
			Parent = head,
		})
		local list = Kit.text("", { Name = "List", Visible = false, Parent = column })
		local rows = Kit.box(auto())
		rows.Name = "Rows"
		rows.LayoutOrder = 2
		rows.Parent = column
		Kit.list("Vertical", Kit.space.xs).Parent = rows
		cols[k] = { face = face, who = who, total = total, list = list, rows = rows }
	end
	local note = Kit.caption("", { Name = "StrongholdsNote", LayoutOrder = 4, Parent = root })

	-- One stronghold's row: the code (bold, in the holder's readable color),
	-- the state's name and its votes at the right.
	local function holdRow(parent: Frame, id: string, order: number, color: Color3): Frame
		local row = Kit.panel({
			Name = `Hold_{id}`,
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, HOLD_ROW_H),
			BackgroundColor3 = Kit.colors.raised,
			Parent = parent,
		})
		local pad = row:FindFirstChildOfClass("UIPadding")
		if pad then
			pad.PaddingTop = UDim.new(0, 0)
			pad.PaddingBottom = UDim.new(0, 0)
			pad.PaddingLeft = UDim.new(0, Kit.space.sm)
			pad.PaddingRight = UDim.new(0, Kit.space.sm)
		end
		local record = StateData.byId[id]
		Kit.text(id, {
			Name = "Code",
			Size = UDim2.new(0, HOLD_CODE_W, 1, 0),
			Font = Kit.font.bold,
			TextWrapped = false,
			TextColor3 = Kit.textColor(color),
			Parent = row,
		})
		Kit.text(if record then record.name else id, {
			Name = "StateName",
			Position = UDim2.fromOffset(HOLD_CODE_W, 0),
			Size = UDim2.new(1, -(HOLD_CODE_W + HOLD_EV_W), 1, 0),
			TextSize = Kit.size.caption,
			TextColor3 = Kit.colors.muted,
			TextScaled = true,
			TextWrapped = false,
			Parent = row,
		})
		Kit.text(if record then tostring(record.ev) else "", {
			Name = "Votes",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, HOLD_EV_W, 1, 0),
			Font = Kit.font.bold,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
		return row
	end

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
			local c = cols[k]
			local id = view.players[p].candidate
			local name = Board.candidateName(config, view, p)
			local color = colors[p] or Kit.colors.neutral
			local portrait = c.face:FindFirstChild("Portrait") :: Frame?
			if portrait == nil or c.face:GetAttribute("For") ~= `{id}|{name}` then
				if portrait then
					portrait:Destroy()
				end
				c.face:SetAttribute("For", `{id}|{name}`)
				portrait = Kit.portrait(id, name, HOLD_FACE)
				local built = portrait :: Frame
				built.Parent = c.face
			end
			Kit.paintPortrait(portrait :: Frame, { ring = color })
			c.who.Text = Board.who(config, view, p)
			c.who.TextColor3 = if colors[p] then Kit.textColor(colors[p]) else Kit.colors.text
			-- Biggest first.
			local ids = table.clone(view.players[p].strongholds)
			table.sort(ids, function(a, b)
				local ra, rb = StateData.byId[a], StateData.byId[b]
				local ea, eb = if ra then ra.ev else 0, if rb then rb.ev else 0
				if ea ~= eb then
					return ea > eb
				end
				return a < b
			end)
			c.list.Text = listText(view.players[p].strongholds)
			local key = `{table.concat(ids, " ")}|{color.R},{color.G},{color.B}`
			if c.rows:GetAttribute("For") ~= key then
				c.rows:SetAttribute("For", key)
				for _, child in c.rows:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				for order, state in ids do
					holdRow(c.rows, state, order, color)
				end
			end
			local votes = 0
			for _, state in ids do
				local record = StateData.byId[state]
				votes += if record then record.ev else 0
			end
			c.total.Text = Words.votes(votes)
		end
		note.Text = Words.strongholdsNote(config)
	end

	return card :: Strongholds
end

return Board
