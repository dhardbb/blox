--!strict
-- Balance harness: bot-vs-bot matches and the report docs/PLAN.md asks for.
--
--   lune run tests/harness/balance.luau            -- 2,000 matches plus side checks
--   lune run tests/harness/balance.luau 500        -- fewer matches
--   lune run tests/harness/balance.luau 500 POLL_SIGMA=4 DRIFT_CAP=2   -- a Config variant
--   lune run tests/harness/balance.luau EVENTS_ENABLED=false           -- without the event deck
--   lune run tests/harness/balance.luau 500 bot.scoutPolls=2           -- a Bot.tuning variant
--
-- Prints every metric with its target and a list of red flags. Exits 0 either
-- way: the report informs tuning, it does not gate commits.

local process = require("@lune/process")

local Bot = require("@sim/Bot")
local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Issues = require("@sim/Issues")
local Play = require("@testlib/Play")
local Rng = require("@sim/Rng")

local args = {}
for _, arg in process.args do
	if arg ~= "--" then
		table.insert(args, arg)
	end
end

local N = 2000
local changes: { [string]: any } = {}
local tuned: { string } = {}
for _, arg in args do
	local key, value = string.match(arg, "^([%u_]+)=(.+)$")
	local knob, setting = string.match(arg, "^bot%.(%w+)=(.+)$")
	if knob and setting then
		local knobs = Bot.tuning :: any
		assert(knobs[knob] ~= nil, `unknown Bot.tuning key {knob}`)
		knobs[knob] = tonumber(setting)
		table.insert(tuned, arg)
	elseif key and value then
		if value == "true" or value == "false" then
			changes[key] = value == "true" -- e.g. EVENTS_ENABLED=false
		else
			changes[key] = tonumber(value) or value
		end
	elseif tonumber(arg) then
		N = tonumber(arg) :: number
	end
end
local config = Config.with(Config.defaults, changes)

local flags: { string } = {}
local function line(label: string, value: string, target: string?, ok: boolean?)
	local mark = if ok == nil then "  " elseif ok then "ok" else "!!"
	print(string.format("%s %-44s %-16s %s", mark, label, value, target or ""))
	if ok == false then
		table.insert(flags, `{label}: {value} (target {target})`)
	end
end
local function pct(x: number): string
	return string.format("%.1f%%", 100 * x)
end
local function header(title: string)
	print("")
	print(title)
	print(string.rep("-", #title))
end

local started = os.clock()
local ids = Candidates.ids
local K = #ids

-- Two different candidates per match (mirrors excluded), drawn from the seed.
local function pairFor(seed: number): { string }
	local rng = Rng.new(seed * 977 + 13)
	local a = Rng.nextInt(rng, 1, K)
	local b = Rng.nextInt(rng, 1, K - 1)
	if b >= a then
		b += 1
	end
	return { ids[a], ids[b] }
end

-- ---------------------------------------------------------------- main run

local wins: { [string]: number } = {}
local games: { [string]: number } = {}
local pairWins: { [string]: { [string]: number } } = {}
local pairGames: { [string]: { [string]: number } } = {}
local topicWins: { [string]: number } = {}
local topicGames: { [string]: number } = {}
for _, id in ids do
	wins[id], games[id], topicWins[id], topicGames[id] = 0, 0, 0, 0
	pairWins[id], pairGames[id] = {}, {}
	for _, other in ids do
		pairWins[id][other], pairGames[id][other] = 0, 0
	end
end

local priorityWins, comebacks, comebackEligible = 0, 0, 0
local margins: { number } = {}
local blowouts, routs, invalid = 0, 0, 0
local unspent, gotvSpend = 0, 0
local raisedTotal = 0
local raisedEarly, raisedLate = 0, 0 -- weeks 1-3 and 10-12, both players
local tierChanges, underdogWeeks, underdogWrong = 0, 0, 0
local gotvDecided, debateDecided, debateShiftEV, projectionWrong = 0, 0, 0, 0
local stanceDecided, stanceShiftEV, choiceWeeks, sameStance = 0, 0, 0, 0
local focusWon, focusPlayed, sameFocus, debatesPlayed = 0, 0, 0, 0
local stanceTaken: { [string]: number } = {}
local tossupDraft, tossupElection, spread = 0, 0, 0
local leaned, flipped = 0, 0
local leanX, winY = {}, {}
-- Draft shape: how long it is, how often first choices clash, how predictable the
-- picks are (the playtest complaint: "a clear correct choice for both players").
local draftRounds, draftClashes, homeClashes = 0, 0, 0
local homeCount: { [string]: number } = {}
local strongholdCount: { [string]: number } = {}
local strongholdEV, strongholdGaps = 0, {}
local richerWins, richerGames = 0, 0
local issueEVs: { [string]: { number } } = {} -- per issue, its EV in every match (D-047)
local issuePicks: { [string]: number } = {}
local picksTotal, top3, spreads = 0, 0, {}
for _, issue in Issues.list do
	issueEVs[issue], issuePicks[issue] = {}, 0
end

for seed = 1, N do
	local cands = pairFor(seed)
	local r = Play.match(config, seed, cands)
	local w, l = cands[r.winner], cands[3 - r.winner]
	wins[w] += 1
	games[w] += 1
	games[l] += 1
	pairWins[w][l] += 1
	pairGames[w][l] += 1
	pairGames[l][w] += 1
	for p = 1, 2 do
		topicWins[cands[p]] += r.debateTopicsWon[p]
		topicGames[cands[p]] += r.debateTopicsPlayed
	end
	if r.winner == r.priorityA then
		priorityWins += 1
	end
	if r.trueLeaderWeek8 ~= 0 then
		comebackEligible += 1
		if r.trueLeaderWeek8 ~= r.winner then
			comebacks += 1
		end
	end
	local margin = math.abs(r.ev[1] - r.ev[2])
	table.insert(margins, margin)
	if margin >= 40 then
		blowouts += 1
	end
	if margin >= 100 then
		routs += 1
	end
	invalid += r.invalid
	unspent += (r.unspent[1] + r.unspent[2]) / 2
	gotvSpend += (r.gotvSpend[1] + r.gotvSpend[2]) / 2
	raisedTotal += (r.raised[1] + r.raised[2]) / 2
	for week = 1, 3 do
		raisedEarly += r.raisedByWeek[week]
		raisedLate += r.raisedByWeek[config.WEEKS - 3 + week]
	end
	tierChanges += r.tierChanges
	underdogWeeks += r.underdogWeeks
	underdogWrong += r.underdogWrong
	if r.gotvDecided then
		gotvDecided += 1
	end
	if r.debateDecided then
		debateDecided += 1
	end
	debateShiftEV += r.debateShiftEV
	if r.stanceDecided then
		stanceDecided += 1
	end
	stanceShiftEV += r.stanceShiftEV
	focusWon += r.focusWon
	focusPlayed += r.focusPlayed
	sameFocus += r.sameFocus
	debatesPlayed += #r.match.debates
	choiceWeeks += r.choiceWeeks
	sameStance += r.sameStance
	for id, count in r.stances do
		stanceTaken[id] = (stanceTaken[id] or 0) + count
	end
	if r.projectionWrong then
		projectionWrong += 1
	end
	tossupDraft += r.tossupEVDraft / 538
	tossupElection += r.tossupEVElection / 538
	spread += r.noiseSpread
	leaned += r.leanedStates
	flipped += r.leanedFlipped
	local lo, hi = math.huge, -math.huge
	for issue, ev in r.issueEV do
		table.insert(issueEVs[issue], ev)
		lo, hi = math.min(lo, ev), math.max(hi, ev)
	end
	table.insert(spreads, hi - lo)
	for p = 1, 2 do
		for _, issue in r.platforms[p] do
			issuePicks[issue] += 1
			picksTotal += 1
		end
		if r.platformTop3[p] then
			top3 += 1
		end
	end
	table.insert(leanX, r.leanEV[1] - r.leanEV[2])
	table.insert(winY, if r.winner == 1 then 1 else 0)
	draftRounds += r.draftRounds
	draftClashes += r.draftClashes
	if r.homeClash then
		homeClashes += 1
	end
	for p = 1, 2 do
		homeCount[r.homes[p]] = (homeCount[r.homes[p]] or 0) + 1
		for _, id in r.strongholds[p] do
			strongholdCount[id] = (strongholdCount[id] or 0) + 1
		end
		strongholdEV += r.strongholdEV[p] / 2
	end
	local gap = r.strongholdEV[1] - r.strongholdEV[2]
	table.insert(strongholdGaps, math.abs(gap))
	if gap ~= 0 then
		richerGames += 1
		if (gap > 0) == (r.winner == 1) then
			richerWins += 1
		end
	end
end
local mainSeconds = os.clock() - started

local function correlation(x: { number }, y: { number }): number
	local n = #x
	local sx, sy, sxx, syy, sxy = 0, 0, 0, 0, 0
	for k = 1, n do
		sx += x[k]
		sy += y[k]
		sxx += x[k] * x[k]
		syy += y[k] * y[k]
		sxy += x[k] * y[k]
	end
	local cov = sxy / n - sx * sy / n / n
	local vx, vy = sxx / n - (sx / n) ^ 2, syy / n - (sy / n) ^ 2
	if vx <= 0 or vy <= 0 then
		return 0
	end
	return cov / math.sqrt(vx * vy)
end

table.sort(margins)
local meanMargin = 0
for _, m in margins do
	meanMargin += m / #margins
end

print(
	string.format(
		"270 balance report: %d matches in %.1fs (%.1f ms each)",
		N,
		mainSeconds,
		1000 * mainSeconds / N
	)
)
local variantKeys = {}
for key, value in changes do
	table.insert(variantKeys, `{key}={value}`)
end
print(if #variantKeys > 0 then "Config variant: " .. table.concat(variantKeys, " ") else "Config: defaults")
if #tuned > 0 then
	print("Bot variant: " .. table.concat(tuned, " "))
end

header("Candidates (mirror matches excluded)")
for _, id in ids do
	local rate = wins[id] / math.max(1, games[id])
	line(
		Candidates.profile(config, id).name,
		`{pct(rate)} of {games[id]}`,
		"45-55%",
		rate >= 0.45 and rate <= 0.55
	)
end

header("Matchup matrix (row's win rate vs column)")
local head = "          "
for _, id in ids do
	head ..= string.format("%9s", string.sub(id, 1, 8))
end
print(head)
local worstPair, worstRate = "", 0.5
for _, row in ids do
	local text = string.format("%-10s", string.sub(row, 1, 9))
	for _, col in ids do
		if row == col then
			text ..= string.format("%9s", "-")
		else
			local n = pairGames[row][col]
			local rate = pairWins[row][col] / math.max(1, n)
			text ..= string.format("%8.0f%%", 100 * rate)
			if n > 0 and math.abs(rate - 0.5) > math.abs(worstRate - 0.5) then
				worstPair, worstRate = `{row} vs {col}`, rate
			end
		end
	end
	print(text)
end
local perPair = N / (K * (K - 1) / 2)
line(
	"Most lopsided matchup",
	`{worstPair} {pct(worstRate)}`,
	string.format("40-60%% (~%d games/pair)", perPair),
	worstRate >= 0.4 and worstRate <= 0.6
)

header("Match shape")
local priorityRate = priorityWins / N
line("Draft priority A win rate", pct(priorityRate), "47-53%", priorityRate >= 0.47 and priorityRate <= 0.53)
local comebackRate = comebacks / math.max(1, comebackEligible)
line(
	"Comeback rate (trailing true EV at week 8)",
	pct(comebackRate),
	"20-40%",
	comebackRate >= 0.2 and comebackRate <= 0.4
)
local medianMargin = margins[math.ceil(#margins / 2)]
line(
	"Mean / median final EV margin",
	string.format("%.0f / %.0f", meanMargin, medianMargin),
	"median <= 60",
	medianMargin <= 60
)
-- Revised target (D-024): winner-take-all makes "<= 15% by 40+ EV" unreachable.
line("Decided by 40+ EV", pct(blowouts / N), "<= 65%", blowouts / N <= 0.65)
line("Decided by 100+ EV", pct(routs / N), "<= 25%", routs / N <= 0.25)
line("Average money unspent at the end", string.format("$%.1f", unspent / N))
line("Average money raised per player", string.format("$%.1f", raisedTotal / N))
-- D-034: flat, not front-loaded. Weeks 1-3 against weeks 10-12 (week 12's money is
-- never spent, so the bot fundraises less then).
local frontLoad = raisedEarly / math.max(1e-9, raisedLate)
line("Raised in weeks 1-3 / weeks 10-12", string.format("%.2f", frontLoad), "<= 1.5", frontLoad <= 1.5)
line("Invalid bot inputs", tostring(invalid), "0", invalid == 0)
local deciles = {}
for _, q in { 0.1, 0.25, 0.5, 0.75, 0.9 } do
	table.insert(deciles, tostring(margins[math.max(1, math.floor(q * #margins))]))
end
line("EV margin p10/p25/p50/p75/p90", table.concat(deciles, "/"))

header("Map")
line("Tossup EV share after the draft", pct(tossupDraft / N))
line("Tossup EV share at the election", pct(tossupElection / N), "<= 30%", tossupElection / N <= 0.3)
line("Election-noise spread (sd of EV)", string.format("%.1f EV", spread / N), "<= 25", spread / N <= 25)
local flipRate = flipped / math.max(1, leaned)
line("Leaned states that flip", pct(flipRate), "20-40%", flipRate >= 0.2 and flipRate <= 0.4)
local r = correlation(leanX, winY)
line("Correlation: leaned-EV edge vs win", string.format("%.3f", r), "|r| < 0.05", math.abs(r) < 0.05)

header("Draft")
local roundsPerMatch = draftRounds / N
line(
	"Draft rounds / seconds (reveal + rounds)",
	string.format(
		"%.0f / %.0fs",
		roundsPerMatch,
		config.TIMER_MAP_REVEAL + roundsPerMatch * (config.TIMER_DRAFT_ROUND + config.DRAFT_REVEAL)
	)
)
line("Home: both first choices the same state", pct(homeClashes / N))
line("Any round: first choices clash", pct(draftClashes / math.max(1, draftRounds)))
local function top(counts: { [string]: number }, total: number, k: number): string
	local list = {}
	for id, count in counts do
		table.insert(list, { id = id, count = count })
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.id < b.id
	end)
	local parts = {}
	for n = 1, math.min(k, #list) do
		table.insert(parts, `{list[n].id} {string.format("%.0f", 100 * list[n].count / total)}`)
	end
	return table.concat(parts, " ")
end
line("Most picked homes (% of homes)", top(homeCount, 2 * N, 4))
line("Most common strongholds (% of matches)", top(strongholdCount, N, 4))
table.sort(strongholdGaps)
line(
	"Stronghold EV per player / gap p50 p90 max",
	string.format(
		"%.1f / %d %d %d",
		strongholdEV / N,
		strongholdGaps[math.ceil(N / 2)],
		strongholdGaps[math.max(1, math.floor(0.9 * N))],
		strongholdGaps[N]
	)
)
line("Win rate, side with more stronghold EV", pct(richerWins / math.max(1, richerGames)))

-- Issues (D-047): each match draws its own top issues; niche issues hit harder,
-- so no platform should be the obvious pick.
header("Issues (drawn per match)")
local function quantile(list: { number }, q: number): number
	local sorted = table.clone(list)
	table.sort(sorted)
	return sorted[math.clamp(math.ceil(q * #sorted), 1, #sorted)]
end
for _, issue in Issues.list do
	local share = issuePicks[issue] / math.max(1, picksTotal)
	line(
		`{issue}: EV min/median/max, picked`,
		string.format(
			"%d/%d/%d  %s",
			quantile(issueEVs[issue], 0),
			quantile(issueEVs[issue], 0.5),
			quantile(issueEVs[issue], 1),
			pct(share)
		),
		"picked 5-25%",
		share >= 0.05 and share <= 0.25
	)
end
line(
	"Issue EV spread in a match (top - bottom) p50/max",
	string.format("%d / %d", quantile(spreads, 0.5), quantile(spreads, 1)),
	"< 54 (the fixed map)",
	quantile(spreads, 0.5) < 54
)
local top3Rate = top3 / (2 * N)
line("Bot platform = the 3 highest-EV issues", pct(top3Rate), "well under 50%", top3Rate < 0.35)

header("Rubber band")
local wrongRate = underdogWrong / math.max(1, underdogWeeks)
line("Underdog weeks to a true 20+ EV leader", pct(wrongRate), "< 10%", wrongRate < 0.1)
line("Underdog tier changes per match", string.format("%.2f", tierChanges / N), "<= 3", tierChanges / N <= 3)

header("Mechanic impact")
line("GOTV changes the winner", pct(gotvDecided / N), ">= 10%", gotvDecided / N >= 0.1)
line("Average GOTV spend per player", string.format("$%.1f", gotvSpend / N))
line("Week-12 projected leader loses", pct(projectionWrong / N))

-- Debates: recount the final board with the debates' support shifts subtracted
-- (same election noise), like the GOTV check. A paired replay with debates off
-- was tried first and rejected: the bots react to a different board, so the two
-- matches diverge and the number mostly measures chaos (D-017 finding 6).
line("Debates change the winner (counterfactual)", pct(debateDecided / N), ">= 10%", debateDecided / N >= 0.1)
line("Average EV the debates swing", string.format("%.1f EV", debateShiftEV / N))
for _, id in ids do
	local rate = topicWins[id] / math.max(1, topicGames[id])
	line(`Debate topic win rate: {id}`, pct(rate))
end
-- The focus (D-044). Informational: an uncontested focus wins its topic 81% of
-- the time (Config.spec pins the odds), but two bots that need the same states
-- focus on the same topic nearly always, and then the focuses cancel.
local focusRate = focusWon / math.max(1, focusPlayed)
line("Focused topic won by its focuser", pct(focusRate))
line("Both focused on the same topic", pct(sameFocus / math.max(1, debatesPlayed)))

-- Choice stances (D-039): the same counterfactual recount with the stances'
-- shifts subtracted, plus how often the bot takes each slot. Informational: two
-- bots that value the same close states take the same stance nine times in ten,
-- and identical stances cancel in margin terms (D-041), so the recount understates
-- what the decision is worth; the RandomStance check below is the gate.
line("Choice stances change the winner (counterfactual)", pct(stanceDecided / N))
line("Average EV the stances swing", string.format("%.1f EV", stanceShiftEV / N))
line("Choice events per match", string.format("%.2f", choiceWeeks / N))
local taken = 0
for _, count in stanceTaken do
	taken += count
end
local shares = {}
for _, id in { "A", "B", "C" } do
	table.insert(shares, `{id} {pct((stanceTaken[id] or 0) / math.max(1, taken))}`)
end
line("Stances taken (A / B / C)", table.concat(shares, " / "))
line("Both players took the same stance", pct(sameStance / math.max(1, choiceWeeks)))

-- ---------------------------------------------------------------- side checks

local function versus(style: any, n: number): number
	local styleWins = 0
	for k = 1, n do
		local seed = 100000 + k
		local cands = pairFor(seed)
		local styles = if k % 2 == 0 then { style, "Balanced" } else { "Balanced", style }
		local slot = if k % 2 == 0 then 1 else 2
		local result = Play.match(config, seed, cands, styles :: any)
		if result.winner == slot then
			styleWins += 1
		end
	end
	return styleWins / n
end

header("Bots vs the balanced bot")
local sideN = math.max(100, math.floor(N / 5))
local randomRate = versus("Random", math.max(50, math.floor(sideN / 2)))
line("Random bot win rate", pct(randomRate), "<= 5%", randomRate <= 0.05)
for _, style in { "FundraiseOnly", "RallyOnly", "AttackOnly", "NeverPoll" } do
	local rate = versus(style, sideN)
	line(`{style} win rate`, pct(rate), "< 55%", rate < 0.55)
end
local sandbag = versus("Sandbag", sideN)
line("Sandbag win rate", pct(sandbag), "<= 50%", sandbag <= 0.5)
-- Skill expression (D-039): the same bot with random stances must lose to the
-- bot that reads the map, measurably.
local randomStance = versus("RandomStance", sideN * 2)
line("RandomStance win rate", pct(randomStance), "<= 45%", randomStance <= 0.45)
-- The same for the debate focus (D-044): the topic that covers the EV you need beats a random one.
-- Informational: two bots that need the same states focus on the same topic
-- nearly every time, and the focuses cancel, so a random pick does about as
-- well (D-044). The NoFocus check below is what shows the focus is worth taking.
local randomFocus = versus("RandomFocus", sideN * 2)
line("RandomFocus win rate", pct(randomFocus))
local noFocus = versus("NoFocus", sideN * 2)
line("NoFocus win rate (the timeout default)", pct(noFocus), "<= 45%", noFocus <= 0.45)

-- Niche issues hit harder (D-047): running on the biggest or the smallest issues
-- of the match must not beat the standard bot's mixed platform.
for _, style in { "TopIssues", "NicheIssues" } do
	local rate = versus(style, sideN * 2)
	line(`{style} win rate`, pct(rate), "45-55%", rate >= 0.45 and rate <= 0.55)
end

print("")
print(string.format("Total time %.1fs", os.clock() - started))
if #flags == 0 then
	print("No red flags.")
else
	print(`{#flags} red flag(s):`)
	for _, flag in flags do
		print("  - " .. flag)
	end
end
