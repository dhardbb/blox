--!strict
-- Strongholds that were nominated (playtest 1, bug 7). A nominated state loses
-- every draft bonus and becomes a battleground (PLAN.md "Battlegrounds", D-007),
-- so a stronghold the opponent nominated must not be listed as a stronghold.

local Config = require("@sim/Config")
local Drafted = require("@ui/Drafted")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local Format = require("@shared/DebugUI/Format")
local Rig = require("./Rig")
local StateData = require("@sim/StateData")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local C = Config.defaults

local function indexOf(id: string): number
	for i, record in StateData.list do
		if record.id == id then
			return i
		end
	end
	error(`no state {id}`)
end

-- A view where `you` hold two strongholds and the opponent nominated one of them.
local function withNominatedStronghold(view: any): (any, string, string)
	local you, them = view.you, 3 - view.you
	local free = {}
	for i in StateData.list do
		local s = view.states[i]
		if s.owner == nil and not s.battleground and #free < 2 then
			table.insert(free, i)
		end
	end
	local kept, lost = StateData.list[free[1]].id, StateData.list[free[2]].id
	for _, i in free do
		view.states[i].owner = you
		table.insert(view.players[you].strongholds, StateData.list[i].id)
	end
	view.states[free[2]].battleground = true
	table.insert(view.players[them].nominations, lost)
	return view, kept, lost
end

describe("Drafted.strongholds", function()
	it("splits strongholds into the ones that still count and the nominated ones", function()
		local view, kept, lost = withNominatedStronghold(Rig.deepCopy(Fixtures.payload(C, "Plan").view))
		local active, nominated = Drafted.strongholds(view, view.you)
		expect(table.find(active, kept) ~= nil):toBe(true)
		expect(table.find(active, lost)):toBe(nil)
		expect(nominated[#nominated]):toEqual({ state = lost, by = 3 - view.you })
	end)

	it("describes them for the player", function()
		local view, _, lost = withNominatedStronghold(Rig.deepCopy(Fixtures.payload(C, "Plan").view))
		local text = Drafted.summary(view, view.you)
		local listed = string.match(text, "nominated by the opponent: ([^%(]*)") or ""
		expect(string.find(listed, lost, 1, true) ~= nil):toBe(true)
		local strongholds = string.match(text, "^strongholds ([^;]*)") or ""
		expect(string.find(strongholds, lost, 1, true)):toBe(nil)
	end)
end)

describe("nominated strongholds in the debug board (bug 7)", function()
	it("tags a nominated stronghold as a battleground, not a stronghold", function()
		local payload = Rig.deepCopy(Fixtures.payload(C, "Plan"))
		local view, kept, lost = withNominatedStronghold(payload.view)
		local you = view.you
		local tags = Format.stateTags(view.states[indexOf(lost)], you)
		expect(table.find(tags, "BG") ~= nil):toBe(true)
		expect(table.find(tags, `SH P{you} nominated`) ~= nil):toBe(true)
		expect(table.find(tags, `SH P{you}`)):toBe(nil)
		expect(table.find(Format.stateTags(view.states[indexOf(kept)], you), `SH P{you}`) ~= nil):toBe(true)
	end)
end)

describe("nominated strongholds on the real screens (bug 7)", function()
	it("the draft board lists them apart from the strongholds", function()
		local world, peer = Rig.fixture("Draft", nil)
		local payload = Rig.deepCopy(Rig.payloadOf(world, peer))
		local _, kept, lost = withNominatedStronghold(payload.view)
		Rig.push(world, peer, payload)
		local detail = ""
		for _, inst in FakeRoblox.find(peer, "Draft"):GetDescendants() do
			if inst.Name == "Detail" and string.find(tostring(inst.Text), kept, 1, true) then
				detail = tostring(inst.Text)
			end
		end
		local listed = string.match(detail, "nominated by the opponent: ([^·]*)") or ""
		expect(string.find(listed, lost, 1, true) ~= nil):toBe(true)
		local strongholds = string.match(detail, "strongholds ([^·]*)") or ""
		expect(string.find(strongholds, lost, 1, true)):toBe(nil)
		Rig.noErrors(world)
	end)
end)
