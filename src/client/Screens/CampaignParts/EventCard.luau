--!strict
-- The two cards about the week (UI overhaul §3.4):
--
-- The event card, a Collapsible: "Event · Windfall · Donor retreat +" with the
-- effect line always under it (so collapsed it is still two lines), and the
-- flavor text and the map note in its body. Expanded by default in Choice,
-- Spotlight and Regional weeks, collapsed otherwise; the player's own toggle
-- holds for the rest of the week. Hidden during every reveal (B1).
--
-- Choice weeks (D-039, D-042, D-044): the stance is taken on the Decision
-- screen, which shows this card alone: "States you need" (Shared/UI/Swing, from
-- the public poll), the three stances as full-width chips ("A · Side with the
-- staff", "C · Offer to mediate (hedge, default)"; the selection is an accent
-- outline), the one-line summary of the stance on the map, and under "Every
-- state, stance by stance" the full lists for nerds (Explain.choiceLines).
-- While the chips show, the map previews the selected stance; holding a chip
-- previews that one without selecting it. On the plan screen that follows, the
-- card says the stance you took in one line (ChoiceTaken).
--
-- The week card, a Collapsible: last week's public moves by the opponent, their
-- money bracket, either side's underdog tier and what it gives, last week's
-- event (a Choice week: both stances, what they moved and flipped), what you
-- raised, your internal polls, this week's debate topic by topic (prep,
-- platform, stat and roll, then what each topic swung), the next debate, the
-- latest messages. Expanded on 16:9, collapsed on phones.
--
--   local event = EventCard.new(parent, model)        event:render(p, order)
--                                                      event:showsStances() -> boolean
--   local week = EventCard.week(parent, model, order) week:render(p); week:setPortrait(portrait)
--
-- Element names: EventCard (attributes EventKind, EventName), EventToggle,
-- EventEffect, EventText, EventMapNote, ChoiceNeed, ChoiceRow, ChoiceA, ChoiceB,
-- ChoiceC, ChoiceSummary, ChoiceNote, ChoicePayHead, ChoicePay1..3, ChoiceTaken; WeekCard,
-- WeekToggle, FeedOpponent, FeedMoney, FeedUnderdog, FeedTheirUnderdog,
-- FeedEvent, FeedRaised, FeedPolls, FeedLastDebate, FeedDebate, FeedMessages.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedFolder = ReplicatedStorage.Shared
local ConfigModule = require(SharedFolder.Sim.Config)
local Events = require(SharedFolder.Sim.Events)
local Explain = require(SharedFolder.UI.Explain)
local PlanDraft = require(SharedFolder.UI.PlanDraft)
local SharedTypes = require(SharedFolder.Types)
local Swing = require(SharedFolder.UI.Swing)
local ViewModule = require(SharedFolder.Sim.View)

local Collapsible = require(script.Parent.Parent.Parent.UI.Collapsible)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Model = require(script.Parent.Model)

type View = ViewModule.View

local EventCard = {}

local FEED_MESSAGES = 3 -- latest messages listed in the week card

export type EventCard = {
	root: Frame,
	render: (self: EventCard, p: Model.Payload, order: number) -> (),
	showsStances: (self: EventCard) -> boolean,
}

export type WeekCard = {
	root: Frame,
	render: (self: WeekCard, p: Model.Payload) -> (),
	setPortrait: (self: WeekCard, portrait: boolean) -> (),
}

-- Is the event card open by default this week?
local function openByDefault(event: ViewModule.EventView): boolean
	return event.kind == "Choice" or event.kind == "Spotlight" or event.kind == "Regional"
end

function EventCard.new(parent: Instance, model: Model.Model): EventCard
	local config = model.config
	local card = Collapsible.new(parent, {
		title = "Event",
		name = "EventCard",
		onToggle = function()
			model.render()
		end,
	})
	card.toggle.Name = "EventToggle"
	-- The effect line sits between the title row and the body: always shown.
	card.body.LayoutOrder = 3
	local effect = Kit.text("", {
		Name = "EventEffect",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.medium,
		Parent = card.root,
	})
	-- Next week's event, for a candidate who previews the deck (Strand, D-035). It
	-- sits below the body so it shows whether or not the card is expanded.
	local nextLine = Kit.caption("", {
		Name = "NextEvent",
		LayoutOrder = 4,
		TextColor3 = Kit.colors.text,
		Visible = false,
		Parent = card.root,
	})
	local flavor = Kit.caption("", { Name = "EventText", LayoutOrder = 1, Parent = card.body })
	-- On the plan screen after the Decision step: the stance you took, in one line.
	local taken = Kit.text("", {
		Name = "ChoiceTaken",
		LayoutOrder = 5,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.medium,
		Visible = false,
		Parent = card.root,
	})
	local mapNote = Kit.caption("", { Name = "EventMapNote", LayoutOrder = 2, Parent = card.body })
	local need = Kit.caption("", {
		Name = "ChoiceNeed",
		LayoutOrder = 3,
		TextColor3 = Kit.colors.text,
		Parent = card.body,
	})
	-- The stances, one full-width chip each, so long names stay readable on phones.
	local answerRow = Kit.box({
		Name = "ChoiceRow",
		LayoutOrder = 4,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card.body,
	})
	Kit.list("Vertical", Kit.space.sm).Parent = answerRow
	local choiceButtons: { [string]: TextButton } = {}
	local function held(input: InputObject): boolean
		local kind = input.UserInputType.Name
		return kind == "MouseButton1" or kind == "Touch"
	end
	for k = 1, #Events.CHOICES do
		local answer: SharedTypes.Choice = Events.CHOICES[k]
		local button: TextButton
		button = Kit.button(answer, function()
			if button.Active == false then
				return
			end
			model.choice = answer
			model.peekChoice = nil
			model.render()
		end, {
			variant = "chip",
			Name = `Choice{answer}`,
			LayoutOrder = k,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = answerRow,
		})
		-- Press and hold: preview this stance on the map without picking it.
		button.InputBegan:Connect(function(input: InputObject)
			if held(input) and model.peekChoice ~= answer then
				model.peekChoice = answer
				model.render()
			end
		end)
		button.InputEnded:Connect(function(input: InputObject)
			if held(input) and model.peekChoice == answer then
				model.peekChoice = nil
				model.render()
			end
		end)
		choiceButtons[answer] = button
	end
	local summary = Kit.text("", {
		Name = "ChoiceSummary",
		LayoutOrder = 5,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.medium,
		Parent = card.body,
	})
	local choiceNote = Kit.caption("", { Name = "ChoiceNote", LayoutOrder = 6, Parent = card.body })
	local payHead = Kit.caption("Every state, stance by stance:", {
		Name = "ChoicePayHead",
		LayoutOrder = 7,
		Parent = card.body,
	})
	local payLines: { TextLabel } = {}
	for k = 1, #Events.CHOICES do
		payLines[k] = Kit.caption("", {
			Name = `ChoicePay{k}`,
			LayoutOrder = 7 + k,
			TextColor3 = Kit.colors.text,
			Parent = card.body,
		})
	end

	local defaultFor: string? = nil -- the event whose default expansion was applied

	local eventCard: EventCard = {
		root = card.root,
		showsStances = function(_self: EventCard): boolean
			return card.root.Visible and card:isExpanded() and answerRow.Visible
		end,
		render = function(_self: EventCard, p: Model.Payload, order: number)
			local event = Model.shownEvent(p)
			local upcoming = if p.reveal == nil then p.view.nextEvent else nil
			card.root.Visible = event ~= nil or upcoming ~= nil
			card.root.LayoutOrder = order
			nextLine.Visible = upcoming ~= nil
			if upcoming then
				nextLine.Text =
					`Next week, from your pollster: {upcoming.kind} · {upcoming.name}. {PlanDraft.eventEffect(
						config,
						upcoming
					)}`
			end
			effect.Visible = event ~= nil
			if event == nil then
				defaultFor = nil
				card:setTitle("No event this week")
				card:setExpanded(false)
				card.root:SetAttribute("EventKind", nil)
				card.root:SetAttribute("EventName", nil)
				return
			end
			local key = `{event.week}:{event.id}`
			if defaultFor ~= key then
				defaultFor = key
				card:setExpanded(openByDefault(event))
			end
			card:setTitle(`Event · {event.kind} · {event.name}`)
			card.root:SetAttribute("EventKind", event.kind)
			card.root:SetAttribute("EventName", event.name)
			effect.Text = PlanDraft.eventEffect(config, event)
			flavor.Text = event.text
			local note = PlanDraft.eventMapNote(event)
			mapNote.Text = note or ""
			mapNote.Visible = note ~= nil
			local choosing = event.kind == "Choice" and Model.deciding(p) == "Stance"
			answerRow.Visible = choosing
			choiceNote.Visible = choosing
			need.Visible = choosing
			summary.Visible = choosing
			local isChoice = choosing
			payHead.Visible = isChoice
			local view = p.view
			local mine: SharedTypes.Choice? = view.stance
			taken.Visible = event.kind == "Choice" and not choosing and mine ~= nil
			if mine ~= nil then
				local name = ""
				local stances: { ViewModule.StanceView } = event.stances or {}
				for _, entry in stances do
					if entry.id == mine then
						name = ` · {entry.name}`
					end
				end
				taken.Text = `Your stance: {mine}{name}. Secret until the week resolves.`
			end
			local me = view.players[view.you]
			for k, line in Explain.choiceLines(config, view.issueMap, event, me.platform, Events.baseOf(me)) do
				local label = payLines[k]
				if label then
					label.Text = line
					label.Visible = isChoice
				end
			end
			if not choosing then
				return
			end
			need.Text = Swing.needText(config, view)
			choiceNote.Text = PlanDraft.choiceNote(config)
			local canEdit = Model.editable(model, p)
			local stances = event.stances
			if stances then
				local hedge: SharedTypes.Choice = Events.defaultChoice()
				for _, stance in stances do
					local button = choiceButtons[stance.id]
					if button then
						button.Text = if stance.id == hedge
							then `{stance.id} · {stance.name} (hedge, default)`
							else `{stance.id} · {stance.name}`
					end
				end
			end
			for answer, button in choiceButtons do
				Kit.setSelected(button, model.choice == answer)
				Kit.setEnabled(button, canEdit)
			end
			local shownStance: SharedTypes.Choice = model.peekChoice or model.choice or Events.defaultChoice()
			summary.Text = Swing.stanceSummary(config, view, Swing.stance(config, view, shownStance))
		end,
	}
	return eventCard
end

-- What the opponent did in public last week.
local function opponentCard(config: ConfigModule.Config, view: View): string
	local them = Model.opponentOf(view)
	local name = Model.candidateName(config, view, them)
	local card = view.players[them].card
	if card == nil then
		return `{name} has no public moves yet.`
	end
	local issueName = Model.issueName
	local parts: { string } = {}
	local rallies: { string } = {}
	for _, rally in card.rallies do
		table.insert(rallies, `{rally.state} ({issueName(rally.issue)})`)
	end
	if #rallies > 0 then
		table.insert(parts, "rallies in " .. table.concat(rallies, ", "))
	end
	if #card.fundraisers > 0 then
		table.insert(parts, "fundraisers in " .. table.concat(card.fundraisers, ", "))
	end
	local ads: { string } = {}
	local attacks: { string } = {}
	for _, media in card.media do
		table.insert(if media.attack then attacks else ads, `{media.state} ({issueName(media.issue)})`)
	end
	if #ads > 0 then
		table.insert(parts, "ads in " .. table.concat(ads, ", "))
	end
	if #attacks > 0 then
		table.insert(parts, "attack ads in " .. table.concat(attacks, ", "))
	end
	if card.pivot then
		table.insert(parts, `pivoted from {issueName(card.pivot.drop)} to {issueName(card.pivot.add)}`)
	end
	if card.flights > 0 then
		table.insert(parts, Model.plural(card.flights, "flight"))
	end
	if #parts == 0 then
		return `{name} made no public moves last week.`
	end
	return `{name} last week: {table.concat(parts, "; ")}.`
end

function EventCard.week(parent: Instance, model: Model.Model, order: number): WeekCard
	local config = model.config
	local card =
		Collapsible.new(parent, { title = "Week card", name = "WeekCard", order = order, expanded = true })
	card.toggle.Name = "WeekToggle"
	local function line(k: number, name: string, color: Color3?): TextLabel
		return Kit.text("", {
			Name = name,
			LayoutOrder = k,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextColor3 = color or Kit.colors.text,
			Parent = card.body,
		})
	end
	local opponent = line(1, "FeedOpponent")
	local money = line(2, "FeedMoney", Kit.colors.muted)
	local underdog = line(3, "FeedUnderdog")
	local theirUnderdog = line(4, "FeedTheirUnderdog")
	local lastEvent = line(5, "FeedEvent")
	local raised = line(6, "FeedRaised", Kit.colors.good)
	local polls = line(7, "FeedPolls")
	local lastDebate = Kit.caption("", { Name = "FeedLastDebate", LayoutOrder = 8, Parent = card.body })
	local debateLine = line(9, "FeedDebate")
	local messages = Kit.caption("", { Name = "FeedMessages", LayoutOrder = 10, Parent = card.body })
	local portrait: boolean? = nil

	local week: WeekCard = {
		root = card.root,
		setPortrait = function(_self: WeekCard, isPortrait: boolean)
			if portrait ~= isPortrait then
				portrait = isPortrait
				card:setExpanded(not isPortrait)
			end
		end,
		render = function(_self: WeekCard, p: Model.Payload)
			local view = p.view
			local you, them = view.you, Model.opponentOf(view)
			opponent.Text = opponentCard(config, view)
			money.Text = `Their money: {view.players[them].money}`
			local mine = Explain.underdogText(config, view, you)
			underdog.Text = mine or ""
			underdog.Visible = mine ~= nil
			local theirs = Explain.underdogText(config, view, them)
			theirUnderdog.Text = theirs or ""
			theirUnderdog.Visible = theirs ~= nil
			local eventLine = PlanDraft.lastEventLine(view)
			local choiceResult = Swing.lastChoice(view)
			if eventLine and choiceResult then
				eventLine ..= "\n" .. table.concat(Swing.choiceLines(config, view, choiceResult), "\n")
			end
			lastEvent.Text = eventLine or ""
			lastEvent.Visible = eventLine ~= nil
			raised.Text = `You raised {Model.money(view.raised)} from fundraisers last week.`
			raised.Visible = view.raised > 0
			local pollParts: { string } = {}
			for _, result in view.internalPolls do
				local units = result.gotv[them] or 0
				table.insert(
					pollParts,
					string.format(
						"%s %.1f-%.1f%s",
						result.state,
						result.support[you] or 0,
						result.support[them] or 0,
						if units > 0 then ` (their ground game {units})` else ""
					)
				)
			end
			polls.Text = `Your internal polls (you-them): {table.concat(pollParts, ", ")}`
			polls.Visible = #pollParts > 0
			-- This week's debate, topic by topic: why each was won or tied.
			local result = view.debates[#view.debates]
			if result and result.week == view.week then
				local rows: { string } = {}
				for t, topic in result.topics do
					local winner = result.winners[t]
					local verdict = if winner == you
						then "you won"
						elseif winner == 0 then "tie"
						else "they won"
					table.insert(
						rows,
						`{Model.issueName(topic)} ({verdict}): {Explain.debateLine(config, view, result, t)}`
					)
				end
				-- Then what each topic moved, in words (the reveal said it too).
				for t = 1, #result.topics do
					local entry = Swing.debateTopic(config, view, result, t)
					table.insert(rows, entry.line)
					for _, gaffe in entry.gaffeLines do
						table.insert(rows, gaffe)
					end
				end
				local other = Swing.debateOther(view, result)
				if #other > 0 then
					local phrases: { string } = {}
					for _, flip in other do
						table.insert(phrases, Swing.flipPhrase(view, flip))
					end
					table.insert(rows, `Also, from the points every state got: {table.concat(phrases, ", ")}`)
				end
				lastDebate.Text = `This week's debate: {table.concat(rows, "\n")}`
				lastDebate.Visible = true
			else
				lastDebate.Visible = false
			end
			local debate = view.nextDebate
			if debate then
				local names: { string } = {}
				for _, topic in debate.topics do
					table.insert(names, Model.issueName(topic))
				end
				debateLine.Text = `Next debate, week {debate.week}: {table.concat(names, ", ")}`
			end
			debateLine.Visible = debate ~= nil
			local latest: { string } = {}
			local all = model.messages
			for k = math.max(1, #all - FEED_MESSAGES + 1), #all do
				table.insert(latest, all[k].text)
			end
			messages.Text = table.concat(latest, "\n")
			messages.Visible = #latest > 0
		end,
	}
	return week
end

return EventCard
