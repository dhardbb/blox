--!strict
-- MemoryStoreService access for matching across servers and the online count
-- (docs/DESIGN.md D-080). Every call is pcall'd and retried with backoff
-- (Matchmaking.ATTEMPTS, BACKOFF); a failure returns false and never throws.
--
-- Off in Studio and in an unpublished place (PlaceId 0): Studio's memory stores
-- are a separate test scope that no live server sees, and TeleportService does
-- not work in Studio playtests, so a Studio server matches in-server only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Matchmaking = require(ReplicatedStorage.Shared.Net.Matchmaking)

local Memory = {}

local structures: { [string]: any } = {}
local warnedAt: { [string]: number } = {} -- label -> os.clock() of its last warning
local WARN_EVERY = 60 -- s between warnings for one kind of call

-- True if this server may use memory stores and teleports at all.
function Memory.available(): boolean
	local studio = false
	pcall(function()
		studio = RunService:IsStudio()
	end)
	if studio then
		return false
	end
	local placeId = 0
	pcall(function()
		placeId = game.PlaceId
	end)
	return placeId ~= 0
end

local function structure(kind: "Sorted" | "Hash", name: string): any?
	local key = `{kind}:{name}`
	local found = structures[key]
	if found ~= nil then
		return found
	end
	local ok, result = pcall(function(): any
		local service = game:GetService("MemoryStoreService")
		if kind == "Sorted" then
			return service:GetSortedMap(name)
		end
		return service:GetHashMap(name)
	end)
	if ok and result ~= nil then
		structures[key] = result
		return result
	end
	return nil
end

function Memory.sorted(name: string): any?
	return structure("Sorted", name)
end

function Memory.hash(name: string): any?
	return structure("Hash", name)
end

local function warnSome(label: string, err: any)
	local t = os.clock()
	local last = warnedAt[label]
	if last == nil or t - last >= WARN_EVERY then
		warnedAt[label] = t
		warn(`[270] MemoryStore {label} failed: {err}`)
	end
end

-- Calls `fn` (which yields on a MemoryStore request) up to ATTEMPTS times.
-- Returns (true, its result) or (false, nil).
function Memory.call(label: string, fn: () -> any): (boolean, any)
	local lastErr: any = nil
	for attempt = 1, Matchmaking.ATTEMPTS do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if attempt < Matchmaking.ATTEMPTS then
			task.wait(Matchmaking.BACKOFF * 2 ^ (attempt - 1))
		end
	end
	warnSome(label, lastErr)
	return false, nil
end

return Memory
