--!strict
-- Results' Map tab (docs/DESIGN.md D-073): the final polls against the real
-- result, on the map. Everything comes from the player's own end-of-match View
-- through Shared/UI/PollMiss; the map is driven only through MapInterface
-- (setView, setMarks, setLens, select, onSelect).
--
--   MapTab.new(parent, order) -> Tab
--   tab:set(payload)            the match to show (redraws the current mode)
--   tab:layout(width, height)   fits the map to the column and the room left
--
-- Layout, top to bottom (a stack in the page's column):
--   ModeSwitch   two chips, full width: "Final polls" (Mode_Polls) | "Real
--                results" (Mode_Result), the shown one selected
--   ModeVotes    "Final polls: you 290, Rex 248" / "Election night: you 302, Rex 236"
--   MissLine     "Polls missed 3 states: NV, WI, AZ" (or "… called every state right.")
--   MapBox       the map: each state's fill is the final poll's leader by their
--                lead (as players saw it the last week) or election night's
--                winner by their margin; the lead or margin in the state's pill
--                ("+3", "+0.4"); every state the polls called wrong carries a
--                MISS tag edged in the real winner's color, in both modes
--   StateLine    "Tap a state to compare." / the tapped state's poll and result
-- The map is made the first time the tab shows (NodeMap is heavy; most players
-- never open the tab) and sized so the whole tab fits the screen without
-- scrolling.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Colors = require(ReplicatedStorage.Shared.UI.Colors)
local MapLayout = require(ReplicatedStorage.Shared.UI.MapLayout)
local PollMiss = require(ReplicatedStorage.Shared.UI.PollMiss)
local Session = require(ReplicatedStorage.Shared.Net.Session)

local Kit = require(script.Parent.Parent.Parent.UI.Kit)
local MapInterface = require(script.Parent.Parent.Parent.Map.MapInterface)
local NodeMap = require(script.Parent.Parent.Parent.Map.NodeMap)

local MapTab = {}

local MISS = "MISS" -- the tag on a state the polls called wrong
local LINE_H = Kit.size.body + 6 -- px, a one-line text row
local MAP_MIN_H = 160 -- px, the map never gets smaller than this
local STATE_H = 2 * (Kit.size.caption + 4) -- px, room for a tapped state's two lines, so a tap never moves the map
local HINT = "Tap a state to compare its final poll and its result."
local MODE_LABEL: { [PollMiss.Mode]: string } = { Polls = "Final polls", Result = "Real results" }

export type Tab = {
	root: Frame,
	set: (self: Tab, payload: Session.StatePayload, names: { string }) -> (),
	show: (self: Tab, visible: boolean) -> (),
	layout: (self: Tab, width: number, height: number) -> (),
}

function MapTab.new(parent: Instance, order: number): Tab
	local root = Kit.stack(
		{ Name = "MapTab", LayoutOrder = order, Visible = false, Parent = parent },
		"Vertical",
		Kit.space.sm
	)

	local switch = Kit.box({
		Name = "ModeSwitch",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, Kit.MIN_TOUCH),
		Parent = root,
	})
	Kit.list("Horizontal", Kit.space.xs).Parent = switch

	local votes = Kit.text("", {
		Name = "ModeVotes",
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, LINE_H),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.medium,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = root,
	})
	local mapBox =
		Kit.box({ Name = "MapBox", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, MAP_MIN_H), Parent = root })
	local missLine = Kit.text("", {
		Name = "MissLine",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, LINE_H),
		AutomaticSize = Enum.AutomaticSize.Y,
		Font = Kit.font.medium,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = root,
	})
	local stateLine = Kit.caption(HINT, {
		Name = "StateLine",
		LayoutOrder = 5,
		Size = UDim2.new(1, 0, 0, STATE_H),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = root,
	})

	local mode: PollMiss.Mode = "Polls"
	local current: Session.StatePayload? = nil
	local names: { string } = {}
	local rows: { PollMiss.Row } = {}
	local byId: { [string]: PollMiss.Row } = {}
	local selected: string? = nil
	local map: MapInterface.Map? = nil
	local chips: { [string]: TextButton } = {}
	local tab: Tab

	local function describe()
		local payload = current
		local row = if selected then byId[selected] else nil
		if payload and row then
			stateLine.Text = PollMiss.stateLine(row, payload.you, names)
			stateLine.TextColor3 = Kit.colors.text
		else
			stateLine.Text = HINT
			stateLine.TextColor3 = Kit.colors.muted
		end
	end

	local function paint()
		local payload = current
		local m = map
		for id, chip in chips do
			Kit.setSelected(chip, id == mode)
		end
		if payload == nil then
			return
		end
		local view = payload.view
		votes.Text = PollMiss.votesLine(mode, PollMiss.votes(rows, mode, #view.players), payload.you, names)
		if m == nil then
			return
		end
		local colors: { Colors.RGB } = {}
		for p, player in view.players do
			colors[p] = Colors.of(player.color)
		end
		local shown = table.clone(view)
		shown.states = PollMiss.mapStates(view, rows, mode)
		m:setView(shown, colors)
		local marks: { [string]: MapInterface.Mark } = {}
		local lines: { [string]: MapInterface.LensLine } = {}
		for _, row in rows do
			local leader, lead = PollMiss.lead(row, mode)
			if leader ~= 0 then
				lines[row.id] = {
					parts = {
						{
							text = PollMiss.leadText(lead),
							color = Kit.playerColor(view, leader),
							filled = true,
						},
					},
				}
			else
				lines[row.id] = { parts = { { text = "tie", color = Kit.colors.muted } } }
			end
			if row.miss then
				marks[row.id] = { note = MISS, noteColor = Kit.playerColor(view, row.winner) }
			end
		end
		m:setMarks(marks)
		m:setLens(lines)
		m:select(selected)
	end

	local function pick(next: PollMiss.Mode)
		if next == mode then
			return
		end
		mode = next
		paint()
	end

	for k, each in PollMiss.MODES do
		local id: PollMiss.Mode = each :: PollMiss.Mode
		local chip = Kit.chip(MODE_LABEL[id], function()
			pick(id)
		end, {
			Name = `Mode_{id}`,
			LayoutOrder = k,
			Size = UDim2.new(0.5, -Kit.space.xs / 2, 1, 0),
			Parent = switch,
		})
		chips[id] = chip
	end

	local function ensureMap()
		if map ~= nil then
			return
		end
		local made = NodeMap.new()
		made.root.AnchorPoint = Vector2.new(0.5, 0.5)
		made.root.Position = UDim2.fromScale(0.5, 0.5)
		made.root.Parent = mapBox
		made:onSelect(function(id: string)
			selected = if selected == id then nil else id
			made:select(selected)
			describe()
		end)
		map = made
	end

	tab = {
		root = root,
		set = function(_self: Tab, payload: Session.StatePayload, shortNames: { string })
			if current == nil or current.matchId ~= payload.matchId then
				mode = "Polls"
				selected = nil
			end
			current = payload
			names = shortNames
			rows = PollMiss.rows(payload.view)
			byId = {}
			for _, row in rows do
				byId[row.id] = row
			end
			missLine.Text = PollMiss.summary(PollMiss.misses(rows))
			describe()
			paint()
		end,
		show = function(_self: Tab, visible: boolean)
			root.Visible = visible
			if visible and map == nil then
				ensureMap()
				paint()
			end
		end,
		-- The map as wide as the column, but never so tall that the tab scrolls.
		layout = function(_self: Tab, width: number, height: number)
			local others = Kit.MIN_TOUCH
				+ votes.AbsoluteSize.Y
				+ missLine.AbsoluteSize.Y
				+ STATE_H
				+ 4 * Kit.space.sm
			local h = math.floor(math.min(width / MapLayout.ASPECT, math.max(height - others, MAP_MIN_H)))
			mapBox.Size = UDim2.new(1, 0, 0, h)
		end,
	}
	return tab
end

return MapTab
