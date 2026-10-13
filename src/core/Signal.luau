--!nonstrict
-- core/Signal: lightweight event emitter used by every module (Event Manager).
-- Handlers run in registration order on a snapshot, each inside pcall, so one
-- failing subscriber never blocks the others. Errors go to Signal.onError.
-- Depends on: nothing.

local Signal = {}
Signal.__index = Signal

-- Optional global error sink, wired to Logger by Core. fn(message, signalName)
Signal.onError = nil

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local signal = self._signal
	self._signal = nil
	if signal then
		local list = signal._handlers
		for i = 1, #list do
			if list[i] == self then
				table.remove(list, i)
				break
			end
		end
	end
end

function Signal.new(name)
	return setmetatable({ _handlers = {}, _name = name or "Signal" }, Signal)
end

function Signal:Connect(fn)
	assert(type(fn) == "function", "Signal:Connect expects a function")
	local conn = setmetatable({ Connected = true, _fn = fn, _signal = self }, Connection)
	table.insert(self._handlers, conn)
	return conn
end

function Signal:Once(fn)
	assert(type(fn) == "function", "Signal:Once expects a function")
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Fire(...)
	local list = self._handlers
	if #list == 0 then
		return
	end
	local snapshot = table.clone(list)
	for _, conn in ipairs(snapshot) do
		if conn.Connected then
			local ok, err = pcall(conn._fn, ...)
			if not ok and Signal.onError then
				pcall(Signal.onError, tostring(err), self._name)
			end
		end
	end
end

function Signal:Count()
	return #self._handlers
end

function Signal:DisconnectAll()
	local snapshot = table.clone(self._handlers)
	for _, conn in ipairs(snapshot) do
		conn:Disconnect()
	end
	table.clear(self._handlers)
end

Signal.Destroy = Signal.DisconnectAll

return Signal
