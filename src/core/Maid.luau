--!nonstrict
-- core/Maid: ownership container for connections, instances, functions and
-- nested objects (Cleanup Manager building block). Every Maid is tracked in a
-- weak registry so Diagnostics can report live task counts (feature 88).
-- Depends on: nothing.

local Maid = {}
Maid.__index = Maid

local live = setmetatable({}, { __mode = "k" })

local function disposeTask(task)
	local t = type(task)
	if t == "function" then
		task()
	elseif t == "thread" then
		if coroutine.status(task) ~= "dead" then
			pcall(coroutine.close, task)
		end
	elseif t == "table" then
		if type(task.Disconnect) == "function" then
			task:Disconnect()
		elseif type(task.Destroy) == "function" then
			task:Destroy()
		elseif type(task.Cleanup) == "function" then
			task:Cleanup()
		end
	elseif typeof(task) == "Instance" then
		task:Destroy()
	elseif typeof(task) == "RBXScriptConnection" then
		task:Disconnect()
	end
end

local function validTask(task)
	local t = type(task)
	if t == "function" or t == "thread" then
		return true
	end
	if t == "table" then
		return type(task.Disconnect) == "function" or type(task.Destroy) == "function" or type(task.Cleanup) == "function"
	end
	local tof = typeof(task)
	return tof == "Instance" or tof == "RBXScriptConnection"
end

function Maid.new(name)
	local self = setmetatable({ _tasks = {}, _named = {}, _order = 0, Name = name or "Maid" }, Maid)
	live[self] = true
	return self
end

-- Give(task) -> task. Unsupported task types raise immediately so leaks are
-- caught at the call site rather than at cleanup time.
function Maid:Give(task)
	if not validTask(task) then
		error("Maid:Give unsupported task type: " .. typeof(task), 2)
	end
	self._order += 1
	self._tasks[self._order] = task
	return task
end

function Maid:GiveNamed(name, task)
	assert(type(name) == "string", "name must be a string")
	self:Remove(name)
	if task ~= nil then
		if not validTask(task) then
			error("Maid:GiveNamed unsupported task type: " .. typeof(task), 2)
		end
		self._named[name] = task
	end
	return task
end

function Maid:Remove(name)
	local old = self._named[name]
	if old ~= nil then
		self._named[name] = nil
		local ok, err = pcall(disposeTask, old)
		if not ok then
			return false, tostring(err)
		end
	end
	return true
end

function Maid:Count()
	local n = 0
	for _ in pairs(self._tasks) do
		n += 1
	end
	for _ in pairs(self._named) do
		n += 1
	end
	return n
end

-- Clean(): dispose newest-first. Returns the list of error strings (empty on
-- success); never throws, so cleanup of later tasks always happens.
function Maid:Clean()
	local errors = {}
	local keys = {}
	for k in pairs(self._tasks) do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return a > b
	end)
	for _, k in ipairs(keys) do
		local task = self._tasks[k]
		self._tasks[k] = nil
		local ok, err = pcall(disposeTask, task)
		if not ok then
			table.insert(errors, tostring(err))
		end
	end
	local names = {}
	for k in pairs(self._named) do
		table.insert(names, k)
	end
	for _, k in ipairs(names) do
		local task = self._named[k]
		self._named[k] = nil
		local ok, err = pcall(disposeTask, task)
		if not ok then
			table.insert(errors, tostring(err))
		end
	end
	return errors
end

Maid.Destroy = Maid.Clean

-- Maid.stats() -> { maids = n, tasks = n } across every live Maid.
function Maid.stats()
	local maids, tasks = 0, 0
	for maid in pairs(live) do
		maids += 1
		tasks += maid:Count()
	end
	return { maids = maids, tasks = tasks }
end

-- Per-name breakdown for the Diagnostics page.
function Maid.breakdown()
	local out = {}
	for maid in pairs(live) do
		local c = maid:Count()
		if c > 0 then
			table.insert(out, { name = maid.Name, tasks = c })
		end
	end
	table.sort(out, function(a, b)
		if a.tasks ~= b.tasks then
			return a.tasks > b.tasks
		end
		return a.name < b.name
	end)
	return out
end

return Maid
