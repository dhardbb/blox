--!strict
-- Results (docs/UI-STYLE.md §4.9): who won, big, and why in three short
-- reasons, then the details one tap away. The player leaves with Back to lobby
-- or goes straight into another match.
--
-- Layout: a scrolling column over the pinned ActionBar ("Play vs Bot again" /
-- "Play again" primary, "Back to lobby" secondary):
--   Banner        "You won" / "You lost" (hero, good / bad)
--   Reason        "280 votes to 258" (or the tiebreak, a forfeit)
--   RatingSlot    the rating change, once the server sends it (rated matches)
--   EVBar         both players' votes in their colors, the 270 tick (data colors)
--   Versus        two cards: color dot + name, "280 votes", "20 states", debate
--                 topics won. Player colors stay on the dot and the bar, never
--                 on big numbers next to the primary button (D-047, D-051).
--   WhyHead       "Why you won" / "Why Rex won" and three bullets Reason_<k>
--                 (Shared/UI/Words/Reveal.keyReasons); after a loss, one more
--                 line NextTime ("Try next time: …", Words.nextTime)
--   FullBreakdown ghost button: the BreakdownSheet with "What decided it"
--                 (Decided, Decided_<k>: Swing.decided), the closest states
--                 (Closest, Closest_<id>) and every debate (Debates, Debate_<k>).
-- Four text sizes: hero, heading, body, caption.
--
-- The moment (docs/UI-STYLE.md §2.7, D-053), once per match: a win pops the
-- banner from BANNER_FROM, counts both vote totals up, drops confetti in both
-- players' colors and plays "victory"; a loss fades the banner in, counts the
-- votes, and plays "defeat". Nothing else moves, and nothing waits on it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Session = require(ReplicatedStorage.Shared.Net.Session)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local State = require(ReplicatedStorage.Shared.Sim.State)
local Swing = require(ReplicatedStorage.Shared.UI.Swing)
local Words = require(ReplicatedStorage.Shared.UI.Words.Reveal)

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local Audio = require(script.Parent.Parent.UI.Audio)
local Data = require(script.Parent.Common.Data)
local Kit = require(script.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Common.Layout)
local Motion = require(script.Parent.Parent.UI.Motion)
local Sheet = require(script.Parent.Parent.UI.Sheet)
local Types = require(script.Parent.Types)

local Screen = {}

local MAX_WIDTH = 640 -- px
local CLOSEST_STATES = 5
local TOTAL_EV = 538
local WIN_EV = 270
local EV_BAR_H = 14 -- px
local TICK_W = 2 -- px, the 270 mark on the EV bar
local DOT = 14 -- px, a player's color dot
local BANNER_FROM = 0.8 -- a won banner's starting scale (it springs to 1)
local LOSS_FADE = 0.5 -- s, a lost banner fading in
local COUNT_SECONDS = 0.6 -- s, the vote totals counting up
local CONFETTI = 50 -- pieces on a win

local DECIDED_BY: { [string]: string } = {
	States = "Votes tied, so the most states won decided it.",
	Popular = "Votes and states tied, so the popular vote decided it.",
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
		local tie = DECIDED_BY[election.decidedBy]
		if tie then
			return tie
		end
		local you = payload.you
		local them = if you == 1 then 2 else 1
		return `{election.ev[you]} votes to {election.ev[them]}`
	end
	return "Decided on election night."
end

local function plural(n: number, word: string): string
	return `{n} {word}{if n == 1 then "" else "s"}`
end

function Screen.mount(parent: Frame, ctx: Types.Ctx): Types.Screen
	local page = Layout.page(parent, { maxWidth = MAX_WIDTH, footer = Kit.BAR_H })

	local rendered: Session.StatePayload? = nil
	local celebrated: string? = nil -- the match whose moment has played
	local details: Frame? = nil
	local ratingLine: TextLabel? = nil
	local sheet = Sheet.new(parent, { title = "Full breakdown", name = "BreakdownSheet" })

	local againBot = false
	local bar = ActionBar.new(page.footer :: Frame, {
		primary = "Play again",
		onPrimary = function()
			ctx.store.dismissResult()
			ctx.net.send(if againBot then "Practice" else "Queue")
		end,
		primaryName = "PlayAgain",
		secondary = "Back to lobby",
		onSecondary = function()
			ctx.store.dismissResult()
		end,
		secondaryName = "BackToLobby",
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

	-- Debate topics won by each player, over every debate.
	local function topicsWon(view: any, player: number): number
		local won = 0
		for _, debate in view.debates do
			for t = 1, #debate.topics do
				if debate.winners[t] == player then
					won += 1
				end
			end
		end
		return won
	end

	local function playerCard(
		into: Instance,
		current: Session.StatePayload,
		player: number,
		order: number
	): TextLabel?
		local view = current.view
		local election = view.election
		local mine = player == current.you
		local entry = view.players[player]
		local card = Kit.card({
			Name = if mine then "Player_You" else "Player_Opponent",
			LayoutOrder = order,
			Size = UDim2.new(0.5, -Kit.space.sm / 2, 0, 0),
			Parent = into,
		})
		local nameRow = Kit.box({
			Name = "NameRow",
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, Kit.size.heading + 8),
			Parent = card,
		})
		local dot = Kit.box({
			Name = "Swatch",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(DOT, DOT),
			BackgroundTransparency = 0,
			BackgroundColor3 = Kit.playerColor(view, player),
			Parent = nameRow,
		})
		Kit.round().Parent = dot
		Kit.text(Data.candidateName(ctx.config, if entry then entry.candidate else nil), {
			Name = "Candidate",
			Position = UDim2.fromOffset(DOT + Kit.space.sm, 0),
			Size = UDim2.new(1, -(DOT + Kit.space.sm), 1, 0),
			Font = Kit.font.bold,
			TextSize = Kit.size.heading,
			TextScaled = true,
			Parent = nameRow,
		})
		label(card, if mine then "You" else "Opponent", {
			Name = "Tag",
			LayoutOrder = 2,
			TextSize = Kit.size.caption,
			TextColor3 = Kit.colors.muted,
		})
		local votes: TextLabel? = nil
		if election then
			votes = label(card, plural(election.ev[player], "vote"), {
				Name = "EV",
				LayoutOrder = 3,
				Font = Kit.font.bold,
			})
			-- Its own line, so a phone never breaks "20 states" in two.
			label(card, plural(election.statesWon[player], "state"), {
				Name = "States",
				LayoutOrder = 4,
				TextSize = Kit.size.caption,
				TextColor3 = Kit.colors.muted,
			})
		end
		if #view.debates > 0 then
			label(card, `{plural(topicsWon(view, player), "debate topic")} won`, {
				Name = "Topics",
				LayoutOrder = 5,
				TextSize = Kit.size.caption,
				TextColor3 = Kit.colors.muted,
			})
		end
		return votes
	end

	-- The sheet: what decided it, the closest states, every debate.
	local function fillSheet(current: Session.StatePayload)
		for _, child in sheet.body:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local view = current.view
		local election = view.election
		local you = current.you
		local order = 0
		local function section(name: string, title: string): Frame
			order += 1
			local box =
				Kit.stack({ Name = name, LayoutOrder = order, Parent = sheet.body }, "Vertical", Kit.space.xs)
			Kit.text(title, { Name = "Title", LayoutOrder = 0, Font = Kit.font.bold, Parent = box })
			return box
		end
		if election then
			local box = section("Decided", "What decided it")
			for index, line in Swing.decided(ctx.config, view) do
				label(
					box,
					Words.inVotes(line),
					{ Name = `Decided_{index}`, LayoutOrder = index, TextSize = Kit.size.caption }
				)
			end
		end
		if election and #election.results > 0 then
			local box = section("Closest", "Closest states")
			local row = 0
			for k = #election.results, math.max(1, #election.results - CLOSEST_STATES + 1), -1 do
				local r = election.results[k]
				local record = StateData.byId[r.state]
				local stateName = if record then record.name else r.state
				local votes = if record then record.ev else 0
				local who = if r.winner == 0
					then "tied"
					elseif r.winner == you then `you by {string.format("%.1f", r.margin)} points`
					else `opponent by {string.format("%.1f", r.margin)} points`
				row += 1
				label(box, `{stateName} · {plural(votes, "vote")}: {who}`, {
					Name = `Closest_{r.state}`,
					LayoutOrder = row,
					TextSize = Kit.size.caption,
					TextColor3 = if r.winner == 0 then Kit.colors.muted else Kit.playerColor(view, r.winner),
				})
			end
		end
		if #view.debates > 0 then
			local box = section("Debates", "Debates")
			for index, debate in view.debates do
				local parts: { string } = {}
				for t, topic in debate.topics do
					local winner = debate.winners[t]
					local who = if winner == you
						then "you"
						elseif winner == nil or winner == 0 then "tie"
						else "opponent"
					table.insert(parts, `{Data.issueName(topic)}: {who}`)
				end
				label(box, `Week {debate.week} · {table.concat(parts, ", ")}`, {
					Name = `Debate_{index}`,
					LayoutOrder = index,
					TextSize = Kit.size.caption,
					TextColor3 = Kit.colors.muted,
				})
			end
		end
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
		Kit.list("Vertical", Kit.space.md).Parent = column
		details = column

		-- Banner.
		local bannerText, bannerColor = "No result", Kit.colors.muted
		if result and result.winner == you then
			bannerText, bannerColor = "You won", Kit.colors.good
		elseif result and result.winner ~= 0 then
			bannerText, bannerColor = "You lost", Kit.colors.danger
		end
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		local banner = Kit.text(bannerText, {
			Name = "Banner",
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, Kit.size.hero + 8),
			Font = Kit.font.bold,
			TextSize = Kit.size.hero,
			TextScaled = true,
			TextColor3 = bannerColor,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = column,
		})
		label(column, reasonText(current, election), {
			Name = "Reason",
			LayoutOrder = nextOrder(),
			Font = Kit.font.medium,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		-- The rating line's room is always there, so the layout never shifts when
		-- the change arrives (rated matches only).
		local slot = Kit.box({
			Name = "RatingSlot",
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, Kit.size.body + 6),
			Parent = column,
		})
		ratingLine = Kit.text("", {
			Name = "RatingChange",
			Size = UDim2.fromScale(1, 1),
			TextColor3 = Kit.colors.muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Visible = false,
			Parent = slot,
		})

		-- Electoral vote bar.
		if election then
			local evBar = Kit.dataColor(Kit.box({
				Name = "EVBar",
				LayoutOrder = nextOrder(),
				Size = UDim2.new(1, 0, 0, EV_BAR_H),
				BackgroundTransparency = 0,
				BackgroundColor3 = Kit.colors.surface,
				ClipsDescendants = true,
				Parent = column,
			}))
			Kit.corner(EV_BAR_H / 2).Parent = evBar
			local left = 0
			local players: { number } = { you }
			for player = 1, #view.players do
				if player ~= you then
					table.insert(players, player)
				end
			end
			for _, player in players do
				local share = election.ev[player] / TOTAL_EV
				Kit.box({
					Name = `EVBar_{player}`,
					Position = UDim2.fromScale(left, 0),
					Size = UDim2.fromScale(share, 1),
					BackgroundTransparency = 0,
					BackgroundColor3 = Kit.playerColor(view, player),
					Parent = evBar,
				})
				left += share
			end
			Kit.box({
				Name = "Marker270",
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(WIN_EV / TOTAL_EV, 0),
				Size = UDim2.new(0, TICK_W, 1, 0),
				BackgroundTransparency = 0,
				BackgroundColor3 = Kit.colors.text,
				ZIndex = 2,
				Parent = evBar,
			})
		end

		-- You and your opponent, side by side.
		local versus = Kit.box({
			Name = "Versus",
			LayoutOrder = nextOrder(),
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = column,
		})
		Kit.list("Horizontal", Kit.space.sm).Parent = versus
		local players: { number } = { you }
		for player = 1, #view.players do
			if player ~= you then
				table.insert(players, player)
			end
		end
		local voteLabels: { [number]: TextLabel } = {}
		for index, player in players do
			voteLabels[player] = playerCard(versus, current, player, index) :: any
		end

		-- Why: three short reasons, the winner's side.
		local winner = if result then result.winner else 0
		local names: { string } = {}
		for p = 1, #view.players do
			local entry = view.players[p]
			local full = Data.candidateName(ctx.config, if entry then entry.candidate else nil)
			names[p] = string.match(full, "^(%S+)") or full
		end
		local reasons: { string } = if election then Words.keyReasons(ctx.config, view, winner, names) else {}
		if #reasons > 0 then
			local why = Kit.stack(
				{ Name = "Why", LayoutOrder = nextOrder(), Parent = column },
				"Vertical",
				Kit.space.xs
			)
			Kit.heading(if winner == you then "Why you won" else `Why {names[winner]} won`, {
				Name = "WhyHead",
				LayoutOrder = 0,
				Parent = why,
			})
			for k, text in reasons do
				label(why, `{Kit.glyph.bullet} {text}`, { Name = `Reason_{k}`, LayoutOrder = k })
			end
			local tip = Words.nextTime(ctx.config, view, winner, names)
			if tip then
				label(why, tip, {
					Name = "NextTime",
					LayoutOrder = #reasons + 1,
					Font = Kit.font.medium,
					TextColor3 = Kit.colors.text,
				})
			end
		end

		fillSheet(current)
		if election then
			Kit.button(`Full breakdown {Kit.glyph.arrow}`, function()
				sheet:open()
			end, {
				variant = "ghost",
				Name = "FullBreakdown",
				LayoutOrder = nextOrder(),
				Size = UDim2.fromOffset(180, Kit.MIN_TOUCH),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = column,
			})
		end

		local _, opponent = Data.opponent(current)
		againBot = opponent ~= nil and opponent.kind == "Bot"
		bar:setPrimary(if againBot then "Play vs Bot again" else "Play again", true)

		-- The moment, once per match (a later payload of the same match redraws quietly).
		if result == nil or result.winner == 0 or celebrated == current.matchId then
			return
		end
		celebrated = current.matchId
		if election then
			for player, votes in voteLabels do
				local total = election.ev[player]
				Motion.countTo(votes, 0, total, function(n: number): string
					return plural(math.floor(n + 0.5), "vote")
				end, COUNT_SECONDS)
			end
		end
		if result.winner == you then
			if not Motion.reduced() then
				local scale = Motion.scale(banner)
				scale.Scale = BANNER_FROM
				Motion.tween(scale, { Scale = 1 }, Motion.t.hero, Motion.ease.back)
			end
			local colors: { Color3 } = {}
			for player = 1, #view.players do
				table.insert(colors, Kit.playerColor(view, player))
			end
			Motion.confetti(parent, colors, CONFETTI)
			Audio.play("victory")
		else
			banner.TextTransparency = 1
			Motion.tween(banner, { TextTransparency = 0 }, LOSS_FADE, Motion.ease.out)
			Audio.play("defeat")
		end
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
			local line = ratingLine
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
