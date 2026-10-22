--!strict
-- Server entry point: starts the remotes and the match service, then plays one
-- bot-vs-bot match through the simulation as a self-test, so the humans can
-- confirm in Studio that the Sim modules load and run under Roblox.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Version = require(ReplicatedStorage.Shared.Version)
local Sim = ReplicatedStorage.Shared.Sim
local Config = require(Sim.Config)
local Bot = require(Sim.Bot)
local Candidates = require(Sim.Candidates)
local Match = require(Sim.Match)
local Rng = require(Sim.Rng)
local View = require(Sim.View)
local MatchService = require(script.Parent.MatchService)
local Replication = require(script.Parent.Replication)

Replication.init(MatchService.handle)
MatchService.start()
print(`[270] server up: v{Version.VERSION} ({Version.PHASE}), {Config.defaults.WEEKS} weeks`)

local function selfTest(): string
	local config = Config.defaults
	local seed = math.floor(workspace:GetServerTimeNow())
	local picker = Rng.new(seed)
	local candidates = {
		Candidates.ids[Rng.nextInt(picker, 1, #Candidates.ids)],
		Candidates.ids[Rng.nextInt(picker, 1, #Candidates.ids)],
	}
	local rngs = { Rng.fork(picker, "bot1"), Rng.fork(picker, "bot2") }
	local started = os.clock()
	local match = Match.new(config, seed, { "bot1", "bot2" })
	local phases = 0
	while match.phase ~= "Done" do
		local inputs = {}
		if Match.wantsInput(match) then
			for p = 1, 2 do
				inputs[p] = Bot.act(config, View.build(config, match, p), rngs[p], candidates[p])
			end
		end
		match = Match.advance(config, match, inputs)
		phases += 1
	end
	local result = match.election
	assert(result, "match finished without an election result")
	local names = {}
	for p = 1, 2 do
		names[p] = Candidates.profile(config, candidates[p]).name
	end
	return `[270] sim self-test: seed {seed}: {names[1]} {result.ev[1]} - {result.ev[2]} {names[2]}, `
		.. `winner {names[result.winner]}, {phases} phases in {math.floor((os.clock() - started) * 1000)} ms`
end

local ok, message = pcall(selfTest)
if ok then
	print(message)
else
	warn(`[270] sim self-test FAILED: {message}`)
end
