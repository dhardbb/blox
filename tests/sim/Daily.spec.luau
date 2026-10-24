--!strict
-- The Daily Race's day -> race derivation (D-080): UTC dates, the seeded
-- candidate rotation (never the same candidate two days running, every cycle
-- uses the whole roster), the bot's candidate and level, and the seed.

local Test = require("@testlib/Test")
local Candidates = require("@sim/Candidates")
local Config = require("@sim/Config")
local Daily = require("@sim/Daily")
local Match = require("@sim/Match")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults
local TODAY = 20750 -- 2026-10-24
local N = #Candidates.ids

describe("Daily: days and dates", function()
	it("cuts Unix time into UTC days", function()
		expect(Daily.dayOf(0)):toBe(0)
		expect(Daily.dayOf(86399)):toBe(0)
		expect(Daily.dayOf(86400)):toBe(1)
		expect(Daily.dayOf(-1)):toBe(-1)
		expect(Daily.dayOf(TODAY * 86400 + 3600)):toBe(TODAY)
		expect(Daily.endsAt(TODAY)):toBe((TODAY + 1) * 86400)
	end)

	it("names the day as YYYY-MM-DD, leap days included", function()
		expect(Daily.dateKey(0)):toBe("1970-01-01")
		expect(Daily.dateKey(-1)):toBe("1969-12-31")
		expect(Daily.dateKey(TODAY)):toBe("2026-10-24")
		expect(Daily.dateKey(19782)):toBe("2024-02-29")
		expect(Daily.dateKey(19783)):toBe("2024-03-01")
		expect(Daily.dateKey(11017)):toBe("2000-03-01")
		expect(Daily.dateKey(11016)):toBe("2000-02-29")
	end)

	it("knows the weekday (1 = Sunday)", function()
		expect(Daily.weekday(0)):toBe(5) -- a Thursday
		expect(Daily.weekday(TODAY)):toBe(7) -- a Saturday
	end)
end)

describe("Daily: the candidate rotation", function()
	it("never runs the same candidate two days in a row (400 days)", function()
		local before = Daily.candidate(TODAY - 1)
		for day = TODAY, TODAY + 399 do
			local now = Daily.candidate(day)
			if now == before then
				error(`{Daily.dateKey(day)} repeats {now} from the day before`, 0)
			end
			before = now
		end
	end)

	it("uses every candidate once in each cycle of one day per candidate", function()
		local first = math.floor(TODAY / N)
		for cycle = first, first + 49 do
			local seen: { [string]: number } = {}
			for k = 0, N - 1 do
				local id = Daily.candidate(cycle * N + k)
				seen[id] = (seen[id] or 0) + 1
			end
			for _, id in Candidates.ids do
				expect(seen[id]):toBe(1)
			end
		end
	end)

	it("any 30 days in a row cover the whole roster and never repeat back to back", function()
		for start = TODAY, TODAY + 60, 7 do
			local seen: { [string]: boolean } = {}
			local count = 0
			for day = start, start + 29 do
				local id = Daily.candidate(day)
				if not seen[id] then
					seen[id] = true
					count += 1
				end
				expect(id ~= Daily.candidate(day + 1)):toBe(true)
			end
			expect(count):toBe(N)
		end
	end)

	it("fixes a cycle that would open with the last cycle's closer (the swap path runs)", function()
		local swaps = 0
		for cycle = 0, 999 do
			local order = Daily.cycle(cycle)
			local previous = Daily.cycle(cycle - 1)
			expect(order[1] ~= previous[N]):toBe(true)
			local sorted = table.clone(order)
			table.sort(sorted)
			local ids = table.clone(Candidates.ids) :: { string }
			table.sort(ids)
			expect(sorted):toEqual(ids)
			-- The last cycle's closer second: one cycle in eight by chance, and one
			-- in eight more that was swapped there.
			if order[2] == previous[N] then
				swaps += 1
			end
		end
		expect(swaps > 180 and swaps < 330):toBe(true)
	end)

	it("is the same for everyone: a pure function of the day", function()
		for day = TODAY, TODAY + 20 do
			expect(Daily.race(C, day)):toEqual(Daily.race(C, day))
		end
	end)
end)

describe("Daily: the race", function()
	it("gives the bot another candidate, at the Config level (Hard)", function()
		expect(C.DAILY_BOT_LEVEL):toBe("Hard")
		for day = TODAY, TODAY + 99 do
			local race = Daily.race(C, day)
			expect(Candidates.exists(race.candidate)):toBe(true)
			expect(Candidates.exists(race.botCandidate)):toBe(true)
			expect(race.botCandidate ~= race.candidate):toBe(true)
			expect(race.level):toBe("Hard")
			expect(race.date):toBe(Daily.dateKey(day))
			expect(race.endsAt):toBe((day + 1) * 86400)
		end
	end)

	it("draws a seed per day, in range and different from day to day", function()
		local seen: { [number]: boolean } = {}
		local distinct = 0
		for day = TODAY, TODAY + 199 do
			local seed = Daily.race(C, day).seed
			expect(seed >= 1 and seed <= 2 ^ 31 - 1 and seed == math.floor(seed)):toBe(true)
			if not seen[seed] then
				seen[seed] = true
				distinct += 1
			end
		end
		expect(distinct):toBe(200)
	end)

	it("the seed builds the same map for every player that day", function()
		local race = Daily.race(C, TODAY)
		local a = Match.new(C, race.seed, { "1", "bot" })
		local b = Match.new(C, race.seed, { "2", "bot" })
		for i, s in a.states do
			expect(s.lean):toBe(b.states[i].lean)
			expect(s.leanTo):toBe(b.states[i].leanTo)
		end
		expect(a.issueMap):toEqual(b.issueMap)
		expect(a.eventDeck):toEqual(b.eventDeck)
		expect(a.debateTopics):toEqual(b.debateTopics)
	end)
end)
