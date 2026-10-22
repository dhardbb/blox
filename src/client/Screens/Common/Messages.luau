--!strict
-- Reading the Store's message log. Lines carry ids that only grow, and the log
-- drops its oldest lines, so screens remember the id of the newest line they have
-- handled and ask for what came after it. Counting lines would stall once the log
-- is full.

local Types = require(script.Parent.Parent.Types)

local Messages = {}

-- The id of the newest message (0 when there is none).
function Messages.lastId(state: Types.State): number
	local list = state.messages
	local newest = list[#list]
	return if newest then newest.id else 0
end

-- The newest message that came after `id`, or nil.
function Messages.newestAfter(state: Types.State, id: number): Types.Message?
	local list = state.messages
	local newest = list[#list]
	if newest ~= nil and newest.id > id then
		return newest
	end
	return nil
end

-- The newest rejection that came after `id`, or nil.
function Messages.rejectionAfter(state: Types.State, id: number): Types.Message?
	local list = state.messages
	for k = #list, 1, -1 do
		local message = list[k]
		if message.id <= id then
			return nil
		end
		if message.rejected then
			return message
		end
	end
	return nil
end

return Messages
