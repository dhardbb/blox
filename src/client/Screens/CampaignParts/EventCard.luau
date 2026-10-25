--!strict
-- The week's event and the week's news (UI overhaul §3.4):
--
-- The event strip (D-065), on the plan screen: one compact, tappable card
-- right under the header's score, full width, so the week's event is seen
-- without scrolling on a phone, an iPad or a desktop. A gold plate with the
-- event's icon (Spotlight tv, Regional megaphone, Windfall coins, Choice vote),
-- the title "Windfall · Small-dollar surge" (EventTitle) and one line of what
-- it does, "Fundraisers where you trail: 20% more" (EventLine; in a Choice
-- week the stance you took), then an arrow. A tap opens the EventSheet with
-- the details: the full effect (EventEffect), the story (EventText), what the
-- map's * marks (EventMapNote), the stance taken (ChoiceTaken) and, for a
-- candidate who previews the deck, next week's event (NextEvent). With only
-- next week's event known, the strip shows that ("Next week: …"). From
-- CLOSING_FROM_WEEK, and the week before, a third line says the closing-weeks
-- bonus ("Closing weeks: rallies and ads +15%", EventClosing; the sheet says it
-- in a sentence, ClosingDetail); a closing week with no event shows the strip
-- for that alone. Hidden during every reveal (B1). Its gold plate pulses once
-- when a new week's event arrives.
--
--   local strip = EventCard.strip(parent, sheetParent, model)
--   strip:render(p); strip:height() -> number (0 when hidden)
--
-- The event card, used by the Decision screen in a Choice week, a Collapsible
-- under a "THIS WEEK" eyebrow (EventEyebrow):
-- "Windfall · Donor retreat +" with the
-- effect line always under it (so collapsed it is still two lines), and the
-- flavor text and the map note in its body. Expanded by default in Spotlight
-- and Regional weeks, collapsed otherwise; the player's own toggle
-- holds for the rest of the week. Hidden during every reveal (B1).
--
-- Choice weeks (D-039, D-042, D-044, docs/UI-STYLE.md §4.4): the stance is
-- taken on the Decision screen, which shows this card alone, without its title
-- row (the header names the event): the question in one sentence, the story,
-- the three stances as full-width chips, each with what it does in a few words
-- ("A · Side with the staff" / "+4 states  −2 states", the gain green and the
-- loss orange; "C · Offer to mediate (safe)"; the selection is the white outline
-- and a white bar at the chip's left), the rival's line ("Rex picks too, in
-- secret. Same side: it mostly cancels. …", ChoiceRival), then "Why?" with the rest:
-- "States you need" (Shared/UI/Swing, from the public poll), the summary of
-- the shown stance on the map, the tradeoff note, and every state, stance by
-- stance (Explain.choiceLines). While the chips show, the map previews the
-- selected stance; holding a chip previews that one without selecting it. On
-- the plan screen that follows, the card says the stance you took in one line
-- (ChoiceTaken).
--
-- The week card ("News"), a Collapsible: last week's public moves by the opponent, their
-- money bracket, either side's underdog tier and what it gives, last week's
-- event (a Choice week: both stances, what they moved and flipped), what you
-- raised, your internal polls, this week's debate topic by topic (prep,
-- platform, stat and roll, then what each topic swung), the next debate, the
-- latest messages. Collapsed by default on every screen (the map and the
-- state card come first); the player's own toggle holds.
--
--   local event = EventCard.new(parent, model)        event:render(p, order)
--                                                      event:showsStances() -> boolean
--   local week = EventCard.week(parent, model, order) week:render(p); week:setPortrait(portrait)
--
-- Element names: EventCard (attributes EventKind, EventName), EventEyebrow, EventToggle,
-- EventEffect, EventText, EventMapNote, ChoiceRow, ChoiceA, ChoiceB, ChoiceC
-- (each with PickBar and Choice<X>Line: Choice<X>Effect, Choice<X>Loss), ChoiceRival, ChoiceWhy (WhyToggle), ChoiceNeed,
-- ChoiceSummary, ChoiceNote, ChoicePayHead, ChoicePay1..3, ChoiceTaken; EventClosing,
-- ClosingDetail (the strip); WeekCard,
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

local Words = require(SharedFolder.UI.Words.Campaign)

local Colors = require(SharedFolder.UI.Colors)
local Collapsible = require(script.Parent.Parent.Parent.UI.Collapsible)
local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local Model = require(script.Parent.Model)
local Motion = require(script.Parent.Parent.Parent.UI.Motion)
local Sheet = require(script.Parent.Parent.Parent.UI.Sheet)

type View = ViewModule.View

local EventCard = {}

local FEED_MESSAGES = 3 -- latest messages listed in the week card
local STANCE_H = 60 -- px, one stance chip: its name over what it does
local STANCE_BAR = 4 -- px, the bar at a stance chip's left: white when it is the pick
local STANCE_INSET = Kit.space.md + Kit.space.sm -- px, the chip's text inset (room for the bar)
local STRIP_ICON = 32 -- px, the event strip's icon plate
local STRIP_GLYPH = 22 -- px, the icon on the plate (two thirds of it)
local STRIP_ARROW = 28 -- px, the arrow at the strip's right end
local STRIP_H = 52 -- px, the strip: a touch target with two one-line texts
local STRIP_TITLE_H = Kit.size.body + 4 -- px, its title line (bold body)
local STRIP_LINE_H = Kit.size.caption + 4 -- px, its effect line (caption)
local STRIP_CLOSING_H = STRIP_H + STRIP_LINE_H + Kit.space.xs -- px, the strip with its closing-weeks line too (S3)
local STRIP_SHEET_H = 0.5 -- share of the screen the details sheet takes
local EVENT_ICONS: { [string]: string } = {
	Spotlight = "tv", -- the issue is on every channel
	Regional = "megaphone", -- rallies in one region
	Windfall = "coins", -- fundraisers
	Choice = "vote", -- take a stance
}

export type EventCard = {
	root: Frame,
	render: (self: EventCard, p: Model.Payload, order: number) -> (),
	showsStances: (self: EventCard) -> boolean,
}

export type EventStrip = {
	root: TextButton,
	sheet: Sheet.Sheet,
	render: (self: EventStrip, p: Model.Payload) -> (),
	height: (self: EventStrip) -> number,
}

export type WeekCard = {
	root: Frame,
	render: (self: WeekCard, p: Model.Payload) -> (),
	setPortrait: (self: WeekCard, portrait: boolean) -> (),
}

-- Is the event card open by default this week? (A Choice week's stance was
-- taken on the Decision screen, which always shows it open; on the plan screen
-- its one-line "Your stance" says enough.)
local function openByDefault(event: ViewModule.EventView): boolean
	return event.kind == "Spotlight" or event.kind == "Regional"
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
	-- "THIS WEEK" over the title row: the event is news, like a broadcast's eyebrow.
	local eyebrow = Kit.eyebrow("This week", { Name = "EventEyebrow", LayoutOrder = 0, Parent = card.root })
	-- Lined up with the title's text (the title row is a button with its padding).
	Kit.new("UIPadding", { PaddingLeft = UDim.new(0, Kit.space.sm), Parent = eyebrow })
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
	-- Everything about the stances beyond the one-line effects, one tap away.
	local why = Collapsible.new(card.body, { title = "Why?", name = "ChoiceWhy", order = 6 })
	why.toggle.Name = "WhyToggle"
	why.root.BackgroundTransparency = 1
	local whyPad = why.root:FindFirstChildOfClass("UIPadding")
	if whyPad then
		whyPad:Destroy()
	end
	local need = Kit.caption("", {
		Name = "ChoiceNeed",
		LayoutOrder = 1,
		TextColor3 = Kit.colors.text,
		Parent = why.body,
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
	local choiceEffects: { [string]: TextLabel } = {}
	local choiceLosses: { [string]: TextLabel } = {}
	local choiceBars: { [string]: Frame } = {}
	local function held(input: InputObject): boolean
		local kind = input.UserInputType.Name
		return kind == "MouseButton1" or kind == "Touch"
	end
	for k = 1, #Events.CHOICES do
		local answer: SharedTypes.Choice = Events.CHOICES[k]
		local button: TextButton
		button = Kit.chip(answer, function()
			if button.Active == false then
				return
			end
			model.choice = answer
			model.peekChoice = nil
			model.render()
		end, {
			Name = `Choice{answer}`,
			LayoutOrder = k,
			Size = UDim2.new(1, 0, 0, STANCE_H),
			Font = Kit.font.bold,
			TextScaled = false,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			Parent = answerRow,
		})
		local pad = button:FindFirstChildOfClass("UIPadding")
		if pad then
			pad.PaddingTop = UDim.new(0, Kit.space.sm)
			pad.PaddingBottom = UDim.new(0, Kit.space.sm)
			pad.PaddingLeft = UDim.new(0, STANCE_INSET)
			pad.PaddingRight = UDim.new(0, Kit.space.md)
		end
		-- A tab-like bar at the left edge: quiet, white on the picked stance.
		local bar = Kit.new("Frame", {
			Name = "PickBar",
			Position = UDim2.fromOffset(Kit.space.sm - STANCE_INSET, 0),
			Size = UDim2.new(0, STANCE_BAR, 1, 0),
			BackgroundColor3 = Kit.colors.raisedHover,
			BorderSizePixel = 0,
			Parent = button,
		})
		Kit.round().Parent = bar
		-- Decoration (the outline already shows the pick); it sits in the chip's
		-- left padding, which the headless engine does not lay out.
		bar:SetAttribute("Decor", true)
		-- What it does: the gain (green) and the loss (orange, with its −).
		local line = Kit.box({
			Name = `Choice{answer}Line`,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, Kit.size.caption + 4),
			Parent = button,
		})
		Kit.list("Horizontal", Kit.space.sm).Parent = line
		choiceEffects[answer] = Kit.text("", {
			Name = `Choice{answer}Effect`,
			LayoutOrder = 1,
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = Kit.size.caption,
			TextWrapped = false,
			TextColor3 = Kit.colors.good,
			Parent = line,
		})
		choiceLosses[answer] = Kit.text("", {
			Name = `Choice{answer}Loss`,
			LayoutOrder = 2,
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			TextSize = Kit.size.caption,
			TextWrapped = false,
			TextColor3 = Kit.colors.loss,
			Parent = line,
		})
		choiceBars[answer] = bar
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
	-- Under the chips, above "Why?": the rival takes a stance too (M2).
	local rivalNote = Kit.caption("", {
		Name = "ChoiceRival",
		LayoutOrder = 5,
		TextColor3 = Kit.colors.text,
		Visible = false,
		Parent = card.body,
	})
	local summary = Kit.text("", {
		Name = "ChoiceSummary",
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.medium,
		Parent = why.body,
	})
	local choiceNote = Kit.caption("", { Name = "ChoiceNote", LayoutOrder = 3, Parent = why.body })
	local payHead = Kit.caption("Every state, stance by stance:", {
		Name = "ChoicePayHead",
		LayoutOrder = 4,
		Parent = why.body,
	})
	local payLines: { TextLabel } = {}
	for k = 1, #Events.CHOICES do
		payLines[k] = Kit.caption("", {
			Name = `ChoicePay{k}`,
			LayoutOrder = 4 + k,
			TextColor3 = Kit.colors.text,
			Parent = why.body,
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
					`Next week, from your pollster: {upcoming.kind} · {upcoming.name}. {Words.percent(
						PlanDraft.eventEffect(config, upcoming)
					)}`
			end
			effect.Visible = event ~= nil
			eyebrow.Visible = event ~= nil and not (event.kind == "Choice" and Model.deciding(p) == "Stance")
			if event == nil then
				defaultFor = nil
				card:setTitle("No event this week")
				card:setExpanded(false)
				card.toggle.Visible = true
				card.root:SetAttribute("EventKind", nil)
				card.root:SetAttribute("EventName", nil)
				return
			end
			local key = `{event.week}:{event.id}`
			if defaultFor ~= key then
				defaultFor = key
				card:setExpanded(openByDefault(event))
			end
			card:setTitle(`{event.kind} · {event.name}`)
			card.root:SetAttribute("EventKind", event.kind)
			card.root:SetAttribute("EventName", event.name)
			effect.Text = Words.percent(PlanDraft.eventEffect(config, event))
			-- An event about an issue leads its effect line with that issue's symbol (D-076).
			local about: string? = if event.kind == "Spotlight" or event.kind == "Choice"
				then event.issue :: any
				else nil
			if effect:GetAttribute("LeadIssue") ~= about then
				effect:SetAttribute("LeadIssue", about)
				Kit.issueLead(effect, about)
			end
			flavor.Text = event.text
			local note = PlanDraft.eventMapNote(event)
			mapNote.Text = note or ""
			mapNote.Visible = note ~= nil
			local choosing = event.kind == "Choice" and Model.deciding(p) == "Stance"
			-- On the Decision screen the header names the event: no title row, always open.
			card.toggle.Visible = not choosing
			if choosing then
				card:setExpanded(true)
			end
			answerRow.Visible = choosing
			why.root.Visible = choosing
			choiceNote.Visible = choosing
			rivalNote.Visible = choosing
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
			rivalNote.Text = PlanDraft.rivalChoiceNote(Model.firstName(config, view, Model.opponentOf(view)))
			local canEdit = Model.editable(model, p)
			local stances = event.stances
			if stances then
				local hedge: SharedTypes.Choice = Events.defaultChoice()
				for _, stance in stances do
					local button = choiceButtons[stance.id]
					if button then
						button.Text = if stance.id == hedge
							then `{stance.id} · {stance.name} (safe)`
							else `{stance.id} · {stance.name}`
						local gain, loss = Words.stanceParts(Swing.stance(config, view, stance.id))
						choiceEffects[stance.id].Text = gain or ""
						choiceEffects[stance.id].Visible = gain ~= nil
						choiceLosses[stance.id].Text = loss or ""
						choiceLosses[stance.id].Visible = loss ~= nil
					end
				end
			end
			for answer, button in choiceButtons do
				local picked = model.choice == answer
				Kit.setSelected(button, picked)
				Kit.setEnabled(button, canEdit)
				choiceBars[answer].BackgroundColor3 = if picked
					then Kit.colors.accent
					else Kit.colors.raisedHover
				local gain = choiceEffects[answer]
				-- "No change" is not a gain: plain text.
				gain.TextColor3 = if not canEdit
					then Kit.colors.disabledText
					elseif string.sub(gain.Text, 1, 1) == "+" then Kit.colors.good
					else Kit.colors.text
				choiceLosses[answer].TextColor3 = if canEdit then Kit.colors.loss else Kit.colors.disabledText
			end
			local shownStance: SharedTypes.Choice = model.peekChoice or model.choice or Events.defaultChoice()
			summary.Text = Swing.stanceSummary(config, view, Swing.stance(config, view, shownStance))
		end,
	}
	return eventCard
end

-- The event strip under the header (D-065): see the top of this file.
function EventCard.strip(parent: Instance, sheetParent: Instance, model: Model.Model): EventStrip
	local config = model.config
	local sheet = Sheet.new(sheetParent, { title = "This week", name = "EventSheet", height = STRIP_SHEET_H })
	local root = Kit.cardButton(function()
		sheet:open()
	end, {
		Name = "EventCard",
		-- A fixed height, so the map under it never jumps: two one-line texts.
		Size = UDim2.new(1, 0, 0, STRIP_H),
		AutomaticSize = Enum.AutomaticSize.None,
		Visible = false,
		Parent = parent,
	})
	-- One row, placed by hand (not the card's column): the plate at the left,
	-- the two lines beside it, the arrow at the right; all centered in height.
	local column = root:FindFirstChildOfClass("UIListLayout")
	if column then
		column:Destroy()
	end
	local pad = root:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingTop = UDim.new(0, Kit.space.sm)
		pad.PaddingBottom = UDim.new(0, Kit.space.sm)
		pad.PaddingLeft = UDim.new(0, Kit.space.sm + Kit.space.xs)
		pad.PaddingRight = UDim.new(0, Kit.space.sm + Kit.space.xs)
	end
	-- The gold plate: news, like the leaderboard's gold coin (a data color).
	local plate = Kit.dataColor(Kit.iconPlate("vote", STRIP_ICON, Kit.colors.background))
	plate.Name = "EventIcon"
	plate.AnchorPoint = Vector2.new(0, 0.5)
	plate.Position = UDim2.fromScale(0, 0.5)
	plate.BackgroundColor3 = Kit.color(Colors.player.Amber)
	plate.Parent = root
	local textX = STRIP_ICON + Kit.space.sm + Kit.space.xs
	local textW = -(textX + STRIP_ARROW + Kit.space.xs)
	-- One line each; a name too long for a narrow phone ends in "…" rather than
	-- pushing the map down (the snapshot audit checks the whole deck at 390 px).
	local title = Kit.text("", {
		Name = "EventTitle",
		Position = UDim2.new(0, textX, 0.5, -STRIP_TITLE_H),
		Size = UDim2.new(1, textW, 0, STRIP_TITLE_H),
		AutomaticSize = Enum.AutomaticSize.None,
		Font = Kit.font.bold,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Parent = root,
	})
	local line = Kit.caption("", {
		Name = "EventLine",
		Position = UDim2.new(0, textX, 0.5, 0),
		Size = UDim2.new(1, textW, 0, STRIP_LINE_H),
		AutomaticSize = Enum.AutomaticSize.None,
		Font = Kit.font.medium,
		TextColor3 = Kit.colors.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = root,
	})
	-- The closing-weeks bonus (S3), under the event's line when there is one.
	local closing = Kit.caption("", {
		Name = "EventClosing",
		Position = UDim2.new(0, textX, 0.5, STRIP_LINE_H / 2),
		Size = UDim2.new(1, textW, 0, STRIP_LINE_H),
		AutomaticSize = Enum.AutomaticSize.None,
		Font = Kit.font.medium,
		TextColor3 = Kit.colors.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextYAlignment = Enum.TextYAlignment.Top,
		Visible = false,
		Parent = root,
	})
	Kit.text(Kit.glyph.arrow, {
		Name = "EventMore",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(STRIP_ARROW, STRIP_ICON),
		TextColor3 = Kit.colors.muted,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = root,
	})

	-- The details, one tap away.
	local function detail(name: string, order: number, caption: boolean): TextLabel
		local props = {
			Name = name,
			LayoutOrder = order,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = sheet.body,
		}
		return if caption then Kit.caption("", props) else Kit.text("", props)
	end
	local effect = detail("EventEffect", 1, false)
	effect.Font = Kit.font.medium
	local flavor = detail("EventText", 2, true)
	local mapNote = detail("EventMapNote", 3, true)
	local taken = detail("ChoiceTaken", 4, false)
	local nextLine = detail("NextEvent", 5, true)
	nextLine.TextColor3 = Kit.colors.text
	local closingDetail = detail("ClosingDetail", 6, true)
	closingDetail.TextColor3 = Kit.colors.text

	local pulsedFor: string? = nil -- the event the strip last pulsed for
	local iconKind: string? = nil -- the kind whose icon the plate shows

	local strip: EventStrip = {
		root = root,
		sheet = sheet,
		height = function(_self: EventStrip): number
			if not root.Visible then
				return 0
			end
			return if closing.Visible then STRIP_CLOSING_H else STRIP_H
		end,
		render = function(_self: EventStrip, p: Model.Payload)
			local view = p.view
			local event = Model.shownEvent(p)
			local upcoming = if p.reveal == nil then view.nextEvent else nil
			local shown = event or upcoming
			local closingWords = if p.reveal == nil then Words.closing(config, view.week) else nil
			root.Visible = shown ~= nil or closingWords ~= nil
			root:SetAttribute("EventKind", if event then event.kind else nil)
			root:SetAttribute("EventName", if event then event.name else nil)
			closingDetail.Text = if closingWords then closingWords.detail else ""
			closingDetail.Visible = closingWords ~= nil
			if shown == nil then
				closing.Visible = false
				root.Size = UDim2.new(1, 0, 0, STRIP_H)
				if closingWords == nil then
					sheet:close()
					return
				end
				-- A closing week with no event: the strip says the bonus alone.
				if iconKind ~= "Closing" then
					iconKind = "Closing"
					for _, child in plate:GetChildren() do
						if child:IsA("GuiObject") then
							child:Destroy()
						end
					end
					local icon = Kit.icon("clock", STRIP_GLYPH, Kit.colors.background)
					icon.Name = "Icon"
					icon.AnchorPoint = Vector2.new(0.5, 0.5)
					icon.Position = UDim2.fromScale(0.5, 0.5)
					icon.Parent = plate
				end
				title.Text = closingWords.title
				line.Text = closingWords.alone
				title.Position = UDim2.new(0, textX, 0.5, -STRIP_TITLE_H)
				line.Position = UDim2.new(0, textX, 0.5, 0)
				sheet:setTitle(closingWords.title)
				effect.Text = ""
				for _, label in { effect, flavor, mapNote, taken, nextLine } do
					label.Visible = false
				end
				return
			end
			effect.Visible = true
			flavor.Visible = true
			-- With the closing line, the three lines sit centered together.
			closing.Visible = closingWords ~= nil
			closing.Text = if closingWords then closingWords.line else ""
			local lift = if closing.Visible then STRIP_LINE_H / 2 else 0
			root.Size = UDim2.new(1, 0, 0, if closing.Visible then STRIP_CLOSING_H else STRIP_H)
			title.Position = UDim2.new(0, textX, 0.5, -STRIP_TITLE_H - lift)
			line.Position = UDim2.new(0, textX, 0.5, -lift)
			local key = `{shown.week}:{shown.id}`
			if pulsedFor ~= key then
				pulsedFor = key
				-- The gold plate pulses, not the whole strip: a full-width strip
				-- scaled 3% would run past the screen's edge and clip its arrow.
				Motion.pulseOnce(plate)
			end
			-- An event about an issue (a spotlight, a stance) shows that issue's
			-- symbol (D-076); the others, their kind's icon.
			local issue: string? = if shown.kind == "Spotlight" or shown.kind == "Choice"
				then shown.issue :: any
				else nil
			local useIssue = issue ~= nil and Kit.hasIssueIcon(issue)
			local iconFor = if issue and useIssue then `{shown.kind}:{issue}` else shown.kind
			if iconKind ~= iconFor then
				-- The plate's icon follows the event's kind (or issue).
				iconKind = iconFor
				for _, child in plate:GetChildren() do
					if child:IsA("GuiObject") then
						child:Destroy()
					end
				end
				local icon = if issue and useIssue
					then Kit.issueIcon(issue, STRIP_GLYPH, Kit.colors.background)
					else Kit.icon(EVENT_ICONS[shown.kind] or "vote", STRIP_GLYPH, Kit.colors.background)
				icon.Name = "Icon"
				icon.AnchorPoint = Vector2.new(0.5, 0.5)
				icon.Position = UDim2.fromScale(0.5, 0.5)
				icon.Parent = plate
			end
			title.Text = Words.eventTitle(shown, event == nil)
			line.Text = Words.eventLine(config, shown, if event then view.stance else nil)
			sheet:setTitle(Words.eventTitle(shown, event == nil))
			effect.Text = Words.percent(PlanDraft.eventEffect(config, shown))
			flavor.Text = shown.text
			local note = PlanDraft.eventMapNote(shown)
			mapNote.Text = note or ""
			mapNote.Visible = note ~= nil
			local mine: SharedTypes.Choice? = if event then view.stance else nil
			taken.Visible = event ~= nil and event.kind == "Choice" and mine ~= nil
			if event and mine ~= nil then
				local name = ""
				local stances: { ViewModule.StanceView } = event.stances or {}
				for _, entry in stances do
					if entry.id == mine then
						name = ` · {entry.name}`
					end
				end
				taken.Text = `Your stance: {mine}{name}. Secret until the week resolves.`
			end
			nextLine.Visible = event ~= nil and upcoming ~= nil
			if event and upcoming then
				nextLine.Text =
					`Next week, from your pollster: {upcoming.kind} · {upcoming.name}. {Words.percent(
						PlanDraft.eventEffect(config, upcoming)
					)}`
			end
		end,
	}
	return strip
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
		Collapsible.new(parent, { title = "News", name = "WeekCard", order = order, expanded = false })
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

	local week: WeekCard = {
		root = card.root,
		setPortrait = function(_self: WeekCard, _portrait: boolean)
			-- The same on every screen size since UI style v2 (collapsed by default).
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
