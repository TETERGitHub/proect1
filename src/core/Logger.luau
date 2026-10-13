--!nonstrict
-- core/Logger: structured ring-buffer log. Entries are {id, time, clock, level, tag, message}.
-- Depends on: Signal.

local import = ...
local Signal = import("core/Signal")

local Logger = {}

local LEVELS = { debug = 1, info = 2, warn = 3, error = 4 }
local CAPACITY = 500

local entries = {}
local nextId = 1
local minLevel = 1
local clock = os.clock
local counts = { debug = 0, info = 0, warn = 0, error = 0 }

Logger.onEntry = Signal.new("Logger.onEntry")
Logger.LEVELS = LEVELS
Logger.CAPACITY = CAPACITY

function Logger.setClock(fn)
	assert(type(fn) == "function", "clock must be a function")
	clock = fn
end

function Logger.setMinLevel(level)
	assert(LEVELS[level], "unknown log level: " .. tostring(level))
	minLevel = LEVELS[level]
end

local function format(message, ...)
	if select("#", ...) == 0 then
		return tostring(message)
	end
	local ok, text = pcall(string.format, tostring(message), ...)
	if ok then
		return text
	end
	return tostring(message) .. " (format error)"
end

-- Logger.log(level, tag, message, ...) -> entry|nil
function Logger.log(level, tag, message, ...)
	local lv = LEVELS[level]
	if not lv then
		level = "info"
		lv = LEVELS.info
	end
	counts[level] += 1
	if lv < minLevel then
		return nil
	end
	local entry = {
		id = nextId,
		time = os.time(),
		clock = clock(),
		level = level,
		tag = tostring(tag),
		message = format(message, ...),
	}
	nextId += 1
	table.insert(entries, entry)
	if #entries > CAPACITY then
		table.remove(entries, 1)
	end
	Logger.onEntry:Fire(entry)
	return entry
end

function Logger.debug(tag, message, ...)
	return Logger.log("debug", tag, message, ...)
end
function Logger.info(tag, message, ...)
	return Logger.log("info", tag, message, ...)
end
function Logger.warn(tag, message, ...)
	return Logger.log("warn", tag, message, ...)
end
function Logger.error(tag, message, ...)
	return Logger.log("error", tag, message, ...)
end

-- Logger.entries(filter?) -> copy. filter = {level = "warn"} keeps >= level, {tag = "x"} exact tag.
function Logger.entries(filter)
	local out = {}
	local minLv = filter and filter.level and LEVELS[filter.level] or 1
	for _, e in ipairs(entries) do
		if LEVELS[e.level] >= minLv and (not filter or not filter.tag or e.tag == filter.tag) then
			table.insert(out, e)
		end
	end
	return out
end

function Logger.count(level)
	return counts[level] or 0
end

function Logger.clear()
	table.clear(entries)
	for k in pairs(counts) do
		counts[k] = 0
	end
end

function Logger.formatEntry(e)
	return string.format("[%8.2f] %-5s %-12s %s", e.clock, string.upper(e.level), e.tag, e.message)
end

-- Logger.dump(n?) -> text of the last n entries (default all).
function Logger.dump(n)
	local list = Logger.entries()
	local start = 1
	if n and #list > n then
		start = #list - n + 1
	end
	local lines = {}
	for i = start, #list do
		table.insert(lines, Logger.formatEntry(list[i]))
	end
	return table.concat(lines, "\n")
end

-- Test helper: reset everything including the id counter.
function Logger.reset()
	Logger.clear()
	nextId = 1
	minLevel = 1
	clock = os.clock
end

return Logger
