--!nonstrict
-- core/Core: module lifecycle (registration, dependency ordering, start/stop,
-- isolated failure + restart) and re-initialisation detection.
-- Depends on: Maid, Logger, Signal, Env, Cleanup.

local import = ...
local Maid = import("core/Maid")
local Logger = import("core/Logger")
local Signal = import("core/Signal")
local Env = import("core/Env")

local Core = {}

Core.StateChanged = Signal.new("Core.StateChanged") -- (moduleName, state, err)

local modules = {} -- name -> record
local order = {} -- registration order
local startOrder = {} -- actual start order
local MAX_ATTEMPTS = 3
local clock = os.clock

-- registerModule{name, deps?, optionalEnv?, start=fn(ctx), stop=fn(ctx)?}
function Core.registerModule(def)
	assert(type(def) == "table" and type(def.name) == "string", "module needs a name")
	assert(type(def.start) == "function", "module needs start(): " .. def.name)
	assert(not modules[def.name], "duplicate module: " .. def.name)
	modules[def.name] = {
		name = def.name,
		deps = def.deps or {},
		optionalEnv = def.optionalEnv or {},
		start = def.start,
		stop = def.stop,
		state = "registered", -- registered|running|failed|blocked|stopped
		attempts = 0,
		err = nil,
		startMs = 0,
		maid = nil,
	}
	table.insert(order, def.name)
end

-- checkDependencies() -> problems{ {module, kind, detail} }
function Core.checkDependencies()
	local problems = {}
	for _, name in ipairs(order) do
		local m = modules[name]
		for _, dep in ipairs(m.deps) do
			if not modules[dep] then
				table.insert(problems, { module = name, kind = "missing-module", detail = dep })
			end
		end
		for _, cap in ipairs(m.optionalEnv) do
			if not Env.has(cap) then
				table.insert(problems, { module = name, kind = "missing-env", detail = cap })
			end
		end
	end
	-- cycle detection (DFS)
	local visiting, done = {}, {}
	local function visit(name, path)
		if done[name] then
			return
		end
		if visiting[name] then
			table.insert(problems, { module = name, kind = "cycle", detail = table.concat(path, " -> ") .. " -> " .. name })
			return
		end
		visiting[name] = true
		table.insert(path, name)
		local m = modules[name]
		if m then
			for _, dep in ipairs(m.deps) do
				if modules[dep] then
					visit(dep, path)
				end
			end
		end
		table.remove(path)
		visiting[name] = nil
		done[name] = true
	end
	for _, name in ipairs(order) do
		visit(name, {})
	end
	return problems
end

local function setState(m, state, err)
	m.state = state
	m.err = err
	Core.StateChanged:Fire(m.name, state, err)
end

local function startOne(m, ctx)
	for _, dep in ipairs(m.deps) do
		local d = modules[dep]
		if not d or d.state ~= "running" then
			setState(m, "blocked", "dependency '" .. dep .. "' is not running")
			Logger.warn("Core", "%s blocked: dependency %s not running", m.name, dep)
			return false
		end
	end
	m.attempts += 1
	m.maid = Maid.new("module:" .. m.name)
	local t0 = clock()
	local mctx = setmetatable({ maid = m.maid, name = m.name }, { __index = ctx })
	local ok, err = xpcall(m.start, function(e)
		return tostring(e) .. "\n" .. debug.traceback("", 2)
	end, mctx)
	m.startMs = (clock() - t0) * 1000
	if ok then
		setState(m, "running")
		table.insert(startOrder, m.name)
		Logger.info("Core", "%s started in %.1f ms", m.name, m.startMs)
		return true
	end
	m.maid:Clean()
	m.maid = nil
	setState(m, "failed", tostring(err))
	Logger.error("Core", "%s failed to start: %s", m.name, tostring(err))
	return false
end

-- startAll(ctx) -> {started, failed, blocked}. Dependency-ordered; a failing
-- module never prevents unrelated modules from starting.
function Core.startAll(ctx)
	ctx = ctx or {}
	local pending = table.clone(order)
	local progressed = true
	local report = { started = {}, failed = {}, blocked = {} }
	while #pending > 0 and progressed do
		progressed = false
		for i = #pending, 1, -1 do
			local m = modules[pending[i]]
			local ready = true
			for _, dep in ipairs(m.deps) do
				local d = modules[dep]
				if d and (d.state == "registered" or d.state == "stopped") then
					ready = false
					break
				end
			end
			if ready then
				table.remove(pending, i)
				progressed = true
				if startOne(m, ctx) then
					table.insert(report.started, m.name)
				elseif m.state == "blocked" then
					table.insert(report.blocked, m.name)
				else
					table.insert(report.failed, m.name)
				end
			end
		end
	end
	for _, name in ipairs(pending) do
		local m = modules[name]
		setState(m, "blocked", "unresolvable dependencies")
		table.insert(report.blocked, name)
	end
	Core._ctx = ctx
	return report
end

local function stopOne(m)
	if m.state ~= "running" then
		return true
	end
	local ok, err = true, nil
	if m.stop then
		ok, err = xpcall(m.stop, function(e)
			return tostring(e)
		end, { maid = m.maid, name = m.name })
		if not ok then
			Logger.error("Core", "%s stop error: %s", m.name, tostring(err))
		end
	end
	if m.maid then
		local errors = m.maid:Clean()
		for _, e in ipairs(errors) do
			Logger.error("Core", "%s cleanup error: %s", m.name, e)
		end
		m.maid = nil
	end
	local i = table.find(startOrder, m.name)
	if i then
		table.remove(startOrder, i)
	end
	setState(m, "stopped", if ok then nil else tostring(err))
	return ok
end

-- stopAll() -> {stopped, errors}. Reverse start order.
function Core.stopAll()
	local report = { stopped = 0, errors = 0 }
	for i = #startOrder, 1, -1 do
		local m = modules[startOrder[i]]
		if m then
			report.stopped += 1
			if not stopOne(m) then
				report.errors += 1
			end
		end
	end
	return report
end

-- restart(name) -> ok, err. Dependents are not restarted; the UI offers per-module restart.
function Core.restart(name)
	local m = modules[name]
	if not m then
		return false, "unknown module"
	end
	if m.attempts >= MAX_ATTEMPTS + 5 then
		return false, "too many restart attempts"
	end
	stopOne(m)
	local ok = startOne(m, Core._ctx or {})
	return ok, m.err
end

-- the hub's own infrastructure cannot be switched off from the module list (everything else stands on it)
local PROTECTED = { services = true, input = true, window = true }

-- stopModule(name) -> ok, err: switches one module off (its connections, loops and objects are released). Refused for the
-- infrastructure and while a running module depends on it.
function Core.stopModule(name)
	local m = modules[name]
	if not m then
		return false, "unknown module"
	end
	if PROTECTED[name] then
		return false, "core infrastructure cannot be stopped"
	end
	if m.state ~= "running" then
		return false, "not running"
	end
	for _, other in pairs(modules) do
		if other.state == "running" and other.deps and table.find(other.deps, name) then
			return false, "needed by " .. other.name
		end
	end
	return stopOne(m), m.err
end

function Core.status()
	local out = {}
	for _, name in ipairs(order) do
		local m = modules[name]
		table.insert(out, { name = name, state = m.state, err = m.err, attempts = m.attempts, startMs = m.startMs, deps = m.deps })
	end
	return out
end

function Core.moduleState(name)
	return modules[name] and modules[name].state
end

function Core.setClock(fn)
	clock = fn or os.clock
end

-- boot(opts) -> handle. Detects a previous instance in the shared global table and
-- shuts it down first (re-initialisation), then registers this instance's shutdown.
-- opts = {globalKey, shutdown = fn}
function Core.boot(opts)
	local g = Env.global()
	local key = opts.globalKey or "__MM2HUB"
	local previous = g[key]
	local replaced = false
	if type(previous) == "table" and type(previous.shutdown) == "function" then
		replaced = true
		Logger.warn("Core", "previous hub instance detected; shutting it down")
		local ok, err = pcall(previous.shutdown)
		if not ok then
			Logger.error("Core", "previous instance shutdown failed: %s", tostring(err))
		end
	end
	local handle = { shutdown = opts.shutdown, replaced = replaced }
	g[key] = handle
	return handle
end

function Core.release(globalKey)
	local g = Env.global()
	g[globalKey or "__MM2HUB"] = nil
end

function Core._reset()
	table.clear(modules)
	table.clear(order)
	table.clear(startOrder)
	Core._ctx = nil
	Core.StateChanged:DisconnectAll()
	clock = os.clock
end

return Core
