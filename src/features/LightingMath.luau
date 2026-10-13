--!nonstrict
-- features/LightingMath: pure maths for the colour-correction presets and time-of-day presets.

local LM = {}

LM.filters = {
	None = { tint = { 255, 255, 255 }, saturation = 0, contrast = 0, exposure = 0 },
	Warm = { tint = { 255, 232, 205 }, saturation = 0.05, contrast = 0.03, exposure = 0.02 },
	Cool = { tint = { 205, 228, 255 }, saturation = 0.05, contrast = 0.03, exposure = 0 },
	Mono = { tint = { 255, 255, 255 }, saturation = -1, contrast = 0.08, exposure = 0 },
	Sepia = { tint = { 255, 226, 180 }, saturation = -0.55, contrast = 0.05, exposure = 0.02 },
	Vivid = { tint = { 255, 255, 255 }, saturation = 0.55, contrast = 0.15, exposure = 0 },
}

LM.times = {
	Dawn = { clock = 6.2, ambient = { 96, 80, 96 }, outdoor = { 130, 104, 110 } },
	Noon = { clock = 12, ambient = { 120, 120, 125 }, outdoor = { 150, 150, 155 } },
	Dusk = { clock = 18.3, ambient = { 100, 70, 80 }, outdoor = { 140, 95, 90 } },
	Night = { clock = 0, ambient = { 28, 32, 52 }, outdoor = { 40, 46, 72 } },
}

local function clamp(v, lo, hi)
	return math.max(lo, math.min(hi, v))
end

-- combine(sliders{saturation,contrast,exposure,tint{r,g,b}}, filterName) -> final values.
-- Sliders and the preset add up (clamped to the engine ranges); tints multiply.
function LM.combine(s, filterName)
	local f = LM.filters[filterName] or LM.filters.None
	return {
		saturation = clamp(s.saturation + f.saturation, -1, 2),
		contrast = clamp(s.contrast + f.contrast, -1, 1),
		exposure = clamp(s.exposure + f.exposure, -1, 1),
		tint = {
			r = math.floor(s.tint.r * f.tint[1] / 255 + 0.5),
			g = math.floor(s.tint.g * f.tint[2] / 255 + 0.5),
			b = math.floor(s.tint.b * f.tint[3] / 255 + 0.5),
		},
	}
end

return LM
