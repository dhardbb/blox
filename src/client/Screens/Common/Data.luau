--!strict
-- Lookups the Lobby, Select and Results screens share: issue names, candidate
-- names, and the opponent's seat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Candidates = require(ReplicatedStorage.Shared.Sim.Candidates)
local ConfigModule = require(ReplicatedStorage.Shared.Sim.Config)
local Issues = require(ReplicatedStorage.Shared.Sim.Issues)
local Session = require(ReplicatedStorage.Shared.Net.Session)

local Data = {}

local names: { [string]: string } = Issues.displayName :: any

function Data.issueName(issue: string): string
	return names[issue] or issue
end

-- "Jobs, Health, Schools" for a platform.
function Data.platformText(platform: { any }?): string
	if platform == nil or #platform == 0 then
		return "not chosen"
	end
	local parts: { string } = {}
	for _, issue in platform do
		table.insert(parts, Data.issueName(tostring(issue)))
	end
	return table.concat(parts, ", ")
end

function Data.candidateName(config: ConfigModule.Config, id: string?): string
	if id == nil or not Candidates.exists(id) then
		return "Unknown"
	end
	return Candidates.profile(config, id).name
end

-- The other seat in a two-player match: (index, info).
function Data.opponent(payload: Session.StatePayload): (number, Session.SeatInfo?)
	for index, seat in payload.seats do
		if index ~= payload.you then
			return index, seat
		end
	end
	return 0, nil
end

return Data
