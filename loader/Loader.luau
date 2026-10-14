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

-- Dependency contract (see the header). Checked once in run() so a missing function is named, not a nil call.
local REQUIRED = { "request", "loadstring", "readKey", "writeKey", "prompt", "notify", "clock", "spawn", "wait" }

-- Refusals that end the licence for good. Everything else a server may say (rate limit, malformed request,
-- anything unknown) is treated as transient so one bad minute never unloads a paying user's hub.
local FATAL = { "revoked", "expired", "invalid key", "bound to another", "not valid yet" }

local function isFatal(message)
	local text = string.lower(tostring(message))
	for _, needle in ipairs(FATAL) do
		if string.find(text, needle, 1, true) then
			return true
		end
	end
	return false
end

Loader.isFatal = isFatal

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
		log(deps, "http: request failed: %s", tostring(res))
		return nil, "could not reach the licence server"
	end
	-- executors differ: Body/body, StatusCode/status_code/Status; take whichever is a string
	local text = type(res) == "table" and (res.Body or res.body or res.Response or res.response) or (type(res) == "string" and res or nil)
	if type(text) ~= "string" or text == "" then
		local code = type(res) == "table" and (res.StatusCode or res.status_code or res.Status or res.status) or "?"
		log(deps, "http: no body (status %s, success %s)", tostring(code), tostring(type(res) == "table" and (res.Success or res.success)))
		return nil, "empty response from the licence server"
	end
	local data = Json.decode(text)
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
	if data.ok ~= true then
		log(deps, "step 2/5 server refused the key: %s", tostring(data.error))
		return nil, tostring(data.error or "key rejected")
	end
	if type(data.payload) ~= "string" or type(data.nonce) ~= "string" or type(data.tag) ~= "string" then
		log(deps, "step 2/5 FAILED: answer lacks payload/nonce/tag")
		return nil, "malformed payload from the licence server"
	end
	log(deps, "step 2/5 server accepted the key (payload %d chars base64)", #data.payload)
	local nonce = Codec.b64decode(data.nonce)
	local cipher = Codec.b64decode(data.payload)
	if not nonce or not cipher or #nonce ~= 12 then
		log(deps, "step 3/5 FAILED: payload is not valid base64 or the nonce has the wrong size")
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
	if type(fn) ~= "function" then
		log(deps, "step 4/5 FAILED: %s", tostring(lerr))
		return nil, "hub code failed to compile: " .. tostring(lerr)
	end
	-- a wrongly typed term must not reach the heartbeat (comparing it would kill that thread)
	local expires = type(data.expires) == "number" and data.expires or nil
	local serverNow = type(data.now) == "number" and data.now or nil
	return { canonical = canonical, fn = fn, expires = expires, serverNow = serverNow, startedAt = deps.clock() }
end

-- run(deps) -> handle. Prompts for a key when none is stored or the stored one is refused.
-- handle: running, stopped, hub, session, lastError, pingFailures, stop(reason)
function Loader.run(deps)
	for _, name in ipairs(REQUIRED) do
		if type(deps[name]) ~= "function" then
			error("loader: missing dependency '" .. name .. "' (function expected)", 2)
		end
	end
	if type(deps.serverUrl) ~= "string" or deps.serverUrl == "" then
		error("loader: missing dependency 'serverUrl' (string expected)", 2)
	end

	local handle = { running = false, hub = nil, stopped = false, pingFailures = 0 }
	local busy = false -- an activation is in flight (the server call can take seconds)

	local function stop(reason)
		if handle.stopped then
			return
		end
		handle.stopped = true
		handle.running = false
		local hub = handle.hub
		if type(hub) == "table" and type(hub.unload) == "function" then
			local ok, err = pcall(hub.unload)
			if not ok then
				log(deps, "unload failed: %s", tostring(err))
			end
		end
		pcall(deps.notify, "Licence", reason)
	end
	handle.stop = stop

	local function heartbeat(session)
		while handle.running and not handle.stopped do
			deps.wait(deps.heartbeat or 300)
			if not handle.running or handle.stopped then
				break
			end
			if session.expires and session.serverNow and session.serverNow + (deps.clock() - session.startedAt) >= session.expires then
				stop("Your key has expired.")
				break
			end
			local data, err = post(deps, "/v1/ping", { key = session.canonical, uid = deps.uid })
			if data and data.ok == false and isFatal(data.error) then
				stop("Licence refused: " .. tostring(data.error))
				break
			elseif data then
				handle.pingFailures = 0
				if data.ok == false then
					log(deps, "ping: transient refusal ignored: %s", tostring(data.error))
				end
			else
				-- network trouble is tolerated (the local term check above still applies) but counted and logged
				handle.pingFailures += 1
				handle.lastError = err
				log(deps, "ping failed (%d in a row): %s", handle.pingFailures, tostring(err))
			end
		end
	end

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
		handle.pingFailures = 0
		pcall(deps.writeKey, session.canonical)
		deps.spawn(function()
			heartbeat(session)
		end)
		return true
	end

	local function attempt(keyText)
		if busy or handle.running or handle.stopped then
			return false, "already running"
		end
		busy = true
		local session, err = Loader.activate(deps, keyText)
		local ok = false
		if session then
			ok, err = start(session)
			if not ok then
				pcall(deps.notify, "Hub", err)
			end
		end
		busy = false
		if not ok then
			handle.lastError = err
			pcall(deps.prompt, function(text)
				attempt(text)
			end, err)
		end
		return ok, err
	end

	local stored = deps.readKey()
	if type(stored) == "string" and stored ~= "" then
		attempt(stored)
		return handle
	end
	deps.prompt(function(text)
		attempt(text)
	end, nil)
	return handle
end

return Loader
