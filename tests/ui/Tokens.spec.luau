--!strict
-- Static checks of the design system (docs/DESIGN.md D-030), read straight from
-- the source files: screens and the map use Kit tokens, never color literals,
-- TextSize literals or off-scale button heights, and nobody uses the old
-- Kit.size names. Crude regexes, but they catch regressions.
--
-- Transition (UI overhaul v0.4.0): PENDING lists the files that still break a
-- rule, with how many offending lines each may have at most. A listed file may
-- only get better; a file that is clean must lose its entry (the spec says so).
-- Each work package deletes its own lines when its screens are redone.

local fs = require("@lune/fs")

local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

local FOLDERS = { "src/client/Screens", "src/client/Map" }

local PENDING: { [string]: number } = {
	-- WP2 (Lobby, Select, Results)
	["src/client/Screens/Lobby.luau"] = 3,
	["src/client/Screens/Select.luau"] = 2,
	["src/client/Screens/Results.luau"] = 1,
	-- WP3 (Campaign)
	["src/client/Screens/Campaign.luau"] = 2,
	-- WP4 (Draft, Election)
	["src/client/Screens/Draft.luau"] = 10,
	["src/client/Screens/DraftParts/StateList.luau"] = 6,
}

-- What a screen file may not contain, as Lua patterns.
local RULES: { { name: string, pattern: string } } = {
	{ name = "a Color3 literal", pattern = "Color3%.new" },
	{ name = "a Color3 literal", pattern = "Color3%.fromRGB" },
	{ name = "a TextSize literal", pattern = "TextSize%s*=%s*%d" },
	{ name = "a 48 px height", pattern = "0, 48%)" },
	{ name = "a 52 px height", pattern = "0, 52%)" },
	{ name = "a 64 px height", pattern = "0, 64%)" },
	{ name = "a 104 px height", pattern = "0, 104%)" },
}

local function luauFiles(dir: string, out: { string })
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			luauFiles(path, out)
		elseif string.match(entry, "%.luau$") then
			table.insert(out, path)
		end
	end
end

-- Offending lines in `path`: "line N: <rule>".
local function offences(path: string): { string }
	local found = {}
	local n = 0
	for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
		n += 1
		for _, rule in RULES do
			if string.find(line, rule.pattern) then
				table.insert(found, `line {n}: {rule.name}`)
				break
			end
		end
	end
	return found
end

describe("Design tokens in screens and the map", function()
	local files: { string } = {}
	for _, folder in FOLDERS do
		luauFiles(folder, files)
	end

	it("finds the files to check", function()
		expect(#files > 10):toBe(true)
	end)

	it("has no color literals, TextSize literals or odd button heights", function()
		local problems = {}
		for _, path in files do
			local found = offences(path)
			local allowed = PENDING[path] or 0
			if #found > allowed then
				table.insert(
					problems,
					`{path}: {#found} offending line(s), {allowed} allowed ({table.concat(found, "; ")})`
				)
			elseif allowed > 0 and #found == 0 then
				table.insert(problems, `{path} is clean now: delete its PENDING entry in Tokens.spec`)
			end
		end
		if #problems > 0 then
			error(table.concat(problems, "\n"), 0)
		end
	end)

	it("lists only files that exist", function()
		for path in PENDING do
			if not fs.isFile(path) then
				error(`PENDING lists {path}, which does not exist`, 0)
			end
		end
	end)
end)

describe("Old Kit size names", function()
	it("are gone from the whole client", function()
		local files: { string } = {}
		luauFiles("src", files)
		local problems = {}
		for _, path in files do
			local n = 0
			for line in string.gmatch(fs.readFile(path) .. "\n", "([^\n]*)\n") do
				n += 1
				for _, old in { "small", "large", "huge" } do
					if string.find(line, `Kit%.size%.{old}`) then
						table.insert(problems, `{path}:{n} uses Kit.size.{old}`)
					end
				end
			end
		end
		if #problems > 0 then
			error(table.concat(problems, "\n"), 0)
		end
	end)
end)
