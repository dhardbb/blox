--!strict
-- Results (docs/UI-STYLE.md §4.9): who won, big, and why in three short
-- reasons, then the details one tap away. The player leaves with Back to lobby
-- or plays the same opponent again (Rematch, D-083).
--
-- Layout: three tabs pinned at the top once the election is in (D-073; a
-- segmented row of chips Tab_Summary | Tab_Map | Tab_Graph, "Summary" | "Map" |
-- "Graph"), a scrolling column, and the pinned ActionBar ("Play vs Bot again" /
-- "Rematch" primary, "Back to lobby" secondary). Summary is the first view:
--   BannerBox     a stamp, "You won" (green) / "You lost" (orange, dark text: no
--                 red anywhere on a loss), hero size, tilted, with the winner's
--                 glow behind it; its label is Banner (D-056)
--   LandslideBox  only after a landslide (D-062: the winner took more than 70%
--                 of the votes; Shared/UI/Landslide): an eyebrow "YOU WON BY A"
--                 (LandslideEyebrow; "BUSTER WON BY A" for the loser), a big
--                 "LANDSLIDE" stamp in the winner's color tilted the other way
--                 (LandslideStamp, label LandslideLabel) and "You took 412 of
--                 538 votes, over 70%." (LandslideLine)
--   Reason        "280 votes to 258" (or the tiebreak, a forfeit)
--   RatingSlot    the rating change, once the server sends it (rated matches)
--   DailySummary  a Daily Race run only (D-082): an eyebrow with the day,
--                 DailyLine ("You won by 62 votes.", or "Practice run: …") and
--                 DailyMore (rank today and streak, or why it did not count),
--                 filled when the server's Daily message arrives
--   EVBar         Kit.raceBar, 14 px: you from the left, them from the right,
--                 the 270 tick (Marker270) with its caption (data colors)
--   Versus        two player cards: a 64 px portrait (D-068) over the name, You /
--                 Opponent, "280 votes" in Fredoka, "20 states", debate topics
--                 won; the winner's card is edged in their color. Player colors
--                 stay on the portrait ring, the edge and the bar, never on big
--                 numbers next to the primary button (D-047, D-051).
--   WhyHead       "Why you won" / "Why Buster won" and three bullets Reason_<k>
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
-- After the tutorial (D-080) a card TutorialReady ("Practice done!", ReadyTitle,
-- ReadyText) stands in the right column, and the primary button reads "Play a real
-- match" (not Rematch): it queues for a match against a person. The banner
-- stamp is "You're ready!" in green, win or lose (D-090: no orange "You lost"
-- over a practice).
--
-- D-090 (end-screen social; the layout is E's): when the opponent asks for a
-- rematch, RematchBanner fills E's RematchSlot at the top of the right column (their portrait,
-- RematchFace, and "Buster wants a rematch!" with the seconds left,
-- RematchText) and pops in; the bar's status line steps aside. A counted Daily
-- Race run shows its rank as a big number with the flame (DailyRankRow:
-- DailyRankFlame, DailyRank) and drops gold confetti once.
--
-- The end screen's layout (D-098). A compact top section, then two columns on
-- a wide screen (an iPad, a desktop) and one on a phone:
--   Top        BannerBox: the "You won" / "You lost" stamp, hero size. After a
--              landslide LANDSLIDE is the hero instead: "You won" shrinks to a
--              pill (still Banner, in BannerBox) and the LANDSLIDE stamp under it
--              wears a gold edge and, for the winner, a gold light sweeping it.
--              The plain "280 votes to 258" line is gone (the scoreboard says it;
--              Reason stays for a tiebreak, a forfeit or an abandoned match).
--   Left       Scoreboard: the race bar, then both candidates side by side, each a
--              compact card (portrait left; name, "280 votes", "You · 20 states",
--              debate topics won), then RatingSlot.
--   Right      RematchSlot (empty: the rematch banner's place), TutorialReady,
--              DailySummary, Why (WhyHead, Reason_k, NextTime), FullBreakdown.
-- Two columns once the column is at least TWO_COL_W wide (Columns, SummaryLeft, SummaryRight);
-- the page is MAX_WIDTH_WIDE there, so the vote counts sit well above the bar.
--
-- Rematch (D-083; Net/Rematch): against the bot a new match at the same level
-- at once; against a person both tap within Config.REMATCH_WINDOW_SECONDS
-- (the bar's status line counts down: "Waiting for Buster… · 14 s", "Buster wants a
-- rematch! · 9 s"), then a new match with a new seed and the same seats. The
-- button says when it can't: "Opponent left", "Rematch expired". In a match
-- server Back to lobby also asks to go back to a lobby server (Return).
-- Four text sizes: hero, heading, body, caption.
--
-- The moment (docs/UI-STYLE.md §2.7, D-053), once per match: the banner stamp
-- slams in (Motion.stamp; at once under reduced motion), both vote totals count
-- up and the bar fills; a win drops confetti in both players' colors and white
-- and plays "victory"; a loss plays "defeat". Nothing waits on it. After a
-- landslide the LANDSLIDE stamp slams in LANDSLIDE_DELAY later; for the winner
-- with a light sweeping across it (Motion.shine: a gradient on the stamp's
-- plate, so it never spills past the tilted stamp), twice the confetti and a
-- second hit ("debateWin"); for the loser it lands quietly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)
local Landslide = require(ReplicatedStorage.Shared.UI.Landslide)
local LobbyWords = require(ReplicatedStorage.Shared.UI.Words.Lobby)
local MatchWords = require(ReplicatedStorage.Shared.UI.Words.Matchmaking)
local Session = require(ReplicatedStorage.Shared.Net.Session)
local StateData = require(ReplicatedStorage.Shared.Sim.StateData)
local State = require(ReplicatedStorage.Shared.Sim.State)
local Swing = require(ReplicatedStorage.Shared.UI.Swing)
local DailyNet = require(ReplicatedStorage.Shared.Net.Daily)
local DailyWords = require(ReplicatedStorage.Shared.UI.Words.Daily)
local SetupWords = require(ReplicatedStorage.Shared.UI.Words.Setup)
local Words = require(ReplicatedStorage.Shared.UI.Words.Reveal)

local ActionBar = require(script.Parent.Parent.UI.ActionBar)
local Featured = require(script.Parent.Parent.UI.Featured)
local Audio = require(script.Parent.Parent.UI.Audio)
local Data = require(script.Parent.Common.Data)
local GraphTab = require(script.Parent.ResultsParts.GraphTab)
local Kit = require(script.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Common.Layout)
local MapTab = require(script.Parent.ResultsParts.MapTab)
local Motion = require(script.Parent.Parent.UI.Motion)
local Sheet = require(script.Parent.Parent.UI.Sheet)
local Types = require(script.Parent.Types)

local Screen = {}

local MAX_WIDTH = 640 -- px, the column on a phone or a narrow window
local MAX_WIDTH_WIDE = 960 -- px, the page on a wide screen: two columns (D-098)
local TWO_COL_W = 760 -- px of column from which the summary stands in two columns (D-098)
local CLOSEST_STATES = 5
local TOTAL_EV = 538
local WIN_EV = 270
local EV_BAR_H = 14 -- px, the race bar's thickness
local PORTRAIT = 56 -- px, a player's portrait on their card (left of the words, D-098)
local CARD_PAD = 14 -- px, Kit.card's padding
local STAMP_SLACK = 24 -- px over the banner stamp's height in its row: room for its tilt
local PILL_ROW = Kit.PILL_H + 4 -- px, the "You won" pill's row over a LANDSLIDE (D-098)
local LANDSLIDE_EDGE = 3 -- px, the gold edge on the LANDSLIDE stamp (D-098)
local BANNER_GLOW = 0.6 -- the glow behind the banner, in the winner's color (transparency)
local BANNER_GLOW_W = 1.1 -- the glow's width, a share of the column
local COUNT_SECONDS = 0.6 -- s, the vote totals counting up
local CONFETTI = 50 -- pieces on a win
local LANDSLIDE_CONFETTI = 100 -- pieces on a landslide win (D-062)
local LANDSLIDE_DELAY = 0.45 -- s after the banner's stamp, the LANDSLIDE stamp lands
local LANDSLIDE_TILT = 4 -- degrees: the other way from the banner's −6, so the two read as two moments
local LANDSLIDE_LINE_H = Kit.size.caption + 6 -- px, the votes line under it
local LANDSLIDE_GLOW = 0.45 -- the glow behind the stamp, in the winner's color (transparency)
local LANDSLIDE_GLOW_W = 1.2 -- its width, a share of the column
local LANDSLIDE_BREATHE = { 0.45, 0.65, 1.6 } -- the winner's glow breathes between these transparencies, s per breath
local TAB_H = Kit.MIN_TOUCH -- px, the pinned tab row (D-073)
-- Gold: the leaderboard's first medal (the Amber player color), the LANDSLIDE's
-- edge and its light (D-098).
local GOLD = Kit.color(Colors.player.Amber)
local TABS = { "Summary", "Map", "Graph" }
local TUTORIAL_TILT = -3 -- degrees: the tutorial's "You're ready!" stamp, half the usual tilt (D-090)
local REMATCH_H = 56 -- px, the rematch banner above the action bar (D-090)
local REMATCH_FACE = 40 -- px, the asker's portrait on it
local REMATCH_FLOAT_GAP = Kit.space.md + Kit.space.sm -- px between a floating banner and the bar (a landscape phone)
local REMATCH_TIME_W = 36 -- px, the seconds left at its right
local RANK_FLAME = Kit.size.hero -- px, the flame beside a Daily rank (D-090), as tall as the number
local RANK_CONFETTI = 40 -- pieces when a counted Daily rank arrives

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
	local page =
		Layout.page(parent, { maxWidth = MAX_WIDTH, footer = Kit.BAR_H, header = TAB_H, side = true })

	local rendered: Session.StatePayload? = nil
	local celebrated: string? = nil -- the match whose moment has played
	local details: Frame? = nil
	local columnsList: UIListLayout? = nil -- the summary's two columns (D-098), set by render
	local sides: { Frame } = {} -- Left and Right
	local ratingLine: TextLabel? = nil
	-- The landslide's looping effects (Motion.shine, Motion.breathe): stopped
	-- when the column is redrawn and when the screen goes.
	local stops: { () -> () } = {}
	local function stopEffects()
		for _, stop in stops do
			stop()
		end
		table.clear(stops)
	end
	local sheet = Sheet.new(parent, { title = "Full breakdown", name = "BreakdownSheet" })

	-- The tabs (D-073): Summary first; Map and Graph once the election is in.
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
	local afterTutorial = false -- the tutorial just ended: its primary is a real match (D-080)
	local againDaily = false -- a Daily Race run: the primary plays today's race again (practice, D-082)
	local dailyLine: TextLabel? = nil
	local dailyMore: TextLabel? = nil
	local dailyRank: TextLabel? = nil -- the big "#7" (D-090)
	local rankCheered: string? = nil -- the match whose rank already dropped confetti
	local rivalName = "your opponent" -- the opponent's first name, for the rematch line
	local bar = ActionBar.new(page.footer :: Frame, {
		primary = MatchWords.REMATCH,
		onPrimary = function()
			if afterTutorial then
				-- The tutorial's end (D-080): into the queue for a real match.
				ctx.store.dismissResult()
				ctx.net.send("Queue")
				return
			end
			-- A Daily Race's rematch is today's race again, a practice run once
			-- today's run counted: the server decides (D-082).
			local rematch = ctx.net.rematch
			if rematch then
				rematch()
			else
				local payload = ctx.store.get().payload
				if payload then
					ctx.net.send("Rematch", { matchId = payload.matchId })
				end
			end
		end,
		primaryName = "Rematch",
		secondary = "Back to lobby",
		onSecondary = function()
			ctx.store.dismissResult()
			-- A match server sends its players back to a lobby server (D-083).
			local lobby = ctx.store.get().lobby
			if lobby and lobby.matchServer then
				ctx.net.send("Return")
			end
		end,
		secondaryName = "BackToLobby",
	})

	-- The rematch banner (D-090): in the summary's RematchSlot (D-098), hidden
	-- until asked; render() moves it into each new slot.
	local rematchBanner = Kit.new("Frame", {
		Name = "RematchBanner",
		Size = UDim2.new(1, 0, 0, REMATCH_H),
		BackgroundColor3 = Kit.colors.raised,
		BorderSizePixel = 0,
		Visible = false,
	}) :: Frame
	Kit.corner(Kit.radius.panel).Parent = rematchBanner
	Kit.new("UIStroke", {
		Name = "RematchEdge",
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Kit.colors.good,
		Thickness = 2,
		Parent = rematchBanner,
	})
	local rematchFaceSlot = Kit.box({
		Name = "RematchFaceSlot",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, Kit.space.sm, 0.5, 0),
		Size = UDim2.fromOffset(REMATCH_FACE, REMATCH_FACE),
		Parent = rematchBanner,
	})
	local rematchTime = Kit.text("", {
		Name = "RematchTime",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Kit.space.sm, 0, 0),
		Size = UDim2.new(0, REMATCH_TIME_W, 1, 0),
		TextSize = Kit.size.caption,
		TextColor3 = Kit.colors.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
		Parent = rematchBanner,
	})
	local rematchText = Kit.text("", {
		Name = "RematchText",
		Position = UDim2.fromOffset(REMATCH_FACE + 2 * Kit.space.sm, 0),
		Size = UDim2.new(1, -(REMATCH_FACE + 4 * Kit.space.sm + REMATCH_TIME_W), 1, 0),
		Font = Kit.font.bold,
		TextColor3 = Kit.colors.text,
		TextScaled = true,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = rematchBanner,
	})
	Kit.new(
		"UITextSizeConstraint",
		{ MinTextSize = Kit.MIN_TEXT, MaxTextSize = Kit.size.body, Parent = rematchText }
	)
	local rematchFaceFor: string? = nil -- the candidate whose portrait is on the banner

	-- The banner for an "Asked" rematch, or hidden.
	local rematchHome: Instance? = nil -- the summary's RematchSlot (set by render)
	-- Where the banner stands: in RematchSlot, or on a landscape phone (the
	-- summary scrolls under one column there) just above the action bar in the
	-- side column, so the ask is seen without a scroll.
	local function placeBanner()
		local floating = page.sideways()
		local want: Instance? = if floating then bar.root else rematchHome
		if rematchBanner.Parent ~= want then
			rematchBanner.Parent = want
		end
		rematchBanner.AnchorPoint = if floating then Vector2.new(0, 1) else Vector2.new(0, 0)
		rematchBanner.Position = if floating then UDim2.fromOffset(0, -REMATCH_FLOAT_GAP) else UDim2.new()
		rematchBanner:SetAttribute("Overhang", if floating then true else nil)
	end

	local function paintBanner(current: Session.StatePayload, asked: boolean, seconds: number?)
		placeBanner()
		local was = rematchBanner.Visible
		rematchBanner.Visible = asked
		if not asked then
			return
		end
		local them = Data.opponent(current)
		local player = current.view.players[them]
		local id = if player then player.candidate else nil
		if id and rematchFaceFor ~= id then
			rematchFaceFor = id
			for _, child in rematchFaceSlot:GetChildren() do
				child:Destroy()
			end
			local face = Kit.portrait(id, Data.playerName(ctx.config, current.view, them), REMATCH_FACE, {
				ring = Kit.playerColor(current.view, them),
			})
			face.Name = "RematchFace"
			face.Parent = rematchFaceSlot
		end
		rematchText.Text = MatchWords.rematchAsked(rivalName)
		rematchTime.Text = if seconds then `{math.max(0, math.ceil(seconds))} s` else ""
		if not was then
			Motion.pop(rematchBanner, Motion.POP_FROM)
			Audio.play("select")
		end
	end

	-- The Rematch button and the status line follow the server's word (D-083).
	local function showRematch(state: Types.State)
		local current = state.payload
		if current == nil then
			return
		end
		local status = state.rematch
		local mine = status ~= nil and status.matchId == current.matchId
		local kind = if mine then status.state else "Open"
		local seconds = if mine and type(status.untilAt) == "number" then status.untilAt - ctx.now() else nil
		local asked = not afterTutorial
			and not againBot
			and kind == "Asked"
			and (seconds == nil or seconds > 0)
		paintBanner(current, asked, seconds)
		if afterTutorial then
			-- The tutorial's end (D-080): "Play a real match", never a rematch.
			bar:setPrimary(LobbyWords.READY_PLAY, true)
			bar:setStatus("", "muted")
			return
		end
		if againBot then
			bar:setPrimary(MatchWords.REMATCH, kind ~= "Gone" and kind ~= "Started")
			bar:setStatus(if againDaily then DailyWords.REMATCH_PRACTICE else "", "muted")
			return
		end
		if kind == "Gone" then
			bar:setPrimary(MatchWords.REMATCH_GONE, false)
		elseif kind == "Expired" or (seconds ~= nil and seconds <= 0) then
			bar:setPrimary(MatchWords.REMATCH_EXPIRED, false)
		elseif kind == "Waiting" then
			bar:setPrimary(MatchWords.REMATCH_ASKED, false)
		elseif kind == "Started" then
			bar:setPrimary(MatchWords.REMATCH, false)
		else
			bar:setPrimary(MatchWords.REMATCH, true)
		end
		local line = if seconds == nil or seconds > 0
			then MatchWords.rematchStatus(kind, seconds, rivalName)
			else nil
		-- An asked rematch says so on the banner (D-090); the status line steps aside.
		bar:setStatus(if asked then "" else line or "", if kind == "Asked" then "ok" else "muted")
	end

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

	-- A compact player card (D-098): the portrait on the left, the words beside
	-- it: the name, "280 votes" in Fredoka, "You · 20 states", debate topics won.
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
		local card = Kit.card({
			Name = if mine then "Player_You" else "Player_Opponent",
			LayoutOrder = order,
			Size = UDim2.new(0.5, -Kit.space.sm / 2, 0, 0),
			Parent = into,
		})
		local list = card:FindFirstChildOfClass("UIListLayout")
		if list then
			list.FillDirection = Enum.FillDirection.Horizontal
			list.VerticalAlignment = Enum.VerticalAlignment.Center
		end
		-- The winner's card is edged in their color.
		local result = current.result
		if result and result.winner == player then
			Kit.bevel(card, color, 2, 1)
		end
		local name = Data.playerName(ctx.config, view, player)
		local portrait =
			Kit.portrait(if entry then entry.candidate else nil, name, PORTRAIT, { ring = color })
		portrait.LayoutOrder = 1
		portrait.Parent = card
		-- The words, one line each and never wrapping, so the card's height is
		-- known: the name, the votes, "You · 20 states", the debate topics won.
		local lines: { { text: string, name: string, size: number, font: any, color: Color3 } } = {}
		table.insert(lines, {
			text = name,
			name = "Candidate",
			size = Kit.size.body,
			font = Kit.font.bold,
			color = Kit.colors.text,
		})
		if election then
			table.insert(lines, {
				text = plural(election.ev[player], "vote"),
				name = "EV",
				size = Kit.size.heading,
				font = Kit.font.display,
				color = Kit.colors.text,
			})
		end
		local tag = if mine then "You" else "Opponent"
		table.insert(lines, {
			text = if election then `{tag} · {plural(election.statesWon[player], "state")}` else tag,
			name = "Tag",
			size = Kit.size.caption,
			font = Kit.font.body,
			color = Kit.colors.muted,
		})
		if #view.debates > 0 then
			table.insert(lines, {
				text = `{plural(topicsWon(view, player), "debate topic")} won`,
				name = "Topics",
				size = Kit.size.caption,
				font = Kit.font.body,
				color = Kit.colors.muted,
			})
		end
		local report = ctx.report
		local reportable = not mine and report ~= nil and entry ~= nil and entry.customName ~= nil
		local infoH = if reportable then Kit.MIN_TOUCH else 0
		for _, line in lines do
			infoH += line.size + 6
		end
		-- The card's height from its words (a card is padded 14 px all round).
		card.AutomaticSize = Enum.AutomaticSize.None
		card.Size = UDim2.new(0.5, -Kit.space.sm / 2, 0, math.max(PORTRAIT, infoH) + 2 * CARD_PAD)
		local info = Kit.box({
			Name = "Info",
			LayoutOrder = 2,
			Size = UDim2.new(1, -(PORTRAIT + Kit.space.sm), 0, infoH),
			Parent = card,
		})
		Kit.list("Vertical", 0).Parent = info
		local votes: TextLabel? = nil
		for k, line in lines do
			local made = Kit.text(line.text, {
				Name = line.name,
				LayoutOrder = k,
				Size = UDim2.new(1, 0, 0, line.size + 6),
				Font = line.font,
				TextSize = line.size,
				TextColor3 = line.color,
				TextWrapped = false,
				TextScaled = true, -- a long name or a narrow card shrinks a line, never wraps it
				Parent = info,
			})
			if line.name == "EV" then
				votes = made
			end
		end
		-- The opponent's custom name (D-069): a quiet way to report it.
		if reportable and report then
			Kit.button(SetupWords.REPORT, function()
				report(player)
			end, {
				variant = "ghost",
				Name = "ReportName",
				LayoutOrder = #lines + 1,
				Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
				Parent = info,
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
		stopEffects()
		if details then
			rematchHome = nil
			if rematchBanner.Parent ~= bar.root then
				rematchBanner.Parent = nil -- kept: the next slot takes it
			end
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
		if current.tutorial then
			-- The tutorial's end (D-090): win or lose, the headline is that you're ready.
			bannerText, bannerColor = LobbyWords.READY_TITLE, Kit.colors.good
		end
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end

		-- First names, for the landslide's words and the reasons below.
		local names: { string } = {}
		for p = 1, #view.players do
			local entry = view.players[p]
			local full = Data.playerName(ctx.config, view, p)
			-- A custom name stays whole (D-069); a candidate's goes by its first name.
			names[p] = if entry and entry.customName then full else string.match(full, "^(%S+)") or full
		end
		-- A landslide (D-062): LANDSLIDE is the hero; "You won" shrinks to a pill (D-098).
		local slide = Landslide.moment(ctx.config, view, result, names)

		local stampRow = Kit.size.hero + 20 + STAMP_SLACK
		local bannerBox = Kit.box({
			Name = "BannerBox",
			LayoutOrder = nextOrder(),
			Size = UDim2.new(1, 0, 0, if slide then PILL_ROW else stampRow),
			Parent = column,
		})
		local stamp: GuiObject
		if slide then
			local pill = Kit.pill(bannerText, "text", {
				Name = "Banner",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				filled = true,
				fill = bannerColor,
				Parent = bannerBox,
			})
			stamp = pill
		else
			if result and result.winner ~= 0 then
				Kit.glow(
					bannerBox,
					Kit.playerColor(view, result.winner),
					{ scale = BANNER_GLOW_W, stretch = true, transparency = BANNER_GLOW }
				)
			end
			local made = Kit.stamp(bannerText, bannerColor, {
				size = Kit.size.hero,
				-- "You're ready!" is long: a gentler tilt and a fit keep it on screen (D-090).
				fit = if current.tutorial then Kit.space.xl else nil,
				Rotation = if current.tutorial then TUTORIAL_TILT else nil,
				Name = "BannerStamp",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				ZIndex = 2,
				Parent = bannerBox,
			})
			local banner = (made:FindFirstChild("Plate") :: Frame):FindFirstChild("Label") :: TextLabel
			banner.Name = "Banner"
			banner.TextTransparency = 0 -- the resting value Motion.stamp's fade ends on
			stamp = made
		end

		local slideStamp: Frame? = nil
		local slideGlow: ImageLabel? = nil
		if slide then
			local box = Kit.box({
				Name = "LandslideBox",
				LayoutOrder = nextOrder(),
				Size = UDim2.new(1, 0, 0, stampRow + LANDSLIDE_LINE_H),
				Parent = column,
			})
			slideGlow = Kit.glow(
				box,
				Kit.playerColor(view, slide.winner),
				{ scale = LANDSLIDE_GLOW_W, stretch = true, transparency = LANDSLIDE_GLOW }
			)
			local made = Kit.stamp(slide.stamp, Kit.playerColor(view, slide.winner), {
				size = Kit.size.hero,
				Name = "LandslideStamp",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, stampRow / 2),
				Rotation = LANDSLIDE_TILT,
				ZIndex = 3,
				Parent = box,
			})
			local plate = made:FindFirstChild("Plate") :: Frame
			local stampLabel = plate:FindFirstChild("Label") :: TextLabel
			stampLabel.Name = "LandslideLabel"
			stampLabel.TextTransparency = 0
			-- The winner's gold edge (D-098): the leaderboard's first medal, on the
			-- hero. The loser's stays plain (their moment is quiet).
			local edge = plate:FindFirstChild("Edge") :: UIStroke?
			if edge and slide.mine then
				edge.Color = GOLD
				edge.Thickness = LANDSLIDE_EDGE
			end
			label(box, slide.line, {
				Name = "LandslideLine",
				Position = UDim2.fromOffset(0, stampRow),
				Size = UDim2.new(1, 0, 0, LANDSLIDE_LINE_H),
				AutomaticSize = Enum.AutomaticSize.None,
				TextSize = Kit.size.caption,
				TextColor3 = Kit.colors.text,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			slideStamp = made
		end
		-- The plain "280 votes to 258" repeats the scoreboard (D-098): only a
		-- tiebreak, a forfeit or an abandoned match says something here.
		local reason = reasonText(current, election)
		label(column, reason, {
			Name = "Reason",
			LayoutOrder = nextOrder(),
			Font = Kit.font.medium,
			TextXAlignment = Enum.TextXAlignment.Center,
			Visible = not (
					election ~= nil
					and DECIDED_BY[election.decidedBy] == nil
					and result ~= nil
					and result.reason == "Election"
				),
		})

		-- Two columns on a wide screen, one on a phone (relayout sets which).
		local columns = Kit.box({
			Name = "Columns",
			LayoutOrder = nextOrder(),
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = column,
		})
		local list = Kit.list("Vertical", Kit.space.md)
		list.Parent = columns
		columnsList = list
		local function side(sideName: string, k: number): Frame
			local frame = Kit.box({
				Name = sideName,
				LayoutOrder = k,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = columns,
			})
			Kit.list("Vertical", Kit.space.md).Parent = frame
			return frame
		end
		local left = side("SummaryLeft", 1)
		local right = side("SummaryRight", 2)
		sides = { left, right }
		local leftOrder, rightOrder = 0, 0
		local function leftNext(): number
			leftOrder += 1
			return leftOrder
		end
		local function rightNext(): number
			rightOrder += 1
			return rightOrder
		end

		-- The scoreboard: the race to 270 (you from the left, your opponent from
		-- the right; it fills as the screen comes in), then both candidates.
		local scoreboard = Kit.stack(
			{ Name = "Scoreboard", LayoutOrder = leftNext(), Parent = left },
			"Vertical",
			Kit.space.sm
		)
		local them = if you == 1 then 2 else 1
		if election then
			local race = Kit.raceBar(scoreboard, {
				h = EV_BAR_H,
				mark = WIN_EV / TOTAL_EV,
				caption = tostring(WIN_EV),
				name = "EVBar",
				order = 1,
			})
			race.tick.Name = "Marker270"
			race:setColors(Kit.playerColor(view, you), Kit.playerColor(view, them))
			race:set(election.ev[you] / TOTAL_EV, election.ev[them] / TOTAL_EV)
		end
		local versus = Kit.box({
			Name = "Versus",
			LayoutOrder = 2,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = scoreboard,
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

		-- The rating line's room is always there, so the layout never shifts when
		-- the change arrives (rated matches only).
		local slot = Kit.box({
			Name = "RatingSlot",
			LayoutOrder = leftNext(),
			Size = UDim2.new(1, 0, 0, Kit.size.body + 6),
			Visible = current.daily == nil, -- a Daily Race never moves a rating (D-082)
			Parent = left,
		})
		ratingLine = Kit.text("", {
			Name = "RatingChange",
			Size = UDim2.fromScale(1, 1),
			TextColor3 = Kit.colors.muted,
			TextXAlignment = Enum.TextXAlignment.Center,
			Visible = false,
			Parent = slot,
		})

		-- The rematch banner's place (filled by the rematch offer; empty, it takes no room).
		local rematchSlot = Kit.box({
			Name = "RematchSlot",
			LayoutOrder = rightNext(),
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = right,
		})
		Kit.list("Vertical", Kit.space.sm).Parent = rematchSlot
		-- The rematch banner (D-090) stands in it; hidden, it takes no room.
		rematchHome = rematchSlot
		placeBanner()
		-- The tutorial's end (D-080): win or lose, the player is ready for a real match.
		if current.tutorial then
			local ready = Kit.card({ Name = "TutorialReady", LayoutOrder = rightNext(), Parent = right })
			Kit.heading(LobbyWords.READY_PRACTICE, { Name = "ReadyTitle", LayoutOrder = 1, Parent = ready })
			Kit.text(LobbyWords.readyText(ConfigModule.defaults), {
				Name = "ReadyText",
				LayoutOrder = 2,
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Parent = ready,
			})
		end
		-- A Daily Race run (D-082): its own summary, filled by update().
		dailyLine, dailyMore, dailyRank = nil, nil, nil
		local run = current.daily
		if run then
			local box = Kit.card({ Name = "DailySummary", LayoutOrder = rightNext(), Parent = right })
			Kit.eyebrow(`{DailyWords.EYEBROW} · {DailyWords.dateLabel(run.day)}`, {
				Name = "DailyEyebrow",
				LayoutOrder = 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = box,
			})
			dailyLine = label(box, DailyWords.SAVING, {
				Name = "DailyLine",
				LayoutOrder = 2,
				Font = Kit.font.medium,
				TextColor3 = Kit.colors.text,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			dailyMore = label(box, "", {
				Name = "DailyMore",
				LayoutOrder = 4,
				TextSize = Kit.size.caption,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			-- A counted run's rank today, big, with the flame (D-090).
			local rankRow = Kit.box({
				Name = "DailyRankRow",
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, Kit.size.hero + Kit.space.sm),
				Visible = false,
				Parent = box,
			})
			local rankList = Kit.list("Horizontal", Kit.space.sm)
			rankList.HorizontalAlignment = Enum.HorizontalAlignment.Center
			rankList.VerticalAlignment = Enum.VerticalAlignment.Center
			rankList.Parent = rankRow
			local flame = Kit.icon("flame", RANK_FLAME, Featured.GOLD)
			flame.Name = "DailyRankFlame"
			flame.LayoutOrder = 1
			flame.Parent = rankRow
			dailyRank = Kit.text("", {
				Name = "DailyRank",
				LayoutOrder = 2,
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				Font = Kit.font.display,
				TextSize = Kit.size.hero,
				TextColor3 = Featured.GOLD,
				TextWrapped = false,
				Parent = rankRow,
			})
			Kit.dataColor(dailyRank)
		end

		-- Why: three short reasons, the winner's side.
		local winner = if result then result.winner else 0
		local reasons: { string } = if election then Words.keyReasons(ctx.config, view, winner, names) else {}
		if #reasons > 0 then
			local why = Kit.stack(
				{ Name = "Why", LayoutOrder = rightNext(), Parent = right },
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
				LayoutOrder = rightNext(),
				Size = UDim2.fromOffset(180, Kit.MIN_TOUCH),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = right,
			})
		end

		local _, opponent = Data.opponent(current)
		againBot = opponent ~= nil and opponent.kind == "Bot"
		afterTutorial = current.tutorial == true
		againDaily = current.daily ~= nil
		local opponentSeat = Data.opponent(current)
		rivalName = names[opponentSeat] or rivalName
		bar:setPrimary(if afterTutorial then LobbyWords.READY_PLAY else MatchWords.REMATCH, true)

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
				table.insert(stops, Motion.shine(plate))
				-- A gold light (D-098), not the usual white.
				local band = plate:FindFirstChild("Shine")
				if band and band:IsA("Frame") then
					band.BackgroundColor3 = GOLD
				end
				local glow = slideGlow
				if glow then
					local b = LANDSLIDE_BREATHE
					table.insert(stops, Motion.breathe(glow, "ImageTransparency", b[1], b[2], b[3]))
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

	-- The page's lanes: MAX_WIDTH, or MAX_WIDTH_WIDE on a wide screen (D-098).
	local laneWidth = MAX_WIDTH
	local function setLaneWidth(width: number)
		if width == laneWidth then
			return
		end
		laneWidth = width
		local lanes: { Frame } = { page.content }
		if page.header then
			table.insert(lanes, page.header)
		end
		for _, lane in lanes do
			local cap = lane:FindFirstChildOfClass("UISizeConstraint")
			if cap then
				cap.MaxSize = Vector2.new(width, math.huge)
			end
		end
	end

	local function relayout()
		page.setPortrait(ctx.portrait())
		-- A wide screen gets the wide page and two columns; a phone one column.
		local wide = not ctx.portrait() and not page.sideways() and page.root.AbsoluteSize.X >= TWO_COL_W
		setLaneWidth(if wide then MAX_WIDTH_WIDE else MAX_WIDTH)
		local list = columnsList
		if list then
			-- The wide lane is at least TWO_COL_W here: the page is that wide.
			local two = wide
			list.FillDirection = if two then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
			local gap = Kit.space.md
			for _, frame in sides do
				frame.Size = if two then UDim2.new(0.5, -gap / 2, 0, 0) else UDim2.fromScale(1, 0)
			end
		end
		if not tabbed and not page.sideways() then
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
			-- A Daily Race run (D-082): the server's word on it, once it arrives.
			local runLine, moreLine = dailyLine, dailyMore
			local mine = state.dailyRun
			if runLine and moreLine and current and mine and mine.matchId == current.matchId then
				runLine.Text = DailyWords.resultLine(mine)
				local info = state.daily
				local today = info ~= nil and current.daily ~= nil and info.day == current.daily.day
				if mine.counted then
					local you = if today and info.board then info.board.you else nil
					local rank = mine.rank or (if you then you.rank else nil)
					local streak = if today then ` · {DailyWords.streak(info.streak)}` else ""
					moreLine.Text = `{DailyWords.rankLine(rank, DailyNet.TOP)}{streak}`
					-- The rank, big, with the flame; gold confetti once (D-090).
					local big = dailyRank
					if big and rank then
						big.Text = `#{rank}`
						local row = big.Parent :: Frame
						row.Visible = true
						if rankCheered ~= current.matchId then
							rankCheered = current.matchId
							Motion.pop(row, Motion.POP_FROM)
							Motion.confetti(parent, { Featured.GOLD, Kit.colors.text }, RANK_CONFETTI)
						end
					end
				else
					moreLine.Text = DailyWords.practiceLine(if today then info.margin else nil)
				end
			end
			showRematch(state)
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
			showRematch(ctx.store.get())
		end,
		destroy = function()
			stopEffects()
			mapTab:destroy()
		end,
	}
end

return Screen
