--!strict
-- UI/Audio (docs/DESIGN.md D-053) on the fake engine: one Sound per cue under
-- SoundService, cooldowns, the voice cap, mute, volume, fallbacks for assets
-- that fail to load, and the maxLength cut. world.sounds logs every
-- Sound:Play(); Rig.sounds(peer) reads it.

local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local check = Rig.check

type Client = {
	world: FakeRoblox.World,
	peer: FakeRoblox.Peer,
	Audio: any,
	Kit: any,
}

local CUES = {
	"tap",
	"select",
	"planAdd",
	"planRemove",
	"lockIn",
	"error",
	"tick",
	"whoosh",
	"flip",
	"debateWin",
	"call",
	"victory",
	"defeat",
}

-- A fresh client on the Select fixture (it has a header); `broken` content
-- ids fail to preload.
local function client(broken: { string }?): Client
	local world = Rig.newWorld(3, nil)
	for _, id in broken or {} do
		world.brokenAssets[id] = true
	end
	local peer = FakeRoblox.join(world, "P", { DebugScreen = "Select" })
	FakeRoblox.run(world, 1.5)
	return {
		world = world,
		peer = peer,
		Audio = FakeRoblox.require(world, peer, "src/client/UI/Audio.luau"),
		Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau"),
	}
end

local function play(c: Client, name: string, opts: any?)
	c.world.current = c.peer
	c.Audio.play(name, opts)
	c.world.current = nil
end

local function last(c: Client): any
	local found = nil
	for _, entry in c.world.sounds do
		if entry.peer == c.peer.name then
			found = entry
		end
	end
	return found
end

local function count(list: { string }, name: string): number
	local n = 0
	for _, item in list do
		if item == name then
			n += 1
		end
	end
	return n
end

describe("Audio cues", function()
	it("has the 13 cues, each well formed", function()
		local Audio = client().Audio
		local n = 0
		for _ in Audio.CUES do
			n += 1
		end
		expect(n):toBe(#CUES)
		for _, name in CUES do
			local cue = Audio.CUES[name]
			check(cue ~= nil, `no cue {name}`)
			check(cue.id == "" or string.match(cue.id, "^rbxassetid://%d+$") ~= nil, `{name} id {cue.id}`)
			check(cue.volume > 0 and cue.volume <= 1, `{name} volume {cue.volume}`)
			check(cue.group == "UI" or cue.group == "Stingers", `{name} group {cue.group}`)
			check(cue.cooldown >= 0 and cue.jitter >= 0 and cue.jitter < 0.2, `{name} timing`)
			if cue.fallback then
				check(Audio.CUES[cue.fallback.cue] ~= nil, `{name} falls back to a missing cue`)
			end
		end
		for _, name in { "planAdd", "lockIn", "call" } do
			check((Audio.CUES[name].maxLength or 99) <= 1, `{name} has no maxLength`)
		end
	end)

	it("builds the sound groups and one Sound per cue under SoundService", function()
		local c = client()
		local soundService = c.peer.game:GetService("SoundService")
		local ui = soundService:FindFirstChild("UI")
		local stingers = soundService:FindFirstChild("Stingers")
		check(ui ~= nil and stingers ~= nil, "no sound groups")
		expect(ui.Volume):toBe(0.8)
		expect(stingers.Volume):toBe(0.9)
		local folder = soundService:FindFirstChild("Cues")
		for _, name in CUES do
			local sound = folder:FindFirstChild(name)
			check(sound ~= nil and sound.ClassName == "Sound", `no Sound {name}`)
			expect(sound.SoundId):toBe(c.Audio.CUES[name].id)
			expect(sound.SoundGroup):toBe(soundService:FindFirstChild(c.Audio.CUES[name].group))
		end
	end)
end)

describe("Audio.play", function()
	it("plays a cue with its pitch and logs it", function()
		local c = client()
		play(c, "error")
		local entry = last(c)
		check(entry ~= nil and entry.name == "error", "error did not play")
		check(math.abs(entry.speed - 0.75) <= 0.75 * 0.03 + 1e-9, `error speed {entry.speed}`)
		expect(c.Audio.played[#c.Audio.played]):toBe("error")
		play(c, "call", { pitch = 1.2 })
		expect(last(c).speed):toBe(1.2)
	end)

	it("keeps each cue's cooldown", function()
		local c = client()
		play(c, "lockIn")
		play(c, "lockIn")
		expect(count(Rig.sounds(c.peer), "lockIn")):toBe(1)
		FakeRoblox.run(c.world, 0.4)
		play(c, "lockIn")
		expect(count(Rig.sounds(c.peer), "lockIn")):toBe(2)
	end)

	it("never plays more than 4 cues at once", function()
		local c = client()
		for _, name in { "flip", "debateWin", "victory", "whoosh", "lockIn", "planAdd" } do
			play(c, name)
		end
		expect(#Rig.sounds(c.peer)):toBe(4)
		FakeRoblox.run(c.world, 1.5)
		play(c, "select")
		expect(#Rig.sounds(c.peer)):toBe(5)
	end)

	it("stops a long cue after its maxLength", function()
		local c = client()
		local sound = c.peer.game:GetService("SoundService").Cues.planAdd
		sound.TimeLength = 2.7
		play(c, "planAdd")
		expect(sound.Playing):toBe(true)
		FakeRoblox.run(c.world, 0.9)
		expect(sound.Playing):toBe(false)
	end)

	it("is silent while muted and follows the volume", function()
		local c = client()
		local changes: { boolean } = {}
		c.Audio.changed:Connect(function(muted: boolean)
			table.insert(changes, muted)
		end)
		c.Audio.setMuted(true)
		expect(c.Audio.muted()):toBe(true)
		play(c, "tap")
		expect(#Rig.sounds(c.peer)):toBe(0)
		c.Audio.setMuted(false)
		play(c, "tap")
		expect(#Rig.sounds(c.peer)):toBe(1)
		expect(#changes):toBe(2)
		c.Audio.setVolume(0.5)
		local soundService = c.peer.game:GetService("SoundService")
		expect(soundService.UI.Volume):toBe(0.4)
		expect(soundService.Stingers.Volume):toBe(0.45)
		c.Audio.setVolume(1)
	end)
end)

describe("Audio fallbacks", function()
	it("plays the fallback when a cue's asset fails to load", function()
		local select = "rbxassetid://15675059323"
		local c = client({ select })
		play(c, "select")
		local entry = last(c)
		check(entry ~= nil and entry.name == "tap", `select played as {entry and entry.name}`)
		check(math.abs(entry.speed - 1.15) <= 1.15 * 0.05 + 1e-9, `fallback speed {entry.speed}`)
		expect(c.Audio.played[#c.Audio.played]):toBe("select")
		expect(Rig.count(c.peer, "did not load")):toBe(1)
	end)

	it("skips a cue that has not loaded and has no fallback, warning once", function()
		local c = client()
		c.peer.game:GetService("SoundService").Cues.whoosh.IsLoaded = false
		play(c, "whoosh")
		FakeRoblox.run(c.world, 0.6)
		play(c, "whoosh")
		expect(count(Rig.sounds(c.peer), "whoosh")):toBe(0)
		expect(Rig.count(c.peer, "whoosh is not loaded")):toBe(1)
		Rig.noErrors(c.world)
	end)
end)

describe("Audio in the UI", function()
	it("clicks on a button and selects on a chip", function()
		local c = client()
		-- Built as the client, so the handlers run (and play) on its thread.
		c.world.current = c.peer
		local stage = c.Kit.box({ Name = "Stage" })
		local button = c.Kit.button("Go", function() end, { variant = "secondary", Parent = stage })
		local chip = c.Kit.chip("Jobs", function() end, { Parent = stage })
		button.Activated.fire()
		FakeRoblox.run(c.world, 0.1)
		chip.Activated.fire()
		c.world.current = nil
		FakeRoblox.run(c.world, 0.1)
		local played = Rig.sounds(c.peer)
		expect(count(played, "tap")):toBe(1)
		expect(count(played, "select")):toBe(1)
	end)

	it("mutes and unmutes from the header's sound button", function()
		local c = client()
		local button = Rig.need(c.peer, "Select", "SoundButton")
		expect(button:GetAttribute("Muted")):toBe(false)
		Rig.tap(c.world, c.peer, "Select", "SoundButton")
		expect(c.Audio.muted()):toBe(true)
		expect(button:GetAttribute("Muted")):toBe(true)
		-- The uploaded volume-x image while muted; a glyph (no image id) gets a slash.
		local icon = button:FindFirstChild("Icon")
		if icon:IsA("ImageLabel") then
			local Icons = FakeRoblox.require(c.world, c.peer, "src/client/UI/Icons.luau")
			expect(icon.Image):toBe(Icons["volume-x"].id)
			check(button:FindFirstChild("Slash") == nil, "a slash over the muted image")
		else
			check(button:FindFirstChild("Slash") ~= nil, "no slash over the muted glyph")
		end
		Rig.tap(c.world, c.peer, "Select", "SoundButton")
		expect(c.Audio.muted()):toBe(false)
		expect(button:GetAttribute("Muted")):toBe(false)
		Rig.noErrors(c.world)
	end)
end)
