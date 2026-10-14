--!nonstrict
-- tests/mesh_snapshot: not part of the suite. Prints the smooth meshes of every model of a kind as JSON ("@@MESH <id> <json>") for tools/model_render.py --mesh.
local import = ...
local Json = import("core/Json")
local Lib = import("data/ModelLib")
local Kit = import("data/ModelKit")
local Mesher = import("data/Mesher")

for _, id in ipairs(Lib.ids(MODEL_KIND)) do
	local ok, err = pcall(function()
		local look = Lib.styleLook(MODEL_KIND, id)
		local groups = Mesher.build(Lib.model(MODEL_KIND, id))
		local out = {}
		for _, g in ipairs(groups) do
			local color, material, transparency, neon = Kit.partLook(g.role, g.material, g.decor, look)
			local obj, center, size = Mesher.toObj(g.mesh)
			table.insert(out, { key = g.key, color = color, material = material, transparency = transparency, neon = neon, center = center, size = size, tris = #g.mesh.f, obj = obj })
		end
		print("@@MESH " .. id .. " " .. Json.encode({ groups = out }))
	end)
	if not ok then print("@@ERR " .. id .. " " .. tostring(err)) end
end
return true
