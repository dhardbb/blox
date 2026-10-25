--!strict
-- The duel harness's bot seat (tests/duel/Seats.luau): `--bot 2:Easy` lets one
-- agent play the practice bot through the same files (the Easy-bot study).

local Test = require("@testlib/Test")
local Seats = require("./Seats")

local describe, it, expect = Test.describe, Test.it, Test.expect

describe("Duel seats: --bot SEAT:LEVEL", function()
	it("reads seat 2 and any of the four levels, in any case", function()
		local easy = Seats.parse("2:Easy")
		expect(easy and easy.seat):toBe(2)
		expect(easy and easy.level):toBe("Easy")
		local hard = Seats.parse("2:hard")
		expect(hard and hard.level):toBe("Hard")
		local spaced = Seats.parse(" 2 : EXTREME ")
		expect(spaced and spaced.level):toBe("Extreme")
		local medium = Seats.parse("2:Medium")
		expect(medium and medium.level):toBe("Medium")
	end)

	it("refuses seat 1: a practice match seats the person first", function()
		local seat, message = Seats.parse("1:Easy")
		expect(seat):toBe(nil)
		expect(string.find(message or "", "seat must be 2", 1, true) ~= nil):toBe(true)
	end)

	it("refuses an unknown level instead of quietly playing Medium", function()
		local seat, message = Seats.parse("2:Impossible")
		expect(seat):toBe(nil)
		expect(string.find(message or "", "Easy, Medium, Hard, Extreme", 1, true) ~= nil):toBe(true)
	end)

	it("refuses a value that is not SEAT:LEVEL", function()
		for _, bad in { "Easy", "2", "2:", ":Easy", "two:Easy", "2:Easy:x" } do
			local seat, message = Seats.parse(bad)
			expect(seat):toBe(nil)
			expect(string.find(message or "", "SEAT:LEVEL", 1, true) ~= nil):toBe(true)
		end
		local missing, message = Seats.parse(nil)
		expect(missing):toBe(nil)
		expect(string.find(message or "", "SEAT:LEVEL", 1, true) ~= nil):toBe(true)
	end)

	it("one person joins and sends a Practice request at that level", function()
		local bot = Seats.parse("2:Easy")
		expect(Seats.people(bot)):toBe(1)
		expect(Seats.people(nil)):toBe(2)
		local request = Seats.request(bot)
		expect(request and request.op):toBe("Practice")
		expect(request and request.difficulty):toBe("Easy")
		expect(Seats.request(nil)):toBe(nil)
		expect(Seats.botName(bot :: any)):toBe("bot (Easy)")
	end)
end)
