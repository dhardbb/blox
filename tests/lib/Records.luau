--!strict
-- Reads exported match records (docs/DESIGN.md D-094; Net/MatchRecord) and
-- builds a balance summary in the shape of the balance harness's report:
-- candidate win rates, the matchup matrix, match shape (margins, landslides,
-- comebacks), debates (how often the debate winner wins), stances, timings
-- and timeouts. tests/harness/records.luau prints it; the spec checks it.
--
-- Input: JSON lines. Each line is a record, or an Open Cloud "get entry"
-- response whose `value` is the record. Blank lines and lines that are not a
-- record (v missing, or a newer MatchRecord.SCHEMA) are counted and skipped.

local serde = require("@lune/serde")

local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local MatchRecord = require("@net/MatchRecord")

local Records = {}

export type Filter = {
	mode: string?, -- only this mode ("Queue", "Private", "Practice", "WaitBot", "Tutorial", "Daily")
	humans: boolean?, -- only matches between two people
	version: string?, -- only this game version
}

-- The records in `text` (JSON lines), and how many lines were skipped.
function Records.parse(text: string): ({ MatchRecord.Record }, number)
	local out: { MatchRecord.Record } = {}
	local skipped = 0
	for _, raw in string.split(text, "\n") do
		local trimmed = string.match(raw, "^%s*(.-)%s*$") or ""
		if trimmed == "" then
			continue
		end
		local ok, value = pcall(serde.decode, "json" :: any, trimmed)
		if ok and type(value) == "table" and value.v == nil and type(value.value) == "table" then
			value = value.value -- an Open Cloud entry
		end
		if
			ok
			and type(value) == "table"
			and type(value.v) == "number"
			and value.v <= MatchRecord.SCHEMA
			and type(value.seats) == "table"
		then
			table.insert(out, value :: any)
		else
			skipped += 1
		end
	end
	return out, skipped
end

local function humanMatch(record: MatchRecord.Record): boolean
	for _, seat in record.seats do
		if seat.kind ~= "Human" then
			return false
		end
	end
	return true
end

function Records.filter(records: { MatchRecord.Record }, filter: Filter?): { MatchRecord.Record }
	local out: { MatchRecord.Record } = {}
	for _, record in records do
		if filter and filter.mode and record.mode ~= filter.mode then
			continue
		end
		if filter and filter.humans and not humanMatch(record) then
			continue
		end
		if filter and filter.version and record.version ~= filter.version then
			continue
		end
		table.insert(out, record)
	end
	return out
end

local function pct(x: number): string
	return string.format("%.1f%%", 100 * x)
end

local function quantile(sorted: { number }, q: number): number
	if #sorted == 0 then
		return 0
	end
	local k = math.clamp(math.floor(q * (#sorted - 1) + 0.5) + 1, 1, #sorted)
	return sorted[k]
end

local function sortedCopy(list: { number }): { number }
	local out = table.clone(list)
	table.sort(out)
	return out
end

local function len(value: any): number
	return if type(value) == "table" then #value else 0
end

-- The summary as printable lines, and its red flags. Same line format as the
-- balance harness: "ok"/"!!" mark, label, value, target.
function Records.summarize(records: { MatchRecord.Record }, title: string?): ({ string }, { string })
	local lines: { string } = {}
	local flags: { string } = {}
	local function out(text: string)
		table.insert(lines, text)
	end
	local function line(label: string, value: string, target: string?, ok: boolean?)
		local mark = if ok == nil then "  " elseif ok then "ok" else "!!"
		out(string.format("%s %-44s %-16s %s", mark, label, value, target or ""))
		if ok == false then
			table.insert(flags, `{label}: {value} (target {target})`)
		end
	end
	local function header(text: string)
		out("")
		out(text)
		out(string.rep("-", #text))
	end

	local config = Config.defaults
	local ids = Candidates.ids
	local modes: { [string]: number } = {}
	local versions: { [string]: number } = {}
	local wins: { [string]: number } = {}
	local games: { [string]: number } = {}
	local pairWins: { [string]: { [string]: number } } = {}
	local pairGames: { [string]: { [string]: number } } = {}
	for _, id in ids do
		wins[id], games[id] = 0, 0
		pairWins[id], pairGames[id] = {}, {}
		for _, other in ids do
			pairWins[id][other], pairGames[id][other] = 0, 0
		end
	end
	local elections, forfeits, abandoned, landslides = 0, 0, 0, 0
	local margins: { number } = {}
	local comebacks, comebackEligible = 0, 0
	local projectedWrong, projectedEligible = 0, 0
	local debateDecisive, debateEligible = 0, 0
	local rounds, splits, sameMove, canned, zingers, zingerWins = 0, 0, 0, 0, 0, 0
	local moves: { [string]: number } = { Defend = 0, Attack = 0, Pivot = 0 }
	local stances: { [string]: number } = {}
	local stanceCount, sameStance = 0, 0
	local durations: { number } = {}
	local fullDurations: { number } = {}
	local timeouts, planTimeouts, humanSeats, planSeats = 0, 0, 0, 0

	for _, record in records do
		modes[record.mode] = (modes[record.mode] or 0) + 1
		versions[record.version] = (versions[record.version] or 0) + 1
		table.insert(durations, record.duration / 60)
		if record.reason == "Election" and not record.tutorial then
			table.insert(fullDurations, record.duration / 60)
		end
		for _, seat in record.seats do
			if seat.kind == "Human" then
				humanSeats += 1
			end
		end
		timeouts += len(record.timeouts)
		for _, t in record.timeouts or {} do
			local phase, _, seat = string.match(t, "^(%a+):(%d+):(%d+)$")
			local s = tonumber(seat)
			if phase == "Plan" and s and record.seats[s] and record.seats[s].kind == "Human" then
				planTimeouts += 1
			end
		end
		for _, seat in record.seats do
			if seat.kind == "Human" then
				planSeats += record.weeks
			end
		end
		if record.reason == "Forfeit" then
			forfeits += 1
		elseif record.reason == "Abandoned" then
			abandoned += 1
		end
		if record.landslide then
			landslides += 1
		end

		local a, b = record.seats[1], record.seats[2]
		local decided = record.winner == 1 or record.winner == 2
		if
			decided
			and a
			and b
			and a.candidate ~= b.candidate
			and games[a.candidate]
			and games[b.candidate]
		then
			local winner = if record.winner == 1 then a.candidate else b.candidate
			local loser = if record.winner == 1 then b.candidate else a.candidate
			games[winner] += 1
			games[loser] += 1
			wins[winner] += 1
			pairGames[winner][loser] += 1
			pairGames[loser][winner] += 1
			pairWins[winner][loser] += 1
		end

		local ev = record.ev
		if record.reason == "Election" and ev and #ev >= 2 then
			elections += 1
			table.insert(margins, math.abs(ev[1] - ev[2]))
			-- Comebacks: trailing on the projected EV at week 8, then winning.
			for _, row in record.projected or {} do
				if row[1] == 8 and decided then
					local mine, theirs = row[1 + record.winner], row[1 + (3 - record.winner)]
					if mine and theirs and mine ~= theirs then
						comebackEligible += 1
						if mine < theirs then
							comebacks += 1
						end
					end
				end
			end
			local last = (record.projected or {})[len(record.projected)]
			if last and decided and last[2] ~= last[3] then
				projectedEligible += 1
				local leader = if last[2] > last[3] then 1 else 2
				if leader ~= record.winner then
					projectedWrong += 1
				end
			end
			-- Debates: did the side that won more rounds win the match?
			local roundWins = { 0, 0 }
			for _, debate in record.debates or {} do
				for _, round in debate.rounds or {} do
					if round.winner == 1 or round.winner == 2 then
						roundWins[round.winner] += 1
					end
				end
			end
			if decided and roundWins[1] ~= roundWins[2] then
				debateEligible += 1
				local better = if roundWins[1] > roundWins[2] then 1 else 2
				if better == record.winner then
					debateDecisive += 1
				end
			end
		end
		for _, debate in record.debates or {} do
			for _, round in debate.rounds or {} do
				rounds += 1
				if round.winner == 0 then
					splits += 1
				end
				local picks = round.picks or {}
				if #picks >= 2 and picks[1] == picks[2] then
					sameMove += 1
				end
				for p, pick in picks do
					if (round.canned or {})[p] then
						canned += 1
					elseif moves[pick] then
						moves[pick] += 1
					end
					if (round.zingers or {})[p] then
						zingers += 1
						if round.winner == p then
							zingerWins += 1
						end
					end
				end
			end
		end
		for _, stance in record.stances or {} do
			stanceCount += 1
			local choices = stance.choices or {}
			for _, c in choices do
				stances[c] = (stances[c] or 0) + 1
			end
			if #choices >= 2 and choices[1] == choices[2] then
				sameStance += 1
			end
		end
	end

	local n = #records
	out(`{title or "270 match records"}: {n} matches, {elections} reached election night`)
	local modeText: { string } = {}
	for _, mode in { "Queue", "Private", "Practice", "WaitBot", "Tutorial", "Daily" } do
		if modes[mode] then
			table.insert(modeText, `{mode} {modes[mode]}`)
		end
	end
	out("Modes: " .. (if #modeText > 0 then table.concat(modeText, " · ") else "none"))
	local versionText: { string } = {}
	for version, count in versions do
		table.insert(versionText, `{version} {count}`)
	end
	table.sort(versionText)
	out("Versions: " .. (if #versionText > 0 then table.concat(versionText, " · ") else "none"))

	header("Candidates (mirror matches excluded)")
	for _, id in ids do
		local rate = wins[id] / math.max(1, games[id])
		line(
			Candidates.profile(config, id).name,
			`{pct(rate)} of {games[id]}`,
			"45-55%",
			if games[id] >= 20 then rate >= 0.45 and rate <= 0.55 else nil
		)
	end

	header("Matchup matrix (row's win rate vs column)")
	local head = "          "
	for _, id in ids do
		head ..= string.format("%9s", string.sub(id, 1, 8))
	end
	out(head)
	for _, row in ids do
		local text = string.format("%-10s", string.sub(row, 1, 9))
		for _, col in ids do
			local games2 = pairGames[row][col]
			if row == col or games2 == 0 then
				text ..= string.format("%9s", "-")
			else
				text ..= string.format("%8.0f%%", 100 * pairWins[row][col] / games2)
			end
		end
		out(text)
	end

	header("Match shape")
	local sorted = sortedCopy(margins)
	local mean = 0
	for _, m in margins do
		mean += m / math.max(1, #margins)
	end
	local median = quantile(sorted, 0.5)
	line("Mean / median final EV margin", `{math.floor(mean + 0.5)} / {median}`, "median <= 60", median <= 60)
	local blowouts, routs = 0, 0
	for _, m in margins do
		if m >= 40 then
			blowouts += 1
		end
		if m >= 100 then
			routs += 1
		end
	end
	local blowRate = blowouts / math.max(1, elections)
	local routRate = routs / math.max(1, elections)
	line("Decided by 40+ EV", pct(blowRate), "<= 65%", blowRate <= 0.65)
	line("Decided by 100+ EV", pct(routRate), "<= 25%", routRate <= 0.25)
	line("Landslides (winner over 70% of EV)", pct(landslides / math.max(1, elections)), nil, nil)
	local comebackRate = comebacks / math.max(1, comebackEligible)
	line(
		"Comeback rate (trailing projected EV at week 8)",
		pct(comebackRate),
		"20-40%",
		comebackRate >= 0.2 and comebackRate <= 0.4
	)
	line("Week-12 projected leader loses", pct(projectedWrong / math.max(1, projectedEligible)), nil, nil)
	line(
		"EV margin p10/p25/p50/p75/p90",
		string.format(
			"%d/%d/%d/%d/%d",
			quantile(sorted, 0.1),
			quantile(sorted, 0.25),
			median,
			quantile(sorted, 0.75),
			quantile(sorted, 0.9)
		),
		nil,
		nil
	)
	line(
		"Forfeits / abandoned",
		`{pct(forfeits / math.max(1, n))} / {pct(abandoned / math.max(1, n))}`,
		nil,
		nil
	)

	header("Debates and stances")
	local decisive = debateDecisive / math.max(1, debateEligible)
	line("Debate decisive (more rounds won, won match)", `{pct(decisive)} of {debateEligible}`, nil, nil)
	local played = moves.Defend + moves.Attack + moves.Pivot
	local function share(k: string): string
		return string.format("%.1f%%", 100 * moves[k] / math.max(1, played))
	end
	line(
		"Debate moves played (D / A / P)",
		`D {share("Defend")} / A {share("Attack")} / P {share("Pivot")}`,
		"each 20-50%",
		if played >= 30
			then moves.Defend / played >= 0.2
				and moves.Defend / played <= 0.5
				and moves.Attack / played >= 0.2
				and moves.Attack / played <= 0.5
				and moves.Pivot / played >= 0.2
				and moves.Pivot / played <= 0.5
			else nil
	)
	local splitRate = splits / math.max(1, rounds)
	line(
		"Debate rounds that split",
		pct(splitRate),
		"<= 35%",
		if rounds >= 30 then splitRate <= 0.35 else nil
	)
	line("Both played the same move", pct(sameMove / math.max(1, rounds)), nil, nil)
	line(
		"Canned answers (timed out) per round",
		string.format("%.2f", canned / math.max(1, rounds)),
		nil,
		nil
	)
	line("Staked Zingers that won the round", pct(zingerWins / math.max(1, zingers)), nil, nil)
	local stanceTotal = 0
	for _, count in stances do
		stanceTotal += count
	end
	local function stanceShare(k: string): string
		return string.format("%.1f%%", 100 * (stances[k] or 0) / math.max(1, stanceTotal))
	end
	line(
		"Stances taken (A / B / C)",
		`A {stanceShare("A")} / B {stanceShare("B")} / C {stanceShare("C")}`,
		nil,
		nil
	)
	line("Both players took the same stance", pct(sameStance / math.max(1, stanceCount)), nil, nil)

	header("Timings")
	local d = sortedCopy(fullDurations)
	local typical = quantile(d, 0.5)
	line(
		"Full match minutes p50 / p90",
		string.format("%.1f / %.1f", typical, quantile(d, 0.9)),
		"p50 <= 15 (D-005)",
		if #d > 0 then typical <= 15 else nil
	)
	local all = sortedCopy(durations)
	line("Any match minutes p50 (all reasons)", string.format("%.1f", quantile(all, 0.5)), nil, nil)
	line("Timeouts per match (all phases)", string.format("%.2f", timeouts / math.max(1, n)), nil, nil)
	line("Human plans left to time out", pct(planTimeouts / math.max(1, planSeats)), nil, nil)
	line("Human seats", tostring(humanSeats), nil, nil)

	out("")
	out(`{#flags} red flag(s):`)
	for _, flag in flags do
		out(`  - {flag}`)
	end
	return lines, flags
end

return Records
