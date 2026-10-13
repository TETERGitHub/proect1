--!strict
-- core/Codec: base64 and FNV-1a 32-bit checksum. Pure functions, no Roblox APIs.
-- Used by Config for export strings and integrity checks.

local Codec = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DECODE: { [number]: number } = {}
for i = 1, #ALPHABET do
	DECODE[string.byte(ALPHABET, i)] = i - 1
end

function Codec.b64encode(data: string): string
	local out: { string } = {}
	local len = #data
	for i = 1, len, 3 do
		local b1 = string.byte(data, i)
		local b2 = string.byte(data, i + 1)
		local b3 = string.byte(data, i + 2)
		local n = b1 * 65536 + (b2 or 0) * 256 + (b3 or 0)
		local c1 = n // 262144
		local c2 = (n // 4096) % 64
		local c3 = (n // 64) % 64
		local c4 = n % 64
		out[#out + 1] = string.sub(ALPHABET, c1 + 1, c1 + 1)
		out[#out + 1] = string.sub(ALPHABET, c2 + 1, c2 + 1)
		out[#out + 1] = if b2 then string.sub(ALPHABET, c3 + 1, c3 + 1) else "="
		out[#out + 1] = if b3 then string.sub(ALPHABET, c4 + 1, c4 + 1) else "="
	end
	return table.concat(out)
end

-- Returns decoded string, or nil plus an error message for malformed input.
function Codec.b64decode(text: string): (string?, string?)
	local clean = string.gsub(text, "%s", "")
	if #clean % 4 ~= 0 then
		return nil, "base64 length is not a multiple of 4"
	end
	local out: { string } = {}
	for i = 1, #clean, 4 do
		local vals: { number } = {}
		local pad = 0
		for j = 0, 3 do
			local ch = string.byte(clean, i + j)
			if ch == 61 then -- '='
				if i + 4 <= #clean or j < 2 then
					return nil, "misplaced base64 padding"
				end
				pad += 1
				vals[#vals + 1] = 0
			else
				if pad > 0 then
					return nil, "data after base64 padding"
				end
				local v = DECODE[ch]
				if v == nil then
					return nil, "invalid base64 character at " .. tostring(i + j)
				end
				vals[#vals + 1] = v
			end
		end
		local n = vals[1] * 262144 + vals[2] * 4096 + vals[3] * 64 + vals[4]
		local b1 = n // 65536
		local b2 = (n // 256) % 256
		local b3 = n % 256
		out[#out + 1] = string.char(b1)
		if pad < 2 then
			out[#out + 1] = string.char(b2)
		end
		if pad < 1 then
			out[#out + 1] = string.char(b3)
		end
	end
	return table.concat(out), nil
end

-- FNV-1a 32-bit. Multiplication by the FNV prime (2^24 + 403) is split so every
-- intermediate value stays below 2^53 and is exact in double precision.
function Codec.fnv1a(data: string): string
	local h = 2166136261
	for i = 1, #data do
		h = bit32.bxor(h, string.byte(data, i))
		h = (h * 403 + (h % 256) * 16777216) % 4294967296
	end
	return string.format("%08x", h)
end

return Codec
