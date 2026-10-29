--!strict
-- UI/Icons (docs/GAMEPLAN §2.3, WP-3): the fourteen Lucide icons. Every name has
-- a glyph and an id that is "" (glyph until uploaded) or "rbxassetid://<n>";
-- every name has its PNG and source SVG under assets/icons/; every action icon
-- Kit uses exists; Kit.icon draws the glyph while the id is "".

local fs = require("@lune/fs")

local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Test = require("@testlib/Test")
local Icons = require("../../src/client/UI/Icons")

local describe, it, expect = Test.describe, Test.it, Test.expect

local NAMES = {
	"megaphone",
	"coins",
	"tv",
	"zap",
	"search",
	"footprints",
	"vote",
	"clock",
	"volume-2",
	"volume-x",
	"sparkles",
	"plane",
	"scale",
	"chart-column",
}
local KINDS = { "Rally", "Fundraise", "Media", "Attack", "Poll", "RegionPoll", "Gotv" }

local function kit(): (FakeRoblox.World, FakeRoblox.Peer, any)
	local world = Rig.newWorld(3, nil)
	local peer = FakeRoblox.join(world, "P", { DebugScreen = "Select" })
	FakeRoblox.run(world, 1.5)
	return world, peer, FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
end

describe("Icons", function()
	it("has the fourteen names, each with a glyph and an empty or rbxassetid id", function()
		local count = 0
		for name, icon in Icons do
			count += 1
			expect(table.find(NAMES, name) ~= nil):toBe(true)
			expect(#icon.glyph > 0):toBe(true)
			local ok = icon.id == "" or string.match(icon.id, "^rbxassetid://%d+$") ~= nil
			expect(ok):toBe(true)
		end
		expect(count):toBe(#NAMES)
		for _, name in NAMES do
			expect(Icons[name] ~= nil):toBe(true)
		end
	end)

	it("ships a PNG and its source SVG for every name", function()
		for _, name in NAMES do
			expect(fs.isFile(`assets/icons/{name}.png`)):toBe(true)
			expect(fs.isFile(`assets/icons/src/{name}.svg`)):toBe(true)
		end
	end)

	it("covers every action icon Kit uses", function()
		local _, _, Kit = kit()
		for _, kind in KINDS do
			local name = Kit.actionIcon(kind)
			expect(name ~= nil and Icons[name] ~= nil):toBe(true)
		end
	end)

	it("draws the glyph while the id is empty, the image once it is set", function()
		local world, peer, Kit = kit()
		local Live = FakeRoblox.require(world, peer, "src/client/UI/Icons.luau")
		local saved = Live.megaphone.id
		Live.megaphone.id = ""
		local glyph = Kit.icon("megaphone", 20)
		expect(glyph.ClassName):toBe("TextLabel")
		expect(glyph.Text):toBe(Icons.megaphone.glyph)
		expect(glyph:GetAttribute("Icon")):toBe("megaphone")

		Live.megaphone.id = "rbxassetid://1"
		local image = Kit.icon("megaphone", 20)
		Live.megaphone.id = saved
		expect(image.ClassName):toBe("ImageLabel")
		expect(image.Image):toBe("rbxassetid://1")
	end)
end)
