--!strict
-- The two cards about the week (UI overhaul §3.4):
--
-- The event card, a Collapsible: "Event · Windfall · Donor retreat +" with the
-- effect line always under it (so collapsed it is still two lines), and the
-- flavor text, the map note and, in Choice weeks, the three answer chips in its
-- body, with what each answer pays against each of theirs (Shared/UI/Explain,
-- from Config's payoff matrix). Expanded by default in Choice, Spotlight and Regional weeks, collapsed
-- otherwise; the player's own toggle holds for the rest of the week. Hidden
-- during every reveal (B1). In Choice weeks it moves above the state card.
--
-- The week card, a Collapsible: last week's public moves by the opponent, their
-- money bracket, either side's underdog tier and what it gives, last week's
-- event, what you raised, your internal polls, this week's debate topic by
-- topic (prep, platform, stat and roll), the next debate, the latest messages. Expanded on 16:9, collapsed on phones.
--
--   local event = EventCard.new(parent, model)        event:render(p, order)
--   local week = EventCard.week(parent, model, order) week:render(p); week:setPortrait(portrait)
--
-- Element names: EventCard (attributes EventKind, EventName), EventToggle,
-- EventEffect, EventText, EventMapNote, ChoiceRow, ChoiceAttack, ChoiceDefend,
-- ChoiceIgnore, ChoiceNote, ChoicePayHead, ChoicePay1..3; WeekCard, WeekToggle,
-- FeedOpponent, FeedMoney, FeedUnderdog, FeedTheirUnderdog, FeedEvent,
-- FeedRaised, FeedPolls, FeedLastDebate, FeedDebate, FeedMessages.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedFolder = ReplicatedStorage.Shared
local ConfigModule = require(SharedFolder.Sim.Config)
local Events = require(SharedFolder.Sim.Events)
local Explain = require(SharedFolder.UI.Explain)
local PlanDraft = require(SharedFolder.UI.PlanDraft)
local SharedTypes = require(SharedFolder.Types)
local ViewModule = require(SharedFolder.Sim.View)

local Collapsible = require(script.Parent.Parent.Parent.UI.Collapsible)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Layout = require(script.Parent.Parent.Common.Layout)
local Model = require(script.Parent.Model)

type View = ViewModule.View

local EventCard = {}

local FEED_MESSAGES = 3 -- latest messages listed in the week card

export type EventCard = {
	root: Frame,
	render: (self: EventCard, p: Model.Payload, order: number) -> (),
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
	local card = Collapsible.new(parent, { title = "Event", name = "EventCard" })
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
	local mapNote = Kit.caption("", { Name = "EventMapNote", LayoutOrder = 2, Parent = card.body })
	local answerRow, answerLayout = Layout.grid(card.body, "ChoiceRow", 3)
	Layout.setGrid(answerLayout, #Events.CHOICES, Kit.MIN_TOUCH, Kit.space.sm)
	local choiceButtons: { [string]: TextButton } = {}
	for k = 1, #Events.CHOICES do
		local answer: SharedTypes.Choice = Events.CHOICES[k]
		local button: TextButton
		button = Kit.button(answer, function()
			if button.Active == false then
				return
			end
			model.draft.choice = answer
			model.render()
		end, {
			variant = "chip",
			Name = `Choice{answer}`,
			LayoutOrder = k,
			Size = answerLayout.CellSize,
			Parent = answerRow,
		})
		choiceButtons[answer] = button
	end
	local choiceNote = Kit.caption("", { Name = "ChoiceNote", LayoutOrder = 4, Parent = card.body })
	local payHead = Kit.caption("National points for you, by their answer:", {
		Name = "ChoicePayHead",
		LayoutOrder = 5,
		Parent = card.body,
	})
	local payLines: { TextLabel } = {}
	for k = 1, #Events.CHOICES do
		payLines[k] = Kit.caption("", {
			Name = `ChoicePay{k}`,
			LayoutOrder = 5 + k,
			TextColor3 = Kit.colors.text,
			Parent = card.body,
		})
	end

	local defaultFor: string? = nil -- the event whose default expansion was applied

	local eventCard: EventCard = {
		root = card.root,
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
			local choosing = event.kind == "Choice" and Model.planning(p)
			answerRow.Visible = choosing
			choiceNote.Visible = choosing
			local isChoice = event.kind == "Choice"
			payHead.Visible = isChoice
			for k, line in Explain.choiceLines(config) do
				local label = payLines[k]
				if label then
					label.Text = line
					label.Visible = isChoice
				end
			end
			if not choosing then
				return
			end
			choiceNote.Text = PlanDraft.choiceNote(config)
			local canEdit = Model.editable(model, p)
			for answer, button in choiceButtons do
				Kit.setSelected(button, model.draft.choice == answer)
				Kit.setEnabled(button, canEdit)
			end
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
			lastEvent.Text = eventLine or ""
			lastEvent.Visible = eventLine ~= nil
			raised.Text = `You raised {Model.money(view.raised)} from fundraisers last week.`
			raised.Visible = view.raised > 0
			local pollParts: { string } = {}
			for _, result in view.internalPolls do
				table.insert(
					pollParts,
					string.format(
						"%s %.1f-%.1f",
						result.state,
						result.support[you] or 0,
						result.support[them] or 0
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
