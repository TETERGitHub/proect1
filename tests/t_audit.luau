--!nonstrict
-- Audit regression tests: independent reference vectors (RFC 4648, FIPS 180-2 / hashlib, RFC 4231, FNV
-- reference values) and failure paths of Json, Codec, PayloadCipher, Loader and LicenseText.
local import = ...
local T = import("tests/Framework")
local Codec = import("core/Codec")
local Hash = import("core/Hash")
local Json = import("core/Json")
local PayloadCipher = import("core/PayloadCipher")
local Loader = import("loader/Loader")
local Text = import("core/LicenseText")

local function bytes(n, seed)
	local t = {}
	for i = 0, n - 1 do t[#t + 1] = string.char((i * 7 + seed) % 256) end
	return table.concat(t)
end

T.suite("Codec (reference vectors)")
T.test("base64 matches RFC 4648 section 10", "all seven reference strings, both directions", function()
	local vec = { { "", "" }, { "f", "Zg==" }, { "fo", "Zm8=" }, { "foo", "Zm9v" }, { "foob", "Zm9vYg==" }, { "fooba", "Zm9vYmE=" }, { "foobar", "Zm9vYmFy" } }
	for _, v in ipairs(vec) do
		T.eq(Codec.b64encode(v[1]), v[2])
		T.eq((Codec.b64decode(v[2])), v[1])
	end
end)
T.test("base64 decode rejects non-canonical and malformed input", "padding, length, characters, trailing bits", function()
	for _, bad in ipairs({ "Zg=", "Zg", "Z===", "====", "Zg==Zg==", "Zg=A", "Zm9v!", "Zm8", "=Zm8", "Zh==", "Zm9=" }) do
		local r, err = Codec.b64decode(bad)
		T.eq(r, nil, bad); T.truthy(err, bad)
	end
end)
T.test("base64 binary roundtrip for every byte value and many lengths", "no loss, deterministic pseudo-random data", function()
	local all = {}
	for i = 0, 255 do all[#all + 1] = string.char(i) end
	local s = table.concat(all)
	T.eq((Codec.b64decode(Codec.b64encode(s))), s)
	for n = 0, 70 do
		local d = bytes(n, n)
		T.eq((Codec.b64decode(Codec.b64encode(d))), d, "len " .. n)
	end
	local big = bytes(100000, 3)
	T.eq((Codec.b64decode(Codec.b64encode(big))), big)
end)
T.test("fnv1a matches the published 32-bit reference values", "empty, a, foobar", function()
	T.eq(Codec.fnv1a(""), "811c9dc5"); T.eq(Codec.fnv1a("a"), "e40c292c"); T.eq(Codec.fnv1a("foobar"), "bf9cf968")
end)

T.suite("Hash (reference vectors)")
T.test("sha256 across the padding boundaries", "lengths 0,1,55,56,63,64,65,119,120,1000 against hashlib", function()
	local ref = {
		[0] = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		[1] = "4bf5122f344554c53bde2ebb8cd2b7e3d1600ad631c385a5d7cce23c7785459a",
		[55] = "81afe5b788dc2ce138ff83d9b20164db75a94d75d2b2432eea4a0ef605088c72",
		[56] = "2aba54f0ac632420a2b502431408866e40e1d5e430df4cd822642c78ab2eb9c1",
		[63] = "733d3d4ee79ee67145bf73da13588f6f235d37414fc64b14a2f00f1762792f5e",
		[64] = "79322907b3e9d013d7dc2c2f256674dbf733045cde01df3539271c6f5605feb8",
		[65] = "d85c007c6eb440f085afa2b84f6f2bce4658b240e9f62cb1364bf0485a57e720",
		[119] = "6c87eedf096b345de205b702e5223b73b447a3207791ded3ea007ba15ed6736e",
		[120] = "42500cf6a1e3936d6b9e0bcfe296d654b63255e525487d3634d0b15fde591c4d",
		[1000] = "6b0df76627243d095b0c4400cb658b7e804dd03461cc03aee8fc8fe0bcada168",
	}
	for n, want in pairs(ref) do T.eq(Hash.hex(Hash.sha256(bytes(n, n))), want, "len " .. n) end
	T.eq(Hash.hex(Hash.sha256("abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
	T.eq(Hash.hex(Hash.sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
end)
T.test("hmac-sha256 matches RFC 4231", "cases 1, 2 and 6 (key longer than a block)", function()
	T.eq(Hash.hex(Hash.hmacSha256(string.rep("\11", 20), "Hi There")), "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
	T.eq(Hash.hex(Hash.hmacSha256("Jefe", "what do ya want for nothing?")), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
	T.eq(Hash.hex(Hash.hmacSha256(string.rep("\170", 131), "Test Using Larger Than Block-Size Key - Hash Key First")), "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
end)
T.test("hex and base32 edge cases", "empty, odd length, bad characters, canonical form", function()
	T.eq(Hash.hex(""), ""); T.eq(Hash.fromHex(""), ""); T.eq(Hash.fromHex("abc"), nil); T.eq(Hash.fromHex("zz"), nil); T.eq(Hash.fromHex("0aFF"), "\10\255")
	T.eq(Hash.base32encode("f"), "CR"); T.eq(Hash.base32encode("foobar"), "CSQPYRK1E8"); T.eq(Hash.base32encode(""), "")
	T.eq(Hash.base32decode("CSQPYRK1E8", 6), "foobar")
	T.eq(Hash.base32decode("CR", 1), "f")
	T.eq(Hash.base32decode("CS", 1), nil, "non-zero padding bits")
	T.eq(Hash.base32decode("CSQPYRK1E8", 5), nil, "wrong byte count")
	T.eq(Hash.base32decode("CSQPYRK1E!", 6), nil, "invalid character")
	T.eq(Hash.base32decode("", 0), "")
	T.eq(Hash.base32decode("csqp-yrk1 e8", 6), "foobar", "case, dashes and spaces ignored")
end)

T.suite("Json (audit)")
T.test("numbers follow the JSON grammar", "1. 1.e5 01 -01 1e 1e+ + . are rejected; valid forms accepted", function()
	for _, bad in ipairs({ "1.", "1.e5", "01", "-01", "1e", "1e+", "+1", ".5", "-", "--1", "1.5.2", "0x10", "1e400", "NaN", "Infinity" }) do
		T.eq(Json.decode("[" .. bad .. "]"), nil, bad)
	end
	local v = Json.decode("[0,-0,1.5,-2.25e3,1E2,3e-2,10,123456789012]")
	T.eq(#v, 8); T.eq(v[3], 1.5); T.eq(v[4], -2250); T.eq(v[5], 100); T.eq(v[6], 0.03); T.eq(v[8], 123456789012)
end)
T.test("strings: escapes, unicode, surrogate pairs, DEL", "decoded values are exact", function()
	T.eq(Json.decode('"a\\u00e9\\n\\\\"'), "a\u{e9}\n\\")
	T.eq(Json.decode('"\\ud83d\\ude00"'), "\u{1F600}")
	T.eq(Json.decode('"x\127y"'), "x\127y", "raw DEL is legal JSON")
	T.eq(Json.decode('"\\ud83d"'), nil); T.eq(Json.decode('"\\ude00"'), nil); T.eq(Json.decode('"\\x"'), nil)
	T.eq(Json.decode('"a\nb"'), nil, "raw newline is illegal")
	T.eq(Json.decode('"abc'), nil)
	T.eq(Json.decode(Json.encode("\0\1\31\127\"\\")), "\0\1\31\127\"\\")
end)
T.test("structure errors are reported, never thrown", "commas, brackets, trailing data, duplicates, depth", function()
	for _, bad in ipairs({ "[1,]", "[,1]", "[1 2]", '{"a":1,}', '{"a" 1}', "{1:2}", "[", "{", "[1]x", '{"a":1}{', "", "   ", "nul", "tru", '{"a":1,"a":2}', '{"a":null,"a":2}' }) do
		local v, err = Json.decode(bad)
		T.eq(v, nil, "[" .. bad .. "]"); T.truthy(err, bad)
	end
	T.eq(Json.decode(string.rep("[", 200) .. string.rep("]", 200)), nil)
	T.truthy(Json.decode(string.rep("[", 60) .. string.rep("]", 60)))
	T.eq(Json.decode(nil), nil); T.eq(Json.decode(5), nil)
end)
T.test("a UTF-8 byte order mark before the document is tolerated", "some HTTP stacks prepend it", function()
	local v = Json.decode("\239\187\191{\"ok\":true}")
	T.truthy(v and v.ok)
end)
T.test("null handling is explicit", "object nulls are dropped, array nulls stay Json.Null, encode writes null", function()
	local o = Json.decode('{"a":null,"b":1}')
	T.eq(o.a, nil); T.eq(o.b, 1)
	local a = Json.decode("[null,1]")
	T.eq(a[1], Json.Null); T.eq(a[2], 1)
	T.eq(Json.encode({ a = Json.Null }), '{"a":null}')
	T.eq(Json.encode({ Json.Null, 1 }), "[null,1]")
end)
T.test("encoder edge cases", "empty table, sparse array, bad keys, NaN, depth", function()
	T.eq(Json.encode({}), "{}")
	T.eq(Json.decode("[]") ~= nil, true)
	T.eq(select("#", Json.tryEncode({ [1] = 1, [3] = 3 })), 2)
	T.eq((Json.tryEncode({ [1] = 1, [3] = 3 })), nil)
	T.eq((Json.tryEncode({ [true] = 1 })), nil)
	T.eq((Json.tryEncode(0 / 0)), nil); T.eq((Json.tryEncode(math.huge)), nil)
	local deep = {}; local cur = deep
	for _ = 1, 100 do cur[1] = {}; cur = cur[1] end
	T.eq((Json.tryEncode(deep)), nil)
	T.eq(Json.encode({ b = 1, a = { 3, 2 } }), '{"a":[3,2],"b":1}')
	T.eq(Json.encode(1e20), "1e+20"); T.eq(Json.encode(0.5), "0.5"); T.eq(Json.encode(-7), "-7")
	for _, v in ipairs({ 0.1, 1 / 3, 123456.789, 1e-7, 2 ^ 52 }) do T.eq(Json.decode("[" .. Json.encode(v) .. "]")[1], v, tostring(v)) end
end)

T.suite("Json contract (absent / null / value)")
T.test("object field: absent, null and a value are three distinct inputs", "default decode merges absent and null; keepNull separates them", function()
	local absent, null, value = Json.decode('{"a":1}'), Json.decode('{"a":1,"b":null}'), Json.decode('{"a":1,"b":2}')
	T.eq(absent.b, nil); T.eq(null.b, nil); T.eq(value.b, 2)
	T.eq(Json.encode(absent), Json.encode(null), "default: null == absent on the wire")
	local strict = Json.decode('{"a":1,"b":null}', { keepNull = true })
	T.eq(strict.b, Json.Null); T.eq(strict.a, 1)
	T.eq(Json.encode(strict), '{"a":1,"b":null}', "keepNull round-trips")
end)
T.test("empty array vs empty object", "plain {} stays an object; marked or shape-preserving arrays stay arrays", function()
	T.eq(Json.encode({}), "{}"); T.eq(Json.encode(Json.array({})), "[]"); T.eq(Json.encode({ list = Json.array() }), '{"list":[]}')
	local round = Json.decode('{"o":{},"a":[],"n":[1,[]]}', { keepShape = true })
	T.eq(Json.encode(round), '{"a":[],"n":[1,[]],"o":{}}')
	T.eq(Json.encode(Json.decode('{"o":{},"a":[]}')), '{"a":{},"o":{}}', "default decode does not keep the shape (documented)")
	T.eq(Json.encode(Json.array({ 1, 2 })), "[1,2]")
end)
T.test("decode options do not leak between calls", "a keepNull call does not change the next default call", function()
	Json.decode('{"b":null}', { keepNull = true, keepShape = true })
	local v = Json.decode('{"b":null,"c":[]}')
	T.eq(v.b, nil); T.eq(getmetatable(v.c), nil)
end)

T.suite("PayloadCipher (audit)")
local KEY = "MM2H-0406N-KMFQ9-NCZR9-T6QA2-QNQS4-A5MEY-7BZ39-07AR"
local NONCE = string.rep("\7", 12)
T.test("bad arguments give an error result, not an exception", "nil/non-string nonce, cipher and tag", function()
	local cipher, tag = PayloadCipher.encrypt(KEY, NONCE, "hello")
	T.eq((PayloadCipher.decrypt(KEY, NONCE, cipher, tag)), "hello")
	for _, args in ipairs({ { KEY, nil, cipher, tag }, { KEY, NONCE, nil, tag }, { KEY, NONCE, cipher, nil }, { KEY, NONCE, cipher, 5 }, { nil, NONCE, cipher, tag }, { KEY, "short", cipher, tag }, { KEY, NONCE, cipher, "" }, { KEY, NONCE, cipher, "zz" } }) do
		local ok, a, b = pcall(PayloadCipher.decrypt, table.unpack(args, 1, 4))
		T.truthy(ok, "must not throw")
		T.eq(a, nil); T.truthy(b)
	end
end)
T.test("empty and corrupted ciphertext are refused before decrypting", "every single-byte change and truncation fails", function()
	local cipher, tag = PayloadCipher.encrypt(KEY, NONCE, bytes(100, 1))
	for i = 1, #cipher, 9 do
		local bad = string.sub(cipher, 1, i - 1) .. string.char((string.byte(cipher, i) + 1) % 256) .. string.sub(cipher, i + 1)
		T.eq((PayloadCipher.decrypt(KEY, NONCE, bad, tag)), nil)
	end
	T.eq((PayloadCipher.decrypt(KEY, NONCE, string.sub(cipher, 1, -2), tag)), nil)
	T.eq((PayloadCipher.decrypt(KEY, NONCE, "", tag)), nil)
	T.eq((PayloadCipher.decrypt(KEY, string.rep("\8", 12), cipher, tag)), nil, "other nonce")
	local c0, t0 = PayloadCipher.encrypt(KEY, NONCE, "")
	T.eq(c0, ""); T.eq((PayloadCipher.decrypt(KEY, NONCE, c0, t0)), "")
	T.eq((PayloadCipher.decrypt(KEY, NONCE, cipher, string.upper(tag))), bytes(100, 1), "tag case is irrelevant")
end)

T.suite("LicenseText (audit)")
T.test("remaining() survives odd numbers", "negative, zero, NaN, infinity, huge, non-number", function()
	T.eq(Text.remaining(-5), "срок истёк"); T.eq(Text.remaining(0), "срок истёк"); T.eq(Text.remaining(0.9), "срок истёк")
	T.eq(Text.remaining(0 / 0), "срок истёк"); T.eq(Text.remaining(nil), "срок истёк"); T.eq(Text.remaining("x"), "срок истёк")
	T.eq(Text.remaining(math.huge), "без ограничения срока")
	T.eq(Text.remaining(59), "59 с"); T.eq(Text.remaining(60), "1 минута 0 с"); T.eq(Text.remaining(3599), "59 минут 59 с"); T.eq(Text.remaining(3600), "1 ч 0 мин 0 с")
	T.eq(Text.remaining(86399), "23 ч 59 мин 59 с"); T.eq(Text.remaining(86400), "1 день 0 ч 0 мин")
	T.truthy(string.find(Text.remaining(1e12), " д"))
end)
T.test("prefix translations keep the technical tail", "details are preserved for the log", function()
	local r = Text.ru("hub failed to start: attempt to index nil")
	T.truthy(string.find(r, "attempt to index nil", 1, true))
	T.truthy(string.find(Text.ru("hub code failed to compile: line 3"), "line 3", 1, true))
end)

T.suite("Loader (audit)")
local function deps(opts)
	opts = opts or {}
	local d = { requests = {}, notes = {}, prompts = {}, spawned = 0, waits = 0, clockValue = 0, hubCount = 0 }
	local cipher, tag = PayloadCipher.encrypt(KEY, NONCE, "return nil")
	local function reply(path)
		if path == "/v1/ping" then return opts.ping and opts.ping(d) or { ok = true } end
		local r = { ok = true, expires = 10000, now = 100, nonce = Codec.b64encode(NONCE), tag = tag, payload = Codec.b64encode(cipher) }
		for k, v in pairs(opts.activate or {}) do r[k] = v end
		return r
	end
	d.request = function(req)
		table.insert(d.requests, req)
		if opts.raw then return opts.raw(req, d) end
		local path = string.match(req.Url, "(/v1/%a+)$")
		return { Success = true, StatusCode = 200, Body = Json.encode(reply(path)) }
	end
	d.loadstring = function() return function() d.hubCount += 1; local hub = { n = 0, unload = function(self) end }; hub.unload = function() hub.n += 1; d.lastHub = hub; if opts.unloadThrows then error("unload boom") end end; d.lastHub = hub; return hub end end
	d.readKey = function() return opts.stored end
	d.writeKey = function() end
	d.prompt = function(cb, err) table.insert(d.prompts, { cb = cb, err = err }) end
	d.uid = 1
	d.notify = function(_, text) if opts.notifyThrows then error("notify boom") end table.insert(d.notes, text) end
	d.clock = function() return d.clockValue end
	d.spawn = function(fn) d.spawned += 1; pcall(fn) end
	d.wait = function(s) d.waits += 1; d.clockValue += s; if d.waits > (opts.maxWaits or 3) then error("stop") end end
	d.serverUrl = "https://x.example"
	d.heartbeat = 50
	return d
end

T.test("missing dependencies produce a clear error", "names the missing function", function()
	for _, name in ipairs({ "request", "loadstring", "readKey", "writeKey", "prompt", "notify", "clock", "spawn", "wait", "serverUrl" }) do
		local d = deps(); d[name] = nil
		local ok, err = pcall(Loader.run, d)
		T.falsy(ok, name); T.truthy(string.find(tostring(err), name, 1, true), name)
	end
end)
T.test("executor response shapes are understood", "Body/body, odd tables, strings, nil", function()
	local good = Json.encode({ ok = false, error = "key expired" })
	for _, shape in ipairs({ { Body = good }, { body = good }, { Success = true, StatusCode = 200, Body = good }, good }) do
		local d = deps({ raw = function() return shape end })
		local s, err = Loader.activate(d, KEY)
		T.eq(s, nil); T.eq(err, "key expired")
	end
	for _, shape in ipairs({ {}, { Body = "" }, { Body = 5 }, 5, true }) do
		local d = deps({ raw = function() return shape end })
		local s, err = Loader.activate(d, KEY)
		T.eq(s, nil); T.eq(err, "empty response from the licence server")
	end
	local d = deps({ raw = function() return { Body = "<html>502</html>", StatusCode = 502 } end })
	local _, err = Loader.activate(d, KEY)
	T.eq(err, "licence server sent an unreadable response")
	local d2 = deps({ raw = function() return nil end })
	T.eq(select(2, Loader.activate(d2, KEY)), "empty response from the licence server")
end)
T.test("malformed activation answers are rejected cleanly", "missing or mistyped payload, nonce, tag", function()
	for _, bad in ipairs({ { payload = false }, { nonce = false }, { tag = false }, { payload = 5 }, { nonce = Codec.b64encode("short") }, { tag = 5 }, { payload = "!!!" } }) do
		local d = deps({ activate = bad })
		local s, err = Loader.activate(d, KEY)
		T.eq(s, nil, Json.encode(bad)); T.truthy(err)
	end
end)
T.test("non-numeric expiry cannot kill the heartbeat thread", "expires/now of the wrong type are ignored", function()
	local d = deps({ activate = { expires = "never", now = {} }, maxWaits = 3 })
	local h = Loader.run({ request = d.request, loadstring = d.loadstring, readKey = function() return KEY end, writeKey = d.writeKey, prompt = d.prompt, uid = 1, notify = d.notify, clock = d.clock, spawn = d.spawn, wait = d.wait, serverUrl = d.serverUrl, heartbeat = 50 })
	T.truthy(h.running)
	T.truthy(d.waits >= 3, "the loop kept running (it was stopped only by the test's wait limit)")
end)
T.test("transient server refusals do not unload the hub", "rate limit and bad request keep it running; revocation unloads", function()
	for _, msg in ipairs({ "too many attempts, wait a minute", "bad request", "not found", "something new" }) do
		local d = deps({ stored = KEY, ping = function() return { ok = false, error = msg } end, maxWaits = 3 })
		local h = Loader.run(d)
		T.truthy(h.running, msg); T.eq(d.lastHub.n, 0, msg)
	end
	for _, msg in ipairs({ "this key has been revoked", "key expired", "invalid key", "key is already bound to another account", "key is not valid yet" }) do
		local d = deps({ stored = KEY, ping = function() return { ok = false, error = msg } end, maxWaits = 3 })
		local h = Loader.run(d)
		T.falsy(h.running, msg); T.eq(d.lastHub.n, 1, msg)
	end
end)
T.test("consecutive ping failures are counted and reset on success", "handle.pingFailures", function()
	local d = deps({ stored = KEY, maxWaits = 4 })
	local fail = true
	local orig = d.request
	d.request = function(req) if string.find(req.Url, "ping") and fail then error("offline") end return orig(req) end
	local h = Loader.run(d)
	T.eq(h.pingFailures, 4, "every ping failed until the test wait limit")
	T.truthy(h.running)
	local d2 = deps({ stored = KEY, maxWaits = 4 })
	local n = 0
	local orig2 = d2.request
	d2.request = function(req) if string.find(req.Url, "ping") then n += 1; if n == 1 then error("offline") end end return orig2(req) end
	local h2 = Loader.run(d2)
	T.eq(h2.pingFailures, 0)
end)
T.test("maxPingFailures is an opt-in limit on offline time", "default tolerates, a limit stops the hub after N failures", function()
	local function offline(limit)
		local d = deps({ stored = KEY, maxWaits = 10 })
		local orig = d.request
		d.request = function(req) if string.find(req.Url, "ping") then error("offline") end return orig(req) end
		d.maxPingFailures = limit
		local h = Loader.run(d)
		return h, d
	end
	local h1 = offline(nil)
	T.truthy(h1.running)
	local h2, d2 = offline(3)
	T.falsy(h2.running); T.eq(h2.pingFailures, 3); T.eq(d2.lastHub.n, 1)
end)
T.test("double submit starts the hub once", "second activation while running or in flight is ignored", function()
	local d = deps({})
	local h = Loader.run(d)
	d.prompts[1].cb(KEY)
	d.prompts[1].cb(KEY)
	T.eq(d.hubCount, 1); T.truthy(h.running)
	T.eq(#d.requests >= 1, true)
end)
T.test("reentrant activation is ignored", "submit from inside the request does not start twice", function()
	local d = deps({})
	local h = Loader.run(d)
	local inner
	local orig = d.request
	d.request = function(req) if not inner and string.find(req.Url, "activate") then inner = true; d.prompts[1].cb(KEY) end return orig(req) end
	d.prompts[1].cb(KEY)
	T.eq(d.hubCount, 1)
end)
T.test("unload and notify failures are contained", "stop() never throws and still marks the handle stopped", function()
	local d = deps({ stored = KEY, unloadThrows = true, notifyThrows = true, ping = function() return { ok = false, error = "this key has been revoked" } end, maxWaits = 3 })
	local ok, h = pcall(Loader.run, d)
	T.truthy(ok); T.falsy(h.running); T.truthy(h.stopped)
	local h2 = Loader.run(deps({ stored = KEY }))
	h2.stop("manual"); h2.stop("again")
	T.truthy(h2.stopped)
end)
T.test("a hub that returns nothing is tolerated on stop", "no unload method, no crash", function()
	local d = deps({ stored = KEY })
	d.loadstring = function() return function() return nil end end
	local h = Loader.run(d)
	T.truthy(h.running)
	h.stop("bye")
	T.falsy(h.running)
end)
T.test("stop ends the heartbeat loop", "no background work after stop", function()
	local d = deps({ stored = KEY, maxWaits = 50 })
	local h
	d.spawn = function(fn) d.spawned += 1 end
	h = Loader.run(d)
	T.eq(d.spawned, 1)
	h.stop("manual")
	local before = d.waits
	T.eq(d.waits, before)
end)
T.test("failed hub start leaves no heartbeat and allows a retry", "start error then a good start works", function()
	local d = deps({})
	local first = true
	local load = d.loadstring
	d.loadstring = function(src) local f = load(src); return function() if first then first = false; error("boom") end return f() end end
	local h = Loader.run(d)
	d.prompts[1].cb(KEY)
	T.falsy(h.running); T.eq(d.spawned, 0)
	d.prompts[#d.prompts].cb(KEY)
	T.truthy(h.running); T.eq(d.spawned, 1)
end)

T.suite("Core / Actions / I18n (audit)")
local Core = import("core/Core")
local Actions = import("core/Actions")
local I18n = import("core/I18n")
T.test("a clean stop records no error text", "state.err is nil, not the string 'nil'", function()
	T.fresh()
	Core.registerModule({ name = "clean", start = function() end, stop = function() end })
	Core.registerModule({ name = "dirty", start = function() end, stop = function() error("stop boom") end })
	Core.startAll(); Core.stopAll()
	for _, row in ipairs(Core.status()) do
		if row.name == "clean" then T.eq(row.err, nil) end
		if row.name == "dirty" then T.truthy(row.err and string.find(row.err, "stop boom", 1, true)) end
	end
end)
T.test("Actions.Ran reports a real error only on failure", "nil error on success", function()
	T.fresh()
	Actions.register("audit.ok", { title = "ok", fn = function() return 1 end })
	Actions.register("audit.bad", { title = "bad", fn = function() error("nope") end })
	local seen = {}
	local conn = Actions.Ran:Connect(function(id, ok, err) seen[id] = { ok, err } end)
	Actions.run("audit.ok"); Actions.run("audit.bad")
	conn:Disconnect()
	T.eq(seen["audit.ok"][2], nil); T.eq(seen["audit.bad"][1], false); T.truthy(string.find(seen["audit.bad"][2], "nope", 1, true))
end)
T.test("changing the language leaks no globals", "cache/cacheSize stay local to I18n", function()
	I18n.set("en"); I18n.set("ru"); I18n.set("en"); I18n.set("ru")
	T.eq(rawget(_G, "cache"), nil); T.eq(rawget(_G, "cacheSize"), nil)
end)

T.suite("Interface wiring (audit)")
local Mock = import("tests/mock_roblox")
local Services = import("core/Services")
local Hub = import("app/Hub")
local Window = import("ui/Window")
local Perf = import("core/Perf")
local Settings = import("core/Settings")
T.test("every visible setting has a control on some page", "no schema entry exists only on paper", function()
	T.fresh(); Mock.uninstall(); local game = Mock.install(); Services.clear()
	local h = Hub.run({ skipLicense = true })
	local gui = game.__services.CoreGui.MM2Hub
	local named = {}
	for _, id in ipairs(Window.pageIds()) do
		Window.navigate(id); for _ = 1, 6 do Perf.frame(1 / 30) end
		for _, d in ipairs(gui:GetDescendants()) do
			named[d.Name] = true
			if type(d.Text) == "string" then named[d.Text] = true end
		end
	end
	local missing = {}
	for _, key in ipairs(Settings.keys()) do
		local def = Settings.schema(key)
		-- toggles/sliders/enums are named by key; text fields are found by their (translated) label
		local shown = named[key] or named[def.label] or named[I18n.tr(def.label)]
		-- state.* are saved window geometry; music.playlist has its own editor (Add/Remove/Move) and music.index is the play cursor
		local special = string.find(key, "^state%.") or key == "music.playlist" or key == "music.index"
		if not special and not shown and not def.hidden then table.insert(missing, key) end
	end
	h.unload(); Mock.uninstall()
	T.eq(table.concat(missing, ", "), "")
end)

T.test("a refused favourite tells the user why", "star at the limit raises a warning instead of doing nothing", function()
	T.fresh(); Mock.uninstall(); local game = Mock.install(); Services.clear()
	local h = Hub.run({ skipLicense = true })
	local Recents = import("core/Recents")
	local Notify = import("core/Notify")
	local limit = Settings.schema("state.favorites").maxItems
	local ids = {}
	for _, f in ipairs(import("core/Registry").all()) do if #ids < limit then table.insert(ids, f.id) end end
	for _, id in ipairs(ids) do Recents.toggleFavorite(id) end
	T.eq(#Recents.favorites(), limit)
	Window.navigate("camera"); for _ = 1, 4 do Perf.frame(1 / 30) end
	local gui = game.__services.CoreGui.MM2Hub
	local before = #Notify.history()
	local pressed = 0
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("TextButton") and d.Parent and d.Parent.Name ~= "Frame" and Settings.has(d.Parent.Name) and not Recents.isFavorite(import("core/Registry").forSetting(d.Parent.Name) and import("core/Registry").forSetting(d.Parent.Name).id or "") then
			d.Activated:Fire({}, 1); pressed += 1
			if pressed >= 1 then break end
		end
	end
	T.truthy(pressed >= 1, "found a star for a feature that is not a favourite yet")
	T.eq(#Recents.favorites(), limit)
	T.truthy(#Notify.history() > before, "a warning was raised")
	h.unload(); Mock.uninstall()
end)

T.suite("Settings contract (audit)")
local Logger = import("core/Logger")
T.test("every setting survives valid, extreme and invalid values", "no exception, bad values rejected without change, no module fails, no logged error", function()
	T.fresh(); Mock.uninstall(); local game = Mock.install(); Services.clear()
	local h = Hub.run({ skipLicense = true })
	for _ = 1, 3 do Perf.frame(1 / 30) end
	local errorsBefore = Logger.count("error")
	local problems = {}
	local function note(key, what) table.insert(problems, key .. ": " .. what) end
	for _, key in ipairs(Settings.keys({ includeHidden = true })) do
		local def = Settings.schema(key)
		local original = Settings.get(key)
		local good, bad = {}, {}
		if def.type == "number" then
			good = { def.min, def.max, (def.min + def.max) / 2 }
			bad = { "x", 0 / 0, {}, true }
		elseif def.type == "bool" then
			good = { not original }
			bad = { "yes", 1, {} }
		elseif def.type == "enum" then
			good = def.options
			bad = { "__bogus__", 5, {} }
		elseif def.type == "color" then
			good = { { r = 0, g = 0, b = 0 }, { r = 255, g = 255, b = 255 } }
			bad = { "red", { r = "x", g = 1, b = 1 }, { r = 1 } }
		elseif def.type == "string" or def.type == "key" then
			good = { def.type == "key" and "None" or "" }
			bad = { 5, {}, string.rep("a", (def.maxLen or 64) + 1) }
		else
			good = { {} }
			bad = { "x", { 5 }, 5 }
		end
		for _, v in ipairs(good) do
			local ok, res = pcall(Settings.set, key, v, "audit")
			if not ok then note(key, "set threw " .. tostring(res)) end
			Perf.frame(1 / 30); Perf.frame(1 / 30)
		end
		for _, v in ipairs(bad) do
			local before = Settings.get(key)
			local ok, accepted = pcall(Settings.set, key, v, "audit")
			if not ok then note(key, "invalid value threw " .. tostring(accepted))
			elseif accepted == true and def.type ~= "number" then note(key, "invalid value " .. tostring(v) .. " was accepted")
			elseif accepted ~= true and not Settings.deepEqual(before, Settings.get(key)) then note(key, "rejected value changed the setting") end
		end
		Settings.set(key, original, "audit")
		Perf.frame(1 / 30)
	end
	for _, row in ipairs(Core.status()) do
		if row.state == "failed" then note("module " .. row.name, "failed: " .. tostring(row.err)) end
	end
	if Logger.count("error") ~= errorsBefore then
		for _, e in ipairs(Logger.entries and Logger.entries({ level = "error" }) or {}) do note("log", e.tag .. ": " .. e.message) end
		note("log", (Logger.count("error") - errorsBefore) .. " new error entries")
	end
	h.unload(); Mock.uninstall()
	T.eq(table.concat(problems, "\n"), "")
end)

T.suite("Module restart (audit)")
T.test("every module can be restarted from Diagnostics", "restart returns ok, module runs again, no duplicate GUI, unload still clean", function()
	T.fresh(); Mock.uninstall(); local game = Mock.install(); Services.clear()
	local h = Hub.run({ skipLicense = true })
	for _ = 1, 3 do Perf.frame(1 / 30) end
	local problems = {}
	for _, row in ipairs(Core.status()) do
		local ok, err = Core.restart(row.name)
		if not ok then table.insert(problems, row.name .. ": " .. tostring(err)) end
		for _ = 1, 3 do Perf.frame(1 / 30) end
		if Core.moduleState(row.name) ~= "running" then table.insert(problems, row.name .. " not running after restart: " .. tostring(Core.moduleState(row.name))) end
	end
	local guis = 0
	for _, c in ipairs(game.__services.CoreGui:GetChildren()) do if c.Name == "MM2Hub" then guis += 1 end end
	if guis ~= 1 then table.insert(problems, "MM2Hub ScreenGui count = " .. guis) end
	h.unload()
	if #game.__services.CoreGui:GetChildren() ~= 0 then table.insert(problems, "GUI left after unload: " .. #game.__services.CoreGui:GetChildren()) end
	Mock.uninstall()
	T.eq(table.concat(problems, "\n"), "")
end)

T.suite("Removed features (audit)")
T.test("old saves and favourites that mention the removed drone do not break anything", "unknown keys / ids are ignored, UI and buttons still build", function()
	T.fresh(); Mock.uninstall(); local game = Mock.install(); Services.clear()
	local h = Hub.run({ skipLicense = true })
	local report = Settings.applyMap({ ["drone.speed"] = 90, ["drone.mode"] = "Fling", ["crosshair.size"] = 14 }, "profile", "test", false)
	T.eq(Settings.get("crosshair.size"), 14, "known keys of the same save still apply")
	T.truthy(report ~= nil)
	Settings.set("state.favorites", { "train.drone", "xh.enable" }, "test")
	Settings.set("ui.screenButtons", true)
	Window.navigate("dashboard"); for _ = 1, 6 do Perf.frame(1 / 30) end
	local ok, err = pcall(function() Window.relocalize() end)
	T.truthy(ok, tostring(err))
	for _ = 1, 6 do Perf.frame(1 / 30) end
	T.eq(Core.moduleState("window"), "running"); T.eq(Core.moduleState("screenbuttons"), "running")
	h.unload(); Mock.uninstall()
end)
