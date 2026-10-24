--!strict
-- The debate stage (docs/DESIGN.md D-072): both candidates' faces with their
-- Zinger, the crowd meter between them, and the moderator's question for this
-- round with the facts that set its strengths.
--
--   (DO) Dana              Rex +2             Rex (RC)
--        Zinger ✓       ◀▓▓▓▓|░░░░▶     No Zinger
--   ROUND 2 OF 3 · HEALTH
--   "Clinics out west have month-long waits. What would you do?"
--   <Their issue> <You trail its states> <Counter +3>
--
-- Faces are the candidates' portraits ringed in their player colors (Kit.portrait,
-- D-068); Stage.face is the one place that makes a face.
--
--   local stage = Stage.new(parent, model, order)
--   stage:render(p)          -- the live round, its clash or the verdict
--   stage.root  Frame "DebateStage"
--   Elements: YouFace, ThemFace, YouName, ThemName, YouZinger, ThemZinger,
--   CrowdBar, CrowdLine, RoundLabel, Question, Facts (Fact1..).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Swing = require(ReplicatedStorage.Shared.UI.Swing)
local Words = require(ReplicatedStorage.Shared.UI.Words.Debate)

local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Model = require(script.Parent.Parent.CampaignParts.Model)

local Stage = {}

local FACE = 40 -- px, a face
local ROW_H = 48 -- px, the faces row
local SIDE_W = 128 -- px, one side: face + name column
local CROWD_SPAN = 12 -- crowd points from the middle to either end of the meter
local MAX_FACTS = 4

export type Stage = {
	root: Frame,
	render: (self: Stage, p: Model.Payload) -> (),
}

-- A candidate's face: their portrait ringed in `color` (the initials of `name`
-- until it is uploaded). The one place faces are made.
function Stage.face(name: string, color: Color3, px: number, candidate: string?): Frame
	return Kit.portrait(candidate, name, px, { ring = color })
end

function Stage.new(parent: Instance, model: Model.Model, order: number): Stage
	local config = model.config
	local root = Kit.card({ Name = "DebateStage", LayoutOrder = order, Parent = parent })

	local row = Kit.box({ Name = "Faces", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, ROW_H), Parent = root })
	local function side(prefix: string, right: boolean): (Frame, TextLabel, TextLabel)
		local holder = Kit.box({
			Name = `{prefix}Side`,
			AnchorPoint = Vector2.new(if right then 1 else 0, 0),
			Position = UDim2.fromScale(if right then 1 else 0, 0),
			Size = UDim2.new(0, SIDE_W, 1, 0),
			Parent = row,
		})
		local faceSlot = Kit.box({
			Name = `{prefix}FaceSlot`,
			AnchorPoint = Vector2.new(if right then 1 else 0, 0.5),
			Position = UDim2.fromScale(if right then 1 else 0, 0.5),
			Size = UDim2.fromOffset(FACE, FACE),
			Parent = holder,
		})
		local column = Kit.box({
			Name = `{prefix}Column`,
			Position = UDim2.fromOffset(if right then 0 else FACE + Kit.space.xs, 0),
			Size = UDim2.new(1, -(FACE + Kit.space.xs), 1, 0),
			Parent = holder,
		})
		local list = Kit.list("Vertical", 0)
		list.HorizontalAlignment = if right
			then Enum.HorizontalAlignment.Right
			else Enum.HorizontalAlignment.Left
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Parent = column
		local name = Kit.text("", {
			Name = `{prefix}Name`,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 20),
			Font = Kit.font.bold,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
			Parent = column,
		})
		local zinger = Kit.caption("", {
			Name = `{prefix}Zinger`,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 18),
			TextWrapped = false,
			TextXAlignment = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left,
			Parent = column,
		})
		return faceSlot, name, zinger
	end
	local youSlot, youName, youZinger = side("You", false)
	local themSlot, themName, themZinger = side("Them", true)
	local middle = Kit.box({
		Name = "Crowd",
		Position = UDim2.fromOffset(SIDE_W + Kit.space.sm, 0),
		Size = UDim2.new(1, -2 * (SIDE_W + Kit.space.sm), 1, 0),
		Parent = row,
	})
	local crowdList = Kit.list("Vertical", 2)
	crowdList.VerticalAlignment = Enum.VerticalAlignment.Center
	crowdList.Parent = middle
	local crowdLine = Kit.caption("", {
		Name = "CrowdLine",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 18),
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = middle,
	})
	local crowd = Kit.raceBar(middle, { h = 10, mark = 0.5, name = "CrowdBar", order = 2 })

	-- "ROUND 1 OF 3 · SAFETY", led by the topic's symbol (D-076).
	local roundRow = Kit.box({
		Name = "RoundRow",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, Kit.size.caption + 4),
		Parent = root,
	})
	local roundFlow = Kit.list("Horizontal", Kit.space.xs)
	roundFlow.VerticalAlignment = Enum.VerticalAlignment.Center
	roundFlow.Parent = roundRow
	local roundLabel = Kit.eyebrow("", {
		Name = "RoundLabel",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, Kit.size.caption + 4),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		Parent = roundRow,
	})
	local roundIcon: GuiObject? = nil
	local function setRoundIcon(topic: string?)
		local old = roundIcon
		if old and old:GetAttribute("IssueIcon") == topic then
			return
		end
		if old then
			old:Destroy()
		end
		roundIcon = nil
		if topic and Kit.hasIssueIcon(topic) then
			local icon = Kit.issueIcon(topic, Kit.MIN_ICON + 2, Kit.colors.muted)
			icon.LayoutOrder = 1
			icon.Parent = roundRow
			roundIcon = icon
		end
	end
	local question = Kit.text("", {
		Name = "Question",
		LayoutOrder = 4,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.medium,
		Parent = root,
	})
	local facts =
		Kit.box({ Name = "Facts", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, Kit.PILL_H), Parent = root })
	Kit.list("Horizontal", Kit.space.xs).Parent = facts
	local factPills: { TextLabel } = {}
	for k = 1, MAX_FACTS do
		factPills[k] =
			Kit.pill("", "text", { Name = `Fact{k}`, LayoutOrder = k, Visible = false, Parent = facts })
	end

	local faces: { [string]: string } = {}
	local function setFace(slot: Frame, key: string, name: string, color: Color3, candidate: string?)
		local stamp = `{candidate}|{name}|{tostring(color)}`
		if faces[key] == stamp then
			return
		end
		faces[key] = stamp
		for _, child in slot:GetChildren() do
			child:Destroy()
		end
		local face = Stage.face(name, color, FACE, candidate)
		face.Name = `{key}Face`
		face.Parent = slot
	end

	local stage: Stage = {
		root = root,
		render = function(_self: Stage, p: Model.Payload)
			local view = p.view
			local me, them = view.you, Model.opponentOf(view)
			local live = view.debate
			local result = view.debates[#view.debates]
			local zingers: { number } = if live then live.zingers else { 0, 0 }
			local crowdBy: { number } = if live
				then live.crowd
				elseif result and result.crowd then result.crowd
				else { 0, 0 }
			local myName = Model.candidateName(config, view, me)
			local theirName = Model.candidateName(config, view, them)
			setFace(youSlot, "You", myName, Kit.playerColor(view, me), view.players[me].candidate)
			setFace(themSlot, "Them", theirName, Kit.playerColor(view, them), view.players[them].candidate)
			youName.Text = Model.firstName(config, view, me)
			themName.Text = Model.firstName(config, view, them)
			youName.TextColor3 = Kit.playerText(view, me)
			themName.TextColor3 = Kit.playerText(view, them)
			local function zingerText(n: number): string
				return if n > 0 then `Zinger {Kit.glyph.check}` else "No Zinger"
			end
			youZinger.Text = zingerText(zingers[me] or 0)
			themZinger.Text = zingerText(zingers[them] or 0)
			local lead = (crowdBy[me] or 0) - (crowdBy[them] or 0)
			local share = math.clamp(0.5 + lead / (2 * CROWD_SPAN), 0.02, 0.98)
			crowd:setColors(Kit.playerColor(view, me), Kit.playerColor(view, them))
			crowd:set(share, 1 - share)
			crowdLine.Text = Words.crowdLine(view, crowdBy, Model.firstName(config, view, them))

			-- The round: live, or the one the clash shows.
			-- The board only while a round asks for moves: during a clash the live
			-- debate already holds the next round's board.
			local board = if Model.debating(p) then Swing.debateBoard(config, view) else nil
			local topic: string? = nil
			local roundNo, rounds = 0, config.DEBATE_TOPICS
			if board then
				topic, roundNo, rounds = board.topic, board.round, board.rounds
			elseif Model.debateReveal(p) == "Clash" then
				local list = if live then live.rounds elseif result then result.rounds else nil
				local last = list and list[#list]
				if last then
					topic, roundNo = last.topic, last.round
				end
			end
			local verdict = Model.debateReveal(p) == "Verdict"
			local intro = Model.debateReveal(p) == "DebateIntro"
			roundRow.Visible = topic ~= nil or verdict or intro
			setRoundIcon(if verdict or intro then nil else topic)
			question.Visible = topic ~= nil
			if verdict then
				roundLabel.Text = "THE VERDICT"
			elseif intro then
				roundLabel.Text = `WEEK {view.week} DEBATE · {rounds} ROUNDS`
			elseif topic then
				roundLabel.Text = `ROUND {roundNo} OF {rounds} · {string.upper(Model.issueName(topic))}`
				question.Text = `"{Words.question(topic)}"`
			end
			local list = if board then Words.facts(board) else {}
			for k, pill in factPills do
				local text = list[k]
				pill.Visible = text ~= nil
				if text then
					pill.Text = text
					local tone = if text == "Your issue" or text == "You lead its states"
						then "good"
						elseif text == "Their issue" or text == "You trail its states" then "text"
						else "muted"
					Kit.paintPill(pill, tone :: any, false)
				end
			end
			facts.Visible = #list > 0
		end,
	}
	return stage
end

return Stage
