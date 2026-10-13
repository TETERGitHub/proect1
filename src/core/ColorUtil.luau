--!strict
-- core/ColorUtil: pure colour maths (RGB 0-255 <-> HSV, hex, blending). No Roblox APIs.

local ColorUtil = {}

export type RGB = { r: number, g: number, b: number }

local function clamp(n: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, n))
end

-- toHSV(r,g,b 0-255) -> h 0-1, s 0-1, v 0-1
function ColorUtil.toHSV(r: number, g: number, b: number): (number, number, number)
	local rf, gf, bf = r / 255, g / 255, b / 255
	local max = math.max(rf, gf, bf)
	local min = math.min(rf, gf, bf)
	local d = max - min
	local h = 0
	if d > 0 then
		if max == rf then
			h = ((gf - bf) / d) % 6
		elseif max == gf then
			h = (bf - rf) / d + 2
		else
			h = (rf - gf) / d + 4
		end
		h /= 6
	end
	local s = max == 0 and 0 or d / max
	return h, s, max
end

-- fromHSV(h,s,v 0-1) -> r,g,b integers 0-255
function ColorUtil.fromHSV(h: number, s: number, v: number): (number, number, number)
	h = (h % 1) * 6
	s = clamp(s, 0, 1)
	v = clamp(v, 0, 1)
	local c = v * s
	local x = c * (1 - math.abs(h % 2 - 1))
	local m = v - c
	local r, g, b
	if h < 1 then
		r, g, b = c, x, 0
	elseif h < 2 then
		r, g, b = x, c, 0
	elseif h < 3 then
		r, g, b = 0, c, x
	elseif h < 4 then
		r, g, b = 0, x, c
	elseif h < 5 then
		r, g, b = x, 0, c
	else
		r, g, b = c, 0, x
	end
	return math.floor((r + m) * 255 + 0.5), math.floor((g + m) * 255 + 0.5), math.floor((b + m) * 255 + 0.5)
end

function ColorUtil.toHex(c: RGB): string
	return string.format("#%02X%02X%02X", c.r, c.g, c.b)
end

-- fromHex("#RRGGBB" | "RRGGBB" | "#RGB") -> RGB|nil
function ColorUtil.fromHex(text: string): RGB?
	local hex = string.match(text, "^%s*#?(%x+)%s*$")
	if not hex then
		return nil
	end
	if #hex == 3 then
		hex = string.gsub(hex, ".", function(ch)
			return ch .. ch
		end)
	end
	if #hex ~= 6 then
		return nil
	end
	return {
		r = tonumber(string.sub(hex, 1, 2), 16) :: number,
		g = tonumber(string.sub(hex, 3, 4), 16) :: number,
		b = tonumber(string.sub(hex, 5, 6), 16) :: number,
	}
end

-- mix(a, b, t) -> RGB (t=0 gives a)
function ColorUtil.mix(a: RGB, b: RGB, t: number): RGB
	t = clamp(t, 0, 1)
	return {
		r = math.floor(a.r + (b.r - a.r) * t + 0.5),
		g = math.floor(a.g + (b.g - a.g) * t + 0.5),
		b = math.floor(a.b + (b.b - a.b) * t + 0.5),
	}
end

-- luminance (0-1) for choosing readable text on a background
function ColorUtil.luminance(c: RGB): number
	local function lin(v: number): number
		v /= 255
		return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
end

-- contrast ratio (1-21) between two colours
function ColorUtil.contrast(a: RGB, b: RGB): number
	local la, lb = ColorUtil.luminance(a), ColorUtil.luminance(b)
	if la < lb then
		la, lb = lb, la
	end
	return (la + 0.05) / (lb + 0.05)
end

return ColorUtil
