--!nonstrict
-- features/KillSounds: two independent kill sounds, one per role. Murderer and Sheriff never share a setting, a list, a
-- preview player or an Apply/Reset: every function takes the role and touches only ksound.<role>* keys.
--   library  the sounds YOU added for that role (name, source, category). Nothing is bundled and no sound id is invented.
--   pick     the list entry that is selected (what Preview plays)
--   source   the applied sound (what a confirmed kill plays)
-- Sources are asset:<id> or file:<name> (MM2Hub/sounds/), exactly like the other sound slots. Playback is local only.
-- Depends on: Settings, Json, Sources, Sounds, Env, Services, Logger, KillEvents.

local import = ...
local Settings = import("core/Settings")
local Json = import("core/Json")
local Sources = import("features/Sources")
local Sounds = import("features/Sounds")
local Services = import("core/Services")
local Logger = import("core/Logger")
local KillEvents = import("features/KillEvents")
local Pack = import("features/SoundPack")

local KS = {}

KS.ROLES = { "murderer", "sheriff" }
KS.MAX_ENTRIES = 30
local ROLE_OK = { murderer = true, sheriff = true }

local state = nil
local previews = { murderer = nil, sheriff = nil } -- role -> { sound, token }
local durations = {} -- source -> seconds (only when a sound really loaded)
local token = 0

local function key(role, field)
	return "ksound." .. role .. string.upper(string.sub(field, 1, 1)) .. string.sub(field, 2)
end
KS.key = key

local function checkRole(role)
	assert(ROLE_OK[role], "unknown kill-sound role: " .. tostring(role))
end

-- Library -----------------------------------------------------------------------------------------------------------------------

local function cleanText(s, max)
	if type(s) ~= "string" then
		return nil
	end
	local t = string.match(s, "^%s*(.-)%s*$")
	if t == "" or #t > max or string.find(t, "%c") then
		return nil
	end
	return t
end

-- userLibrary(role) -> the entries YOU added: list of { name, source, category }; unreadable or invalid entries are dropped
function KS.userLibrary(role)
	checkRole(role)
	local text = Settings.get(key(role, "library"))
	if text == "" then
		return {}
	end
	local raw = Json.decode(text)
	local out = {}
	if type(raw) == "table" and type(raw.list) == "table" then
		for _, e in ipairs(raw.list) do
			if type(e) == "table" and #out < KS.MAX_ENTRIES then
				local name, src = cleanText(e.n, 24), cleanText(e.s, 120)
				if name and src and Sources.parse(src, "audio") then
					table.insert(out, { name = name, source = src, category = cleanText(e.c, 16) or "Custom" })
				end
			end
		end
	end
	return out
end

-- library(role) -> the owner's bundled sounds (builtin = true, measured duration) followed by the entries you added for this role
function KS.library(role)
	checkRole(role)
	local out = {}
	for _, b in ipairs(Pack.list()) do
		table.insert(out, { name = b.name, ru = b.ru, source = b.source, category = b.category, builtin = true, duration = b.duration })
	end
	for _, e in ipairs(KS.userLibrary(role)) do
		table.insert(out, e)
	end
	return out
end

local function writeLibrary(role, list)
	local arr = {}
	for _, e in ipairs(list) do
		table.insert(arr, { n = e.name, s = e.source, c = e.category })
	end
	return Settings.set(key(role, "library"), Json.encode({ v = 1, list = Json.array(arr) }), "ksound")
end

-- addSound(role, name, source, category?) -> true | false, err
function KS.addSound(role, name, source, category)
	checkRole(role)
	local n = cleanText(name, 24)
	if not n then
		return false, "give the sound a name (1-24 characters)"
	end
	local src = cleanText(source, 120)
	if not src then
		return false, "source is empty or too long"
	end
	local parsed, err = Sources.parse(src, "audio")
	if not parsed or parsed.type == "proc" then
		return false, err or "use asset:<id> or file:<name>"
	end
	local list = KS.userLibrary(role)
	if #list >= KS.MAX_ENTRIES then
		return false, "the list is full (" .. KS.MAX_ENTRIES .. ")"
	end
	for _, e in ipairs(KS.library(role)) do
		if string.lower(e.name) == string.lower(n) then
			return false, "a sound named '" .. n .. "' is already in this list"
		end
	end
	table.insert(list, { name = n, source = src, category = cleanText(category or "", 16) or "Custom" })
	return writeLibrary(role, list)
end

function KS.removeSound(role, index)
	checkRole(role)
	local all = KS.library(role)
	local e = all[index]
	if not e then
		return false, "no such entry"
	end
	if e.builtin then
		return false, "bundled sounds cannot be removed"
	end
	local list = KS.userLibrary(role)
	for i, u in ipairs(list) do
		if u.source == e.source and u.name == e.name then
			table.remove(list, i)
			break
		end
	end
	local ok, err = writeLibrary(role, list)
	-- a removed sound can no longer be the selection; the applied one stays until Apply or Reset (it is a copy)
	if Settings.get(key(role, "pick")) == e.source then
		Settings.set(key(role, "pick"), "", "ksound")
	end
	return ok, err
end

-- pick(role, source): selects a list entry (does not change what is applied)
function KS.pick(role, source)
	checkRole(role)
	for _, e in ipairs(KS.library(role)) do
		if e.source == source then
			return Settings.set(key(role, "pick"), source, "ksound")
		end
	end
	return false, "that sound is not in this list"
end

-- apply(role) -> true | false, err: the selection becomes the sound played on a confirmed kill (and the role is switched on)
function KS.apply(role)
	checkRole(role)
	local pick = Settings.get(key(role, "pick"))
	if pick == "" then
		return false, "select a sound first"
	end
	local ok, err = Settings.set(key(role, "source"), pick, "ksound")
	if not ok then
		return false, err
	end
	Settings.set(key(role, "enabled"), true, "ksound")
	return true
end

-- reset(role): this role only. Switch off, clear selection and applied sound, volume back to default. The list is kept.
function KS.reset(role)
	checkRole(role)
	KS.stopPreview(role)
	for _, f in ipairs({ "enabled", "pick", "source", "volume" }) do
		Settings.reset(key(role, f), "ksound")
	end
end

-- Playback ----------------------------------------------------------------------------------------------------------------------

local function resolve(source)
	local parsed, err = Sources.parse(source, "audio")
	if not parsed then
		return nil, err
	end
	if parsed.type == "file" and Pack.has(parsed.ref) then
		local ok, perr = Pack.ensure(parsed.ref)
		if not ok then
			return nil, perr
		end
	end
	return Sounds.resolveParsed(parsed, "sounds")
end

local function destroySound(snd)
	if snd then
		pcall(function()
			snd:Stop()
			snd:Destroy()
		end)
	end
end

function KS.stopPreview(role)
	checkRole(role)
	local p = previews[role]
	if p then
		previews[role] = nil
		destroySound(p.sound)
	end
end

function KS.isPreviewing(role)
	checkRole(role)
	return previews[role] ~= nil
end

function KS.duration(source)
	local b = Pack.fromSource(source)
	return b and b.duration or durations[source]
end

-- preview(role, cb) -> true | false, err. Plays the SELECTED entry (or the applied one if nothing is selected) at this role's
-- volume. A previous preview of the same role is stopped first. cb(ok, message, seconds?) is called when loading finished.
function KS.preview(role, cb)
	checkRole(role)
	local source = Settings.get(key(role, "pick"))
	if source == "" then
		source = Settings.get(key(role, "source"))
	end
	if source == "" then
		return false, "select a sound first"
	end
	local id, err = resolve(source)
	if not id then
		return false, err or "cannot resolve the sound"
	end
	KS.stopPreview(role)
	local ok, snd = pcall(function()
		local s = Instance.new("Sound")
		s.Name = "MM2Hub_KillPreview_" .. role
		s.SoundId = id
		s.Volume = Settings.get(key(role, "volume"))
		s.Parent = Services.SoundService
		return s
	end)
	if not ok then
		return false, "could not create the sound: " .. tostring(snd)
	end
	token += 1
	local mine = token
	previews[role] = { sound = snd, token = mine }
	task.spawn(function()
		-- wait until the audio is available; a refused/unknown asset is reported instead of failing silently
		local loaded = pcall(function()
			game:GetService("ContentProvider"):PreloadAsync({ snd })
		end)
		local p = previews[role]
		if not p or p.token ~= mine then
			return -- stopped or replaced meanwhile
		end
		if snd.IsLoaded == false then
			previews[role] = nil
			destroySound(snd)
			Logger.warn("KillSounds", "%s preview: '%s' did not load", role, source)
			if cb then
				cb(false, "the sound did not load (wrong id, no permission or file missing)")
			end
			return
		end
		local len = tonumber(snd.TimeLength)
		if len and len > 0 then
			durations[source] = len
		end
		snd.Ended:Once(function()
			if previews[role] and previews[role].token == mine then
				previews[role] = nil
			end
			destroySound(snd)
		end)
		snd:Play()
		if cb then
			cb(true, "playing", durations[source])
		end
	end)
	return true
end

-- playEvent(role) -> true when a sound was started. Honors this role's own switch and volume only.
function KS.playEvent(role)
	checkRole(role)
	if not Settings.get(key(role, "enabled")) then
		return false
	end
	local source = Settings.get(key(role, "source"))
	if source == "" then
		return false
	end
	local id, err = resolve(source)
	if not id then
		Logger.warn("KillSounds", "%s: %s", role, tostring(err))
		return false
	end
	KS.stopPreview(role) -- a real event never overlaps this role's preview
	local ok = pcall(function()
		local s = Instance.new("Sound")
		s.Name = "MM2Hub_KillSound_" .. role
		s.SoundId = id
		s.Volume = Settings.get(key(role, "volume"))
		s.Parent = Services.SoundService
		s.Ended:Once(function()
			s:Destroy()
		end)
		Services.Debris:AddItem(s, 15)
		s:Play()
	end)
	return ok
end

function KS.start(ctx)
	assert(state == nil, "KillSounds already started")
	state = { played = 0 }
	ctx.maid:Give(KillEvents.Confirmed:Connect(function(ev)
		if state and KS.playEvent(ev.role) then
			state.played += 1
		end
	end))
	ctx.maid:Give(function()
		for _, role in ipairs(KS.ROLES) do
			KS.stopPreview(role)
		end
		state = nil
	end)
end

function KS.playedCount()
	return state and state.played or 0
end

return KS
