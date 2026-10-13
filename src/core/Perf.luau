--!nonstrict
-- core/Perf: one shared frame pump + scheduler for every periodic task, FPS/ping
-- metrics, per-task timing, long-operation detection and the low-load profile.
-- Modules call Perf.every() instead of creating their own loops.
-- Depends on: Settings, Logger, Signal.

local import = ...
local Settings = import("core/Settings")
local Logger = import("core/Logger")
local Signal = import("core/Signal")

local Perf = {}

Perf.LowChanged = Signal.new("Perf.LowChanged") -- (isLow)
Perf.TaskFailed = Signal.new("Perf.TaskFailed") -- (name, err)

local MAX_CONSECUTIVE_ERRORS = 5

local tasks = {}
local longOps = {}
local fps = 60
local frames = 0
local clock = os.clock
local autoLowEngaged = false
local lowSeconds = 0
local sources = { ping = nil }

local function setting(key, fallback)
	if Settings.has(key) then
		return Settings.get(key)
	end
	return fallback
end

function Perf.setClock(fn)
	clock = fn or os.clock
end

function Perf.setSources(s)
	sources = s or {}
end

-- Low profile ---------------------------------------------------------------

function Perf.isLow()
	return setting("perf.lowProfile", false) or autoLowEngaged
end

local lastLow = nil
local function notifyLow()
	local low = Perf.isLow()
	if low ~= lastLow then
		lastLow = low
		Perf.LowChanged:Fire(low)
	end
end

function Perf.effectiveHz(hz, visual)
	local eff = hz
	if visual then
		eff = math.min(eff, setting("perf.visualHz", 30))
	end
	if Perf.isLow() then
		eff = eff * 0.5
	end
	return math.max(eff, 0.25)
end

-- Scheduler --------------------------------------------------------------------

-- every(name, hz, fn, opts{visual=bool}) -> handle with Cancel()/IsActive()
function Perf.every(name, hz, fn, opts)
	assert(type(name) == "string" and type(fn) == "function", "bad task")
	assert(type(hz) == "number" and hz > 0, "hz must be positive")
	assert(not tasks[name], "duplicate task: " .. name)
	local task = {
		name = name,
		hz = hz,
		fn = fn,
		visual = opts and opts.visual or false,
		acc = 0,
		calls = 0,
		totalMs = 0,
		maxMs = 0,
		lastMs = 0,
		errors = 0,
		consecutive = 0,
		disabled = false,
		lastError = nil,
	}
	tasks[name] = task
	return {
		Cancel = function()
			if tasks[name] == task then
				tasks[name] = nil
			end
		end,
		IsActive = function()
			return tasks[name] == task and not task.disabled
		end,
		Name = name,
	}
end

function Perf.cancel(name)
	tasks[name] = nil
end

function Perf.reenable(name)
	local t = tasks[name]
	if t then
		t.disabled = false
		t.consecutive = 0
		return true
	end
	return false
end

local function runTask(task, dt)
	local t0 = clock()
	local ok, err = pcall(task.fn, dt)
	local ms = (clock() - t0) * 1000
	task.calls += 1
	task.totalMs += ms
	task.lastMs = ms
	if ms > task.maxMs then
		task.maxMs = ms
	end
	if not ok then
		task.errors += 1
		task.consecutive += 1
		task.lastError = tostring(err)
		Logger.error("Perf", "task '%s' error: %s", task.name, tostring(err))
		if task.consecutive >= MAX_CONSECUTIVE_ERRORS then
			task.disabled = true
			Logger.error("Perf", "task '%s' disabled after %d consecutive errors", task.name, task.consecutive)
			Perf.TaskFailed:Fire(task.name, tostring(err))
		end
	else
		task.consecutive = 0
	end
	local warnMs = setting("perf.warnMs", 8)
	if ms > warnMs then
		Logger.warn("Perf", "long operation: '%s' took %.2f ms", task.name, ms)
		table.insert(longOps, { name = task.name, ms = ms, time = os.time() })
		if #longOps > 30 then
			table.remove(longOps, 1)
		end
	end
end

-- frame(dt): the only per-frame entry point. Called from a single RenderStepped/Heartbeat.
function Perf.frame(dt)
	if dt <= 0 then
		return
	end
	frames += 1
	local inst = 1 / dt
	fps = fps + (inst - fps) * math.min(1, dt * 4) -- ~250 ms smoothing

	-- auto low profile
	if setting("perf.autoLow", false) and not setting("perf.lowProfile", false) then
		if fps < setting("perf.autoLowFps", 25) then
			lowSeconds += dt
			if lowSeconds >= 5 and not autoLowEngaged then
				autoLowEngaged = true
				Logger.warn("Perf", "auto low profile engaged at %.0f FPS", fps)
			end
		else
			lowSeconds = 0
			if autoLowEngaged and fps > setting("perf.autoLowFps", 25) + 15 then
				autoLowEngaged = false
				Logger.info("Perf", "auto low profile released")
			end
		end
	elseif autoLowEngaged then
		autoLowEngaged = false
	end
	notifyLow()

	-- snapshot names so tasks may cancel/register during the pump
	local list = {}
	for _, task in pairs(tasks) do
		table.insert(list, task)
	end
	for _, task in ipairs(list) do
		if not task.disabled and tasks[task.name] == task then
			task.acc += dt
			local interval = 1 / Perf.effectiveHz(task.hz, task.visual)
			if task.acc >= interval then
				local elapsed = task.acc
				task.acc = task.acc % interval
				runTask(task, elapsed)
			end
		end
	end
end

-- Metrics ---------------------------------------------------------------------

function Perf.fps()
	return fps
end

function Perf.ping()
	if sources.ping then
		local ok, v = pcall(sources.ping)
		if ok and type(v) == "number" then
			return v
		end
	end
	return nil
end

function Perf.timings()
	local out = {}
	for _, t in pairs(tasks) do
		table.insert(out, {
			name = t.name,
			hz = t.hz,
			calls = t.calls,
			avgMs = t.calls > 0 and t.totalMs / t.calls or 0,
			maxMs = t.maxMs,
			lastMs = t.lastMs,
			errors = t.errors,
			disabled = t.disabled,
			visual = t.visual,
		})
	end
	table.sort(out, function(a, b)
		if a.avgMs ~= b.avgMs then
			return a.avgMs > b.avgMs
		end
		return a.name < b.name
	end)
	return out
end

function Perf.taskCount()
	local n = 0
	for _ in pairs(tasks) do
		n += 1
	end
	return n
end

function Perf.longOps()
	return table.clone(longOps)
end

function Perf.frames()
	return frames
end

function Perf._reset()
	table.clear(tasks)
	table.clear(longOps)
	fps = 60
	frames = 0
	autoLowEngaged = false
	lowSeconds = 0
	lastLow = nil
	clock = os.clock
	sources = {}
	Perf.LowChanged:DisconnectAll()
	Perf.TaskFailed:DisconnectAll()
end

return Perf
