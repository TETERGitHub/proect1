--!nonstrict
-- core/PayloadCipher: decrypts the hub payload delivered by the licence server.
--   k          = SHA256("MM2HUB-PAYLOAD" .. canonicalKey .. nonce)
--   keystream  = SHA256(k .. u32be(counter)) blocks of 32 bytes
--   cipher     = plaintext XOR keystream
--   tag        = first 16 bytes of HMAC-SHA256(k, nonce .. cipher)   (checked before decrypting)
-- The key never leaves the machine; the server derives the same k from the key it just verified.
-- Used by the loader (which contains NO signing secret) and by tests against Python vectors.

local import = ...
local Hash = import("core/Hash")

local PayloadCipher = {}

local B32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

local function group(raw)
	local parts = {}
	for i = 1, #raw, 5 do
		table.insert(parts, string.sub(raw, i, i + 4))
	end
	return "MM2H-" .. table.concat(parts, "-")
end

-- canonicalKey(text) -> "MM2H-XXXXX-..." | nil. Structural only (no signature check, no secret needed).
function PayloadCipher.canonicalKey(text)
	if type(text) ~= "string" then
		return nil
	end
	local body = string.match(string.upper(text), "^%s*MM2H[%-%s]*(.-)%s*$")
	if not body then
		return nil
	end
	local bytes = Hash.base32decode(body, 24)
	if not bytes then
		return nil
	end
	return group(Hash.base32encode(bytes))
end

function PayloadCipher.deriveKey(canonical, nonce)
	return Hash.sha256("MM2HUB-PAYLOAD" .. canonical .. nonce)
end

local function keystreamXor(k, data)
	local out = {}
	local n = #data
	local counter = 0
	local pos = 1
	while pos <= n do
		local ks = Hash.sha256(k .. string.pack(">I4", counter))
		local last = math.min(pos + 31, n)
		local len = last - pos + 1
		local a = { string.byte(data, pos, last) }
		local b = { string.byte(ks, 1, len) }
		for i = 1, len do
			a[i] = bit32.bxor(a[i], b[i])
		end
		out[#out + 1] = string.char(table.unpack(a, 1, len))
		counter += 1
		pos += 32
	end
	return table.concat(out)
end

-- decrypt(canonicalKey, nonce, cipher, tagHex) -> plaintext | nil, err
function PayloadCipher.decrypt(canonical, nonce, cipher, tagHex)
	local k = PayloadCipher.deriveKey(canonical, nonce)
	local tag = string.sub(Hash.hex(Hash.hmacSha256(k, nonce .. cipher)), 1, 32)
	if not Hash.equal(tag, string.lower(tagHex or "")) then
		return nil, "payload authentication failed (wrong key or tampered data)"
	end
	return keystreamXor(k, cipher)
end

-- encrypt(): same construction; used by tests to prove the roundtrip and by tooling in Luau if ever needed.
function PayloadCipher.encrypt(canonical, nonce, plaintext)
	local k = PayloadCipher.deriveKey(canonical, nonce)
	local cipher = keystreamXor(k, plaintext)
	local tag = string.sub(Hash.hex(Hash.hmacSha256(k, nonce .. cipher)), 1, 32)
	return cipher, tag
end

return PayloadCipher
