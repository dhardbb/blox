--!strict
-- Shared helpers for the end-to-end specs (tests/e2e) and the playtest CLI
-- (tests/play.luau). Wraps the fake Roblox engine with a recorder: the debug UI
-- shows only the last five log lines, so the recorder snapshots every client's
-- UI log after each simulated step and keeps every line it ever showed.

local FakeRoblox = require("@testlib/FakeRoblox")

local Support = {}

export type Rig = {
	world: FakeRoblox.World,
	peers: { FakeRoblox.Peer },
	history: { [FakeRoblox.Peer]: { string } }, -- every UI log line each client has shown
	last: { [FakeRoblox.Peer]: { string } }, -- the previous UI log snapshot
	logBoxes: { [FakeRoblox.Peer]: any },
}

local STEP = 0.1

local function lines(text: string): { string }
	local out = {}
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end

-- Appends the lines of `now` that were not already at the end of `before`.
local function appendNew(history: { string }, before: { string }, now: { string })
	local overlap = 0
	for k = math.min(#before, #now), 1, -1 do
		local same = true
		for i = 1, k do
			if before[#before - k + i] ~= now[i] then
				same = false
				break
			end
		end
		if same then
			overlap = k
			break
		end
	end
	for i = overlap + 1, #now do
		table.insert(history, now[i])
	end
end

local function record(rig: Rig)
	for _, peer in rig.peers do
		local box = rig.logBoxes[peer]
		if box == nil then
			box = FakeRoblox.find(peer, "Log")
			rig.logBoxes[peer] = box
		end
		if box ~= nil then
			local now = lines(tostring(box.Text))
			appendNew(rig.history[peer], rig.last[peer], now)
			rig.last[peer] = now
		end
	end
end

-- A new world with the server running and no players.
function Support.new(root: string, seed: number?, screen: { x: number, y: number }?): Rig
	local world = FakeRoblox.world({ root = root, seed = seed or 1, screen = screen })
	return { world = world, peers = {}, history = {}, last = {}, logBoxes = {} }
end

-- Adds a player and lets their client start up. `attributes` go on that client's
-- workspace (e.g. DebugText = true shows the debug panel).
function Support.join(rig: Rig, name: string, attributes: { [string]: any }?): FakeRoblox.Peer
	local peer = FakeRoblox.join(rig.world, name, attributes)
	table.insert(rig.peers, peer)
	rig.history[peer] = {}
	rig.last[peer] = {}
	FakeRoblox.run(rig.world, 1)
	record(rig)
	return peer
end

-- A player disconnects (the recorder keeps their history).
function Support.leave(rig: Rig, peer: FakeRoblox.Peer)
	FakeRoblox.leave(rig.world, peer)
	local at = table.find(rig.peers, peer)
	if at then
		table.remove(rig.peers, at)
	end
end

function Support.run(rig: Rig, seconds: number)
	for _ = 1, math.ceil(seconds / STEP - 1e-9) do
		FakeRoblox.step(rig.world, STEP)
		record(rig)
	end
end

-- Runs until `predicate()` holds or `limit` simulated seconds pass.
function Support.runUntil(rig: Rig, predicate: () -> boolean, limit: number): boolean
	local waited = 0
	while waited < limit do
		if predicate() then
			return true
		end
		FakeRoblox.step(rig.world, STEP)
		record(rig)
		waited += STEP
	end
	return predicate()
end

-- Types a command / presses a button, then lets the message round trip settle.
function Support.type(rig: Rig, peer: FakeRoblox.Peer, command: string)
	FakeRoblox.type(rig.world, peer, command)
	Support.run(rig, 0.2)
end

function Support.press(rig: Rig, peer: FakeRoblox.Peer, label: string)
	FakeRoblox.press(rig.world, peer, label)
	Support.run(rig, 0.2)
end

function Support.fire(rig: Rig, peer: FakeRoblox.Peer, payload: any)
	FakeRoblox.fire(rig.world, peer, payload)
	Support.run(rig, 0.2)
end

-- What the client's debug UI shows right now, as one string per widget.
function Support.screen(peer: FakeRoblox.Peer): { status: string, board: string, log: string }
	return FakeRoblox.screen(peer)
end

-- True if `text` (plain match) is in the status line, board or log right now.
function Support.shows(peer: FakeRoblox.Peer, text: string): boolean
	local s = FakeRoblox.screen(peer)
	return string.find(s.status, text, 1, true) ~= nil
		or string.find(s.board, text, 1, true) ~= nil
		or string.find(s.log, text, 1, true) ~= nil
end

-- True if the client's UI log has ever shown a line containing `text`.
function Support.said(rig: Rig, peer: FakeRoblox.Peer, text: string): boolean
	for _, line in rig.history[peer] do
		if string.find(line, text, 1, true) then
			return true
		end
	end
	return false
end

-- All lines of an Output window (server or client) containing `text`.
function Support.outputLines(peer: FakeRoblox.Peer, text: string): { string }
	local out = {}
	for _, line in peer.log do
		if string.find(line, text, 1, true) then
			table.insert(out, line)
		end
	end
	return out
end

-- Joins `count` players, named Player1..PlayerN.
function Support.players(rig: Rig, count: number): { FakeRoblox.Peer }
	local out = {}
	for k = 1, count do
		table.insert(out, Support.join(rig, `Player{k}`))
	end
	return out
end

-- Both players press Queue and a two-player match starts.
function Support.queueMatch(rig: Rig, a: FakeRoblox.Peer, b: FakeRoblox.Peer)
	Support.press(rig, a, "Queue")
	Support.press(rig, b, "Queue")
	Support.run(rig, 0.5)
end

-- The "Election night: you N EV - M EV them" line: (N, M), or nil.
function Support.electionScore(peer: FakeRoblox.Peer): (number?, number?)
	local board = FakeRoblox.screen(peer).board
	local n, m = string.match(board, "Election night: you (%d+) EV %- (%d+) EV them")
	return tonumber(n), tonumber(m)
end

-- Runs until the stage text for `peer` contains `phase` ("Week 1 Plan", "Select"...).
function Support.untilStatus(rig: Rig, peer: FakeRoblox.Peer, text: string, limit: number): boolean
	return Support.runUntil(rig, function()
		return string.find(FakeRoblox.screen(peer).status, text, 1, true) ~= nil
	end, limit)
end

-- Plays every step with the debug UI's Auto button (for each player whose status
-- says "your move") until the first player's status contains `text`. The text is
-- checked before anyone is auto-played, so the stage you asked for is still open.
function Support.autoUntil(rig: Rig, peers: { FakeRoblox.Peer }, text: string, limit: number): boolean
	local waited = 0
	while waited < limit do
		Support.run(rig, 0.5)
		waited += 0.5
		if string.find(FakeRoblox.screen(peers[1]).status, text, 1, true) then
			return true
		end
		for _, peer in peers do
			if string.find(FakeRoblox.screen(peer).status, "your move", 1, true) then
				Support.press(rig, peer, "Auto")
				waited += 0.2
			end
		end
	end
	return false
end

-- The seconds left shown in the status line ("... Input · 90s · ..."), or nil.
function Support.countdown(peer: FakeRoblox.Peer): number?
	return tonumber(string.match(FakeRoblox.screen(peer).status, "· (%d+)s"))
end

-- The player's home state code from the board's YOU line, or nil before the draft.
function Support.homeState(peer: FakeRoblox.Peer): string?
	for line in string.gmatch(FakeRoblox.screen(peer).board, "[^\n]+") do
		if string.sub(line, 1, 3) == "YOU" then
			return string.match(line, "home (%u%u)")
		end
	end
	return nil
end

return Support
