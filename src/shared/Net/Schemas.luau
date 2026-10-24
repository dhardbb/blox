--!strict
-- Runtime validation of every client request, before anything else reads it.
-- Checks the envelope only: game inputs (selections, draft picks, plans) are
-- validated later against the match by Match.validate. Never throws.

local Bot = require("../Sim/Bot")
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
	if type(raw) ~= "table" or not Schemas.isPlain(raw) then
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
		-- plays Medium, the standard bot. Never a rejection.
		request.difficulty = Bot.difficulty(raw.difficulty)
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
		-- still the one queued (D-076).
		if op ~= "ReportName" then
			if type(raw.name) ~= "string" then
				return false, "BadShape", nil
			end
			request.name = raw.name
		end
	elseif op == "Forfeit" then
		-- The match being left: a stale request can never end a newer match.
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
