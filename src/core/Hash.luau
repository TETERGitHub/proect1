--!nonstrict
-- core/Hash: SHA-256, HMAC-SHA256 and Crockford base32 in pure Luau (bit32 only).
-- Cross-checked against Python's hashlib/hmac in tests/t_license.

local Hash = {}

local K: { number } = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function add(...: number): number
	local sum = 0
	for _, v in ipairs({ ... }) do
		sum += v
	end
	return sum % 4294967296
end

-- sha256(data) -> 32-byte binary string
function Hash.sha256(data: string): string
	local h0: number, h1: number, h2: number, h3: number = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
	local h4: number, h5: number, h6: number, h7: number = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

	local len = #data
	local padLen = (55 - len) % 64
	local bitLen = len * 8
	local padded = data .. "\128" .. string.rep("\0", padLen) .. string.pack(">I4I4", bitLen // 4294967296, bitLen % 4294967296)

	local w: { number } = {}
	for chunk = 1, #padded, 64 do
		for i = 0, 15 do
			w[i + 1] = (string.unpack(">I4", padded, chunk + i * 4)) :: number
		end
		for i = 17, 64 do
			local a, b = w[i - 15], w[i - 2]
			local s0 = bit32.bxor(bit32.rrotate(a, 7), bit32.rrotate(a, 18), bit32.rshift(a, 3))
			local s1 = bit32.bxor(bit32.rrotate(b, 17), bit32.rrotate(b, 19), bit32.rshift(b, 10))
			w[i] = add(w[i - 16], s0, w[i - 7], s1)
		end
		local a: number, b: number, c: number, d: number = h0, h1, h2, h3
		local e: number, f: number, g: number, h: number = h4, h5, h6, h7
		for i = 1, 64 do
			local S1 = bit32.bxor(bit32.rrotate(e, 6), bit32.rrotate(e, 11), bit32.rrotate(e, 25))
			local ch = bit32.bxor(bit32.band(e, f), bit32.band(bit32.bnot(e), g))
			local t1 = add(h, S1, ch, K[i], w[i])
			local S0 = bit32.bxor(bit32.rrotate(a, 2), bit32.rrotate(a, 13), bit32.rrotate(a, 22))
			local maj = bit32.bxor(bit32.band(a, b), bit32.band(a, c), bit32.band(b, c))
			local t2 = add(S0, maj)
			h, g, f, e, d, c, b, a = g, f, e, add(d, t1), c, b, a, add(t1, t2)
		end
		h0, h1, h2, h3 = add(h0, a), add(h1, b), add(h2, c), add(h3, d)
		h4, h5, h6, h7 = add(h4, e), add(h5, f), add(h6, g), add(h7, h)
	end
	return string.pack(">I4I4I4I4I4I4I4I4", h0, h1, h2, h3, h4, h5, h6, h7)
end

function Hash.hex(bytes: string): string
	return (string.gsub(bytes, ".", function(c)
		return string.format("%02x", string.byte(c))
	end))
end

function Hash.fromHex(hex: string): string?
	if #hex % 2 ~= 0 or string.find(hex, "[^%x]") then
		return nil
	end
	return (string.gsub(hex, "%x%x", function(h)
		return string.char(tonumber(h, 16) :: number)
	end))
end

-- hmacSha256(key, message) -> 32-byte binary string
function Hash.hmacSha256(key: string, message: string): string
	if #key > 64 then
		key = Hash.sha256(key)
	end
	key = key .. string.rep("\0", 64 - #key)
	local inner = string.gsub(key, ".", function(c)
		return string.char(bit32.bxor(string.byte(c), 0x36))
	end)
	local outer = string.gsub(key, ".", function(c)
		return string.char(bit32.bxor(string.byte(c), 0x5c))
	end)
	return Hash.sha256(outer .. Hash.sha256(inner .. message))
end

-- constant-time-ish comparison
function Hash.equal(a: string, b: string): boolean
	if #a ~= #b then
		return false
	end
	local diff = 0
	for i = 1, #a do
		diff = bit32.bor(diff, bit32.bxor(string.byte(a, i), string.byte(b, i)))
	end
	return diff == 0
end

-- Crockford base32 (no I, L, O, U) ----------------------------------------------------------------

local B32 = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
local B32_DECODE: { [string]: number } = {}
for i = 1, #B32 do
	B32_DECODE[string.sub(B32, i, i)] = i - 1
end

function Hash.base32encode(data: string): string
	local out: { string } = {}
	local bits, acc = 0, 0
	for i = 1, #data do
		acc = acc * 256 + string.byte(data, i)
		bits += 8
		while bits >= 5 do
			local shift = 2 ^ (bits - 5)
			local v = acc // shift
			acc = acc % shift
			bits -= 5
			out[#out + 1] = string.sub(B32, v + 1, v + 1)
		end
	end
	if bits > 0 then
		local v = acc * 2 ^ (5 - bits)
		out[#out + 1] = string.sub(B32, v + 1, v + 1)
	end
	return table.concat(out)
end

-- base32decode(text, byteCount) -> binary string|nil. Lenient: ignores '-' and spaces, maps O->0, I/L->1.
function Hash.base32decode(text: string, byteCount: number): string?
	local clean = string.upper((string.gsub(text, "[%s%-]", "")))
	clean = string.gsub(clean, "O", "0")
	clean = string.gsub(clean, "[IL]", "1")
	local out: { string } = {}
	local bits, acc = 0, 0
	for i = 1, #clean do
		local v = B32_DECODE[string.sub(clean, i, i)]
		if v == nil then
			return nil
		end
		local vv: number = v
		acc = acc * 32 + vv
		bits += 5
		if bits >= 8 then
			local shift = 2 ^ (bits - 8)
			out[#out + 1] = string.char(acc // shift)
			acc = acc % shift
			bits -= 8
		end
	end
	-- strict canonical form: exact length and zero padding bits, so each key has one valid spelling
	local s = table.concat(out)
	if #s ~= byteCount or acc ~= 0 then
		return nil
	end
	return s
end

return Hash
