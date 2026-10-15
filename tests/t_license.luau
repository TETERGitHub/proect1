--!nonstrict
-- Cross-implementation tests: keys and hashes below were produced by Python (hashlib/hmac and
-- tools/keygen.py with the fixed test secret) and must be accepted by the Luau verifier.
local import = ...
local T = import("tests/Framework")
local Hash = import("core/Hash")
local License = import("core/License")
local Env = import("core/Env")

local SECRET = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
local ISSUED = 1767225600 -- 2026-01-01 00:00:00 UTC
local K_ABS_46D = "MM2H-0406J-NDS01-MS61P-0H9WC-YX3J1-A27ZD-05GPY-PSZ0"  -- until 2026-02-16 12:00 UTC
local K_ABS_1Y = "MM2H-0406J-NDS01-NKDV4-004SN-YZGG7-QAR4S-TPSTD-EMSG"   -- until 2027-01-01
local K_ACT_30D = "MM2H-040PJ-NDS00-02F38-0X2GH-RTFKS-HYBGE-X8KBA-1YSR"  -- 30 days from activation
local K_ABS_CAL = "MM2H-0406J-NDS01-MR5HB-JFVG3-MY8CB-44RGB-SXNJV-5QB0"  -- until 2026-02-04 04:05:06 UTC

local function setup()
	T.fresh()
	License._setSecretHex(SECRET)
	License.setRevoked({})
	License._setRequired(false)
end

T.suite("Hash")
T.test("sha256 matches Python hashlib", "known digests incl. multi-block", function()
	T.eq(Hash.hex(Hash.sha256("")), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
	T.eq(Hash.hex(Hash.sha256("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
	T.eq(Hash.hex(Hash.sha256(string.rep("a", 1000))), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
end)
T.test("hmac-sha256 matches Python hmac", "short and over-block-size keys", function()
	T.eq(Hash.hex(Hash.hmacSha256("key", "The quick brown fox jumps over the lazy dog")), "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
	T.eq(Hash.hex(Hash.hmacSha256(string.rep("k", 100), "msg")), "bd56a1782c2830e8abc6ed866a57a1230661e650b84c62f7ee3accc5fa5af491")
end)
T.test("base32 roundtrip and lenient decode", "no data loss; O/I/L mapped; separators ignored", function()
	local data = ""
	for i = 0, 23 do data ..= string.char((i * 37 + 11) % 256) end
	local enc = Hash.base32encode(data)
	T.eq(#enc, 39); T.eq(Hash.base32decode(enc, 24), data)
	local a = Hash.base32decode("1111-OOOO", 5)
	T.truthy(a ~= nil, "decodes"); T.eq(a, Hash.base32decode("llll 0000", 5))
	T.eq(Hash.base32decode(enc .. "0", 24), nil)
	T.eq(Hash.base32decode("@@@@", 1), nil)
end)

T.suite("License")
T.test("python-generated absolute key verifies", "valid before expiry, remaining computed", function()
	setup()
	local ok, res = License.check(K_ABS_46D, ISSUED + 3600)
	T.truthy(ok, tostring(res)); T.eq(res.mode, 0); T.eq(res.expiresAt, 1771243200); T.eq(res.remaining, 1771243200 - ISSUED - 3600)
end)
T.test("calendar-aware durations", "1 month from Jan 1 + 15 d + 12 h and 1 year", function()
	setup()
	T.eq(select(2, License.check(K_ABS_46D, ISSUED)).expiresAt, 1771243200) -- 2026-02-16 12:00 UTC
	T.eq(select(2, License.check(K_ABS_1Y, ISSUED)).expiresAt, 1798761600) -- 2027-01-01 00:00 UTC
	T.eq(select(2, License.check(K_ABS_CAL, ISSUED)).expiresAt, 1770177906) -- 2026-02-04 04:05:06 UTC
end)
T.test("expiry is exact to the second", "valid at T-1, expired at T", function()
	setup()
	local exp = 1771243200
	T.truthy((License.check(K_ABS_46D, exp - 1)))
	local ok, err = License.check(K_ABS_46D, exp)
	T.falsy(ok); T.truthy(string.find(err, "expired"))
end)
T.test("lenient input", "lowercase, spaces, missing dashes accepted", function()
	setup()
	T.truthy((License.check(string.lower(K_ABS_46D), ISSUED)))
	T.truthy((License.check("  " .. string.gsub(K_ABS_46D, "-", " ") .. "  ", ISSUED)))
	T.truthy((License.check(string.gsub(K_ABS_46D, "-", ""), ISSUED)))
end)
T.test("tampered keys rejected", "every single-character change fails", function()
	setup()
	local body = string.sub(K_ABS_46D, 6)
	local rejected, total = 0, 0
	for i = 1, #body do
		local c = string.sub(body, i, i)
		if c ~= "-" then
			local repl = (c == "0") and "1" or "0"
			local key = "MM2H-" .. string.sub(body, 1, i - 1) .. repl .. string.sub(body, i + 1)
			total += 1
			if not License.check(key, ISSUED) then rejected += 1 end
		end
	end
	T.eq(rejected, total); return rejected .. "/" .. total .. " mutations rejected"
end)
T.test("wrong secret rejects", "key from another secret is invalid", function()
	setup()
	License._setSecretHex(string.rep("ab", 32))
	local ok, err = License.check(K_ABS_46D, ISSUED)
	T.falsy(ok); T.truthy(string.find(err, "signature"))
end)
T.test("garbage rejected", "wrong prefix, short, bad characters, non-text", function()
	setup()
	for _, bad in ipairs({ "", "hello", "MM2H-", "MM2H-0000", "XXXX-0406J-NDS01", "MM2H-@@@@@-@@@@@-@@@@@-@@@@@-@@@@@-@@@@@-@@@@@-@@@@", 42 }) do
		local ok, err = License.check(bad, ISSUED)
		T.falsy(ok, tostring(bad)); T.truthy(err)
	end
end)
T.test("no secret configured", "clear error instead of crash", function()
	setup(); License._setSecretHex("zz")
	local ok, err = License.check(K_ABS_46D, ISSUED)
	T.falsy(ok); T.truthy(string.find(err, "no license secret"))
	T.falsy(License.isConfigured())
end)
T.test("activation-mode key counts from first activation", "30 days after activation, persisted", function()
	setup()
	local ok, res = License.check(K_ACT_30D, ISSUED)
	T.truthy(ok); T.truthy(res.needsActivation)
	local t0 = ISSUED + 5 * 86400
	ok, res = License.activate(K_ACT_30D, t0)
	T.truthy(ok, tostring(res)); T.eq(res.expiresAt, t0 + 30 * 86400)
	ok, res = License.verifyStored(t0 + 29 * 86400); T.truthy(ok); T.eq(res.remaining, 86400)
	ok = License.verifyStored(t0 + 30 * 86400); T.falsy(ok)
end)
T.test("reactivating does not restart the clock", "activatedAt stays fixed", function()
	setup()
	local t0 = ISSUED
	License.activate(K_ACT_30D, t0)
	local ok, res = License.activate(K_ACT_30D, t0 + 10 * 86400)
	T.truthy(ok); T.eq(res.expiresAt, t0 + 30 * 86400)
end)
T.test("clock rollback detected", "time set back after use is refused", function()
	setup()
	License.activate(K_ABS_1Y, ISSUED + 100 * 86400)
	local ok, err = License.verifyStored(ISSUED + 10 * 86400)
	T.falsy(ok); T.truthy(string.find(err, "clock"))
	T.truthy((License.verifyStored(ISSUED + 100 * 86400 + 60)))
end)
T.test("key issued in the future refused", "device clock far behind", function()
	setup()
	local ok, err = License.check(K_ABS_1Y, ISSUED - 10 * 86400)
	T.falsy(ok); T.truthy(string.find(err, "clock"))
	T.truthy((License.check(K_ABS_1Y, ISSUED - 3600)))
end)
T.test("revoked keys refused", "nonce on the revocation list", function()
	setup()
	local info = License.parse(K_ABS_46D)
	License.setRevoked({ string.upper(info.nonce) })
	local ok, err = License.check(K_ABS_46D, ISSUED)
	T.falsy(ok); T.truthy(string.find(err, "revoked"))
end)
T.test("stored key survives restart", "verifyStored reads the persisted key", function()
	setup()
	T.falsy((License.verifyStored(ISSUED)))
	License.activate(K_ABS_1Y, ISSUED)
	T.eq(License.storedKey(), K_ABS_1Y)
	T.truthy((License.verifyStored(ISSUED + 60)))
	License.clear(); T.falsy((License.verifyStored(ISSUED + 60)))
end)
T.test("encode matches python byte for byte", "Luau-built key equals Python-built key", function()
	setup()
	local nonceHex = License.parse(K_ABS_46D).nonce
	local nonce = Hash.fromHex(nonceHex)
	T.eq(License.encode(0, ISSUED, 1771243200, nonce), K_ABS_46D)
end)
T.test("forever key never expires", "value 2^32-1 = no time limit, even past 2106", function()
	setup()
	local nonce = Hash.fromHex(License.parse(K_ABS_46D).nonce)
	local key = License.encode(0, ISSUED, 4294967295, nonce)
	for _, t in ipairs({ ISSUED, 4102444800, 4294967295, 5000000000 }) do
		local ok, res = License.check(key, t)
		T.truthy(ok, tostring(res)); T.eq(res.remaining, math.huge); T.truthy(res.forever)
	end
	T.eq(import("core/LicenseText").remaining(math.huge), "без ограничения срока")
end)
T.test("remaining time formatting", "d/h/m and expired", function()
	T.eq(License.formatRemaining(90061), "1d 1h 1m"); T.eq(License.formatRemaining(3725), "1h 2m 5s")
	T.eq(License.formatRemaining(61), "1m 1s"); T.eq(License.formatRemaining(0), "expired")
end)

local PayloadCipher = import("core/PayloadCipher")
T.suite("PayloadCipher")
local PY_NONCE = Hash.fromHex("000102030405060708090a0b")
local PY_CIPHER = Hash.fromHex("e1bcfcfe05fa5e84b0ff57bdb9993593305bd54d9eac4f4c63eaf49366dd00420a6dc1aac2037cf7050a78bec40a9b5407a43b4c9a6f2746316a8c407e239d77e461908121e605153b5dba9f737ffb4de9b8e960")
local PY_TAG = "622d54e6590d2b7996e9a5524febf0a1"
local PY_PLAIN = string.rep("print('hello from the hub')\n", 3)
T.test("decrypts Python-encrypted payload", "plaintext identical to what Python encrypted", function()
	local canon = PayloadCipher.canonicalKey(string.lower(string.gsub(K_ABS_46D, "-", " ")))
	T.eq(canon, K_ABS_46D)
	local plain, err = PayloadCipher.decrypt(canon, PY_NONCE, PY_CIPHER, PY_TAG)
	T.eq(err, nil); T.eq(plain, PY_PLAIN)
end)
T.test("luau encrypt equals python ciphertext", "byte-identical construction", function()
	local c, tag = PayloadCipher.encrypt(K_ABS_46D, PY_NONCE, PY_PLAIN)
	T.eq(c, PY_CIPHER); T.eq(tag, PY_TAG)
end)
T.test("wrong key or tampering is rejected", "tag mismatch before any decryption", function()
	local other = PayloadCipher.canonicalKey(K_ABS_1Y)
	T.eq((PayloadCipher.decrypt(other, PY_NONCE, PY_CIPHER, PY_TAG)), nil)
	local bad = string.sub(PY_CIPHER, 1, 10) .. "X" .. string.sub(PY_CIPHER, 12)
	local plain, err = PayloadCipher.decrypt(K_ABS_46D, PY_NONCE, bad, PY_TAG)
	T.eq(plain, nil); T.truthy(string.find(err, "authentication"))
	T.eq((PayloadCipher.decrypt(K_ABS_46D, PY_NONCE, PY_CIPHER, string.rep("0", 32))), nil)
end)
T.test("roundtrip over odd sizes", "0, 1, 31, 32, 33, 1000 bytes", function()
	for _, n in ipairs({ 0, 1, 31, 32, 33, 1000 }) do
		local data = ""
		for i = 1, n do data ..= string.char((i * 7) % 256) end
		local c, tag = PayloadCipher.encrypt(K_ABS_1Y, PY_NONCE, data)
		T.eq(#c, n); T.eq(PayloadCipher.decrypt(K_ABS_1Y, PY_NONCE, c, tag), data, "n=" .. n)
	end
end)
T.test("canonical form rejects junk", "non-keys give nil", function()
	for _, bad in ipairs({ "", "abc", "MM2H-", "MM2H-0000", 5 }) do T.eq(PayloadCipher.canonicalKey(bad), nil, tostring(bad)) end
end)

local Loader = import("loader/Loader")
local Json = import("core/Json")
local Codec = import("core/Codec")

T.suite("Loader")
local function okResponse(overrides)
	local r = { ok = true, expires = 1000, now = 100, nonce = Codec.b64encode(PY_NONCE), tag = PY_TAG, payload = Codec.b64encode(PY_CIPHER) }
	for k, v in pairs(overrides or {}) do r[k] = v end
	return r
end
local function makeDeps(opts)
	opts = opts or {}
	local d = { log = {}, clockValue = 0, waits = 0, notes = {}, prompts = {}, written = nil, requests = {} }
	d.request = function(req)
		table.insert(d.requests, req)
		if opts.throw then error("network down") end
		local path = string.match(req.Url, "(/v1/%a+)$")
		local body = (path == "/v1/ping") and (opts.pingReply and opts.pingReply(#d.requests) or { ok = true }) or (opts.reply or okResponse())
		return { Success = true, StatusCode = 200, Body = Json.encode(body) }
	end
	d.loadstring = function(src)
		d.source = src
		if opts.compileError then return nil, "syntax error" end
		d.hub = { unloaded = false, unload = function(self) end }
		local hub = { unloadCalls = 0 }
		hub.unload = function() hub.unloadCalls += 1 end
		d.hubObj = hub
		return function() if opts.startError then error("boom") end return hub end
	end
	d.readKey = function() return opts.stored end
	d.writeKey = function(t) d.written = t end
	d.prompt = function(cb, err) table.insert(d.prompts, { cb = cb, err = err }) end
	d.uid = 12345
	d.notify = function(title, text) table.insert(d.notes, text) end
	d.clock = function() return d.clockValue end
	d.spawn = function(fn) local ok = pcall(fn) end
	d.wait = function(s)
		d.waits += 1
		d.clockValue += s
		if d.waits > (opts.maxWaits or 4) then error("stop test loop") end
	end
	d.serverUrl = "https://licence.example"
	d.heartbeat = 100
	return d
end

T.test("stored key activates and runs the decrypted hub", "payload authenticated, decrypted, executed, key remembered", function()
	local d = makeDeps({ stored = K_ABS_46D, pingReply = function() return { ok = true } end })
	local h = Loader.run(d)
	T.truthy(h.running); T.eq(d.source, PY_PLAIN); T.eq(d.written, K_ABS_46D)
	local req = Json.decode(d.requests[1].Body)
	T.eq(req.uid, 12345); T.eq(req.key, K_ABS_46D)
	T.eq(d.requests[1].Url, "https://licence.example/v1/activate")
end)
T.test("no stored key opens the prompt and then runs", "prompt -> submit -> running", function()
	local d = makeDeps({})
	local h = Loader.run(d)
	T.eq(#d.prompts, 1); T.falsy(h.running)
	d.prompts[1].cb(string.lower(K_ABS_46D))
	T.truthy(h.running); T.eq(d.source, PY_PLAIN)
end)
T.test("refused key reopens the prompt with the server message", "error shown, nothing executed", function()
	local d = makeDeps({ reply = { ok = false, error = "key expired" } })
	local h = Loader.run(d)
	d.prompts[1].cb(K_ABS_46D)
	T.falsy(h.running); T.eq(d.source, nil); T.eq(d.prompts[2].err, "key expired")
end)
T.test("garbage key never contacts the server", "rejected locally", function()
	local d = makeDeps({})
	local h = Loader.run(d)
	d.prompts[1].cb("hello")
	T.eq(#d.requests, 0); T.truthy(d.prompts[2].err)
end)
T.test("tampered or mismatched payload is rejected", "authentication failure, hub not run", function()
	local bad = Codec.b64encode(string.sub(PY_CIPHER, 1, 5) .. "Z" .. string.sub(PY_CIPHER, 7))
	local d = makeDeps({ stored = K_ABS_46D, reply = okResponse({ payload = bad }) })
	local h = Loader.run(d)
	T.falsy(h.running); T.eq(d.source, nil)
	local d2 = makeDeps({ stored = K_ABS_1Y })  -- right payload, wrong key
	T.falsy(Loader.run(d2).running)
	local d3 = makeDeps({ stored = K_ABS_46D, reply = okResponse({ nonce = "AAAA" }) })
	T.falsy(Loader.run(d3).running)
end)
T.test("network failure is reported", "no crash, prompt with message", function()
	local d = makeDeps({ stored = K_ABS_46D, throw = true })
	local h = Loader.run(d)
	T.falsy(h.running); T.truthy(string.find(d.prompts[1].err, "reach"))
end)
T.test("compile and startup errors are contained", "reported, not thrown", function()
	local d = makeDeps({ stored = K_ABS_46D, compileError = true })
	T.falsy(Loader.run(d).running)
	local d2 = makeDeps({ stored = K_ABS_46D, startError = true })
	local h2 = Loader.run(d2)
	T.falsy(h2.running); T.truthy(string.find(d2.notes[1], "failed to start"))
end)
T.test("heartbeat unloads the hub when the term ends", "local expiry enforcement", function()
	local d = makeDeps({ stored = K_ABS_46D, reply = okResponse({ expires = 250, now = 100 }), maxWaits = 10 })
	local h = Loader.run(d)
	T.falsy(h.running); T.eq(d.hubObj.unloadCalls, 1); T.truthy(string.find(d.notes[#d.notes], "expired"))
end)
T.test("heartbeat unloads when the server revokes", "ping refusal stops the hub", function()
	local d = makeDeps({ stored = K_ABS_46D, reply = okResponse({ expires = 1e9, now = 100 }), pingReply = function(n) return n >= 3 and { ok = false, error = "this key has been revoked" } or { ok = true } end, maxWaits = 10 })
	local h = Loader.run(d)
	T.falsy(h.running); T.eq(d.hubObj.unloadCalls, 1); T.truthy(string.find(d.notes[#d.notes], "revoked"))
end)
T.test("temporary network loss does not unload", "pings fail, hub keeps running until the term ends", function()
	local flaky = makeDeps({ stored = K_ABS_46D, reply = okResponse({ expires = 1e9, now = 100 }), maxWaits = 3 })
	flaky.request = (function(orig)
		return function(req)
			if string.find(req.Url, "ping") then error("offline") end
			return orig(req)
		end
	end)(flaky.request)
	local h = Loader.run(flaky)
	T.truthy(h.running); T.eq(flaky.hubObj.unloadCalls, 0)
end)

T.suite("Loader diagnostics")
T.test("loader reports each stage and the exact failing step", "log lines name the step; no secrets in the log", function()
	local d = makeDeps({ stored = K_ABS_46D, pingReply = function() return { ok = true } end })
	local lines = {}
	d.log = function(t) table.insert(lines, t) end
	Loader.run(d)
	local text = table.concat(lines, "\n")
	for _, step in ipairs({ "step 1/5", "step 2/5", "step 3/5", "step 4/5", "step 5/5 hub started" }) do T.truthy(string.find(text, step, 1, true), step) end
	T.falsy(string.find(text, K_ABS_46D, 1, true), "the key must never be logged")
	local bad = makeDeps({ stored = K_ABS_46D, reply = { ok = false, error = "key expired" } })
	local l2 = {}; bad.log = function(t) table.insert(l2, t) end
	Loader.run(bad)
	T.truthy(string.find(table.concat(l2, "\n"), "step 2/5 server refused the key: key expired", 1, true))
	local off = makeDeps({ stored = K_ABS_46D, throw = true })
	local l3 = {}; off.log = function(t) table.insert(l3, t) end
	Loader.run(off)
	T.truthy(string.find(table.concat(l3, "\n"), "step 2/5 FAILED: could not reach", 1, true))
	local broken = makeDeps({ stored = K_ABS_46D, compileError = true })
	local l4 = {}; broken.log = function(t) table.insert(l4, t) end
	Loader.run(broken)
	T.truthy(string.find(table.concat(l4, "\n"), "step 4/5 FAILED", 1, true))
end)
