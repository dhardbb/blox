--!strict
-- Style v2 (docs/UI-STYLE.md): the UI audit's style rules (tokenColor,
-- textSizes, labelWords, wallOfText) on every screen, on a phone and at 16:9.
-- A screen may only break a style rule that Audit.PENDING still lists for it,
-- and every listed rule must still fire somewhere: when a work package fixes a
-- screen, this spec tells it to delete the line (the list only shrinks).

local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

type Shot = {
	moment: string,
	screen: string,
	steps: ((world: FakeRoblox.World, peer: FakeRoblox.Peer) -> ())?,
}

local SIZES = {
	{ name = "phone", x = 390, y = 844 },
	{ name = "16:9", x = 1280, y = 720 },
}

local SHOTS: { Shot } = {
	{ moment = "Lobby", screen = "Lobby" },
	{ moment = "Select", screen = "Select" },
	{
		moment = "Select",
		screen = "Select",
		steps = function(world, peer)
			Rig.tap(world, peer, "Select", "Candidate_okafor")
			Rig.tap(world, peer, "Select", "LockIn", 0.5)
			Rig.tap(world, peer, "Select", "Issue_Jobs")
		end,
	},
	{ moment = "MapReveal", screen = "Draft" },
	{ moment = "Draft", screen = "Draft" },
	{ moment = "Stance", screen = "Decision" },
	{ moment = "Focus", screen = "Decision" },
	{ moment = "Plan", screen = "Campaign" },
	{ moment = "ChoiceWeek", screen = "Campaign" },
	{ moment = "Resolve", screen = "Campaign" },
	{ moment = "Debate", screen = "Campaign" },
	{ moment = "Election", screen = "Election" },
	{ moment = "Over", screen = "Results" },
}

describe("Style v2 rules on every screen", function()
	it("breaks only the rules Audit.PENDING lists, and every listed rule still fires", function()
		local Audit: any = nil
		local hit: { [string]: { [string]: boolean } } = {}
		local problems: { string } = {}
		for _, size in SIZES do
			for _, shot in SHOTS do
				local world, peer = Rig.fixture(shot.moment, { x = size.x, y = size.y })
				if shot.steps then
					shot.steps(world, peer)
				end
				Audit = FakeRoblox.require(world, peer, "src/client/UI/Audit.luau")
				local holder = FakeRoblox.find(peer, shot.screen)
				Rig.check(holder ~= nil, `{shot.screen} is not mounted for {shot.moment}`)
				local findings = Audit.check(holder, { style = true })
				for _, finding in findings do
					if not Audit.STYLE[finding.rule] then
						continue
					end
					local label = if finding.onMap then "NodeMap" else shot.screen
					local pending = Audit.PENDING[label]
					if pending and pending[finding.rule] then
						hit[label] = hit[label] or {}
						hit[label][finding.rule] = true
					else
						table.insert(problems, `{size.name} {shot.moment}: {finding.rule}: {finding.message}`)
					end
				end
				Rig.noErrors(world)
			end
		end
		for label, rules in Audit.PENDING do
			for rule in rules do
				if Audit.STYLE[rule] and not (hit[label] and hit[label][rule]) then
					table.insert(problems, `Audit.PENDING.{label}.{rule} no longer fires: delete it`)
				end
			end
		end
		Rig.check(#problems == 0, table.concat(problems, "\n"))
		expect(#problems):toBe(0)
	end)
end)
