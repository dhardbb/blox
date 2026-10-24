--!strict
-- The end-of-week reveal as a running tally (D-063): each shown move is followed
-- by its effect on the map and the projected votes, and the last step lands on
-- the real new polls. Pure: works from Config, fixed state data, the player's
-- own Views (the plan-stage one from before the week and the one after) and the
-- public events, and reuses the sim's own formulas read-only (Resolve, Support,
-- Events, Polls), so a rules change flows through without edits here.
--
-- The server never says what one action did: the true change depends on true
-- support, which never leaves the server, and the public polls only come out
-- once, at the end of the week, with fresh poll noise and the momentum drift
-- folded in. So each move's step is an ESTIMATE in public-poll points: the
-- sim's own arithmetic for that action (issue, platform, candidate, battleground,
-- underdog, closing weeks, the event and its cap, the undecided/opponent split),
-- read from the start-of-week public poll in place of true support. Every
-- action reads the snapshot of its own Resolve step (rallies the week's start,
-- ads and attacks after the rallies, pivots after the ads, stances after the
-- pivots), so neither the display order nor the viewer's seat changes any
-- action's number (D-001). The last step, "New polls are in", is whatever is left:
-- momentum drift, the new poll noise, and anything the estimates missed. It
-- moves the map and the score onto exactly the new View's polls and
-- projected votes.
--
-- Steps follow the reveal order (Words.revealFirst: the trailing player's
-- actions first, then the other's, then the settle). A step holds one move
-- that changes support (a rally, an ad, an attack, a backlash, a pivot, a
-- stance) and the events around it that change nothing on the map (flights,
-- fundraisers, money raised, private polls), so the pace goes to what moves.
--
--   RevealSteps.build(config, before?, after, events) -> Tally
--   RevealSteps.viewAt(tally, k) -> View        what the map and score show after step k (0: before the week)
--   RevealSteps.eventsUpTo(tally, k) -> { Event }  the moves shown by step k, in reveal order
--   RevealSteps.lead(step) -> Event?            the event a step is about (its move, else its last event)
--   RevealSteps.margin(view, id) -> number?     your public-poll margin over your best rival

local ConfigModule = require("../Sim/Config")
local Events = require("../Sim/Events")
local Explain = require("./Explain")
local Polls = require("../Sim/Polls")
local Resolve = require("../Sim/Resolve")
local SimState = require("../Sim/State")
local StateData = require("../Sim/StateData")
local Support = require("../Sim/Support")
local Swing = require("./Swing")
local Types = require("../Types")
local ViewModule = require("../Sim/View")
local Words = require("./Words/Reveal")

type Config = ConfigModule.Config
type View = ViewModule.View
type Event = SimState.Event
type Poll = SimState.Poll

local RevealSteps = {}

RevealSteps.MIN_MOVE = 0.05 -- points: a smaller change to a margin is no change (Numbers.signed shows +0.0)
local TIE = 1e-6 -- points: running shares closer than this are a tie

export type Step = {
	kind: "Move" | "Settle",
	player: number?, -- whose step (nil: news, or the settle)
	events: { Event }, -- what the step shows, in order (the settle: the Polls event)
	moving: number?, -- index in `events` of the move that changes support, if any
	net: { [string]: number }, -- this step's change to your margin over your best rival, by state
	flips: { Swing.Flip }, -- states whose poll leader changed at this step
	ev: { number }, -- projected votes after this step, by player
}

export type Tally = {
	before: View?, -- the plan-stage View from before the week (nil: unknown, nothing is estimated)
	after: View,
	first: number, -- whose moves come first (Words.revealFirst)
	trails: boolean,
	steps: { Step }, -- the last one is the settle
	views: { View }, -- views[k]: after step k (views[#steps] is `after`)
}

-- A state's shares as the estimates work on them: a public poll, with
-- fractional points once a move lands on it.
type Shares = { support: { number }, undecided: number }
-- One move's requested change per state index, against its step's snapshot.
type Delta = { [number]: { delta: { number }, du: number } }

local function sharesOf(view: View): { Shares? }
	local out: { Shares? } = {}
	for i, s in view.states do
		local poll = s.poll
		out[i] = if poll then { support = table.clone(poll.support), undecided = poll.undecided } else nil
	end
	return out
end

-- `base` with the deltas applied (each state once, Support.apply's clamp and
-- rescale). States no delta touches keep the same tables.
local function applied(base: { Shares? }, deltas: { Delta }): { Shares? }
	local sum: { [number]: { delta: { number }, du: number } } = {}
	for _, delta in deltas do
		for i, entry in delta do
			local row = sum[i]
			if row == nil then
				row = { delta = table.create(#entry.delta, 0), du = 0 }
				sum[i] = row
			end
			for p, d in entry.delta do
				row.delta[p] += d
			end
			row.du += entry.du
		end
	end
	local out = table.clone(base)
	for i, row in sum do
		local shares = base[i]
		if shares then
			local copy = { support = table.clone(shares.support), undecided = shares.undecided }
			Support.apply(copy :: any, row.delta, row.du)
			out[i] = copy
		end
	end
	return out
end

local function slot(delta: Delta, i: number, n: number): { delta: { number }, du: number }
	local entry = delta[i]
	if entry == nil then
		entry = { delta = table.create(n, 0), du = 0 }
		delta[i] = entry
	end
	return entry
end

local function platformOf(view: View, p: number): { Types.Issue }
	local player = view.players[p]
	return if player and player.platform then player.platform else {}
end

-- Polls.underdogMults reads only the player's tier and profile (as in Explain).
local function underdogRally(config: Config, view: View, p: number): number
	local players = {}
	players[p] = { underdogTier = view.players[p].underdogTier, profile = Explain.profileOf(config, view, p) }
	local rally = Polls.underdogMults(config, { players = players } :: any, p)
	return rally
end

local function effectOf(view: View): Events.Effect?
	local event = view.event
	if event == nil then
		return nil
	end
	return { kind = event.kind, issue = event.issue, region = event.region }
end

-- The rival an attack hits: in 1v1 the other player; with more, the strongest
-- other player in the state (the public event does not name the target).
local function targetOf(shares: Shares, p: number): number
	local best, target = -math.huge, 0
	for q, share in shares.support do
		if q ~= p and share > best then
			best, target = share, q
		end
	end
	return target
end

-- The Choice result this week resolved, from the View after it.
local function choiceOf(before: View, after: View): SimState.EventResult?
	for _, result in after.eventLog do
		if result.week == before.week and result.moves ~= nil then
			return result
		end
	end
	return nil
end

-- Each moving event's requested change, by its index in `events`, in Resolve's
-- order and from Resolve's snapshots (see the header).
local function estimate(
	config: Config,
	before: View,
	after: View,
	events: { Event }
): ({ [number]: Delta }, { [number]: number })
	local n = #before.players
	local out: { [number]: Delta } = {}
	local phases: { [number]: number } = {} -- 1 rallies, 2 ads and attacks, 3 pivots, 4 stances
	local effect = effectOf(before)
	local closing = Resolve.closingMult(config, before.week)
	local ledger: Events.Ledger = {}

	-- Rallies: all from the week's start.
	local start = sharesOf(before)
	local rallies: { Delta } = {}
	for k, event in events do
		local p, id = event.player, event.state
		if event.kind == "Rally" and p and id and event.issue and before.players[p] then
			local i = SimState.indexOf[id]
			local s = start[i]
			if i and s then
				local profile = Explain.profileOf(config, before, p)
				local issue: Types.Issue = event.issue :: any
				local mult = Resolve.issueMult(
					config,
					platformOf(before, p),
					before.issueMap[i],
					issue,
					before.platformMults
				) * profile.rallyMult * (if before.states[i].battleground
					then config.BATTLEGROUND_MULT
					else 1) * underdogRally(config, before, p) * (if before.players[p].frontrunner
					then profile.frontrunnerRallyMult
					else 1) * closing
				local gain = profile.rallySupport * mult * Support.saturation(config, s.support[p])
				local eventMult = Events.supportMult(config, effect, "Rally", issue, i)
				gain += Events.grant(config, ledger, i, p, gain * (eventMult - 1))
				local delta: Delta = {}
				local entry = slot(delta, i, n)
				entry.du += Support.addGain(config, s :: any, p, gain, entry.delta)
				out[k] = delta
				phases[k] = 1
				table.insert(rallies, delta)
			end
		end
	end

	-- Ads, attacks and backlash: after the rallies.
	local afterRallies = applied(start, rallies)
	local media: { Delta } = {}
	local bought: { [number]: { [number]: number } } = {}
	for k, event in events do
		local p, id = event.player, event.state
		local kind = event.kind
		if (kind == "Media" or kind == "Attack" or kind == "Backlash") and p and id and before.players[p] then
			local i = SimState.indexOf[id]
			local s = afterRallies[i]
			if i and s then
				local profile = Explain.profileOf(config, before, p)
				local delta: Delta = {}
				local entry = slot(delta, i, n)
				if kind == "Backlash" then
					entry.du += Support.addLoss(p, config.BACKLASH_PENALTY, entry.delta)
				elseif event.issue then
					local issue: Types.Issue = event.issue :: any
					local mine = bought[p] or {}
					bought[p] = mine
					local count = (mine[i] or 0) + 1
					mine[i] = count
					local common = profile.mediaMult
						* (if before.states[i].battleground then config.BATTLEGROUND_MULT else 1)
						* closing
						* profile.mediaSaturation ^ (count - 1)
					if kind == "Attack" then
						local target = targetOf(s, p)
						if target > 0 then
							local mult = Resolve.attackMult(
								config,
								platformOf(before, target),
								before.issueMap[i],
								issue
							)
							entry.du += Support.addAttack(
								config,
								p,
								target,
								config.ATTACK_LOSS * mult * common,
								entry.delta
							)
						end
					else
						local mult = Resolve.issueMult(
							config,
							platformOf(before, p),
							before.issueMap[i],
							issue,
							before.platformMults
						)
						local gain = config.MEDIA_SUPPORT
							* mult
							* common
							* Support.saturation(config, s.support[p])
						local eventMult = Events.supportMult(config, effect, "Media", issue, i)
						gain += Events.grant(config, ledger, i, p, gain * (eventMult - 1))
						entry.du += Support.addGain(config, s :: any, p, gain, entry.delta)
					end
				end
				out[k] = delta
				phases[k] = 2
				table.insert(media, delta)
			end
		end
	end

	-- Pivots: a national loss, after the ads (every state needs a poll for its weight).
	local afterMedia = applied(afterRallies, media)
	local pivots: { Delta } = {}
	local complete = #afterMedia == #StateData.list
	for i = 1, #StateData.list do
		complete = complete and afterMedia[i] ~= nil
	end
	for k, event in events do
		local p = event.player
		if event.kind == "Pivot" and p and before.players[p] and complete then
			local copies = {}
			for i, shares in afterMedia do
				local s = shares :: Shares
				copies[i] = { support = table.clone(s.support), undecided = s.undecided }
			end
			local xs = table.create(n, 0)
			xs[p] = -config.PIVOT_PENALTY
			Support.national(config, copies :: any, xs)
			local delta: Delta = {}
			for i, copy in copies do
				local s = afterMedia[i] :: Shares
				local entry = slot(delta, i, n)
				for q = 1, n do
					entry.delta[q] = copy.support[q] - s.support[q]
				end
				entry.du = copy.undecided - s.undecided
			end
			out[k] = delta
			phases[k] = 3
			table.insert(pivots, delta)
		end
	end

	-- Stances: the points each one asked for (public), after the pivots.
	local result = choiceOf(before, after)
	local afterPivots = applied(afterMedia, pivots)
	for k, event in events do
		local p = event.player
		if event.kind == "Choice" and p and result and result.moves then
			local delta: Delta = {}
			local any = false
			for _, move in result.moves do
				local i = SimState.indexOf[move.state]
				local s = if i then afterPivots[i] else nil
				local points = move.points[p] or 0
				if i and s and points ~= 0 then
					local entry = slot(delta, i, n)
					if points > 0 then
						entry.du += Support.addGain(config, s :: any, p, points, entry.delta)
					else
						entry.du += Support.addLoss(p, -points, entry.delta)
					end
					any = true
				end
			end
			if any then
				out[k] = delta
				phases[k] = 4
			end
		end
	end
	return out, phases
end

-- `start` with the shown moves applied phase by phase, the way Resolve flushes
-- each of its steps (so a clamp lands where it does in the sim).
local function chain(start: { Shares? }, byPhase: { { Delta } }): { Shares? }
	local shares = start
	for _, list in byPhase do
		if #list > 0 then
			shares = applied(shares, list)
		end
	end
	return shares
end

-- The outright leader of some shares, 0 on a tie (within TIE).
local function leaderOf(support: { number }): number
	local best, second, leader = -math.huge, -math.huge, 0
	for p, share in support do
		if share > best then
			second, best, leader = best, share, p
		elseif share > second then
			second = share
		end
	end
	if best - second < TIE then
		return 0
	end
	return leader
end

local function marginIn(support: { number }, you: number): number
	local best = -math.huge
	for p, share in support do
		if p ~= you and share > best then
			best = share
		end
	end
	return (support[you] or 0) - (if best == -math.huge then 0 else best)
end

-- Your public-poll margin over your best rival in state `id`, nil without a poll.
function RevealSteps.margin(view: View, id: string): number?
	local i = SimState.indexOf[id]
	local s = if i then view.states[i] else nil
	if s == nil or s.poll == nil then
		return nil
	end
	return marginIn(s.poll.support, view.you)
end

local function evFrom(shares: { Shares? }, players: number): { number }
	local ev = table.create(players, 0)
	for i, s in shares do
		if s then
			local leader = leaderOf(s.support)
			if leader > 0 then
				ev[leader] += StateData.list[i].ev
			end
		end
	end
	return ev
end

-- The change between two sets of shares, as your margin (net) and leader changes.
local function compare(
	view: View,
	from: { Shares? },
	to: { Shares? },
	only: { [number]: boolean }?
): ({ [string]: number }, { Swing.Flip })
	local net: { [string]: number } = {}
	local flips: { Swing.Flip } = {}
	for i, record in ipairs(StateData.list) do
		if only and not only[i] then
			continue
		end
		local a, b = from[i], to[i]
		if a and b and a ~= b then
			local d = marginIn(b.support, view.you) - marginIn(a.support, view.you)
			if math.abs(d) >= RevealSteps.MIN_MOVE then
				net[record.id] = d
			end
			local was, now = leaderOf(a.support), leaderOf(b.support)
			if was ~= now then
				table.insert(flips, { state = record.id, from = was, to = now, ev = record.ev })
			end
		end
	end
	table.sort(flips, function(x: Swing.Flip, y: Swing.Flip): boolean
		if x.ev ~= y.ev then
			return x.ev > y.ev
		end
		return x.state < y.state
	end)
	return net, flips
end

-- `base` showing `shares` and `ev`: the same View with new polls (in the states
-- whose shares are no longer `start`'s) and score.
local function viewWith(base: View, start: { Shares? }, shares: { Shares? }, ev: { number }): View
	local view = table.clone(base)
	local states = table.clone(base.states)
	for i, s in base.states do
		local now = shares[i]
		if now and s.poll and now ~= start[i] then
			local copy = table.clone(s)
			copy.poll = { support = now.support, undecided = now.undecided }
			states[i] = copy
		end
	end
	view.states = states
	view.projectedEV = ev
	return view
end

function RevealSteps.build(config: Config, before: View?, after: View, events: { Event }): Tally
	local first, trails = Words.revealFirst(before or after)
	-- The reveal order: news, the first player's events, everyone else's, then the polls.
	local news: { number } = {}
	local firsts: { number } = {}
	local seconds: { number } = {}
	for k, event in events do
		if Words.shows(event) then
			if event.player == nil then
				table.insert(news, k)
			elseif event.player == first then
				table.insert(firsts, k)
			else
				table.insert(seconds, k)
			end
		end
	end
	local order: { number } = {}
	for _, list in { news, firsts, seconds } do
		for _, k in list do
			table.insert(order, k)
		end
	end

	local deltas: { [number]: Delta } = {}
	local phases: { [number]: number } = {}
	if before then
		deltas, phases = estimate(config, before, after, events)
	end
	local function moves(k: number): boolean
		local delta = deltas[k]
		return delta ~= nil and next(delta) ~= nil
	end

	-- Group into steps: one move each, with the still events around it.
	type Draft = { player: number?, keys: { number }, moving: number? }
	local drafts: { Draft } = {}
	local current: Draft? = nil
	for _, k in order do
		local player = events[k].player
		local moving = moves(k)
		local draft: Draft
		local open = current
		if open == nil or open.player ~= player or (moving and open.moving ~= nil) then
			draft = { player = player, keys = {}, moving = nil }
			table.insert(drafts, draft)
			current = draft
		else
			draft = open
		end
		table.insert(draft.keys, k)
		if moving then
			draft.moving = #draft.keys
		end
	end

	local steps: { Step } = {}
	local views: { View } = {}
	local base = before or after
	local players = #after.players
	local start = if before then sharesOf(before) else sharesOf(after)
	local shown: { { Delta } } = { {}, {}, {}, {} } -- the moves shown so far, by Resolve phase
	local running = start
	for _, draft in drafts do
		local list: { Event } = {}
		local touched: { [number]: boolean } = {}
		for _, k in draft.keys do
			table.insert(list, events[k])
			local delta = deltas[k]
			if delta then
				table.insert(shown[phases[k]], delta)
				for i in delta do
					touched[i] = true
				end
			end
		end
		local nextShares = if next(touched) ~= nil then chain(start, shown) else running
		local net, flips = compare(after, running, nextShares, touched)
		local ev = if before then evFrom(nextShares, players) else table.clone(after.projectedEV)
		table.insert(steps, {
			kind = "Move",
			player = draft.player,
			events = list,
			moving = draft.moving,
			net = net,
			flips = flips,
			ev = ev,
		})
		table.insert(views, if before then viewWith(base, start, nextShares, ev) else after)
		running = nextShares
	end

	-- The settle: the real new polls, whatever the moves did not explain.
	local polls: { Event } = {}
	for _, event in events do
		if event.kind == "Polls" then
			table.insert(polls, event)
		end
	end
	if #polls == 0 then
		table.insert(polls, { kind = "Polls" })
	end
	local final = sharesOf(after)
	local net, flips = compare(after, running, final, nil)
	if before == nil then
		net, flips = {}, {}
	end
	table.insert(steps, {
		kind = "Settle",
		player = nil,
		events = polls,
		moving = nil,
		net = net,
		flips = flips,
		ev = table.clone(after.projectedEV),
	})
	table.insert(views, after)
	return {
		before = before,
		after = after,
		first = first,
		trails = trails,
		steps = steps,
		views = views,
	}
end

-- What the map and the score show after step k: 0 is the week's start (the
-- plan-stage View), #steps (or more) the new View.
function RevealSteps.viewAt(tally: Tally, k: number): View
	if k <= 0 then
		return tally.before or tally.after
	end
	return tally.views[math.min(k, #tally.views)]
end

-- The moves shown by step k (the settle's Polls event left out), in reveal order.
function RevealSteps.eventsUpTo(tally: Tally, k: number): { Event }
	local out: { Event } = {}
	for j = 1, math.min(k, #tally.steps) do
		local step = tally.steps[j]
		if step.kind == "Move" then
			for _, event in step.events do
				table.insert(out, event)
			end
		end
	end
	return out
end

-- The event a step is about: its move, else its last event.
function RevealSteps.lead(step: Step): Event?
	local k = step.moving or #step.events
	return step.events[k]
end

return table.freeze(RevealSteps)
