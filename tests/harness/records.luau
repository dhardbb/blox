--!strict
-- Balance summary from real matches (docs/DESIGN.md D-094): reads match records
-- exported from the "MatchRecords_v1" DataStore as JSON lines (docs/TESTING.md,
-- "Match records": how to export them with Open Cloud) and prints a report in
-- the balance harness's shape.
--
--   lune run tests/harness/records.luau records.jsonl              -- every record
--   lune run tests/harness/records.luau records.jsonl mode=Queue   -- one mode
--   lune run tests/harness/records.luau records.jsonl humans       -- people vs people only
--   lune run tests/harness/records.luau a.jsonl b.jsonl version=0.17.0
--
-- Modes: Queue, Private, Practice, WaitBot, Tutorial, Daily. Exits 0 either way.

local fs = require("@lune/fs")
local process = require("@lune/process")

local Records = require("@testlib/Records")

local files: { string } = {}
local filter: Records.Filter = {}
for _, arg in process.args do
	if arg == "--" then
		continue
	end
	local key, value = string.match(arg, "^(%a+)=(.+)$")
	if key == "mode" then
		filter.mode = value
	elseif key == "version" then
		filter.version = value
	elseif arg == "humans" then
		filter.humans = true
	else
		table.insert(files, arg)
	end
end

if #files == 0 then
	print("usage: lune run tests/harness/records.luau <records.jsonl>... [mode=Queue] [humans] [version=x]")
	process.exit(1)
end

local all = {}
local skipped = 0
for _, path in files do
	if not fs.isFile(path) then
		print(`no such file: {path}`)
		process.exit(1)
	end
	local records, bad = Records.parse(fs.readFile(path))
	skipped += bad
	for _, record in records do
		table.insert(all, record)
	end
end

local chosen = Records.filter(all, filter)
local parts: { string } = {}
if filter.mode then
	table.insert(parts, `mode {filter.mode}`)
end
if filter.humans then
	table.insert(parts, "people only")
end
if filter.version then
	table.insert(parts, `version {filter.version}`)
end
local title = "270 match records" .. (if #parts > 0 then ` ({table.concat(parts, ", ")})` else "")
local lines = Records.summarize(chosen, title)
for _, text in lines do
	print(text)
end
if skipped > 0 then
	print(`({skipped} line(s) skipped: not a match record, or from a newer schema)`)
end
