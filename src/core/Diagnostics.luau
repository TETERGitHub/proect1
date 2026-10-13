--!nonstrict
-- core/Diagnostics: error log access, plain-text report builder/exporter, safe-call wrapper.
-- Report sections come from providers registered by other modules, so this module
-- has no hard dependency on them.
-- Depends on: Logger, Env, Version, Maid.

local import = ...
local Logger = import("core/Logger")
local Env = import("core/Env")
local Version = import("core/Version")
local Maid = import("core/Maid")

local Diagnostics = {}

local providers = {}
local providerOrder = {}

-- addProvider(title, fn -> string|{string}) ; replaces a provider with the same title.
function Diagnostics.addProvider(title, fn)
	assert(type(title) == "string" and type(fn) == "function", "bad provider")
	if not providers[title] then
		table.insert(providerOrder, title)
	end
	providers[title] = fn
end

function Diagnostics.removeProvider(title)
	if providers[title] then
		providers[title] = nil
		local i = table.find(providerOrder, title)
		if i then
			table.remove(providerOrder, i)
		end
	end
end

-- safeCall(label, fn, ...) -> ok, result. Logs failures with the label as context.
function Diagnostics.safeCall(label, fn, ...)
	local results = table.pack(xpcall(fn, function(err)
		return tostring(err) .. "\n" .. debug.traceback("", 2)
	end, ...))
	if not results[1] then
		Logger.error("Safe", "%s failed: %s", label, tostring(results[2]))
		return false, results[2]
	end
	return true, results[2]
end

function Diagnostics.errors(limit)
	local list = Logger.entries({ level = "warn" })
	if limit and #list > limit then
		local out = {}
		for i = #list - limit + 1, #list do
			table.insert(out, list[i])
		end
		return out
	end
	return list
end

-- report() -> multi-line string
function Diagnostics.report()
	local lines = {}
	local function add(s)
		table.insert(lines, s)
	end
	add("=== " .. Version.info() .. " diagnostic report ===")
	add("generated: " .. os.date("!%Y-%m-%d %H:%M:%S UTC"))
	add("persistent storage: " .. tostring(Env.persistent()))
	add("")
	add("-- environment capabilities --")
	for _, c in ipairs(Env.capList()) do
		add(string.format("  %-14s %s", c.name, c.available and "yes" or "no"))
	end
	local stats = Maid.stats()
	add("")
	add(string.format("-- resources --\n  maids=%d tracked tasks=%d", stats.maids, stats.tasks))
	for _, title in ipairs(providerOrder) do
		add("")
		add("-- " .. title .. " --")
		local ok, res = pcall(providers[title])
		if not ok then
			add("  (provider failed: " .. tostring(res) .. ")")
		elseif type(res) == "table" then
			for _, l in ipairs(res) do
				add("  " .. tostring(l))
			end
		else
			add("  " .. tostring(res))
		end
	end
	add("")
	add(string.format("-- log (%d warn, %d error, last 60 entries) --", Logger.count("warn"), Logger.count("error")))
	add(Logger.dump(60))
	return table.concat(lines, "\n")
end

-- export() -> ok, summary. Writes MM2Hub/report.txt and copies to clipboard when possible.
function Diagnostics.export()
	local text = Diagnostics.report()
	local wrote, werr = Env.write(Env.ROOT .. "/report.txt", text)
	local copied = Env.clipboard(text)
	if not wrote and not copied then
		return false, "could not save or copy report: " .. tostring(werr)
	end
	local parts = {}
	if wrote then
		table.insert(parts, Env.persistent() and ("saved to " .. Env.ROOT .. "/report.txt") or "kept in session memory (no file API)")
	end
	if copied then
		table.insert(parts, "copied to clipboard")
	end
	return true, table.concat(parts, ", ")
end

return Diagnostics
