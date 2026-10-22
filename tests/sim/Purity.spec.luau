--!strict
-- Enforces the non-negotiable Sim rules: no Roblox APIs, no wall-clock time,
-- no unseeded randomness, and --!strict at the top of every module.

local fs = require("@lune/fs")

local Test = require("@testlib/Test")

local describe, it, expect = Test.describe, Test.it, Test.expect

-- The simulation, the pure networking core, and the debug UI text helpers.
local PURE_DIRS = { "src/shared/Sim", "src/shared/Net", "src/shared/DebugUI", "src/shared/UI" }

local FORBIDDEN: { { pattern: string, label: string } } = {
	{ pattern = "%f[%w_]game%f[^%w_]", label = "game" },
	{ pattern = "%f[%w_]workspace%f[^%w_]", label = "workspace" },
	{ pattern = "%f[%w_]script%f[^%w_]", label = "script" },
	{ pattern = "%f[%w_]Instance%f[^%w_]", label = "Instance" },
	{ pattern = "%f[%w_]Random%.new", label = "Random.new" },
	{ pattern = "%f[%w_]task%.", label = "task library" },
	{ pattern = "%f[%w_]os%.", label = "os library" },
	{ pattern = "%f[%w_]math%.random", label = "math.random" },
	{ pattern = "%f[%w_]tick%s*%(", label = "tick()" },
	{ pattern = "%f[%w_]wait%s*%(", label = "wait()" },
	{ pattern = "%f[%w_]Enum%.", label = "Enum" },
	{ pattern = "@lune/", label = "Lune library" },
}

-- Removes comments and string literals so the scan only sees code.
local function codeOnly(source: string): string
	local out = string.gsub(source, "%-%-%[(=*)%[.-%]%1%]", "")
	out = string.gsub(out, "%-%-[^\n]*", "")
	out = string.gsub(out, '"[^"\n]*"', '""')
	out = string.gsub(out, "'[^'\n]*'", "''")
	out = string.gsub(out, "`[^`]*`", "``")
	return out
end

local function simFiles(): { string }
	local files = { "src/shared/Types.luau" }
	for _, dir in PURE_DIRS do
		for _, entry in fs.readDir(dir) do
			if string.match(entry, "%.luau$") then
				table.insert(files, `{dir}/{entry}`)
			end
		end
	end
	table.sort(files)
	return files
end

describe("Sim purity", function()
	it("has modules to check", function()
		expect(#simFiles()):toBeGreaterThan(0)
	end)

	for _, path in simFiles() do
		it(`{path} is strict and Roblox-free`, function()
			local source = fs.readFile(path)
			expect(string.sub(source, 1, 9)):toBe("--!strict")
			local code = codeOnly(source)
			for _, rule in FORBIDDEN do
				if string.find(code, rule.pattern) then
					error(`{path} uses forbidden {rule.label}`)
				end
			end
		end)
	end
end)
