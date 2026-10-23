--!strict
-- Duel harness: two AI agents play one full match of 270 against each other
-- through files, on the real server and client code (fake Roblox engine, simulated
-- clock). Not a spec: `lune run tests` ignores it. Run from the repo root.
--
--   lune run tests/duel.luau -- --dir <dir> [--seed N] [--timeout 600] [--attempts 5] [--screen 1280x720]
--
-- Player 1 and Player 2 join, both press Queue and get matched. Whenever a player
-- must act (the debug UI status says "your move") the simulated clock stops, so
-- agents have unlimited real time; the harness writes <dir>/pN.screen.txt and waits
-- for <dir>/pN.cmd.txt. Everything else (reveals, debates, election night) runs by
-- itself, and the resolve animation and election night are skipped.
--
-- Files in <dir> (all writes are atomic: tmp file, then rename):
--   state.txt       "starting", "running", "waiting p1", "waiting p1 p2" or "done"
--   map.txt         static map data (EV, issues, region, neighbors, pool size), written once
--   pN.screen.txt   what player N must answer now. First line "TURN: k": k grows by one with
--                   every new screen for that player (also after a rejection, not after
--                   info commands such as show/help). Second line "REFRESH: r": r grows
--                   when an info command rewrote the same turn's screen with its output
--   pN.cmd.txt      written by the agent: one or more command lines. The harness types each
--                   into the debug command box, then deletes the file
--   pN.result.txt   the harness's verdict on the last command file ("TURN: k" it answered):
--                   ACCEPTED, REJECTED (uses an attempt), INFO (info lines only, such as
--                   show/rules/help: never an attempt) or AUTO-SUBMITTED
--   result.txt      the match result, written just before state.txt says "done"
-- tests/duel/README.md has the protocol and a rules summary; tests/duel/wait.sh and
-- send.sh wrap the file dance in two shell commands.
--
-- Exit code: 0 match finished, 1 script errors happened, 3 harness gave up (stuck).

local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")

local FakeRoblox = require("@testlib/FakeRoblox")
local Support = require("./e2e/Support")
local Candidates = require("@shared/Sim/Candidates")
local Config = require("@shared/Sim/Config")
local IssueMap = require("@shared/Sim/IssueMap")
local Issues = require("@shared/Sim/Issues")
local Drafted = require("@shared/UI/Drafted")
local Events = require("@shared/Sim/Events")
local Explain = require("@shared/UI/Explain")
local Format = require("@shared/DebugUI/Format")
local Numbers = require("@shared/UI/Numbers")
local PlanDraft = require("@shared/UI/PlanDraft")
local StateData = require("@shared/Sim/StateData")
local Swing = require("@shared/UI/Swing")
local Verdict = require("./duel/Verdict")

-- ---------------------------------------------------------------- arguments

local dir: string? = nil
local seed, timeout, maxAttempts = 1, 600, 5
local screenSize = { x = 1280, y = 720 }
local usageError: string? = nil
do
	local args = process.args
	local k = 1
	while k <= #args do
		local arg = args[k]
		if arg == "--" then
			k += 1
		elseif
			arg == "--dir"
			or arg == "--seed"
			or arg == "--timeout"
			or arg == "--attempts"
			or arg == "--screen"
		then
			local value = args[k + 1]
			if value == nil then
				usageError = `{arg} needs a value`
				break
			end
			if arg == "--dir" then
				dir = (string.gsub(value, "/+$", ""))
			elseif arg == "--seed" then
				seed = tonumber(value) or seed
			elseif arg == "--timeout" then
				timeout = tonumber(value) or timeout
			elseif arg == "--attempts" then
				maxAttempts = math.max(1, tonumber(value) or maxAttempts)
			else
				local x, y = string.match(value, "^(%d+)x(%d+)$")
				if x == nil then
					usageError = `--screen needs WIDTHxHEIGHT, got {value}`
					break
				end
				screenSize = { x = tonumber(x) :: number, y = tonumber(y) :: number }
			end
			k += 2
		else
			usageError = `unknown argument {arg}`
			break
		end
	end
end
if usageError or dir == nil then
	if usageError then
		print(`error: {usageError}`)
	end
	print("usage: lune run tests/duel.luau -- --dir <dir> [--seed N] [--timeout 600] [--attempts 5]")
	print("see tests/duel/README.md")
	process.exit(2)
end
local DIR: string = dir :: string

-- ---------------------------------------------------------------- files

local function path(name: string): string
	return `{DIR}/{name}`
end

local function writeAtomic(file: string, text: string)
	local tmp = `{file}.tmp`
	fs.writeFile(tmp, text)
	fs.move(tmp, file, true)
end

local function removeFile(file: string)
	if fs.isFile(file) then
		pcall(fs.removeFile, file)
	end
end

local function readFile(file: string): string?
	if not fs.isFile(file) then
		return nil
	end
	local ok, text = pcall(fs.readFile, file)
	if ok then
		return text :: string
	end
	return nil
end

if not fs.isDir(DIR) then
	fs.writeDir(DIR)
end
for _, name in fs.readDir(DIR) do
	if
		string.match(name, "^p%d+%.[%a]+%.txt")
		or string.match(name, "^%.p%d+%.seen$")
		or name == "result.txt"
		or name == "state.txt"
		or name == "map.txt"
	then
		removeFile(path(name))
	end
end

local lastState = ""
local function setState(text: string)
	if text ~= lastState then
		lastState = text
		writeAtomic(path("state.txt"), text .. "\n")
	end
end
setState("starting")

local function nowSeconds(): number
	return DateTime.now().unixTimestamp
end

-- ---------------------------------------------------------------- the world

local rig = Support.new(process.cwd, seed, screenSize)
local world = rig.world
local peers = Support.players(rig, 2)

export type Turn = {
	key: string, -- "matchId:step" of the stage this player is answering
	step: number,
	label: string, -- "Select", "Draft round 2/8 (Stronghold)", "Week 3 Plan"
	phase: string, -- View phase: Select, Draft or Plan
	attempts: number, -- rejected command files so far
	shownAt: number, -- real time the current screen appeared
	output: { string }, -- what the last command file printed, shown on the next screen
	focus: string?, -- the state of the last "show ST": WHAT TO DO previews it
	focusShown: boolean, -- the last command file's output already holds that show
}

export type Slot = {
	peer: FakeRoblox.Peer,
	n: number, -- 1 or 2
	name: string,
	latest: any?, -- last State payload
	rejects: number, -- Rejected messages seen
	lastReject: string?,
	screens: number, -- turns shown so far (the TURN number)
	refreshes: number, -- rewrites of the current turn's screen after info commands
	mark: number, -- how much of the UI log history earlier screens already showed
	turn: Turn?,
	lastSkip: string,
	trend: { string },
}

local slots: { Slot } = {}
for n, peer in peers do
	table.insert(slots, {
		peer = peer,
		n = n,
		name = peer.name,
		latest = nil,
		rejects = 0,
		lastReject = nil,
		screens = 0,
		refreshes = 0,
		mark = 0,
		turn = nil,
		lastSkip = "",
		trend = {},
	})
end

-- Listen to the server's messages on each client, next to the debug panel, to see
-- the full State payload (the panel keeps it private) and the rejection reasons.
do
	local remotes = world.shared:FindFirstChild("Remotes")
	local toClient = if remotes then remotes:FindFirstChild("ToClient") else nil
	assert(toClient, "the server did not create the Remotes folder")
	for _, slot in slots do
		world.current = slot.peer
		toClient.OnClientEvent:Connect(function(message: any)
			if message.kind == "State" and message.state then
				local payload = message.state
				slot.latest = payload
			elseif message.kind == "Rejected" then
				slot.rejects += 1
				slot.lastReject = `{message.op or "?"}: {message.reason or "?"}`
			end
		end)
		world.current = nil
	end
end

Support.queueMatch(rig, peers[1], peers[2])

-- ---------------------------------------------------------------- text helpers

local function lines(text: string): { string }
	local out = {}
	for line in string.gmatch(text, "[^\r\n]+") do
		table.insert(out, line)
	end
	return out
end

local function trim(text: string): string
	return (string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""))
end

local function issueIds(): string
	return table.concat(Issues.list, " ")
end

local function profileOf(candidate: string?): Candidates.Profile?
	if candidate == nil or not Candidates.exists(candidate) then
		return nil
	end
	return Candidates.profile(Config.defaults, candidate)
end

local function stateRecord(id: string): any
	return StateData.byId[id]
end

local function margin(poll: any?, you: number): string
	if poll == nil then
		return "no poll"
	end
	local them = if you == 1 then 2 else 1
	return string.format("%d-%d u%d", poll.support[you], poll.support[them], poll.undecided)
end

local function stageLabel(view: any): string
	if view.phase == "Select" then
		return "Select"
	elseif view.phase == "Draft" then
		return `Draft round {view.draftRound + 1}/8 ({view.draftKind})`
	end
	return `Week {view.week} {view.phase}`
end

local function matchesPlatform(view: any, record: any, platform: { string }?): boolean
	if platform == nil then
		return false
	end
	for _, issue in IssueMap.of(view.issueMap, record.id) do
		if table.find(platform, issue) then
			return true
		end
	end
	return false
end

-- The full table of states: everything this player's View says about each.
local function statesTable(payload: any): { string }
	local view = payload.view
	local you = payload.you
	local me = view.players[you]
	local rows = {}
	for i, s in view.states do
		table.insert(rows, { i = i, s = s, r = StateData.list[i] })
	end
	table.sort(rows, function(a, b)
		if a.r.ev ~= b.r.ev then
			return a.r.ev > b.r.ev
		end
		return a.r.id < b.r.id
	end)
	local C = Config.defaults
	local out = {
		`Momentum drift: {Explain.driftRule(C, payload.view)}. "leans you +4" = the state started 4 points of margin your way.`,
		"ID  EV  issues                  poll (you-them, u=undecided)  momentum you/them  tags",
	}
	for _, row in rows do
		local s, r = row.s, row.r
		local tags = {}
		if s.battleground then
			table.insert(tags, "BG")
		end
		if s.owner then
			local holder = `P{s.owner}{if s.owner == you then "(you)" else ""}`
			if s.isHome then
				table.insert(tags, `home {holder}`)
			elseif s.battleground then
				-- Nominated: the stronghold bonus is gone (playtest 1).
				table.insert(tags, `nominated stronghold of {holder}, no bonus`)
			else
				table.insert(tags, `stronghold {holder}`)
			end
		end
		if s.leanTo then
			table.insert(tags, Explain.leanText(view, s))
		end
		if s.gotv > 0 then
			table.insert(
				tags,
				`your gotv {s.gotv} (+{Numbers.points(s.gotv * C.GOTV_PER_UNIT)} margin on election night)`
			)
		end
		if s.backlash > 0 then
			table.insert(
				tags,
				`your backlash {s.backlash} of {C.BACKLASH_THRESHOLD} (once full, your next attack here also costs you {Numbers.points(
					C.BACKLASH_PENALTY
				)})`
			)
		end
		if matchesPlatform(view, r, me.platform) then
			table.insert(tags, "platform match")
		end
		table.insert(
			out,
			string.format(
				"%s %3d  %-22s  %-12s  %.1f/%.1f  %s",
				r.id,
				r.ev,
				table.concat(IssueMap.of(view.issueMap, r.id), "/"),
				margin(s.poll, you),
				s.momentum[you],
				s.momentum[if you == 1 then 2 else 1],
				table.concat(tags, ", ")
			)
		)
	end
	return out
end

-- Static map data, written once at the start.
local function mapText(): string
	local payload = slots[1].latest
	local out = {
		`MAP: 50 states + DC, 538 EV, {Config.defaults.EV_TO_WIN} wins. Winner-take-all. 'adjacent' states are a free route hop;`,
		`anything else costs a {Numbers.cost(Config.defaults.FLIGHT_COST)} flight. AK and HI have no neighbors (flights only).`,
		`pool = state fundraising pool capacity in $ (refills {math.floor(
			Config.defaults.POOL_REFILL * 100 + 0.5
		)}% per week, shared by both players).`,
		"The 'rules' command prints how every action, poll, debate, event and election night works, with the numbers.",
		"Top issues (the two after the region) are drawn new for this match (D-044).",
		"",
	}
	for i, r in StateData.list do
		local cap = if payload then payload.view.states[i].capacity else 0
		table.insert(
			out,
			string.format(
				"%s %-20s %2d EV  pop %5.2fM  pool %-6s  %-13s %-21s adjacent: %s",
				r.id,
				r.name,
				r.ev,
				r.pop,
				Numbers.money(cap),
				r.region,
				if payload then table.concat(payload.view.issueMap[i], "/") else "?",
				if #r.adjacent > 0 then table.concat(r.adjacent, " ") else "none (fly)"
			)
		)
	end
	return table.concat(out, "\n") .. "\n"
end

-- ---------------------------------------------------------------- stage guides

local function selectGuide(payload: any): { string }
	local view = payload.view
	local out = {
		"STAGE: Select, in two steps (D-045). Two players never share a candidate: the first to claim one holds it.",
		"  1. claim CANDIDATE                     holds a free candidate while you choose issues (optional)",
		"  2. select CANDIDATE ISSUE ISSUE ISSUE  locks in your candidate and platform (claims it too, if still free)",
		`Your color is drawn: {view.players[view.you].color or "?"}. Your platform stays hidden until both lock.`,
		"Candidates (TAKEN = your opponent holds it; pick another):",
	}
	for _, id in Candidates.ids do
		local p = Candidates.profile(Config.defaults, id)
		local owner = view.claims[id]
		local tag = if owner == nil then "" elseif owner == view.you then "YOURS " else "TAKEN "
		table.insert(
			out,
			string.format(
				"  %-9s %s%s, %s. Perk: %s. Drawback: %s. [AP %d, start $%g, income $%g, rally %g, ad $%g, debate prep %d]",
				id,
				tag,
				p.name,
				p.archetype,
				p.perk,
				p.drawback,
				p.apPerWeek,
				p.startCash,
				p.passiveIncome,
				p.rallySupport,
				p.mediaCost,
				p.debatePrep
			)
		)
	end
	-- This match's issues (D-044): EV covered and the platform multiplier.
	table.insert(
		out,
		"Issues this match (EV = votes of the states where it is a top issue; x = rally/ad multiplier there once it is on your platform; niche issues hit harder):"
	)
	local ev = IssueMap.evByIssue(view.issueMap)
	for _, issue in IssueMap.ranked(view.issueMap) do
		table.insert(
			out,
			string.format(
				"  %-11s %3d EV  x%.2f",
				string.lower(issue),
				ev[issue],
				view.platformMults[issue] or 0
			)
		)
	end
	table.insert(out, `Issue ids: {string.lower(issueIds())}`)
	table.insert(out, "Example:   claim okafor")
	table.insert(out, "Example:   select okafor jobs health schools")
	return out
end

local function draftGuide(payload: any): { string }
	local view = payload.view
	local you = payload.you
	local me = view.players[you]
	local C = Config.defaults
	local kind = view.draftKind
	local rule
	if kind == "Home" then
		rule =
			`HOME: +{C.HOME_BONUS} support there (+{C.HOME_BONUS_BIG} if {C.BIG_STATE_EV}+ EV); your fundraisers there yield x{C.HOME_FUNDRAISE_MULT} all game; your candidate starts the campaign there.`
	elseif kind == "Stronghold" then
		rule =
			`STRONGHOLD: +{C.STRONGHOLD_BONUS} support there (+{C.STRONGHOLD_BONUS_BIG} if {C.BIG_STATE_EV}+ EV).`
	else
		rule =
			`NOMINATE a battleground: it loses ALL draft bonuses (back to {C.BASE_SUPPORT}/{C.BASE_SUPPORT}/{C.BASE_UNDECIDED} plus its lean) and gets x{C.BATTLEGROUND_MULT} on every campaign effect all game, for both players. A home state cannot be nominated; an opponent's stronghold can.`
	end
	local priority = view.draftPriority
	local out = {
		`STAGE: State draft, round {view.draftRound + 1} of 8: {kind}. Blind and simultaneous; picks are revealed together afterwards.`,
		rule,
		`Clash priority this round: P{priority} {if priority == you
			then "(YOU win a clash on the same first choice)"
			else "(the OPPONENT wins a clash on the same first choice, so your 2nd choice matters)"}.`,
		"Command:  draft ST [ST]      (ranked top 2; the 2nd is your fallback, if you give one only the first is used and the server fills the 2nd)",
		"Example:   draft OH PA",
		`Your platform: {if me.platform then table.concat(me.platform, ", ") else "?"}.  Legal states (* = a top issue matches your platform):`,
	}
	local rows = {}
	for i, s in view.states do
		local legal
		if kind == "Nominate" then
			legal = not s.isHome and not s.battleground
		else
			legal = s.owner == nil and not s.battleground
		end
		if legal then
			table.insert(rows, { s = s, r = StateData.list[i] })
		end
	end
	table.sort(rows, function(a, b)
		if a.r.ev ~= b.r.ev then
			return a.r.ev > b.r.ev
		end
		return a.r.id < b.r.id
	end)
	for _, row in rows do
		local owner = ""
		if row.s.owner then
			owner = `  [stronghold of P{row.s.owner}{if row.s.owner == you then " (you)" else ""}]`
		end
		table.insert(
			out,
			string.format(
				"  %s%s %2d EV  %-21s %-13s %s%s",
				row.r.id,
				if matchesPlatform(view, row.r, me.platform) then "*" else " ",
				row.r.ev,
				table.concat(IssueMap.of(view.issueMap, row.r.id), "/"),
				row.r.region,
				Explain.leanText(view, row.s),
				owner
			)
		)
	end
	return out
end

local function planGuide(payload: any, turn: Turn): { string }
	local view = payload.view
	local you = payload.you
	local me = view.players[you]
	local C = Config.defaults
	local profile = profileOf(me.candidate) :: Candidates.Profile
	local location = me.location or me.home
	local out = {
		`STAGE: Week {view.week} of {C.WEEKS} Plan. Simultaneous and hidden: the opponent plans now too; both plans resolve together.`,
		string.format(
			"You: %s (%s). Cash %s. AP %d (use it or lose it). Candidate is in %s; free route hop to: %s.",
			profile.name,
			me.candidate,
			Numbers.money(me.cash or 0),
			profile.apPerWeek,
			location or "?",
			if location then table.concat(stateRecord(location).adjacent, " ") else "?"
		),
		`Platform: {if me.platform then table.concat(me.platform, ", ") else "?"}.  Your draft: see "Your draft" on the board.`,
		string.format(
			"Costs: rally 1 AP; fund 1 AP; flight (a rally/fund stop that is neither your state nor adjacent to the previous stop) +$%d; ad/attack ad $%g; poll $%d (%d free per week for you); rpoll $%d; gotv $%g per unit (max %d per state); pivot 1 AP, once per match (%s).",
			C.FLIGHT_COST,
			profile.mediaCost,
			C.INTERNAL_POLL_COST,
			profile.freePolls,
			C.REGION_POLL_COST,
			profile.gotvCost,
			profile.gotvMaxUnits,
			if me.pivotUsed then "ALREADY USED" else "available"
		),
	}
	local ownGotv = {}
	for _, s in view.states do
		if s.gotv > 0 then
			table.insert(ownGotv, `{s.id} {s.gotv}`)
		end
	end
	table.insert(
		out,
		`Your ground game so far: {if #ownGotv > 0 then table.concat(ownGotv, ", ") else "none"}.`
	)
	-- This week's event and the next debate are on the board below; only what to
	-- add to the plan is said here.
	if view.event then
		if view.event.kind == "Choice" then
			table.insert(
				out,
				`CHOICE WEEK ({view.event.name}, issue {view.event.issue}): add "choice a", "choice b" or "choice c" to your plan (default c, the hedge). The board below has the states you need and one summary per stance (what it gains, the leads it risks, the poll leaders it would flip on today's polls, before their stance). Every state each stance moves, for you:`
			)
			for _, line in Explain.choiceLines(C, view.event, me.platform, Events.baseOf(me)) do
				table.insert(out, `  {line}`)
			end
			for _, stance in view.event.stances or {} do
				table.insert(out, `  {stance.id}: "{stance.text}"`)
			end
		end
	end
	local prepDue = table.find(C.DEBATE_WEEKS, view.week + 1) ~= nil
	local prepText = ""
	if prepDue and view.nextDebate then
		local points = profile.debatePrep
		local base = math.floor(points / 3)
		local extra = points - base * 3
		local spread = {}
		for k = 1, 3 do
			table.insert(spread, base + (if k <= extra then 1 else 0))
		end
		prepText = `; prep {table.concat(spread, " ")}`
		table.insert(
			out,
			`DEBATE PREP DUE: the debate is next week, topics in order: {table.concat(
				view.nextDebate.topics,
				", "
			)}. Add "prep A B C" to your plan: {points} points over those 3 topics, max {C.DEBATE_MAX_PER_TOPIC} per topic (default {table.concat(
				spread,
				" "
			)}). Leave it out to keep the default.`
		)
	end
	-- Previews follow the last "show ST" of this turn, else where the candidate is.
	local previewAt = turn.focus or location
	if previewAt and me.candidate then
		if turn.focus and turn.focusShown then
			table.insert(
				out,
				`WHAT EACH ACTION WOULD DO in {previewAt}: in the output of your "show {previewAt}" above ("show ST" for any other state).`
			)
		else
			local why = if turn.focus then `your last "show {previewAt}"` else "where your candidate is"
			table.insert(
				out,
				`WHAT EACH ACTION WOULD DO in {previewAt} ({why}; expected values; "show ST" gives this for any state):`
			)
			local message = PlanDraft.bestIssue(C, view, previewAt)
			for _, entry in Explain.previews(C, view, PlanDraft.new(), previewAt, message) do
				table.insert(out, `  {entry.text}`)
			end
		end
	end
	table.insert(out, "")
	table.insert(
		out,
		"COMMANDS (one per line in the cmd file; send as many info lines as you like, but one plan/pass locks you in):"
	)
	table.insert(
		out,
		"  plan ACTION; ACTION; ...      actions (separate with ';'), in route order for rally/fund:"
	)
	table.insert(
		out,
		"     rally ST ISSUE   fund ST   ad ST ISSUE   attack ad ST ISSUE   poll ST   rpoll REGION"
	)
	table.insert(out, "     gotv ST UNITS    pivot DROP ADD   prep A B C   choice a|b|c")
	table.insert(
		out,
		"     (names as the game says them: ad = Ad (media also works), attack ad = Attack ad (attack also works), gotv = Ground game, rpoll = Region poll)"
	)
	table.insert(out, `     ISSUE is one of: {string.lower(issueIds())}`)
	table.insert(out, `     REGION is one of: {table.concat(Issues.regions, " ")}`)
	table.insert(
		out,
		"  pass                          empty plan (AP lost, money banks; default prep / stance c, the hedge)"
	)
	table.insert(
		out,
		"  show ST                       one state: numbers, what lean/momentum mean there, each action's expected effect (free)"
	)
	table.insert(
		out,
		"  rules                         how every action, poll, debate, event and election night works (free)"
	)
	table.insert(
		out,
		"  auto                          the built-in bot fills this step for you (locks you in)"
	)
	table.insert(
		out,
		"  help | bank                   bank is pointless here: the clock is stopped while you think"
	)

	local adj = if location then stateRecord(location).adjacent else {}
	local issueA = if me.platform then me.platform[1] else "Jobs"
	local issueB = if me.platform then me.platform[2] or me.platform[1] else "Jobs"
	local rallyStop = adj[1] or location or "OH"
	local cash = me.cash or 0
	local second = ""
	if cash >= C.INTERNAL_POLL_COST and #adj > 1 then
		second = `; poll {adj[2]}`
	end
	if cash >= profile.mediaCost + (if second ~= "" then C.INTERNAL_POLL_COST else 0) then
		second ..= `; ad {adj[2] or rallyStop} {string.lower(issueB)}`
	end
	local extra = prepText
	if view.event and view.event.kind == "Choice" then
		extra ..= "; choice a"
	end
	table.insert(
		out,
		`Example:   plan rally {location or rallyStop} {string.lower(issueA)}; fund {location or rallyStop}{extra}`
	)
	table.insert(
		out,
		`Example:   plan fund {location or rallyStop}; rally {rallyStop} {string.lower(issueB)}{second}{extra}`
	)
	table.insert(out, `Example:   pass`)
	return out
end

-- ---------------------------------------------------------------- screens

local function recapLines(payload: any): { string }
	local view = payload.view
	local you = payload.you
	local out = {}
	for _, debate in view.debates do
		table.insert(out, Format.debate(debate, you))
		if debate.week == view.week then
			-- This week's: the score breakdown (what each topic swung is on the board).
			for t, topic in debate.topics do
				table.insert(out, `  {topic}: {Explain.debateLine(Config.defaults, view, debate, t)}`)
			end
		else
			-- Earlier ones: what each topic swung and flipped, in words.
			for t = 1, #debate.topics do
				local entry = Swing.debateTopic(Config.defaults, view, debate, t)
				table.insert(out, `  {entry.line}`)
				for _, gaffe in entry.gaffeLines do
					table.insert(out, `  {gaffe}`)
				end
			end
			local other = {}
			for _, flip in Swing.debateOther(view, debate) do
				table.insert(other, Swing.flipPhrase(view, flip))
			end
			if #other > 0 then
				table.insert(out, `  And from the points every state got: {table.concat(other, ", ")}`)
			end
		end
	end
	local lastChoice = Swing.lastChoice(view)
	for _, e in view.eventLog do
		if e.choices and e ~= lastChoice then
			-- Last week's Choice is on the board; earlier ones are summed up here.
			table.insert(out, `Event week {e.week} ({e.id}):`)
			for _, line in Swing.choiceLines(Config.defaults, view, e) do
				table.insert(out, `  {line}`)
			end
		elseif not e.choices then
			table.insert(out, `Event week {e.week}: {e.id}`)
		end
	end
	return out
end

local function buildScreen(slot: Slot, extraOutput: { string }): string
	local payload = slot.latest
	local view = payload.view
	local you = payload.you
	local turn = slot.turn :: Turn
	local ui = Support.screen(slot.peer)
	local out = {}
	local function add(text: string)
		table.insert(out, text)
	end
	add(`TURN: {slot.screens}`)
	add(`REFRESH: {slot.refreshes}`)
	add(
		`PLAYER: p{slot.n} ({slot.name}), seat P{you}     MATCH: {payload.matchId}     STEP: {payload.step}     ATTEMPT: {turn.attempts + 1} of {maxAttempts}`
	)
	if turn.attempts > 0 then
		local left = maxAttempts - turn.attempts
		add(
			`!!! YOUR LAST COMMAND FILE WAS REJECTED: {left} attempt{if left == 1 then "" else "s"} left before the harness plays "{if turn.phase
					== "Plan"
				then "pass"
				else "auto"}" for you !!!`
		)
	end
	add(`STATUS: {ui.status}`)
	add(
		`ACTION NEEDED: {turn.label}. Write your command(s) to p{slot.n}.cmd.txt in the duel directory (tests/duel/send.sh does it).`
	)
	if #extraOutput > 0 then
		add("")
		add("=== OUTPUT OF YOUR LAST COMMAND FILE ===")
		for _, line in extraOutput do
			add(line)
		end
	end
	add("")
	add("=== WHAT TO DO ===")
	local guide
	if view.phase == "Select" then
		guide = selectGuide(payload)
	elseif view.phase == "Draft" then
		guide = draftGuide(payload)
	else
		guide = planGuide(payload, turn)
	end
	for _, line in guide do
		add(line)
	end
	add("")
	add("=== BOARD (the debug panel's board text) ===")
	add(ui.board)
	local recap = recapLines(payload)
	if #recap > 0 then
		add("")
		add("=== DEBATES AND EVENTS SO FAR ===")
		for _, line in recap do
			add(line)
		end
	end
	if #slot.trend > 0 then
		add("")
		add(`Projected EV at the start of each plan (you-them): {table.concat(slot.trend, ", ")}`)
	end
	add("")
	add("=== LOG SINCE YOUR LAST TURN ===")
	local history = rig.history[slot.peer]
	local count = 0
	for k = slot.mark + 1, #history do
		add(history[k])
		count += 1
	end
	if count == 0 then
		add("(nothing new)")
	end
	if view.phase ~= "Select" then
		add("")
		add("=== ALL STATES (what your View shows; map.txt has neighbors and pool sizes) ===")
		for _, line in statesTable(payload) do
			add(line)
		end
	end
	return table.concat(out, "\n") .. "\n"
end

-- Starts (or restarts, after a rejection) the screen for a pending player. A
-- refresh rewrites the same turn after info commands (show, help): TURN stays,
-- REFRESH grows, so notes keyed by turn number stay right.
local function showScreen(slot: Slot, output: { string }, refresh: boolean?)
	if refresh then
		slot.refreshes += 1
	else
		slot.screens += 1
		slot.refreshes = 0
	end
	local turn = slot.turn :: Turn
	turn.shownAt = nowSeconds()
	local text = buildScreen(slot, output)
	-- A command file written before this screen existed answered nothing.
	removeFile(path(`p{slot.n}.cmd.txt`))
	writeAtomic(path(`p{slot.n}.screen.txt`), text)
	slot.mark = #rig.history[slot.peer]
end

-- ---------------------------------------------------------------- commands

-- Which lines are info only, and the verdict names: tests/duel/Verdict.luau.

-- What the server's reason codes mean, for the agent reading the verdict.
local GLOSS: { [string]: string } = {
	WrongPhase = "this command is for a different stage (select, draft and plan only work in their own stage)",
	BadShape = "malformed input",
	TooManyActions = "too many actions in one plan",
	UnknownState = "no such state code",
	UnknownIssue = "no such issue",
	UnknownRegion = "no such region",
	UnknownCandidate = "no such candidate",
	CandidateTaken = "your opponent holds that candidate; pick another",
	AlreadyClaimed = "you already hold a candidate",
	BadPlatform = "pick exactly three different issues",
	BadChoiceCount = "draft takes one or two states",
	DuplicateChoice = "the same state twice in a draft",
	IllegalChoice = "that state is not legal this round (already drafted, a battleground, or a home when nominating)",
	BadTarget = "bad attack target",
	BadUnits = "gotv units must be a whole number from 1 up",
	GotvCap = "gotv would go over the per-state cap",
	DuplicatePoll = "polled the same state twice",
	PivotUsed = "the pivot is once per match, one per plan",
	BadPivot = "pivot DROP must be in your platform and ADD must not be",
	NotEnoughAP = "the plan uses more AP than you have",
	NotEnoughMoney = "the plan costs more than your cash (ads, attack ads, polls, ground game (gotv) and flights cost money)",
	BadPrep = "prep must be your debate points split over the 3 topics, max 4 on one topic",
	UnexpectedPrep = "prep is only accepted in the week before a debate",
	BadChoice = "choice must be a, b or c (the stances on the board; c is the hedge)",
	UnexpectedChoice = "choice is only accepted in a Choice-event week",
	StaleStep = "the stage moved on",
	AlreadyLocked = "you are already locked in",
}

local function explain(reason: string?): string
	local code = string.match(reason or "", "([%a]+)$") or ""
	local gloss = GLOSS[code]
	return if gloss then `{reason} ({gloss})` else tostring(reason)
end

local submitted: { { week: string, who: number, text: string } } = {}
local notes: { string } = {}
local function note(text: string)
	table.insert(notes, text)
	print(`[duel] {text}`)
end

-- True once this player's input for `turn` is in (locked, or the stage moved on).
local function accepted(slot: Slot, turn: Turn): boolean
	local payload = slot.latest
	if payload == nil then
		return false
	end
	if payload.matchId ~= string.match(turn.key, "^[^:]*") or payload.step ~= turn.step then
		return true
	end
	return payload.seats[payload.you].locked == true
end

-- Types the lines of one command file. Returns (locked, rejectedAny, report lines).
local function runCommands(slot: Slot, commands: { string }): (boolean, boolean, { string })
	local turn = slot.turn :: Turn
	local report = {}
	local rejectedAny = false
	local locked = false
	for _, command in commands do
		if locked then
			table.insert(report, `> {command}`)
			table.insert(report, "  ignored: you are already locked in for this step")
			continue
		end
		local head = string.lower(string.match(command, "^%S+") or "")
		table.insert(report, `> {command}`)
		local kind = Verdict.kind(command)
		if kind == "Blocked" then
			rejectedAny = true
			table.insert(report, `  REJECTED: "{head}" is not available in a duel`)
			continue
		end
		local historyBefore = #rig.history[slot.peer]
		local rejectsBefore = slot.rejects
		Support.type(rig, slot.peer, command)
		local printed = {}
		local history = rig.history[slot.peer]
		for i = historyBefore + 1, #history do
			table.insert(printed, history[i])
		end
		local rejectedNow = slot.rejects > rejectsBefore
		if accepted(slot, turn) and not rejectedNow then
			locked = true
			table.insert(report, "  ACCEPTED: locked in")
			table.insert(submitted, { week = turn.label, who = slot.n, text = command })
		elseif kind == "Info" then
			table.insert(
				report,
				if rejectedNow
					then `  info only, not available now (no harm done): {explain(slot.lastReject)}`
					else "  info"
			)
			for _, line in printed do
				table.insert(report, `  {line}`)
			end
		else
			rejectedAny = true
			if rejectedNow then
				table.insert(report, `  REJECTED: {explain(slot.lastReject)}`)
			else
				table.insert(report, `  REJECTED: {printed[1] or "not a valid command"}`)
				table.remove(printed, 1)
			end
			for _, line in printed do
				table.insert(report, `  {line}`)
			end
		end
	end
	return locked, rejectedAny, report
end

local function writeResult(slot: Slot, turnNo: number, status: string, report: { string })
	local out = { `TURN: {turnNo}`, `STATUS: {status}` }
	for _, line in report do
		table.insert(out, line)
	end
	writeAtomic(path(`p{slot.n}.result.txt`), table.concat(out, "\n") .. "\n")
end

-- The harness default for this turn: "pass" in a plan week, else "auto".
local function defaultMove(turn: Turn): string
	return if turn.phase == "Plan" then "pass" else "auto"
end

-- What a rejected screen and verdict say about the attempts left.
local function attemptsLeft(turn: Turn): string
	local left = maxAttempts - turn.attempts
	return `{left} attempt{if left == 1 then "" else "s"} left before the harness plays "{defaultMove(turn)}" for you`
end

-- The verdict when the harness played the default: its own lines first, then
-- what the player sent (so AUTO-SUBMITTED never reads as part of a rejection).
local function autoSubmitted(slot: Slot, answered: number, harness: { string }, sent: { string })
	local report = table.clone(harness)
	if #sent > 0 then
		table.insert(report, "--- your last command file, for reference ---")
		for _, line in sent do
			table.insert(report, line)
		end
	end
	writeResult(slot, answered, "AUTO-SUBMITTED (this turn is over for you)", report)
end

-- The harness's own move when a player runs out of tries or time.
local function defaultSubmit(slot: Slot, why: string): ({ string }, boolean)
	local turn = slot.turn :: Turn
	local first = defaultMove(turn)
	note(`p{slot.n} {turn.label}: {why}; submitting {first}`)
	Support.type(rig, slot.peer, first)
	if not accepted(slot, turn) then
		Support.type(rig, slot.peer, "auto")
	end
	local ok = accepted(slot, turn)
	if ok then
		table.insert(submitted, { week = turn.label, who = slot.n, text = `({why}) {first}` })
	end
	return {
		`HARNESS: {why}; submitted "{first}" for you.{if ok then "" else " (it did not lock)"}`,
	}, ok
end

local fallbackFailures = 0
local function fallback(slot: Slot, why: string): { string }
	local report, ok = defaultSubmit(slot, why)
	if not ok then
		fallbackFailures += 1
	end
	return report
end

-- ---------------------------------------------------------------- loop

local function pendingTurn(slot: Slot): { key: string, payload: any }?
	local payload = slot.latest
	if payload == nil or payload.stage ~= "Input" or payload.seats[payload.you].locked then
		return nil
	end
	if string.find(Support.screen(slot.peer).status, "your move", 1, true) == nil then
		return nil
	end
	return { key = `{payload.matchId}:{payload.step}`, payload = payload }
end

local function isOver(): boolean
	for _, slot in slots do
		local payload = slot.latest
		if payload == nil or payload.stage ~= "Over" then
			return false
		end
	end
	return true
end

local started = world.clock
local runningSeconds = 0
local stuck = false
local MAX_RUNNING = 4000 -- simulated seconds of auto-advancing before giving up

local function pendingList(): { string }
	local out = {}
	for _, slot in slots do
		if slot.turn ~= nil then
			table.insert(out, `p{slot.n}`)
		end
	end
	return out
end

local function serve(slot: Slot, pending: { key: string, payload: any })
	local payload = pending.payload
	local turn = slot.turn
	if turn == nil or turn.key ~= pending.key then
		slot.turn = {
			key = pending.key,
			step = payload.step,
			label = stageLabel(payload.view),
			phase = payload.view.phase,
			attempts = 0,
			shownAt = nowSeconds(),
			output = {},
			focus = nil,
			focusShown = false,
		}
		if payload.view.phase == "Plan" then
			local ev = payload.view.projectedEV
			table.insert(
				slot.trend,
				`W{payload.view.week} {ev[payload.you]}-{ev[if payload.you == 1 then 2 else 1]}`
			)
		end
		showScreen(slot, {})
		print(`[duel] p{slot.n} to act: {(slot.turn :: Turn).label} (screen {slot.screens})`)
		return
	end
	local current = slot.turn :: Turn
	local file = path(`p{slot.n}.cmd.txt`)
	local text = readFile(file)
	if text ~= nil then
		removeFile(file)
		removeFile(path(`p{slot.n}.result.txt`))
		local commands = {}
		for _, line in lines(text) do
			local cleaned = trim(line)
			if cleaned ~= "" and string.sub(cleaned, 1, 1) ~= "#" then
				table.insert(commands, cleaned)
			end
		end
		local answered = slot.screens
		current.focusShown = false
		if #commands == 0 then
			current.attempts += 1
			if current.attempts >= maxAttempts then
				local report = fallback(slot, "no valid command after the allowed attempts")
				autoSubmitted(slot, answered, report, { "(your command file was empty)" })
				removeFile(path(`p{slot.n}.screen.txt`))
				slot.turn = nil
			else
				writeResult(
					slot,
					answered,
					`NOTHING TO DO: the command file was empty; {attemptsLeft(current)}`,
					{}
				)
				showScreen(slot, { "(your command file was empty)" })
			end
			return
		end
		local locked, rejected, report = runCommands(slot, commands)
		local focus = Verdict.focus(commands)
		if focus then
			current.focus = focus
			current.focusShown = true
		end
		local outcome = Verdict.outcome(rejected)
		-- The report already shows what these commands printed: keep it out of the
		-- next screen's log.
		slot.mark = #rig.history[slot.peer]
		if locked then
			writeResult(slot, answered, "ACCEPTED", report)
			removeFile(path(`p{slot.n}.screen.txt`))
			slot.turn = nil
			print(`[duel] p{slot.n} locked: {current.label}`)
			return
		end
		if outcome.usesAttempt then
			current.attempts += 1
		end
		if current.attempts >= maxAttempts then
			local harness = fallback(slot, `{maxAttempts} rejected command files on this turn`)
			autoSubmitted(slot, answered, harness, report)
			removeFile(path(`p{slot.n}.screen.txt`))
			slot.turn = nil
			return
		end
		if outcome.refresh then
			writeResult(slot, answered, outcome.status, report)
			showScreen(slot, report, true)
		else
			writeResult(slot, answered, `{outcome.status}; {attemptsLeft(current)}`, report)
			showScreen(slot, report)
		end
		return
	end
	if nowSeconds() - current.shownAt >= timeout then
		local answered = slot.screens
		local report = fallback(slot, `no command within {timeout} s`)
		removeFile(path(`p{slot.n}.cmd.txt`))
		autoSubmitted(slot, answered, report, {})
		removeFile(path(`p{slot.n}.screen.txt`))
		slot.turn = nil
	end
end

-- Skips the resolve animation and election night for everyone.
local function skipAnimations()
	for _, slot in slots do
		local payload = slot.latest
		if payload ~= nil then
			local skippable = payload.reveal == "Resolve"
				or (payload.stage == "Show" and payload.view.phase == "Election")
			local key = `{payload.matchId}:{payload.step}`
			if skippable and slot.lastSkip ~= key then
				slot.lastSkip = key
				Support.type(rig, slot.peer, "skip")
			end
		end
	end
end

writeAtomic(path("map.txt"), mapText())

while not isOver() do
	local pending = {}
	for _, slot in slots do
		local p = pendingTurn(slot)
		if p then
			pending[slot.n] = p
		elseif slot.turn ~= nil then
			-- Locked or moved on through some other path: drop the stale screen.
			slot.turn = nil
			removeFile(path(`p{slot.n}.screen.txt`))
		end
	end
	if next(pending) == nil then
		setState("running")
		skipAnimations()
		Support.run(rig, 0.5)
		runningSeconds += 0.5
		if runningSeconds > MAX_RUNNING then
			note(`gave up: {MAX_RUNNING} simulated seconds passed without anyone being asked to act`)
			stuck = true
			break
		end
	else
		runningSeconds = 0
		for _, slot in slots do
			local p = pending[slot.n]
			if p then
				serve(slot, p)
			end
		end
		local waiting = pendingList()
		if #waiting > 0 then
			setState("waiting " .. table.concat(waiting, " "))
			task.wait(0.5)
		end
		if fallbackFailures >= 3 then
			note("gave up: the default move could not be submitted for a player")
			stuck = true
			break
		end
	end
end

-- ---------------------------------------------------------------- result

local function playerSummary(slot: Slot): string
	local payload = slot.latest
	if payload == nil then
		return `p{slot.n}: no state`
	end
	local view = payload.view
	local me = view.players[payload.you]
	local p = profileOf(me.candidate)
	return string.format(
		"p%d (%s, seat P%d): %s (%s), platform %s, home %s, %s",
		slot.n,
		slot.name,
		payload.you,
		if p then p.name else "?",
		me.color or "?",
		if me.platform then table.concat(me.platform, "/") else "?",
		me.home or "-",
		Drafted.summary(view, payload.you)
	)
end

local function resultText(): string
	local out = {}
	local function add(text: string)
		table.insert(out, text)
	end
	local first = slots[1].latest
	add("DUEL RESULT")
	if stuck or first == nil or first.result == nil then
		add("winner: none (the harness gave up before the match ended)")
	else
		local result = first.result
		local ev = if first.view.election then first.view.election.ev else nil
		local winnerText = if result.winner == 0
			then "nobody"
			else `p{result.winner} ({slots[result.winner].name})`
		add(`winner: {winnerText}`)
		add(
			`reason: {result.reason}{if first.view.election
				then ` (decided by {first.view.election.decidedBy})`
				else ""}`
		)
		if ev then
			add(`EV: p1 {ev[1]} - p2 {ev[2]} (270 wins)`)
			add(`states won: p1 {first.view.election.statesWon[1]} - p2 {first.view.election.statesWon[2]}`)
		else
			add("EV: no election was held")
		end
	end
	add(`seed: {seed}   simulated time: {string.format("%.0f", world.clock - started)} s`)
	add("")
	for _, slot in slots do
		add(playerSummary(slot))
	end
	add("")
	add("=== COMMANDS EACH PLAYER LOCKED IN, BY STEP ===")
	for _, entry in submitted do
		add(`{entry.week} | p{entry.who} | {entry.text}`)
	end
	add("")
	add("=== HARNESS NOTES (timeouts, fallbacks) ===")
	if #notes == 0 then
		add("none")
	end
	for _, line in notes do
		add(line)
	end
	add("")
	add(`=== SCRIPT ERRORS ({#world.errors}) ===`)
	for _, message in world.errors do
		add(message)
	end
	add(`=== WIRE WARNINGS ({#world.wireWarnings}) ===`)
	for _, message in world.wireWarnings do
		add(message)
	end
	for _, slot in slots do
		add("")
		add(`=== FINAL BOARD p{slot.n} ===`)
		add(Support.screen(slot.peer).status)
		add(Support.screen(slot.peer).board)
		add(`--- p{slot.n} UI log history (last 25 lines) ---`)
		local history = rig.history[slot.peer]
		for k = math.max(1, #history - 24), #history do
			add(history[k])
		end
	end
	return table.concat(out, "\n") .. "\n"
end

for _, slot in slots do
	removeFile(path(`p{slot.n}.screen.txt`))
	removeFile(path(`p{slot.n}.cmd.txt`))
end
local text = resultText()
writeAtomic(path("result.txt"), text)
setState("done")
print(string.match(text, "^[^\n]*\n[^\n]*\n[^\n]*\n[^\n]*") or "")
print(`[duel] done. Result in {DIR}/result.txt`)

if #world.errors > 0 then
	process.exit(1)
elseif stuck then
	process.exit(3)
end
