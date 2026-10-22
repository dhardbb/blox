--!strict
-- Phase 0 smoke test: shared modules load under Lune.

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local Version = require("@shared/Version")

local describe, it, expect = Test.describe, Test.it, Test.expect

describe("Smoke", function()
	it("loads Config", function()
		expect(Config.defaults.WEEKS):toBe(12)
	end)

	it("Config is frozen", function()
		expect(function()
			(Config.defaults :: any).WEEKS = 1
		end):toThrow()
	end)

	it("has a version string", function()
		expect(type(Version.VERSION)):toBe("string")
	end)
end)
