--!nonstrict
-- tests/Framework: tiny test harness producing the results table for docs/TESTING.md.
-- A test passes when its function returns without error; the returned string (if any)
-- is recorded as the actual result, otherwise "as expected".

local import = ...

local T = {}

local cases = {}
local currentSuite = "?"

function T.suite(name)
	currentSuite = name
end

-- T.test(name, expected, fn)
function T.test(name, expected, fn)
	table.insert(cases, { module = currentSuite, name = name, expected = expected, fn = fn })
end

function T.eq(a, b, msg)
	if a ~= b then
		error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
	end
end

function T.deepEq(a, b, msg)
	local Settings = import("core/Settings")
	if not Settings.deepEqual(a, b) then
		error((msg or "deepEq") .. ": tables differ", 2)
	end
end

function T.truthy(v, msg)
	if not v then
		error(msg or "expected truthy value", 2)
	end
end

function T.falsy(v, msg)
	if v then
		error(msg or "expected falsy value", 2)
	end
end

function T.throws(fn, pattern, msg)
	local ok, err = pcall(fn)
	if ok then
		error((msg or "throws") .. ": expected an error", 2)
	end
	if pattern and not string.find(tostring(err), pattern, 1, true) then
		error(string.format("%s: error '%s' lacks '%s'", msg or "throws", tostring(err), pattern), 2)
	end
end

-- Resets every singleton module to a clean state with the real schema loaded.
function T.fresh(opts)
	opts = opts or {}
	local Settings = import("core/Settings")
	local Actions = import("core/Actions")
	local Input = import("core/Input")
	local Config = import("core/Config")
	local Env = import("core/Env")
	local Logger = import("core/Logger")
	local Perf = import("core/Perf")
	local Notify = import("core/Notify")
	local Core = import("core/Core")
	local Search = import("core/Search")
	local Schema = import("data/Schema")
	local Version = import("core/Version")
	Settings._reset()
	Actions._reset()
	Input._reset()
	Config._reset()
	Perf._reset()
	Notify._reset()
	Core._reset()
	Search.invalidate()
	Logger.reset()
	Env.setLookup(opts.lookup)
	Env.setForceMemory(opts.lookup == nil)
	Env.resetMemory()
	Version.clearMigrations()
	Settings.defineAll(Schema.settings)
	for _, c in ipairs(Schema.conflicts) do
		Settings.defineConflict(c.id, c.keys, c.check)
	end
end

function T.runAll()
	local rows = {}
	local passed, failed = 0, 0
	for _, c in ipairs(cases) do
		local ok, res = xpcall(c.fn, function(e)
			return tostring(e)
		end)
		local row = { module = c.module, name = c.name, expected = c.expected }
		if ok then
			row.actual = type(res) == "string" and res or "as expected"
			row.status = "PASS"
			passed += 1
		else
			row.actual = string.gsub(res, "\n.*", "")
			row.status = "FAIL"
			failed += 1
		end
		table.insert(rows, row)
	end
	return rows, passed, failed
end

function T.count()
	return #cases
end

return T
