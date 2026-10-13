--!nonstrict
-- core/Registry: catalogue of user-facing features with implementation status.
-- Each entry names its implementation (setting / action / function / ui id) so
-- tests can verify that every catalogue entry resolves to real code.
-- Depends on: data/Features.

local import = ...
local Features = import("data/Features")

local Registry = {}

local entries = {}
local byId = {}
local provided = {} -- ui feature ids announced by UI modules

Registry.STATUS = {
	tested = "logic covered by automated tests",
	implemented = "implemented; only exercised against the mock Roblox layer",
	env = "depends on executor/engine behaviour; verify in the target environment",
	partial = "works with documented limitations",
}

Registry.CATEGORIES = Features.categories

for _, e in ipairs(Features.list) do
	assert(not byId[e.id], "duplicate feature id: " .. e.id)
	assert(Registry.STATUS[e.status], "bad status for " .. e.id)
	table.insert(entries, e)
	byId[e.id] = e
end

function Registry.all()
	return entries
end

function Registry.get(id)
	return byId[id]
end

function Registry.count()
	return #entries
end

function Registry.byCategory(cat)
	local out = {}
	for _, e in ipairs(entries) do
		if e.cat == cat then
			table.insert(out, e)
		end
	end
	return out
end

function Registry.forSetting(key)
	for _, e in ipairs(entries) do
		if e.impl.kind == "setting" and e.impl.target == key then
			return e
		end
	end
	return nil
end

-- UI modules call provide("Window.drag") at load time.
function Registry.provide(id)
	provided[id] = true
end

function Registry.isProvided(id)
	return provided[id] == true
end

-- validate(resolvers) -> list of problem strings.
-- resolvers = {setting = fn(key)->bool, action = fn(id)->bool, fn = fn(mod, name)->bool, ui = fn(id)->bool}
function Registry.validate(resolvers)
	local problems = {}
	for _, e in ipairs(entries) do
		local impl = e.impl
		local check = resolvers[impl.kind]
		if not check then
			table.insert(problems, e.id .. ": unknown impl kind " .. tostring(impl.kind))
		else
			local ok, res
			if impl.kind == "fn" then
				ok, res = pcall(check, impl.module, impl.target)
			else
				ok, res = pcall(check, impl.target)
			end
			if not ok or not res then
				table.insert(problems, string.format("%s: %s '%s' does not resolve", e.id, impl.kind, tostring(impl.target)))
			end
		end
	end
	return problems
end

function Registry.statusCounts()
	local out = { tested = 0, implemented = 0, env = 0, partial = 0 }
	for _, e in ipairs(entries) do
		out[e.status] += 1
	end
	return out
end

return Registry
