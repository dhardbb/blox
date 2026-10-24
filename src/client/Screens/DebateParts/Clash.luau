--!strict
-- The debate's moments without input (docs/DESIGN.md D-072): the intro before
-- round 1, a round's clash, and the verdict after round 3.
--
--   Clash     [ You · Defend 8 ]   [ Rex · Attack 5 ]
--             Your Defend beats Attack: +2
--             (stamp) YOU WIN BY 3
--             Your Defend won Jobs by 3: +2.0 in OH, PA ... (Zinger ×2) - PA flipped to you
--             Their Attack backfired: −0.5 in OH, PA ...
--   Verdict   (stamp) YOU WON THE CROWD · Crowd: you +4 · a line per round
--   Intro     the three topics, each tagged with whose issue it is
--
--   local clash = Clash.new(parent, model, order)
--   clash:render(p) -> Round?   -- the round the clash shows (the screen marks the map with it)
--   clash.root  Frame "DebateClash"
--   Elements: ClashYou, ClashThem (ClashYouMove, ClashThemMove), CounterLine,
--   ClashStamp, ClashLine, ClashBackfire1.., VerdictLine1.., OvationLine,
--   IntroTopic1...

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

local CARD_H = 56 -- px, one side's card in the clash
local STAMP_ROW = 56 -- px, the row the stamp sits in
local MAX_LINES = 3

export type Clash = {
	root: Frame,
	render: (self: Clash, p: Model.Payload) -> SimState.DebateRound?,
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

	local cards =
		Kit.box({ Name = "ClashCards", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, CARD_H), Parent = root })
	local function card(prefix: string, right: boolean): (Frame, TextLabel, TextLabel)
		local box = Kit.panel({
			Name = `Clash{prefix}`,
			AnchorPoint = Vector2.new(if right then 1 else 0, 0),
			Position = UDim2.fromScale(if right then 1 else 0, 0),
			Size = UDim2.new(0.5, -Kit.space.xs, 1, 0),
			Parent = cards,
		})
		Kit.list("Vertical", 0).Parent = box
		local who =
			Kit.caption("", { Name = `Clash{prefix}Who`, LayoutOrder = 1, TextWrapped = false, Parent = box })
		local move = Kit.text("", {
			Name = `Clash{prefix}Move`,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 24),
			Font = Kit.font.bold,
			TextSize = Kit.size.heading,
			TextWrapped = false,
			Parent = box,
		})
		return box, who, move
	end
	local youCard, youWho, youMove = card("You", false)
	local themCard, themWho, themMove = card("Them", true)
	local counter = Kit.caption(
		"",
		{ Name = "CounterLine", LayoutOrder = 2, TextColor3 = Kit.colors.text, Parent = root }
	)
	local stampRow =
		Kit.box({ Name = "StampRow", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, STAMP_ROW), Parent = root })
	local line = Kit.text("", {
		Name = "ClashLine",
		LayoutOrder = 4,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = root,
	})
	local extra: { TextLabel } = {}
	for k = 1, MAX_LINES do
		extra[k] =
			Kit.caption("", { Name = `ClashExtra{k}`, LayoutOrder = 4 + k, Visible = false, Parent = root })
	end

	local stamp: Frame? = nil
	local shownKey: string? = nil
	local function setStamp(text: string, color: Color3, key: string)
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
			size = Kit.size.heading,
			Parent = stampRow,
		})
		stamp = s
		Motion.stamp(s)
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
			if kind == "DebateIntro" then
				cards.Visible = false
				counter.Visible = false
				stampRow.Visible = false
				local live = view.debate
				local topics = if live then live.topics else {}
				local mine: { SharedTypes.Issue } = view.players[me].platform or {}
				local theirs: { SharedTypes.Issue } = view.players[them].platform or {}
				local parts: { string } = {}
				for k = 1, #topics do
					local topic: SharedTypes.Issue = topics[k]
					local tag = if table.find(mine, topic)
						then " (your issue)"
						elseif table.find(theirs, topic) then " (their issue)"
						else ""
					table.insert(parts, `{k}. {Model.issueName(topic)}{tag}`)
				end
				line.Text = `Three rounds: {table.concat(parts, " · ")}`
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
				local text, color
				if lead > 0 then
					text, color = "YOU WON THE CROWD", Kit.colors.good
				elseif lead < 0 then
					text, color = `{string.upper(theirName)} WON THE CROWD`, Kit.colors.loss
				else
					text, color = "AN EVEN CROWD", Kit.colors.raised
				end
				setStamp(text, color, `verdict:{result.week}`)
				line.Text = Words.crowdLine(view, result.crowd, theirName)
				local lines: { string } = {}
				if result.ovation and result.ovation > 0 then
					local who = if result.ovation == me then "Your" else "Their"
					table.insert(
						lines,
						`{who} standing ovation: +{config.DEBATE_OVATION_MOMENTUM} momentum in every battleground`
					)
				end
				for _, round in result.rounds do
					local stampText = Words.stamp(view, round, theirName)
					table.insert(
						lines,
						`R{round.round} {Model.issueName(round.topic)}: {string.lower(stampText)}`
					)
				end
				setLines(lines)
				return nil
			end
			-- The clash of the last finished round.
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
			local color = if tone == "good"
				then Kit.colors.good
				elseif tone == "loss" then Kit.colors.loss
				else Kit.colors.raised
			local key = `clash:{view.week}:{round.round}`
			if shownKey ~= key then
				Audio.play(if round.winner == me then "debateWin" else "whoosh")
			end
			setStamp(text, color, key)
			local topic = Swing.debateRound(config, view, round)
			line.Text = topic.line
			setLines(topic.gaffeLines)
			return round
		end,
	}
	return part
end

return Clash
