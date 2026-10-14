--!nonstrict
-- tests/model_snapshot: not part of the suite. Prints the resolved part data of every customisation model of a kind
-- ("@@MODEL <name> <json>") for tools/model_render.py. Pure data: no Roblox objects are created.
local import = ...
local Json = import("core/Json")
local Lib = import("data/ModelLib")

local kind = MODEL_KIND
for _, id in ipairs(Lib.ids(kind)) do
	local ok, err = pcall(function()
		local parts = Lib.parts(kind, id, Lib.styleLook(kind, id))
		print("@@MODEL " .. id .. " " .. Json.encode({ parts = parts }))
	end)
	if not ok then print("@@ERR " .. id .. " " .. tostring(err)) end
end
return true
