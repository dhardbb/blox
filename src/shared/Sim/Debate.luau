--!strict
-- Debates (docs/PLAN.md "Debates", D-010). Topics are drawn from the seed when the
-- match starts; prep comes from the plan of the week before. Resolves at the start
-- of the debate week.
--
-- topicScore(P) = prep + platform bonus + debate stat + seeded roll (0..DEBATE_ROLL_MAX)
-- The unique highest score wins the topic (+DEBATE_TOPIC_WIN national); an exact tie
-- gives it to nobody. Winning every topic adds DEBATE_SWEEP and momentum in every
-- battleground. Losing a topic you put no prep on costs DEBATE_GAFFE.

local ConfigModule = require("./Config")
local Issues = require("./Issues")
local Plan = require("./Plan")
local Rng = require("./Rng")
local State = require("./State")
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

-- Resolves the debate for the current week. Mutates `match`.
function Debate.resolve(config: Config, match: MatchState): State.DebateResult
	local week = match.week
	local topics = match.debateTopics[week]
	assert(topics, `no debate in week {week}`)
	local n = #match.players
	local rng = Rng.fork(match.rng, `debate:{week}`)

	local prep: { { number } } = {}
	local scores: { { number } } = {}
	for p, player in match.players do
		prep[p] = player.debatePrep or Plan.defaultPrep(config, player.profile.debatePrep)
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
	local wins = table.create(n, 0)
	local national = table.create(n, 0)
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
			national[winner] += config.DEBATE_TOPIC_WIN
			for p = 1, n do
				if p ~= winner and prep[p][t] == 0 then
					national[p] -= config.DEBATE_GAFFE
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
	Support.national(config, match.states, national)

	for _, player in match.players do
		player.debatePrep = nil
	end
	local result: State.DebateResult = {
		week = week,
		topics = topics,
		prep = prep,
		scores = scores,
		winners = winners,
		national = national,
	}
	table.insert(match.debates, result)
	return result
end

return table.freeze(Debate)
