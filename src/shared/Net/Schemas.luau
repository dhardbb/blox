--!strict
-- Runtime validation of every client request, before anything else reads it.
-- Checks the envelope only: game inputs (selections, draft picks, plans) are
-- validated later against the match by Match.validate. Never throws.

local Bot = require("../Sim/Bot")
local BugReport = require("./BugReport")
local Remotes = require("./Remotes")

local Schemas = {}

local MAX_DEPTH = 6 -- deepest nesting a request may have (a plan is 4 deep)
local MAX_NODES = 600 -- most table entries in one request (40 actions x 8 fields, with room)
local MAX_STRING = 64 -- longest string anywhere in a request
local CODE_PATTERN = "^[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]$"

local OPS: { [string]: boolean } = {
	Queue = true,
	Host = true,
	Join = true,
	Practice = true,
	Leave = true,
	PrePick = true,
	SetColor = true,
	SetName = true,
	ReportName = true,
	ReviewList = true,
	ReviewKeep = true,
	ReviewRemove = true,
	Claim = true,
	ClaimColor = true,
	Submit = true,
	Bank = true,
	Skip = true,
	Resync = true,
	Leaderboard = true,
	Forfeit = true,
	SetTimersOff = true,
	DailyRace = true, -- no fields (D-082)
	Daily = true, -- no fields (D-082)
	WaitBot = true,
	Answer = true,
	Rematch = true,
	Return = true,
	BugReport = true, -- { text, screen? } (D-090)
	BugList = true, -- admins, no fields (D-090)
}

-- True if `value` is plain data within the size limits: only tables, strings,
-- numbers and booleans, no cycles, bounded depth, entries and string length.
function Schemas.isPlain(value: any): boolean
	local nodes = 0
	local seen: { [any]: boolean } = {}
	local function walk(v: any, depth: number): boolean
		local kind = type(v)
		if kind == "string" then
			return #v <= MAX_STRING
		elseif kind == "number" then
			return v == v and v ~= math.huge and v ~= -math.huge
		elseif kind == "boolean" then
			return true
		elseif kind ~= "table" then
			return false
		end
		if depth > MAX_DEPTH or seen[v] then
			return false
		end
		seen[v] = true
		for key, child in v do
			nodes += 1
			if nodes > MAX_NODES then
				return false
			end
			local keyKind = type(key)
			if keyKind ~= "string" and keyKind ~= "number" then
				return false
			end
			if not walk(key, depth + 1) or not walk(child, depth + 1) then
				return false
			end
		end
		return true
	end
	local ok, result = pcall(walk, value, 1)
	return ok and result == true
end

function Schemas.isCode(value: any): boolean
	return type(value) == "string" and string.match(value, CODE_PATTERN) ~= nil
end

-- Validates a raw request. Returns (true, nil, request) or (false, reason, nil).
function Schemas.request(raw: any): (boolean, string?, Remotes.Request?)
	if type(raw) ~= "table" then
		return false, "BadShape", nil
	end
	-- A bug report's text is the one string allowed past MAX_STRING (D-090): it
	-- is checked on its own (a string, at most BugReport.MAX_BYTES) and the rest
	-- of the request as usual.
	local reportText: string? = nil
	if raw.op == "BugReport" then
		if type(raw.text) ~= "string" or #raw.text > BugReport.MAX_BYTES then
			return false, "BadShape", nil
		end
		reportText = raw.text
		local rest = table.clone(raw)
		rest.text = nil
		raw = rest
	end
	if not Schemas.isPlain(raw) then
		return false, "BadShape", nil
	end
	local op = raw.op
	if type(op) ~= "string" or not OPS[op] then
		return false, "UnknownOp", nil
	end
	local request: Remotes.Request = { op = op :: Remotes.Op }
	if op == "Host" then
		-- Optional private-match setting: events = false turns the event deck off.
		if raw.events ~= nil then
			if type(raw.events) ~= "boolean" then
				return false, "BadShape", nil
			end
			request.events = raw.events
		end
	elseif op == "Join" then
		if not Schemas.isCode(raw.code) then
			return false, "BadCode", nil
		end
		request.code = raw.code
	elseif op == "Practice" then
		-- Optional bot difficulty (D-057): absent or not one of the four names
		-- plays Easy (D-087). Never a rejection.
		request.difficulty = Bot.difficulty(raw.difficulty)
		-- Optional tutorial replay (D-075): only `true` asks for it; anything else
		-- is an ordinary practice match. Never a rejection either.
		if raw.tutorial == true then
			request.tutorial = true
		end
	elseif op == "PrePick" then
		if type(raw.pick) ~= "table" then
			return false, "BadShape", nil
		end
		request.pick = raw.pick
	elseif op == "SetColor" then
		-- Optional: absent means auto. Which names are colors is the server's check.
		if raw.color ~= nil then
			if type(raw.color) ~= "string" then
				return false, "BadShape", nil
			end
			request.color = raw.color
		end
	elseif op == "SetName" then
		-- Optional: absent means the candidate's own name. Cleaning, the length
		-- limit and the text filter are the server's checks (D-069).
		if raw.name ~= nil then
			if type(raw.name) ~= "string" then
				return false, "BadShape", nil
			end
			request.name = raw.name
		end
	elseif op == "ReportName" or op == "ReviewKeep" or op == "ReviewRemove" then
		-- A user id as digits; who may do this, and to whom, is the server's check (D-069).
		if type(raw.userId) ~= "string" or not string.match(raw.userId, "^%d+$") or #raw.userId > 20 then
			return false, "BadShape", nil
		end
		request.userId = raw.userId
		-- A review names the name the admin saw: the server acts only if it is
		-- still the one queued (D-078).
		if op ~= "ReportName" then
			if type(raw.name) ~= "string" then
				return false, "BadShape", nil
			end
			request.name = raw.name
		end
	elseif op == "BugReport" then
		-- The length rules, the text filter and the rate limit are the server's
		-- checks (D-090); the screen is a short tag (BugReport.screen cleans it).
		if raw.screen ~= nil and type(raw.screen) ~= "string" then
			return false, "BadShape", nil
		end
		request.text = reportText
		request.screen = raw.screen
	elseif op == "SetTimersOff" then
		-- An admin's "Timers off" toggle (D-081): a boolean, required. Who is an
		-- admin, and what it does, is the server's check.
		if type(raw.on) ~= "boolean" then
			return false, "BadShape", nil
		end
		request.on = raw.on
	elseif op == "WaitBot" then
		-- The bot's level, as for Practice (D-057): never a rejection.
		request.difficulty = Bot.difficulty(raw.difficulty)
	elseif op == "Answer" then
		if type(raw.accept) ~= "boolean" then
			return false, "BadShape", nil
		end
		request.accept = raw.accept
	elseif op == "Forfeit" or op == "Rematch" then
		-- Forfeit: the match being left, so a stale request can never end a newer
		-- match. Rematch: the finished match to play again (D-083).
		if type(raw.matchId) ~= "string" then
			return false, "BadShape", nil
		end
		request.matchId = raw.matchId
	elseif op == "Submit" or op == "Claim" or op == "ClaimColor" or op == "Bank" or op == "Skip" then
		local matchId, step = raw.matchId, raw.step
		if type(matchId) ~= "string" or type(step) ~= "number" or step ~= math.floor(step) then
			return false, "BadShape", nil
		end
		request.matchId = matchId
		request.step = step
		if op == "Submit" then
			if raw.input == nil then
				return false, "BadShape", nil
			end
			request.input = raw.input
		elseif op == "Claim" then
			if type(raw.input) ~= "string" then
				return false, "BadShape", nil
			end
			request.input = raw.input
		elseif op == "ClaimColor" then
			-- Which names are colors, and who may claim one, is the match's check (D-061).
			if type(raw.color) ~= "string" then
				return false, "BadShape", nil
			end
			request.color = raw.color
		end
	end
	return true, nil, request
end

return table.freeze(Schemas)
