--!strict
-- Results: who won and why, the final electoral votes and states, both
-- candidates, the closest states and the debate topics each side won. The
-- player leaves with Back to lobby or goes straight into another match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local State = require(ReplicatedStorage.Shared.Sim.State)

local Data = require(script.Parent.Common.Data)
local Kit = require(script.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Common.Layout)
local Types = require(script.Parent.Types)

local Screen = {}

local MAX_WIDTH = 760 -- px
local FOOTER = 64 -- px
local CLOSEST_STATES = 5
local TOTAL_EV = 538

local DECIDED_BY: { [string]: string } = {
	EV = "Decided on electoral votes.",
	States = "Electoral votes tied, so the most states won decided it.",
	Popular = "Electoral votes and states tied, so the popular vote decided it.",
	Coin = "Everything tied, so a coin flip decided it.",
}

-- The sentence under the banner.
local function reasonText(payload: Session.StatePayload, election: State.ElectionResult?): string
	local result = payload.result
	if result == nil then
		return "The match ended without a result."
	end
	if result.reason == "Forfeit" then
		if result.winner == payload.you then
			return "Your opponent forfeited the match."
		end
		return "You forfeited the match by missing too many turns."
	elseif result.reason == "Abandoned" then
		return "The match was abandoned before election night."
	end
	if election then
		return DECIDED_BY[election.decidedBy] or "Decided on election night."
	end
	return "Decided on election night."
end

local function playerColor(view: any, player: number): Color3
	local entry = view.players[player]
	return Kit.color(Colors.of(if entry then entry.color else nil))
end

function Screen.mount(parent: Frame, ctx: Types.Ctx): Types.Screen
	local page = Layout.page(parent, { maxWidth = MAX_WIDTH, footer = FOOTER })
	local footer = page.footer :: Frame
	Kit.list("Horizontal", 8).Parent = footer

	local rendered: Session.StatePayload? = nil
	local details: Frame? = nil

	Kit.button("Back to lobby", function()
		ctx.store.dismissResult()
	end, {
		Name = "BackToLobby",
		LayoutOrder = 1,
		Size = UDim2.new(0.5, -4, 1, 0),
		TextSize = Kit.size.large,
		Parent = footer,
	})
	local againBot = false
	local playAgain = Kit.button("Play again", function()
		ctx.store.dismissResult()
		ctx.net.send(if againBot then "Practice" else "Queue")
	end, {
		Name = "PlayAgain",
		LayoutOrder = 2,
		Size = UDim2.new(0.5, -4, 1, 0),
		TextSize = Kit.size.large,
		BackgroundColor3 = Kit.colors.accent,
		TextColor3 = Kit.colors.background,
		Parent = footer,
	})

	local function label(into: Instance, text: string, props: { [string]: any }?): TextLabel
		local base: { [string]: any } = {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = into,
		}
		if props then
			for key, value in props do
				base[key] = value
			end
		end
		return Kit.text(text, base)
	end

	local function panel(into: Instance, name: string, order: number, size: UDim2?): Frame
		local frame = Kit.panel({
			Name = name,
			LayoutOrder = order,
			Size = size or UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = into,
		})
		Kit.list("Vertical", 6).Parent = frame
		return frame
	end

	local function playerPanel(into: Instance, current: Session.StatePayload, player: number, order: number)
		local view = current.view
		local election = view.election
		local mine = player == current.you
		local entry = view.players[player]
		local tint = playerColor(view, player)
		local box =
			panel(into, if mine then "Player_You" else "Player_Opponent", order, UDim2.new(0.5, -4, 0, 0))

		label(box, if mine then "YOU" else "OPPONENT", {
			Name = "Tag",
			LayoutOrder = 1,
			TextSize = Kit.size.small,
			TextColor3 = Kit.colors.muted,
			Font = Kit.font.bold,
		})
		label(box, if election then `{election.ev[player]} EV` else "- EV", {
			Name = "EV",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 44),
			AutomaticSize = Enum.AutomaticSize.None,
			Font = Kit.font.bold,
			TextSize = Kit.size.huge,
			TextScaled = true,
			TextColor3 = tint,
		})
		if election then
			local won = election.statesWon[player]
			label(box, `{won} {if won == 1 then "state" else "states"} won`, {
				Name = "StatesWon",
				LayoutOrder = 3,
			})
		end
		label(box, Data.candidateName(ctx.config, if entry then entry.candidate else nil), {
			Name = "Candidate",
			LayoutOrder = 4,
			Font = Kit.font.bold,
			TextSize = Kit.size.large,
		})
		local colorRow = Kit.box({
			Name = "ColorRow",
			LayoutOrder = 5,
			Size = UDim2.new(1, 0, 0, 22),
			Parent = box,
		})
		Kit.list("Horizontal", 6).Parent = colorRow
		local swatch = Kit.box({
			Name = "Swatch",
			LayoutOrder = 1,
			Size = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 0,
			BackgroundColor3 = tint,
			Parent = colorRow,
		})
		Kit.round().Parent = swatch
		Kit.text(if entry and entry.color then entry.color else "No color", {
			Name = "ColorName",
			LayoutOrder = 2,
			Size = UDim2.new(1, -22, 1, 0),
			TextColor3 = Kit.colors.muted,
			Parent = colorRow,
		})
		label(box, `Platform: {Data.platformText(if entry then entry.platform else nil)}`, {
			Name = "Platform",
			LayoutOrder = 6,
			TextSize = Kit.size.small,
			TextColor3 = Kit.colors.muted,
		})
	end

	local function render(current: Session.StatePayload)
		if details then
			details:Destroy()
		end
		local view = current.view
		local election = view.election
		local result = current.result
		local you = current.you

		local column = Kit.box({
			Name = "Details",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = page.content,
		})
		Kit.list("Vertical", 12).Parent = column
		details = column

		-- Banner.
		local bannerText, bannerColor = "No result", Kit.colors.muted
		if result and result.winner == you then
			bannerText, bannerColor = "YOU WON", Kit.colors.good
		elseif result and result.winner ~= 0 then
			bannerText, bannerColor = "You lost", Kit.colors.danger
		end
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		Kit.text(bannerText, {
			Name = "Banner",
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, 72),
			Font = Kit.font.bold,
			TextSize = 64,
			TextScaled = true,
			TextColor3 = bannerColor,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = column,
		})
		label(column, reasonText(current, election), {
			Name = "Reason",
			LayoutOrder = nextOrder(),
			TextColor3 = Kit.colors.muted,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		label(column, "", {
			Name = "RatingChange",
			LayoutOrder = nextOrder(),
			TextColor3 = Kit.colors.accent,
			TextXAlignment = Enum.TextXAlignment.Center,
			Visible = false,
		})

		-- Electoral vote bar.
		if election then
			local bar = Kit.box({
				Name = "EVBar",
				LayoutOrder = nextOrder(),
				Size = UDim2.new(1, 0, 0, 14),
				BackgroundTransparency = 0,
				BackgroundColor3 = Kit.colors.surface,
				ClipsDescendants = true,
				Parent = column,
			})
			Kit.corner(7).Parent = bar
			local left = 0
			for player = 1, #view.players do
				local share = election.ev[player] / TOTAL_EV
				Kit.box({
					Name = `EVBar_{player}`,
					Position = UDim2.fromScale(left, 0),
					Size = UDim2.fromScale(share, 1),
					BackgroundTransparency = 0,
					BackgroundColor3 = playerColor(view, player),
					Parent = bar,
				})
				left += share
			end
		end

		-- You and your opponent, side by side.
		local versus = Kit.box({
			Name = "Versus",
			LayoutOrder = nextOrder(),
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = column,
		})
		Kit.list("Horizontal", 8).Parent = versus
		local players: { number } = { you }
		for player = 1, #view.players do
			if player ~= you then
				table.insert(players, player)
			end
		end
		for index, player in players do
			playerPanel(versus, current, player, index)
		end

		-- The closest states, closest first.
		if election and #election.results > 0 then
			local box = panel(column, "Closest", nextOrder())
			label(box, "Closest states", {
				Name = "ClosestHeading",
				LayoutOrder = 1,
				Font = Kit.font.bold,
				TextSize = Kit.size.large,
			})
			local row = 1
			for k = #election.results, math.max(1, #election.results - CLOSEST_STATES + 1), -1 do
				local r = election.results[k]
				local record = StateData.byId[r.state]
				local stateName = if record then record.name else r.state
				local votes = if record then record.ev else 0
				local who = if r.winner == 0
					then "tied"
					elseif r.winner == you then `you by {string.format("%.1f", r.margin)}`
					else `opponent by {string.format("%.1f", r.margin)}`
				row += 1
				label(box, `{stateName} ({votes} EV): {who}`, {
					Name = `Closest_{r.state}`,
					LayoutOrder = row,
					TextColor3 = if r.winner == 0 then Kit.colors.muted else playerColor(view, r.winner),
				})
			end
		end

		-- Debate topics.
		if #view.debates > 0 then
			local box = panel(column, "Debates", nextOrder())
			local mine, theirs = 0, 0
			local lines: { string } = {}
			for _, debate in view.debates do
				local parts: { string } = {}
				for t, topic in debate.topics do
					local winner = debate.winners[t]
					if winner == you then
						mine += 1
					elseif winner ~= nil and winner ~= 0 then
						theirs += 1
					end
					local who = if winner == you
						then "you"
						elseif winner == nil or winner == 0 then "tie"
						else "opponent"
					table.insert(parts, `{Data.issueName(topic)}: {who}`)
				end
				table.insert(lines, `Week {debate.week} - {table.concat(parts, ", ")}`)
			end
			label(box, `Debate topics won: you {mine}, opponent {theirs}`, {
				Name = "DebateHeading",
				LayoutOrder = 1,
				Font = Kit.font.bold,
				TextSize = Kit.size.large,
			})
			for index, line in lines do
				label(box, line, {
					Name = `Debate_{index}`,
					LayoutOrder = index + 1,
					TextColor3 = Kit.colors.muted,
				})
			end
		end

		local _, opponent = Data.opponent(current)
		againBot = opponent ~= nil and opponent.kind == "Bot"
		playAgain.Text = if againBot then "Practice again" else "Play again"
	end

	local function relayout()
		page.setPortrait(ctx.portrait())
	end

	relayout()

	return {
		update = function(state: Types.State)
			relayout()
			local current = state.payload :: Session.StatePayload?
			if current and current ~= rendered then
				rendered = current
				render(current)
			end
			-- Rated matches: "Rating 1000 → 1016 (+16)", once the server sends it.
			local change = state.rating
			local line = parent:FindFirstChild("RatingChange", true) :: TextLabel?
			if line and current and change and change.matchId == current.matchId then
				local delta = change.after - change.before
				line.Text =
					`Rating {change.before} → {change.after} ({if delta >= 0 then "+" else ""}{delta})`
				line.Visible = true
			end
		end,
		tick = function(_now: number)
			relayout()
		end,
		destroy = function() end,
	}
end

return Screen
