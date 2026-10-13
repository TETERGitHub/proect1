--!nonstrict
-- core/Pool: reusable object pool. Rows/cards are acquired, reset and released
-- instead of destroyed, so repeated page switches do not churn instances.
-- Depends on: nothing.

local Pool = {}
Pool.__index = Pool

-- Pool.new{create = fn()->obj, reset = fn(obj), destroy = fn(obj)?, max = n?}
function Pool.new(opts)
	assert(type(opts) == "table" and type(opts.create) == "function", "Pool needs create()")
	return setmetatable({
		_create = opts.create,
		_reset = opts.reset,
		_destroy = opts.destroy,
		_free = {},
		_max = opts.max or 64,
		created = 0,
		reused = 0,
		inUse = 0,
	}, Pool)
end

function Pool:Acquire()
	local obj = table.remove(self._free)
	if obj ~= nil then
		self.reused += 1
	else
		obj = self._create()
		self.created += 1
	end
	self.inUse += 1
	return obj
end

function Pool:Release(obj)
	if obj == nil then
		return
	end
	self.inUse = math.max(0, self.inUse - 1)
	if self._reset then
		local ok = pcall(self._reset, obj)
		if not ok then
			if self._destroy then
				pcall(self._destroy, obj)
			end
			return
		end
	end
	if #self._free >= self._max then
		if self._destroy then
			pcall(self._destroy, obj)
		end
		return
	end
	table.insert(self._free, obj)
end

function Pool:Free()
	return #self._free
end

function Pool:Clear()
	for _, obj in ipairs(self._free) do
		if self._destroy then
			pcall(self._destroy, obj)
		end
	end
	table.clear(self._free)
end

function Pool:Stats()
	return { created = self.created, reused = self.reused, inUse = self.inUse, free = #self._free }
end

return Pool
