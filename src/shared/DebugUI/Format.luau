--!strict
-- Turns a State payload (or lobby status) into plain text for the Phase 2 debug
-- UI. Reads only what the server sent, which is only the player's own View.

local Candidates = require("../Sim/Candidates")
local Config = require("../Sim/Config")
local StateData = require("../Sim/StateData")
local Remotes = require("../Net/Remotes")
local Session = require("../Net/Session")

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
		text ..= ` · {lobby.queued} in queue`
		if lobby.full then
			text ..= " · server full"
		end
		return text
	end
	local view = payload.view
	local me = view.players[payload.you]
	local label = view.phase
	if view.phase == "Plan" or view.phase == "Debate" then
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
		text ..= string.format(" · $%.1f", me.cash)
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

-- The full board summary.
function Format.board(payload: Session.StatePayload, now: number): string
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
			if player.cash then string.format("$%.1f", player.cash) else `money {player.money}`,
			player.home or "-"
		)
		if player.platform then
			text ..= `  platform {table.concat(player.platform, "/")}`
		end
		if player.underdogTier > 0 then
			text ..= `  underdog tier {player.underdogTier}`
		end
		if not seat.connected then
			text ..= string.format("  DISCONNECTED (grace %ds)", secondsLeft(seat.graceUntil or now, now))
		elseif payload.stage == "Input" then
			text ..= if seat.locked then "  locked" else "  thinking"
		end
		text ..= string.format("  bank %ds", seat.bank)
		add(text)
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
		add(string.format("You raised $%.1f last week", view.raised))
	end

	if #view.draftLog > 0 and (view.phase == "Draft" or view.week <= 1) then
		local parts = {}
		for _, pick in view.draftLog do
			table.insert(parts, `{pick.kind} P{pick.player} {pick.state}`)
		end
		add("Draft: " .. table.concat(parts, ", "))
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
	add("Closest states (you-them, undecided, momentum you/them):")
	for k = 1, math.min(CLOSEST, #rows) do
		local row = rows[k]
		local s, record = row.s, row.record
		local tags = {}
		if s.battleground then
			table.insert(tags, "BG")
		end
		if s.owner then
			table.insert(tags, `{if s.isHome then "home" else "SH"} P{s.owner}`)
		end
		if s.leanTo then
			table.insert(tags, `lean {if s.leanTo == you then "+" else "-"}{s.lean}`)
		end
		if s.gotv > 0 then
			table.insert(tags, `gotv {s.gotv}`)
		end
		add(
			string.format(
				"  %s %2d EV  %s  mom %.1f/%.1f  %s  [%s]",
				record.id,
				record.ev,
				row.text,
				s.momentum[you],
				s.momentum[them],
				table.concat(record.issues, "/"),
				table.concat(tags, " ")
			)
		)
	end
	return table.concat(lines, "\n")
end

-- Details of one state.
function Format.state(payload: Session.StatePayload, id: string): string
	local view = payload.view
	for i, s in view.states do
		if s.id == id then
			local record = StateData.list[i]
			local text = marginText(s.poll, payload.you)
			return string.format(
				"%s (%s): %d EV, issues %s, region %s, neighbors %s, pool cap $%.1f, poll %s, battleground %s",
				record.name,
				id,
				record.ev,
				table.concat(record.issues, "/"),
				record.region,
				if #record.adjacent > 0 then table.concat(record.adjacent, " ") else "none (fly)",
				s.capacity,
				text,
				if s.battleground then "yes" else "no"
			)
		end
	end
	return `no state {id}`
end

return table.freeze(Format)
