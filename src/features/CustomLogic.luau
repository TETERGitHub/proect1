--!nonstrict
-- features/CustomLogic: the data side of the Custom gun / knife / character systems. No Roblox objects are created here.
--   draft      = the plain custom.<kind>* settings the page edits and the preview shows
--   applied    = a validated snapshot (custom.<kind>Applied) that features/Cosmetics draws on your own tools / avatar
--   presets    = named snapshots (custom.<kind>Presets); each kind keeps its own list, so gun, knife and character
--                presets can never overwrite one another
-- Everything read back from settings or a preset is re-validated (unknown models dropped, colours clamped, materials
-- whitelisted); the stored text is plain JSON data, never code. Nothing here touches damage, speed or hitboxes.
-- Depends on: Settings, Json, ModelLib.

local import = ...
local Settings = import("core/Settings")
local Json = import("core/Json")
local Lib = import("data/ModelLib")
local Meshes = import("features/MeshModels")

local L = {}

L.KINDS = { "gun", "knife", "char" }
L.MAX_PRESETS = 20
L.CHAR_SLOTS = { "costume", "head", "back", "aura" }
local COLOR_FIELDS = { "primary", "secondary", "grip", "detail", "glow" }

local function cap(s)
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

-- key(kind, field) -> setting key, e.g. key("gun", "primary") = "custom.gunPrimary"
function L.key(kind, field)
	return "custom." .. kind .. cap(field)
end

local function validKind(kind)
	return kind == "gun" or kind == "knife" or kind == "char"
end

local function clampByte(v)
	v = tonumber(v)
	if not v or v ~= v then
		return nil
	end
	return math.clamp(math.floor(v + 0.5), 0, 255)
end

local function cleanColor(c)
	if type(c) ~= "table" then
		return nil
	end
	local r, g, b
	if c.r ~= nil then
		r, g, b = clampByte(c.r), clampByte(c.g), clampByte(c.b)
	else
		r, g, b = clampByte(c[1]), clampByte(c[2]), clampByte(c[3])
	end
	if not (r and g and b) then
		return nil
	end
	return { r, g, b }
end

local MATERIAL_OK = {}
for _, m in ipairs(Lib.MATERIALS) do
	MATERIAL_OK[m] = true
end

-- Draft access ---------------------------------------------------------------------------------------------------------------

-- readLook(kind) -> look ({r,g,b} arrays etc.) from the draft settings
function L.readLook(kind)
	local look = {}
	for _, f in ipairs(COLOR_FIELDS) do
		local c = Settings.get(L.key(kind, f))
		look[f] = { c.r, c.g, c.b }
	end
	look.material = Settings.get(L.key(kind, "material"))
	look.glowAmount = Settings.get(L.key(kind, "glowAmount"))
	look.decor = Settings.get(L.key(kind, "decor"))
	look.effects = Settings.get(L.key(kind, "effects"))
	return look
end

function L.writeLook(kind, look)
	for _, f in ipairs(COLOR_FIELDS) do
		local c = look[f] and cleanColor(look[f])
		if c then
			Settings.set(L.key(kind, f), { r = c[1], g = c[2], b = c[3] }, "custom")
		end
	end
	if look.material and MATERIAL_OK[look.material] then
		Settings.set(L.key(kind, "material"), look.material, "custom")
	end
	if look.glowAmount ~= nil then
		Settings.set(L.key(kind, "glowAmount"), look.glowAmount, "custom")
	end
	if look.decor ~= nil then
		Settings.set(L.key(kind, "decor"), look.decor, "custom")
	end
	if look.effects ~= nil then
		Settings.set(L.key(kind, "effects"), look.effects and true or false, "custom")
	end
end

-- readSelection(kind) -> { model = id } for gun/knife, { costume, head, back, aura } for char (ids, "" = none)
function L.readSelection(kind)
	if kind == "char" then
		local sel = {}
		for _, slot in ipairs(L.CHAR_SLOTS) do
			sel[slot] = Settings.get(L.key("char", slot))
		end
		return sel
	end
	return { model = Settings.get(L.key(kind, "model")) }
end

function L.writeSelection(kind, sel)
	if kind == "char" then
		for _, slot in ipairs(L.CHAR_SLOTS) do
			if sel[slot] ~= nil then
				Settings.set(L.key("char", slot), sel[slot], "custom")
			end
		end
	elseif sel.model then
		Settings.set(L.key(kind, "model"), sel.model, "custom")
	end
end

-- Validation ---------------------------------------------------------------------------------------------------------------

-- normalizeLook(kind, raw) -> a complete, safe look (missing or bad fields fall back to the base look)
function L.normalizeLook(kind, raw)
	local base = Lib.baseLook(kind)
	raw = type(raw) == "table" and raw or {}
	local out = {}
	for _, f in ipairs(COLOR_FIELDS) do
		out[f] = cleanColor(raw[f]) or base[f]
	end
	out.material = MATERIAL_OK[raw.material] and raw.material or base.material
	out.glowAmount = math.clamp(tonumber(raw.glowAmount) or base.glowAmount, 0, 1)
	out.decor = math.clamp(tonumber(raw.decor) or 0, 0, 0.6)
	out.effects = raw.effects ~= false
	return out
end

-- modelInfo(kind, id) -> info for a built-in shape ("revolver") or an imported mesh ("import:awp"), else nil
function L.modelInfo(kind, id)
	if type(id) ~= "string" then
		return nil
	end
	local name = string.match(id, "^import:([%w_]+)$")
	if name then
		local e = Meshes.info(kind, name)
		if e then
			return { id = id, name = e.name, category = "Import", group = e.group, slot = e.slot, imported = true, partCount = #e.parts, tris = e.tris }
		end
		return nil
	end
	if Lib.has(kind, id) then
		return Lib.info(kind, id)
	end
	return nil
end

local function cleanModel(kind, id, slot)
	if type(id) ~= "string" or id == "" then
		return ""
	end
	local info = L.modelInfo(kind, id)
	if not info then
		return ""
	end
	if kind == "char" then
		if slot == "costume" then
			return info.group == "costume" and id or ""
		end
		return (info.group == "accessory" and info.slot == slot) and id or ""
	end
	return id
end

-- normalize(kind, raw) -> snapshot | nil, err. snapshot = { sel = {...}, look = {...} }
function L.normalize(kind, raw)
	if not validKind(kind) then
		return nil, "unknown kind"
	end
	if type(raw) ~= "table" then
		return nil, "not a table"
	end
	local sel = {}
	local rs = type(raw.sel) == "table" and raw.sel or {}
	if kind == "char" then
		local any = false
		for _, slot in ipairs(L.CHAR_SLOTS) do
			sel[slot] = cleanModel(kind, rs[slot], slot)
			any = any or sel[slot] ~= ""
		end
		if not any then
			return nil, "nothing selected"
		end
	else
		sel.model = cleanModel(kind, rs.model)
		if sel.model == "" then
			return nil, "unknown model"
		end
	end
	return { sel = sel, look = L.normalizeLook(kind, raw.look) }
end

-- Snapshots ------------------------------------------------------------------------------------------------------------------

-- snapshot(kind) -> normalized snapshot of the current draft, or nil, err when nothing is selected
function L.snapshot(kind)
	return L.normalize(kind, { sel = L.readSelection(kind), look = L.readLook(kind) })
end

local function encodeSnapshot(s)
	local look = {}
	for _, f in ipairs(COLOR_FIELDS) do
		look[f] = s.look[f]
	end
	look.material, look.glowAmount, look.decor, look.effects = s.look.material, s.look.glowAmount, s.look.decor, s.look.effects
	return Json.encode({ v = 1, sel = s.sel, look = look })
end
L.encodeSnapshot = encodeSnapshot

local function decodeSnapshot(kind, text)
	if type(text) ~= "string" or text == "" then
		return nil, "empty"
	end
	local raw, err = Json.decode(text)
	if type(raw) ~= "table" then
		return nil, err or "not an object"
	end
	return L.normalize(kind, raw)
end
L.decodeSnapshot = decodeSnapshot

-- applied(kind) -> snapshot | nil. The setting is only trusted after validation.
function L.applied(kind)
	if not Settings.get(L.key(kind, "enabled")) then
		return nil
	end
	local snap = decodeSnapshot(kind, Settings.get(L.key(kind, "applied")))
	return snap
end

-- apply(kind) -> true | false, err. Copies the draft into the applied snapshot and turns the look on.
function L.apply(kind)
	local snap, err = L.snapshot(kind)
	if not snap then
		return false, err
	end
	local text = encodeSnapshot(snap)
	local ok, serr = Settings.set(L.key(kind, "applied"), text, "custom")
	if not ok then
		return false, serr
	end
	Settings.set(L.key(kind, "enabled"), true, "custom")
	return true
end

-- reset(kind): hides the look and returns this kind's draft to its defaults. Other kinds and the saved presets stay.
function L.reset(kind)
	Settings.set(L.key(kind, "enabled"), false, "custom")
	Settings.reset(L.key(kind, "applied"), "custom")
	local fields = { "style", "primary", "secondary", "grip", "detail", "glow", "material", "glowAmount", "decor", "effects" }
	if kind == "char" then
		for _, s in ipairs(L.CHAR_SLOTS) do
			table.insert(fields, s)
		end
	else
		table.insert(fields, "model")
	end
	for _, f in ipairs(fields) do
		Settings.reset(L.key(kind, f), "custom")
	end
end

-- Style presets and model choice -----------------------------------------------------------------------------------------

-- applyStyle(kind, styleId): copies the category's palette into the draft (the model choice is kept)
function L.applyStyle(kind, styleId)
	for _, st in ipairs(Lib.styles(kind)) do
		if st.id == styleId then
			local look = Lib.baseLook(kind)
			for k, v in pairs(st.look) do
				look[k] = type(v) == "table" and table.clone(v) or v
			end
			look.effects = Settings.get(L.key(kind, "effects"))
			L.writeLook(kind, look)
			Settings.set(L.key(kind, "style"), styleId, "custom")
			return true
		end
	end
	return false
end

-- selectModel(kind, id): chooses a model; for characters the slot comes from the model (choosing the chosen one again clears it)
function L.selectModel(kind, id)
	local info = L.modelInfo(kind, id)
	if not info then
		return false, "unknown model"
	end
	if kind == "char" then
		local slot = info.group == "costume" and "costume" or info.slot
		local cur = Settings.get(L.key("char", slot))
		local ok, err = Settings.set(L.key("char", slot), cur == id and "" or id, "custom")
		if not ok then
			return false, err
		end
		if cur ~= id and info.group == "costume" then
			-- a costume brings its own natural colours (an imported mesh keeps its texture, so only built-in shapes have one)
			if not info.imported then
				L.writeLook("char", Lib.styleLook("char", id))
			end
		end
		return true
	end
	local ok, err = Settings.set(L.key(kind, "model"), id, "custom")
	if not ok then
		return false, err
	end
	return true
end

-- Presets ---------------------------------------------------------------------------------------------------------------------

local function cleanName(name)
	if type(name) ~= "string" then
		return nil, "name must be text"
	end
	local n = string.match(name, "^%s*(.-)%s*$")
	if n == "" then
		return nil, "name is empty"
	end
	if #n > 24 then
		return nil, "name is longer than 24 characters"
	end
	if string.find(n, "[%c]") then
		return nil, "name contains control characters"
	end
	return n
end

local function readPresets(kind)
	local text = Settings.get(L.key(kind, "presets"))
	if text == "" then
		return {}
	end
	local raw = Json.decode(text)
	if type(raw) ~= "table" or type(raw.list) ~= "table" then
		return {}
	end
	local out, seen = {}, {}
	for _, e in ipairs(raw.list) do
		if type(e) == "table" and type(e.n) == "string" and type(e.s) == "table" then
			local name = cleanName(e.n)
			local snap = name and L.normalize(kind, e.s)
			if snap and not seen[string.lower(name)] and #out < L.MAX_PRESETS then
				seen[string.lower(name)] = true
				table.insert(out, { name = name, category = type(e.c) == "string" and string.sub(e.c, 1, 16) or "", t = tonumber(e.t) or 0, snap = snap })
			end
		end
	end
	return out
end

local function writePresets(kind, list)
	local arr = {}
	for _, e in ipairs(list) do
		table.insert(arr, { n = e.name, c = e.category, t = e.t, s = { sel = e.snap.sel, look = e.snap.look } })
	end
	local text = Json.encode({ v = 1, list = Json.array(arr) })
	return Settings.set(L.key(kind, "presets"), text, "custom")
end

-- presets(kind) -> list of { name, category, t (unix time, 0 if unknown), snap }; invalid entries are dropped on read
function L.presets(kind)
	return readPresets(kind)
end

local function nowTime()
	local ok, t = pcall(os.time)
	return ok and t or 0
end

-- savePreset(kind, name) -> true | false, err. An existing name is overwritten ONLY by the same name (inside this kind).
function L.savePreset(kind, name)
	local n, err = cleanName(name)
	if not n then
		return false, err
	end
	local snap, serr = L.snapshot(kind)
	if not snap then
		return false, serr
	end
	local list = readPresets(kind)
	local entry = { name = n, category = Settings.get(L.key(kind, "style")), t = nowTime(), snap = snap }
	for i, e in ipairs(list) do
		if string.lower(e.name) == string.lower(n) then
			list[i] = entry
			local ok, werr = writePresets(kind, list)
			return ok, werr
		end
	end
	if #list >= L.MAX_PRESETS then
		return false, "preset limit reached (" .. L.MAX_PRESETS .. ")"
	end
	table.insert(list, entry)
	return writePresets(kind, list)
end

function L.deletePreset(kind, name)
	local list = readPresets(kind)
	for i, e in ipairs(list) do
		if e.name == name then
			table.remove(list, i)
			return writePresets(kind, list)
		end
	end
	return false, "no such preset"
end

function L.duplicatePreset(kind, name)
	local list = readPresets(kind)
	for _, e in ipairs(list) do
		if e.name == name then
			if #list >= L.MAX_PRESETS then
				return false, "preset limit reached (" .. L.MAX_PRESETS .. ")"
			end
			local base = string.sub(name, 1, 20)
			local copy, n = base .. " 2", 2
			local function taken(nm)
				for _, x in ipairs(list) do
					if string.lower(x.name) == string.lower(nm) then
						return true
					end
				end
				return false
			end
			while taken(copy) do
				n += 1
				copy = base .. " " .. n
			end
			table.insert(list, { name = copy, category = e.category, t = nowTime(), snap = e.snap })
			local ok, err = writePresets(kind, list)
			return ok, err, copy
		end
	end
	return false, "no such preset"
end

-- loadPreset(kind, name): copies the preset into the draft (the preview shows it; Apply puts it on the avatar/tool)
function L.loadPreset(kind, name)
	for _, e in ipairs(readPresets(kind)) do
		if e.name == name then
			L.writeSelection(kind, e.snap.sel)
			L.writeLook(kind, e.snap.look)
			return true
		end
	end
	return false, "no such preset"
end

return L
