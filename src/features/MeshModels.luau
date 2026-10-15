--!nonstrict
-- features/MeshModels: models YOU imported as real meshes, as opposed to the built-in primitive shapes of data/Models*.luau.
-- The files are produced by tools/convert_mesh.py (OBJ + PNG per material and an entry in MM2Hub/models/index.json) from a
-- model you downloaded yourself; the hub never downloads anything and ships no third-party meshes. An entry may also point at a
-- Roblox asset id you uploaded (parts[i].assetId / textureId) instead of local files.
-- Everything read from index.json is validated (ids, file names, sizes, triangle budget); a model that fails to load is reported and
-- every temporary object it created is destroyed. EXECUTOR-DEPENDENT: local files need getcustomasset, and setting MeshId on a
-- MeshPart needs an executor identity that allows it; neither is verified here.
-- Depends on: Env, Json, Logger, Rig.

local import = ...
local Env = import("core/Env")
local Json = import("core/Json")
local Logger = import("core/Logger")
local Rig = import("data/Rig")

local M = {}

M.INDEX = Env.ROOT .. "/models/index.json"
M.LIMITS = { parts = 48, trisPart = 60000, trisTotal = 120000, extent = 40, minExtent = 0.05 }

local entries = nil -- ordered, validated entries
local byKey = {}

local function fileOk(name, exts)
	if type(name) ~= "string" or #name > 64 or string.find(name, "..", 1, true) or string.find(name, "[/\\]") or not string.match(name, "^[%w _%-%.%(%)]+$") then
		return false
	end
	local ext = string.lower(string.match(name, "%.(%w+)$") or "")
	return exts[ext] == true
end

local function vec3(v, lo, hi)
	if type(v) ~= "table" or #v ~= 3 then
		return nil
	end
	local out = {}
	for i = 1, 3 do
		local n = tonumber(v[i])
		if not n or n ~= n or n < lo or n > hi then
			return nil
		end
		out[i] = n
	end
	return out
end

-- validate(raw) -> entry | nil, err
function M.validate(raw)
	if type(raw) ~= "table" then
		return nil, "entry is not an object"
	end
	local id = raw.id
	if type(id) ~= "string" or not string.match(id, "^[%w_]+$") or #id > 24 then
		return nil, "bad id"
	end
	if raw.kind ~= "gun" and raw.kind ~= "knife" and raw.kind ~= "char" then
		return nil, id .. ": bad kind"
	end
	if type(raw.parts) ~= "table" or #raw.parts < 1 or #raw.parts > M.LIMITS.parts then
		return nil, id .. ": needs 1-" .. M.LIMITS.parts .. " parts"
	end
	local parts, total = {}, 0
	for i, p in ipairs(raw.parts) do
		if type(p) ~= "table" then
			return nil, id .. ": part " .. i .. " is not an object"
		end
		local center = vec3(p.center, -M.LIMITS.extent, M.LIMITS.extent)
		local size = vec3(p.size, M.LIMITS.minExtent, M.LIMITS.extent)
		if not center or not size then
			return nil, id .. ": part " .. i .. " has a bad center or size"
		end
		local tris = tonumber(p.tris) or 0
		if tris < 0 or tris > M.LIMITS.trisPart then
			return nil, id .. ": part " .. i .. " has too many triangles (" .. tostring(tris) .. ")"
		end
		total += tris
		local part = { center = center, size = size, tris = tris }
		if p.bone ~= nil then
			-- costume piece split per R15 body part by tools/convert_mesh.py: it follows that limb's animation
			if type(p.bone) ~= "string" or not Rig.bone(p.bone) then
				return nil, id .. ": part " .. i .. " has an unknown bone '" .. tostring(p.bone) .. "'"
			end
			part.bone = p.bone
		end
		if p.assetId ~= nil then
			if not string.match(tostring(p.assetId), "^%d+$") or #tostring(p.assetId) > 20 then
				return nil, id .. ": part " .. i .. " has a bad assetId"
			end
			part.assetId = tostring(p.assetId)
			if p.textureId ~= nil then
				if not string.match(tostring(p.textureId), "^%d+$") then
					return nil, id .. ": part " .. i .. " has a bad textureId"
				end
				part.textureId = tostring(p.textureId)
			end
		else
			if not fileOk(p.mesh, { obj = true, fbx = true }) then
				return nil, id .. ": part " .. i .. " has a bad mesh file name"
			end
			if p.texture ~= nil and not fileOk(p.texture, { png = true, jpg = true, jpeg = true }) then
				return nil, id .. ": part " .. i .. " has a bad texture file name"
			end
			part.mesh, part.texture = p.mesh, p.texture
		end
		parts[i] = part
	end
	if total > M.LIMITS.trisTotal then
		return nil, id .. ": too many triangles (" .. total .. ")"
	end
	local entry = {
		id = id, kind = raw.kind, name = type(raw.name) == "string" and string.sub(raw.name, 1, 32) or id,
		parts = parts, tris = total, credit = type(raw.credit) == "string" and string.sub(raw.credit, 1, 200) or "",
		hold = vec3(raw.hold, -M.LIMITS.extent, M.LIMITS.extent) or { 0, 0, 0 },
		-- knives only: "reverse" = held blade-down along the forearm (turned 180 degrees about the grip); anything else = blade up
		grip = (raw.kind == "knife" and raw.grip == "reverse") and "reverse" or "normal",
	}
	if raw.kind == "char" then
		entry.group = raw.group == "accessory" and "accessory" or "costume"
		if entry.group == "accessory" then
			if raw.slot ~= "head" and raw.slot ~= "back" and raw.slot ~= "aura" then
				return nil, id .. ": accessory needs a slot (head, back or aura)"
			end
			entry.slot = raw.slot
		end
	end
	return entry
end

-- reload() -> count, problems (list of strings). Reads MM2Hub/models/index.json; a missing file simply means no imports.
function M.reload()
	entries, byKey = {}, {}
	local problems = {}
	local text, rerr = Env.read(M.INDEX)
	if not text then
		return 0, rerr and { rerr } or problems
	end
	local raw, err = Json.decode(text)
	if type(raw) ~= "table" or type(raw.models) ~= "table" then
		return 0, { "index.json: " .. tostring(err or "no 'models' list") }
	end
	for _, r in ipairs(raw.models) do
		local e, verr = M.validate(r)
		if e then
			local key = e.kind .. "|" .. e.id
			if byKey[key] then
				table.insert(problems, e.id .. ": duplicate id")
			else
				byKey[key] = e
				table.insert(entries, e)
			end
		else
			table.insert(problems, verr)
			Logger.warn("MeshModels", "%s", tostring(verr))
		end
	end
	return #entries, problems
end

local function ensure()
	if not entries then
		M.reload()
	end
end

function M.list(kind)
	ensure()
	local out = {}
	for _, e in ipairs(entries) do
		if e.kind == kind then
			table.insert(out, e)
		end
	end
	return out
end

function M.has(kind, id)
	ensure()
	return byKey[kind .. "|" .. tostring(id)] ~= nil
end

function M.info(kind, id)
	ensure()
	return byKey[kind .. "|" .. tostring(id)]
end

local function newRoot(model)
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Parent = model
	model.PrimaryPart = root
	return root
end

-- build(kind, id) -> Model | nil, err. Root at the origin, every MeshPart welded to it. On any failure nothing is left behind.
function M.build(kind, id)
	local e = M.info(kind, id)
	if not e then
		return nil, "unknown imported model '" .. tostring(id) .. "'"
	end
	local model = Instance.new("Model")
	model.Name = "Skin_import_" .. e.id
	local root = newRoot(model)
	for i, p in ipairs(e.parts) do
		local meshUrl, texUrl, err
		if p.assetId then
			meshUrl = "rbxassetid://" .. p.assetId
			texUrl = p.textureId and ("rbxassetid://" .. p.textureId) or nil
		else
			meshUrl, err = Env.customAsset(Env.ROOT .. "/models/" .. p.mesh)
			if meshUrl and p.texture then
				texUrl, err = Env.customAsset(Env.ROOT .. "/models/" .. p.texture)
			end
		end
		if not meshUrl or (p.texture and not p.assetId and not texUrl) then
			model:Destroy()
			return nil, tostring(err or "could not resolve the mesh file")
		end
		local ok, part = pcall(function()
			local mp = Instance.new("MeshPart")
			mp.MeshId = meshUrl
			if texUrl then
				mp.TextureID = texUrl
			end
			return mp
		end)
		if not ok then
			model:Destroy()
			return nil, "this executor cannot create a MeshPart with a custom MeshId: " .. tostring(part)
		end
		part.Name = "Mesh" .. i
		if p.bone then
			part:SetAttribute("bone", p.bone)
		end
		part.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
		local rel = CFrame.new(p.center[1] - e.hold[1], p.center[2] - e.hold[2], p.center[3] - e.hold[3])
		if e.grip == "reverse" then
			rel = CFrame.Angles(math.pi, 0, 0) * rel
		end
		part.CFrame = root.CFrame * rel
		part.Parent = model
		-- unanchored in tools: without this weld the mesh would fall out of the Handle (the rig path replaces it with Welds)
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = root, part
		w.Parent = part
	end
	return model
end

return M
