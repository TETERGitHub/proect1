--!nonstrict
-- core/Json: deterministic JSON encoder (sorted object keys) and strict decoder.
-- Deterministic output is required so checksums over settings stay stable.
-- Depends on: nothing (does not use HttpService, so it is unit-testable).

-- CONTRACT (client <-> server, pinned by tests/t_audit):
--   * object field absent  == object field null  by default: decode drops `"k": null`, encode skips nil fields. The
--     licence server treats a missing and a null `uid` identically, and Config files never contain null.
--     Pass { keepNull = true } to decode to see the difference (the field then holds Json.Null).
--   * array elements keep null as Json.Null (positions must not shift).
--   * an empty Lua table encodes as `{}`. Json.array(t) marks a table as an array so an empty one encodes as `[]`;
--     decode with { keepShape = true } marks every decoded array, so decode -> encode round-trips the shape.
--   * encode is deterministic (sorted keys) because Config checksums are taken over its output.

local Json = {}

Json.Null = setmetatable({}, { __tostring = function() return "null" end })

local ARRAY = {}

-- Json.array(t) -> t. Marks t so it is always written as a JSON array, even when empty.
function Json.array(t)
	return setmetatable(t or {}, ARRAY)
end

local MAX_DEPTH = 64

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function escapeString(s)
	return '"' .. string.gsub(s, '[%c"\\]', function(c)
		return ESCAPES[c] or string.format("\\u%04x", string.byte(c))
	end) .. '"'
end

local function isArray(t)
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
			return false
		end
		n += 1
	end
	return n == #t
end

local function encodeValue(v, out, depth)
	if depth > MAX_DEPTH then
		error("JSON encode: nesting too deep")
	end
	local t = type(v)
	if v == nil or v == Json.Null then
		out[#out + 1] = "null"
	elseif t == "boolean" then
		out[#out + 1] = v and "true" or "false"
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			error("JSON encode: NaN/Infinity not representable")
		end
		if v % 1 == 0 and math.abs(v) < 1e15 then
			out[#out + 1] = string.format("%d", v)
		else
			-- shortest representation that reads back as the same double (0.35 stays "0.35")
			local text = string.format("%.15g", v)
			if tonumber(text) ~= v then
				text = string.format("%.16g", v)
				if tonumber(text) ~= v then
					text = string.format("%.17g", v)
				end
			end
			out[#out + 1] = text
		end
	elseif t == "string" then
		out[#out + 1] = escapeString(v)
	elseif t == "table" then
		if next(v) == nil then
			out[#out + 1] = getmetatable(v) == ARRAY and "[]" or "{}"
		elseif isArray(v) then
			out[#out + 1] = "["
			for i = 1, #v do
				if i > 1 then
					out[#out + 1] = ","
				end
				encodeValue(v[i], out, depth + 1)
			end
			out[#out + 1] = "]"
		else
			local keys = {}
			for k in pairs(v) do
				if type(k) ~= "string" then
					error("JSON encode: object keys must be strings, got " .. type(k))
				end
				keys[#keys + 1] = k
			end
			table.sort(keys)
			out[#out + 1] = "{"
			for i, k in ipairs(keys) do
				if i > 1 then
					out[#out + 1] = ","
				end
				out[#out + 1] = escapeString(k)
				out[#out + 1] = ":"
				encodeValue(v[k], out, depth + 1)
			end
			out[#out + 1] = "}"
		end
	else
		error("JSON encode: unsupported type " .. t)
	end
end

-- Json.encode(value) -> string. Throws on unsupported values; use Json.tryEncode for pcall form.
function Json.encode(value)
	local out = {}
	encodeValue(value, out, 0)
	return table.concat(out)
end

function Json.tryEncode(value)
	local ok, res = pcall(Json.encode, value)
	if ok then
		return res, nil
	end
	return nil, tostring(res)
end

-- Decoder -------------------------------------------------------------------

local function fail(pos, msg)
	error({ pos = pos, msg = msg }, 0)
end

local function skip(s, i)
	local _, e = string.find(s, "^[ \t\r\n]*", i)
	return (e or i - 1) + 1
end

local parseValue

local KEEP_NULL, KEEP_SHAPE = false, false -- set per decode() call

local function parseString(s, i)
	-- s[i] == '"'
	local out = {}
	local j = i + 1
	while true do
		local c = string.sub(s, j, j)
		if c == "" then
			fail(j, "unterminated string")
		elseif c == '"' then
			return table.concat(out), j + 1
		elseif c == "\\" then
			local n = string.sub(s, j + 1, j + 1)
			local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
			if map[n] then
				out[#out + 1] = map[n]
				j += 2
			elseif n == "u" then
				local hex = string.match(s, "^%x%x%x%x", j + 2)
				if not hex then
					fail(j, "bad \\u escape")
				end
				local cp = tonumber(hex, 16)
				j += 6
				if cp >= 0xD800 and cp <= 0xDBFF then
					local lo = string.match(s, "^\\u(%x%x%x%x)", j)
					local lov = lo and tonumber(lo, 16)
					if lov and lov >= 0xDC00 and lov <= 0xDFFF then
						cp = 0x10000 + (cp - 0xD800) * 0x400 + (lov - 0xDC00)
						j += 6
					else
						fail(j, "unpaired surrogate")
					end
				elseif cp >= 0xDC00 and cp <= 0xDFFF then
					fail(j, "unpaired surrogate")
				end
				out[#out + 1] = utf8.char(cp)
			else
				fail(j, "bad escape")
			end
		elseif string.byte(c) < 32 then
			fail(j, "control character in string")
		else
			local run = string.match(s, '^[^"\\\0-\31]+', j)
			out[#out + 1] = run
			j += #run
		end
	end
end

local function parseNumber(s, i)
	-- strict JSON grammar: -? (0 | [1-9]d*) (. d+)? ([eE] [+-]? d+)?
	local text = string.match(s, "^-?%d+", i)
	if not text then
		fail(i, "bad number")
	end
	if string.match(text, "^-?0%d") then
		fail(i, "leading zero in number")
	end
	local stop = i + #text
	local frac = string.match(s, "^%.%d+", stop)
	if frac then
		text ..= frac
		stop += #frac
	elseif string.sub(s, stop, stop) == "." then
		fail(i, "digits required after the decimal point")
	end
	local exp = string.match(s, "^[eE][+-]?%d+", stop)
	if exp then
		text ..= exp
		stop += #exp
	elseif string.match(s, "^[eE]", stop) then
		fail(i, "digits required in the exponent")
	end
	local n = tonumber(text)
	if not n or n ~= n or n == math.huge or n == -math.huge then
		fail(i, "number out of range")
	end
	return n, stop
end

function parseValue(s, i, depth)
	if depth > MAX_DEPTH then
		fail(i, "nesting too deep")
	end
	i = skip(s, i)
	local c = string.sub(s, i, i)
	if c == "{" then
		local obj, seen = {}, {}
		i = skip(s, i + 1)
		if string.sub(s, i, i) == "}" then
			return obj, i + 1
		end
		while true do
			i = skip(s, i)
			if string.sub(s, i, i) ~= '"' then
				fail(i, "expected object key")
			end
			local key
			key, i = parseString(s, i)
			i = skip(s, i)
			if string.sub(s, i, i) ~= ":" then
				fail(i, "expected ':'")
			end
			local value
			value, i = parseValue(s, i + 1, depth + 1)
			if seen[key] then
				fail(i, "duplicate key '" .. key .. "'")
			end
			seen[key] = true
			if value ~= Json.Null or KEEP_NULL then
				obj[key] = value
			end
			i = skip(s, i)
			local d = string.sub(s, i, i)
			if d == "," then
				i += 1
			elseif d == "}" then
				return obj, i + 1
			else
				fail(i, "expected ',' or '}'")
			end
		end
	elseif c == "[" then
		local arr = KEEP_SHAPE and Json.array({}) or {}
		i = skip(s, i + 1)
		if string.sub(s, i, i) == "]" then
			return arr, i + 1
		end
		while true do
			local value
			value, i = parseValue(s, i, depth + 1)
			arr[#arr + 1] = value
			i = skip(s, i)
			local d = string.sub(s, i, i)
			if d == "," then
				i += 1
			elseif d == "]" then
				return arr, i + 1
			else
				fail(i, "expected ',' or ']'")
			end
		end
	elseif c == '"' then
		return parseString(s, i)
	elseif c == "t" and string.sub(s, i, i + 3) == "true" then
		return true, i + 4
	elseif c == "f" and string.sub(s, i, i + 4) == "false" then
		return false, i + 5
	elseif c == "n" and string.sub(s, i, i + 3) == "null" then
		return Json.Null, i + 4
	elseif c == "-" or string.match(c, "%d") then
		return parseNumber(s, i)
	end
	fail(i, "unexpected character '" .. c .. "'")
end

-- Json.decode(text) -> value|nil, err|nil. Never throws.
function Json.decode(text, opts)
	if type(text) ~= "string" then
		return nil, "input is not a string"
	end
	KEEP_NULL = type(opts) == "table" and opts.keepNull == true
	KEEP_SHAPE = type(opts) == "table" and opts.keepShape == true
	if string.sub(text, 1, 3) == "\239\187\191" then
		text = string.sub(text, 4) -- UTF-8 byte order mark
	end
	local ok, value, nextPos = pcall(parseValue, text, 1, 0)
	if not ok then
		local e = value
		if type(e) == "table" then
			return nil, string.format("JSON error at %d: %s", e.pos, e.msg)
		end
		return nil, tostring(e)
	end
	local rest = skip(text, nextPos)
	if rest <= #text then
		return nil, string.format("JSON error at %d: trailing data", rest)
	end
	if value == Json.Null then
		return nil, "top-level null"
	end
	return value, nil
end

return Json
