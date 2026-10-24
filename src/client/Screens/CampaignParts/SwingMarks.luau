--!strict
-- Map marks for what a stance or a debate moves (D-042), from Shared/UI/Swing's
-- numbers. Pure apart from colors: the Campaign screen hands the result to the
-- map in place of its usual marks.
--
-- Only what matters gets a label (docs/UI-STYLE.md §4.6, D-079): never more
-- than SwingMarks.LABELS on the map at once. A flip is a 3 px outline in the
-- new leader's color (the halo, strong) and, on the SwingMarks.FLIP_TAGS
-- biggest flips by votes, a one-character tag: ▲ when it comes your way, ▼
-- when it goes away from you (edged in the new leader's color; grey for a
-- tie: white means "selected"). The biggest moves (by points, then votes) get
-- a signed tag, at most SwingMarks.MOVES of them, fewer when flips took the
-- room; every other moved state only glows.
--
-- Preview (a stance, or a debate move while you pick it; your side only): a
-- state the choice helps glows and is outlined in `good` green, one it hurts in
-- `loss` orange (never a player's color, which the fills already use, so the
-- legend's "Helps you" dot matches what the map shows); the biggest gains carry
-- a green "+1.5"; a state the choice does not move is dimmed.
-- Reveal (a debate round or both stances, after the fact): each moved state
-- glows toward whoever gained (the net points toward you in your color, or
-- toward them in theirs: ownership, not a loss).
-- Step (one move of the week's reveal, D-066): the states the move touched
-- carry their signed points toward you: "+1.5" in your color when it helps
-- you, "−1.5" in orange when it hurts you.
--
--   SwingMarks.preview(view, preview, keep) -> marks
--   SwingMarks.reveal(view, net, flips, keep) -> marks
--   SwingMarks.step(view, net, flips, keep) -> marks
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

SwingMarks.LABELS = 8 -- labels on the map at most (docs/UI-STYLE.md §4.6)
SwingMarks.FLIP_TAGS = 5 -- flips that carry a ▲ / ▼ tag (the biggest by votes)
SwingMarks.MOVES = 5 -- moves that carry their points (the biggest)
SwingMarks.BADGES = SwingMarks.MOVES -- the old name

SwingMarks.UP = "▲" -- a flip your way
SwingMarks.DOWN = "▼" -- a flip away from you

local function evOf(id: string): number
	local record = StateData.byId[id]
	return if record then record.ev else 0
end

-- The `n` states in `points` that moved most (by points, then votes).
local function biggest(
	points: { [string]: number },
	n: number,
	skip: { [string]: boolean }?
): { [string]: boolean }
	local ids: { string } = {}
	for id, value in points do
		if value ~= 0 and not (skip and skip[id]) then
			table.insert(ids, id)
		end
	end
	table.sort(ids, function(a: string, b: string): boolean
		local da, db = math.abs(points[a]), math.abs(points[b])
		if math.abs(da - db) > 1e-9 then
			return da > db
		end
		local ea, eb = evOf(a), evOf(b)
		if ea ~= eb then
			return ea > eb
		end
		return a < b
	end)
	local out: { [string]: boolean } = {}
	for k = 1, math.min(n, #ids) do
		out[ids[k]] = true
	end
	return out
end

-- The flips that carry a tag: the FLIP_TAGS biggest by votes.
local function taggedFlips(flips: { Swing.Flip }): { [string]: boolean }
	local list = table.clone(flips)
	table.sort(list, function(a: Swing.Flip, b: Swing.Flip): boolean
		local ea, eb = evOf(a.state), evOf(b.state)
		if ea ~= eb then
			return ea > eb
		end
		return a.state < b.state
	end)
	local out: { [string]: boolean } = {}
	for k = 1, math.min(SwingMarks.FLIP_TAGS, #list) do
		out[list[k].state] = true
	end
	return out
end

-- ▲ when the state comes your way (you lead now, or a rival lost it to a tie), else ▼.
local function direction(view: View, flip: Swing.Flip): string
	local good = flip.to == view.you or (flip.to == 0 and flip.from ~= view.you)
	return if good then SwingMarks.UP else SwingMarks.DOWN
end

local function base(keep: Marks, id: string): { [string]: any }
	local old = keep[id]
	return { ring = if old then old.ring else nil }
end

local function rivalOf(view: View): number
	return if view.you == 1 then 2 else 1
end

-- Every flip: the strong outline in the new leader's color; the biggest a
-- ▲ / ▼ tag (and no points). Returns the flipped states and how many tags.
local function markFlips(view: View, flips: { Swing.Flip }, marks: Marks): ({ [string]: boolean }, number)
	local tagged = taggedFlips(flips)
	local flipped: { [string]: boolean } = {}
	local tags = 0
	for _, flip in flips do
		local mark = marks[flip.state]
		if mark then
			flipped[flip.state] = true
			local color = if flip.to == 0 then Kit.colors.undecided else Kit.playerColor(view, flip.to)
			mark.badge = nil
			mark.badgeColor = nil
			mark.halo = color
			mark.haloStrong = true
			if tagged[flip.state] then
				mark.note = direction(view, flip)
				mark.noteColor = color
				tags += 1
			end
		end
	end
	return flipped, tags
end

-- A stance (Swing.Preview) or a debate move (Swing's board row): both carry effects and flips.
function SwingMarks.preview(
	view: View,
	preview: { effects: { [string]: number }, flips: { Swing.Flip } },
	keep: Marks
): Marks
	local marks: Marks = {}
	for _, s in view.states do
		local mark = base(keep, s.id)
		local points = preview.effects[s.id]
		if points == nil or points == 0 then
			mark.dim = true
		else
			mark.halo = if points > 0 then Kit.colors.good else Kit.colors.loss
		end
		marks[s.id] = mark
	end
	local flipped, tags = markFlips(view, preview.flips, marks)
	-- Flips here are in the helps / hurts colors too: they are your choice's effect.
	for _, flip in preview.flips do
		local mark = marks[flip.state]
		if mark then
			local good = direction(view, flip) == SwingMarks.UP
			mark.halo = if good then Kit.colors.good else Kit.colors.loss
			if mark.note then
				mark.noteColor = mark.halo
			end
		end
	end
	local gains: { [string]: number } = {}
	for id, points in preview.effects do
		if points > 0 then
			gains[id] = points
		end
	end
	local room = math.min(SwingMarks.MOVES, SwingMarks.LABELS - tags)
	for id in biggest(gains, room, flipped) do
		marks[id].badge = Numbers.signed(gains[id])
		marks[id].badgeColor = Kit.colors.good
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
			mark.halo = if points > 0 then mine else theirs
		end
		marks[s.id] = mark
	end
	local flipped, tags = markFlips(view, flips, marks)
	local room = math.min(SwingMarks.MOVES, SwingMarks.LABELS - tags)
	for id in biggest(net, room, flipped) do
		local points = net[id]
		marks[id].badge = Numbers.signed(points)
		marks[id].badgeColor = if points > 0 then mine else theirs
	end
	return marks
end

function SwingMarks.step(view: View, net: { [string]: number }, flips: { Swing.Flip }, keep: Marks): Marks
	local mine = Kit.playerColor(view, view.you)
	local marks: Marks = {}
	for _, s in view.states do
		local mark = base(keep, s.id)
		local points = net[s.id]
		if points ~= nil and points ~= 0 then
			mark.halo = if points > 0 then mine else Kit.colors.loss
		end
		marks[s.id] = mark
	end
	local flipped, tags = markFlips(view, flips, marks)
	local room = math.min(SwingMarks.MOVES, SwingMarks.LABELS - tags)
	for id in biggest(net, room, flipped) do
		local points = net[id]
		marks[id].badge = Numbers.signed(points)
		marks[id].badgeColor = if points > 0 then mine else Kit.colors.loss
	end
	return marks
end

return SwingMarks
