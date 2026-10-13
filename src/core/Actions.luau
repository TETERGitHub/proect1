--!nonstrict
-- core/Actions: named, discoverable commands (quick commands palette, hotkeys,
-- dashboard quick actions all dispatch through here).
-- Depends on: Logger, Signal.

local import = ...
local Logger = import("core/Logger")
local Signal = import("core/Signal")

local Actions = {}
Actions.Ran = Signal.new("Actions.Ran") -- (id, ok, err)

local actions = {}
local order = {}

-- register(id, {name, desc, fn, category?, keywords?})
function Actions.register(id, def)
	assert(type(id) == "string" and #id > 0, "action id required")
	assert(type(def) == "table" and type(def.fn) == "function", "action needs fn: " .. id)
	assert(not actions[id], "duplicate action: " .. id)
	actions[id] = {
		id = id,
		name = def.name or id,
		desc = def.desc or "",
		fn = def.fn,
		category = def.category or "general",
		keywords = def.keywords or {},
	}
	table.insert(order, id)
end

function Actions.unregister(id)
	if actions[id] then
		actions[id] = nil
		local i = table.find(order, id)
		if i then
			table.remove(order, i)
		end
	end
end

function Actions.has(id)
	return actions[id] ~= nil
end

function Actions.get(id)
	return actions[id]
end

function Actions.list()
	local out = {}
	for _, id in ipairs(order) do
		table.insert(out, actions[id])
	end
	return out
end

-- run(id, ...) -> ok, resultOrError. Never throws.
function Actions.run(id, ...)
	local a = actions[id]
	if not a then
		return false, "unknown action: " .. tostring(id)
	end
	local ok, res = pcall(a.fn, ...)
	if not ok then
		Logger.error("Actions", "%s failed: %s", id, tostring(res))
	end
	Actions.Ran:Fire(id, ok, ok and nil or tostring(res))
	return ok, res
end

function Actions._reset()
	table.clear(actions)
	table.clear(order)
	Actions.Ran:DisconnectAll()
end

return Actions
