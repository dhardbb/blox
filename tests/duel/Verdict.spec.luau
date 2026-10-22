--!strict
-- The duel harness's verdict rules (tests/duel/Verdict.luau): which command
-- lines are info only, what a command file that locked nothing is called, and
-- which state the refreshed screen previews. Playtest 2, bugs 2 and 3.

local Test = require("@testlib/Test")
local Verdict = require("./Verdict")

local describe, it, expect = Test.describe, Test.it, Test.expect

describe("Duel verdict: info commands (playtest 2, bug 2)", function()
	it("treats rules, help, show, bank and resync as info at any stage", function()
		for _, line in { "rules", "RULES", "help", "show OH", "show", "bank", "resync", "skip" } do
			expect(Verdict.kind(line)):toBe("Info")
		end
		expect(Verdict.kind("pass")):toBe("Move")
		expect(Verdict.kind("plan rally OH jobs")):toBe("Move")
		expect(Verdict.kind("auto")):toBe("Move")
		expect(Verdict.kind("dance")):toBe("Move")
		expect(Verdict.kind("queue")):toBe("Blocked")
	end)

	it("an info-only file gets a neutral INFO verdict, a refresh and no attempt", function()
		local info = Verdict.outcome(false)
		expect(string.sub(info.status, 1, 5)):toBe("INFO:")
		expect(string.find(info.status, "REJECT", 1, true)):toBe(nil)
		expect(info.usesAttempt):toBe(false)
		expect(info.refresh):toBe(true)
	end)

	it("a file with a rejected move still uses an attempt and starts a new TURN", function()
		local rejected = Verdict.outcome(true)
		expect(string.sub(rejected.status, 1, 9)):toBe("REJECTED:")
		expect(rejected.usesAttempt):toBe(true)
		expect(rejected.refresh):toBe(false)
	end)
end)

describe("Duel verdict: the refreshed screen follows show (playtest 2, bug 3)", function()
	it("previews the state of the last valid show in the file", function()
		expect(Verdict.focus({ "show ny", "rules" })):toBe("NY")
		expect(Verdict.focus({ "show NY", "help", "show tx" })):toBe("TX")
		expect(Verdict.focus({ "show tx", "show" })):toBe("TX")
		expect(Verdict.focus({ "rules", "help" })):toBe(nil)
		expect(Verdict.focus({ "plan rally OH jobs" })):toBe(nil)
	end)
end)
