--!nonstrict
-- core/Notify: notification queue with timers. Pure logic (no GUI): the UI layer
-- listens to Shown/Expired/Dismissed and renders pooled cards.
-- Depends on: Signal, Settings.

local import = ...
local Signal = import("core/Signal")
local Settings = import("core/Settings")

local Notify = {}

Notify.Shown = Signal.new("Notify.Shown")
Notify.Expired = Signal.new("Notify.Expired")
Notify.Dismissed = Signal.new("Notify.Dismissed")

local LEVELS = { info = true, success = true, warn = true, error = true }
local active = {}
local queue = {}
local nextId = 1
local history = {}

local function maxVisible()
	local limit = 4
	if Settings.has("perf.maxDecor") then
		limit = math.max(1, math.min(limit, Settings.get("perf.maxDecor")))
	end
	return limit
end

local function enabled()
	return not Settings.has("ui.notifications") or Settings.get("ui.notifications")
end

local function show(item)
	item.remaining = item.duration
	table.insert(active, item)
	Notify.Shown:Fire(item)
end

local function promote()
	while #queue > 0 and #active < maxVisible() do
		show(table.remove(queue, 1))
	end
end

-- push{title, text, level?, duration?, force?} -> id|nil (nil when notifications are off)
function Notify.push(opts)
	assert(type(opts) == "table", "notification options required")
	local level = LEVELS[opts.level] and opts.level or "info"
	local item = {
		id = nextId,
		title = tostring(opts.title or ""),
		text = tostring(opts.text or ""),
		level = level,
	}
	nextId += 1
	local duration = opts.duration
	if type(duration) ~= "number" then
		duration = Settings.has("ui.notifyDuration") and Settings.get("ui.notifyDuration") or 4
	end
	item.duration = math.max(0.5, duration)
	table.insert(history, item)
	if #history > 50 then
		table.remove(history, 1)
	end
	-- errors are never swallowed by the "notifications off" switch
	if not enabled() and level ~= "error" and not opts.force then
		return nil
	end
	if #active < maxVisible() then
		show(item)
	else
		table.insert(queue, item)
	end
	return item.id
end

-- tick(dt): advance timers, expire finished toasts, promote queued ones.
function Notify.tick(dt)
	local i = 1
	while i <= #active do
		local item = active[i]
		item.remaining -= dt
		if item.remaining <= 0 then
			table.remove(active, i)
			Notify.Expired:Fire(item)
		else
			i += 1
		end
	end
	promote()
end

function Notify.dismiss(id)
	for i, item in ipairs(active) do
		if item.id == id then
			table.remove(active, i)
			Notify.Dismissed:Fire(item)
			promote()
			return true
		end
	end
	for i, item in ipairs(queue) do
		if item.id == id then
			table.remove(queue, i)
			return true
		end
	end
	return false
end

function Notify.active()
	return table.clone(active)
end

function Notify.queued()
	return #queue
end

function Notify.history()
	return table.clone(history)
end

function Notify.clear()
	for _, item in ipairs(table.clone(active)) do
		Notify.dismiss(item.id)
	end
	table.clear(queue)
end

function Notify._reset()
	table.clear(active)
	table.clear(queue)
	table.clear(history)
	nextId = 1
	Notify.Shown:DisconnectAll()
	Notify.Expired:DisconnectAll()
	Notify.Dismissed:DisconnectAll()
end

return Notify
