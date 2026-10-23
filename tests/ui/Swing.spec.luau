--!strict
-- Shared/UI/Swing (D-042): what a stance or a debate moves, in words. The
-- previews must be the sim's own public arithmetic (Events.stanceEffects,
-- Polls.projectFlips, Debate.topicStates) on the player's own View, and "states
-- you need" must come from the public poll only.

local Config = require("@sim/Config")
local Debate = require("@sim/Debate")
local Events = require("@sim/Events")
local Fixtures = require("@ui/Fixtures")
local State = require("@sim/State")
local StateData = require("@sim/StateData")
local Swing = require("@ui/Swing")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function check(condition: boolean, message: string)
	if not condition then
		error(message, 0)
	end
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

local cache: { [string]: any } = {}
local function viewAt(moment: string): any
	if cache[moment] == nil then
		cache[moment] = Fixtures.payload(C, moment :: any)
	end
	-- Each test edits its own copy.
	return State.deepCopy(cache[moment].view) :: any
end

local function setPoll(view: any, id: string, mine: number, theirs: number)
	local you, them = view.you, 3 - view.you
	local support = { 0, 0 }
	support[you], support[them] = mine, theirs
	view.states[State.indexOf[id]].poll = { support = support, undecided = 100 - mine - theirs }
end

-- Every state far from close, so a test decides exactly which ones are in play.
local function calm(view: any)
	for _, s in view.states do
		setPoll(view, s.id, 60, 30)
	end
end

local function effects(view: any, id: string): { [string]: number }
	local me = view.players[view.you]
	return Events.stanceEffects(
		C,
		view.issueMap,
		Events.byId[view.event.id],
		id :: any,
		me.platform,
		Events.baseOf(me)
	)
end

-- A stance with at least one gain and one loss state, and those states. Each is
-- worth more than a point, so a one-point poll gap flips rather than ties.
local function splitStance(view: any): (string, string, string)
	for _, id in { "A", "B" } do
		local gain, loss = nil, nil
		for _, record in StateData.list do
			local points = effects(view, id)[record.id]
			if points and points > 1 and gain == nil then
				gain = record.id
			elseif points and points < -1 and loss == nil then
				loss = record.id
			end
		end
		if gain and loss then
			return id, gain, loss
		end
	end
	error("no stance with a big gain and a big loss")
end

describe("Swing: states you need", function()
	it("counts a state as in play within CLOSE points of the public poll, either way", function()
		local view = viewAt("ChoiceWeek")
		calm(view)
		setPoll(view, "OH", 40, 40 + Swing.CLOSE)
		setPoll(view, "PA", 44, 40)
		setPoll(view, "MI", 30, 31 + Swing.CLOSE)
		local ids = {}
		for _, entry in Swing.inPlay(view) do
			table.insert(ids, entry.state)
		end
		expect(ids):toEqual({ "PA", "OH" })
		expect(Swing.margin(view, "OH")):toBe(-Swing.CLOSE)
		local text = Swing.needText(C, view)
		check(has(text, `within {Swing.CLOSE} points`), text)
		check(has(text, `you trail OH by {Swing.CLOSE}`), text)
		check(has(text, "you lead PA by 4"), text)
		check(has(text, `You project {view.projectedEV[view.you]} EV`), text)
	end)
end)

describe("Swing: stance previews", function()
	it("splits the sim's own per-state effects into gains and losses", function()
		local view = viewAt("ChoiceWeek")
		for _, id in Events.CHOICES do
			local preview = Swing.stance(C, view, id)
			local want = effects(view, id)
			expect(preview.effects):toEqual(want)
			local gain, loss, n = 0, 0, 0
			for _, points in want do
				n += 1
				if points > 0 then
					gain += points
				else
					loss += points
				end
			end
			expect(#preview.gains + #preview.losses):toBe(n)
			expect(preview.gainTotal):toBeCloseTo(gain, 1e-9)
			expect(preview.lossTotal):toBeCloseTo(loss, 1e-9)
		end
		-- The hedge gains nowhere; it only costs in the taker's base states with the issue.
		local hedge = Swing.stance(C, view, "C")
		expect(hedge.hedge):toBe(true)
		expect(#hedge.gains):toBe(0)
		local base = Events.baseOf(view.players[view.you])
		for _, state in hedge.losses do
			expect(table.find(base, state) ~= nil):toBe(true)
		end
		expect(#hedge.losses <= #base):toBe(true)
	end)

	it("names the gains you need, the leads you risk and the leader flips", function()
		local view = viewAt("ChoiceWeek")
		calm(view)
		local id, gain, loss = splitStance(view)
		-- You trail the gain state by 1 and lead the loss state by 1: both flip.
		setPoll(view, gain, 40, 41)
		setPoll(view, loss, 41, 40)
		local preview = Swing.stance(C, view, id :: any)
		expect(preview.needed):toEqual({ gain })
		expect(preview.leadsHurt[1]):toBe(loss)
		local flipped: { [string]: any } = {}
		for _, flip in preview.flips do
			flipped[flip.state] = flip
		end
		check(flipped[gain] ~= nil and flipped[gain].to == view.you, "the gain state does not flip to you")
		check(flipped[loss] ~= nil and flipped[loss].from == view.you, "the lead is not lost")
		local text = Swing.stanceSummary(C, view, preview)
		check(has(text, `Stance {id} · {preview.name}:`), text)
		check(has(text, `1 you need: {gain}`), text)
		check(has(text, `you lead: {loss} by 1`), text)
		check(has(text, `flip {gain} (+{StateData.byId[gain].ev} EV)`), text)
		check(has(text, `lose {loss} (-{StateData.byId[loss].ev} EV)`), text)
	end)

	it("labels the hedge and says when nothing flips", function()
		local view = viewAt("ChoiceWeek")
		calm(view)
		local text = Swing.stanceSummary(C, view, Swing.stance(C, view, "C"))
		check(has(text, "(the hedge)"), text)
		check(has(text, "no poll leader would change"), text)
		-- Nothing to gain; the only cost is the hedge's, in your own base.
		local preview = Swing.stance(C, view, "C")
		expect(#preview.gains):toBe(0)
		expect(preview.flips):toEqual({})
		if #preview.losses == 0 then
			check(has(text, "no state loses"), text)
		else
			check(
				has(text, `{string.format("%+.1f", preview.lossTotal)} total over {#preview.losses} state`),
				text
			)
		end
	end)
end)

describe("Swing: debates", function()
	it("says which states each topic swung and credits every flip once", function()
		local view = viewAt("Debate")
		local result = view.debates[#view.debates]
		local credited: { [string]: number } = {}
		for t, topic in result.topics do
			local entry = Swing.debateTopic(C, view, result, t)
			expect(#entry.states):toBe(#Debate.topicStates(view.issueMap, topic))
			if entry.winner == view.you then
				check(has(entry.line, "Your "), entry.line)
				check(has(entry.line, `win swung {entry.states[1]}`), entry.line)
				check(has(entry.line, `{string.format("%+.1f", C.DEBATE_TOPIC_WIN)} each`), entry.line)
			elseif entry.winner == 0 then
				check(has(entry.line, "tie"), entry.line)
			end
			for _, flip in entry.flips do
				credited[flip.state] = (credited[flip.state] or 0) + 1
				check(has(entry.line, Swing.flipPhrase(view, flip)), entry.line)
			end
		end
		for _, flip in Swing.debateOther(view, result) do
			credited[flip.state] = (credited[flip.state] or 0) + 1
		end
		for _, flip in result.flips do
			expect(credited[flip.state]):toBe(1)
		end
	end)

	it("writes gaffes as a loss in the topic's states", function()
		local view = viewAt("Debate")
		local result = view.debates[#view.debates]
		result.gaffes[view.you][1] = true
		local entry = Swing.debateTopic(C, view, result, 1)
		check(
			has(entry.gaffeLines[1], `Your gaffe on`)
				and has(entry.gaffeLines[1], `{string.format("%+.1f", -C.DEBATE_GAFFE)} in {entry.states[1]}`),
			entry.gaffeLines[1]
		)
	end)

	it("phrases a flip from your side", function()
		local view = viewAt("Debate")
		local you, them = view.you, 3 - view.you
		expect(Swing.flipPhrase(view, { state = "PA", from = them, to = you, ev = 19 })):toBe(
			"PA flipped to you (+19 EV)"
		)
		expect(Swing.flipPhrase(view, { state = "WI", from = you, to = them, ev = 10 })):toBe(
			"WI flipped to them (10 EV)"
		)
		expect(Swing.flipPhrase(view, { state = "NV", from = you, to = 0, ev = 6 })):toBe(
			"NV slipped from you to a tie (-6 EV)"
		)
	end)
end)

describe("Swing: resolved Choice weeks and the result", function()
	it("writes both stances and the flips of a resolved Choice week", function()
		local view = viewAt("ChoiceWeek")
		local you, them = view.you, 3 - view.you
		local row = function(mine: number, theirs: number): { number }
			local out = { 0, 0 }
			out[you], out[them] = mine, theirs
			return out
		end
		local entry: any = {
			week = view.week,
			id = view.event.id,
			choices = row(1, 2),
			moves = {
				{ state = "OH", points = row(1.5, -1.5) },
				{ state = "PA", points = row(-1.5, 1.5) },
				{ state = "MI", points = row(0.5, 0) },
			},
			flips = { { state = "OH", from = them, to = you } },
		}
		entry.choices[you], entry.choices[them] = "A", "B"
		local lines = Swing.choiceLines(C, view, entry)
		local stanceA = Events.stance(Events.byId[view.event.id], "A") :: any
		expect(lines[1]):toBe(
			`You took A · {stanceA.name}: +2.0 total over 2 states, -1.5 total over 1 state.`
		)
		check(has(lines[2], "They took B"), lines[2])
		expect(lines[3]):toBe(`On the polls you both saw, the stances flipped: OH flipped to you (+17 EV).`)
		expect(Swing.net(entry.moves, view)):toEqual({ OH = 3, PA = -3, MI = 0.5 })
	end)

	it("sums what debates and stances flipped on the Results screen", function()
		local view = viewAt("Over")
		local lines = Swing.decided(C, view)
		check(has(lines[1], "Debates: "), lines[1])
		check(has(lines[2], "Choice stances: "), lines[2])
		local toYou = 0
		for _, result in view.debates do
			for _, flip in result.flips do
				if flip.to == view.you then
					toYou += StateData.byId[flip.state].ev
				end
			end
		end
		if toYou > 0 then
			check(has(lines[1], `flipped to you (+{toYou} EV)`), lines[1])
		end
		check(has(lines[3], "Final gap: "), lines[3])
	end)
end)

describe("Swing: the debate focus (D-044)", function()
	it("lists a topic's states and EV, the ones you need, and the odds a focus gives", function()
		local view = viewAt("Focus")
		expect(view.decision):toBe("Focus")
		calm(view)
		local topics = view.nextDebate.topics
		local topic = topics[1]
		local states = Debate.topicStates(view.issueMap, topic)
		local need, needEV = states[1], StateData.byId[states[1]].ev
		setPoll(view, need, 40, 40)
		local info = Swing.focus(C, view, topic)
		local total = 0
		for _, id in states do
			total += StateData.byId[id].ev
		end
		expect(info.ev):toBe(total)
		expect(#info.states):toBe(#states)
		expect(#info.need):toBe(1)
		expect(info.needEV):toBe(needEV)
		check(has(info.head, `{#states} states, {total} EV`), info.head)
		check(has(info.needLine, `You need 1 of them ({needEV} EV): tied {need}`), info.needLine)
		-- The odds: your focus edge on top of platform and stat, against theirs without a focus.
		expect(info.mine - info.theirs >= info.edge - 2 * C.DEBATE_PLATFORM_BONUS):toBe(true)
		check(info.win > info.winBoth, "their focus on the same topic cancels yours")
		check(has(info.oddsLine, "You win"), info.oddsLine)
		-- The map preview: a win's points in every one of its states, and the flip it makes.
		expect(info.effects[need]):toBe(C.DEBATE_TOPIC_WIN)
		expect(#info.flips):toBe(1)
		expect(info.flips[1].state):toBe(need)
		check(has(info.winLine, `could flip {need}`), info.winLine)
		-- Nothing close: nothing needed.
		calm(view)
		check(has(Swing.focus(C, view, topic).needLine, "You need none of them"), "no need")
	end)
end)
