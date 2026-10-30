--!strict
-- UI/Board (docs/proposals/whiteboard.md): the whiteboard props. While an image's
-- id is "" each helper falls back (nothing, or a flat stand-in) and adds no
-- image; with a stand-in id (Board.assets, as ShapeMap.assets) it adds its
-- decor image, tinted and sliced as the art needs. Every Assets entry and its
-- PNG exist.

local fs = require("@lune/fs")

local FakeRoblox = require("@testlib/FakeRoblox")
local Rig = require("./Rig")
local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect
local UDim2 = FakeRoblox.types.UDim2
local Color3 = FakeRoblox.types.Color3

-- Assets key -> its PNG (assets/ui/make.py).
local FILES = {
	board = "board.png",
	sticky = "sticky.png",
	markerBox = "marker-box.png",
	magnet = "magnet.png",
	scribbleCircle = "scribble-circle.png",
	tape = "tape.png",
}

type Client = { Board: any, Kit: any, stage: any, Assets: any }

local function client(): Client
	local world, peer = Rig.fixture("Lobby", nil)
	local Kit = FakeRoblox.require(world, peer, "src/client/UI/Kit.luau")
	local Board = FakeRoblox.require(world, peer, "src/client/UI/Board.luau")
	local Assets = FakeRoblox.require(world, peer, "src/client/UI/Assets.luau")
	local gui = Kit.new("ScreenGui", { Name = "TestGui" })
	local stage = Kit.box({ Name = "Stage", Parent = gui })
	return { Board = Board, Kit = Kit, stage = stage, Assets = Assets }
end

-- A stand-in list: every whiteboard image "uploaded".
local function uploaded(): { [string]: any }
	local list = {}
	for key in FILES do
		list[key] = { id = `rbxassetid://{key}`, kind = "sprite" }
	end
	return list
end

local function card(c: Client, name: string): any
	return c.Kit.new("Frame", {
		Name = name,
		Size = UDim2.fromOffset(160, 100),
		BackgroundColor3 = Color3.fromRGB(1, 2, 3),
		Parent = c.stage,
	})
end

local function decorOk(label: any, asset: string)
	expect(label.ClassName):toBe("ImageLabel")
	expect(label:GetAttribute("Decor")):toBe(true)
	expect(label:GetAttribute("Asset")):toBe(asset)
	expect(label.Image):toBe(`rbxassetid://{asset}`)
end

describe("Board", function()
	it("lists every whiteboard image in Assets with an empty or rbxassetid id, and ships its PNG", function()
		local c = client()
		for key, file in FILES do
			local entry = c.Assets[key]
			expect(entry ~= nil):toBe(true)
			local ok = entry.id == "" or string.match(entry.id, "^rbxassetid://%d+$") ~= nil
			expect(ok):toBe(true)
			expect(fs.isFile(`assets/ui/{file}`)):toBe(true)
		end
	end)

	it("falls back cleanly while the ids are empty", function()
		local c = client()
		c.Board.assets = {}
		for key in FILES do
			c.Board.assets[key] = { id = "", kind = "sprite" }
		end
		local root = card(c, "Root")
		expect(c.Board.texture(root)):toBe(nil)

		local note = card(c, "Note")
		note.BackgroundTransparency = 1
		expect(c.Board.sticky(note)):toBe(nil)
		expect(note.BackgroundTransparency):toBe(0)
		local sticky = c.Kit.colors.sticky
		expect(note.BackgroundColor3.R):toBe(sticky.R)

		local button = card(c, "Button")
		local stroke = c.Kit.new("UIStroke", { Parent = button })
		expect(c.Board.markerBox(button)):toBe(nil)
		expect(stroke.Enabled ~= false):toBe(true)

		local pin = c.Board.magnet(card(c, "Pinned"), Color3.fromRGB(200, 20, 70))
		expect(pin.ClassName):toBe("Frame")
		expect(pin:GetAttribute("Decor")):toBe(true)

		expect(c.Board.circle(card(c, "Stamp"))):toBe(nil)
		expect(#c.Board.tape(card(c, "Taped"))):toBe(0)

		local photo = c.Board.photo("rbxassetid://5", 80)
		expect(photo.Name):toBe("Photo")
		expect(photo:FindFirstChild("Tape", true)):toBe(nil)
		local face = photo:FindFirstChild("Face", true)
		expect(face ~= nil and face.Image == "rbxassetid://5"):toBe(true)

		for _, name in { "Root", "Note", "Button", "Stamp", "Taped" } do
			for _, child in c.stage:FindFirstChild(name):GetChildren() do
				expect(child.ClassName ~= "ImageLabel"):toBe(true)
			end
		end
		c.Board.assets = nil
	end)

	it("applies each image once it has an id", function()
		local c = client()
		c.Board.assets = uploaded()

		local texture = c.Board.texture(card(c, "Root"))
		decorOk(texture, "board")
		expect(texture.ScaleType.Name):toBe("Tile")

		local note = card(c, "Note")
		local sticky = c.Board.sticky(note, Color3.fromRGB(10, 20, 30))
		decorOk(sticky, "sticky")
		expect(sticky.ScaleType.Name):toBe("Slice")
		expect(sticky.ImageColor3.G):toBe(Color3.fromRGB(10, 20, 30).G)
		expect(note.BackgroundTransparency):toBe(1)

		local button = card(c, "Button")
		local stroke = c.Kit.new("UIStroke", { Parent = button })
		local box = c.Board.markerBox(button)
		decorOk(box, "markerBox")
		expect(box.SliceScale):toBe(c.Board.BOX_SCALE)
		expect(stroke.Enabled):toBe(false)

		decorOk(c.Board.magnet(card(c, "Pinned"), Color3.fromRGB(200, 20, 70)), "magnet")
		decorOk(c.Board.circle(card(c, "Stamp")), "scribbleCircle")

		local strips = c.Board.tape(card(c, "Taped"))
		expect(#strips):toBe(1)
		decorOk(strips[1], "tape")
		expect(#c.Board.tape(card(c, "Cornered"), { at = "corners" })):toBe(2)

		local face = c.Kit.new("ImageLabel", { Name = "Face" })
		local photo = c.Board.photo(face, 80, { tilt = 3 })
		expect(photo.Rotation):toBe(3)
		expect(face.Parent.Name):toBe("Window")
		decorOk(photo:FindFirstChild("Tape"), "tape")
		c.Board.assets = nil
	end)

	it("keeps props out of a parent that lays out its children", function()
		local c = client()
		c.Board.assets = uploaded()
		local list = card(c, "List")
		c.Kit.new("UIListLayout", { Parent = list })
		expect(c.Board.markerBox(list)):toBe(nil)
		expect(c.Board.circle(list)):toBe(nil)
		expect(#c.Board.tape(list)):toBe(0)
		expect(c.Board.sticky(list)):toBe(nil)
		for _, child in list:GetChildren() do
			expect(child.ClassName == "UIListLayout"):toBe(true)
		end
		c.Board.assets = nil
	end)
end)
