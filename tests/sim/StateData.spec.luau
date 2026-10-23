--!strict
-- StateData invariants: EV total, symmetric adjacency, connectivity, and flavor issues.
-- The per-match issue map is tests/sim/IssueMap.spec.

local Test = require("@testlib/Test")
local StateData = require("@sim/StateData")
local Issues = require("@sim/Issues")

local describe, it, expect = Test.describe, Test.it, Test.expect

local states = StateData.list
local byId = StateData.byId

describe("StateData", function()
	it("has 51 records with unique ids", function()
		expect(#states):toBe(51)
		local seen = {}
		for _, s in states do
			expect(seen[s.id]):toBe(nil)
			seen[s.id] = true
			expect(byId[s.id]):toBe(s)
		end
	end)

	it("electoral votes sum to 538", function()
		local total = 0
		for _, s in states do
			total += s.ev
		end
		expect(total):toBe(538)
	end)

	it("matches 2024 apportionment spot checks", function()
		expect(byId.CA.ev):toBe(54)
		expect(byId.TX.ev):toBe(40)
		expect(byId.FL.ev):toBe(30)
		expect(byId.NY.ev):toBe(28)
		expect(byId.PA.ev):toBe(19)
		expect(byId.DC.ev):toBe(3)
	end)

	it("every adjacency is symmetric, known, and not a self-loop", function()
		for _, s in states do
			for _, other in s.adjacent do
				if other == s.id then
					error(`{s.id} lists itself`)
				end
				local o = byId[other]
				if o == nil then
					error(`{s.id} lists unknown state {other}`)
				end
				if not table.find(o.adjacent, s.id) then
					error(`{s.id} -> {other} is not symmetric`)
				end
			end
		end
	end)

	it("lists no duplicate neighbors", function()
		for _, s in states do
			local seen = {}
			for _, other in s.adjacent do
				if seen[other] then
					error(`{s.id} lists {other} twice`)
				end
				seen[other] = true
			end
		end
	end)

	it("Alaska and Hawaii are flight-only; every other state has a neighbor", function()
		expect(#byId.AK.adjacent):toBe(0)
		expect(#byId.HI.adjacent):toBe(0)
		for _, s in states do
			if s.id ~= "AK" and s.id ~= "HI" and #s.adjacent == 0 then
				error(`{s.id} has no neighbors`)
			end
		end
	end)

	it("the contiguous 48 + DC form one connected graph", function()
		local seen = { OH = true }
		local queue = { "OH" }
		local head = 1
		while queue[head] do
			for _, other in byId[queue[head]].adjacent do
				if not seen[other] then
					seen[other] = true
					table.insert(queue, other)
				end
			end
			head += 1
		end
		expect(#queue):toBe(49)
	end)

	it("every state has two distinct valid flavor issues (the issue draw weights them, D-047)", function()
		for _, s in states do
			expect(#s.flavor):toBe(2)
			expect(Issues.isIssue(s.flavor[1]) and Issues.isIssue(s.flavor[2])):toBe(true)
			if s.flavor[1] == s.flavor[2] then
				error(`{s.id} repeats an issue`)
			end
		end
	end)

	it("every region is valid and holds 3-9 states", function()
		local counts = {}
		for _, s in states do
			counts[s.region] = (counts[s.region] or 0) + 1
		end
		for _, region in Issues.regions do
			local n = counts[region] or 0
			if n < 3 or n > 9 then
				error(`{region} has {n} states`)
			end
			counts[region] = nil
		end
		expect(next(counts)):toBe(nil)
	end)

	it("has positive population and plausible coordinates", function()
		for _, s in states do
			expect(s.pop):toBeGreaterThan(0)
			expect(s.lat > 18 and s.lat < 72 and s.lon > -170 and s.lon < -66):toBe(true)
		end
	end)
end)
