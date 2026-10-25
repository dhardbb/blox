--!strict
-- Key states (src/shared/UI/KeyStates.luau, D-088): the tipping state and the
-- biggest states polling within KEY_STATE_BAND points of it, at most
-- KEY_STATES, from the player's own public polls only; the same for both seats.
-- Then the Campaign screen: the "Key states" line, the glowing states on the
-- map, the legend, the coach tip, the Map key and Help.

local fs = require("@lune/fs")

local Config = require("@sim/Config")
local Explain = require("@ui/Explain")
local FakeRoblox = require("@testlib/FakeRoblox")
local Fixtures = require("@ui/Fixtures")
local KeyStates = require("@ui/KeyStates")
local RevealWords = require("@ui/Words/Reveal")
local Rig = require("./Rig")
local Rng = require("@sim/Rng")
local StateData = require("@sim/StateData")
local Test = require("@testlib/Test")
local Words = require("@ui/Words/Campaign")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

local C = Config.defaults

local function planView(): any
	return Rig.deepCopy(Fixtures.payload(C, "Plan").view)
end

-- A view whose public polls give player 1 the margin `margins[id]` (0 elsewhere).
local function withMargins(margins: { [string]: number }): any
	local v = planView()
	for _, s in v.states do
		local m = margins[s.id] or 0
		s.poll = { support = { 45 + m / 2, 45 - m / 2 }, undecided = 10 }
	end
	return v
end

-- Random public polls (seeded), integer shares like the real ones.
local function randomView(seed: number, you: number): any
	local rng = Rng.new(seed)
	local v = planView()
	v.you = you
	for _, s in v.states do
		local a = Rng.nextInt(rng, 30, 60)
		local b = Rng.nextInt(rng, 30, math.min(60, 95 - a))
		s.poll = { support = { a, b }, undecided = 100 - a - b }
	end
	return v
end

local function ids(keys: { KeyStates.Key }): string
	local out = {}
	for _, key in keys do
		table.insert(out, key.id)
	end
	return table.concat(out, " ")
end

describe("KeyStates (D-088)", function()
	it("finds the state that carries the leader past 269", function()
		local v = planView()
		local tip = KeyStates.tipping(C, v)
		check(tip ~= nil, "no tipping state")
		-- Walk the states from your safest: the votes before the tipping state fall
		-- short of 270, with it they reach it.
		local rows = {}
		for _, s in v.states do
			table.insert(rows, { id = s.id, ev = StateData.byId[s.id].ev, m = KeyStates.margin(v, s) })
		end
		local before, through = 0, 0
		for _, row in rows do
			if row.m > (tip :: any).margin then
				before += row.ev
			end
			if row.m >= (tip :: any).margin then
				through += row.ev
			end
		end
		check(before < C.EV_TO_WIN, `{before} votes already safer than the tipping state`)
		check(through >= C.EV_TO_WIN, `{through} votes at or above the tipping state`)
	end)

	it("keeps the tipping state and the biggest states within the band, biggest first", function()
		for seed = 1, 50 do
			local v = randomView(seed, 1)
			local tip = KeyStates.tipping(C, v) :: KeyStates.Key
			local keys = KeyStates.of(C, v)
			check(#keys >= 1 and #keys <= C.KEY_STATES, `seed {seed}: {#keys} key states`)
			local hasTip, smallest = false, math.huge
			for k, key in keys do
				hasTip = hasTip or key.id == tip.id
				check(key.tipping == (key.id == tip.id), `seed {seed}: {key.id} tipping flag`)
				check(
					math.abs(key.margin - tip.margin) <= C.KEY_STATE_BAND,
					`seed {seed}: {key.id} out of band`
				)
				if k > 1 then
					check(key.ev <= keys[k - 1].ev, `seed {seed}: not biggest first`)
				end
				if not key.tipping then
					smallest = math.min(smallest, key.ev)
				end
			end
			check(hasTip, `seed {seed}: tipping state {tip.id} missing`)
			-- No bigger state in the band was left out for a smaller one.
			if #keys == C.KEY_STATES then
				local chosen = KeyStates.set(C, v)
				for _, s in v.states do
					local ev = StateData.byId[s.id].ev
					if
						not chosen[s.id]
						and math.abs(KeyStates.margin(v, s) - tip.margin) <= C.KEY_STATE_BAND
					then
						check(ev <= smallest, `seed {seed}: {s.id} ({ev}) left out for a {smallest}`)
					end
				end
			end
		end
	end)

	it("a lopsided race keys the states near its tipping state, not the close ones", function()
		-- Player 1 leads every state by 20 except a few: the tipping state is a +20
		-- state, so a 1-point state far from it is not key.
		local margins: { [string]: number } = {}
		for _, record in StateData.list do
			margins[record.id] = 20
		end
		margins.WY = 1
		local v = withMargins(margins)
		local tip = KeyStates.tipping(C, v) :: KeyStates.Key
		expect(tip.margin):toBe(20)
		expect(KeyStates.set(C, v).WY):toBe(nil)
		-- Everything else ties at 20: one step, whose biggest state tips it; the
		-- next biggest fill the slots.
		expect(tip.id):toBe("CA")
		expect(ids(KeyStates.of(C, v))):toBe("CA TX FL")
	end)

	it("gives both seats the same key states from the same public polls", function()
		local same = 0
		for seed = 1, 200 do
			local a = KeyStates.of(C, randomView(seed, 1))
			local b = KeyStates.of(C, randomView(seed, 2))
			if ids(a) == ids(b) then
				same += 1
			end
		end
		-- Ties on a margin and a 269-269 line are settled the same way from both sides.
		expect(same):toBe(200)
	end)

	it("reads only public polls: private fields change nothing", function()
		local v = randomView(7, 1)
		local before = ids(KeyStates.of(C, v))
		for _, s in v.states do
			s.gotv = 4
			s.backlash = 3
		end
		v.internalPolls =
			{ { state = "PA", support = { 70, 20 }, undecided = 10, momentum = { 0, 0 }, gotv = { 0, 6 } } }
		v.scouted = { { state = "PA", gotv = 6 } }
		v.players[1].cash = 999
		expect(ids(KeyStates.of(C, v))):toBe(before)
	end)

	it("uses the public lean before the first poll", function()
		local v = planView()
		for _, s in v.states do
			s.poll = nil
			s.lean, s.leanTo = 0, nil
		end
		local ca = nil
		for _, s in v.states do
			if s.id == "CA" then
				ca = s
			end
		end
		ca.lean, ca.leanTo = 4, 2
		expect(KeyStates.margin(v, ca)):toBe(-4)
		v.you = 2
		expect(KeyStates.margin(v, ca)):toBe(4)
		expect(#KeyStates.of(C, v)):toBe(C.KEY_STATES)
	end)

	it("is a UI aid: nothing in Sim reads it or its numbers", function()
		for _, entry in fs.readDir("src/shared/Sim") do
			if entry ~= "Config.luau" and string.match(entry, "%.luau$") then
				local source = fs.readFile(`src/shared/Sim/{entry}`)
				check(string.find(source, "KeyStates", 1, true) == nil, `{entry} reads KeyStates`)
				check(string.find(source, "KEY_STATE", 1, true) == nil, `{entry} reads KEY_STATE*`)
			end
		end
	end)
end)

local PHONE = { x = 390, y = 844 }

-- The states the map marks as key (Nodes/<id> carries the Key attribute).
local function keyedOnMap(peer: FakeRoblox.Peer): string
	local map = Rig.need(peer, "Campaign", "NodeMap")
	local out = {}
	for _, node in map.Nodes:GetChildren() do
		if node:GetAttribute("Key") == true then
			table.insert(out, node.Name)
		end
	end
	table.sort(out)
	return table.concat(out, " ")
end

local function sortedIds(keys: { KeyStates.Key }): string
	local out = {}
	for _, key in keys do
		table.insert(out, key.id)
	end
	table.sort(out)
	return table.concat(out, " ")
end

local function tipShown(peer: FakeRoblox.Peer): string?
	for _, inst in FakeRoblox.find(peer, "Campaign"):GetDescendants() do
		if inst.Name == "CoachTip" and inst.Parent ~= nil then
			return inst:GetAttribute("TipId")
		end
	end
	return nil
end

describe("Key states on the Campaign screen (D-088)", function()
	for _, screen in { { name = "16:9", size = nil :: any }, { name = "phone", size = PHONE } } do
		it(`names them over the map and lights the same states on it ({screen.name})`, function()
			local world, peer = Rig.fixture("Plan", screen.size)
			local keys = KeyStates.of(C, Fixtures.payload(C, "Plan").view)
			check(#keys >= 1, "the Plan fixture has no key states")
			local row = Rig.need(peer, "Campaign", "KeyStates")
			check(Rig.shown(row, "Campaign"), "the key states line is hidden")
			expect(row:GetAttribute("Count")):toBe(#keys)
			expect(Rig.textOf(peer, "Campaign", "KeyStatesLabel")):toBe(Words.KEY_STATES)
			for _, key in keys do
				expect(Rig.textOf(peer, "Campaign", `Key_{key.id}`)):toBe(`{key.id} {key.ev}`)
			end
			expect(keyedOnMap(peer)):toBe(sortedIds(keys))
			-- The legend row names the glow.
			local legend = Rig.need(peer, "Campaign", "MapLegend")
			check(Rig.shown(legend, "Campaign"), "no map legend")
			expect(legend.Item1.Text.Text):toBe(Words.KEY_LEGEND)
			expect(Rig.audit(peer, "Campaign")):toEqual({})
			Rig.noErrors(world)
		end)
	end

	it("a tap on a name selects that state, as a tap on the map does", function()
		local world, peer = Rig.fixture("Plan")
		local keys = KeyStates.of(C, Fixtures.payload(C, "Plan").view)
		local id = keys[#keys].id
		Rig.tap(world, peer, "Campaign", `Key_{id}`)
		check(
			Rig.contains(Rig.textOf(peer, "Campaign", "CardTitle"), StateData.byId[id].name),
			`{id} was not selected`
		)
		expect(Rig.need(peer, "Campaign", `Key_{id}`):GetAttribute("Selected")):toBe(true)
		-- The tip about them is done once they are used.
		local CoachTip = FakeRoblox.require(world, peer, "src/client/UI/CoachTip.luau")
		expect(CoachTip.seen("campaign.keys")):toBe(true)
		Rig.noErrors(world)
	end)

	it("on a phone the open card takes the line's place", function()
		local world, peer = Rig.fixture("Plan", PHONE)
		local keys = KeyStates.of(C, Fixtures.payload(C, "Plan").view)
		Rig.tap(world, peer, "Campaign", `Key_{keys[1].id}`)
		check(
			not Rig.shown(Rig.need(peer, "Campaign", "KeyStates"), "Campaign"),
			"the line stays over the card"
		)
		Rig.tap(world, peer, "Campaign", "CloseCard")
		check(Rig.shown(Rig.need(peer, "Campaign", "KeyStates"), "Campaign"), "the line did not come back")
		Rig.noErrors(world)
	end)

	it("tips once, after the map tip, in the match and in the tutorial", function()
		local world, peer = Rig.fixture("Plan")
		local CoachTip = FakeRoblox.require(world, peer, "src/client/UI/CoachTip.luau")
		expect(tipShown(peer)):toBe("campaign.map")
		CoachTip.markSeen("campaign.map")
		Rig.push(world, peer, Rig.deepCopy(Fixtures.payload(C, "Plan")))
		expect(tipShown(peer)):toBe("campaign.keys")
		expect(Rig.textOf(peer, "Campaign", "TipText")):toBe(CoachTip.TIPS["campaign.keys"])
		Rig.tap(world, peer, "Campaign", "GotIt")
		check(tipShown(peer) ~= "campaign.keys", "the key states tip came back")
		-- Both copies stay within the 12-word limit.
		for _, copy in { CoachTip.TIPS["campaign.keys"], CoachTip.TUTORIAL["campaign.keys"] } do
			local n = 0
			for _ in string.gmatch(copy, "%S+") do
				n += 1
			end
			check(n <= 12, `"{copy}" is {n} words`)
		end

		local tw, tp = Rig.fixture("PlanTutorial")
		local TutorialTip = FakeRoblox.require(tw, tp, "src/client/UI/CoachTip.luau")
		TutorialTip.markSeen("campaign.map")
		Rig.push(tw, tp, Rig.deepCopy(Fixtures.payload(C, "PlanTutorial")))
		expect(tipShown(tp)):toBe("campaign.keys")
		expect(Rig.textOf(tp, "Campaign", "TipText")):toBe(TutorialTip.TUTORIAL["campaign.keys"])
		check(Rig.shown(Rig.need(tp, "Campaign", "KeyStates"), "Campaign"), "no key states in the tutorial")
		Rig.noErrors(world)
		Rig.noErrors(tw)
	end)

	it("only while planning: a reveal shows none", function()
		local world, peer = Rig.fixture("Resolve")
		local row = Rig.findIn(peer, "Campaign", "KeyStates")
		check(row == nil or not Rig.shown(row, "Campaign"), "the key states line shows in a reveal")
		expect(keyedOnMap(peer)):toBe("")
		Rig.noErrors(world)
	end)

	it("the Map key, Help and the numbers say what they are", function()
		check(table.find(Words.key("EV"), Words.KEY_MAP) ~= nil, "the Map key has no key states line")
		check(table.find(Words.key("Polls"), Words.KEY_MAP) ~= nil, "the Polls key has no key states line")
		-- Help opens on Your turn while you plan.
		local turn = RevealWords.help(C)[2]
		expect(turn.id):toBe("turn")
		check(Rig.contains(turn.text, "key states"), "Your turn does not mention key states")
		local n = 0
		for _ in string.gmatch(turn.text, "%S+") do
			n += 1
		end
		check(n <= RevealWords.HELP_WORDS, `Your turn is {n} words`)
		local found = false
		for _, section in Explain.help(C, nil) do
			for _, line in section.lines do
				if
					Rig.contains(line, "Key states")
					and Rig.contains(line, `within {C.KEY_STATE_BAND} points`)
					and Rig.contains(line, `{C.KEY_STATES} at most`)
				then
					found = true
				end
			end
		end
		check(found, "All the numbers does not state the key states rule")
	end)
end)
