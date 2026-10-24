--!strict
-- Results (docs/UI-STYLE.md §4.9): who won, big, and why in three short
-- reasons, then the details one tap away. The player leaves with Back to lobby
-- or goes straight into another match.
--
-- Layout: three tabs pinned at the top once the election is in (D-066; a
-- segmented row of chips Tab_Summary | Tab_Map | Tab_Graph, "Summary" | "Map" |
-- "Graph"), a scrolling column, and the pinned ActionBar ("Play vs Bot again" /
-- "Play again" primary, "Back to lobby" secondary). Summary is the first view:
--   BannerBox     a stamp, "You won" (green) / "You lost" (orange, dark text: no
--                 red anywhere on a loss), hero size, tilted, with the winner's
--                 glow behind it; its label is Banner (D-056)
--   LandslideBox  only after a landslide (D-062: the winner took more than 70%
--                 of the votes; Shared/UI/Landslide): an eyebrow "YOU WON BY A"
--                 (LandslideEyebrow; "REX WON BY A" for the loser), a big
--                 "LANDSLIDE" stamp in the winner's color tilted the other way
--                 (LandslideStamp, label LandslideLabel) and "You took 412 of
--                 538 votes, over 70%." (LandslideLine)
--   Reason        "280 votes to 258" (or the tiebreak, a forfeit)
--   RatingSlot    the rating change, once the server sends it (rated matches)
--   EVBar         Kit.raceBar, 14 px: you from the left, them from the right,
--                 the 270 tick (Marker270) with its caption (data colors)
--   Versus        two player cards: a 64 px monogram over the name, You /
--                 Opponent, "280 votes" in Fredoka, "20 states", debate topics
--                 won; the winner's card is edged in their color. Player colors
--                 stay on the monogram, the edge and the bar, never on big
--                 numbers next to the primary button (D-047, D-051).
--   WhyHead       "Why you won" / "Why Rex won" and three bullets Reason_<k>
--                 (Shared/UI/Words/Reveal.keyReasons); after a loss, one more
--                 line NextTime ("Try next time: …", Words.nextTime)
--   FullBreakdown ghost button: the BreakdownSheet with "What decided it"
--                 (Decided, Decided_<k>: Swing.decided), the closest states
--                 (Closest, Closest_<id>) and every debate (Debates, Debate_<k>).
-- Map (ResultsParts/MapTab): the final polls against the real result, a switch
-- between the two, MISS on the states the polls got wrong and one line naming
-- them. Graph (ResultsParts/GraphTab): both players' projected votes week by
-- week and the real result, with the 270 line and the debate and stance weeks.
-- Without an election (a forfeit) there are no tabs: Summary alone.
-- Four text sizes: hero, heading, body, caption.
--
-- The moment (docs/UI-STYLE.md §2.7, D-053), once per match: the banner stamp
-- slams in (Motion.stamp; at once under reduced motion), both vote totals count
-- up and the bar fills; a win drops confetti in both players' colors and white
-- and plays "victory"; a loss plays "defeat". Nothing waits on it. After a
-- landslide the LANDSLIDE stamp slams in LANDSLIDE_DELAY later; for the winner
-- with a light sweeping across it (Motion.shine), twice the confetti and a
-- second hit ("debateWin"); for the loser it lands quietly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Landslide = require(ReplicatedStorage.Shared.UI.Landslide)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local State = require(ReplicatedStorage.Shared.Sim.State)
local Swing = require(ReplicatedStorage.Shared.UI.Swing)
local Words = require(ReplicatedStorage.Shared.UI.Words.Reveal)

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local Audio = require(script.Parent.Parent.UI.Audio)
local BotLevel = require(script.Parent.Parent.UI.BotLevel)
local Data = require(script.Parent.Common.Data)
local GraphTab = require(script.Parent.ResultsParts.GraphTab)
local Kit = require(script.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Common.Layout)
local MapTab = require(script.Parent.ResultsParts.MapTab)
local Motion = require(script.Parent.Parent.UI.Motion)
local Sheet = require(script.Parent.Parent.UI.Sheet)
local Types = require(script.Parent.Types)

local Screen = {}

local MAX_WIDTH = 640 -- px
local CLOSEST_STATES = 5
local TOTAL_EV = 538
local WIN_EV = 270
local EV_BAR_H = 14 -- px, the race bar's thickness
local PORTRAIT = 64 -- px, a player's monogram on their card
local STAMP_SLACK = 36 -- px over the banner stamp's height in its row: room for its tilt
local BANNER_GLOW = 0.6 -- the glow behind the banner, in the winner's color (transparency)
local BANNER_GLOW_W = 1.1 -- the glow's width, a share of the column
local COUNT_SECONDS = 0.6 -- s, the vote totals counting up
local CONFETTI = 50 -- pieces on a win
local LANDSLIDE_CONFETTI = 100 -- pieces on a landslide win (D-062)
local LANDSLIDE_DELAY = 0.45 -- s after the banner's stamp, the LANDSLIDE stamp lands
local LANDSLIDE_TILT = 4 -- degrees: the other way from the banner's −6, so the two read as two moments
local LANDSLIDE_EYEBROW_H = Kit.size.caption + 6 -- px, "YOU WON BY A" over the stamp
local LANDSLIDE_LINE_H = Kit.size.caption + 6 -- px, the votes line under it
local LANDSLIDE_GLOW = 0.45 -- the glow behind the stamp, in the winner's color (transparency)
local LANDSLIDE_GLOW_W = 1.2 -- its width, a share of the column
local LANDSLIDE_BREATHE = { 0.45, 0.65, 1.6 } -- the winner's glow breathes between these transparencies, s per breath
local TAB_H = Kit.MIN_TOUCH -- px, the pinned tab row (D-066)
local TABS = { "Summary", "Map", "Graph" }

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
	local page = Layout.page(parent, { maxWidth = MAX_WIDTH, footer = Kit.BAR_H, header = TAB_H })

	local rendered: Session.StatePayload? = nil
	local celebrated: string? = nil -- the match whose moment has played
	local details: Frame? = nil
	local ratingLine: TextLabel? = nil
	local sheet = Sheet.new(parent, { title = "Full breakdown", name = "BreakdownSheet" })

	-- The tabs (D-066): Summary first; Map and Graph once the election is in.
	local tabBar = page.header :: Frame
	tabBar.Name = "Tabs"
	tabBar.Visible = false
	Kit.list("Horizontal", Kit.space.xs).Parent = tabBar
	local mapTab = MapTab.new(page.content, 2)
	local graphTab = GraphTab.new(page.content, 3)
	local tab = "Summary"
	local tabChips: { [string]: TextButton } = {}
	local tabbed = false -- the tabs are shown (the match has an election)
	local tabsFor: string? = nil -- the match the tabs were last reset for
	local function showTab(id: string)
		tab = id
		for name, chip in tabChips do
			Kit.setSelected(chip, name == id)
		end
		if details then
			details.Visible = id == "Summary"
		end
		mapTab:show(id == "Map")
		graphTab:show(id == "Graph")
		page.scroll.CanvasPosition = Vector2.new(0, 0)
	end
	for k, id in TABS do
		tabChips[id] = Kit.chip(id, function()
			if id ~= tab then
				showTab(id)
			end
		end, {
			Name = `Tab_{id}`,
			LayoutOrder = k,
			Size = UDim2.new(1 / #TABS, -Kit.space.xs * (#TABS - 1) / #TABS, 1, 0),
			Parent = tabBar,
		})
	end

	local againBot = false
	local bar = ActionBar.new(page.footer :: Frame, {
		primary = "Play again",
		onPrimary = function()
			ctx.store.dismissResult()
			if againBot then
				ctx.net.send("Practice", { difficulty = BotLevel.get() }) -- the level picked in the Lobby (D-059)
			else
				ctx.net.send("Queue")
			end
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
		local color = Kit.playerColor(view, player)
		local center = Enum.TextXAlignment.Center
		local card = Kit.card({
			Name = if mine then "Player_You" else "Player_Opponent",
			LayoutOrder = order,
			Size = UDim2.new(0.5, -Kit.space.sm / 2, 0, 0),
			Parent = into,
		})
		local list = card:FindFirstChildOfClass("UIListLayout")
		if list then
			list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		end
		-- The winner's card is edged in their color.
		local result = current.result
		if result and result.winner == player then
			Kit.bevel(card, color, 2, 1)
		end
		local name = Data.candidateName(ctx.config, if entry then entry.candidate else nil)
		local portrait = Kit.monogram(name, color, PORTRAIT)
		portrait.LayoutOrder = 1
		portrait.Parent = card
		Kit.text(name, {
			Name = "Candidate",
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, Kit.size.heading + 8),
			Font = Kit.font.bold,
			TextSize = Kit.size.heading,
			TextScaled = true,
			TextXAlignment = center,
			Parent = card,
		})
		label(card, if mine then "You" else "Opponent", {
			Name = "Tag",
			LayoutOrder = 3,
			TextSize = Kit.size.caption,
			TextColor3 = Kit.colors.muted,
			TextXAlignment = center,
		})
		local votes: TextLabel? = nil
		if election then
			votes = label(card, plural(election.ev[player], "vote"), {
				Name = "EV",
				LayoutOrder = 4,
				Font = Kit.font.display,
				TextSize = Kit.size.heading,
				TextXAlignment = center,
			})
			-- Its own line, so a phone never breaks "20 states" in two.
			label(card, plural(election.statesWon[player], "state"), {
				Name = "States",
				LayoutOrder = 5,
				TextSize = Kit.size.caption,
				TextColor3 = Kit.colors.muted,
				TextXAlignment = center,
			})
		end
		if #view.debates > 0 then
			label(card, `{plural(topicsWon(view, player), "debate topic")} won`, {
				Name = "Topics",
				LayoutOrder = 6,
				TextSize = Kit.size.caption,
				TextColor3 = Kit.colors.muted,
				TextXAlignment = center,
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
					TextColor3 = if r.winner == 0 then Kit.colors.muted else Kit.playerText(view, r.winner),
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
			LayoutOrder = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = page.content,
		})
		Kit.list("Vertical", Kit.space.md).Parent = column
		details = column

		-- Banner: a stamp, green for a win, orange (dark text) for a loss.
		local bannerText, bannerColor = "No result", Kit.colors.raisedHover
		if result and result.winner == you then
			bannerText, bannerColor = "You won", Kit.colors.good
		elseif result and result.winner ~= 0 then
			bannerText, bannerColor = "You lost", Kit.colors.loss
		end
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		local bannerBox = Kit.box({
			Name = "BannerBox",
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, Kit.size.hero + 20 + STAMP_SLACK),
			Parent = column,
		})
		if result and result.winner ~= 0 then
			Kit.glow(
				bannerBox,
				Kit.playerColor(view, result.winner),
				{ scale = BANNER_GLOW_W, stretch = true, transparency = BANNER_GLOW }
			)
		end
		local stamp = Kit.stamp(bannerText, bannerColor, {
			size = Kit.size.hero,
			Name = "BannerStamp",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			ZIndex = 2,
			Parent = bannerBox,
		})
		local banner = (stamp:FindFirstChild("Plate") :: Frame):FindFirstChild("Label") :: TextLabel
		banner.Name = "Banner"
		banner.TextTransparency = 0 -- the resting value Motion.stamp's fade ends on

		-- First names, for the landslide's eyebrow and the reasons below.
		local names: { string } = {}
		for p = 1, #view.players do
			local entry = view.players[p]
			local full = Data.candidateName(ctx.config, if entry then entry.candidate else nil)
			names[p] = string.match(full, "^(%S+)") or full
		end

		-- A landslide (D-062): the big stamp in the winner's color, for both players.
		local slide = Landslide.moment(ctx.config, view, result, names)
		local slideStamp: Frame? = nil
		local slideGlow: ImageLabel? = nil
		if slide then
			local stampRow = Kit.size.hero + 20 + STAMP_SLACK
			local box = Kit.box({
				Name = "LandslideBox",
				LayoutOrder = nextOrder(),
				Size = UDim2.new(1, 0, 0, LANDSLIDE_EYEBROW_H + stampRow + LANDSLIDE_LINE_H),
				Parent = column,
			})
			slideGlow = Kit.glow(
				box,
				Kit.playerColor(view, slide.winner),
				{ scale = LANDSLIDE_GLOW_W, stretch = true, transparency = LANDSLIDE_GLOW }
			)
			Kit.eyebrow(slide.eyebrow, {
				Name = "LandslideEyebrow",
				Size = UDim2.new(1, 0, 0, LANDSLIDE_EYEBROW_H),
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = box,
			})
			local made = Kit.stamp(slide.stamp, Kit.playerColor(view, slide.winner), {
				size = Kit.size.hero,
				Name = "LandslideStamp",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, LANDSLIDE_EYEBROW_H + stampRow / 2),
				Rotation = LANDSLIDE_TILT,
				ZIndex = 3,
				Parent = box,
			})
			local plate = made:FindFirstChild("Plate") :: Frame
			local stampLabel = plate:FindFirstChild("Label") :: TextLabel
			stampLabel.Name = "LandslideLabel"
			stampLabel.TextTransparency = 0
			label(box, slide.line, {
				Name = "LandslideLine",
				Position = UDim2.fromOffset(0, LANDSLIDE_EYEBROW_H + stampRow),
				Size = UDim2.new(1, 0, 0, LANDSLIDE_LINE_H),
				AutomaticSize = Enum.AutomaticSize.None,
				TextSize = Kit.size.caption,
				TextColor3 = Kit.colors.text,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			slideStamp = made
		end
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

		-- The race to 270: you from the left, your opponent from the right (it
		-- fills as the screen comes in).
		local them = if you == 1 then 2 else 1
		if election then
			local race = Kit.raceBar(column, {
				h = EV_BAR_H,
				mark = WIN_EV / TOTAL_EV,
				caption = tostring(WIN_EV),
				name = "EVBar",
				order = nextOrder(),
			})
			race.tick.Name = "Marker270"
			race:setColors(Kit.playerColor(view, you), Kit.playerColor(view, them))
			race:set(election.ev[you] / TOTAL_EV, election.ev[them] / TOTAL_EV)
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

		-- The tabs: a new match opens on Summary; a later payload of the same
		-- match keeps the tab the player is on.
		tabbed = election ~= nil
		tabBar.Visible = tabbed
		if tabbed then
			mapTab:set(current, names)
			graphTab:set(current, names)
		end
		if tabsFor ~= current.matchId or not tabbed then
			tabsFor = current.matchId
			showTab("Summary")
		else
			showTab(tab)
		end

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
		Motion.stamp(stamp)
		local landslide = slideStamp
		if landslide then
			Motion.stamp(landslide, LANDSLIDE_DELAY)
		end
		if result.winner == you then
			local colors: { Color3 } = {}
			for player = 1, #view.players do
				table.insert(colors, Kit.playerColor(view, player))
			end
			table.insert(colors, Kit.colors.text)
			Motion.confetti(parent, colors, if landslide then LANDSLIDE_CONFETTI else CONFETTI)
			Audio.play("victory")
			if landslide then
				-- The reward: a second hit as the stamp lands, then a light sweeps it.
				local plate = landslide:FindFirstChild("Plate") :: Frame
				plate.Active = true -- Motion.shine sweeps only an active object
				Motion.shine(plate)
				local glow = slideGlow
				if glow then
					local b = LANDSLIDE_BREATHE
					Motion.breathe(glow, "ImageTransparency", b[1], b[2], b[3])
				end
				task.delay(LANDSLIDE_DELAY, function()
					if landslide.Parent ~= nil then
						Audio.play("debateWin")
					end
				end)
			end
		else
			Audio.play("defeat")
		end
	end

	local function relayout()
		page.setPortrait(ctx.portrait())
		if not tabbed then
			-- No tabs: the column starts at the top.
			local footerH = Kit.BAR_H + Layout.GAP
			page.scroll.Position = UDim2.fromOffset(0, 0)
			page.scroll.Size = UDim2.new(1, 0, 1, -footerH)
		end
		local width = page.content.AbsoluteSize.X - 4 -- the column's 2 px side padding
		local height = page.scroll.AbsoluteSize.Y
		if width > 0 and height > 0 then
			mapTab:layout(width, height)
			graphTab:layout(width, height)
		end
	end

	relayout()

	return {
		update = function(state: Types.State)
			relayout()
			local current = state.payload :: Session.StatePayload?
			if current and current ~= rendered then
				rendered = current
				render(current)
				relayout()
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
