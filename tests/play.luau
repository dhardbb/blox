--!strict
-- Agent playtest CLI: plays 270 through the real server and client scripts on the
-- fake Roblox engine (tests/lib/FakeRoblox.luau) and prints what each player's
-- debug UI shows. Not a spec: `lune run tests` ignores it. Run from the repo root.
--
--   lune run tests/play.luau -- [--seed N] [--players 2] [--screen 1280x720] STEP STEP ...
--
-- Each STEP is one quoted string, run in order:
--   p1: <command>        type a debug UI command as player 1 (p2:, p3: ... likewise)
--   p1! <Button>         press a button: Practice Queue Host Auto Autoplay Pass Bank Skip Help
--   wait <seconds>       advance simulated time
--   until pN <text> [limit]
--                        run until pN's status, board or log shows text (default limit 300 s).
--                        Quote text that has spaces and ends in a number: until p1 "Week 2 Plan" 60
--                        Unquoted, a trailing number is the limit: until p1 match over 400
--   autoto <text> [limit]
--                        press Auto for every player whose status says "your move", over and
--                        over, until p1's status contains text (same quoting as `until`). Use
--                        it to skip ahead, e.g. autoto "Week 1 Plan · Input", then type a plan.
--   screen pN            print pN's status line, board and log
--   history pN           print every log line pN's UI has shown (the UI keeps only the last 5)
--   logs                 print the server Output and each client's Output (WARN = warn())
--   fire pN <json>       send a raw request as pN, e.g. {"op":"Resync"}
-- After each command, button press or fire, 0.2 s of simulated time passes so the
-- reply arrives. The script ends with a summary (simulated time, script errors,
-- wire warnings, failed steps). Exit code: 1 if there were script errors, 2 if only
-- a step failed (an `until` timed out, a bad step), else 0.
--
-- Examples
--   Practice match to the end (Autoplay), then read the result:
--     lune run tests/play.luau -- "p1: practice" "p1! Autoplay" \
--         "until p1 match over" "screen p1" "logs"
--
--   Two players: queue, Player1 types a selection, Player2 lets the bot pick, both
--   auto-play to week 1, then Player1 types a plan (home state is on the board's YOU line):
--     lune run tests/play.luau -- --seed 7 "p1: queue" "p2: queue" \
--         "p1: select hale teal jobs farms safety" "p2! Auto" \
--         "autoto Week 1 Plan · Input 120" "p1: plan rally TX jobs; fund TX; poll OH" \
--         "screen p1" "screen p2"

local process = require("@lune/process")
local serde = require("@lune/serde")

local FakeRoblox = require("@testlib/FakeRoblox")
local Support = require("./e2e/Support")

-- ---------------------------------------------------------------- arguments

local seed, playerCount, screen = 1, 2, { x = 1280, y = 720 }
local steps: { string } = {}

local usageError: string? = nil
do
	local args = process.args
	local k = 1
	while k <= #args do
		local arg = args[k]
		if arg == "--" then
			k += 1
		elseif arg == "--seed" or arg == "--players" or arg == "--screen" then
			local value = args[k + 1]
			if value == nil then
				usageError = `{arg} needs a value`
				break
			end
			if arg == "--seed" then
				seed = tonumber(value) or seed
			elseif arg == "--players" then
				playerCount = tonumber(value) or playerCount
			else
				local x, y = string.match(value, "^(%d+)x(%d+)$")
				if x == nil then
					usageError = `--screen needs WIDTHxHEIGHT, got {value}`
					break
				end
				screen = { x = tonumber(x) :: number, y = tonumber(y) :: number }
			end
			k += 2
		else
			table.insert(steps, arg)
			k += 1
		end
	end
end

if usageError or #steps == 0 then
	if usageError then
		print(`error: {usageError}`)
	end
	print(
		'usage: lune run tests/play.luau -- [--seed N] [--players 2] [--screen 1280x720] "p1: practice" ...'
	)
	print(
		"steps: pN: <command> | pN! <Button> | wait <s> | until pN <text> [limit] | autoto <text> [limit] | screen pN | history pN | logs | fire pN <json>"
	)
	print("see the header of tests/play.luau for examples")
	process.exit(2)
end

-- ---------------------------------------------------------------- run

local rig = Support.new(process.cwd, seed, screen)
local world = rig.world
local peers = Support.players(rig, playerCount)
local started = world.clock

local failures: { string } = {}

local function fail(step: string, why: string)
	local line = `FAIL [{step}]: {why}`
	table.insert(failures, line)
	print(line)
end

local function peerFor(name: string, step: string): FakeRoblox.Peer?
	local n = tonumber(string.match(name, "^p(%d+)$") or "")
	local peer = if n then peers[n] else nil
	if peer == nil then
		fail(step, `no player "{name}" (players are p1..p{#peers})`)
	end
	return peer
end

local function elapsed(): string
	return string.format("t=%.1fs", world.clock - started)
end

local function printScreen(peer: FakeRoblox.Peer)
	local s = Support.screen(peer)
	print(`===== screen {peer.name} @ {elapsed()} =====`)
	print("--- status ---")
	print(s.status)
	print("--- board ---")
	print(s.board)
	print("--- log ---")
	print(s.log)
	print("===== end screen =====")
end

local function printLines(title: string, lines: { string })
	print(`--- {title} ({#lines} lines) ---`)
	for _, line in lines do
		print(line)
	end
end

-- Splits `until` / `autoto` arguments into (text, limit).
local function untilArgs(rest: string): (string, number)
	local quoted, after = string.match(rest, '^"([^"]*)"%s*(.*)$')
	if quoted then
		return quoted, tonumber(after) or 300
	end
	local text, limit = string.match(rest, "^(.-)%s+(%d+%.?%d*)$")
	if text and text ~= "" then
		return text, tonumber(limit) or 300
	end
	return rest, 300
end

local function runStep(step: string)
	local who, command = string.match(step, "^(p%d+):%s*(.-)%s*$")
	if who then
		local peer = peerFor(who, step)
		if peer then
			Support.type(rig, peer, command)
		end
		return
	end
	local pressWho, button = string.match(step, "^(p%d+)!%s*(%S+)%s*$")
	if pressWho then
		local peer = peerFor(pressWho, step)
		if peer then
			if FakeRoblox.find(peer, button) == nil then
				fail(step, `no button "{button}"`)
			else
				Support.press(rig, peer, button)
			end
		end
		return
	end
	local seconds = string.match(step, "^wait%s+([%d%.]+)%s*$")
	if seconds then
		Support.run(rig, tonumber(seconds) :: number)
		return
	end
	local untilWho, rest = string.match(step, "^until%s+(p%d+)%s+(.+)$")
	if untilWho then
		local peer = peerFor(untilWho, step)
		if peer then
			local text, limit = untilArgs(rest :: string)
			local ok = Support.runUntil(rig, function()
				return Support.shows(peer, text) or Support.said(rig, peer, text)
			end, limit)
			if ok then
				print(`ok [{step}] after {elapsed()}`)
			else
				fail(step, `"{text}" never appeared on {untilWho} within {limit}s (now {elapsed()})`)
			end
		end
		return
	end
	local autoRest = string.match(step, "^autoto%s+(.+)$")
	if autoRest then
		local text, limit = untilArgs(autoRest)
		if Support.autoUntil(rig, peers, text, limit) then
			print(`ok [{step}] after {elapsed()}`)
		else
			fail(step, `"{text}" never appeared on p1 within {limit}s (now {elapsed()})`)
		end
		return
	end
	local screenWho = string.match(step, "^screen%s+(p%d+)%s*$")
	if screenWho then
		local peer = peerFor(screenWho, step)
		if peer then
			printScreen(peer)
		end
		return
	end
	local historyWho = string.match(step, "^history%s+(p%d+)%s*$")
	if historyWho then
		local peer = peerFor(historyWho, step)
		if peer then
			printLines(`{peer.name} UI log history`, rig.history[peer])
		end
		return
	end
	if step == "logs" then
		print(`===== logs @ {elapsed()} =====`)
		printLines("server Output", world.server.log)
		for _, peer in peers do
			printLines(`{peer.name} Output`, peer.log)
		end
		print("===== end logs =====")
		return
	end
	local fireWho, json = string.match(step, "^fire%s+(p%d+)%s+(.+)$")
	if fireWho then
		local peer = peerFor(fireWho, step)
		if peer then
			local ok, payload = pcall(serde.decode, "json" :: "json", json :: string)
			if not ok then
				fail(step, `bad JSON: {string.match(tostring(payload), "^[^\n]*")}`)
			else
				Support.fire(rig, peer, payload)
			end
		end
		return
	end
	fail(step, "unknown step")
end

for _, step in steps do
	runStep(step)
end

-- ---------------------------------------------------------------- summary

print("===== summary =====")
print(string.format("simulated time elapsed: %.1fs", world.clock - started))
print(`script errors: {#world.errors}`)
for _, message in world.errors do
	print(`  {message}`)
end
print(`wire warnings: {#world.wireWarnings}`)
for _, message in world.wireWarnings do
	print(`  {message}`)
end
print(`failed steps: {#failures}`)
for _, message in failures do
	print(`  {message}`)
end

if #world.errors > 0 then
	process.exit(1)
elseif #failures > 0 then
	process.exit(2)
end
