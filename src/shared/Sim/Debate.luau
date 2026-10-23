--!strict
-- Debates (docs/PLAN.md "Debates", D-010, D-040, D-044). Topics are drawn from
-- the seed when the match starts; each candidate's focus topic comes from the
-- Focus decision that opens the debate week (Sim/Decision). Resolves right after
-- it, before the week's plan.
--
-- topicScore(P) = focus + platform bonus + debate stat + seeded roll (0..DEBATE_ROLL_MAX)
-- where focus is the candidate's focusEdge on the one topic they focused on and
-- 0 on the others. The unique highest score wins the topic; an exact tie gives
-- it to nobody.
--
-- Debates move states, not an average (D-040). Winning a topic adds
-- DEBATE_TOPIC_WIN support in every state where the topic is a top issue
-- (Debate.topicStates: the match's issue map, D-047) plus a flat
-- DEBATE_TOPIC_NATIONAL in every state. A candidate who took no focus at all
-- (the Focus decision timed out) gaffes on every topic they lose:
-- -DEBATE_GAFFE in the topic's states. Winning every topic adds a flat
-- DEBATE_SWEEP everywhere and momentum in every battleground. Every point asked
-- for is public arithmetic, recorded in DebateResult.moves; the public polls are
-- then republished with the same error terms so the map shows the debate at
-- once, and DebateResult.flips lists the states whose poll leader changed.

local ConfigModule = require("./Config")
local IssueMap = require("./IssueMap")
local Issues = require("./Issues")
local Polls = require("./Polls")
local Rng = require("./Rng")
local State = require("./State")
local StateData = require("./StateData")
local Support = require("./Support")
local Types = require("../Types")

type Config = ConfigModule.Config
type MatchState = State.MatchState

local Debate = {}

-- Seeded topics for every debate week.
function Debate.drawTopics(config: Config, rng: Rng.Rng): { [number]: { Types.Issue } }
	local topics: { [number]: { Types.Issue } } = {}
	for _, week in config.DEBATE_WEEKS do
		local pool: { Types.Issue } = table.clone(Issues.list)
		Rng.shuffle(Rng.fork(rng, `debate-topics:{week}`), pool)
		local chosen: { Types.Issue } = {}
		for k = 1, config.DEBATE_TOPICS do
			chosen[k] = pool[k]
		end
		topics[week] = chosen
	end
	return topics
end

-- The next debate week at or after `week`, or nil.
function Debate.nextWeek(config: Config, week: number): number?
	for _, w in config.DEBATE_WEEKS do
		if w >= week then
			return w
		end
	end
	return nil
end

-- Ids of the states where `topic` is a top issue on this match's issue map, in
-- StateData order. Public: the client may call it to preview what a topic win
-- would move.
function Debate.topicStates(issueMap: IssueMap.IssueMap, topic: Types.Issue): { string }
	local out: { string } = {}
	for i, record in StateData.list do
		if table.find(issueMap[i], topic) then
			table.insert(out, record.id)
		end
	end
	return out
end

-- Chance to win, tie and lose a topic when your fixed score (focus + platform +
-- stat) leads the opponent's by `edge`, against two uniform 0..DEBATE_ROLL_MAX rolls.
function Debate.odds(config: Config, edge: number): (number, number, number)
	local faces = config.DEBATE_ROLL_MAX + 1
	local win, tie = 0, 0
	for mine = 0, config.DEBATE_ROLL_MAX do
		for theirs = 0, config.DEBATE_ROLL_MAX do
			local diff = edge + mine - theirs
			if diff > 0 then
				win += 1
			elseif diff == 0 then
				tie += 1
			end
		end
	end
	local n = faces * faces
	return win / n, tie / n, (n - win - tie) / n
end

-- The state-targeted points (topic wins and gaffes) a debate outcome asks for:
-- one StateMove per state that moves, in StateData order. Public arithmetic.
function Debate.moves(
	config: Config,
	issueMap: IssueMap.IssueMap,
	n: number,
	topics: { Types.Issue },
	winners: { number },
	gaffes: { { boolean } }
): { State.StateMove }
	local out: { State.StateMove } = {}
	for i, record in StateData.list do
		local points = table.create(n, 0)
		local any = false
		for t, topic in topics do
			if table.find(issueMap[i], topic) then
				local winner = winners[t]
				if winner > 0 then
					points[winner] += config.DEBATE_TOPIC_WIN
					any = true
				end
				for p = 1, n do
					if gaffes[p][t] then
						points[p] -= config.DEBATE_GAFFE
						any = true
					end
				end
			end
		end
		if any then
			table.insert(out, { state = record.id, points = points })
		end
	end
	return out
end

-- Resolves the debate for the current week. Mutates `match`.
function Debate.resolve(config: Config, match: MatchState): State.DebateResult
	local week = match.week
	local topics = match.debateTopics[week]
	assert(topics, `no debate in week {week}`)
	local n = #match.players
	local rng = Rng.fork(match.rng, `debate:{week}`)

	local prep: { { number } } = {}
	local focus: { number } = {}
	local scores: { { number } } = {}
	for p, player in match.players do
		local chosen = player.debateFocus
		focus[p] = if chosen then table.find(topics, chosen) or 0 else 0
		prep[p] = table.create(#topics, 0)
		if focus[p] > 0 then
			prep[p][focus[p]] = player.profile.focusEdge
		end
		scores[p] = {}
	end
	for t, topic in topics do
		for p, player in match.players do
			local platform = if table.find(player.platform, topic) then config.DEBATE_PLATFORM_BONUS else 0
			local roll = Rng.nextInt(rng, 0, config.DEBATE_ROLL_MAX)
			scores[p][t] = prep[p][t] + platform + player.profile.debateStat + roll
		end
	end

	local winners: { number } = {}
	local gaffes: { { boolean } } = {}
	local wins = table.create(n, 0)
	local national = table.create(n, 0)
	for p = 1, n do
		gaffes[p] = table.create(#topics, false)
	end
	for t = 1, #topics do
		local best, winner = -math.huge, 0
		for p = 1, n do
			local score = scores[p][t]
			if score > best then
				best, winner = score, p
			elseif score == best then
				winner = 0
			end
		end
		winners[t] = winner
		if winner > 0 then
			wins[winner] += 1
			national[winner] += config.DEBATE_TOPIC_NATIONAL
			for p = 1, n do
				if p ~= winner and focus[p] == 0 then
					gaffes[p][t] = true
				end
			end
		end
	end
	for p = 1, n do
		if wins[p] == #topics then
			national[p] += config.DEBATE_SWEEP
			for _, s in match.states do
				if s.battleground then
					s.momentum[p] =
						math.min(config.MOMENTUM_CAP, s.momentum[p] + config.DEBATE_SWEEP_MOMENTUM)
				end
			end
		end
	end

	-- Apply the targeted and flat points from one snapshot (D-001): gains use the
	-- normal split, losses go to undecided. Record what each state's support
	-- actually moved by, so the harness can recount the election without debates.
	local moves = Debate.moves(config, match.issueMap, n, topics, winners, gaffes)
	local byState: { [string]: State.StateMove } = {}
	for _, move in moves do
		byState[move.state] = move
	end
	for _, s in match.states do
		local before = table.clone(s.support)
		local delta = Support.zero(s)
		local du = 0
		local move = byState[s.id]
		for p = 1, n do
			local x = national[p] + (if move then move.points[p] else 0)
			if x > 0 then
				du += Support.addGain(config, s, p, x, delta)
			elseif x < 0 then
				du += Support.addLoss(p, -x, delta)
			end
		end
		Support.apply(s, delta, du)
		for p = 1, n do
			s.debateShift[p] += s.support[p] - before[p]
		end
	end
	local flips = Polls.refresh(match)

	for _, player in match.players do
		player.debateFocus = nil
	end
	local result: State.DebateResult = {
		week = week,
		topics = topics,
		focus = focus,
		prep = prep,
		scores = scores,
		winners = winners,
		gaffes = gaffes,
		national = national,
		moves = moves,
		flips = flips,
	}
	table.insert(match.debates, result)
	return result
end

return table.freeze(Debate)
