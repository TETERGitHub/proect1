--!nonstrict
-- core/Env: executor capability detection and a storage abstraction.
-- NOTHING here assumes a specific executor: every optional API is looked up by
-- name, type-checked and wrapped in pcall. Results are reported in Diagnostics.
-- STATUS: environment-dependent; verify in your own executor.

local import = ...
local Logger = import("core/Logger")

local Env = {}

local ROOT = "MM2Hub"
Env.ROOT = ROOT

-- Static references (not string lookups) so renaming obfuscators keep working. Each getter is
-- wrapped in pcall at call time because the global may simply not exist in this executor.
local STATIC = {
	writefile = function() return writefile end,
	readfile = function() return readfile end,
	isfile = function() return isfile end,
	makefolder = function() return makefolder end,
	isfolder = function() return isfolder end,
	delfile = function() return delfile end,
	gethui = function() return gethui end,
	setclipboard = function() return setclipboard end,
	getgenv = function() return getgenv end,
	getcustomasset = function() return getcustomasset end,
	listfiles = function() return listfiles end,
}

local function lookup(name)
	local getter = STATIC[name]
	if getter then
		local ok, value = pcall(getter)
		if ok then
			return value
		end
	end
	return nil
end

-- Overridable for tests: Env.setLookup(function(name) ... end)
local lookupFn = lookup
function Env.setLookup(fn)
	lookupFn = fn or lookup
	Env.refresh()
end

local caps = {}

function Env.refresh()
	local function has(name)
		return type(lookupFn(name)) == "function"
	end
	caps = {
		writefile = has("writefile"),
		readfile = has("readfile"),
		isfile = has("isfile"),
		makefolder = has("makefolder"),
		isfolder = has("isfolder"),
		delfile = has("delfile"),
		gethui = has("gethui"),
		setclipboard = has("setclipboard"),
		getgenv = has("getgenv"),
		getcustomasset = has("getcustomasset"),
		listfiles = has("listfiles"),
	}
	caps.fileIO = caps.writefile and caps.readfile and caps.isfile
end

Env.refresh()

function Env.caps()
	return table.clone(caps)
end

function Env.has(name)
	return caps[name] == true
end

function Env.capList()
	local names = {}
	for k in pairs(caps) do
		table.insert(names, k)
	end
	table.sort(names)
	local out = {}
	for _, k in ipairs(names) do
		table.insert(out, { name = k, available = caps[k] })
	end
	return out
end

-- Env.global() -> table shared across re-executions of the hub (used for re-init detection).
local fallbackGlobal = {}
function Env.global()
	if caps.getgenv then
		local ok, g = pcall(lookupFn("getgenv"))
		if ok and type(g) == "table" then
			return g
		end
	end
	-- _G is writable in Roblox; some sandboxes freeze it, so probe before relying on it.
	local writable = pcall(function()
		_G.__mm2probe = nil
	end)
	if writable then
		return _G
	end
	return fallbackGlobal
end

function Env.clipboard(text)
	if not caps.setclipboard then
		return false, "setclipboard is not available in this environment"
	end
	local ok, err = pcall(lookupFn("setclipboard"), text)
	if not ok then
		Logger.warn("Env", "setclipboard failed: %s", tostring(err))
		return false, tostring(err)
	end
	return true
end

-- Env.guiParent() -> container for the hub's ScreenGuis: gethui(), else CoreGui when it accepts
-- children, else PlayerGui. Returns nil, err when nothing works.
function Env.guiParent()
	if caps.gethui then
		local ok, h = pcall(lookupFn("gethui"))
		if ok and h then
			return h, "gethui"
		end
	end
	local ok, cg = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and cg then
		local probe = Instance.new("Folder")
		local set = pcall(function()
			probe.Parent = cg
		end)
		if set and probe.Parent == cg then
			probe:Destroy()
			return cg, "CoreGui"
		end
		pcall(function()
			probe:Destroy()
		end)
	end
	local okp, pg = pcall(function()
		return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	end)
	if okp and pg then
		return pg, "PlayerGui"
	end
	return nil, "no usable GUI container"
end

-- Env.customAsset(path) -> rbxasset url|nil, err  (getcustomasset is executor-specific)
function Env.customAsset(path)
	if not caps.getcustomasset then
		return nil, "getcustomasset is not available in this executor"
	end
	local ok, res = pcall(lookupFn("getcustomasset"), path)
	if not ok or type(res) ~= "string" or res == "" then
		return nil, "getcustomasset failed: " .. tostring(res)
	end
	return res
end

-- Storage ---------------------------------------------------------------------
-- Persistent when file APIs exist, otherwise an in-memory table for the session.

local memory = {}
local forceMemory = false

function Env.setForceMemory(flag)
	forceMemory = flag and true or false
end

function Env.persistent()
	return caps.fileIO and not forceMemory
end

local function ensureFolder(path)
	if not caps.makefolder then
		return
	end
	local isfolder = caps.isfolder and lookupFn("isfolder")
	local make = lookupFn("makefolder")
	local built = ""
	for part in string.gmatch(path, "[^/]+") do
		built = built == "" and part or (built .. "/" .. part)
		local exists = false
		if isfolder then
			local ok, res = pcall(isfolder, built)
			exists = ok and res == true
		end
		if not exists then
			pcall(make, built)
		end
	end
end

-- Env.write(path, text) -> ok, err
function Env.write(path, text)
	if type(path) ~= "string" or type(text) ~= "string" then
		return false, "path and text must be strings"
	end
	if not Env.persistent() then
		memory[path] = text
		return true
	end
	local dir = string.match(path, "^(.*)/[^/]+$")
	if dir then
		ensureFolder(dir)
	end
	local ok, err = pcall(lookupFn("writefile"), path, text)
	if not ok then
		Logger.error("Env", "writefile(%s) failed: %s", path, tostring(err))
		return false, tostring(err)
	end
	return true
end

-- Env.read(path) -> text|nil, err
function Env.read(path)
	if not Env.persistent() then
		return memory[path], nil
	end
	local okExists, exists = pcall(lookupFn("isfile"), path)
	if not okExists or not exists then
		return nil, nil
	end
	local ok, res = pcall(lookupFn("readfile"), path)
	if not ok then
		Logger.error("Env", "readfile(%s) failed: %s", path, tostring(res))
		return nil, tostring(res)
	end
	return res, nil
end

function Env.exists(path)
	if not Env.persistent() then
		return memory[path] ~= nil
	end
	local ok, res = pcall(lookupFn("isfile"), path)
	return ok and res == true
end

function Env.delete(path)
	if not Env.persistent() then
		memory[path] = nil
		return true
	end
	if not caps.delfile then
		return false, "delfile is not available"
	end
	local ok, err = pcall(lookupFn("delfile"), path)
	if not ok then
		return false, tostring(err)
	end
	return true
end

function Env.resetMemory()
	table.clear(memory)
end

return Env
