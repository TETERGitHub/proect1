--!nonstrict
-- loader/Loader: the small client that ships to users in server-licensed builds. It contains NO signing
-- secret and none of the hub code: it sends the key to the licence server, receives the encrypted hub
-- bundle, authenticates and decrypts it with a key derived from the licence key, and runs it.
-- A heartbeat re-checks the licence; when the server refuses or the term ends, the hub is unloaded.
--
-- All environment access is injected (deps) so the whole flow is unit-tested without a network.
-- deps = { request(tbl)->{Success,StatusCode,Body}, loadstring(src)->fn|nil,err, readKey()->text|nil,
--          writeKey(text), prompt(onSubmit, lastError), uid, notify(title,text), clock()->seconds,
--          spawn(fn), wait(seconds), serverUrl, heartbeat(seconds), log(text)? }

local import = ...
local Json = import("core/Json")
local Codec = import("core/Codec")
local PayloadCipher = import("core/PayloadCipher")

local Loader = {}

local function log(deps, text, ...)
	if deps.log then
		pcall(deps.log, string.format(text, ...))
	end
end

local function post(deps, path, body)
	local ok, res = pcall(deps.request, {
		Url = deps.serverUrl .. path,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = Json.encode(body),
	})
	if not ok then
		return nil, "could not reach the licence server"
	end
	if type(res) ~= "table" or type(res.Body) ~= "string" then
		return nil, "empty response from the licence server"
	end
	local data = Json.decode(res.Body)
	if type(data) ~= "table" then
		return nil, "licence server sent an unreadable response"
	end
	return data
end

-- activate(deps, keyText) -> session|nil, err
function Loader.activate(deps, keyText)
	local canonical = PayloadCipher.canonicalKey(keyText)
	if not canonical then
		log(deps, "step 1/5 FAILED: that does not look like a key")
		return nil, "that does not look like a key"
	end
	log(deps, "step 1/5 key format ok, contacting %s", tostring(deps.serverUrl))
	local data, err = post(deps, "/v1/activate", { key = canonical, uid = deps.uid })
	if not data then
		log(deps, "step 2/5 FAILED: %s", tostring(err))
		return nil, err
	end
	if not data.ok then
		log(deps, "step 2/5 server refused the key: %s", tostring(data.error))
		return nil, tostring(data.error or "key rejected")
	end
	log(deps, "step 2/5 server accepted the key (payload %d chars base64)", #tostring(data.payload))
	local nonce = Codec.b64decode(tostring(data.nonce))
	local cipher = Codec.b64decode(tostring(data.payload))
	if not nonce or not cipher or #nonce ~= 12 or type(data.tag) ~= "string" then
		return nil, "malformed payload from the licence server"
	end
	log(deps, "step 3/5 decrypting %d bytes (can take a few seconds on phones)", #cipher)
	local source, derr = PayloadCipher.decrypt(canonical, nonce, cipher, data.tag)
	if not source then
		log(deps, "step 3/5 FAILED: %s", tostring(derr))
		return nil, derr
	end
	log(deps, "step 4/5 compiling %d bytes of hub code", #source)
	local fn, lerr = deps.loadstring(source)
	if not fn then
		log(deps, "step 4/5 FAILED: %s", tostring(lerr))
		return nil, "hub code failed to compile: " .. tostring(lerr)
	end
	return { canonical = canonical, fn = fn, expires = data.expires, serverNow = data.now, startedAt = deps.clock() }
end

-- run(deps) -> handle. Prompts for a key when none is stored or the stored one is refused.
function Loader.run(deps)
	local handle = { running = false, hub = nil, stopped = false }

	local function stop(reason)
		if handle.stopped then
			return
		end
		handle.stopped = true
		handle.running = false
		if handle.hub and type(handle.hub) == "table" and type(handle.hub.unload) == "function" then
			pcall(handle.hub.unload)
		end
		deps.notify("Licence", reason)
	end
	handle.stop = stop

	local function start(session)
		local ok, hub = pcall(session.fn)
		if not ok then
			log(deps, "step 5/5 FAILED: %s", tostring(hub))
			return false, "hub failed to start: " .. tostring(hub)
		end
		log(deps, "step 5/5 hub started")
		handle.hub = hub
		handle.running = true
		handle.session = session
		deps.writeKey(session.canonical)
		-- heartbeat: server re-check plus local term enforcement
		deps.spawn(function()
			while handle.running and not handle.stopped do
				deps.wait(deps.heartbeat or 300)
				if not handle.running or handle.stopped then
					break
				end
				local elapsed = deps.clock() - session.startedAt
				if session.expires and session.serverNow and session.serverNow + elapsed >= session.expires then
					stop("Your key has expired.")
					break
				end
				local data, err = post(deps, "/v1/ping", { key = session.canonical, uid = deps.uid })
				if data and data.ok == false then
					stop("Licence refused: " .. tostring(data.error))
					break
				end
				-- network errors are tolerated (the local term check above still applies)
				if not data and err then
					handle.lastError = err
				end
			end
		end)
		return true
	end

	local function attempt(keyText, lastError)
		local session, err = Loader.activate(deps, keyText)
		if not session then
			if deps.prompt then
				deps.prompt(function(text)
					attempt(text, nil)
				end, err)
			end
			handle.lastError = err
			return false, err
		end
		local ok, serr = start(session)
		if not ok then
			handle.lastError = serr
			deps.notify("Hub", serr)
		end
		return ok, serr
	end

	local stored = deps.readKey()
	if stored and stored ~= "" then
		local ok = attempt(stored, nil)
		-- a refused stored key already opened the prompt via attempt()
		return handle
	end
	deps.prompt(function(text)
		attempt(text, nil)
	end, nil)
	return handle
end

return Loader
