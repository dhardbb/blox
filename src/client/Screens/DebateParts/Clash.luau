--!strict
-- The debate's moments without input (docs/DESIGN.md D-072): the intro before
-- round 1, a round's clash, and the verdict after round 3.
--
--   Clash     (stamp) YOU WIN BY 3                      the result first, big
--             [ You  Defend 8 ]   [ Buster  Attack 5 ]   both moves, big
--             Your Defend beats Attack: +2
--             Your Defend won Jobs by 3: +2.0 in OH, PA ... (Zinger ×2) - PA flipped to you
--             Their Attack backfired: −0.5 in OH, PA ...
--   Verdict   (face) (stamp) BUSTER WON THE CROWD       the crowd's winner, big, with their face
--             [Safety · Split] [Jobs · You] [Health · Buster]   a chip per round in its winner's color
--             Crowd: Buster +2
--   Intro     the three topics, each tagged with whose issue it is
--
-- The slam (D-098): the two move cards pop in, the stamp lands on them a beat
-- later and the panel jolts. Under Reduce motion everything is simply there
-- (Motion's pop, stamp and shake do nothing then). On a landscape phone
-- (clash:setCompact(true)) the panel packs tighter, so the stamp and both moves
-- fit above the action bar, and the chips say "R1 · Split" instead of the topic.
--
--   local clash = Clash.new(parent, model, order)
--   clash:render(p) -> Round?   -- the round the clash shows (the screen marks the map with it)
--   clash:setCompact(on)   -- a landscape phone (optional for callers)
--   clash.root  Frame "DebateClash"
--   Elements: StampRow (VerdictFace, StampSlot > ClashStamp), ClashCards
--   (ClashYou, ClashThem: ClashYouMove, ClashThemMove), VerdictRounds
--   (VerdictRound1..), CounterLine, ClashLine, ClashExtra1.., RoundTopics.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedTypes = require(ReplicatedStorage.Shared.Types)
local SimState = require(ReplicatedStorage.Shared.Sim.State)
local Swing = require(ReplicatedStorage.Shared.UI.Swing)
local Words = require(ReplicatedStorage.Shared.UI.Words.Debate)

local Audio = require(script.Parent.Parent.Parent.UI.Audio)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Model = require(script.Parent.Parent.CampaignParts.Model)
local Motion = require(script.Parent.Parent.Parent.UI.Motion)

local Clash = {}

local CARD_H = 68 -- px, one side's card in the clash (the move in title size, D-098)
local CARD_H_COMPACT = 58 -- px, the same on a landscape phone
local STAMP_ROW = 60 -- px, the row the stamp sits in (a title-size stamp, D-098)
local STAMP_ROW_COMPACT = 52 -- px, the same on a landscape phone
local STAMP_INSET = 8 -- px kept free beside the stamp: room for its tilt
local FACE = 48 -- px, the crowd's winner's face beside the verdict stamp (D-098)
local PAD_COMPACT = 6 -- px, the panel's padding on a landscape phone
local SLAM_DELAY = 0.2 -- s after the cards pop in, the stamp lands on them
local SLAM_PX = 6 -- px the panel jolts as the stamp lands
local MAX_LINES = 3
local ROUNDS_WORD = { "One round:", "Two rounds:", "Three rounds:" } -- the intro's line over its topics

export type Clash = {
	root: Frame,
	render: (self: Clash, p: Model.Payload) -> SimState.DebateRound?,
	-- Packed tighter on a landscape phone (D-098). Optional for callers.
	setCompact: ((self: Clash, on: boolean) -> ())?,
}

-- The round a clash shows: the last finished one.
function Clash.lastRound(p: Model.Payload): SimState.DebateRound?
	local view = p.view
	local live = view.debate
	if live and #live.rounds > 0 then
		return live.rounds[#live.rounds]
	end
	local result = view.debates[#view.debates]
	if result and result.rounds and #result.rounds > 0 and result.week == view.week then
		return result.rounds[#result.rounds]
	end
	return nil
end

function Clash.new(parent: Instance, model: Model.Model, order: number): Clash
	local config = model.config
	local root = Kit.card({ Name = "DebateClash", LayoutOrder = order, Visible = false, Parent = parent })

	local compact = false
	-- The result first (D-098): the stamp, with the crowd's winner's face beside
	-- it on the verdict.
	local stampRow =
		Kit.box({ Name = "StampRow", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, STAMP_ROW), Parent = root })
	local faceSlot = Kit.box({
		Name = "VerdictFace",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(FACE, FACE),
		Visible = false,
		Parent = stampRow,
	})
	local stampSlot = Kit.box({ Name = "StampSlot", Parent = stampRow })

	local cards =
		Kit.box({ Name = "ClashCards", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, CARD_H), Parent = root })
	local cardPads: { UIPadding } = {}
	local function card(prefix: string, right: boolean): (Frame, TextLabel, TextLabel)
		local box = Kit.panel({
			Name = `Clash{prefix}`,
			AnchorPoint = Vector2.new(if right then 1 else 0, 0),
			Position = UDim2.fromScale(if right then 1 else 0, 0),
			Size = UDim2.new(0.5, -Kit.space.xs, 1, 0),
			Parent = cards,
		})
		local pad = box:FindFirstChildOfClass("UIPadding")
		if pad then
			table.insert(cardPads, pad)
		end
		local list = Kit.list("Vertical", 0)
		list.HorizontalAlignment = if right
			then Enum.HorizontalAlignment.Right
			else Enum.HorizontalAlignment.Left
		list.Parent = box
		local align = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
		local who = Kit.caption("", {
			Name = `Clash{prefix}Who`,
			LayoutOrder = 1,
			TextWrapped = false,
			TextXAlignment = align,
			Parent = box,
		})
		local move = Kit.text("", {
			Name = `Clash{prefix}Move`,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, Kit.size.title + 2),
			Font = Kit.font.display,
			TextSize = Kit.size.title,
			TextWrapped = false,
			TextScaled = true, -- "Pivot 5 · Zinger" shrinks in a landscape phone's column (D-089)
			TextXAlignment = align,
			Parent = box,
		})
		return box, who, move
	end
	local youCard, youWho, youMove = card("You", false)
	local themCard, themWho, themMove = card("Them", true)
	-- The verdict's rounds (D-098): one chip each, in the round winner's color.
	local roundChips = Kit.box({
		Name = "VerdictRounds",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, Kit.PILL_H),
		Parent = root,
	})
	Kit.list("Horizontal", Kit.space.xs).Parent = roundChips
	local counter = Kit.caption(
		"",
		{ Name = "CounterLine", LayoutOrder = 3, TextColor3 = Kit.colors.text, Parent = root }
	)
	local line = Kit.text("", {
		Name = "ClashLine",
		LayoutOrder = 4,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	-- The intro's rounds, one row each: "1." and the topic's symbol and name (D-076).
	local topicRows = Kit.stack({ Name = "RoundTopics", LayoutOrder = 5, Visible = false, Parent = root })
	local extra: { TextLabel } = {}
	for k = 1, MAX_LINES do
		extra[k] =
			Kit.caption("", { Name = `ClashExtra{k}`, LayoutOrder = 5 + k, Visible = false, Parent = root })
	end

	local stamp: Frame? = nil
	local shownKey: string? = nil
	-- The slam (D-098): with `cards`, both move cards pop in first and the stamp
	-- lands on them a beat later with a jolt; alone (the verdict), it just lands.
	local function setStamp(text: string, color: Color3, key: string, slam: boolean)
		if shownKey == key then
			return
		end
		shownKey = key
		if stamp then
			stamp:Destroy()
		end
		local s = Kit.stamp(text, color, {
			Name = "ClashStamp",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			size = Kit.size.title,
			fit = STAMP_INSET, -- a long name never pushes it past the column
			Parent = stampSlot,
		})
		stamp = s
		if slam then
			Motion.pop(youCard)
			Motion.pop(themCard)
			Motion.stamp(s, SLAM_DELAY)
			if not Motion.reduced() then
				task.delay(SLAM_DELAY + Motion.t.pop, function()
					if s.Parent ~= nil then
						Motion.shake(root, SLAM_PX)
					end
				end)
			end
		else
			Motion.stamp(s)
		end
	end

	-- The crowd's winner's face beside the verdict stamp; nil hides it.
	local faceKey: string? = nil
	local function setFace(view: any, winner: number?)
		faceSlot.Visible = winner ~= nil
		stampSlot.Position = UDim2.fromOffset(if winner then FACE + Kit.space.sm else 0, 0)
		stampSlot.Size = UDim2.new(1, if winner then -(FACE + Kit.space.sm) else 0, 1, 0)
		if winner == nil then
			return
		end
		local entry = view.players[winner]
		local name = Model.candidateName(config, view, winner)
		local key = `{winner}|{name}`
		if faceKey == key then
			return
		end
		faceKey = key
		for _, child in faceSlot:GetChildren() do
			child:Destroy()
		end
		local face = Kit.portrait(
			if entry then entry.candidate else nil,
			name,
			FACE,
			{ ring = Kit.playerColor(view, winner) }
		)
		face.Name = "CrowdWinnerFace"
		face.Parent = faceSlot
	end

	-- The verdict's chips, one per round.
	local function setChips(view: any, rounds: { SimState.DebateRound }, theirName: string)
		for _, child in roundChips:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		local n = math.max(#rounds, 1)
		local gap = Kit.space.xs * (n - 1) / n
		for k, round in rounds do
			local text, winner = Words.roundChip(view, round, theirName)
			if compact then
				-- A landscape phone: the round's number for its topic.
				text = `R{round.round} · {string.match(text, "· (.+)$") or text}`
			end
			local chip = Kit.pill(text, "text", {
				Name = `VerdictRound{k}`,
				LayoutOrder = k,
				Size = UDim2.new(1 / n, -gap, 1, 0),
				AutomaticSize = Enum.AutomaticSize.None,
				TextScaled = true,
				Parent = roundChips,
			})
			Kit.new("UITextSizeConstraint", {
				MaxTextSize = Kit.size.caption,
				MinTextSize = Kit.MIN_TEXT,
				Parent = chip,
			})
			if winner ~= 0 then
				Kit.paintPill(chip, "text", true, Kit.playerColor(view, winner))
			end
		end
	end

	local function setCompact(_self: Clash, on: boolean)
		if on == compact then
			return
		end
		compact = on
		local pad = root:FindFirstChildOfClass("UIPadding")
		if pad then
			local px = UDim.new(0, if on then PAD_COMPACT else 14)
			pad.PaddingTop, pad.PaddingBottom, pad.PaddingLeft, pad.PaddingRight = px, px, px, px
		end
		local list = root:FindFirstChildOfClass("UIListLayout")
		if list then
			list.Padding = UDim.new(0, if on then Kit.space.xs else Kit.space.sm)
		end
		stampRow.Size = UDim2.new(1, 0, 0, if on then STAMP_ROW_COMPACT else STAMP_ROW)
		cards.Size = UDim2.new(1, 0, 0, if on then CARD_H_COMPACT else CARD_H)
		for _, cardPad in cardPads do
			local px = UDim.new(0, if on then PAD_COMPACT else Kit.space.md)
			cardPad.PaddingTop, cardPad.PaddingBottom = px, px
		end
		-- Redraw the chips in the new form next render.
		shownKey = nil
	end

	local function toneColor(tone: string): Color3 -- a Words.Tone
		return if tone == "good"
			then Kit.colors.good
			elseif tone == "loss" then Kit.colors.loss
			else Kit.colors.raised
	end

	local function setLines(lines: { string })
		for k, label in extra do
			local text = lines[k]
			label.Visible = text ~= nil
			label.Text = text or ""
		end
	end

	local part: Clash = {
		root = root,
		setCompact = setCompact,
		render = function(_self: Clash, p: Model.Payload): SimState.DebateRound?
			local kind = Model.debateReveal(p)
			root.Visible = kind ~= nil
			if kind == nil then
				shownKey = nil
				return nil
			end
			local view = p.view
			local me, them = view.you, Model.opponentOf(view)
			local theirName = Model.firstName(config, view, them)
			topicRows.Visible = false
			roundChips.Visible = false
			if kind == "DebateIntro" then
				cards.Visible = false
				counter.Visible = false
				stampRow.Visible = false
				local live = view.debate
				local topics = if live then live.topics else {}
				local mine: { SharedTypes.Issue } = view.players[me].platform or {}
				local theirs: { SharedTypes.Issue } = view.players[them].platform or {}
				for _, child in topicRows:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				for k = 1, #topics do
					local topic: SharedTypes.Issue = topics[k]
					local tag = if table.find(mine, topic)
						then " (your issue)"
						elseif table.find(theirs, topic) then " (their issue)"
						else ""
					local row = Kit.box({
						Name = `RoundTopic{k}`,
						LayoutOrder = k,
						Size = UDim2.new(1, 0, 0, Kit.size.body + 6),
						Parent = topicRows,
					})
					local flow = Kit.list("Horizontal", Kit.space.sm)
					flow.VerticalAlignment = Enum.VerticalAlignment.Center
					flow.Parent = row
					Kit.text(`{k}.`, {
						Name = "Number",
						LayoutOrder = 1,
						Size = UDim2.fromOffset(0, Kit.size.body + 6),
						AutomaticSize = Enum.AutomaticSize.X,
						TextWrapped = false,
						Parent = row,
					})
					Kit.issueTag(topic, {
						LayoutOrder = 2,
						text = `{Model.issueName(topic)}{tag}`,
						textSize = Kit.size.body,
						iconSize = Kit.ISSUE_ICON,
						font = Kit.font.body,
						Parent = row,
					})
				end
				topicRows.Visible = #topics > 0
				line.Text = ROUNDS_WORD[#topics] or `{#topics} rounds:`
				setLines({ "Each round: pick Defend, Attack or Pivot. Your buttons show every outcome." })
				return nil
			end
			if kind == "Verdict" then
				cards.Visible = false
				counter.Visible = false
				stampRow.Visible = true
				local result = view.debates[#view.debates]
				if result == nil or result.crowd == nil then
					return nil
				end
				local lead = (result.crowd[me] or 0) - (result.crowd[them] or 0)
				local text, tone = Words.crowdStamp(lead, theirName)
				local key = `verdict:{result.week}:{text}` -- a redrawn payload with a new crowd redraws it
				if shownKey ~= key then
					setChips(view, result.rounds or {}, theirName)
				end
				-- The crowd's winner, big, with their face (D-098).
				setFace(view, if lead > 0 then me elseif lead < 0 then them else nil)
				setStamp(text, toneColor(tone), key, false)
				roundChips.Visible = result.rounds ~= nil and #result.rounds > 0
				line.Text = `Crowd: {Words.crowdLine(view, result.crowd, theirName)}`
				local lines: { string } = {}
				if result.ovation and result.ovation > 0 then
					local who = if result.ovation == me then "Your" else "Their"
					table.insert(
						lines,
						`{who} standing ovation: +{config.DEBATE_OVATION_MOMENTUM} momentum in every battleground`
					)
				end
				setLines(lines)
				return nil
			end
			-- The clash of the last finished round.
			setFace(view, nil)
			local round = Clash.lastRound(p)
			cards.Visible = round ~= nil
			counter.Visible = round ~= nil
			stampRow.Visible = round ~= nil
			if round == nil then
				return nil
			end
			local function side(p2: number): string
				local move = if round.canned[p2] then "No answer" else round.picks[p2]
				local z = if round.zingers[p2] then " · Zinger" else ""
				return `{move} {round.scores[p2]}{z}`
			end
			youWho.Text = "You"
			themWho.Text = theirName
			youMove.Text = side(me)
			themMove.Text = side(them)
			youMove.TextColor3 = Kit.playerText(view, me)
			themMove.TextColor3 = Kit.playerText(view, them)
			youCard.Visible = true
			themCard.Visible = true
			counter.Text = Words.counterLine(round, view) or "No counter this round"
			local text, tone = Words.stamp(view, round, theirName)
			local color = toneColor(tone)
			local key = `clash:{view.week}:{round.round}:{text}`
			if shownKey ~= key then
				Audio.play(if round.winner == me then "debateWin" else "whoosh")
			end
			setStamp(text, color, key, true)
			local topic = Swing.debateRound(config, view, round)
			line.Text = topic.line
			setLines(topic.gaffeLines)
			return round
		end,
	}
	return part
end

return Clash
