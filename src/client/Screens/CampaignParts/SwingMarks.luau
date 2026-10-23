--!strict
-- Map marks for what a stance or a debate moves (D-042), from Shared/UI/Swing's
-- numbers. Pure apart from colors: the Campaign screen hands the result to the
-- map in place of its usual marks.
--
-- Preview (a stance in a Choice week, your side only): a gain is a "+1.5" badge
-- in your color with a soft glow; a loss is a red "-1.5" badge; a state whose
-- public-poll leader would change says FLIP under it (your color if it comes to
-- you, red if you lose it) with a strong glow; a state the stance does not move
-- is dimmed.
-- Reveal (a debate topic or both stances, after the fact): each moved state's
-- badge is the net points toward you (your color) or toward them (their color),
-- with a soft glow in that color; a flip says FLIP in the new leader's color.
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

local SwingMarks = {}

local FLIP = "FLIP"

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
	local marks: Marks = {}
	for _, s in view.states do
		local mark = base(keep, s.id)
		local points = preview.effects[s.id]
		if points == nil or points == 0 then
			mark.dim = true
		elseif points > 0 then
			mark.badge = Numbers.signed(points)
			mark.badgeColor = mine
			mark.halo = mine
		else
			mark.badge = Numbers.signed(points)
			mark.badgeColor = Kit.colors.danger
		end
		marks[s.id] = mark
	end
	for _, flip in preview.flips do
		local mark = marks[flip.state]
		if mark then
			local good = flip.to == view.you or (flip.to == 0 and flip.from ~= view.you)
			mark.note = FLIP
			mark.noteColor = if good then mine else Kit.colors.danger
			mark.halo = if good then mine else Kit.colors.danger
			mark.haloStrong = true
		end
	end
	return marks
end

function SwingMarks.reveal(view: View, net: { [string]: number }, flips: { Swing.Flip }, keep: Marks): Marks
	local mine = Kit.playerColor(view, view.you)
	local theirs = Kit.playerColor(view, rivalOf(view))
	local marks: Marks = {}
	for _, s in view.states do
		local mark = base(keep, s.id)
		local points = net[s.id]
		if points ~= nil and points ~= 0 then
			local color = if points > 0 then mine else theirs
			mark.badge = Numbers.signed(points)
			mark.badgeColor = color
			mark.halo = color
		end
		marks[s.id] = mark
	end
	for _, flip in flips do
		local mark = marks[flip.state]
		if mark then
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
