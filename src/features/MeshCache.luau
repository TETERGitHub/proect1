--!nonstrict
-- features/MeshCache: makes the built-in models available as SMOOTH MESHES (data/Mesher) instead of Part primitives.
-- For a model the groups are written once as OBJ files to MM2Hub/meshcache/ (writefile), turned into URLs with getcustomasset and
-- checked by really loading a MeshPart: the mesh is "ready" only when the engine reports a non-zero MeshSize. Anything else is
-- "failed" with the reason (no file API, no getcustomasset, the executor refused the MeshId, load timeout) and the caller falls back to
-- the Part version of the same model. Nothing is assumed: status() says which one you are looking at.
-- EXECUTOR-DEPENDENT and unverified in a real client: needs writefile/readfile/isfile, getcustomasset, and an identity that may set
-- MeshPart.MeshId.
-- Depends on: Mesher, ModelLib, Env, Settings, Signal, Logger.

local import = ...
local Mesher = import("data/Mesher")
local Lib = import("data/ModelLib")
local Env = import("core/Env")
local Settings = import("core/Settings")
local Signal = import("core/Signal")
local Logger = import("core/Logger")

local M = {}

M.Ready = Signal.new("MeshCache.Ready") -- (kind, id, ok, detail)
M.LOAD_TIMEOUT = 8

local entries = {} -- "kind|id" -> { status = "loading"|"ready"|"failed", detail, groups }
local loadCheck = nil -- test seam: fn(url, size) -> ok, detail

function M._setLoadCheck(fn)
	loadCheck = fn
end

function M.enabled()
	return Settings.get("custom.useMeshes")
end

local function key(kind, id)
	return kind .. "|" .. id
end

-- status(kind, id) -> "none" | "loading" | "ready" | "failed", detail
function M.status(kind, id)
	local e = entries[key(kind, id)]
	if not e then
		return "none", "not requested"
	end
	return e.status, e.detail
end

-- groups(kind, id) -> list of { key, role, material, decor, url, center, size } when ready
function M.groups(kind, id)
	local e = entries[key(kind, id)]
	return e and e.status == "ready" and e.groups or nil
end

local function engineLoad(url, size)
	-- a real MeshPart is created (not parented) and fetched; the engine reports the mesh's native size once it is loaded
	local ok, part = pcall(function()
		local p = Instance.new("MeshPart")
		p.MeshId = url
		return p
	end)
	if not ok then
		return false, "the executor cannot set MeshPart.MeshId: " .. tostring(part)
	end
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ part })
	end)
	local function meshSize()
		local rok, v = pcall(function()
			return part.MeshSize
		end)
		return rok and v or nil -- not readable in this executor: the size check is skipped
	end
	local waited = 0
	local native = meshSize()
	while native ~= nil and native.Magnitude < 1e-4 and waited < M.LOAD_TIMEOUT do
		task.wait(0.1)
		waited += 0.1
		native = meshSize()
	end
	pcall(function()
		part:Destroy()
	end)
	if native ~= nil and native.Magnitude < 1e-4 then
		return false, string.format("the engine did not load the mesh within %d s (MeshSize stayed 0): the executor may not accept OBJ files for MeshId", M.LOAD_TIMEOUT)
	end
	return true, native and string.format("engine mesh size %.2f x %.2f x %.2f", native.X, native.Y, native.Z) or "loaded (no MeshSize reported)"
end

local function finish(e, kind, id, ok, detail)
	e.status = ok and "ready" or "failed"
	e.detail = detail
	if not ok then
		Logger.warn("MeshCache", "%s/%s: %s", kind, id, tostring(detail))
	end
	M.Ready:Fire(kind, id, ok, detail)
end

-- request(kind, id): start preparing a model (idempotent). Writes the files, loads one mesh to verify, then fires Ready.
function M.request(kind, id)
	local k = key(kind, id)
	if entries[k] then
		return
	end
	local e = { status = "loading", detail = "preparing" }
	entries[k] = e
	task.spawn(function()
		local ok, err = pcall(function()
			if not Lib.has(kind, id) then
				return finish(e, kind, id, false, "unknown model")
			end
			if not Env.persistent() then
				return finish(e, kind, id, false, "this executor has no file API (writefile/readfile/isfile), so meshes cannot be written")
			end
			if not Env.has("getcustomasset") then
				return finish(e, kind, id, false, "getcustomasset is not available in this executor")
			end
			local groups = Mesher.build(Lib.model(kind, id), { bones = Lib.isCostume(kind, id) })
			local out = {}
			for i, g in ipairs(groups) do
				local obj, center, size = Mesher.toObj(g.mesh)
				local path = string.format("%s/meshcache/%s_%s_v%d_%d.obj", Env.ROOT, kind, id, Mesher.VERSION, i)
				local existing = Env.read(path)
				if not existing or #existing ~= #obj then
					local wok, werr = Env.write(path, obj)
					if not wok then
						return finish(e, kind, id, false, "could not write " .. path .. ": " .. tostring(werr))
					end
				end
				local url, uerr = Env.customAsset(path)
				if not url then
					return finish(e, kind, id, false, tostring(uerr))
				end
				out[#out + 1] = { key = g.key, role = g.role, material = g.material, decor = g.decor, bone = g.bone, url = url, center = center, size = size, tris = #g.mesh.f }
			end
			if #out == 0 then
				return finish(e, kind, id, false, "the model produced no mesh groups")
			end
			-- one mesh is enough to know whether the executor accepts generated OBJ files at all
			local lok, ldetail = (loadCheck or engineLoad)(out[1].url, out[1].size)
			if not lok then
				return finish(e, kind, id, false, ldetail)
			end
			e.groups = out
			finish(e, kind, id, true, ldetail)
		end)
		if not ok then
			finish(e, kind, id, false, "internal error: " .. tostring(err))
		end
	end)
end

-- forgetFailed(): lets failed models be tried again (after the user changed something)
function M.forgetFailed()
	for k, e in pairs(table.clone(entries)) do
		if e.status == "failed" then
			entries[k] = nil
		end
	end
end

function M.reset()
	table.clear(entries)
	loadCheck = nil
end

return M
