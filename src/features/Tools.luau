--!nonstrict
-- features/Tools: session timer, stopwatch with laps, countdown timers, local notes.
-- Pure logic (injectable clock) so it is fully unit-testable.
-- Depends on: Signal, Settings, Env, Logger.

local import = ...
local Signal = import("core/Signal")
local Settings = import("core/Settings")
local Env = import("core/Env")
local Logger = import("core/Logger")

local Tools = {}

Tools.TimerDone = Signal.new("Tools.TimerDone") -- (id, name)
Tools.NotesSaved = Signal.new("Tools.NotesSaved")

local NOTES_PATH = Env.ROOT .. "/notes.txt"
local MAX_NOTES = 4000
local MAX_TIMERS = 8
local MAX_LAPS = 50

local clock = os.clock
local startedAt = clock()

local sw = { running = false, base = 0, startedAt = 0, laps = {} }
local timers = {}
local nextTimerId = 1
local notes = ""
local notesDirty = false
local notesIdle = 0
local NOTES_DELAY = 3

function Tools.init(clockFn)
	clock = clockFn or os.clock
	startedAt = clock()
	sw = { running = false, base = 0, startedAt = 0, laps = {} }
	table.clear(timers)
	nextTimerId = 1
	notes = ""
	notesDirty = false
	notesIdle = 0
end

-- Session ------------------------------------------------------------------

function Tools.sessionSeconds()
	return clock() - startedAt
end

function Tools.formatTime(seconds, withTenths)
	seconds = math.max(0, seconds)
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = math.floor(seconds % 60)
	local base
	if h > 0 then
		base = string.format("%d:%02d:%02d", h, m, s)
	else
		base = string.format("%02d:%02d", m, s)
	end
	if withTenths then
		base ..= string.format(".%d", math.floor((seconds % 1) * 10))
	end
	return base
end

-- Stopwatch --------------------------------------------------------------------

function Tools.stopwatchElapsed()
	if sw.running then
		return sw.base + (clock() - sw.startedAt)
	end
	return sw.base
end

function Tools.stopwatchRunning()
	return sw.running
end

function Tools.stopwatchStart()
	if not sw.running then
		sw.running = true
		sw.startedAt = clock()
	end
end

function Tools.stopwatchStop()
	if sw.running then
		sw.base = sw.base + (clock() - sw.startedAt)
		sw.running = false
	end
end

function Tools.stopwatchToggle()
	if sw.running then
		Tools.stopwatchStop()
	else
		Tools.stopwatchStart()
	end
	return sw.running
end

function Tools.stopwatchReset()
	sw = { running = false, base = 0, startedAt = 0, laps = {} }
end

-- stopwatchLap() -> lapIndex, lapTime, total | nil when stopped
function Tools.stopwatchLap()
	if not sw.running then
		return nil
	end
	local total = Tools.stopwatchElapsed()
	local previous = sw.laps[#sw.laps] and sw.laps[#sw.laps].total or 0
	table.insert(sw.laps, { total = total, split = total - previous })
	if #sw.laps > MAX_LAPS then
		table.remove(sw.laps, 1)
	end
	return #sw.laps, total - previous, total
end

function Tools.laps()
	return table.clone(sw.laps)
end

-- Timers -------------------------------------------------------------------

-- addTimer(name, seconds) -> id | nil, err
function Tools.addTimer(name, seconds)
	if type(seconds) ~= "number" or seconds ~= seconds or seconds < 1 or seconds > 86400 then
		return nil, "duration must be between 1 and 86400 seconds"
	end
	if #timers >= MAX_TIMERS then
		return nil, "timer limit reached (" .. MAX_TIMERS .. ")"
	end
	local label = type(name) == "string" and string.sub(name, 1, 24) or ""
	if label == "" then
		label = "Timer " .. nextTimerId
	end
	local t = { id = nextTimerId, name = label, total = seconds, remaining = seconds, running = true, done = false }
	nextTimerId += 1
	table.insert(timers, t)
	return t.id
end

local function find(id)
	for i, t in ipairs(timers) do
		if t.id == id then
			return t, i
		end
	end
	return nil
end

function Tools.removeTimer(id)
	local t, i = find(id)
	if t then
		table.remove(timers, i)
		return true
	end
	return false
end

function Tools.pauseTimer(id, paused)
	local t = find(id)
	if not t or t.done then
		return false
	end
	t.running = not paused
	return true
end

function Tools.timers()
	local out = {}
	for _, t in ipairs(timers) do
		table.insert(out, table.clone(t))
	end
	return out
end

-- tick(dt): advance timers and the notes autosave debounce.
function Tools.tick(dt)
	for _, t in ipairs(table.clone(timers)) do
		if t.running and not t.done then
			t.remaining -= dt
			if t.remaining <= 0 then
				t.remaining = 0
				t.running = false
				t.done = true
				Tools.TimerDone:Fire(t.id, t.name)
			end
		end
	end
	if notesDirty and Settings.has("tools.notesAutosave") and Settings.get("tools.notesAutosave") then
		notesIdle += dt
		if notesIdle >= NOTES_DELAY then
			Tools.saveNotes()
		end
	end
end

-- Notes -------------------------------------------------------------------------

function Tools.setNotes(text)
	if type(text) ~= "string" then
		return false, "notes must be text"
	end
	if #text > MAX_NOTES then
		text = string.sub(text, 1, MAX_NOTES)
	end
	if text ~= notes then
		notes = text
		notesDirty = true
		notesIdle = 0
	end
	return true
end

function Tools.getNotes()
	return notes
end

function Tools.saveNotes()
	local ok, err = Env.write(NOTES_PATH, notes)
	if ok then
		notesDirty = false
		notesIdle = 0
		Tools.NotesSaved:Fire()
	else
		Logger.error("Tools", "notes save failed: %s", tostring(err))
	end
	return ok, err
end

function Tools.loadNotes()
	local text = Env.read(NOTES_PATH)
	if type(text) == "string" then
		notes = string.sub(text, 1, MAX_NOTES)
		notesDirty = false
		return true
	end
	return false
end

function Tools.notesDirty()
	return notesDirty
end

return Tools
