--!nonstrict
-- features/ModelSync: fetches the models pack (weapons, knives, characters) from the licence server the hub was started from,
-- so buyers do not copy MM2Hub/models by hand. Uses the same key as the loader (core/Launch); the server hands the pack only
-- to a valid key (server/app.py /v1/models). Only missing or changed files are downloaded (compared by size), each one is
-- written to MM2Hub/models/, index.json last, then features/MeshModels reloads. Runs in the background after the hub starts.
-- Nothing happens when the hub was not started by the loader, the executor has no file API, or the server has no pack.
-- STATUS: implemented; verified against the mock layer only (not checked in a real executor).
-- Depends on: Settings, Env, Json, Codec, Logger, Notify, Launch, MeshModels.

local import = ...
local Settings = import("core/Settings")
local Env = import("core/Env")
local Json = import("core/Json")
local Codec = import("core/Codec")
local Logger = import("core/Logger")
local Notify = import("core/Notify")
local Launch = import("core/Launch")
local MeshModels = import("features/MeshModels")

local ModelSync = {}

local FOLDER = Env.ROOT .. "/models/"
local MAX_FILES = 600
local status = { state = "idle", done = 0, total = 0, error = nil }

local function nameOk(n)
	return type(n) == "string" and #n <= 64 and not string.find(n, "..", 1, true) and string.match(n, "^[%w _%-%.%(%)]+%.%a+$") ~= nil
end

-- post(launch, path, body) -> table|nil, err (executors differ in field names; take whichever is a string)
local function post(launch, path, body)
	local ok, res = pcall(launch.request, {
		Url = launch.serverUrl .. path,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = Json.encode(body),
	})
	if not ok then
		return nil, "request failed: " .. tostring(res)
	end
	local text = type(res) == "table" and (res.Body or res.body or res.Response or res.response) or (type(res) == "string" and res or nil)
	if type(text) ~= "string" or text == "" then
		return nil, "empty response"
	end
	local data = Json.decode(text)
	if type(data) ~= "table" then
		return nil, "unreadable response"
	end
	return data
end

function ModelSync.status()
	return status
end

-- sync(launch, pause) -> downloaded count | nil, err. pause() is called between files (task.wait in the game).
function ModelSync.sync(launch, pause)
	launch = launch or Launch
	if not (launch.serverUrl and launch.key and launch.request) then
		return nil, "not started by the loader"
	end
	if not Env.persistent() then
		return nil, "this executor has no file API"
	end
	status = { state = "checking", done = 0, total = 0 }
	local who = { key = launch.key, uid = launch.uid }
	local list, err = post(launch, "/v1/models", who)
	if not list then
		status = { state = "error", error = err, done = 0, total = 0 }
		return nil, err
	end
	if list.ok ~= true or type(list.files) ~= "table" or type(list.index) ~= "string" then
		local why = tostring(list.error or "no models pack")
		status = { state = "none", error = why, done = 0, total = 0 }
		return nil, why
	end
	local need = {}
	for i, f in ipairs(list.files) do
		if i > MAX_FILES then
			break
		end
		if type(f) == "table" and nameOk(f.name) and type(f.bytes) == "number" then
			local have = Env.read(FOLDER .. f.name)
			if not have or #have ~= f.bytes then
				table.insert(need, f)
			end
		end
	end
	local oldIndex = Env.read(FOLDER .. "index.json")
	if #need == 0 and oldIndex == list.index then
		status = { state = "ready", done = 0, total = 0 }
		return 0
	end
	status = { state = "downloading", done = 0, total = #need }
	if #need > 0 then
		Notify.push({ title = "Models", text = string.format("Downloading %d model files...", #need) })
	end
	for _, f in ipairs(need) do
		local data, ferr = post(launch, "/v1/models/file", { key = launch.key, uid = launch.uid, name = f.name })
		local raw = data and data.ok == true and type(data.data) == "string" and Codec.b64decode(data.data) or nil
		if not raw or #raw ~= f.bytes then
			local why = string.format("%s: %s", f.name, tostring(ferr or (data and data.error) or "bad file"))
			Logger.warn("ModelSync", "download failed: %s", why)
			status = { state = "error", error = why, done = status.done, total = #need }
			return nil, why
		end
		local ok, werr = Env.write(FOLDER .. f.name, raw)
		if not ok then
			status = { state = "error", error = werr, done = status.done, total = #need }
			return nil, werr
		end
		status.done += 1
		if pause then
			pause()
		end
	end
	Env.write(FOLDER .. "index.json", list.index) -- last: a half-finished download never points at missing files
	local count = MeshModels.reload()
	status = { state = "ready", done = #need, total = #need }
	Notify.push({ title = "Models", text = string.format("Models ready: %d (open the Custom pages to use them).", count or 0) })
	return #need
end

-- start(ctx): in the background, once, when the setting is on
function ModelSync.start(ctx)
	if not Settings.get("models.autoDownload") or not Launch.serverUrl then
		return
	end
	local alive = true
	ctx.maid:Give(function()
		alive = false
	end)
	task.spawn(function()
		local ok, res, err = pcall(ModelSync.sync, Launch, function()
			if alive then
				task.wait()
			end
		end)
		if not ok then
			Logger.warn("ModelSync", "sync failed: %s", tostring(res))
		elseif res == nil then
			Logger.info("ModelSync", "no download: %s", tostring(err))
		end
	end)
end

return ModelSync
