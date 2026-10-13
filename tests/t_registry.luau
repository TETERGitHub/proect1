--!nonstrict
local import = ...
local T = import("tests/Framework")
local Registry = import("core/Registry")
local Settings = import("core/Settings")
local Actions = import("core/Actions")

T.suite("Registry")
T.test("at least 100 unique features", ">= 100 entries, ids unique", function()
	T.truthy(Registry.count() >= 100, tostring(Registry.count()))
	local seen = {}
	for _, e in ipairs(Registry.all()) do
		T.falsy(seen[e.id], "duplicate " .. e.id); seen[e.id] = true
	end
	return Registry.count() .. " features"
end)
T.test("every feature has text and valid category", "name/ru/desc present", function()
	for _, e in ipairs(Registry.all()) do
		T.truthy(e.name ~= "" and e.ru ~= "" and e.desc ~= "", e.id)
		T.truthy(Registry.CATEGORIES[e.cat], e.id)
	end
end)
T.test("setting impls resolve to schema", "no dangling setting keys", function()
	T.fresh()
	for _, e in ipairs(Registry.all()) do
		if e.impl.kind == "setting" then T.truthy(Settings.has(e.impl.target), e.id .. " -> " .. e.impl.target) end
	end
end)
T.test("fn impls resolve to real functions", "module exports named function", function()
	local n = 0
	for _, e in ipairs(Registry.all()) do
		if e.impl.kind == "fn" then
			local ok, mod = pcall(import, e.impl.module)
			T.truthy(ok, e.id .. ": cannot load " .. e.impl.module .. " " .. tostring(mod))
			T.eq(type(mod[e.impl.target]), "function", e.id .. " -> " .. e.impl.module .. ":" .. e.impl.target)
			n += 1
		end
	end
	return n .. " functions resolved"
end)
T.test("statuses valid and counted", "all four statuses known", function()
	local c = Registry.statusCounts()
	T.eq(c.tested + c.implemented + c.env + c.partial, Registry.count())
end)
T.test("partial/env features carry a note", "limitations documented", function()
	for _, e in ipairs(Registry.all()) do
		if e.status == "partial" or e.status == "env" then T.truthy(e.note, e.id .. " needs a note") end
	end
end)
