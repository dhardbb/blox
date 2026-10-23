--!strict
-- Request schemas and the lobby: queue pairing, private codes, practice, capacity.

local Test = require("@testlib/Test")
local Config = require("@sim/Config")
local Lobby = require("@net/Lobby")
local Rng = require("@sim/Rng")
local Schemas = require("@net/Schemas")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

describe("Schemas.request", function()
	it("accepts every well-formed op", function()
		local good: { any } = {
			{ op = "Queue" },
			{ op = "Host" },
			{ op = "Join", code = "AB3CD" },
			{ op = "Practice" },
			{ op = "Leave" },
			{ op = "PrePick", pick = { candidate = "hale" } },
			{ op = "Submit", matchId = "m1", step = 3, input = { actions = {} } },
			{ op = "Bank", matchId = "m1", step = 3 },
			{ op = "Skip", matchId = "m1", step = 3 },
			{ op = "Resync" },
			{ op = "SetColor", color = "Crimson" },
		}
		for _, raw in good do
			local ok, reason, request = Schemas.request(raw)
			expect(reason):toBe(nil)
			expect(ok):toBe(true)
			expect((request :: any).op):toBe(raw.op)
		end
	end)

	it("drops unknown fields", function()
		local _, _, request = Schemas.request({ op = "Bank", matchId = "m", step = 1, admin = true })
		expect((request :: any).admin):toBe(nil)
	end)

	it("rejects malformed requests with reason codes", function()
		local deep: any = {}
		local cursor = deep
		for _ = 1, 10 do
			cursor.x = {}
			cursor = cursor.x
		end
		local cyclic: any = { op = "Queue" }
		cyclic.self = cyclic
		local wide = { op = "Queue", junk = {} }
		for k = 1, 1000 do
			wide.junk[k] = k
		end
		local cases: { { any } } = {
			{ nil, "BadShape" },
			{ "Queue", "BadShape" },
			{ { op = "Explode" }, "UnknownOp" },
			{ { op = 5 }, "UnknownOp" },
			{ { op = "Join", code = "abc" }, "BadCode" },
			{ { op = "Join", code = "ABCDEF" }, "BadCode" },
			{ { op = "Submit", matchId = "m", step = 1.5, input = {} }, "BadShape" },
			{ { op = "Submit", matchId = "m", step = 1 }, "BadShape" },
			{ { op = "Bank", step = 1 }, "BadShape" },
			{ { op = "Queue", text = string.rep("x", 65) }, "BadShape" },
			{ { op = "Queue", n = 0 / 0 }, "BadShape" },
			{ { op = "Queue", n = math.huge }, "BadShape" },
			{ { op = "Queue", f = print }, "BadShape" },
			{ { op = "Queue", deep = deep }, "BadShape" },
			{ cyclic, "BadShape" },
			{ wide, "BadShape" },
		}
		for _, case in cases do
			local ok, reason = Schemas.request(case[1])
			expect(ok):toBe(false)
			expect(reason):toBe(case[2])
		end
	end)

	it("a SetColor request carries an optional string color (D-055)", function()
		local ok, _, request = Schemas.request({ op = "SetColor", color = "Teal" })
		expect(ok):toBe(true)
		expect((request :: any).color):toBe("Teal")
		ok, _, request = Schemas.request({ op = "SetColor" })
		expect(ok):toBe(true)
		expect((request :: any).color):toBe(nil)
		for _, bad in { 5, true, {} } do
			local good, reason = Schemas.request({ op = "SetColor", color = bad })
			expect(good):toBe(false)
			expect(reason):toBe("BadShape")
		end
	end)

	it("a Host request may carry events = false, nothing else (D-027)", function()
		local ok, _, request = Schemas.request({ op = "Host", events = false })
		expect(ok):toBe(true)
		expect((request :: any).events):toBe(false)
		ok, _, request = Schemas.request({ op = "Host" })
		expect(ok):toBe(true)
		expect((request :: any).events):toBe(nil)
		for _, bad in { "no", 0, {} } do
			local good, reason = Schemas.request({ op = "Host", events = bad })
			expect(good):toBe(false)
			expect(reason):toBe("BadShape")
		end
		-- Other ops ignore the field: the public queue always has events on.
		_, _, request = Schemas.request({ op = "Queue", events = false })
		expect((request :: any).events):toBe(nil)
	end)

	it("lets a full 40-action plan through", function()
		local actions = {}
		for k = 1, C.PLAN_MAX_ACTIONS do
			actions[k] = { kind = "Gotv", state = "OH", units = 1, issue = "Jobs", target = 2 }
		end
		local ok = Schemas.request({
			op = "Submit",
			matchId = "m",
			step = 9,
			input = { actions = actions, prep = { 2, 2, 2 } },
		})
		expect(ok):toBe(true)
	end)

	it("never throws on random garbage", function()
		local rng = Rng.new(5)
		local atoms: { any } = { 1, -1, 0.5, "Submit", "op", true, {}, "AB3CD" }
		local keys = { "op", "code", "pick", "matchId", "step", "input" }
		for _ = 1, 300 do
			local raw: { [string]: any } = {}
			for _, key in keys do
				if Rng.nextFloat(rng) < 0.5 then
					raw[key] = atoms[Rng.nextInt(rng, 1, #atoms)]
				end
			end
			local ok, reason = Schemas.request(raw)
			expect(ok or type(reason) == "string"):toBe(true)
		end
	end)
end)

describe("Lobby", function()
	it("pairs the queue first come, first served", function()
		local lobby = Lobby.new(C)
		local outcome = Lobby.queue(lobby, "a")
		expect(outcome and outcome.kind):toBe("Waiting")
		expect(Lobby.state(lobby, "a")):toBe("Queued")
		local match = Lobby.queue(lobby, "b")
		expect(match and match.kind):toBe("Match")
		expect(match and match.players):toEqual({ "a", "b" })
		expect(Lobby.state(lobby, "a")):toBe("InMatch")
		expect(#lobby.queue):toBe(0)
		expect(select(2, Lobby.queue(lobby, "a"))):toBe("InMatch")
	end)

	it("private codes: host, join, no self-join, closed on leave", function()
		local lobby = Lobby.new(C)
		local hosted = Lobby.host(lobby, "a", "AB3CD")
		expect(hosted and hosted.code):toBe("AB3CD")
		expect(select(2, Lobby.host(lobby, "b", "AB3CD"))):toBe("CodeTaken")
		expect(select(2, Lobby.join(lobby, "a", "AB3CD"))):toBe("OwnCode")
		expect(select(2, Lobby.join(lobby, "b", "ZZZZZ"))):toBe("NoSuchCode")
		local match = Lobby.join(lobby, "b", "AB3CD")
		expect(match and match.players):toEqual({ "a", "b" })
		expect(lobby.codes.AB3CD):toBe(nil)

		Lobby.host(lobby, "c", "QQQQQ")
		Lobby.leave(lobby, "c")
		expect(select(2, Lobby.join(lobby, "d", "QQQQQ"))):toBe("NoSuchCode")
	end)

	it("a host can turn events off for their private match only", function()
		local lobby = Lobby.new(C)
		Lobby.host(lobby, "a", "AB3CD", { events = false })
		local match = Lobby.join(lobby, "b", "AB3CD")
		expect(match and match.events):toBe(false)
		expect(lobby.options.AB3CD):toBe(nil)
		Lobby.host(lobby, "c", "QQQQQ")
		match = Lobby.join(lobby, "d", "QQQQQ")
		expect(match and match.events):toBe(nil)
		Lobby.host(lobby, "e", "WWWWW", { events = false })
		Lobby.leave(lobby, "e")
		expect(lobby.options.WWWWW):toBe(nil)
		local queued = (Lobby.queue(lobby, "f"))
		queued = Lobby.queue(lobby, "g")
		expect(queued and queued.events):toBe(nil)
		local practice = Lobby.practice(lobby, "h")
		expect(practice and practice.events):toBe(nil)
	end)

	it("hosting takes a player out of the queue", function()
		local lobby = Lobby.new(C)
		Lobby.queue(lobby, "a")
		Lobby.host(lobby, "a", "AB3CD")
		expect(#lobby.queue):toBe(0)
		expect(Lobby.state(lobby, "a")):toBe("Hosting")
	end)

	it("caps concurrent matches, practice included, and frees seats when one ends", function()
		local lobby = Lobby.new(C)
		for k = 1, C.MATCHES_PER_SERVER do
			expect((Lobby.practice(lobby, `p{k}`)) ~= nil):toBe(true)
		end
		expect(select(2, Lobby.practice(lobby, "late"))):toBe("ServerFull")
		expect(select(2, Lobby.queue(lobby, "late"))):toBe("ServerFull")
		Lobby.ended(lobby, { "p1" })
		expect(Lobby.state(lobby, "p1")):toBe("Idle")
		expect((Lobby.practice(lobby, "late")) ~= nil):toBe(true)
	end)
end)
