--!nonstrict
-- core/Cleanup: ordered shutdown steps with error isolation (safe shutdown).
-- Steps run newest-first; one failing step never prevents the rest.
-- Depends on: Logger, Maid.

local import = ...
local Logger = import("core/Logger")
local Maid = import("core/Maid")

local Cleanup = {}

local steps = {}

-- register(name, fn) -> unregister function
function Cleanup.register(name, fn)
	assert(type(name) == "string" and type(fn) == "function", "bad cleanup step")
	local entry = { name = name, fn = fn }
	table.insert(steps, entry)
	return function()
		local i = table.find(steps, entry)
		if i then
			table.remove(steps, i)
		end
	end
end

-- run() -> {ran = n, failed = {{name, err}}}
function Cleanup.run()
	local failed = {}
	local ran = 0
	for i = #steps, 1, -1 do
		local entry = steps[i]
		steps[i] = nil
		ran += 1
		local ok, err = pcall(entry.fn)
		if not ok then
			Logger.error("Cleanup", "step '%s' failed: %s", entry.name, tostring(err))
			table.insert(failed, { name = entry.name, err = tostring(err) })
		end
	end
	return { ran = ran, failed = failed }
end

function Cleanup.pending()
	return #steps
end

function Cleanup.stats()
	return Maid.stats()
end

return Cleanup
