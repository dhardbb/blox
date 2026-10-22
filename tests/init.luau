--!strict
-- Test entry point: `lune run tests` (optionally `lune run tests <name filter>`).
-- Loads every *.spec.luau under tests/ and runs the registered cases.

local fs = require("@lune/fs")
local process = require("@lune/process")

local Test = require("@self/lib/Test")

local function collect(dir: string, out: { string })
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(entry, "%.spec%.luau$") then
			table.insert(out, path)
		end
	end
end

if not fs.isFile("default.project.json") then
	print("Run tests from the repository root: lune run tests")
	process.exit(1)
end

local specs = {}
collect("tests", specs)

for _, path in specs do
	-- "tests/sim/Rng.spec.luau" -> "@self/sim/Rng.spec"
	local modulePath = "@self/" .. string.gsub(string.sub(path, #"tests/" + 1), "%.luau$", "")
	require(modulePath)
end

local filter: string? = nil
for _, arg in process.args do
	if arg ~= "--" then
		filter = arg
	end
end
local clock = os.clock()
local passed, failed = Test.run(filter)
print(
	string.format("%d passed, %d failed (%d spec files, %.2fs)", passed, failed, #specs, os.clock() - clock)
)

if failed > 0 or passed == 0 then
	process.exit(1)
end
