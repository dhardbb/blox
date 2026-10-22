--!strict
-- Turns a State payload (or lobby status) into plain text for the Phase 2 debug
-- UI. Reads only what the server sent, which is only the player's own View.

local Candidates = require("../Sim/Candidates")
local Config = require("../Sim/Config")
local Events = require("../Sim/Events")
local Issues = require("../Sim/Issues")
local StateData = require("../Sim/StateData")
local Colors = require("../UI/Colors")
local Drafted = require("../UI/Drafted")
local Explain = require("../UI/Explain")
local Numbers = require("../UI/Numbers")
local PlanDraft = require("../UI/PlanDraft")
local Profile = require("../Net/Profile")
local View = require("../Sim/View")
local Remotes = require("../Net/Remotes")
local Session = require("../Net/Session")
local State = require("../Sim/State")
local Swing = require("../UI/Swing")
local Types = require("../Types")

local Format = {}

local CLOSEST = 14 -- states listed in the board summary

local function name(candidate: string?): string
	if candidate == nil then
		return "?"
	end
	return Candidates.profile(Config.defaults, candidate).name
end

local function secondsLeft(deadline: number, now: number): number
	return math.max(0, math.ceil(deadline - now))
end

-- "Rating 1032 (12-7)" for the lobby line.
function Format.profile(profile: Profile.Summary): string
	return `Rating {profile.rating} ({profile.wins}-{profile.losses})`
end

-- "Rating 1032 → 1048" after a rated match.
function Format.ratingChange(change: Remotes.RatingChange): string
	return `Rating {change.before} → {change.after}`
end

-- One-line status for the top bar: the match while one is running, else the lobby.
function Format.status(payload: Session.StatePayload?, lobby: Remotes.LobbyStatus?, now: number): string
	if payload == nil or payload.stage == "Over" then
		if lobby == nil then
			return "Connecting..."
		end
		local text = `Lobby: {lobby.state}`
		if lobby.code then
			text ..= ` · your code {lobby.code} (the other player types: join {lobby.code})`
		end
		if lobby.profile then
			text ..= ` · {Format.profile(lobby.profile)}`
		end
		text ..= ` · {lobby.queued} in queue`
		if lobby.full then
			text ..= " · server full"
		end
		return text
	end
	local view = payload.view
	local me = view.players[payload.you]
	local label = view.phase
	if payload.reveal == "Draft" then
		label = "Draft"
	elseif view.phase == "Plan" or view.phase == "Debate" then
		label = `Week {view.week} {view.phase}`
	elseif view.phase == "Draft" then
		label =
			`Draft round {view.draftRound + 1} ({view.draftKind or ""}, priority P{view.draftPriority or 0})`
	end
	local stage = payload.stage :: string
	if payload.reveal then
		stage = payload.reveal :: string
	end
	local locked = payload.seats[payload.you].locked
	local text = `{payload.matchId} · {label} · {stage} · {secondsLeft(payload.deadline, now)}s`
	if payload.stage == "Input" then
		text ..= if locked then " · LOCKED" else " · your move"
	end
	if me.cash then
		text ..= ` · {Numbers.money(me.cash)}`
	end
	return text
end

local function marginText(poll: { support: { number }, undecided: number }?, you: number): (string, number)
	if poll == nil then
		return "no poll", 0
	end
	local them = if you == 1 then 2 else 1
	local m = poll.support[you] - poll.support[them]
	return string.format("%2d-%2d u%2d", poll.support[you], poll.support[them], poll.undecided), m
end

-- One line describing a weekly event and what it does.
function Format.event(event: View.EventView): string
	local C = Config.defaults
	local rule
	if event.kind == "Spotlight" then
		local issue: Types.Issue? = event.issue
		rule = string.format(
			"Spotlight: rallies and ads on %s x%.1f, max +%g per state",
			if issue then Issues.displayName[issue] else "?",
			C.EVENT_SPOTLIGHT_MULT,
			C.EVENT_CAP
		)
	elseif event.kind == "Regional" then
		local region: Types.Region? = event.region
		rule = string.format(
			"Regional: rallies in %s x%.1f, max +%g per state",
			if region then Issues.regionName[region] else "?",
			C.EVENT_REGIONAL_MULT,
			C.EVENT_CAP
		)
	elseif event.kind == "Windfall" then
		rule = string.format(
			"Windfall: fundraisers x%.1f where you trail in the poll, max +$%g per state",
			C.EVENT_WINDFALL_MULT,
			C.EVENT_CAP
		)
	else
		rule = 'Choice: add "choice a|b|c" to your plan (default c, the hedge)'
	end
	return `{event.name} ({rule}). {event.text}`
end

local PICK_NOUN: { [string]: string } = { Home = "home", Stronghold = "stronghold" }

-- "P1 (you)" or "P2".
local function seatName(p: number?, you: number): string
	if p == nil then
		return "?"
	end
	return if p == you then `P{p} (you)` else `P{p}`
end

local function plural(n: number, word: string): string
	return `{n} {word}{if n == 1 then "" else "s"}`
end

-- One server event as a short line, or nil for events with nothing to say. The
-- list comes from the payload, which only holds what this player may see
-- (View.events): public events plus their own private ones.
function Format.eventLine(event: State.Event, you: number): string?
	local kind = event.kind
	local who = seatName(event.player, you)
	local where = event.state or "?"
	local issue = event.issue or "?"
	local amount = event.amount or 0
	if kind == "Pick" then
		if issue == "Nominate" then
			return `{who} nominated {where} (battleground)`
		end
		return `{who} picked {where} ({PICK_NOUN[issue] or string.lower(issue)})`
	elseif kind == "Rally" then
		return `{who} rallied in {where} on {issue}`
	elseif kind == "Fundraise" then
		return `{who} held a fundraiser in {where}`
	elseif kind == "Media" then
		return `{who} ran an ad in {where} on {issue}`
	elseif kind == "Attack" then
		return `{who} ran an attack ad in {where} on {issue}`
	elseif kind == "Backlash" then
		return `backlash for {who} in {where}`
	elseif kind == "Pivot" then
		return `{who} pivoted the platform to {issue}`
	elseif kind == "Flights" then
		return `{who} took {plural(amount, "flight")}`
	elseif kind == "Raised" then
		return `you raised {Numbers.money(amount)}`
	elseif kind == "InternalPolls" then
		return `your {plural(amount, "internal poll")} came back`
	elseif kind == "Choice" then
		return `{who} took stance {issue} ({Numbers.signed(amount)} points in all over the states it moved)`
	elseif kind == "DebateTopic" then
		if event.player == nil or event.player == 0 then
			return `debate: {issue} tied`
		end
		return `debate: {who} won {issue}`
	elseif kind == "PollFlip" then
		if event.player == nil or event.player == 0 then
			return `{where} is now tied in the polls after the {string.lower(issue)}`
		end
		return `{where} flips to {who} in the polls after the {string.lower(issue)} ({amount} EV)`
	elseif kind == "Polls" then
		return "new public polls"
	elseif kind == "Selected" then
		return nil
	end
	return kind
end

-- Every event line of a payload's event list, in order.
function Format.events(events: { State.Event }, you: number): { string }
	local out = {}
	for _, event in events do
		local line = Format.eventLine(event, you)
		if line then
			table.insert(out, line)
		end
	end
	return out
end

-- One resolved debate: who won each topic, both preps, and the national points.
function Format.debate(debate: State.DebateResult, you: number): string
	local them = if you == 1 then 2 else 1
	local parts = {}
	for t, topic in debate.topics do
		local w = debate.winners[t]
		local prep = `{debate.prep[you][t]}/{debate.prep[them][t]}`
		table.insert(
			parts,
			`{topic} {if w == you then "you" elseif w == 0 then "tie" else "them"} (prep {prep})`
		)
	end
	return `Debate week {debate.week}: {table.concat(parts, ", ")}; national {Numbers.signed(
		debate.national[you] or 0
	)} you, {Numbers.signed(debate.national[them] or 0)} them`
end

-- Short tags for one state in the board list: "BG", "home P1", "SH P2", a
-- nominated stronghold as "SH P2 nominated" (it lost its bonus), the lean from
-- your side ("leans you +4"), gotv.
function Format.stateTags(s: View.StateView, you: number): { string }
	local tags = {}
	if s.battleground then
		table.insert(tags, "BG")
	end
	if s.owner then
		if s.isHome then
			table.insert(tags, `home P{s.owner}`)
		elseif s.battleground then
			table.insert(tags, `SH P{s.owner} nominated`)
		else
			table.insert(tags, `SH P{s.owner}`)
		end
	end
	if s.leanTo then
		table.insert(tags, `leans {if s.leanTo == you then "you" else "them"} +{s.lean}`)
	end
	if s.gotv > 0 then
		table.insert(tags, `gotv {s.gotv}`)
	end
	return tags
end

-- The full board summary.
function Format.board(payload: Session.StatePayload, now: number, rating: Remotes.RatingChange?): string
	local view = payload.view
	local you = payload.you
	local them = if you == 1 then 2 else 1
	local lines = {}
	local function add(text: string)
		table.insert(lines, text)
	end

	for p, player in view.players do
		local seat = payload.seats[p]
		local who = if p == you then "YOU" else "OPP"
		local text = string.format(
			"%s P%d %s (%s)  %s  home %s",
			who,
			p,
			name(player.candidate),
			player.color or "?",
			if player.cash then Numbers.money(player.cash) else `money {player.money}`,
			player.home or "-"
		)
		if player.platform then
			text ..= `  platform {table.concat(player.platform, "/")}`
		end
		local tier = Explain.underdogText(Config.defaults, view, p)
		if tier then
			text ..= `  {tier}`
		end
		if not seat.connected then
			text ..= string.format("  DISCONNECTED (grace %ds)", secondsLeft(seat.graceUntil or now, now))
		elseif payload.stage == "Input" then
			text ..= if seat.locked then "  locked" else "  thinking"
		end
		text ..= string.format("  bank %ds", seat.bank)
		add(text)
	end
	local clash = Colors.clashNotice(view)
	if clash then
		add(`NOTE: {clash}`)
	end
	add(string.format("Projected EV  you %d - %d them", view.projectedEV[you], view.projectedEV[them]))

	local result = payload.result
	if result then
		local why = if result.reason == "Election" then "" else ` ({result.reason})`
		add(
			if result.winner == you
				then `YOU WON{why}`
				elseif result.winner == 0 then `No result{why}`
				else `You lost{why}`
		)
		if rating and rating.matchId == payload.matchId then
			add(Format.ratingChange(rating))
		end
	end
	local election = view.election
	if election then
		add(string.format("Election night: you %d EV - %d EV them", election.ev[you], election.ev[them]))
		local closest = {}
		for k = #election.results, math.max(1, #election.results - 5), -1 do
			local r = election.results[k]
			table.insert(
				closest,
				string.format("%s %s by %.1f", r.state, if r.winner == you then "you" else "them", r.margin)
			)
		end
		add("Closest: " .. table.concat(closest, ", "))
	end

	if view.nextDebate then
		add(`Next debate week {view.nextDebate.week}: {table.concat(view.nextDebate.topics, ", ")}`)
	end
	if view.event then
		add("Event this week: " .. Format.event(view.event))
		-- A Choice week: the states you need and what each stance would do (D-042).
		if view.event.kind == "Choice" and view.phase == "Plan" then
			add(Swing.needText(Config.defaults, view))
			for k = 1, #Events.CHOICES do
				local id: Types.Choice = Events.CHOICES[k]
				add(
					"  "
						.. Swing.stanceSummary(Config.defaults, view, Swing.stance(Config.defaults, view, id))
				)
			end
		end
	end
	if view.nextEvent then
		add(`Next week's event (your pollster's briefing): {Format.event(view.nextEvent)}`)
	end
	local lastEvent = Swing.lastChoice(view)
	if lastEvent and lastEvent.choices and lastEvent.moves then
		local definition = Events.byId[lastEvent.id]
		add(
			string.format(
				"Last week's event %s: you took stance %s, them %s (%d states moved)",
				if definition then definition.name else lastEvent.id,
				lastEvent.choices[you],
				lastEvent.choices[them],
				#lastEvent.moves
			)
		)
		for _, line in Swing.choiceLines(Config.defaults, view, lastEvent) do
			add("  " .. line)
		end
	end
	if view.debatePrep then
		add(`Your prep: {table.concat(view.debatePrep, "/")}`)
	end
	local last = view.debates[#view.debates]
	if last and last.week == view.week then
		local winners = {}
		for t, topic in last.topics do
			local w = last.winners[t]
			table.insert(winners, `{topic}: {if w == you then "you" elseif w == 0 then "tie" else "them"}`)
		end
		add("Debate: " .. table.concat(winners, ", "))
		for t = 1, #last.topics do
			local entry = Swing.debateTopic(Config.defaults, view, last, t)
			add("  " .. entry.line)
			for _, gaffe in entry.gaffeLines do
				add("  " .. gaffe)
			end
		end
		local other: { string } = {}
		for _, flip in Swing.debateOther(view, last) do
			table.insert(other, Swing.flipPhrase(view, flip))
		end
		if #other > 0 then
			add(`  And from the points every state got: {table.concat(other, ", ")}`)
		end
	end

	local card = view.players[them].card
	if card then
		local parts = {}
		for _, r in card.rallies do
			table.insert(parts, `rally {r.state} ({r.issue})`)
		end
		for _, f in card.fundraisers do
			table.insert(parts, `fund {f}`)
		end
		for _, m in card.media do
			table.insert(parts, `{if m.attack then "attack" else "ads"} {m.state} ({m.issue})`)
		end
		if card.pivot then
			table.insert(parts, `pivot {card.pivot.drop}->{card.pivot.add}`)
		end
		if card.choice then
			table.insert(parts, `choice {card.choice}`)
		end
		add("Opponent last week: " .. (if #parts > 0 then table.concat(parts, ", ") else "nothing public"))
	end
	if #view.internalPolls > 0 then
		local parts = {}
		for _, poll in view.internalPolls do
			table.insert(
				parts,
				string.format("%s %.1f-%.1f", poll.state, poll.support[you], poll.support[them])
			)
		end
		add("Your internal polls: " .. table.concat(parts, ", "))
	end
	if view.raised > 0 then
		add(`You raised {Numbers.money(view.raised)} last week`)
	end

	if #view.draftLog > 0 and (view.phase == "Draft" or view.week <= 1) then
		local parts = {}
		for _, pick in view.draftLog do
			table.insert(parts, `{pick.kind} P{pick.player} {pick.state}`)
		end
		add("Draft: " .. table.concat(parts, ", "))
	end

	if view.phase ~= "Select" then
		add(`Your draft: home {view.players[you].home or "-"}; {Drafted.summary(view, you)}`)
	end

	-- The closest states by public poll (or, before polls, by lean).
	local rows = {}
	for i, s in view.states do
		local text, margin = marginText(s.poll, you)
		local record = StateData.list[i]
		local closeness = if s.poll then math.abs(margin) else (if s.leanTo then s.lean else 0)
		table.insert(
			rows,
			{ i = i, closeness = closeness - record.ev / 100, text = text, s = s, record = record }
		)
	end
	table.sort(rows, function(a, b)
		return a.closeness < b.closeness
	end)
	add(
		`Closest states (you-them, undecided, momentum you/them). Momentum drift: {Explain.driftRule(
			Config.defaults,
			view
		)}:`
	)
	for k = 1, math.min(CLOSEST, #rows) do
		local row = rows[k]
		local s, record = row.s, row.record
		local tags = Format.stateTags(s, you)
		add(
			string.format(
				"  %s %2d EV  %s  mom %.1f/%.1f  %s  [%s]",
				record.id,
				record.ev,
				row.text,
				s.momentum[you],
				s.momentum[them],
				table.concat(record.issues, "/"),
				table.concat(tags, ", ")
			)
		)
	end
	return table.concat(lines, "\n")
end

-- The log line for a rejected request. A plan turned down for money says what it
-- costs and what you have, worked out here from the plan we sent and our own View
-- (the server only sends the reason code).
function Format.rejected(payload: Session.StatePayload?, op: string?, reason: string?, input: any?): string
	local text = `rejected {op or "?"}: {reason or "?"}`
	if reason ~= "NotEnoughMoney" or payload == nil or payload.view.phase ~= "Plan" then
		return text
	end
	if type(input) ~= "table" or type(input.actions) ~= "table" then
		return text
	end
	local ok, detail = pcall(PlanDraft.moneyText, Config.defaults, payload.view, input :: any)
	if ok and type(detail) == "string" then
		return `{text}. {detail}`
	end
	return text
end

-- Details of one state, then what its lean, momentum and backlash mean and, in a
-- plan, what each action would do there (Shared/UI/Explain, empty plan).
function Format.state(payload: Session.StatePayload, id: string): string
	local view = payload.view
	for i, s in view.states do
		if s.id == id then
			local record = StateData.list[i]
			local text = marginText(s.poll, payload.you)
			local lines = { Explain.leanText(view, s), Explain.momentumNote(Config.defaults, view, s) }
			local backlash = Explain.backlashNote(Config.defaults, view, s)
			if backlash then
				table.insert(lines, backlash)
			end
			if view.phase == "Plan" and view.players[view.you].candidate then
				local message: Types.Issue = PlanDraft.bestIssue(Config.defaults, view, id)
				for _, entry in Explain.previews(Config.defaults, view, PlanDraft.new(), id, message) do
					table.insert(lines, entry.text)
				end
			end
			return string.format(
				"%s (%s): %d EV, issues %s, region %s, neighbors %s, pool cap %s, poll %s, battleground %s",
				record.name,
				id,
				record.ev,
				table.concat(record.issues, "/"),
				record.region,
				if #record.adjacent > 0 then table.concat(record.adjacent, " ") else "none (fly)",
				Numbers.money(s.capacity),
				text,
				if s.battleground then "yes" else "no"
			) .. "\n  " .. table.concat(lines, "\n  ")
		end
	end
	return `no state {id}`
end

-- The "How it works" text (Shared/UI/Explain.help), for the `rules` command.
function Format.rules(payload: Session.StatePayload?): string
	local out = {}
	for _, section in Explain.help(Config.defaults, if payload then payload.view else nil) do
		table.insert(out, `== {section.title} ==`)
		for _, line in section.lines do
			table.insert(out, line)
		end
	end
	return table.concat(out, "\n")
end

return table.freeze(Format)
