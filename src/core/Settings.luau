--!nonstrict
-- core/Settings: typed, validated key/value store with change events, history,
-- resets by key/category/module, conflict rules, and snapshot import.
-- Single source of truth: UI controls, features and Config all go through here.
-- Depends on: Signal, Logger.

local import = ...
local Signal = import("core/Signal")
local Logger = import("core/Logger")

local Settings = {}

Settings.Changed = Signal.new("Settings.Changed") -- (key, newValue, oldValue, source)

local defs = {} -- key -> def
local order = {} -- keys in definition order
local values = {} -- key -> current value
local conflictRules = {}
local history = {}
local HISTORY_LIMIT = 100
local observers = {} -- key -> Signal

local VALID_TYPES = { bool = true, number = true, enum = true, color = true, key = true, string = true, strlist = true }

-- Normalisation -------------------------------------------------------------

local function clamp(n, lo, hi)
	if lo and n < lo then
		n = lo
	end
	if hi and n > hi then
		n = hi
	end
	return n
end

local function roundToStep(n, step, base)
	local k = math.floor((n - base) / step + 0.5)
	local r = base + k * step
	-- trim float noise (0.30000000000000004 -> 0.3)
	return tonumber(string.format("%.10g", r))
end

-- normalize(def, raw) -> value|nil, err|nil
local function normalize(def, raw)
	local t = def.type
	if t == "bool" then
		if type(raw) ~= "boolean" then
			return nil, "expected boolean"
		end
		return raw
	elseif t == "number" then
		if type(raw) ~= "number" or raw ~= raw or raw == math.huge or raw == -math.huge then
			return nil, "expected finite number"
		end
		local n = clamp(raw, def.min, def.max)
		if def.step and def.step > 0 then
			n = roundToStep(n, def.step, def.min or 0)
			n = clamp(n, def.min, def.max)
		end
		return n
	elseif t == "enum" then
		if type(raw) ~= "string" or not table.find(def.options, raw) then
			return nil, "expected one of: " .. table.concat(def.options, ", ")
		end
		return raw
	elseif t == "color" then
		if type(raw) ~= "table" then
			return nil, "expected {r,g,b}"
		end
		local out = {}
		for _, ch in ipairs({ "r", "g", "b" }) do
			local v = raw[ch]
			if type(v) ~= "number" or v ~= v then
				return nil, "color channel '" .. ch .. "' must be a number"
			end
			out[ch] = math.floor(clamp(v, 0, 255) + 0.5)
		end
		return out
	elseif t == "key" then
		if type(raw) ~= "string" or #raw > 24 or not string.match(raw, "^%w+$") then
			return nil, "expected key name (letters/digits), e.g. RightShift or None"
		end
		return raw
	elseif t == "string" then
		if type(raw) ~= "string" then
			return nil, "expected string"
		end
		local maxLen = def.maxLen or 64
		if #raw > maxLen then
			return nil, "string longer than " .. maxLen
		end
		return raw
	elseif t == "strlist" then
		if type(raw) ~= "table" then
			return nil, "expected list of strings"
		end
		local out, seen = {}, {}
		for i = 1, #raw do
			local item = raw[i]
			local itemMax = def.itemMax or 64
			if type(item) ~= "string" or #item > itemMax then
				return nil, "list items must be strings up to " .. itemMax .. " chars"
			end
			if not seen[item] then
				seen[item] = true
				table.insert(out, item)
			end
		end
		local maxItems = def.maxItems or 32
		if #out > maxItems then
			return nil, "list longer than " .. maxItems
		end
		return out
	end
	return nil, "unknown type"
end

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function copyValue(v)
	if type(v) == "table" then
		return table.clone(v)
	end
	return v
end

Settings.deepEqual = deepEqual

-- Definition ----------------------------------------------------------------

-- def = {key, type, default, label, desc, category, module, min,max,step, options, scope, hidden}
function Settings.define(def)
	assert(type(def) == "table", "definition must be a table")
	local key = def.key
	assert(type(key) == "string" and string.match(key, "^[%w_]+%.[%w_]+$"), "bad setting key: " .. tostring(key))
	assert(not defs[key], "duplicate setting: " .. key)
	assert(VALID_TYPES[def.type], "bad type for " .. key)
	assert(type(def.category) == "string", "category required for " .. key)
	if def.type == "enum" then
		assert(type(def.options) == "table" and #def.options > 0, "enum needs options: " .. key)
	end
	if def.type == "number" then
		assert(type(def.min) == "number" and type(def.max) == "number" and def.min <= def.max, "number needs min/max: " .. key)
	end
	local norm, err = normalize(def, def.default)
	assert(norm ~= nil, string.format("default for %s invalid: %s", key, tostring(err)))
	def.default = norm
	def.scope = def.scope or "profile"
	def.module = def.module or def.category
	def.label = def.label or key
	def.desc = def.desc or ""
	defs[key] = def
	table.insert(order, key)
	values[key] = copyValue(norm)
end

function Settings.defineAll(list)
	for _, def in ipairs(list) do
		Settings.define(def)
	end
end

function Settings.defineConflict(id, keys, check)
	assert(type(id) == "string" and type(check) == "function", "bad conflict rule")
	table.insert(conflictRules, { id = id, keys = keys, check = check })
end

function Settings.has(key)
	return defs[key] ~= nil
end

function Settings.schema(key)
	return defs[key]
end

function Settings.keys(filter)
	local out = {}
	for _, key in ipairs(order) do
		local d = defs[key]
		if
			not filter
			or ((not filter.category or d.category == filter.category)
				and (not filter.module or d.module == filter.module)
				and (not filter.scope or d.scope == filter.scope)
				and (filter.includeHidden or not d.hidden))
		then
			table.insert(out, key)
		end
	end
	return out
end

function Settings.categories()
	local out, seen = {}, {}
	for _, key in ipairs(order) do
		local d = defs[key]
		if not d.hidden and d.scope == "profile" and not seen[d.category] then
			seen[d.category] = true
			table.insert(out, d.category)
		end
	end
	return out
end

-- Access ---------------------------------------------------------------------

function Settings.get(key)
	local def = defs[key]
	if not def then
		error("unknown setting: " .. tostring(key), 2)
	end
	return values[key]
end

local function record(key, old, new, source)
	table.insert(history, { time = os.time(), key = key, old = old, new = new, source = source or "api" })
	if #history > HISTORY_LIMIT then
		table.remove(history, 1)
	end
end

-- set(key, value, source?) -> ok, normalizedValueOrError
function Settings.set(key, value, source)
	local def = defs[key]
	if not def then
		return false, "unknown setting: " .. tostring(key)
	end
	local norm, err = normalize(def, value)
	if norm == nil then
		Logger.warn("Settings", "rejected %s: %s", key, tostring(err))
		return false, err
	end
	local old = values[key]
	if deepEqual(old, norm) then
		return true, old
	end
	values[key] = norm
	record(key, old, norm, source)
	Settings.Changed:Fire(key, norm, old, source)
	local obs = observers[key]
	if obs then
		obs:Fire(norm, old, source)
	end
	return true, norm
end

-- observe(key, fn, callNow?) -> connection. fn(newValue, oldValue, source)
function Settings.observe(key, fn, callNow)
	assert(defs[key], "observe: unknown setting " .. tostring(key))
	local sig = observers[key]
	if not sig then
		sig = Signal.new("Settings.observe." .. key)
		observers[key] = sig
	end
	local conn = sig:Connect(fn)
	if callNow then
		local ok, err = pcall(fn, values[key], values[key], "init")
		if not ok then
			Logger.error("Settings", "observer for %s failed on init: %s", key, tostring(err))
		end
	end
	return conn
end

function Settings.isDefault(key)
	return deepEqual(values[key], defs[key].default)
end

function Settings.toggle(key, source)
	local def = defs[key]
	if not def or def.type ~= "bool" then
		return false, "not a boolean setting"
	end
	return Settings.set(key, not values[key], source)
end

-- Resets ---------------------------------------------------------------------

function Settings.reset(key, source)
	local def = defs[key]
	if not def then
		return false, "unknown setting"
	end
	return Settings.set(key, copyValue(def.default), source or "reset")
end

local function resetKeys(keys, source)
	local n = 0
	for _, key in ipairs(keys) do
		if not Settings.isDefault(key) then
			Settings.reset(key, source)
			n += 1
		end
	end
	return n
end

function Settings.resetCategory(category)
	return resetKeys(Settings.keys({ category = category, scope = "profile", includeHidden = true }), "reset-category")
end

function Settings.resetModule(module)
	return resetKeys(Settings.keys({ module = module, scope = "profile", includeHidden = true }), "reset-module")
end

function Settings.resetAll()
	return resetKeys(Settings.keys({ scope = "profile", includeHidden = true }), "reset-all")
end

-- Snapshots ------------------------------------------------------------------

-- snapshot(scope) -> {key = value} for the given scope ("profile" default).
function Settings.snapshot(scope)
	scope = scope or "profile"
	local out = {}
	for _, key in ipairs(order) do
		if defs[key].scope == scope then
			out[key] = copyValue(values[key])
		end
	end
	return out
end

-- validateMap(map, scope) -> accepted{key=normalized}, report{rejected={},unknown={},missing=n}
function Settings.validateMap(map, scope)
	scope = scope or "profile"
	local accepted = {}
	local report = { rejected = {}, unknown = {}, missing = 0 }
	if type(map) ~= "table" then
		report.fatal = "settings payload is not a table"
		return accepted, report
	end
	for key, raw in pairs(map) do
		local def = defs[key]
		if type(key) ~= "string" or not def or def.scope ~= scope then
			table.insert(report.unknown, tostring(key))
		else
			local norm, err = normalize(def, raw)
			if norm == nil then
				table.insert(report.rejected, { key = key, reason = err })
			else
				accepted[key] = norm
			end
		end
	end
	for _, key in ipairs(order) do
		if defs[key].scope == scope and map[key] == nil then
			report.missing += 1
		end
	end
	table.sort(report.unknown)
	table.sort(report.rejected, function(a, b)
		return a.key < b.key
	end)
	return accepted, report
end

-- applyMap(map, scope, source) -> report. Keys missing from `map` are reset to
-- defaults when opts.resetMissing is true (used when loading a whole profile).
function Settings.applyMap(map, scope, source, resetMissing)
	scope = scope or "profile"
	local accepted, report = Settings.validateMap(map, scope)
	if report.fatal then
		return report
	end
	local applied = 0
	for _, key in ipairs(order) do
		local def = defs[key]
		if def.scope == scope then
			local value = accepted[key]
			if value == nil and resetMissing and map[key] == nil then
				value = copyValue(def.default)
			end
			if value ~= nil and not deepEqual(values[key], value) then
				Settings.set(key, value, source or "import")
				applied += 1
			end
		end
	end
	report.applied = applied
	return report
end

-- diff(a, b) -> sorted list of {key, a, b} for keys whose values differ.
function Settings.diff(a, b)
	local out = {}
	for _, key in ipairs(order) do
		local va, vb = a[key], b[key]
		if va == nil then
			va = defs[key].default
		end
		if vb == nil then
			vb = defs[key].default
		end
		if not deepEqual(va, vb) then
			table.insert(out, { key = key, a = va, b = vb })
		end
	end
	return out
end

-- History / conflicts ------------------------------------------------------------

function Settings.history()
	return table.clone(history)
end

function Settings.clearHistory()
	table.clear(history)
end

-- conflicts() -> list of {id, keys, message}
function Settings.conflicts()
	local out = {}
	local function get(key)
		return values[key]
	end
	for _, rule in ipairs(conflictRules) do
		local ok, msg = pcall(rule.check, get)
		if ok and msg then
			table.insert(out, { id = rule.id, keys = rule.keys, message = msg })
		elseif not ok then
			Logger.error("Settings", "conflict rule %s failed: %s", rule.id, tostring(msg))
		end
	end
	return out
end

function Settings.activeCount()
	local n = 0
	for _, key in ipairs(order) do
		local d = defs[key]
		if d.type == "bool" and d.toggle ~= false and d.scope == "profile" and values[key] == true and d.master then
			n += 1
		end
	end
	return n
end

-- Wipes definitions: used by tests to rebuild a clean store.
function Settings._reset()
	table.clear(defs)
	table.clear(order)
	table.clear(values)
	table.clear(conflictRules)
	table.clear(history)
	table.clear(observers)
	Settings.Changed:DisconnectAll()
end

return Settings
