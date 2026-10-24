--!strict
-- The plan preview (src/shared/UI/PlanPreview.luau, D-071): per state, the
-- plan's expected margin change summed over its actions, each from Explain's
-- estimate with the actions before it queued; the projected votes; and, on the
-- Campaign screen, faint tags on the map and the votes line under it while you
-- draft, gone once you lock in.

local Config = require("@sim/Config")
local Explain = require("@ui/Explain")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local PlanDraft = require("@ui/PlanDraft")
local PlanPreview = require("@ui/PlanPreview")
local Rig = require("./Rig")
local State = require("@sim/State")
local StateData = require("@sim/StateData")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local C = Config.defaults

local function near(got: number?, want: number, what: string)
	check(got ~= nil, `{what}: no value`)
	check(math.abs((got :: number) - want) < 1e-6, `{what}: got {got}, want {want}`)
end

local function view(): any
	return Rig.deepCopy(Fixtures.payload(C, "Plan").view)
end

local function draftOf(actions: { any }): PlanDraft.Draft
	local draft = PlanDraft.new()
	for _, action in actions do
		PlanDraft.add(draft, action)
	end
	return draft
end

-- Explain's margin for one action, given the actions queued before it.
local function margin(v: any, before: { any }, action: any): number
	local p = Explain.action(C, v, draftOf(before), action.state, action.kind, action.issue)
	return (p.you or 0) - (p.them or 0)
end

describe("PlanPreview (D-071)", function()
	it("shows nothing for an empty plan, and the header's votes either way", function()
		local v = view()
		local draft = PlanDraft.new()
		expect(next(PlanPreview.changes(C, v, draft))):toBe(nil)
		local now, after = PlanPreview.votes(C, v, draft)
		expect(now):toBe(v.projectedEV[v.you])
		expect(after):toBe(now)
		local tags, line = PlanPreview.build(C, v, draft)
		expect(next(tags)):toBe(nil)
		expect(line):toBe(nil)
	end)

	it("sums one state's actions, each estimated after the ones before it", function()
		local v = view()
		local ad = { kind = "Media", state = "OH" }
		local rally = { kind = "Rally", state = "PA" }
		local changes = PlanPreview.changes(C, v, draftOf({ ad, rally, ad }))
		local first = margin(v, {}, ad)
		local second = margin(v, { ad, rally }, ad)
		check(second < first, "a repeat ad should count for less")
		near(changes.OH, first + second, "OH")
		near(changes.PA, margin(v, {}, rally), "PA")
	end)

	it("counts ground game on election night and skips money, polls and pivots", function()
		local v = view()
		local changes = PlanPreview.changes(
			C,
			v,
			draftOf({
				{ kind = "Gotv", state = "WI", units = 2 },
				{ kind = "Fundraise", state = "TX" },
				{ kind = "Poll", state = "AZ" },
			})
		)
		near(changes.WI, 2 * C.GOTV_PER_UNIT, "WI")
		expect(changes.TX):toBe(nil)
		expect(changes.AZ):toBe(nil)
	end)

	it("adds an attack's damage to them and marks a plan that costs you margin", function()
		local v = view()
		local attack = { kind = "Attack", state = "OH" }
		local changes = PlanPreview.changes(C, v, draftOf({ attack }))
		local p = Explain.action(C, v, PlanDraft.new(), "OH", "Attack")
		near(changes.OH, (p.you or 0) - (p.them or 0), "OH")
		-- Backlash due: the attack costs you more than it takes from them.
		v.states[State.indexOf.OH].backlash = C.BACKLASH_THRESHOLD
		local p2 = Explain.action(C, v, PlanDraft.new(), "OH", "Attack")
		local cost = (p2.you or 0) - (p2.them or 0)
		local tags = PlanPreview.build(C, v, draftOf({ attack }))
		expect(tags.OH.negative == true):toBe(cost < 0)
		check(string.sub(tags.OH.text, 1, 1) == (if cost < 0 then "-" else "+"), `sign of {tags.OH.text}`)
	end)

	it("projects the votes: a state you would take the lead in moves its votes to you", function()
		local v = view()
		local me, them = v.you, if v.you == 1 then 2 else 1
		local oh = v.states[State.indexOf.OH]
		oh.poll = { support = table.create(#v.players, 0), undecided = 20 }
		oh.poll.support[me], oh.poll.support[them] = 39.8, 40
		v.projectedEV[me] = 200
		local draft = draftOf({ { kind = "Media", state = "OH" } })
		local now, after = PlanPreview.votes(C, v, draft)
		expect(now):toBe(200)
		expect(after):toBe(200 + StateData.byId.OH.ev)
		local _, line = PlanPreview.build(C, v, draft)
		expect(line):toBe(`Plan: 200 → {200 + StateData.byId.OH.ev} EV`)
		-- An unpolled state never moves the count (the header counts polls only).
		oh.poll = nil
		local _, after2 = PlanPreview.votes(C, v, draft)
		expect(after2):toBe(200)
	end)

	it("with three players, passing one rival is not enough while another still leads", function()
		local v = view()
		local me, them = v.you, if v.you == 1 then 2 else 1
		local third = #v.players + 1
		v.players[third] = Rig.deepCopy(v.players[them])
		v.players[third].id = "third"
		v.projectedEV[third] = 0
		local oh = v.states[State.indexOf.OH]
		oh.poll = { support = table.create(third, 0), undecided = 10 }
		oh.poll.support[me], oh.poll.support[them], oh.poll.support[third] = 39.8, 40, 45
		v.projectedEV[me] = 200
		local _, after = PlanPreview.votes(C, v, draftOf({ { kind = "Media", state = "OH" } }))
		expect(after):toBe(200)
	end)
end)

describe("Plan preview on the Campaign map", function()
	local function tap(world: any, peer: any, name: string)
		FakeRoblox.press(world, peer, name)
		FakeRoblox.run(world, 0.3)
	end

	it(
		"shows faint tags and the votes line while drafting, in every lens, and hides them at lock-in",
		function()
			local world, peer = Rig.fixture("Plan")
			local map = Rig.need(peer, "Campaign", "NodeMap")
			local layer = map:FindFirstChild("Preview")
			check(layer ~= nil, "no preview layer")
			local function shownTags(): { [string]: string }
				local out = {}
				for _, tag in layer:GetChildren() do
					if tag.Visible ~= false then
						out[tag.Name] = tag.Text
					end
				end
				return out
			end
			expect(next(shownTags())):toBe(nil)
			-- Two rallies in Ohio (an ad costs $3 and the fixture has $4).
			tap(world, peer, "OH")
			tap(world, peer, "Rally")
			local one = tonumber(shownTags().OH)
			check(one ~= nil and one > 0, `one rally shows {shownTags().OH}`)
			tap(world, peer, "Rally")
			local tags = shownTags()
			local two = tonumber(tags.OH)
			check(two ~= nil and math.abs(two - 2 * (one :: number)) <= 0.11, `two rallies show {tags.OH}`)
			local text = ""
			for _, inst in map.MapLegend:GetDescendants() do
				if inst.Name == "Text" then
					text ..= inst.Text .. "|"
				end
			end
			check(string.find(text, "Plan: ", 1, true) ~= nil, `no votes line: {text}`)
			check(
				layer.ZIndex > map.Pins.ZIndex and layer.ZIndex > map.Tags.ZIndex,
				"the preview is not on top"
			)
			-- Every lens keeps it.
			for _, id in { "Votes", "Issues", "Polls", "Money" } do
				Rig.tap(world, peer, "Campaign", `Lens{if id == "Votes" then "EV" else id}`)
				check(shownTags().OH ~= nil, `the preview left in the {id} lens`)
			end
			-- Locked in: the plan is sent, the preview goes.
			tap(world, peer, "LockIn")
			FakeRoblox.run(world, 0.5)
			expect(next(shownTags())):toBe(nil)
			Rig.noErrors(world)
		end
	)
end)
