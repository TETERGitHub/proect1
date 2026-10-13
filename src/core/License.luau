--!nonstrict
-- core/License: offline-signed time-limited keys.
--
-- Key = Crockford-base32( payload(14 bytes) .. HMAC-SHA256(secret, payload)[1..10] )
--   payload = version(1) mode(1) issued(u32 BE) value(u32 BE) nonce(4)
--   mode 0 "absolute":   value = unix expiry time, fixed when the key was generated
--   mode 1 "activation": value = duration in seconds, counted from the first activation on this install
--
-- SECURITY NOTE (read before relying on this): the HMAC secret has to live inside the shipped script,
-- so anyone who can read the script can extract it and mint keys, and anyone can patch the check out.
-- This stops guessing and hand-edited expiry dates, nothing more. Real protection requires a
-- server-side check. Server time (Workspace:GetServerTimeNow) is used so changing the local clock does
-- not extend a key; a stored high-water mark rejects clock roll-backs.
--
-- Depends on: Hash, Env, Json, Logger, Services (lazy).

local import = ...
local Hash = import("core/Hash")
local Env = import("core/Env")
local Json = import("core/Json")
local Logger = import("core/Logger")
local Services = import("core/Services")

local License = {}

-- Replaced by tools/build.py --license; stay as placeholders in the source tree.
local SECRET_HEX = "@@LICENSE_SECRET_HEX@@"
local REQUIRED = "@@LICENSE_REQUIRED@@"

local VERSION = 1
local PAYLOAD_BYTES = 14
local MAC_BYTES = 10
local TOTAL_BYTES = PAYLOAD_BYTES + MAC_BYTES
local MAX_SKEW = 2 * 86400 -- issue date may be at most 2 days in the future (clock drift)
local ROLLBACK_TOLERANCE = 3600
local PATH = Env.ROOT .. "/license.json"

local secret = nil
local revoked = {}

local function loadSecret()
	if secret ~= nil then
		return secret
	end
	local bytes = Hash.fromHex(SECRET_HEX)
	secret = bytes or false
	return secret
end

function License.isConfigured()
	return loadSecret() ~= false
end

function License.isRequired()
	return REQUIRED == "1"
end

-- Test hooks ---------------------------------------------------------------------------------------------------

function License._setSecretHex(hex)
	secret = Hash.fromHex(hex) or false
end

function License._setRequired(flag)
	REQUIRED = flag and "1" or "0"
end

function License.setRevoked(list)
	revoked = {}
	for _, nonce in ipairs(list) do
		revoked[string.lower(nonce)] = true
	end
end

-- Parsing -------------------------------------------------------------------------------------------------------------

local function groupKey(raw)
	local parts = {}
	for i = 1, #raw, 5 do
		table.insert(parts, string.sub(raw, i, i + 4))
	end
	return "MM2H-" .. table.concat(parts, "-")
end

-- encode(mode, issued, value, nonceBytes) -> key. Used by tests; the real generator is tools/keygen.py.
function License.encode(mode, issued, value, nonce)
	assert(loadSecret(), "license secret not configured")
	local payload = string.pack(">BBI4I4", VERSION, mode, issued, value) .. nonce
	local mac = string.sub(Hash.hmacSha256(secret, payload), 1, MAC_BYTES)
	return groupKey(Hash.base32encode(payload .. mac))
end

-- parse(key) -> info|nil, err. Verifies structure and signature (not the expiry).
function License.parse(key)
	if type(key) ~= "string" then
		return nil, "key must be text"
	end
	if not loadSecret() then
		return nil, "this build has no license secret configured"
	end
	local body = string.match(string.upper(key), "^%s*MM2H[%-%s]*(.-)%s*$")
	if not body then
		return nil, "not a MM2 Hub key (expected MM2H-...)"
	end
	local bytes = Hash.base32decode(body, TOTAL_BYTES)
	if not bytes then
		return nil, "key contains invalid characters or is too short"
	end
	local payload = string.sub(bytes, 1, PAYLOAD_BYTES)
	local mac = string.sub(bytes, PAYLOAD_BYTES + 1, TOTAL_BYTES)
	local expected = string.sub(Hash.hmacSha256(secret, payload), 1, MAC_BYTES)
	if not Hash.equal(mac, expected) then
		return nil, "invalid key (signature mismatch)"
	end
	local version, mode, issued, value = string.unpack(">BBI4I4", payload)
	if version ~= VERSION then
		return nil, "unsupported key version " .. tostring(version)
	end
	if mode ~= 0 and mode ~= 1 then
		return nil, "unknown key mode"
	end
	local nonce = Hash.hex(string.sub(payload, 11, 14))
	if revoked[nonce] then
		return nil, "this key has been revoked"
	end
	return { version = version, mode = mode, issued = issued, value = value, nonce = nonce }
end

-- Time ----------------------------------------------------------------------------------------------------------------------

function License.now()
	local ok, t = pcall(function()
		return Services.Workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" and t > 1.6e9 then
		return math.floor(t)
	end
	return os.time()
end

function License.formatRemaining(seconds)
	if seconds <= 0 then
		return "expired"
	end
	local d = seconds // 86400
	local h = (seconds % 86400) // 3600
	local m = (seconds % 3600) // 60
	local s = seconds % 60
	if d > 0 then
		return string.format("%dd %dh %dm", d, h, m)
	elseif h > 0 then
		return string.format("%dh %dm %ds", h, m, s)
	end
	return string.format("%dm %ds", m, s)
end

-- Stored state --------------------------------------------------------------------------------------------------------------------

local function readState()
	local text = Env.read(PATH)
	if not text then
		return nil
	end
	local data = Json.decode(text)
	if type(data) ~= "table" or type(data.key) ~= "string" then
		return nil
	end
	return data
end

local function writeState(state)
	return Env.write(PATH, Json.encode(state))
end

-- evaluate(info, state, now) -> ok, result|err
local function evaluate(info, state, now)
	if info.issued - now > MAX_SKEW then
		return false, "key is not valid yet (device clock appears to be behind)"
	end
	if state and state.lastSeen and now < state.lastSeen - ROLLBACK_TOLERANCE then
		return false, "system clock was set back; refusing to run"
	end
	local expiresAt
	if info.mode == 0 then
		expiresAt = info.value
	else
		if not state or not state.activatedAt then
			return true, { mode = 1, needsActivation = true, duration = info.value }
		end
		expiresAt = state.activatedAt + info.value
	end
	if now >= expiresAt then
		return false, "key expired " .. License.formatRemaining(now - expiresAt + 1) .. " ago"
	end
	return true, { mode = info.mode, expiresAt = expiresAt, remaining = expiresAt - now }
end

-- check(key, now?) -> ok, result|err   (pure with respect to stored state except for reading it)
function License.check(key, now)
	local info, err = License.parse(key)
	if not info then
		return false, err
	end
	local state = readState()
	if state and state.key ~= key then
		state = nil
	end
	return evaluate(info, state, now or License.now())
end

-- activate(key, now?) -> ok, result|err. Persists the key; starts the clock for mode-1 keys.
function License.activate(key, now)
	now = now or License.now()
	local info, err = License.parse(key)
	if not info then
		return false, err
	end
	local state = readState()
	if state and state.key ~= key then
		state = nil
	end
	local ok, res = evaluate(info, state, now)
	if not ok then
		return false, res
	end
	state = state or { key = key }
	if info.mode == 1 and not state.activatedAt then
		state.activatedAt = now
		ok, res = evaluate(info, state, now)
	end
	state.lastSeen = math.max(state.lastSeen or 0, now)
	local wok, werr = writeState(state)
	if not wok then
		Logger.warn("License", "could not persist license: %s", tostring(werr))
	end
	return ok, res
end

-- verifyStored(now?) -> ok, result|err. Used at startup and by the periodic expiry check.
function License.verifyStored(now)
	now = now or License.now()
	local state = readState()
	if not state then
		return false, "no key activated"
	end
	local ok, res = License.check(state.key, now)
	if ok and not res.needsActivation then
		state.lastSeen = math.max(state.lastSeen or 0, now)
		writeState(state)
	end
	return ok, res
end

function License.storedKey()
	local s = readState()
	return s and s.key or nil
end

function License.clear()
	Env.delete(PATH)
	Env.write(PATH, "")
end

return License
