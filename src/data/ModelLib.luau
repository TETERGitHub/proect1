--!nonstrict
-- data/ModelLib: catalogue of the customisation models (gun, knife, character accessories and costumes) and their
-- style presets. Pure data: nothing here creates Roblox objects. The in-game builder is features/Cosmetics, the
-- offline picture is tools/model_render.py.
-- Depends on: ModelKit, ModelsGun, ModelsKnife, ModelsChar.

local import = ...
local Kit = import("data/ModelKit")
local Guns = import("data/ModelsGun")
local Rig = import("data/Rig")

local Lib = {}

local SETS = {
	gun = Guns,
}
local ok1, Knives = pcall(import, "data/ModelsKnife")
if ok1 then SETS.knife = Knives end
local ok2, Chars = pcall(import, "data/ModelsChar")
if ok2 then SETS.char = Chars end

local cache = {} -- kind|id -> built model

function Lib.kinds()
	return { "gun", "knife", "char" }
end

-- ids(kind) -> ordered model ids
function Lib.ids(kind)
	local set = SETS[kind]
	return set and set.order and table.clone(set.order) or {}
end

function Lib.has(kind, id)
	local set = SETS[kind]
	return set ~= nil and set[id] ~= nil and type(set[id]) == "table" and set[id].build ~= nil
end

-- info(kind, id) -> { id, name, category, partCount }
function Lib.info(kind, id)
	if not Lib.has(kind, id) then
		return nil
	end
	local def = SETS[kind][id]
	local model = Lib.model(kind, id)
	return { id = id, name = def.name, category = def.category, group = def.group, partCount = #model.parts, anchor = def.anchor, slot = def.slot }
end

function Lib.model(kind, id)
	local key = kind .. "|" .. id
	local m = cache[key]
	if not m then
		local def = SETS[kind] and SETS[kind][id]
		assert(def and def.build, "unknown model " .. key)
		m = Kit.new()
		def.build(m)
		cache[key] = m
	end
	return m
end

-- styles(kind) -> list of { id, look } category presets
function Lib.styles(kind)
	local set = SETS[kind]
	return set and set.styles or {}
end

local function copyLook(l)
	local out = {}
	for k, v in pairs(l) do
		out[k] = type(v) == "table" and table.clone(v) or v
	end
	return out
end

-- baseLook(kind) -> a full look filled with defaults
function Lib.baseLook(kind)
	local look = Kit.defaultLook()
	local set = SETS[kind]
	if set and set.baseLook then
		for k, v in pairs(set.baseLook) do
			look[k] = type(v) == "table" and table.clone(v) or v
		end
	end
	return look
end

-- styleLook(kind, modelId) -> the model's own default look (a model may carry `look`), else the first style
function Lib.styleLook(kind, id)
	local look = Lib.baseLook(kind)
	local def = SETS[kind] and SETS[kind][id]
	local src = def and def.look
	if not src then
		-- the style named like the model's category, else the first one
		local styles = Lib.styles(kind)
		src = styles[1] and styles[1].look
		for _, st in ipairs(styles) do
			if def and st.id == def.category then
				src = st.look
				break
			end
		end
	end
	for k, v in pairs(src or {}) do
		look[k] = type(v) == "table" and table.clone(v) or v
	end
	return look
end

-- parts(kind, id, look) -> resolved plain part list (see ModelKit.resolve)
function Lib.parts(kind, id, look, opts)
	local parts = Kit.resolve(Lib.model(kind, id), look or Lib.styleLook(kind, id), opts)
	local def = SETS[kind] and SETS[kind][id]
	if def and def.group == "costume" then
		-- every piece of a costume follows one body part (see data/Rig)
		for _, p in ipairs(parts) do
			p.bone = p.bone or Rig.assign(p.pos)
		end
	end
	return parts
end

-- isCostume(kind, id) -> true for full-body costumes (their meshes/parts are split per bone)
function Lib.isCostume(kind, id)
	local def = SETS[kind] and SETS[kind][id]
	return def ~= nil and def.group == "costume"
end

-- bounds(kind, id) -> lo {x,y,z}, hi {x,y,z}, size {x,y,z} of the model's rotated parts (cached with the model)
function Lib.bounds(kind, id)
	local key = "b|" .. kind .. "|" .. id
	local c = cache[key]
	if not c then
		local lo, hi = Kit.bounds(Lib.parts(kind, id))
		c = { lo = lo, hi = hi, size = { hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3] } }
		cache[key] = c
	end
	return c.lo, c.hi, c.size
end

Lib.copyLook = copyLook
Lib.MATERIALS = Kit.MATERIALS
return Lib
