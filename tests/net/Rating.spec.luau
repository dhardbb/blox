--!strict
-- Elo math and the saved player profile: pure, no engine.

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local Profile = require("@net/Profile")
local Rating = require("@net/Rating")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

-- A rated win or loss against `opponent`.
local function rated(won: boolean, opponent: number?, candidate: string?): Profile.Result
	return {
		at = 1000,
		reason = "Election",
		rated = true,
		won = won,
		candidate = candidate or "hale",
		opponentCandidate = "reyes",
		opponentRating = opponent or 1000,
		evFor = if won then 300 else 238,
		evAgainst = if won then 238 else 300,
	}
end

describe("Rating", function()
	it("expects an even match to be 50/50, and a 400-point edge to be 10 to 1", function()
		expect(Rating.expected(1000, 1000)):toBeCloseTo(0.5, 1e-9)
		expect(Rating.expected(1400, 1000)):toBeCloseTo(10 / 11, 1e-9)
		expect(Rating.expected(1000, 1400)):toBeCloseTo(1 / 11, 1e-9)
	end)

	it("expected scores of two players add to 1", function()
		for _, pair in { { 1000, 1100 }, { 1500, 900 }, { 100, 2400 } } do
			expect(Rating.expected(pair[1], pair[2]) + Rating.expected(pair[2], pair[1])):toBeCloseTo(1, 1e-9)
		end
	end)

	it("moves an even match by K/2 and uses Config.ELO_K", function()
		expect(Rating.delta(C, 1000, 1000, 1)):toBe(C.ELO_K // 2)
		expect(Rating.delta(C, 1000, 1000, 0)):toBe(-(C.ELO_K // 2))
		expect(Rating.delta(C, 1000, 1000, 0.5)):toBe(0)
		local double = table.clone(C)
		double.ELO_K = 64
		expect(Rating.delta(double, 1000, 1000, 1)):toBe(32)
	end)

	it("pays an upset more than a favourite win", function()
		local upset = Rating.delta(C, 1000, 1400, 1)
		local favourite = Rating.delta(C, 1400, 1000, 1)
		expect(upset):toBeGreaterThan(favourite)
		expect(upset):toBe(29) -- 32 * (1 - 1/11) = 29.09
		expect(favourite):toBe(3) -- 32 * (1 - 10/11) = 2.91
	end)

	it("is zero-sum: the two players always move by equal and opposite amounts", function()
		for a = 800, 1600, 37 do
			for b = 800, 1600, 53 do
				local winnerDelta = Rating.delta(C, a, b, 1)
				local loserDelta = Rating.delta(C, b, a, 0)
				expect(winnerDelta + loserDelta):toBe(0)
				expect(Rating.next(C, a, b, true) - a):toBe(winnerDelta)
				expect(Rating.next(C, b, a, false) - b):toBe(loserDelta)
			end
		end
	end)

	it("never drops below the floor", function()
		expect(C.ELO_FLOOR):toBe(100)
		expect(Rating.next(C, 100, 1000, false)):toBe(100)
		expect(Rating.next(C, 105, 105, false)):toBe(100) -- would be 89
		expect(Rating.next(C, 110, 110, false)):toBe(100) -- would be 94
	end)
end)

describe("Profile.new", function()
	it("starts at Config.ELO_START with nothing played", function()
		local p = Profile.new()
		expect(p.version):toBe(Profile.VERSION)
		expect(p.rating):toBe(C.ELO_START)
		expect(p.games + p.wins + p.losses):toBe(0)
		expect(#p.recent):toBe(0)
		expect(next(p.perCandidate)):toBe(nil)
	end)
end)

describe("Profile.migrate", function()
	it("turns nil and non-tables into a fresh profile", function()
		expect(Profile.migrate(nil)):toEqual(Profile.new())
		for _, junk in { "hello", 42, true, function() end } do
			expect(Profile.migrate(junk)):toEqual(Profile.new())
		end
	end)

	it("never returns the table it was given", function()
		local raw = Profile.new()
		local migrated = Profile.migrate(raw)
		expect(migrated == raw):toBe(false)
		expect(migrated.perCandidate == raw.perCandidate):toBe(false)
	end)

	it("keeps a valid current profile as it is", function()
		local p = Profile.new()
		local a = Profile.applyResult(p, rated(true, 1100, "hale"))
		local b = Profile.applyResult(a, rated(false, 1050, "reyes"))
		expect(Profile.migrate(b)):toEqual(b)
	end)

	it("reads an older record with no version and fills what is missing", function()
		local migrated = Profile.migrate({ rating = 1234, wins = 5, losses = 2 })
		expect(migrated.version):toBe(Profile.VERSION)
		expect(migrated.rating):toBe(1234)
		expect(migrated.wins):toBe(5)
		expect(migrated.losses):toBe(2)
		expect(migrated.games):toBe(7) -- never fewer games than results
		expect(#migrated.recent):toBe(0)
	end)

	it("repairs garbage fields one by one", function()
		local migrated = Profile.migrate({
			version = "two",
			rating = 0 / 0,
			games = -4,
			wins = "many",
			losses = 3.7,
			perCandidate = { hale = { wins = 2, losses = "x" }, [5] = { wins = 1 }, reyes = "no" },
			recent = { "bad", { at = 5 }, 7 },
			practice = 12,
		})
		expect(migrated.rating):toBe(C.ELO_START)
		expect(migrated.wins):toBe(0)
		expect(migrated.losses):toBe(3)
		expect(migrated.games):toBe(3)
		expect(migrated.perCandidate):toEqual({ hale = { wins = 2, losses = 0 } })
		expect(#migrated.recent):toBe(0)
		expect(migrated.practice):toEqual({ games = 0, wins = 0, losses = 0 })
	end)

	it("keeps a saved color that is one of the six and drops anything else (D-055)", function()
		expect(Profile.migrate({ rating = 1100, color = "Emerald" }).color):toBe("Emerald")
		for _, bad in { "Gold", "emerald", 5, {} } do
			expect(Profile.migrate({ rating = 1100, color = bad }).color):toBe(nil)
		end
		-- A version-1 profile from before colors loads as auto, everything else kept.
		local old = Profile.migrate({ version = 1, rating = 1040, wins = 2, losses = 1, games = 3 })
		expect(old.color):toBe(nil)
		expect(old.rating):toBe(1040)
		expect(Profile.isFromFuture({ version = 1, color = "Teal" })):toBe(false)
	end)

	it("clamps a stored rating to the floor and rounds it", function()
		expect(Profile.migrate({ rating = -50 }).rating):toBe(C.ELO_FLOOR)
		expect(Profile.migrate({ rating = 1000.6 }).rating):toBe(1000)
	end)

	it("keeps only the last 10 valid recent matches", function()
		local recent = {}
		for k = 1, 14 do
			table.insert(recent, {
				at = k,
				opponentRating = 1000,
				candidate = "hale",
				opponentCandidate = "reyes",
				won = true,
				reason = "Election",
			})
		end
		local migrated = Profile.migrate({ recent = recent })
		expect(#migrated.recent):toBe(10)
		expect(migrated.recent[1].at):toBe(5)
		expect(migrated.recent[10].at):toBe(14)
	end)

	it("flags a record from a newer version", function()
		expect(Profile.isFromFuture({ version = Profile.VERSION + 1 })):toBe(true)
		expect(Profile.isFromFuture({ version = Profile.VERSION })):toBe(false)
		expect(Profile.isFromFuture(nil)):toBe(false)
		expect(Profile.isFromFuture({})):toBe(false)
	end)
end)

describe("Profile.applyResult", function()
	it("records a rated win: rating, totals, candidate record and recent", function()
		local before = Profile.new()
		local after, change = Profile.applyResult(before, rated(true, 1000, "hale"))
		expect(change):toEqual({ before = 1000, after = 1016, rated = true })
		expect(after.rating):toBe(1016)
		expect(after.games):toBe(1)
		expect(after.wins):toBe(1)
		expect(after.losses):toBe(0)
		expect(after.perCandidate.hale):toEqual({ wins = 1, losses = 0 })
		expect(#after.recent):toBe(1)
		expect(after.recent[1]):toEqual({
			at = 1000,
			opponentRating = 1000,
			candidate = "hale",
			opponentCandidate = "reyes",
			won = true,
			evFor = 300,
			evAgainst = 238,
			reason = "Election",
		})
	end)

	it("does not change the profile it was given", function()
		local before = Profile.new()
		local snapshot = Profile.migrate(before)
		Profile.applyResult(before, rated(true))
		expect(before):toEqual(snapshot)
	end)

	it("records a rated loss and tracks candidates separately", function()
		local p = Profile.new()
		p = Profile.applyResult(p, rated(true, 1000, "hale"))
		p = Profile.applyResult(p, rated(false, 1000, "hale"))
		p = Profile.applyResult(p, rated(false, 1000, "reyes"))
		expect(p.wins):toBe(1)
		expect(p.losses):toBe(2)
		expect(p.games):toBe(3)
		expect(p.perCandidate.hale):toEqual({ wins = 1, losses = 1 })
		expect(p.perCandidate.reyes):toEqual({ wins = 0, losses = 1 })
	end)

	it("keeps only the last 10 matches, oldest dropped", function()
		local p = Profile.new()
		for k = 1, 13 do
			local result = rated(k % 2 == 0, 1000, "hale")
			result.at = k
			p = Profile.applyResult(p, result)
		end
		expect(#p.recent):toBe(Profile.RECENT_MAX)
		expect(p.recent[1].at):toBe(4)
		expect(p.recent[10].at):toBe(13)
		expect(p.games):toBe(13)
	end)

	it("a forfeit is rated and has no final score", function()
		local result = rated(false, 1200, "hale")
		result.reason = "Forfeit"
		result.evFor, result.evAgainst = nil, nil
		local p, change = Profile.applyResult(Profile.new(), result)
		expect(change.rated):toBe(true)
		expect(p.rating < 1000):toBe(true)
		expect(p.recent[1].reason):toBe("Forfeit")
		expect(p.recent[1].evFor):toBe(nil)
	end)

	it("practice never changes the rating and keeps its own count", function()
		local result = rated(true, nil, "hale")
		result.rated = false
		result.opponentRating = nil
		local p, change = Profile.applyResult(Profile.new(), result)
		expect(change):toEqual({ before = 1000, after = 1000, rated = false })
		expect(p.rating):toBe(1000)
		expect(p.games + p.wins + p.losses):toBe(0)
		expect(#p.recent):toBe(0)
		expect(next(p.perCandidate)):toBe(nil)
		expect(p.practice):toEqual({ games = 1, wins = 1, losses = 0 })
		local lost = rated(false)
		lost.rated = false
		p = Profile.applyResult(p, lost)
		expect(p.practice):toEqual({ games = 2, wins = 1, losses = 1 })
	end)

	it("an abandoned match changes nothing at all", function()
		local result = rated(true)
		result.reason = "Abandoned"
		local before = Profile.new()
		local p, change = Profile.applyResult(before, result)
		expect(p):toEqual(Profile.new())
		expect(change.rated):toBe(false)
		result.rated = false
		expect(Profile.applyResult(before, result)):toEqual(before)
	end)

	it("two profiles settling the same rated match move equal and opposite", function()
		local a = Profile.migrate({ rating = 1180 })
		local b = Profile.migrate({ rating = 1043 })
		local newA, changeA = Profile.applyResult(a, rated(true, b.rating, "hale"))
		local newB, changeB = Profile.applyResult(b, rated(false, a.rating, "reyes"))
		expect(changeA.after - changeA.before):toBe(-(changeB.after - changeB.before))
		expect(newA.rating + newB.rating):toBe(1180 + 1043)
	end)

	it("summarises for the lobby", function()
		local p = Profile.applyResult(Profile.new(), rated(true))
		expect(Profile.summary(p)):toEqual({ rating = 1016, games = 1, wins = 1, losses = 0 })
	end)
end)

describe("Profile.withColor (D-055)", function()
	it("sets or clears the color and never touches the argument", function()
		local p = Profile.new()
		local picked, ok = Profile.withColor(p, "Violet")
		expect(ok):toBe(true)
		expect(picked.color):toBe("Violet")
		expect(p.color):toBe(nil)
		local cleared, clearedOk = Profile.withColor(picked, nil)
		expect(clearedOk):toBe(true)
		expect(cleared.color):toBe(nil)
		expect(picked.color):toBe("Violet")
	end)

	it("refuses a name that is not one of the six", function()
		local p = Profile.withColor(Profile.new(), "Teal")
		local same, ok = Profile.withColor(p, "Gold")
		expect(ok):toBe(false)
		expect(same == p):toBe(true)
		expect(Profile.isColor("Crimson")):toBe(true)
		expect(Profile.isColor("Red")):toBe(false)
	end)

	it("survives a round trip through migrate", function()
		local p = Profile.withColor(Profile.applyResult(Profile.new(), rated(true)), "Amber")
		expect(Profile.migrate(p)):toEqual(p)
	end)
end)
