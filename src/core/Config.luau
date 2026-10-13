--!nonstrict
-- core/Config: named configuration profiles + UI state persistence, export/import
-- strings with checksum, validation, migration, diff and integrity checks.
-- Files (under MM2Hub/): index.json, state.json, profiles/<name>.json.
-- Without file APIs, Env falls back to session memory (reported to the user).
-- Depends on: Settings, Env, Json, Codec, Version, Logger, Signal.

local import = ...
local Settings = import("core/Settings")
local Env = import("core/Env")
local Json = import("core/Json")
local Codec = import("core/Codec")
local Version = import("core/Version")
local Logger = import("core/Logger")
local Signal = import("core/Signal")

local Config = {}

Config.Changed = Signal.new("Config.Changed") -- (event, profileName)

local PREFIX = "MM2HUB1:"
local MAX_PROFILES = 20
local MAX_IMPORT_BYTES = 200000
local AUTOSAVE_DELAY = 2

local dirtyProfile = false
local dirtyState = false
local sinceChange = 0
local profiles = {} -- ordered list of names
local initialized = false

local function profilePath(name)
	return Env.ROOT .. "/profiles/" .. name .. ".json"
end
local INDEX = Env.ROOT .. "/index.json"
local STATE = Env.ROOT .. "/state.json"

-- Names ------------------------------------------------------------------------

function Config.validateName(name)
	if type(name) ~= "string" then
		return false, "name must be a string"
	end
	local trimmed = string.match(name, "^%s*(.-)%s*$")
	if #trimmed < 1 or #trimmed > 32 then
		return false, "name must be 1-32 characters"
	end
	if not string.match(trimmed, "^[%w _%-]+$") then
		return false, "only letters, digits, space, '_' and '-' are allowed"
	end
	return true, trimmed
end

local function indexOf(name)
	local lower = string.lower(name)
	for i, n in ipairs(profiles) do
		if string.lower(n) == lower then
			return i
		end
	end
	return nil
end

function Config.exists(name)
	return type(name) == "string" and indexOf(name) ~= nil
end

function Config.list()
	local out = table.clone(profiles)
	table.sort(out, function(a, b)
		return string.lower(a) < string.lower(b)
	end)
	return out
end

function Config.active()
	return Settings.get("state.activeProfile")
end

-- Serialisation ------------------------------------------------------------------

local function buildProfile(name, settingsMap, created)
	return {
		schema = Version.SCHEMA,
		app = Version.VERSION,
		name = name,
		created = created or os.time(),
		modified = os.time(),
		settings = settingsMap,
		checksum = Codec.fnv1a(Json.encode(settingsMap)),
	}
end

-- parseProfile(text) -> profile|nil, report. Applies structure checks, migration, checksum and per-key validation.
local function parseProfile(text)
	local report = { warnings = {}, rejected = {}, unknown = {} }
	local data, err = Json.decode(text)
	if not data then
		report.error = err
		return nil, report
	end
	if type(data) ~= "table" or type(data.settings) ~= "table" then
		report.error = "missing 'settings' table"
		return nil, report
	end
	local migrated, notes, merr = Version.migrate(data)
	if not migrated then
		report.error = merr
		return nil, report
	end
	for _, n in ipairs(notes or {}) do
		table.insert(report.warnings, n)
	end
	data = migrated
	if type(data.checksum) ~= "string" then
		report.error = "missing checksum"
		return nil, report
	end
	local actual = Codec.fnv1a(Json.encode(data.settings))
	if actual ~= data.checksum then
		report.error = string.format("checksum mismatch (stored %s, computed %s): file was edited or corrupted", data.checksum, actual)
		return nil, report
	end
	local accepted, vreport = Settings.validateMap(data.settings, "profile")
	if vreport.fatal then
		report.error = vreport.fatal
		return nil, report
	end
	report.rejected = vreport.rejected
	report.unknown = vreport.unknown
	report.missing = vreport.missing
	if type(data.name) ~= "string" then
		data.name = "Imported"
	end
	data.accepted = accepted
	return data, report
end

local function writeIndex()
	local ok, err = Env.write(INDEX, Json.encode({ schema = Version.SCHEMA, profiles = profiles }))
	if not ok then
		Logger.error("Config", "could not write index: %s", tostring(err))
	end
	return ok, err
end

local function writeProfile(name, settingsMap, created)
	local payload = buildProfile(name, settingsMap, created)
	local text, err = Json.tryEncode(payload)
	if not text then
		return false, err
	end
	return Env.write(profilePath(name), text)
end

local function readProfileFile(name)
	local text, err = Env.read(profilePath(name))
	if not text then
		return nil, { error = err or "file missing" }
	end
	return parseProfile(text)
end

-- State -------------------------------------------------------------------------

function Config.saveState()
	local map = Settings.snapshot("state")
	local text = Json.encode({ schema = Version.SCHEMA, state = map, checksum = Codec.fnv1a(Json.encode(map)) })
	dirtyState = false
	return Env.write(STATE, text)
end

local function loadState()
	local text = Env.read(STATE)
	if not text then
		return false, "no saved state"
	end
	local data, err = Json.decode(text)
	if not data or type(data.state) ~= "table" then
		Logger.warn("Config", "state file unreadable: %s", tostring(err or "bad structure"))
		return false, "state file unreadable"
	end
	if data.checksum ~= Codec.fnv1a(Json.encode(data.state)) then
		Logger.warn("Config", "state checksum mismatch; ignoring saved state")
		return false, "state checksum mismatch"
	end
	local report = Settings.applyMap(data.state, "state", "state-load", false)
	if report.fatal then
		return false, report.fatal
	end
	return true
end

-- Profile operations ----------------------------------------------------------

local function currentSettings()
	return Settings.snapshot("profile")
end

-- save(name?) -> ok, err
function Config.save(name)
	name = name or Config.active()
	local i = indexOf(name)
	if not i then
		return false, "no such profile: " .. tostring(name)
	end
	name = profiles[i]
	local ok, err = writeProfile(name, currentSettings())
	if ok then
		dirtyProfile = false
		Config.Changed:Fire("saved", name)
	end
	return ok, err
end

-- create(name, fromCurrent?) -> ok, errOrName
function Config.create(name, fromCurrent)
	local ok, clean = Config.validateName(name)
	if not ok then
		return false, clean
	end
	if indexOf(clean) then
		return false, "a profile named '" .. clean .. "' already exists"
	end
	if #profiles >= MAX_PROFILES then
		return false, "profile limit reached (" .. MAX_PROFILES .. ")"
	end
	local map
	if fromCurrent then
		map = currentSettings()
	else
		map = {}
		for _, key in ipairs(Settings.keys({ scope = "profile", includeHidden = true })) do
			map[key] = Settings.schema(key).default
		end
	end
	local wok, werr = writeProfile(clean, map)
	if not wok then
		return false, werr
	end
	table.insert(profiles, clean)
	writeIndex()
	Config.Changed:Fire("created", clean)
	return true, clean
end

-- load(name) -> ok, errOrReport. Missing keys fall back to defaults.
function Config.load(name)
	local i = indexOf(name or "")
	if not i then
		return false, "no such profile"
	end
	name = profiles[i]
	local profile, report = readProfileFile(name)
	if not profile then
		Logger.error("Config", "profile '%s' unreadable: %s", name, tostring(report.error))
		return false, report.error
	end
	local applied = Settings.applyMap(profile.accepted, "profile", "profile-load", true)
	Settings.set("state.activeProfile", name, "profile-load")
	dirtyProfile = false
	dirtyState = true
	Config.Changed:Fire("loaded", name)
	return true, { applied = applied.applied, rejected = report.rejected, unknown = report.unknown, warnings = report.warnings }
end

function Config.rename(old, new)
	local i = indexOf(old or "")
	if not i then
		return false, "no such profile"
	end
	local ok, clean = Config.validateName(new)
	if not ok then
		return false, clean
	end
	local j = indexOf(clean)
	if j and j ~= i then
		return false, "a profile named '" .. clean .. "' already exists"
	end
	local oldName = profiles[i]
	if oldName == clean then
		return true, clean
	end
	local profile = readProfileFile(oldName)
	local map = profile and profile.accepted or currentSettings()
	local wok, werr = writeProfile(clean, map, profile and profile.created)
	if not wok then
		return false, werr
	end
	Env.delete(profilePath(oldName))
	profiles[i] = clean
	writeIndex()
	if Config.active() == oldName then
		Settings.set("state.activeProfile", clean, "profile-rename")
		dirtyState = true
	end
	Config.Changed:Fire("renamed", clean)
	return true, clean
end

function Config.duplicate(src, new)
	local i = indexOf(src or "")
	if not i then
		return false, "no such profile"
	end
	local ok, clean = Config.validateName(new)
	if not ok then
		return false, clean
	end
	if indexOf(clean) then
		return false, "a profile named '" .. clean .. "' already exists"
	end
	if #profiles >= MAX_PROFILES then
		return false, "profile limit reached (" .. MAX_PROFILES .. ")"
	end
	local profile, report = readProfileFile(profiles[i])
	if not profile then
		return false, "source unreadable: " .. tostring(report.error)
	end
	local wok, werr = writeProfile(clean, profile.accepted)
	if not wok then
		return false, werr
	end
	table.insert(profiles, clean)
	writeIndex()
	Config.Changed:Fire("duplicated", clean)
	return true, clean
end

-- delete(name) -> ok, err. The UI asks for confirmation before calling this.
function Config.delete(name)
	local i = indexOf(name or "")
	if not i then
		return false, "no such profile"
	end
	if #profiles <= 1 then
		return false, "cannot delete the last profile"
	end
	local removed = table.remove(profiles, i)
	Env.delete(profilePath(removed))
	writeIndex()
	if Config.active() == removed then
		local nextName = Config.list()[1]
		Config.load(nextName)
	end
	Config.Changed:Fire("deleted", removed)
	return true
end

-- Export / import -----------------------------------------------------------------

-- exportString(name?) -> string|nil, err. nil name exports the live settings.
function Config.exportString(name)
	local payload
	if name then
		local i = indexOf(name)
		if not i then
			return nil, "no such profile"
		end
		local profile, report = readProfileFile(profiles[i])
		if not profile then
			return nil, report.error
		end
		payload = buildProfile(profiles[i], profile.accepted, profile.created)
	else
		payload = buildProfile(Config.active(), currentSettings())
	end
	local text, err = Json.tryEncode(payload)
	if not text then
		return nil, err
	end
	return PREFIX .. Codec.b64encode(text)
end

local function uniqueName(base)
	local ok, clean = Config.validateName(base)
	if not ok then
		clean = "Imported"
	end
	if not indexOf(clean) then
		return clean
	end
	local n = 2
	while indexOf(string.sub(clean, 1, 28) .. "_" .. n) do
		n += 1
	end
	return string.sub(clean, 1, 28) .. "_" .. n
end

-- importString(str, asName?) -> ok, report. Creates a new profile (does not apply it).
function Config.importString(str, asName)
	local report = { warnings = {}, rejected = {}, unknown = {} }
	if type(str) ~= "string" then
		report.error = "input is not text"
		return false, report
	end
	str = string.match(str, "^%s*(.-)%s*$")
	if #str > MAX_IMPORT_BYTES then
		report.error = "import is too large"
		return false, report
	end
	if string.sub(str, 1, #PREFIX) ~= PREFIX then
		report.error = "not an MM2 Hub export (missing '" .. PREFIX .. "' prefix)"
		return false, report
	end
	local json, derr = Codec.b64decode(string.sub(str, #PREFIX + 1))
	if not json then
		report.error = "decode failed: " .. tostring(derr)
		return false, report
	end
	local profile, preport = parseProfile(json)
	if not profile then
		return false, preport
	end
	if #profiles >= MAX_PROFILES then
		preport.error = "profile limit reached"
		return false, preport
	end
	local name = uniqueName(asName or profile.name)
	local wok, werr = writeProfile(name, profile.accepted)
	if not wok then
		preport.error = tostring(werr)
		return false, preport
	end
	table.insert(profiles, name)
	writeIndex()
	preport.name = name
	Config.Changed:Fire("imported", name)
	return true, preport
end

-- diff(a, b) -> list. Use nil for the live settings.
function Config.diff(a, b)
	local function snap(name)
		if name == nil then
			return currentSettings(), nil
		end
		local i = indexOf(name)
		if not i then
			return nil, "no such profile: " .. tostring(name)
		end
		local p, r = readProfileFile(profiles[i])
		if not p then
			return nil, "unreadable: " .. tostring(r.error)
		end
		return p.accepted, nil
	end
	local sa, ea = snap(a)
	if not sa then
		return nil, ea
	end
	local sb, eb = snap(b)
	if not sb then
		return nil, eb
	end
	return Settings.diff(sa, sb)
end

-- checkIntegrity() -> list of {name, ok, problem?}
function Config.checkIntegrity()
	local out = {}
	for _, name in ipairs(Config.list()) do
		local profile, report = readProfileFile(name)
		if not profile then
			table.insert(out, { name = name, ok = false, problem = report.error })
		elseif #report.rejected > 0 then
			table.insert(out, { name = name, ok = false, problem = #report.rejected .. " invalid value(s), first: " .. report.rejected[1].key })
		else
			table.insert(out, { name = name, ok = true })
		end
	end
	return out
end

-- Autosave -----------------------------------------------------------------------

function Config.attach(maid)
	local conn = Settings.Changed:Connect(function(key)
		local def = Settings.schema(key)
		if not def then
			return
		end
		if def.scope == "state" then
			dirtyState = true
		else
			dirtyProfile = true
		end
		sinceChange = 0
	end)
	if maid then
		maid:Give(conn)
	end
	return conn
end

-- tick(dt): debounced autosave of the active profile and UI state.
function Config.tick(dt)
	if not (dirtyProfile or dirtyState) then
		return
	end
	sinceChange += dt
	if sinceChange < AUTOSAVE_DELAY then
		return
	end
	sinceChange = 0
	if dirtyProfile then
		local ok, err = Config.save()
		if not ok then
			Logger.error("Config", "autosave failed: %s", tostring(err))
			dirtyProfile = false
		end
	end
	if dirtyState then
		local ok, err = Config.saveState()
		if not ok then
			Logger.error("Config", "state save failed: %s", tostring(err))
			dirtyState = false
		end
	end
end

function Config.flush()
	local a, b = true, true
	if dirtyProfile then
		a = Config.save()
	end
	if dirtyState then
		b = Config.saveState()
	end
	return a and b
end

function Config.isDirty()
	return dirtyProfile or dirtyState
end

-- init() -> report. Loads index/state, ensures a "Default" profile, loads the active profile.
function Config.init()
	local report = { persistent = Env.persistent(), notes = {} }
	table.clear(profiles)
	local text = Env.read(INDEX)
	if text then
		local data = Json.decode(text)
		if data and type(data.profiles) == "table" then
			for _, n in ipairs(data.profiles) do
				if type(n) == "string" and Config.validateName(n) and not indexOf(n) then
					table.insert(profiles, n)
				end
			end
		else
			table.insert(report.notes, "index.json unreadable; rebuilding")
			Logger.warn("Config", "index unreadable, rebuilding")
		end
	end
	loadState()
	if #profiles == 0 then
		local ok, err = Config.create("Default", true)
		if not ok then
			table.insert(report.notes, "could not create Default: " .. tostring(err))
		end
		Settings.set("state.activeProfile", "Default", "init")
	end
	local active = Config.active()
	if not indexOf(active) then
		active = Config.list()[1]
		Settings.set("state.activeProfile", active, "init")
	end
	local ok, res = Config.load(active)
	if not ok then
		table.insert(report.notes, "active profile '" .. tostring(active) .. "' failed to load: " .. tostring(res))
		Logger.error("Config", "active profile load failed: %s", tostring(res))
	end
	dirtyProfile, dirtyState, sinceChange = false, false, 0
	initialized = true
	report.profiles = #profiles
	report.active = active
	return report
end

function Config.isInitialized()
	return initialized
end

function Config._reset()
	table.clear(profiles)
	dirtyProfile, dirtyState, sinceChange, initialized = false, false, 0, false
	Config.Changed:DisconnectAll()
end

return Config
