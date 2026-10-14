--!nonstrict
-- features/SoundPack: the sounds supplied by the project owner (assets/sounds -> data/SoundPack). They are written to
-- MM2Hub/sounds/ the first time one is needed, so a bundled sound works without copying files by hand. Needs the executor's file API
-- (writefile) and, to play, getcustomasset; without them the sound is reported as unavailable instead of failing silently.
-- Depends on: SoundPack data, Codec, Env, Logger.

local import = ...
local Data = import("data/SoundPack")
local Codec = import("core/Codec")
local Env = import("core/Env")
local Logger = import("core/Logger")

local M = {}

local byFile = {}
for _, e in ipairs(Data) do
	byFile[e.file] = e
end

local installed = {} -- file -> true once written/verified this session

-- list() -> entries without the data: { file, name, ru, category, duration, bytes, source }
function M.list()
	local out = {}
	for _, e in ipairs(Data) do
		table.insert(out, { file = e.file, name = e.name, ru = e.ru, category = e.category, duration = e.duration, bytes = e.bytes, source = "file:" .. e.file })
	end
	return out
end

function M.has(file)
	return byFile[file] ~= nil
end

-- sourceInfo("file:x.mp3") -> entry or nil
function M.fromSource(source)
	local file = type(source) == "string" and string.match(source, "^file:%s*(.-)%s*$")
	return file and byFile[file] or nil
end

-- ensure(file) -> true | false, err. Writes MM2Hub/sounds/<file> unless it is already there with the right size.
function M.ensure(file)
	local e = byFile[file]
	if not e then
		return false, "not a bundled sound"
	end
	if installed[file] then
		return true
	end
	if not Env.persistent() then
		return false, "this executor has no file API (writefile), so bundled sounds cannot be installed"
	end
	local path = Env.ROOT .. "/sounds/" .. file
	local existing = Env.read(path)
	if existing and #existing == e.bytes then
		installed[file] = true
		return true
	end
	local raw, derr = Codec.b64decode(e.data)
	if not raw or #raw ~= e.bytes then
		return false, "bundled sound is corrupt: " .. tostring(derr)
	end
	local ok, err = Env.write(path, raw)
	if not ok then
		return false, tostring(err)
	end
	-- read it back: an executor whose writefile mangles binary data (stops at a zero byte, re-encodes) must not pass as installed
	local back = Env.read(path)
	if not back or #back ~= e.bytes then
		return false, string.format("writefile stored %s of %d bytes: this executor cannot write binary files", back and tostring(#back) or "nothing", e.bytes)
	end
	installed[file] = true
	Logger.info("SoundPack", "installed %s (%d bytes)", file, e.bytes)
	return true
end

-- installAll() -> installed count, problems
function M.installAll()
	local n, problems = 0, {}
	for _, e in ipairs(Data) do
		local ok, err = M.ensure(e.file)
		if ok then
			n += 1
		else
			table.insert(problems, e.file .. ": " .. tostring(err))
		end
	end
	return n, problems
end

function M._reset()
	table.clear(installed)
end

return M
