--!strict
-- Map marks for what a stance or a debate moves (D-042), from Shared/UI/Swing's
-- numbers. Pure apart from colors: the Campaign screen hands the result to the
-- map in place of its usual marks.
--
-- Only what matters gets a label (docs/UI-STYLE.md §4.6): the flips and the
-- SwingMarks.BADGES biggest moves (by points, then votes) carry a badge; every
-- other moved state only glows, so the map never shows more than a handful of
-- labels at once.
--
-- Preview (a stance in a Choice week, your side only): a gain glows in your
-- color ("+1.5" on a tag filled in your color if it is one of the biggest); a
-- loss glows orange ("−0.5" on an orange tag with a dark number: Kit.colors.loss,
-- never red, which is a player's color, D-056); a state whose public-poll leader
-- would change says FLIP (a dark tag edged in your color if it comes to you, in
-- orange if you lose it) with a strong glow; a state the stance does not
-- move is dimmed.
-- Reveal (a debate topic or both stances, after the fact): each moved state
-- glows toward whoever gained (badge: the net points toward you, in your color,
-- or toward them, in theirs: ownership, not a loss); a flip says just FLIP,
-- edged in the new leader's color.
--
--   SwingMarks.preview(view, preview, keep) -> marks
--   SwingMarks.reveal(view, net, flips, keep) -> marks
-- `keep` is the screen's usual marks; their owner rings are kept.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Numbers = require(ReplicatedStorage.Shared.UI.Numbers)
local Swing = require(ReplicatedStorage.Shared.UI.Swing)
local ViewModule = require(ReplicatedStorage.Shared.Sim.View)

local Kit = require(script.Parent.Parent.Parent.UI.Kit)

type View = ViewModule.View
type Marks = { [string]: any }

local StateData = require(ReplicatedStorage.Shared.Sim.StateData)

local SwingMarks = {}

SwingMarks.BADGES = 5 -- biggest moves labelled on the map (flips always are)

local FLIP = "FLIP"

-- The states in `points` that get a badge: the BADGES biggest moves.
local function biggest(points: { [string]: number }): { [string]: boolean }
	local ids: { string } = {}
	for id, value in points do
		if value ~= 0 then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a: string, b: string): boolean
		local da, db = math.abs(points[a]), math.abs(points[b])
		if math.abs(da - db) > 1e-9 then
			return da > db
		end
		local ea, eb = StateData.byId[a].ev, StateData.byId[b].ev
		if ea ~= eb then
			return ea > eb
		end
		return a < b
	end)
	local out: { [string]: boolean } = {}
	for k = 1, math.min(SwingMarks.BADGES, #ids) do
		out[ids[k]] = true
	end
	return out
end

local function base(keep: Marks, id: string): { [string]: any }
	local old = keep[id]
	return { ring = if old then old.ring else nil }
end

local function rivalOf(view: View): number
	return if view.you == 1 then 2 else 1
end

-- A stance (Swing.Preview) or a debate focus (Swing.Focus): both carry effects and flips.
function SwingMarks.preview(
	view: View,
	preview: { effects: { [string]: number }, flips: { Swing.Flip } },
	keep: Marks
): Marks
	local mine = Kit.playerColor(view, view.you)
	local labelled = biggest(preview.effects)
	local marks: Marks = {}
	for _, s in view.states do
		local mark = base(keep, s.id)
		local points = preview.effects[s.id]
		if points == nil or points == 0 then
			mark.dim = true
		else
			local color = if points > 0 then mine else Kit.colors.loss
			mark.halo = color
			if labelled[s.id] then
				mark.badge = Numbers.signed(points)
				mark.badgeColor = color
			end
		end
		marks[s.id] = mark
	end
	for _, flip in preview.flips do
		local mark = marks[flip.state]
		if mark then
			local good = flip.to == view.you or (flip.to == 0 and flip.from ~= view.you)
			local points = preview.effects[flip.state]
			if points and points ~= 0 and mark.badge == nil then
				mark.badge = Numbers.signed(points)
				mark.badgeColor = if good then mine else Kit.colors.loss
			end
			mark.note = FLIP
			mark.noteColor = if good then mine else Kit.colors.loss
			mark.halo = if good then mine else Kit.colors.loss
			mark.haloStrong = true
		end
	end
	return marks
end

function SwingMarks.reveal(view: View, net: { [string]: number }, flips: { Swing.Flip }, keep: Marks): Marks
	local mine = Kit.playerColor(view, view.you)
	local theirs = Kit.playerColor(view, rivalOf(view))
	local labelled = biggest(net)
	local marks: Marks = {}
	for _, s in view.states do
		local mark = base(keep, s.id)
		local points = net[s.id]
		if points ~= nil and points ~= 0 then
			local color = if points > 0 then mine else theirs
			mark.halo = color
			if labelled[s.id] then
				mark.badge = Numbers.signed(points)
				mark.badgeColor = color
			end
		end
		marks[s.id] = mark
	end
	for _, flip in flips do
		local mark = marks[flip.state]
		if mark then
			-- A flip says FLIP alone: the panel has its points, and a short tag
			-- keeps the busy debate map readable.
			mark.badge = nil
			local color = if flip.to == 0 then Kit.colors.text else Kit.playerColor(view, flip.to)
			mark.note = FLIP
			mark.noteColor = color
			mark.halo = color
			mark.haloStrong = true
		end
	end
	return marks
end

return SwingMarks
