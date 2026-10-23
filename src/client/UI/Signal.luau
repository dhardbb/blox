--!strict
-- A tiny signal for client modules (Motion.changed, Audio.changed): handlers
-- run in order, synchronously, on the caller's thread. Shaped like a Roblox
-- event so callers write `Motion.changed:Connect(fn)`.
--
--   local changed = Signal.new()
--   local connection = changed:Connect(function(value) ... end)
--   changed:Fire(value)
--   connection:Disconnect()

local Signal = {}

export type Connection = {
	Disconnect: (self: Connection) -> (),
}

export type Signal<T> = {
	Connect: (self: Signal<T>, fn: (T) -> ()) -> Connection,
	Fire: (self: Signal<T>, value: T) -> (),
}

function Signal.new<T>(): Signal<T>
	local handlers: { { fn: (T) -> (), live: boolean } } = {}
	local signal = {} :: Signal<T>
	function signal.Connect(_self: Signal<T>, fn: (T) -> ()): Connection
		local entry = { fn = fn, live = true }
		table.insert(handlers, entry)
		local connection = {} :: Connection
		function connection.Disconnect(_c: Connection)
			entry.live = false
			local at = table.find(handlers, entry)
			if at then
				table.remove(handlers, at)
			end
		end
		return connection
	end
	function signal.Fire(_self: Signal<T>, value: T)
		for _, entry in table.clone(handlers) do
			if entry.live then
				entry.fn(value)
			end
		end
	end
	return signal
end

return Signal
