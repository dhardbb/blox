--!strict
-- "How to play" for brand-new players (docs/DESIGN.md D-059): the Lobby's
-- ghost button opens this sheet of five short pages, one idea each: the goal
-- (270 votes, over two sample candidates' portraits), a week (plan, both reveal, the map moves), the actions, debates
-- and events, election night. Each page is a title, a small picture built from
-- Kit pieces and at most 30 words (Shared/UI/Words/Lobby.howTo). The pictures
-- for the goal, the actions and the debates are the in-match Help's own
-- (UI/Help.art), so both always show the same thing; the full rules stay in
-- the in-match "?" sheet.
--
-- Back and Next step through the pages; the last page's Next reads "Got it"
-- and closes. The sheet never holds a primary action (Next is a secondary).
--
--   local howTo = HowTo.new(screenRoot, ctx)
--   howTo.open()          opens on page 1
--   howTo.show(page)      shows page `page` (1-based)
--   howTo.page() -> number
--   howTo.sheet   the Sheet "HowToSheet"
--   Elements: HowToPage_<id> (HowToTitle_<id>, HowToArt_<id>, HowToText_<id>),
--   HowToNav (HowToBack, HowToCount, HowToNext)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local Words = require(ReplicatedStorage.Shared.UI.Words.Lobby)

local Help = require(script.Parent.Help)
local Kit = require(script.Parent.Kit)
local Sheet = require(script.Parent.Sheet)
local Types = require(script.Parent.Parent.Screens.Types)

local HowTo = {}

local HEIGHT = 0.7 -- share of the screen height (the tallest page, Actions, fits on a 720 px screen)
local NUMBER = 28 -- px, a step number's circle
local ROW = 28 -- px, one row of a picture
local NAV_W = 0.32 -- share of the row each nav button takes
local FACE = 40 -- px, the goal page's two candidate portraits (D-068)
local FACE_YOU = "okafor" -- the goal page's sample candidates: you (blue) and a rival (red)
local FACE_RIVAL = "calloway"

export type HowTo = {
	sheet: Sheet.Sheet,
	open: () -> (),
	show: (page: number) -> (),
	page: () -> number,
}

local function row(parent: Instance, name: string, order: number): Frame
	return Kit.box({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW),
		Parent = parent,
	})
end

-- Each week: the three beats, numbered (the look of Help's "Your turn").
local function weekArt(art: Frame)
	for k, text in Words.WEEK_STEPS do
		local line = row(art, `Step{k}`, k)
		local circle = Kit.text(tostring(k), {
			Name = "Number",
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(NUMBER, NUMBER),
			BackgroundTransparency = 0,
			BackgroundColor3 = Kit.colors.raised,
			Font = Kit.font.display,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = line,
		})
		Kit.round().Parent = circle
		Kit.bevel(circle)
		Kit.text(text, {
			Name = "Text",
			Position = UDim2.fromOffset(NUMBER + Kit.space.sm, 0),
			Size = UDim2.new(1, -(NUMBER + Kit.space.sm), 1, 0),
			Parent = line,
		})
	end
end

-- The goal page's face-off over the race bar: a sample candidate for you
-- (ringed blue) and one for your rival (ringed red), as in a match.
local function facesArt(art: Frame, config: any)
	local line = Kit.box({
		Name = "Faces",
		LayoutOrder = 0,
		Size = UDim2.new(1, 0, 0, FACE),
		Parent = art,
	})
	for k, id in { FACE_YOU, FACE_RIVAL } do
		local face = Kit.portrait(id, Candidates.profile(config, id).name, FACE, {
			ring = Kit.color(if k == 1 then Colors.player.Cobalt else Colors.player.Crimson),
		})
		face.AnchorPoint = Vector2.new(if k == 1 then 0 else 1, 0)
		face.Position = UDim2.fromScale(if k == 1 then 0 else 1, 0)
		face.Parent = line
	end
end

-- Election night: three states called, each for you or your rival.
local function nightArt(art: Frame)
	for k, call in Words.nightCalls() do
		local line = row(art, `Call{k}`, k)
		Kit.text(call.state, {
			Name = "State",
			Size = UDim2.fromScale(0.45, 1),
			Font = Kit.font.bold,
			Parent = line,
		})
		Kit.text(`{call.votes} votes`, {
			Name = "Votes",
			TextSize = Kit.size.caption,
			Position = UDim2.fromScale(0.45, 0),
			Size = UDim2.fromScale(0.25, 1),
			TextColor3 = Kit.colors.muted,
			Parent = line,
		})
		local box = Kit.box({
			Name = "WinnerBox",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.3, 1),
			Parent = line,
		})
		-- The winner's tag filled in their own color (blue you, red rival): red
		-- is a player here, never "bad" (D-056).
		Kit.pill(if call.you then "You" else "Rival", "text", {
			Name = "Winner",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			fill = Kit.color(if call.you then Colors.player.Cobalt else Colors.player.Crimson),
			Parent = box,
		})
	end
end

function HowTo.new(screen: Instance, ctx: Types.Ctx): HowTo
	local pages = Words.howTo(ctx.config)
	local sheet = Sheet.new(screen, { title = Words.HOWTO_TITLE, name = "HowToSheet", height = HEIGHT })
	local current = 1

	local frames: { Frame } = {}
	for k, page in pages do
		local frame = Kit.stack({
			Name = `HowToPage_{page.id}`,
			LayoutOrder = 1,
			Visible = k == 1,
			Parent = sheet.body,
		}, "Vertical", Kit.space.md)
		frames[k] = frame
		Kit.text(page.title, {
			Name = `HowToTitle_{page.id}`,
			LayoutOrder = 1,
			Font = Kit.font.display,
			Parent = frame,
		})
		local art = Kit.card({
			Name = `HowToArt_{page.id}`,
			LayoutOrder = 2,
			BackgroundColor3 = Kit.colors.field,
			Parent = frame,
		})
		if page.id == "goal" then
			facesArt(art, ctx.config)
			Help.art.win(art, ctx.config)
		elseif page.id == "week" then
			weekArt(art)
		elseif page.id == "actions" then
			Help.art.actions(art)
		elseif page.id == "events" then
			Help.art.events(art)
		else
			nightArt(art)
		end
		Kit.text(page.text, {
			Name = `HowToText_{page.id}`,
			LayoutOrder = 3,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = frame,
		})
	end

	-- Back · "2 of 5" · Next (or Got it).
	local nav = Kit.box({
		Name = "HowToNav",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = sheet.body,
	})
	local show: (page: number) -> ()
	local back = Kit.button(Words.HOWTO_BACK, function()
		show(current - 1)
	end, {
		variant = "ghost",
		Name = "HowToBack",
		Size = UDim2.fromScale(NAV_W, 1),
		Parent = nav,
	})
	local count = Kit.caption("", {
		Name = "HowToCount",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1 - 2 * NAV_W, 1),
		AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = nav,
	})
	local nextButton = Kit.button(Words.HOWTO_NEXT, function()
		if current >= #pages then
			sheet:close()
		else
			show(current + 1)
		end
	end, {
		variant = "secondary",
		Name = "HowToNext",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(NAV_W, 1),
		Parent = nav,
	})

	show = function(page: number)
		current = math.clamp(page, 1, #pages)
		for k, frame in frames do
			frame.Visible = k == current
		end
		back.Visible = current > 1
		count.Text = Words.pageCount(current, #pages)
		nextButton.Text = if current >= #pages then Words.HOWTO_DONE else Words.HOWTO_NEXT
	end
	show(1)

	return {
		sheet = sheet,
		open = function()
			show(1)
			sheet:open()
		end,
		show = function(page: number)
			show(page)
		end,
		page = function(): number
			return current
		end,
	}
end

return HowTo
